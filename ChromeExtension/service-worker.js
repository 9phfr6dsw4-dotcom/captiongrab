'use strict';

const HOST_NAME = 'com.captiongrab.host';
const VIDEO_ID = /^[A-Za-z0-9_-]{11}$/;
const REQUEST_ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !['captiongrab.transcript', 'captiongrab.error'].includes(message.type)) return false;

  try {
    const page = new URL(sender.url || '');
    const videoID = page.searchParams.get('v');
    const requestID = page.searchParams.get('captiongrab_request');
    const requestMatches = REQUEST_ID.test(requestID || '') && requestID === message.requestID;
    const messageVideoIsValid = VIDEO_ID.test(message.videoID || '');
    const pageIsValid = page.protocol === 'https:' && page.hostname === 'www.youtube.com' && page.pathname === '/watch';
    const videoMatches = VIDEO_ID.test(videoID || '') && videoID === message.videoID;
    const isSafeMismatchError = message.type === 'captiongrab.error' && messageVideoIsValid;
    if (!pageIsValid || !requestMatches || !messageVideoIsValid || (!videoMatches && !isSafeMismatchError)) {
      sendResponse({ ok: false, error: 'CaptionGrab rejected a message not tied to the requested YouTube video.' });
      return false;
    }
  } catch {
    sendResponse({ ok: false, error: 'CaptionGrab could not verify the YouTube tab.' });
    return false;
  }

  chrome.runtime.sendNativeMessage(HOST_NAME, message, response => {
    if (chrome.runtime.lastError) {
      sendResponse({ ok: false, error: 'CaptionGrab native host is unavailable. Run Set up Chrome extension in CaptionGrab, then load the unpacked extension.' });
      return;
    }
    sendResponse(response || { ok: false, error: 'The CaptionGrab native host returned no response.' });
  });
  return true;
});
