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
  const TRANSCRIPT_BUTTON_SEARCH_MS = 10_000;
  const TRANSCRIPT_PANEL_RETRY_INTERVAL_MS = 2_000;
  const MAX_TRANSCRIPT_BUTTON_ATTEMPTS = 3;
  const MAX_DEBUG_LOG_CHARS = 30_000;
  const MAX_DEBUG_EVENTS = 300;
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

  function inViewport(node, document) {
    const view = document?.defaultView;
    const rect = node?.getBoundingClientRect?.();
    if (!view || !rect || !(view.innerWidth > 0) || !(view.innerHeight > 0)) return false;
    const width = Number(rect.width ?? (rect.right - rect.left));
    const height = Number(rect.height ?? (rect.bottom - rect.top));
    return width > 0 && height > 0 && rect.right > 0 && rect.bottom > 0 &&
      rect.left < view.innerWidth && rect.top < view.innerHeight;
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
      if (candidate.matches?.('button, [role="button"], tp-yt-paper-button')) return candidate;
      const parent = candidate.parentElement;
      if (parent) {
        candidate = parent;
      } else {
        candidate = candidate.getRootNode?.()?.host ?? null;
      }
    }
    return null;
  }

  function findShowTranscriptButton(document, section = findTranscriptSection(document)) {
    const scopes = [];
    if (section && visible(section, document)) scopes.push(section);
    if (!scopes.includes(document)) scopes.push(document);

    for (const scope of scopes) {
      const directControls = allElements(scope).filter(node =>
        visible(node, document) &&
        node.matches?.('button, [role="button"], tp-yt-paper-button') &&
        hasShowTranscriptLabel(node)
      );
      if (directControls.length) {
        directControls.sort((left, right) => {
          const leftViewport = inViewport(left, document) ? 0 : 1;
          const rightViewport = inViewport(right, document) ? 0 : 1;
          if (leftViewport !== rightViewport) return leftViewport - rightViewport;
          const leftNative = left.matches?.('button') ? 0 : 1;
          const rightNative = right.matches?.('button') ? 0 : 1;
          return leftNative - rightNative || labels(left).join(' ').length - labels(right).join(' ').length;
        });
        return directControls[0];
      }
    }

    for (const scope of scopes) {
      const labelledContainers = allElements(scope).filter(node =>
        visible(node, document) && hasShowTranscriptLabel(node)
      );
      for (const container of labelledContainers) {
        const clickable = findClickableAncestor(container, document);
        if (clickable) return clickable;
      }
    }
    return null;
  }

  function nodesIncludingShadow(scope, selector) {
    return [...new Set([
      ...nodes(scope, selector),
      ...allElements(scope).filter(node => node.matches?.(selector))
    ])];
  }

  function hasTranscriptTabLabel(node) {
    return labels(node).some(value =>
      /^transcript$/i.test(value) || value.toLowerCase() === 'transcript tab'
    );
  }

  function isAncestorOrSelf(ancestor, node) {
    let current = node;
    const seen = new Set();
    while (current && !seen.has(current)) {
      if (current === ancestor) return true;
      seen.add(current);
      current = current.parentElement ?? current.getRootNode?.()?.host ?? null;
    }
    return false;
  }

  function belongsToDifferentEngagementPanel(node, panel) {
    let current = node;
    const seen = new Set();
    while (current && !seen.has(current)) {
      if (current !== panel && current.matches?.(ENGAGEMENT_PANEL_SELECTOR) && !isAncestorOrSelf(current, panel)) return true;
      if (current === panel) return false;
      seen.add(current);
      current = current.parentElement ?? current.getRootNode?.()?.host ?? null;
    }
    return false;
  }

  function isAssociatedWithTranscriptPanel(node, panel) {
    if (belongsToDifferentEngagementPanel(node, panel)) return false;

    let current = node;
    const seen = new Set();
    while (current && !seen.has(current)) {
      if (current === panel) return true;
      if (current.matches?.(ENGAGEMENT_PANEL_SELECTOR) && isAncestorOrSelf(current, panel)) return true;
      seen.add(current);
      current = current.parentElement ?? current.getRootNode?.()?.host ?? null;
    }

    const panelReferences = [
      panel?.id,
      panel?.getAttribute?.('id'),
      panel?.getAttribute?.('target-id'),
      panel?.getAttribute?.('targetId')
    ].map(value => String(value ?? '').trim()).filter(Boolean);
    const tabReferences = [node?.getAttribute?.('aria-controls'), node?.getAttribute?.('aria-owns')]
      .flatMap(value => String(value ?? '').trim().split(/\s+/)).filter(Boolean);
    if (panelReferences.some(value => tabReferences.includes(value))) return true;

    const tabID = String(node?.id ?? node?.getAttribute?.('id') ?? '').trim();
    const panelLabelReferences = String(panel?.getAttribute?.('aria-labelledby') ?? '').trim().split(/\s+/).filter(Boolean);
    return Boolean(tabID && panelLabelReferences.includes(tabID));
  }

  function modernTranscriptTabCandidates(panel, document) {
    const elements = allElements(document);
    const tabs = elements.filter(node =>
      node.matches?.('[role="tab"], tp-yt-paper-tab, yt-tab-shape') &&
      visible(node, document) && hasTranscriptTabLabel(node) && !belongsToDifferentEngagementPanel(node, panel)
    );
    const closeControls = elements.filter(node =>
      node.matches?.('button, [role="button"]') &&
      visible(node, document) && !belongsToDifferentEngagementPanel(node, panel) &&
      labels(node).some(value => /^close transcript$/i.test(value))
    );
    const chapterItemCount = nodesIncludingShadow(panel, 'macro-markers-panel-item-view-model').filter(node =>
      visible(node, document)
    ).length;
    return { tabs, closeControls, chapterItemCount };
  }

  function findTranscriptTab(panel, document = null) {
    const localTab = nodesIncludingShadow(panel, TRANSCRIPT_TAB_SELECTOR).find(node =>
      visible(node, document ?? panel) && hasTranscriptTabLabel(node)
    );
    if (localTab) return localTab;

    const targetID = panel?.getAttribute?.('target-id') ?? panel?.getAttribute?.('targetId') ?? '';
    if (targetID !== 'PAmodern_transcript_view' || !document) return null;
    const { tabs, closeControls, chapterItemCount } = modernTranscriptTabCandidates(panel, document);
    const associatedTabs = tabs.filter(node => isAssociatedWithTranscriptPanel(node, panel));
    if (associatedTabs.length === 1) return associatedTabs[0];
    // The modern UI can render its tab outside the panel without an ARIA link.
    // Only use that tab when the modern panel shows chapters and the page
    // also exposes YouTube's transcript-specific close control.
    return associatedTabs.length === 0 && tabs.length === 1 && closeControls.length > 0 && chapterItemCount > 0
      ? tabs[0] : null;
  }

  function modernTranscriptTabDiagnostics(panel, document) {
    const { tabs, closeControls, chapterItemCount } = modernTranscriptTabCandidates(panel, document);
    const allTabs = allElements(document).filter(node =>
      node.matches?.('[role="tab"], tp-yt-paper-tab, yt-tab-shape') && hasTranscriptTabLabel(node)
    );
    return {
      targetId: panel.getAttribute?.('target-id') ?? '',
      localTabCount: nodesIncludingShadow(panel, TRANSCRIPT_TAB_SELECTOR).filter(node =>
        visible(node, document) && hasTranscriptTabLabel(node)
      ).length,
      pageTabCount: tabs.length,
      inspectedTabCount: allTabs.length,
      closeTranscriptControlCount: closeControls.length,
      chapterItemCount,
      tabs: allTabs.slice(0, 5).map(node => {
        const isVisible = visible(node, document);
        const otherPanel = belongsToDifferentEngagementPanel(node, panel);
        const associated = isAssociatedWithTranscriptPanel(node, panel);
        return {
          tag: String(node.tagName ?? '').toLowerCase(),
          role: node.getAttribute?.('role') ?? '',
          associated,
          rejection: !isVisible ? 'hidden' : otherPanel ? 'other-panel' :
            associated ? 'none' : chapterItemCount === 0 ? 'no-chapters' :
              closeControls.length === 0 ? 'no-close-control' : tabs.length !== 1 ? 'ambiguous' : 'none',
          hasAriaControls: Boolean(node.getAttribute?.('aria-controls')),
          selected: transcriptTabIsSelected(node),
          inViewport: inViewport(node, document)
        };
      }),
      selectedTab: findTranscriptTab(panel, document) ? 'found' : 'none'
    };
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
    return nodesIncludingShadow(panel, TRANSCRIPT_LINE_SELECTOR).some(node => visible(node, panel));
  }

  function isTranscriptRelatedEngagementPanel(panel) {
    const targetID = panel?.getAttribute?.('target-id') ?? panel?.getAttribute?.('targetId') ?? '';
    if (targetID) return /transcript|macro-markers-description-chapters/i.test(targetID);
    return labels(panel).some(value => /\bin this video\b/i.test(value));
  }

  function findTranscriptPanel(document) {
    const dedicatedPanel = nodes(document, TRANSCRIPT_PANEL_SELECTOR).find(node => visible(node, document));
    if (dedicatedPanel) return dedicatedPanel;
    const engagementPanels = nodes(document, ENGAGEMENT_PANEL_SELECTOR).filter(panel =>
      visible(panel, document) && isTranscriptRelatedEngagementPanel(panel)
    );
    return engagementPanels.find(node => {
      const targetID = node.getAttribute?.('target-id') ?? node.getAttribute?.('targetId') ?? '';
      if (/transcript/i.test(targetID)) return true;
      const transcriptTab = findTranscriptTab(node, document);
      return Boolean(transcriptTab && transcriptTabIsSelected(transcriptTab));
    }) ?? null;
  }

  function engagementPanelState(panel, document = null) {
    const targetID = panel.getAttribute?.('target-id') ?? panel.getAttribute?.('targetId') ?? '';
    const transcriptTab = findTranscriptTab(panel, document);
    return `${targetID}|${transcriptTab ? transcriptTabIsSelected(transcriptTab) : false}`;
  }

  function captureEngagementPanelStates(document) {
    return new Map(nodes(document, ENGAGEMENT_PANEL_SELECTOR)
      .filter(panel => visible(panel, document) && findTranscriptTab(panel, document))
      .map(panel => [panel, engagementPanelState(panel, document)]));
  }

  function findEngagementPanelOpenedSince(document, previousStates) {
    return nodes(document, ENGAGEMENT_PANEL_SELECTOR).find(panel => {
      if (!visible(panel, document) || !isTranscriptRelatedEngagementPanel(panel) || !findTranscriptTab(panel, document)) return false;
      return !previousStates.has(panel) || previousStates.get(panel) !== engagementPanelState(panel, document);
    }) ?? null;
  }

  function progressSnapshot(progress) {
    return { ...progress };
  }

  function debugControlLabel(value) {
    const normalized = String(value ?? '').replace(/\s+/g, ' ').trim();
    if (!normalized) return '';
    if (/^(show transcript|close transcript|transcript|transcript tab|chapters|\.\.\.more|…more|more|read more)$/i.test(normalized)) return normalized;
    if (/^chapter\s+\d+\b/i.test(normalized)) return 'Chapter item';
    return '[other control]';
  }

  function describeControl(node, document = null) {
    const values = labels(node);
    return {
      tag: String(node?.tagName ?? '').toLowerCase(),
      id: String(node?.id ?? '').slice(0, 120),
      role: String(node?.getAttribute?.('role') ?? '').slice(0, 80),
      text: debugControlLabel(node?.innerText ?? node?.textContent),
      ariaLabel: debugControlLabel(node?.getAttribute?.('aria-label')),
      title: debugControlLabel(node?.getAttribute?.('title')),
      labels: values.slice(0, 4).map(debugControlLabel),
      visible: document ? visible(node, document) : Boolean(node && node.isConnected !== false && !node.hidden && node.getAttribute?.('aria-hidden') !== 'true'),
      inViewport: document ? inViewport(node, document) : null
    };
  }

  function describePanel(node, document) {
    return {
      tag: String(node?.tagName ?? '').toLowerCase(),
      id: String(node?.id ?? '').slice(0, 120),
      targetId: String(node?.getAttribute?.('target-id') ?? node?.getAttribute?.('targetId') ?? '').slice(0, 160),
      ariaLabel: debugControlLabel(node?.getAttribute?.('aria-label')),
      visible: visible(node, document)
    };
  }

  function inspectPage(document, pageReady) {
    const pageElements = allElements(document);
    const controls = pageElements
      .filter(node => node.matches?.(`${CONTROL_SELECTOR}, [role="tab"], tp-yt-paper-tab, yt-tab-shape`) && labels(node).some(value => /transcript|chapter/i.test(value)))
      .slice(0, 40)
      .map(node => describeControl(node, document));
    const panels = pageElements
      .filter(node => node.matches?.(`${ENGAGEMENT_PANEL_SELECTOR}, ${TRANSCRIPT_PANEL_SELECTOR}`))
      .filter(node => visible(node, document))
      .slice(0, 12)
      .map(node => describePanel(node, document));
    const section = findTranscriptSection(document);
    return {
      readyState: String(document?.readyState ?? 'unknown'),
      pageReady: Boolean(pageReady),
      transcriptSection: section ? {
        tag: String(section.tagName ?? '').toLowerCase(),
        id: String(section.id ?? '').slice(0, 120),
        visible: visible(section, document)
      } : null,
      transcriptRelatedControls: controls,
      openPanels: panels
    };
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
        : reason === 'button-not-clicked'
          ? 'CaptionGrab found the transcript button but could not click it before the search window ended.'
          : 'CaptionGrab could not find YouTube’s transcript button automatically.';
    return `${prefix} ${MANUAL_ACTIONS}${progress ? `\n\n${progressSummary(progress)}` : ''}`;
  }

  async function openTranscriptPanel({
    document = globalThis.document,
    isPageReady = () => document?.readyState === 'complete',
    sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds)),
    now = () => Date.now(),
    timeoutMs = 45_000,
    pollIntervalMs = 300,
    transcriptButtonTimeoutMs = TRANSCRIPT_BUTTON_SEARCH_MS
  } = {}) {
    const startedAt = now();
    const debugEvents = [];
    let lastObservation = '';
    let lastObservationAt = startedAt - 1_000;
    let lastHeartbeatAt = startedAt - 1_000;
    let lastReadyState = null;
    let pollCount = 0;
    let transcriptButtonSearchDeadline = null;
    let transcriptButtonAttempts = 0;
    let nextTranscriptPanelCheckAt = null;
    let lastTranscriptButton = null;
    let panelStatesBeforeFirstButtonClick = null;
    let lastTabDiagnostics = '';
    let pendingTabClick = null;
    let lastTabClick = null;
    const record = (event, details = null) => {
      const elapsed = Math.max(0, now() - startedAt);
      const suffix = details === null ? '' : ` ${JSON.stringify(details)}`;
      debugEvents.push(`[+${elapsed}ms] ${event}${suffix}`);
      if (debugEvents.length > MAX_DEBUG_EVENTS) debugEvents.shift();
    };
    const debugLog = () => {
      const value = debugEvents.join('\n');
      if (value.length <= MAX_DEBUG_LOG_CHARS) return value;
      const marker = '[earlier log text omitted]\n';
      return marker + value.slice(-(MAX_DEBUG_LOG_CHARS - marker.length));
    };
    record('automation started', { readyState: String(document?.readyState ?? 'unknown'), transcriptButtonTimeoutMs });
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
      pollCount += 1;
      let ready = false;
      try {
        ready = Boolean(isPageReady());
      } catch {
        ready = false;
      }
      if (ready !== lastReadyState || now() - lastObservationAt >= 750) {
        if (ready) {
          const snapshot = inspectPage(document, ready);
          const serialized = JSON.stringify(snapshot);
          if (serialized !== lastObservation) record('page observation', snapshot);
          lastObservation = serialized;
        } else {
          record('page not ready', { readyState: String(document?.readyState ?? 'unknown') });
        }
        lastObservationAt = now();
        lastReadyState = ready;
      }
      if (now() - lastHeartbeatAt >= 1_000) {
        const elapsedSinceExpandMs = transcriptButtonSearchDeadline === null
          ? null
          : Math.max(0, now() - (transcriptButtonSearchDeadline - transcriptButtonTimeoutMs));
        record(ready ? 'retrying transcript controls' : 'waiting for page to load', {
          pollCount,
          pageReady: ready,
          elapsedMs: now() - startedAt,
          elapsedSinceExpandMs,
          transcriptButtonSearchRemainingMs: transcriptButtonSearchDeadline === null
            ? null
            : Math.max(0, transcriptButtonSearchDeadline - now())
        });
        lastHeartbeatAt = now();
      }
      if (!ready) {
        await sleep(pollIntervalMs);
        continue;
      }

      let transcriptPanel = findTranscriptPanel(document);
      if (pendingTabClick) {
        const selected = transcriptTabIsSelected(pendingTabClick.tab);
        const rowsLoaded = hasTranscriptLines(pendingTabClick.panel);
        progress.transcriptTabSelected = selected;
        record('Transcript tab click outcome', {
          selected,
          rowsLoaded,
          tabConnected: pendingTabClick.tab.isConnected !== false,
          panelConnected: pendingTabClick.panel.isConnected !== false
        });
        pendingTabClick = null;
      }
      if (!transcriptPanel && transcriptButtonAttempts > 0 && panelStatesBeforeFirstButtonClick) {
        transcriptPanel = findEngagementPanelOpenedSince(document, panelStatesBeforeFirstButtonClick);
        if (transcriptPanel) {
          record('new In this video panel appeared after Show transcript click', describePanel(transcriptPanel, document));
        }
      }
      if (transcriptPanel?.getAttribute?.('target-id') === 'PAmodern_transcript_view' && transcriptButtonAttempts > 0) {
        const details = modernTranscriptTabDiagnostics(transcriptPanel, document);
        const serialized = JSON.stringify(details);
        if (serialized !== lastTabDiagnostics) record('Transcript tab candidates', details);
        lastTabDiagnostics = serialized;
      }
      if (transcriptPanel && hasTranscriptLines(transcriptPanel)) {
        if (!progress.panelOpened) record('transcript panel opened and transcript rows observed', inspectPage(document, ready).openPanels);
        progress.panelOpened = true;
        const transcriptTab = findTranscriptTab(transcriptPanel, document);
        if (transcriptTab && !transcriptTabIsSelected(transcriptTab) && !clickedTranscriptTabs.has(transcriptTab)) {
          try {
            scrollIntoView(transcriptTab);
            record('clicked Transcript tab', describeControl(transcriptTab));
            transcriptTab.click();
            clickedTranscriptTabs.add(transcriptTab);
            progress.transcriptTabSelected = true;
            pendingTabClick = { tab: transcriptTab, panel: transcriptPanel };
            lastTabClick = { tab: transcriptTab, panel: transcriptPanel, at: now() };
          } catch (error) {
            record('Transcript tab click threw', { error: String(error).slice(0, 240) });
          }
          await sleep(pollIntervalMs);
          continue;
        }
        progress.transcriptTabSelected = Boolean(transcriptTab && transcriptTabIsSelected(transcriptTab));
        progress.transcriptLinesLoaded = true;
        record('transcript lines loaded', { panel: describePanel(transcriptPanel, document), transcriptTabSelected: progress.transcriptTabSelected });
        return {
          ok: true, panel: transcriptPanel, opened: progress.transcriptButtonClicked,
          progress: progressSnapshot(progress), debugLog: debugLog(), elapsedMs: now() - startedAt
        };
      }

      if (transcriptButtonAttempts > 0) {
        if (transcriptPanel) {
          if (!progress.panelOpened) record('transcript panel appeared after Show transcript click', inspectPage(document, ready).openPanels);
          progress.panelOpened = true;
          const transcriptTab = findTranscriptTab(transcriptPanel, document);
          if (transcriptTab && !transcriptTabIsSelected(transcriptTab) && !clickedTranscriptTabs.has(transcriptTab)) {
            try {
              scrollIntoView(transcriptTab);
              record('clicked Transcript tab', describeControl(transcriptTab));
              transcriptTab.click();
              clickedTranscriptTabs.add(transcriptTab);
              progress.transcriptTabSelected = true;
              pendingTabClick = { tab: transcriptTab, panel: transcriptPanel };
              lastTabClick = { tab: transcriptTab, panel: transcriptPanel, at: now() };
            } catch (error) {
              record('Transcript tab click threw', { error: String(error).slice(0, 240) });
            }
            await sleep(pollIntervalMs);
            continue;
          }
          if (transcriptTab && transcriptTabIsSelected(transcriptTab) && !progress.transcriptTabSelected) {
            progress.transcriptTabSelected = true;
            record('Transcript tab is selected', describeControl(transcriptTab));
          }
          if (hasTranscriptLines(transcriptPanel)) {
            progress.transcriptLinesLoaded = true;
            record('transcript lines loaded', { panel: describePanel(transcriptPanel, document), transcriptTabSelected: progress.transcriptTabSelected });
            return {
              ok: true, panel: transcriptPanel, opened: true,
              progress: progressSnapshot(progress), debugLog: debugLog(), elapsedMs: now() - startedAt
            };
          }
          await sleep(pollIntervalMs);
          continue;
        }

        if (nextTranscriptPanelCheckAt !== null && now() >= nextTranscriptPanelCheckAt) {
          if (transcriptButtonAttempts >= MAX_TRANSCRIPT_BUTTON_ATTEMPTS) {
            record('transcript panel did not open after three Show transcript button attempts', {
              attempts: transcriptButtonAttempts,
              retryIntervalMs: TRANSCRIPT_PANEL_RETRY_INTERVAL_MS
            });
            return {
              ok: false,
              reason: 'panel-not-loaded',
              progress: progressSnapshot(progress),
              debugLog: debugLog(),
              elapsedMs: now() - startedAt
            };
          }
          const section = findTranscriptSection(document);
          const button = findShowTranscriptButton(document, section) ??
            (lastTranscriptButton && visible(lastTranscriptButton, document) ? lastTranscriptButton : null);
          if (!button) {
            record('cannot retry Show transcript because its visible button is no longer available', {
              attempts: transcriptButtonAttempts,
              lastButton: lastTranscriptButton ? describeControl(lastTranscriptButton) : null
            });
            return {
              ok: false,
              reason: 'panel-not-loaded',
              progress: progressSnapshot(progress),
              debugLog: debugLog(),
              elapsedMs: now() - startedAt
            };
          }
          transcriptButtonAttempts += 1;
          lastTranscriptButton = button;
          scrollIntoView(button);
          record(`clicked Show transcript button (attempt ${transcriptButtonAttempts}/${MAX_TRANSCRIPT_BUTTON_ATTEMPTS})`, describeControl(button, document));
          try {
            button.click();
            progress.transcriptButtonClicked = true;
          } catch (error) {
            record('Show transcript button click threw', { attempt: transcriptButtonAttempts, error: String(error).slice(0, 240) });
          }
          nextTranscriptPanelCheckAt = now() + TRANSCRIPT_PANEL_RETRY_INTERVAL_MS;
          continue;
        }

        const retryDelay = nextTranscriptPanelCheckAt === null
          ? pollIntervalMs
          : Math.min(pollIntervalMs, Math.max(1, nextTranscriptPanelCheckAt - now()));
        await sleep(retryDelay);
        continue;
      }

      if (!progress.descriptionExpanded) {
        const moreButton = findDescriptionExpandButton(document);
        if (moreButton) {
          try {
            scrollIntoView(moreButton);
            record('clicked description expand control', describeControl(moreButton));
            moreButton.click();
            progress.descriptionExpanded = true;
            transcriptButtonSearchDeadline = now() + Math.max(0, transcriptButtonTimeoutMs);
            record('description expanded; transcript-button search window started', { searchWindowMs: transcriptButtonTimeoutMs });
          } catch (error) {
            record('description expand click threw', { control: describeControl(moreButton), error: String(error).slice(0, 240) });
          }
          await sleep(pollIntervalMs);
          continue;
        }
      }

      const transcriptSection = findTranscriptSection(document);
      if (transcriptSection) {
        progress.descriptionExpanded = true;
        if (!progress.transcriptSectionFound) {
          progress.transcriptSectionFound = true;
          record('Transcript section found', { section: describePanel(transcriptSection, document) });
        }
        if (!scrolledTranscriptSections.has(transcriptSection)) {
          scrollIntoView(transcriptSection);
          scrolledTranscriptSections.add(transcriptSection);
          record('scrolled Transcript section into view', { section: describePanel(transcriptSection, document) });
        }
      }

      const transcriptButton = findShowTranscriptButton(document, transcriptSection);
      const searchWindowExpired = transcriptButtonSearchDeadline !== null && now() > transcriptButtonSearchDeadline;
      if (transcriptButton) {
        if (!progress.transcriptButtonFound) {
          progress.transcriptButtonFound = true;
          record('Show transcript button found', describeControl(transcriptButton, document));
        }
        if (searchWindowExpired) {
          record('Show transcript button appeared after the search window; not clicking it', describeControl(transcriptButton, document));
        } else {
          if (panelStatesBeforeFirstButtonClick === null) {
            panelStatesBeforeFirstButtonClick = captureEngagementPanelStates(document);
            record('captured panel state before Show transcript click', [...panelStatesBeforeFirstButtonClick].map(([panel, state]) => ({
              ...describePanel(panel, document), state
            })));
          }
          transcriptButtonAttempts += 1;
          lastTranscriptButton = transcriptButton;
          scrollIntoView(transcriptButton);
          record(`clicked Show transcript button (attempt ${transcriptButtonAttempts}/${MAX_TRANSCRIPT_BUTTON_ATTEMPTS})`, describeControl(transcriptButton, document));
          try {
            transcriptButton.click();
            progress.transcriptButtonClicked = true;
          } catch (error) {
            record('Show transcript button click threw', { attempt: transcriptButtonAttempts, error: String(error).slice(0, 240) });
          }
          nextTranscriptPanelCheckAt = now() + TRANSCRIPT_PANEL_RETRY_INTERVAL_MS;
          continue;
        }
      }

      if (transcriptButtonSearchDeadline !== null && now() >= transcriptButtonSearchDeadline && !progress.transcriptButtonClicked) {
        const elapsed = now() - startedAt;
        const reason = progress.transcriptButtonFound ? 'button-not-clicked' : 'button-not-found';
        record(
          reason === 'button-not-found'
            ? 'Show transcript button not found before the ten-second search window ended'
            : 'Show transcript button click did not succeed before the search window ended',
          {
            windowMs: transcriptButtonTimeoutMs,
            elapsedSinceExpandMs: transcriptButtonTimeoutMs,
            latestPageObservation: lastObservation ? JSON.parse(lastObservation) : null
          }
        );
        return {
          ok: false,
          reason,
          progress: progressSnapshot(progress),
          debugLog: debugLog(),
          elapsedMs: elapsed
        };
      }
      await sleep(pollIntervalMs);
    }

    let ready = false;
    try {
      ready = Boolean(isPageReady());
    } catch {
      ready = false;
    }
    const reason = !ready ? 'page-not-ready' : progress.transcriptButtonClicked ? 'panel-not-loaded' : 'button-not-found';
    if (lastTabClick) {
      record('Transcript tab final state', {
        elapsedSinceClickMs: now() - lastTabClick.at,
        selected: transcriptTabIsSelected(lastTabClick.tab),
        rowsLoaded: hasTranscriptLines(lastTabClick.panel),
        tabConnected: lastTabClick.tab.isConnected !== false,
        panelConnected: lastTabClick.panel.isConnected !== false
      });
    }
    record('automation stopped', { reason, elapsedMs: now() - startedAt, progress: progressSnapshot(progress) });
    return {
      ok: false,
      reason,
      progress: progressSnapshot(progress),
      debugLog: debugLog(),
      elapsedMs: now() - startedAt
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
