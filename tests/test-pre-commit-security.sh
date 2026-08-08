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
# Strategy: walk every fenced shell code block in src/skills/**/*.md,
# src/internal-skills/**/*.md, and src/shared/agents/*.md, looking for
# `git commit` or `git push`. Every such block is a *subject* and must be gated:
#
#   - inside the block: an *invocation* of the scanner — a `python3 …
#     gi-secscan.py` command line — or a citation of the canonical document
#     `docs/pre-commit-security.md`;
#   - within 12 lines above the block: an invocation ONLY. It may sit in prose
#     or in a preceding *shell* fenced block, because "scan in one block, push
#     in the next" is the pattern authors reach for. A display-only fence
#     (```text, ```json, ```markdown, bare ```) does not gate from above: those
#     carry transcripts and templates, and a transcript of the scan is not the
#     scan. A bare doc name does not gate from above, because every SKILL.source.md
#     ends with an "Additional Resources" navigation index that lists
#     `pre-commit-security.md`. That index sits inside the 12-line window of
#     anything appended near the end of the file, so accepting it would
#     auto-gate an ungated commit block by proximity to a table of contents.
#
# Four properties the gate recogniser must hold, each learned from a defeat:
#
#   1. An invocation must be a *command*, not a mention. The bare path
#      `references/scripts/gi-secscan.py` is this repo's documented citation
#      token for a shared script (CLAUDE.md, "Scripts placement rule") and
#      already appears in ordinary prose that gates nothing. Requiring the
#      `python3 …` command form is what separates "the skill runs the scan"
#      from "the skill mentions the scan".
#   2. A commented-out invocation is not an invocation. A line whose first
#      non-blank character is `#` cannot supply the invocation gate — otherwise
#      `# DISABLED for debugging: python3 … gi-secscan.py` gates. (The in-block
#      *document* citation is exempt: that form is deliberately written as a
#      shell comment beside the block it gates.)
#   3. Every fence form must be seen. The parser handles indented fences,
#      backtick and tilde fences of any length ≥ 3, and info strings
#      (```bash title="x"). src/ contains dozens of indented fences; a parser
#      blind to them never toggles `in_block`, so their bodies leak into the
#      prose window and can act as a false gate for a later, ungated block.
#      A fence left *open* at EOF is a valid CommonMark block that renders
#      normally, so the END clause must evaluate it; otherwise a `git push` in
#      the last fence of a file is never looked at.
#   4. In a session-transcript fence (```console, ```shell-session), a leading
#      `#` is the root prompt, not a comment — property 2's `comment_re` would
#      throw away a real command. Such a line gates only when the interpreter
#      comes first after the prompt, which keeps property 2 intact inside those
#      fences: `# DISABLED: python3 … gi-secscan.py` still gates nothing.
#
# A subject with neither gate is an ungated commit. Both the scan and the pin
# below are non-vacuity guards: T3 can only report "all gated" over blocks it
# actually looked at, so T3b pins the exact *set* of subject files. Without that
# pin, downgrading every ```bash fence to a plain ``` fence scans zero blocks
# and still passes; and a count alone is satisfied by any two subjects, so a
# refactor that drops a real subject and introduces an unrelated one keeps the
# arithmetic while losing the gate.
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
# T3: Every fenced shell block containing `git commit` or `git push` in
#     skill sources is gated — by a `python3 … gi-secscan.py` invocation or a
#     docs/pre-commit-security.md citation inside the block, or by such an
#     invocation in the 12 lines immediately preceding it. See the strategy
#     note in the file header for why prose accepts only the invocation form.
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
    # Parse a fence line into (fence_ch, fence_len, fence_info). Returns 1 if
    # the line is fence-shaped, 0 otherwise. CommonMark: a fence is a run of
    # three or more backticks or tildes, indented by any amount; the info
    # string of a backtick fence may not itself contain a backtick.
    function parse_fence(line,   t, c, k) {
      fence_ch = ""; fence_len = 0; fence_info = ""
      t = line
      sub(/^[[:space:]]+/, "", t)
      c = substr(t, 1, 1)
      if (c != "`" && c != "~") return 0
      k = 0
      while (substr(t, k + 1, 1) == c) k++
      if (k < 3) return 0
      fence_ch = c
      fence_len = k
      fence_info = substr(t, k + 1)
      sub(/^[[:space:]]+/, "", fence_info)
      sub(/[[:space:]]+$/, "", fence_info)
      if (c == "`" && index(fence_info, "`") > 0) return 0
      return 1
    }
    # Evaluate the block that just ended (or that EOF ended). Kept as a function
    # so the closing-fence path and the END path cannot drift apart.
    function evaluate_block() {
      if (is_shell_block == 1 && block_has_commit_or_push == 1) {
        # Every subject is recorded, gated or not: T3b pins which files they
        # live in, so an empty scan cannot report success.
        printf("SUBJECT\t%s:%d\n", file, block_start)
        if (block_has_gate == 0 && window_has_inv == 0) {
          printf("VIOLATION\t%s:%d: shell block with `git commit` or `git push` is gated by neither a `python3 … gi-secscan.py` invocation (in-block or in the 12 lines above) nor an in-block docs/pre-commit-security.md citation\n", file, block_start)
        }
      }
      in_block = 0
      is_shell_block = 0
      is_session_block = 0
    }
    # Is this line a live invocation of the scanner?
    function is_invocation(line) {
      if (line ~ inv_re && line !~ comment_re) return 1
      # In a session-transcript fence (```console, ```shell-session) a leading
      # `#` is the *root prompt*, not a comment — comment_re would disqualify a
      # real command. Accept it only when the text after the prompt *begins*
      # with the interpreter, which is what separates a transcribed command from
      # a commented-out one: `# DISABLED for debugging: python3 … gi-secscan.py`
      # still does not gate (header note 2 holds inside these fences too).
      if (is_session_block == 1 && line ~ prompt_inv_re) return 1
      return 0
    }
    BEGIN {
      in_block = 0
      is_shell_block = 0
      is_session_block = 0
      block_start = 0
      block_has_commit_or_push = 0
      block_has_gate = 0
      # How far above a block an invocation may sit and still gate it. Measured
      # in *physical* lines, not prose lines: an invocation separated from the
      # block by a long unrelated code block is not adjacent to it, and must
      # not gate it.
      window_size = 12
      last_inv_line = 0
      window_has_inv = 0
      # An *invocation* of the scanner: a `python3 … gi-secscan.py` command
      # line. A bare path is deliberately NOT accepted: the token
      # `references/scripts/gi-secscan.py` is the documented way this repo
      # *cites* a shared script, and appears in prose that runs nothing
      # (see header note 1).
      inv_re = "python3[[:space:]][^\n]*gi-secscan\\.py"
      # The same command behind a session prompt (`# ` or `$ `). The interpreter
      # must come first — see is_invocation().
      prompt_inv_re = "^[[:space:]]*[#$][[:space:]]+python3[[:space:]][^\n]*gi-secscan\\.py"
      # A commented-out command is not a command (header note 2). Applies to
      # inv_re only; the in-block doc citation is written as a comment on
      # purpose.
      comment_re = "^[[:space:]]*#"
      # A citation of the canonical document. Accepted inside a block only:
      # a comment in the block is written for that block. In prose it would be
      # satisfied by any nearby navigation index (see nav_re).
      doc_re = "pre-commit-security\\.md"
      # A skill navigation index ("**Docs** (`docs/`): … pre-commit-security.md
      # …") is a table of contents, not a gate. Every SKILL.source.md ends with
      # one, so it falls inside the window of anything appended at the end of
      # the file. Never let one satisfy a gate.
      nav_re = "^\\*\\*(Docs|References|Agents|Scripts)\\*\\*"
      # Fence info strings whose first word marks executable shell. Anything
      # else (```json, ```text, or a bare ```) is display-only: error messages,
      # sample output, templates.
      shell_lang_re = "^(bash|sh|shell|zsh|ksh|console|shell-session|bash-session)$"
      # The subset of those whose lines are a transcript: a leading `#` is the
      # root prompt rather than a comment.
      session_lang_re = "^(console|shell-session|bash-session)$"
      # A *subject*: a `git commit` or `git push` command. `git` takes global
      # options before the subcommand, so the subject is not always the two
      # words verbatim — /issue-resolver works from a worktree and reaches it
      # as `git -C <dir> push`. Accept a run of `-opt` words between `git` and
      # the subcommand, each optionally followed by its value (the `-C` in
      # `git -C /path push` takes one; the `--no-pager` in
      # `git --no-pager -C /path commit` does not).
      git_opt_re = "([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*"
      commit_re = "(^|[[:space:]&|;])git" git_opt_re "[[:space:]]+commit([[:space:]]|$)"
      push_re = "(^|[[:space:]&|;])git" git_opt_re "[[:space:]]+push([[:space:]]|$)"
    }
    {
      if (parse_fence($0)) {
        if (in_block == 0) {
          in_block = 1
          open_ch = fence_ch
          open_len = fence_len
          lang = fence_info
          sub(/[[:space:]].*$/, "", lang)   # first word of the info string
          is_shell_block = (tolower(lang) ~ shell_lang_re) ? 1 : 0
          is_session_block = (tolower(lang) ~ session_lang_re) ? 1 : 0
          block_start = NR
          block_has_commit_or_push = 0
          block_has_gate = 0
          # Snapshot whether an invocation sits within window_size lines above.
          window_has_inv = (last_inv_line > 0 && NR - last_inv_line <= window_size) ? 1 : 0
          next
        }
        if (fence_ch == open_ch && fence_len >= open_len && fence_info == "") {
          # Closing fence — evaluate the block.
          evaluate_block()
          next
        }
        # A shorter or differently-charactered fence inside an open block is
        # block content (a ```bash sample nested in a ````markdown wrapper).
        # Fall through.
      }
      # Remember where the most recent live invocation was. Two places count:
      # prose, and a *shell* fence. Counting shell fences is deliberate — the
      # most natural authoring pattern is a ```bash block that runs the scan
      # immediately followed by a ```bash block that pushes, and that gates.
      #
      # A non-shell fence does not count. The same info-string test that makes a
      # ```text/```json/```markdown/bare fence inert as a *subject*
      # (shell_lang_re, see its comment) makes it inert as a *gate*: those
      # fences carry sample transcripts, error messages and templates, and a
      # transcript of the scan running is not the scan running. Counting them
      # let a ```text transcript of a blocked scan gate an ungated ```bash push
      # block below it.
      #
      # Only the *document citation* is restricted further, to in-block use, and
      # for a reason that does not apply here: the "Additional Resources"
      # navigation index would otherwise gate by proximity (see nav_re). The
      # 12-line physical window still bounds adjacency, so an invocation in an
      # unrelated listing further up does not reach.
      #
      # Not closed, for two different reasons:
      #
      #   - A ```bash fence that is a negative example ("do NOT do this") is
      #     *indistinguishable* from a legitimate scan-then-push pair at this
      #     level: strip the prose marker and the two inputs are byte-identical
      #     below it. Only prose keywords could tell them apart, and "Never push
      #     without running this first" carries the same keywords as "do NOT do
      #     this" with the opposite intent — so that discriminator would break
      #     real gates. Authoring rule instead, documented in the doc.
      #   - A heredoc that only *writes* the command into a file IS separable
      #     (a heredoc-terminator tracker is ~10 lines). It is left open because
      #     the same tracker also flags a heredoc installing the scan as a
      #     .git/hooks/pre-commit hook, which is a strictly *stronger* gate than
      #     an inline call. The discriminator points the wrong way, so closing
      #     this trades a benign false negative for a false positive against the
      #     best available pattern.
      if ((in_block == 0 || is_shell_block == 1) && is_invocation($0)) last_inv_line = NR
      if (in_block == 1) {
        # Match `git commit` or `git push` as actual commands, not in comments
        # or inline-code mentions: at start of line or after a shell separator,
        # with any global options in between (see commit_re / push_re).
        if ($0 ~ commit_re || $0 ~ push_re) {
          block_has_commit_or_push = 1
        }
        if (is_invocation($0) || ($0 ~ doc_re && $0 !~ nav_re)) {
          block_has_gate = 1
        }
      }
    }
    END {
      # A fence left open at EOF is a *valid* CommonMark code block — it renders
      # exactly like a closed one, so nothing looks wrong to the author — and
      # without this clause it was never evaluated at all. A `git push` in the
      # last, unclosed fence of a file escaped the gate silently.
      if (in_block == 1) evaluate_block()
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
#     "All blocks are gated" is also true of zero blocks, so the subjects are
#     pinned. A fence written as ``` instead of ```bash, a renamed scan
#     directory, or a find/awk regression all empty the scan while T3 keeps
#     printing PASS; this is the assertion that catches them.
#
#     The pin is the *list of files* the subjects live in, one entry per
#     subject, sorted — not a bare count. A count is satisfied by any two
#     blocks, so a refactor that deletes the resolver push gate and grows an
#     unrelated commit block elsewhere keeps the arithmetic and loses the gate.
#     Line numbers are deliberately not pinned: they churn on every edit above
#     the block and would make the check noise rather than signal.
#
#     Today's subjects (both gated, verified by T3):
#       src/skills/issue-resolver/SKILL.source.md          (Step 5 — push + PR)
#       src/skills/issue-pr-review/references/
#         prepass-tests-ci-mechanics.md                    (Step 3 — auto-fixes)
#
#     When a skill legitimately gains or loses a `git commit`/`git push` block,
#     update this list in the same commit — deliberately, not by deleting the
#     check.
# ───────────────────────────────────────────────────────────
EXPECTED_SUBJECT_FILES=(
  "src/skills/issue-pr-review/references/prepass-tests-ci-mechanics.md"
  "src/skills/issue-resolver/SKILL.source.md"
)

# One repo-relative path per subject, sorted — absolute paths would make the
# expected list unwritable and the failure output machine-specific.
actual_subjects="$(
  grep '^SUBJECT' "$scan_out" 2>/dev/null \
    | sed -e 's/^SUBJECT	//' -e 's/:[0-9]*$//' -e "s#^$REPO_ROOT/##" \
    | LC_ALL=C sort || true
)"
expected_subjects="$(printf '%s\n' "${EXPECTED_SUBJECT_FILES[@]}" | LC_ALL=C sort)"

if [ "$actual_subjects" = "$expected_subjects" ]; then
  pass "T3 scanned $SCANNED \`git commit\`/\`git push\` block(s), in exactly the expected files"
else
  fail "T3 scanned a different set of \`git commit\`/\`git push\` block(s) than expected"
  echo "      A scan that saw no blocks reports PASS without checking anything,"
  echo "      and a scan that saw the wrong blocks reports PASS for the wrong gate."
  echo "      If a skill gained or lost such a block, update EXPECTED_SUBJECT_FILES"
  echo "      in tests/test-pre-commit-security.sh."
  echo "      Expected ${#EXPECTED_SUBJECT_FILES[@]} subject(s):"
  printf '        %s\n' "${EXPECTED_SUBJECT_FILES[@]}"
  echo "      Found $SCANNED subject(s):"
  if [ -n "$actual_subjects" ]; then
    printf '%s\n' "$actual_subjects" | sed 's/^/        /'
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
