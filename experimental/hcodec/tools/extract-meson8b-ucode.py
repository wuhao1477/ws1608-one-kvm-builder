#!/usr/bin/env python3
"""Extract raw Meson8b H.264 microcode from a GPL C word array."""

import argparse
import hashlib
import pathlib
import re
import struct
import sys


ARRAY_RE = re.compile(
    r"\bMicroCode\s*\[\s*\]\s*[^=]*=\s*\{(?P<body>.*?)\}\s*;",
    re.DOTALL,
)
WORD_RE = re.compile(r"0x[0-9a-fA-F]+|\b\d+\b")


def extract(source: str) -> bytes:
    match = ARRAY_RE.search(source)
    if not match:
        raise ValueError("MicroCode[] array was not found")

    words = [int(value, 0) for value in WORD_RE.findall(match.group("body"))]
    if not words:
        raise ValueError("MicroCode[] array is empty")
    if any(word > 0xFFFFFFFF for word in words):
        raise ValueError("MicroCode[] contains a value wider than 32 bits")

    return struct.pack(f"<{len(words)}I", *words)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("header", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    args = parser.parse_args()

    try:
        data = extract(args.header.read_text(encoding="ascii"))
    except (OSError, UnicodeDecodeError, ValueError) as error:
        print(f"extract-meson8b-ucode: {error}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(
        f"wrote {len(data)} bytes to {args.output} "
        f"sha256={hashlib.sha256(data).hexdigest()}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
