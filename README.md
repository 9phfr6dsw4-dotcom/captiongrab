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

Download the latest `CaptionGrab.zip` from [GitHub Releases](https://github.com/9phfr6dsw4-dotcom/captiongrab/releases/latest). The app is ad-hoc signed and not notarized; macOS may require Control-click → **Open** the first time.

| Feature | Setup |
| --- | --- |
| Chrome fallback | Open CaptionGrab and click **Set up Chrome extension**. Approve the folder prompt for `Library/Application Support/Google/Chrome`. In Chrome's extensions page, enable **Developer mode**, choose **Load unpacked**, and select the `ChromeExtension` folder shown in Finder. |
| Automatic capture | Click **Get transcript** as usual. When direct retrieval is blocked, CaptionGrab opens the matching YouTube page in Chrome, reads the English transcript panel, and imports it locally. |
| Stable extension ID | The unpacked extension's `manifest.json` contains its public `key`; its ID remains `kajphiodjnkmgeidbcndikaaegghiffi` if you move the extension folder. |
| Local-only bridge | The extension needs only YouTube page access and `nativeMessaging`. It reads transcript text from the displayed page and sends it to a local helper; it does not request cookie access. Captured data stays in a CaptionGrab subfolder of Chrome's local profile. |

Keep CaptionGrab in its installed location after setup. If you move the app itself, click **Set up Chrome extension** again so Chrome's local helper registration can be refreshed. You can move the extension folder without changing the extension ID.

## Build and test

Requires Xcode and macOS 26 or later:

```sh
swift test
bash Scripts/package-app.sh
```

The public GitHub Actions workflow runs tests and packages the app on a standard `macos-26` runner. All caption fixtures in tests are invented sample data; tests do not contact YouTube.
