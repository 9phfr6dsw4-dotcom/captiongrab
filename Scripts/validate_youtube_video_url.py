#!/usr/bin/env python3
"""Validate and canonicalize a public YouTube video URL for media capture."""

from __future__ import annotations

import os
import re
import sys
from urllib.parse import parse_qsl, urlsplit


_VIDEO_ID = re.compile(r"\A[A-Za-z0-9_-]{11}\Z")
_ALLOWED_HOSTS = {"youtube.com", "www.youtube.com", "m.youtube.com", "youtu.be"}


def normalize_youtube_url(value: str) -> str:
    """Return a canonical watch URL, rejecting non-video or non-YouTube links."""
    if not isinstance(value, str):
        raise ValueError("expected a YouTube video URL")

    value = value.strip()
    try:
        parts = urlsplit(value)
        port = parts.port
    except ValueError as exc:
        raise ValueError("expected a valid public YouTube video URL") from exc

    host = parts.hostname.lower() if parts.hostname else ""
    if (
        parts.scheme.lower() != "https"
        or host not in _ALLOWED_HOSTS
        or parts.username is not None
        or parts.password is not None
        or port is not None
        or parts.fragment
    ):
        raise ValueError("expected a public HTTPS YouTube video URL")

    video_id: str | None = None
    if host == "youtu.be":
        if parts.path.count("/") != 1 or not parts.path.startswith("/"):
            raise ValueError("expected one YouTube video ID")
        video_id = parts.path[1:]
        if parts.query:
            raise ValueError("short YouTube URLs must not contain query parameters")
    elif parts.path == "/watch":
        query = parse_qsl(parts.query, keep_blank_values=True, strict_parsing=True)
        if len(query) != 1 or query[0][0] != "v":
            raise ValueError("watch URLs must contain only one video ID")
        video_id = query[0][1]
    elif host != "m.youtube.com" and re.fullmatch(r"/shorts/[A-Za-z0-9_-]{11}", parts.path):
        video_id = parts.path.rsplit("/", 1)[-1]
    else:
        raise ValueError("expected a YouTube watch, Shorts, or short video URL")

    if not _VIDEO_ID.fullmatch(video_id or ""):
        raise ValueError("YouTube video IDs must be exactly 11 valid characters")
    return f"https://www.youtube.com/watch?v={video_id}"


def main() -> int:
    try:
        normalized = normalize_youtube_url(os.environ.get("CAPTIONGRAB_VIDEO_URL", ""))
    except ValueError as exc:
        print(f"Invalid capture input: {exc}", file=sys.stderr)
        return 2
    print(normalized)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
