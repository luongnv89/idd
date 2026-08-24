#!/usr/bin/env python3
"""Run the build package with ``python -m scripts.build``."""

from __future__ import annotations

import sys

from .cli import main


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
