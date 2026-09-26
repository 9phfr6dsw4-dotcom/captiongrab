<p align="center">
  <img src="docs/images/captiongrab-icon.png" width="88" alt="CaptionGrab app icon">
</p>

<h1 align="center">CaptionGrab</h1>

<p align="center">Get English YouTube captions and save them as Markdown or Word.</p>

<p align="center"><a href="https://github.com/9phfr6dsw4-dotcom/captiongrab/releases/latest"><strong>Download the latest release</strong></a> · macOS 26+</p>

<p align="center"><img src="docs/images/captiongrab-window.png" alt="CaptionGrab displaying a fetched YouTube transcript" width="820"></p>

## Features

- Paste or drop a YouTube link. CaptionGrab prefers creator-made English captions and falls back to auto-generated English when available.
- See the caption type, then copy the transcript or export it as Markdown or Word (`.docx`). Caption cue order and explicit line breaks are preserved.
- If YouTube blocks direct retrieval, the optional Chrome companion reads the transcript shown on the matching video page without changing the displayed language or subtitle setting. It does not request cookie access.
- If YouTube changes the transcript markup and CaptionGrab cannot parse the shown captions, Apple Foundation Models can try an on-device recovery; the result is checked against visible source text and timestamps and clearly marked for review.
- Clear or replace a link without losing the current transcript or recent-video list.
- Keep a recent-video list on your Mac and clear it whenever you like.

## Install

1. Download `CaptionGrab.zip` from the latest release and unzip it.
2. Move **CaptionGrab.app** to **Applications before opening it**.
3. Open it once. If macOS blocks it, go to **System Settings → Privacy & Security → Open Anyway**, confirm, then reopen CaptionGrab from Applications.

The release is ad-hoc signed and not notarized. CaptionGrab needs no macOS privacy permissions. The optional Chrome fallback needs the companion extension:

<details>
<summary>Set up the optional Chrome companion</summary>

1. Open CaptionGrab from Applications and choose **Set up Chrome extension**.
2. In Chrome, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select the `ChromeExtension` folder revealed by CaptionGrab.
3. If Chrome still points to an older or temporary folder, remove that stale entry and load the folder from the installed app.

Keep CaptionGrab in Applications after setup. If you move it, run setup again to refresh the Native Messaging helper path.
After installing CaptionGrab 1.2.16, open `chrome://extensions` and click **Reload** on the CaptionGrab companion so Chrome loads extension version 1.2.13 from the updated app bundle.
If automatic panel opening fails, use **Copy debug log** to capture a privacy-safe trace; caption text is not included.

</details>

## Privacy

CaptionGrab contacts YouTube for video information and captions. It uses no account, API key, paid service, analytics, or third-party transcription service. The optional Apple Foundation Models fallback runs only on this Mac, only when Apple Intelligence is available, and only after the deterministic transcript readers fail. The visible transcript text is passed from Chrome to CaptionGrab through local Native Messaging; it is not sent to a remote AI service. Generated cues must match the visible text and timestamps and are labeled for review. Recent-video history and preferences stay on your Mac; exports go only to the location you choose.

> CaptionGrab is an unofficial tool and is not affiliated with or endorsed by YouTube or Google. YouTube may change the web-player behavior the app relies on.

<details>
<summary>Build and test</summary>

Requires Xcode and macOS 26 or later.

```sh
swift test
bash Scripts/package-app.sh
```

</details>
