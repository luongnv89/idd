#!/usr/bin/env bash
# test-scripts-pipeline-251.sh — Issue #251 acceptance checks for the shared
# scripts pipeline (gi-config, gi-runlog, gi-deps).
#
# Acceptance criteria covered:
#   AC1  Bundling + guards — every script a skill bundles is named in that
#        skill's bundled-dependency precheck fence, and every script the fence
#        names is actually bundled. Both directions, derived independently.
#   AC2  Shipped parser — the dependency-marker parser ships inside auto-pilot
#        as references/scripts/gi-deps.py; the old dev-tree module name
#        (dependency_gate_parse) survives nowhere, and phases.md cites the
#        shipped path rather than a scripts/*.py dev path.
#   AC3  gi-config — merges the documented defaults with .gitissue.yml and
#        prints one JSON line; exit 3 on an invalid config, exit 4 when it
#        cannot complete.
#   AC4  gi-runlog — --echo normalizes and writes nothing, --append writes
#        exactly one \n-terminated line, complexity collapses 5 values to 3,
#        and an invalid record exits 3 without writing.
#   AC5  Prose fallback — every wiring skill keeps its inline defaults and the
#        `gi-config unavailable` degrade path, both run-log sites keep the
#        `mkdir -p .gitissue` fallback, and phases.md keeps the manual parse.
#
# Also asserted: source and shipped copies are byte-identical and share the
# same 0755 mode, every script's --help exits 0, and gi-config's vendored
# restricted-YAML parser agrees with scripts/build.py's.
#
# Usage: bash tests/test-scripts-pipeline-251.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
SKILLS="$REPO_ROOT/skills"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Fold a PASS|label / FAIL|label report file into the counters. A report with
# zero lines is itself a failure: a check that asserts nothing is a defect, not
# a pass.
report() {
  local file="$1" label_for_empty="$2" count=0 verdict label
  while IFS='|' read -r verdict label; do
    [ -n "$verdict" ] || continue
    count=$((count + 1))
    if [ "$verdict" = "PASS" ]; then pass "$label"; else fail "$label"; fi
  done < "$file"
  if [ "$count" -eq 0 ]; then
    fail "$label_for_empty (no assertions produced — vacuous check)"
  fi
}

# Portable mode read: GNU `stat -c` and BSD `stat -f` disagree, python3 does not.
mode_of() {
  python3 -c 'import os,sys;print(oct(os.stat(sys.argv[1]).st_mode & 0o777))' "$1"
}

# Umask-proof executability. Git records only the exec bit, so checkout writes a
# 100755 blob as 0777 & ~umask: 0o755 under umask 022 (the GitHub runner
# default), 0o775 under the equally common 002. Absolute-mode assertions turn a
# correct build red on a contributor's clone — assert `mode & 0o111` instead.
has_exec_bit() {
  python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$1"
}

echo "◆ Shared Scripts Pipeline Tests (issue #251)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1 (AC1): precheck fence ↔ bundled scripts, both directions
# ───────────────────────────────────────────────────────────
# The fence set is parsed from the built SKILL.md's precheck section; the
# bundled set is listed from the filesystem. Neither is derived from the other.
python3 - "$SKILLS" > "$TMP/ac1.txt" <<'PY'
import re
import sys
from pathlib import Path

skills_root = Path(sys.argv[1])
WIRED = [
    "auto-pilot",
    "issue-analysis",
    "issue-creator",
    "issue-pr-review",
    "issue-resolver",
    "issue-triage",
]
HEADING_RE = re.compile(r"^\s{0,3}#{2,4}\s+Bundled dependency precheck\s*$")
SCRIPT_REF_RE = re.compile(r"(?<![\w/])references/scripts/([a-z][a-z0-9-]+\.py)")

out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


def precheck_section(text):
    """Body of the 'Bundled dependency precheck' section, or None."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if HEADING_RE.match(line):
            start = i + 1
            break
    if start is None:
        return None
    body = []
    for line in lines[start:]:
        if re.match(r"^\s*##\s", line) or re.match(r"^\s*---\s*$", line):
            break
        body.append(line)
    return "\n".join(body)


for name in WIRED:
    skill_md = skills_root / name / "SKILL.md"
    if not skill_md.is_file():
        emit(False, f"T1: skills/{name}/SKILL.md is missing")
        continue
    section = precheck_section(skill_md.read_text(encoding="utf-8"))
    if section is None:
        emit(False, f"T1: skills/{name} has no 'Bundled dependency precheck' section")
        continue
    named = set(SCRIPT_REF_RE.findall(section))
    scripts_dir = skills_root / name / "references" / "scripts"
    bundled = {p.name for p in scripts_dir.glob("*.py")} if scripts_dir.is_dir() else set()

    emit(bool(bundled), f"T1: skills/{name} bundles at least one script")
    missing = sorted(bundled - named)
    emit(
        not missing,
        f"T1: skills/{name} precheck names every bundled script"
        + (" (missing: " + ", ".join(missing) + ")" if missing else ""),
    )
    stale = sorted(named - bundled)
    emit(
        not stale,
        f"T1: skills/{name} bundles every script its precheck names"
        + (" (stale: " + ", ".join(stale) + ")" if stale else ""),
    )

# A skill outside the wired six must not have acquired a scripts bundle without
# a precheck entry — catches an accidental closure widening.
for skill_dir in sorted(p for p in skills_root.iterdir() if p.is_dir()):
    if skill_dir.name in WIRED:
        continue
    stray = sorted(p.name for p in (skill_dir / "references" / "scripts").glob("*.py"))
    emit(
        not stray,
        f"T1: skills/{skill_dir.name} bundles no scripts"
        + (" (unexpected: " + ", ".join(stray) + ")" if stray else ""),
    )

print("\n".join(out))
PY
report "$TMP/ac1.txt" "T1: precheck/bundle parity"

# ───────────────────────────────────────────────────────────
# T2 (AC2): the dependency parser ships inside auto-pilot
# ───────────────────────────────────────────────────────────
# Drive the scan from the git index rather than the filesystem. `grep -r … 2>/dev/null`
# cannot tell "no match" (exit 1) from "directory missing" (exit 2) once stderr is
# swallowed, so a tree with no skills/ at all would print PASS; and walking the
# working tree also reads untracked build artifacts (scripts/__pycache__/*.pyc),
# where stale bytecode of a since-deleted module produces a spurious FAIL.
GATE_LITERAL='dependency_gate_parse'
T2_FILES=()
while IFS= read -r tracked; do
  T2_FILES+=("$tracked")
done < <(cd "$REPO_ROOT" && git ls-files -- src skills scripts docs)

if [ "${#T2_FILES[@]}" -eq 0 ]; then
  fail "T2: git tracks no files under src/, skills/, scripts/, docs/ — the scan would be vacuous"
else
  pass "T2.0: scanning ${#T2_FILES[@]} tracked file(s) under src/, skills/, scripts/, docs/"
  set +e
  gate_hits="$(cd "$REPO_ROOT" && grep -lIFe "$GATE_LITERAL" -- "${T2_FILES[@]}")"
  gate_rc=$?
  set -e
  if [ "$gate_rc" -gt 1 ]; then
    fail "T2: the '$GATE_LITERAL' scan itself errored (grep exit $gate_rc)"
  elif [ -n "$gate_hits" ]; then
    fail "T2: the '$GATE_LITERAL' dev-tree literal still exists"
    printf '%s\n' "$gate_hits" | sed 's|^|    |'
  else
    pass "T2: no '$GATE_LITERAL' literal under src/, skills/, scripts/, docs/"
  fi
fi

SHIPPED_DEPS="$SKILLS/auto-pilot/references/scripts/gi-deps.py"
if [ -f "$SHIPPED_DEPS" ]; then
  pass "T2.1: skills/auto-pilot/references/scripts/gi-deps.py exists"
else
  fail "T2.1: skills/auto-pilot/references/scripts/gi-deps.py missing"
fi

if [ -x "$SHIPPED_DEPS" ]; then
  pass "T2.2: shipped gi-deps.py is executable"
else
  fail "T2.2: shipped gi-deps.py is not executable (mode $(mode_of "$SHIPPED_DEPS" 2>/dev/null || echo '?'))"
fi

if [ -f "$SHIPPED_DEPS" ]; then
  deps_out="$(printf '%s' 'Blocked by: acme/lib#15, #12' | python3 "$SHIPPED_DEPS")"
  if [ "$deps_out" = "12" ]; then
    pass "T2.3: shipped gi-deps.py drops the cross-repo ref and prints exactly '12'"
  else
    fail "T2.3: shipped gi-deps.py printed '$deps_out' (expected '12')"
  fi
fi

PHASES="$SKILLS/auto-pilot/references/phases.md"
if grep -qF 'references/scripts/gi-deps.py' "$PHASES"; then
  pass "T2.4: shipped phases.md cites references/scripts/gi-deps.py"
else
  fail "T2.4: shipped phases.md does not cite references/scripts/gi-deps.py"
fi

# The dev-tree path form must not survive into the install surface: a skill
# installed elsewhere has no scripts/ directory to read.
if grep -qE '(^|[^a-zA-Z0-9_/-])scripts/[a-z_][a-z0-9_-]*\.py' "$PHASES"; then
  fail "T2.5: shipped phases.md still names a bare scripts/*.py dev path"
  grep -nE '(^|[^a-zA-Z0-9_/-])scripts/[a-z_][a-z0-9_-]*\.py' "$PHASES" | sed 's/^/    /'
else
  pass "T2.5: shipped phases.md names no bare scripts/*.py dev path"
fi

# ───────────────────────────────────────────────────────────
# T3 (AC3): gi-config against a shipped copy + its bundled schema
# ───────────────────────────────────────────────────────────
GI_CONFIG="$SKILLS/issue-resolver/references/scripts/gi-config.py"
GI_SCHEMA="$SKILLS/issue-resolver/references/docs/config-schema.md"
REPO_CONFIG="$REPO_ROOT/.gitissue.yml"
REPO_CONFIG_BEFORE=""
[ -f "$REPO_CONFIG" ] && REPO_CONFIG_BEFORE="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO_CONFIG")"

# --config always points at a scratch file: this test never reads or mutates
# the repository's own .gitissue.yml.
printf 'resolve:\n  max_commits: 7\n' > "$TMP/good.yml"
printf 'resolve:\n  max_commits: "ten"\n' > "$TMP/bad.yml"

set +e
"$GI_CONFIG" --schema "$GI_SCHEMA" --config "$TMP/good.yml" > "$TMP/good.json" 2>"$TMP/good.err"
gi_rc=$?
set -e
if [ "$gi_rc" -eq 0 ]; then
  pass "T3: gi-config exits 0 against a valid config and its bundled schema"
else
  fail "T3: gi-config exited $gi_rc (expected 0)"
  sed 's/^/    /' "$TMP/good.err"
fi

lines="$(wc -l < "$TMP/good.json" | tr -d ' ')"
if [ "$lines" = "1" ]; then
  pass "T3.1: gi-config stdout is exactly one line"
else
  fail "T3.1: gi-config stdout has $lines line(s) (expected 1)"
fi

python3 - "$TMP/good.json" > "$TMP/ac3.txt" <<'PY'
import json
import sys
from pathlib import Path

out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


raw = Path(sys.argv[1]).read_text(encoding="utf-8")
try:
    payload = json.loads(raw)
except json.JSONDecodeError as exc:
    emit(False, f"T3.2: gi-config stdout is not JSON — {exc.msg}")
else:
    emit(
        sorted(payload) == ["config", "config_file", "first_run"],
        "T3.2: gi-config emits exactly the keys config, config_file, first_run "
        f"(got {sorted(payload)})",
    )
    emit(isinstance(payload.get("config"), dict), "T3.3: 'config' is an object")
    emit(
        isinstance(payload.get("first_run"), bool),
        "T3.4: 'first_run' is a boolean",
    )
print("\n".join(out))
PY
report "$TMP/ac3.txt" "T3.2: gi-config payload shape"

# Every dotted key the resolver's own inline defaults list names must be
# resolvable from the merged config — the fallback prose and the script must
# describe the same configuration surface.
python3 - "$SKILLS/issue-resolver/SKILL.md" "$TMP/good.json" > "$TMP/ac3keys.txt" <<'PY'
import json
import re
import sys
from pathlib import Path

skill_md, payload_file = (Path(a) for a in sys.argv[1:3])
out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


text = skill_md.read_text(encoding="utf-8")
lines = text.splitlines()
start = next((i + 1 for i, l in enumerate(lines) if l.strip() == "## Configuration"), None)
body = []
if start is not None:
    in_fence = False
    for line in lines[start:]:
        if re.match(r"^##\s", line):
            break
        # Drop fenced blocks: their delimiters are backtick runs that would
        # otherwise shift the inline-code-span pairing for the whole block.
        if re.match(r"^\s*```", line):
            in_fence = not in_fence
            continue
        if not in_fence:
            body.append(line)

DOTTED_RE = re.compile(r"^[a-z_][a-z0-9_]*(?:\.[a-z0-9_]+)+$")
named = set()
for span in re.findall(r"`([^`]+)`", "\n".join(body)):
    candidate = span.split(":", 1)[0].strip()
    if DOTTED_RE.fullmatch(candidate):
        named.add(candidate)

config = json.loads(payload_file.read_text(encoding="utf-8"))["config"]
emit(bool(named), f"T3.5: resolver inline defaults name {len(named)} dotted key(s)")
absent = sorted(named - set(config))
emit(
    not absent,
    "T3.6: every dotted key the resolver's inline defaults name is present in "
    "gi-config's merged config"
    + (" (absent: " + ", ".join(absent) + ")" if absent else ""),
)
print("\n".join(out))
PY
report "$TMP/ac3keys.txt" "T3.5: resolver inline-default key coverage"

set +e
"$GI_CONFIG" --schema "$GI_SCHEMA" --config "$TMP/bad.yml" >"$TMP/bad.json" 2>"$TMP/bad.err"
bad_rc=$?
set -e
if [ "$bad_rc" -eq 3 ]; then
  pass "T3.7: an invalid .gitissue.yml (resolve.max_commits: \"ten\") exits 3"
else
  fail "T3.7: invalid config exited $bad_rc (expected 3)"
fi
if grep -qF '✗ Invalid .gitissue.yml:' "$TMP/bad.err"; then
  pass "T3.8: the exit-3 path reports '✗ Invalid .gitissue.yml:' on stderr"
else
  fail "T3.8: exit-3 stderr missing the '✗ Invalid .gitissue.yml:' prefix"
fi

set +e
"$GI_CONFIG" --schema /nonexistent --config "$TMP/good.yml" >/dev/null 2>"$TMP/noschema.err"
noschema_rc=$?
set -e
if [ "$noschema_rc" -eq 4 ]; then
  pass "T3.9: --schema /nonexistent exits 4 (caller falls back to inline defaults)"
else
  fail "T3.9: missing schema exited $noschema_rc (expected 4)"
fi
if grep -qF '⚠ gi-config:' "$TMP/noschema.err"; then
  pass "T3.10: the exit-4 path reports '⚠ gi-config:' on stderr"
else
  fail "T3.10: exit-4 stderr missing the '⚠ gi-config:' prefix"
fi

if [ -n "$REPO_CONFIG_BEFORE" ]; then
  after="$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$REPO_CONFIG")"
  if [ "$after" = "$REPO_CONFIG_BEFORE" ]; then
    pass "T3.11: the repository's own .gitissue.yml was not modified"
  else
    fail "T3.11: the repository's own .gitissue.yml changed during the run"
  fi
fi

# ───────────────────────────────────────────────────────────
# T3.12-T3.15: the no-PyYAML branch (the branch CI actually runs)
# ───────────────────────────────────────────────────────────
# gi-config has two parsers with deliberately *different* contracts for the same
# malformed file: with PyYAML a YAML error is a user error (exit 3, skill stops);
# without it, anything outside the vendored restricted grammar is a parser
# limitation, not a user error (exit 4, skill degrades to its inline defaults).
# Whichever branch the host happens to take, the other ships untested — and
# .github/workflows/dist-check.yml runs actions/setup-python with no pip install,
# so CI only ever exercises the vendored one. Force it here with a stub module
# that raises ImportError, so both branches are covered on every host.
NOYAML_DIR="$TMP/noyaml"
mkdir -p "$NOYAML_DIR"
cat > "$NOYAML_DIR/yaml.py" <<'STUB'
raise ImportError("PyYAML masked by test-scripts-pipeline-251.sh")
STUB

# Flow mapping: valid YAML that the restricted grammar deliberately rejects.
printf 'resolve: {max_commits: 7}\n' > "$TMP/flow.yml"
# Plain block mapping: inside the restricted grammar, must still resolve.
printf 'resolve:\n  max_commits: 7\n' > "$TMP/plain.yml"

set +e
PYTHONPATH="$NOYAML_DIR" "$GI_CONFIG" --schema "$GI_SCHEMA" --config "$TMP/plain.yml" \
  >"$TMP/noyaml-plain.json" 2>"$TMP/noyaml-plain.err"
noyaml_plain_rc=$?
PYTHONPATH="$NOYAML_DIR" "$GI_CONFIG" --schema "$GI_SCHEMA" --config "$TMP/flow.yml" \
  >/dev/null 2>"$TMP/noyaml-flow.err"
noyaml_flow_rc=$?
PYTHONPATH="$NOYAML_DIR" "$GI_CONFIG" --schema "$GI_SCHEMA" --config "$TMP/bad.yml" \
  >/dev/null 2>"$TMP/noyaml-bad.err"
noyaml_bad_rc=$?
set -e

# Guard the guard: if the stub did not take effect the three checks below would
# be silently re-testing the PyYAML branch.
if PYTHONPATH="$NOYAML_DIR" python3 -c 'import yaml' 2>/dev/null; then
  fail "T3.12: the PyYAML stub did not mask 'import yaml' — T3.13-T3.15 are vacuous"
else
  pass "T3.12: the PyYAML stub masks 'import yaml' for the checks below"
fi

if [ "$noyaml_plain_rc" -eq 0 ]; then
  pass "T3.13: without PyYAML, the vendored parser reads a restricted-grammar config (exit 0)"
else
  fail "T3.13: without PyYAML, a restricted-grammar config exited $noyaml_plain_rc (expected 0)"
  sed 's/^/    /' "$TMP/noyaml-plain.err"
fi

if [ "$noyaml_flow_rc" -eq 4 ]; then
  pass "T3.14: without PyYAML, YAML outside the restricted grammar degrades (exit 4, not 3)"
else
  fail "T3.14: without PyYAML, a flow mapping exited $noyaml_flow_rc (expected 4 — a parser limitation is not a user error)"
  sed 's/^/    /' "$TMP/noyaml-flow.err"
fi

if [ "$noyaml_bad_rc" -eq 3 ]; then
  pass "T3.15: without PyYAML, a type-invalid value is still a user error (exit 3)"
else
  fail "T3.15: without PyYAML, resolve.max_commits: \"ten\" exited $noyaml_bad_rc (expected 3)"
  sed 's/^/    /' "$TMP/noyaml-bad.err"
fi

# ───────────────────────────────────────────────────────────
# T4 (AC4): gi-runlog echo/append/normalize/reject
# ───────────────────────────────────────────────────────────
GI_RUNLOG="$SKILLS/issue-resolver/references/scripts/gi-runlog.py"
RECORD='{"issue":251,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":270,"complexity":"complex"}'

ECHO_TARGET="$TMP/echo-must-not-exist/runs.jsonl"
# Capture to a file, not just to `$( )`: command substitution strips trailing
# newlines, so zero output and one line are indistinguishable once piped through
# `printf '%s\n'`. The file preserves the difference for the line count below.
ECHO_OUT_FILE="$TMP/echo.out"
set +e
printf '%s' "$RECORD" | python3 "$GI_RUNLOG" --echo --path "$ECHO_TARGET" \
  >"$ECHO_OUT_FILE" 2>"$TMP/echo.err"
echo_rc=$?
set -e
echo_out="$(cat "$ECHO_OUT_FILE")"
if [ "$echo_rc" -eq 0 ]; then
  pass "T4: gi-runlog --echo exits 0 on a valid record"
else
  fail "T4: gi-runlog --echo exited $echo_rc (expected 0)"
  sed 's/^/    /' "$TMP/echo.err"
fi
echo_lines="$(wc -l < "$ECHO_OUT_FILE" | tr -d ' ')"
echo_bytes="$(wc -c < "$ECHO_OUT_FILE" | tr -d ' ')"
if [ "$echo_lines" = "1" ] && [ -s "$ECHO_OUT_FILE" ]; then
  pass "T4.1: gi-runlog --echo prints exactly one line"
else
  fail "T4.1: gi-runlog --echo printed $echo_lines newline-terminated line(s) / $echo_bytes byte(s) (expected exactly 1 line)"
fi
if [ ! -e "$ECHO_TARGET" ] && [ ! -e "$TMP/echo-must-not-exist" ]; then
  pass "T4.2: gi-runlog --echo created no file (the --no-run-log contract)"
else
  fail "T4.2: gi-runlog --echo wrote to $ECHO_TARGET"
fi

APPEND_TARGET="$TMP/append/runs.jsonl"
set +e
printf '%s' "$RECORD" | python3 "$GI_RUNLOG" --append --path "$APPEND_TARGET" 2>"$TMP/append.err"
append_rc=$?
set -e
if [ "$append_rc" -eq 0 ]; then
  pass "T4.3: gi-runlog --append exits 0 and creates the parent directory"
else
  fail "T4.3: gi-runlog --append exited $append_rc (expected 0)"
  sed 's/^/    /' "$TMP/append.err"
fi
python3 - "$APPEND_TARGET" "$echo_out" > "$TMP/ac4.txt" <<'PY'
import json
import sys
from pathlib import Path

target = Path(sys.argv[1])
echoed = sys.argv[2]
out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


if not target.is_file():
    emit(False, "T4.4: --append wrote no file")
else:
    raw = target.read_bytes()
    emit(
        raw.count(b"\n") == 1 and raw.endswith(b"\n") and not raw.endswith(b"\n\n"),
        "T4.4: --append wrote exactly one line terminated by a single newline",
    )
    written = raw.decode("utf-8").rstrip("\n")
    emit(written == echoed, "T4.5: --append and --echo produce the identical line")
    try:
        record = json.loads(written)
    except json.JSONDecodeError as exc:
        emit(False, f"T4.6: the appended line is not JSON — {exc.msg}")
    else:
        emit(
            record.get("complexity") == "high",
            "T4.6: complexity 'complex' normalizes to 'high' "
            f"(got {record.get('complexity')!r})",
        )
print("\n".join(out))
PY
report "$TMP/ac4.txt" "T4.4: appended-line shape"

set +e
trivial_out="$(printf '%s' '{"issue":251,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":null,"complexity":"trivial"}' \
  | python3 "$GI_RUNLOG" --echo 2>/dev/null)"
set -e
if printf '%s' "$trivial_out" | grep -qF '"complexity":"low"'; then
  pass "T4.7: complexity 'trivial' normalizes to 'low'"
else
  fail "T4.7: complexity 'trivial' did not normalize to 'low' (got: $trivial_out)"
fi

MISSING_PR_TARGET="$TMP/missing-pr/runs.jsonl"
set +e
printf '%s' '{"issue":251,"mode":"auto","skill":"issue-resolver","outcome":"success"}' \
  | python3 "$GI_RUNLOG" --append --path "$MISSING_PR_TARGET" >/dev/null 2>"$TMP/missing.err"
missing_rc=$?
set -e
if [ "$missing_rc" -eq 3 ]; then
  pass "T4.8: a record missing 'pr' exits 3"
else
  fail "T4.8: a record missing 'pr' exited $missing_rc (expected 3)"
fi
if [ ! -e "$MISSING_PR_TARGET" ]; then
  pass "T4.9: the exit-3 path wrote nothing"
else
  fail "T4.9: the exit-3 path still wrote $MISSING_PR_TARGET"
fi

# `pr` is the only nullable field in the schema. A null in any other required
# key once sailed through — the type loops skip None and the null-drop pass
# covers optional keys only — and was emitted verbatim, e.g. `"issue":null`.
NULL_TARGET="$TMP/null-required/runs.jsonl"
for null_key in issue mode skill outcome; do
  record="$(python3 -c '
import json, sys
rec = {"issue": 251, "mode": "auto", "skill": "issue-resolver", "outcome": "success", "pr": 270}
rec[sys.argv[1]] = None
sys.stdout.write(json.dumps(rec))' "$null_key")"
  set +e
  printf '%s' "$record" | python3 "$GI_RUNLOG" --append --path "$NULL_TARGET" \
    >/dev/null 2>"$TMP/null-$null_key.err"
  null_rc=$?
  set -e
  if [ "$null_rc" -eq 3 ]; then
    pass "T4.10: a null '$null_key' exits 3 (only 'pr' is nullable)"
  else
    fail "T4.10: a null '$null_key' exited $null_rc (expected 3)"
  fi
done
if [ ! -e "$NULL_TARGET" ]; then
  pass "T4.11: no null-required-key record reached the run log"
else
  fail "T4.11: a null-required-key record was written to $NULL_TARGET"
fi

# The two documented exceptions must keep working: `pr: null` is emitted as-is,
# and an explicit `ts: null` is treated as absent and filled from the clock.
set +e
nullable_out="$(printf '%s' '{"ts":null,"issue":251,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":null}' \
  | python3 "$GI_RUNLOG" --echo 2>/dev/null)"
nullable_rc=$?
set -e
if [ "$nullable_rc" -eq 0 ] \
  && printf '%s' "$nullable_out" | grep -qF '"pr":null' \
  && ! printf '%s' "$nullable_out" | grep -qF '"ts":null'; then
  pass "T4.12: 'pr: null' survives and 'ts: null' is filled from the clock"
else
  fail "T4.12: nullable-field handling regressed (rc=$nullable_rc, out: $nullable_out)"
fi

# ───────────────────────────────────────────────────────────
# T5 (AC5): the prose fallback survives in source and in the build
# ───────────────────────────────────────────────────────────
python3 - "$REPO_ROOT" > "$TMP/ac5.txt" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
WIRED = [
    "auto-pilot",
    "issue-analysis",
    "issue-creator",
    "issue-pr-review",
    "issue-resolver",
    "issue-triage",
]
DOTTED_RE = re.compile(r"^[a-z_][a-z0-9_]*(?:\.[a-z0-9_]+)+$")
out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


def configuration_block(path):
    """The '## Configuration' body with fenced blocks removed.

    Fence delimiters are backtick runs; leaving them in shifts the pairing of
    every inline `code span` that follows, which silently empties the defaults
    set instead of failing loudly.
    """
    lines = path.read_text(encoding="utf-8").splitlines()
    start = next(
        (i + 1 for i, l in enumerate(lines) if l.strip() == "## Configuration"), None
    )
    if start is None:
        return None
    body = []
    in_fence = False
    for line in lines[start:]:
        if re.match(r"^##\s", line):
            break
        if re.match(r"^\s*```", line):
            in_fence = not in_fence
            continue
        if not in_fence:
            body.append(line)
    return "\n".join(body)


for name in WIRED:
    for label, path in (
        ("source", root / "src" / "skills" / name / "SKILL.source.md"),
        ("built", root / "skills" / name / "SKILL.md"),
    ):
        block = configuration_block(path) if path.is_file() else None
        if block is None:
            emit(False, f"T5: {name} ({label}) has no '## Configuration' block")
            continue
        defaults = {
            span.split(":", 1)[0].strip()
            for span in re.findall(r"`([^`]+)`", block)
            if DOTTED_RE.fullmatch(span.split(":", 1)[0].strip())
        }
        emit(
            bool(defaults),
            f"T5: {name} ({label}) Configuration keeps its inline defaults "
            f"({len(defaults)} dotted key(s))",
        )
        emit(
            "gi-config unavailable" in block,
            f"T5: {name} ({label}) Configuration keeps the "
            "'gi-config unavailable' degrade path",
        )
        # The degrade path is only safe while these two clauses bound it. Run
        # gi-config from anywhere but the repo root and it exits 0 reporting
        # first_run, silently discarding the repo's real config; treat a missing
        # script file as a degrade and a broken install silently runs on
        # defaults. Both are the same silent-config-discard hole.
        emit(
            "**Working directory:** the repo root" in block,
            f"T5: {name} ({label}) Configuration keeps the "
            "'Working directory: the repo root' requirement",
        )
        emit(
            "Script file absent" in block and "broken install and not a degrade" in block,
            f"T5: {name} ({label}) Configuration keeps the "
            "'script absent = broken install, not a degrade' fatal branch",
        )

# Both run-log writers keep the hand-rolled append as the script's fallback.
for name in ("issue-resolver", "auto-pilot"):
    for label, path in (
        ("source", root / "src" / "skills" / name / "SKILL.source.md"),
        ("built", root / "skills" / name / "SKILL.md"),
    ):
        text = path.read_text(encoding="utf-8") if path.is_file() else ""
        emit(
            "mkdir -p .gitissue" in text,
            f"T5: {name} ({label}) keeps the 'mkdir -p .gitissue' run-log fallback",
        )
        # Exit 3 rejects the record itself, so the fallback must not fire for
        # it — an unqualified "best-effort" degrade would append the very
        # malformed line the script exists to reject.
        emit(
            "**Exit 3:**" in text
            and "Correct the record and re-run, or drop the line." in text,
            f"T5: {name} ({label}) documents the gi-runlog exit-3 stop clause",
        )
        emit(
            "Fallback when `python3` is unavailable or the script exits 4"
            in text,
            f"T5: {name} ({label}) scopes the run-log fallback to exit 4 / no python3",
        )

# phases.md keeps the manual two-step parse the script replaces.
for label, path in (
    ("source", root / "src" / "skills" / "auto-pilot" / "references" / "phases.md"),
    ("built", root / "skills" / "auto-pilot" / "references" / "phases.md"),
):
    text = path.read_text(encoding="utf-8") if path.is_file() else ""
    emit(
        "**Strip cross-repo tokens**" in text and "**Capture bare refs**" in text,
        f"T5: phases.md ({label}) keeps manual steps 1-2 of the dependency parse",
    )
    emit(
        "apply steps 1–2 above by hand" in text,
        f"T5: phases.md ({label}) tells the agent to apply steps 1-2 by hand "
        "when the script cannot run",
    )

print("\n".join(out))
PY
report "$TMP/ac5.txt" "T5: prose fallback"

# ───────────────────────────────────────────────────────────
# T6: modes, byte identity, and --help for every shipped copy
# ───────────────────────────────────────────────────────────
while read -r mode _ _ path; do
  rel="${path#"$REPO_ROOT/"}"
  if [ "$mode" = "100755" ]; then
    pass "T6: git records $rel as 100755"
  else
    fail "T6: git records $rel as $mode (expected 100755)"
  fi
done < <(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/)

src_count=0
for src_script in "$SRC_SCRIPTS"/*.py; do
  [ -f "$src_script" ] || continue
  src_count=$((src_count + 1))
  name="$(basename "$src_script")"
  # The exec bit, never the absolute digits: git stores only the exec bit, so
  # checkout materialises the 100755 blob T6 just verified as 0777 & ~umask —
  # 0o775 under umask 002, 0o755 under 022. The index mode is the real guard.
  src_mode="$(mode_of "$src_script")"
  if has_exec_bit "$src_script"; then
    pass "T6.1: src/shared/scripts/$name is executable on disk (mode $src_mode)"
  else
    fail "T6.1: src/shared/scripts/$name is not executable (mode $src_mode)"
  fi

  set +e
  python3 "$src_script" --help >/dev/null 2>&1
  help_rc=$?
  set -e
  if [ "$help_rc" -eq 0 ]; then
    pass "T6.2: $name --help exits 0"
  else
    fail "T6.2: $name --help exited $help_rc"
  fi

  copies=0
  while IFS= read -r shipped; do
    copies=$((copies + 1))
    rel="${shipped#"$REPO_ROOT/"}"
    if cmp -s "$src_script" "$shipped"; then
      pass "T6.3: $rel is byte-identical to its source"
    else
      fail "T6.3: $rel differs from src/shared/scripts/$name"
    fi
    shipped_mode="$(mode_of "$shipped")"
    if [ "$shipped_mode" = "$src_mode" ]; then
      pass "T6.4: $rel has the source's mode ($shipped_mode)"
    else
      fail "T6.4: $rel is mode $shipped_mode, source is $src_mode"
    fi
  done < <(find "$SKILLS" -type f -path '*/references/scripts/*' -name "$name" | sort)

  if [ "$copies" -gt 0 ]; then
    pass "T6.5: $name is bundled into $copies skill(s)"
  else
    fail "T6.5: $name is bundled into no skill — it ships nowhere"
  fi
done

if [ "$src_count" -gt 0 ]; then
  pass "T6.6: src/shared/scripts/ holds $src_count script(s)"
else
  fail "T6.6: src/shared/scripts/ is empty — the whole suite would pass vacuously"
fi

# ───────────────────────────────────────────────────────────
# T7: gi-config's vendored parser agrees with scripts/build.py's
# ───────────────────────────────────────────────────────────
# gi-config.py cannot import from the build tree (it ships inside installed
# skills), so it carries a verbatim copy of build.py's restricted-YAML parser.
# A silent divergence would make the script resolve different defaults than the
# build validates — this is the only thing keeping the copy honest.
# PYTHONDONTWRITEBYTECODE: the importlib exec_module calls below would otherwise
# drop __pycache__/ directories into src/shared/scripts/ and scripts/. Both are
# gitignored, but a test has no business writing into src/.
PYTHONDONTWRITEBYTECODE=1 python3 - "$REPO_ROOT" > "$TMP/parity.txt" <<'PY'
import importlib.util
import sys
from pathlib import Path

root = Path(sys.argv[1])
out = []


def emit(ok, label):
    out.append(("PASS" if ok else "FAIL") + "|" + label)


def load(module_name, path):
    spec = importlib.util.spec_from_file_location(module_name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


build = load("idd_build_parity", root / "scripts" / "build.py")
gi_config = load("idd_gi_config", root / "src" / "shared" / "scripts" / "gi-config.py")

emit(
    build._FULL_SCHEMA_FENCE_RE.pattern == gi_config._FULL_SCHEMA_FENCE_RE.pattern,
    "T7: both parsers use the same Full Schema fence pattern",
)

schema_text = (root / "docs" / "config-schema.md").read_text(encoding="utf-8")
match = build._FULL_SCHEMA_FENCE_RE.search(schema_text)
if match is None:
    emit(False, "T7.1: docs/config-schema.md has no Full Schema fence")
else:
    fence = match.group(1)
    build_map = build._parse_config_mapping(fence, "config-schema.md")
    gi_map = gi_config._parse_config_mapping(fence, "config-schema.md")
    emit(bool(build_map), f"T7.1: the Full Schema fence parses to {len(build_map)} key(s)")
    emit(
        build_map == gi_map,
        "T7.2: build.py and gi-config.py agree on docs/config-schema.md's defaults",
    )

template = root / "src" / "skills" / "init-gitissue" / "templates" / "gitissue-template.yml"
if not template.is_file():
    emit(False, "T7.3: the init-gitissue template is missing")
else:
    text = template.read_text(encoding="utf-8")
    build_map = build._parse_config_mapping(text, template.name)
    gi_map = gi_config._parse_config_mapping(text, template.name)
    emit(bool(build_map), f"T7.3: the init template parses to {len(build_map)} key(s)")
    emit(
        build_map == gi_map,
        "T7.4: build.py and gi-config.py agree on the init-gitissue template",
    )

print("\n".join(out))
PY
report "$TMP/parity.txt" "T7: parser equivalence"

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Shared scripts pipeline tests failed"
  exit 1
fi

echo "  ✓ Shared scripts pipeline is wired, shipped, and executable"
exit 0
