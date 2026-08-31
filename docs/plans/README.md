# Plans

One file per feature, written by the `feature-workflow` skill before any code is written:

- `<slug>.md` — the plan: problem, existing code to reuse, research findings with sources and
  tradeoffs, design, build sequence, test plan, risks, out of scope.
- `<slug>.review.md` — an independent subagent's verdict on that plan. Starts with
  `VERDICT: APPROVED`, `VERDICT: CHANGES_REQUESTED`, or `VERDICT: REJECTED`.

Implementation only proceeds on `APPROVED`. These files are committed deliberately: they are the
audit trail for work done unattended, and they let a cycle that ran out of budget mid-feature be
picked up by the next one.

A rejected plan is a legitimate outcome — it means several hours of wrong implementation were
avoided for the cost of a few minutes of planning.
