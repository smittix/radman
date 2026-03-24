#!/usr/bin/env python3
from __future__ import annotations

import struct
import sys
from pathlib import Path


ICON_TYPE_BY_NAME = [
    ("icon_16x16.png", "icp4"),
    ("icon_16x16@2x.png", "ic11"),
    ("icon_32x32.png", "icp5"),
    ("icon_32x32@2x.png", "ic12"),
    ("icon_32x32@2x.png", "icp6"),
    ("icon_128x128.png", "ic07"),
    ("icon_128x128@2x.png", "ic13"),
    ("icon_256x256.png", "ic08"),
    ("icon_256x256@2x.png", "ic14"),
    ("icon_512x512.png", "ic09"),
    ("icon_512x512@2x.png", "ic10"),
]


def build_icns(iconset_dir: Path, output_path: Path) -> None:
    chunks: list[bytes] = []

    for file_name, icon_type in ICON_TYPE_BY_NAME:
        png_path = iconset_dir / file_name
        if not png_path.exists():
            raise FileNotFoundError(f"missing icon asset: {png_path}")

        payload = png_path.read_bytes()
        chunk_size = 8 + len(payload)
        chunks.append(icon_type.encode("ascii") + struct.pack(">I", chunk_size) + payload)

    total_size = 8 + sum(len(chunk) for chunk in chunks)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(b"icns" + struct.pack(">I", total_size) + b"".join(chunks))


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("usage: build-icns.py ICONSET_DIR OUTPUT_ICNS", file=sys.stderr)
        return 1

    iconset_dir = Path(argv[1])
    output_path = Path(argv[2])
    build_icns(iconset_dir, output_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
