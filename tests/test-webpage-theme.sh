#!/usr/bin/env bash
# test-webpage-theme.sh — Light/dark theme guards for the three public pages
# (v2 theme work, deck §B).
#
# Per page (landing.html, docs.html, changelog.html):
#   T1 — exactly one <script id="theme-init">, inside <head>, before any
#        stylesheet or <style>: the palette must be resolved before first
#        paint, and the attributed id keeps it invisible to the harnesses
#        that slice the first/last PLAIN <script>.
#   T2 — exactly one html[data-theme="light"] rule, and it re-declares every
#        colour token in the page's dark :root; no :root[...] selector
#        anywhere and only one bare :root rule (the a11y scanner merges all
#        bare :root rules to read the dark palette, and treats :root[...] as
#        an unmodelled feature).
#   T3 — every light text token is >= 4.5:1 on every light background token
#        the page declares (WCAG AA for the light palette).
#   T4 — a #theme-toggle <button type="button"> with an aria-label inside the
#        nav, plus a .theme-toggle rule with a 44px min width and height.
#   T5 — behavioral: the theme-init script runs in a node vm DOM shim. Stored
#        light/dark wins; nothing stored follows prefers-color-scheme;
#        localStorage failures fall back to the OS; no matchMedia means dark.
#        A delegated click on #theme-toggle flips the theme, persists it and
#        flips the aria-label. Requires node; absent node fails loudly.
#   T6 — landing only: the light-theme rule that re-declares dark tokens on
#        .terminal & friends also sets `color:` — bare text nodes inside
#        .term-body otherwise inherit the light --fg from <body> and vanish.
#
# Usage: bash tests/test-webpage-theme.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0
FAIL=0

pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }

echo "◆ Webpage Theme Tests (v2 light/dark)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

# ── T1–T4: static structure + light palette (python3, one pass per page) ──
if python3 - "$REPO_ROOT/landing.html" "$REPO_ROOT/docs.html" "$REPO_ROOT/changelog.html" <<'PY'
import io, re, sys

# (text tokens, background tokens) used by the T3 contrast matrix. Token
# names differ per page (docs uses --muted/--dim/--panel2); the values must
# come out of each page's own html[data-theme="light"] rule.
PAGES = {
    'landing.html': {
        'text': ['--fg', '--fg-muted', '--fg-dim', '--green', '--cyan', '--yellow', '--red'],
        'bg': ['--bg', '--panel', '--panel-2', '--bg-soft'],
    },
    'docs.html': {
        'text': ['--fg', '--muted', '--dim', '--green', '--cyan', '--yellow', '--red'],
        'bg': ['--bg', '--panel', '--panel2'],
    },
    'changelog.html': {
        'text': ['--fg', '--fg-muted', '--fg-dim', '--green', '--cyan', '--yellow', '--red'],
        'bg': ['--bg', '--panel', '--panel-2', '--bg-soft'],
    },
}


def css_of(src):
    css = '\n'.join(re.findall(r'<style>(.*?)</style>', src, re.S))
    return re.sub(r'/\*.*?\*/', '', css, flags=re.S)


def rule_body(css, selector):
    """Declarations of the rule whose selector is exactly `selector`."""
    m = re.search(re.escape(selector) + r'\s*\{', css)
    if not m:
        return None
    depth, i = 1, m.end()
    while i < len(css) and depth:
        if css[i] == '{':
            depth += 1
        elif css[i] == '}':
            depth -= 1
        i += 1
    return css[m.end():i - 1]


def tokens_of(body):
    return dict(re.findall(r'(--[\w-]+)\s*:\s*([^;]+);', body))


def is_colour(value):
    return re.match(r'\s*(#[0-9a-fA-F]{3,8}|rgba?\()', value) is not None


def lum(hexv):
    hexv = hexv.lstrip('#')
    if len(hexv) == 3:
        hexv = ''.join(c * 2 for c in hexv)
    r, g, b = (int(hexv[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    def ch(c):
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


results = {}
for path in sys.argv[1:]:
    name = path.rsplit('/', 1)[-1]
    spec = PAGES[name]
    src = io.open(path, encoding='utf-8').read()
    css = css_of(src)
    out = {'t1': [], 't2': [], 't3': [], 't4': [], 't6': []}

    # T1 — one attributed init script, in <head>, before any styling
    if src.count('id="theme-init"') != 1:
        out['t1'].append('expected exactly one id="theme-init", found %d'
                         % src.count('id="theme-init"'))
    else:
        idx = src.find('id="theme-init"')
        head_end = src.find('</head>')
        if head_end < 0 or idx > head_end:
            out['t1'].append('theme-init script is not inside <head>')
        first_style = min([p for p in (src.find('<style'), src.find('rel="stylesheet"')) if p >= 0],
                          default=len(src))
        if idx > first_style:
            out['t1'].append('theme-init comes after a stylesheet/<style> (first paint unguarded)')
        if not re.search(r'<script id="theme-init">', src):
            out['t1'].append('theme-init is not a plain attributed <script id="theme-init"> tag')

    # T2 — one light rule covering every dark colour token; clean :root usage
    if ':root[' in css:
        out['t2'].append('forbidden :root[ selector present')
    if len(re.findall(r'(?:^|\})\s*:root\s*\{', css)) != 1:
        out['t2'].append('expected exactly one bare :root rule, found %d'
                         % len(re.findall(r'(?:^|\})\s*:root\s*\{', css)))
    light_count = len(re.findall(r'html\[data-theme="light"\]\s*\{', css))
    if light_count != 1:
        out['t2'].append('expected exactly one html[data-theme="light"] rule, found %d' % light_count)
    dark = rule_body(css, ':root')
    light = rule_body(css, 'html[data-theme="light"]')
    dark_tok = tokens_of(dark or '')
    light_tok = tokens_of(light or '')
    dark_colours = {k for k, v in dark_tok.items() if is_colour(v)}
    missing = sorted(dark_colours - set(light_tok))
    if light is None:
        out['t2'].append('html[data-theme="light"] rule missing')
    elif missing:
        out['t2'].append('light rule does not declare dark colour tokens: %s' % ', '.join(missing))
    if 'color-scheme: light' not in (light or ''):
        out['t2'].append('light rule lacks color-scheme: light')
    if 'color-scheme: dark' not in (dark or ''):
        out['t2'].append(':root lacks color-scheme: dark')

    # T3 — light text tokens >= 4.5:1 on every light background token.
    # First assert the rule actually defines every token we measure so this
    # can never pass vacuously on a page with no light palette.
    if light is None:
        out['t3'].append('no html[data-theme="light"] rule — nothing to measure')
    else:
        for tname in spec['text'] + spec['bg']:
            if tname not in light_tok:
                out['t3'].append('light rule does not define %s' % tname)
        for tname in spec['text']:
            tv = light_tok.get(tname, '').strip()
            if not tv.startswith('#'):
                out['t3'].append('%s is not a hex colour in the light rule (%r)' % (tname, tv))
                continue
            for bname in spec['bg']:
                bv = light_tok.get(bname, '').strip()
                if not bv.startswith('#'):
                    continue
                r = contrast(tv, bv)
                if r < 4.5:
                    out['t3'].append('%s (%s) vs %s (%s) = %.2f:1 < 4.5' % (tname, tv, bname, bv, r))

    # T4 — toggle button inside <nav>, and its 44px floor
    btn = re.search(r'<button[^>]*id="theme-toggle"[^>]*>', src)
    if not btn:
        out['t4'].append('no <button> with id="theme-toggle"')
    else:
        tag = btn.group(0)
        if 'type="button"' not in tag:
            out['t4'].append('#theme-toggle lacks type="button"')
        if 'aria-label=' not in tag:
            out['t4'].append('#theme-toggle lacks an aria-label')
        nav_open = src.rfind('<nav', 0, btn.start())
        nav_close = src.find('</nav>', btn.end())
        if nav_open < 0 or nav_close < 0:
            out['t4'].append('#theme-toggle is not inside a <nav> element')
    body = rule_body(css, '.theme-toggle') or ''
    for prop in ('min-width', 'min-height'):
        if not re.search(prop + r'\s*:\s*44px', body):
            out['t4'].append('.theme-toggle lacks %s: 44px' % prop)

    # T6 (landing only) — the dark terminal surfaces must re-resolve the
    # inherited text colour, not just the tokens: bare text nodes inside
    # .term-body otherwise inherit the light --fg from <body> and vanish.
    if name == 'landing.html':
        surf = re.search(r'html\[data-theme="light"\][^{}]*\.terminal[^{}]*\{([^}]*)\}', css)
        if not surf:
            out['t6'].append('no light-theme rule re-declares dark tokens on .terminal')
        elif not re.search(r'(^|[;\s])color\s*:', surf.group(1)):
            out['t6'].append('dark-surface rule lacks color: — inherited text goes light-on-dark')

    results[name] = out

had_fail = False
for name in PAGES:
    checks = ('t1', 't2', 't3', 't4') + (('t6',) if name == 'landing.html' else ())
    for t in checks:
        probs = results[name][t]
        if probs:
            had_fail = True
            print('FAIL %s %s:' % (name, t.upper()))
            for p in probs:
                print('    ' + p)
        else:
            print('PASS %s %s' % (name, t.upper()))
sys.exit(1 if had_fail else 0)
PY
then
  pass "T1–T4+T6: init script placement, single light rule, contrast, toggle control, dark-surface colour"
else
  fail "T1–T4+T6: theme structure/palette violations (see above)"
fi

# ── T5: theme-init behaviour in a node DOM shim ──
if ! command -v node >/dev/null 2>&1; then
  fail "T5: node is required to exercise theme-init behaviour"
else
  for page in landing.html docs.html changelog.html; do
    if node - "$REPO_ROOT/$page" <<'JS'
const fs = require('fs');
const vm = require('vm');

const src = fs.readFileSync(process.argv[2], 'utf8');
const m = src.match(/<script id="theme-init">([\s\S]*?)<\/script>/);
if (!m) { console.error('  no <script id="theme-init"> found'); process.exit(1); }
const code = m[1];

function run(opts) {
  const store = Object.assign({}, opts.store);
  const root = {
    attrs: {},
    setAttribute(k, v) { this.attrs[k] = v; },
    removeAttribute(k) { delete this.attrs[k]; },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; }
  };
  const toggle = {
    attrs: {},
    setAttribute(k, v) { this.attrs[k] = v; },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attrs, k) ? this.attrs[k] : null; }
  };
  const meta = { attrs: {}, setAttribute(k, v) { this.attrs[k] = v; } };
  const doc = {
    documentElement: root,
    listeners: {},
    addEventListener(t, f) { this.listeners[t] = f; },
    querySelector(s) { return /theme-color/.test(s) ? meta : null; },
    getElementById(id) { return id === 'theme-toggle' ? toggle : null; }
  };
  const ls = {
    getItem() { if (opts.lsThrows) { throw new Error('denied'); } return store['idd-theme'] !== undefined ? store['idd-theme'] : null; },
    setItem(k, v) { store[k] = String(v); }
  };
  const sandbox = { document: doc, localStorage: ls };
  if (!opts.noMM) {
    sandbox.matchMedia = function () {
      return { matches: opts.os === 'light', addEventListener() {}, addListener() {} };
    };
  }
  vm.createContext(sandbox);
  vm.runInContext(code, sandbox);
  return { root, toggle, meta, store, doc };
}

const theme = r => (r.root.attrs['data-theme'] === 'light' ? 'light' : 'dark');
const problems = [];
const cases = [
  ['stored light wins over OS dark', { store: { 'idd-theme': 'light' }, os: 'dark' }, 'light'],
  ['stored dark wins over OS light', { store: { 'idd-theme': 'dark' }, os: 'light' }, 'dark'],
  ['no store + OS light', { store: {}, os: 'light' }, 'light'],
  ['no store + OS dark', { store: {}, os: 'dark' }, 'dark'],
  ['localStorage throws -> OS', { store: {}, os: 'light', lsThrows: true }, 'light'],
  ['no matchMedia -> dark', { store: {}, os: 'light', noMM: true }, 'dark'],
];
for (const [label, opts, want] of cases) {
  const got = theme(run(opts));
  if (got !== want) { problems.push(label + ': got ' + got + ', want ' + want); }
}

const r = run({ store: {}, os: 'dark' });
if (theme(r) !== 'dark') { problems.push('click case did not start dark'); }
if (typeof r.doc.listeners.click !== 'function') { problems.push('no delegated click listener registered'); } else {
  r.doc.listeners.click({ target: { closest: s => (s === '#theme-toggle' ? r.toggle : null) } });
  if (theme(r) !== 'light') { problems.push('click did not flip dark -> light'); }
  if (r.store['idd-theme'] !== 'light') { problems.push('click did not persist light'); }
  if (r.toggle.attrs['aria-label'] !== 'Switch to dark theme') {
    problems.push('aria-label after flip is ' + JSON.stringify(r.toggle.attrs['aria-label']));
  }
  if (r.meta.attrs['content'] !== '#FAFAFA') { problems.push('theme-color meta not #FAFAFA after flip'); }
}

for (const p of problems) { console.error('    ' + p); }
process.exit(problems.length ? 1 : 0);
JS
    then
      pass "T5: $page theme-init behaviour (storage/OS/no-matchMedia/click)"
    else
      fail "T5: $page theme-init behaviour broken (see above)"
    fi
  done
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
