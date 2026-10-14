#!/usr/bin/env python3
"""Fail when the publishable tree appears to contain secrets or machine identity."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path


PATTERNS = {
    "OpenAI-style secret key": re.compile(r"\bsk-(?:proj-)?[A-Za-z0-9_-]{20,}"),
    "private key material": re.compile(
        "BEGIN " + "(?:OPENSSH |RSA |EC )?" + "PRIVATE KEY"
    ),
    "Windows user-profile path": re.compile(
        r"(?i)\b[A-Z]:[\\/]+Users[\\/]+(?!example(?:[\\/]|\b))[^\\/\s]+"
    ),
    "Linux named home path": re.compile(
        r"/home/(?!example(?:/|\b)|remote-user(?:/|\b))[A-Za-z0-9._-]+"
    ),
    "RFC1918 IPv4 address": re.compile(
        r"(?<!\d)(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|"
        r"192\.168\.\d{1,3}\.\d{1,3}|"
        r"172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})(?!\d)"
    ),
    "device authorization code": re.compile(r"\b[A-Z0-9]{4}-[A-Z0-9]{5}\b"),
}

TEXT_SUFFIXES = {
    "",
    ".md",
    ".cmd",
    ".py",
    ".ps1",
    ".sh",
    ".toml",
    ".txt",
    ".yml",
    ".yaml",
    ".example",
}


def iter_text_files(root: Path):
    for path in root.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        if path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        yield path


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=Path(__file__).resolve().parents[1])
    parser.add_argument(
        "--deny",
        action="append",
        default=[],
        help="additional literal text that must not occur (repeatable)",
    )
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    denied = list(args.deny)
    denied.extend(filter(None, os.environ.get("PUBLIC_AUDIT_DENY", "").split(";")))

    findings = []
    for path in iter_text_files(root):
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        for line_number, line in enumerate(text.splitlines(), 1):
            for label, pattern in PATTERNS.items():
                if pattern.search(line):
                    findings.append((path, line_number, label))
            for literal in denied:
                if literal in line:
                    findings.append((path, line_number, "custom denied text"))

    if findings:
        for path, line_number, label in findings:
            print(f"{path.relative_to(root)}:{line_number}: {label}")
        print("Public-tree audit failed. Values are not echoed to avoid re-disclosure.")
        return 1
    print(f"Public-tree audit passed ({sum(1 for _ in iter_text_files(root))} text files).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
