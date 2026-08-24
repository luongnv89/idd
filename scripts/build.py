#!/usr/bin/env python3
"""Compatibility entry point for the phase-oriented build package."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

# Direct execution adds scripts/ rather than the repository root to sys.path,
# while importlib-based parity tests add neither. Import the qualified local
# package so a preloaded third-party top-level `build` module cannot hijack this
# compatibility entry point.
_REPO_ROOT = str(Path(__file__).resolve().parent.parent)
if _REPO_ROOT not in sys.path:
    sys.path.insert(0, _REPO_ROOT)

_package = importlib.import_module("scripts.build")
_expected = Path(__file__).resolve().parent / "build" / "__init__.py"
if Path(_package.__file__).resolve() != _expected:
    raise ImportError(f"scripts.build resolved outside this checkout: {_package.__file__}")
for _name in _package.__all__:
    globals()[_name] = getattr(_package, _name)


if __name__ == "__main__":
    sys.exit(_package.main(sys.argv[1:]))
