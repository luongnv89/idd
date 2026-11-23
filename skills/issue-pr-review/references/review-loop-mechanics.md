# Review Loop Mechanics — Agent Reuse

Exact spawn calls and the token-trade rationale for the reviewer/fixer agents used in Step 3 and the Review Loop of `/issue-pr-review`. SKILL.md keeps the summary (cold start → SendMessage re-review → fresh confirmation); this file holds the detail.

## Config keys and what they gate

SKILL.md's *Configuration* section names the loader and its degrade path; this is
the full key list — every default value, and what each key does to the pipeline.
It is also the list to read the base branch's `.idd.yml` (else legacy `.gitissue.yml`) against by hand when `gi-config` is
unavailable. Value syntax and validation live in `references/docs/config-schema.md`.

The block reads the default branch's tip by full object id, only from a
`refs/remotes/origin/<base>` that `git show-ref --verify` found: a short or
missing ref could resolve a local branch the PR author named. Run it once, as
one shell command, from the repo root:

```bash
is_oid() { case "$1" in ''|*[!0-9a-f]*) return 1 ;; esac; [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]; }
base="$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)"; base_oid=""
if [ -n "$base" ] && git fetch --quiet origin -- "+refs/heads/${base}:refs/remotes/origin/${base}" \
   && git show-ref --verify --quiet "refs/remotes/origin/${base}"; then
  base_oid="$(git rev-parse --verify --quiet "refs/remotes/origin/${base}^{commit}")"
fi
src="defaults — no .idd.yml at the base"
if ! is_oid "$base_oid"; then date +%s >&2; src=""
else
  out=$( (python3 references/scripts/gi-config.py --ref "$base_oid"; ec=$?; date +%s >&2; exit "$ec") ); ec=$?
  if [ "$ec" -eq 3 ]; then echo "✗ Invalid config at origin/${base} — stop"; src=stop
  elif [ "$ec" -eq 0 ] && printf '%s' "$out" | grep -qF "\"config_source\": \"ref:$base_oid\""; then
    printf '%s\n' "$out"
    f="$(printf '%s' "$out" | grep -oE '"config_file": "[^"]*"' | cut -d'"' -f4)"; src="${f:-$src}"
  else
    echo "⚠ gi-config unavailable — reading .idd.yml by hand"
    for f in .idd.yml .gitissue.yml; do   # the legacy name only when .idd.yml is absent
      git --no-replace-objects rev-parse --verify --quiet "${base_oid}:${f}" >/dev/null || continue
      if git --no-replace-objects show "${base_oid}:${f}"; then src="$f"; else src=""; fi; break
    done
  fi
fi
case "$src" in stop) ;; "") echo "⚠ Review settings: built-in defaults (base branch unreadable)" ;;
  *) echo "○ Review settings: origin/$base @ $base_oid ($src)" ;; esac
```

Exit 3 stops; any other script failure prints the base blob to read against
this table.

| Key (default) | What it gates |
|-----|---------------|
| `review.max_cycles: 3` | Cycle cap for Steps 3–6. Three LLM cycles suffice once the script pre-pass has handled the mechanical issues. Step 1's `light` profile and `qa_handoff = trusted` each cap it at `min(1, configured_cap)`. |
| `review.adaptive_depth: true` | Scales review depth to the PR's complexity (*Depth gate*). When `false`, every PR gets full-depth review — `profile` is pinned to `full` — and the *QA handoff gate* is skipped with `qa_handoff = absent`. |
| `review.auto_merge: false` | Whether a clean PR is merged — defined once, in SKILL.md *Step 7 → Merge rule*. |
| `review.merge_method: squash` | The `gh pr merge` flag — `squash`, `merge` or `rebase` — and the method traceability check 4 judges the repo against. Any other value is `✗ Invalid config`: stop, also when reading `.idd.yml` by hand. |
| `review.confidence_threshold: 80` | Minimum confidence for code-reviewer findings; a `constraints` finding is reported at any confidence. The ui-reviewer keeps its own 75 floor and does not read this key. |
| `review.run_tests: true` / `review.check_ci: true` | Enable Step 4 and Step 5. When either is `false` the step reports `○ … skipped` and the soft-pass conjunction treats that leg as satisfied. |
| `review.ignore_ci_billing_failures: false` | `true` makes a terminal Step 5 `fail` non-blocking **at this skill's review gate only**: CI is still polled and reported, Step 6 raises no CI fixable, and the soft-pass conjunction treats the CI leg as satisfied (in strict `soft_pass: false` mode too). `ci_status` still binds as `failed@<sha40>` and the step reports `PARTIAL`. The satisfied leg is **loop exit only**: Step 7's auto-merge gate excludes this path by name — an ignored CI failure is never clean, exactly as pending CI is never clean — so no run merges it, and `/auto-pilot`'s merge gate re-runs its own wait and still refuses. **It does not touch `ci_leg_runnable`** — see below. GitHub exposes no API field naming a billing failure, so it ignores *any* terminal CI failure. |
| `review.ci_poll_interval: 30` / `review.ci_timeout: 600` / `review.test_timeout: 300` | Seconds. The first two are passed to `gi-ci-wait.py` as `--interval` / `--timeout`; the third bounds the Step 4 suite. |
| `review.soft_pass: true` | `true` (default): when zero `action: fix` issues remain and the tests/CI/traceability legs pass, remaining `note` findings and `partial` dimensions are report-only. **`false` (strict):** the same tests/CI gates apply, and in addition every enabled dimension must be `pass` and no `action: "note"` finding may remain — a `partial` dimension or any note blocks a clean result **and blocks merge**. Notes never become fixer inputs (Step 6 fixes only `action: "fix"`), so strict mode surfaces them for manual remediation rather than looping without a fixable action. |
| `review.require_acceptance_criteria_check: true` | `true` (default) gates per-criterion AC verification. When `false`, `acceptance_criteria` reports `disabled` (never `pass`), never blocks soft-pass, and fails the *Merge floor*. |
| `review.require_traceability_check: true` | `true` (default) gates the four traceability checks. When `false`, `traceability` reports `disabled` (never `pass`) and never blocks soft-pass. |
| `review.traceability_exempt_labels: ["refactor", "chore"]` | Labels that exempt a PR from the `Closes #N` hard-fail; the exemption reports `traceability: pass — exempt`. It cannot relax check 4 — a non-`pass` check 4 still stands. Full scope in `verification-checks.md` (*Refactor/chore exemption*). |
| `review.traceability_exempt_pattern: "^\\s*Type:\\s*(refactor|chore)\\s*$"` | Body-line regex granting the same exemption, for PRs that carry the type in the body rather than as a label. |
| `review.ui_review.browser_review: "ask"` | `"false"` \| `"ask"` \| `"true"` — the optional browser (screenshot) review only. `"ask"` prompts interactive users and skips in auto mode. It does **not** gate the auto-detected code-level UI review, which has no config flag at all. |

The traceability flags default to the values shown, so both hard-blocks are on; the cases that excuse a missing `Closes #N` are listed once, under check 1 in `references/verification-checks.md` (*Traceability checks*).

**Pre-existing findings.** The code-reviewer's `pre_existing` array (real problems the PR did not cause, on lines the diff leaves untouched) never enters `findings_json`, the Step 6 fix filter, the soft or strict pass, the stagnation signature or the progress record, so they never block the PR or spend a fix cycle. Step 7 lists the final review cycle's `pre_existing`; each cycle reviews the whole diff, so earlier lists are not merged in.

## Binding the head-ref name

SKILL.md's Step 1 (*Bind the head-ref name*) requires `branch_name` to be bound once with
command substitution and used as `"$branch_name"` in every shell command. This is
why, and why the obvious weaker forms do not work.

A head-ref name is chosen by whoever opened the PR, and git permits `` ` ``, `$`,
`(`, `;` and `&` in a ref. So a branch literally named ``fix/1-`id` `` becomes a
command when it is pasted into a shell word, on the reviewing machine, with the
reviewer's credentials. Double quotes do **not** save it: `"$(…)"` and a backtick
still evaluate inside double quotes — quoting stops word-splitting and globbing,
not substitution.

Command-substitution *output*, by contrast, is never re-evaluated. `branch_name`
holds the bytes `gh` printed, whatever they are, and `"$branch_name"` expands to
exactly one argument containing those bytes. That is the whole mechanism.

The plain `{branch_name}` placeholder still appears in this skill's **display
templates** and in **spawn-variable lists** — neither is a shell word, and
substituting there would only make the output wrong.

The `gi-secscan` call sites bind `base` the same way, with command
substitution; the head-ref name is the one untrusted value this skill cannot hand
straight to a script.

## Depth gate (adaptive review depth)

The Step 1 *Depth gate* selects a review `profile` — `light` or `full`; the <!-- a:rvm-depth-gate -->
`XS … XL` scale lives in `references/docs/agent-model-effort.md` (*Complexity → pipeline
profile*). With no researcher here, the signal comes from Step 1's data, and the
**fuller** of any inputs that disagree wins:

- **Risk tier** — SKILL.md's `gi-sensitive.py --classify` of the PR diff:
  `sensitive` or unknown forces `full`, and `Effort` never lowers it.
- **Diff size / files-changed** (`gh pr view {N} --json files`) — small change
  (≈ ≤ 15 changed lines in 1 file) leans `light`.
- **Linked-issue `Effort` band** — when the PR links an issue (`Closes #N` or a
  first-line `Refs #N`), read the `## Metadata` `Effort` band out of
  `linked_issue_snapshot`. **Do not re-read the issue here**: the snapshot is the
  fresher record. `XS`/`S` asserted leans `light`, `M`/`L`/`XL` or
  low-confidence leans `full`.

Resolve to `light` **only when every available signal agrees on trivial**; any
`full` vote, or a missing/ambiguous signal, wins → `full`. When
`review.adaptive_depth` is `false`, only the signal selection above is skipped
and `profile = full`; the risk tier, the review-boundary refresh and the
fail-safe below still run.

### The empty-record fail-safe

SKILL.md's review-boundary refresh has two paths — the script, then a direct <!-- a:rvm-empty-record-failsafe -->
`gh` degrade. This is what happens when **neither** returns a usable record.

**Scope — one state, and only one: a linked issue exists *and* its record could
not be read.** The refresh is conditional in exactly the way the `Effort` bullet
above is — **when the PR links an issue** (`Closes #N` or a first-line
`Refs #N`). A PR with no linked issue has nothing to refresh, so its empty `linked_issue_snapshot` is the correct state
rather than a failed read, and this fail-safe **never** stops it. It proceeds to
Step 3 like any other PR, where `references/verification-checks.md` already
answers for it: `acceptance_criteria` reports `○ pass — none defined; manual
review recommended`, traceability check 1 **fails** on the missing `Closes #N`
(the canonical traceability failure — Step 6 fixes it by editing the PR body) unless the
*Refactor/chore exemption* applies, and check 2 reports `n/a — no linked issue`.
Stopping those PRs would suppress the exact finding they exist to produce.

**Re-run the refresh once — the whole refresh, both paths in the original order:
`gi-issue.py … --refresh` first, then the direct-`gh` degrade if it fails.**
Retrying only the path that failed can miss a transient fault in the other. If
the second attempt also yields no usable record, stop the review; do not
continue to Step 3. Print the rich error (*Linked issue unreadable at the review
boundary* in `references/error-messages.md`). In this block alone, `{N}` is the
**linked issue** number and `{PR}` is the pull request — the resume command takes
the PR, because `/issue-pr-review` reviews a PR, not an issue:

```
✗ Cannot read linked issue #{N} — review stopped

  To fix:  gh issue view {N} --json number,title,body,labels
  Then:    /issue-pr-review {PR}
  Docs:    https://github.com/luongnv89/idd/blob/main/docs/platform-github.md
```

Two things are forbidden on this path, and they are the whole reason it is
written down:

- **Never proceed with an empty `linked_issue_snapshot` for a PR that links an
  issue.** Step 3 verifies acceptance criteria against that variable, and
  `acceptance_criteria` is a hard-block. A dimension
  whose input is empty reports no failed criterion, so it renders as `pass` —
  turning a hard-block into a no-op while the report still shows five green
  dimensions. That `pass` is *correct* for a PR that defines no criteria and a
  *false* one for a PR whose criteria exist and merely could not be read, which
  is why the scope above is the whole fix. An unverifiable criterion is
  `unverified` at best; an unread issue is not a passing one.
- **Never fall back to a cached record.** The `--refresh` is not an optimization
  to be relaxed under pressure: the review boundary earns its name only by being
  an independently fresh read, and the resolver's Step 0d rewrites the very body
  this snapshot carries. A cache entry predating that rewrite can be missing the
  Acceptance Criteria section 0d created, which is the one section Step 3 exists
  to check.

Stopping is the safe outcome here, not the disruptive one: the alternative is a
review that reports a hard-block dimension as passing without having read the
criteria it claims to have checked. This is a **stop**, not a degrade — the same
class as an exit-3 invalid input, and unlike the missing-`python3` case, which
has a working second path and therefore degrades.

**When `review.require_acceptance_criteria_check` is `false`, the stop still applies.** <!-- a:rvm-verification-flag-false -->
The flag governs reporting, not reading. With it `false`,
`references/verification-checks.md` (*Acceptance-criteria verification*) skips
per-criterion verification and reports `○ acceptance_criteria: disabled`, so the
hard-block cited above never runs — but the record is still read. It feeds the
Depth gate's `Effort` band and labels (which fail safe on their own: a missing
or ambiguous signal → `profile = full`), and `issue_context`, which the fixer
spawn below and the ui-reviewer spawn in `references/ui-review-mechanics.md`
receive ungated and which is specified as *empty if none*. An unread issue would
reach them looking exactly like a PR that links no issue. Continuing would also
print the `disabled` note while a second, unchosen cause applied, crediting a
deliberate opt-out for a gap nobody opted into. No flag moves a PR between
*nothing to read* (no linked issue — proceed) and *the read failed* (stop).

**Placeholder binding at the Depth gate.** SKILL.md's two review-boundary <!-- a:rvm-placeholder-binding -->
command lines take `{linked_issue}` — the linked issue's number — because `{N}`
is the PR number at every other command site in SKILL.md. Step 6's `Closes`
body edit and the Step 3 gate bullet that states it take `{linked_issue}` for
the same reason: each names a number that gets written into the PR body, and
`{N}` there would write the PR's own.

Elsewhere, read each `{N}` from its own line: a PR command (`gh pr …`,
`/issue-pr-review …`) takes the PR number; a closing keyword, a `Refs` line,
a commit reference or a `gh issue …` command takes the linked issue. The
counting uses — `{N} tests passed`, `{N} checks failed`, `Cycle {N}` — are a
different placeholder.

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
review. The AC and traceability hard-blocks (`acceptance_criteria: fail`, missing
`Closes #N`) are never relaxed by the profile — a trivial PR that fails them still
blocks soft-pass and does not merge.

## QA handoff gate

Step 1's *QA handoff gate* sets `qa_handoff = trusted | stale | absent` from a
marker `/issue-resolver` writes as the last line of a PR body it opened after a
**clean** QA loop (producer contract: *QA handoff marker* in that skill's
`references/report-templates.md`). SKILL.md owns the verdict table and the
fail-safe; this section owns the precedence rule and the mechanics — the parse,
what `trusted` narrows, when the verdict is recomputed, and the list of checks it
may never touch.

### Precedence

**Precedence, stated once:** `qa_handoff` is computed *after* `profile`, and its
power is bounded **relative to the ungated pipeline** — it may only **narrow**
what a `stale`/`absent` PR already gets. The bound is per verdict, not monotonic across the run:
a flip back to `stale` restores the full cap and is a return to the ungated
pipeline, not a widening. One asymmetric case: a marker `profile=light` against a
pr-review `profile=full`, where the fuller wins — the review collapse **and** the cycle cap are **refused**,
while the duplicate-test skip still applies, because a test run is a test run at
any depth.

### The trust model — forgery is worthless, not impossible

The PR body is **attacker-controlled**: `gh pr edit --body` is available to
whoever opened the PR, so any author can write this marker. Binding `head=` does
**not** authenticate it either — an author can read their own head SHA and paste
a matching one. The verdict may gate **only duplicated work** — a second run of
a check that already ran, unchanged, on this exact commit — and **never a safety
gate**. A PR that rewrites the `.idd.yml` a secret scan reads can disable that
scan: repo-controlled input reaching a safety gate is the failure this design
refuses. An edit that lets the marker suppress a secret scan, a CI wait, an
acceptance-criteria check, or a traceability check converts a token optimization
into a bypass. Do not make it.

"Only duplicated work" is not enough by itself. A skip is a
duplicate only if the first run really happened, and the marker cannot show
that. A forged marker with `tests=<n>@<head>`, plus any unrelated green check
in the rollup (`ci_leg_runnable` asks only that one exists), would skip both
local test legs, the code UI review and cycle 1 on a commit no suite had ever
run on. So `trusted` also requires a **revision receipt**: a record the
resolver writes outside the PR author's reach, for this exact SHA
(*Verifying the receipt*). A forged marker with no receipt is `stale`, so
forging the marker buys nothing.

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

Read it out of the `body` already fetched in Step 1 — no extra API call: <!-- a:rvm-parse-marker -->

```bash
grep -oE '<!-- (gitissue|idd):qa v[0-9]+ [^>]*-->' <<<"$body"
```

- **Zero matches** ⇒ `absent`. The version is matched loosely on purpose — a
  future `v2` marker must reach the version rule below and resolve `stale`,
  not disappear into `absent`.
- **More than one match** (both namespaces counted together) ⇒ `stale`. A
  body carrying two markers is ambiguous, and "first match wins" is exactly
  how a prepended forgery would beat a genuine trailing one. Ambiguity is
  never resolved in the marker's favour.
- **Exactly one match** ⇒ read it as space-separated `key=value` pairs. Unknown
  or extra keys are **ignored, never fatal** — a newer resolver must be able to
  add a field without invalidating every marker for older reviewers — but a
  malformed pair, a missing `head=`, a `head=` that is not 40 lowercase hex
  characters, a version other than `v1`, or a `review=` that is not `clean` ⇒
  `stale`.
- `trusted` **iff** the single parsed marker survives all of the above **and**
  its `head=` equals the PR's `headRefOid` from Step 1's
  `gh pr view {N} --json …` field list **and** the revision receipt for that
  SHA verifies and agrees with the marker (*Verifying the receipt*). Any doubt
  ⇒ `stale`.

`stale` and `absent` run the full pipeline — no step
shortened, no cycle cap lowered, no pass skipped. A human-authored PR never
carries the marker, so it is `absent` and is therefore unaffected by this gate in
every particular.

### Verifying the receipt <!-- a:rvm-verify-receipt -->

The receipt is the one input to `trusted` that the PR author cannot write.
`/issue-resolver` stores it at clean-QA exit with `references/scripts/gi-receipt.py
--write`, under the git common dir (`idd/receipts/<sha40>.json`). That
directory sits outside every branch and every PR body, and every worktree of
the clone shares it (producer contract: *Revision receipt* in that skill's
`references/report-templates.md`). The script itself measured what the receipt
records: the full SHA, a clean tree, the executor's user, uid and host, the
suite's count, SHA and command, and artifact digests.

1. **Once, at Step 1, before Step 2 executes any PR code.** Bind `head_oid` to
   Step 1's `headRefOid`, require `^[0-9a-f]{40}$`, and run
   `python3 references/scripts/gi-receipt.py --verify "$head_oid"`.
2. **Only `"verified": true` counts.** The script returns that only for a
   regular file that names this SHA, records a clean tree and `review: clean`,
   was written by this user on this host, and whose surviving artifacts still
   match their digests. `"verified": false` (`absent` is the common reason),
   any non-zero exit, and no `python3` all mean **no receipt** ⇒ `stale`. No
   prose procedure may stand in for the script and produce `trusted`. The
   degrade costs a full pipeline, never a skip.
3. **The receipt must agree with the marker.** Every marker field that
   drives a skip must equal what the receipt recorded: `profile=` (the
   collapse and cap carve-out), `tests=` (`<count>@<sha40>`, or `null`) and
   `ui=` (the code UI review skip). Absent on both sides counts as equal. A
   marker field the receipt does not back makes the marker `stale`, so a real
   receipt never lends trust to a forged `profile=`, count or UI leg.
4. **Re-evaluation never re-reads the store.** After a push the marker's
   `head=` no longer matches the new head, so the verdict can only become
   `stale` (*Re-evaluation after a push*). A receipt that PR code wrote during
   this run, for example from a lint hook in Step 2, is never consulted.

**What it does not cover.** The receipt is bookkeeping against the PR author's
write surface: the body, the branch and its CI. It is not cryptographic
authentication. Code already running on this host as this user can write the
store, and a review on another machine finds no receipt and runs in full, which
is the accepted cost.

### Field vocabulary

| Field | Meaning | How the loop uses it |
|-------|---------|----------------------|
| `head=<sha40>` | the commit the resolver QA'd | the whole predicate — must equal `headRefOid` |
| `profile=<light\|full>` | the resolver's own Step 0g profile | `light` is a strictly shallower claim; see *Precedence* above |
| `cycles=<n>` | QA cycles the resolver ran | reported only |
| `review=clean` | the resolver's QA exited clean | required — there is no dirty spelling, because a non-clean resolver run emits no marker at all |
| `tests=<count>@<sha40>` | the final suite's passing count and the SHA it ran against | the two test skips below apply **only** when this field is present, its SHA equals `head`, **and `ci_leg_runnable`** (`review.check_ci` is `true` and Step 1's `statusCheckRollup` is non-empty). Refuse the skip when no CI (`no_ci`) or `review.check_ci` is `false` |
| `ui=<none\|code\|code+browser>:<clean\|noted>@<sha40>` | which UI legs ran, their result, and the SHA the UI review ran against | the code UI review is skipped only on `code`/`code+browser` **and** an `@<sha40>` equal to `head`; a value with no `@<sha40>` suffix is well-formed but not commit-bound, so it never permits the skip; `ui=none` skips nothing |

`tests=` carries its own SHA because the resolver's final suite runs *before* its
*Update documentation* step, which may commit — so the suite's commit and the
head commit can legitimately differ. The field is **absent entirely** when the
resolver ran no final suite (its own auto-test setting was off): nothing was
asserted, so nothing may be skipped. Absent `tests=` ⇒ run both test legs in
full, whatever else the marker says.

The skip is a three-part AND, decided from loaded config plus Step 1's
already-fetched `statusCheckRollup` — **never** from Step 5's later wait:
`qa_handoff = trusted` AND the field is present with a SHA that equals `head`
AND `ci_leg_runnable`. `ci_leg_runnable` is true only when `review.check_ci`
is `true` AND that rollup is non-empty; otherwise false (`review.check_ci:
false`, or an empty/absent/unreadable rollup — the early `no_ci`). An empty
rollup is ambiguous (just-pushed vs no CI) and fail-safes to RUN the suite.
When `ci_leg_runnable` is false, ignore `tests=` and run both local test legs
as if the PR were unmarked. Step 5's CI wait stays ungated.

**`review.ignore_ci_billing_failures` does not enter this predicate.**
`ci_leg_runnable` asks whether CI *ran*; the flag asks whether a CI *failure
blocks*. Folded in, it would drive `ci_leg_runnable` false and run both local
test legs on a PR whose marker says they already ran, so the `tests=` skip is
decided as above whatever the flag says; a wrong answer here makes the suite
run, never skip. Under a `trusted` marker and a non-empty rollup both local legs
skip, and if CI then goes red the flag drops that verdict too: the skip rests on
the head-bound `tests=` marker, never on the flag, which supplies no evidence.

`ui=` is split into legs because the code UI review is environment-independent
while the browser leg is fail-soft and skips on a headless host. A flat verdict
would let this skill trust a leg that never ran. It carries its own SHA for the
same reason `tests=` does, and more sharply: the resolver's UI review runs
*before* its QA cycles, so every QA fix commit — and the later *Update
documentation* commit — lands after the diff that review saw. A marker written
without the `@<sha40>` suffix is not malformed (it stays parsable, and stays
`trusted` for everything else); it is simply never commit-bound, so the code UI
review runs in full.

**There is no security-scan field, in any spelling, and none may be added.** Its
only possible consumer would be a safety gate — see *The trust model* above.

### What `trusted` skips <!-- a:rvm-trusted-skips -->

| Step | Under `trusted` | Condition |
|------|-----------------|-----------|
| 2 — pre-pass test run | skipped | `tests=` present **and** its SHA equals `head` **and `ci_leg_runnable`** |
| 3 — cycle-1 cold-start reviewer | **collapsed into** the fresh confirmation pass | every `trusted` marker **except** the depth carve-out — a marker `profile=light` against this review's `profile=full` refuses the collapse (*Precedence* above owns that rule — not restated here) |
| 3 — code UI review | skipped | `ui=code…` or `ui=code+browser…` **and** its `@<sha40>` present and equal to `head`; never on `ui=none`, and never on an unsuffixed `ui=` |
| 4 — local test + build run | skipped | `tests=` present **and** its SHA equals `head` **and `ci_leg_runnable`** |
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
test legs. If the pass returns fixable findings they go to the fixer; the fixer's commit then moves the head, so the next re-evaluation turns
the verdict `stale` and the remaining cycles are the full pipeline again.

### Re-evaluation after a push <!-- a:rvm-reeval-push -->

`qa_handoff` is a **per-cycle** verdict, not a once-per-run constant. Step 1
computes it, but the Review Loop re-enters at **Step 3, not Step 1** — so nothing
would otherwise re-read the head, and a head SHA is the marker's entire
predicate. Recompute it after **any push this skill makes**, and before the next
step that reads the verdict. There are exactly two such pushes:

- **Step 2's lint/format auto-fix commit** (*Commit auto-fixes*). It lands
  before Step 3 and Step 4 ever consult the verdict, and the resolver runs no
  lint/format of its own, so this is the *likely* case, not an exotic one. Miss
  it and, when CI is runnable, both test legs are skipped on a commit no local
  suite has run — Step 2's leg is skipped before the auto-fix is even
  committed, Step 4's afterwards — leaving only Step 5's CI. Keep this
  recompute: it is still required when CI is runnable. Independently, the
  `tests=` skip is refused when `ci_leg_runnable` is false, so a missed
  recompute on a no-CI / `review.check_ci: false` path cannot auto-merge on
  zero test evidence.
- **Every fixer push in the Review Loop** (Step 6). The same predicate, one
  cycle later.

The procedure is the same for both:

1. Re-read the head — `gh pr view {N} --json headRefOid` — because the push just
   moved it.
2. Recompute `qa_handoff` exactly as Step 1 did (*Parsing the marker*) against
   that new `headRefOid`. Re-read `body` in the same call if Step 6 edited it
   (the `Closes #N` read-modify-write); otherwise the body is unchanged and only
   the SHA comparison can flip. Never re-read the receipt store here: a
   recompute may only turn `trusted` into `stale` (*Verifying the receipt*).
3. Apply the new verdict for the rest of the run: `stale` restores the full
   pipeline — the full cycle cap, the Step 2 and Step 4 test legs, the code UI
   review, and a cold-start cycle-1 reviewer if one is still to come.

A step or cycle that pushed nothing leaves the head where it was, so there is
nothing to recompute.

Skip it and `trusted` survives a push that moved the head, so the local suite
never runs on the pushed commit. Restoring the full pipeline is not a widening
(*Precedence* above).

### Never gated <!-- a:rvm-never-gated -->

`qa_handoff` may **never** skip, shorten, or soften any of the following — on any
profile, for any marker, at any cycle:

- **Step 2's `gi-secscan` pre-commit scan.** It guards a commit *this skill* is
  about to make from a checked-out untrusted branch. It is a safety gate, and
  repo-controlled input must never reach one.
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

Both hard-blocks — `acceptance_criteria: fail` and a missing `Closes #N` —
keep blocking soft-pass and merge under `trusted`, exactly as they do under
`light`.

A progress record never skips any of these either: a resumed review runs every
gate above live, and `qa_handoff` is always recomputed through the receipt
check, never restored (`references/progress-record-mechanics.md`).

## Why reuse the reviewer

To minimize token usage, the review loop **reuses the same reviewer agent** across fix cycles instead of spawning a fresh one each time. The reviewer already has the codebase context loaded, so subsequent reviews are cheaper.

- **Cycle 1:** Spawn a new reviewer agent (cold start — reads diff, files, context).
- **Cycles 2+:** Send the reviewer a follow-up message via `SendMessage` asking it to re-review the diff after fixes were applied. The agent retains its context and only needs to re-read the updated diff, not re-discover the entire codebase.
- **Confirmation pass:** After the fixer reports all issues resolved, spawn a **fresh confirmation reviewer** (separate agent, no memory of prior cycles) for an unbiased final check. This is the only fresh spawn after cycle 1.

This trades perfect independence between cycles (which rarely matters in practice — the reviewer was already correct about what the issues were) for significant token savings. The fresh confirmation pass at the end catches anything the reused reviewer might have missed.

Under `qa_handoff = trusted` the cycle-1 cold start is collapsed into the fresh
confirmation pass (*What `trusted` skips* above).

## Cycle 1 — Initial review

Read `references/agents/code-reviewer.md` for the full prompt template. Read `references/agents/fixer.md` for the fix-cycle prompt template.

**Per-role overrides.** Every spawn in this file — the cycle-1 reviewer, the
confirmation reviewer and the fixer — applies `references/docs/agent-overrides.md` for its role:
`agents.model.code-reviewer` / `agents.effort.code-reviewer` for both reviewer spawns,
`agents.model.fixer` / `agents.effort.fixer` for the fixer. A `null` value (the
default) passes nothing, so the calls below are unchanged; a re-messaged agent keeps
the configuration it was spawned with.

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
- `pr_context`: the PR title, the body's `## Approach` section and **Residual risk** line, and the linked issue's `## Constraints` and `## Acceptance Criteria`, verbatim. Never the rest of the body (Test Results, Acceptance Criteria Verification, Sensitivity evidence, `idd:qa` marker): a grader shown the author's verdicts anchors on them. The confirmation pass binds the same
- `diff_command`: `gh pr diff {N}`
- `confidence_threshold`: `review.confidence_threshold` (default 80) — the reviewer reports only findings scored at or above this floor, except a `constraints` finding, reported at any confidence; ui-reviewer keeps its own 75 floor
- `review_mode`: `review` (`challenge_context` empty) — the PR body never selects challenge mode
- `practice_packs`: the packs `references/practice-packs.md` selects from `gh pr diff {N}` and the linked issue, counting the change as classified sensitive when the *Depth gate*'s risk tier (its step 4) is `sensitive`; select once in cycle 1 and bind the same set in the confirmation pass

## Cycles 2+ — Re-review via SendMessage

Send a message to the existing reviewer agent:

```
The fixer applied changes. Re-review the PR diff to check if the issues were resolved and find any new issues.

Run: {diff_command}

Return the same JSON format as before, with your full current `pre_existing` list.
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
- `secscan_script`: the **absolute** path to `references/scripts/gi-secscan.py` — the bundled script that implements it, and what the fixer MUST run before committing. Absolutize it before binding (a subagent's working directory is the target repo, so a skill-relative path resolves to nothing and the gate silently never runs). Only the path is passed; the script reads `security.*` from `.idd.yml` itself, so no repo-controlled config value reaches a command line. This and `security_convention` are spawn *variables* rather than references inside `fixer.md`, because an emitted agent prompt renders its own references as absolute repo URLs and so cannot name a path inside this skill's bundle
- `secscan_policy_ref`: `origin/<default-branch>` — the ref the scan reads `security.*` from, bound from `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name`, never from the PR's author-chosen `baseRefName`. This skill reviews the branch that wrote the checked-out `.idd.yml`, so without it the artifact under review supplies the policy governing its own review and can allow-list its own secret. A ref name, not a config value — nothing repo-controlled reaches a command line either way

```python
Agent(
  description="fixer — fix PR #N review issues",
  prompt=<fixer.md prompt with {variables} replaced>,
  # do NOT set subagent_type — default general-purpose agent, not a custom "fixer" type
)
```

The fixer subagent reads affected files, applies targeted changes, stages specific files, runs relevant verification, and — before committing — runs the mandatory pre-commit security scan against the staged set — `references/scripts/gi-secscan.py`, whose exit 1 is a block that stops the commit, degrading to the Primary Pattern in `references/docs/pre-commit-security.md` only when the script cannot run (real secrets block the commit either way). It then commits any changes. The main agent only collects the fixer's JSON result and pushes if changes were committed. If the fixer cannot resolve all blocking findings, keep the remaining items for the next loop/report. After the fixer returns with one or more commits, push: `git push origin "$branch_name"` — the variable SKILL.md binds from `gh pr view {N} --json headRefName --jq .headRefName`. A head-ref name is chosen by whoever opened the PR and may contain `` ` ``, `$(`, or `;`, so it is never pasted into a command as a literal.
