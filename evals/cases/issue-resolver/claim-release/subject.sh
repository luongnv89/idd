#!/usr/bin/env bash
# issue-resolver plan/claim stand-in (claim-release): read issue #648 under the
# PATH-shimmed gh exactly as docs/plan-and-claim.md does (*Reading the issue*),
# and decide through the REAL gi-plan.py. This run's own claim reads own, so Release removes it; a run with another id would leave it.
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
[ "$(state claim)" = own ] && : > "$EVAL_OUT/release.txt"
python3 "$PLAN" check --login "$login" --run resolver-other-run --claim-label "$claim_label" \
  < "$EVAL_OUT/issue.json" > "$EVAL_OUT/check-other.json"
[ "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["claim"])' "$EVAL_OUT/check-other.json")" = own ] \
  && : > "$EVAL_OUT/release-foreign.txt"
true
