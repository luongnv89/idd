#!/usr/bin/env bash
# build.sh — stable entrypoint that calls scripts/build.py.
#
# Usage:
#   ./scripts/build.sh                 # writes dist/
#   ./scripts/build.sh --out /tmp/a    # writes /tmp/a/{skills,plugin}/
#   ./scripts/build.sh -v              # verbose output
#
# Per refactor-plan-v10.md §4: production build is byte-deterministic.
# Identical src/ + build.py produces identical dist/ on any machine.

set -eu

ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
exec python3 "$ROOT/scripts/build.py" "$@"
