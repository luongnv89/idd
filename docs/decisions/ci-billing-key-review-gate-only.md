# ADR — `review.ignore_ci_billing_failures` Stays Review-Gate Only

**Status:** Accepted (2026-09-17).
**Issue:** [#451](https://github.com/luongnv89/idd/issues/451).
**Amends:** [#431](https://github.com/luongnv89/idd/issues/431) AC3, as shipped
in [PR #436](https://github.com/luongnv89/idd/pull/436).

## Context

Issue #431 added `review.ignore_ci_billing_failures` so a repository whose CI
fails for billing reasons (GitHub Actions spending limit reached, account
locked) is not stuck behind a red build it cannot fix. PR #436 implemented the
key in `/issue-pr-review` only: with the key on, Step 5 still polls and reports
CI, but a terminal failure no longer blocks the review gate, and the review
exits PARTIAL.

#431's AC3 said "automation continues". Issue #451 observed that it does not.
`/auto-pilot` Phase 5.1a never trusts a `failed@<sha40>` verdict: it reads it
as `absent`, re-runs its own CI wait, and that wait refuses to merge a PR with
failing CI. So an `/auto-pilot` run still stops at merge, and the AC as written
was unmet.

There were two ways to close the gap: extend the key to the merge gate, or keep
the key where it is and make the docs and the AC say what it actually does.

## Decision

**The key stays review-gate only. No behavior changes.**

- `/issue-pr-review` continues past a terminal CI failure and exits PARTIAL.
- Its Step 7 auto-merge gate excludes the ignored-CI path. An ignored CI
  failure is never clean at the merge gate, the same way pending CI is never
  clean.
- `/auto-pilot` Phase 5.1a never trusts `failed@<sha40>`. It reads it as
  `absent`, re-runs its own wait, and leaves the PR open.
- A human merges that PR.

**Why.** The key cannot tell a billing failure from a real one. No GitHub API
field carries the failure reason as data, so the key ignores **any** terminal
CI failure, not only billing ones. If the key reached the merge gate, `--auto`
would squash-merge a genuinely red build whenever the key was on. That inverts
the safety posture PR #436 kept. Its design-confirm checkpoint chose the narrow
scope and left `/auto-pilot`'s merge gate untouched. A later review cycle on
the same PR carved the ignored path out of `/issue-pr-review`'s Step 7
auto-merge gate, on both the soft-pass and strict-pass paths, after finding that
`--auto` with `review.auto_merge: true` would otherwise merge a red PR.

**#431 AC3 is amended to match.** The amended wording is:

> When the setting is enabled, /issue-pr-review's review gate continues instead
> of stopping on a terminal CI failure; no merge gate is relaxed
> (/issue-pr-review --auto and /auto-pilot both still refuse to merge), so the
> PR is merged by hand.

## Consequences

- Automation still stops at merge for a PR with failing CI, with or without the
  key. The key saves the review, not the merge.
- The scope is stated where a user configuring the key reads it: the schema
  comment and defaults-table row in `docs/config-schema.md`, and the comment in
  `/init-gitissue`'s `.gitissue.yml` template. Each says no merge gate is
  relaxed, naming both `/issue-pr-review --auto` and `/auto-pilot`.
- `tests/test-ci-billing-431.sh` pins the scope at `/auto-pilot`'s merge gate:
  Phase 5.1a must keep reading `failed@<sha40>` as `absent`, and the user-facing
  comments must keep the merge-by-hand wording that names both merge gates.
  `/auto-pilot`'s own files still do not name the key.

## Billing detection: annotations and structural signal — closed out

Issue #451 also noted two possible ways to detect a billing failure. Neither is
pursued now.

**(a) Check-run annotations.** The check-run annotations endpoint returns the
failure reason as JSON. Its `message` field, though, is free text, so matching
it is still a consumer-side prose filter. That is exactly why #436 rejected its
Option 1, and the rejection stands. The message wording is not documented as
stable, and relying on `.[0]` assumes an annotation order that has not been
established.

**(b) Structural signal.** A billing-blocked job records zero steps and
completes in under ten seconds (evidence: `luongnv89/textwiz` run 34584883464,
job `build-and-test`). Reading step count and timestamps is a JSON field read,
which the platform driver rule allows. But the signal rests on one sample, and
its false-positive rate against jobs that fail at setup (runner or image errors,
for example) is unknown.

Reopen (b) as its own research issue if more samples accumulate. Even a working
detector would only narrow what the key ignores. It would not, by itself,
justify extending the key to the merge gate.
