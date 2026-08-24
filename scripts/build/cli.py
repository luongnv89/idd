#!/usr/bin/env python3
"""Command-line interface for the IDD distribution build."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .common import BuildError
from .pipeline import build


def _check_python_version() -> None:
    if sys.version_info < (3, 11):
        sys.exit(f"build.py requires Python 3.11+ (running {sys.version.split()[0]})")


def main(argv: list[str]) -> int:
    _check_python_version()
    parser = argparse.ArgumentParser(
        description="Build IDD distribution outputs (skills/, dist/skills/, and dist/agents/)."
    )
    parser.add_argument(
        "--out",
        default="dist",
        help="Output root directory (default: dist).",
    )
    parser.add_argument(
        "--src",
        default="src",
        help="Source root directory (default: src).",
    )
    parser.add_argument(
        "--no-root-skills",
        action="store_true",
        help="Do not copy output into repo-root skills/ (use ./scripts/build.sh for verify-then-promote).",
    )
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)
    out = Path(args.out).resolve()
    src = Path(args.src).resolve()
    if not src.is_dir():
        print(f"✗ src not found: {src}", file=sys.stderr)
        return 1
    try:
        build(out, src, verbose=args.verbose, no_root_skills=args.no_root_skills)
    except BuildError:
        return 1
    return 0
