#!/usr/bin/env bash
# test-merge-identity-516.sh — Bind merge authorization to fresh head/base identity (issue #516)
#
# Acceptance criteria:
#   AC1: a moved base or a moved head blocks a stale merge authorization.
#   AC2: patch-id equality never replaces fresh integration checks.
#
# The contract has one home — /auto-pilot's *Step 5.1c — Merge identity gate* —
# and three restatements that each guard a real merge: Phase 3-4's partial merge,
# /issue-pr-review's standalone --auto merge, and the GitHub driver catalog. A
# merge site that drifts from the home is a merge that is not guarded, so every
# site is pinned, on the authored src/ AND on the built skills/ tree.
#
# M12-M13 (#605, #606) run the shipped merge blocks against a stub `gh` and
# gi-sensitive.py against real repos: the merge is bound to the head and base
# tip the Merge floor classified.
#
# M8 is executable: it drives the gate's predicate against a real local git
# history in which the base moved, and shows that the PR's recorded base oid
# (what `baseRefOid` reports) says "fresh" while the live branch says "stale".
#
# Usage: bash tests/test-merge-identity-516.sh
# Returns: exit 0 if all checks pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

check_has() {
  local file="$1" pattern="$2" label="$3"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
    echo "      in file: ${file#$REPO_ROOT/}"
  fi
}

check_block_has() {
  local block="$1" pattern="$2" label="$3"
  if [ -n "$block" ] && printf '%s' "$block" | grep -qE "$pattern"; then
    pass "$label"
  else
    fail "$label"
    echo "      missing pattern: $pattern"
  fi
}

# shellcheck source=lib/anchors.bash
. "$REPO_ROOT/tests/lib/anchors.bash"

echo "◆ Merge identity contract (issue #516)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

SRC_AP="$REPO_ROOT/src/skills/auto-pilot"
BUILT_AP="$REPO_ROOT/skills/auto-pilot"
SRC_PR="$REPO_ROOT/src/skills/issue-pr-review"
BUILT_PR="$REPO_ROOT/skills/issue-pr-review"

# ───────────────────────────────────────────────────────────
# M1-M5: the single home — Step 5.1c, src and built.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_AP" "built:$BUILT_AP"; do
  tag="${pair%%:*}"
  pkg="${pair#*:}"
  anchor_present "$pkg" ap-merge-identity-gate \
    "M1.1 ($tag): auto-pilot owns a named merge identity gate"
  anchor_check "$pkg" ap-merge-identity-gate 'gh pr view \{pr_number\} --json headRefOid,baseRefName' \
    "M1.2 ($tag): the gate re-reads the head and the base branch name"
  anchor_check "$pkg" ap-merge-identity-gate 'compare/\$\{base_ref\}\.\.\.\$\{verified_head\}' \
    "M1.3 ($tag): the ancestry check compares the live base branch with the verified head"
  anchor_check "$pkg" ap-merge-identity-gate '`behind_by` is exactly `0`' \
    "M1.4 ($tag): fresh requires behind_by to be exactly 0"
  anchor_check "$pkg" ap-merge-identity-gate '`head_now` equals `verified_head`' \
    "M1.5 ($tag): fresh requires the head to be unchanged"
  # AC1, base half: the polarity word is `never`, not the field name.
  anchor_check_flat "$pkg" ap-merge-identity-gate 'never `baseRefOid`' \
    "M2.1 ($tag): the gate compares against the branch, never baseRefOid"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'last synchronization, not the live branch' \
    "M2.2 ($tag): and says why baseRefOid is not the live base"
  # AC1, head half: the pinned SHA comes from before the wait.
  anchor_check_flat "$pkg" ap-merge-identity-gate "Step 5\.1's own read" \
    "M3.1 ($tag): verified_head is bound from Step 5.1's read"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'Never take it from a later read' \
    "M3.2 ($tag): never from a read taken after the wait"
  # Stale outcome: no merge, no re-wait, no repair.
  anchor_check_flat "$pkg" ap-merge-identity-gate 'do \*\*not\*\* merge; outcome `left_open`' \
    "M4.1 ($tag): a stale identity does not merge and ends left_open"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'is never re-waited and never repaired' \
    "M4.2 ($tag): a stale identity is never re-waited or repaired"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'a failed read or API call' \
    "M4.3 ($tag): a failed read or compare is stale (fail-safe)"
  # AC2.
  anchor_check_flat "$pkg" ap-merge-identity-gate 'Patch-id equality never replaces fresh integration checks' \
    "M5.1 ($tag): patch-id equality never replaces fresh integration checks"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'own CI verdict on its own SHA' \
    "M5.2 ($tag): a rebased or cherry-picked twin needs its own CI on its own SHA"
  anchor_check_flat "$pkg" ap-merge-identity-gate 'compare-to-merge window' \
    "M5.3 ($tag): the remaining compare-to-merge race is stated, not hidden"
done

# ───────────────────────────────────────────────────────────
# M6: every merge command is guarded — no unguarded `gh pr merge {…} --…`
# anywhere a skill or the driver doc tells an agent to run one. A bare
# `gh pr merge {N}` with no flags is a prose mention of the command, not one.
# ───────────────────────────────────────────────────────────
for root in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills" "$REPO_ROOT/docs/platform-github.md"; do
  tag="${root#$REPO_ROOT/}"
  merges="$(grep -rhoE 'gh pr merge \{[^}]*\} --[^`|]*' "$root" 2>/dev/null || true)"
  total="$(printf '%s\n' "$merges" | grep -c 'gh pr merge' || true)"
  unguarded="$(printf '%s\n' "$merges" | grep 'gh pr merge' | grep -vc -- '--match-head-commit' || true)"
  if [ "$total" -gt 0 ] && [ "$unguarded" = "0" ]; then
    pass "M6 ($tag): all $total merge commands carry --match-head-commit"
  else
    fail "M6 ($tag): $unguarded of $total merge commands are unguarded"
    printf '%s\n' "$merges" | grep 'gh pr merge' | grep -v -- '--match-head-commit' | sed 's/^/      /'
  fi
done

# M6b: the shipped merge snippets execute the predicate — a comment in front of
# an unconditional merge would merge onto a moved base when run verbatim.
GUARD_RE='^ *if \[ -n "\$verified_head" \] && \[ "\$head_now" = "\$verified_head" \] && \[ "\$behind_by" = "0" \]; then$'
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  for rel in auto-pilot/references/phases/phase-5-merge.md \
             auto-pilot/references/phases/phase-3-4-review.md \
             issue-pr-review/references/report-templates.md; do
    f="$base/$rel"
    if grep -A1 -E "$GUARD_RE" "$f" 2>/dev/null | grep -qE 'gh pr merge \{[^}]*\} --\{merge_method\} --delete-branch --match-head-commit "\$verified_head" --body-file "\$body_file"$'; then
      pass "M6b (${f#$REPO_ROOT/}): the merge runs inside the identity predicate"
    else
      fail "M6b (${f#$REPO_ROOT/}): the merge is not guarded by an executable predicate"
    fi
  done
done

# M6c: each shipped merge block is self-contained. An agent's shell drops
# variables between tool calls, so a guard that reads $verified_head/$head_now/
# $behind_by bound in another block sees "" and silently skips the merge. The
# fenced block holding the guard must bind all three itself and have an `else`
# branch that exits non-zero, so a skipped merge is visible and never `merged`.
# guarded_block FILE — print the fenced block that contains the guard line.
guarded_block() {
  GUARD_RE="$GUARD_RE" awk '
    BEGIN { re = ENVIRON["GUARD_RE"] }
    /^```/ { if (inb) { if (hit) { printf "%s", buf; exit } inb=0; buf="" } else { inb=1; hit=0; buf="" } next }
    inb { buf = buf $0 "\n"; if ($0 ~ re) hit=1 }
  ' "$1" 2>/dev/null || true
}
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  for rel in auto-pilot/references/phases/phase-5-merge.md \
             auto-pilot/references/phases/phase-3-4-review.md \
             issue-pr-review/references/report-templates.md; do
    f="$base/$rel"
    blk="$(guarded_block "$f")"
    label="M6c (${f#$REPO_ROOT/}): the guarded merge block binds its own identity"
    if [ -n "$blk" ] \
       && printf '%s' "$blk" | grep -qE '^verified_head="' \
       && printf '%s' "$blk" | grep -qE '^read -r head_now base_ref <<<' \
       && printf '%s' "$blk" | grep -qE '^read -r behind_by base_tip <<<"\$\(gh api .*\.base_commit\.sha' \
       && printf '%s' "$blk" | grep -qE '^else$'; then
      pass "$label"
    else
      fail "$label"
    fi
  done
done
# M6d (#564): the same block reads the PR body into the file it passes, with
# `--json`, and a failed read empties $verified_head so the guard refuses.
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  for rel in auto-pilot/references/phases/phase-5-merge.md \
             auto-pilot/references/phases/phase-3-4-review.md \
             issue-pr-review/references/report-templates.md; do
    f="$base/$rel"
    blk="$(guarded_block "$f")"
    check_block_has "$blk" '^body_file="\$\(mktemp\)"; gh pr view \{[^}]*\} --json body --jq \.body >"\$body_file" \|\| verified_head=""$' \
      "M6d (${f#$REPO_ROOT/}): the merge block reads the PR body to a file, fail-closed"
    check_block_has "$blk" "^trap 'rm -f \"\\\$body_file\"' EXIT" \
      "M6d (${f#$REPO_ROOT/}): the merge block removes the body file on every path"
  done
done
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  for rel in auto-pilot/references/phases/phase-5-merge.md \
             auto-pilot/references/phases/phase-3-4-review.md; do
    f="$base/$rel"
    blk="$(guarded_block "$f")"
    check_block_has "$blk" 'echo "merge_identity=stale .*exit 1' \
      "M6c (${f#$REPO_ROOT/}): a stale identity prints and exits non-zero"
  done
done

# ───────────────────────────────────────────────────────────
# M7: the partial-merge path and the critical-issue merge use the same gate.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_AP" "built:$BUILT_AP"; do
  tag="${pair%%:*}"
  pkg="${pair#*:}"
  phase34="$pkg/references/phases/phase-3-4-review.md"
  step2a="$(awk '/Step 2a — Dependency and CI gates/{f=1; next} f && /^\*\*Step 2b/{exit} f' "$phase34")"
  check_block_has "$step2a" 'Step 5\.1c — Merge identity gate' \
    "M7.1 ($tag): Phase 3-4 Step 2a runs the merge identity gate"
  check_block_has "$step2a" 'do \*\*not\*\* merge' \
    "M7.2 ($tag): a stale identity on the partial path does not merge"
  anchor_check "$pkg" ap-step2b-merge 'gh pr merge \{pr_number\} --\{merge_method\} --delete-branch --match-head-commit "\$verified_head"' \
    "M7.3 ($tag): Step 2b merges with the expected-head guard"
  check_has "$phase34" 'Option 1:.*Step 5\.1c' \
    "M7.4 ($tag): the critical-issue Option 1 merge runs the same gate"
  check_has "$pkg/references/phases/phase-5-merge.md" 'gh pr merge \{pr_number\} --\{merge_method\} --delete-branch --match-head-commit "\$verified_head"' \
    "M7.5 ($tag): Step 5.2 merges with the expected-head guard"
done

# ───────────────────────────────────────────────────────────
# M9: /issue-pr-review's standalone --auto merge restates the subset it needs.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR" "built:$BUILT_PR"; do
  tag="${pair%%:*}"
  pkg="${pair#*:}"
  anchor_check "$pkg" rv-merge-identity '--match-head-commit' \
    "M9.1 ($tag): pr-review's auto-merge is guarded by the expected head"
  anchor_check "$pkg" rv-merge-identity '`behind_by` is exactly `0`' \
    "M9.2 ($tag): pr-review's auto-merge requires a fresh live base"
  anchor_check "$pkg" rv-merge-identity 'never `baseRefOid`' \
    "M9.3 ($tag): pr-review compares the branch, never baseRefOid"
  anchor_check "$pkg" rv-merge-identity 'never a re-wait' \
    "M9.4 ($tag): a stale identity blocks, never re-waits"
  anchor_check "$pkg" rv-merge-identity 'Patch-id equality never replaces fresh integration checks' \
    "M9.5 ($tag): pr-review states the patch-id prohibition"
  check_has "$pkg/references/report-templates.md" 'BLOCKED \(stale merge authorization\)' \
    "M9.6 ($tag): the report has a stale-merge-authorization outcome"
  check_has "$pkg/references/error-messages.md" '^### Stale merge authorization' \
    "M9.7 ($tag): pr-review's error catalog has the stale-identity block"
done

# ───────────────────────────────────────────────────────────
# M10: the driver catalog and auto-pilot's error catalog.
# ───────────────────────────────────────────────────────────
for f in "$REPO_ROOT/docs/platform-github.md" "$BUILT_AP/references/docs/platform-github.md"; do
  tag="${f#$REPO_ROOT/}"
  check_has "$f" '^\| Merge identity \(live base ancestry\) \|.*--jq \.behind_by' \
    "M10.1 ($tag): the driver catalog has the merge identity operation"
  check_has "$f" '^\| Merge \+ clean up \| `gh pr merge \{N\} --\{merge_method\} --delete-branch --match-head-commit \{verified_head\} --body-file \{f\}`' \
    "M10.2 ($tag): the catalog's merge row is guarded and carries the PR body"
  check_has "$f" 'never `baseRefOid`' \
    "M10.3 ($tag): the catalog says never baseRefOid"
done
for pair in "src:$SRC_AP" "built:$BUILT_AP"; do
  tag="${pair%%:*}"
  check_has "${pair#*:}/references/error-messages.md" '^### Stale merge authorization' \
    "M10.4 ($tag): auto-pilot's error catalog has the stale-identity block"
done

# ───────────────────────────────────────────────────────────
# M8 (executable, AC1): the gate's predicate over a real git history.
#
# merge_identity VERIFIED_HEAD HEAD_NOW BEHIND_BY — the table in Step 5.1c:
# fresh only on an unchanged 40-hex head and an integer behind_by of exactly 0.
# ───────────────────────────────────────────────────────────
merge_identity() {
  local verified="$1" now="$2" behind="$3"
  printf '%s' "$verified" | grep -qE '^[0-9a-f]{40}$' || { echo stale; return; }
  [ "$now" = "$verified" ] || { echo stale; return; }
  [ "$behind" = "0" ] || { echo stale; return; }
  echo fresh
}

check_identity() {
  local want="$1" label="$2" got
  got="$(merge_identity "$3" "$4" "$5")"
  if [ "$got" = "$want" ]; then pass "$label"; else fail "$label (got $got)"; fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
(
  cd "$TMP"
  git init -q -b main repo
  cd repo
  git config user.email t@example.invalid
  git config user.name test
  git commit -q --allow-empty -m base0
  git checkout -q -b feature
  echo change > f.txt && git add f.txt && git commit -q -m feature
  git checkout -q main
) >/dev/null
R="$TMP/repo"
base_at_sync="$(git -C "$R" rev-parse main)"      # what baseRefOid would report
verified="$(git -C "$R" rev-parse feature)"        # the head CI checked
# `compare/{base}...{head}` answers behind_by = commits on base not on head.
behind() { git -C "$R" rev-list --count "$verified..$1"; }

check_identity fresh "M8.1: an unchanged head on an unmoved base is fresh" \
  "$verified" "$verified" "$(behind main)"

# The base advances after the CI verdict — a clean, conflict-free advance.
git -C "$R" commit -q --allow-empty -m "base moved"
check_identity stale "M8.2 (AC1): a moved base makes the authorization stale" \
  "$verified" "$verified" "$(behind main)"
# The trap the gate names: the recorded base oid still answers 0.
check_identity fresh "M8.3: (vacuity guard) the recorded base oid alone still looks fresh" \
  "$verified" "$verified" "$(behind "$base_at_sync")"

# The head moves after the CI verdict: a patch-identical rebase onto the new base.
git -C "$R" checkout -q feature
git -C "$R" rebase -q main
moved="$(git -C "$R" rev-parse feature)"
if [ "$(git -C "$R" show "$verified" | git -C "$R" patch-id --stable | cut -d' ' -f1)" = \
     "$(git -C "$R" show "$moved" | git -C "$R" patch-id --stable | cut -d' ' -f1)" ]; then
  pass "M8.4: (fixture) the rebased head is patch-id-equal to the verified one"
else
  fail "M8.4: (fixture) the rebased head is not patch-id-equal — the AC2 fixture is inert"
fi
check_identity stale "M8.5 (AC1/AC2): a moved head is stale even when patch-id-equal" \
  "$verified" "$moved" "$(git -C "$R" rev-list --count "$moved..main")"

check_identity stale "M8.6: an empty behind_by (failed compare) is stale" "$verified" "$verified" ""
check_identity stale "M8.7: a non-integer behind_by is stale" "$verified" "$verified" "null"
check_identity stale "M8.8: a short head SHA is stale" "${verified:0:7}" "${verified:0:7}" "0"

# ───────────────────────────────────────────────────────────
# M11-M13 (#605, #606): the merge is bound to the head and base tip the Merge
# floor classified. #605 N2: a push after review must not merge on the old
# floor. #606 R5: a retargeted base (variant A) or a stale local origin/<base>
# (variant B) must not merge on a floor classified against another base.
# ───────────────────────────────────────────────────────────
for pair in "src:$SRC_PR/SKILL.source.md" "built:$BUILT_PR/SKILL.md"; do
  tag="${pair%%:*}"
  f="${pair#*:}"
  floor="$(grep -F 'a:rv-merge-floor' "$f")"
  check_block_has "$floor" "step 4's bind, fetch and classify rerun here" \
    "M11.1 ($tag): the floor re-binds and re-fetches the base right before its classify"
  check_block_has "$floor" '`met` reads `met@\{verified_head\}:\{floor_base\}`' \
    "M11.2 ($tag): a met floor names the head and base tip it classified"
  check_block_has "$(grep -F 'a:rv-merge-identity' "$f")" 'base tip `floor_base`' \
    "M11.3 ($tag): merge identity requires the live base tip the floor classified"
done
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  rt="$base/issue-pr-review/references/report-templates.md"
  check_has "$rt" 'is the \*Merge floor\*.s `git rev-parse "origin/\$\{base_ref\}"`' \
    "M11.4 (${rt#$REPO_ROOT/}): {floor_base} is the tip the floor fetched and classified"
  check_has "$base/auto-pilot/references/prompts/reviewer.md" '^  `met` returned whole as `met@<sha40>:<sha40>`' \
    "M11.5 (${base#$REPO_ROOT/}): the auto-pilot reviewer returns the floor's binding"
  anchor_check_flat "$base/auto-pilot" ap-merge-identity-gate 'pasted only as `met@<40 hex>:<40 hex>`' \
    "M11.6 (${base#$REPO_ROOT/}): only a well-formed floor binding is pasted into the shell"
  anchor_check_flat "$base/auto-pilot" ap-merge-identity-gate 'a floor bound to another head or base tip' \
    "M11.7 (${base#$REPO_ROOT/}): a floor bound to another head or base tip is stale"
done

# M12 (executable): run each shipped guarded block, placeholders filled, with a
# stub `gh` that answers the live head, base name, behind_by and base tip.
STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "pr view") case "$*" in
      *headRefOid,baseRefName*) printf '%s %s\n' "$STUB_HEAD" "$STUB_BASE" ;;
      *"--json body"*) echo body ;;
    esac ;;
  "api "*) case "$*" in *base_commit*) printf '%s %s\n' "$STUB_BEHIND" "$STUB_TIP" ;;
      *) echo "$STUB_BEHIND" ;; esac ;;
  "pr merge") echo merged >> "$STUB_LOG" ;;
esac
GH
chmod +x "$STUB/gh"
H1="$(printf 'a%.0s' $(seq 40))"; H2="$(printf 'b%.0s' $(seq 40))"
T1="$(printf 'c%.0s' $(seq 40))"; T2="$(printf 'd%.0s' $(seq 40))"
# run_block BLOCK FLOOR_HEAD FLOOR_TIP HEAD_NOW BASE_NAME BEHIND LIVE_TIP → merged|blocked
run_block() {
  local blk="$1" filled log="$TMP/merge.log"
  filled="$(printf '%s' "$blk" | sed -e "s|{ci_sha}|$4|; s|{verified_head}|$4|" \
    -e "s|{floor_base}|$3|; s|{merge_floor}|met@$2:$3|" \
    -e 's|{N}|7|g; s|{pr_number}|7|g; s|{merge_method}|squash|')"
  rm -f "$log"
  PATH="$STUB:$PATH" STUB_HEAD="$4" STUB_BASE="$5" STUB_BEHIND="$6" STUB_TIP="$7" STUB_LOG="$log" \
    bash -c "$filled" >/dev/null 2>&1 || true
  [ -s "$log" ] && echo merged || echo blocked
}
expect() { if [ "$2" = "$1" ]; then pass "$3"; else fail "$3 (got $2)"; fi; }
for base in "$REPO_ROOT/src/skills" "$REPO_ROOT/skills"; do
  for rel in auto-pilot/references/phases/phase-5-merge.md \
             auto-pilot/references/phases/phase-3-4-review.md \
             issue-pr-review/references/report-templates.md; do
    f="$base/$rel"; tag="${f#$REPO_ROOT/}"
    blk="$(guarded_block "$f")"
    expect merged "$(run_block "$blk" "$H1" "$T1" "$H1" main 0 "$T1")" \
      "M12.1 ($tag): (vacuity guard) an unchanged head and base tip merges"
    expect blocked "$(run_block "$blk" "$H1" "$T1" "$H1" release 0 "$T2")" \
      "M12.2 ($tag): variant A — a PR retargeted to a base the head contains is blocked"
    expect blocked "$(run_block "$blk" "$H1" "$T1" "$H1" main 0 "$T2")" \
      "M12.3 ($tag): variant B — a floor classified on a stale base tip is blocked"
    # Without the floor-binding line the same two answers merge: the line is the fix.
    unbound="$(printf '%s\n' "$blk" | grep -v '^\[ .*\] || verified_head=""$')"
    expect merged "$(run_block "$unbound" "$H1" "$T1" "$H1" release 0 "$T2")" \
      "M12.4 ($tag): (red without the fix) the unbound block merges the retargeted PR"
    case "$rel" in auto-pilot/*)
      # #605 N2: Step 5.1c's verified_head is Step 5.1's read (H2); the floor ran at H1.
      expect blocked "$(run_block "$blk" "$H1" "$T1" "$H2" main 0 "$T1")" \
        "M12.5 ($tag): #605 N2 — a push after review never merges on the old floor"
      expect merged "$(run_block "$unbound" "$H1" "$T1" "$H2" main 0 "$T1")" \
        "M12.6 ($tag): (red without the fix) the unbound block merges on the old floor" ;;
    esac
  done
done

# M13 (executable, #606 variant B): the floor's fresh fetch changes the tier.
# The base gains a workflow (sensitive) commit; the head contains it and then
# reverts it. Against a stale local origin/main the revert cancels out and the
# range looks standard; after the fetch the range is the revert — sensitive.
SEN="$REPO_ROOT/src/shared/scripts/gi-sensitive.py"
gx() { git -C "$1" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "${@:2}"; }
tier() { (cd "$TMP/rev" && printf '{"labels":[],"paths":[],"diff":"origin/main...%s"}' "$1" \
  | python3 "$SEN" --classify 2>/dev/null) | python3 -c 'import json,sys; print(json.load(sys.stdin)["tier"])' 2>/dev/null; }
if git init -q --bare -b main "$TMP/origin.git" && git clone -q "$TMP/origin.git" "$TMP/w" 2>/dev/null \
   && echo r > "$TMP/w/README" && gx "$TMP/w" add -A && gx "$TMP/w" commit -q -m base0 && gx "$TMP/w" push -q origin HEAD:main \
   && git clone -q "$TMP/origin.git" "$TMP/rev" \
   && mkdir -p "$TMP/w/.github/workflows" && echo 'on: push' > "$TMP/w/.github/workflows/s.yml" \
   && gx "$TMP/w" add -A && gx "$TMP/w" commit -q -m sensitive && gx "$TMP/w" push -q origin HEAD:main \
   && gx "$TMP/w" rm -q .github/workflows/s.yml && echo n > "$TMP/w/notes.txt" && gx "$TMP/w" add -A \
   && gx "$TMP/w" commit -q -m revert && gx "$TMP/w" push -q origin HEAD:pr \
   && gx "$TMP/rev" fetch -q origin pr:refs/remotes/origin/pr; then
  pass "M13.1: (fixture) stale origin/main in the reviewer's clone; the head reverts a base workflow commit"
else
  fail "M13.1: (fixture) could not build the variant B repos"
fi
head="$(gx "$TMP/rev" rev-parse origin/pr)"
expect standard "$(tier "$head")" "M13.2: (the hole) a stale origin/main classifies the reverting head standard"
gx "$TMP/rev" fetch -q origin -- main
expect sensitive "$(tier "$head")" "M13.3: after the floor's fresh fetch the same head is sensitive"

echo ""
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Result: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
