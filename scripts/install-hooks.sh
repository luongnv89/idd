#!/bin/sh
# Install this repository's tracked Git hooks into the local checkout.
set -eu

fail() {
  printf '%s\n' "✗ Hook installation failed — $1" >&2
  exit 1
}

command -v git >/dev/null 2>&1 || fail "git is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required by the pre-commit hook"

script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)" || \
  fail "cannot resolve the installer directory"
repo_root="$(git -C "$script_dir/.." rev-parse --show-toplevel 2>/dev/null)" || \
  fail "the installer is not inside a Git working tree"
hook="$repo_root/.githooks/pre-commit"
scanner="$repo_root/src/shared/scripts/gi-secscan.py"

[ -f "$hook" ] || fail "missing .githooks/pre-commit"
[ -f "$scanner" ] || fail "missing src/shared/scripts/gi-secscan.py"

set +e
existing="$(git -C "$repo_root" config --local --get core.hooksPath 2>/dev/null)"
config_status=$?
set -e
if [ "$config_status" -eq 0 ] && [ "$existing" != ".githooks" ]; then
  fail "core.hooksPath is already '$existing'; unset it before installing"
fi
if [ "$config_status" -ne 0 ] && [ "$config_status" -ne 1 ]; then
  fail "cannot read the local core.hooksPath setting"
fi

# Archive downloads may drop executable bits. Repair the hook before enabling it.
chmod +x "$hook" || fail "cannot make .githooks/pre-commit executable"
git -C "$repo_root" config --local core.hooksPath .githooks || \
  fail "cannot set the local core.hooksPath"

printf '%s\n' "✓ Local pre-commit hook installed (.githooks/pre-commit)"
