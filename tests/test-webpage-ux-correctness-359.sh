#!/usr/bin/env bash
# test-webpage-ux-correctness-359.sh — Web page UX correctness (issue #359).
#
# Closes F-UX-001 / F-UX-003 / F-UX-008 / F-UX-011 from the modernization
# report:
#   F-UX-001. Scroll-reveal hiding is gated on a `.js` class that only script
#       can set, so with JavaScript disabled every .reveal block — including
#       the hero and the install command box — stays visible.
#   F-UX-003. changelog.html degrades without script: the shimmer skeletons
#       are hidden and a <noscript> block points at CHANGELOG.md instead of
#       shimmering forever.
#   F-UX-008. The "Commits" stat is read from the GitHub Commits API, never
#       derived from unrelated numbers; when it cannot be established the
#       stat keeps its "—" placeholder rather than showing a guess.
#   F-UX-011. The copy button surfaces a visible error state on every
#       clipboard failure path (rejection, thrown call, missing API,
#       non-thenable writeText return).
#
# Also guards the invariant that none of this loosened the Content-Security-
# Policy metas added by issue #338.
#
# Sections:
#   Static   — string/structure assertions (always run).
#   CSS      — python3 scan of landing.html's <style>: no rule may hide
#              .reveal without a genuine `.js` class requirement (not a
#              substring match; `:not(.js)` does not count).
#   Behavior — node DOM-shim driving landing.html's real inline script through
#              five clipboard scenarios (ok / reject / throws / missing /
#              non-thenable). Requires node; without it the section fails
#              loudly rather than passing silently.
#   Mutation — each new/changed assertion is broken in a temp copy, confirmed
#              red, then discarded. The working tree is never mutated.
#
# Usage: bash tests/test-webpage-ux-correctness-359.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING="$REPO_ROOT/landing.html"
DOCS="$REPO_ROOT/docs.html"
CHANGELOG="$REPO_ROOT/changelog.html"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# C1: a hide rule on .reveal is allowed only when that selector actually
# requires the `js` class. `:not(.js)` and identifiers that merely contain
# the characters `.js` (`.json`) do not qualify.
scan_reveal_gating() {
  python3 - "$1" <<'PY'
import io, re, sys

html = io.open(sys.argv[1], encoding='utf-8').read()
styles = re.findall(r'<style>(.*?)</style>', html, re.S)
if not styles:
    print('  no <style> block found', file=sys.stderr)
    sys.exit(1)

css = '\n'.join(styles)
css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
css = re.sub(r'@media[^{]*\{', '', css)


def requires_js_class(selector):
    """True iff the selector requires the `js` class, not a `.js` substring."""
    stripped = re.sub(r':not\([^)]*\)', '', selector)
    return re.search(r'\.js(?![A-Za-z0-9_-])', stripped) is not None


bad = []
for selector, body in re.findall(r'([^{}]+)\{([^{}]*)\}', css):
    selector = ' '.join(selector.split())
    hides = (re.search(r'opacity:\s*0(\D|$)', body)
             or re.search(r'visibility:\s*hidden', body)
             or re.search(r'display:\s*none', body))
    if not hides:
        continue
    for part in selector.split(','):
        part = ' '.join(part.split())
        if '.reveal' not in part:
            continue
        if not requires_js_class(part):
            bad.append(part)

if bad:
    for s in bad:
        print('  ungated hiding rule: ' + s, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

# T8: the only JS write to the commits stat is Intl.NumberFormat(...).format(total).
scan_commits_writes() {
  python3 - "$1" <<'PY'
import io, re, sys

html = io.open(sys.argv[1], encoding='utf-8').read()
scripts = re.findall(r'<script>(.*?)</script>', html, re.S)
code = '\n'.join(scripts)
code = re.sub(r'/\*.*?\*/', '', code, flags=re.S)
code = re.sub(r'//[^\n]*', '', code)

target = (
    r'(?:commitsEl|document\.getElementById\(\s*[\'"]cl-commits[\'"]\s*\))'
    r'\s*\.\s*(textContent|innerHTML|innerText)\s*=\s*([^;]+)'
)
writes = re.findall(target, code)
if len(writes) != 1:
    print('  expected exactly 1 write to commitsEl value, found %d' % len(writes),
          file=sys.stderr)
    for _, rhs in writes:
        print('    rhs: ' + ' '.join(rhs.split()), file=sys.stderr)
    sys.exit(1)
prop, rhs = writes[0]
rhs = ' '.join(rhs.split())
if prop != 'textContent':
    print('  commitsEl written via ' + prop + ', not textContent', file=sys.stderr)
    sys.exit(1)
if not re.search(r'Intl\.NumberFormat\([^)]*\)\.format\(\s*total\s*\)', rhs):
    print('  commitsEl write is not API-derived format(total): ' + rhs, file=sys.stderr)
    sys.exit(1)
if re.search(r'releases|forks|~|\*', rhs):
    print('  commitsEl write looks fabricated: ' + rhs, file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

scan_commits_placeholder() {
  python3 - "$1" <<'PY'
import io, re, sys

html = io.open(sys.argv[1], encoding='utf-8').read()
m = re.search(r'<[^>]*\bid=["\']cl-commits["\'][^>]*>([^<]*)</', html)
if not m:
    print('  no #cl-commits element in markup', file=sys.stderr)
    sys.exit(1)
placeholder = m.group(1).strip()
if placeholder != '\u2014':
    print('  #cl-commits placeholder is %r, expected em-dash' % placeholder,
          file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
}

# Apply a unique-needle replacement into dst. Exit 2 if the needle is not unique.
apply_mut() {
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import sys
from pathlib import Path

src, dst, old, new = sys.argv[1:5]
text = Path(src).read_text(encoding='utf-8')
count = text.count(old)
if count != 1:
    sys.stderr.write('mutation needle count %d != 1\n' % count)
    sys.exit(2)
Path(dst).write_text(text.replace(old, new, 1), encoding='utf-8')
PY
}

echo "◆ Web page UX correctness (#359)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  if [ ! -f "$page" ]; then
    fail "T0: $(basename "$page") missing"
    echo "Result: $PASS passed, $FAIL failed"
    exit 1
  fi
done
pass "T0: landing.html, docs.html, changelog.html all present"

# ── F-UX-001: reveal gating ────────────────────────────────────────────────
if grep -q "documentElement.classList.add('js')" "$LANDING"; then
  pass "T1 (F-UX-001): landing.html adds the .js gate class from script"
else
  fail "T1 (F-UX-001): no script adds the .js class to documentElement"
fi

# The gate must be set before the body paints, i.e. inside <head>.
gate_line="$(grep -n "documentElement.classList.add('js')" "$LANDING" | head -1 | cut -d: -f1 || true)"
head_end="$(grep -n '</head>' "$LANDING" | head -1 | cut -d: -f1 || true)"
if [ -n "$gate_line" ] && [ -n "$head_end" ] && [ "$gate_line" -lt "$head_end" ]; then
  pass "T2 (F-UX-001): the gate script runs in <head>, before the body paints"
else
  fail "T2 (F-UX-001): gate script is not inside <head> (line $gate_line vs </head> $head_end)"
fi

if grep -q '\.js \.reveal' "$LANDING"; then
  pass "T3 (F-UX-001): reveal rules are scoped under .js"
else
  fail "T3 (F-UX-001): no .js-scoped .reveal rule found"
fi

# Reveal markup itself is untouched — the fix is in the gate, not the markup.
reveals="$(grep -c 'class="[^"]*reveal' "$LANDING" || true)"
if [ "$reveals" -ge 20 ]; then
  pass "T4 (F-UX-001): $reveals .reveal blocks still present (markup untouched)"
else
  fail "T4 (F-UX-001): expected the .reveal markup to survive, found $reveals"
fi

# ── F-UX-003: noscript fallback ────────────────────────────────────────────
if grep -q '<noscript>' "$CHANGELOG"; then
  pass "T5 (F-UX-003): changelog.html has a <noscript> block"
else
  fail "T5 (F-UX-003): changelog.html has no <noscript>"
fi

if grep -q 'blob/main/CHANGELOG.md' "$CHANGELOG"; then
  pass "T6 (F-UX-003): the fallback links CHANGELOG.md"
else
  fail "T6 (F-UX-003): no CHANGELOG.md link in changelog.html"
fi

# The infinite skeletons must actually be suppressed when script is off. The
# <noscript> rules carry the same specificity as the page's own rules, so it is
# not enough for them to exist: they must be the LAST word on `display` for
# each selector they override. This asserts the effect, not the presence.
if python3 - "$CHANGELOG" <<'NOSCRIPT_EOF'
import io, re, sys

html = io.open(sys.argv[1], encoding='utf-8').read()
# Blank HTML comments (offset-preserving) so a tag named in prose is never
# mistaken for real markup.
html = re.sub(r'<!--.*?-->', lambda c: ' ' * len(c.group(0)), html, flags=re.S)

noscript_spans = [m.span() for m in re.finditer(r'<noscript>.*?</noscript>', html, re.S)]
if not noscript_spans:
    print('  no <noscript> block at all', file=sys.stderr)
    sys.exit(1)


def in_noscript(pos):
    return any(a <= pos < b for a, b in noscript_spans)


if not any('CHANGELOG.md' in html[a:b] for a, b in noscript_spans):
    print('  no <noscript> block links CHANGELOG.md', file=sys.stderr)
    sys.exit(1)

# Every rule inside every <style> element, with its document offset. Comments
# and @media wrappers are blanked (not removed) so offsets stay accurate.
rules = []
for m in re.finditer(r'<style>(.*?)</style>', html, re.S):
    base = m.start(1)
    body = re.sub(r'/\*.*?\*/', lambda c: ' ' * len(c.group(0)), m.group(1), flags=re.S)
    body = re.sub(r'@media[^{]*\{', lambda c: ' ' * len(c.group(0)), body)
    for r in re.finditer(r'([^{}]+)\{([^{}]*)\}', body):
        rules.append((base + r.start(), ' '.join(r.group(1).split()), r.group(2)))

ok = True
for selector, want, from_noscript in (
        ('.tl-skeleton', 'none', True),
        ('.changelog-stats', 'none', True),
        ('.cl-noscript', 'block', True)):
    winners = [(pos, decl) for pos, sel, decl in rules
               if sel == selector and re.search(r'display:\s*[a-z-]+', decl)]
    if not winners:
        print('  no display rule for ' + selector, file=sys.stderr)
        ok = False
        continue
    pos, decl = winners[-1]
    value = re.search(r'display:\s*([a-z-]+)', decl).group(1)
    if value != want:
        print('  last display for ' + selector + ' is "' + value +
              '", expected "' + want + '"', file=sys.stderr)
        ok = False
    elif from_noscript and not in_noscript(pos):
        print('  last display for ' + selector + ' is outside <noscript>', file=sys.stderr)
        ok = False

sys.exit(0 if ok else 1)
NOSCRIPT_EOF
then
  pass "T7 (F-UX-003): <noscript> rules win — skeletons/stats hidden, fallback shown"
else
  fail "T7 (F-UX-003): the <noscript> overrides do not take effect (order/specificity)"
fi

# ── F-UX-008: honest stats ─────────────────────────────────────────────────
# The invariant is the value, not two known-bad literals: commitsEl is written
# once, from Intl.NumberFormat(...).format(total), or it stays the "—" markup
# placeholder. A novel formula such as `releases.length * 12` must fail here.
if scan_commits_writes "$CHANGELOG"; then
  pass "T8 (F-UX-008): the only commitsEl write is API-derived format(total)"
else
  fail "T8 (F-UX-008): commitsEl is written from something other than the API total"
fi

if scan_commits_placeholder "$CHANGELOG"; then
  pass "T9 (F-UX-008): #cl-commits markup is the em-dash placeholder"
else
  fail "T9 (F-UX-008): #cl-commits markup is not the em-dash placeholder"
fi

if grep -q "/commits?per_page=1" "$CHANGELOG" && grep -q 'rel="last"' "$CHANGELOG"; then
  pass "T10 (F-UX-008): commit count comes from the Commits API pagination header"
else
  fail "T10 (F-UX-008): commit count is not sourced from the Commits API"
fi

# ── F-UX-011: copy failure path ────────────────────────────────────────────
if grep -q 'copy-error' "$LANDING"; then
  pass "T11 (F-UX-011): a copy-error state exists in markup/CSS/JS"
else
  fail "T11 (F-UX-011): no copy-error state in landing.html"
fi

if grep -qE '\.catch\(failed\)' "$LANDING" && grep -q 'navigator.clipboard.writeText' "$LANDING"; then
  pass "T12 (F-UX-011): the clipboard promise has a rejection handler"
else
  fail "T12 (F-UX-011): the clipboard promise has no rejection handler"
fi

# ── CSP not loosened by any of the above ───────────────────────────────────
csp_ok=1
for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  csp="$(grep -o 'content="default-src[^"]*"' "$page" || true)"
  case "$csp" in
    *"default-src 'self'"*) ;;
    *) csp_ok=0 ;;
  esac
  case "$csp" in
    *unsafe-eval*|*'src *'*|*'http:'*) csp_ok=0 ;;
  esac
done
if [ "$csp_ok" -eq 1 ]; then
  pass "T13: CSP still default-src 'self', no unsafe-eval / wildcard / http: source"
else
  fail "T13: a page's CSP was loosened"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "CSS rule scan (no ungated rule may hide .reveal)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if scan_reveal_gating "$LANDING"; then
  pass "C1 (F-UX-001): every rule that hides .reveal requires the js class"
else
  fail "C1 (F-UX-001): a .reveal rule hides content without requiring the js class"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Behavioral (Node DOM-shim, clipboard scenarios)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if ! command -v node >/dev/null 2>&1; then
  fail "B0: node is required for the behavioral section but was not found"
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

cat > "$TMP/copy-harness.cjs" <<'HARNESS_EOF'
'use strict';
// Drives landing.html's real inline script through one clipboard scenario and
// asserts the button's visible state. Nothing is copied from the page into
// this file — the script under test is read from landing.html itself.
const fs = require('node:fs');
const vm = require('node:vm');

const htmlPath = process.argv[2];
const scenario = process.argv[3];
const html = fs.readFileSync(htmlPath, 'utf8');

const end = html.lastIndexOf('</script>');
const openTag = html.lastIndexOf('<script>', end);
if (openTag < 0 || end <= openTag) {
  console.error('harness: could not locate the landing inline script');
  process.exit(2);
}
const code = html.slice(openTag + '<script>'.length, end);

function makeClassList() {
  const set = new Set();
  return {
    add(c) { set.add(c); },
    remove(c) { set.delete(c); },
    contains(c) { return set.has(c); },
    toggle(c, force) {
      if (force === true) { set.add(c); return true; }
      if (force === false) { set.delete(c); return false; }
      if (set.has(c)) { set.delete(c); return false; }
      set.add(c); return true;
    }
  };
}

const button = {
  tagName: 'BUTTON',
  textContent: 'copy',
  dataset: { copy: 'asm install https://github.com/luongnv89/idd' },
  classList: makeClassList(),
  _listeners: {},
  addEventListener(type, fn) { this._listeners[type] = fn; },
  click() { if (this._listeners.click) { this._listeners.click(); } }
};

let clipboard;
if (scenario === 'reject') {
  clipboard = { writeText() { return Promise.reject(new Error('NotAllowedError')); } };
} else if (scenario === 'throws') {
  clipboard = { writeText() { throw new TypeError('blocked'); } };
} else if (scenario === 'missing') {
  clipboard = undefined;
} else if (scenario === 'ok') {
  clipboard = { writeText() { return Promise.resolve(); } };
} else if (scenario === 'nonthenable') {
  clipboard = { writeText() { return 1; } };
} else {
  console.error('harness: unknown scenario ' + scenario);
  process.exit(2);
}

const shim = {
  console: console,
  setTimeout: setTimeout,
  clearTimeout: clearTimeout,
  Intl: Intl,
  navigator: { clipboard: clipboard },
  // Never settles: the release/stars fetches must not interfere.
  fetch: function () { return new Promise(function () {}); },
  IntersectionObserver: function () {
    this.observe = function () {};
    this.unobserve = function () {};
  },
  document: {
    // The slideshow bails out when its track is absent.
    getElementById: function () { return null; },
    querySelectorAll: function (sel) { return sel === '.copy-btn' ? [button] : []; },
    createElement: function () { return { classList: makeClassList(), appendChild: function () {} }; },
    documentElement: { classList: makeClassList() }
  }
};

vm.createContext(shim);
vm.runInContext(code, shim, { filename: 'landing-inline.js' });

const die = function (msg) { console.error('harness: ' + scenario + ': ' + msg); process.exit(1); };

if (!button._listeners.click) { die('no click listener bound to the copy button'); }
button.click();

// Give a rejected/resolved clipboard promise a turn to settle.
new Promise(function (r) { setTimeout(r, 20); }).then(function () {
  const text = button.textContent;
  if (scenario === 'ok') {
    if (!button.classList.contains('copy-ok')) { die('success did not set copy-ok'); }
    if (button.classList.contains('copy-error')) { die('success wrongly set copy-error'); }
    if (text === 'copy') { die('success gave no visible feedback'); }
    process.stdout.write('success feedback: "' + text + '"\n');
  } else {
    if (!button.classList.contains('copy-error')) { die('failure did not set copy-error'); }
    if (button.classList.contains('copy-ok')) { die('failure wrongly set copy-ok'); }
    if (text === 'copy') { die('failure was silent — label unchanged'); }
    if (text.indexOf('copied') !== -1) { die('failure claimed success: "' + text + '"'); }
    process.stdout.write('error surfaced: "' + text + '"\n');
  }
  process.exit(0);
}).catch(function (e) {
  console.error('harness: ' + ((e && e.stack) || e));
  process.exit(1);
});
HARNESS_EOF

for scenario_name in ok reject throws missing nonthenable; do
  case "$scenario_name" in
    ok)           label="clipboard resolves → success state, no error state" ;;
    reject)       label="clipboard rejects (permission denied) → visible error state" ;;
    throws)       label="writeText throws synchronously → visible error state" ;;
    missing)      label="no Clipboard API at all → visible error state" ;;
    nonthenable)  label="writeText returns a non-thenable → visible error state" ;;
  esac
  if node "$TMP/copy-harness.cjs" "$LANDING" "$scenario_name" >"$TMP/out-$scenario_name.txt" 2>&1; then
    pass "B (F-UX-011): $label"
  else
    fail "B (F-UX-011): $label"
    sed 's/^/      /' "$TMP/out-$scenario_name.txt"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Mutation proofs (temp copies; working tree untouched)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# M-C1a: the F-UX-001 shape that the old substring check accepted.
if python3 - "$LANDING" "$TMP/mut-c1-notjs.html" <<'PY'
from pathlib import Path
import sys
src, dst = sys.argv[1], sys.argv[2]
text = Path(src).read_text(encoding='utf-8')
needle = '</style>'
if text.count(needle) != 1:
    sys.stderr.write('</style> count %d != 1\n' % text.count(needle))
    sys.exit(2)
Path(dst).write_text(
    text.replace(needle, 'html:not(.js) .reveal{opacity:0}\n  </style>', 1),
    encoding='utf-8')
PY
then
  if scan_reveal_gating "$TMP/mut-c1-notjs.html" 2>/dev/null; then
    fail "M-C1a: html:not(.js) .reveal{opacity:0} stayed green — C1 has no teeth"
  else
    pass "M-C1a: html:not(.js) .reveal{opacity:0} turns C1 red"
  fi
else
  fail "M-C1a: could not inject html:not(.js) mutant (</style> not unique)"
fi

# M-C1b: a class whose name merely contains the characters `.js`.
if python3 - "$LANDING" "$TMP/mut-c1-json.html" <<'PY'
from pathlib import Path
import sys
src, dst = sys.argv[1], sys.argv[2]
text = Path(src).read_text(encoding='utf-8')
needle = '</style>'
if text.count(needle) != 1:
    sys.stderr.write('</style> count %d != 1\n' % text.count(needle))
    sys.exit(2)
Path(dst).write_text(
    text.replace(needle, '.json .reveal{opacity:0}\n  </style>', 1),
    encoding='utf-8')
PY
then
  if scan_reveal_gating "$TMP/mut-c1-json.html" 2>/dev/null; then
    fail "M-C1b: .json .reveal{opacity:0} stayed green — C1 is still a substring test"
  else
    pass "M-C1b: .json .reveal{opacity:0} turns C1 red"
  fi
else
  fail "M-C1b: could not inject .json mutant (</style> not unique)"
fi

# M-T8: a novel fabricated formula the old literal greps would miss.
T8_OLD="commitsEl.textContent = new Intl.NumberFormat('en').format(total);"
T8_NEW="commitsEl.textContent = releases.length * 12;"
if apply_mut "$CHANGELOG" "$TMP/mut-t8.html" "$T8_OLD" "$T8_NEW"; then
  if scan_commits_writes "$TMP/mut-t8.html" 2>/dev/null; then
    fail "M-T8: releases.length * 12 stayed green — T8 is still a literal grep"
  else
    pass "M-T8: releases.length * 12 turns the commitsEl invariant red"
  fi
else
  fail "M-T8: format(total) assignment was not a unique needle"
fi

# M-T9: replacing the em-dash placeholder with a hardcoded estimate.
T9_OLD='<div class="val" id="cl-commits">—</div>'
T9_NEW='<div class="val" id="cl-commits">~160</div>'
if apply_mut "$CHANGELOG" "$TMP/mut-t9.html" "$T9_OLD" "$T9_NEW"; then
  if scan_commits_placeholder "$TMP/mut-t9.html" 2>/dev/null; then
    fail "M-T9: ~160 placeholder stayed green — T9 has no teeth"
  else
    pass "M-T9: a ~160 placeholder turns T9 red"
  fi
else
  fail "M-T9: cl-commits placeholder markup was not a unique needle"
fi

# M-B: drop the non-thenable guard; the new scenario must go red.
B_OLD="if (!write || typeof write.then !== 'function') { failed(); return; }"
B_NEW="/* non-thenable guard removed */"
if apply_mut "$LANDING" "$TMP/mut-nonthenable.html" "$B_OLD" "$B_NEW"; then
  if node "$TMP/copy-harness.cjs" "$TMP/mut-nonthenable.html" nonthenable \
       >"$TMP/out-mut-nonthenable.txt" 2>&1; then
    fail "M-B: non-thenable scenario stayed green after removing the guard"
    sed 's/^/      /' "$TMP/out-mut-nonthenable.txt"
  else
    pass "M-B: removing the non-thenable guard turns the scenario red"
  fi
else
  fail "M-B: non-thenable guard was not a unique needle"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
