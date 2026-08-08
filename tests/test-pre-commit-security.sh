#!/usr/bin/env bash
# test-pre-commit-security.sh — Validate the pre-commit security convention (issue #87)
#
# This script verifies issue #87 acceptance criteria:
#   AC #1: A shared pre-commit safety scan procedure exists at
#          docs/pre-commit-security.md with the secret/credential/large-file
#          checks adopted from /auto-push.
#   AC #2: Every skill that runs `git commit` or `git push` references this
#          shared scan in a fenced block that also (or in nearby prose) cites
#          docs/pre-commit-security.md, so the gate cannot be silently dropped.
#   AC #3: The canonical doc explicitly distinguishes real secrets from
#          placeholders (covers AC #3 from the issue).
#   AC #4: The canonical doc defines the rich-error format that skills use
#          when a secret blocks (covers AC #4 from the issue).
#   AC #5: The canonical doc states warnings are non-blocking and require
#          explicit confirmation in interactive mode / log-and-continue in
#          auto mode (covers AC #5 from the issue).
#
# Strategy: walk every fenced code block (```bash / ```sh) in
# src/skills/**/*.md, src/internal-skills/**/*.md, and
# src/shared/agents/*.md, looking for `git commit` or `git push`. Every such
# block is a *subject* and must be gated:
#
#   - inside the block: an invocation of the scanner — a `python3 … gi-secscan.py`
#     command line, or the script's bundled/source path
#     (`references/scripts/gi-secscan.py`, `shared/scripts/gi-secscan.py`) — or a
#     citation of the canonical document `docs/pre-commit-security.md`;
#   - in the 12 lines of prose immediately above the block: an invocation ONLY.
#     A bare doc name does not gate from prose, because every SKILL.source.md
#     ends with an "Additional Resources" navigation index that lists
#     `pre-commit-security.md`. That index sits inside the 12-line window of
#     anything appended near the end of the file, so accepting it would
#     auto-gate an ungated commit block by proximity to a table of contents.
#
# A subject with neither is an ungated commit. Both the scan and the pin below
# are non-vacuity guards: T3 can only report "all gated" over blocks it actually
# looked at, so T3b pins the number of subjects. Without that pin, downgrading
# every ```bash fence to a plain ``` fence scans zero blocks and still passes.
#
# The canonical doc is not in the scan set (SCAN_DIRS is src/ only), so its own
# demonstration snippets never appear here.
#
# Usage: bash tests/test-pre-commit-security.sh
# Returns: exit 0 if all checks pass, exit 1 on failure

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✗ $1"
  FAIL=$((FAIL + 1))
}

echo "◆ Pre-Commit Security Lint (issue #87)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ───────────────────────────────────────────────────────────
# T1: docs/pre-commit-security.md exists
# ───────────────────────────────────────────────────────────
CONV="$REPO_ROOT/docs/pre-commit-security.md"
if [ -f "$CONV" ]; then
  pass "docs/pre-commit-security.md exists (canonical convention)"
else
  fail "docs/pre-commit-security.md missing"
fi

# ───────────────────────────────────────────────────────────
# T2: Canonical doc covers the four required content areas:
#     - real-key vs. placeholder discrimination
#     - rich error format (✗ symbol + 'docs/pre-commit-security.md')
#     - warning non-block contract
#     - skill-side responsibilities section
# ───────────────────────────────────────────────────────────
if [ -f "$CONV" ]; then
  if grep -q -i "placeholder" "$CONV" && grep -q "your-api-key\|your-key\|YOUR_KEY\|placeholder" "$CONV"; then
    pass "canonical doc distinguishes real keys from placeholders"
  else
    fail "canonical doc missing placeholder discrimination"
  fi

  if grep -q "✗" "$CONV" && grep -q "Pre-commit security scan blocked" "$CONV"; then
    pass "canonical doc defines rich-error format (✗ + blocked message)"
  else
    fail "canonical doc missing rich-error format"
  fi

  if grep -q -i "warnings.*log\|warn.*proceed\|log-and-continue\|log and continue" "$CONV"; then
    pass "canonical doc documents warning non-block contract"
  else
    fail "canonical doc missing warning non-block contract"
  fi

  if grep -q -i "Skill-Side Responsibilities" "$CONV"; then
    pass "canonical doc has Skill-Side Responsibilities section"
  else
    fail "canonical doc missing Skill-Side Responsibilities section"
  fi
fi

# ───────────────────────────────────────────────────────────
# T3: Every fenced block containing `git commit` or `git push` in
#     skill sources is gated — by a gi-secscan.py invocation or a
#     docs/pre-commit-security.md citation inside the block, or by a
#     gi-secscan.py invocation in the 12 lines of prose immediately
#     preceding it. See the strategy note in the file header for why
#     prose accepts only the invocation form.
# ───────────────────────────────────────────────────────────

SCAN_DIRS=(
  "$REPO_ROOT/src/skills"
  "$REPO_ROOT/src/internal-skills"
  "$REPO_ROOT/src/shared/agents"
)

scan_out="$(mktemp)"
violations="$(mktemp)"
trap 'rm -f "$scan_out" "$violations"' EXIT

scan_file() {
  local file="$1"
  awk -v file="$file" '
    BEGIN {
      in_block = 0
      is_shell_block = 0
      block_start = 0
      block_has_commit_or_push = 0
      block_has_gate = 0
      # Rolling window of recent prose lines (outside fenced blocks).
      window_size = 12
      for (i = 0; i < window_size; i++) prose[i] = ""
      window_idx = 0
      window_has_inv = 0
      # An *invocation* of the scanner: a `python3 … gi-secscan.py` command
      # line, or the path the skills run it by. This is the only signal the
      # prose window accepts. A sentence that merely names the script does not
      # match, which is the point — "see gi-secscan.py sometime" is not a gate.
      inv_re = "(python3[^\n]*gi-secscan\\.py|(references|shared)/scripts/gi-secscan\\.py)"
      # A citation of the canonical document. Accepted inside a block only:
      # a comment in the block is written for that block. In prose it would be
      # satisfied by any nearby navigation index (see nav_re).
      doc_re = "pre-commit-security\\.md"
      # A skill navigation index ("**Docs** (`docs/`): … pre-commit-security.md
      # …") is a table of contents, not a gate. Every SKILL.source.md ends with
      # one, so it falls inside the prose window of anything appended at the end
      # of the file. Never let one satisfy a gate.
      nav_re = "^\\*\\*(Docs|References|Agents|Scripts)\\*\\*"
    }
    /^```/ {
      if (in_block == 0) {
        in_block = 1
        # Only ```bash and ```sh blocks are executed shell instructions.
        # Plain ``` blocks are display-only (error messages, sample output).
        is_shell_block = ($0 ~ /^```(bash|sh)[[:space:]]*$/) ? 1 : 0
        block_start = NR
        block_has_commit_or_push = 0
        block_has_gate = 0
        # Snapshot whether the prose window invokes the scanner.
        window_has_inv = 0
        for (i = 0; i < window_size; i++) {
          if (prose[i] ~ inv_re) window_has_inv = 1
        }
      } else {
        # Closing fence — evaluate the block.
        if (is_shell_block == 1 && block_has_commit_or_push == 1) {
          # Every subject is recorded, gated or not: T3b pins how many there are
          # so an empty scan cannot report success.
          printf("SUBJECT\t%s:%d\n", file, block_start)
          if (block_has_gate == 0 && window_has_inv == 0) {
            printf("VIOLATION\t%s:%d: shell block with `git commit` or `git push` is gated by neither a gi-secscan.py invocation (in-block or in the 12 lines of prose above) nor an in-block docs/pre-commit-security.md citation\n", file, block_start)
          }
        }
        in_block = 0
        is_shell_block = 0
      }
      next
    }
    {
      if (in_block == 1) {
        # Match `git commit` or `git push` as actual commands, not in comments
        # or inline-code mentions. We look for either at start of line (after
        # optional whitespace) or after a shell separator.
        if ($0 ~ /(^|[[:space:]&|;]|^[[:space:]]*)git[[:space:]]+commit([[:space:]]|$)/) {
          block_has_commit_or_push = 1
        }
        if ($0 ~ /(^|[[:space:]&|;]|^[[:space:]]*)git[[:space:]]+push([[:space:]]|$)/) {
          block_has_commit_or_push = 1
        }
        if ($0 ~ inv_re || ($0 ~ doc_re && $0 !~ nav_re)) {
          block_has_gate = 1
        }
      } else {
        # Update prose window (ring buffer of last N lines).
        prose[window_idx] = $0
        window_idx = (window_idx + 1) % window_size
      }
    }
  ' "$file"
}

for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    continue
  fi
  while IFS= read -r -d '' file; do
    scan_file "$file" >> "$scan_out"
  done < <(find "$dir" -type f -name "*.md" -print0)
done

grep '^VIOLATION' "$scan_out" > "$violations" || true
SCANNED="$(grep -c '^SUBJECT' "$scan_out" || true)"

if [ -s "$violations" ]; then
  fail "Ungated \`git commit\` or \`git push\` found in fenced code blocks:"
  while IFS= read -r line; do
    echo "      ${line#VIOLATION	}"
  done < "$violations"
else
  pass "All $SCANNED fenced \`git commit\` / \`git push\` block(s) are gated"
fi

# ───────────────────────────────────────────────────────────
# T3b: T3 is non-vacuous — it looked at the blocks we know exist.
#     "All blocks are gated" is also true of zero blocks, so the number of
#     subjects is pinned. A fence written as ``` instead of ```bash, a renamed
#     scan directory, or a find/awk regression all empty the scan while T3
#     keeps printing PASS; this is the assertion that catches them.
#
#     Today's subjects (both gated, verified by T3):
#       src/skills/issue-resolver/SKILL.source.md          (Step 5 — push + PR)
#       src/skills/issue-pr-review/references/
#         prepass-tests-ci-mechanics.md                    (Step 3 — auto-fixes)
#
#     When a skill legitimately gains or loses a `git commit`/`git push` block,
#     update this number in the same commit — deliberately, not by deleting the
#     check.
# ───────────────────────────────────────────────────────────
EXPECTED_SUBJECTS=2

if [ "$SCANNED" -eq "$EXPECTED_SUBJECTS" ]; then
  pass "T3 scanned $SCANNED \`git commit\`/\`git push\` block(s), as expected"
else
  fail "T3 scanned $SCANNED \`git commit\`/\`git push\` block(s), expected $EXPECTED_SUBJECTS"
  echo "      A scan that saw no blocks reports PASS without checking anything."
  echo "      If a skill gained or lost such a block, update EXPECTED_SUBJECTS."
  echo "      Subjects found:"
  if grep -q '^SUBJECT' "$scan_out"; then
    while IFS= read -r line; do
      echo "        ${line#SUBJECT	}"
    done < <(grep '^SUBJECT' "$scan_out")
  else
    echo "        (none)"
  fi
fi

# ───────────────────────────────────────────────────────────
# T4: All four touchpoints identified during research reference
#     pre-commit-security.md somewhere in the file.
# ───────────────────────────────────────────────────────────

NAMED_FILES=(
  "src/shared/agents/implementer.md"
  "src/skills/issue-pr-review/SKILL.source.md"
  "src/skills/issue-resolver/SKILL.source.md"
)

for rel in "${NAMED_FILES[@]}"; do
  abs="$REPO_ROOT/$rel"
  if [ ! -f "$abs" ]; then
    fail "$rel missing"
    continue
  fi
  if grep -q "pre-commit-security.md" "$abs"; then
    pass "$rel references pre-commit-security.md"
  else
    fail "$rel does not reference pre-commit-security.md"
  fi
done

# ───────────────────────────────────────────────────────────
# Summary
# ───────────────────────────────────────────────────────────
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Results: $PASS passed, $FAIL failed"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Pre-commit security lint failed"
  exit 1
fi

echo "  ✓ All pre-commit security checks passed"
exit 0
