#!/usr/bin/env python3
"""Shared subprocess boundary for GitHub CLI calls.

The public shared scripts remain standalone entry points, but the build bundles
this module beside every consumer so their ``gh`` process/error contract has one
implementation. Callers retain ownership of command-specific exit handling and
JSON shape validation.
"""

from __future__ import annotations

import argparse
import subprocess
from collections.abc import Sequence
from typing import TypeVar

_Unavailable = TypeVar("_Unavailable", bound=Exception)


def run_gh(
    args: Sequence[str], unavailable: type[_Unavailable]
) -> subprocess.CompletedProcess[str]:
    """Run ``gh`` without a shell and translate process-start failures."""
    try:
        return subprocess.run(
            ["gh", *args], capture_output=True, text=True, check=False
        )
    except FileNotFoundError as exc:
        raise unavailable("gh is not installed or not on PATH") from exc
    except OSError as exc:
        raise unavailable(f"cannot run gh — {exc}") from exc


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="gi-gh.py",
        description="Shared import-only GitHub CLI subprocess boundary.",
    )
    parser.parse_args(argv)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
