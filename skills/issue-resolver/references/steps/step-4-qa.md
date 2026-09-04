# /issue-resolver — Step 4: QA

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 4 — QA (code-reviewer + fixer subagents) <!-- a:rs-step4-qa -->

Each cycle:

1. **Code review** — spawn a *fresh* code-reviewer subagent per cycle (see `references/agents/code-reviewer.md`) so each pass is unbiased. Pass the same `workspace_contract` and independent `expected_lane_identity` sibling used by Steps 1–3 (both `null` on ordinary runs); the reviewer validates their binding before reading the diff or files.
2. **Run tests** — unit, integration, e2e (if present), build/compile. Record <!-- a:rs-qa-run-tests -->
   `tests_state` — the passing count paired with `tests_sha` = `git rev-parse HEAD`,
   see *Last-green test state* below — **at the moment the suite runs**.
   **Record it only for a green run on a clean tree:** a suite that reported any
   failure, that did not complete, or that ran with
   `git status --porcelain=v1 --untracked-files=all` non-empty records *nothing*
   and leaves any earlier value untouched.
   `tests_state` stores a passing count with no pass/fail flag, so a red run is
   not even representable in it — recording one would hand a later consumer a
   failure dressed as a pass. Carry
   it from the cycle that exits clean to Deliver: the QA handoff
   marker's `tests=<count>@<sha40>` is this variable rendered, it names the commit
   the suite actually ran on, and *Update documentation* commits after this point,
   so the value is unrecoverable later (`references/report-templates.md`, *QA
   handoff marker*). Nothing recorded ⇒ omit the whole `tests=` field; never substitute the head SHA.
3. **Evaluate results:** <!-- a:rs-qa-evaluate -->
   - Reviewer returns `PASS` AND all tests pass AND build succeeds → exit loop, QA passed.
   - Issues found → delegate fixes, then start next cycle.
4. **Fix issues** — spawn or re-message the fixer subagent (see `references/agents/fixer.md`) with reviewer findings, failing test/build output, and the same `workspace_contract` plus independent `expected_lane_identity` sibling used by the reviewer (both `null` on ordinary runs), passing `security_convention`: `references/docs/pre-commit-security.md`, `secscan_script`: the **absolute** path to `references/scripts/gi-secscan.py`, **and** `secscan_policy_ref`: `origin/${base}` (paths and a ref name only — the script reads `security.*` from the ref itself, so the branch under fix never supplies the policy that scans it). Absolutize both before binding: a subagent runs with the target repo as its working directory, so a skill-relative path resolves to nothing. Both are spawn variables rather than references inside the agent file, because an emitted agent prompt renders its own references as absolute repo URLs and so cannot name a path inside this skill's bundle. The fixer reads affected files, applies targeted fixes, verifies them, runs the mandatory pre-commit security scan before committing — the script first, the document's Primary Pattern only when the script cannot run, and a script exit of 1 is a block that stops the commit — and commits as `fix(scope): address review feedback (#N)`. The main agent does not apply code fixes inline when the Agent tool is available.

**Profile carry.** The pipeline profile *Step 0g* selected — `light` or `full` —
is carried to Deliver and written as the QA handoff marker's `profile=` field
(`references/report-templates.md`, *QA handoff marker*). Unlike `tests=` and
`ui=`'s `@<sha40>`, it has no omit rule, so it is never dropped and never guessed:
it is already in hand from Step 0g, and carrying it costs nothing, exactly as
`tests_state` and `ui_sha` are carried from where they are captured.

### Last-green test state <!-- a:rs-last-green-state -->

**Single home of `tests_state` and of its two run-state consumers.** Those are <!-- a:rs-clean-tree -->
Step 4 cycle N+1 below and Step 5 Deliver (`references/steps/step-5-deliver.md`). The QA marker is the durable rendering
of the same state; `references/report-templates.md` is only that marker's
rendering location, not a third consumer. Two definitions of "the suite already
ran on this commit" drift apart, so this is the only place either is stated.

```
tests_state = <passing_count>@<tests_sha>        # e.g. 128@9f2c1ab…  (sha40)
```

Captured **where the work ran**, never reconstructed: the count the suite
reported, and `tests_sha` = `git rev-parse HEAD` evaluated in the same step,
*before* anything else commits. Full 40-character SHA — the short form is
display-only. It is a
**run-state variable**, not merely the marker field it renders into (issue #256);
`references/report-templates.md` (*QA handoff marker*) describes how to render
it; it neither defines nor consumes the run-state decision.

Two run-state consumers, and no others:

1. **Step 4, cycle N+1.** **Only against a recorded green run** — cycle N+1
   exists precisely because the reviewer *or* the suite failed, so the previous
   run is usually red, and a red run recorded nothing at all under the capture
   rule above, which leaves nothing to carry and the suite runs. Given a
   recorded green state, compare `tests_state`'s
   SHA to `git rev-parse HEAD`. Equal — and the tree clean, see *Both sides
   require a clean tree* below — means the previous cycle's fixer committed
   nothing, so the suite would run on the identical tree — skip it and carry the
   recorded **green** count into this cycle's evaluation. Any difference, and it runs.
   A carried count never satisfies "all tests pass" by itself: it is an earlier
   green run restated, and only for the identical tree.
2. **Step 5, *Verify all tests pass*.** Same comparison at the Verify moment. A
   QA cycle that exited clean with no commit after it has already run this exact
   suite on this exact commit; re-running it is duplicated work, not verification.

**Both sides require a commit-relevant clean tree.** HEAD equality does not imply
an identical commit-relevant tree. A fixer can edit files and stop without
committing — `references/agents/fixer.md` makes a real-secret block exactly that path.
Run `git status --porcelain=v1 --untracked-files=all` and require empty output
**both** when `tests_state` is captured and at every comparison; command failure
or any output ⇒ `run`. `--untracked-files=all` overrides
`status.showUntrackedFiles`, so nonignored untracked paths stay visible. Ordinary
ignored-only local artifacts are intentionally excluded; a force-added ignored
path is tracked in the index and therefore visible. This establishes equality of
the commit-relevant tree, not the entire execution environment.

Both consumers layer **under `resolve.auto_test`**, never over it: when
`resolve.auto_test` is `false` the suite is skipped for that reason alone and
`tests_state` is never consulted. Fail-safe is `run`: nothing recorded, a short
or non-hex SHA, a count that is not a number, or any doubt at all ⇒ run the
suite, exactly as today. `resolve.adaptive_effort: false` also forces `run`;
no new config key is introduced. Never compare against a SHA captured anywhere but
the step that ran the suite, and never substitute the current head for a missing
record.

*Update documentation* commits **after** Step 5's Verify (see the Deliver order in
SKILL.md), so a doc-only commit is never covered by `tests_state` — that is
today's ordering, unchanged by this variable, and the reason `tests=` is captured
in Step 4 rather than at push time.

One `○` line per skip, per references/docs/terminal-style.md:

```
○ Test suite: skipped (last green 128@9f2c1ab == HEAD)
```

### Loop controls <!-- a:rs-qa-loop-controls -->

- **Max cycles (hard bound):** `resolve.qa_max_cycles` (default: 5). Never
  exceed this configured cap.
- **Policy ceiling by class** (issue #308; distinct from the hard bound):
  `light` → **1**; `full` + low/medium complexity → **2**; `full` + high/complex
  → `resolve.qa_max_cycles`. Missing profile/complexity fail-safe as full +
  medium (ceiling **2**). The reviewer spawn still runs on the `light` path
  (review is reduced in depth, never skipped). A profile upgraded to `full` in
  Step 1 uses the matching class ceiling. Record `ceiling` and, if `qa_cycles`
  exceeds it, a `breach_reason` on the run-log line.
- **Exit on clean:** stop as soon as review passes AND tests pass
- **Exit on stagnation:** if the same issues appear in 2 consecutive cycles, stop and report

### After QA

If clean:
```
[4/5] QA           ✓ clean after {N} cycles
```

If max cycles with remaining issues:
```
[4/5] QA           ⚠ {N} issues remain after {max} cycles
```

- Interactive: show remaining issues, ask to continue.
- Auto: continue to Deliver — PR can be created with known issues noted.

### Step 4 — UI/UX review (auto-detected) <!-- a:rs-step4-ui-review -->

The full mechanics — contract, keyword list, classification, code-review spawn,
display-environment label, browser gate + capability checks, and the skip/success
output — live in one shared home: `references/docs/ui-review.md`. Read it before running
this sub-step. Only the resolver's deltas are listed here.

- **When:** before the QA cycles of Step 4, once per run.
- **Diff command:** `git diff origin/${base}...HEAD` (there is no PR yet), so
  detection step 2 scans `git diff --name-only "origin/${base}"...HEAD`.
- **Agent description:** `"ui-reviewer — UI/UX code review (#N)"`.
- **Variables passed:** `{branch_name}`, `{base_branch}`, `{issue_context}` (the
  issue title/body + acceptance criteria), `{pr_context}` (**empty** — no PR
  exists yet at QA time), `{diff_command}`, `{workspace_contract}` plus the
  independent `{expected_lane_identity}` sibling (both `null` outside a validated
  caller-managed lane), and `{confidence_threshold}` = `80`
  (the resolver has no `resolve.confidence_threshold` knob, so it always passes
  the default floor).
- **Browser gate config key:** `resolve.ui_review.browser_review`.
- **Findings flow:** merged into the QA findings and handled by the Step 4 fixer
  loop.
- **SHA capture:** record `ui_sha` = `git rev-parse HEAD` **at the moment the
  ui-reviewer is spawned** and carry it to Deliver. The QA handoff marker's
  `ui=…@<sha40>` names the commit this review actually saw, and — because this
  sub-step runs before the QA cycles — every fix commit those cycles produce, and
  *Update documentation* after them, lands later (`references/report-templates.md`,
  *QA handoff marker*). Nothing recorded ⇒ omit the `@<sha40>` suffix; never
  substitute the head SHA.
