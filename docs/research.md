# YouTube transcript research and implementation choices

## What the existing tools show

- YouTube's help page describes **Show transcript** as available on videos that have captions; its transcript follows the current caption text and each line can jump to that point in the video. It does not document an export format or a stable public transcript API.
- `youtube-transcript-api` inspects YouTube web-player caption metadata, represents each caption as timed text, and exposes whether a track is generated. Its CLI can exclude generated or manually created tracks. The project explicitly warns that it relies on an undocumented YouTube web API and may stop working when that behavior changes. Its README also documents age/login restrictions and HTTP 429/IP blocking as failure cases.
- `yt-dlp` models manual and automatic subtitles separately and supports subtitle output formats. Its current YouTube support requires external JavaScript challenge-solving components for full support, adding runtime dependencies and maintenance burden that are not appropriate for this small app.
- Licenses checked: `yt-dlp` uses The Unlicense; `youtube-transcript-api` uses MIT. CaptionGrab does not copy their source, bundle either project, or depend on their code. The implementation below is an independent Swift client based on observed behavior and public format descriptions, not a port.

## Choices made

1. Fetch only a YouTube watch page and the selected YouTube caption URL, using the native `URLSession` stack. No API keys, account cookies, third-party service, analytics, update check, crash reporter, or extra network host is needed.
2. Read title and caption-track metadata from the page's player response. Select an English track by language code (`en` or `en-*`), preferring a creator-made track to an `asr`/auto-generated track; never substitute a machine-translated non-English track. Show the selected track type in the app.
3. Request timed caption data in JSON3 form and preserve event order, event boundaries, source timestamps, and text—including explicit line breaks. The formatters do not merge, rewrite, or proofread caption text.
4. Format output locally as Markdown or a minimal Office Open XML `.docx`. Keep recent title/URL history, export preference, and save-folder bookmark in local macOS preferences only.
5. Keep automated fixtures synthetic and hand-authored. CI must never retrieve or store a real video's transcript.
6. Treat YouTube's page schema, caption endpoints, track availability, and network controls as unstable. Explain blocked, unavailable, malformed, offline, and no-English cases rather than crashing. Do not attempt to evade age checks, rate limits, or access controls.

## Fidelity boundary

CaptionGrab preserves the text and timing events returned by the selected YouTube track. It cannot guarantee pixel-for-pixel or byte-for-byte parity with YouTube's changing transcript panel: the site does not publish a stable export contract, and the panel may group, wrap, or render caption content differently. Line wrapping caused by the panel's width is presentation, not a caption-text boundary; explicit breaks supplied by the caption data remain intact. If YouTube changes its player response or caption endpoint, fetching may need an update.

## Sources

- [YouTube Help: View video transcripts](https://support.google.com/youtube/answer/15930243)
- [youtube-transcript-api README](https://github.com/jdepoix/youtube-transcript-api/blob/master/README.md)
- [youtube-transcript-api transcript implementation](https://github.com/jdepoix/youtube-transcript-api/blob/master/youtube_transcript_api/_transcripts.py)
- [youtube-transcript-api MIT License](https://github.com/jdepoix/youtube-transcript-api/blob/master/LICENSE)
- [yt-dlp README](https://github.com/yt-dlp/yt-dlp/blob/master/README.md)
- [yt-dlp JavaScript challenge support notes](https://github.com/yt-dlp/yt-dlp/wiki/EJS)
- [yt-dlp YouTube extractor](https://github.com/yt-dlp/yt-dlp/tree/master/yt_dlp/extractor/youtube)
- [yt-dlp Unlicense](https://github.com/yt-dlp/yt-dlp/blob/master/LICENSE)
- [GitHub Actions standard runner labels and public-repository pricing](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
