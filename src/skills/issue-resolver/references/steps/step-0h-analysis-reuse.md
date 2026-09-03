# /issue-resolver — Step 0h: Analysis reuse gate

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 0h — Analysis reuse gate <!-- a:rs-step0h-gate -->

**The single home of the freshness predicate.** `/issue-analysis` writes
`.gitissue/analysis-<N>.json` carrying everything Steps 1–2 would otherwise
re-derive — extraction, affected files, options, recommendation, complexity and
risk — pinned to the commit it ran against. This gate decides whether that
artifact is still true, so an analyze-then-resolve sequence on an unchanged tree
researches the codebase **once** instead of twice. Every other mention of a
*fresh* analysis in this skill — `references/report-templates.md` (*Lifting the
Decision Record*) and the bug-repro mirror in *Step 3* below — defers to this
section. Do not restate or re-derive a freshness rule anywhere else.

Runs after *0g — Complexity gate*, before *Step 1 — Research*. It sets exactly
one state variable:

```
analysis_reuse = fresh | stale | absent
```

| Value | When | Effect |
|-------|------|--------|
| `fresh` | every condition below holds | Step 1 runs the seeded verify-first pass; Step 2 skips the synthesizer |
| `stale` | the file exists but any condition fails | today's full pipeline, unchanged |
| `absent` | no file, or it does not parse as JSON | today's full pipeline, unchanged |

`stale` and `absent` are distinguished for the operator's benefit only — they
take the identical code path, which is the pipeline that already exists.

When `resolve.adaptive_effort` is `false`, **skip this gate**: set
`analysis_reuse = stale` and continue. That key already pins the pipeline to
`full`, and reuse is the same class of saving, so the one key disables both.
**No new config key is introduced.**

### The predicate — five conditions, all must hold <!-- a:rs-step0h-predicate -->

`{base}` is **this run's synced base** — the branch the mandatory Repo Sync
rebased onto, or the `origin/${base}` that `git worktree add` forked from. Never
a bare `HEAD`: resolutions run in parallel worktrees (issue #260), where `HEAD`
can point at an unrelated branch and an ancestry test against the wrong tip
passes silently.

**Resolve the artifact against the original checkout, never against this run's
workspace.** `.gitissue/` is gitignored, so a *0e* worktree never contains the
analysis — a bare relative `.gitissue/…` path evaluated there answers `absent` on
every interactive run and the gate silently never fires. `git rev-parse
--git-common-dir` points back at the original checkout's `.git` from inside a
linked worktree and is this repo's own `.git` on the in-place path, so it names
the same directory *0e* called `repo_root`. The **base ref** is unaffected: it
stays this run's synced base. Conditions 2–5 are plain commands: a non-zero exit
from any of them ⇒ `stale`.

In the block below `{N}` is the issue number **substituted by the caller**, as
everywhere else in this skill; `$origin_root` and `${base}` are the only real
shell variables.

```bash
# The analysis artifact lives in the ORIGINAL checkout, not in a 0e worktree.
# `cd`+`pwd` absolutizes --git-common-dir, which is relative (`.git`) in place.
origin_root="$(dirname "$(cd "$(git rev-parse --git-common-dir)" && pwd)")"
analysis="$origin_root/.gitissue/analysis-{N}.json"
base_ref="origin/${base}"      # this run's synced base — never a bare HEAD

# 1. Exists and parses as JSON — else `absent`. Never fatal: having no analysis
#    is the normal case, and a corrupt one is a cache problem, not a user error.
[ -f "$analysis" ] || analysis_reuse=absent
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$analysis" || analysis_reuse=absent

# 2. `git_state.commit_sha` is present, is a full 40-character SHA (the sibling
#    `commit_sha_short` is display-only and is never accepted here), and names a
#    commit this repository actually has.
sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("git_state",{}).get("commit_sha",""))' "$analysis")"
[ "${#sha}" -eq 40 ]                    # a full SHA, never commit_sha_short
case "$sha" in *[!0-9a-f]*) false ;; esac    # lowercase hex only
git cat-file -e "${sha}^{commit}"       # a commit this repo actually has

# 3. That commit is an ancestor of this run's synced base (exit 0 = ancestor).
git merge-base --is-ancestor "$sha" "$base_ref"

# 4. Nothing the analysis predicted has moved since: the changed paths and the
#    analysis's own `affected_files[].path` must not intersect.
git diff --name-only "$sha".."$base_ref"    # ∩ affected_files[].path ⇒ must be EMPTY

# 5. The issue has not been edited since the analysis ran: the `updatedAt`
#    captured in *0a* is not newer than the `issue.updatedAt` the analysis
#    recorded. Both sides are GitHub's own clock — never compare against the
#    analysis `timestamp`, which is the *local* capture clock, so skew between
#    the two could read an edited issue as unedited. Compare as ISO-8601
#    instants, not as raw strings; a missing or unparsable value on either
#    side fails the condition.
```

**Condition 5 carries a trap: *0d — Auto-normalize* rewrites the issue body with
`gh issue edit`, which bumps `updatedAt`.** Evaluated against a post-0d value,
every first-normalized issue would report stale and this gate would silently
never fire. *0a* runs **before** 0d and already fetches the issue, so it captures
`updatedAt` in its field list and condition 5 is evaluated against that
**pre-normalization** value — never a re-fetch taken after 0d.

### Fail-safe: any doubt is `stale` <!-- a:rs-step0h-failsafe -->

A missing key, a short or unknown SHA, an unparsable timestamp, a `git` command
that errors for any reason, or any condition that cannot be evaluated ⇒ `stale`
⇒ today's full pipeline, unchanged. The gate may only skip work it has
positively proven redundant. This default is what keeps a wrong answer cheap:
the fallback is the pipeline that runs today.

Surface the decision as one line so the saving is auditable:

```
○ Analysis reuse: fresh (analysis-42.json @ 01afdc5) — seeding research
○ Analysis reuse: stale (base moved: src/auth/middleware.py) — full pipeline
○ Analysis reuse: absent — full pipeline
```

### What `fresh` unlocks <!-- a:rs-step0h-unlocks -->

| Step | `fresh` behavior |
|------|------------------|
| 1 — Research | Seeded verify-first pass — *Step 1 — Research → `reuse`* |
| 2 — Plan | Synthesizer skipped, options lifted — *Step 2 — Plan → `reuse`* |
| 3–5 | **Unchanged.** Reuse never touches implementation, QA, or delivery. |

`fresh` composes with `profile = light`, and the precedence between them is
stated once, here. Both skip the Step 2 synthesizer spawn, but they yield
different plans, so **when both apply, `reuse` wins Step 2**: real lifted options
beat a synthesized minimal plan. Step 2 lifts `options[]` from the analysis, the
Decision Record's *Options rejected* carries the analysis's own reasons, and
`approval_gate: comment-and-wait` presents all three options. The `light` path's
option-less direct plan — and its silent approval gate — applies only to a
`light` run **without** a `fresh` analysis. Step 1 runs the narrower of the two
passes. Both keep the *Verify not already resolved* phase in full.

Because the gate reads only an on-disk artifact and this run's own base, it
needs no change from a caller: `/auto-pilot`'s explicit-list mode, which runs
`/issue-analysis` and then `/issue-resolver` back to back on the same tree, gets
the reuse purely by having written the file.
