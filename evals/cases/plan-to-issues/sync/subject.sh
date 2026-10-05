#!/usr/bin/env bash
# plan-to-issues sync stand-in (#503, upstream eval 2: `/plan-to-issues sync 100`).
#
# Runs the seven shell operations of references/epic-dashboard.md -> *Sync
# algorithm* with the skill's argv copied verbatim, and renders the map with the
# REAL gi-plan-map.py. Every gh call goes through the PATH shim; nothing is filed.
#
# Fixture: epic #100's map lists #101 (0.1) and #102 (0.2). Task 0.2's title
# cites "#999 — 9.9", which an unanchored child parse would adopt as a phantom
# child. The sub_issues API reports #101, #102 and #103, so the map must gain
# #103; plan task 1.2 has no issue and must render `(not filed)`.
#
# Cassettes are static per argv, so step 7's re-read returns the pre-edit body:
# it exercises the documented verify probe, but the graded artifact is the file
# sent with `--body-file` (epic-body-updated.md), not the re-read.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

EPIC=100
SYNCED="2026-10-05"   # caller-supplied render date; fixed so the run is reproducible
START='<!-- plan-dashboard:start -->'
END='<!-- plan-dashboard:end -->'
PLAN_MAP="$EVAL_SCRIPTS_DIR/gi-plan-map.py"

test -f docs/PLAN.md || { echo "✗ fixture plan docs/PLAN.md was not seeded" >&2; exit 1; }

# 1. fetch
gh issue view "$EPIC" --json body --jq '.body' > epic-body.md

# 2. gate: exactly one whole-line start sentinel, else this is not our epic
gate="$(grep -cFx "$START" epic-body.md || true)"
if [ "$gate" != "1" ]; then
  echo "✗ Issue #$EPIC has no plan map — is this the right epic? (start sentinels: $gate)" >&2
  exit 1
fi

# 3. children + task ids, anchored to the task-line grammar
grep -oE '^- #[0-9]+ — [A-Za-z0-9.]+' epic-body.md > children.txt || true
# The unanchored form is what the anchor guards against: record what it would
# have adopted, so the assertions below can prove the fixture is meaningful.
grep -oE '#[0-9]+ — [A-Za-z0-9.]+' epic-body.md > children-unanchored.txt || true

# 4. registered children, one call; issue state is never fetched
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
gh api --paginate "repos/$repo/issues/$EPIC/sub_issues" --jq '.[].number' > registered.txt

# A child registered on the epic but absent from the map is one the map must
# gain. The sub_issues list carries numbers only, so its task id is recovered
# from the title prefix `<task-id>: ` (references/issue-creator-bridge.md
# Step 3) — one title read per gained child, never one per child.
: > gained-titles.txt
for n in $(python3 - <<'PY'
import re
mapped = {int(n) for n in re.findall(r"^- #(\d+) — ", open("children.txt", encoding="utf-8").read(), re.M)}
registered = [int(l) for l in open("registered.txt", encoding="utf-8") if l.strip()]
print(" ".join(str(n) for n in registered if n not in mapped))
PY
); do
  printf '%s\t%s\n' "$n" "$(gh issue view "$n" --json title --jq '.title')" >> gained-titles.txt
done

# Build the render input (references/epic-dashboard.md -> Render input schema)
# from the plan the binding marker names, re-parsed so unmapped tasks surface.
python3 - "$EPIC" "$SYNCED" <<'PY'
import json
import re
import sys
from pathlib import Path

epic, synced = int(sys.argv[1]), sys.argv[2]
body = Path("epic-body.md").read_text(encoding="utf-8")
markers = re.findall(r"^<!-- plan-to-issues:plan=(.+) -->$", body, re.M)
assert len(markers) == 1, f"want one plan-binding marker, got {markers}"
plan_path = markers[0]
plan = Path(plan_path).read_text(encoding="utf-8")

task_to_issue = {}
for line in Path("children.txt").read_text(encoding="utf-8").splitlines():
    m = re.match(r"^- #(\d+) — ([A-Za-z0-9.]+)$", line)
    task_to_issue[m.group(2)] = int(m.group(1))
registered = {int(l) for l in Path("registered.txt").read_text().split()}
# A mapped number that is no longer a registered child is one the map loses.
task_to_issue = {t: n for t, n in task_to_issue.items() if n in registered}
for line in Path("gained-titles.txt").read_text(encoding="utf-8").splitlines():
    n, title = line.split("\t", 1)
    m = re.match(r"^([A-Za-z0-9.]+): ", title)
    assert m, f"gained child #{n} has no task-id title prefix: {title!r}"
    task_to_issue[m.group(1)] = int(n)

header = re.search(r"^\*\*Baseline:\*\* (.+)$", plan, re.M)
critical = re.search(r"^\*\*Critical path:\*\* (.+)$", plan, re.M)
phases, task = [], None
for line in plan.splitlines():
    if m := re.match(r"^## Phase (\S+) — (.+)$", line):
        phases.append({"id": m.group(1), "title": m.group(2), "filed": True, "tasks": []})
    elif m := re.match(r"^\*\*Goal:\*\* (.+) · \*\*Milestone (\S+):\*\* (.+)$", line):
        phases[-1]["goal"] = m.group(1)
        phases[-1]["milestone"] = {"id": m.group(2), "exit": m.group(3)}
    elif m := re.match(r"^#{3,4} Task ([^:]+): (.+)$", line):
        task = {"task_id": m.group(1), "title": m.group(2),
                "issue": task_to_issue.get(m.group(1)),
                "depends_on": [], "unknown_deps": []}
        phases[-1]["tasks"].append(task)
    elif (m := re.match(r"^\*\*Dependencies\*\*: (.+)$", line)) and task is not None:
        deps = m.group(1).strip()
        task["depends_on"] = [] if deps == "None" else [d.strip() for d in deps.split(",")]

render_in = {
    "plan_path": plan_path,
    "baseline": header.group(1) if header else None,
    "synced": synced,
    "epic": epic,
    "critical_path": [t.strip() for t in critical.group(1).split("→")] if critical else [],
    "phases": phases,
}
Path("dashboard-input.json").write_text(json.dumps(render_in, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
unmapped = [t["task_id"] for p in phases for t in p["tasks"] if t["issue"] is None]
Path("unmapped.txt").write_text("".join(f"{t}\n" for t in unmapped), encoding="utf-8")
PY

# Parse verification: the re-parsed task count matches the plan's headings.
plan_tasks="$(grep -cE '^#{3,4} Task ' docs/PLAN.md)"
parsed_tasks="$(python3 -c 'import json; d=json.load(open("dashboard-input.json")); print(sum(len(p["tasks"]) for p in d["phases"]))')"
[ "$plan_tasks" = "$parsed_tasks" ] || { echo "✗ task count $parsed_tasks != plan $plan_tasks" >&2; exit 1; }

# 5. re-render with the real renderer
python3 "$PLAN_MAP" < dashboard-input.json > map.md

# Replace ONLY the sentinel region: first whole-line start, last whole-line end.
replace_region() {
  python3 - "$1" "$2" "$3" <<'PY'
import sys
from pathlib import Path

START, END = "<!-- plan-dashboard:start -->", "<!-- plan-dashboard:end -->"
src, block, dst = (Path(p) for p in sys.argv[1:4])
lines = src.read_text(encoding="utf-8").splitlines(keepends=True)
bare = [line.rstrip("\n") for line in lines]
first = bare.index(START)
last = len(bare) - 1 - bare[::-1].index(END)
assert first < last, "sentinels out of order"
dst.write_text("".join(lines[:first]) + block.read_text(encoding="utf-8") + "".join(lines[last + 1:]),
               encoding="utf-8")
PY
}
replace_region epic-body.md map.md epic-body-updated.md

# 6. write back
gh issue edit "$EPIC" --body-file epic-body-updated.md >/dev/null

# 7. verify by re-read (static cassette — see the header comment)
verify="$(gh issue view "$EPIC" --json body --jq '.body' | grep -cFx -e "$START" -e "$END" || true)"
[ "$verify" = "2" ] || { echo "✗ re-read sentinel count $verify, want 2" >&2; exit 1; }

# Idempotence: a second sync with nothing newly filed rewrites the body to
# identical bytes — apply the same render to the already-updated body.
replace_region epic-body-updated.md map.md epic-body-resynced.md

cp epic-body.md epic-body-updated.md epic-body-resynced.md map.md dashboard-input.json \
  children.txt children-unanchored.txt registered.txt unmapped.txt "$EVAL_OUT/"

python3 - "$EVAL_OUT" <<'PY'
import re
import sys
from pathlib import Path

START, END = "<!-- plan-dashboard:start -->", "<!-- plan-dashboard:end -->"
out = Path(sys.argv[1])
before = (out / "epic-body.md").read_text(encoding="utf-8")
after = (out / "epic-body-updated.md").read_text(encoding="utf-8")
lines = after.splitlines()

# Exactly one whole-line start and one whole-line end sentinel.
assert lines.count(START) == 1 and lines.count(END) == 1, "sentinel pair not unique"

# Bytes outside the region are byte-identical, prefix and suffix.
def outside(text):
    head, _, rest = text.partition(START + "\n")
    _, _, tail = rest.rpartition(END + "\n")
    return head, tail
assert outside(before) == outside(after), "bytes outside the sentinels changed"
assert outside(after)[1].endswith("preserved byte-for-byte -->\n"), "suffix fixture lost"

# The rendered map is exactly what sits between the sentinels.
assert (out / "map.md").read_text(encoding="utf-8") in after

# Children: #103 gained under its own phase; the phantom #999 not adopted.
children = {int(n): t for n, t in re.findall(r"^- #(\d+) — ([A-Za-z0-9.]+)", after, re.M)}
assert children == {101: "0.1", 102: "0.2", 103: "1.1"}, children
assert "- #103 — 1.1 Add the CI workflow" in after.split("### P1 — Harden", 1)[1]
assert not re.search(r"^- #999 ", after, re.M), "phantom #999 became a map row"
unanchored = (out / "children-unanchored.txt").read_text(encoding="utf-8")
assert "#999 — 9.9" in unanchored, "fixture lost its phantom: unanchored parse should see #999"
assert "#999" not in (out / "children.txt").read_text(encoding="utf-8")

# The plan task with no issue renders `(not filed)` and is reported unmapped.
assert "- (not filed) — 1.2 Pin the Node runtime" in after
assert (out / "unmapped.txt").read_text(encoding="utf-8") == "1.2\n"

# The new render date is the caller-supplied one; no issue state is rendered.
assert "rendered 2026-10-05" in after and "rendered 2026-09-01" not in after
assert "- [x]" not in after.split(START, 1)[1]

# Re-running sync with nothing newly filed rewrites the body to identical bytes.
assert (out / "epic-body-resynced.md").read_bytes() == (out / "epic-body-updated.md").read_bytes()
print("✓ sync: region-only rewrite, #103 gained, #999 not adopted, 1.2 (not filed), idempotent")
PY
