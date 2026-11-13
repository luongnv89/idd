#!/usr/bin/env bash
# test-surface-counts-563.sh — Count the moving parts (issue #563)
#
# Acceptance criteria:
#  - AC1: the counts of skills, shared scripts, script lines, config keys,
#         flags and gate headings are recorded in scripts/surface-counts.json,
#         and scripts/surface-count.py fails when one rises without that file
#         changing
#  - AC2: CLAUDE.md and AGENTS.md list every shared script
#
# Obligations from the sensitive-change gate, each a named check below:
#  - P4: a count that rises without the counts file changing fails, and the
#        same rise with the counts file raised by hand passes
#  - P5: the check needs no git repository and no base ref
#
# Every mutation happens in a copy of src/, docs/config-schema.md and the
# counts file under mktemp -d, measured via --root. The committed
# scripts/surface-counts.json is only ever read.
#
# Usage: bash tests/test-surface-counts-563.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/surface-count.py"
COUNTS="$REPO_ROOT/scripts/surface-counts.json"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
F="$TMP/fx"
FC="$F/scripts/surface-counts.json"

echo "◆ Surface count tests (#563)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# run <args...> — run the script, capture output in $OUT and status in $RC.
run() {
  set +e
  OUT="$(python3 "$SCRIPT" "$@" 2>&1)"
  RC=$?
  set -e
}

# frun <args...> — run the script on the fixture tree.
frun() { run --root "$F" "$@"; }

# new_fixture — a fresh copy of the measured tree, outside any git repository.
new_fixture() {
  rm -rf "$F"
  mkdir -p "$F/docs" "$F/scripts"
  cp -R "$REPO_ROOT/src" "$F/src"
  cp "$REPO_ROOT/docs/config-schema.md" "$F/docs/config-schema.md"
  cp "$COUNTS" "$FC"
}

# rec <counts-file> <name> — the recorded number, or "absent".
rec() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["counts"].get(sys.argv[2], "absent"))' "$1" "$2"
}

# setrec <name> <json-value> — hand-edit the fixture's record; null removes it.
setrec() {
  python3 - "$FC" "$1" "$2" <<'EOF'
import json, sys
path, name, value = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
data = json.load(open(path))
if value is None:
    data["counts"].pop(name, None)
else:
    data["counts"][name] = value
json.dump(data, open(path, "w"))
EOF
}

# rises <label> <count>... — --check on the fixture must exit 1 and report
# exactly the named counts as risen, with the hand-edit instruction.
rises() {
  local label="$1" ok=1 name
  shift
  frun --check
  [ "$RC" -eq 1 ] || ok=0
  for name in "$@"; do
    echo "$OUT" | grep -q "✗ $name: rose from" || ok=0
  done
  [ "$(echo "$OUT" | grep -c ': rose from')" -eq "$#" ] || ok=0
  echo "$OUT" | grep -q 'by hand' || ok=0
  if [ "$ok" -eq 1 ]; then
    pass "P4: $label fails --check (exit 1) and names $*"
  else
    fail "P4: $label: exit $RC, output: $OUT"
  fi
}

add_script() {
  printf '#!/usr/bin/env python3\n"""Probe."""\nprint("probe")\n' > "$F/src/shared/scripts/gi-zz-probe.py"
}

# ── Script surface ────────────────────────────────────────────────────────
mode="$(git -C "$REPO_ROOT" ls-files -s scripts/surface-count.py | awk '{print $1}')"
if [ "$mode" = "100755" ]; then
  pass "scripts/surface-count.py is committed with mode 100755"
else
  fail "scripts/surface-count.py committed mode is '${mode:-untracked}', want 100755"
fi

run --help
if [ "$RC" -eq 0 ]; then
  pass "--help exits 0"
else
  fail "--help exited $RC"
fi

if python3 - "$SCRIPT" <<'EOF' 2>/dev/null && ! grep -qE 'subprocess|os\.(system|popen|exec|spawn)' "$SCRIPT"
import ast, sys
mods = set()
for node in ast.walk(ast.parse(open(sys.argv[1], encoding="utf-8").read())):
    if isinstance(node, ast.Import):
        mods.update(alias.name.split(".")[0] for alias in node.names)
    elif isinstance(node, ast.ImportFrom):
        mods.add((node.module or "").split(".")[0])
assert mods <= set(sys.stdlib_module_names)
EOF
then
  pass "P5: the script imports only the standard library and starts no process"
else
  fail "P5: scripts/surface-count.py imports a non-stdlib module or can start a process"
fi

# ── AC1: the committed counts match the committed tree ────────────────────
if git -C "$REPO_ROOT" ls-files --error-unmatch scripts/surface-counts.json >/dev/null 2>&1; then
  pass "scripts/surface-counts.json is committed"
else
  fail "scripts/surface-counts.json is not tracked"
fi

run --check
if [ "$RC" -eq 0 ]; then
  pass "--check passes on the committed tree"
else
  fail "--check fails on the committed tree (exit $RC)"
  echo "$OUT" | grep '✗' | sed 's/^/    /'
fi

run --check --json
if [ "$RC" -eq 0 ] && python3 -c '
import json, sys
d = json.loads(sys.argv[1])
want = ["config_keys", "flags", "gate_headings", "gh_call_files", "script_lines", "scripts", "skills"]
assert d["ok"] is True and d["problems"] == []
assert sorted(d["measured"]) == want and d["measured"] == d["recorded"]
assert d["recorded"] == json.load(open(sys.argv[2]))["counts"]
' "$OUT" "$COUNTS" 2>/dev/null; then
  pass "--json prints the seven measured and recorded counts as one JSON object"
else
  fail "--json output is not the expected JSON object (exit $RC)"
fi

BASE_SCRIPTS="$(rec "$COUNTS" scripts)"
BASE_LINES="$(rec "$COUNTS" script_lines)"
BASE_GATES="$(rec "$COUNTS" gate_headings)"
BASE_FLAGS="$(rec "$COUNTS" flags)"

# ── P5: no git repository, no base ref ────────────────────────────────────
# The fixture is a plain directory, and the only `git` on PATH is a stub that
# records the call and fails.
new_fixture
mkdir -p "$TMP/bin"
printf '#!/bin/sh\ntouch "%s"\nexit 1\n' "$TMP/git-was-called" > "$TMP/bin/git"
chmod +x "$TMP/bin/git"
set +e
OUT="$(cd "$F" && PATH="$TMP/bin:$PATH" python3 "$SCRIPT" --root "$F" --check 2>&1)"
RC=$?
set -e
if [ "$RC" -eq 0 ] && [ ! -e "$TMP/git-was-called" ] && [ ! -e "$F/.git" ]; then
  pass "P5: --check passes on a tree that is not a git repository, and never calls git"
else
  fail "P5: non-git tree: exit $RC, git called: $([ -e "$TMP/git-was-called" ] && echo yes || echo no), output: $OUT"
fi

# ── P4: a rise without the counts file changing fails ─────────────────────
add_script
rises "a new shared script" scripts script_lines

# … and the same rise passes once the counts file is raised by hand.
setrec scripts "$((BASE_SCRIPTS + 1))"
setrec script_lines "$((BASE_LINES + 3))"
frun --check
if [ "$RC" -eq 0 ]; then
  pass "P4: the same rise passes once the counts file is raised by hand"
else
  fail "P4: rise with the counts file raised by hand: exit $RC, output: $OUT"
fi

new_fixture
mkdir -p "$F/src/skills/zz-probe"
printf '# zz-probe\n' > "$F/src/skills/zz-probe/SKILL.source.md"
rises "a new skill directory" skills

new_fixture
python3 - "$F/docs/config-schema.md" <<'EOF'
import sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
head, sep, tail = text.partition("## Full Schema (advanced reference)")
block, fence, rest = tail.partition("```yaml\n")
assert sep and fence
open(path, "w", encoding="utf-8").write(head + sep + block + fence + "zz_probe: true\n" + rest)
EOF
rises "a new config key" config_keys

new_fixture
printf '\nRun `/issue-triage --zz-probe` to probe.\n' >> "$F/src/skills/issue-triage/SKILL.source.md"
rises "a new flag on a skill's own command" flags

new_fixture
printf '# Probe\n\n## Probe gate\n' > "$F/src/shared/references/zz-probe.md"
rises "a new gate heading" gate_headings

# gh_call_files (issue #566): a new file with a gh call is a rise.
new_fixture
printf 'Run `gh issue view 1 --json number`.\n' > "$F/src/shared/references/zz-gh.md"
rises "a new file with a gh call" gh_call_files

# ── --ratchet never raises; it still lowers the rest ──────────────────────
new_fixture
add_script
setrec gate_headings "$((BASE_GATES + 1))"
frun --ratchet
if [ "$RC" -eq 1 ] && [ "$(rec "$FC" scripts)" = "$BASE_SCRIPTS" ] && \
   [ "$(rec "$FC" script_lines)" = "$BASE_LINES" ] && echo "$OUT" | grep -q 'never raises'; then
  pass "--ratchet exits 1 on a rise and leaves the risen records unchanged"
else
  fail "--ratchet on a rise: exit $RC, scripts $(rec "$FC" scripts), output: $OUT"
fi
if [ "$(rec "$FC" gate_headings)" = "$BASE_GATES" ]; then
  pass "--ratchet still lowers the other records"
else
  fail "--ratchet did not lower gate_headings: $(cat "$FC")"
fi

# ── A drop fails until it is ratcheted ────────────────────────────────────
new_fixture
rm "$F/src/shared/scripts/gi-deps.py"
frun --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q '✗ scripts: dropped from' && \
   echo "$OUT" | grep -q -- 'surface-count.py --ratchet'; then
  pass "a removed shared script fails --check (exit 1) and names the --ratchet fix"
else
  fail "drop: exit $RC, output: $OUT"
fi
frun --ratchet
if [ "$RC" -eq 0 ] && [ "$(rec "$FC" scripts)" = "$((BASE_SCRIPTS - 1))" ] && \
   [ "$(rec "$FC" script_lines)" -lt "$BASE_LINES" ]; then
  pass "--ratchet exits 0 and lowers the records to the counts"
else
  fail "--ratchet after a drop: exit $RC, $(cat "$FC")"
fi
frun --check
if [ "$RC" -eq 0 ]; then
  pass "--check passes after the ratchet"
else
  fail "--check after the ratchet: exit $RC, output: $OUT"
fi

# ── An unrecorded count and a stale record ────────────────────────────────
new_fixture
setrec flags null
setrec zz_bogus 1
frun --check
if [ "$RC" -eq 1 ] && echo "$OUT" | grep -q '✗ flags: not recorded' && \
   echo "$OUT" | grep -q '✗ zz_bogus: stale record'; then
  pass "a count with no record and a record with no count fail --check (exit 1)"
else
  fail "unrecorded / stale: exit $RC, output: $OUT"
fi
frun --ratchet
if [ "$RC" -eq 0 ] && [ "$(rec "$FC" flags)" = "$BASE_FLAGS" ] && \
   [ "$(rec "$FC" zz_bogus)" = "absent" ]; then
  pass "--ratchet adds the missing record and drops the stale one"
else
  fail "--ratchet on unrecorded / stale: exit $RC, $(cat "$FC")"
fi

# ── What is not counted ───────────────────────────────────────────────────
new_fixture
cat >> "$F/src/skills/issue-triage/SKILL.source.md" <<'EOF'

Run `/issue-resolver --zz-other-skill` first, or `gh issue list --zz-not-a-command`.
`/issue-triage-next --zz-longer-name` is another command, and --zz-prose is not in a span.
EOF
frun --check
if [ "$RC" -eq 0 ]; then
  pass "a flag outside a span that starts with the skill's own command is not counted"
else
  fail "a foreign flag was counted: exit $RC, output: $OUT"
fi

new_fixture
cat > "$F/src/shared/references/zz-probe.md" <<'EOF'
# Probe

## Gated rollout

## Gateway notes

The gate is mentioned in prose.

```bash
# the probe gate
```

~~~
## Another gate
~~~
EOF
frun --check
if [ "$RC" -eq 0 ]; then
  pass "'Gated', 'Gateway', prose and a '# … gate' line inside a fenced block are not gate headings"
else
  fail "a non-heading or non-word was counted as a gate heading: exit $RC, output: $OUT"
fi

# ── Unusable input and usage ──────────────────────────────────────────────
new_fixture
setrec scripts true
frun --check
if [ "$RC" -eq 3 ]; then
  pass "a record that is not an integer (true) exits 3"
else
  fail "non-integer record exited $RC, want 3"
fi
rm "$FC"
frun --check
if [ "$RC" -eq 3 ]; then
  pass "a missing counts file exits 3"
else
  fail "missing counts file exited $RC, want 3"
fi
new_fixture
rm "$F/docs/config-schema.md"
frun --check
if [ "$RC" -eq 3 ]; then
  pass "a tree without docs/config-schema.md exits 3"
else
  fail "missing config schema exited $RC, want 3"
fi
run --check --ratchet
if [ "$RC" -eq 2 ]; then
  pass "--check and --ratchet together are a usage error (exit 2)"
else
  fail "--check --ratchet exited $RC, want 2"
fi

# ── AC2: CLAUDE.md and AGENTS.md list every shared script ─────────────────
for doc in CLAUDE.md AGENTS.md; do
  missing=""
  for path in "$REPO_ROOT"/src/shared/scripts/*.py; do
    name="$(basename "$path")"
    grep -qE "[├└]── ${name//./\\.}( |\$)" "$REPO_ROOT/$doc" || missing="$missing $name"
  done
  if [ -z "$missing" ]; then
    pass "AC2: $doc lists every shared script ($BASE_SCRIPTS)"
  else
    fail "AC2: $doc's shared-scripts tree lacks:$missing"
  fi
done

# ── CI wiring ─────────────────────────────────────────────────────────────
if grep -qE '^ +run: bash tests/test-surface-counts-563\.sh *$' "$REPO_ROOT/.github/workflows/dist-check.yml"; then
  pass "dist-check.yml runs this test"
else
  fail "dist-check.yml has no step running: bash tests/test-surface-counts-563.sh"
fi

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Surface count tests failed"
  exit 1
fi
echo "  ✓ Surface count contract holds"
exit 0
