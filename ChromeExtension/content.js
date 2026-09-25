'use strict';

(() => {
  const extractor = globalThis.CaptionGrabExtractor;
  const currentURL = new URL(location.href);
  const requestID = currentURL.searchParams.get('captiongrab_request');
  const requestedVideoID = currentURL.searchParams.get('v');
  if (!extractor || !requestID || !requestedVideoID) return;

  let finished = false;
  const requestURL = new URL(location.href);
  const startedAt = Date.now();

  function visibleText(node) {
    return String(node?.innerText ?? node?.textContent ?? '').replace(/\s+/g, ' ').trim();
  }

  function controls(scope = document) {
    return [...scope.querySelectorAll('button, [role="button"], tp-yt-paper-button, yt-button-shape, ytd-button-renderer')];
  }

  function isVisible(node) {
    if (!node || !node.isConnected) return false;
    const style = getComputedStyle(node);
    return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
  }

  function findTranscriptButton() {
    const section = document.querySelector('ytd-video-description-transcript-section-renderer');
    const local = section ? controls(section) : [];
    const all = [...local, ...controls()];
    return all.find(node => isVisible(node) && /^show transcript$/i.test(visibleText(node))) ||
      all.find(node => isVisible(node) && /show transcript/i.test(node.getAttribute('aria-label') || '')) || null;
  }

  function expandDescription() {
    const direct = document.querySelector('ytd-text-inline-expander #expand, #description-inline-expander #expand, #description #expand');
    if (direct && isVisible(direct)) {
      direct.click();
      return true;
    }
    const description = document.querySelector('#description, ytd-watch-metadata, ytd-video-secondary-info-renderer');
    if (!description) return false;
    const more = controls(description).find(node => isVisible(node) && /^(more|read more)$/i.test(visibleText(node)));
    if (more) {
      more.click();
      return true;
    }
    return false;
  }

  function transcriptPanel() {
    return document.querySelector('ytd-transcript-renderer, yt-transcript-renderer, ytd-transcript-search-panel-renderer') ||
      document.querySelector('ytd-engagement-panel-section-list-renderer[target-id*="transcript"]');
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

  function sendError(error) {
    if (finished) return;
    finished = true;
    const message = {
      type: 'captiongrab.error',
      requestID,
      videoID: requestedVideoID,
      error: String(error || 'Chrome could not read the YouTube transcript.').slice(0, 1000)
    };
    displayStatus(message.error, true);
    sendToApp(message);
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

    let attemptedExpand = false;
    let attemptedOpen = false;
    while (!finished && Date.now() - startedAt < 90_000) {
      const panel = transcriptPanel();
      let cues = transcriptCues(panel);
      let language = transcriptLanguage(panel);
      if (cues.length && language) {
        if (!/^English(?:\s+\(auto-generated\))?$/i.test(language)) {
          sendError(`The transcript panel is set to ${language}, not English. Choose English in the transcript panel and try again.`);
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
          finished = true;
          sendToApp(message);
          return;
        } catch (error) {
          sendError(error instanceof Error ? error.message : String(error));
          return;
        }
      }

      const showTranscript = findTranscriptButton();
      if (showTranscript && !attemptedOpen) {
        showTranscript.click();
        attemptedOpen = true;
        await new Promise(resolve => setTimeout(resolve, 400));
        continue;
      }
      if (!attemptedExpand) attemptedExpand = expandDescription();
      await new Promise(resolve => setTimeout(resolve, 500));
    }

    if (!finished) {
      sendError('CaptionGrab could not find an English transcript in this YouTube page. Confirm Show transcript is available, then try again.');
    }
  }

  captureTranscript().catch(error => sendError(error instanceof Error ? error.message : String(error)));
})();
