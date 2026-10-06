#!/usr/bin/env bash
# test-landing-structure.sh — Validate landing.html structure for the batched
# landing-page fixes (issues #147, #148, #149, #150) plus the PAS rewrite
# guardrails:
#
# Asserts:
#   #147 — hero terminal is compact; redundant second eyebrow pill removed
#   #148 — .feat-grid is explicitly closed before .model-highlight so the
#          idd-lint panel is full-width (balanced <div> count)
#   #149 — screenshots render as a single slideshow (track + 5 slides + nav/dots)
#   #150 — install section shows only the full-pack commands; the multi-tab
#          UI and partial/source/first-run commands are gone
#   T10 — the page says "Eight commands" and never "nine commands"/"9 commands"
#   T11 — the install block defines asm via `npm install -g agent-skill-manager`
#   T12 — /idd-doctor is not mentioned (maintainer-only, not shipped by either
#          install path)
#   T13 — both JSON-LD blocks parse, and the FAQPage JSON-LD mirrors the
#          visible .faq items pairwise (question + answer text)
#   T14 — hero terminal carries id="hero-term", a labelled pause control, the
#          static transcript, and a reduced-motion check in the final script
#   T15 — the hero section carries the autonomous band (/plan-to-issues,
#          /auto-pilot, --resume)
#   T16 — the idd-lint panel has a copyable curl -O command
#   T17 — the site is agent-neutral: no fixed agent list, "any coding agent"
#   T18 — section#methodology explains both Issue- and Intention-Driven
#
# This is a static HTML page — there is no JS test runner — so this test does
# structural string + tag-balance checks only.
#
# Usage: bash tests/test-landing-structure.sh
# Returns: exit 0 on pass, exit 1 on failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING="$REPO_ROOT/landing.html"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Landing Structure Tests (issues #147 #148 #149 #150)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# T0: file exists
if [ -f "$LANDING" ]; then
  pass "T0: landing.html exists"
else
  fail "T0: landing.html missing"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

# ── Tag balance (overall integrity; #148 root cause was an unclosed grid) ──
opens=$(grep -o '<div\b' "$LANDING" | wc -l | tr -d ' ')
closes=$(grep -o '</div>' "$LANDING" | wc -l | tr -d ' ')
if [ "$opens" = "$closes" ]; then
  pass "T1: <div> tags balanced ($opens open / $closes close)"
else
  fail "T1: <div> imbalance — $opens open vs $closes close"
fi

# ── #147: hero terminal compact + single eyebrow ──
if grep -q 'class="terminal compact reveal"' "$LANDING"; then
  pass "T2 (#147): hero terminal uses compact sizing"
else
  fail "T2 (#147): hero terminal not marked compact"
fi
eyebrows=$(grep -c 'class="eyebrow' "$LANDING" || true)
if [ "$eyebrows" -le 1 ]; then
  pass "T3 (#147): redundant hero eyebrow pill removed ($eyebrows remaining)"
else
  fail "T3 (#147): expected <=1 hero eyebrow, found $eyebrows"
fi

# ── #148: model-highlight sits OUTSIDE feat-grid ──
# .feat-grid must fully close before .model-highlight opens. Track <div> depth
# from the feat-grid opener; if depth has returned to 0 by the time we reach
# .model-highlight, it is a sibling (correct), not nested. Uses awk rather than
# `grep -P` so the test is portable to BSD grep (macOS), matching the repo's
# portability standard.
mh_nesting=$(awk '
  /<div class="model-highlight/ { print (depth<=0 ? "SIBLING" : "NESTED"); found=1; exit }
  /<div class="feat-grid"/ { infg=1 }
  infg {
    n=gsub(/<div/,"&"); depth+=n
    m=gsub(/<\/div>/,"&"); depth-=m
  }
  END { if(!found) print "NOTFOUND" }
' "$LANDING")
if [ "$mh_nesting" = "SIBLING" ]; then
  pass "T4 (#148): .model-highlight is a sibling of .feat-grid (panel full-width)"
else
  fail "T4 (#148): .model-highlight still nested inside .feat-grid ($mh_nesting)"
fi

# ── #149: slideshow markup present ──
if grep -q 'id="shots-track"' "$LANDING" \
   && grep -q 'id="shots-prev"' "$LANDING" \
   && grep -q 'id="shots-next"' "$LANDING" \
   && grep -q 'id="shots-dots"' "$LANDING"; then
  pass "T5 (#149): slideshow track + prev/next + dots present"
else
  fail "T5 (#149): slideshow controls missing"
fi
slides=$(grep -c 'aria-roledescription="slide"' "$LANDING" || true)
if [ "$slides" = "5" ]; then
  pass "T6 (#149): all 5 screenshots preserved as slides"
else
  fail "T6 (#149): expected 5 slides, found $slides"
fi
if ! grep -q 'class="shot wide' "$LANDING"; then
  pass "T7 (#149): old static grid layout removed (no .shot.wide)"
else
  fail "T7 (#149): leftover static grid markup (.shot.wide)"
fi

# ── #150: single full-pack install command only ──
if grep -q 'asm install https://github.com/luongnv89/idd' "$LANDING"; then
  pass "T8 (#150): full-pack install command present"
else
  fail "T8 (#150): full-pack install command missing"
fi
if ! grep -q 'install-tabs' "$LANDING" \
   && ! grep -q 'install-pane' "$LANDING" \
   && ! grep -q '#main:skills/issue-resolver' "$LANDING" \
   && ! grep -q './scripts/install.sh' "$LANDING"; then
  pass "T9 (#150): tabs + partial/source/first-run install commands removed"
else
  fail "T9 (#150): leftover partial install commands or tab UI"
fi

# ── PAS rewrite: the pack is eight commands, never nine ──
if ! grep -qiE 'nine (terminal )?(commands|skills)' "$LANDING" \
   && ! grep -qiE '(^|[^0-9])9 (commands|skills)' "$LANDING" \
   && grep -q 'Eight commands' "$LANDING"; then
  pass "T10: \"Eight commands\" stated, no nine-command phrasing remains"
else
  fail "T10: stale nine-command phrasing, or \"Eight commands\" missing"
fi

# ── PAS rewrite: asm is defined where it is used ──
if grep -q 'npm install -g agent-skill-manager' "$LANDING"; then
  pass "T11: install block defines asm (npm install -g agent-skill-manager)"
else
  fail "T11: install block never explains where the asm command comes from"
fi

# ── PAS rewrite: /idd-doctor is maintainer tooling, not shipped ──
if ! grep -q 'idd-doctor' "$LANDING"; then
  pass "T12: /idd-doctor not mentioned on the landing page"
else
  fail "T12: /idd-doctor still appears (it is not shipped by either install path)"
fi

# ── PAS rewrite: the FAQPage JSON-LD mirrors the visible FAQ ──
if python3 - "$LANDING" <<'PY'
import io, json, re, sys
from html import unescape

src = io.open(sys.argv[1], encoding='utf-8').read()

blocks = re.findall(r'<script type="application/ld\+json">(.*?)</script>', src, re.S)
if len(blocks) != 2:
    print('  expected 2 JSON-LD blocks, found %d' % len(blocks), file=sys.stderr)
    sys.exit(1)
try:
    docs = [json.loads(b) for b in blocks]
except ValueError as e:
    print('  JSON-LD does not parse: %s' % e, file=sys.stderr)
    sys.exit(1)
faq = next((d for d in docs if d.get('@type') == 'FAQPage'), None)
if not faq or not isinstance(faq.get('mainEntity'), list):
    print('  no FAQPage JSON-LD with a mainEntity list', file=sys.stderr)
    sys.exit(1)


def norm(html):
    html = re.sub(r'<span class="q-ico">.*?</span>', '', html, flags=re.S)
    return ' '.join(unescape(re.sub(r'<[^>]+>', '', html)).split())


items = re.findall(r'<details>\s*<summary>(.*?)</summary>\s*<div class="a">(.*?)</div>', src, re.S)
visible = [(norm(q), norm(a)) for q, a in items]
ld = faq['mainEntity']
problems = []
if len(visible) != len(ld):
    problems.append('visible FAQ has %d items, JSON-LD has %d' % (len(visible), len(ld)))
if not (5 <= len(visible) <= 7):
    problems.append('visible FAQ count %d outside 5..7' % len(visible))
for i, ((vq, va), q) in enumerate(zip(visible, ld)):
    if q.get('name') != vq:
        problems.append('Q%d differs: page %r vs JSON-LD %r' % (i + 1, vq, q.get('name')))
    if q.get('acceptedAnswer', {}).get('text') != va:
        problems.append('A%d differs: page %r vs JSON-LD %r' % (i + 1, va, q.get('acceptedAnswer', {}).get('text')))
if problems:
    for p in problems:
        print('  ' + p, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
then
  pass "T13: both JSON-LD blocks parse; FAQPage mirrors the visible FAQ"
else
  fail "T13: JSON-LD malformed or FAQPage does not mirror the visible FAQ"
fi

# ── v2: the hero terminal is an animated, pausable loop ──
if python3 - "$LANDING" <<'PY'
import io, re, sys

src = io.open(sys.argv[1], encoding='utf-8').read()
problems = []

m = re.search(r'<div class="terminal compact reveal" id="hero-term">', src)
if not m:
    problems.append('id="hero-term" is not on the "terminal compact reveal" element')

pm = re.search(r'<button[^>]*id="hero-term-pause"[^>]*>', src)
if not pm or 'aria-label=' not in pm.group(0):
    problems.append('#hero-term-pause button missing or has no aria-label')

if m:
    seg = src[m.start():src.find('</section>', m.start())]
    for needle in ('/issue-creator', '/issue-triage', '/issue-resolver 42',
                   '/issue-pr-review 87 --auto', 'issue #42 closed'):
        if needle not in seg:
            problems.append('static transcript missing %r' % needle)

final = src[src.rfind('<script>'):]
if 'prefers-reduced-motion' not in final:
    problems.append('final script never checks prefers-reduced-motion')

for p in problems:
    print('  ' + p, file=sys.stderr)
sys.exit(1 if problems else 0)
PY
then
  pass "T14: hero terminal has id, pause control, static transcript, reduced-motion guard"
else
  fail "T14: hero terminal animation requirements unmet"
fi

if ! command -v node >/dev/null 2>&1; then
  fail "T14 behavior: node is required to exercise the hero loop"
elif node - "$LANDING" <<'JS'
const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const src = fs.readFileSync(process.argv[2], 'utf8');
const hero = src.match(/\(function \(\) \{\s*var term = document\.getElementById\('hero-term'\);[\s\S]*?\}\(\)\);/);
assert(hero, 'hero animation script missing');

class Element {
  constructor() {
    this.children = [];
    this.parentNode = null;
    this.style = {};
    this.attrs = {};
    this.listeners = {};
    this.classes = new Set();
    this.classList = {
      add: c => this.classes.add(c),
      remove: c => this.classes.delete(c),
      toggle: (c, on) => on ? this.classes.add(c) : this.classes.delete(c)
    };
    this.clears = 0;
    this.text = '';
    this.clientWidth = 600;
    this.offsetHeight = 600;
  }
  appendChild(el) { el.parentNode = this; this.children.push(el); }
  removeChild(el) {
    this.children.splice(this.children.indexOf(el), 1);
    el.parentNode = null;
  }
  set textContent(text) {
    this.children.forEach(el => { el.parentNode = null; });
    this.children = [];
    this.text = text;
    if (text === '') { this.clears++; }
  }
  get textContent() { return this.text + this.children.map(el => el.textContent).join(''); }
  setAttribute(k, v) { this.attrs[k] = v; }
  getAttribute(k) { return this.attrs[k]; }
  addEventListener(k, fn) { this.listeners[k] = fn; }
}

const body = new Element();
const term = new Element();
const button = new Element();
term.appendChild(body);
term.querySelector = () => body;
term.querySelectorAll = () => [];
const document = {
  hidden: false,
  listeners: {},
  getElementById: id => id === 'hero-term' ? term : button,
  createElement: () => new Element(),
  addEventListener(k, fn) { this.listeners[k] = fn; }
};
let now = 0;
let nextId = 0;
const timers = new Map();
let intersection;
const sandbox = {
  document,
  IntersectionObserver: function (callback) { intersection = callback; this.observe = () => {}; },
  matchMedia: () => ({ matches: false }),
  getComputedStyle: () => ({ lineHeight: '20px', paddingTop: '0px', paddingBottom: '0px' }),
  setTimeout(fn, delay) { const id = ++nextId; timers.set(id, { fn, at: now + delay }); return id; },
  clearTimeout(id) { timers.delete(id); }
};
vm.runInNewContext(hero[0], sandbox);

function advance(ms) {
  const end = now + ms;
  for (let n = 0; n < 10000; n++) {
    const next = [...timers].sort((a, b) => a[1].at - b[1].at)[0];
    if (!next || next[1].at > end) { now = end; return; }
    now = next[1].at;
    timers.delete(next[0]);
    next[1].fn();
  }
  assert.fail('hero timers did not settle');
}
function until(check, label) {
  for (let n = 0; n < 1000 && !check(); n++) { advance(100); }
  assert(check(), label);
}
function visible() {
  assert(body.children.some(el => el.className === 'ln' && el.parentNode === body && el.textContent.trim()),
    'hero has no attached non-empty line');
  assert(!body.classes.has('fading'), 'hero text is still fading out');
}

for (let loop = 1; loop <= 3; loop++) {
  until(() => body.textContent.includes('/issue-creator'), `loop ${loop} never renders its command`);
  visible();
  intersection([{ isIntersecting: false }]);
  const offscreenText = body.textContent;
  document.hidden = true;
  document.listeners.visibilitychange();
  document.hidden = false;
  document.listeners.visibilitychange();
  advance(10000);
  assert.equal(body.textContent, offscreenText, 'visible tab resumed an offscreen hero');
  assert.equal(timers.size, 0, 'offscreen hero kept a pending timer');
  document.hidden = true;
  document.listeners.visibilitychange();
  intersection([{ isIntersecting: true }]);
  assert.equal(timers.size, 0, 'intersection resumed a hidden-tab hero');
  document.hidden = false;
  document.listeners.visibilitychange();
  assert.equal(timers.size, 1, 'visible intersecting hero did not resume');
  button.listeners.click();
  assert.equal(button.attrs['aria-label'], 'Play animation');
  const pausedText = body.textContent;
  intersection([{ isIntersecting: false }]);
  document.hidden = true;
  document.listeners.visibilitychange();
  intersection([{ isIntersecting: true }]);
  document.hidden = false;
  document.listeners.visibilitychange();
  advance(10000);
  assert.equal(body.textContent, pausedText, 'paused hero text changed');
  assert.equal(timers.size, 0, 'paused hero kept a pending timer');
  button.listeners.click();
  assert.equal(button.attrs['aria-label'], 'Pause animation');
  until(() => body.textContent.includes('issue #42 closed'), `loop ${loop} never completes after resume`);
  visible();
  if (loop < 3) {
    const clears = body.clears;
    until(() => body.clears > clears, `loop ${loop} never restarts`);
  }
}
JS
then
  pass "T14 behavior: three attached hero loops, user pause, combined visibility/intersection gating"
else
  fail "T14 behavior: hero loop or pause/resume regression (see above)"
fi

# ── v2: the autonomous band lives inside the hero section ──
hero_seg=$(sed -n '/<section class="hero"/,/id="problem"/p' "$LANDING")
if printf '%s' "$hero_seg" | grep -q '/plan-to-issues' \
   && printf '%s' "$hero_seg" | grep -q '/auto-pilot' \
   && printf '%s' "$hero_seg" | grep -q -- '--resume'; then
  pass "T15: autonomous band in hero (/plan-to-issues → /auto-pilot, --resume)"
else
  fail "T15: hero section lacks the autonomous band content"
fi

# ── v2: the idd-lint get-block is copyable ──
if grep -q 'data-copy="curl -O https://raw.githubusercontent.com/luongnv89/idd/main/scripts/idd-lint.py' "$LANDING"; then
  pass "T16: idd-lint curl command is on a .copy-btn"
else
  fail "T16: no copy button carries the idd-lint curl -O command"
fi

# ── v2: agent-neutral messaging ──
if ! grep -q 'Claude Code · Codex CLI · Gemini CLI' "$LANDING" \
   && grep -q 'Works with any coding agent' "$LANDING"; then
  pass "T17: agent-neutral copy (no fixed agent list; \"any coding agent\" stated)"
else
  fail "T17: fixed agent list remains or \"Works with any coding agent\" missing"
fi

# ── v2: the What-is-IDD rewrite names both readings ──
meth_seg=$(sed -n '/<section id="methodology">/,/<\/section>/p' "$LANDING")
if printf '%s' "$meth_seg" | grep -q 'Issue-Driven Development' \
   && printf '%s' "$meth_seg" | grep -q 'Intention-Driven Development'; then
  pass "T18: methodology explains Issue- and Intention-Driven Development"
else
  fail "T18: methodology section lacks the dual Issue/Intention framing"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
