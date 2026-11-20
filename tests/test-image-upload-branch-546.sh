#!/usr/bin/env bash
# test-image-upload-branch-546.sh — /issue-creator uploads images to the
# `issue-assets` branch, never the default branch (issue #546).
#
# The upload used to PUT to the contents API with no `branch` field, so it
# wrote to the default branch, and a protected default branch refused every
# image with 422 "Changes must be made through a pull request".
#
#   T1  behavioural: the Step 2 bash block of the BUILT image-upload.md runs
#       against a stub `gh` that reproduces real gh error behaviour (exit 1,
#       raw error JSON with message/status on stdout, `gh: <msg> (HTTP <code>)`
#       on stderr, --jq applied only on success). Seven scenarios check the
#       call log and outcome; no PUT ever runs without branch=issue-assets.
#   T2  prose pins: the error-messages.md image entries carry the shared lines
#       of image-upload.md's failure block; the API-error entry points to
#       Step 2 of the procedure.
#   T3  prose pins: raw URL examples use /issue-assets/, none use /main/, and
#       the skill text carries no ticket number.
#
# Reads skills/ (build output), so CI runs it after the build step.
#
# Usage: bash tests/test-image-upload-branch-546.sh
# Returns: exit 0 if all checks pass, exit 1 on failure
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/skills/issue-creator/references/image-upload.md"
ERRS="$ROOT/skills/issue-creator/references/error-messages.md"

PASS=0
FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✗ $1"; FAIL=$((FAIL + 1)); }
check() { if eval "$1"; then pass "$2"; else fail "$2"; fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/idd-img546.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

echo "Image upload branch tests (issue #546)"

# ── T1: run the Step 2 block against a stub gh ───────────────────────────────
# The upload block is the fenced bash block that carries the contents-API PUT.
awk '
  /^[[:space:]]*```bash[[:space:]]*$/ { inb = 1; buf = ""; next }
  inb && /^[[:space:]]*```[[:space:]]*$/ { inb = 0; if (buf ~ /--method PUT/) { printf "%s", buf; exit } next }
  inb { buf = buf $0 "\n" }
' "$DOC" > "$TMP/block.sh"
if [ -s "$TMP/block.sh" ]; then
  pass "T1.0: image-upload.md carries the upload bash block"
else
  fail "T1.0: no fenced bash block with the contents-API PUT in image-upload.md"
fi

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: logs each call and mimics real gh on an HTTP error.
printf '%s\n' "$*" >> "$GH_LOG"
jq=""; method=GET; prev=""
for a in "$@"; do
  case "$prev" in --jq) jq=$a ;; --method|-X) method=$a ;; esac
  prev=$a
done
err() { # real gh: exit 1, raw error body on stdout (no --jq), summary on stderr
  printf '{"message":"%s","documentation_url":"https://docs.github.com/rest","status":"%s"}\n' "$2" "$1"
  printf 'gh: %s (HTTP %s)\n' "$2" "$1" >&2
  exit 1
}
ok() { if [ -n "$jq" ]; then printf '%s\n' "$2"; else printf '%s\n' "$1"; fi; exit 0; }
if [ "$1" = repo ] && [ "$2" = view ]; then
  ok "{\"defaultBranchRef\":{\"name\":\"${GH_DEFAULT-main}\"}}" "${GH_DEFAULT-main}"
fi
[ "$1" = api ] || { echo "stub: unexpected gh $*" >&2; exit 2; }
case "$method $2" in
  "GET "*/git/ref/heads/issue-assets)
    case "${GH_REF:-200}" in
      200) ok '{"object":{"sha":"aaa111"}}' aaa111 ;;
      404) err 404 "Not Found" ;;
      409) err 409 "Git Repository is empty." ;;
      *)   err "$GH_REF" "Server Error" ;;
    esac ;;
  "GET "*/git/ref/heads/*) ok '{"object":{"sha":"bbb222"}}' bbb222 ;;
  "POST "*/git/refs)
    case "${GH_POST:-201}" in
      201)    ok '{"ref":"refs/heads/issue-assets"}' refs/heads/issue-assets ;;
      exists) err 422 "Reference already exists" ;;
      422)    err 422 "Validation Failed" ;;
      *)      err "$GH_POST" "Server Error" ;;
    esac ;;
  "PUT "*/contents/*)
    printf 'stdin_bytes=%s\n' "$(cat | wc -c | tr -d ' ')" >> "$GH_LOG"
    url=https://raw.githubusercontent.com/o/r/issue-assets/.github/issue-assets/x.png
    case "${GH_PUT:-201}" in
      201) ok "{\"content\":{\"download_url\":\"$url\"}}" "$url" ;;
      *)   err "$GH_PUT" "Changes must be made through a pull request" ;;
    esac ;;
  *) echo "stub: unexpected gh $*" >&2; exit 2 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
printf '\x89PNG fake image bytes\n' > "$TMP/shot.png"

# run <name> [VAR=value...] — runs the block in a clean shell; sets RC, LOG, OUT.
run() {
  local name=$1; shift
  LOG="$TMP/$name.log"; OUT="$TMP/$name.out"; : > "$LOG"
  { printf 'owner=o repo=r image_path=%q original_filename=shot.png\n' "$TMP/shot.png"
    cat "$TMP/block.sh"; } > "$TMP/$name.sh"
  set +e
  env "$@" GH_LOG="$LOG" PATH="$TMP/bin:$PATH" bash "$TMP/$name.sh" > "$OUT" 2>&1
  RC=$?
  set -e
}
calls() { grep -c -- "$1" "$LOG" || true; }
put_ok() { [ "$(calls 'method PUT')" -ge 1 ] && ! grep -- '--method PUT' "$LOG" | grep -qv -- '-f branch=issue-assets'; }
no_put() { [ "$(calls 'method PUT')" -eq 0 ]; }
no_post() { [ "$(calls 'method POST')" -eq 0 ]; }
url_out() { grep -q 'raw.githubusercontent.com/o/r/issue-assets/' "$OUT"; }
no_url() { ! grep -q 'raw.githubusercontent.com' "$OUT"; }
ALL_LOGS=()

run exists GH_REF=200; ALL_LOGS+=("$LOG")
check 'put_ok && no_post && [ "$RC" -eq 0 ] && url_out && grep -q "stdin_bytes=[1-9]" "$LOG"' \
  "T1.1: branch exists → PUT with branch=issue-assets and stdin content, no POST, URL produced"

run create GH_REF=404; ALL_LOGS+=("$LOG")
check 'put_ok && [ "$RC" -eq 0 ] && url_out \
  && [ "$(grep -n "" "$LOG" | grep -E "git/ref/heads/issue-assets|repo view|git/ref/heads/main|method POST|method PUT" | cut -d: -f1 | tr "\n" " ")" = "1 2 3 4 5 " ] \
  && grep -q "git/refs --method POST .*-f ref=refs/heads/issue-assets -f sha=bbb222" "$LOG"' \
  "T1.2: branch missing (404) → default branch, its tip, POST refs from the tip, then PUT with branch"

run race GH_REF=404 GH_POST=exists; ALL_LOGS+=("$LOG")
check 'put_ok && [ "$RC" -eq 0 ] && url_out' \
  "T1.3: POST 422 \"Reference already exists\" (concurrent run) → still PUT with branch"

run empty409 GH_REF=409; ALL_LOGS+=("$LOG")
check 'no_post && no_put && [ "$RC" -ne 0 ] && grep -q "empty repository" "$OUT"' \
  "T1.4: GET 409 (empty repository) → no POST, no PUT, failure with the empty-repository reason"

run emptydef GH_REF=404 GH_DEFAULT=; ALL_LOGS+=("$LOG")
check 'no_post && no_put && [ "$RC" -ne 0 ] && grep -q "empty repository" "$OUT"' \
  "T1.4b: empty default branch name → no POST, no PUT, failure with the empty-repository reason"

for code in 403 500; do
  run "get$code" GH_REF=$code; ALL_LOGS+=("$LOG")
  check 'no_post && no_put && [ "$RC" -ne 0 ] && no_url' \
    "T1.5: GET $code → failure path, no POST, no PUT"
done

for p in 422 500; do
  run "post$p" GH_REF=404 GH_POST=$p; ALL_LOGS+=("$LOG")
  check '[ "$(calls "method POST")" -eq 1 ] && no_put && [ "$RC" -ne 0 ] && no_url' \
    "T1.6: POST $p (not already-exists) → failure path, no PUT"
done

run putfail GH_REF=200 GH_PUT=422; ALL_LOGS+=("$LOG")
check 'put_ok && [ "$RC" -ne 0 ] && no_url && ! grep -q "download_url=.*message" "$OUT"' \
  "T1.7: PUT fails (exit 1 + error JSON) → failure path, no URL produced"

if cat "${ALL_LOGS[@]}" | grep -- '--method PUT' | grep -qv -- '-f branch=issue-assets'; then
  fail "T1.8: a PUT ran without -f branch=issue-assets"
else
  pass "T1.8: no PUT in any scenario runs without -f branch=issue-assets"
fi

# ── T2: error-messages.md entries share the failure block's lines ───────────
fblock="$(awk '/^## Failure handling/{on=1;next} on&&/^```$/{if(in_b)exit; in_b=1;next} in_b' "$DOC")"
prefix="$(printf '%s\n' "$fblock" | sed -n '1s/^\(⚠ Image upload failed: {filename} —\).*/\1/p')"
line2="$(printf '%s\n' "$fblock" | sed -n '2s/^ *//p')"
tip="$(printf '%s\n' "$fblock" | sed -n '3s/^ *//p')"
check '[ -n "$prefix" ] && [ "$line2" = "Issue created without embedded image." ] && [ "${tip#Tip: }" != "$tip" ]' \
  "T2.0: image-upload.md failure block has the prefix, created-without line and Tip line"

entry() { awk -v h="### $1" '$0==h{on=1;next} on&&/^##/{exit} on' "$ERRS"; }
for name in "Image file not found" "Image upload API error"; do
  e="$(entry "$name")"
  check 'printf "%s\n" "$e" | grep -qF -- "$prefix" && printf "%s\n" "$e" | grep -qF -- "$line2" && printf "%s\n" "$e" | grep -qF -- "$tip"' \
    "T2.1: '$name' carries all three shared failure-block lines"
done
for name in "Unsupported image format" "Image too large"; do
  e="$(entry "$name")"
  check 'printf "%s\n" "$e" | grep -qF -- "$prefix" && printf "%s\n" "$e" | grep -qF -- "$line2"' \
    "T2.2: '$name' carries the failure prefix and the created-without line"
done
api="$(entry "Image upload API error")"
check 'printf "%s\n" "$api" | grep -E "^ *To fix:" | grep -q "Step 2 of references/image-upload.md"' \
  "T2.3: the API-error entry's To fix line points to Step 2 of references/image-upload.md"
check 'printf "%s\n" "$api" | grep -q "issue-assets"' \
  "T2.4: the API-error entry covers creating the issue-assets branch"

# ── T3: raw URL form, AC4 documentation, no ticket numbers ───────────────────
check 'grep -qF "https://raw.githubusercontent.com/{owner}/{repo}/issue-assets/.github/issue-assets/{filename}" "$DOC"' \
  "T3.1: image-upload.md documents the raw URL form on the issue-assets branch"
check '[ "$(grep -o "raw.githubusercontent.com/[^)]*" "$DOC" | grep -cv "/issue-assets/.github/issue-assets/")" -eq 0 ] \
  && ! grep -q "raw.githubusercontent.com/[^/]*/[^/]*/main/" "$DOC"' \
  "T3.2: every raw URL example uses /issue-assets/, none uses /main/"
check 'grep -q "storage branch" "$DOC" && grep -q "never a work branch" "$DOC"' \
  "T3.3: issue-assets is stated as a storage branch, never a work branch"
check 'grep -q "default branch never receives image commits" "$DOC"' \
  "T3.4: the default branch never receives image commits"
check '! grep -rqE "#546|issue 546" "$ROOT/src/skills/issue-creator" "$ROOT/skills/issue-creator"' \
  "T3.5: the issue-creator skill text carries no ticket number for this fix"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
