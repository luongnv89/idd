# anchors.bash — anchor-scoped contract assertions for the IDD test suite.
#
# Sourced by tests/*.sh; never executed as a test case. The `.bash` extension is
# deliberate: the test command of record (`git ls-files 'tests/*.sh' | xargs -n1
# bash`) and the T9 CI-wiring check in tests/test-build-script.sh both discover
# tests with a git pathspec whose `*` crosses `/`, so a `tests/lib/anchors.sh`
# would be run as a test and demand its own dist-check.yml step.
#
# WHY (issue #358, finding F-TEST-004)
# ────────────────────────────────────
# 36 of 61 test files greped exact English sentences out of skill prose. That
# coupling fails in both directions: rewording a sentence without changing what
# it requires turns CI red, and gutting what it requires while keeping the
# sentence stays green. Anchors separate the two.
#
# AN ANCHOR is the inline HTML comment `<!-- a:<id> -->`, appended to the line
# that opens a contract-critical block of prose in an authored `src/` file. It
# is inert: invisible in rendered Markdown, never read by a skill at runtime,
# and copied byte-identically into `skills/` by scripts/build.py — so a single
# anchor in `src/` serves both the source-side and built-side assertions.
#
# AN ANCHOR REGION runs from the anchor line through the line before the next
# anchor or the next Markdown ATX heading, whichever comes first. Headings and
# anchors inside fenced code blocks do not close a region.
#
# AN ANCHOR SPAN is the pair `<start-id> … <end-id>`: everything from the start
# anchor's line through the line before the end anchor's line. Use it where a
# contract block legitimately contains sub-headings, which a single region stops
# at. Both ids name real sections, so a span never needs a filler marker, and it
# replaces the two exact heading strings an `awk '/^## A/,/^## B/'` extraction
# would otherwise pin.
#
# WHAT TO ASSERT INSIDE A REGION — two tiers, in order of preference:
#   1. A stable machine token the contract turns on: an identifier, config key,
#      command string, placeholder (`{linked_issue}`), or literal output line.
#      Anchor-scoping makes these *stronger* than the greps they replace: the
#      token must appear in the right block, not merely somewhere in the file.
#   2. Where a contract is purely normative prose with no machine token, a short
#      keyword stem any faithful restatement must still contain (`authenticat`,
#      `interpolat`). Far more reword-tolerant than a full sentence, still red
#      when the claim is dropped.
# Never assert a whole English sentence — that is the coupling being removed.
#
# POLARITY. Where the contract is a prohibition, a negation, or a condition, the
# stem MUST come from the polarity-bearing word (`**not**`, `never`, `**no**`,
# `without`, `only after`, `when … links`) — never from the subject noun. A stem
# taken from the subject (`mismatch`, `refresh`) survives the claim's own
# inversion and asserts nothing. For the same reason, never `|`-alternate a
# polarity-bearing token with a polarity-free one: the weakest branch defines
# the assertion.
#
# HARD WRAP. Prose in this repo is hard-wrapped and the helpers below grep the
# region line by line, so no single pattern can span a wrapped claim. A claim
# whose subject and predicate straddle a line break needs `anchor_check_flat`,
# which joins the region into one line before matching.
#
# TEETH. Every helper below fails when the anchor is missing (the contract was
# deleted) or appears more than once (the region is ambiguous), independently of
# the pattern. A migrated assertion therefore keeps three failure modes, not one.
#
# CALLER CONTRACT. Define pass() and fail() before calling anchor_check,
# anchor_check_flat, or anchor_lacks; they are resolved at call time.

# anchor_region FILE ID — print the anchor's region on stdout.
# Exit 1 when the file is unreadable, or the anchor is absent or not unique.
# Exit 2 when ID is not a well-formed anchor id.
anchor_region() {
  local file="$1" id="$2" hits

  case "$id" in
    *[!a-z0-9-]* | '' | -* | *-) return 2 ;;
  esac

  [ -r "$file" ] || return 1

  hits="$(grep -cF -- "<!-- a:${id} -->" "$file" 2>/dev/null || true)"
  [ "${hits:-0}" = "1" ] || return 1

  awk -v id="$id" '
    BEGIN { marker = "<!-- a:" id " -->" }
    { if ($0 ~ /^[[:space:]]*(```|~~~)/) fence = !fence }
    !seen && index($0, marker) { seen = 1; print; next }
    seen && !fence && ($0 ~ /^#+ / || $0 ~ /<!-- a:[a-z0-9-]+ -->/) { exit }
    seen { print }
  ' "$file"
}

# anchor_span FILE START_ID END_ID — print from the START anchor's line through
# the line before the END anchor's line.
# Exit 1 when the file is unreadable, either anchor is absent or not unique, or
# END does not follow START. Exit 2 when an id is not a well-formed anchor id.
anchor_span() {
  local file="$1" start="$2" end="$3" id

  for id in "$start" "$end"; do
    case "$id" in
      *[!a-z0-9-]* | '' | -* | *-) return 2 ;;
    esac
  done

  [ -r "$file" ] || return 1

  for id in "$start" "$end"; do
    [ "$(grep -cF -- "<!-- a:${id} -->" "$file" 2>/dev/null || true)" = "1" ] || return 1
  done

  awk -v s="<!-- a:$start -->" -v e="<!-- a:$end -->" '
    index($0, e) { if (seen) ok = 1; exit }
    index($0, s) { seen = 1 }
    seen { print }
    END { exit ok ? 0 : 1 }
  ' "$file"
}

# anchor_check FILE ID REGEX MSG — region must exist, be unique, and match REGEX.
anchor_check() {
  local file="$1" id="$2" pattern="$3" msg="$4" region rc=0
  region="$(anchor_region "$file" "$id")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$msg"
    printf '      anchor a:%s is missing or not unique in %s\n' "$id" "$file"
    return 0
  fi
  if printf '%s\n' "$region" | grep -qE -- "$pattern"; then
    pass "$msg"
  else
    fail "$msg"
    printf '      anchor a:%s region lacks: %s\n' "$id" "$pattern"
  fi
}

# anchor_check_flat FILE ID REGEX MSG — as anchor_check, but the region's lines
# are joined into one line separated by single spaces before matching, so a
# pattern may span hard-wrapped prose.
anchor_check_flat() {
  local file="$1" id="$2" pattern="$3" msg="$4" region flat rc=0
  region="$(anchor_region "$file" "$id")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$msg"
    printf '      anchor a:%s is missing or not unique in %s\n' "$id" "$file"
    return 0
  fi
  flat="$(printf '%s\n' "$region" | tr '\n' ' ')"
  if printf '%s\n' "$flat" | grep -qE -- "$pattern"; then
    pass "$msg"
  else
    fail "$msg"
    printf '      anchor a:%s flattened region lacks: %s\n' "$id" "$pattern"
  fi
}

# anchor_lacks FILE ID REGEX MSG — region must exist, be unique, and NOT match.
anchor_lacks() {
  local file="$1" id="$2" pattern="$3" msg="$4" region rc=0
  region="$(anchor_region "$file" "$id")" || rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "$msg"
    printf '      anchor a:%s is missing or not unique in %s\n' "$id" "$file"
    return 0
  fi
  if printf '%s\n' "$region" | grep -qE -- "$pattern"; then
    fail "$msg"
    printf '      anchor a:%s region must not contain: %s\n' "$id" "$pattern"
  else
    pass "$msg"
  fi
}

# anchor_present FILE ID MSG — the anchor exists exactly once. Use only for a
# contract with no assertable token of its own; prefer anchor_check.
anchor_present() {
  local file="$1" id="$2" msg="$3"
  if anchor_region "$file" "$id" >/dev/null 2>&1; then
    pass "$msg"
  else
    fail "$msg"
    printf '      anchor a:%s is missing or not unique in %s\n' "$id" "$file"
  fi
}
