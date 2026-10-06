#!/usr/bin/env bash
# test-webpage-ux-clarity-361.sh — UX clarity on landing.html + docs.html
# (issue #361 / F-UX-004, F-UX-005, F-UX-010).
#
# Asserts:
#   F-UX-005 — docs.html has an Install section that defines/links asm and
#              offers a manual-copy alternative
#   F-UX-004 — the primary "Read the full docs" button targets docs.html
#   F-UX-010 — IDD, CursorBench, and SKILL.md are defined at first use;
#              a single product brand (IDD Stack) is used on these pages
#   T8       — the single product brand is IDD Stack (issue #512, superseding
#              IDD and gitissue): after literal identifiers (.gitissue.yml,
#              .gitissue/, init-gitissue, gitissue:normalized, the
#              ~/.cache/gitissue path) are removed, no "gitissue" remains on
#              the website, llms.txt, or the README-level docs
#   T9       — "IDD Stack" fills every product-name slot: page titles,
#              og:site_name, JSON-LD names, llms.txt H1, the plugin
#              displayName, and the plugin README H1. "IDD" alone stays the
#              methodology name (Issue-Driven Development)
#
# Static HTML only — no browser, no JS runner.
#
# Usage: bash tests/test-webpage-ux-clarity-361.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING="$REPO_ROOT/landing.html"
DOCS="$REPO_ROOT/docs.html"
LLMS="$REPO_ROOT/llms.txt"
CHANGELOG_PAGE="$REPO_ROOT/changelog.html"
PLUGIN_JSON="$REPO_ROOT/src/plugin/plugin.json"
PLUGIN_README="$REPO_ROOT/src/plugin/README.md"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Webpage UX clarity (#361)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if [ -f "$LANDING" ] && [ -f "$DOCS" ] && [ -f "$LLMS" ]; then
  pass "T0: landing.html, docs.html, and llms.txt present"
else
  fail "T0: landing.html, docs.html, or llms.txt missing"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

# ── F-UX-005: docs.html install section defines/links asm + manual path ──
if grep -q 'id="install"' "$DOCS"; then
  pass "T1: docs.html has an #install section"
else
  fail "T1: docs.html has no #install section"
fi

if grep -q 'href="https://github.com/luongnv89/asm"' "$DOCS" \
   && grep -q 'agent-skill-manager' "$DOCS" \
   && grep -q 'asm install https://github.com/luongnv89/idd' "$DOCS"; then
  pass "T2: docs.html defines asm (agent-skill-manager) and links the repo"
else
  fail "T2: docs.html does not define/link asm or show the install command"
fi

if grep -q 'cp -r' "$DOCS" && grep -qi 'manual' "$DOCS"; then
  pass "T3: docs.html offers a manual-copy install alternative"
else
  fail "T3: docs.html has no manual-copy install alternative"
fi

# ── F-UX-004: primary docs CTA targets local docs.html, not GitHub root ──
cta_href="$(python3 -c '
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<a class=\"btn btn-primary\" href=\"([^\"]+)\">▶ Read the full docs</a>", html)
print(m.group(1) if m else "")
' "$LANDING")"
if [ "$cta_href" = "docs.html" ]; then
  pass "T4: primary Read the full docs button href is docs.html"
else
  fail "T4: primary docs button href is '${cta_href:-missing}', expected docs.html"
fi

# ── F-UX-010: first-use definitions ──
first_use_ok="$(python3 -c '
import sys

def first_window(text, term, before=80, after=160):
    i = text.find(term)
    if i < 0:
        return None
    return text[max(0, i - before): i + after]

landing = open(sys.argv[1], encoding="utf-8").read()
docs = open(sys.argv[2], encoding="utf-8").read()
ok = True

idd = first_window(landing, "IDD")
if not idd or "Issue-Driven Development" not in idd:
    print("IDD first use on landing is not defined as Issue-Driven Development")
    ok = False

cb = first_window(landing, "CursorBench")
if not cb or "coding-agent benchmark" not in cb:
    print("CursorBench first use is not defined as a coding-agent benchmark")
    ok = False

sk = first_window(landing, "SKILL.md")
if not sk or "teaches" not in sk:
    print("SKILL.md first use is not defined as the file that teaches an agent a skill")
    ok = False

# docs.html also uses IDD; first use there must expand it too
idd_docs = first_window(docs, "IDD")
if idd_docs is not None and "Issue-Driven Development" not in idd_docs:
    print("IDD first use on docs.html is not defined")
    ok = False

sys.exit(0 if ok else 1)
' "$LANDING" "$DOCS")" && first_use_status=0 || first_use_status=$?
if [ "$first_use_status" -eq 0 ]; then
  pass "T5: IDD, CursorBench, and SKILL.md are defined at first use"
else
  fail "T5: first-use glossary missing"
  printf '%s\n' "$first_use_ok" | sed 's/^/        /'
fi

# ── F-UX-010: single on-page brand (IDD Stack), no issuedev dual-name ──
if grep -q 'issuedev / gitissue' "$LANDING" "$DOCS" \
   || grep -q 'gitissue / issuedev' "$LANDING" "$DOCS"; then
  fail "T6: dual issuedev/gitissue naming still present"
else
  pass "T6: no dual issuedev/gitissue phrase"
fi

issuedev_hits="$(grep -c 'issuedev' "$LANDING" "$DOCS" || true)"
# grep -c with two files prints "file:n" per file; sum the numbers.
issuedev_total="$(printf '%s\n' "$issuedev_hits" | awk -F: '{s+=$NF} END {print s+0}')"
if [ "$issuedev_total" -eq 0 ]; then
  pass "T7: issuedev is gone from landing.html and docs.html (brand is IDD Stack)"
else
  fail "T7: issuedev still appears $issuedev_total time(s) on landing.html/docs.html"
fi

# ── Single brand is IDD Stack: "gitissue" survives only inside literal identifiers ──
brand_out="$(python3 -c '
import re, sys

allow = re.compile(r"\.gitissue\.yml|\.gitissue/|init-gitissue|gitissue:normalized|cache\}?/gitissue", re.I)
bad = []
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    scrubbed = allow.sub("", text)
    for m in re.finditer(r"gitissue", scrubbed, re.I):
        ctx = scrubbed[max(0, m.start() - 40): m.end() + 40].replace("\n", "\\n")
        bad.append("%s: ...%s..." % (path, ctx))
for line in bad:
    print(line)
sys.exit(1 if bad else 0)
' "$LANDING" "$DOCS" "$CHANGELOG_PAGE" "$LLMS" "$PLUGIN_README" \
  "$REPO_ROOT/README.md" "$REPO_ROOT/CONTRIBUTING.md" "$REPO_ROOT/SPEC.md" \
  "$REPO_ROOT/docs/skills.md")" && brand_status=0 || brand_status=$?
if [ "$brand_status" -eq 0 ]; then
  pass "T8: no \"gitissue\" outside literal identifiers on the site, llms.txt, or README-level docs"
else
  fail "T8: \"gitissue\" survives outside literal identifiers (brand is IDD Stack)"
  printf '%s\n' "$brand_out" | sed 's/^/        /'
fi

# ── T9: "IDD Stack" fills every product-name slot ──
slots_out="$(python3 -c '
import json, re, sys

landing, docs, changelog, llms, plugin_json, plugin_readme = sys.argv[1:7]
read = lambda p: open(p, encoding="utf-8").read()
bad = []

def title(path):
    m = re.search(r"<title>(.*?)</title>", read(path), re.S)
    return m.group(1) if m else ""

for path in (landing, docs, changelog):
    if "IDD Stack" not in title(path):
        bad.append("%s: <title> does not name IDD Stack" % path)

html = read(landing)
m = re.search(r"<meta property=\"og:site_name\" content=\"([^\"]*)\"", html)
if not m or m.group(1) != "IDD Stack":
    bad.append("landing.html: og:site_name is not IDD Stack")

for block in re.findall(r"<script type=\"application/ld\+json\">(.*?)</script>", html, re.S):
    data = json.loads(block)
    for node in data.get("@graph", [data]):
        if node.get("@type") in ("WebSite", "SoftwareApplication") and node.get("name") != "IDD Stack":
            bad.append("landing.html: JSON-LD %s name is %r" % (node["@type"], node.get("name")))

if read(llms).splitlines()[0].strip() != "# IDD Stack":
    bad.append("llms.txt: first line is not \"# IDD Stack\"")

if not json.loads(read(plugin_json)).get("displayName", "").startswith("IDD Stack"):
    bad.append("src/plugin/plugin.json: displayName does not start with IDD Stack")

if not read(plugin_readme).startswith("# IDD Stack"):
    bad.append("src/plugin/README.md: H1 does not start with IDD Stack")

for line in bad:
    print(line)
sys.exit(1 if bad else 0)
' "$LANDING" "$DOCS" "$CHANGELOG_PAGE" "$LLMS" "$PLUGIN_JSON" "$PLUGIN_README")" && slots_status=0 || slots_status=$?
if [ "$slots_status" -eq 0 ]; then
  pass "T9: IDD Stack fills every product-name slot (titles, og:site_name, JSON-LD, llms.txt, plugin)"
else
  fail "T9: a product-name slot does not say IDD Stack"
  printf '%s\n' "$slots_out" | sed 's/^/        /'
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
