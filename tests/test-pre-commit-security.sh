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
#   3. Every fence form must be seen — and nothing else may be mistaken for one.
#      (a) CommonMark bounds a fence's indentation at three spaces — but three
#          past its *container*, not past column zero. This parser tracks no
#          containers, so it applies the bound only where the container column is
#          knowable, and the two cases come out differently:
#
#            · An *opening* fence is accepted at any indent. A `10. ` list item
#              puts its content at column 4, so a fence nested in one sits at
#              column 4 while being indented 0 relative to its own container —
#              perfectly ordinary markup. An absolute 3-column limit makes every
#              list-nested fence invisible, which fails in both directions at
#              once: an ungated `git push` in a list-nested ```bash block is
#              neither subject nor violation, and an invocation inside a
#              list-nested display-only ```text fence is no longer *in* a block,
#              so it leaks into the 12-line prose window and falsely gates a
#              later ungated block. Fixtures C and D pin the two.
#            · A *closing* fence is accepted only 0–3 columns past its
#              container content column, independently of the opener indent.
#              CommonMark applies that relative limit to both fences. Using
#              `open_indent + 3` accepts an illegal six-space run after a
#              top-level three-space opener; using an absolute three-column cap
#              rejects a legal five-space closer in a list whose content starts
#              at column 2. The scanner tracks active list content columns so
#              both cases parse correctly. Fixtures A, J, and K pin the limits.
#
#          Accepting any opener indent has a cost of its own — a top-level
#          *indented code block* (four spaces, no fence) containing a ``` line
#          opens a block that was never there. Without container tracking that
#          shape is byte-identical to a list-nested fence, so it cannot be told
#          apart here. Note 3(d) recovers from it on either arm: when the run it
#          opens is display-only, and — since issue #280 — when that run carries
#          a shell info string (```bash), which is the case that used to have no
#          guard at either end. Note 3(e) looks at the same shape from the
#          other direction, independently of what 3(d) makes of it — but only
#          its EOF half is a deduction there. Its parity half counts an
#          indented-code-block ``` run like any other run, so a file carrying
#          one is reported UNBALANCED even when the parse is right. Fixture E
#          is such a file. See 3(e).
#
#          src/ carries fences at 0, 2 and 3 columns only, so neither rule moves
#          a real subject today; T3c is what keeps them from drifting.
#      (b) Backtick and tilde fences of any length ≥ 3 count, as do info strings
#          (```bash title="x").
#      (c) A fence left *open* at EOF is a valid CommonMark block that renders
#          normally, so the END clause must evaluate it; otherwise a `git push`
#          in the last fence of a file is never looked at.
#      (d) A *phantom* open block should be recoverable. The recurring defeat
#          here is one shape — a block the parser believes is open swallowing a
#          real ```bash block whole — reached several ways: a false close (a run
#          indented past its opener, note 3a), a false open (a top-level
#          indented code block containing a ``` run), and a fence the author
#          never closed. Only the first is blocked at the entrance, by note
#          3(a)'s closing bound; blocking them one at a time is what let the
#          third survive two rounds of fixing the first two, so there is also a
#          guard at the exit — and for entrances 2 and 3 that guard is the only
#          cover there is.
#
#          The recovery: a same-character run of length ≥ open_len carrying a
#          non-empty info string is taken to mean the open block was a phantom.
#          Evaluate it and open the real block from this fence. It fires on two
#          arms, and the second was added by issue #280:
#            · the open block is *display-only* — a wrong guess there is loud;
#            · or the *incoming* run names a shell language (```bash, ```console
#              …). Inside an open shell block that shape is the signature of a
#              swallowed real block: an author writes ```bash to open a command
#              block, never as the content of one. The heredoc content that the
#              `is_shell_block == 0` arm exists to protect writes ```text, not
#              ```bash — fixtures H and I are both `text`, and both still hold.
#
#          This is a heuristic and it is worth being exact about why, because an
#          earlier version of this note claimed otherwise and the false claim
#          cost a live gate. CommonMark does *not* forbid that shape inside an
#          open fence: every line inside a fenced block is literal content, info
#          string or not, and only an empty-info run can close. So the shape
#          proves nothing on its own. What bounds acting on it is the
#          restriction to a non-shell open block — but "bounds", not "makes
#          free", and the difference is worth stating exactly. The recovery does
#          not merely abandon the open block: it calls open_block() on that
#          fence. So a genuine three-backtick ```text wrapper quoting a nested
#          ```bash sample has the sample *promoted* to a real shell block, and a
#          `git push` inside the sample is reported as a violation — a false
#          positive. (The ````markdown-wraps-```bash idiom escapes that for a
#          second reason: there open_len (4) > fence_len (3), so the branch
#          never fires. A three-backtick display wrapper has no such exemption.)
#          What justifies the restriction is the asymmetry of the two misfires.
#          On a display-only block the misfire is a false positive: loud, and
#          the author can rewrite the wrapper. Applied to a genuinely open
#          ```bash block the same guess is silent: a heredoc writing a fenced
#          snippet ends the block before its `git push` is reached, and the push
#          becomes neither subject nor violation. Fixtures H and I pin that.
#          Measured against the whole of src/: the branch fires zero times on
#          either arm, so zero blocks change hands today. The shell arm's own
#          exposure was measured the same way — across the scanned tree there
#          are zero fence runs of *any* info string inside an open shell block,
#          shell-named or not — so the widening costs nothing that is written
#          here now. Its known false positive is a heredoc that writes a
#          ```bash fence; there are none.
#
#          Order matters — the recovery is tested *before* the note 3(a) indent
#          bound, because that bound reasons "a run this deep is content of the
#          enclosing block", which is void when the enclosing block is a
#          phantom. Behind the bound, a phantom opened at column 0 still eats a
#          list-nested ```bash block. Fixtures E, F and G pin the three.
#
#          Residues — the three the recovery could not reach on its own, and
#          what closes each now. The recovery keys on `fence_ch == open_ch &&
#          fence_len >= open_len`, so it still does not fire when the phantom is
#          a `~~~text` fence or a 4-backtick ````text fence; and before #280 its
#          `is_shell_block == 0` restriction meant it did not fire when the
#          phantom was one this parser reads as a *shell* block either — an
#          unclosed ```bash or ```console fence, or an indented code block
#          carrying a ```bash run (note 3a).
#
#          The third was the live one: the scanned tree carries 122 shell-class
#          fence openers against zero tilde runs and zero 4-backtick runs
#          (issue #280 measured 96 openers in August 2026; the tree has grown,
#          the ratio has not), so one missing closer reached it, and it was the
#          worst of the three because the merged block is
#          itself a shell block — a swallowed `git push` is recorded as a
#          subject at the *phantom's* line, in the phantom's file, so T3b's file
#          pin does not move, and the merged block carries one block_has_gate
#          flag, so an invocation anywhere in the merged span reads as gating
#          the swallowed push.
#
#          It is closed by the shell arm above: the swallowed ```bash block is
#          re-opened as its own block and its push is evaluated on its own gate.
#          Fixture N pins it.
#
#          The other two are closed from the other end, by note 3(e) rather than
#          by the recovery. A `~~~text` or ````text phantom cannot be closed by
#          any ``` run, so it leaves the file both unbalanced and open at EOF,
#          and 3(e) reports it, on both halves. That is a weaker verdict than
#          the shell arm's — "this file is malformed" rather than "this push is
#          ungated" — but it is loud, and here the sound half carries it: a
#          block still open at EOF is proof the parser never saw a terminator,
#          whatever the parity count says (3(e) is exact about which half
#          deduces and which half only measures). A *closed*
#          ````markdown wrapper quoting a ```bash sample stays balanced and is
#          not reported, which is the behaviour that idiom needs.
#
#          What is left. Widening the character/length match is still declined:
#          that is where the ````markdown wrapper idiom lives, so it would trade
#          a real false positive against two shapes nothing here writes. If a
#          tilde or 4-backtick fence ever appears in src/, revisit this rather
#          than assuming the guard covers it.
#      (e) A file's fences should *account* for each other, and two independent
#          checks say so. Both were added by issue #280, and they are not the
#          same kind of statement — an earlier version of this note called both
#          of them deductions, which was false of one of them:
#
#            · **Fence-run parity — an empirical guard, not a deduction.** The
#              scanner counts every fence-shaped run in the file and reports an
#              odd total. The reasoning behind it is that a fenced block
#              contributes two runs, one opener and one closer, so a dropped
#              closer leaves a run without a partner. That is what catches a
#              phantom whose damage is repaired before EOF: the next unrelated
#              bare ``` closes the merged block, parity re-syncs on the pair
#              after it, and the file ends clean while every line between the
#              two has been swallowed into a block carrying a single gate flag.
#              That is the exact reproduction issue #280 opens with, and fixture
#              O pins it.
#
#              What the count does *not* do is prove the file malformed, because
#              a run is counted whether or not the parser acts on it. Three
#              shapes make a correctly-parsed file odd:
#                — a fence-shaped line that is block *content* (an over-indented
#                  ``` run inside an open block, note 3a; a heredoc that writes
#                  a fence line; a nested sample inside a wrapper of a different
#                  character or length);
#                — a top-level *indented code block* containing a ``` run, which
#                  this parser has to read as an opener (note 3a) and which the
#                  count therefore charges to the file;
#                — a fence closed by the end of its list container rather than
#                  by an explicit closer.
#              Ten of T3c's own sixteen fixtures are reported UNBALANCED, and
#              six of those (A, E, H, I, J, M) have a *correct* parse — they are
#              odd for exactly the three reasons above. Only the other four (F,
#              G, N, O) are files a maintainer would call broken. Counting only
#              the runs the parser acts on would
#              make the check sound and useless in the same move: it would then
#              be even by construction everywhere the EOF half is silent, and
#              fixture O — where the extra run is *content* — would stop firing.
#              So the check is kept as measured, not as proved.
#
#              What makes it worth keeping is the measurement, not the
#              argument: over the whole scanned tree the count is 1,314 runs
#              across 67 files with zero odd, so it reports nothing today and
#              any report is a change. It fires the moment one of the three
#              shapes above is written into src/. When that happens, pair the
#              fence, or add an exemption for that file here — do not delete the
#              check, because a false positive is loud and everything it exists
#              to catch is silent.
#            · **A block still open at EOF — a deduction.** This one is sound:
#              the parser reached EOF with a fence it never saw terminated, so
#              the file is malformed however the rest of it is read. Parity does
#              not subsume it: a run *inside* an open block is counted but
#              toggles nothing, so a file can end with a block open and an even
#              run count. Fixture P pins it, and note 3(c) still evaluates that
#              block rather than discarding it. Measured over the scanned tree:
#              zero files end with a block open.
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
    # Return the indentation in columns (tabs advance to a 4-column stop).
    function line_indent(line,   i, col, ch) {
      col = 0
      for (i = 1; i <= length(line); i++) {
        ch = substr(line, i, 1)
        if (ch == " ") col += 1
        else if (ch == "\t") col += 4 - (col % 4)
        else break
      }
      return col
    }
    # Return a list marker content column, or -1 when the line is not a marker.
    # CommonMark gives an empty marker (for example `-` followed by EOL) an
    # implicit one-column padding even though there is no whitespace to count.
    function marker_content_column(line,   i, col, ch, next_ch, t, j, marker_end, saw_digit, empty_marker) {
      col = line_indent(line)
      i = 1
      while (i <= length(line) && (substr(line, i, 1) == " " || substr(line, i, 1) == "\t")) i++
      t = substr(line, i)
      marker_end = 0
      empty_marker = 0
      ch = substr(t, 1, 1)
      next_ch = substr(t, 2, 1)
      if ((ch == "-" || ch == "+" || ch == "*") && (next_ch == "" || next_ch == " " || next_ch == "\t")) {
        marker_end = 1
        if (next_ch == "") empty_marker = 1
      } else {
        j = 1
        saw_digit = 0
        while (j <= 10 && index("0123456789", substr(t, j, 1)) > 0) { saw_digit = 1; j++ }
        ch = substr(t, j, 1)
        next_ch = substr(t, j + 1, 1)
        if (saw_digit && (ch == "." || ch == ")") && (next_ch == "" || next_ch == " " || next_ch == "\t")) {
          marker_end = j
          if (next_ch == "") empty_marker = 1
        }
      }
      if (marker_end == 0) return -1
      col += marker_end
      if (empty_marker) return col + 1
      i += marker_end
      while (i <= length(line)) {
        ch = substr(line, i, 1)
        if (ch == " ") col += 1
        else if (ch == "\t") col += 4 - (col % 4)
        else break
        i++
      }
      return col
    }
    # Maintain the active Markdown list container stack while outside fences.
    # A fence uses the deepest content column not beyond its own indentation.
    function update_list_containers(line,   indent, marker_col) {
      indent = line_indent(line)
      marker_col = marker_content_column(line)
      if (marker_col >= 0) {
        while (list_depth > 0 && indent < list_content[list_depth]) list_depth--
        list_content[++list_depth] = marker_col
        return
      }
      if (line ~ /^[[:space:]]*$/) return
      while (list_depth > 0 && indent < list_content[list_depth]) list_depth--
    }
    # Parse a fence line into (fence_ch, fence_len, fence_info, fence_indent).
    # Returns 1 if the line is fence-shaped, 0 otherwise. CommonMark: a fence is
    # a run of three or more backticks or tildes; the info string of a backtick
    # fence may not itself contain a backtick.
    #
    # The indentation *bound* is deliberately not applied here. CommonMark
    # measures it relative to the enclosing container, and only the caller knows
    # what that is (header note 3a) — this function just measures the indent and
    # reports it in fence_indent.
    function parse_fence(line,   t, c, k, i, ch) {
      fence_ch = ""; fence_len = 0; fence_info = ""; fence_indent = 0
      t = line
      # Indentation in *columns*, not characters: a tab advances to the next
      # 4-column tab stop, which is how CommonMark measures it.
      i = 1
      while (i <= length(t)) {
        ch = substr(t, i, 1)
        if (ch == " ") fence_indent += 1
        else if (ch == "\t") fence_indent += 4 - (fence_indent % 4)
        else break
        i += 1
      }
      t = substr(t, i)
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
    # First word of the info string parse_fence() just read, lowercased — the
    # language token. Shared by open_block() and the note 3(d) recovery so the
    # two cannot disagree about what counts as a shell fence.
    function fence_lang(   l) {
      l = fence_info
      sub(/[[:space:]].*$/, "", l)
      return tolower(l)
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
    # Open a block from the fence parse_fence() just performed. A function for
    # the same reason as evaluate_block(): two paths reach it — a fence found in
    # prose, and the spurious-open recovery below — and a second, copy-pasted
    # body is exactly the thing that drifts.
    function open_block(   lang) {
      in_block = 1
      open_ch = fence_ch
      open_len = fence_len
      open_indent = fence_indent
      open_container_indent = (list_depth > 0 && list_content[list_depth] <= fence_indent) ? list_content[list_depth] : 0
      open_indent_is_valid = (fence_indent - open_container_indent >= 0 && fence_indent - open_container_indent <= 3)
      lang = fence_lang()
      is_shell_block = (lang ~ shell_lang_re) ? 1 : 0
      is_session_block = (lang ~ session_lang_re) ? 1 : 0
      block_start = NR
      block_has_commit_or_push = 0
      block_has_gate = 0
      # Snapshot whether an invocation sits within window_size lines above.
      window_has_inv = (last_inv_line > 0 && NR - last_inv_line <= window_size) ? 1 : 0
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
      fence_runs = 0
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
      # An outdented non-blank line ends the list container that owns an open
      # fence, and therefore ends the fence even without an explicit closer.
      # Evaluate that block first, then let the same physical line continue
      # through normal outside-block parsing; it may itself start a new fence.
      if (in_block == 1 && open_container_indent > 0 &&
          $0 !~ /^[[:space:]]*$/ && line_indent($0) < open_container_indent) {
        evaluate_block()
      }
      if (in_block == 0) update_list_containers($0)
      if (parse_fence($0)) {
        # Every fence-shaped run in the file, counted before any decision about
        # what it means. The END parity check reads this; see note 3(e).
        fence_runs += 1
        # Phantom-block recovery — a heuristic, not a deduction (note 3d).
        # CommonMark makes *every* line inside an open fence literal content,
        # info string or not, so a same-character run carrying one is not proof
        # of anything. Two clauses bound the guess, and the condition below
        # fires on either:
        #
        #   - `is_shell_block == 0` — the open block is *display-only*, where a
        #     wrong guess is loud rather than silent. Not free even there:
        #     open_block() below promotes the run to a real block, so a ```text
        #     wrapper quoting a ```bash sample gets the sample scanned as shell
        #     (a false positive; header note 3d).
        #   - `fence_lang() ~ shell_lang_re` — the *incoming* run names a shell
        #     language. Added by issue #280. Inside an open shell block that
        #     shape is the signature of a swallowed real block: an author writes
        #     ```bash to open a command block, never as the content of one.
        #     Measured over the scanned tree there are zero fence runs of any
        #     info string inside an open shell block, so this arm costs nothing
        #     written here today; its known false positive is a heredoc that
        #     writes a ```bash fence, and there are none.
        #
        # What neither clause may do is act on a *non-shell* run inside a
        # genuinely open ```bash block — there the shape is ordinary content, a
        # heredoc writing a fenced snippet, and ending the block would drop its
        # `git push` before it is seen, losing the subject entirely. That is the
        # one thing this gate must never do; fixtures H and I are both `text`
        # and pin it.
        #
        # Checked before the indentation bound, because that bound argues "a run
        # this deep is *content* of the enclosing block" — reasoning that is void
        # when the enclosing block does not exist.
        if (in_block == 1 && fence_ch == open_ch && fence_len >= open_len && fence_info != "" &&
            (is_shell_block == 0 || fence_lang() ~ shell_lang_re)) {
          evaluate_block()
          open_block()
          next
        }
        # A valid closer is indented 0–3 columns past the same container content
        # column as its opener (note 3a). For an intentionally over-indented
        # phantom opener, retain the relative approximation used by recovery.
        valid_fence_indent = (in_block == 0 ||
          (open_indent_is_valid && fence_indent >= open_container_indent && fence_indent <= open_container_indent + 3) ||
          (!open_indent_is_valid && fence_indent <= open_indent + 3))
        if (valid_fence_indent) {
          if (in_block == 0) {
            open_block()
            next
          }
          if (fence_ch == open_ch && fence_len >= open_len && fence_info == "") {
            # Closing fence — evaluate the block.
            evaluate_block()
            next
          }
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
      #
      # Evaluating it is necessary but not sufficient. The block that reaches
      # EOF open may be a *phantom* that swallowed real blocks on the way, and
      # the merged block carries one block_has_gate flag, so a gate anywhere in
      # the swallowed span reads as gating every push in it — the block is
      # evaluated, and evaluated wrong. So report the unbalanced fence itself.
      # Unlike the note 3(d) recovery this is a deduction rather than a
      # heuristic: a well-formed file closes the fences it opens, so a block
      # still open at EOF is proof the file is malformed, whatever the parser
      # then makes of its contents. Measured over the scanned tree: zero files
      # reach EOF with a block open, so this reports nothing today.
      if (in_block == 1) {
        printf("UNCLOSED\t%s:%d\n", file, block_start)
        evaluate_block()
      }
      # Note 3(e). Fence parity is the check that survives a phantom whose
      # damage is repaired before EOF. A missing closer does not always leave a
      # block open: the next unrelated bare ``` closes the merged block, parity
      # re-syncs on the pair after it, and the file ends balanced — while every
      # line between the two has been swallowed into a block that carries one
      # gate flag. Counting runs catches it where the EOF state cannot.
      #
      # Unlike the UNCLOSED report above, this is an *empirical* guard, not a
      # deduction: a run is counted whether or not the parser acts on it, so a
      # correctly-parsed file whose content happens to contain a fence-shaped
      # line is odd too (note 3e lists the three shapes; six of the sixteen
      # T3c fixtures are odd with a right parse). What justifies it is the
      # measurement, not the argument — over the scanned tree the count is
      # 1,314 runs across 67 files with zero odd, so any report is a change.
      if (fence_runs % 2 == 1) {
        printf("UNBALANCED\t%s\t%d\n", file, fence_runs)
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
# T3a: No scanned file reaches EOF with a fenced block still open.
#     T3 asks whether each block it found is gated. This asks whether the
#     blocks it found are the blocks that are there. An unbalanced fence makes
#     the two diverge: every later fence in the file is read with inverted
#     parity, so a real ```bash block is swallowed by the open one, its
#     `git push` is attributed to the swallowing block, and it inherits that
#     block's gate. T3 then reports "all gated" about a push it never looked
#     at, and T3b's file pin does not move because the subject is still counted
#     in the same file. That is the note 3(d) shell-block residue, and this is
#     the assertion that closes it.
#
#     A well-formed markdown file closes the fences it opens, so the *open at
#     EOF* half is a deduction about the file rather than a guess about the
#     parse. It also covers the two residues the recovery cannot reach — a
#     `~~~text` phantom and a 4-backtick ````text phantom both leave their block
#     open at EOF, because no ``` run can close either.
#
#     A second check, because a phantom does not always reach EOF: the next
#     unrelated bare ``` closes the merged block and parity re-syncs on the pair
#     after it, leaving the file balanced at EOF with everything between the two
#     fences already swallowed. The *run count* still shows that one.
#
#     The two are not the same kind of statement, and note 3(e) is exact about
#     the difference: the EOF half is sound, the parity half is an empirical
#     guard. Parity counts every fence-shaped run, acted on or not, so a
#     correctly-parsed file containing a fence-shaped *content* line, an
#     indented-code-block ``` run, or a fence closed by its container is odd as
#     well — six of T3c's sixteen fixtures are. It is kept because it is
#     measured at zero over src/ and because the thing it catches is otherwise
#     silent, not because an odd count proves the file broken.
#
#     Today both expect zero: no scanned file ends with an open block, and all
#     1,314 fence runs across the 67 scanned files pair up.
# ───────────────────────────────────────────────────────────
unclosed_fences="$(grep '^UNCLOSED' "$scan_out" 2>/dev/null | sed -e 's/^UNCLOSED\t//' -e "s#^$REPO_ROOT/##" || true)"
unbalanced_files="$(grep '^UNBALANCED' "$scan_out" 2>/dev/null | sed -e 's/^UNBALANCED\t//' -e "s#^$REPO_ROOT/##" -e 's/\t/: /' || true)"

if [ -z "$unclosed_fences" ]; then
  pass "no scanned file ends with an unclosed fenced block"
else
  fail "a scanned file reaches EOF with a fenced block still open:"
  printf '%s\n' "$unclosed_fences" | sed 's/^/      /'
  echo "      An unbalanced fence inverts fence parity for the rest of the"
  echo "      file, so a later \`\`\`bash block is swallowed whole and its"
  echo "      \`git push\` inherits the swallowing block's gate. Close the fence."
fi

if [ -z "$unbalanced_files" ]; then
  pass "every scanned file has an even number of fence runs"
else
  fail "a scanned file has an odd number of fence runs (file: count):"
  printf '%s\n' "$unbalanced_files" | sed 's/^/      /'
  echo "      A fenced block normally contributes two runs, so an odd total"
  echo "      usually means one fence is missing its partner — and a missing"
  echo "      closer merges two blocks into one that carries a single gate flag."
  echo "      This is a measured guard, not a proof: every fence-shaped run is"
  echo "      counted, acted on or not, so a correct file is odd too if it"
  echo "      carries a fence-shaped *content* line (a heredoc writing a fence,"
  echo "      an over-indented run inside a block), a top-level indented code"
  echo "      block containing a \`\`\` run, or a fence closed by its list"
  echo "      container. src/ carries none of those today. Check the file first;"
  echo "      if the parse is right, pair the fence or add an exemption for that"
  echo "      file here rather than deleting this check."
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
# T3c: The fence parser must not let a phantom open block swallow a real one.
#      T3 and T3b notice a scan that saw the wrong *files*, but neither notices
#      a mis-parse that happens to leave today's two subjects intact — and a
#      swallowed block is exactly that: the push never becomes a subject, so the
#      pinned set is unchanged and nothing fires. So the parser is exercised
#      directly against sixteen synthetic fixtures whose expected verdict is known.
#      A–D and J–M pin list/container indentation (note 3a); E–G pin the phantom-block
#      recovery, H–I pin its *limits*, and N pins the shell arm issue #280 added
#      (note 3d); O and P pin the two fence-accounting deductions (note 3e).
#      Each fixture fails for one specific wrong model. A–N report exactly
#      1 VIOLATION; O and P assert on the UNBALANCED and UNCLOSED records
#      instead, because the shapes they pin leave the violation count untouched
#      — which is precisely what made them invisible.
#      A fixture only earns its place if some mutation makes it fail — B did not
#      until it was rebuilt, having been written for an absolute bound and left
#      trivially true when the bound became relative.
#
#      One interaction is worth stating plainly, because it costs the suite
#      something. The note 3(d) shell arm repairs the same parse that K, L and M
#      were written to protect, so those three no longer fail when the container
#      tracking alone is reverted — they fail only when the container rules and
#      the recovery are *both* reverted. Verified: at the merge base, disabling
#      update_list_containers() fails K, L and M; here it fails nothing, and the
#      compound mutation fails E, F, G, K, L, M and N. They are kept because
#      they still pin the outcome, but they no longer discriminate the bound on
#      their own, and no claim is made here that they do.
#
#        A. Too loose (no bound). An ungated `git push` that a 4-column ``` run
#           *inside* the enclosing ```bash block tries to hide. Read as a fence
#           it closes the block early, the block's real closing fence then opens
#           a phantom non-shell block, and the push is swallowed. Read correctly
#           as block content, the push is a subject.
#        B. Too tight (bound below +3). A gated ```bash block whose closing
#           fence sits 3 columns past its opener — which CommonMark allows —
#           followed by a second, ungated ```bash push. Only the second is a
#           violation. Tighten the bound and the first block never closes: it
#           swallows the second, and because the merged block carries the first
#           block's in-block citation it reads as *gated*, so the violation
#           disappears rather than moving. The opener and closer must sit at
#           different columns or this fixture is vacuous — with both at column 3
#           every bound from +0 up holds and no mutation can fail it.
#        C. Bound made *absolute* — false-negative half. An ungated `git push`
#           in a ```bash block nested in a `10. ` list item, which puts the
#           fence at column 4 while leaving it indented 0 within its container.
#        D. Bound made *absolute* — false-gate half. A `python3 … gi-secscan.py`
#           transcript inside a list-nested, display-only ```text fence,
#           followed within the 12-line window by an ungated ```bash push. An
#           absolute limit makes the ```text fence invisible, so the transcript
#           reads as prose and gates the push it has nothing to do with. This is
#           the more dangerous half: it turns a violation into a silent pass.
#        E. Phantom from a false *open*. A top-level 4-column indented code
#           block containing a ``` run — no unclosed fence anywhere, so the END
#           clause cannot help — followed by a real ```bash block with an
#           ungated push. Fails if the note 3d recovery is removed.
#        F. Phantom from an unclosed fence. A ```text fence the author never
#           closed, followed by a ```bash push. Same recovery, third entrance.
#        G. Recovery ordering. A phantom opened at column 0, then a list-nested
#           (column 4) ```bash push. Fails if the recovery is tested *behind*
#           the note 3a indent bound rather than before it — the bound rejects
#           the column-4 fence as "content of the enclosing block", which is
#           reasoning about a block that does not exist.
#        H. Recovery misfire, indented form. Fixture A's shape with `text`
#           appended to the indented run, so the run now carries an info string.
#           Inside a genuinely open ```bash block that is ordinary content; an
#           unrestricted recovery ends the block before its push and re-opens
#           the remainder as non-shell, so the push is silently lost. Fails if
#           the `is_shell_block == 0` clause is dropped. A and H are three
#           characters apart and must stay adjacent — they are the two readings
#           of the same line, and the distinction between them is the whole
#           content of that clause.
#        I. Recovery misfire, realistic form. A ```bash block whose heredoc
#           writes a fenced snippet, then pushes. Same clause, but a shape an
#           author would plausibly write.
#        J. Top-level false close. A three-space opener followed by a six-space
#           fence-shaped run. CommonMark treats that run as block content, not a
#           closer; accepting `open_indent + 3` at top level drops the push that
#           follows it from the subject set.
#        K. List-relative legal close. A bullet content column at 2, an opener at
#           2, and a legal closer at 5. An absolute three-column cap rejects it
#           and lets the gated block swallow the unrelated violation below.
#        L. Empty-list-marker legal close. Same shape as K, but the bullet marker
#           is alone on its line. CommonMark supplies one implicit padding column,
#           so its content also starts at column 2. Missing that rule rejects the
#           legal closer and swallows the later ungated push.
#        M. Outdent ends a list-contained fence. A gated list-nested fence has no
#           explicit closer before an outdented paragraph ends its container. The
#           later top-level ungated push must be parsed as its own shell block,
#           not swallowed into the already-gated list block.
#
#        N. Phantom that is itself a *shell* block. An unclosed ```bash fence,
#           gated by its own in-block citation, followed by a real ```bash push
#           block. Before #280 the recovery's `is_shell_block == 0` restriction
#           refused to fire here, so the second block was swallowed and read as
#           gated by the first block's citation — a violation that vanished
#           rather than moved. Fails if the shell arm is dropped.
#        O. Missing closer whose damage re-syncs before EOF. A dropped closing
#           fence, then a ```text block whose bare closer terminates the merged
#           block — so the file ends balanced and the EOF clause sees nothing,
#           while both pushes sit inside one gated block. Only the odd fence-run
#           count shows it. Asserts 1 UNBALANCED; fails if the parity check goes.
#        P. Block open at EOF with *even* parity. A ```text phantom, then a
#           gated ```bash block with no closer: two runs, so parity is silent
#           and only the EOF state can report it. Asserts 1 UNCLOSED. O and P
#           are the two halves of note 3(e) and neither subsumes the other.
#
#      All fixtures live in a mktemp -d scratch directory and are removed on
#      exit; nothing is written inside the repo.
# ───────────────────────────────────────────────────────────
fixture_dir="$(mktemp -d)"
trap 'rm -f "$scan_out" "$violations"; rm -rf "$fixture_dir"' EXIT

cat > "$fixture_dir/indent-4-defeat.md" <<'FIXTURE_A'
## Appendix

```bash
echo "an example"
    ```
git push origin main
```
FIXTURE_A

cat > "$fixture_dir/closer-deeper-than-opener.md" <<'FIXTURE_B'
## Appendix

```bash
# see docs/pre-commit-security.md
git push origin main
   ```

Later, an unrelated block:

```bash
git push origin main
```
FIXTURE_B

cat > "$fixture_dir/list-nested-subject.md" <<'FIXTURE_C'
## Appendix

10. Push the branch when the review is done:

    ```bash
    git push origin main
    ```
FIXTURE_C

cat > "$fixture_dir/list-nested-false-gate.md" <<'FIXTURE_D'
## Appendix

1.  Run the scan first:

    ```text
    $ python3 references/scripts/gi-secscan.py --staged
    verdict: clean
    ```

Then push:

```bash
git push origin main
```
FIXTURE_D

cat > "$fixture_dir/phantom-from-indented-code.md" <<'FIXTURE_E'
## Appendix

The scanner prints a verdict line that looks like this:

    ```text
    verdict: clean

Once you are satisfied, publish the branch:

```bash
git commit -am "wip"
git push origin main
```
FIXTURE_E

cat > "$fixture_dir/phantom-from-unclosed-fence.md" <<'FIXTURE_F'
## Appendix

An unclosed display fence:

```text
verdict: clean

Now publish:

```bash
git push origin main
```
FIXTURE_F

cat > "$fixture_dir/phantom-swallows-list-nested.md" <<'FIXTURE_G'
## Appendix

```text
verdict: clean

Some prose in between.

1.  Publish the branch:

    ```bash
    git push origin main
    ```
FIXTURE_G

cat > "$fixture_dir/recovery-misfire-in-shell-block.md" <<'FIXTURE_H'
## Appendix

```bash
echo "an example"
    ```text
git push origin main
```
FIXTURE_H

cat > "$fixture_dir/recovery-misfire-on-heredoc.md" <<'FIXTURE_I'
## Appendix

Record the release note, then publish:

```bash
cat >> notes.md <<'NOTE'
```text
verdict: clean
NOTE
git push origin main
```
FIXTURE_I

cat > "$fixture_dir/top-level-overindented-false-close.md" <<'FIXTURE_J'
## Appendix

   ```bash
      ```
   git push origin main
   ```
FIXTURE_J

cat > "$fixture_dir/list-relative-closer.md" <<'FIXTURE_K'
## Appendix

- First block:
  ```bash
  # see docs/pre-commit-security.md
  git push origin main
     ```

Later, an unrelated block:

```bash
git push origin main
```
FIXTURE_K

cat > "$fixture_dir/empty-list-marker-closer.md" <<'FIXTURE_L'
## Appendix

-
  ```bash
  # see docs/pre-commit-security.md
  git push origin main
     ```

Later, an unrelated block:

```bash
git push origin main
```
FIXTURE_L

cat > "$fixture_dir/list-fence-ended-by-outdent.md" <<'FIXTURE_M'
## Appendix

- First, publish the reviewed branch:
  ```bash
  # see docs/pre-commit-security.md
  git push origin reviewed

This paragraph ends the list container and its fenced block.

```bash
git push origin main
```
FIXTURE_M

cat > "$fixture_dir/phantom-shell-swallows-real-block.md" <<'FIXTURE_N'
## Appendix

```bash
# see docs/pre-commit-security.md
git push origin reviewed

Prose in between.

```bash
git push origin main
```
FIXTURE_N

cat > "$fixture_dir/missing-closer-resyncs-before-eof.md" <<'FIXTURE_O'
## Appendix

```bash
# see docs/pre-commit-security.md
git push origin reviewed
git push --force origin main

The author meant the fence above to close here.

```text
verdict: clean
```
FIXTURE_O

cat > "$fixture_dir/phantom-open-at-eof-even-parity.md" <<'FIXTURE_P'
## Appendix

```text
verdict: clean

Then publish:

```bash
# see docs/pre-commit-security.md
git push origin main
FIXTURE_P

fixture_violations() {
  scan_file "$1" | grep -c '^VIOLATION' || true
}

fixture_unbalanced() {
  scan_file "$1" | grep -c '^UNBALANCED' || true
}

fixture_unclosed() {
  scan_file "$1" | grep -c '^UNCLOSED' || true
}

if [ "$(fixture_violations "$fixture_dir/indent-4-defeat.md")" = "1" ]; then
  pass "fence parser treats a \`\`\` run 4 columns past its opener as block content"
else
  fail "fence parser closed a block on a run indented 4+ columns past its opener"
  echo "      A closing fence is never more than 3 columns past its opening"
  echo "      fence. Closing the block on a deeper run inverts fence parity for"
  echo "      the rest of the file, so every later \`\`\`bash block is swallowed"
  echo "      and an ungated \`git push\` is never evaluated. See header note 3a."
fi

if [ "$(fixture_violations "$fixture_dir/closer-deeper-than-opener.md")" = "1" ]; then
  pass "fence parser accepts a closing fence up to 3 columns past its opener"
else
  fail "fence parser rejected a closing fence within 3 columns of its opener"
  echo "      CommonMark allows a closing fence 0–3 columns past its opener, and"
  echo "      rejecting one does not merely mislabel a line: the block stays"
  echo "      open and swallows the ungated \`\`\`bash block below it. Because the"
  echo "      swallowing block carries its own in-block citation, the merged"
  echo "      block reads as gated and the violation vanishes rather than"
  echo "      moving. See header note 3a."
fi

if [ "$(fixture_violations "$fixture_dir/list-nested-subject.md")" = "1" ]; then
  pass "fence parser sees a \`\`\`bash block nested in a list item (opener at column 4)"
else
  fail "fence parser missed a list-nested \`\`\`bash block — the indent bound is absolute"
  echo "      A \`10. \` list item puts its content at column 4, so a fence nested"
  echo "      in one is indented 0 relative to its own container. Bounding the"
  echo "      opener at an absolute 3 columns erases every such block, and an"
  echo "      ungated \`git push\` inside one is neither subject nor violation."
  echo "      The bound belongs on the closing fence, relative to its opener."
fi

if [ "$(fixture_violations "$fixture_dir/list-nested-false-gate.md")" = "1" ]; then
  pass "a transcript in a list-nested display-only fence does not gate a later push"
else
  fail "a \`\`\`text transcript nested in a list item falsely gated an ungated push"
  echo "      With the indent bound applied absolutely, the list-nested \`\`\`text"
  echo "      fence is invisible, so its transcript of the scan is read as prose"
  echo "      and lands in the 12-line window above an unrelated \`\`\`bash push"
  echo "      block — which it then gates. A transcript of the scan running is"
  echo "      not the scan running. See header note 3a."
fi

if [ "$(fixture_violations "$fixture_dir/phantom-from-indented-code.md")" = "1" ]; then
  pass "a phantom block opened by an indented code block does not swallow a push"
else
  fail "a \`\`\`bash push block was swallowed by a phantom open block"
  echo "      A top-level 4-column indented code block containing a \`\`\` run"
  echo "      opens a block that CommonMark never opened. Nothing here is an"
  echo "      unclosed fence, so the END clause does not help: the phantom eats"
  echo "      the next real \`\`\`bash block whole, the push never becomes a"
  echo "      subject, and T3b's pinned file set is unchanged. See note 3d."
fi

if [ "$(fixture_violations "$fixture_dir/phantom-from-unclosed-fence.md")" = "1" ]; then
  pass "an unclosed display fence does not swallow the next \`\`\`bash block"
else
  fail "an unclosed \`\`\`text fence swallowed the following \`\`\`bash push block"
  echo "      Only a same-character run with an *empty* info string closes a"
  echo "      block, so without the note 3d recovery the following \`\`\`bash line"
  echo "      reads as content and that block's closing \`\`\` is consumed as the"
  echo "      text block's terminator — one real subject lost per stray fence."
fi

if [ "$(fixture_violations "$fixture_dir/phantom-swallows-list-nested.md")" = "1" ]; then
  pass "phantom recovery is tested before the indent bound, not behind it"
else
  fail "a phantom at column 0 swallowed a list-nested \`\`\`bash push block"
  echo "      The note 3d recovery must be checked BEFORE the note 3a indent"
  echo "      bound. That bound reasons \"a run this deep is content of the"
  echo "      enclosing block\" — which is void when the enclosing block is a"
  echo "      phantom. Behind the bound, a phantom opened at column 0 still eats"
  echo "      every list-nested block below it."
fi

if [ "$(fixture_violations "$fixture_dir/recovery-misfire-in-shell-block.md")" = "1" ]; then
  pass "phantom recovery does not fire inside a genuinely open shell block"
else
  fail "phantom recovery abandoned an open \`\`\`bash block and lost its push"
  echo "      This is fixture A's shape with an info string appended to the"
  echo "      indented run. Inside an open shell block that run is ordinary"
  echo "      content, but an ungated recovery reads it as proof of a phantom,"
  echo "      ends the block before the \`git push\` is reached, and re-opens the"
  echo "      remainder as non-shell — so the push becomes neither subject nor"
  echo "      violation and the scan output is empty. See header note 3d."
fi

if [ "$(fixture_violations "$fixture_dir/recovery-misfire-on-heredoc.md")" = "1" ]; then
  pass "phantom recovery survives a heredoc that writes a fence inside a block"
else
  fail "phantom recovery abandoned a \`\`\`bash block at a heredoc's fenced text"
  echo "      A shell block whose heredoc writes a fenced snippet contains a"
  echo "      \`\`\`text line as plain content. Recovering on it drops the rest of"
  echo "      the block, including the \`git push\` below the heredoc. Only the"
  echo "      is_shell_block == 0 clause keeps this block intact."
fi

if [ "$(fixture_violations "$fixture_dir/top-level-overindented-false-close.md")" = "1" ]; then
  pass "top-level fence closers are independently limited to three columns"
else
  fail "a six-space run falsely closed a top-level block opened at three spaces"
  echo "      CommonMark permits each top-level fence at columns 0–3; the closing"
  echo "      bound is not relative to the opener. Treating open_indent + 3 as"
  echo "      legal here closes early and drops the following \`git push\`."
fi

if [ "$(fixture_violations "$fixture_dir/list-relative-closer.md")" = "1" ]; then
  pass "list-nested fence closers use the container-relative three-column limit"
else
  fail "a legal list-nested closer was rejected by an absolute indent bound"
  echo "      The list content begins at column 2, so CommonMark permits its closer"
  echo "      through column 5. Rejecting it merges the next block into the first"
  echo "      gated block and hides the unrelated \`git push\` violation."
fi

if [ "$(fixture_violations "$fixture_dir/empty-list-marker-closer.md")" = "1" ]; then
  pass "empty list markers supply CommonMark's implicit content indentation"
else
  fail "an empty list marker lost its implicit one-column content padding"
  echo "      A marker alone on its line still puts list content at column 2."
  echo "      Missing that implicit column rejects the legal closer at column 5,"
  echo "      merging the later ungated \`git push\` into the first gated block."
fi

if [ "$(fixture_violations "$fixture_dir/list-fence-ended-by-outdent.md")" = "1" ]; then
  pass "an outdent ends a list-contained fence before a later top-level block"
else
  fail "a list-contained gated fence swallowed a top-level ungated push"
  echo "      An outdented non-blank line ends the list container and its open"
  echo "      fence. The line must then be parsed again outside that block, or the"
  echo "      later top-level \`\`\`bash push is absorbed by the already-gated fence."
fi

if [ "$(fixture_violations "$fixture_dir/phantom-shell-swallows-real-block.md")" = "1" ]; then
  pass "an unclosed \`\`\`bash fence does not swallow the next \`\`\`bash push block"
else
  fail "a phantom *shell* block swallowed the next \`\`\`bash push block"
  echo "      The note 3(d) recovery is restricted to a display-only open block,"
  echo "      so a phantom the parser reads as a shell block — an unclosed"
  echo "      \`\`\`bash or \`\`\`console fence — had no guard at either end. The"
  echo "      swallowed push inherits the phantom's gate and reads as gated. The"
  echo "      recovery must also fire when the *incoming* run names a shell"
  echo "      language, which a heredoc writing \`\`\`text never does."
fi

if [ "$(fixture_unbalanced "$fixture_dir/missing-closer-resyncs-before-eof.md")" = "1" ]; then
  pass "a missing closer is caught even when parity re-syncs before EOF"
else
  fail "a missing closing fence went unreported because the file ended balanced"
  echo "      A dropped closer does not always leave a block open at EOF: the"
  echo "      next unrelated fence closes the merged block and the file ends"
  echo "      clean, while every line between the two has been swallowed into a"
  echo "      block carrying one gate flag. The run *count* still shows it —"
  echo "      each block contributes exactly two runs. See note 3(e)."
fi

if [ "$(fixture_unclosed "$fixture_dir/phantom-open-at-eof-even-parity.md")" = "1" ]; then
  pass "a block left open at EOF is reported even when fence parity is even"
else
  fail "a fenced block still open at EOF went unreported"
  echo "      Parity and EOF state are independent: a run *inside* an open block"
  echo "      is counted but toggles nothing, so a file can end with a block"
  echo "      open and an even run count. Both deductions are needed; neither"
  echo "      subsumes the other. See note 3(e)."
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
