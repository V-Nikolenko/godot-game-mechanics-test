VERDICT: CHANGES_REQUESTED

Reviewer: independent plan review of `3-plan.md` (t19, epic §2.18), against the code on `agent/auto-dev` @ `8d2af49`. The design is right and
most of the plan's claims about the code check out (verified list at the end). Two things need amending before implementation. Both are small:
one gate predicate is not conservative, and one attack row has no boundary. A few notes follow that the implementer should act on but that do
not block.

## Required changes

**R1. The column-clearance row's lit window ends too early, so as written it is not a worst-case gate.**
`assault/scenes/hazards/laser_ray/laser_ray.gd:182-188, 205-218, 248-255`: `start()` holds the warning line for `warn_duration` (timer). Then
`laser_increase` plays, and only when it *finishes* does the ray go IDLE, turn `monitoring` on (the kill) and start the `active_duration` timer.
`_begin_dissolve()` turns monitoring off. So the lethal window is `[time + warn + increase, time + warn + increase + active]`. `laser_increase` is
7 frames × 0.4 at speed 5 = **0.56 s** (`laser_ray.tscn:218-222`). Plan §C.3 filters columns by `[time, time + warn + active]`, which stops 0.56 s
before the beam actually goes dark. For this placement it makes no difference: the members live 3.5 → ≤ 31.6 s, and every deep_space row
(6 / 14 / 22 s) overlaps either way. But the row exists to gate *future* static placements, and a member spawning in that last 0.56 s gap would pass
while it sits in a lethal beam. Fix it one of two ways:
  - (simpler, stricter, and still green for this placement) drop the time filter and check every column of the section, or
  - extend the window end by the `laser_increase` length, read from `laser_ray.tscn`'s `SpriteFrames` (frame durations / speed), never typed.
Either way, keep the revision-1 boundary.

**R2. The tender's attack-in-budget row has no boundary.**
Plan §E and the Test plan give the twin pair a boundary (private `engage_seconds` 1.0 never reaches ADVANCE), but not the tender. The tender row
asserts LAUNCH with budget left, exactly one `launched`, and the launched rig reaching ADVANCE. Every earlier attack-in-budget row has a
"same predicate, short budget, fails" companion: the Ph7 layer (`test_mine_layer.gd:1726-1745`), the support (`test_support_ship.gd:1865-1880`)
and the corvette (`test_missile_corvette.gd:1323`). Add one for the tender: its private `engage_seconds` cut so that the budget runs out before it
reaches the hold band and the view, giving no LAUNCH and no `launched`. Assert the shipped `.tres` is untouched. This one is cheap, because the slice
stops at the tender's DISENGAGE. A boundary for the turret row is recommended, not required (see N6).

## Notes (act on them; not blocking)

**N1. `Slice.run()` hands `observe` only the first target.** `tests/helpers/level1_slice_replay.gd:131-134, 166-170`: `observe(ship, t)` gets `_target`,
the first ship whose `scene_file_path` matches. The turret row has two `defense_turret.tscn` targets and the pair row has two `twin_laser_drone.tscn`
targets, so the second has to be collected in the `tweak` callback, which runs for *every* target. The Ph7 layer row already uses its hook that way.
Say this in the plan, and assert `out["targets"] == 2` for both rows. Targeting by member scene path does work: `TurretGroup.spawn_members()`
(`turret_group.gd:84-115`) and `TwinLaserPairSpawn.spawn_pair()` (`twin_laser_pair_spawn.gd:31-58`) both `add_child` into the container, so
`child_entered_tree` sees them, and both member kinds are `BaseEnemy`.

**N2. Two existing level-1 slice rows now replay Ph8 traffic.** The deep_space support slice `[25.0, 37.0)` (`test_support_ship.gd:1819-1821`,
engage 9) and the deep_space Mine Layer slice `[15.0, 32.0)` (`test_mine_layer.gd:1662-1664`) both contain the 29.0 s wave, and therefore the twin
pair, whose beam hurts enemies. Both rows should stay green: the support row stops once its shield is up, about 3 s after its 26.0 s spawn, and
the layer row stops 0.5 s after its DISENGAGE, both before the pair can form and advance (≥ about 31 s). Still, name them under Risks and check them
by name after the director edit. None of the specialist / corvette slices contains the 3.5 s group wave.

**N3. The column measurement's "nothing shoots in this world" premise no longer holds.** `tests/helpers/level1_column_replay_worker.gd:15-19`
counts a `died` whose origin lies inside a lit ray's rect as a column kill. The twin beam and the turret's `EnergyRing` hurt AI enemies, so a
friendly-fire death inside a lit rect would now count as a column kill. When you record the post-placement counts in DECISIONS, note this, or have
the worker exclude deaths during a Ph8 beam or ring hit.

**N4. The "worst case" drift life ignores camera shake.** `wave_manager.gd:194` uses `cam.offset`, which includes `CameraShake.get_offset()`, up to
`_MAX_OFFSET` 8 px (`global/systems/camera_shake.gd:22, 43-50`), on top of the clamped −380. The highest spawn can sit 8 px higher, adding up to
0.13 s of life. No peak changes: nothing specialist starts in deep_space after 29.0 s, and the members end before any later start. Either add
the 8 px (read the constant) or say in the row's comment why it is excluded. Do not claim "worst case" without one or the other.

**N5. Cache the Ph8 lives once per file.** Every call to `PH8_EXITS.drone_exit()` / `tender_exit()` rebuilds `corridor_starts(host)` (an
`ArenaCamera` plus about 2166 starts) just to form the memo key (`tests/helpers/ph8_exit_keys.gd:26-35, 63-68`). Since `_ai_intervals()` is called
by several rows, compute `_ph8_lives()` once (in `before_all()` beside the Ph5 / Ph7 probes, or as a member cache), not per call.

**N6. The turret row can fail, but nothing proves the observer can see a miss.** A cheap boundary, if it fits the 3.5 s allotment: the same slice
with each turret's private config made blind (e.g. `perceive_radius` 0 via the tweak), giving no FIRE. Also cap that slice's `length` explicitly at
the members' computed life, so a red row cannot run on.

**N7. The `persist == false` sanity.** Build it the way `TurretGroup.mount_reaches()` does (`turret_group.gd:156-178`): the slot's `variant`
overrides mount index 0, and the others come from the turret's `MountSlots`. Instance each through `TurretMountScenes.scene_for(v)` and call
`pool_specs()` off-tree. That works: `burst_cannon_mount.gd:38-47` reads only exports and returns `persist: false`, and the pulse ring keeps the base
class's empty list (`turret_mount.gd:161-163`). Make the row fail on a `rocket_battery` (`persist: true`, `rocket_battery_mount.gd:42-53`) as its
boundary.

**N8. Engagement-deadline boundaries.** The three life boundaries in §D (tender 11.1 s, pair 11.22 s, group ≥ 13.4 s from the lowest view:
spawn y 740 − 440 + 60 = 360, then (1164 − 360) / 60) are correct lower bounds against cloud_descent's 10 s. The laser fence keeps only its
detection boundary (`test_engagement_deadline.gd:924-935`). That is acceptable, because level 1 places no fence and C.3 asserts that it does not.

## Verified against the code (the plan is right on these)

- **Drone deferral.** `TwinLaserPair.is_committed()` covers TELEGRAPH / ADVANCE only (`twin_laser_pair.gd:167-168`). `EngagementBudget.update()`
  is sticky once expired (`global/enemy_ai/engagement_budget.gd:37-44`). `_decide()` disengages on `expired or advances_started > 0` whenever the rig
  is not committed (`twin_laser_drone_brain.gd:205-210`). TELEGRAPH ends one leader tick after the beam goes ACTIVE (`twin_laser_pair.gd:341-345`),
  which `_TICK_SLACK` covers. Every Assault advance is ≤ `standoff + overshoot`: `assault_frame()` at `:577-605` and `_launched_advance()` at
  `:291-296`. So `engage + telegraph + (260+200)/240 + slack + exit` is a true bound. A launched drone's budget starts at its own first tick
  (`_setup()`, `:142-150`). LAUNCHED (≤ 1.4 s + 2 ticks) cannot outlast 8 s, and an expiry in FORM / BREAK / COLLAPSED disengages at once.
- **Tender bound.** An expiry outside LAUNCH goes to DISENGAGE before `_decide()` runs, so the tender never launches after its budget. An expiry
  inside LAUNCH sets `_leave_after_launch` and the launch fires at `launch_telegraph` (`laser_tender_brain.gd:78-84, 236-237, 345-353`). So a launch
  happens no later than spawn + engage + 0.6 + slack, as §B states.
- **Drift life.** Spawn = `cam.global_position + cam.offset + offset·2` (`wave_manager.gd:194`); offset y is clamped to ±380 (`arena_camera.gd:139-143`);
  `AssaultDrift` frees strictly below `projectile_world_rect().end.y` = 1164 (`global/components/assault_drift.gd:29-36`). Ring −520 gives 28.07 s,
  power −460 gives 27.07 s and burst −400 gives 26.07 s, which are correct (modulo N4). Members have no `EnemyMover`, so no tow or push can stretch
  this (`base_enemy.gd:148-162`, `defense_turret.gd:4`).
- **World-anchored x.** `turret_group.gd:65-69` subtracts the view-centre pan, which includes shake, in the same frame the spawn read it, so members
  land at 640 + 2·(−64) + slot.x = 462 / 512 / 562. Clearances to the nearest deep_space columns are 78 / 128 / 78 against 56 / 62 / 56 (hurtbox =
  body circle r 28 / 34, `defense_turret.tscn:13-14, 65`, `power_source.tscn:14-15, 66`). Revision 1's (0, −220) puts the power source at 640 and
  fails.
- **Reads that work.** `get_script_method_list()` exposes `_spawn_laser_columns`'s `default_args` = `[3.0, 4.0]`, and `LaserRay._BEAM_WIDTH` is
  readable (56.0). Both were confirmed with a one-off headless script. `EnemyBeamScenes.export_of(TWIN, &"telegraph_seconds")` resolves to 0.8
  (`twin_beam.tscn:8`).
- **Density.** deep_space: 7 base at 29.0 s, plus 3 members (to ≤ 31.6 s) plus 2 drones, gives 12 ≤ 12.5. At 16.0 s and 26.5 s it is 8 + 3 = 11.
  planet_approach: at 28.4 s, 2 tender drones (to 29.21 s) + the 16.0 s sniper + the 28.0 s ram + the support + 2 rams = 7 ≤ 7.5. At 32.0 s the drones
  are gone, giving 6. The three existing boundaries that assert "planet_approach peaks at 7" (`test_level1_specialist_spawns.gd:502-537, 758-783,
  952-977`) survive: `_peak()["at"]` becomes 28.4, the inserted wave lands before the 32.0 s wave in list order with effective trigger 28.4, and
  7 + 1 (or + 3) exceeds 7.5. Only their comments change, as §C.5 says.
- **Spill-over.** deep_space's deadline is 30 + 30 + 0 = 60 s and the pair ends ≈ 45.6 s. planet_approach's is 186 s. `_ordnance_tail()` returns 0
  for the new kinds, which is right: burst rounds are `persist: false`, the ring is a mount child, the twin beam is a child of drone A.
- **No unexpected breakage elsewhere.** `test_level_1_sequence.gd` spawns nothing, because `_spawn_ship()` returns without a `Camera2D`. The fighter
  density / exit and drone gates filter by scene path. The sniper / ram level-1 rows spawn their own offsets only.
- **Exits.** Both come through `ph8_exit_keys.gd` with its static `prepare_probe`, so they are memo hits after `test_laser_tender.gd`, which sorts
  first.

## Round 2

VERDICT: APPROVED

I re-read the revised `3-plan.md` against the round-1 findings and checked the new figures against the code.

- **R1 is resolved.** §C.3 now checks every column of the member's section whose start time is before the member's life ends, with no end filter
  and no start filter. That is a superset of the real lethal window `[time + warn + 0.56, time + warn + 0.56 + active]`, so a lit column can no
  longer be missed. For this placement every deep_space column (6 / 14 / 22 s) starts before the members leave (≤ 31.7 s), so the row checks all
  seven columns, and the revision-1 boundary still fails on the power source at 640.
- **R2 is resolved.** §E adds a tender boundary: with a private `engage_seconds` of 0.5, the tender never reaches LAUNCH and launches nothing, and the
  slice stops at its DISENGAGE. One caveat for the implementer, which can only turn the boundary red, never make it vacuous: if a tender ever entered
  LAUNCH inside 0.5 s it would still launch (`_leave_after_launch`, `laser_tender_brain.gd:78-82`). In the slice it spawns about 40 px above the view
  top (y ≈ 180 against a view top of 220), and `_can_launch()` needs it inside the view and in the hold band, so it cannot. Assert the shipped `.tres`
  is unchanged, as the earlier boundaries do.
- **N1 is resolved.** The second turret and the second drone are collected through `tweak`, and each row asserts `targets == 2`.
- **N2 and N3 are under Risks.** The DECISIONS note on contamination is enough. Counting the brainless power source in the worker is a sensible
  extension, because it is the one static member a column would kill.
- **N4 is resolved.** The highest spawn now includes the 8 px shake: 360 − 380 − 8 − 440 − 60 = −528, giving (1164 + 528) / 60 = 28.20 s.
  With slack, the members end by ≈ 31.73 s, so the deep_space peak stays 12 at 29.0 s (nothing specialist starts later) and the deep_space spill-over
  deadline of 60 s is unaffected. Read the 8 from `CameraShake`'s `_MAX_OFFSET`, never typed. If the autoload constant cannot be reached from the
  test, preload `global/systems/camera_shake.gd` and read it from the script.
- **N5 is resolved** (the Ph8 lives are cached once per file). **N7 is resolved:** the mounts are read the way `mount_reaches()` reads them, and
  the `ROCKET_BATTERY` case fails. **N6** is declined for gate time. That is acceptable: the turret row asserts a positive outcome (FIRE in view)
  for each of two targets, so it fails if either turret never fires.

Nit, not blocking: the "Test plan" summary still lists only round 1's boundaries. Add the tender 0.5 s boundary and the `ROCKET_BATTERY` persist
case there too, so the list matches §C and §E.
