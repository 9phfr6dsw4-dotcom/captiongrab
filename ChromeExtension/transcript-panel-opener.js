(function attach(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.CaptionGrabTranscriptPanel = api;
})(globalThis, function createTranscriptPanelOpener() {
  'use strict';

  const CONTROL_SELECTOR = 'button, [role="button"], tp-yt-paper-button, yt-button-shape, ytd-button-renderer, #expand';
  const DESCRIPTION_SELECTOR = '#description, #description-inline-expander, ytd-text-inline-expander, ytd-watch-metadata, ytd-video-secondary-info-renderer, ytd-video-primary-info-renderer';
  const TRANSCRIPT_SECTION_SELECTOR = 'ytd-video-description-transcript-section-renderer';
  const TRANSCRIPT_INTRO = 'follow along using the transcript';
  const TRANSCRIPT_PANEL_SELECTOR = 'ytd-transcript-renderer, yt-transcript-renderer, ytd-transcript-search-panel-renderer';
  const ENGAGEMENT_PANEL_SELECTOR = 'ytd-engagement-panel-section-list-renderer, yt-engagement-panel-section-list-renderer';
  const TRANSCRIPT_TAB_SELECTOR = 'button, [role="button"], [role="tab"], tp-yt-paper-tab, yt-tab-shape, yt-button-shape, ytd-button-renderer';
  const TRANSCRIPT_LINE_SELECTOR = 'ytd-transcript-segment-renderer, yt-transcript-segment-renderer, .transcript-segment';
  const MANUAL_ACTIONS = 'In the Chrome video tab, expand “...more” in the description if shown, scroll down to the Transcript section, and click the “Show transcript” button. If the “In this video” panel opens on “Chapters,” click its “Transcript” tab. Wait for transcript lines to appear, then try Get transcript again.';

  function nodes(scope, selector) {
    try {
      const result = [...(scope?.querySelectorAll?.(selector) ?? [])];
      if (scope?.matches?.(selector)) result.unshift(scope);
      return [...new Set(result)];
    } catch {
      return [];
    }
  }

  function allElements(scope) {
    const found = [];
    const pending = [scope];
    const seen = new Set();
    while (pending.length) {
      const current = pending.pop();
      if (!current || seen.has(current)) continue;
      seen.add(current);
      for (const node of nodes(current, '*')) {
        if (!seen.has(node)) {
          found.push(node);
          seen.add(node);
          if (node.shadowRoot) pending.push(node.shadowRoot);
        }
      }
      if (current.shadowRoot) pending.push(current.shadowRoot);
    }
    return found;
  }

  function visible(node, document) {
    if (!node || node.isConnected === false || node.hidden || node.getAttribute?.('aria-hidden') === 'true') return false;
    const getStyle = document?.defaultView?.getComputedStyle ?? globalThis.getComputedStyle;
    if (typeof getStyle !== 'function') return true;
    try {
      const style = getStyle(node);
      return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
    } catch {
      return true;
    }
  }

  function labels(node) {
    return [...new Set([
      node?.getAttribute?.('aria-label') ?? '',
      node?.getAttribute?.('title') ?? '',
      node?.innerText ?? '',
      node?.textContent ?? ''
    ].map(value => String(value).replace(/\s+/g, ' ').trim()).filter(Boolean))];
  }

  function scrollIntoView(node) {
    try {
      node?.scrollIntoView?.({ block: 'center', behavior: 'instant' });
    } catch {
      try { node?.scrollIntoView?.(true); } catch { /* continue clicking/retrying */ }
    }
  }

  function findDescriptionExpandButton(document) {
    const roots = nodes(document, DESCRIPTION_SELECTOR);
    for (const root of roots) {
      const candidates = [
        ...(root.matches?.(CONTROL_SELECTOR) ? [root] : []),
        ...nodes(root, CONTROL_SELECTOR)
      ];
      const match = candidates.find(node => visible(node, document) && (
        node.id === 'expand' || labels(node).some(value => /^(?:(?:\.{3}|…)?\s*)?(?:more|read more)(?:\s*…|\.{3})?$/i.test(value))
      ));
      if (match) return match;
    }
    return null;
  }

  function findTranscriptSection(document) {
    const known = nodes(document, TRANSCRIPT_SECTION_SELECTOR).find(node => visible(node, document));
    if (known) return known;

    const phraseNodes = allElements(document).filter(node => visible(node, document) && labels(node).some(value =>
      value.toLowerCase().includes(TRANSCRIPT_INTRO)
    ));
    phraseNodes.sort((left, right) => {
      const leftLength = Math.min(...labels(left).map(value => value.length), Number.MAX_SAFE_INTEGER);
      const rightLength = Math.min(...labels(right).map(value => value.length), Number.MAX_SAFE_INTEGER);
      return leftLength - rightLength;
    });
    return phraseNodes[0] ?? null;
  }

  function hasShowTranscriptLabel(node) {
    return labels(node).some(value => /\bshow\s+transcript\b/i.test(value));
  }

  function findClickableAncestor(node, boundary) {
    let candidate = node;
    while (candidate && candidate !== boundary) {
      if (candidate.matches?.(CONTROL_SELECTOR)) return candidate;
      candidate = candidate.parentElement;
    }
    return node;
  }

  function findShowTranscriptButton(document, section = findTranscriptSection(document)) {
    const sectionElements = section ? allElements(section) : [];
    const pageElements = allElements(document);
    const sectionMatches = sectionElements.filter(node => visible(node, document) && hasShowTranscriptLabel(node));
    const pageMatches = pageElements.filter(node => visible(node, document) && hasShowTranscriptLabel(node));
    const matches = [...new Set(sectionMatches.length ? sectionMatches : pageMatches)];
    const targets = matches.map(node => findClickableAncestor(node, document));
    const uniqueTargets = [...new Set(targets)].filter(node => visible(node, document));
    uniqueTargets.sort((left, right) => {
      const leftInteractive = left.matches?.(CONTROL_SELECTOR) ? 0 : 1;
      const rightInteractive = right.matches?.(CONTROL_SELECTOR) ? 0 : 1;
      if (leftInteractive !== rightInteractive) return leftInteractive - rightInteractive;
      const leftLength = Math.min(...labels(left).map(value => value.length), Number.MAX_SAFE_INTEGER);
      const rightLength = Math.min(...labels(right).map(value => value.length), Number.MAX_SAFE_INTEGER);
      return leftLength - rightLength;
    });
    return uniqueTargets[0] ?? null;
  }

  function findTranscriptTab(panel) {
    return nodes(panel, TRANSCRIPT_TAB_SELECTOR).find(node => visible(node, panel) && labels(node).some(value =>
      /^transcript$/i.test(value) || value.toLowerCase() === 'transcript tab'
    )) ?? null;
  }

  function transcriptTabIsSelected(tab) {
    const className = String(tab?.getAttribute?.('class') ?? tab?.className ?? '');
    const classTokens = className.toLowerCase().split(/\s+/);
    return tab?.getAttribute?.('aria-selected') === 'true' ||
      tab?.getAttribute?.('aria-pressed') === 'true' ||
      tab?.getAttribute?.('aria-current') === 'page' ||
      tab?.getAttribute?.('selected') !== null ||
      classTokens.some(token => token === 'selected' || token.endsWith('--selected') || token === 'active' || token.endsWith('--active'));
  }

  function hasTranscriptLines(panel) {
    return nodes(panel, TRANSCRIPT_LINE_SELECTOR).some(node => visible(node, panel));
  }

  function findTranscriptPanel(document) {
    const dedicatedPanel = nodes(document, TRANSCRIPT_PANEL_SELECTOR).find(node => visible(node, document));
    if (dedicatedPanel) return dedicatedPanel;
    const engagementPanels = nodes(document, ENGAGEMENT_PANEL_SELECTOR).filter(node => visible(node, document));
    return engagementPanels.find(node =>
      findTranscriptTab(node) || /transcript/i.test(node.getAttribute?.('target-id') ?? node.getAttribute?.('targetId') ?? '')
    ) ?? null;
  }

  function progressSnapshot(progress) {
    return { ...progress };
  }

  function progressSummary(progress) {
    const state = value => value ? 'yes' : 'no';
    return [
      'Chrome automation progress:',
      `- Description expanded: ${state(progress.descriptionExpanded)}`,
      `- Transcript section found: ${state(progress.transcriptSectionFound)}`,
      `- Show transcript button found: ${state(progress.transcriptButtonFound)}`,
      `- Show transcript button clicked: ${state(progress.transcriptButtonClicked)}`,
      `- Transcript panel opened: ${state(progress.panelOpened)}`,
      `- Transcript tab selected: ${state(progress.transcriptTabSelected)}`,
      `- Transcript lines loaded: ${state(progress.transcriptLinesLoaded)}`
    ].join('\n');
  }

  function manualActionMessage(reason, progress) {
    const prefix = reason === 'page-not-ready'
      ? 'The YouTube page did not finish loading in time.'
      : reason === 'panel-not-loaded'
        ? 'YouTube did not show the transcript panel after CaptionGrab clicked its button.'
        : 'CaptionGrab could not find YouTube’s transcript button automatically.';
    return `${prefix} ${MANUAL_ACTIONS}${progress ? `\n\n${progressSummary(progress)}` : ''}`;
  }

  async function openTranscriptPanel({
    document = globalThis.document,
    isPageReady = () => document?.readyState === 'complete',
    sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)),
    now = () => Date.now(),
    timeoutMs = 45_000,
    pollIntervalMs = 300
  } = {}) {
    const startedAt = now();
    const progress = {
      descriptionExpanded: false,
      transcriptSectionFound: false,
      transcriptButtonFound: false,
      transcriptButtonClicked: false,
      panelOpened: false,
      transcriptTabSelected: false,
      transcriptLinesLoaded: false
    };
    const clickedTranscriptTabs = new WeakSet();
    const scrolledTranscriptSections = new WeakSet();

    while (now() - startedAt < timeoutMs) {
      let ready = false;
      try {
        ready = Boolean(isPageReady());
      } catch {
        ready = false;
      }
      if (!ready) {
        await sleep(pollIntervalMs);
        continue;
      }

      const transcriptPanel = findTranscriptPanel(document);
      if (transcriptPanel && hasTranscriptLines(transcriptPanel)) {
        progress.panelOpened = true;
        const transcriptTab = findTranscriptTab(transcriptPanel);
        if (transcriptTab && !transcriptTabIsSelected(transcriptTab) && !clickedTranscriptTabs.has(transcriptTab)) {
          try {
            transcriptTab.scrollIntoView?.({ block: 'center', behavior: 'instant' });
            transcriptTab.click();
            clickedTranscriptTabs.add(transcriptTab);
            progress.transcriptTabSelected = true;
          } catch {
            // Keep waiting for YouTube to update the tab state after selection.
          }
          await sleep(pollIntervalMs);
          continue;
        }
        progress.transcriptTabSelected = Boolean(transcriptTab && transcriptTabIsSelected(transcriptTab));
        progress.transcriptLinesLoaded = true;
        return { ok: true, panel: transcriptPanel, opened: progress.transcriptButtonClicked, progress: progressSnapshot(progress) };
      }

      if (progress.transcriptButtonClicked) {
        if (transcriptPanel) {
          progress.panelOpened = true;
          const transcriptTab = findTranscriptTab(transcriptPanel);
          if (transcriptTab && !transcriptTabIsSelected(transcriptTab) && !clickedTranscriptTabs.has(transcriptTab)) {
            try {
              scrollIntoView(transcriptTab);
              transcriptTab.click();
              clickedTranscriptTabs.add(transcriptTab);
              progress.transcriptTabSelected = true;
            } catch {
              // Keep waiting: YouTube may replace or hydrate its tab after the click.
            }
            await sleep(pollIntervalMs);
            continue;
          }
          if (transcriptTab && transcriptTabIsSelected(transcriptTab)) progress.transcriptTabSelected = true;
          if (hasTranscriptLines(transcriptPanel)) {
            progress.transcriptLinesLoaded = true;
            return { ok: true, panel: transcriptPanel, opened: true, progress: progressSnapshot(progress) };
          }
        }
        await sleep(pollIntervalMs);
        continue;
      }

      if (!progress.descriptionExpanded) {
        const moreButton = findDescriptionExpandButton(document);
        if (moreButton) {
          try {
            scrollIntoView(moreButton);
            moreButton.click();
            progress.descriptionExpanded = true;
          } catch {
            // YouTube may replace a stale button while its page is hydrating.
          }
          await sleep(pollIntervalMs);
          continue;
        }
      }

      const transcriptSection = findTranscriptSection(document);
      if (transcriptSection) {
        progress.descriptionExpanded = true;
        progress.transcriptSectionFound = true;
        if (!scrolledTranscriptSections.has(transcriptSection)) {
          scrollIntoView(transcriptSection);
          scrolledTranscriptSections.add(transcriptSection);
        }
      }

      const transcriptButton = findShowTranscriptButton(document, transcriptSection);
      if (transcriptButton) {
        progress.transcriptButtonFound = true;
        try {
          scrollIntoView(transcriptButton);
          transcriptButton.click();
          progress.transcriptButtonClicked = true;
        } catch {
          // Keep polling: YouTube can replace a stale button during its delayed render.
        }
        await sleep(pollIntervalMs);
        continue;
      }

      await sleep(pollIntervalMs);
    }

    let ready = false;
    try {
      ready = Boolean(isPageReady());
    } catch {
      ready = false;
    }
    return {
      ok: false,
      reason: !ready ? 'page-not-ready' : progress.transcriptButtonClicked ? 'panel-not-loaded' : 'button-not-found',
      progress: progressSnapshot(progress)
    };
  }

  return {
    findDescriptionExpandButton,
    findShowTranscriptButton,
    findTranscriptPanel,
    manualActionMessage,
    openTranscriptPanel,
    progressSummary
  };
});
