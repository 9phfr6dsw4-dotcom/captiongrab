#!/usr/bin/env python3
"""Fail closed unless CaptionGrab exposes the requested nonempty transcript."""

from __future__ import annotations

import re
import sys

_VIDEO_ID = re.compile(r"\A[A-Za-z0-9_-]{11}\Z")
_TIMESTAMP = re.compile(r"(?<!\d)\d{1,2}:[0-5]\d(?!\d)")
_CAPTION_TYPE_LABELS = (
    "auto-generated english captions",
    "creator-made english captions",
    "captions shown in youtube",
)


def _compact_id(value: str) -> str:
    return "".join(character.lower() for character in value if character.isalnum())


def has_visible_transcript(accessibility_text: str, expected_video_id: str) -> bool:
    """Check accessible UI text, title, video ID, cue timestamps, and cue text."""
    if not isinstance(accessibility_text, str) or not _VIDEO_ID.fullmatch(expected_video_id):
        return False

    lines = [line.strip() for line in accessibility_text.splitlines() if line.strip()]
    normalized = "\n".join(lines).lower()
    if (
        "captiongrab" not in normalized
        or "transcript" not in normalized
        or "no transcript yet" in normalized
        or "fetching captions" in normalized
        or "paste a youtube link above to get started" in normalized
    ):
        return False

    transcript_index = next((index for index, line in enumerate(lines) if "transcript" in line.lower()), None)
    url_index = next(
        (
            index
            for index, line in enumerate(lines)
            if "youtube video url" in line.lower()
        ),
        None,
    )
    if transcript_index is None or url_index is None or transcript_index >= url_index:
        return False

    url_text = lines[url_index]
    if _compact_id(expected_video_id) not in _compact_id(url_text):
        return False

    title_lines = [
        line
        for line in lines[transcript_index + 1 : url_index]
        if len(line) >= 3 and not any(label in line.lower() for label in _CAPTION_TYPE_LABELS)
    ]
    if not title_lines or not any(any(character.isalpha() for character in line) for line in title_lines):
        return False

    cue_lines = lines[url_index + 1 :]
    cue_text = "\n".join(cue_lines)
    if len(_TIMESTAMP.findall(cue_text)) < 2:
        return False
    return any(any(character.isalpha() for character in line) for line in cue_lines)


def main() -> int:
    if len(sys.argv) != 2:
        print("Expected the selected YouTube video ID.", file=sys.stderr)
        return 2
    accessibility_text = sys.stdin.read()
    if not has_visible_transcript(accessibility_text, sys.argv[1]):
        print("CaptionGrab has not exposed the selected video's title and nonempty transcript cues.", file=sys.stderr)
        return 1
    print("Accessibility check passed: requested video title and nonempty transcript cues are visible.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
