#!/usr/bin/env bash
# test-scripts-253.sh — Issue #253 acceptance checks for the third wave of
# shared scripts (gi-triage-graph, gi-stack-detect, gi-model-cache).
#
# AC1 (deterministic duplicate scoring) is deliberately not covered here:
# `gi-dup-score.py` was removed from this change set and stays open on #253,
# to be redone against a corrected scoring model. Nothing below refers to it.
#
# Acceptance criteria covered:
#   AC2  Triage ordering is produced by a script emitting the same cache payload
#        shape; keyword extraction stays with the agents.
#   AC3  init-gitissue detection runs scripted with an LLM fallback on unknown
#        stacks.
#   AC4  The model-cache lifecycle runs scripted; its reference doc becomes
#        refresh/debug-only reading.
#   AC5  Every replaced prose procedure survives as a documented fallback, and
#        no untrusted value reaches a shared-script command line.
#
# The behavioral halves run each script directly out of src/shared/scripts/ —
# the build already asserts the shipped copies are byte-identical, so testing
# one file proves both and keeps this suite independent of build order. The
# wiring halves read the *built* skills, because what ships is what runs.
#
# Usage: bash tests/test-scripts-253.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_SCRIPTS="$REPO_ROOT/src/shared/scripts"
SKILLS="$REPO_ROOT/skills"
SRC="$REPO_ROOT/src"
GRAPH="$SRC_SCRIPTS/gi-triage-graph.py"
STACK="$SRC_SCRIPTS/gi-stack-detect.py"
MODEL="$SRC_SCRIPTS/gi-model-cache.py"

NEW_SCRIPTS="gi-triage-graph gi-stack-detect gi-model-cache"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run a command, capturing stdout and the exit status without tripping `set -e`.
run_status() {
  local __out_var="$1"; shift
  local __status_var="$1"; shift
  local __out __status=0
  __out="$("$@" 2>/dev/null)" || __status=$?
  printf -v "$__out_var" '%s' "$__out"
  printf -v "$__status_var" '%s' "$__status"
}

# Read one key (dotted path supported) out of a JSON object on stdin.
jkey() {
  python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for part in sys.argv[1].split("."):
    d = d[int(part)] if part.isdigit() else d[part]
print(d)
' "$1"
}

echo "◆ Shared Scripts, Wave 3 (issue #253)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T0: all three scripts exist, are executable, and --help exits 0
# ───────────────────────────────────────────────────────────
for s in $NEW_SCRIPTS; do
  path="$SRC_SCRIPTS/$s.py"
  if [ ! -f "$path" ]; then
    fail "$s.py exists"
    continue
  fi
  # Git records only the exec bit, and checkout applies the umask, so assert
  # the bit rather than an absolute mode.
  if python3 -c 'import os,sys;sys.exit(0 if os.stat(sys.argv[1]).st_mode & 0o111 else 1)' "$path"; then
    pass "$s.py is executable"
  else
    fail "$s.py is executable"
  fi
  if python3 "$path" --help >/dev/null 2>&1; then
    pass "$s.py --help exits 0"
  else
    fail "$s.py --help exits 0"
  fi
  # Stdlib only: an import of a third-party package would break every install.
  if grep -qE '^(import|from) (yaml|requests|jinja2|numpy|pydantic)\b' "$path"; then
    fail "$s.py imports a third-party package"
  else
    pass "$s.py is stdlib-only"
  fi
done

while IFS= read -r line; do
  mode="${line%% *}"
  file="${line##*	}"
  case "$file" in
    *gi-triage-graph.py|*gi-stack-detect.py|*gi-model-cache.py)
      if [ "$mode" = "100755" ]; then
        pass "$(basename "$file") is committed 0755"
      else
        fail "$(basename "$file") is committed $mode, expected 100755"
      fi
      ;;
  esac
done < <(cd "$REPO_ROOT" && git ls-files -s src/shared/scripts/)

# ───────────────────────────────────────────────────────────
# T2 (AC2): gi-triage-graph — the documented payload, computed
# ───────────────────────────────────────────────────────────
SCAN="$TMP/scan.json"
cat > "$SCAN" <<'EOF'
{"issues":[
 {"number":12,"title":"Fix auth redirect","type":"bug","labels":["bug","auth"],
  "createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-03-18T10:00:00Z",
  "affected_files":["auth.py","middleware.py"]},
 {"number":8,"title":"Add pagination","type":"feature","labels":["feature"],
  "createdAt":"2026-01-05T00:00:00Z","updatedAt":"2026-03-19T10:00:00Z",
  "affected_files":["list.py"]},
 {"number":15,"title":"Refactor DB","type":"improvement","labels":[],
  "createdAt":"2026-02-01T00:00:00Z","updatedAt":"2026-03-10T10:00:00Z",
  "affected_files":["auth.py"]},
 {"number":3,"title":"Old UI bug","type":"bug","labels":[],
  "createdAt":"2025-11-01T00:00:00Z","updatedAt":"2026-02-20T10:00:00Z",
  "affected_files":["ui.py"]},
 {"number":21,"title":"Session timeout","type":"bug","labels":[],
  "createdAt":"2026-02-10T00:00:00Z","updatedAt":"2026-03-19T00:00:00Z",
  "affected_files":["session.py"],
  "potentially_fixed_by":{"pr":43,"confidence":"high","target_issue":42}}],
 "edges":[{"a":12,"b":15}]}
EOF

graph() { python3 "$GRAPH" --no-config --now 2026-03-20T14:30:00Z "$@" < "$SCAN"; }

out="$(graph)"
if [ "$(printf '%s' "$out" | jkey 'summary.suggested_order.0')" = "3" ] \
   && [ "$(printf '%s' "$out" | jkey 'summary.suggested_order.4')" = "21" ]; then
  pass "AC2: topological order applies the tie-breaks and sinks maybe-fixed last"
else
  fail "AC2: execution order is wrong (got: $(printf '%s' "$out" | jkey 'summary.suggested_order'))"
fi

for probe in '15|status|blocked' '15|blocked_by.0|12' '12|blocks.0|15' \
             '3|status|stale' '3|stale_days|28' '21|status|maybe-fixed' \
             '12|priority|P1' '8|priority|P3' '15|priority|P3'; do
  num="${probe%%|*}"; rest="${probe#*|}"; key="${rest%%|*}"; want="${rest##*|}"
  got="$(printf '%s' "$out" | python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
issue = next(i for i in d["issues"] if i["number"] == int(sys.argv[1]))
for part in sys.argv[2].split("."):
    issue = issue[int(part)] if part.isdigit() else issue[part]
print(issue)
' "$num" "$key")"
  if [ "$got" = "$want" ]; then
    pass "AC2: #$num $key = $want"
  else
    fail "AC2: #$num $key = $want (got $got)"
  fi
done

# Parallel sets must exclude the pair that shares auth.py, and the blocked issue
# is not at the same level as its blocker.
groups="$(printf '%s' "$out" | jkey 'summary.parallel_groups')"
case "$groups" in
  *15*) fail "AC2: a blocked issue was grouped as parallelizable ($groups)" ;;
  *12*) pass "AC2: parallel groups are same-level, edge-free and file-disjoint" ;;
  *) fail "AC2: no parallel group was identified ($groups)" ;;
esac

# The payload must carry exactly the documented schema — parsed out of the
# reference document, so the two cannot drift apart silently.
PERSIST="$SRC/skills/issue-triage/references/output-and-persist.md"
cat > "$TMP/schema-check.py" <<'PY'
import json, re, sys
payload = json.loads(sys.stdin.read())
doc = open(sys.argv[1], encoding="utf-8").read()
documented = set(re.findall(r"^\| `([A-Za-z_][\w\[\].]*)`", doc, re.M))
top = {f"{k}" for k in payload}
missing_top = {k for k in ("version", "updated", "source", "analyzed_count",
                           "issues[]", "history[]") if k not in documented}
summary = {f"summary.{k}" for k in payload["summary"]}
issues = {f"issues[].{k}" for k in payload["issues"][0]}
gaps = sorted((summary | issues) - documented) + sorted(missing_top)
if gaps:
    print("undocumented payload key(s): " + ", ".join(gaps))
    sys.exit(1)
holes = sorted(k for k in documented
               if k.startswith(("summary.", "issues[].")) and k not in (summary | issues))
if holes:
    print("documented but absent from the payload: " + ", ".join(holes))
    sys.exit(1)
sys.exit(0)
PY
if printf '%s' "$out" | python3 "$TMP/schema-check.py" "$PERSIST"; then
  pass "AC2: the payload keys are exactly those output-and-persist.md documents"
else
  fail "AC2: the payload and the documented schema have drifted"
fi

# Cycles are detected, reported, and broken — never fatal.
CYC="$TMP/cyc.json"
cat > "$CYC" <<'EOF'
{"issues":[{"number":1,"title":"a","type":"bug","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-03-19T00:00:00Z"},
           {"number":2,"title":"b","type":"bug","createdAt":"2026-01-02T00:00:00Z","updatedAt":"2026-03-19T00:00:00Z"}],
 "edges":[{"from":1,"to":2},{"from":2,"to":1}]}
EOF
out2="$(python3 "$GRAPH" --no-config --now 2026-03-20T00:00:00Z < "$CYC")"
if [ "$(printf '%s' "$out2" | jkey 'summary.circular_deps.0.0')" = "1" ] \
   && [ "$(printf '%s' "$out2" | jkey 'summary.suggested_order')" = "[1, 2]" ]; then
  pass "AC2: a cycle is reported and broken, and every issue still gets ordered"
else
  fail "AC2: cycle handling is wrong (got: $out2)"
fi

# Determinism: identical input, identical bytes. Same reason as AC1.
if [ "$(graph)" = "$(graph)" ]; then
  pass "AC2: the payload is deterministic across runs"
else
  fail "AC2: the payload changes between identical runs"
fi

# Config-driven staleness and the auto_priority: false contract.
TCFG="$TMP/tcfg"
mkdir -p "$TCFG"
printf 'triage:\n  stale_threshold_days: 60\n  auto_priority: false\n' > "$TCFG/.gitissue.yml"
out3="$(python3 "$GRAPH" --config "$TCFG/.gitissue.yml" --now 2026-03-20T14:30:00Z < "$SCAN")"
if [ "$(printf '%s' "$out3" | jkey 'summary.stale_count')" = "0" ] \
   && [ "$(printf '%s' "$out3" | jkey 'summary.stale_threshold_days')" = "60" ] \
   && [ "$(printf '%s' "$out3" | jkey 'issues.0.priority')" = "None" ]; then
  pass "AC2: triage.stale_threshold_days and triage.auto_priority are honoured"
else
  fail "AC2: triage.* config is ignored"
fi

# Undirected scanner edges are directed by the documented heuristics.
UND="$TMP/und.json"
cat > "$UND" <<'EOF'
{"issues":[{"number":5,"title":"older","type":"feature","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-03-19T00:00:00Z","affected_files":["x.py"]},
           {"number":6,"title":"newer","type":"bug","createdAt":"2026-02-01T00:00:00Z","updatedAt":"2026-03-19T00:00:00Z","affected_files":["x.py"]}],
 "edges":[{"a":6,"b":5}]}
EOF
out4="$(python3 "$GRAPH" --no-config --now 2026-03-20T00:00:00Z < "$UND")"
if [ "$(printf '%s' "$out4" | jkey 'summary.suggested_order.0')" = "5" ]; then
  pass "AC2: an undirected edge is directed by creation date, not by input order"
else
  fail "AC2: undirected edge direction ignores createdAt"
fi

# Exit-code vocabulary: 3 is a stop, and never swallowed by a degrade.
run_status out st bash -c "printf '{\"issues\":[{\"title\":\"no number\"}]}' | python3 '$GRAPH' --no-config"
[ "$st" = "3" ] && pass "AC2: an issue without a number exits 3" \
                || fail "AC2: an issue without a number exits 3 (got $st)"
run_status out st bash -c "printf '{\"issues\":[{\"number\":1}],\"edges\":[{\"a\":1,\"b\":77}]}' | python3 '$GRAPH' --no-config"
[ "$st" = "3" ] && pass "AC2: an edge naming an unknown issue exits 3" \
                || fail "AC2: an edge naming an unknown issue exits 3 (got $st)"
run_status out st bash -c "printf '{\"issues\":[{\"number\":1,\"updatedAt\":\"not-a-date\"}]}' | python3 '$GRAPH' --no-config"
[ "$st" = "3" ] && pass "AC2: an unparsable timestamp exits 3, never a silent 'fresh'" \
                || fail "AC2: an unparsable timestamp exits 3 (got $st)"
run_status out st bash -c "printf '{}' | python3 '$GRAPH' --no-config"
[ "$st" = "3" ] && pass "AC2: a request with no issues array exits 3" \
                || fail "AC2: a request with no issues array exits 3 (got $st)"

# Exit 4 is delivery, not computation: the payload still reaches stdout.
run_status out st bash -c "python3 '$GRAPH' --no-config --now 2026-03-20T00:00:00Z --out /proc/nonexistent/dir/t.json < '$SCAN'"
if [ "$st" = "4" ] && printf '%s' "$out" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  pass "AC2: an unwritable --out exits 4 but still prints the payload"
else
  fail "AC2: an unwritable --out exits 4 with the payload on stdout (got $st)"
fi

# --out really persists, so Step 9 is the same call.
run_status out st bash -c "python3 '$GRAPH' --no-config --now 2026-03-20T00:00:00Z --out '$TMP/persisted/triage.json' < '$SCAN'"
if [ "$st" = "0" ] && python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$TMP/persisted/triage.json" 2>/dev/null; then
  pass "AC2: --out writes a parsable .gitissue/triage.json (Step 9 is the same call)"
else
  fail "AC2: --out did not persist a parsable payload (exit $st)"
fi

# Injection: a title carrying shell syntax must be inert.
INJ2="$TMP/inj-graph"
mkdir -p "$INJ2"
(
  cd "$INJ2"
  printf '{"issues":[{"number":1,"title":"x\\"; touch PWNED; echo \\"","createdAt":"2026-01-01T00:00:00Z","updatedAt":"2026-01-01T00:00:00Z"}]}' \
    | python3 "$GRAPH" --no-config --now 2026-03-20T00:00:00Z >/dev/null 2>&1
) || true
[ ! -e "$INJ2/PWNED" ] && pass "AC2: a quote-bearing issue title cannot execute" \
                       || fail "AC2: a crafted issue title executed a command — injection"

# ───────────────────────────────────────────────────────────
# T3 (AC3): gi-stack-detect — the tables, and the LLM fallback signal
# ───────────────────────────────────────────────────────────
TS="$TMP/ts-repo"
mkdir -p "$TS/.github/ISSUE_TEMPLATE"
cat > "$TS/package.json" <<'EOF'
{"dependencies": {"next": "15.0.0", "react": "19.0.0"},
 "devDependencies": {"typescript": "5.5.0", "jest": "29.0.0"}}
EOF
printf '{}\n' > "$TS/jest.config.js"
printf 'a\n' > "$TS/.github/ISSUE_TEMPLATE/bug.yml"
printf 'a\n' > "$TS/.github/ISSUE_TEMPLATE/feature.yml"
out="$(python3 "$STACK" --root "$TS")"
if [ "$(printf '%s' "$out" | jkey language)" = "TypeScript" ] \
   && [ "$(printf '%s' "$out" | jkey framework)" = "Next.js" ] \
   && [ "$(printf '%s' "$out" | jkey test_runner)" = "Jest" ] \
   && [ "$(printf '%s' "$out" | jkey issue_templates)" = "2" ] \
   && [ "$(printf '%s' "$out" | jkey 'derived.auto_test')" = "True" ]; then
  pass "AC3: a TypeScript + Next.js + Jest repo is detected end to end"
else
  fail "AC3: TypeScript/Next.js/Jest detection is wrong (got: $out)"
fi
# `next` must beat `react`: every Next.js project carries react too.
if [ "$(printf '%s' "$out" | jkey framework)" = "Next.js" ]; then
  pass "AC3: the more specific framework wins over its transitive dependency"
else
  fail "AC3: react shadowed Next.js"
fi

PY_REPO="$TMP/py-repo"
mkdir -p "$PY_REPO"
printf 'django==5.0\n' > "$PY_REPO/requirements.txt"
printf '[tool.pytest.ini_options]\n' > "$PY_REPO/pyproject.toml"
out="$(python3 "$STACK" --root "$PY_REPO")"
if [ "$(printf '%s' "$out" | jkey language)" = "Python" ] \
   && [ "$(printf '%s' "$out" | jkey framework)" = "Django" ] \
   && [ "$(printf '%s' "$out" | jkey test_runner)" = "pytest" ]; then
  pass "AC3: a Python + Django + pytest repo is detected end to end"
else
  fail "AC3: Python/Django/pytest detection is wrong (got: $out)"
fi

# The LLM fallback signal: unknown is `null` + a name in `unresolved`, exit 0.
# Guessing to avoid an empty field would remove the caller's only cue to fall
# back to the prose tables.
EMPTY="$TMP/empty-repo"
mkdir -p "$EMPTY"
printf 'hello\n' > "$EMPTY/README.md"
run_status out st python3 "$STACK" --root "$EMPTY"
if [ "$st" = "0" ] \
   && [ "$(printf '%s' "$out" | jkey language)" = "None" ] \
   && [ "$(printf '%s' "$out" | jkey unresolved)" = "['language', 'framework', 'test_runner']" ]; then
  pass "AC3: an unrecognized stack is exit 0 with nulls and a full unresolved list"
else
  fail "AC3: an unrecognized stack does not signal the LLM fallback (exit $st, out=$out)"
fi
if [ "$(printf '%s' "$out" | jkey 'derived.auto_test')" = "False" ] \
   && [ "$(printf '%s' "$out" | jkey 'derived.stale_threshold_days')" = "7" ] \
   && [ "$(printf '%s' "$out" | jkey 'derived.test_timeout')" = "60" ]; then
  pass "AC3: the derived Step 2 defaults follow the size band and the runner"
else
  fail "AC3: the derived defaults are wrong (got: $out)"
fi

# Size bands, and the honest report of which count was used.
python3 -c '
import os, sys
root = sys.argv[1]
for n in range(150):
    open(os.path.join(root, "f%d.txt" % n), "w").write("x")
' "$EMPTY"
out="$(python3 "$STACK" --root "$EMPTY")"
if [ "$(printf '%s' "$out" | jkey repo_size)" = "medium" ] \
   && [ "$(printf '%s' "$out" | jkey file_count_source)" = "filesystem walk" ]; then
  pass "AC3: the size band follows the count, and the count names its own source"
else
  fail "AC3: size band / file_count_source wrong (got: $out)"
fi

# The tables are overridable for a stack the defaults do not describe.
RULES="$TMP/rules.json"
printf '{"language": [["deno.json", "Deno"]], "framework": [["oak", "Oak"]]}\n' > "$RULES"
DENO="$TMP/deno-repo"
mkdir -p "$DENO"
printf '{"imports": {"oak": "jsr:@oak/oak"}}\n' > "$DENO/deno.json"
printf 'oak\n' > "$DENO/package.json"
out="$(python3 "$STACK" --root "$DENO" --rules "$RULES")"
if [ "$(printf '%s' "$out" | jkey language)" = "Deno" ]; then
  pass "AC3: --rules replaces a built-in detection table"
else
  fail "AC3: --rules is ignored (got: $out)"
fi

run_status out st python3 "$STACK" --root "$TMP/no-such-dir"
[ "$st" = "3" ] && pass "AC3: a non-directory --root exits 3" \
                || fail "AC3: a non-directory --root exits 3 (got $st)"
printf 'not json\n' > "$TMP/badrules.json"
run_status out st python3 "$STACK" --root "$EMPTY" --rules "$TMP/badrules.json"
[ "$st" = "3" ] && pass "AC3: an unparsable --rules file exits 3" \
                || fail "AC3: an unparsable --rules file exits 3 (got $st)"
printf '{"language": ["nope"]}\n' > "$TMP/shaperules.json"
run_status out st python3 "$STACK" --root "$EMPTY" --rules "$TMP/shaperules.json"
[ "$st" = "3" ] && pass "AC3: a wrongly-shaped --rules table exits 3" \
                || fail "AC3: a wrongly-shaped --rules table exits 3 (got $st)"

# A dependency file is attacker-controlled on a fork; its bytes must be data.
INJ3="$TMP/inj-stack"
mkdir -p "$INJ3"
printf '{"dependencies": {"react": "1.0"}, "x": "\\"; touch PWNED; echo \\""}\n' > "$INJ3/package.json"
( cd "$INJ3" && python3 "$STACK" --root . >/dev/null 2>&1 ) || true
[ ! -e "$INJ3/PWNED" ] && pass "AC3: a crafted dependency file cannot execute" \
                       || fail "AC3: a crafted dependency file executed a command — injection"

# ───────────────────────────────────────────────────────────
# T4 (AC4): gi-model-cache — the lifecycle, and the no-substitution rule
# ───────────────────────────────────────────────────────────
SEED_SRC="$SRC/skills/issue-creator/templates/model-data.json"
new_skill_dir() {
  local d="$1"
  mkdir -p "$d/templates"
  cp "$SEED_SRC" "$d/templates/model-data.json"
}

SK1="$TMP/skill1"
new_skill_dir "$SK1"
out="$(python3 "$MODEL" --skill-dir "$SK1" --no-config --now 2026-06-14)"
if [ "$(printf '%s' "$out" | jkey state)" = "seeded" ] \
   && [ "$(printf '%s' "$out" | jkey data_date)" = "2026-06-12" ] \
   && [ -f "$SK1/model-data-2026-06-12.json" ]; then
  pass "AC4: a missing cache is seeded under the SEED's own date, not today's"
else
  fail "AC4: seeding is wrong (got: $out)"
fi

out="$(python3 "$MODEL" --skill-dir "$SK1" --no-config --now 2026-06-14)"
if [ "$(printf '%s' "$out" | jkey state)" = "fresh" ] \
   && [ "$(printf '%s' "$out" | jkey stale)" = "False" ] \
   && [ "$(printf '%s' "$out" | jkey age_days)" = "2" ]; then
  pass "AC4: a cache inside the TTL is fresh"
else
  fail "AC4: a fresh cache is misreported (got: $out)"
fi
out="$(python3 "$MODEL" --skill-dir "$SK1" --no-config --now 2026-07-30)"
if [ "$(printf '%s' "$out" | jkey state)" = "stale" ] \
   && [ "$(printf '%s' "$out" | jkey stale)" = "True" ]; then
  pass "AC4: a cache past the TTL is stale (a warning, not a failure)"
else
  fail "AC4: a stale cache is misreported (got: $out)"
fi

# The bands are what the rendering rule needs, with per-model costs that are
# never summed — the two picks are alternatives.
if [ "$(printf '%s' "$out" | jkey 'bands.M.openai')" = "GPT-5.5 High" ] \
   && [ "$(printf '%s' "$out" | jkey 'bands.M.anthropic')" = "Opus 4.8 Medium" ] \
   && [ "$(printf '%s' "$out" | jkey 'bands.M.openai_cost')" = "3.59" ] \
   && [ "$(printf '%s' "$out" | jkey 'bands.M.anthropic_cost')" = "3.83" ] \
   && [ "$(printf '%s' "$out" | jkey data_version)" = "3.1" ]; then
  pass "AC4: the effort bands carry both picks and each pick's own cost"
else
  fail "AC4: the band mapping is wrong (got: $out)"
fi

# TTL is config-overridable through .gitissue.yml.
MCFG="$TMP/mcfg"
mkdir -p "$MCFG"
printf 'model_suggestion:\n  cache_ttl_days: 60\n' > "$MCFG/.gitissue.yml"
out="$(python3 "$MODEL" --skill-dir "$SK1" --config "$MCFG/.gitissue.yml" --now 2026-07-30)"
[ "$(printf '%s' "$out" | jkey stale)" = "False" ] \
  && pass "AC4: model_suggestion.cache_ttl_days from .gitissue.yml is honoured" \
  || fail "AC4: model_suggestion.cache_ttl_days is ignored"

# --install writes the new dated file AND prunes every other one.
printf 'x\n' > "$SK1/model-data-2020-01-01.json"
NEWDATA="$TMP/newdata.json"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["last_fetched"] = "2026-08-01T00:00:00Z"
json.dump(d, open(sys.argv[2], "w"))
' "$SEED_SRC" "$NEWDATA"
out="$(python3 "$MODEL" --skill-dir "$SK1" --no-config --install "$NEWDATA" --now 2026-08-02)"
remaining="$(ls "$SK1" | grep -c '^model-data-' || true)"
if [ "$(printf '%s' "$out" | jkey state)" = "installed" ] \
   && [ -f "$SK1/model-data-2026-08-01.json" ] && [ "$remaining" = "1" ]; then
  pass "AC4: --install writes the dated cache and prunes every older copy"
else
  fail "AC4: --install left $remaining dated file(s) (got: $out)"
fi

# ── Fail closed: a corrupt cache is NOT silently replaced by the seed ────────
# Reseeding there would report a refresh the user never got, and would throw
# away their refreshed data. Exit 4 and leave the file alone.
SK2="$TMP/skill2"
new_skill_dir "$SK2"
printf 'not json at all\n' > "$SK2/model-data-2026-06-12.json"
run_status out st python3 "$MODEL" --skill-dir "$SK2" --no-config --now 2026-06-14
seeded_over="$(ls "$SK2" | grep -c '^model-data-' || true)"
if [ "$st" = "4" ] && [ "$seeded_over" = "1" ] \
   && grep -q 'not json at all' "$SK2/model-data-2026-06-12.json"; then
  pass "AC4: a corrupt cache exits 4 and is never overwritten by the bundled seed"
else
  fail "AC4: a corrupt cache was silently replaced (exit $st, files=$seeded_over)"
fi

# No cache and no seed is the documented "disable suggestions" degrade.
SK3="$TMP/skill3"
mkdir -p "$SK3"
run_status out st python3 "$MODEL" --skill-dir "$SK3" --no-config
[ "$st" = "4" ] && pass "AC4: no cache and no bundled seed exits 4 (degrade, keep creating)" \
                || fail "AC4: no cache and no seed exits 4 (got $st)"

# An --install payload that is not model data must not clobber a good cache.
SK4="$TMP/skill4"
new_skill_dir "$SK4"
python3 "$MODEL" --skill-dir "$SK4" --no-config --now 2026-06-14 >/dev/null
printf '{"hello": 1}\n' > "$TMP/junk.json"
run_status out st python3 "$MODEL" --skill-dir "$SK4" --no-config --install "$TMP/junk.json"
if [ "$st" = "3" ] && [ -f "$SK4/model-data-2026-06-12.json" ]; then
  pass "AC4: a non-model-data --install payload exits 3 and leaves the cache intact"
else
  fail "AC4: a junk --install payload exits 3 without clobbering (got $st)"
fi

# ── A shape-valid but IMPOSSIBLE date in the fetched payload ────────────────
# `2026-02-30` matches `^\d{4}-\d{2}-\d{2}` and is not a date. The payload is
# fetched web content, so an attacker who controls the fetched bytes picks it.
# Three separate things must hold, and each one failed before this guard:
#   1. exit 3, not a bare 1 — no call site classifies 1, so an exit-1 traceback
#      leaves the agent with no documented instruction at all.
#   2. the good cache survives, which is what the --install call site in
#      references/model-suggestion.md promises ("the old cache is untouched").
#   3. the *next* ordinary run still works. Writing the poison first bricked
#      the cache permanently: every later run re-read it and re-crashed, and
#      the script deliberately never reseeds over a cache it cannot read.
SK5="$TMP/skill5"
new_skill_dir "$SK5"
python3 "$MODEL" --skill-dir "$SK5" --no-config --now 2026-06-14 >/dev/null
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["last_fetched"] = "2026-02-30T00:00:00Z"
json.dump(d, open(sys.argv[2], "w"))
' "$SEED_SRC" "$TMP/impossible-date.json"
run_status out st python3 "$MODEL" --skill-dir "$SK5" --no-config \
  --install "$TMP/impossible-date.json"
[ "$st" = "3" ] && pass "AC4: an impossible last_fetched date in --install exits 3, not 1" \
                || fail "AC4: an impossible --install date exits 3 (got $st)"
if [ -f "$SK5/model-data-2026-06-12.json" ] \
   && [ ! -f "$SK5/model-data-2026-02-30.json" ]; then
  pass "AC4: an impossible --install date leaves the existing cache untouched"
else
  fail "AC4: an impossible --install date clobbered the cache ($(ls "$SK5"))"
fi
run_status out st python3 "$MODEL" --skill-dir "$SK5" --no-config --now 2026-06-14
[ "$st" = "0" ] && pass "AC4: the run after a rejected --install date still succeeds" \
                || fail "AC4: a rejected --install date bricked the cache (got $st)"

# The same impossible date already sitting in a cache degrades (4), never 1.
SK6="$TMP/skill6"
new_skill_dir "$SK6"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["last_fetched"] = "2026-02-30T00:00:00Z"
json.dump(d, open(sys.argv[2], "w"))
' "$SEED_SRC" "$SK6/model-data-2026-02-30.json"
run_status out st python3 "$MODEL" --skill-dir "$SK6" --no-config --now 2026-06-14
[ "$st" = "4" ] && pass "AC4: an impossible date in an existing cache exits 4, not 1" \
                || fail "AC4: an impossible cached date exits 4 (got $st)"

# And the same shape on the flag that supplies "today".
run_status out st python3 "$MODEL" --skill-dir "$SK1" --no-config --now 2026-02-30
[ "$st" = "3" ] && pass "AC4: an impossible --now date exits 3, not 1" \
                || fail "AC4: an impossible --now date exits 3 (got $st)"

run_status out st python3 "$MODEL" --skill-dir "$TMP/no-such-skill-dir" --no-config
[ "$st" = "3" ] && pass "AC4: a non-directory --skill-dir exits 3" \
                || fail "AC4: a non-directory --skill-dir exits 3 (got $st)"
run_status out st python3 "$MODEL" --skill-dir "$SK1" --no-config --ttl-days -1
[ "$st" = "3" ] && pass "AC4: a negative --ttl-days exits 3" \
                || fail "AC4: a negative --ttl-days exits 3 (got $st)"
run_status out st python3 "$MODEL"
[ "$st" = "2" ] && pass "AC4: a missing --skill-dir exits 2 (usage)" \
                || fail "AC4: a missing --skill-dir exits 2 (got $st)"

# Refreshed data comes from the network; it must arrive by file or stdin.
INJ4="$TMP/inj-model"
mkdir -p "$INJ4"
SK5="$TMP/skill5"
new_skill_dir "$SK5"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["last_fetched"] = "2026-08-03T00:00:00Z"
d["source"] = "CursorBench 3.1\"; touch " + sys.argv[3] + "/PWNED; echo \""
json.dump(d, open(sys.argv[2], "w"))
' "$SEED_SRC" "$TMP/evil.json" "$INJ4"
( cd "$INJ4" && python3 "$MODEL" --skill-dir "$SK5" --no-config --install - < "$TMP/evil.json" >/dev/null 2>&1 ) || true
[ ! -e "$INJ4/PWNED" ] && pass "AC4: crafted fetched content cannot execute (stdin/file, never a command line)" \
                       || fail "AC4: crafted model data executed a command — injection"

# ───────────────────────────────────────────────────────────
# T5 (AC5): wiring — the built skills call the scripts and keep a fallback
# ───────────────────────────────────────────────────────────
expect_bundled() {
  local skill="$1" script="$2"
  if [ -f "$SKILLS/$skill/references/scripts/$script" ]; then
    pass "AC5: $skill bundles $script"
  else
    fail "AC5: $skill bundles $script"
  fi
}
expect_bundled issue-creator gi-model-cache.py
expect_bundled issue-triage gi-triage-graph.py
expect_bundled auto-pilot gi-triage-graph.py
expect_bundled init-gitissue gi-stack-detect.py

expect_grep() {
  local label="$1" pattern="$2" file="$3"
  if grep -q -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label"
  fi
}
expect_grep "AC2: issue-triage's ordering step calls gi-triage-graph" \
  "references/scripts/gi-triage-graph.py" "$SKILLS/issue-triage/SKILL.md"
expect_grep "AC2: auto-pilot Phase 1 calls the SAME script, not a reimplementation" \
  "references/scripts/gi-triage-graph.py" "$SKILLS/auto-pilot/references/phases.md"
expect_grep "AC3: init-gitissue Step 1 calls gi-stack-detect" \
  "references/scripts/gi-stack-detect.py" "$SKILLS/init-gitissue/SKILL.md"
expect_grep "AC4: issue-creator's config step calls gi-model-cache" \
  "references/scripts/gi-model-cache.py" "$SKILLS/issue-creator/SKILL.md"

# AC5: every replaced procedure survives as a documented fallback.
expect_grep "AC5: issue-triage keeps the ordering rules as a runnable procedure" \
  "Steps 3-7 — the prose procedure" "$SKILLS/issue-triage/references/detection.md"
expect_grep "AC5: the prose procedure still carries the priority buckets" \
  "P1 (Critical)" "$SKILLS/issue-triage/references/detection.md"
expect_grep "AC5: init-gitissue keeps the language detection table" \
  "### Language Detection" "$SKILLS/init-gitissue/SKILL.md"
expect_grep "AC5: init-gitissue keeps the test-runner detection table" \
  "### Test Runner Detection" "$SKILLS/init-gitissue/SKILL.md"
expect_grep "AC4: the model-suggestion doc is marked refresh/debug-only reading" \
  "refresh- and debug-only reading" "$SKILLS/issue-creator/references/model-suggestion.md"
expect_grep "AC4: the model-suggestion doc keeps the by-hand lifecycle" \
  "Seeded model data from bundled" "$SKILLS/issue-creator/references/model-suggestion.md"

# Exit 3 must never be swallowed by a degrade path, and exit 4 must be named.
for entry in \
  "issue-triage|SKILL.md" \
  "init-gitissue|SKILL.md" \
; do
  skill="${entry%%|*}"; f="$SKILLS/$skill/${entry##*|}"
  if grep -qi "never degrade past exit 3" "$f"; then
    pass "AC5: $skill states that exit 3 stops rather than degrades"
  else
    fail "AC5: $skill does not say exit 3 is a stop"
  fi
  if grep -q "exit 4" "$f"; then
    pass "AC5: $skill classifies exit 4"
  else
    fail "AC5: $skill leaves exit 4 unclassified"
  fi
done
expect_grep "AC5: auto-pilot classifies exit 3 and exit 4 at its call site" \
  "Exit 4 means only the write failed" "$SKILLS/auto-pilot/references/phases.md"
# issue-creator's only wave-3 call site is gi-model-cache, whose exit-3 stop is
# stated in the call-site prose rather than in the shared exit-code table.
expect_grep "AC4: issue-creator's gi-model-cache call site stops on exit 3" \
  "stop and print the validation error" "$SKILLS/issue-creator/SKILL.md"
expect_grep "AC4: issue-creator classifies gi-model-cache exit 4" \
  "exit 4" "$SKILLS/issue-creator/SKILL.md"

# An agent prompt renders its references as absolute URLs, so it must NOT carry
# a skill-relative script path (issue #245).
if grep -q "references/scripts/" "$SKILLS/issue-creator/references/agents/duplicate-detector.md"; then
  fail "AC5: duplicate-detector.md cites a skill-relative script path (issue #245)"
else
  pass "AC5: duplicate-detector.md cites no skill-relative script path"
fi

# ───────────────────────────────────────────────────────────
# T6 (AC5): call-site injection lint, extended to the wave-3 scripts
# ───────────────────────────────────────────────────────────
#
# The wave-2 lint (tests/test-scripts-252.sh) already matches any `gi-*.py`
# call site, so the four new scripts are inside it by construction. This is the
# *extension* it asked for, and it is deliberately stricter on exactly the
# property wave 3 turns on: these four scripts consume issue titles, issue
# bodies, dependency files, and fetched web content — the most attacker-
# controlled inputs in the system. So on a wave-3 call line:
#
#   * NO placeholder is allowed at all, in any of the three styles skills
#     actually write — `{name}`, `<name>` and `[name]`. The wave-2 allowlist
#     exists because wave-2 scripts legitimately take an integer issue number on
#     the command line; none of these four take any untrusted value by any
#     route, so the only variable admitted is the one on ALLOWED_VARS below.
#   * The untrusted value must arrive by stdin redirect, a file path the skill
#     itself wrote, or a fetch the script performs — asserted below per script.
#
# Issue #278 closed five gaps found by adversarial mutation, and each was closed
# by removing the thing that could be wrong rather than by adding a case:
#
#   1. `[name]` was not a placeholder style. It is now (lowercase identifier,
#      two characters or more — no `[A-Z0-9]` character class or `[e]dit` idiom
#      looks like that, and unlike wave 2 there is no allowlist to reconcile).
#   2. A command substitution inside double quotes was skipped, because the
#      check ran on the quote-stripped text. Quoting stops word-splitting; it
#      does not stop `$(gh issue view …)` from pasting a reporter-written title
#      onto the command line. `$(` is now a finding wherever it appears.
#   3. A placeholder could hide in a later backtick span, because spans were
#      admitted to the command by a heuristic (opens with an option, a pipe, or
#      follows a dangling flag). The heuristic is gone: on a line that carries a
#      wave-3 call, **every** backtick span on that line is inspected.
#   4. The presence guard was per-script, so deleting one of a script's two call
#      sites left it satisfied. It is now a pinned per-script *count*.
#   5. A call site outside the four scanned ROOTS was invisible. There is no
#      ROOTS list any more: the lint walks every file the repository tracks,
#      minus the build output, the vendored copies, and this suite's own
#      fixtures. Adding a call site somewhere new cannot escape it.
python3 - "$REPO_ROOT" <<'PY' > "$TMP/lint-report"
import pathlib, re, subprocess, sys

root = pathlib.Path(sys.argv[1])
WAVE3 = ("gi-triage-graph.py", "gi-stack-detect.py", "gi-model-cache.py")

# Gap 4: a pinned count per script, not "at least one somewhere". Deleting one
# of `gi-triage-graph.py`'s two call sites is a real change to the contract this
# lint pins, so it must be an explicit edit here and not a silent pass.
EXPECTED_SITES = {
    "gi-triage-graph.py": 2,
    "gi-stack-detect.py": 1,
    "gi-model-cache.py": 2,
}

# Gap 5: every tracked file, not a list of roots. `skills/` and `dist/` are
# byte-identical build output of `src/`, `.pi/` is a vendored copy, and
# `tests/` is where this suite writes its own adversarial fixtures.
SKIP_PREFIXES = ("skills/", "dist/", ".pi/", "tests/")
SCAN_SUFFIXES = (".md", ".yml", ".yaml", ".json", ".txt")

_LAUNCH = r"(?:python[0-9.]*|uv\s+run|\"?\$\{?\w+\}?\"?)"
CALL = re.compile(
    _LAUNCH + r"(?:\s+\S+){0,4}?\s+\S*gi-[a-z0-9-]+\.py"
    r"|\./\S*gi-[a-z0-9-]+\.py"
    r"|" + _LAUNCH + r"(?:\s+\S+){0,4}?\s+\S*\{[^{}]+\}"
)
WAVE3_RE = re.compile("|".join(re.escape(name) for name in WAVE3))
PLACEHOLDER = re.compile(
    r"(?<!\$)\{\s*[A-Za-z_][\w.-]*\s*\}"
    r"|<[A-Za-z_][\w-]*>"
    # Gap 1. Wave 2 leaves `[name]` out because a square bracket is a glob range
    # and a regex character class first, and its allowlist has to coexist with
    # documented `[A-Z0-9]` examples. Here no placeholder is admitted at all, so
    # the rule can be narrow instead of negotiated: a lowercase identifier of
    # two or more characters is not `[A-Z0-9]`, not `[e]dit`, and not `[Y/n]`.
    r"|\[[a-z_][a-z0-9_.-]+\]"
)
VAR = re.compile(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?")
# Gap 2: checked on the raw text. `"$(gh issue view 42 --json title -q .title)"`
# is quoted and still puts a reporter-written title on the command line. The one
# substitution that is not a finding is the one that *contains* the call, which
# is the documented capture idiom `body="$(python3 …gi-issue.py …)"` and puts
# nothing on anybody's command line.


def loose_substitutions(cmd):
    """(start, end) of every `$(…)` on the line, with naive paren balancing.

    `end` is `len(cmd)` when the substitution never closes, which is itself a
    finding: an unclosed one swallows whatever follows it.
    """
    out, i = [], cmd.find("$(")
    while i != -1:
        depth, j = 0, i + 1
        while j < len(cmd):
            if cmd[j] == "(":
                depth += 1
            elif cmd[j] == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        out.append((i, j))
        i = cmd.find("$(", max(j, i + 2))
    return out
REPARSE = re.compile(
    r"(?<![\w.-])(?:sh|bash|zsh|dash|ksh)(?:\s+\S+)*?\s+-[A-Za-z]*c[A-Za-z]*\b"
    r"|\bxargs\b|\beval\b"
)
DQUOTED = re.compile(r'"(?:[^"\\]|\\.)*"')
SQUOTED = re.compile(r"'[^']*'")

# Shell variables permitted on a wave-3 command line, and why each is safe.
# A variable is only inert while it is quoted; VAR checks that separately.
# This map is deliberately non-empty and small — "the allowlist is empty" was a
# claim a reviewer had to check against the code, so the code states it.
ALLOWED_VARS = {
    "$skill_dir": "path the skill resolves from its own SKILL.md dirname",
}


def logical_lines(path):
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    i = 0
    while i < len(lines):
        joined, j = lines[i], i
        while (
            j + 1 < len(lines)
            and re.search(r"(\\|\|)\s*$", joined)
            and not (joined.lstrip().startswith("|") and joined.rstrip().endswith("|"))
        ):
            j += 1
            joined = re.sub(r"\\\s*$", " ", joined) + " " + lines[j].strip()
        pulled = 0
        is_fence = joined.lstrip().startswith("```") or joined.lstrip().startswith("~~~")
        while not is_fence and joined.count("`") % 2 and j + 1 < len(lines) and pulled < 4:
            j += 1
            pulled += 1
            joined += " " + lines[j].strip()
        yield i + 1, joined
        i = j + 1


def commands(text):
    """Every backtick span on a line that carries a wave-3 call.

    Gap 3. The wave-2 version admits a sibling span only when it opens with an
    option or a pipe, or when the span before it ended on a flag still waiting
    for its value. That is a heuristic, and a heuristic that decides what to
    inspect is a heuristic an attacker writes around — `python3 …gi-model-cache.py`
    followed by prose followed by `[issue_title]` passed it. Here there is
    nothing to write around: if one span on the line is a call, all of them are
    part of the command text.
    """
    spans = re.findall(r"`([^`]+)`", text)
    if not any(CALL.search(span) for span in spans):
        return [text] if CALL.search(text) else []
    return spans


proc = subprocess.run(
    ["git", "-C", str(root), "ls-files", "-z"], capture_output=True, check=False
)
if proc.returncode != 0:
    print("FAIL|AC5: cannot enumerate tracked files — the lint is not scanning")
    raise SystemExit(0)
tracked = [p for p in proc.stdout.decode("utf-8", "replace").split("\0") if p]

bad = []
seen = {name: set() for name in WAVE3}
for rel in tracked:
    if rel.startswith(SKIP_PREFIXES) or not rel.endswith(SCAN_SUFFIXES):
        continue
    path = root / rel
    if not path.is_file():
        continue
    for lineno, text in logical_lines(path):
        cmds = commands(text)
        if not any(WAVE3_RE.search(cmd) for cmd in cmds):
            continue
        for name in WAVE3:
            if any(name in cmd for cmd in cmds):
                seen[name].add((rel, lineno))
        for cmd in cmds:
            if "<<" in cmd:
                bad.append(f"{rel}:{lineno}: a heredoc hides its body from this lint")
            for token in PLACEHOLDER.findall(cmd):
                bad.append(
                    f"{rel}:{lineno}: {token} is interpolated into a wave-3 "
                    f"command line — these scripts read untrusted input "
                    f"themselves, so no placeholder is ever needed there"
                )
            if REPARSE.search(cmd):
                bad.append(
                    f"{rel}:{lineno}: a wave-3 call inside `sh -c`/`eval`/`xargs` "
                    f"re-parses its argument, so quoting makes nothing inert"
                )
            call = CALL.search(cmd)
            for start, end in loose_substitutions(cmd):
                if (
                    call is not None
                    and start < call.start()
                    and call.end() <= end < len(cmd)
                ):
                    continue  # the substitution captures the call's own output
                bad.append(
                    f"{rel}:{lineno}: a command substitution puts its output on a "
                    f"wave-3 command line — quoting it does not make it inert"
                )
            unquoted = DQUOTED.sub(lambda m: " " * len(m.group(0)), cmd)
            unquoted = SQUOTED.sub(lambda m: " " * len(m.group(0)), unquoted)
            for token in VAR.findall(unquoted):
                bad.append(f"{rel}:{lineno}: {token} is unquoted on a wave-3 command line")
            for token in set(VAR.findall(cmd)):
                if token not in ALLOWED_VARS:
                    bad.append(
                        f"{rel}:{lineno}: {token} is on a wave-3 command line and "
                        f"is not on the reviewed variable allowlist"
                    )

drift = [
    f"{name}: {len(seen[name])} call site(s), pinned at {want}"
    for name, want in sorted(EXPECTED_SITES.items())
    if len(seen[name]) != want
]
if drift:
    print("FAIL|AC5: the wave-3 call-site count moved — " + "; ".join(drift)
          + ". A deleted call site is a contract change; update EXPECTED_SITES "
          "deliberately or restore the site")
elif bad:
    for entry in sorted(set(bad)):
        print(f"FAIL|AC5: {entry}")
else:
    total = sum(len(v) for v in seen.values())
    print(f"PASS|AC5: no value is interpolated at any of the {total} wave-3 call sites")
PY
while IFS='|' read -r verdict label; do
  [ -n "$verdict" ] || continue
  if [ "$verdict" = "PASS" ]; then pass "$label"; else fail "$label"; fi
done < "$TMP/lint-report"

# The static half of the same property: none of the four scripts offers a flag
# that would tempt a caller to pass issue text on the command line. gi-branch
# shipped exactly that flag in wave 2 and it became an injection.
for s in $NEW_SCRIPTS; do
  if grep -qE '^\s*(parser\.add_argument\(\s*)?"--(title|body|issue-title|items|text)"' \
       "$SRC_SCRIPTS/$s.py"; then
    fail "AC5: $s.py offers a text-carrying flag — untrusted input would reach a shell"
  else
    pass "AC5: $s.py has no flag that would carry issue text on a command line"
  fi
done

# And the positive statement: each script's own docstring names where its
# untrusted input comes from, so a reader of the script sees the contract.
for entry in "gi-triage-graph|on stdin" \
             "gi-stack-detect|it reads the repository" "gi-model-cache|stdin"; do
  s="${entry%%|*}"; needle="${entry##*|}"
  if head -80 "$SRC_SCRIPTS/$s.py" | grep -q -- "$needle"; then
    pass "AC5: $s.py documents that untrusted input arrives out-of-band"
  else
    fail "AC5: $s.py does not document where its untrusted input comes from"
  fi
done

# The skills must say so too, at the call site, where an author will read it.
expect_grep "AC5: issue-triage forbids an issue title on a command line" \
  "never\*\* put an issue title on a command line" "$SKILLS/issue-triage/SKILL.md"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Shared-scripts wave 3 tests failed"
  exit 1
fi
echo "  ✓ All shared-scripts wave 3 checks passed"
