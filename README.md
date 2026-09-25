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

1. Download the latest `CaptionGrab.zip`, replace `CaptionGrab.app` in Applications, and open it from Applications. The Chrome helper setup now detects when macOS launched a temporary App Translocation copy and asks Launch Services for a matching, complete, non-translocated installed copy. It registers the Native Messaging helper and reveals the extension folder from that stable copy—not the temporary path.
2. Choose **Set up Chrome extension**. If CaptionGrab cannot find a valid installed copy, it shows Finder-only recovery steps with **Open Applications in Finder** and **Quit CaptionGrab** buttons. Quit, double-click CaptionGrab from Applications, and run setup again. If it is not there, use Finder to move CaptionGrab.app into Applications first; no Terminal commands are needed.
3. In Chrome, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select the `ChromeExtension` folder revealed by CaptionGrab. If Chrome still shows an extension loaded from the old temporary location, remove that stale entry and load the folder from the installed app.
4. Click **Get transcript** as usual. When direct retrieval is blocked, CaptionGrab opens the matching video in Chrome, expands the description, waits for the Transcript section, clicks the inner **Show transcript** button, checks whether the transcript panel opened within about two seconds, and retries up to three total clicks if it did not. It selects the Transcript tab if the panel defaults to Chapters, then checks the transcript language menu, prefers regular English over auto-generated English, and uses auto-generated captions only when regular English is unavailable.
5. After installing CaptionGrab 1.2.8, open `chrome://extensions` and click **Reload** on the CaptionGrab unpacked extension so Chrome uses the updated transcript language selection. You do not need to remove and re-add it; its extension ID stays the same.
6. If automatic panel opening fails, click **Copy debug log** beneath CaptionGrab’s message, then paste the copied text into your reply. The log records relative timings, transcript-related button labels/text, CSS and on-screen visibility, observed open panels, and controls clicked or attempted. It does not include caption text. Other setup failures show the exact operation, path, OS error domain/code, and underlying error text.

On launch, CaptionGrab removes the old `CaptionGrab.chromeNativeMessagingFolderBookmark` preference left by older versions. This does not clear other settings, such as your chosen export folder. The Chrome Native Messaging manifest is installed under Chrome's Application Support folder; transcript messages are stored in CaptionGrab's normal Application Support folder. The extension reads transcript text shown on YouTube and does not request cookie access. Its fixed ID remains `kajphiodjnkmgeidbcndikaaegghiffi` if the extension folder is moved. Keep CaptionGrab in its installed location after setup; if you move the app itself, click **Set up Chrome extension** again to refresh the host path.

## Chrome transcript debug log
If Chrome transcript automation fails, leave CaptionGrab open and click **Copy debug log** beneath the error. Paste the copied text into your reply here. The trace includes elapsed timings, transcript-related button text/ARIA labels and visibility, open panel identifiers, and controls the extension clicked or attempted. It does not include transcript caption text.

## Build and test

Requires Xcode and macOS 26 or later:

```sh
swift test
bash Scripts/package-app.sh
```

The public GitHub Actions workflow runs tests and packages the app on a standard `macos-26` runner. All caption fixtures in tests are invented sample data; tests do not contact YouTube.
