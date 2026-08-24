#!/usr/bin/env python3
"""Compatibility entry point for the phase-oriented build package."""

from __future__ import annotations

import hashlib
import importlib.util
import sys
from pathlib import Path

# Load the adjacent package by exact path under a private name. Importing
# `scripts.build` by name is unsafe because scripts/ is a namespace package: a
# regular third-party `scripts` package later on sys.path wins resolution, and
# its code runs before an origin check can reject it.
_package_dir = Path(__file__).resolve().parent / "build"
_package_init = _package_dir / "__init__.py"
_package_name = "_idd_build_" + hashlib.sha256(
    str(_package_dir).encode("utf-8")
).hexdigest()[:16]
_spec = importlib.util.spec_from_file_location(
    _package_name,
    _package_init,
    submodule_search_locations=[str(_package_dir)],
)
if _spec is None or _spec.loader is None:
    raise ImportError(f"cannot load local build package: {_package_init}")
_package = importlib.util.module_from_spec(_spec)
sys.modules[_package_name] = _package
try:
    _spec.loader.exec_module(_package)
except BaseException:
    sys.modules.pop(_package_name, None)
    raise
for _name in _package.__all__:
    globals()[_name] = getattr(_package, _name)


if __name__ == "__main__":
    sys.exit(_package.main(sys.argv[1:]))
