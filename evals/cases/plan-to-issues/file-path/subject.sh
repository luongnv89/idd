#!/usr/bin/env bash
# plan-to-issues file-path stand-in (#503, upstream eval 1: "turn the plan into
# GitHub issues with an epic on top").
#
# Files docs/PLAN.md (2 phases, 3 tasks) the way SKILL.md Phases 1-5 do, with
# argv copied from the skill prose, and renders the epic map with the REAL
# gi-plan-map.py. The /issue-creator bodies are stood in by fixed templates.
# Every gh call goes through the PATH shim: `issue create` is allocated by the
# shim's EVAL_STATE_DIR (epic #1, children #2-#4) and every other call replays
# a static cassette. Preflight (Phase 0) is not exercised here.
#
# Shim facts this subject works around, on purpose:
#   - a state-backed `issue view` ignores --jq and prints {"body": ...}, so the
#     bind read is decoded as JSON;
#   - `issue edit` does not update shim state, so a re-read returns the
#     create-time body. Phase 5 therefore starts from the bound body on disk,
#     and grading reads the files sent with --body-file, never a re-read.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_STATE_DIR:?EVAL_STATE_DIR is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

PLAN="docs/PLAN.md"
SYNCED="2026-10-05"   # caller-supplied render date; fixed so the run is reproducible
PLAN_MAP="$EVAL_SCRIPTS_DIR/gi-plan-map.py"

test -f "$PLAN" || { echo "✗ fixture plan $PLAN was not seeded" >&2; exit 1; }

# ── Phase 1: parse the plan into the worklist ─────────────────────────────
python3 - "$PLAN" <<'PY'
import json
import re
import sys
from pathlib import Path

plan_path = sys.argv[1]
plan = Path(plan_path).read_text(encoding="utf-8")
DEFAULT_PRIORITY = {"Pre": "high", "P0": "high", "P1": "high", "P2": "medium", "P3": "low", "P4": "low"}
project = re.search(r"^# .* — (.+)$", plan, re.M).group(1)
baseline = re.search(r"^\*\*Baseline:\*\* (.+)$", plan, re.M).group(1)
critical = re.search(r"^\*\*Critical path:\*\* (.+)$", plan, re.M).group(1)
phases, task, sprint, in_ac = [], None, None, False
for line in plan.splitlines():
    if m := re.match(r"^## Phase (\S+) — (.+)$", line):
        phases.append({"id": m.group(1), "title": m.group(2), "tasks": []})
        task, in_ac = None, False
    elif m := re.match(r"^\*\*Goal:\*\* (.+) · \*\*Milestone (\S+):\*\* (.+)$", line):
        phases[-1]["goal"] = m.group(1)
        phases[-1]["milestone"] = {"id": m.group(2), "exit": m.group(3)}
    elif m := re.match(r"^#{3} Sprint (\S+) — (.+)$", line):
        sprint = m.group(1)
    elif m := re.match(r"^#{3,4} Task ([^:]+): (.+)$", line):
        task = {"task_id": m.group(1), "title": m.group(2), "sprint": sprint,
                "criteria": [], "depends_on": [], "unknown_deps": []}
        phases[-1]["tasks"].append(task)
        in_ac = False
    elif task is None:
        continue
    elif m := re.match(r"^\*\*(Description|Closes|Dependencies|Effort)\*\*: (.+)$", line):
        key, value = m.group(1).lower(), m.group(2).strip()
        if key == "closes":
            task["closes"] = [c.strip() for c in value.split(",")]
        elif key == "dependencies":
            task["depends_on"] = [] if value == "None" else [d.strip() for d in value.split(",")]
        else:
            task[key] = value
    elif line.startswith("**Acceptance Criteria**:"):
        in_ac = True
    elif in_ac and (m := re.match(r"^- \[ \] (.+)$", line)):
        task["criteria"].append(m.group(1))
    elif in_ac and line.strip() == "":
        in_ac = False

# Label set (references/labels.md): phase, type, dim per finding, priority.
for phase in phases:
    for t in phase["tasks"]:
        dims = [c.split("-")[1].lower() for c in t["closes"]]
        t["priority"] = DEFAULT_PRIORITY[phase["id"]]   # no MODERNIZATION_REPORT.md beside the plan
        t["labels"] = (["phase:" + phase["id"].lower(), "improvement"]
                       + ["dim:" + d for d in dims] + ["priority:" + t["priority"]])
worklist = {"plan_path": plan_path, "project": project, "baseline": baseline,
            "severity_source": "phase-default", "phase_source": "headings",
            "critical_path": [c.strip() for c in critical.split("→")], "phases": phases}
Path("worklist.json").write_text(json.dumps(worklist, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY

# Parse verification: the worklist task count equals the plan's task headings.
plan_tasks="$(grep -cE '^#{3,4} Task ' "$PLAN")"
parsed_tasks="$(python3 -c 'import json; w=json.load(open("worklist.json")); print(sum(len(p["tasks"]) for p in w["phases"]))')"
[ "$plan_tasks" = "$parsed_tasks" ] || { echo "✗ task count $parsed_tasks != plan $plan_tasks" >&2; exit 1; }
echo "$plan_tasks" > task-count.txt

# ── Phase 2: labels — diff, print missing with colours, create in one pass ─
gh label list --limit 200 --json name --jq '.[].name' > labels-existing.txt
python3 - <<'PY'
import json
from pathlib import Path

COLOURS = {"epic": "5319E7", "phase:p0": "B60205", "phase:p1": "D93F0B",
           "dim:dep": "0E8A16", "dim:ci": "0052CC", "priority:high": "D93F0B"}
w = json.loads(Path("worklist.json").read_text(encoding="utf-8"))
needed = ["epic"]
for phase in w["phases"]:
    for t in phase["tasks"]:
        needed += [label for label in t["labels"] if label not in needed]
existing = set(Path("labels-existing.txt").read_text(encoding="utf-8").split())
rows = []
for name in needed:
    if name in existing:
        continue
    axis, _, value = name.partition(":")
    desc = {"epic": "Tracking epic for a filed plan", "phase": f"Plan phase {value}",
            "dim": f"Audit dimension {value}", "priority": f"Priority {value}"}[axis]
    rows.append(f"{name}\t{COLOURS.get(name, '')}\t{desc}\n")
Path("labels-missing.tsv").write_text("".join(rows), encoding="utf-8")
PY
label_grammar='^(epic|bug|improvement|feature|priority:(critical|high|medium|low)|dim:[a-z0-9]+|phase:[a-z0-9._-]+)$'
while IFS=$'\t' read -r name color desc; do
  printf '  ○ missing label %s (#%s)\n' "$name" "$color"
done < labels-missing.tsv
while IFS=$'\t' read -r name color desc; do
  if [[ $name =~ $label_grammar ]]; then
    args=("$name" --description "$desc")
    if [ -n "$color" ]; then args+=(--color "$color"); fi
    gh label create "${args[@]}" >/dev/null </dev/null
  else
    printf '⚠ dropped malformed label: %s\n' "$name"
  fi
done < labels-missing.tsv

# ── Phase 3: epic — look up by binding marker, else create, label, bind ───
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
gh api --paginate "repos/$repo/issues?state=all&per_page=100" \
  --jq '.[] | select(.pull_request == null) | {number,title,body,state,created_at,labels:[.labels[].name]}' \
  > existing-issues.jsonl
if grep -qF "<!-- plan-to-issues:plan=$PLAN -->" existing-issues.jsonl; then
  echo "✗ fixture expects no existing epic for $PLAN" >&2
  exit 1
fi

# /issue-creator stand-in: the epic body, milestone exits as its criteria.
# The binding marker is NOT in the create body (it would be blockquoted).
python3 - <<'PY'
import json
from pathlib import Path

w = json.loads(Path("worklist.json").read_text(encoding="utf-8"))
phases = " · ".join(f"{p['id']} {p['title']}" for p in w["phases"])
ids = [p["id"] for p in w["phases"]]
Path("epic-title.txt").write_text(f"Epic: Modernize {w['project']} — {ids[0]}–{ids[-1]}\n", encoding="utf-8")
criteria = "".join(f"- [ ] {p['milestone']['id']} — {p['milestone']['exit']}\n" for p in w["phases"])
Path("epic-create.md").write_text(f"""<!-- idd:normalized v1 -->

## Type

Improvement

## Description

**Current state:**
{w['project']} — baseline {w['baseline']}.

**Proposed change:**
Deliver {w['plan_path']} phase by phase ({phases}); every plan task is a child issue of this epic.

> **Reporter Context**
> Turn {w['plan_path']} into GitHub issues with an epic on top that tracks the whole thing.

## Acceptance Criteria

{criteria}
## Metadata

**Priority:** P1
**Effort:** M
**Labels:** epic
""", encoding="utf-8")
PY
epic_title="$(cat epic-title.txt)"
epic_url="$(gh issue create --title "$epic_title" --body-file epic-create.md)"
epic="${epic_url##*/}"
gh issue edit "$epic" --add-label epic >/dev/null

# Bind (references/epic-identity.md step 4), before any child is filed. The
# state-backed shim ignores --jq, so the read is decoded from its JSON.
gh issue view "$epic" --json body --jq '.body' \
  | python3 -c 'import json,sys; sys.stdout.write(json.load(sys.stdin)["body"])' > epic-body.md
grep -qFx "<!-- plan-to-issues:plan=$PLAN -->" epic-body.md \
  || printf '\n<!-- plan-to-issues:plan=%s -->\n' "$PLAN" >> epic-body.md
grep -q '^<!-- plan-dashboard:start -->$' epic-body.md \
  || printf '<!-- plan-dashboard:start -->\n<!-- plan-dashboard:end -->\n' >> epic-body.md
gh issue edit "$epic" --body-file epic-body.md >/dev/null
cp epic-body.md epic-body-bound.md

# ── Phase 4: one batch per phase — create, label, register sub-issues ─────
: > task-issues.tsv
for phase_id in $(python3 -c 'import json; print(" ".join(p["id"] for p in json.load(open("worklist.json"))["phases"]))'); do
  : > batch.tsv
  for task_id in $(python3 - "$phase_id" <<'PY'
import json, sys
w = json.load(open("worklist.json", encoding="utf-8"))
print(" ".join(t["task_id"] for p in w["phases"] if p["id"] == sys.argv[1] for t in p["tasks"]))
PY
  ); do
    # /issue-creator --parent stand-in: the child body ends with `Part of #<epic>`.
    python3 - "$task_id" "$epic" <<'PY'
import json, sys
from pathlib import Path

task_id, epic = sys.argv[1], sys.argv[2]
w = json.loads(Path("worklist.json").read_text(encoding="utf-8"))
phase, t = next((p, t) for p in w["phases"] for t in p["tasks"] if t["task_id"] == task_id)
criteria = "".join(f"- [ ] {c}\n" for c in t["criteria"])
Path(f"child-{task_id}-title.txt").write_text(f"{task_id}: {t['title']}\n", encoding="utf-8")
Path(f"child-{task_id}.md").write_text(f"""<!-- idd:normalized v1 -->

## Type

Improvement

## Description

**Current state:**
{t['description']}

**Proposed change:**
{t['title']}.

> **Reporter Context**
> Plan task: {task_id} — Sprint {t['sprint']} · Phase {phase['id']} {phase['title']} · {w['plan_path']}
> Closes: {', '.join(t['closes'])}

## Acceptance Criteria

{criteria}
## Metadata

**Priority:** P1
**Effort:** {t['effort']}
**Labels:** {', '.join(t['labels'])}

Part of #{epic}
""", encoding="utf-8")
PY
    # The title is read out of a file, never retyped as a shell literal.
    title="$(cat "child-$task_id-title.txt")"
    url="$(gh issue create --title "$title" --body-file "child-$task_id.md")"
    printf '%s\t%s\n' "$task_id" "${url##*/}" >> batch.tsv
  done
  cat batch.tsv >> task-issues.tsv
  # After each batch: the label set, then native sub-issue registration.
  while IFS=$'\t' read -r task_id n; do
    labels="$(python3 - "$task_id" <<'PY'
import json, sys
w = json.load(open("worklist.json", encoding="utf-8"))
print(",".join(next(t for p in w["phases"] for t in p["tasks"] if t["task_id"] == sys.argv[1])["labels"]))
PY
    )"
    gh issue edit "$n" --add-label "$labels" >/dev/null </dev/null
    child_id="$(gh api "repos/$repo/issues/$n" --jq '.id' </dev/null)"
    gh api --method POST "repos/$repo/issues/$epic/sub_issues" -F sub_issue_id="$child_id" >/dev/null </dev/null
  done < batch.tsv
done

# ── Phase 5: render the map and write it between the sentinels ────────────
python3 - "$epic" "$SYNCED" <<'PY'
import json, sys
from pathlib import Path

epic, synced = int(sys.argv[1]), sys.argv[2]
w = json.loads(Path("worklist.json").read_text(encoding="utf-8"))
issues = dict(line.split("\t") for line in Path("task-issues.tsv").read_text().splitlines())
render_in = {
    "plan_path": w["plan_path"], "baseline": w["baseline"], "synced": synced, "epic": epic,
    "critical_path": w["critical_path"],
    "phases": [{"id": p["id"], "title": p["title"], "goal": p.get("goal"), "filed": True,
                "milestone": p.get("milestone"),
                "tasks": [{"task_id": t["task_id"], "title": t["title"],
                           "issue": int(issues[t["task_id"]]) if t["task_id"] in issues else None,
                           "depends_on": t["depends_on"], "unknown_deps": []}
                          for t in p["tasks"]]}
               for p in w["phases"]],
}
Path("dashboard-input.json").write_text(json.dumps(render_in, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
PY
python3 "$PLAN_MAP" < dashboard-input.json > map.md
python3 - <<'PY'
from pathlib import Path

START, END = "<!-- plan-dashboard:start -->", "<!-- plan-dashboard:end -->"
lines = Path("epic-body.md").read_text(encoding="utf-8").splitlines(keepends=True)
bare = [line.rstrip("\n") for line in lines]
first = bare.index(START)
last = len(bare) - 1 - bare[::-1].index(END)
Path("epic-body-updated.md").write_text(
    "".join(lines[:first]) + Path("map.md").read_text(encoding="utf-8") + "".join(lines[last + 1:]),
    encoding="utf-8")
PY
gh issue edit "$epic" --body-file epic-body-updated.md >/dev/null

# ── Artifacts: what gh actually received, plus the bodies sent by edit ────
cp epic-body-bound.md epic-body-updated.md map.md worklist.json task-issues.tsv \
  task-count.txt "$EVAL_OUT/"
for n in 1 2 3 4; do
  cp "$EVAL_STATE_DIR/issue_$n.md" "$EVAL_OUT/created-$n.md"
  cp "$EVAL_STATE_DIR/issue_$n.json" "$EVAL_OUT/created-$n.json"
done

python3 - "$EVAL_OUT" "$PLAN" <<'PY'
import json
import re
import sys
from pathlib import Path

START, END = "<!-- plan-dashboard:start -->", "<!-- plan-dashboard:end -->"
out, plan_path = Path(sys.argv[1]), sys.argv[2]
assert (out / "task-count.txt").read_text().strip() == "3"

epic = json.loads((out / "created-1.json").read_text(encoding="utf-8"))
assert epic["number"] == 1 and epic["title"] == "Epic: Modernize acme-cli — P0–P1", epic["title"]
assert "plan-to-issues:plan=" not in epic["body"], "marker must not ride in the create body"

# Bind wrote the marker and an empty sentinel pair before any child existed.
bound = (out / "epic-body-bound.md").read_text(encoding="utf-8")
assert bound.endswith(f"<!-- plan-to-issues:plan={plan_path} -->\n{START}\n{END}\n")

# The written-back epic: one marker, one sentinel pair, the rendered map inside.
body = (out / "epic-body-updated.md").read_text(encoding="utf-8")
lines = body.splitlines()
assert lines.count(f"<!-- plan-to-issues:plan={plan_path} -->") == 1
assert lines.count(START) == 1 and lines.count(END) == 1
region = body[body.index(START + "\n"): body.index(END + "\n") + len(END) + 1]
assert region == (out / "map.md").read_text(encoding="utf-8"), "map is not exactly the sentinel region"
assert body.startswith(epic["body"]), "bytes before the bound marker changed"
rows = re.findall(r"^- #(\d+) — ([A-Za-z0-9.]+) ", region, re.M)
assert rows == [("2", "0.1"), ("3", "0.2"), ("4", "1.1")], rows

# Children: what the shim received — task-id title prefix and `Part of #1`.
want = {2: "0.1: Commit the lockfile", 3: "0.2: Add the CI workflow", 4: "1.1: Pin the Node runtime"}
for n, title in want.items():
    child = json.loads((out / f"created-{n}.json").read_text(encoding="utf-8"))
    assert child["title"] == title, (n, child["title"])
    assert re.search(r"^Part of #1$", child["body"], re.M), f"#{n} lacks Part of #1"
    task_id = title.split(":")[0]
    assert f"> Plan task: {task_id} — " in child["body"], f"#{n} lacks its Plan task marker"
print("✓ file-path: 3 tasks reconciled, epic #1 bound, children #2-#4 under it, map rendered")
PY
