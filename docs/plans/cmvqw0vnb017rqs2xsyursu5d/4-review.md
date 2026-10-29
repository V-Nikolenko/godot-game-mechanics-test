# Round 1

VERDICT: CHANGES_REQUESTED

Reviewed against epic plan `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` (For every task, §2.7, §2.8–§2.10, §2.15, §2.19, §2.20), `CLAUDE.md`,
`tests/README.md`, DECISIONS.md Phase 8, and the code listed below.

## What holds up (checked, no change needed)

The plan builds what §2.7 and §2.19 ask for. I checked these claims against the code:
- **`_ready` order.** Children are ready before the root, so `brain.rng` is already seeded (`enemy_brain.gd:55-59`) when `DefenseTurret._ready()`
  hands it to the mounts.
- **Pool container.** Root-child pools resolve the turret's parent as their container (`bullet_pool.gd:63`), so rounds land in the enemy container.
- **Mover-less tick.** `BaseEnemy._physics_process` ticks a brain with no mover (`base_enemy.gd:115-120`), and `is_ai_driven()` is false
  without one (`:148`).
- **Escape flag.** `counts_as_escape` is copied from the config in `_ready` (`base_enemy.gd:103`). `ScoreTracker` reads it at registration
  (`score_tracker.gd:142`) and skips the combo penalty when it is false (`:219`).
- **Mining beam.** `BeamBehavior` treats a layer-1 body with `is_laser_blocking() == false` as a target, not a blocker (`beam_behavior.gd:64-70`).
  Row 14 can therefore fail on a blocking root.
- **Pulse pool size.** 4 · ceil(8 / 2.96) = 12 is right for `pulse_round.tscn` (`max_time` 8, 300 px/s).
- **Line of sight.** `LineOfSight` masks ENVIRONMENT | HAZARD_CONTACT and excludes the actor's RID, so the turret body never blocks its own ray.
- **No `ContactHitBox`.** NONE with a null hitbox is safe (`contact_profile.gd:117-119`).
- **Single-writer gate.** `test_enemy_mover_single_writer.gd` cannot see the turret: there is no mover reference in its scene, and `assault_drift.gd`
  sits outside the swept directories. The brain writes no `actor.` motion.
- **Roster count.** There are 13 `BaseEnemy` directories today, so `_MIN_ROSTER_SIZE` 14 is right.
- **Separate tow row.** It is a legitimate reading: `_REFUSING_PHASES` needs an accepting phase (`test_base_enemy.gd:509-516`).
- **ScoreTracker frame.** Freeing a node runs during the frame's `_flush_delete_queue`, so one awaited `process_frame` is enough.
- **Shared `TurretMount` base.** A cycle in the base class with weapon hooks in subclasses is the right shape for t7, t8 and t11. Having the slot carry
  `turn_rate_override` matches what t11 needs.

## Findings

### B1 (blocking): row 4 measures the cone from the muzzle, but the mount gates it from the pivot

**Where.** `3-plan.md` row 4 compares each round's heading with `aim_point() − muzzle`. The plan defines `aim_error()` as the angle between
`global_rotation` and `(aim_point − global_position)`, which is measured from the mount's pivot, and the burst cannon fires only while that error is
≤ `fire_cone_deg / 2`.

**Why it fails.** The muzzle sits 28 px out along +X. When the error from the pivot is θ, the error from the muzzle is larger. With θ = 4° (the cone
edge) and the aim point 300 px away, the error from the muzzle is asin(300 · sin 4° / 272.1) ≈ 4.41°. That is 0.4° past the row's
`+ 0.01°` tolerance.

The jump in row 4 is designed to make the mount re-enter the cone at its edge. So a correct implementation fails the row, and the likely "fix" is to
loosen the tolerance until it passes.

**Fix.** At each `round_fired`, assert either of these, within 1e-4 rad:
- `mount.aim_error() ≤ fire_cone_deg / 2`, or
- the round heading against `aim_point() − mount.global_position`.

Keep the `shots_held > 0` boundary.

### B2 (blocking): `scan()` throws away the cooldown, so a turret whose perception flickers fires faster than its exports allow

**Where.** Under "Other inputs", `scan(delta)` from any live phase runs `_stop_weapon()` and then enters SCAN. That includes COOLDOWN. After
re-perception the path back to firing is NOTICING 0.3 s → TRACK → TELEGRAPH 0.4 s → FIRE.

**How it happens.** In Assault, perception is just "centre inside `view_rect()`". The view's x edges move with `ArenaCamera.offset`
(`arena_camera.gd:102-104`). A turret near a side edge goes in and out of perception as the player strafes. Each flicker skips the remaining
cooldown, so bursts can come about 1.1 s apart instead of 2.96 s.

**What it breaks.**
- The "cooldown from exports" contract.
- The pool-size derivation, which assumes `min_burst_period` = charge + burst + cooldown. Five bursts in flight need 20 rounds against a pool of 12,
  and `BulletPool.acquire` then logs `push_warning` on every miss (`bullet_pool.gd:81-84`).

**Fix.**
- Keep a `_cooldown_left` that counts down in every phase, SCAN included.
- TRACK may not enter TELEGRAPH while it is > 0.
- Only `power_down()` clears it.

Add a row: fire a burst, drop perception for 0.2 s (move the stub out of `lose_radius` in Open Space, or make the turret's centre leave
`view_rect()`), then restore it. The next first round must come no earlier than the last round + `cooldown_seconds` + `charge_seconds` − 1 tick.

### B3 (blocking): the gate-time estimate is not credible

**Where.** The Risks section says "about 6 s of simulated ticks per harness".

**Why that is wrong.** Rows 4, 5 and 6 alone are 6 + 6.5 + 9 = 21.5 s per harness, and rows 1, 2, 3, 7, 8 and 12 add several seconds more. That
cost is still small, because hand-ticking is cheap. The real cost is elsewhere:
- About 28 parameterised cases, at roughly 0.02–0.06 s each (epic §2.20).
- Four real-physics cases at 8×: rows 13 and 14, each run in both harnesses. Each costs about 0.25–0.5 s; t4 of Phase 7 measured one 8× row at
  about 0.5 s (`tests/README.md` gate table). Row 13 alone spends up to 3 s of game time per harness.

A realistic total is about 1.8–2.4 s against the 1.5 s allotment. The plan names no lever.

**Fix.** Add a per-row estimate and build the cheap form in from the start:
- Run rows 13 and 14 in one 8× world per harness: first the wreck and line of sight, then free the wreck, then the beam driver.
- End each "a round within X" wait on the first `round_fired`, polling with X as the timeout, rather than waiting a fixed X.
- Run row 1's "root never rotates" check inside row 2's run.
- Name the fallback lever, in line with §2.20: share a scenario before trimming anything else.

### N1 (non-blocking): row 2's geometry and time bound are off

**Geometry.** T + (−300, 0) is 90° from the rest bearing (90° is down), not opposite it.

**Time bound.** If the stub really is placed opposite, the turn can take up to π/2 s plus the 0.3 s NOTICING. That exceeds the stated
`π / turn_rate + 0.1 s`.

**Fix.**
- Use `start_engaged` and time from the first tick, or add `notice_time` to the bound.
- Measure Δrotation with `angle_difference`, so an implementation that wraps its rotation does not jump by 2π.

### N2 (non-blocking): row 12's "rounds keep moving" cannot be observed in a hand-ticked row

`EnemyBullet` moves only in its own `_physics_process` (`enemy_bullet.gd:41-42`). With no awaited frames, nothing moves, so "`_active` unchanged
over 2 s" is trivially true.

**Fix.**
- Step each in-flight round's `_physics_process(DT)` by hand and assert that it moved and is still valid in the container.
- Assert "no further acquire" with `round_fired` count 0 and `_idle.size()` unchanged.

### N3 (non-blocking, recommended): make the base cycle's hooks general enough that t7 and t8 only subclass

**What is missing.**
- `_tracks_during_telegraph()` is a single boolean. The lance tracks for the first 0.5 s of TELEGRAPH and is frozen for the last 0.5 s (§2.8).
- FIRE always "aims and turns". The beam cannon and the sweep must not re-aim in ACTIVE.
- The TRACK → TELEGRAPH condition (range, cone, `can_fire`) is fixed in the base. The pulse ring uses `trigger_range` and ignores the cone, and
  t8's `TurretGroup.request_telegraph()` stagger also has to gate that same transition.

**Fix.**
- Replace the boolean with a virtual `_tracks(phase, phase_clock) -> bool`.
- Add a virtual `_wants_telegraph(target, can_fire) -> bool`.
- Add a `telegraph_gate: Callable` that the host may set; the default always returns true. This keeps the "never reads its host's type" rule.

These cost a few lines now and save t7 and t8 from editing the base cycle.

### N4 (non-blocking): row 13 setup

Follow the existing wreck rule (`test_fighter.gd:1433-1462`, from `test_sniper.gd`):
- A still `wreck_medium` with `set_physics_process(false)`.
- Await 2 physics frames before the turret starts ticking, so the ray can see the body.

In Assault the turret drifts during the row (300 → about 390 in 1.5 s). The geometry stays valid (wreck at 500, player at 700), but state it in the
plan.

### N5 (non-blocking): the new tow row in `test_base_enemy.gd`

**Leak trap.** Reach the brain with `get_node("Brain")` and its phases with `get_script_constant_map()["Phase"]`, as `test_base_enemy.gd:492-516`
does. Never name `DefenseTurret`, `DefenseTurretBrain` or `TurretMount` statically; see the leak note at `:129-137`.

**Assertions.** In all four phases, assert both `brain.accepts_tow() == false` and `turret.accept_tow(v) == false`. The second one alone is vacuous
because there is no mover.

**Record it.** Log this deviation from §2.19's "add to the table" in DECISIONS.

### N6 (non-blocking): row 5 timing comparison

"At least `charge_seconds` after TELEGRAPH" compares 24 · (1/60) with 0.4 in floating point. Allow 1e-6, as t2 does for its phase lengths.

### N7 (non-blocking): `pool_specs()` creates a round instance

The "throw-away instance" of the round must be `free()`d at once, or it is an orphan at exit (`scripts/check-test-leaks.sh`). Alternatively, read
`max_time` with `EnemyBeamScenes.export_of_scene(round_scene, &"max_time", fallback, ^"ProjectileLifetime")`; `pulse_round.tscn` authors that
override, so the read works.

### N8 (non-blocking): fallbacks for gate reads

When reading through `TurretMountScenes.export_of`, pass `Script.get_property_default_value()` as the fallback (t2's rule). An editor resave drops
values that equal the script default.

### N9 (nit): names that shadow built-in functions

- The `range` export shadows the built-in `range()`. It runs fine on 4.6.3; I probed it headless, and `for i in range(3)` still works in the same
  script. The editor will likely raise a shadowing warning, though.
- The `round_fired(round: Node2D)` parameter shadows the built-in `round()`.

Prefer `fire_range` and `projectile`.

### N10 (non-blocking): the acceptance criterion "the mount writes only its own rotation" is only half covered

Row 1 checks only the root's rotation. Also assert that, after 3 s of tracking, these are unchanged:
- the root's `global_position` (Open Space),
- the `MountSlots` transform,
- the `Slot0` transform.

### N11 (non-blocking): small precision items

- **Row 10.** Emit `enemy_spawned_orphan` only after `add_child`, because `counts_as_escape` is read from the live node.
- **Row 9.** Read the drift speed from the shipped `.tres` (`assault_drift_speed`) rather than typing 60.
- **`rest_bearing_deg`.** State that it is local to the mount's parent, so a rotating Phase 10 host droops relative to its hull.

# Round 2

VERDICT: CHANGES_REQUESTED

Revision 2 answers round 1 well. B1, B2 and B3 are fixed as asked, and N1, N2 and N4–N11 are fixed inline. The new hook table (N3), checked
against epic §2.8 and §2.10 and the real `EnemyBeam` and `EnergyRing` code, still leaves out the one hook that every owner-ticked weapon needs.
Row 3's own timing also cannot be met. Both fixes are small.

## Round 1 items, checked

### Fixed

- **B1.** Row 3 now asserts `mount.aim_error()` from the pivot, and that the heading equals the mount's facing. That is the quantity the mount gates
  on.
- **B2.** `_cooldown_left` counts down in every phase, SCAN included. TRACK → TELEGRAPH is refused while it is > 0, and only `power_down()` clears
  it.
  - Row 5 can fail without the fix. Without it, the next round would come about 0.2 + 0.3 (NOTICING) + 0.4 (charge) ≈ 0.9 s after the last one,
    against a required 2.6 s.
  - The `cooldown_left()` control is good.
- **B3.** The table is credible.
  - Row 15 needs about 2.2 s of game time per harness with the early exits: (a) 1.5 s fixed, (b) about 0.4–0.8 s, (c) a handful of ticks. At 8×
    that is about 0.3 s each, against the 0.25 s estimated.
  - The levers are concrete and keep every assertion.
  - The shorter (a) window still proves the hold. Charge 0.4 + two bursts' worth is about 1.12 s, which is more than the worst ungated
    time-to-first-round: a turn of 0.39 s plus the 0.4 s charge.
- **N1.** The stub at T + (0, −300) really is opposite the 90° rest bearing. From any start in [45°, 135°] the worst turn is 180°, which takes π/2 s,
  so the bound `π / turn_rate + 2·DT` with `start_engaged` holds. Δ is now measured with `angle_difference`.
- **N2.** Row 12 hand-steps the in-flight rounds and checks `_idle.size()`.
- **N4.** Row 15 uses a still wreck and awaits 2 physics frames. The Assault geometry still holds: turret 300 → 390, wreck 500, player 700.
- **N5.** The tow row reaches the brain by node name, uses the phase map and makes both assertions.
- **N6, N8, N9, N10, N11.** Done.
- **N7.** I probed it headless on 4.6.3: `EnemyBeamScenes.export_of_scene(pulse_round.tscn, &"max_time", -1, ^"ProjectileLifetime")` returns
  `8.0`, so the inherited scene's override is read.

### Blocking

#### R2-B1: no hook ticks the weapon outside FIRE, so t7 and t8 would have to edit the base cycle

**What the plan says.** `_fire_tick` runs only in FIRE. TELEGRAPH advances the mount's own clock to `_telegraph_seconds()`. COOLDOWN, SCAN (after
`_stop_weapon()`) and UNPOWERED ("every later tick only droops") call nothing in the subclass.

**What the weapons need.** `EnemyBeam.tick()` is the beam's only clock (`enemy_beam.gd:138-149`), and `EnergyRing.tick()` is the ring's
(`energy_ring.gd:115`).

**What goes wrong.**
- **TELEGRAPH.** A beam started in `_on_telegraph_start()` is never ticked during TELEGRAPH. Its TELEGRAPH → ACTIVE clock only begins in FIRE, so
  the shot is late by a whole telegraph. Beyond that, the mount and the weapon have two independent clocks for the same phase change.
- **COOLDOWN and UNPOWERED.** A beam or ring that `cancel()` or the end of ACTIVE sends to FADE (`enemy_beam.gd:152-158`, `_advance` `:211-219`)
  is never ticked again. It stays drawn mid-fade forever: after every ACTIVE, in COOLDOWN, and after `power_down()` in UNPOWERED. §2.8's row
  "mid-ACTIVE → FADE within one tick" only passes because the fade never ends.

**Fix.**
- Add `_weapon_tick(delta)`. The base calls it once per `tick()` and `scan()` in **every** phase, UNPOWERED included. The default does nothing;
  the burst cannon does not need it.
- Add `_telegraph_done() -> bool`, with the default `clock ≥ _telegraph_seconds()`. t7's beams answer from `beam.phase() == ACTIVE`, so a single
  clock decides the transition.
- Pin both with one structural row: a fixture `TurretMount` subclass that counts `_weapon_tick` calls in each phase, including after
  `power_down()`.

#### R2-B2: row 3 cannot reach "2 rounds after the jump" inside its 6 s timeout

**The timing.** Without `start_engaged`:
- First round ≈ 0.3 (NOTICING) + ≤ 0.4 (turn) + 0.4 (charge) ≈ 1.1 s.
- Second burst's first round ≈ 1.1 + 0.36 + 2.2 + 0.4 ≈ 4.06 s. The jump happens here.
- A 400 px jump at about 330–500 px range is roughly a 70°–100° turn, about 0.6–0.9 s. That is longer than the rest of the burst (0.36 s), so every
  remaining shot is held.
- The next rounds come at about 4.06 + 0.36 + 2.2 + 0.4 ≈ 7.0 s.

**Result.** The row times out. Either it fails on a correct build, or it never sees a round fired near the edge of the cone, which is the case B1
was about.

**Fix.**
- Set `start_engaged`.
- Jump at the **first** burst's first round.
- Size the jump to about 15° of bearing (move the stub 2 · 300 · sin 7.5° ≈ 78 px across, at its distance), so the mount comes back inside the 4°
  half-cone within the burst. Then at least one shot is held, and the next due shot leaves near the cone edge.
- Keep `shots_held > 0`, and also require at least one round fired after the jump within the same burst.
- Use a timeout of about 3 s. The row then also gets cheaper.

### Non-blocking

- **N2-1: the `telegraph_gate` contract.** State the signature (`telegraph_gate.call() -> bool`; the host binds itself, e.g.
  `group.request_telegraph.bind(self)`), and that the gate is consulted **last**, only when the cooldown, `_wants_telegraph()` and the turn checks
  have all passed. §2.10's `request_telegraph` uses up the group's 0.3 s stagger window when it grants, so a gate asked while the mount is still
  out of the cone would waste grants and starve its group-mates. On refusal the mount stays in TRACK and asks again next tick, matching §2.10's
  "retries next tick".
- **N2-2: an interrupted FIRE should still start the cooldown.** "Set to `cooldown_seconds` when a FIRE ends" should also cover a FIRE ended by
  `scan()` (perception lost mid-burst). Otherwise a burst cut after 2 rounds, plus a re-perception, gives 2 + 4 rounds within about 1 s.
  Rule: any exit from FIRE except `power_down()` sets the cooldown.
- **N2-3: row 4's tick order.** Its lower bound (`≥ cooldown + charge − 1e-6`) relies on the cooldown and the TELEGRAPH clock both starting to
  count on the tick **after** they are set or entered. Say so in the cycle table, so the implementation and the row agree. Row 5 uses `− DT`,
  which is fine.
- **N2-4: record the `fire_range` rename in DECISIONS** (§2.7 and §2.10's coverage rule say "range"), so t9 reads `fire_range`.

# Round 3

VERDICT: APPROVED

This approval is conditional on two amendments, A1 and A2 below. Both are numeric details with the exact replacement written out, so they need no
further design review. The implementer must apply them; a build that skips them fails row 3 and row 4 on correct code.

## Round 2 items, checked

- **R2-B1 is fixed.**
  - `_weapon_tick(delta)` now runs once per `tick()` and `scan()` in every phase, UNPOWERED included, after the cycle step. A beam or ring started
    in `_on_telegraph_start()` is ticked from that same tick. A FADE begun by `cancel()` or by the end of ACTIVE finishes in COOLDOWN, SCAN and
    UNPOWERED, because `EnemyBeam.tick()` and `EnergyRing.tick()` are their only clocks.
  - `_telegraph_done()` lets t7 hand the TELEGRAPH → FIRE step to the beam's own clock.
  - Row 16 pins the per-phase count, and the fixture's flag shows the hook decides the step.
  - Checked against §2.8: sweep, lance and beam cannon fit `_tracks`, `_on_telegraph_start`, `_weapon_tick` and `_telegraph_done`. The ring fits
    `_wants_telegraph` and `_weapon_tick`. The rocket battery fits `pool_specs` with persist, `fires_past_cover`, `_fire_tick` and `rng`.
  - Checked against §2.10: the stagger fits `telegraph_gate`, which is asked last and asked again on the next tick.
  - t7 and t8 now only subclass.
- **N2-1, N2-2, N2-3 and N2-4 are fixed.** Row 5(b) can fail without the "any FIRE exit except power-down starts the cooldown" rule.
- **R2-B2 is answered, but the geometry I suggested in round 2 was wrong.** See A2.

## Required amendments

### A1: compare clocks with an epsilon, or the plan's own tick counts are wrong

**What the plan claims.** The "Tick order" section says a 0.4 s charge fires on tick k + 24, and a 2.2 s cooldown frees TRACK on tick k + 132.

**What naive accumulation gives.** I measured this headless on Godot 4.6.3:
- adding `1/60.0` until it is `≥ 0.4` takes **25** ticks;
- subtracting `1/60.0` from 2.2 until it is `≤ 0` takes **133** ticks.

**What breaks.** Row 4's gap then becomes 133 + 1 + 25 = 159 ticks, which is 2.65 s. Row 4's upper bound is `cooldown + charge` + 2 ticks, which
is 2.633 s, so the row fails on a correct-looking build.

**Fix.** Use `EnemyBeam`'s rule (`EPS := 1e-6`, `_t + EPS >= duration`, `enemy_beam.gd:41, 213`):
- `phase_clock + EPS ≥ _telegraph_seconds()` in the default `_telegraph_done()`;
- `_cooldown_left ≤ EPS` wherever the cooldown is tested.

With that, the gap is 132 + 1 + 24 = 157 ticks, which is 2.617 s, inside [2.6 − 1e-6, 2.633]. Add it to the "Tick order" section.

### A2: row 3's jump of about 15° is too small to hold a shot

My round-2 suggestion forgot that the mount keeps turning during the burst gap.

**Why 15° fails.**
- After the jump, the next due shot comes 7 or 8 ticks later (`burst_gap` 0.12 s is 7.2 ticks, and BurstClock subtracts rather than resets).
- In those ticks the mount turns 2.0 rad/s × 0.117–0.133 s, which is 13.4°–15.3°.
- A 15° jump is therefore back inside the 4° half-cone by the 2nd shot, nothing is held, and `shots_held > 0` fails.
- With the stub still crossing (≈ 38°/s at 300 px) and a lead aim point that moves too, the outcome depends on which way the jump goes.

**Fix.**
- Keep the stub **standing still** in row 3, so aim = P and the change in bearing is exactly the jump. The lead is already row 2's job.
- After the first round, teleport the stub around T at constant distance by `θ = 1.6 · turn_rate · burst_gap`, read from exports (≈ 22°). Then:
  - at the 2nd shot (≤ 0.133 s) the error is ≥ 22 − 15.3 = 6.7° > 4°, so that shot is **held**;
  - at the 3rd shot (≥ 0.223 s) the mount has turned ≥ 25.6°, so that shot **fires**.
- Assert that the 2nd round was held, that at least one later round of the same burst fired, the per-round pivot `aim_error()` check, and that the
  heading equals the facing.
- Keep the 3 s timeout and `start_engaged`.

## Non-blocking

- **One tick in the light for beams.** For beams, `_telegraph_done()` reads `beam.phase() == ACTIVE`, which `_weapon_tick` sets in step 4. The mount
  therefore enters FIRE one tick after the beam turns lethal, and for that tick the light still shows CHARGING. This is harmless, but t7 should
  know about it; it could check `_telegraph_done()` again after `_weapon_tick`.
