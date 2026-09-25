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

  function transcriptCues(panel) {
    return extractor.extractTranscriptCues(panel || document);
  }

  function languageSelectionError(selection) {
    const languages = selection.availableLanguages.join(', ') || 'none detected';
    switch (selection.reason) {
      case 'no-english-language':
        return `No English captions are available in the transcript panel. Available languages: ${languages}.`;
      case 'transcript-refresh-not-confirmed':
        return `YouTube selected ${selection.selectedLanguage}, but CaptionGrab could not confirm that its captions refreshed. Try again.`;
      case 'language-menu-unavailable':
      case 'language-options-unavailable':
        return `CaptionGrab could not inspect the transcript language menu, so it cannot confirm the preferred English captions. Open the transcript language menu in YouTube and try again. Available languages: ${languages}.`;
      default:
        return `CaptionGrab could not select and confirm an English transcript (${selection.reason}). Available languages: ${languages}.`;
    }
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

    const transcriptPanel = panelOpener.findTranscriptPanel(document);
    if (!transcriptPanel) {
      sendError('YouTube opened the transcript panel, but CaptionGrab could not find its language controls.', panelResult.progress, panelResult.debugLog);
      return;
    }

    const displayedModernTranscript = transcriptPanel.getAttribute?.('target-id') === 'PAmodern_transcript_view';
    const languageSelection = displayedModernTranscript
      ? {
          ok: true, reason: 'displayed-transcript', availableLanguages: [],
          currentlySelectedLanguage: null, selectedLanguage: 'as-displayed',
          isAutoGenerated: null, menuInspected: false,
          selectionConfirmed: false, transcriptRefreshed: false
        }
      : await extractor.selectPreferredEnglishTranscript({ panel: transcriptPanel, document });
    const debugLog = appendDebugEvent(panelResult.debugLog, 'transcript language selection', {
      reason: languageSelection.reason,
      availableLanguages: languageSelection.availableLanguages,
      previouslySelectedLanguage: languageSelection.currentlySelectedLanguage,
      selectedLanguage: languageSelection.selectedLanguage,
      isAutoGenerated: languageSelection.isAutoGenerated,
      menuInspected: languageSelection.menuInspected,
      selectionConfirmed: languageSelection.selectionConfirmed,
      transcriptRefreshed: languageSelection.transcriptRefreshed
    });
    if (!languageSelection.ok) {
      sendError(languageSelectionError(languageSelection), panelResult.progress, debugLog);
      return;
    }

    while (!finished && Date.now() - startedAt < 90_000) {
      const panel = panelOpener.findTranscriptPanel(document) || transcriptPanel;
      if (displayedModernTranscript && panel !== transcriptPanel) {
        sendError('YouTube replaced the transcript panel while CaptionGrab was reading it. Try again.',
          panelResult.progress, appendDebugEvent(debugLog, 'transcript panel changed'));
        return;
      }
      const cues = transcriptCues(panel);
      if (cues.length) {
        const language = languageSelection.selectedLanguage;
        const heading = document.querySelector('h1.ytd-watch-metadata yt-formatted-string, ytd-watch-metadata h1, h1');
        const title = visibleText(heading) || document.title.replace(/\s+-\s+YouTube\s*$/i, '').trim();
        const isAutoGenerated = languageSelection.isAutoGenerated;
        try {
          const message = extractor.buildCaptureMessage({
            requestID,
            videoID: requestedVideoID,
            title,
            languageName: language,
            isAutoGenerated
          }, cues);
          message.progress = panelResult.progress;
          message.debugLog = appendDebugEvent(debugLog, 'transcript cues extracted', {
            cueCount: cues.length,
            language,
            isAutoGenerated
          });
          finished = true;
          sendToApp(message);
          return;
        } catch (error) {
          sendError(error instanceof Error ? error.message : String(error), panelResult.progress, debugLog);
          return;
        }
      }

      await new Promise(resolve => setTimeout(resolve, 500));
    }

    if (!finished) {
      sendError(
        displayedModernTranscript
          ? 'CaptionGrab could not read the transcript shown in YouTube’s panel. Wait for its lines to load, then try again.'
          : 'CaptionGrab could not read the selected English transcript after opening YouTube’s transcript panel. Confirm that the selected language has loaded, then try again.',
        panelResult.progress,
        appendDebugEvent(debugLog, 'transcript read timed out', { timeoutMs: 90_000, language: languageSelection.selectedLanguage })
      );
    }
  }

  captureTranscript().catch(error => sendError(error instanceof Error ? error.message : String(error)));
})();
