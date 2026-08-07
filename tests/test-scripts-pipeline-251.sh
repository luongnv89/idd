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
if grep -rqF 'dependency_gate_parse' \
     "$REPO_ROOT/src" "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$REPO_ROOT/docs" 2>/dev/null; then
  fail "T2: the 'dependency_gate_parse' dev-tree literal still exists"
  grep -rlF 'dependency_gate_parse' \
    "$REPO_ROOT/src" "$REPO_ROOT/skills" "$REPO_ROOT/scripts" "$REPO_ROOT/docs" \
    2>/dev/null | sed "s|$REPO_ROOT/|    |"
else
  pass "T2: no 'dependency_gate_parse' literal under src/, skills/, scripts/, docs/"
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
# T4 (AC4): gi-runlog echo/append/normalize/reject
# ───────────────────────────────────────────────────────────
GI_RUNLOG="$SKILLS/issue-resolver/references/scripts/gi-runlog.py"
RECORD='{"issue":251,"mode":"auto","skill":"issue-resolver","outcome":"success","pr":270,"complexity":"complex"}'

ECHO_TARGET="$TMP/echo-must-not-exist/runs.jsonl"
set +e
echo_out="$(printf '%s' "$RECORD" | python3 "$GI_RUNLOG" --echo --path "$ECHO_TARGET" 2>"$TMP/echo.err")"
echo_rc=$?
set -e
if [ "$echo_rc" -eq 0 ]; then
  pass "T4: gi-runlog --echo exits 0 on a valid record"
else
  fail "T4: gi-runlog --echo exited $echo_rc (expected 0)"
  sed 's/^/    /' "$TMP/echo.err"
fi
if [ "$(printf '%s\n' "$echo_out" | wc -l | tr -d ' ')" = "1" ]; then
  pass "T4.1: gi-runlog --echo prints exactly one line"
else
  fail "T4.1: gi-runlog --echo printed $(printf '%s\n' "$echo_out" | wc -l | tr -d ' ') lines"
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
  src_mode="$(mode_of "$src_script")"
  if [ "$src_mode" = "0o755" ]; then
    pass "T6.1: src/shared/scripts/$name is mode 0755 on disk"
  else
    fail "T6.1: src/shared/scripts/$name is mode $src_mode (expected 0o755)"
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
python3 - "$REPO_ROOT" > "$TMP/parity.txt" <<'PY'
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
