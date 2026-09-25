(function attach(root, factory) {
  const api = factory();
  if (typeof module === 'object' && module.exports) module.exports = api;
  root.CaptionGrabTranscriptPanel = api;
})(globalThis, function createTranscriptPanelOpener() {
  'use strict';

  const CONTROL_SELECTOR = 'button, [role="button"], tp-yt-paper-button, yt-button-shape, ytd-button-renderer, #expand';
  const DESCRIPTION_SELECTOR = '#description, #description-inline-expander, ytd-text-inline-expander, ytd-watch-metadata, ytd-video-secondary-info-renderer, ytd-video-primary-info-renderer';
  const TRANSCRIPT_SECTION_SELECTOR = 'ytd-video-description-transcript-section-renderer, ytd-video-secondary-info-renderer, ytd-watch-metadata, ytd-watch-flexy';
  const TRANSCRIPT_PANEL_SELECTOR = 'ytd-transcript-renderer, yt-transcript-renderer, ytd-transcript-search-panel-renderer';
  const ENGAGEMENT_PANEL_SELECTOR = 'ytd-engagement-panel-section-list-renderer, yt-engagement-panel-section-list-renderer';
  const TRANSCRIPT_TAB_SELECTOR = 'button, [role="button"], [role="tab"], tp-yt-paper-tab, yt-tab-shape, yt-button-shape, ytd-button-renderer';
  const TRANSCRIPT_LINE_SELECTOR = 'ytd-transcript-segment-renderer, yt-transcript-segment-renderer, .transcript-segment';
  const MANUAL_ACTIONS = 'In the Chrome video tab, expand “...more” in the description if shown, scroll down in the expanded description, and click the “Show transcript” button. If the “In this video” panel opens on “Chapters,” click its “Transcript” tab. Wait for transcript lines to appear, then try Get transcript again.';

  function nodes(scope, selector) {
    try {
      return [...(scope?.querySelectorAll?.(selector) ?? [])];
    } catch {
      return [];
    }
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

  function findShowTranscriptButton(document) {
    const sections = nodes(document, TRANSCRIPT_SECTION_SELECTOR);
    const preferred = sections.flatMap(section => nodes(section, CONTROL_SELECTOR));
    const candidates = [...new Set([...preferred, ...nodes(document, CONTROL_SELECTOR)])];
    return candidates.find(node => visible(node, document) && labels(node).some(value =>
      /^show transcript$/i.test(value) || /\bshow transcript\b/i.test(value)
    )) ?? null;
  }

  function findTranscriptTab(panel) {
    return nodes(panel, TRANSCRIPT_TAB_SELECTOR).find(node => visible(node, panel) && labels(node).some(value =>
      /^transcript$/i.test(value) || value.toLowerCase() === 'transcript tab'
    )) ?? null;
  }

  function transcriptTabIsSelected(tab) {
    const className = String(tab?.getAttribute?.('class') ?? tab?.className ?? '');
    return tab?.getAttribute?.('aria-selected') === 'true' ||
      tab?.getAttribute?.('aria-pressed') === 'true' ||
      tab?.getAttribute?.('aria-current') === 'page' ||
      tab?.getAttribute?.('selected') !== null ||
      className.toLowerCase().split(' ').some(token => token === 'selected' || token.endsWith('--selected')) ||
      /(?:\\bselected\\b|--selected\\b|\\bactive\\b|--active\\b)/i.test(className);
  }

  function hasTranscriptLines(panel) {
    return nodes(panel, TRANSCRIPT_LINE_SELECTOR).some(node => visible(node, panel));
  }

  function findTranscriptPanel(document) {
    const engagementPanels = nodes(document, ENGAGEMENT_PANEL_SELECTOR).filter(node => visible(node, document));
    const inThisVideoPanel = engagementPanels.find(node => Boolean(findTranscriptTab(node)));
    if (inThisVideoPanel) return inThisVideoPanel;

    const transcriptRenderer = nodes(document, TRANSCRIPT_PANEL_SELECTOR).find(node => visible(node, document));
    if (transcriptRenderer) return transcriptRenderer;
    return engagementPanels.find(node =>
      /transcript/i.test(node.getAttribute?.('target-id') ?? node.getAttribute?.('targetId') ?? '')
    ) ?? null;
  }

  function manualActionMessage(reason) {
    const prefix = reason === 'page-not-ready'
      ? 'The YouTube page did not finish loading in time.'
      : reason === 'panel-not-loaded'
        ? 'YouTube did not show the transcript panel after CaptionGrab clicked its button.'
        : 'CaptionGrab could not find YouTube’s transcript button automatically.';
    return `${prefix} ${MANUAL_ACTIONS}`;
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
    let descriptionExpanded = false;
    let transcriptButtonClicked = false;
    const clickedTranscriptTabs = new WeakSet();

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

      const existingPanel = findTranscriptPanel(document);
      if (existingPanel) {
        const transcriptTab = findTranscriptTab(existingPanel);
        if (transcriptTab && !transcriptTabIsSelected(transcriptTab) && !clickedTranscriptTabs.has(transcriptTab)) {
          try {
            transcriptTab.scrollIntoView?.({ block: 'center', behavior: 'instant' });
            transcriptTab.click();
            clickedTranscriptTabs.add(transcriptTab);
          } catch {
            // Keep waiting: YouTube may replace or hydrate its tab after the click.
          }
          await sleep(pollIntervalMs);
          continue;
        }
        if (hasTranscriptLines(existingPanel)) {
          return { ok: true, panel: existingPanel, opened: transcriptButtonClicked };
        }
        await sleep(pollIntervalMs);
        continue;
      }

      if (!descriptionExpanded) {
        const moreButton = findDescriptionExpandButton(document);
        if (moreButton) {
          try {
            moreButton.scrollIntoView?.({ block: 'center', behavior: 'instant' });
            moreButton.click();
            descriptionExpanded = true;
          } catch {
            // YouTube may replace a stale button while its page is hydrating.
          }
          await sleep(pollIntervalMs);
          continue;
        }
      }

      if (!transcriptButtonClicked) {
        const transcriptButton = findShowTranscriptButton(document);
        if (transcriptButton) {
          try {
            transcriptButton.scrollIntoView?.({ block: 'center', behavior: 'instant' });
            transcriptButton.click();
            transcriptButtonClicked = true;
          } catch {
            // Keep polling for a replacement control or a panel opened by the page.
          }
          await sleep(pollIntervalMs);
          continue;
        }
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
      reason: !ready ? 'page-not-ready' : transcriptButtonClicked ? 'panel-not-loaded' : 'button-not-found'
    };
  }

  return { findDescriptionExpandButton, findShowTranscriptButton, findTranscriptPanel, manualActionMessage, openTranscriptPanel };
});
