#!/usr/bin/env bash
# pr-review stand-in: the revert path (#571), `/issue-pr-review 12 --revert`.
#
# PR #12 (`Closes #7`) was squash-merged into main of a local bare remote. The
# subject follows references/revert-path.md: read #12, revert its squash commit
# on fix/7-revert-pr-12 made from origin/main, scan the staged set, commit with
# git's own message, push that branch only, open the revert PR with the
# documented body, reopen #7 with a comment linking the revert, and write the
# `revert_opened` run-log row (`pr` is the reverted PR, never the revert PR).
#
# Commits use fixed identities and dates, so the squash commit's sha is the one
# the cassette's `mergeCommit.oid` names; a host that hashes differently fails
# loudly below. Each verified decision is emitted as a file named after it, so
# case.json asserts it with `file-exists`.
set -euo pipefail

: "${EVAL_OUT:?EVAL_OUT is required}"
: "${EVAL_SCRIPTS_DIR:?EVAL_SCRIPTS_DIR is required}"

export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=eval GIT_AUTHOR_EMAIL=eval@harness.local
export GIT_COMMITTER_NAME=eval GIT_COMMITTER_EMAIL=eval@harness.local
export GIT_AUTHOR_DATE='2026-11-01T12:00:00Z' GIT_COMMITTER_DATE='2026-11-01T12:00:00Z'

# Fixture: main holds an initial commit and PR #12's squash commit.
git init -q --bare -b main origin.git
git init -q -b main work
cd work
git config commit.gpgsign false
echo "app" > app.txt
git add app.txt
git commit -qm "chore(init): scaffold app (#1)"
echo "x" > x.txt
git add x.txt
git commit -qm "feat(x): add x (#7) (#12)"
git remote add origin ../origin.git
git push -q origin main

# 1. Read M.
gh pr view 12 --json number,title,body,state,baseRefName,url,mergeCommit > "$EVAL_OUT/pr-view.json"
read -r state base oid issue title owner_repo < <(python3 - "$EVAL_OUT/pr-view.json" <<'PY'
import json, re, sys
pr = json.load(open(sys.argv[1], encoding="utf-8"))
m = re.search(r"(?i)\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s+#(\d+)", pr["body"])
owner_repo = "/".join(pr["url"].split("/")[3:5])
print(pr["state"], pr["baseRefName"], pr["mergeCommit"]["oid"], m.group(1) if m else "-",
      pr["title"].replace(" ", "\x1f"), owner_repo)
PY
)
title="${title//$'\x1f'/ }"
[ "$state" = "MERGED" ] || { echo "✗ PR #12 is not merged ($state) — nothing to revert"; exit 1; }
[ "$issue" = "7" ] || { echo "✗ linked issue not read from the body"; exit 1; }

# 2. Revert on a branch made from the base.
git fetch -q origin "$base"
[ "$(git rev-parse "origin/$base")" = "$oid" ] \
  || { echo "✗ fixture sha $(git rev-parse "origin/$base") differs from the cassette oid $oid"; exit 1; }
base_before="$(git ls-remote origin "refs/heads/$base" | cut -f1)"
parents=$(( $(git rev-list --parents -n 1 "$oid" | wc -w) - 1 ))
subject="$(git log -1 --format=%s "$oid")"
if [ "$parents" -eq 1 ] && [[ "$subject" == *"(#12)" ]]; then
  method=squash
elif [ "$parents" -eq 2 ]; then
  method=merge
else
  echo "✗ PR #12 was rebase-merged — no single commit to revert"; exit 1
fi
branch="fix/${issue}-revert-pr-12"
git switch -q -c "$branch" "origin/$base"
if [ "$method" = merge ]; then git revert --no-commit -m 1 "$oid"; else git revert --no-commit "$oid"; fi
printf '%s\n' "$method" > "$EVAL_OUT/method.txt"

# 3. Scan the staged set against the default branch's policy, then commit and push.
policy_base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"
python3 "$EVAL_SCRIPTS_DIR/gi-secscan.py" --staged --policy-ref "origin/${policy_base}" > "$EVAL_OUT/secscan.json"
python3 - "$EVAL_OUT/secscan.json" "origin/${policy_base}" <<'PY'
import json, sys
v = json.load(open(sys.argv[1], encoding="utf-8"))
ok = (v.get("verdict") != "block" and v.get("policy_source") == "ref:" + sys.argv[2]
      and not (v.get("scanned") == 0 and v.get("skipped", 0) > 0))
sys.exit(0 if ok else 1)
PY
git commit -q --no-edit
git push -q -u origin "$branch"
git log -1 --format=%B > "$EVAL_OUT/revert-commit.txt"
printf '%s\n' "$branch" > "$EVAL_OUT/branch.txt"
git log -1 --format=%s > "$EVAL_OUT/commit-subject.txt"

# 4. Open R. Fixed relative body path, so the recorded argv is the same on every run.
cat > revert-body.md <<EOF
Reverts ${owner_repo}#12

This reverts commit ${oid}.

Rolls back the x feature after a regression in production. Reopens #${issue}.

> **Note:** No acceptance criteria defined — a revert restores the code before #12.
EOF
pr_url="$(gh pr create --base "$base" --head "$branch" --title "Revert \"$title\"" --body-file revert-body.md)"
revert_pr="${pr_url##*/}"
gh pr view "$revert_pr" --json number,url,state > "$EVAL_OUT/revert-pr.json"
cp revert-body.md "$EVAL_OUT/revert-body.md"

# 5. Reopen N with a comment linking the revert, then re-read it.
gh issue reopen "$issue"
printf 'Reopened: #12 is being reverted in #%s (%s).\n' "$revert_pr" "$pr_url" > reopen-comment.md
gh issue comment "$issue" --body-file reopen-comment.md
cp reopen-comment.md "$EVAL_OUT/reopen-comment.md"
issue_state="$(gh issue view "$issue" --json state --jq .state)"

# 6. The run-log row.
printf '{"issue":%s,"mode":"auto","skill":"issue-pr-review","outcome":"revert_opened","pr":12,"revert_pr":%s}\n' \
  "$issue" "$revert_pr" > "$EVAL_OUT/run-log-row.json"

# Decisions, each emitted only when verified.
[ "$(git ls-remote origin "refs/heads/$base" | cut -f1)" = "$base_before" ] && : > "$EVAL_OUT/base-unchanged.txt"
[ -n "$(git ls-remote origin "refs/heads/$branch")" ] && : > "$EVAL_OUT/revert-branch-pushed.txt"
grep -qxF "This reverts commit ${oid}." "$EVAL_OUT/revert-commit.txt" && : > "$EVAL_OUT/commit-keeps-footer.txt"
[ ! -e x.txt ] && : > "$EVAL_OUT/change-reverted.txt"
python3 - "$EVAL_OUT/revert-body.md" "$owner_repo" "$oid" "$EVAL_OUT" <<'PY'
import os, re, sys
body, owner_repo, oid, out = sys.argv[1:]
lines = open(body, encoding="utf-8").read().splitlines()
closer = re.search(r"(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?)\s+#\d+", "\n".join(lines))
if lines[0] == f"Reverts {owner_repo}#12" and f"This reverts commit {oid}." in lines and not closer:
    open(os.path.join(out, "body-ok.txt"), "w").close()
PY
grep -qF "$pr_url" "$EVAL_OUT/reopen-comment.md" && : > "$EVAL_OUT/comment-links-revert.txt"
[ "$issue_state" = "OPEN" ] && : > "$EVAL_OUT/issue-open.txt"

{
  printf '◆ Revert of #12\n'
  printf '  ✓ #%s opened against %s\n    %s\n' "$revert_pr" "$base" "$pr_url"
  printf '  ✓ #%s reopened, linked to #%s\n' "$issue" "$revert_pr"
  printf '  ✓ run log: revert_opened\n'
} > "$EVAL_OUT/report.txt"
