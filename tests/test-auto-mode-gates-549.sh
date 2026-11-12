#!/usr/bin/env bash
# test-auto-mode-gates-549.sh — auto mode takes the printed default (issue #549).
#
# A `[y/N]` gate defaults to No. In auto mode it must take that No, or be listed
# in the one exception table in docs/auto-mode.md. Every `? [y/N]` prompt in a
# skill source (src/**/*.md), a runtime doc (docs/*.md) or the built skills
# (skills/**/*.md) carries a marker after it, before the next prompt or heading:
#   <!-- auto:no -->                 takes the default No
#   <!-- auto:exception=<id> -->     differs; <id> is a row of the table
#
#   T1  the lint: every gate is marked, every exception id is a table row, and
#       every table row is referenced by a marker (src, docs, built skills);
#   T2  the lint fails on fixtures: an unmarked gate, a marker past the next
#       heading, an unknown id, an unreferenced row;
#   T3  auto mode never closes an issue: it comments and records already_resolved;
#   T4  the resolver's default-No gates stop in auto with a skipped_reason, and
#       gi-runlog accepts that record;
#   T5  the CI step exists.
#
# Usage: bash tests/test-auto-mode-gates-549.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AUTOMODE="$ROOT/docs/auto-mode.md"
RS_SRC="$ROOT/src/skills/issue-resolver"
RS_DIST="$ROOT/skills/issue-resolver"
WORKFLOW="$ROOT/.github/workflows/dist-check.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Auto mode takes the printed default (#549)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for f in "$AUTOMODE" "$WORKFLOW" "$RS_SRC/SKILL.source.md"; do
  [ -f "$f" ] || { echo "  ✗ missing $f"; exit 1; }
done

# The lint. Usage: lint <table-doc> <file>... ; prints one line per problem,
# exits 1 when there is any.
cat > "$TMP/lint.py" <<'PY'
import re, sys
from pathlib import Path

GATE = re.compile(r"\?\s*[\[(]y/N[\])]")
# An `auto:no` gate whose own Auto clause still continues contradicts its marker.
WIDER = re.compile(r"(?i)\bauto\b[^\n]*\b(continue|proceed)")
MARK = re.compile(r"<!--\s*auto:(no|exception=([a-z0-9-]+))\s*-->")
HEADING = re.compile(r"^#{1,6} ")
FENCE = re.compile(r"^\s*(```|~~~)")
ROW = re.compile(r"^\|\s*`([a-z0-9-]+)`\s*\|")

table_doc, files = sys.argv[1], []
for arg in sys.argv[2:]:  # @list reads one path per line
    files += Path(arg[1:]).read_text().split("\n") if arg.startswith("@") else [arg]
files = [f for f in files if f]
ids, in_table = set(), False
for line in Path(table_doc).read_text(encoding="utf-8").splitlines():
    if line.startswith("## "):
        in_table = line.strip() == "## Exception table"
    elif in_table and (m := ROW.match(line)):
        ids.add(m.group(1))

problems, referenced, gates = [], set(), 0
for name in files:
    lines = Path(name).read_text(encoding="utf-8").splitlines()
    fenced = []
    infence = False
    for line in lines:
        if FENCE.match(line):
            infence = not infence
        fenced.append(infence)
    for i, line in enumerate(lines):
        for m in MARK.finditer(line):
            if m.group(2):
                referenced.add(m.group(2))
                if m.group(2) not in ids:
                    problems.append(f"{name}:{i+1}: unknown exception id '{m.group(2)}'")
        g = GATE.search(line)
        if not g:
            continue
        gates += 1
        window = [line[g.end():]]
        for j in range(i + 1, len(lines)):
            if GATE.search(lines[j]) or (not fenced[j] and HEADING.match(lines[j])):
                break
            window.append(lines[j])
        marks = [m for w in window for m in MARK.finditer(w)]
        if not marks:
            problems.append(f"{name}:{i+1}: [y/N] gate has no auto marker")
        elif marks[0].group(1) == "no" and any(WIDER.search(w) for w in window):
            problems.append(f"{name}:{i+1}: auto:no gate says auto continues — take No or list it")
for unused in sorted(ids - referenced):
    problems.append(f"{table_doc}: exception '{unused}' is referenced by no marker")
for p in problems:
    print(p)
print(f"gates={gates} ids={len(ids)}", file=sys.stderr)
sys.exit(1 if problems else 0)
PY

# ── T1: the repository passes ─────────────────────────────────────────────
(cd "$ROOT" && git ls-files 'src/*.md' 'docs/*.md' | grep -v '^docs/.*/' | sed "s|^|$ROOT/|") > "$TMP/src.list"
if out="$(python3 "$TMP/lint.py" "$AUTOMODE" "@$TMP/src.list" 2>"$TMP/stats")"; then
  pass "T1.1 every [y/N] gate in src/ and docs/ is marked; ids and rows agree ($(cat "$TMP/stats"))"
else
  fail "T1.1 auto-mode gate lint (src/, docs/):"; printf '      %s\n' "$out"
fi
gates="$(sed -n 's/^gates=\([0-9]*\).*/\1/p' "$TMP/stats")"
[ "${gates:-0}" -ge 10 ] && pass "T1.2 the lint saw the gates ($gates ≥ 10)" \
  || fail "T1.2 the lint saw only ${gates:-0} gates — the scan lost its inputs"

if [ -d "$ROOT/skills" ]; then
  find "$ROOT/skills" -name '*.md' -type f > "$TMP/dist.list"
  if out="$(python3 "$TMP/lint.py" "$AUTOMODE" "@$TMP/dist.list" 2>/dev/null)"; then
    pass "T1.3 the built skills keep every gate marker"
  else
    fail "T1.3 auto-mode gate lint (built skills/):"; printf '      %s\n' "$out"
  fi
else
  fail "T1.3 skills/ missing — build first"
fi

grep -q '^## Exception table' "$AUTOMODE" && pass "T1.4 docs/auto-mode.md has the one exception table" \
  || fail "T1.4 docs/auto-mode.md lacks '## Exception table'"
grep -qF 'take the gate'"'"'s **printed default**' "$AUTOMODE" \
  && pass "T1.5 the gate rule takes the printed default" \
  || fail "T1.5 the gate rule does not say auto takes the printed default"

# ── T2: the lint fails when it should ─────────────────────────────────────
fx="$TMP/fx"; mkdir -p "$fx"
cat > "$fx/table.md" <<'MD'
## Exception table

| Id | Gate | Auto behavior | Why |
|----|------|---------------|-----|
| `kept` | x | y | z |

## Next
MD
printf '  Go? [y/N]\n<!-- auto:exception=kept -->\n' > "$fx/ok.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" >/dev/null 2>&1 \
  && pass "T2.0 a marked gate and a referenced row pass" || fail "T2.0 the clean fixture failed"

printf '  Go? [y/N]\nAuto: continue anyway.\n' > "$fx/unmarked.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/unmarked.md" >/dev/null 2>&1 \
  && fail "T2.1 an unmarked gate passed" || pass "T2.1 an unmarked gate fails"

printf '  Go? [y/N]\n\n## Other\n<!-- auto:no -->\n' > "$fx/late.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/late.md" >/dev/null 2>&1 \
  && fail "T2.2 a marker past the next heading counted" || pass "T2.2 a marker past the next heading does not count"

printf '  Go? [y/N]\n  Stop? [y/N]\n<!-- auto:no -->\n' > "$fx/shared.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/shared.md" >/dev/null 2>&1 \
  && fail "T2.3 two gates shared one marker" || pass "T2.3 each gate needs its own marker"

printf '  Go? [y/N]\n**Auto:** warn in log, continue anyway. <!-- auto:no -->\n' > "$fx/wider.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/wider.md" >/dev/null 2>&1 \
  && fail "T2.6 an auto:no gate whose Auto clause continues passed" \
  || pass "T2.6 an auto:no gate whose Auto clause continues fails"

printf '  Go? (y/N)\n' > "$fx/paren.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/paren.md" >/dev/null 2>&1 \
  && fail "T2.7 an unmarked (y/N) gate passed" || pass "T2.7 an unmarked (y/N) gate fails"

printf '  Go? [y/N]\n<!-- auto:exception=unlisted -->\n' > "$fx/unknown.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/ok.md" "$fx/unknown.md" >/dev/null 2>&1 \
  && fail "T2.4 an unlisted exception id passed" || pass "T2.4 an exception id missing from the table fails"

printf '  Go? [y/N]\n<!-- auto:no -->\n' > "$fx/norow.md"
python3 "$TMP/lint.py" "$fx/table.md" "$fx/norow.md" >/dev/null 2>&1 \
  && fail "T2.5 a table row no marker references passed" || pass "T2.5 an unreferenced table row fails"

# ── T3: auto mode never closes an issue ───────────────────────────────────
if grep -rqiE 'close the issue with a comment|closed with a comment|gh issue close|auto-close' \
     "$RS_SRC" "$ROOT/src/shared/agents"; then
  fail "T3.1 the resolver still closes an issue"
else
  pass "T3.1 no resolver source closes an issue"
fi
grep -rq --exclude-dir=__pycache__ 'issue_close' "$ROOT/src" "$ROOT/skills" \
  && fail "T3.2 an 'issue_close' effect remains" || pass "T3.2 the progress effect is issue_comment, not issue_close"
for tree in "$RS_SRC" "$RS_DIST"; do
  f="$tree/references/steps/step-1-research.md"
  if grep -qF 'gh issue comment {N} --body-file' "$f" && grep -qF 'author.login' "$f" && grep -qF '<!-- idd:already-resolved -->' "$f" \
     && grep -qF '**never close the issue.**' "$f"; then
    pass "T3.3 ${tree#"$ROOT"/}: auto comments a close recommendation, never closes"
  else
    fail "T3.3 ${tree#"$ROOT"/}: the already-resolved auto path is not comment-only"
  fi
done
grep -qF '`issue_comment` (Step 1)' "$RS_SRC/references/steps/step-0j-progress-record.md" \
  && grep -qF 'never post a second' "$RS_SRC/references/steps/step-0j-progress-record.md" \
  && pass "T3.4 a resume reconciles the comment against live comments" \
  || fail "T3.4 the comment effect is not reconciled"
grep -qF 'It **never closes an issue**' "$AUTOMODE" \
  && pass "T3.5 docs/auto-mode.md states auto never closes an issue" \
  || fail "T3.5 docs/auto-mode.md does not state the no-close rule"

# ── T4: the resolver's default-No gates ──────────────────────────────────
PS="$RS_SRC/references/pipeline-steps.md"
for stale in 'Skip the assignment guard' 'log blocking labels as warnings and continue' \
             'Continue past the max-commits guard' 'Auto: warn in log, continue'; do
  grep -qF "$stale" "$PS" "$RS_SRC/SKILL.source.md" "$RS_SRC/references/steps/step-3-implement.md" \
    && fail "T4.1 stale auto-continue wording remains: '$stale'" \
    || pass "T4.1 no auto-continue: '$stale'"
done
for reason in assigned_to_other blocked_label empty_body large_scope max_commits_exceeded; do
  grep -qF "skipped_reason: $reason\`. <!-- auto:no -->" "$RS_SRC/references/error-messages.md" \
    && pass "T4.2 error-messages: auto takes No with skipped_reason $reason" \
    || fail "T4.2 error-messages: no auto-No line for $reason"
done
row='{"ts":"2026-11-12T00:00:00Z","issue":1,"mode":"auto","skill":"issue-resolver","outcome":"failed","pr":null,"skipped_reason":"blocked_label"}'
if printf '%s' "$row" | python3 "$ROOT/src/shared/scripts/gi-runlog.py" --echo >/dev/null 2>&1; then
  pass "T4.3 gi-runlog accepts a resolver failed row with skipped_reason"
else
  fail "T4.3 gi-runlog rejects a resolver failed row with skipped_reason"
fi
n="$(grep -c '^- skipped_reason:' "$ROOT/src/skills/auto-pilot/references/subagent-prompts.md" || true)"
[ "$n" -eq 2 ] && pass "T4.4 both auto-pilot resolver prompts return skipped_reason" \
  || fail "T4.4 auto-pilot resolver prompts return skipped_reason $n time(s), want 2"
P23="$ROOT/src/skills/auto-pilot/references/phases/phase-2-resolve.md"
grep -qF '`failure_reason`, `skipped_reason`.' "$P23" \
  && grep -qF 'it never feeds the failure streak, quarantine or' "$P23" \
  && pass "T4.5 auto-pilot records a gate decline as skipped, outside the failure streak" \
  || fail "T4.5 auto-pilot does not treat a gate decline as a skip"
grep -qF 'with `skipped_reason: already_resolved`, add the issue to' "$P23" \
  && grep -qF 'the session skip list — it stays open, so triage would re-pick it' "$P23" \
  && pass "T4.7 auto-pilot adds an already-resolved issue to the session skip list" \
  || fail "T4.7 the already_resolved handler does not add the issue to the session skip list"
grep -qF 'body_file="$(mktemp)"' "$RS_SRC/references/steps/step-1-research.md" \
  && pass "T4.8 the close-recommendation snippet creates its body file with mktemp" \
  || fail "T4.8 the close-recommendation snippet never creates its body file"
# A skipped line ends a failure streak: gi-runlog counts only `failed`.
log="$TMP/runs.jsonl"
for o in failed failed skipped; do
  printf '{"ts":"2026-11-12T00:00:00Z","issue":7,"mode":"balanced","skill":"auto-pilot","outcome":"%s","pr":null}\n' "$o" >> "$log"
done
streak="$(python3 "$ROOT/src/shared/scripts/gi-runlog.py" --failure-streak 7 --path "$log" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["streak"])' 2>/dev/null || echo err)"
[ "$streak" = "0" ] && pass "T4.6 a gate-decline skipped line resets the failure streak" \
  || fail "T4.6 failure streak after a skipped line is '$streak', want 0"

# ── T5: CI runs this lint ─────────────────────────────────────────────────
grep -qF 'run: bash tests/test-auto-mode-gates-549.sh' "$WORKFLOW" \
  && pass "T5 dist-check.yml runs the lint" || fail "T5 dist-check.yml does not run the lint"

echo ""
echo "  Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
