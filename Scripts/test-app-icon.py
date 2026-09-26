#!/usr/bin/env python3
"""Verify CaptionGrab packages the owner-approved app icon."""

from __future__ import annotations

import argparse
import hashlib
import plistlib
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
EXPECTED_ASSETS = {
    ROOT / "Resources" / "AppIcon-1024.png": "aa8d920a5f659e4a7c7aacfed898a44be59beeba671d88dc75d496c228e68c7d",
    ROOT / "Resources" / "AppIcon-1024.svg": "aa634beb16cd48b50f73a9312fd1b9d95c17ecaab2a5afde597fc085f064ebf7",
    ROOT / "docs" / "images" / "captiongrab-icon.png": "aa8d920a5f659e4a7c7aacfed898a44be59beeba671d88dc75d496c228e68c7d",
}
ICONSET_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_dimensions(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise AssertionError(f"not a valid PNG with IHDR: {path}")
    return struct.unpack(">II", data[16:24])


def rgba_pixels(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    offset = 8
    compressed = bytearray()
    width = height = bit_depth = color_type = interlace = None
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk = data[offset + 8 : offset + 8 + length]
        if chunk_type == b"IHDR":
            width, height, bit_depth, color_type, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
        elif chunk_type == b"IDAT":
            compressed.extend(chunk)
        elif chunk_type == b"IEND":
            break
        offset += length + 12
    if (bit_depth, color_type, interlace) != (8, 6, 0):
        raise AssertionError(f"expected non-interlaced 8-bit RGBA PNG: {path}")
    assert width is not None and height is not None
    stride = width * 4
    decoded = zlib.decompress(compressed)
    if len(decoded) != height * (stride + 1):
        raise AssertionError(f"unexpected decoded PNG length: {path}")

    previous = bytearray(stride)
    pixels = bytearray()
    cursor = 0
    for _ in range(height):
        filter_type = decoded[cursor]
        cursor += 1
        filtered = decoded[cursor : cursor + stride]
        cursor += stride
        row = bytearray(stride)
        for index, value in enumerate(filtered):
            left = row[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            elif filter_type == 4:
                estimate = left + above - upper_left
                distances = (abs(estimate - left), abs(estimate - above), abs(estimate - upper_left))
                predictor = (left, above, upper_left)[distances.index(min(distances))]
            else:
                raise AssertionError(f"unsupported PNG filter {filter_type}: {path}")
            row[index] = (value + predictor) & 0xFF
        pixels.extend(row)
        previous = row
    return width, height, bytes(pixels)


def validate_icns(path: Path) -> None:
    data = path.read_bytes()
    if len(data) < 16 or data[:4] != b"icns":
        raise AssertionError(f"missing or invalid ICNS file: {path}")
    if struct.unpack(">I", data[4:8])[0] != len(data):
        raise AssertionError(f"ICNS declared length does not match file size: {path}")
    offset = 8
    while offset < len(data):
        if offset + 8 > len(data):
            raise AssertionError(f"truncated ICNS chunk header: {path}")
        chunk_length = struct.unpack(">I", data[offset + 4 : offset + 8])[0]
        if chunk_length < 8 or offset + chunk_length > len(data):
            raise AssertionError(f"invalid ICNS chunk length at byte {offset}: {path}")
        offset += chunk_length
    if offset != len(data):
        raise AssertionError(f"ICNS chunks do not end at file boundary: {path}")


def check(app: Path, preview: Path | None) -> None:
    for path, expected_hash in EXPECTED_ASSETS.items():
        if not path.is_file():
            raise AssertionError(f"approved icon asset is missing: {path}")
        actual_hash = sha256(path)
        if actual_hash != expected_hash:
            raise AssertionError(f"approved icon asset changed: {path} ({actual_hash})")

    source_png = ROOT / "Resources" / "AppIcon-1024.png"
    if png_dimensions(source_png) != (1024, 1024):
        raise AssertionError("approved app icon source must be 1024 x 1024 pixels")
    source_pixels = rgba_pixels(source_png)

    info_path = app / "Contents" / "Info.plist"
    with info_path.open("rb") as info_file:
        info = plistlib.load(info_file)
    if info.get("CFBundleIconFile") != "AppIcon":
        raise AssertionError("Info.plist must point to AppIcon.icns")

    icns = app / "Contents" / "Resources" / "AppIcon.icns"
    validate_icns(icns)

    with tempfile.TemporaryDirectory(prefix="captiongrab-iconset-") as temp_dir:
        iconset = Path(temp_dir) / "AppIcon.iconset"
        subprocess.run(
            ["iconutil", "-c", "iconset", str(icns), "-o", str(iconset)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for filename, dimension in ICONSET_SIZES.items():
            image = iconset / filename
            if not image.is_file():
                raise AssertionError(f"packaged icon is missing rendition: {filename}")
            if png_dimensions(image) != (dimension, dimension):
                raise AssertionError(f"packaged icon rendition has wrong dimensions: {filename}")
        packaged_pixels = rgba_pixels(iconset / "icon_512x512@2x.png")
        if packaged_pixels != source_pixels:
            raise AssertionError("packaged 1024px icon pixels differ from the approved PNG")
        if preview is not None:
            preview.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(iconset / "icon_512x512@2x.png", preview)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path, help="CaptionGrab.app bundle to inspect")
    parser.add_argument("--preview", type=Path, help="write the extracted 1024px app icon PNG")
    args = parser.parse_args()
    check(args.app, args.preview)
    print(f"Verified approved CaptionGrab icon in {args.app}")
    if args.preview:
        print(f"Wrote extracted app icon preview to {args.preview}")


if __name__ == "__main__":
    main()
