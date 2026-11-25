VERDICT: CHANGES_REQUESTED

Round 1 review of `3-plan.md` (t14: level 1 places a local jammer and a Hacker Frigate), checked against the epic
`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.17 / §2.18, the task's acceptance criteria and the code.

## What I checked, and what holds

- **Lives.** `hacker_frigate_config.tres`: `engage_seconds` 9.0, `pulse_seconds` 1.6, `first_pulse_delay` 2.0.
  `hacker_frigate_brain.gd:270-279` (`_on_budget_expired`): an expiry in TELEGRAPH cancels it, one in PULSE sets
  `_disengage_pending` and the window finishes (`_end_pulse` -> `_leave_attack`, :492-515), so the deferral is at most
  `pulse_seconds` plus a tick. `EngagementBudget` (`update()` from the first brain tick) has no other deferral, and nothing
  in level 1 can EMP an enemy (the only `TARGET_ENEMIES`/`TARGET_ALL` emitters are `emp_zone.gd:36` and a placed mine,
  `enemy_mine.gd:394`, which are the things the guards forbid). 9.0 + 1.6 + 2/60 + 5.67 (DECISIONS.md:3698) = **16.30 s**. Correct.
- **Jammer life.** `jamming_structure_config.tres` `assault_drift_speed` 60, body `CircleShape2D` r 28 (`jamming_structure.tscn`).
  `AssaultDrift.step()` frees below `projectile_world_rect().end.y`. `ArenaCamera._visible_rect()` = (640, 360) ± (740, 740), grown
  by `_PROJECTILE_MARGIN` 64, so end.y = 1164; `V_LIMIT` 380, `CameraShake._MAX_OFFSET` 8. y_spawn = 360 − 380 − 8 − 440 = −468;
  1632 / 60 + 2/60 = **27.23 s**. This matches `_member_life()` (`test_level1_specialist_spawns.gd`, Ph8 section). Correct.
- **World x.** `JammingStructure._ready()` removes the camera pan (`world_anchored_x` true), so `.at(-80, …)` lands at 480.
  `LaserRay._BEAM_WIDTH` 56 (`laser_ray.gd:76`), need = 28 + 28 = 56. Columns lit before 89.23 s
  (`level_1_director.gd:91-97`): the nearest to 480 are 550 (70), 400 (80), 384 (96), 600 (120). Clear. The 16-column count and
  the `3·(8+12) + 1·16` = 76 sanity are right.
- **Count curve.** Against the printed planet_approach curve: during [42.00, 58.30) the max is 6 (55.30, 58.00) -> 7; during
  [62.00, 89.23) the max is 6 (65.00, 75.50, 88.80) -> 7. 7 ≤ 7.5. `_peak()` iterates intervals in list order and only updates
  on a strictly greater count; Ph9 intervals are appended last and reach 3 (Hacker at 42.0) and 5 (jammer at 62.0), so the
  reported `at` stays 28.40 and the ram-triple / corvette / mine-layer boundaries keep their insertion moment. Correct.
- **Hacker at 96 s boundary.** Inserted between the 95.0 and 98.0 waves (effective 96.0); alive to 112.3; at the 98.00 start
  the count is 7 + 1 = 8 > 7.5 (the plan's jammer and Hacker are gone by then). Correct.
- **Constraints 2 / 3.** 58.30 < 98, 89.23 < 98, 58.30 ≤ 62.00. Option A is the first option and fits; B–D are not needed.
- **Guards.** The existing Ph9 rows (`test_engagement_deadline.gd:1082-1125`) cover jammers in ENEMIES_CLEARED, the sector jammer in
  any level-1 section and the Hacker in ENEMIES_CLEARED; the plan adds the Disruptor, the EMP zone, the EMP Minefield wave-entry row
  and the §2.17 source scan with the 0.15 / 0.0 `w_emp` boundaries. Today's scan is clean
  (`grep` over `assault/scenes/levels/` and `wave_builder.gd` finds no `emp_zone`, `EmpZone`, `emp_mine`, `w_emp` or `sector_jammer`).
  `minefield.tscn` authors no `w_emp` (default 0.0, `minefield.gd:46`), so the `initial_props` predicate is sufficient.
- **Reuse.** `_member_life()` -> `_static_life()`, `_column_conflicts()`, `_ph8_intervals()` shape, `Slice.placed()/slice_waves()/run()`,
  `ph9_exit_keys.hacker_exit()` (memo hit after `test_hacker_frigate.gd`), `_step_disruption()` on a real fighter
  (`test_player_ability_lock.gd`). Nothing is reinvented; no frozen constant is added or raised; no config retune; no deep_space.
- **Gate time.** t19's five 16× slice replays cost +1.14 s (`tests/README.md:626`); three replays here (≈ 5 + 7 + 9 game s) plus
  arithmetic rows fit the 2.5 s allotment.

## Blocking

**B1 — the column boundary's expected result is wrong under the rule the plan keeps.** `3-plan.md:56-57` says the jammer moved to
design x −45 (world 550) "is reported, and only against columns at 550". But the plan (line 31-32) deliberately keeps
`_column_conflicts()`'s "no end filter" rule (`test_level1_specialist_spawns.gd`, `_column_conflicts`: it skips a row only when
`row.time >= end`, never when the column went dark before the static spawned), so the 10.0 s row's **600** column counts too, and
|550 − 600| = 50 < 56. The boundary as written fails on its "only" assertion. Fix one of the two:
(a) keep the strict rule and assert the conflicts **include** "the 78.0 s column at 550" (and print the list; the 600 hit is an
artefact of the conservative rule, which DECISIONS should note), or (b) add a start filter (skip a row whose lethal window,
`time + warn + active`, ended before the static's spawn, the epic's literal "lit during its life") and prove it bit-identical for the
Ph8 rows (the wall row at time 0.0 then needs its real warn/active, read from `laser_wall.tscn`). (a) is the smaller change.

**B2 — the source scan misses the canonical way to put a sector jammer in an Assault level.** The plan's sector-jammer flag is the
strings `sector_jammer` / `SECTOR_JAMMER` (`3-plan.md:67-68`). The documented API is `b.jammer(&"sector")`
(`wave_builder.gd:122-131`), whose text contains neither. Level 1 is covered by the wave-entry row (`resource_path`), but level 2
builds its waves inside `level_2_waves.gd::_ready()`, so the source scan is the **only** guard for it, and it would pass a
`builder.jammer(&"sector")` line. The acceptance criterion ("no sector jammer … in any Assault level", each guard with a failing
synthetic boundary) is therefore not met for the most likely spelling. Add a pattern for a `jammer(` call with a `"sector"` argument
(e.g. regex `jammer\(\s*&?"sector"`) and a synthetic `.gd` boundary containing `b.jammer(&"sector")` that fails, plus one with
`b.jammer(&"pulsed")` that passes.

## Non-blocking

**N1 — the rename is churn with live references.** Renaming `test_ph8_static_members_clear_every_lit_column` (`3-plan.md:55`) stales
three live references: `CLAUDE.md` (the Phase 8 t19 paragraph), the comment in `level_1_director.gd` and
`assault/scenes/structures/turret_group/STRUCTURE.md`. The epic says "extend" it. Keep the name, or update all three in the same commit.

**N2 — the "< 98.0 s" half of the constraints row has no boundary.** Only disjointness gets one (jammer in the 50.0 s wave). Add a
second synthetic case for the end predicate, e.g. the jammer in the 75.0 s wave (75 + 27.23 = 102.23 ≥ 98.0) is flagged.

**N3 — the "rockets were in flight at PULSE start" assertion depends on traffic surviving the rockets.** Rockets lock only onto live
non-Hacker enemies more than 30° off the Hacker's bearing, and "none -> no rocket". At 500 px/s and 0.4 s cadence they will kill
the 42.0 s cluster and the 44.0 s snipers / drones fast, and the slice never sees earlier traffic (`level1_slice_replay.gd` header),
so whether a rocket is in flight at PULSE (≈ 45–46 s) depends on spawn timing, which runs on idle time at 16×. Make the precondition
independent of traffic: when no target qualifies, launch an unlocked rocket on a fixed heading at least 30° off the Hacker's bearing
(it is still `SeekingOrdnance.eligible`). Also state the slice length and assert `stopped == true`, as the Ph8 pair row does.

**N4 — the 1 s-budget Hacker boundary holds by construction.** `engage_seconds` 1.0 < `first_pulse_delay` 2.0 means no TELEGRAPH
regardless of placement or rockets, so it says nothing about level 1. It matches the Ph8 precedent, so this is acceptable. A row
showing that a rocket locked on the Hacker cancels its TELEGRAPH (`_on_health_changed`) would test the premise the >30° rule
protects; optional.

**N5 — scope edges of the guards.** (a) `assault/scenes/enemies/space_station/station_reinforcements.gd` builds `WaveBuilder` waves
outside `assault/scenes/levels/`, so neither the wave-entry rows nor the scan see a jammer, Hacker or EMP piece added there. List it
under Out of scope or add that file to the scan. (b) `emp_mine.tscn` is flagged only in a level `.tscn` (the epic's wording). Adding
it to the level-1 wave-entry sweep and to the `.gd` scan costs one line each and closes the "placed EMP mine via a wave" route.

**N6 — the jammer replay's slice length is unstated.** Give it explicitly (spawn − 1 s to spawn + about 12 s covers the
≈ 8.5 s to reach the stub at dx 160 / r 240). Assert the stop came from the lock (`stopped == true`), not from running out the
length. The far ship at x 1240 (760 px from x 480) is a weak control, but it is a real one.

## Summary

The option choice, every life, the count curve, the x clearance and the 96 s boundary check out against the code. Two things must
change before building. B1: the column boundary's "only 550" claim fails on the 10.0 s / 600 column under the strict rule the plan
keeps. B2: the level-2 sector-jammer guard misses `b.jammer(&"sector")`. Both fixes are small.

## Round 2

VERDICT: APPROVED

Checked `3-plan.md` → "Revision 1 (answers review round 1)" against the round 1 findings and the code.

- **B1, resolved.** The boundary now asserts the conflicts are non-empty and include the 78.0 s column at 550, with the 10.0 s /
  600 hit (50 < 56 px) named as the strict no-end-filter rule doing its job. That is option (a) and it matches `_column_conflicts()`.
- **B2, resolved.** The regex `jammer\(\s*&?"sector"` catches `b.jammer(&"sector")` and `jammer("sector")`
  (`wave_builder.gd:122-131`). There is a failing `.gd` boundary and a passing `&"pulsed"` case. No scanned file matches today:
  `grep` over `assault/scenes/levels/` and `station_reinforcements.gd` finds no `sector`, `jammer`, `emp_mine`, `EMP_MINE`,
  `emp_zone`, `EmpZone` or `w_emp`. After t14 the director's `b.jammer().at(-80, -220)` has no `"sector"` argument, so the
  real scan stays empty.
- **N1, resolved.** The name is kept, so the CLAUDE.md, director comment and `STRUCTURE.md` references stay valid.
- **N2, resolved.** The 75.0 s wave case (75 + 27.23 = 102.23 ≥ 98.0) is a correct failing boundary for the end predicate.
- **N3, resolved.** A fixed-heading unlocked rocket when no target qualifies removes the dependence on surviving traffic. It still
  passes `SeekingOrdnance.eligible` (`can_be_retargeted()` is false only when claimed, done, out of the tree or in a lit jammer). The
  12 s slice and the stopped-on-claim assertion match the Ph8 pair row. Build note: an unlocked `homing_missile` flies along
  `Vector2.UP.rotated(rotation)` (`_fly_forward`), so set `rotation = heading.angle() + PI / 2`.
- **N4:** kept, as round 1 allowed.
- **N5, resolved.** `station_reinforcements.gd` joins the scan (so the "read ≥ N files" sanity should count it), and `emp_mine` /
  `EMP_MINE` is flagged in `.gd` too. Both have boundaries.
- **N6, resolved.** The 28.3 game s cap (≈ 1.8 s wall at 16×) is paid only on a failure; the expected lock at ≈ 8–9 s keeps
  the row near 0.6 s, inside the 2.5 s allotment with the other two replays.

No remaining findings.
