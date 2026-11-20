#!/usr/bin/env bash
# issue-resolver plan/claim stand-in (plan-required): read issue #648 under the
# PATH-shimmed gh exactly as docs/plan-and-claim.md does (*Reading the issue*),
# and decide through the REAL gi-plan.py. No plan comment exists, so the run posts one and, under plan_approval: human, stops awaiting approval.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

PLAN="$EVAL_SCRIPTS_DIR/gi-plan.py"
gh auth status >/dev/null
login="$(gh api user --jq .login)"
claim_run="resolver-20261119T120000Z-a1b2"
claim_label="agent:working"
gh issue view 648 --json body,labels,comments > "$EVAL_OUT/issue.json"
python3 "$PLAN" check --login "$login" --run "$claim_run" --claim-label "$claim_label" \
  < "$EVAL_OUT/issue.json" > "$EVAL_OUT/check.json"
state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$EVAL_OUT/check.json" "$1"; }
: > "$EVAL_OUT/plan-$(state plan).txt"
: > "$EVAL_OUT/claim-$(state claim).txt"
[ "$(state approved)" = True ] && : > "$EVAL_OUT/approved.txt"
# The plan step: render from the live body (--issue), as *Posting a plan* does,
# then re-read the issue with the posted comment appended.
gh issue view 648 --json body > "$EVAL_OUT/body.json"
cat > "$EVAL_OUT/plan-input.json" <<'JSON'
{"criteria": [{"id": "AC1", "text": "The settings page shows a dark mode toggle"}, {"id": "AC2", "text": "The choice persists across reloads"}], "option": {"name": "Minimal toggle", "summary": "Add the toggle and persist it in local storage", "files_to_modify": [{"path": "src/settings.js", "changes": "render the toggle"}], "files_to_create": [{"path": "tests/settings.test.js", "purpose": "toggle tests"}], "criteria_covered": ["AC1", "AC2"], "test_strategy": "unit tests for the toggle and persistence", "risk_details": "low: settings page only"}}
JSON
python3 "$PLAN" render-plan --issue "$EVAL_OUT/body.json" < "$EVAL_OUT/plan-input.json" > "$EVAL_OUT/plan.md"
python3 - "$EVAL_OUT/issue.json" "$EVAL_OUT/plan.md" "$login" > "$EVAL_OUT/issue-after.json" <<'PY'
import json, sys
issue = json.load(open(sys.argv[1]))
issue["labels"] = [l for l in issue["labels"] if l["name"] != "plan-approved"] + [{"name": "planned"}]
issue["comments"].append({"author": {"login": sys.argv[3]}, "body": open(sys.argv[2]).read(),
                          "createdAt": "2026-11-19T12:00:00Z"})
print(json.dumps(issue))
PY
python3 "$PLAN" check --login "$login" --run "$claim_run" --claim-label "$claim_label" \
  < "$EVAL_OUT/issue-after.json" > "$EVAL_OUT/check-after.json"
after() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$EVAL_OUT/check-after.json" "$1"; }
: > "$EVAL_OUT/after-plan-$(after plan).txt"
[ "$(after approved)" = True ] && : > "$EVAL_OUT/after-approved.txt"
head -1 "$EVAL_OUT/plan.md" | grep -qE '^<!-- idd:plan v1 body=[0-9a-f]{16} -->$' && : > "$EVAL_OUT/plan-marker.txt"
# Under plan_approval: human the run stops only when the posted plan is not approved.
if [ "$(after approved)" != True ]; then
  cat > "$EVAL_OUT/run.json" <<'JSON'
{"ts": "2026-11-19T12:00:00Z", "issue": 648, "mode": "auto", "skill": "issue-resolver", "outcome": "failed", "pr": null, "skipped_reason": "plan_awaiting_approval", "duration_s": 7}
JSON
fi
