#!/usr/bin/env bash
# test-build-script.sh — Validate scripts/build.sh produces expected outputs
# (issue #58, §9 of refactor-plan-v10.md; updated for #106).
#
# Asserts:
#   - All public skills (src/skills/<name>/) appear in root skills/<name>/
#   - Every shared source agent is emitted as a standalone Claude Code agent
#   - Internal skills (src/internal-skills/) and deprecated skills
#     (src/deprecated-skills/) without a distribute flag are excluded.
#   - Every shared script (src/shared/scripts/) ships into at least one skill,
#     byte-identically, executable, and runnable (issue #251).
#   - Every tests/*.sh is invoked by a GitHub Actions workflow, or is listed in
#     this file's EXCLUDED array with a written reason (T9, issue #275).
#
# T9 lives here, in an already-wired test, on purpose: a standalone
# tests/test-ci-wiring.sh would itself need wiring, which is the failure mode it
# exists to catch.
#
# Usage: bash tests/test-build-script.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"
SRC_SKILLS="$REPO_ROOT/src/skills"
SRC_AGENTS="$REPO_ROOT/src/shared/agents"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
ROOT_SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

# Portable mode read: GNU `stat -c` and BSD `stat -f` disagree, python3 does not.
mode_of() {
  python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

echo "◆ Build Script Tests (issue #58)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: build.sh exists and is executable
# ───────────────────────────────────────────────────────────
if [ -x "$BUILD_SH" ]; then
  pass "T1: scripts/build.sh exists and is executable"
else
  fail "T1: scripts/build.sh missing or not executable"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# ───────────────────────────────────────────────────────────
# T2: build runs cleanly into a temp out dir
# ───────────────────────────────────────────────────────────
TMP_OUT="$(mktemp -d)"
trap 'rm -rf "$TMP_OUT"' EXIT
if "$BUILD_SH" --out "$TMP_OUT" >/dev/null 2>&1; then
  pass "T2: build.sh --out <tmp> exits 0"
else
  fail "T2: build.sh --out <tmp> failed"
  echo "  Build aborted — cannot continue."
  exit 1
fi

# Also build into the canonical dist/ for the rest of the tests
if "$BUILD_SH" >/dev/null 2>&1; then
  pass "T2.1: build.sh (default out=dist/) exits 0"
else
  fail "T2.1: build.sh failed against default out"
fi

# ───────────────────────────────────────────────────────────
# T3: every public src skill is present in root skills/
# ───────────────────────────────────────────────────────────
for src_skill_dir in "$SRC_SKILLS"/*/; do
  name="$(basename "$src_skill_dir")"
  if [ -f "$ROOT_SKILLS/$name/SKILL.md" ]; then
    pass "T3: skills/$name/SKILL.md present"
  else
    fail "T3: skills/$name/SKILL.md missing"
  fi
done

# ───────────────────────────────────────────────────────────
# T5: every shared source agent is emitted as a standalone Claude Code agent
#      in the built dist/agents/ (agent outputs are gitignored, not committed)
# ───────────────────────────────────────────────────────────
TMP_AGENTS="$(mktemp -d)"
"$BUILD_SH" --out "$TMP_AGENTS" >/dev/null 2>&1
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  stem="${name%.md}"
  dist_agent="$TMP_AGENTS/agents/$name"
  if [ -f "$dist_agent" ] && \
     grep -q "^name: $stem$" "$dist_agent" && \
     grep -q '^description: ' "$dist_agent" && \
     grep -q 'Managed by IDD installer' "$dist_agent"; then
    pass "T5: dist/agents/$name generated with Claude Code frontmatter"
  else
    fail "T5: dist/agents/$name missing or malformed"
  fi
done
rm -rf "$TMP_AGENTS"

# ───────────────────────────────────────────────────────────
# T5b: every shared source agent is emitted for pi-subagents in .pi/agents/
# ───────────────────────────────────────────────────────────
PI_AGENTS="$REPO_ROOT/.pi/agents"
for src_agent in "$SRC_AGENTS"/*.md; do
  [ -f "$src_agent" ] || continue
  name="$(basename "$src_agent")"
  pi_agent="$PI_AGENTS/$name"
  if [ -f "$pi_agent" ] && \
     grep -q '^display_name: ' "$pi_agent" && \
     grep -q 'Managed by IDD installer (pi-subagents)' "$pi_agent" && \
     ! grep -q 'display_name:.*—' "$pi_agent" && \
     ! grep -q 'display_name:.*\\u2014' "$pi_agent"; then
    pass "T5b: .pi/agents/$name generated (role-only display_name)"
  else
    fail "T5b: .pi/agents/$name missing or still has persona display_name"
  fi
done

# ───────────────────────────────────────────────────────────
# T6: internal-skills excluded from generated outputs
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/internal-skills" ]; then
  for internal_dir in "$REPO_ROOT/src/internal-skills"/*/; do
    [ -d "$internal_dir" ] || continue
    name="$(basename "$internal_dir")"
    if [ ! -d "$ROOT_SKILLS/$name" ]; then
      pass "T6: internal skill '$name' correctly excluded from generated outputs"
    else
      fail "T6: internal skill '$name' leaked into generated outputs"
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# T7: deprecated-skills without distribute flag excluded
# ───────────────────────────────────────────────────────────
if [ -d "$REPO_ROOT/src/deprecated-skills" ]; then
  for dep_dir in "$REPO_ROOT/src/deprecated-skills"/*/; do
    [ -d "$dep_dir" ] || continue
    name="$(basename "$dep_dir")"
    skill_md="$dep_dir/SKILL.md"
    distribute_flag=""
    if [ -f "$skill_md" ]; then
      # Look for "distribute:" in YAML frontmatter (first 30 lines).
      distribute_flag="$(head -30 "$skill_md" | grep -E '^distribute:' || true)"
    fi
    if [ -z "$distribute_flag" ]; then
      if [ ! -d "$ROOT_SKILLS/$name" ]; then
        pass "T7: deprecated skill '$name' (no distribute flag) excluded"
      else
        fail "T7: deprecated skill '$name' leaked into generated outputs without distribute flag"
      fi
    fi
  done
fi

# ───────────────────────────────────────────────────────────
# T8: every shared script ships into at least one skill, unchanged and runnable
# (issue #251). The build copies these with copy2 rather than copyfile — a
# regression to copyfile drops the mode to a umask-dependent 0644 and the
# shipped script silently stops being executable.
# ───────────────────────────────────────────────────────────
script_count=0
for src_script in "$SRC_SCRIPTS"/*.py; do
  [ -f "$src_script" ] || continue
  script_count=$((script_count + 1))
  name="$(basename "$src_script")"

  copies=0
  while IFS= read -r shipped; do
    copies=$((copies + 1))
    rel="${shipped#"$REPO_ROOT/"}"
    if cmp -s "$src_script" "$shipped"; then
      pass "T8: $rel is byte-identical to src/shared/scripts/$name"
    else
      fail "T8: $rel differs from src/shared/scripts/$name"
    fi
    # Never assert an absolute mode here: git records only the exec bit, so a
    # fresh checkout materialises a 100755 blob as 0777 & ~umask — 0o775 under
    # the common umask 002, 0o755 under 022. Compare the shipped copy to its
    # source instead; that is what catches a copy2 → copyfile regression, and it
    # holds under every umask.
    shipped_mode="$(mode_of "$shipped")"
    src_mode="$(mode_of "$src_script")"
    if [ "$shipped_mode" = "$src_mode" ]; then
      pass "T8: $rel has the source's mode ($shipped_mode)"
    else
      fail "T8: $rel is mode $shipped_mode, source is $src_mode"
    fi
    if [ -x "$shipped" ]; then
      pass "T8: $rel is executable"
    else
      fail "T8: $rel is not executable"
    fi
    set +e
    python3 "$shipped" --help >/dev/null 2>&1
    help_rc=$?
    set -e
    if [ "$help_rc" -eq 0 ]; then
      pass "T8: $rel --help exits 0"
    else
      fail "T8: $rel --help exited $help_rc"
    fi
  done < <(find "$ROOT_SKILLS" -type f -path '*/references/scripts/*' -name "$name" | sort)

  if [ "$copies" -gt 0 ]; then
    pass "T8: src/shared/scripts/$name ships into $copies skill(s)"
  else
    fail "T8: src/shared/scripts/$name ships into no skill — nothing cites it"
  fi
done

if [ "$script_count" -gt 0 ]; then
  pass "T8: src/shared/scripts/ holds $script_count script(s) to verify"
else
  fail "T8: src/shared/scripts/ is empty — T8 would pass vacuously"
fi

# ───────────────────────────────────────────────────────────
# T9: every tests/*.sh is invoked by a workflow (issue #275)
#
# A test nobody runs is not a test. Issue #275 found 20 of 42 test files that no
# workflow ever invoked — including the pre-commit security lint. Nothing
# asserted the wiring, so the gap grew silently, one unwired file at a time.
#
# To add a test: create tests/test-<name>.sh and add a named step for it in
# .github/workflows/dist-check.yml — before the build if it reads only src/ and
# docs/, after the build if it reads dist/ or skills/.
#
# To deliberately keep a test out of CI: add it to EXCLUDED below WITH a reason.
# The reason is the whole point of the array — an exclusion nobody can justify
# is indistinguishable from the rot this check exists to prevent.
# ───────────────────────────────────────────────────────────
WORKFLOW_DIR="$REPO_ROOT/.github/workflows"

# Format: "<basename>|<reason>". Empty today — every tests/*.sh runs in CI.
EXCLUDED=(
  # "test-example.sh|needs a live GitHub token; run locally with GH_TOKEN set"
)

excluded_reason() {
  local want="$1" entry
  if [ "${#EXCLUDED[@]}" -eq 0 ]; then
    return 1
  fi
  for entry in "${EXCLUDED[@]}"; do
    if [ "${entry%%|*}" = "$want" ]; then
      printf '%s' "${entry#*|}"
      return 0
    fi
  done
  return 1
}

TEST_FILES=()
while IFS= read -r tracked; do
  TEST_FILES+=("$tracked")
done < <(cd "$REPO_ROOT" && git ls-files 'tests/*.sh')

# Scan every workflow, not just dist-check.yml: a test wired from any of them is
# wired. `grep -rho … || true` because grep exits 1 on no match under `set -e`.
WIRED=""
if [ -d "$WORKFLOW_DIR" ]; then
  WIRED="$(grep -rhoE 'tests/[A-Za-z0-9._-]+\.sh' "$WORKFLOW_DIR" | sort -u || true)"
fi

if [ "${#TEST_FILES[@]}" -eq 0 ]; then
  fail "T9: git tracks no tests/*.sh — the wiring check would be vacuous"
elif [ -z "$WIRED" ]; then
  fail "T9: no workflow under .github/workflows/ invokes any tests/*.sh"
else
  wired_count="$(printf '%s\n' "$WIRED" | wc -l | tr -d ' ')"
  pass "T9.0: checking ${#TEST_FILES[@]} tracked test(s) against $wired_count workflow reference(s)"

  unwired=0
  for rel in "${TEST_FILES[@]}"; do
    base="$(basename "$rel")"
    if printf '%s\n' "$WIRED" | grep -qxF "tests/$base"; then
      continue
    fi
    if reason="$(excluded_reason "$base")" && [ -n "$reason" ]; then
      pass "T9: $base excluded from CI — $reason"
    else
      unwired=$((unwired + 1))
      fail "T9: $base is not invoked by any workflow and has no EXCLUDED reason"
    fi
  done

  if [ "$unwired" -eq 0 ]; then
    pass "T9: every tests/*.sh is invoked by a workflow or excluded with a reason"
  else
    echo "      Add a step to .github/workflows/dist-check.yml, or add the file"
    echo "      to EXCLUDED in tests/test-build-script.sh with a written reason."
  fi

  # A stale exclusion outlives the test it names and would silently excuse a
  # future file that reuses the name.
  if [ "${#EXCLUDED[@]}" -gt 0 ]; then
    for entry in "${EXCLUDED[@]}"; do
      name="${entry%%|*}"
      if [ -f "$REPO_ROOT/tests/$name" ]; then
        pass "T9: EXCLUDED entry '$name' names an existing test"
      else
        fail "T9: EXCLUDED entry '$name' names no tests/$name — stale exclusion"
      fi
    done
  fi
fi

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Build script tests failed"
  exit 1
fi

echo "  ✓ Build script tests pass"
exit 0
