import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { runInNewContext } from 'node:vm';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const importedExtractor = await import(path.join(root, 'ChromeExtension/transcript-extractor.js'));
const extractor = importedExtractor.default ?? importedExtractor;

function element(text) {
  return { innerText: text, textContent: text };
}
function segment(timestamp, caption) {
  return {
    querySelector(selector) {
      if (selector.includes('timestamp')) return element(timestamp);
      if (selector.includes('text')) return element(caption);
      return null;
    }
  };
}

class FakeDOMNode {
  constructor({ tag = 'div', id = '', role = '', text = '', ariaLabel = '', attributes = {}, onClick = null } = {}) {
    this.tagName = tag.toUpperCase();
    this.id = id;
    this.innerText = text;
    this.textContent = text;
    this.attributes = { ...(role ? { role } : {}), ...(ariaLabel ? { 'aria-label': ariaLabel } : {}), ...attributes };
    this.children = [];
    this.parentElement = null;
    this.isConnected = true;
    this.hidden = false;
    this.clickCount = 0;
    this.onClick = onClick;
  }

  append(child) {
    child.parentElement = this;
    this.children.push(child);
    return child;
  }

  matches(selector) {
    return selector.split(',').some(part => {
      const value = part.trim();
      if (value === '*') return true;
      if (value.startsWith('#')) return this.id === value.slice(1);
      const roleMatch = value.match(/^\\[role=["']?([^\\]"']+)/);
      if (roleMatch) return this.attributes.role === roleMatch[1];
      return this.tagName.toLowerCase() === value.toLowerCase();
    });
  }

  querySelectorAll(selector) {
    const matches = [];
    const visit = node => {
      for (const child of node.children) {
        if (child.matches(selector)) matches.push(child);
        visit(child);
      }
    };
    visit(this);
    return matches;
  }

  getAttribute(name) { return this.attributes[name] ?? null; }
  click() { this.clickCount += 1; this.onClick?.(this); }
}

function languageMenuFixture(languageNames, selectedLanguage, { refreshCues = true, portalMenu = false, replaceCueNodeWithSameText = false } = {}) {
  const document = new FakeDOMNode({ tag: 'document' });
  const heading = element('Synthetic video title');
  document.readyState = 'complete';
  document.title = 'Synthetic video title - YouTube';
  document.documentElement = { appendChild() {} };
  document.querySelector = selector => selector.includes('h1') ? heading : null;
  document.createElement = () => ({ style: {}, setAttribute() {}, remove() {}, textContent: '' });
  const panel = document.append(new FakeDOMNode({ tag: 'ytd-transcript-renderer' }));
  const trigger = panel.append(new FakeDOMNode({ tag: 'button', id: 'language-menu', ariaLabel: selectedLanguage }));
  const cue = text => {
    const row = new FakeDOMNode({ tag: 'ytd-transcript-segment-renderer', text });
    row.querySelector = selector => selector.includes('timestamp') ? element('0:00') : selector.includes('text') ? element(text) : null;
    return row;
  };
  panel.append(cue('Currently selected synthetic caption.'));
  let menu;
  const optionNodes = new Map();
  trigger.onClick = () => {
    if (menu && !menu.hidden) return;
    menu = (portalMenu ? document : panel).append(new FakeDOMNode({ tag: 'tp-yt-paper-listbox', role: 'listbox' }));
    for (const name of languageNames) {
      const option = menu.append(new FakeDOMNode({ tag: 'tp-yt-paper-item', role: 'option', text: name }));
      optionNodes.set(name, option);
      option.onClick = () => {
        trigger.attributes['aria-label'] = name;
        menu.hidden = true;
        if (name !== selectedLanguage && replaceCueNodeWithSameText) {
          panel.children = panel.children.filter(child => child.tagName !== 'YTD-TRANSCRIPT-SEGMENT-RENDERER');
          panel.append(cue('Currently selected synthetic caption.'));
        } else if (name !== selectedLanguage && refreshCues) {
          panel.children = panel.children.filter(child => child.tagName !== 'YTD-TRANSCRIPT-SEGMENT-RENDERER');
          panel.append(cue(`Caption from ${name}.`));
        }
      };
    }
  };
  return { document, panel, trigger, optionNodes, getCueText: () => panel.querySelectorAll('ytd-transcript-segment-renderer').map(node => node.innerText) };
}

async function runContentCapture(fixture) {
  let resolveMessage;
  const receivedMessage = new Promise(resolve => { resolveMessage = resolve; });
  let currentTime = 0;
  const testExtractor = {
    ...extractor,
    selectPreferredEnglishTranscript: options => extractor.selectPreferredEnglishTranscript({
      ...options,
      sleep: async milliseconds => { currentTime += milliseconds; await Promise.resolve(); },
      now: () => currentTime,
      timeoutMs: 10_000,
      pollIntervalMs: 100
    })
  };
  fixture.document.defaultView = { setTimeout: callback => { queueMicrotask(callback); return 0; } };
  const panelOpener = {
    openTranscriptPanel: async () => ({
      ok: true,
      panel: fixture.panel,
      progress: {
        descriptionExpanded: true,
        transcriptSectionFound: true,
        transcriptButtonFound: true,
        transcriptButtonClicked: true,
        panelOpened: true,
        transcriptTabSelected: true,
        transcriptLinesLoaded: true
      },
      debugLog: '[+0ms] fixture transcript panel opened'
    }),
    findTranscriptPanel: () => fixture.panel,
    manualActionMessage: reason => String(reason)
  };
  const sandbox = {
    CaptionGrabExtractor: testExtractor,
    CaptionGrabTranscriptPanel: panelOpener,
    URL,
    Date: { now: () => (currentTime += 100) },
    Promise,
    location: {
      href: 'https://www.youtube.com/watch?v=5fJl_ZX91l0&captiongrab_request=e6b7b1e7-cc6d-4d34-9ab9-c8ec20dd85ce',
      pathname: '/watch'
    },
    history: { state: null, replaceState() {} },
    setTimeout: callback => { queueMicrotask(callback); return 0; },
    chrome: {
      runtime: {
        lastError: null,
        sendMessage(message, callback) {
          callback({ ok: true });
          resolveMessage(message);
        }
      }
    },
    document: fixture.document
  };
  sandbox.globalThis = sandbox;
  runInNewContext(await readFile(path.join(root, 'ChromeExtension/content.js'), 'utf8'), sandbox);
  return Promise.race([
    receivedMessage,
    new Promise((_, reject) => globalThis.setTimeout(() => reject(new Error('Content script did not send a response.')), 2_000))
  ]);
}

test('parses YouTube minute and hour timestamps', () => {
  assert.equal(extractor.parseTimestamp('12:45'), 765_000);
  assert.equal(extractor.parseTimestamp('1:02:15'), 3_735_000);
  assert.equal(extractor.parseTimestamp('not-a-time'), null);
});

test('extracts ordered cues and preserves explicit caption line breaks', () => {
  const cues = extractor.extractCues([
    segment('12:45', 'A synthetic first line.'),
    segment('12:51', 'A second line.\nBreak preserved.')
  ]);
  assert.deepEqual(cues, [
    { startTimeMilliseconds: 765_000, text: 'A synthetic first line.' },
    { startTimeMilliseconds: 771_000, text: 'A second line.\nBreak preserved.' }
  ]);
});

test('extracts transcript cue rows from the modern panel shadow root', () => {
  const panel = new FakeDOMNode({ tag: 'ytd-engagement-panel-section-list-renderer' });
  const shadowRoot = new FakeDOMNode({ tag: 'shadow-root' });
  shadowRoot.host = panel;
  panel.shadowRoot = shadowRoot;
  const row = new FakeDOMNode({ tag: 'yt-transcript-segment-renderer' });
  row.querySelector = selector => selector.includes('timestamp')
    ? element('1:23')
    : selector.includes('text') ? element('Synthetic auto-generated line.') : null;
  shadowRoot.append(row);

  assert.deepEqual(extractor.extractTranscriptCues(panel), [
    { startTimeMilliseconds: 83_000, text: 'Synthetic auto-generated line.' }
  ]);
});

test('extracts timestamped modern timeline captions and skips chapter headings', () => {
  const panel = new FakeDOMNode({ tag: 'ytd-engagement-panel-section-list-renderer' });
  const chapter = panel.append(new FakeDOMNode({ tag: 'macro-markers-panel-item-view-model', role: 'button' }));
  chapter.append(new FakeDOMNode({ tag: 'timeline-chapter-view-model' })).append(new FakeDOMNode({ tag: 'h3', text: 'Chapter title' }));
  const item = panel.append(new FakeDOMNode({ tag: 'macro-markers-panel-item-view-model', role: 'button' }));
  const timeline = item.append(new FakeDOMNode({ tag: 'timeline-item-view-model' }));
  const container = timeline.append(new FakeDOMNode({ tag: 'div' }));
  const segment = container.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '1:23' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: 'not a timestamp' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'Synthetic modern caption.\nSecond line.' }));

  assert.deepEqual(extractor.extractTranscriptCues(panel), [
    { startTimeMilliseconds: 83_000, text: 'Synthetic modern caption.\nSecond line.' }
  ]);
});

test('does not treat modern chapter headings or timestampless captions as cues', () => {
  const panel = new FakeDOMNode({ tag: 'ytd-engagement-panel-section-list-renderer' });
  const chapter = panel.append(new FakeDOMNode({ tag: 'macro-markers-panel-item-view-model' }));
  chapter.append(new FakeDOMNode({ tag: 'timeline-chapter-view-model' })).append(new FakeDOMNode({ tag: 'h3', text: '1:23' }));
  const segment = panel.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: 'not a time' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: '1:23 happens in this caption.' }));
  assert.deepEqual(extractor.extractTranscriptCues(panel), []);
});

test('does not extract a modern cue when its timeline row is hidden', () => {
  const panel = new FakeDOMNode({ tag: 'ytd-engagement-panel-section-list-renderer' });
  const item = panel.append(new FakeDOMNode({ tag: 'macro-markers-panel-item-view-model' }));
  item.hidden = true;
  const segment = item.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '1:23' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'Hidden caption.' }));
  assert.deepEqual(extractor.extractTranscriptCues(panel), []);
});

test('does not duplicate an available modern cue from a legacy renderer in the same panel', () => {
  const panel = new FakeDOMNode({ tag: 'ytd-engagement-panel-section-list-renderer', attributes: { 'target-id': 'PAmodern_transcript_view' } });
  const legacy = panel.append(new FakeDOMNode({ tag: 'ytd-transcript-segment-renderer' }));
  legacy.querySelector = selector => selector.includes('timestamp') ? element('1:23') : element('Same caption.');
  const segment = panel.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '1:23' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'Same caption.' }));
  assert.deepEqual(extractor.extractTranscriptCues(panel), [
    { startTimeMilliseconds: 83_000, text: 'Same caption.' }
  ]);
});

test('rejects empty and malformed transcript segments', () => {
  assert.deepEqual(extractor.extractCues([segment('0:01', '  \n  ')]), []);
  assert.deepEqual(extractor.extractCues([segment('bad', 'Synthetic text')]), []);
});

test('prefers regular English over auto-generated captions when both are available', () => {
  assert.deepEqual(extractor.choosePreferredEnglishLanguage([
    'English (auto-generated)',
    'Français',
    'English'
  ]), {
    availableLanguages: ['English (auto-generated)', 'Français', 'English'],
    selectedLanguage: 'English',
    isAutoGenerated: false
  });
});

test('chooses regular English case-insensitively and deduplicates language labels', () => {
  assert.deepEqual(extractor.choosePreferredEnglishLanguage([
    'english (auto-generated)',
    'ENGLISH',
    'ENGLISH'
  ]), {
    availableLanguages: ['english (auto-generated)', 'ENGLISH'],
    selectedLanguage: 'English',
    isAutoGenerated: false
  });
});

test('uses auto-generated English only when regular English is unavailable', () => {
  assert.deepEqual(extractor.choosePreferredEnglishLanguage([
    'Français',
    'English (auto-generated)'
  ]), {
    availableLanguages: ['Français', 'English (auto-generated)'],
    selectedLanguage: 'English (auto-generated)',
    isAutoGenerated: true
  });
});

test('does not select a transcript when no English option is available', () => {
  assert.deepEqual(extractor.choosePreferredEnglishLanguage(['Français', 'Deutsch']), {
    availableLanguages: ['Français', 'Deutsch'],
    selectedLanguage: null,
    isAutoGenerated: null
  });
});

test('opens the transcript language menu and switches to regular English before caption rows are read', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'Français', 'English'], 'English (auto-generated)');
  let currentTime = 0;
  const result = await extractor.selectPreferredEnglishTranscript({
    panel: fixture.panel,
    document: fixture.document,
    timeoutMs: 1_000,
    pollIntervalMs: 100,
    now: () => currentTime,
    sleep: async milliseconds => { currentTime += milliseconds; }
  });
  assert.equal(result.ok, true, result.reason);
  assert.equal(result.currentlySelectedLanguage, 'English (auto-generated)');
  assert.equal(result.selectedLanguage, 'English');
  assert.equal(result.isAutoGenerated, false);
  assert.deepEqual(result.availableLanguages, ['English (auto-generated)', 'Français', 'English']);
  assert.equal(fixture.trigger.clickCount, 1);
  assert.equal(fixture.optionNodes.get('English').clickCount, 1);
  assert.equal(fixture.optionNodes.get('English (auto-generated)').clickCount, 0);
  assert.deepEqual(fixture.getCueText(), ['Caption from English.']);
});

test('selects auto-generated English only when it is the only English menu option', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'Français'], 'Français');
  let currentTime = 0;
  const result = await extractor.selectPreferredEnglishTranscript({
    panel: fixture.panel,
    document: fixture.document,
    timeoutMs: 1_000,
    pollIntervalMs: 100,
    now: () => currentTime,
    sleep: async milliseconds => { currentTime += milliseconds; }
  });
  assert.equal(result.ok, true, result.reason);
  assert.equal(result.selectedLanguage, 'English (auto-generated)');
  assert.equal(result.isAutoGenerated, true);
  assert.equal(fixture.optionNodes.get('English (auto-generated)').clickCount, 1);
});

test('content script sends regular English captions and logs available and selected languages', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'Français', 'English'], 'English (auto-generated)');
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.isAutoGenerated, false);
  assert.deepEqual(message.cues.map(cue => cue.text), ['Caption from English.']);
  assert.match(message.debugLog, /transcript language selection/);
  assert.match(message.debugLog, /English \(auto-generated\)/);
  assert.match(message.debugLog, /Français/);
  assert.ok(message.debugLog.includes('"previouslySelectedLanguage":"English (auto-generated)"'));
  assert.ok(message.debugLog.includes('"selectedLanguage":"English"'));
});

test('content script sends timestamped modern-panel captions as displayed without selecting English', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'English'], 'English');
  const oldRow = fixture.panel.querySelectorAll('ytd-transcript-segment-renderer')[0];
  fixture.panel.children = fixture.panel.children.filter(child => child !== oldRow);
  fixture.panel.tagName = 'YTD-ENGAGEMENT-PANEL-SECTION-LIST-RENDERER';
  fixture.panel.attributes['target-id'] = 'PAmodern_transcript_view';
  const item = fixture.panel.append(new FakeDOMNode({ tag: 'macro-markers-panel-item-view-model', role: 'button' }));
  const segment = item.append(new FakeDOMNode({ tag: 'timeline-item-view-model' }))
    .append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '0:00' }));
  segment.append(new FakeDOMNode({ tag: 'div' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'Synthetic modern English caption.' }));

  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.isAutoGenerated, null);
  assert.deepEqual(message.cues.map(cue => cue.text), ['Synthetic modern English caption.']);
  assert.match(message.debugLog, /"selectedLanguage":"as-displayed"/);
  assert.match(message.debugLog, /"reason":"displayed-transcript"/);
  assert.equal(fixture.trigger.clickCount, 0);
});

test('modern panel sends the displayed transcript without choosing a language', async () => {
  const fixture = languageMenuFixture([], '');
  fixture.panel.children = [];
  fixture.panel.tagName = 'YTD-ENGAGEMENT-PANEL-SECTION-LIST-RENDERER';
  fixture.panel.attributes['target-id'] = 'PAmodern_transcript_view';
  const segment = fixture.panel.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '0:00' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'A short synthetic caption.' }));
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.captionLanguage, 'as-displayed');
  assert.equal(message.isAutoGenerated, null);
  assert.deepEqual(message.cues.map(cue => cue.text), ['A short synthetic caption.']);
  assert.match(message.debugLog, /displayed-transcript/);
  assert.ok(!message.debugLog.includes('A short synthetic caption.'));
});

test('modern panel captures the shown cues without claiming a detected language', async () => {
  const fixture = languageMenuFixture([], '');
  fixture.panel.children = [];
  fixture.panel.tagName = 'YTD-ENGAGEMENT-PANEL-SECTION-LIST-RENDERER';
  fixture.panel.attributes['target-id'] = 'PAmodern_transcript_view';
  const segment = fixture.panel.append(new FakeDOMNode({ tag: 'transcript-segment-view-model' }));
  segment.append(new FakeDOMNode({ tag: 'div', text: '0:03' }));
  segment.append(new FakeDOMNode({ tag: 'span', role: 'text', text: 'Texte fictif non anglais.' }));
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.captionLanguage, 'as-displayed');
  assert.equal(message.isAutoGenerated, null);
  assert.deepEqual(message.cues, [{ startTimeMilliseconds: 3_000, text: 'Texte fictif non anglais.' }]);
});

test('content script marks and logs auto-generated captions only as the fallback', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'Français'], 'Français');
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.isAutoGenerated, true);
  assert.deepEqual(message.cues.map(cue => cue.text), ['Caption from English (auto-generated).']);
  assert.ok(message.debugLog.includes('"selectedLanguage":"English (auto-generated)"'));
  assert.match(message.debugLog, /"isAutoGenerated":true/);
});

test('content script logs available languages and fails clearly when none are English', async () => {
  const fixture = languageMenuFixture(['Français', 'Deutsch'], 'Français');
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.error');
  assert.match(message.error, /No English captions are available/);
  assert.match(message.error, /Français, Deutsch/);
  assert.match(message.debugLog, /"availableLanguages":\["Français","Deutsch"\]/);
  assert.match(message.debugLog, /"selectedLanguage":null/);
});

test('does not assume available languages when the transcript language control is unavailable', async () => {
  const fixture = languageMenuFixture(['English'], 'English');
  fixture.panel.children = fixture.panel.children.filter(child => child !== fixture.trigger);
  fixture.panel.innerText = 'English';
  const result = await extractor.selectPreferredEnglishTranscript({
    panel: fixture.panel,
    document: fixture.document,
    timeoutMs: 100,
    pollIntervalMs: 10,
    now: () => 0,
    sleep: async () => {}
  });
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'language-menu-unavailable');
  assert.deepEqual(result.availableLanguages, []);
  assert.equal(result.currentlySelectedLanguage, 'English');
  assert.equal(result.menuInspected, false);
});

test('does not send stale cue rows when YouTube confirms the language but does not refresh captions', async () => {
  const fixture = languageMenuFixture(
    ['English (auto-generated)', 'Français', 'English'],
    'English (auto-generated)',
    { refreshCues: false }
  );
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.error');
  assert.match(message.error, /could not confirm that its captions refreshed/i);
  assert.match(message.debugLog, /"transcriptRefreshed":false/);
});

test('ignores unrelated visible English menus outside the transcript panel', async () => {
  const fixture = languageMenuFixture(['English (auto-generated)', 'Français'], 'Français');
  const unrelatedMenu = fixture.document.append(new FakeDOMNode({ tag: 'tp-yt-paper-listbox', role: 'listbox' }));
  const unrelatedEnglish = unrelatedMenu.append(new FakeDOMNode({ tag: 'tp-yt-paper-item', role: 'option', text: 'English' }));
  unrelatedEnglish.onClick = () => {};
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.transcript');
  assert.equal(message.isAutoGenerated, true);
  assert.equal(unrelatedEnglish.clickCount, 0);
  assert.deepEqual(message.cues.map(cue => cue.text), ['Caption from English (auto-generated).']);
});

test('selects the transcript language from a newly opened portal menu, not an existing page menu', async () => {
  const fixture = languageMenuFixture(
    ['English (auto-generated)', 'Français', 'English'],
    'English (auto-generated)',
    { portalMenu: true }
  );
  const unrelatedMenu = fixture.document.append(new FakeDOMNode({ tag: 'tp-yt-paper-listbox', role: 'listbox' }));
  const unrelatedEnglish = unrelatedMenu.append(new FakeDOMNode({ tag: 'tp-yt-paper-item', role: 'option', text: 'English' }));
  let currentTime = 0;
  const result = await extractor.selectPreferredEnglishTranscript({
    panel: fixture.panel,
    document: fixture.document,
    timeoutMs: 1_000,
    pollIntervalMs: 100,
    now: () => currentTime,
    sleep: async milliseconds => { currentTime += milliseconds; }
  });
  assert.equal(result.ok, true, result.reason);
  assert.deepEqual(result.availableLanguages, ['English (auto-generated)', 'Français', 'English']);
  assert.equal(result.selectedLanguage, 'English');
  assert.equal(unrelatedEnglish.clickCount, 0);
  assert.deepEqual(fixture.getCueText(), ['Caption from English.']);
});

test('does not treat replacement rows with identical cue text as a refreshed transcript', async () => {
  const fixture = languageMenuFixture(
    ['English (auto-generated)', 'Français', 'English'],
    'English (auto-generated)',
    { replaceCueNodeWithSameText: true }
  );
  const message = await runContentCapture(fixture);
  assert.equal(message.type, 'captiongrab.error');
  assert.match(message.error, /could not confirm that its captions refreshed/i);
  assert.match(message.debugLog, /"transcriptRefreshed":false/);
});

test('does not truncate the available language list before choosing English', async () => {
  const languages = Array.from({ length: 100 }, (_, index) => `Language ${index + 1}`);
  languages.push('English');
  const fixture = languageMenuFixture(languages, 'Français');
  let currentTime = 0;
  const result = await extractor.selectPreferredEnglishTranscript({
    panel: fixture.panel,
    document: fixture.document,
    timeoutMs: 1_000,
    pollIntervalMs: 100,
    now: () => currentTime,
    sleep: async milliseconds => { currentTime += milliseconds; }
  });
  assert.equal(result.ok, true, result.reason);
  assert.equal(result.availableLanguages.length, 101);
  assert.equal(result.availableLanguages.at(-1), 'English');
  assert.equal(result.selectedLanguage, 'English');
});

test('builds a local capture message for confirmed English or as-displayed transcript pages', () => {
  const result = extractor.buildCaptureMessage({
    requestID: 'e6b7b1e7-cc6d-4d34-9ab9-c8ec20dd85ce',
    videoID: '5fJl_ZX91l0',
    title: 'Fictional test video',
    languageName: 'English',
    isAutoGenerated: null
  }, [{ startTimeMilliseconds: 1_000, text: 'Invented sample caption.' }]);
  assert.equal(result.type, 'captiongrab.transcript');
  assert.equal(result.videoURL, 'https://www.youtube.com/watch?v=5fJl_ZX91l0');
  assert.equal(result.cues[0].text, 'Invented sample caption.');
  assert.equal(result.isAutoGenerated, null);
  const displayed = extractor.buildCaptureMessage({
    requestID: 'e6b7b1e7-cc6d-4d34-9ab9-c8ec20dd85ce',
    videoID: '5fJl_ZX91l0',
    title: 'Fictional test video',
    languageName: 'as-displayed'
  }, [{ startTimeMilliseconds: 1_000, text: 'Invented sample caption.' }]);
  assert.equal(displayed.captionLanguage, 'as-displayed');
  assert.equal(displayed.isAutoGenerated, null);
  assert.throws(() => extractor.buildCaptureMessage({
    requestID: 'e6b7b1e7-cc6d-4d34-9ab9-c8ec20dd85ce',
    videoID: '5fJl_ZX91l0',
    title: 'Fictional test video',
    languageName: 'French'
  }, [{ startTimeMilliseconds: 1_000, text: 'Faux.' }]), /English/);
});

test('extension manifest requests only the YouTube page and native-messaging permission', async () => {
  const manifest = JSON.parse(await readFile(path.join(root, 'ChromeExtension/manifest.json'), 'utf8'));
  assert.equal(manifest.manifest_version, 3);
  assert.deepEqual(manifest.permissions, ['nativeMessaging']);
  assert.deepEqual(manifest.host_permissions, ['https://www.youtube.com/*']);
  assert.equal(manifest.version, '1.2.12');
  assert.deepEqual(manifest.content_scripts[0].js, ['transcript-extractor.js', 'transcript-panel-opener.js', 'content.js']);
  const panelOpenerSource = await readFile(path.join(root, 'ChromeExtension/transcript-panel-opener.js'), 'utf8');
  assert.ok(panelOpenerSource.includes('Show transcript'));
  assert.ok(!('cookies' in manifest.permissions));
  assert.ok(!('cookies' in (manifest.optional_permissions ?? [])));
  const publicKey = Buffer.from(manifest.key, 'base64');
  const digest = createHash('sha256').update(publicKey).digest().subarray(0, 16);
  const id = digest.toString('hex').replace(/[0-9a-f]/g, digit => String.fromCharCode(97 + Number.parseInt(digit, 16)));
  assert.equal(id, 'kajphiodjnkmgeidbcndikaaegghiffi');
});
