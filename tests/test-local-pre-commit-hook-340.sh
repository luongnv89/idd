#!/usr/bin/env bash
# Behavioral contract for the installable local pre-commit security hook (#340).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() {
  local description="$1"
  shift
  if "$@"; then pass "$description"; else fail "$description"; fi
}

echo "◆ Local Pre-Commit Hook (issue #340)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

fixture="$TMP/repo with spaces"
outside="$TMP/outside"
mkdir -p "$fixture/.githooks" "$fixture/scripts" \
  "$fixture/src/shared/scripts" "$fixture/nested/dir" "$outside" \
  "$TMP/home" "$TMP/xdg"
cp "$REPO_ROOT/.githooks/pre-commit" "$fixture/.githooks/pre-commit"
cp "$REPO_ROOT/scripts/install-hooks.sh" "$fixture/scripts/install-hooks.sh"
cp "$REPO_ROOT/src/shared/scripts/gi-secscan.py" \
  "$fixture/src/shared/scripts/gi-secscan.py"
chmod 0644 "$fixture/.githooks/pre-commit"

export HOME="$TMP/home"
export XDG_CONFIG_HOME="$TMP/xdg"
export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$TMP/global.gitconfig"
: > "$GIT_CONFIG_GLOBAL"

git -C "$fixture" init -q
git -C "$fixture" symbolic-ref HEAD refs/heads/feature/hook-test
git -C "$fixture" config user.name "Hook Test"
git -C "$fixture" config user.email "hook-test@example.invalid"
git -C "$fixture" config commit.gpgsign false

install_output="$(cd "$outside" && sh "$fixture/scripts/install-hooks.sh")"
check "documented installer works outside the repository" \
  test "$install_output" = "✓ Local pre-commit hook installed (.githooks/pre-commit)"
check "installer sets the worktree-specific hooks path" \
  test "$(git -C "$fixture" config --worktree --get core.hooksPath)" = ".githooks"
if git -C "$fixture" config --local --get core.hooksPath >/dev/null 2>&1; then
  fail "installer leaves the shared hooks path unset"
else
  pass "installer leaves the shared hooks path unset"
fi
check "installer restores the hook executable bit" \
  test -x "$fixture/.githooks/pre-commit"
if sh "$fixture/scripts/install-hooks.sh" >/dev/null; then
  pass "installer is idempotent"
else
  fail "installer is idempotent"
fi

multi="$TMP/multi"
sibling="$TMP/sibling"
mkdir -p "$multi/.githooks" "$multi/scripts" "$multi/src/shared/scripts"
cp "$REPO_ROOT/.githooks/pre-commit" "$multi/.githooks/pre-commit"
cp "$REPO_ROOT/scripts/install-hooks.sh" "$multi/scripts/install-hooks.sh"
cp "$REPO_ROOT/src/shared/scripts/gi-secscan.py" \
  "$multi/src/shared/scripts/gi-secscan.py"
git -C "$multi" init -q
git -C "$multi" config user.name "Hook Test"
git -C "$multi" config user.email "hook-test@example.invalid"
git -C "$multi" config commit.gpgsign false
git -C "$multi" add .
git -C "$multi" commit -q -m "test: initialize linked worktrees"
git -C "$multi" worktree add -q -b sibling "$sibling"
sh "$multi/scripts/install-hooks.sh" >/dev/null
check "installing one linked worktree does not configure its sibling" \
  test -z "$(git -C "$sibling" config --get core.hooksPath 2>/dev/null || true)"
printf '%s\n' '#!/bin/sh' 'touch sibling-hook-ran' 'exit 1' \
  > "$sibling/.githooks/pre-commit"
printf '%s\n' "safe sibling" > "$sibling/safe-sibling.txt"
git -C "$sibling" add safe-sibling.txt
if (cd "$sibling" && git commit -q -m "test: sibling stays unconfigured"); then
  pass "installing one linked worktree does not execute its sibling hook"
else
  fail "installing one linked worktree does not execute its sibling hook"
fi
check "unconfigured sibling hook did not run" \
  test ! -e "$sibling/sibling-hook-ran"

printf '%s\n' "safe fixture" > "$fixture/safe.txt"
git -C "$fixture" add safe.txt
if (cd "$fixture/nested/dir" && git commit -q -m "test: benign commit") \
  >"$TMP/benign.out" 2>"$TMP/benign.err"; then
  pass "a benign commit succeeds from a nested directory"
else
  fail "a benign commit succeeds from a nested directory"
fi

# Assemble a documented canary at runtime so no live-key-shaped value is stored
# in this test file (the repository's own pre-push scanner reads this source).
canary="AKIA""IOSFODNN7EXAMPLE"
printf 'token=%s\n' "$canary" > "$fixture/canary.txt"
git -C "$fixture" add canary.txt

set +e
(
  cd "$fixture"
  python3 src/shared/scripts/gi-secscan.py --staged
) >"$TMP/direct.out" 2>"$TMP/direct.err"
direct_status=$?
(
  cd "$fixture/nested/dir"
  "$fixture/.githooks/pre-commit"
) >"$TMP/hook.out" 2>"$TMP/hook.err"
hook_status=$?
set -e

check "direct scanner blocks the staged canary" test "$direct_status" -eq 1
check "hook propagates the scanner's blocking exit" test "$hook_status" -eq 1
check "hook preserves scanner stdout verbatim" cmp -s "$TMP/direct.out" "$TMP/hook.out"
check "hook preserves scanner stderr verbatim" cmp -s "$TMP/direct.err" "$TMP/hook.err"
check "hook surfaces the scanner's blocked-commit message" \
  grep -q "Pre-commit security scan blocked the commit" "$TMP/hook.err"

head_before="$(git -C "$fixture" rev-parse HEAD)"
set +e
(cd "$fixture/nested/dir" && git commit -q -m "test: reject canary") \
  >"$TMP/commit.out" 2>"$TMP/commit.err"
commit_status=$?
set -e
check "commit containing the staged canary is blocked" test "$commit_status" -ne 0
check "blocked commit leaves HEAD unchanged" \
  test "$(git -C "$fixture" rev-parse HEAD)" = "$head_before"
check "blocked commit prints the scanner's message" \
  grep -q "Pre-commit security scan blocked the commit" "$TMP/commit.err"

mv "$fixture/src/shared/scripts/gi-secscan.py" \
  "$fixture/src/shared/scripts/gi-secscan.py.missing"
set +e
(cd "$fixture" && .githooks/pre-commit) >"$TMP/missing.out" 2>"$TMP/missing.err"
missing_status=$?
set -e
check "missing scanner fails closed" test "$missing_status" -ne 0
check "missing scanner names the infrastructure failure" \
  grep -q "scanner not found" "$TMP/missing.err"
mv "$fixture/src/shared/scripts/gi-secscan.py.missing" \
  "$fixture/src/shared/scripts/gi-secscan.py"

printf '%s\n' 'security:' '  allow_pattern: "["' > "$fixture/.gitissue.yml"
set +e
(cd "$fixture" && .githooks/pre-commit) >"$TMP/config.out" 2>"$TMP/config.err"
config_status=$?
set -e
check "invalid scanner policy fails closed with exit 3" test "$config_status" -eq 3
check "invalid policy preserves the scanner diagnostic" \
  grep -q "security.allow_pattern is not a valid regex" "$TMP/config.err"
rm "$fixture/.gitissue.yml"

mkdir -p "$fixture/custom-hooks"
git -C "$fixture" config --worktree --unset core.hooksPath
git config --global core.hooksPath custom-hooks
set +e
sh "$fixture/scripts/install-hooks.sh" >"$TMP/conflict.out" 2>"$TMP/conflict.err"
conflict_status=$?
set -e
check "installer refuses to mask another effective hooks path" \
  test "$conflict_status" -ne 0
check "conflicting global hooks path remains effective" \
  test "$(git -C "$fixture" config --get core.hooksPath)" = "custom-hooks"
if git -C "$fixture" config --local --get core.hooksPath >/dev/null 2>&1; then
  fail "refused installation leaves local core.hooksPath unset"
else
  pass "refused installation leaves local core.hooksPath unset"
fi

check "CONTRIBUTING documents the exact one-command installer" \
  grep -q '^bash scripts/install-hooks\.sh$' "$REPO_ROOT/CONTRIBUTING.md"

printf '\n  %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
