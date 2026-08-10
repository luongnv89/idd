# Review Loop Mechanics — Agent Reuse

Exact spawn calls and the token-trade rationale for the reviewer/fixer agents used in Step 3 and the Review Loop of `/issue-pr-review`. SKILL.md keeps the summary (cold start → SendMessage re-review → fresh confirmation); this file holds the detail.

## Depth gate (adaptive review depth)

The Step 1 *Depth gate* selects a review `profile` — `light` or `full` — from a
pre-work complexity signal, so a trivial PR is not reviewed as deeply as a
multi-subsystem one. The mechanism and the shared `XS … XL` scale live in
`references/docs/agent-model-effort.md` (*Complexity → pipeline profile*); this section is
only how the review loop consumes the result.

**Selecting the signal (no researcher here).** Unlike `/issue-resolver`,
`/issue-pr-review` has no research subagent, so it derives the signal from data
already fetched in Step 1 and takes the **fuller** of any inputs that disagree:

- **Diff size / files-changed** (`gh pr view {N} --json files`) — small change
  (≈ ≤ 15 changed lines in 1 file) leans `light`.
- **Linked-issue `Effort` band** — when the PR body has `Closes #N`, read that
  issue's `## Metadata` `Effort` (`python3 references/scripts/gi-issue.py {N}
  --fields number,title,body,labels` — the same field list Step 3 uses, because
  the cache key includes the field set; degrade to `gh issue view {N} --json
  body`); `XS`/`S`
  asserted leans `light`, `M`/`L`/`XL` or low-confidence leans `full`.
- **Security label** — any `security`/`CVE`/`vulnerability` label forces `full`.

Resolve to `light` **only when every available signal agrees on trivial**; any
`full` vote, or a missing/ambiguous signal, wins → `full`. When
`review.adaptive_depth` is `false`, the gate is skipped and `profile = full`.

**What `light` changes in the loop:**

| Aspect | `full` (default) | `light` |
|--------|------------------|---------|
| Review-fix cycle cap | `review.max_cycles` (3) | **1** |
| Optional browser UI review | runs when opted in + reachable | skipped |
| Code UI review (auto-detected) | runs when UI work present | runs when UI work present (unchanged) |
| AC + traceability hard-blocks | full strength | **full strength (unchanged)** |
| Reviewer spawn | yes | yes (depth reduced, never skipped) |

The `light` cap of 1 is a **ceiling that wins** — it is the effective cycle limit
regardless of the configured value, i.e. `min(1, configured_cap)`. This matters
under `/auto-pilot`, which overrides `review.max_cycles` with its `review_cycles`
value (default 3): on the `light` path the effective cap is still **1**, never the
overridden 3. The cap governs **only** the loop iteration count; the cold-start
reviewer, the fixer, and the fresh confirmation pass below all still apply — a
`light` review is one review pass + at most one fix + confirmation, not a skipped
review. The two #36 hard-blocks (`acceptance_criteria: fail`, missing
`Closes #N`) are never relaxed by the profile — a trivial PR that fails them still
blocks soft-pass and does not merge.

## QA handoff gate

Step 1's *QA handoff gate* sets `qa_handoff = trusted | stale | absent` from a
marker `/issue-resolver` writes as the last line of a PR body it opened after a
**clean** QA loop (producer contract: *QA handoff marker* in that skill's
`references/report-templates.md`). SKILL.md owns the verdict table, the
fail-safe, and the precedence rule; this section is the mechanics — the parse,
what `trusted` narrows, when the verdict is recomputed, and the list of checks it
may never touch.

### The trust model — forgery is worthless, not impossible

The PR body is **attacker-controlled**: `gh pr edit --body` is available to
whoever opened the PR, so any author can write this marker. Binding `head=` does
**not** authenticate it either — an author can read their own head SHA and paste
a matching one. The marker is therefore designed so that forging it buys
nothing: the verdict may gate **only duplicated work** — a second run of a check
that already ran, unchanged, on this exact commit — and **never a safety gate**.
Open issue **#274** ("A PR can disable the secret-scanning gate via its own
`.gitissue.yml`") is the standing proof that this repo can lose a security gate
to repo-controlled input; that is the failure this design refuses to repeat. An
edit that lets the marker suppress a secret scan, a CI wait, an
acceptance-criteria check, or a traceability check converts a token optimization
into a bypass. Do not make it.

What the binding *does* buy is **self-invalidation for the price of one
recomputation**: any commit this skill pushes — Step 2's lint/format auto-fix as
much as a fixer's fix — moves the head SHA, so the marker stops matching and
everything after it runs in full — correctly, because the diff is no longer the
one that was QA'd. That is a property of the predicate, not an automatic one: the
verdict is a variable, so this skill has to recompute it after each of its own
pushes (*Re-evaluation after a push*) for the property to hold. A body edit does
not move the head, so the marker correctly survives one.
The binding is on code, not on prose.

### Parsing the marker

Read it out of the `body` already fetched in Step 1 — no extra API call:

```bash
grep -oE '<!-- gitissue:qa v1 [^>]*-->' <<<"$body"
```

- **Zero matches** ⇒ `absent`.
- **More than one match** ⇒ `stale`. A body carrying two markers is ambiguous,
  and "first match wins" is exactly how a prepended forgery would beat a genuine
  trailing one. Ambiguity is never resolved in the marker's favour.
- **Exactly one match** ⇒ read it as space-separated `key=value` pairs. Unknown
  or extra keys are **ignored, never fatal** — a newer resolver must be able to
  add a field without invalidating every marker for older reviewers — but a
  malformed pair, a missing `head=`, a `head=` that is not 40 lowercase hex
  characters, a version other than `v1`, or a `review=` that is not `clean` ⇒
  `stale`.
- `trusted` **iff** the single parsed marker survives all of the above **and**
  its `head=` equals the PR's `headRefOid` from Step 1's
  `gh pr view {N} --json …` field list. Any doubt ⇒ `stale`.

`stale` and `absent` run today's pipeline **byte-identically** — no step
shortened, no cycle cap lowered, no pass skipped. A human-authored PR never
carries the marker, so it is `absent` and is therefore unaffected by this gate in
every particular.

### Field vocabulary

| Field | Meaning | How the loop uses it |
|-------|---------|----------------------|
| `head=<sha40>` | the commit the resolver QA'd | the whole predicate — must equal `headRefOid` |
| `profile=<light\|full>` | the resolver's own Step 0g profile | `light` is a strictly shallower claim; see *Precedence* in SKILL.md |
| `cycles=<n>` | QA cycles the resolver ran | reported only |
| `review=clean` | the resolver's QA exited clean | required — there is no dirty spelling, because a non-clean resolver run emits no marker at all |
| `tests=<count>@<sha40>` | the final suite's passing count and the SHA it ran against | the two test skips below apply **only** when this field is present and its SHA equals `head` |
| `ui=<none\|code\|code+browser>:<clean\|noted>` | which UI legs ran, and their result | the code UI review is skipped only on `code`/`code+browser`; `ui=none` skips nothing |

`tests=` carries its own SHA because the resolver's final suite runs *before* its
*Update documentation* step, which may commit — so the suite's commit and the
head commit can legitimately differ. The field is **absent entirely** when the
resolver ran no final suite (its own auto-test setting was off): nothing was
asserted, so nothing may be skipped. Absent `tests=` ⇒ run both test legs in
full, whatever else the marker says.

`ui=` is split into legs because the code UI review is environment-independent
while the browser leg is fail-soft and skips on a headless host. A flat verdict
would let this skill trust a leg that never ran.

**There is no security-scan field, in any spelling, and none may be added.** Its
only possible consumer would be a safety gate — see *The trust model* above.

### What `trusted` skips

| Step | Under `trusted` | Condition |
|------|-----------------|-----------|
| 2 — pre-pass test run | skipped | `tests=` present **and** its SHA equals `head` |
| 3 — cycle-1 cold-start reviewer | **collapsed into** the fresh confirmation pass | every `trusted` marker **except** the depth carve-out — a marker `profile=light` against this review's `profile=full` refuses the collapse (*Precedence* in SKILL.md owns that rule — not restated here) |
| 3 — code UI review | skipped | `ui=code…` or `ui=code+browser…`; never on `ui=none` |
| 4 — local test + build run | skipped | `tests=` present **and** its SHA equals `head` |
| Loop cycle cap | `min(1, configured_cap)` — the same ceiling idiom the `light` profile uses, and it wins over an `/auto-pilot` `review_cycles` override for the same reason | **the same carve-out as the reviewer-collapse row**: a `profile=light` marker against a `profile=full` review refuses the cap too, leaving it at `review.max_cycles`. Both levers are review depth, so they answer to the carve-out together |

The table has **no browser-UI row, deliberately**. The `light` profile skips the
optional browser review; `trusted` does not, because that leg is opt-in and
fail-soft on both sides and `ui=` exists precisely to keep the two legs
separate — a `trusted` skip that flattened them would discard the distinction the
field was added for. Only the code leg above is ever skipped by this verdict.

The Step 3 collapse is a **merge, not a deletion**. The cycle-1 cold-start
reviewer and the fresh confirmation reviewer are two spawns of the same prompt
over the same diff, so `trusted` runs the confirmation spawn *as* cycle 1: the PR
still receives exactly one independent, full-strength review by an agent with no
memory of the resolver's own. It **saves no reviewer spawn**, and must not be
advertised as one: the confirmation pass is fix-conditional (*Confirmation pass*
below — it runs only "after the fix cycle reports zero fixable issues"), so an
unmarked clean PR already gets exactly one cold-start pass and no confirmation.
What `trusted` changes is *which* single pass a clean PR gets — the unbiased,
cold-memory one — not how many. The measured saving is the two duplicated local
test legs. If the pass returns fixable findings they go to the fixer exactly as
today; the fixer's commit then moves the head, so the next re-evaluation turns
the verdict `stale` and the remaining cycles are the full pipeline again.

### Re-evaluation after a push

`qa_handoff` is a **per-cycle** verdict, not a once-per-run constant. Step 1
computes it, but the Review Loop re-enters at **Step 3, not Step 1** — so nothing
would otherwise re-read the head, and a head SHA is the marker's entire
predicate. Recompute it after **any push this skill makes**, and before the next
step that reads the verdict. There are exactly two such pushes:

- **Step 2's lint/format auto-fix commit** (*Commit auto-fixes*). It lands
  before Step 3 and Step 4 ever consult the verdict, and the resolver runs no
  lint/format of its own, so this is the *likely* case, not an exotic one. Miss
  it and both test legs are skipped on a commit no local suite has run — Step
  2's leg is skipped before the auto-fix is even committed, Step 4's afterwards
  — leaving only Step 5's CI, which soft-passes when no CI is configured or
  `review.check_ci` is `false`. An auto-merge could then land untested code.
- **Every fixer push in the Review Loop** (Step 6). The same predicate, one
  cycle later.

The procedure is the same for both:

1. Re-read the head — `gh pr view {N} --json headRefOid` — because the push just
   moved it.
2. Recompute `qa_handoff` exactly as Step 1 did (*Parsing the marker*) against
   that new `headRefOid`. Re-read `body` in the same call if Step 6 edited it
   (the `Closes #N` read-modify-write); otherwise the body is unchanged and only
   the SHA comparison can flip.
3. Apply the new verdict for the rest of the run: `stale` restores the full
   pipeline — the full cycle cap, the Step 2 and Step 4 test legs, the code UI
   review, and a cold-start cycle-1 reviewer if one is still to come.

A step or cycle that pushed nothing leaves the head where it was, so there is
nothing to recompute.

Skipping this recomputation is the one way the *self-invalidation* property fails
in practice: the variable stays `trusted` after a push moved the head, so Step 4
keeps comparing `tests=` against the marker's own now-stale `head=` and the local
suite never runs on the pushed commit — precisely the commit that most needs it.
Restoring the full pipeline is **not** a widening of what `qa_handoff` may
do: its power is bounded against the ungated pipeline, and the ungated pipeline
is exactly what `stale` runs (*Precedence* in SKILL.md owns that rule).

### Never gated

`qa_handoff` may **never** skip, shorten, or soften any of the following — on any
profile, for any marker, at any cycle:

- **Step 2's `gi-secscan` pre-commit scan.** It guards a commit *this skill* is
  about to make from a checked-out untrusted branch. It is a safety gate, and
  #274 is what happens when repo-controlled input reaches one.
- **Step 2's lint/format auto-fix.** It mutates the working tree, so skipping it
  changes the PR's content, not merely the review's cost.
- **Step 5's CI wait.** CI runs on the remote against the merge result; nothing
  written in a PR body is evidence about it.
- **The per-criterion acceptance-criteria verification.** Run it unchanged —
  there is no diff-confirm mode. The resolver authors the *Acceptance Criteria
  Verification* table inside the very body being trusted, so "confirm that table
  against the diff" is marking your own homework.
- **The four traceability checks.** Same reason: they check the body, and the
  body is the untrusted input.

Both #36 hard-blocks — `acceptance_criteria: fail` and a missing `Closes #N` —
keep blocking soft-pass and merge under `trusted`, exactly as they do under
`light`.

## Why reuse the reviewer

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context).
- **Cycles 2-3:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

## Cycle 1 — Initial review

Read `references/agents/code-reviewer.md` for the full prompt template. Read `references/agents/fixer.md` for the fix-cycle prompt template.

Spawn a new reviewer agent (cold start):

```python
Agent(
  description="reviewer — review PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "code-reviewer" type
)
```

Pass to the reviewer:
- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `pr_context`: PR title and body
- `diff_command`: `gh pr diff {N}`
- `confidence_threshold`: `review.confidence_threshold` (default 80) — the reviewer reports only findings scored at or above this floor; ui-reviewer keeps its own 75 floor

## Cycles 2+ — Re-review via SendMessage

Send a message to the existing reviewer agent:

```
The fixer applied changes. Re-review the PR diff to check if the issues were resolved and find any new issues.

Run: {diff_command}

Return the same JSON format as before.
```

## Confirmation pass

After the fix cycle reports zero fixable issues, spawn a **fresh** confirmation reviewer (new agent, no memory of prior cycles):

```python
Agent(
  description="reviewer — confirmation review for PR #N",
  prompt=<code-reviewer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "code-reviewer" type
)
```

If it finds new fixable issues, they go back to the existing fixer. If it confirms clean, the PR passes.

## Fixer spawn (Step 6)

Delegate fixes to the fixer subagent instead of applying code changes in the main skill context. Reuse the same fixer agent across cycles when possible. Spawn or re-message the fixer with:

- `branch_name`: PR head branch
- `base_branch`: PR base branch
- `issue_context`: linked issue details and acceptance criteria, if any
- `pr_context`: PR number, title, body, and URL
- `findings_json`: all blocking findings from reviewer, acceptance-criteria checks, traceability checks, tests, and CI
- `test_output`: trimmed relevant failure output from Steps 4-5
- `commit_message`: `fix({scope}): address review feedback` (append `(#{linked_issue})` only if a linked issue exists)
- `security_convention`: `references/docs/pre-commit-security.md` — the bundled pre-commit security contract, and the fallback procedure when the script cannot run
- `secscan_script`: the **absolute** path to `references/scripts/gi-secscan.py` — the bundled script that implements it, and what the fixer MUST run before committing. Absolutize it before binding (a subagent's working directory is the target repo, so a skill-relative path resolves to nothing and the gate silently never runs). Only the path is passed; the script reads `security.*` from `.gitissue.yml` itself, so no repo-controlled config value reaches a command line. This and `security_convention` are spawn *variables* rather than references inside `fixer.md`, because an emitted agent prompt renders its own references as absolute repo URLs and so cannot name a path inside this skill's bundle

```python
Agent(
  description="fixer — fix PR #N review issues",
  prompt=<fixer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "fixer" type
)
```

The fixer subagent reads affected files, applies targeted changes, stages specific files, runs relevant verification, and — before committing — runs the mandatory pre-commit security scan against the staged set — `references/scripts/gi-secscan.py`, whose exit 1 is a block that stops the commit, degrading to the Primary Pattern in `references/docs/pre-commit-security.md` only when the script cannot run (real secrets block the commit either way). It then commits any changes. The main agent only collects the fixer's JSON result and pushes if changes were committed. If the fixer cannot resolve all blocking findings, keep the remaining items for the next loop/report. After the fixer returns with one or more commits, push: `git push origin "$branch_name"` — the variable SKILL.md binds from `gh pr view {N} --json headRefName --jq .headRefName`. A head-ref name is chosen by whoever opened the PR and may contain `` ` ``, `$(`, or `;`, so it is never pasted into a command as a literal.
