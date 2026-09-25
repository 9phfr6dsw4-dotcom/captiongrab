# CaptionGrab

CaptionGrab is a native SwiftUI macOS app for fetching an English caption track from a YouTube link and exporting it as Markdown or Word (`.docx`). It prefers creator-made English captions and falls back to auto-generated English captions, with the track type shown in the app. If YouTube blocks direct requests, CaptionGrab can automatically read the transcript panel from a matching YouTube page in Chrome through its bundled unpacked extension and local Native Messaging helper.

**CaptionGrab is an unofficial personal-use tool and is not affiliated with, endorsed by, or sponsored by YouTube or Google.** It uses YouTube's undocumented web-player behavior, which may change or become unavailable.

## Use

1. Paste or drag a YouTube watch, short, Shorts, live, or embed link into the app.
2. Select **Get transcript**. The app shows the title, selected caption type, and transcript.
3. Choose **Copy all**, **Save Markdown**, or **Save Word document**.
4. Review or clear the locally stored recent list at any time.

No account, API key, paid service, AI, or third-party runtime dependency is used. The app's network client is restricted to YouTube hosts. Transcript formatting, export, and history are handled on your Mac. Exported files are saved only to a location you choose.

CaptionGrab preserves the caption events and text supplied by YouTube, including source event order and explicit line breaks. The YouTube transcript panel has no published stable export contract; its visual line wrapping or grouping may differ. See [`docs/research.md`](docs/research.md).

## Download

Download the latest [`CaptionGrab.zip`](https://github.com/9phfr6dsw4-dotcom/captiongrab/releases/latest) from GitHub Releases. Requires macOS 26 or later. The app is not App Sandbox-signed; its ad-hoc signature is not notarized, so the first launch may require Control-click → **Open**.

## Chrome transcript fallback

1. Open CaptionGrab and choose **Set up Chrome extension**. No folder picker or folder-access bookmark is needed.
2. CaptionGrab registers its Native Messaging host at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.captiongrab.host.json` and creates its transcript inbox at `~/Library/Application Support/CaptionGrab/ChromeInbox`.
3. In Chrome, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select the `ChromeExtension` folder revealed by CaptionGrab.
4. Click **Get transcript** as usual. When direct retrieval is blocked, CaptionGrab opens the matching video in Chrome and reads its English transcript panel.
5. If setup fails, the app displays the failing operation, exact path, operating-system error domain/code, and underlying error text. The error text is selectable so it can be copied.

On launch, CaptionGrab removes the old `CaptionGrab.chromeNativeMessagingFolderBookmark` preference left by older versions. This does not clear other settings, such as your chosen export folder. The Chrome Native Messaging manifest is installed under Chrome's Application Support folder; transcript messages are stored in CaptionGrab's normal Application Support folder. The extension reads transcript text shown on YouTube and does not request cookie access. Its fixed ID remains `kajphiodjnkmgeidbcndikaaegghiffi` if the extension folder is moved. Keep CaptionGrab in its installed location after setup; if you move the app itself, click **Set up Chrome extension** again to refresh the host path.

## Build and test

Requires Xcode and macOS 26 or later:

```sh
swift test
bash Scripts/package-app.sh
```

The public GitHub Actions workflow runs tests and packages the app on a standard `macos-26` runner. All caption fixtures in tests are invented sample data; tests do not contact YouTube.
