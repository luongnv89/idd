#!/usr/bin/env bash
# test-agent-conventions-inline-245.sh — shared-agent conventions must travel
# inside the injected prompt (issue #245).
#
# A spawned subagent's working directory is the *target repo*, not the skill
# directory, so `references/docs/shared-agent-conventions.md` dangles at spawn
# time and every safety rule it carries silently fails to load. The build now
# inlines those rules into each emitted agent prompt and renders every logical
# reference inside an agent file as an absolute repo URL.
#
# Asserts:
#   T1 — every built agent file carries the inlined conventions preamble, and
#        each required section heading appears *inside the preamble region*
#        (not merely somewhere in the file).
#   T2 — each inlined section is byte-identical to the corresponding section of
#        docs/shared-agent-conventions.md (single source of truth, no drift).
#   T3 — no built agent file cites a path that is unresolvable from a target
#        repo's working directory (URL-masked scan, mirrors build.py semantics).
#   T4 — the bundled references/docs/shared-agent-conventions.md still exists in
#        every skill whose "Bundled dependency precheck" names it. Guards the
#        regression where killing the closure edge un-bundles the doc and breaks
#        the runtime precheck.
#   T5 — the confidence scale is inlined for review agents only.
#   T6 — for every agent whose file carries a `## Prompt` fenced block
#        (code-reviewer / fixer / ui-reviewer), the preamble sits *inside* that
#        fence. The orchestrator injects only the fence body, so a preamble
#        emitted above `## Contract` still satisfies T1/T2 while never reaching
#        the subagent — AC1 would be false with the suite fully green.
#
# Operates on the committed skills/ + .pi/agents/ trees (and dist/agents/ when
# present) so doc→build drift is caught, not masked by a rebuild.
#
# Usage: bash tests/test-agent-conventions-inline-245.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_SH="$REPO_ROOT/scripts/build.sh"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Shared-Agent Conventions Inlining Tests (issue #245)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ ! -d "$REPO_ROOT/skills" ]; then
  echo "  ○ skills/ missing — running build..."
  "$BUILD_SH" >/dev/null 2>&1 || {
    fail "Pre-build failed — cannot run scan"
    exit 1
  }
fi

# All assertions run in one Python pass; each prints "PASS <label>" or
# "FAIL <label>" so the bash layer keeps the repo's counter/format style.
# The results go through a temp file rather than $(...) — the analysis script
# contains quote characters that a command substitution would try to lex.
REPORT_FILE="$(mktemp "${TMPDIR:-/tmp}/idd-245.XXXXXX")"
trap 'rm -f "$REPORT_FILE"' EXIT

python3 - "$REPO_ROOT" >"$REPORT_FILE" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
out = []


def ok(label):
    out.append(f"PASS {label}")


def bad(label):
    out.append(f"FAIL {label}")


# ── Mirror of scripts/build.py contract (deliberately re-stated here so the
# ── test fails independently if the build's constants are weakened).
PREAMBLE_HEADING = "## Shared agent conventions (inlined — no file lookup required)"
SECTIONS_ALL = (
    "Tool posture",
    "Prompt-injection boundary",
    "Platform driver",
    "Autonomous operation",
    "Output discipline",
)
SECTIONS_REVIEW = ("Confidence scale (review agents)",)
REVIEW_AGENTS = {"code-reviewer", "ui-reviewer"}
REPO_BLOB = "https://github.com/luongnv89/idd/blob/main/"

URL_RE = re.compile(r"https?://[^\s<>'\"\)]+")
DOC_TOKEN_RE = re.compile(r"(?<![\w/])docs/([a-z][a-z0-9-]+\.md)")
DANGLING_RE = re.compile(
    r"(?<![\w/])("
    r"references/[A-Za-z0-9._/-]+\.[A-Za-z0-9]+"
    r"|docs/[a-z][a-z0-9-]+\.md"
    r"|shared/agents/[a-z][a-z0-9-]+\.md"
    r"|skills/[a-z][a-z0-9-]+/SKILL\.md"
    r")"
)
PRECHECK_HEADING_RE = re.compile(r"^\s{0,3}#{2,4}\s+Bundled dependency precheck\s*$")


def doc_section(text, heading):
    m = re.search(
        r"^## " + re.escape(heading) + r"[ \t]*\n(?P<body>.*?)(?=^## |\Z)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    return m.group("body").strip() if m else ""


# ── Inputs -------------------------------------------------------------------
conv_doc = root / "docs" / "shared-agent-conventions.md"
if not conv_doc.is_file():
    bad("T0: docs/shared-agent-conventions.md exists")
    print("\n".join(out))
    sys.exit(0)

conv_text = conv_doc.read_text(encoding="utf-8")
expected = {}
for heading in SECTIONS_ALL + SECTIONS_REVIEW:
    body = doc_section(conv_text, heading)
    if not body:
        bad(f"T0: docs/shared-agent-conventions.md has a non-empty '## {heading}' section")
    # The build rewrites bare docs/X.md tokens inside agent files to repo URLs.
    expected[heading] = DOC_TOKEN_RE.sub(
        lambda m: f"{REPO_BLOB}docs/{m.group(1)}", body
    )

agent_files = sorted(root.glob("skills/*/references/agents/*.md"))
agent_files += sorted((root / ".pi" / "agents").glob("*.md"))
dist_agents = root / "dist" / "agents"
if dist_agents.is_dir():
    agent_files += sorted(dist_agents.glob("*.md"))

# Non-vacuity guard: an empty file list would make every per-file loop below
# pass without checking anything.
if len(agent_files) >= 21:
    ok(f"T0: found {len(agent_files)} built agent files to scan")
else:
    bad(f"T0: expected >= 21 built agent files, found {len(agent_files)}")
    print("\n".join(out))
    sys.exit(0)


def preamble_region(text):
    """Text from the preamble heading to the next '## ' heading after it.

    Anchoring matters: a whole-file search would pass on a file that merely
    mentions a section name somewhere else, and would keep passing if the
    preamble were emitted outside the injected prompt.
    """
    start = text.find(PREAMBLE_HEADING)
    if start == -1:
        return None
    after = text[start + len(PREAMBLE_HEADING):]
    nxt = re.search(r"^## ", after, re.MULTILINE)
    return after[: nxt.start()] if nxt else after


# ── T1 / T2 / T5 -------------------------------------------------------------
missing_preamble = []
missing_section = []
drifted = []
review_leak = []

for f in agent_files:
    label = f.relative_to(root).as_posix()
    text = f.read_text(encoding="utf-8")
    region = preamble_region(text)
    if region is None:
        missing_preamble.append(label)
        continue
    agent_name = f.stem
    wanted = list(SECTIONS_ALL)
    if agent_name in REVIEW_AGENTS:
        wanted += list(SECTIONS_REVIEW)
    for heading in wanted:
        if f"\n### {heading}\n" not in region:
            missing_section.append(f"{label} → {heading}")
            continue
        if expected[heading] not in region:
            drifted.append(f"{label} → {heading}")
    for heading in SECTIONS_REVIEW:
        if agent_name not in REVIEW_AGENTS and f"\n### {heading}\n" in region:
            review_leak.append(f"{label} → {heading}")

if missing_preamble:
    bad(f"T1.1: every built agent carries the inlined preamble ({len(missing_preamble)} missing: {missing_preamble[:3]})")
else:
    ok("T1.1: every built agent carries the inlined conventions preamble")

if missing_section:
    bad(f"T1.2: required sections present inside the preamble region ({missing_section[:4]})")
else:
    ok("T1.2: every required conventions section is inside the preamble region")

if drifted:
    bad(f"T2: inlined sections match docs/shared-agent-conventions.md ({drifted[:4]})")
else:
    ok("T2: inlined sections are byte-identical to docs/shared-agent-conventions.md")

if review_leak:
    bad(f"T5: confidence scale inlined for review agents only ({review_leak[:4]})")
else:
    ok("T5: confidence scale is inlined for code-reviewer/ui-reviewer only")

# ── T6 — the preamble is inside the injected prompt fence --------------------
# T1/T2/T5 anchor on the `## ` heading structure alone, which is satisfied
# wherever the preamble lands. For the fenced agents only the fence *body* is
# injected, so placement is the property AC1 actually rests on.
PROMPT_FENCE_RE = re.compile(r"^## Prompt[ \t]*\n+^(```[A-Za-z]*[ \t]*)\n", re.MULTILINE)

fenced_seen = 0
outside_fence = []
for f in agent_files:
    text = f.read_text(encoding="utf-8")
    m = PROMPT_FENCE_RE.search(text)
    if m is None:
        continue
    fenced_seen += 1
    label = f.relative_to(root).as_posix()
    body_start = m.end()
    close = re.search(r"^```[ \t]*$", text[body_start:], re.MULTILINE)
    body_end = body_start + close.start() if close else len(text)
    at = text.find(PREAMBLE_HEADING)
    if not (body_start <= at < body_end):
        where = "absent" if at == -1 else f"offset {at}, fence body {body_start}-{body_end}"
        outside_fence.append(f"{label} ({where})")

# Non-vacuity: 3 fenced agents × (issue-resolver, issue-pr-review, .pi) = 9,
# plus dist/agents/ when present.
if fenced_seen < 9:
    bad(f"T6: expected >= 9 fenced agent prompts, found {fenced_seen}")
elif outside_fence:
    bad(f"T6: preamble inside the injected ## Prompt fence ({len(outside_fence)} outside: {outside_fence[:3]})")
else:
    ok(f"T6: preamble is inside the injected prompt fence in all {fenced_seen} fenced agents")

# ── T3 — no unresolvable path in any built agent file ------------------------
dangling = []
for f in agent_files:
    text = f.read_text(encoding="utf-8")
    masked = URL_RE.sub(lambda m: " " * len(m.group(0)), text)
    for m in DANGLING_RE.finditer(masked):
        line_no = masked[: m.start()].count("\n") + 1
        dangling.append(f"{f.relative_to(root).as_posix()}:{line_no}: {m.group(1)}")

if dangling:
    bad(f"T3: no built agent cites an unresolvable path ({len(dangling)} hits: {dangling[:4]})")
else:
    ok("T3: no built agent file cites a path unresolvable from a target repo cwd")

# ── T4 — precheck-named bundle still present ---------------------------------
CONV_REF = "references/docs/shared-agent-conventions.md"
named, broken = 0, []
for skill_md in sorted(root.glob("skills/*/SKILL.md")):
    lines = skill_md.read_text(encoding="utf-8").splitlines()
    start = None
    for i, line in enumerate(lines):
        if PRECHECK_HEADING_RE.match(line):
            start = i + 1
            break
    if start is None:
        continue
    body = []
    for line in lines[start:]:
        if re.match(r"^\s*##\s", line) or re.match(r"^\s*---\s*$", line):
            break
        body.append(line)
    if CONV_REF not in "\n".join(body):
        continue
    named += 1
    if not (skill_md.parent / CONV_REF).is_file():
        broken.append(skill_md.parent.name)

if named == 0:
    bad("T4: at least one skill precheck names the bundled conventions doc")
elif broken:
    bad(f"T4: precheck-named conventions doc bundled in every naming skill (missing in: {broken})")
else:
    ok(f"T4: conventions doc bundled in all {named} skills whose precheck names it")

print("\n".join(out))
PY

while IFS= read -r line; do
  case "$line" in
    PASS\ *) pass "${line#PASS }" ;;
    FAIL\ *) fail "${line#FAIL }" ;;
    *) [ -n "$line" ] && echo "    $line" ;;
  esac
done < "$REPORT_FILE"

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [ "$FAIL" -gt 0 ]; then
  echo "  ✗ Shared-agent conventions are not reaching injected prompts"
  exit 1
fi

echo "  ✓ Shared-agent conventions travel inside every injected prompt"
exit 0
