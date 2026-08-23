#!/usr/bin/env bash
# test-webpage-hardening-338.sh — Web page hardening (issue #338).
#
# Closes F-BUG-002 / F-SEC-002 from the modernization report:
#   AC1. Every deployed page (landing.html, docs.html, changelog.html)
#       carries exactly one Content-Security-Policy meta whose connect-src
#       allows api.github.com.
#   AC2. changelog.html contains no innerHTML assignment at all — API-derived
#       strings reach the DOM only as DOM-node text (textContent), never as
#       markup.
#   AC3. A release tag is promoted to an href only after passing a validation
#       predicate; invalid tags render as inert text.
#   AC4. Behavioral (Node): fed a mocked GitHub-API payload containing
#       <script> tags and quote characters, the changelog renders them as
#       inert text — no script elements, no anchors for invalid tags; a valid
#       tag still produces the expected release link; the offline fallback
#       path still renders known releases through the safe path.
#
# The behavioral section requires node; without it the static section still
# runs and the behavioral section fails loudly rather than passing silently.
#
# Usage: bash tests/test-webpage-hardening-338.sh
# Returns: exit 0 if all tests pass, exit 1 on any failure.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LANDING="$REPO_ROOT/landing.html"
DOCS="$REPO_ROOT/docs.html"
CHANGELOG="$REPO_ROOT/changelog.html"

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

echo "◆ Web page hardening (#338)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

for page in "$LANDING" "$DOCS" "$CHANGELOG"; do
  name="$(basename "$page")"
  if [ ! -f "$page" ]; then
    fail "T0: $name missing"
    echo "Result: $PASS passed, $FAIL failed"
    exit 1
  fi
  count="$(grep -c 'Content-Security-Policy' "$page" || true)"
  if [ "$count" -eq 1 ]; then
    pass "T1: $name carries exactly one CSP meta"
  else
    fail "T1: $name has $count Content-Security-Policy occurrences (expected 1)"
  fi
  if grep -q 'connect-src[^"]*api\.github\.com' "$page"; then
    pass "T2: $name connect-src allows api.github.com"
  else
    fail "T2: $name connect-src does not include api.github.com"
  fi
done

# T3: the verify command of record — no innerHTML assignments anywhere in
# changelog.html, including the timeline clear.
if grep -nE '\.innerHTML[[:space:]]*=' "$CHANGELOG" >/dev/null 2>&1; then
  fail "T3: changelog.html still assigns innerHTML"
else
  pass "T3: no .innerHTML assignments in changelog.html"
fi

# T4: tag→href promotion is guarded by the validation predicate.
if grep -q 'function isValidReleaseTag' "$CHANGELOG" \
   && grep -q 'isValidReleaseTag(rel.tag)' "$CHANGELOG"; then
  pass "T4: release-tag predicate exists and guards href promotion"
else
  fail "T4: unguarded tag-to-href assignment in changelog.html"
fi

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Behavioral (Node DOM-shim, mocked GitHub API)"
echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"

if ! command -v node >/dev/null 2>&1; then
  fail "B0: node is required for the behavioral section but was not found"
  echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
  echo "Result: $PASS passed, $FAIL failed"
  exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/harness.cjs" <<'HARNESS_EOF'
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');

const htmlPath = process.argv[2];
const scenario = process.argv[3];
const html = fs.readFileSync(htmlPath, 'utf8');

const start = html.indexOf('<script>') + '<script>'.length;
const end = html.lastIndexOf('</script>');
if (start < 8 || end <= start) {
  console.error('harness: could not locate the inline changelog script');
  process.exit(2);
}
const code = html.slice(start, end);

class El {
  constructor(tag) {
    this.tagName = String(tag).toUpperCase();
    this.children = [];
    this.parentNode = null;
    this.className = '';
    this.attrs = {};
    this._text = '';
    const set = new Set();
    this.classList = {
      toggle(c) { if (set.has(c)) { set.delete(c); return false; } set.add(c); return true; },
      contains(c) { return set.has(c); },
      add(c) { set.add(c); },
      remove(c) { set.delete(c); }
    };
    this._listeners = {};
  }
  get href() { return this.attrs.href || ''; }
  set href(v) { this.attrs.href = String(v); }
  get textContent() {
    if (this.children.length === 0) return this._text;
    return this.children.map(function (c) { return c.textContent; }).join('');
  }
  set textContent(v) { this._text = String(v); this.children = []; }
  appendChild(c) { c.parentNode = this; this.children.push(c); return c; }
  replaceChildren(...kids) {
    this.children.forEach(function (k) { k.parentNode = null; });
    this.children = kids.slice();
    kids.forEach(function (k) { k.parentNode = this; }, this);
  }
  addEventListener(type, fn) { this._listeners[type] = fn; }
  click() { if (this._listeners.click) this._listeners.click(); }
}

const byId = {};
['changelog-timeline', 'cl-releases', 'cl-commits', 'cl-days'].forEach(function (id) {
  byId[id] = new El('div');
});
const shim = {
  document: {
    getElementById: function (id) {
      if (!byId[id]) byId[id] = new El('div');
      return byId[id];
    },
    createElement: function (t) { return new El(t); }
  }
};

function walk(node, out) {
  out.push(node);
  node.children.forEach(function (c) { walk(c, out); });
}
function findAll(root, pred) {
  const out = [];
  walk(root, out);
  return out.filter(pred);
}

let releasesJson, repoJson, failFetch;
if (scenario === 'xss') {
  releasesJson = [{
    tag_name: 'v9"><script>alert(1)</script>',
    name: 'Evil <b>name</b> "quoted"',
    body: 'body <script>alert(2)</script> & """quotes"""',
    published_at: '2026-08-01T00:00:00Z'
  }];
  repoJson = { forks_count: 2 };
} else if (scenario === 'valid') {
  releasesJson = [{
    tag_name: 'v9.9.9-mock_1',
    name: 'Mock release',
    body: 'n/a',
    published_at: '2026-08-01T00:00:00Z'
  }];
  repoJson = { forks_count: 2 };
}

shim.fetch = function (url) {
  if (failFetch) return Promise.reject(new Error('network down'));
  if (String(url).indexOf('/releases') !== -1) return Promise.resolve({ json: function () { return Promise.resolve(releasesJson); } });
  return Promise.resolve({ json: function () { return Promise.resolve(repoJson); } });
};

if (scenario === 'fallback') failFetch = true;

vm.createContext(shim);
vm.runInContext(code, shim, { filename: 'changelog-inline.js' });

// Let the mocked fetch promises settle.
new Promise(function (r) { setTimeout(r, 50); }).then(function () {
  const timeline = byId['changelog-timeline'];
  const nodes = [];
  walk(timeline, nodes);

  const die = function (msg) { console.error('harness: ' + msg); process.exit(1); };

  if (nodes.some(function (n) { return n.tagName === 'SCRIPT'; })) {
    die(scenario + ': a SCRIPT element reached the rendered tree');
  }

  const anchors = nodes.filter(function (n) { return n.tagName === 'A'; });

  if (scenario === 'xss') {
    if (!timeline.textContent.includes('<script>alert(1)</script>')) {
      die('xss: payload text did not render as inert text');
    }
    if (!timeline.textContent.includes('<b>')) {
      die('xss: payload markup chars were not preserved literally');
    }
    if (anchors.length !== 0) {
      die('xss: an anchor was created for an invalid tag');
    }
    if (byId['cl-releases'].textContent !== '1') {
      die('xss: stats element not updated (got ' + byId['cl-releases'].textContent + ')');
    }
    process.stdout.write('xss payload rendered inert: no SCRIPT nodes, no anchors\n');
  } else if (scenario === 'valid') {
    if (anchors.length !== 1) die('valid: expected exactly 1 anchor, got ' + anchors.length);
    const link = anchors[0];
    const want = 'https://github.com/luongnv89/idd/releases/tag/v9.9.9-mock_1';
    if (link.href !== want) die('valid: wrong href ' + link.href);
    if (link.textContent !== 'v9.9.9-mock_1') die('valid: wrong link text');
    const btn = nodes.find(function (n) { return n.tagName === 'BUTTON'; }) ||
      nodes.filter(function (n) { return n.className === 'tl-expand'; })[0];
    if (!btn) die('valid: expand button missing');
    const detail = nodes.find(function (n) { return n.className === 'tl-detail'; });
    if (!detail) die('valid: detail container missing');
    btn.click();
    if (!detail.classList.contains('open')) die('valid: click did not open detail');
    if (btn.textContent !== 'Less ▴') die('valid: click did not relabel button');
    btn.click();
    if (detail.classList.contains('open')) die('valid: second click did not close detail');
    process.stdout.write('valid tag linked correctly; details toggle works\n');
  } else if (scenario === 'fallback') {
    if (timeline.children.length === 0) die('fallback: nothing rendered offline');
    const bad = anchors.filter(function (a) {
      return !/\/releases\/tag\/[A-Za-z0-9][A-Za-z0-9._-]*$/.test(a.href);
    });
    if (bad.length > 0) die('fallback: anchor with non-conforming href: ' + bad[0].href);
    if (byId['cl-releases'].textContent === '') die('fallback: stats not populated');
    process.stdout.write('offline fallback rendered ' + timeline.children.length +
      ' releases through the safe path\n');
  } else {
    die('unknown scenario ' + scenario);
  }
  process.exit(0);
}).catch(function (e) {
  console.error('harness: ' + (e && e.stack || e));
  process.exit(1);
});
HARNESS_EOF

b_pass() { pass "B: $1"; }
b_fail() { fail "B: $1"; }

for scenario_name in xss valid fallback; do
  label=""
  case "$scenario_name" in
    xss) label="mocked <script>/quote payload renders inert (no SCRIPT nodes, no anchor for hostile tag)" ;;
    valid) label="validated tag produces the release link; details toggle works" ;;
    fallback) label="offline fallback renders known releases through the safe path" ;;
  esac
  if node "$TMP/harness.cjs" "$CHANGELOG" "$scenario_name" >"$TMP/out-$scenario_name.txt" 2>&1; then
    b_pass "$label"
  else
    b_fail "$label"
    sed 's/^/      /' "$TMP/out-$scenario_name.txt"
  fi
done

echo "┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄"
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
