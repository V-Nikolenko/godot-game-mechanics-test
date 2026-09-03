# Completed epics

One folder per finished epic. Written at the moment the epic completes, while the detail is still
recoverable — reconstructing it later from commits and diffs is far more expensive and less
accurate.

```
docs/epics-done/<epic-slug>/
├── REPORT.md      the epic in full: what was built, how it was verified, what changed course
├── PRD.md         what was asked for and why, as finally understood
└── SOURCES.md     every external source consulted, with what each contributed
```

The per-feature working artifacts stay in `docs/plans/<slug>/` — this folder is the durable
summary, not a copy of them. `REPORT.md` links back to the plan directories rather than
duplicating their content.

## Why this exists

An unattended loop produces a lot of decisions nobody watched being made. Six weeks later the
questions are always the same: why is it built this way, what else was considered, where did
these numbers come from, and what is known to be unfinished. This folder answers those without
re-reading the diff.
