#!/usr/bin/env bash
# test-webpage-ux-a11y-360.sh — Web page nav / mobile / a11y (issue #360).
#
# Closes F-UX-002 / F-UX-006 / F-UX-007 / F-UX-009 / F-UX-012 from the
# modernization report, plus two items handed forward by the review of #359:
#   F-UX-002. Below the nav breakpoint every inline link but the GitHub CTA is
#       hidden, stranding Docs and Changelog. A <details> disclosure menu now
#       carries them — no script, so it degrades exactly like #359 required.
#   F-UX-006. --fg-dim / --dim was #6b7479: 4.15:1 on --bg, 3.90:1 on --panel,
#       both under the 4.5:1 WCAG AA floor for the body copy that used it.
#   F-UX-007. The sticky header is 64px, so anchor jumps landed underneath it.
#       html { scroll-padding-top } must clear it on all three pages.
#   F-UX-009. Nav links, footer links, the copy button, the carousel arrows and
#       dots, the changelog Details toggle and the docs TOC rows all sat under
#       the 44x44 CSS px touch-target floor.
#   F-UX-012. Wide tables had no scroll container. docs.html — which holds all
#       nine reference tables — has no `body { overflow-x: hidden }` net either.
#   Handed forward (a). The install copy row's min-content width exceeded a
#       375px viewport by ~57px, because an unbreakable 32-character URL set the
#       text column's floor while the button refused to shrink.
#   Handed forward (b). `new IntersectionObserver` was unguarded: where the API
#       is missing it throws, and every .reveal block stays at opacity: 0 — the
#       F-UX-001 failure mode with scripting ON.
#
# Also re-guards the invariant that none of this loosened the CSP metas.
#
# Sections:
#   Static   — string/structure assertions (always run).
#   CSS      — python3 cascade walk over each page's <style>: resolves the
#              LAST-winning declaration per selector, in the base context and
#              again inside every @media context, then asserts the *effect*
#              (computed contrast ratio, computed box height/width, scroll
#              padding vs. header height, table enclosure, flex min-content).
#   Behavior — node DOM-shim driving landing.html's real inline script with and
#              without IntersectionObserver. Requires node; without it the
#              section fails loudly rather than passing silently.
#
# Not covered mechanically: pixel-accurate layout. There is no browser in this
# suite, so the copy-row assertions verify the three CSS properties that remove
# the min-content floor, not a measured overflow of 0px.
#
# Usage: bash tests/test-webpage-ux-a11y-360.sh
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

echo "◆ Web page nav / mobile / a11y (#360)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  if [ ! -f "$page" ]; then
    fail "T0: $(basename "$page") missing"
    echo "Result: $PASS passed, $FAIL failed"
    exit 1
  fi
done
pass "T0: landing.html, docs.html, changelog.html all present"

# ── F-UX-007: one scroll-padding-top per page ──────────────────────────────
sp_ok=1
for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  n="$(grep -c 'scroll-padding-top' "$page" || true)"
  [ "$n" -eq 1 ] || sp_ok=0
done
if [ "$sp_ok" -eq 1 ]; then
  pass "T1 (F-UX-007): scroll-padding-top declared exactly once on each page"
else
  fail "T1 (F-UX-007): scroll-padding-top is missing or duplicated on some page"
fi

# ── F-UX-002: the disclosure menu is a <details>, not a scripted widget ────
menu_ok=1
for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  grep -q '<details class="nav-menu"' "$page" || menu_ok=0
  grep -q '<summary>Menu</summary>' "$page" || menu_ok=0
done
if [ "$menu_ok" -eq 1 ]; then
  pass "T2 (F-UX-002): every page has a <details>/<summary> nav menu (no script needed)"
else
  fail "T2 (F-UX-002): a page is missing the <details>-based nav menu"
fi

# ── Handed forward (b): the observer is capability-checked ─────────────────
if grep -q "typeof IntersectionObserver !== 'function'" "$LANDING"; then
  pass "T3 (handed): landing.html checks for IntersectionObserver before using it"
else
  fail "T3 (handed): IntersectionObserver is still constructed unguarded"
fi

# ── F-UX-006: the one-off copy-error red now goes through the token ───────
if grep -q '\.copy-btn\.copy-error { color: var(--red)' "$LANDING"; then
  pass "T4 (F-UX-006): the copy-error state uses the --red token, not a one-off hex"
else
  fail "T4 (F-UX-006): the copy-error state still bypasses the --red token"
fi

# ── CSP not loosened by any of the above (invariant from #338 / #359) ─────
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
  pass "T5: CSP still default-src 'self', no unsafe-eval / wildcard / http: source"
else
  fail "T5: a page's CSP was loosened"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "CSS cascade scan (contrast, touch targets, scroll padding, overflow)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

python3 - "$LANDING" "$DOCS" "$CHANGELOG" >"$TMP/css.txt" 2>"$TMP/css.err" <<'CSS_EOF'
"""Resolve each page's cascade and assert the *effect* of the #360 fixes.

Emits one `PASS\tlabel` / `FAIL\tlabel` line per check so the shell wrapper
keeps a single pass/fail ledger.
"""
import io
import re
import sys

TARGET = 44.0          # WCAG 2.5.5 touch-target floor, CSS px
AA = 4.5               # WCAG 1.4.3 contrast floor for normal-size text
ROOT_FONT = 16.0       # rem base

results = []


def emit(ok, label):
    results.append(('PASS' if ok else 'FAIL', label))


# ── CSS parsing ────────────────────────────────────────────────────────────

def parse_rules(css):
    """[(media, selector, declarations)] in source order; media '' at top level."""
    css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
    out, buf, stack, i, n = [], '', [], 0, len(css)
    while i < n:
        ch = css[i]
        if ch == '{':
            head = ' '.join(buf.split())
            buf = ''
            if head.startswith('@media'):
                stack.append(head)
                i += 1
                continue
            depth, j = 1, i + 1
            while j < n and depth:
                if css[j] == '{':
                    depth += 1
                elif css[j] == '}':
                    depth -= 1
                j += 1
            out.append((' && '.join(stack), head, css[i + 1:j - 1]))
            i = j
            continue
        if ch == '}':
            if stack:
                stack.pop()
            buf = ''
            i += 1
            continue
        buf += ch
        i += 1
    return out


def load(path):
    html = io.open(path, encoding='utf-8').read()
    # Blank comments so a selector quoted in prose is never parsed as CSS.
    stripped = re.sub(r'<!--.*?-->', lambda c: ' ' * len(c.group(0)), html, flags=re.S)
    css = '\n'.join(re.findall(r'<style>(.*?)</style>', stripped, re.S))
    return html, stripped, parse_rules(css)


def resolve(rules, selector, media=''):
    """Merge every rule for `selector` in the base context, then in `media`.

    Later rules win, which is how the real cascade resolves equal-specificity
    rules — the same "last word" model the #359 noscript scan uses.
    """
    merged = {}
    for ctx in ('', media) if media else ('',):
        for rmedia, rsel, body in rules:
            if rmedia != ctx or rsel != selector:
                continue
            for m in re.finditer(r'([a-z-]+)\s*:\s*([^;]+)', body):
                merged[m.group(1)] = m.group(2).strip()
    return merged


def media_contexts(rules, selector):
    """Every @media context that says anything about `selector`."""
    return sorted({m for m, s, _ in rules if s == selector and m})


def px(value):
    if value is None:
        return None
    m = re.match(r'^(-?[\d.]+)(px|rem)?$', value.strip())
    if not m:
        return None
    n = float(m.group(1))
    return n * ROOT_FONT if m.group(2) == 'rem' else n


# ── Contrast ───────────────────────────────────────────────────────────────

def channel(c):
    c /= 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def luminance(hexcolor):
    h = hexcolor.lstrip('#')
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(fg, bg):
    a, b = luminance(fg), luminance(bg)
    hi, lo = max(a, b), min(a, b)
    return (hi + 0.05) / (lo + 0.05)


def tokens(rules):
    out = {}
    for _, sel, body in rules:
        if sel != ':root':
            continue
        for m in re.finditer(r'(--[a-z0-9-]+)\s*:\s*([^;]+)', body):
            out[m.group(1)] = m.group(2).strip()
    return out


# ── Page-specific expectations ─────────────────────────────────────────────
# (selector, human label, must the width also be >= 44?)
# check_width is False where the control is a block/flex box filling its
# container (its width is layout-driven, not content-driven) and True where it
# shrinks to fit its label and so needs an explicit floor.
PAGES = {
    'landing.html': {
        'text_tokens': ['--fg', '--fg-muted', '--fg-dim', '--green', '--cyan', '--yellow', '--red'],
        'backgrounds': ['--bg', '--panel', '--panel-2', '#0c0e0f', '#131618', '#0b0c0d', '#0e0f10'],
        'header_selector': '.nav-inner',
        'collapse_rule': '.nav-links > a:not(.nav-cta)',
        'shrink': ['.model-highlight > *'],
        'controls': [
            ('.nav-links > a', 'header nav links (GitHub CTA included)', True),
            ('.brand', 'brand / home link', False),
            ('.btn', 'hero and CTA buttons', False),
            ('.copy-btn', 'install copy button', True),
            ('.shots-nav', 'carousel prev / next arrows', True),
            ('.shots-dots button', 'carousel dots', True),
            ('.faq summary', 'FAQ disclosure rows', False),
            ('.foot-links a', 'footer links', True),
            ('.nav-menu > summary', 'mobile menu button', True),
            ('.nav-menu-panel a', 'mobile menu items', False),
        ],
    },
    'docs.html': {
        'text_tokens': ['--fg', '--muted', '--dim', '--green', '--cyan', '--yellow', '--red'],
        'backgrounds': ['--bg', '--panel', '--panel2', '#15191b', '#0e1011', '#0d0f10'],
        'header_selector': '.nav',
        'collapse_rule': '.nav-links > a:not(.cta)',
        'shrink': ['.grid > *'],
        'controls': [
            ('.nav-links > a', 'header nav links (GitHub CTA included)', True),
            ('.brand', 'brand / home link', False),
            ('.toc a', 'table-of-contents links', False),
            ('.foot-links a', 'footer links', True),
            ('.nav-menu > summary', 'mobile menu button', True),
            ('.nav-menu-panel a', 'mobile menu items', False),
        ],
    },
    'changelog.html': {
        'text_tokens': ['--fg', '--fg-muted', '--fg-dim', '--green', '--cyan', '--yellow', '--red'],
        'backgrounds': ['--bg', '--panel', '--panel-2', '#0e0f10'],
        'header_selector': '.nav-inner',
        'collapse_rule': '.nav-links > a:not(.nav-cta)',
        'shrink': [],
        'controls': [
            ('.nav-links > a', 'header nav links (GitHub CTA included)', True),
            ('.brand', 'brand / home link', False),
            ('.tl-expand', 'release Details toggle', True),
            ('.foot-links a', 'footer links', True),
            ('.nav-menu > summary', 'mobile menu button', True),
            ('.nav-menu-panel a', 'mobile menu items', False),
        ],
    },
}

paths = {}
for arg in sys.argv[1:]:
    paths[arg.rsplit('/', 1)[-1]] = arg

for name, spec in PAGES.items():
    if name not in paths:
        emit(False, '%s was not passed to the scanner' % name)
        continue
    _, stripped, rules = load(paths[name])
    tok = tokens(rules)
    lh = float(resolve(rules, 'body').get('line-height', '1.6'))

    # ── F-UX-006: every text colour clears AA on every surface it sits on ──
    worst = None
    bad = []
    for tname in spec['text_tokens']:
        fg = tok.get(tname)
        if not fg or not fg.startswith('#'):
            bad.append('%s is not a hex token' % tname)
            continue
        for bname in spec['backgrounds']:
            bg = tok.get(bname, bname)
            if not bg.startswith('#'):
                bad.append('%s is not a hex background' % bname)
                continue
            r = ratio(fg, bg)
            if worst is None or r < worst[0]:
                worst = (r, tname, bname)
            if r < AA:
                bad.append('%s on %s is %.2f:1' % (tname, bname, r))
    if bad:
        emit(False, '%s F-UX-006: below AA — %s' % (name, '; '.join(sorted(set(bad)))))
    else:
        emit(True, '%s F-UX-006: every text token >= %.1f:1 on every surface '
                   '(worst %s on %s = %.2f:1)' % (name, AA, worst[1], worst[2], worst[0]))

    # Button-label contrast is a literal pair, not a token pair.
    if name == 'landing.html':
        r = ratio('#001a06', tok['--green'])
        emit(r >= AA, 'landing.html F-UX-006: primary button label on --green = %.2f:1' % r)

    # ── F-UX-007: the offset must actually clear the sticky header ────────
    sp = px(resolve(rules, 'html').get('scroll-padding-top'))
    header = px(resolve(rules, spec['header_selector']).get('height'))
    if sp is None:
        emit(False, '%s F-UX-007: html has no scroll-padding-top' % name)
    elif header is None:
        emit(False, '%s F-UX-007: could not read the sticky header height' % name)
    else:
        emit(sp >= header,
             '%s F-UX-007: scroll-padding-top is %.0fpx, sticky header is %.0fpx '
             '(the offset must clear the header)' % (name, sp, header))

    # ── F-UX-009: computed hit area, in the base context and every @media ──
    for selector, label, check_width in spec['controls']:
        contexts = [''] + media_contexts(rules, selector)
        smallest_h, smallest_w, where = None, None, ''
        missing = False
        for ctx in contexts:
            d = resolve(rules, selector, ctx)
            if not d:
                missing = True
                break
            h = max([v for v in (px(d.get('min-height')), px(d.get('height'))) if v is not None] or [0])
            if h == 0:
                pad = px((d.get('padding', '0') .split() + ['0'])[0]) or 0.0
                border = 0.0
                bw = d.get('border-width') or d.get('border')
                if bw:
                    m = re.search(r'([\d.]+)px', bw)
                    border = float(m.group(1)) if m else 0.0
                fs = px(d.get('font-size')) or 0.0
                h = 2 * pad + 2 * border + fs * lh
            w = max([v for v in (px(d.get('min-width')), px(d.get('width'))) if v is not None] or [0])
            if smallest_h is None or h < smallest_h:
                smallest_h, where = h, ctx or 'base'
            if smallest_w is None or w < smallest_w:
                smallest_w = w
        if missing:
            emit(False, '%s F-UX-009: no rule found for %s' % (name, selector))
            continue
        if smallest_h < TARGET:
            emit(False, '%s F-UX-009: %s (%s) is %.1fpx tall at "%s"'
                        % (name, label, selector, smallest_h, where))
        elif check_width and smallest_w < TARGET:
            emit(False, '%s F-UX-009: %s (%s) has no %.0fpx width floor (%.1fpx)'
                        % (name, label, selector, TARGET, smallest_w))
        else:
            emit(True, '%s F-UX-009: %s >= %.0fx%.0f (h %.1fpx%s)'
                       % (name, label, TARGET, TARGET, smallest_h,
                          ', w %.1fpx' % smallest_w if check_width else ''))

    # ── F-UX-002: the menu appears exactly where the inline links vanish ──
    collapse_media = [m for m, s, b in rules
                      if s == spec['collapse_rule'] and 'display' in b and 'none' in b and m]
    if not collapse_media:
        emit(False, '%s F-UX-002: could not find the rule that hides the inline nav links' % name)
    else:
        ctx = collapse_media[-1]
        base_menu = resolve(rules, '.nav-menu').get('display')
        shown = resolve(rules, '.nav-menu', ctx).get('display')
        ok = base_menu == 'none' and shown not in (None, 'none')
        emit(ok, '%s F-UX-002: .nav-menu display is %r by default and %r inside "%s" '
                  '(must be none, then shown)' % (name, base_menu, shown, ctx))

    # The panel must actually carry the two links the finding named.
    panel = re.search(r'<div class="nav-menu-panel">(.*?)</div>', stripped, re.S)
    if not panel:
        emit(False, '%s F-UX-002: no .nav-menu-panel in the markup' % name)
    else:
        body_html = panel.group(1)
        have = ['docs.html' in body_html, 'changelog.html' in body_html]
        emit(all(have), '%s F-UX-002: the menu links Docs and Changelog' % name)

    # ── F-UX-012: every table scrolls inside its own container ────────────
    tables = [m.start() for m in re.finditer(r'<table[\s>]', stripped)]
    if tables:
        wrapped = 0
        for pos in tables:
            before = stripped[:pos].rstrip()
            if before.endswith('<div class="table-scroll" tabindex="0">'):
                wrapped += 1
        ov = resolve(rules, '.table-scroll').get('overflow-x')
        if wrapped != len(tables):
            emit(False, '%s F-UX-012: %d of %d tables lack a .table-scroll wrapper'
                        % (name, len(tables) - wrapped, len(tables)))
        elif ov != 'auto':
            emit(False, '%s F-UX-012: .table-scroll overflow-x resolves to %r' % (name, ov))
        else:
            emit(True, '%s F-UX-012: all %d table(s) wrapped in a focusable overflow-x:auto box'
                       % (name, len(tables)))

        # overflow-x:auto alone is not enough: a grid/flex item defaults to
        # min-width:auto, so the COLUMN grows to the table's min-content and the
        # wrapper never scrolls — the page scrolls sideways instead. Measured in
        # Firefox: without this, docs.html is 416px wide in a 320px viewport.
        for sel in spec['shrink']:
            got = resolve(rules, sel).get('min-width')
            emit(px(got) == 0,
                 '%s F-UX-012: %s has min-width:0 so the scroll container can '
                 'actually scroll (got %r)' % (name, sel, got))

    # The footer link row overflowed 320px even before #360, and the 44px width
    # floor widened it further.
    fl = resolve(rules, '.foot-links')
    emit(fl.get('flex-wrap') == 'wrap',
         '%s F-UX-012: .foot-links wraps instead of overflowing (flex-wrap: %r)'
         % (name, fl.get('flex-wrap')))

# ── Handed forward (a): the install copy row's min-content floor ──────────
_, _, rules = load(paths['landing.html'])
row = resolve(rules, '.copy-row')
col = resolve(rules, '.copy-row > div')
cmd = resolve(rules, '.install-body .cmt, .install-body .cmd')
btn = resolve(rules, '.copy-btn')
problems = []
if row.get('flex-wrap') != 'wrap':
    problems.append('.copy-row does not wrap')
if px(col.get('min-width')) != 0:
    problems.append('the text column keeps its auto min-width floor')
if cmd.get('overflow-wrap') not in ('anywhere', 'break-word'):
    problems.append('the command line cannot break inside the URL')
if btn.get('max-width') != '100%':
    problems.append('the copy button has no max-width')
emit(not problems,
     'landing.html handed(a): install copy row cannot exceed its box — %s'
     % ('; '.join(problems) if problems else
        'row wraps, text column min-width:0, URL breaks anywhere, button capped'))

for status, label in results:
    sys.stdout.write('%s\t%s\n' % (status, label))
sys.exit(0)
CSS_EOF

if [ ! -s "$TMP/css.txt" ]; then
  fail "C0: the CSS cascade scanner produced no output"
  sed 's/^/      /' "$TMP/css.err" || true
else
  while IFS="$(printf '\t')" read -r status label; do
    if [ "$status" = "PASS" ]; then pass "C ($label)"; else fail "C ($label)"; fi
  done < "$TMP/css.txt"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Nav reachability (specificity-aware cascade over real element paths)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

python3 - "$LANDING" "$DOCS" "$CHANGELOG" >"$TMP/reach.txt" 2>"$TMP/reach.err" <<'REACH_EOF'
"""Does a rule elsewhere in the sheet win `display` on the menu's own links?

The scan above resolves declarations by *selector-string equality*, which
cannot see a competing rule that also matches the element. That blind spot is
not hypothetical: `.nav-links a:not(.nav-cta)` is (0,2,1) and matches the
disclosure panel's links, beating `.nav-menu-panel a` at (0,1,1) — so the menu
opened onto an empty box while every selector-equality assertion stayed green.

This section therefore walks a real element path, matches every selector
against it, orders the matches by (specificity, source order), and reports the
winning value — a small cascade engine, stdlib only.

Modelled: type / class / id / attribute / :not() simple selectors, descendant
and child combinators, and width-based @media. NOT modelled: sibling
combinators, structural pseudo-classes, and non-width media — a rule using one
is treated as not matching and is counted in the `unmodelled` tally, which is
printed so a silent skip cannot hide behind a pass.
"""
import io
import re
import sys

STATE_PC = {'hover', 'focus', 'focus-visible', 'focus-within', 'active', 'visited', 'target'}

TOKEN = re.compile(r"""
    (?P<pe>::[-\w]+)
  | :not\((?P<notarg>[^()]*)\)
  | (?P<pc>:[-\w]+)
  | \[(?P<attr>[^\]]*)\]
  | \.(?P<cls>[-\w]+)
  | \#(?P<id>[-\w]+)
  | (?P<tag>\*|[-\w]+)
""", re.X)

unmodelled = set()
results = []


def emit(ok, label):
    results.append(('PASS' if ok else 'FAIL', label))


def parse_compound(text):
    c = {'tag': None, 'ids': [], 'classes': [], 'attrs': [], 'pcs': [], 'pes': [], 'nots': []}
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m:
            raise ValueError('unparsable compound %r' % text)
        pos = m.end()
        if m.group('pe'):
            c['pes'].append(m.group('pe'))
        elif m.group('notarg') is not None:
            c['nots'].append(parse_compound(m.group('notarg').strip()))
        elif m.group('pc'):
            c['pcs'].append(m.group('pc')[1:])
        elif m.group('attr'):
            c['attrs'].append(m.group('attr').split('=')[0].strip())
        elif m.group('cls'):
            c['classes'].append(m.group('cls'))
        elif m.group('id'):
            c['ids'].append(m.group('id'))
        else:
            c['tag'] = m.group('tag')
    return c


def split_combinators(sel):
    out, buf, i = [], '', 0
    while i < len(sel):
        ch = sel[i]
        if ch in '>+~':
            out.append(parse_compound(buf.strip()))
            out.append(ch)
            buf = ''
        elif ch == ' ':
            j = i
            while j < len(sel) and sel[j] == ' ':
                j += 1
            if j < len(sel) and sel[j] in '>+~':
                i = j
                continue
            if buf.strip():
                out.append(parse_compound(buf.strip()))
                out.append(' ')
                buf = ''
            i = j
            continue
        else:
            buf += ch
        i += 1
    if buf.strip():
        out.append(parse_compound(buf.strip()))
    return out


def compound_matches(c, el):
    if c['pes']:
        return False                     # targets a pseudo-element, not the element
    for pc in c['pcs']:
        if pc not in STATE_PC:
            unmodelled.add(pc)
        return False                     # at-rest state only
    if c['tag'] and c['tag'] != '*' and c['tag'] != el['tag']:
        return False
    if any(i not in el.get('ids', []) for i in c['ids']):
        return False
    if any(k not in el['classes'] for k in c['classes']):
        return False
    if any(a not in el.get('attrs', []) for a in c['attrs']):
        return False
    return not any(compound_matches(n, el) for n in c['nots'])


def selector_matches(sel, path):
    parts = split_combinators(sel)
    i, e = len(parts) - 1, len(path) - 1
    if not compound_matches(parts[i], path[e]):
        return False
    i -= 1
    while i >= 0:
        comb, comp = parts[i], parts[i - 1]
        i -= 2
        if comb == '>':
            e -= 1
            if e < 0 or not compound_matches(comp, path[e]):
                return False
        elif comb == ' ':
            j, found = e - 1, False
            while j >= 0:
                if compound_matches(comp, path[j]):
                    e, found = j, True
                    break
                j -= 1
            if not found:
                return False
        else:
            unmodelled.add(comb)
            return False
    return True


def spec_of(c):
    return (len(c['ids']),
            len(c['classes']) + len(c['attrs']) + len(c['pcs']),
            len(c['pes']) + (1 if c['tag'] and c['tag'] != '*' else 0))


def specificity(sel):
    a = b = c = 0
    for part in split_combinators(sel):
        if isinstance(part, str):
            continue
        pa, pb, pc = spec_of(part)
        a, b, c = a + pa, b + pb, c + pc
        for n in part['nots']:
            na, nb, nc = spec_of(n)
            a, b, c = a + na, b + nb, c + nc
    return (a, b, c)


def media_applies(cond, width):
    if not cond:
        return True
    for clause in cond.split(' && '):
        found = re.findall(r'\((max|min)-width:\s*(\d+)px\)', clause)
        if not found:
            return False                 # non-width media: not modelled
        for kind, n in found:
            n = int(n)
            if kind == 'max' and width > n:
                return False
            if kind == 'min' and width < n:
                return False
    return True


def parse_rules(css):
    css = re.sub(r'/\*.*?\*/', '', css, flags=re.S)
    out, buf, stack, i, n = [], '', [], 0, len(css)
    while i < n:
        ch = css[i]
        if ch == '{':
            head = ' '.join(buf.split())
            buf = ''
            if head.startswith('@media'):
                stack.append(head)
                i += 1
                continue
            depth, j = 1, i + 1
            while j < n and depth:
                if css[j] == '{':
                    depth += 1
                elif css[j] == '}':
                    depth -= 1
                j += 1
            out.append((' && '.join(stack), head, css[i + 1:j - 1]))
            i = j
            continue
        if ch == '}':
            if stack:
                stack.pop()
            buf = ''
            i += 1
            continue
        buf += ch
        i += 1
    return out


def computed(rules, path, prop, width):
    cands = []
    for order, (media, sel_list, body) in enumerate(rules):
        val = None
        for m in re.finditer(r'(?:^|;)\s*' + re.escape(prop) + r'\s*:\s*([^;]+)', body):
            val = m.group(1).strip()
        if val is None:
            continue
        if not media_applies(media, width):
            continue
        for sel in sel_list.split(','):
            sel = ' '.join(sel.split())
            if not sel or sel.startswith('@') or sel.startswith('%'):
                continue
            try:
                if not selector_matches(sel, path):
                    continue
            except ValueError:
                # A selector the parser cannot model is a blind spot, not a
                # non-match: tally it so the guard below fails loud instead of
                # silently dropping a rule that might win `display`.
                unmodelled.add(sel)
                continue
            cands.append((specificity(sel), order, val))
    if not cands:
        return None
    cands.sort(key=lambda t: (t[0], t[1]))
    return cands[-1][2]


def el(tag, classes=(), ids=(), attrs=()):
    """Class names are stored bare, exactly as parse_compound() records them."""
    return {'tag': tag, 'classes': list(classes),
            'ids': list(ids), 'attrs': list(attrs)}


PAGES = {
    'landing.html': {'header_classes': ['nav'], 'wrap_classes': ['wrap', 'nav-inner'],
                     'cta': 'nav-cta', 'breakpoint': 760},
    'docs.html': {'header_classes': [], 'wrap_classes': ['wrap', 'nav', 'nav-inner'],
                  'cta': 'cta', 'breakpoint': 860},
    'changelog.html': {'header_classes': ['nav'], 'wrap_classes': ['wrap', 'nav-inner'],
                       'cta': 'nav-cta', 'breakpoint': 760},
}

paths = {}
for arg in sys.argv[1:]:
    paths[arg.rsplit('/', 1)[-1]] = arg

DESKTOP = 1280

for name, cfg in PAGES.items():
    html = io.open(paths[name], encoding='utf-8').read()
    html = re.sub(r'<!--.*?-->', lambda c: ' ' * len(c.group(0)), html, flags=re.S)
    rules = parse_rules('\n'.join(re.findall(r'<style>(.*?)</style>', html, re.S)))
    mobile = cfg['breakpoint'] - 1

    base = [el('html'), el('body'), el('header', cfg['header_classes']),
            el('div', cfg['wrap_classes']), el('nav', ['nav-links'])]
    inline_link = base + [el('a')]
    inline_cta = base + [el('a', [cfg['cta']])]
    menu = base + [el('details', ['nav-menu'], ['nav-menu'], ['open'])]
    panel = menu + [el('div', ['nav-menu-panel'])]
    panel_link = panel + [el('a')]

    # Desktop: inline links carry navigation; the menu must not duplicate them.
    d = computed(rules, inline_link, 'display', DESKTOP)
    emit(d is not None and d != 'none',
         '%s @%dpx: inline nav links are visible (display: %r)' % (name, DESKTOP, d))
    emit(computed(rules, menu, 'display', DESKTOP) == 'none',
         '%s @%dpx: the disclosure menu is hidden — no duplicate tab stops' % (name, DESKTOP))

    # Mobile: the inline links collapse and the menu takes over.
    emit(computed(rules, inline_link, 'display', mobile) == 'none',
         '%s @%dpx: inline nav links collapse' % (name, mobile))
    d = computed(rules, inline_cta, 'display', mobile)
    emit(d is not None and d != 'none',
         '%s @%dpx: the GitHub CTA survives the collapse (display: %r)' % (name, mobile, d))
    d = computed(rules, menu, 'display', mobile)
    emit(d is not None and d != 'none',
         '%s @%dpx: the disclosure menu is shown (display: %r)' % (name, mobile, d))

    # The assertion the selector-equality scan structurally could not make.
    bad = []
    for label, node in (('panel', panel), ('panel link', panel_link)):
        d = computed(rules, node, 'display', mobile)
        v = computed(rules, node, 'visibility', mobile)
        if d is None:
            bad.append('%s matched no display rule at all (engine or markup drift)' % label)
        elif d == 'none':
            bad.append('%s display:none' % label)
        if v == 'hidden':
            bad.append('%s visibility:hidden' % label)
    emit(not bad,
         '%s @%dpx: the menu\'s own links are NOT hidden by any rule that also '
         'matches them%s' % (name, mobile, (' — ' + '; '.join(bad)) if bad else ''))

emit(not unmodelled,
     'the cascade engine met no unmodelled selector feature on the nav paths%s'
     % ((' — saw: ' + ', '.join(sorted(unmodelled))) if unmodelled else ''))

for status, label in results:
    sys.stdout.write('%s\t%s\n' % (status, label))
sys.exit(0)
REACH_EOF

if [ ! -s "$TMP/reach.txt" ]; then
  fail "R0: the reachability scanner produced no output"
  sed 's/^/      /' "$TMP/reach.err" || true
else
  while IFS="$(printf '\t')" read -r status label; do
    if [ "$status" = "PASS" ]; then pass "R ($label)"; else fail "R ($label)"; fi
  done < "$TMP/reach.txt"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Behavioral (Node DOM-shim, IntersectionObserver availability)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if ! command -v node >/dev/null 2>&1; then
  fail "B0: node is required for the behavioral section but was not found"
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

cat > "$TMP/reveal-harness.cjs" <<'HARNESS_EOF'
'use strict';
// Drives landing.html's real inline script with and without
// IntersectionObserver, and asserts what a reader would actually see. Nothing
// is copied from the page into this file — the script under test is sliced out
// of landing.html itself.
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

// One stand-in per .reveal block actually present in the page.
const revealCount = (html.match(/class="[^"]*\breveal\b/g) || []).length;
if (revealCount < 20) {
  console.error('harness: expected the .reveal markup to survive, found ' + revealCount);
  process.exit(2);
}
const reveals = [];
for (let i = 0; i < revealCount; i++) {
  reveals.push({ tagName: 'DIV', classList: makeClassList() });
}

let observed = 0;
const shim = {
  console: console,
  setTimeout: setTimeout,
  clearTimeout: clearTimeout,
  Intl: Intl,
  navigator: {},
  // Never settles: the release/stars fetches must not interfere.
  fetch: function () { return new Promise(function () {}); },
  document: {
    // Slideshow and nav-menu blocks bail out when their elements are absent.
    getElementById: function () { return null; },
    querySelectorAll: function (sel) { return sel === '.reveal' ? reveals : []; },
    createElement: function () { return { classList: makeClassList(), appendChild: function () {} }; },
    documentElement: { classList: makeClassList() }
  }
};

if (scenario === 'io-present') {
  shim.IntersectionObserver = function () {
    this.observe = function () { observed += 1; };
    this.unobserve = function () {};
  };
} else if (scenario !== 'io-missing') {
  console.error('harness: unknown scenario ' + scenario);
  process.exit(2);
}

vm.createContext(shim);
try {
  vm.runInContext(code, shim, { filename: 'landing-inline.js' });
} catch (err) {
  console.error('harness: ' + scenario + ': the inline script threw: ' + ((err && err.message) || err));
  process.exit(1);
}

const die = function (msg) { console.error('harness: ' + scenario + ': ' + msg); process.exit(1); };
const shown = reveals.filter(function (el) { return el.classList.contains('in'); }).length;

if (scenario === 'io-missing') {
  // .js is on <html>, so `.js .reveal { opacity: 0 }` is live. Without the
  // observer nothing would ever add .in — every block must be revealed up front.
  if (shown !== revealCount) {
    die(shown + ' of ' + revealCount + ' .reveal blocks visible — the rest stay at opacity: 0');
  }
  process.stdout.write('all ' + revealCount + ' .reveal blocks revealed without the API\n');
} else {
  if (observed !== revealCount) {
    die('observer saw ' + observed + ' of ' + revealCount + ' .reveal blocks');
  }
  if (shown !== 0) {
    die(shown + ' blocks were revealed up front — the scroll animation was lost');
  }
  process.stdout.write('all ' + revealCount + ' .reveal blocks handed to the observer\n');
}
process.exit(0);
HARNESS_EOF

for scenario_name in io-present io-missing; do
  case "$scenario_name" in
    io-present) label="IntersectionObserver available → every .reveal is observed, none pre-revealed" ;;
    io-missing) label="IntersectionObserver missing → every .reveal is revealed, none left invisible" ;;
  esac
  if node "$TMP/reveal-harness.cjs" "$LANDING" "$scenario_name" >"$TMP/out-$scenario_name.txt" 2>&1; then
    pass "B (handed): $label"
  else
    fail "B (handed): $label"
    sed 's/^/      /' "$TMP/out-$scenario_name.txt"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
