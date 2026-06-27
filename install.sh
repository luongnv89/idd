#!/usr/bin/env bash
# install.sh — curl-friendly entrypoint for IDD skill installation.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/luongnv89/idd/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --tools all
#
# After git clone, ./install.sh delegates to scripts/install.sh in the repo.
# For curl | bash (only this file on disk), fetches scripts/install.sh from GitHub.

set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]:-}"
IDD_RAW_BASE="${IDD_INSTALL_RAW:-https://raw.githubusercontent.com/luongnv89/idd/main}"

case "$SCRIPT_PATH" in
  ""|-|/dev/stdin|/dev/fd/*|/proc/*/fd/*) ;;
  *)
    if [ -f "$SCRIPT_PATH" ]; then
      HERE="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
      if [ -f "$HERE/scripts/install.sh" ]; then
        exec bash "$HERE/scripts/install.sh" "$@"
      fi
    fi
    ;;
esac

TMP_INSTALLER="$(mktemp)"
trap 'rm -f "$TMP_INSTALLER"' EXIT
if ! curl -fsSL "$IDD_RAW_BASE/scripts/install.sh" -o "$TMP_INSTALLER"; then
  echo "✗ Could not download $IDD_RAW_BASE/scripts/install.sh" >&2
  exit 1
fi
exec bash "$TMP_INSTALLER" "$@"