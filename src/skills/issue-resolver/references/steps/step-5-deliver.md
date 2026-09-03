# /issue-resolver — Step 5: Deliver

One part of `references/pipeline-steps.md` — the index that maps every step to its file. Read only the part for the step you are on; a pointer to another step (*Step N — …*) resolves through that index.

## Step 5 — Deliver <!-- a:rs-step5-deliver -->

### Pre-push secret scan

Full rationale for SKILL.md *Step 5 — Deliver → Push branch and create PR*, which owns
the invocation, the pass condition and every exit code. Two of its rules look like style
and are not.

**Why no config value ever reaches the command line.** `gi-secscan.py` reads
`security.allow_pattern`, `security.extra_secret_file_pattern`,
`security.extra_secret_value_pattern` and `security.max_file_size_mb` out of
`.gitissue.yml` itself. `.gitissue.yml` is repo-controlled, so its values are attacker
-influenced on a public repository; interpolating one into a shell word lets a crafted
value close its quote and append a command to a step that `/auto-pilot` runs unattended.
Passing only flags and a ref name keeps every untrusted string inside the script's own
parser.

**Why `--policy-ref` names the base, not the branch.** The branch being scanned was
implemented from an untrusted issue body. If the scan read `security.*` from that same
branch, a change that grew a permissive `security.allow_pattern` would be deciding how
it is scanned — the gate would approve exactly the commit that disarmed it. Reading the
policy from `origin/<base>` means the rules come from a ref the resolution cannot write.
That is also why the pass condition checks `policy_source`: an exit 0 whose
`policy_source` is not the `ref:origin/…` that was asked for means the script fell back
to some other policy, and the scan that ran is not the scan that was requested.

**Why `scanned: 0` with `skipped > 0` is not a pass.** An allow pattern suppresses
*scanning*, not findings. A `.gitissue.yml` whose allow pattern matches everything
produces a clean verdict over nothing at all, which is indistinguishable from a clean
verdict over the diff unless the counts are read. Treat "examined nothing" as a failure
to scan and degrade to the documented prose pass instead.

**Why exit 1 never degrades.** Every other non-zero exit from a bundled script means the
script could not answer. Exit 1 here means it *did* answer, and the answer was `block`.
Reading it as a degrade inverts the verdict and pushes the secret. The one exception is
exit 1 with no parsable JSON on stdout — that is a crash, not a verdict, and is handled
as exit 2.
