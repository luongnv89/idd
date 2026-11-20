#!/usr/bin/env bash
# issue-analysis stand-in (fresh-read-only): a fresh analysis of issue #42.
#
# Reads the issue once through the REAL gi-issue.py (under the PATH-shimmed
# gh), numbers its criteria and checks the recommended option's coverage with
# the REAL gi-ready.py, pins git_state from the fixture repository, and
# persists .idd/analysis-42.json the way references/output-and-persist.md
# specifies: validate, write a temp file, parse it back, replace atomically,
# re-read. The analysis itself (affected file, options) is this stand-in's
# fixed judgment for the fixture; whether a live agent analyzes well is out of
# scope. The run is read-only: one issue read, no tracker write, no source
# file touched.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_WORK:?EVAL_WORK is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

N=42
FIELDS="number,title,body,labels,assignees,state,comments,createdAt,updatedAt,author"

# The fixture is copied without history; give it one commit to pin against.
git init -q -b main
git add -A
git -c user.name=idd-eval -c user.email=idd-eval@example.invalid -c commit.gpgsign=false \
  commit -q -m "fixture"

python3 "$EVAL_SCRIPTS_DIR/gi-issue.py" "$N" --fields "$FIELDS" \
  --cache-dir "$EVAL_WORK/issue-cache" > "$EVAL_WORK/issue-envelope.json"

# git_state: one clock read feeds both timestamp keys.
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
SHA="$(git rev-parse HEAD)"
SHA_SHORT="$(git rev-parse --short=7 HEAD)"
NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LINE="$(grep -n 'return self.count <= self.limit + 1' ratelimit/window.py | cut -d: -f1)"

N="$N" BRANCH="$BRANCH" SHA="$SHA" SHA_SHORT="$SHA_SHORT" NOW="$NOW" LINE="$LINE" \
  SCRIPTS="$EVAL_SCRIPTS_DIR" WORKDIR="$EVAL_WORK" OUT="$EVAL_OUT" python3 - <<'PY'
import copy
import json
import os
import re
import subprocess
import sys

env = os.environ
out, scripts, n = env["OUT"], env["SCRIPTS"], int(env["N"])
issue = json.load(open(os.path.join(env["WORKDIR"], "issue-envelope.json"), encoding="utf-8"))["issue"]


def run(script, payload, *args):
    proc = subprocess.run([sys.executable, os.path.join(scripts, script), *args],
                          input=json.dumps(payload), capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"{script} exited {proc.returncode}: {proc.stderr}")
    return json.loads(proc.stdout)


def touch(name, text=""):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        fh.write(text + "\n")


criteria = run("gi-ready.py", {"issue": issue}, "--criteria")["criteria"]
ids = [c["id"] for c in criteria]
path = "ratelimit/window.py"
options = [
    {
        "number": 1, "name": "Fix the boundary comparison",
        "summary": f"Compare against the limit itself in Window.allow ({path}:{env['LINE']}) and add a boundary test",
        "files_to_modify": [{"path": path, "changes": "drop the + 1 from the comparison"},
                            {"path": "tests/test_window.py", "changes": "assert call n+1 is refused"}],
        "files_to_create": [], "pros": ["One-line fix", "Boundary pinned by a test"],
        "cons": ["Callers that relied on the extra request change behaviour"],
        "complexity": "XS", "risk": "Low", "risk_details": "Single comparison",
        "criteria_covered": ids,
    },
    {
        "number": 2, "name": "Count after the check",
        "summary": "Test the limit before incrementing the counter",
        "files_to_modify": [{"path": path, "changes": "reorder increment and comparison"}],
        "files_to_create": [], "pros": ["Refused calls stop consuming the window"],
        "cons": ["Changes counting semantics beyond the reported bug"],
        "complexity": "S", "risk": "Medium", "risk_details": "Alters what count means",
        "criteria_covered": ids[:1],
    },
]
coverage = run("gi-ready.py", {"issue": issue, "options": options, "selected": 1,
                               "criteria": criteria}, "--coverage")
touch(f"coverage-{coverage['verdict']}.txt", json.dumps(coverage, sort_keys=True))
selected = options[0]
analysis = {
    "version": 1,
    "timestamp": env["NOW"],
    "source": "/issue-analysis",
    "issue": {
        "number": issue["number"], "title": issue["title"], "type": "bug",
        "reporter": issue["author"], "labels": [l["name"] for l in issue["labels"]],
        "state": issue["state"].lower(), "createdAt": issue["createdAt"],
        "updatedAt": issue["updatedAt"],
    },
    "research_status": {"already_resolved": False, "pr_in_progress": False,
                        "possibly_already_fixed": False, "resolution_details": None},
    "extraction": {"error_messages": [], "functions": ["allow"], "classes": ["Window"],
                   "file_refs": [], "modules": ["ratelimit"],
                   "keywords": ["rate", "limiter", "window", "boundary"]},
    "affected_files": [{"path": path, "relevance": "critical", "role": "limit check",
                        "match_reasons": ["function match: allow"]}],
    "analysis": {"type_specific": "root_cause",
                 "summary": f"Window.allow compares against limit + 1 ({path}:{env['LINE']}), so call n+1 passes.",
                 "details": "Observed in code; not reproduced by running it."},
    "options": options,
    "criteria": criteria,
    "recommended_option": 1,
    "overall_complexity": selected["complexity"],
    "overall_risk": selected["risk"],
    "git_state": {"branch": env["BRANCH"], "commit_sha": env["SHA"],
                  "commit_sha_short": env["SHA_SHORT"], "captured_at": env["NOW"]},
    "decision_record": {
        "root_cause": f"Window.allow compares against limit + 1 ({path}:{env['LINE']}), so call n+1 passes.",
        "options_considered": [{"number": o["number"], "name": o["name"]} for o in options],
        "options_rejected": [{"number": 2, "name": options[1]["name"], "reason": options[1]["cons"][0]}],
        "selected_option": {"number": 1, "name": selected["name"], "summary": selected["summary"]},
        "residual_risk": selected["cons"][0],
    },
}

ISO = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z")


def problems(obj):
    """The *Validate analysis data* rules this stand-in can check."""
    bad = []
    if obj.get("version") != 1 or obj.get("source") != "/issue-analysis":
        bad.append("version/source")
    if obj.get("issue", {}).get("number") != n:
        bad.append("issue.number")
    if obj.get("issue", {}).get("updatedAt") != issue["updatedAt"]:
        bad.append("issue.updatedAt not verbatim")
    opts = obj.get("options") or []
    if [o.get("number") for o in opts] != list(range(1, len(opts) + 1)) or not opts:
        bad.append("options numbering")
    rec = obj.get("recommended_option")
    if type(rec) is not int or not 1 <= rec <= len(opts):
        bad.append("recommended_option")
    else:
        sel = obj.get("decision_record", {}).get("selected_option", {})
        if sel.get("number") != rec or sel.get("name") != opts[rec - 1]["name"]:
            bad.append("decision_record.selected_option")
        if obj.get("overall_complexity") != opts[rec - 1]["complexity"] or \
           obj.get("overall_risk") != opts[rec - 1]["risk"]:
            bad.append("overall complexity/risk")
        rejected = {r.get("number") for r in obj["decision_record"].get("options_rejected", [])}
        if rejected != {o["number"] for o in opts} - {rec}:
            bad.append("options_rejected")
    crit = [c.get("id") for c in obj.get("criteria", [])]
    if crit != [f"AC{i}" for i in range(1, len(crit) + 1)]:
        bad.append("criteria ids")
    if any(not set(o.get("criteria_covered", [])) <= set(crit) for o in opts):
        bad.append("criteria_covered")
    gs = obj.get("git_state", {})
    if not re.fullmatch(r"[0-9a-f]{40}", str(gs.get("commit_sha", ""))):
        bad.append("git_state.commit_sha")
    elif gs.get("commit_sha_short") != gs["commit_sha"][:7]:
        bad.append("git_state.commit_sha_short")
    if not ISO.fullmatch(str(obj.get("timestamp", ""))) or obj.get("timestamp") != gs.get("captured_at"):
        bad.append("timestamp")
    return bad


found = problems(analysis)
if found:
    sys.exit(f"analysis failed validation: {found}")
touch("schema-valid.txt")

# Each tampered copy breaks one documented rule; every one must be refused.
tampered = []
t = copy.deepcopy(analysis); t["git_state"]["sha"] = t["git_state"].pop("commit_sha"); tampered.append(t)
t = copy.deepcopy(analysis); t["issue"]["updatedAt"] = env["NOW"]; tampered.append(t)
t = copy.deepcopy(analysis); t["recommended_option"] = 3; tampered.append(t)
t = copy.deepcopy(analysis); t["options"][1]["criteria_covered"] = ["AC9"]; tampered.append(t)
accepted = [i for i, t in enumerate(tampered) if not problems(t)]
if accepted:
    touch("tampered-accepted.txt", json.dumps(accepted))

# Persist: temp file, parse back, atomic replace, re-read the destination.
os.makedirs(".idd", exist_ok=True)
dest = os.path.join(".idd", f"analysis-{n}.json")
tmp = os.path.join(".idd", f".analysis-{n}.{os.getpid()}.tmp")
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(analysis, fh, indent=2)
    fh.write("\n")
if json.load(open(tmp, encoding="utf-8")) != analysis:
    os.remove(tmp)
    sys.exit("temp file did not parse back to the analysis")
os.replace(tmp, dest)
if json.load(open(dest, encoding="utf-8")) == analysis:
    touch("persist-verified.txt")
with open(os.path.join(out, f"analysis-{n}.json"), "w", encoding="utf-8") as fh:
    json.dump(analysis, fh, indent=2)
    fh.write("\n")

with open(os.path.join(out, "report.txt"), "w", encoding="utf-8") as fh:
    fh.write(
        f"  ◆ Issue Analysis: #{n} {issue['title']}\n"
        f"  Result:   DONE — root cause at {path}:{env['LINE']} (observed in code, not reproduced)\n"
        f"  Recommended:  Option 1 — {selected['name']} (covers {', '.join(ids)})\n"
        f"  Analyzed at:  {env['BRANCH']} @ {env['SHA_SHORT']}\n"
        f"  Saved:    {dest}\n"
        "  Decision: No approval needed.\n"
    )
PY

# Read-only: the analysis wrote only under .idd/, and no tracked file changed.
if git diff --quiet HEAD && [ -z "$(git ls-files --others --exclude-standard | grep -v '^\.idd/' || true)" ]; then
  : > "$EVAL_OUT/source-untouched.txt"
fi
