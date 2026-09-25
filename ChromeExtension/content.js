'use strict';

(() => {
  const extractor = globalThis.CaptionGrabExtractor;
  const panelOpener = globalThis.CaptionGrabTranscriptPanel;
  const currentURL = new URL(location.href);
  const requestID = currentURL.searchParams.get('captiongrab_request');
  const requestedVideoID = currentURL.searchParams.get('v');
  if (!extractor || !panelOpener || !requestID || !requestedVideoID) return;

  let finished = false;
  const requestURL = new URL(location.href);
  const startedAt = Date.now();

  function visibleText(node) {
    return String(node?.innerText ?? node?.textContent ?? '').replace(/\s+/g, ' ').trim();
  }

  function transcriptLanguage(panel) {
    if (!panel) return null;
    const nodes = [...panel.querySelectorAll('#language-menu, #dropdown-trigger, [id*="language" i], [class*="language" i], [aria-label*="language" i], button, [role="button"], tp-yt-paper-button')];
    for (const node of nodes) {
      const label = `${node.getAttribute('aria-label') || ''} ${visibleText(node)}`.trim();
      if (/^English(?:\s+\(auto-generated\))?$/i.test(visibleText(node))) return visibleText(node);
      if (/language/i.test(label)) {
        const match = label.match(/English(?:\s+\(auto-generated\))?/i);
        if (match) return match[0];
      }
    }
    const lines = String(panel.innerText || '').split(/\n+/).map(line => line.trim()).filter(Boolean);
    return [...lines].reverse().find(line => /^English(?:\s+\(auto-generated\))?$/i.test(line)) || null;
  }

  function transcriptCues(panel) {
    const scope = panel || document;
    const segments = scope.querySelectorAll('ytd-transcript-segment-renderer, yt-transcript-segment-renderer, .transcript-segment');
    return extractor.extractCues(segments);
  }

  function displayStatus(message, isError = false) {
    const node = document.createElement('div');
    node.textContent = message;
    node.setAttribute('role', 'status');
    Object.assign(node.style, {
      position: 'fixed', zIndex: '2147483647', right: '24px', bottom: '24px', maxWidth: '440px',
      padding: '14px 18px', borderRadius: '10px', background: isError ? '#8d1f1f' : '#1b5e20',
      color: '#fff', font: '14px/1.4 system-ui, sans-serif', boxShadow: '0 4px 18px #0008'
    });
    document.documentElement.appendChild(node);
    setTimeout(() => node.remove(), 8000);
  }

  function clearRequestFromHistory() {
    const cleanURL = new URL(location.href);
    cleanURL.searchParams.delete('captiongrab_request');
    history.replaceState(history.state, '', cleanURL.pathname + cleanURL.search + cleanURL.hash);
  }

  function sendToApp(message) {
    chrome.runtime.sendMessage(message, response => {
      if (chrome.runtime.lastError) {
        displayStatus('CaptionGrab could not connect to its Chrome helper. In CaptionGrab, choose Set up Chrome extension and load the unpacked extension.', true);
        clearRequestFromHistory();
        return;
      }
      if (!response?.ok) {
        displayStatus(response?.error || 'CaptionGrab could not receive this transcript.', true);
      } else {
        displayStatus('Transcript sent to CaptionGrab. You can return to the app.');
      }
      clearRequestFromHistory();
    });
  }

  function sendError(error, progress = null, debugLog = '') {
    if (finished) return;
    finished = true;
    const message = {
      type: 'captiongrab.error',
      requestID,
      videoID: requestedVideoID,
      error: String(error || 'Chrome could not read the YouTube transcript.').slice(0, 1000),
      ...(progress ? { progress } : {}),
      ...(debugLog ? { debugLog: String(debugLog).slice(0, 30_000) } : {})
    };
    displayStatus(message.error, true);
    sendToApp(message);
  }

  function appendDebugEvent(debugLog, event, details = {}) {
    const elapsed = Math.max(0, Date.now() - startedAt);
    const line = `[+${elapsed}ms] ${event} ${JSON.stringify(details)}`;
    return `${debugLog || ''}${debugLog ? '\n' : ''}${line}`.slice(-30_000);
  }

  function pageVideoID() {
    const match = location.pathname === '/watch' && new URL(location.href).searchParams.get('v');
    return match || '';
  }

  async function captureTranscript() {
    if (pageVideoID() !== requestedVideoID || !/^[A-Za-z0-9_-]{11}$/.test(requestedVideoID)) {
      sendError('The YouTube page no longer matches the video requested in CaptionGrab.');
      return;
    }

    const panelResult = await panelOpener.openTranscriptPanel({
      document,
      timeoutMs: 45_000,
      isPageReady: () => document.readyState === 'complete' &&
        pageVideoID() === requestedVideoID &&
        Boolean(document.querySelector('ytd-watch-flexy, ytd-watch-metadata, #movie_player'))
    });
    if (!panelResult.ok) {
      sendError(panelOpener.manualActionMessage(panelResult.reason), panelResult.progress, panelResult.debugLog);
      return;
    }

    while (!finished && Date.now() - startedAt < 90_000) {
      const panel = panelOpener.findTranscriptPanel(document);
      let cues = transcriptCues(panel);
      let language = transcriptLanguage(panel);
      if (cues.length && language) {
        if (!/^English(?:\s+\(auto-generated\))?$/i.test(language)) {
          sendError(`The transcript panel is set to ${language}, not English. Choose English in the transcript panel and try again.`, panelResult.progress, panelResult.debugLog);
          return;
        }
        const heading = document.querySelector('h1.ytd-watch-metadata yt-formatted-string, ytd-watch-metadata h1, h1');
        const title = visibleText(heading) || document.title.replace(/\s+-\s+YouTube\s*$/i, '').trim();
        const isAutoGenerated = /auto-generated/i.test(language) ? true : null;
        try {
          const message = extractor.buildCaptureMessage({
            requestID,
            videoID: requestedVideoID,
            title,
            languageName: language,
            isAutoGenerated
          }, cues);
          message.progress = panelResult.progress;
          message.debugLog = appendDebugEvent(panelResult.debugLog, 'transcript cues extracted', { cueCount: cues.length, language });
          finished = true;
          sendToApp(message);
          return;
        } catch (error) {
          sendError(error instanceof Error ? error.message : String(error), panelResult.progress, panelResult.debugLog);
          return;
        }
      }

      await new Promise(resolve => setTimeout(resolve, 500));
    }

    if (!finished) {
      sendError(
        'CaptionGrab could not read the English transcript after opening the YouTube transcript panel. In Chrome, confirm that the transcript has loaded and its language is English, then try again.',
        panelResult.progress,
        appendDebugEvent(panelResult.debugLog, 'transcript read timed out', { timeoutMs: 90_000 })
      );
    }
  }

  captureTranscript().catch(error => sendError(error instanceof Error ? error.message : String(error)));
})();
