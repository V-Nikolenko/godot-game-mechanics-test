# Plans

One **directory** per feature, written by the `feature-workflow` skill. Every stage checkpoints
to its own file so a cycle that runs out of budget mid-feature resumes instead of restarting:

```
docs/plans/<slug>/
├── STATUS.md       ← the resume pointer: which stages are done, what to do next
├── 1-context.md    ← modules involved, existing code to reuse, constraints
├── 2-research.md   ← how shipped games solve this: findings, tradeoffs, sources
├── 3-plan.md       ← problem, design, build sequence, test plan, risks, out of scope
├── 4-review.md     ← independent subagent verdict (APPROVED / CHANGES_REQUESTED / REJECTED)
└── 5-progress.md   ← per-build-step implementation log
```

`STATUS.md` is the important one. Every cycle checks `docs/plans/*/STATUS.md` for unchecked
boxes before touching the backlog, and resumes from the first incomplete stage. Its
`Next action:` line is what stops the next run re-reading the codebase and re-running the same
web searches — which costs a large part of a 5-hour window and produces the same answer.

Implementation only proceeds on `VERDICT: APPROVED`.

These files are committed deliberately: they are the audit trail for work done unattended. If a
morning report claims a plan was approved and there is no `4-review.md`, the review did not
happen.

A rejected plan is a legitimate outcome — it means hours of wrong implementation were avoided for
the cost of a few minutes of planning.
