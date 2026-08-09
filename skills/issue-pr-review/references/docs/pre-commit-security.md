<!-- Generated from /docs/pre-commit-security.md. Do not edit. Edit source and run ./scripts/build.sh. -->
# Pre-Commit Security Conventions

Standard convention for scanning a working tree for secrets, credentials, and risky artifacts before any IDD skill stages, commits, or pushes changes. Centralizing this here ensures every skill that runs `git add` / `git commit` / `git push` applies the same gate — once a secret reaches a public branch the leak is permanent, so the check must never be skipped or copy-pasted into a divergent variant.

The checks below are adopted from the `auto-push` skill and codified here as the canonical reference for this project.

> **Runtime digest (generated).** This is the normative subset of [pre-commit-security.md](https://github.com/luongnv89/idd/blob/main/docs/pre-commit-security.md) that skills read at run time. The sections a skill run never acts on live in the full document.

## Why This Matters

A leaked API key, private key, or `.env` file pushed to a public remote is a security incident: the key must be rotated, the history must be rewritten, and the leak window must be assumed exploited. The fix is mechanical — scan staged changes for known secret patterns and refuse to proceed when one is detected. This document is the single source of truth; skills should link here rather than copy-pasting the snippet, so the rules can be tightened in one place.

---

## Script Path (preferred)

The gate is shipped as a deterministic script, `references/scripts/gi-secscan.py`. Prefer it everywhere it is available: the rules below are ~90 lines of bash, and a gate re-derived by hand at four or five commit sites per issue eventually gets re-derived slightly wrong — in the one direction (a blocking check that stops blocking) nobody notices until after the leak.

Skills that bundle it invoke the emitted copy, never a source-tree path:

```bash
# Exactly one input: --staged (index blobs), --working-tree (files on disk),
# --range BASE (every blob in BASE..HEAD, commit by commit — a secret added and
# then removed inside the branch is still pushed), --files-from -, or explicit
# paths. In auto mode export IDD_AUTO_MODE=1 first.
# Run from the repo root: the script reads the security.* block of
# .gitissue.yml itself. Never interpolate a config value into this command.
python3 references/scripts/gi-secscan.py --staged
```

It applies the same five rules in the same order and prints one JSON verdict on stdout (`verdict`: `clean`, `warn`, or `block`), with the `✗`/`⚠`/`○` lines on stderr. A repository's `security.*` extensions (documented in the configuration schema) apply because the script reads the `security:` block of `.gitissue.yml` itself. **Never pass a config value on the command line** — not as `--config-json`, not as `--allow-pattern`. `.gitissue.yml` is repository-controlled and `/issue-pr-review` runs with a pull request's branch checked out, so a value interpolated into a quoted shell word can close the quote and append a command that executes on the reviewer's machine at the exact moment the gate runs. Only the four documented scalars are read, so this is not a second copy of the configuration resolver.

**Exit contract — the block code is a verdict, not a failure:**

| Exit | Meaning | Caller behavior |
|------|---------|-----------------|
| `0` | `clean`, or `warn` with nothing blocking | Proceed. On `warn`, apply the *Mode Contract* below — the script never prompts (it does not own the terminal, and the path list may be arriving on its stdin); `confirm_required` is that decision pre-computed. |
| `1` | `block` — a real secret was found | **Stop.** Never treat this as the degrade path: degrading past a real secret is the single outcome this gate exists to prevent. Report the path from `blocking[]`. |
| `2` | Usage error — a malformed invocation, or a script path that did not resolve (`python3` returns 2 for a file it cannot open) | Fix the invocation where you control it. A caller that cannot tell the two apart treats it as **cannot complete**: fall back to the *Primary Pattern* below. A scan that never ran is never a scan that passed. |
| `3` | Invalid input — a `security.*` value of the wrong type, or a `security.*` regex that does not compile | **Stop.** A scan configured wrongly has not run, so its silence means nothing. |
| `4` | Cannot complete — no file list, `git` unavailable, or a declared byte source that could not be read | Print `⚠ gi-secscan unavailable — running the documented scan` and fall back to the *Primary Pattern* below. |

The file being **absent from the bundle** is a different failure: a broken install, not a degrade, and the skill stops with its `✗ Missing bundled dependency` block.

---

## Primary Pattern: Pre-Commit Scan

This is the canonical statement of the rules, and the **documented fallback** for the script above — run it verbatim when `gi-secscan.py` cannot run (no `python3`, exit `2`, exit `4`) and in any context that does not bundle the script. The script and this block implement the same five **rules**; when they disagree about a rule, this document is the specification and the script is the bug.

They differ in what each can *read*, never in what counts as a secret, and both differences favour the script — this one, and the quoted-path limitation noted inside the block below. This block (and rule 3's `stat`) reads the file on disk; for a **staged** set those are not the bytes being committed — `git add` a key, edit it out, and the file reads clean over a blob that still carries it. `gi-secscan.py --staged` reads the index blob and is the stronger of the two: prefer it wherever it runs.

Every skill that runs `git add`, `git commit`, or `git push` MUST execute one of the two against the staged set (or the about-to-be-staged set) before proceeding — never neither, and never a weaker check improvised inline.

```bash
# Pre-commit security scan — canonical procedure (see surrounding prose).
# Inputs: $files = newline-separated list of paths the skill is about to stage,
#         commit, or push. If empty, derive it — and derive it correctly:
#           staged:       git diff --cached --name-only
#           working tree: git status --porcelain | sed 's/^...//; s/^.* -> //'
#         Do NOT use `awk '{print $2}'` here. On a rename (`R  old -> new`) it
#         yields the *old* path, which no longer exists, so the new file — the
#         one actually being committed — is never scanned. It also truncates any
#         path containing a space.
#         Residual limitation of the shell form: it reads the file on disk, not
#         the staged blob. See the paragraph above this block — prefer
#         gi-secscan.py --staged, which reads the index.
#         Residual limitation of any line-based form: git still quotes a path
#         containing a space or a non-ASCII byte, and the quoted string names no
#         file, so its contents go unscanned. That is not fixable in a `while
#         read` loop, and it is one of the reasons gi-secscan.py exists — it
#         reads `-z` output, where nothing is ever quoted. Prefer the script.
secrets_found=0
warnings=()

# 1. Block: secret-bearing filenames.
secret_patterns='(^|/)\.env($|\..+$)|\.key$|\.pem$|(^|/)credentials\.json$|(^|/)secrets\.ya?ml$|(^|/)id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if printf '%s\n' "$f" | grep -E -q "$secret_patterns"; then
    echo "✗ Secret-bearing file staged: $f"
    secrets_found=1
  fi
done <<< "$files"

# 2. Block: real API-key values inside text files.
#    Distinguish placeholders ('your-...', 'xxx', 'placeholder', '<...>', '${...}')
#    from real keys via known prefixes.
realkey_patterns='(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|gho_[A-Za-z0-9]{30,}|ghs_[A-Za-z0-9]{30,}|ghu_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  # Skip binary files.
  file --mime "$f" 2>/dev/null | grep -q 'charset=binary' && continue
  # -q, not -n: printing the match would copy the secret into the terminal,
  # the transcript, and quite possibly a PR comment — a second leak on top of
  # the first. gi-secscan.py redacts for the same reason.
  if grep -E -q "$realkey_patterns" "$f" 2>/dev/null; then
    echo "✗ Real API key detected in: $f"
    secrets_found=1
  fi
done <<< "$files"

# 3. Warn: large files (>10 MB) without Git LFS.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$size" -gt 10485760 ]; then
    warnings+=("⚠ Large file (>10 MB) without LFS: $f")
  fi
done <<< "$files"

# 4. Warn: build artifacts and temp files (gitignore hygiene).
junk_patterns='(^|/)(node_modules|dist|build|__pycache__|\.venv)(/|$)|\.pyc$|(^|/)(\.DS_Store|thumbs\.db)$|\.swp$|\.tmp$'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if printf '%s\n' "$f" | grep -E -q "$junk_patterns"; then
    warnings+=("⚠ Build artifact / temp file staged: $f — add to .gitignore")
  fi
done <<< "$files"

# 5. Warn: pushing directly to a protected branch.
branch="$(git rev-parse --abbrev-ref HEAD)"
case "$branch" in
  main|master|production|release) warnings+=("⚠ On protected branch: $branch — confirm push is intentional") ;;
esac

# Report and decide.
if [ "$secrets_found" -eq 1 ]; then
  cat <<'EOF'

✗ Pre-commit security scan blocked the commit — secrets detected.

  To fix:  remove or rotate the offending value, then re-stage the file.
           If the match was a false positive, replace the literal with a
           placeholder (your-key, xxx, <your-key>, ${YOUR_KEY}) and rerun.
  Docs:    pre-commit-security conventions reference

EOF
  exit 1
fi

if [ "${#warnings[@]}" -gt 0 ]; then
  printf '%s\n' "${warnings[@]}"
  # Auto mode: log and proceed. Interactive mode: prompt.
  # Skills set IDD_AUTO_MODE=1 when invoked with --auto (or by /auto-pilot).
  if [ "${IDD_AUTO_MODE:-0}" = "1" ]; then
    echo "○ Warnings logged — proceeding (auto mode)."
  else
    printf "Proceed anyway? [y/N] "
    read -r reply
    case "$reply" in
      y|Y|yes|YES) echo "○ Continuing despite warnings." ;;
      *) echo "✗ Stopped — resolve the warnings or rerun and confirm."; exit 1 ;;
    esac
  fi
fi
```

### Behavior Notes

- **Real keys vs. placeholders.** Real-key detection is gated on prefix patterns (`sk-proj-`, `sk_live_`, `AKIA`, `ghp_`, `gho_`, `ghs_`, `xox[abp]-`, `glpat-`, `AIza...`) plus length, so common placeholders (`your-api-key`, `xxx`, `placeholder`, `<your-key>`, `${VAR}`) do not match. When extending the pattern, prefer **prefix + length** over **identifier + value** — the latter false-positives on docstrings and tests.
- **Binary skip.** Real-key scanning skips files whose MIME charset is `binary`. Without this, scanning a large image or PDF burns time and can false-positive on encoded bytes.
- **Working set.** The scan operates on the file list the skill is about to stage/commit/push. Pre-stage skills (e.g., `implementer.md`'s atomic-commit step) pass the file list explicitly. Post-stage skills (e.g., `issue-pr-review` Step 2 auto-fix) fall back to `git diff --cached --name-only`.
- **Exit code.** Real secrets exit `1` and stop the skill. Warnings print and either prompt the user (interactive mode) or log-and-continue (auto mode); see *Mode Contract* below.
- **`.gitignore` hygiene.** When a warning fires for a build artifact (`node_modules/`, `dist/`, etc.), the user is told to add it to `.gitignore` rather than the skill rewriting `.gitignore` itself — `.gitignore` edits are too consequential to do silently.

---

## Mode Contract

Both interactive and auto-pilot modes use **the same scan logic**, and both scan paths — `gi-secscan.py` and the Primary Pattern — implement the same contract. Real secrets always block. Warnings differ by mode:

| Signal | Interactive mode | Auto mode (`--auto`) |
|--------|------------------|----------------------|
| Real secret detected (file or value) | `✗` error, stop | `✗` error, stop (auto-pilot does not bypass) |
| Large file (>10 MB) without LFS | `⚠` warn, **prompt for confirmation** | `⚠` warn, log and proceed |
| Build artifact / temp file staged | `⚠` warn, **prompt for confirmation** | `⚠` warn, log and proceed |
| On protected branch (main/master/production/release) | `⚠` warn, **prompt for confirmation** | `⚠` warn, log and proceed |

Real-secret detection is non-bypassable in both modes. If a real secret would block a commit in interactive mode, it blocks the commit in auto mode too — and the auto-pilot loop reports the issue and moves on rather than committing the leak.

In **interactive mode**, when one or more warnings fire, the skill prints them and prompts `Proceed anyway? [y/N]` before running `git commit` or `git push`. A blank or `n` response stops the action; `y` proceeds. In **auto mode**, the prompt is skipped — warnings are logged via `○` and the action proceeds. Auto mode treats warnings the same way it treats blocking labels and other non-fatal risk signals: surfaced, recorded, but not blocking the loop.

---

## Skill-Side Responsibilities

Every IDD skill that runs `git add`, `git commit`, or `git push` MUST:

1. **Run the scan** — `gi-secscan.py` where it is bundled, the Primary Pattern otherwise — against the staged or about-to-be-staged set before each `git commit` and before each `git push`. Skills that batch multiple commits should scan once before each commit, not once per pipeline run.
2. **Cite `pre-commit-security.md` next to the invocation** — even when calling the script, because the document is the script's fallback procedure and its specification. A call site that names only the script leaves an agent with nothing to do on exit `4`. The build's runtime-doc bundler (`scripts/build.py`) picks up bare `pre-commit-security.md` references with the `docs/` prefix automatically, and the shared-script bundler does the same for `gi-secscan.py`.
3. **Honor the mode contract** — the scan reads `IDD_AUTO_MODE` to decide whether warnings need confirmation (interactive) or are logged and passed (auto). Skills invoked with `--auto` (or by `/auto-pilot`) MUST `export IDD_AUTO_MODE=1` before running the scan. Real-secret detection always blocks regardless of mode. The script reports the decision as `confirm_required` and leaves the prompt to the caller; the Primary Pattern prompts inline.
4. **Never skip the scan to avoid a false positive** — if the scan flags a literal that is not a secret (e.g., a fixture, a docstring example, a regex pattern), replace it with a placeholder or move it behind a tested guard. Disabling the scan is not an option.

---

## When the Scan Blocks

| Failure | Cause | Recovery |
|---------|-------|----------|
| `✗ Secret-bearing file staged: <path>` | A filename matched the secret-file pattern (`.env*`, `*.key`, etc.) | Add the path to `.gitignore`, unstage with `git reset HEAD <path>`, and remove from disk if the file is genuinely a secret. If it is a fixture/template, rename so it does not match (e.g., `.env.example`). |
| `✗ Real API key detected in: <path>` | A real-key prefix matched (`sk-...`, `AKIA...`, `ghp_...`, etc.) | **Rotate the key first** (assume the leak window is exploited), then replace the literal in source with a placeholder (`your-key`, `${YOUR_KEY}`, `<your-key>`) and re-stage. If the literal is a fixture or test value, prefix with a non-real marker (`test-`, `fake-`, `example-`) so it no longer matches. |
| `⚠ gi-secscan: …` and exit `4` | `git` was needed and is unavailable, or no file list could be determined | Not a pass — the scan did not run. Print `⚠ gi-secscan unavailable — running the documented scan` and execute the *Primary Pattern* instead. Never proceed on an exit `4` alone. |
| `✗ gi-secscan: security.… is not a valid regex` and exit `3` | A `security.*` extension pattern in `.gitissue.yml` does not compile | Fix the regex (or clear the key) and rerun. A misconfigured scan has not run, so its silence is not a pass. |
| `file: command not found` (no scan output) | `file` is not installed (BSD/macOS coreutils variants) | Install via `brew install file-formula` (macOS) or `apt install file` (Linux). Without `file`, binary files are not skipped — scans run slower but stay correct. |
| `stat: illegal option -- f` or `stat: invalid option -- 'c'` | Platform mismatch (`-f%z` is BSD/macOS, `-c%s` is GNU/Linux) | The snippet falls through both forms with `2>/dev/null`. If both fail, large-file detection is silently skipped — fix by ensuring at least one `stat` form is available. |
| Scan blocks on a value that genuinely is not a key | Real-key prefix matched a coincidental literal (rare but possible with `AKIA...` strings or long base64) | Replace the literal with a placeholder, or wrap the value behind a fixture loader (`os.environ["AWS_KEY"]`) so the literal never appears in source. Disabling the scan is not an option. |

If the scan keeps firing on the same false positive across runs, do not edit the scan to suppress it — fix the source so it stops matching. The scan rules are in this document; if a rule is genuinely wrong, propose an update here so it applies project-wide.

---

## Quick Reference (Copy-Paste Snippet)

For skills that want the minimal form inline:

```bash
# Pre-commit security scan — canonical procedure (see surrounding prose).
# Block real secrets; warn on large files, build artifacts, protected-branch pushes.
files="$(git diff --cached --name-only)"
if printf '%s\n' "$files" | grep -E -q '(^|/)\.env($|\.)|\.key$|\.pem$|credentials\.json$|secrets\.ya?ml$|id_rsa($|\.pub$)|\.p12$|\.pfx$|\.cer$'; then
  echo "✗ Secret-bearing file staged."
  exit 1
fi
realkey='(sk-(proj-)?[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{30,}|xox[abprs]-[A-Za-z0-9-]{10,}|glpat-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{30,})'
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || continue
  file --mime "$f" 2>/dev/null | grep -q 'charset=binary' && continue
  if grep -E -q "$realkey" "$f" 2>/dev/null; then
    echo "✗ Real API key detected in: $f."
    exit 1
  fi
done <<< "$files"
```
