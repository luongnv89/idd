#!/usr/bin/env bash
# issue-resolver plan/claim stand-in (foreign-claim): read issue #648 under the
# PATH-shimmed gh exactly as docs/plan-and-claim.md does (*Reading the issue*),
# and decide through the REAL gi-plan.py. Another account's run holds the claim, so the run stops claimed_elsewhere and touches nothing.
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
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if (d["claim_run"], d["claim_branch"]) == ("resolver-20261119T110000Z-ffff", "feat/648-other") else 1)' "$EVAL_OUT/check.json" \
  && : > "$EVAL_OUT/claim-named.txt"
cat > "$EVAL_OUT/run.json" <<'JSON'
{"ts": "2026-11-19T12:00:00Z", "issue": 648, "mode": "auto", "skill": "issue-resolver", "outcome": "failed", "pr": null, "skipped_reason": "claimed_elsewhere", "duration_s": 7}
JSON
