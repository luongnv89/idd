#!/usr/bin/env bash
# test-skill-frontmatter-keys-307.sh — Enforce the skill-creator SKILL.md
# frontmatter key set (issue #307)
#
# Background: all seven built skills used to carry a top-level `effort:` key,
# which made every one of them fail skill-creator's `quick_validate.py`:
#
#   Unexpected key(s) in SKILL.md frontmatter: effort.
#   Allowed properties are: allowed-tools, compatibility, description,
#                           license, metadata, name
#
# #307 resolved that by moving the value under the already-allowed `metadata:`
# mapping (`metadata.effort`), which the validator permits — it subtracts only
# *top-level* keys from its allowed set and never inspects nested ones. This
# test keeps that true: it is the thing that would notice if a new top-level key
# appeared, or if the standard's allowed set changed again.
#
# ALLOWED_KEYS below mirrors ALLOWED_PROPERTIES in skill-creator's
# scripts/quick_validate.py. The check is reimplemented here rather than
# shelled out to, because that validator ships in a marketplace plugin that CI
# does not install — a test that silently skips is worse than no test.
#
# Acceptance criteria:
#  - Every built skills/<name>/SKILL.md uses only allowed top-level keys
#  - Every SKILL.source.md does too, including src/internal-skills/idd-doctor,
#    which is source-only and never built
#  - The effort value survived the move: metadata.effort is present and in the
#    known vocabulary
#  - No top-level `effort:` key returns anywhere
#
# Usage: bash tests/test-skill-frontmatter-keys-307.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

# Mirrors ALLOWED_PROPERTIES in skill-creator's quick_validate.py.
ALLOWED_KEYS="allowed-tools compatibility description license metadata name"

# The harness reasoning-effort vocabulary. Values are per-skill; this pins the
# spelling, not the choice.
EFFORT_VOCAB="low medium high xhigh max"

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ SKILL.md Frontmatter Key Tests (issue #307)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# Print one top-level frontmatter key per line. A top-level key is a line
# between the opening and closing `---` that starts at column 0.
frontmatter_keys() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^[A-Za-z_][A-Za-z0-9_-]*:/ { sub(/:.*$/, ""); print }
  ' "$1"
}

# Print the value of `metadata.<key>`, or nothing if absent. Reads only the
# indented block that directly follows a column-0 `metadata:` line.
#
# Bounded to the frontmatter with the same three lines frontmatter_keys() uses:
# line 1 must be the opening fence, and the next column-0 `---` closes the
# block. Kept structurally identical on purpose — SKILL.md bodies are full of
# `---` horizontal rules and column-0 `key:` lines, so a read that ran past the
# closing fence would answer from the body and look like a normal verdict. T5
# holds that bound for both functions.
metadata_value() {
  awk -v want="$2" '
    NR == 1 && $0 != "---" { exit }
    NR == 1 { next }
    $0 == "---" { exit }
    /^metadata:[[:space:]]*$/ { inmeta = 1; next }
    inmeta && /^[^[:space:]]/ { inmeta = 0 }
    inmeta && $0 ~ "^[[:space:]]+" want ":" {
      sub("^[[:space:]]+" want ":[[:space:]]*", "")
      print; exit
    }
  ' "$1"
}

is_allowed() {
  local key="$1" allowed
  for allowed in $ALLOWED_KEYS; do
    [ "$key" = "$allowed" ] && return 0
  done
  return 1
}

in_vocab() {
  local val="$1" known
  for known in $EFFORT_VOCAB; do
    [ "$val" = "$known" ] && return 0
  done
  return 1
}

# Assert one SKILL file's key set. $1 = label, $2 = path.
check_key_set() {
  local label="$1" file="$2" keys unexpected=""

  keys="$(frontmatter_keys "$file")"
  if [ -z "$keys" ]; then
    fail "$label: no top-level frontmatter keys found — malformed or missing frontmatter"
    return
  fi

  local key
  while IFS= read -r key; do
    [ -n "$key" ] || continue
    is_allowed "$key" || unexpected="$unexpected $key"
  done <<EOF
$keys
EOF

  if [ -n "$unexpected" ]; then
    fail "$label: unexpected top-level key(s):$unexpected — allowed are: $ALLOWED_KEYS (move the value under 'metadata:' instead)"
    return
  fi

  # quick_validate.py's other hard requirement: name and description exist.
  local missing=""
  echo "$keys" | grep -qx "name" || missing="$missing name"
  echo "$keys" | grep -qx "description" || missing="$missing description"
  if [ -n "$missing" ]; then
    fail "$label: missing required frontmatter key(s):$missing"
    return
  fi

  pass "$label: frontmatter key set conforms to the skill-creator standard"
}

# Assert metadata.effort survived and is spelled correctly. $1 = label, $2 = path.
check_effort() {
  local label="$1" file="$2" val
  val="$(metadata_value "$file" effort)"

  if [ -z "$val" ]; then
    fail "$label: metadata.effort is missing — #307 moved it there from the top level; do not drop it"
    return
  fi
  if ! in_vocab "$val"; then
    fail "$label: metadata.effort is '$val', not one of: $EFFORT_VOCAB"
    return
  fi
  pass "$label: metadata.effort = $val"
}

# ── T1: every built SKILL.md ──────────────────────────────────────────────────
shopt -s nullglob
built_any=0
for skill_md in "$REPO_ROOT"/skills/*/SKILL.md; do
  built_any=1
  name="$(basename "$(dirname "$skill_md")")"
  check_key_set "T1: skills/$name/SKILL.md" "$skill_md"
done

if [ "$built_any" -eq 0 ]; then
  fail "T1: no built skills/*/SKILL.md found — run ./scripts/build.sh first"
fi

# ── T2: every source the build compiles from ──────────────────────────────────
# idd-doctor is internal and source-only — it has no built SKILL.md, so this is
# the only place its frontmatter is ever checked.
source_any=0
saw_doctor=0
for source_md in "$REPO_ROOT"/src/skills/*/SKILL.source.md \
                 "$REPO_ROOT"/src/internal-skills/*/SKILL.source.md; do
  [ -f "$source_md" ] || continue
  source_any=1
  name="$(basename "$(dirname "$source_md")")"
  [ "$name" = "idd-doctor" ] && saw_doctor=1
  check_key_set "T2: $name SKILL.source.md" "$source_md"
done

if [ "$source_any" -eq 0 ]; then
  fail "T2: no SKILL.source.md found under src/ — the glob or the layout changed"
fi
if [ "$saw_doctor" -eq 1 ]; then
  pass "T2: src/internal-skills/idd-doctor is covered (source-only, never built)"
else
  fail "T2: src/internal-skills/idd-doctor/SKILL.source.md not reached — the eighth source is uncovered"
fi

# ── T3: the effort value survived the move to metadata ────────────────────────
for skill_md in "$REPO_ROOT"/skills/*/SKILL.md; do
  name="$(basename "$(dirname "$skill_md")")"
  check_effort "T3: skills/$name/SKILL.md" "$skill_md"
done
for source_md in "$REPO_ROOT"/src/skills/*/SKILL.source.md \
                 "$REPO_ROOT"/src/internal-skills/*/SKILL.source.md; do
  [ -f "$source_md" ] || continue
  name="$(basename "$(dirname "$source_md")")"
  check_effort "T3: $name SKILL.source.md" "$source_md"
done
shopt -u nullglob

# ── T4: the specific regression #307 fixed must not return ────────────────────
if offenders="$(grep -rln '^effort:' "$REPO_ROOT"/skills "$REPO_ROOT"/src \
                  --include='SKILL.md' --include='SKILL.source.md' 2>/dev/null)"; then
  fail "T4: top-level 'effort:' key is back in: $(echo "$offenders" | tr '\n' ' ')"
else
  pass "T4: no top-level 'effort:' key in any SKILL.md or SKILL.source.md"
fi

# ── T5: the extractors stay inside the frontmatter ────────────────────────────
# T1–T4 read only well-formed files, where an unbounded extractor happens to
# agree with a bounded one — so they cannot tell "the key is absent" from "the
# reader wandered into the body". SKILL.md bodies are full of `---` horizontal
# rules and column-0 `key:` lines, so that distinction is the one thing holding
# T3's verdict up. Each fixture below is built so an unbounded reader returns a
# *different* answer than a bounded one; both were confirmed to fail when the
# closing-fence exit is removed.
FIXTURE_KEYS="$(mktemp -t skill-fm-307-keys.XXXXXX)"
FIXTURE_META="$(mktemp -t skill-fm-307-meta.XXXXXX)"
trap 'rm -f "$FIXTURE_KEYS" "$FIXTURE_META"' EXIT

# Body carries column-0 keys an unbounded reader would report as frontmatter.
cat > "$FIXTURE_KEYS" <<'FIXEOF'
---
name: fixture
description: "bounded-extractor fixture"
metadata:
  effort: low
---

Body starts here.

---

decoy: value
effort: max
FIXEOF

# No `metadata:` in the frontmatter at all, and a decoy block in the body: a
# bounded reader must return nothing, an unbounded one returns 'xhigh'.
cat > "$FIXTURE_META" <<'FIXEOF'
---
name: fixture-no-metadata
description: "frontmatter deliberately has no metadata mapping"
---

Body starts here.

---

metadata:
  effort: xhigh
FIXEOF

fixture_keys="$(frontmatter_keys "$FIXTURE_KEYS" | tr '\n' ' ' | sed 's/ *$//')"
if [ "$fixture_keys" = "name description metadata" ]; then
  pass "T5: frontmatter_keys stops at the closing fence (ignored the body's 'decoy'/'effort')"
else
  fail "T5: frontmatter_keys read past the closing fence — got '$fixture_keys', expected 'name description metadata'"
fi

fixture_effort="$(metadata_value "$FIXTURE_KEYS" effort)"
if [ "$fixture_effort" = "low" ]; then
  pass "T5: metadata_value reads the frontmatter's metadata mapping"
else
  fail "T5: metadata_value misread the frontmatter — got '$fixture_effort', expected 'low'"
fi

fixture_absent="$(metadata_value "$FIXTURE_META" effort)"
if [ -z "$fixture_absent" ]; then
  pass "T5: metadata_value reports absence rather than reading the body's decoy block"
else
  fail "T5: metadata_value read past the closing fence — got '$fixture_absent', expected nothing"
fi

echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ SKILL.md frontmatter key tests failed ($PASS passed, $FAIL failed)"
  exit 1
fi
echo "  ✓ All SKILL.md frontmatter key checks passed ($PASS)"
