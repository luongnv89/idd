#!/usr/bin/env bash
# pr-review stand-in: a repo that merges by merge commit keeps its settings
# (issue #564, AC1).
#
# The fixture repo allows merge commits only and leaves both message sources at
# GitHub's defaults. `.idd.yml` sets `review.merge_method: merge` and
# `review.auto_merge: true`. Traceability check 4 judges the repo against that
# method (verification-checks.md), so it passes with a hand-merge note, and the
# merge runs the Auto-Merge block from report-templates.md: `--merge`, the
# head guard, and the PR body passed as a file so the merge commit carries it.
# No call changes a repository setting — case.json asserts the whole gh argv
# sequence.
#
# Each decision is emitted as a file named after it, so case.json asserts the
# outcome with `file-exists`: a check that decides differently does not create
# the file the case expects.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"

cat > .idd.yml <<'YML'
review:
  auto_merge: true
  merge_method: merge
YML

# Config load by hand (the prose fallback): one of three values, else stop.
merge_method="$(awk '/^review:/{f=1; next} /^[^[:space:]#]/{f=0} f && $1 == "merge_method:" {print $2}' .idd.yml)"
merge_method="${merge_method:-squash}"
case "$merge_method" in
  squash|merge|rebase) ;;
  *) echo "✗ Invalid config: .idd.yml review.merge_method" >&2; exit 3 ;;
esac

gh auth status >/dev/null
gh pr view 12 --json number,title,body,state,headRefOid > "$EVAL_OUT/pr-view.json"

# Traceability check 4: both reads, judged against the configured method.
gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed > "$EVAL_OUT/strategy.json"
gh api repos/acme/app --jq '{squash_merge_commit_message, merge_commit_message}' > "$EVAL_OUT/message-source.json"

EVAL_OUT="$EVAL_OUT" METHOD="$merge_method" python3 - <<'PY'
import json
import os

out = os.environ["EVAL_OUT"]
method = os.environ["METHOD"]
with open(os.path.join(out, "strategy.json"), encoding="utf-8") as fh:
    strategy = json.load(fh)
with open(os.path.join(out, "message-source.json"), encoding="utf-8") as fh:
    source = json.load(fh)

allowed_flag = {"squash": "squashMergeAllowed", "merge": "mergeCommitAllowed"}
source_field = {"squash": "squash_merge_commit_message", "merge": "merge_commit_message"}
binding = {"squash": "B1/squash", "merge": "B2/merge"}

if method == "rebase":
    line, verdict = "partial — tracker-only, no commit binding (review.merge_method: rebase)", "partial-rebase"
elif strategy.get(allowed_flag[method]) is not True:
    line, verdict = f"partial — merge method not allowed (review.merge_method: {method})", "partial-not-allowed"
else:
    line, verdict = f"pass ({binding[method]}: body passed at merge)", f"pass-{method}"
    field = source_field[method]
    value = source.get(field, "unread")
    if value != "PR_BODY":
        line += f"\n○ a hand merge will not carry the PR body ({field}: {value})"
        open(os.path.join(out, f"hand-merge-note-{field}-{value}.txt"), "w").close()
open(os.path.join(out, f"traceability-{verdict}.txt"), "w").close()
with open(os.path.join(out, "traceability.txt"), "w", encoding="utf-8") as fh:
    fh.write(line + "\n")
PY

grep -q '^pass ' "$EVAL_OUT/traceability.txt" || { echo "BLOCKED (traceability not pass)"; exit 1; }

# Auto-Merge block (report-templates.md), {N}=12, {merge_method} from config.
# The body file is a relative path so the recorded argv is the same on every run.
verified_head="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["headRefOid"])' "$EVAL_OUT/pr-view.json")"
body_file="pr-body.txt"; gh pr view 12 --json body --jq .body >"$body_file" || verified_head=""
read -r head_now base_ref <<<"$(gh pr view 12 --json headRefOid,baseRefName --jq '"\(.headRefOid) \(.baseRefName)"')"
behind_by="$(gh api "repos/acme/app/compare/${base_ref}...${verified_head}" --jq .behind_by)"
if [ -n "$verified_head" ] && [ "$head_now" = "$verified_head" ] && [ "$behind_by" = "0" ]; then
  gh pr merge 12 "--$merge_method" --delete-branch --match-head-commit "$verified_head" --body-file "$body_file"
else
  echo "BLOCKED (stale merge authorization)"; exit 1
fi

cp "$body_file" "$EVAL_OUT/merge-body.txt"
: > "$EVAL_OUT/merged-by-$merge_method.txt"
{
  printf 'Result: MERGED — PR #12 merged (%s), branch feat/77-export-csv deleted\n' "$merge_method"
  printf 'Evidence: traceability %s; head %s unchanged, base not ahead\n' "$(head -1 "$EVAL_OUT/traceability.txt")" "$verified_head"
  printf 'Uncertainty: %s\n' "$(sed -n 2p "$EVAL_OUT/traceability.txt")"
  printf 'Decision: No approval needed.\n'
} > "$EVAL_OUT/report.txt"
