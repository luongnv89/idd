#!/usr/bin/env bash
# issue-triage route-mode stand-in (route-clear-bug): fetch issue #21 under the
# PATH-shimmed gh, answer the closed questions, and route through the REAL
# gi-route.py, with the `criteria` answer from the REAL gi-ready.py — as
# references/route-mode.md specifies. The other answers are this stand-in's
# fixed judgment for the fixture (a clear, in-scope, small bug with acceptance criteria); the route is computed, never chosen.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

gh auth status >/dev/null
gh issue view 21 --json number,title,body,labels,state > "$EVAL_OUT/issue.json"

EVAL_OUT="$EVAL_OUT" SCRIPTS="$EVAL_SCRIPTS_DIR" python3 - <<'PY'
import json
import os
import subprocess
import sys

out = os.environ["EVAL_OUT"]
scripts = os.environ["SCRIPTS"]
issue = json.load(open(os.path.join(out, "issue.json"), encoding="utf-8"))


def run(args, stdin):
    proc = subprocess.run([sys.executable, *args], input=stdin, capture_output=True, text=True)
    if proc.returncode != 0:
        sys.exit(f"{args[0]} exited {proc.returncode}: {proc.stderr}")
    return json.loads(proc.stdout)


questions = run([os.path.join(scripts, "gi-route.py"), "--questions"], "")["questions"]
ready = run([os.path.join(scripts, "gi-ready.py")],
            json.dumps({"number": issue["number"], "body": issue["body"]}))
answers = {"scope": "yes", "clarity": "yes", "duplicate": "no", "size": "S", "injection": "no"}
answers["criteria"] = "no" if "no_criteria" in ready["reasons"] else "yes"
for q in questions:
    option = answers[q["id"]]
    assert option in q["options"] or (q["id"] == "duplicate" and option.startswith("yes:#")), q

request = {"number": issue["number"], "questions": [q["id"] for q in questions], "answers": answers}
verdict = run([os.path.join(scripts, "gi-route.py"), "--comment"], json.dumps(request))
comment = verdict.pop("comment")
with open(os.path.join(out, "verdict.json"), "w", encoding="utf-8") as fh:
    json.dump(verdict, fh, sort_keys=True)
    fh.write("\n")
with open(os.path.join(out, "comment.md"), "w", encoding="utf-8") as fh:
    fh.write(comment)


def touch(name, text=""):
    with open(os.path.join(out, name), "w", encoding="utf-8") as fh:
        fh.write(text + "\n")


touch(f"route-{verdict['route']}.txt", json.dumps(verdict, sort_keys=True))
touch(f"rule-{verdict['rule']}.txt")
if set(verdict["answers"]) == {q["id"] for q in questions}:
    touch("answers-complete.txt")
if comment.splitlines()[0] == f"<!-- idd:route v1 route={verdict['route']} -->":
    touch("comment-marker.txt")
# The comment must never echo issue text: no title, and no body line of
# twelve characters or more, may appear in it.
fragments = [issue["title"]] + [l.strip() for l in issue["body"].splitlines() if len(l.strip()) >= 12]
echoed = [f for f in fragments if f in comment]
if echoed:
    touch("comment-echoes-issue-text.txt", "\n".join(echoed))
print(f"  ○ #{verdict['number']} → {verdict['route']} (rule {verdict['rule']})")
PY
