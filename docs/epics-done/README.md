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

## Index

| Epic | Folder | Shipped | One-line |
|---|---|---|---|
| Level 1 space-station mini-boss | [`station-mini-boss/`](station-mini-boss/) | 2026-09-01 → 2026-09-03, six cycles | A two-phase cores-and-turrets mini-boss that gates Level 1's third section. Built, gated, armed, reinforced and staged, with 93 tests — **never played by a human**, and its hull sprite currently renders opaque. |
| Enemy rework, phase 1: mode-neutral enemy AI architecture | [`cmufklb100001p92xs1ey2fb1/`](cmufklb100001p92xs1ey2fb1/) | 2026-09-25 → 2026-09-27, 16 tasks | The `EnemyBrain`/`EnemyMover`/`AttackController`/`DefenseProfile`/`TargetInfo`/`ProjectileLifetime` architecture the rest of the 20-phase roster rework builds on, plus the Drone Interceptor ported onto it as proof — **never played by a human**, and the Assault corridor constraint is untested by any real AI-driven enemy yet. |
| Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles | [`cmufs7ek60001nm2x6d0bt2et/`](cmufs7ek60001nm2x6d0bt2et/) | 2026-09-27 → 2026-09-28, 20 tasks | The two contact-damage drones on the phase-1 stack, `SquadController`, `AnchorIdle`, `ContactProfile`/`ContactBlast`, `StateLight`, and level 1's and the hub's drone spawns moved onto them — **never played by a human**; level 1's new density and the `StateLight` cues at Assault speed are unwatched. |
| Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family | [`cmufs7ekv000lnm2x7nbswijy/`](cmufs7ekv000lnm2x7nbswijy/) | 2026-09-28 → 2026-10-07, 19 tasks | The Fighter's attack runs, the Gatling's pressure windows and convergence fire, the four pooled enemy rounds, `BurstClock`/`DubinsPath`/`WFormation`, hub patrols, and all 64 of level 1's fighter/Gatling spawns off rails — **never played by a human**; squad separation after a death and the feel of level 1's density are open. |

`foundations-test-harness-uid-integrity-art-pipeline` also completed (GUT bootstrap, UID integrity
test, PixelLab pipeline) but predates this folder, so it has no dossier — its record is the plan
directories and commits `79da62b`, `94e251d`, `fc4992d`.
