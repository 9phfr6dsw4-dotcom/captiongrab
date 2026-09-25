import test from 'node:test';
import assert from 'node:assert/strict';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const imported = await import(path.join(root, 'ChromeExtension/transcript-panel-opener.js'));
const opener = imported.default ?? imported;

class FakeElement {
  constructor({ tag = 'button', id = '', role = '', text = '', ariaLabel = '', attributes = {}, onClick = null } = {}) {
    this.tagName = tag.toUpperCase();
    this.id = id;
    this.role = role;
    this.innerText = text;
    this.textContent = text;
    this.attributes = { ...(role ? { role } : {}), ...(ariaLabel ? { 'aria-label': ariaLabel } : {}), ...attributes };
    this.children = [];
    this.parentElement = null;
    this.isConnected = true;
    this.hidden = false;
    this.style = { display: 'block', visibility: 'visible', opacity: '1' };
    this.clickCount = 0;
    this.onClick = onClick;
    this.scrollCount = 0;
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
      const roleMatch = value.match(/^\[role=["']?([^\]"']+)/);
      if (roleMatch) return this.role === roleMatch[1];
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

  getAttribute(name) {
    return this.attributes[name] ?? null;
  }

  getRootNode() {
    let root = this;
    while (root.parentElement) root = root.parentElement;
    return root;
  }

  scrollIntoView() {
    this.scrollCount += 1;
  }

  click() {
    this.clickCount += 1;
    this.onClick?.(this);
  }
}

class FakeDocument extends FakeElement {
  constructor() {
    super({ tag: 'document' });
    this.readyState = 'complete';
  }

  querySelectorAll(selector) {
    const result = [];
    if (this.matches(selector)) result.push(this);
    return result.concat(super.querySelectorAll(selector));
  }

  querySelector(selector) {
    return this.querySelectorAll(selector)[0] ?? null;
  }
}

function harness(document, { timeoutMs = 3_000, tickMs = 100, onTick = () => {}, isPageReady = () => document.readyState === 'complete' } = {}) {
  let currentTime = 0;
  return {
    run: () => opener.openTranscriptPanel({
      document,
      timeoutMs,
      pollIntervalMs: tickMs,
      now: () => currentTime,
      sleep: async milliseconds => {
        currentTime += milliseconds;
        onTick(currentTime);
      },
      isPageReady
    })
  };
}

function transcriptPanel(document) {
  const panel = document.append(new FakeElement({ tag: 'ytd-transcript-renderer' }));
  panel.append(new FakeElement({ tag: 'ytd-transcript-segment-renderer', text: 'Synthetic transcript line.' }));
  return panel;
}

test('waits for full page load, retries late controls, expands the description, and waits for the panel', async () => {
  const document = new FakeDocument();
  document.readyState = 'loading';
  const description = document.append(new FakeElement({ tag: 'ytd-text-inline-expander', id: 'description-inline-expander' }));
  let more;
  let show;
  let tickCount = 0;
  const task = harness(document, {
    isPageReady: () => document.readyState === 'complete' && Boolean(document.querySelector('ytd-watch-flexy')),
    onTick() {
      tickCount += 1;
      if (tickCount === 2) document.readyState = 'complete';
      if (tickCount === 3) document.append(new FakeElement({ tag: 'ytd-watch-flexy' }));
      if (tickCount === 4) {
        more = description.append(new FakeElement({ tag: 'tp-yt-paper-button', id: 'expand', text: '...more' }));
        more.onClick = () => {};
      }
      if (tickCount === 6 && more?.clickCount && !show) {
        show = description.append(new FakeElement({ tag: 'ytd-button-renderer', text: 'Show transcript' }));
        show.onClick = () => { transcriptPanel(document); };
      }
    }
  });

  const result = await task.run();
  assert.equal(result.ok, true);
  assert.equal(result.reason, undefined);
  assert.equal(more.clickCount, 1);
  assert.equal(show.clickCount, 1);
  assert.equal(show.scrollCount, 1);
  assert.ok(tickCount >= 4, 'waited for asynchronous panel rendering');
});

test('opens the In this video panel and switches from Chapters to Transcript before reading lines', async () => {
  const document = new FakeDocument();
  const actions = [];
  const description = document.append(new FakeElement({ tag: 'ytd-text-inline-expander', id: 'description-inline-expander' }));
  const more = description.append(new FakeElement({ tag: 'tp-yt-paper-button', id: 'expand', text: '...more' }));
  more.onClick = () => {
    actions.push('expand-description');
    const transcriptSection = document.append(new FakeElement({ tag: 'ytd-video-description-transcript-section-renderer' }));
    const show = transcriptSection.append(new FakeElement({ tag: 'ytd-button-renderer', text: 'Show transcript' }));
    show.onClick = () => {
      actions.push('show-transcript');
      const panel = document.append(new FakeElement({
        tag: 'ytd-engagement-panel-section-list-renderer',
        text: 'In this video',
        attributes: { 'target-id': 'engagement-panel-macro-markers-description-chapters' }
      }));
      const chapters = panel.append(new FakeElement({ tag: 'tp-yt-paper-tab', role: 'tab', text: 'Chapters', attributes: { 'aria-selected': 'true' } }));
      const transcript = panel.append(new FakeElement({ tag: 'tp-yt-paper-tab', role: 'tab', text: 'Transcript', attributes: { 'aria-selected': 'false' } }));
      transcript.onClick = () => {
        actions.push('select-transcript-tab');
        chapters.attributes['aria-selected'] = 'false';
        transcript.attributes['aria-selected'] = 'true';
      };
    };
  };

  let pageTicks = 0;
  const result = await harness(document, {
    onTick() {
      pageTicks += 1;
      if (pageTicks === 3) {
        const panel = opener.findTranscriptPanel(document);
        panel?.append(new FakeElement({ tag: 'ytd-transcript-segment-renderer', text: 'Synthetic caption row.' }));
      }
    }
  }).run();
  assert.equal(result.ok, true);
  assert.equal(more.clickCount, 1);
  assert.deepEqual(actions, ['expand-description', 'show-transcript', 'select-transcript-tab']);
  assert.equal(result.panel.getAttribute('target-id'), 'engagement-panel-macro-markers-description-chapters');
  assert.ok(result.panel.querySelectorAll('ytd-transcript-segment-renderer').length > 0);
});

test('opens the delayed below-the-fold description Transcript section before touching the existing Chapters panel', async () => {
  const document = new FakeDocument();
  const actions = [];
  const description = document.append(new FakeElement({ tag: 'ytd-text-inline-expander', id: 'description-inline-expander' }));
  const more = description.append(new FakeElement({ tag: 'tp-yt-paper-button', id: 'expand', text: '...more' }));
  const chapterPanel = document.append(new FakeElement({
    tag: 'ytd-engagement-panel-section-list-renderer',
    text: 'In this video',
    attributes: { 'target-id': 'engagement-panel-macro-markers-description-chapters' }
  }));
  const chapters = chapterPanel.append(new FakeElement({ tag: 'tp-yt-paper-tab', role: 'tab', text: 'Chapters', attributes: { 'aria-selected': 'true' } }));
  const transcriptTab = chapterPanel.append(new FakeElement({ tag: 'tp-yt-paper-tab', role: 'tab', text: 'Transcript', attributes: { 'aria-selected': 'false' } }));
  let section;
  let show;
  let tickCount = 0;

  more.onClick = () => actions.push('expand-description');
  transcriptTab.onClick = () => {
    actions.push('select-transcript-tab');
    chapters.attributes['aria-selected'] = 'false';
    transcriptTab.attributes['aria-selected'] = 'true';
  };

  const result = await harness(document, {
    timeoutMs: 3_000,
    onTick() {
      tickCount += 1;
      if (tickCount === 3) {
        section = document.append(new FakeElement({ tag: 'section', text: 'Transcript Follow along using the transcript' }));
        show = section.append(new FakeElement({ tag: 'div', role: 'button', ariaLabel: 'Show transcript' }));
        show.innerText = '';
        show.textContent = '';
        show.onClick = () => {
          actions.push('show-transcript');
          chapterPanel.attributes['target-id'] = 'engagement-panel-transcript-search';
          chapterPanel.append(new FakeElement({ tag: 'ytd-transcript-segment-renderer', text: 'Loaded synthetic caption.' }));
        };
      }
    }
  }).run();

  assert.equal(result.ok, true);
  assert.deepEqual(actions, ['expand-description', 'show-transcript', 'select-transcript-tab']);
  assert.equal(section.scrollCount > 0 || show.scrollCount > 0, true);
  assert.deepEqual(result.progress, {
    descriptionExpanded: true,
    transcriptSectionFound: true,
    transcriptButtonFound: true,
    transcriptButtonClicked: true,
    panelOpened: true,
    transcriptTabSelected: true,
    transcriptLinesLoaded: true
  });
});

test('records control labels, panel state, click steps, and timing while waiting ten seconds after expanding description', async () => {
  const document = new FakeDocument();
  const events = [];
  const description = document.append(new FakeElement({ tag: 'ytd-text-inline-expander', id: 'description-inline-expander' }));
  const more = description.append(new FakeElement({ tag: 'tp-yt-paper-button', id: 'expand', text: '...more' }));
  const chaptersPanel = document.append(new FakeElement({
    tag: 'ytd-engagement-panel-section-list-renderer', text: 'In this video',
    attributes: { 'target-id': 'engagement-panel-macro-markers-description-chapters' }
  }));
  chaptersPanel.append(new FakeElement({ tag: 'tp-yt-paper-tab', role: 'tab', text: 'Chapters', attributes: { 'aria-selected': 'true' } }));
  let show;
  more.onClick = () => events.push('more-clicked');
  const result = await harness(document, {
    timeoutMs: 30_000,
    tickMs: 250,
    onTick(now) {
      if (now === 9_750) {
        const section = document.append(new FakeElement({ tag: 'section', text: 'Transcript Follow along using the transcript' }));
        show = section.append(new FakeElement({ tag: 'button', text: 'Show transcript', ariaLabel: 'Show transcript' }));
        show.onClick = () => {
          events.push('show-transcript-clicked');
          const panel = document.append(new FakeElement({ tag: 'ytd-engagement-panel-section-list-renderer', text: 'In this video', attributes: { 'target-id': 'engagement-panel-transcript-search' } }));
          panel.append(new FakeElement({ tag: 'ytd-transcript-segment-renderer', text: 'Synthetic line' }));
        };
      }
    }
  }).run();

  assert.equal(result.ok, true);
  assert.equal(show.clickCount, 1);
  assert.deepEqual(events, ['more-clicked', 'show-transcript-clicked']);
  assert.match(result.debugLog, /clicked description expand.*more/i);
  assert.match(result.debugLog, /Show transcript/);
  assert.match(result.debugLog, /Chapters/);
  assert.match(result.debugLog, /panel/i);
  assert.match(result.debugLog, /\+\d+ms/);
  assert.doesNotMatch(result.debugLog, /Synthetic line/);
});

test('stops transcript-button discovery ten seconds after expanding description and returns observations', async () => {
  const document = new FakeDocument();
  const description = document.append(new FakeElement({ tag: 'ytd-text-inline-expander', id: 'description-inline-expander' }));
  const more = description.append(new FakeElement({ tag: 'tp-yt-paper-button', id: 'expand', text: '...more' }));
  more.onClick = () => {};
  const result = await harness(document, { timeoutMs: 30_000, tickMs: 250 }).run();
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'button-not-found');
  assert.equal(result.elapsedMs, 10_000);
  assert.match(result.debugLog, /description expanded/i);
  assert.match(result.debugLog, /Show transcript button not found/i);
});
test('clicks the custom YouTube button host when Show transcript text lives in its shadow root', async () => {
  const document = new FakeDocument();
  const section = document.append(new FakeElement({ tag: 'section', text: 'Transcript Follow along using the transcript' }));
  const shadowHost = section.append(new FakeElement({ tag: 'tp-yt-paper-button' }));
  const shadowRoot = new FakeElement({ tag: 'shadow-root' });
  shadowRoot.host = shadowHost;
  shadowHost.shadowRoot = shadowRoot;
  shadowRoot.append(new FakeElement({ tag: 'span', text: 'Show transcript' }));
  shadowHost.onClick = () => { transcriptPanel(document); };
  const result = await harness(document).run();
  assert.equal(result.ok, true, result.debugLog);
  assert.equal(shadowHost.clickCount, 1);
  assert.match(result.debugLog, /clicked Show transcript control/);
});

test('still clicks the Show transcript control if scrolling it throws', async () => {
  const document = new FakeDocument();
  const section = document.append(new FakeElement({ tag: 'section', text: 'Transcript Follow along using the transcript' }));
  const show = section.append(new FakeElement({ tag: 'div', role: 'button', ariaLabel: 'Show transcript' }));
  show.scrollIntoView = () => { throw new Error('scroll unsupported'); };
  show.onClick = () => { transcriptPanel(document); };
  const result = await harness(document).run();
  assert.equal(result.ok, true);
  assert.equal(show.clickCount, 1);
});


test('recognizes the older standalone transcript renderer layout', async () => {
  const document = new FakeDocument();
  const section = document.append(new FakeElement({ tag: 'ytd-video-description-transcript-section-renderer' }));
  const show = section.append(new FakeElement({ tag: 'button', ariaLabel: 'Show transcript' }));
  show.onClick = () => { transcriptPanel(document); };
  const result = await harness(document).run();
  assert.equal(result.ok, true);
  assert.equal(show.clickCount, 1);
});

test('waits for transcript rows when the Transcript tab is already selected without toggling it', async () => {
  const document = new FakeDocument();
  const panel = document.append(new FakeElement({ tag: 'ytd-engagement-panel-section-list-renderer', text: 'In this video' }));
  const transcript = panel.append(new FakeElement({ tag: 'yt-tab-shape', text: 'Transcript', attributes: { 'aria-selected': 'true' } }));
  const section = document.append(new FakeElement({ tag: 'ytd-video-description-transcript-section-renderer' }));
  const show = section.append(new FakeElement({ tag: 'button', text: 'Show transcript' }));
  show.onClick = () => {};
  let pageTicks = 0;
  const result = await harness(document, {
    onTick() {
      pageTicks += 1;
      if (pageTicks === 2) panel.append(new FakeElement({ tag: 'yt-transcript-segment-renderer', text: 'Loaded caption row.' }));
    }
  }).run();
  assert.equal(result.ok, true);
  assert.equal(show.clickCount, 1);
  assert.equal(transcript.clickCount, 0);
  assert.ok(pageTicks >= 2);
});

test('reports a clear button-not-found result after retrying a loaded page', async () => {
  const document = new FakeDocument();
  document.append(new FakeElement({ tag: 'ytd-watch-metadata' }));
  const result = await harness(document, { timeoutMs: 350, tickMs: 100 }).run();
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'button-not-found');
  assert.deepEqual(result.progress, {
    descriptionExpanded: false,
    transcriptSectionFound: false,
    transcriptButtonFound: false,
    transcriptButtonClicked: false,
    panelOpened: false,
    transcriptTabSelected: false,
    transcriptLinesLoaded: false
  });
  assert.match(result.debugLog, /automation stopped/);
  const message = opener.manualActionMessage(result.reason, result.progress);
  assert.match(message, /expand “\.\.\.more”/);
  assert.match(message, /click the “Show transcript” button/);
  assert.match(message, /click its “Transcript” tab/);
  assert.match(message, /try Get transcript again/);
  assert.match(message, /Description expanded: no/);
  assert.match(message, /Show transcript button found: no/);
});

test('reports when Show transcript was clicked but its panel never loaded', async () => {
  const document = new FakeDocument();
  const section = document.append(new FakeElement({ tag: 'ytd-video-description-transcript-section-renderer' }));
  const show = section.append(new FakeElement({ tag: 'button', text: 'Show transcript' }));
  const result = await harness(document, { timeoutMs: 350, tickMs: 100 }).run();
  assert.equal(result.ok, false);
  assert.equal(result.reason, 'panel-not-loaded');
  assert.deepEqual(result.progress, {
    descriptionExpanded: true,
    transcriptSectionFound: true,
    transcriptButtonFound: true,
    transcriptButtonClicked: true,
    panelOpened: false,
    transcriptTabSelected: false,
    transcriptLinesLoaded: false
  });
  assert.match(result.debugLog, /clicked Show transcript control/);
  assert.equal(show.clickCount, 1);
});

test('does not click controls while the page is still loading', async () => {
  const document = new FakeDocument();
  document.readyState = 'loading';
  const section = document.append(new FakeElement({ tag: 'ytd-video-description-transcript-section-renderer' }));
  const show = section.append(new FakeElement({ tag: 'button', text: 'Show transcript' }));
  const result = await harness(document, {
    timeoutMs: 250,
    tickMs: 100,
    onTick() {}
  }).run();
  assert.equal(show.clickCount, 0);
  assert.equal(result.reason, 'page-not-ready');
  assert.equal(result.progress.transcriptButtonFound, false);
});
