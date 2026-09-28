VERDICT: CHANGES_REQUESTED

# Review — t8b Swarm Drone solo cycle, plan round 1

Reviewed `3-plan.md` and `1-context.md` against the epic plan (§2.2, §2.3, §2.6, §2.7, §2.7.1, the §4 t8b row), the
epic's round-2 review (B5, N14, N15, N19), and the code itself. I checked the numeric claims with a throwaway
headless script (`/tmp/rv/sim.gd`). It re-implements `EnemyMover.step()`'s `limit_length` / `move_toward` /
braking-selection at 60 Hz and calls the real `Steering` statics.

The design is mostly sound. The B5 fix is right: I replayed it and got **76.2°** of turn with braking 900. The
per-tick heading change stays ≤ 2.4·dt·(1 + 2.4e-6), the speed never drops below 219.99, and no tick turns the wrong
way at 50/100/200/400 px. The pin formula gives 70.3°. Reusing `Steering`, `EngagementBudget`, `ContactProfile`,
`StateLight` and the harness is correct, and nothing is reinvented.

Five problems block approval. Two are mechanisms that do not work the way the plan says. Two make the tests assert
something false or impossible to fail. One makes the deadline gate stop being a real bound.

## Blocking

### B1 — The budget and the brain's fields are built before the config reaches them
Files: `3-plan.md:24`, `:61`; `base_enemy.gd:71-79`; `drone_interceptor.gd:23-36`.

- Godot runs a child's `_ready()` before its parent's. So `SwarmDroneBrain._ready()` runs before
  `SwarmDrone._ready()` copies the config onto "brain fields".
- The plan builds `EngagementBudget.new(engage_seconds, get_tree())` in the brain's `_ready`. `EngagementBudget.seconds`
  is fixed at construction (`engagement_budget.gd:29-31`), so it gets the brain's default, not the `.tres` value.
  The same goes for anything else the brain derives in `_ready` from copied fields, such as `passes_left`.
- The planned tests cannot catch this. If the brain's default happens to be 5.5, "never before `engage_seconds`"
  passes on the broken build.

Required:
- Build the budget (and seed `passes_left`) on the brain's **first tick**. The epic §2.6 already says "It starts
  counting in the brain's first tick". An explicit `configure(cfg)` called from `SwarmDrone._ready()` would also work.
- Add a case that proves the config flows through. Give the drone a config duplicate with a non-default
  `engage_seconds` (for example 2.0) before `add_child`, and assert DISENGAGE starts at 2.0 s and not before.
  - Do the same for "config applied" (`3-plan.md:110`). Today the scene authors the same values the config holds, so
    "health 30, damage 30, blast 48/15" passes even if nothing is copied.

### B2 — `release_lead` on a squad of one makes the drone REAR, not LEAD
Files: `3-plan.md:132`; `squad_controller.gd:117-123`, `:162-186`.

- `release_lead(m)` calls `_reassign(m)`. That removes `m` from `eligible`, which leaves the list empty, so no LEAD is
  assigned. It then runs `_set_role(force_rear, REAR)`.
- The plan's case "`release_lead` at REJOIN keeps it LEAD (squad of one)" therefore asserts something false. The
  implementer would have to either edit `SquadController`, which is out of scope, or weaken the test.
- It also matters beyond this test. `WaveManager` gives every squad-capable spawn a board, a board of one when there
  is no id (t5, `wave_manager.gd:206-207`). So every level-spawned solo drone becomes REAR after its first REJOIN, and
  in t8c "REAR never attacks".

Required: decide, and record it in DECISIONS. Either:
- skip `release_lead` when `squad.members().size() == 1`, and assert the drone stays LEAD; or
- keep the call, assert REAR, and hand the problem to t8c explicitly.

### B3 — Deferring DISENGAGE through a BURST breaks the §2.6 deadline bound, and the plan never updates it
Files: `3-plan.md:61-63`, `:86-87`; `test_engagement_deadline.gd:97-100`; `level_section.gd:35` (default timeout 10.0).

- The plan adopts N19's deferral unconditionally. N19 made it conditional on t15 failing, and paired it with "add
  `burst_seconds` to the formula".
- With the deferral in place, exit can begin up to 0.45 s after `engage_seconds`, and possibly with a reversal from
  480 px/s. The repointed formula leaves both out, so the deadline test is no longer an upper bound. It stays green on
  a worst case it no longer describes.
- Adding the term honestly gives 9.58 + 0.45 = **10.03 s > 10 s**, so the test would fail.

Required: resolve this in the plan. Options:
- Add `burst_seconds` (from the config) to the formula, and buy the 0.03 s somewhere: `engage_seconds` 5.0, or a
  stated smaller margin. Either choice goes in DECISIONS as an epic deviation.
- Or do not defer. Enter DISENGAGE at expiry, keep the profile and light armed while `mover.is_boosting()`, and
  disarm when the boost ends. The boost ignores requests either way, so this has the same timing profile as today's
  formula. It still needs N19's reversal argument stated.

### B4 — The WINDUP facing tolerance fails on the plan's own numbers
Files: `3-plan.md:116`; `enemy_mover.gd:279-287`.

- The facing runs `lerp_angle` with `turn_lerp` 10, capped at `max_turn_rate` 5.0 rad/s. Over the 0.4 s windup
  (24 ticks), the residual facing error depends on the starting offset:

  | Starting offset | Residual error |
  |---|---|
  | 45° | 0.012 rad |
  | **90°** | **0.066 rad** |
  | 135° | 0.366 rad |
  | 180° | 1.142 rad |

- CLOSE_IN flies roughly tangentially, so WINDUP starts about 90° off the aim, and the "within 0.05 rad" assertion
  fails on a correct build.

Required:
- State the test's initial facing.
- Derive the tolerance from `turn_lerp` and `max_turn_rate`, or raise `turn_lerp` or `max_turn_rate` and say so.
- Note that a second-pass WINDUP starts up to about 100° or more off, which is past what 0.4 s at 5 rad/s can close.

### B5 — Three cases cannot fail
Files: `3-plan.md:113-115`, `:129`, `:130`; `arena_camera.gd:40-43`, `:108-111`; `assault_corridor_constraint.gd:27`.

1. **Below-screen spawn** at (640, 1100). The visible rect is (−100, −380)–(1380, 1100), so y = 1100 lies **on** the
   bottom edge. `_axis_state` treats it as inside, and the case passes at tick 0. Spawn clearly outside instead, e.g.
   (640, 1300), and assert it was outside at tick 0.
2. **Burst toward an edge stays inside the hard band.**
   - A burst covers 480 × 0.45 = 216 px, and the overshoot adds at most about 176 px. From a drone starting inside
     `visible`, that total stays under the 450 px `hard_band` even with the mover's constraint set to `NONE`, so the
     case passes without any corridor.
   - Make it discriminating: assert the Assault run's maximum outward excursion is strictly below the same setup's
     `open_space` run, or use a bound the unconstrained path actually crosses.
3. **Far/near/mid prediction.**
   - With a stationary fake player, `predicted_position(t) == position` for every `t`, so `aim == predicted_position(…)`
     cannot tell 0.4 from 0.8. Only the `lead_time` field check discriminates.
   - Give the harness player a non-zero `velocity` perpendicular to the line of sight (the harness allows it), so the
     aim point itself pins the clamp.
   - Also name the seam behind "force WINDUP end", for example: set the phase to WINDUP and tick `windup_seconds`.

## Non-blocking (fix in the revision or record the choice in DECISIONS)

- **N1 — WINDUP "hold" drifts** (`3-plan.md:55`, `:117`).
  - `hold_position(_hold_at = entry pos, 4, …)` uses `arrive` with decel 900. A drone entering at 220 px/s
    overshoots by about 27 px and comes back. The replay ends the 0.4 s windup at **40 px/s, 30 px from the hold
    point**, so "speed decays to ~0" needs a loose tolerance.
  - Hold at the stopping point instead: `_hold_at = pos + v·|v| / (2·braking)`. The replay then reaches 0 by about
    0.25 s. Give the test a numeric threshold.
- **N2 — CLOSE_IN geometry** (`3-plan.md:54`; `steering.gd:214-217`).
  - The anchor moves at 1.4 rad/s × 200–360 px, which is 280–504 px/s. That exceeds `max_speed` 220, so the drone
    chases a point it cannot catch.
  - `radius_rate` −120 is added on top of a ring that the brain is also shrinking at 120 px/s, so the shrink is
    counted twice.
  - The replay dips to **109 px** from the player and settles at about 157 px (v/ω). The exit only fires because the
    band happens to be crossed at 1.33 s.
  - Suggest `radius_rate` 0 while `_ring` shrinks (or a fixed ring with `radius_rate` −120, not both), and an angular
    speed ≤ `max_speed / 200` ≈ 1.1 rad/s.
- **N3 — The corkscrew is imperceptible.**
  - `Steering.corkscrew`'s `amplitude` is a **velocity** (px/s). At 60 px/s and 1.5 Hz the replayed lateral swing is
    ±7.6–7.9 px on a 32 px hull. The legacy `sine()` rails it replaces swing 45 design px (90 world px).
  - The "> 5 px" case passes by about 2.6 px. That is an epic value, so this is not a plan defect, but record it for
    the owner or t15 tuning. Lateral amplitude ≈ `amplitude / (2π·f)`, so for example 120 px/s at 0.6 Hz gives ≈ 32 px.
- **N4 — The placeholder art region is wrong** (`3-plan.md:25`; `1-context.md:8`).
  - `drones.png` is 126×84 in a 3×2 grid, so the cells are **42×42**, not 42×28 (the grid marks sit at y = 42).
  - `Rect2(0, 0, 42, 28)` crops about 9 px off the first drone. Use `Rect2(0, 0, 42, 42)`.
  - Check the nose direction by eye before settling on `sprite_forward_angle = -PI/2`. The legacy Kamikaze draws the
    whole sheet rotated 180°, so it tells you nothing.
- **N5 — The real-physics cases need their drive stated** (`3-plan.md:122-124`).
  - `contact_fixture.build_player()` is not in group `player`.
  - For "no damage in CLOSE_IN", let the brain tick (with a `player`-group node at the hurtbox) for the 10 frames, so
    a brain that arms outside BURST fails the case, not only a mis-authored profile mode.
  - For the blast case, keep the drone still (`set_physics_process(false)`), or it seeks.
  - For "contact while armed", do not assert exact player damage: without i-frames the player takes 30 contact + 15
    blast.
- **N6 — The overshoot-curve setup is unspecified.** With a stationary player the burst runs through the player's
  position, which leaves the bearing near 180° and makes the sign ambiguous. Say how the player is placed 90° off,
  for example by teleporting the fake player at OVERSHOOT entry.
- **N7 — The "uses facing" interpretation** (`3-plan.md:73-76`). This is a reasonable reading and it is flagged. Record
  it in DECISIONS as a clarification of the epic's §4 wording. The other reading is the player's `TargetInfo.facing`.
- **N8 — DISENGAGE picks its edge once, on entry.** N19 assumed the nearest edge is re-chosen every tick. Either is
  fine inside the deadline, but say which.

## Checked and fine

- The single-writer gate is satisfied. The brain only requests or writes fields (`release_constraint`, `max_speed`),
  and `SwarmDrone` adds no `_physics_process`.
- `phase_changed(phase: int)` satisfies the arity gate.
- The contact-damage gate reads `ContactHitBox.damage` after `_ready()`.
- The config-isolation and sprite-transparency gates discover the directory themselves. `drones.png` already passes
  transparency.
- The hurtbox and contact geometry are satisfied by the shared shape id and scale.
- The blast-case geometry is right: contact 13 + player 12 = 25 < 40 < 48 + 12 = 60. The ordering also works:
  `BaseEnemy._on_health_changed` calls `queue_free` first, the profile detonates while the actor is still in the tree,
  and one blast results.
- The rail case works: `EnemyPathMover._ready` → `suspend_ai()` → `set_armed(true)` + `on_suspended()`.

## Round 2

VERDICT: APPROVED

Re-reviewed the revised `3-plan.md` against the code, and re-checked every new mechanism numerically with a
headless replay (`/tmp/rv/sim2.gd`). The replay re-implements `EnemyMover.step()`'s `limit_length` / `move_toward` /
braking selection at 60 Hz and calls the real `Steering` statics. All five round-1 blockers are resolved, and every
new case can distinguish a broken build. Three small things are left; none of them blocks.

### Round-1 blockers — verified

- **B1 (config timing), resolved.** The budget and `passes_left` are now built on the first tick (`3-plan.md:61-65`),
  which matches epic §2.6. "config flows through" uses values that differ from the scene's, and "budget from config"
  uses `engage_seconds` 2.0 (`:140-141`). Both fail on the round-1 design.
- **B2 (squad of one), resolved.** The brain skips `release_lead` when the squad has one member (`:58`, `:86-90`);
  this matches `squad_controller.gd:117-123` / `:162-186`. Both sizes are tested (`:164`). See R2-N2 for one
  precondition the squad-of-two case needs.
- **B3 (deadline bound), resolved in substance.** WINDUP is now gated on `budget.remaining() ≥ 1.14 s` (`:66-73`). I
  checked the tick counts:

  | Stage | Ticks |
  |---|---|
  | WINDUP | 24–25 (float accumulation) |
  | BURST boost | 27–28 |
  | Overshoot until speed ≤ 221 px/s | 18 (0.300 s, not the 0.289 s the formula assumes, because part of the Δv goes on turning) |
  | **Worst total** | **71 ticks = 1.183 s** |

  So a BURST ends by tick 53, well inside the 1.14 s gate. Expiry can never land in a burst, and the §2.6 formula
  stays valid. See R2-N1 for a 43 ms gap in the speed assertion.
- **B4 (facing), resolved.** With `turn_lerp` 20 and `max_turn_rate` 10, the residual facing error after the windup
  is:

  | Starting offset | 24 ticks | 25 ticks |
  |---|---|---|
  | 90° | 0.0004 rad | 0.0003 rad |
  | 135° | 0.0027 rad | 0.0018 rad |
  | 180° | 0.0185 rad | 0.0124 rad |

  All are well under the 0.05 rad tolerance, including the 180° variant. `max_turn_rate` still only turns the sprite
  (D7), so the overshoot curve is unaffected.
- **B5 (cases that could not fail), resolved.**
  - **Below-screen spawn:** (640, 1300) is 200 px below the visible edge at y = 1100, and the case asserts it is
    outside at tick 0.
  - **Edge case:** it now compares the Assault run's excursion against the Open Space run's
    (`assault_corridor_constraint.gd:58-76` filters even a boost), so removing the constraint fails it.
  - **Prediction cases:** the player moves perpendicular at (0, 150), so the 0.8 s and 0.4 s aim points differ by
    60 px.
  - **Seam:** `enter_phase()` is named.

### New mechanisms — checked

- **Hold at the stopping point:** entered at 220 px/s, the drone reaches 0 px/s by tick 18 and stops 3.9 px from the
  hold point, inside the 4 px tolerance. "≤ 5 px/s by the end of WINDUP" holds with room to spare.
- **CLOSE_IN** (`radius_rate` 0, 130 px/s tangential): I ran starts at 350 and 360 px, with initial velocity zero,
  inward at 220 px/s, and diagonal.
  - WINDUP is entered at 1.25 s / 1.33 s at **≈ 226 px**.
  - The closest approach is 226 px, against 109 px in round 1, so the "never below 150" half of the settle case really
    does discriminate.
- **Corkscrew** (120 px/s at 0.6 Hz, forward re-aimed each tick, starting 700 px above the player): across 8 starting
  phases the maximum lateral offset is 29–44 px, and APPROACH takes about 1.84 s. The "> 15 px" threshold has ≥ 14 px
  of margin, and a straight seek gives 0.
- **Overshoot setup:** teleporting the player 90° off at OVERSHOOT entry reproduces my round-1 replay: 76.2° of turn,
  per-tick heading change ≤ 2.4·dt·(1 + 2.4e-6), speed never below 219.99, and no wrong-sign tick.
- **Real-physics cases:**
  - **No damage in CLOSE_IN:** the brain now runs, so a brain that arms outside BURST fails the case. The unarmed hitbox
    is not monitorable (`contact_profile.gd:65-67`).
  - **Blast:** the unarmed control makes the case two-sided.

### Non-blocking (implementer resolves; record in DECISIONS)

- **R2-N1 — The gate constant is 43 ms short of the real worst case.** The 1.14 s figure assumes the overshoot slows
  to 220 px/s in 0.289 s. The replay says 0.300 s, plus up to two ticks of float-accumulation slack (see the B3
  table), for a real worst case of 1.183 s.
  - "speed ≤ `max_speed` + 1 at the expiry tick" (`:157`) can fail if a seeded run enters WINDUP with between 1.14 and
    1.18 s left. At that moment the drone would be in OVERSHOOT at about 230 px/s, not in a BURST, so the deadline
    itself is unaffected.
  - Fix: add a few ticks of margin, e.g. `+ 4 × (1/60)` or a flat 1.2 s, and pin that constant in the unit case.
- **R2-N2 — The squad-of-two case can pass vacuously** (`:164`).
  - `release_lead` is a no-op on a member that is not LEAD, and "no longer LEAD after REJOIN" is also true of a drone
    that was never LEAD.
  - Fix: assert the drone **is** LEAD before REJOIN. Place the second member farther from the hint at join time, since
    `_reassign` sorts by distance to `target_position_hint`.
- **R2-N3 — The settle case's first half is the exit condition restated.** "Distance at WINDUP entry within 200 ± 30"
  (`:144`) is just CLOSE_IN's exit condition, so it only fails when the 2.5 s cap fires. The real discriminator is
  "never below 150". Adding "entered WINDUP before `CLOSE_IN_MAX_SECONDS`" makes the first half meaningful.
  - Note for ENEMY.md: the drone trails the shrinking ring and actually winds up at about 226 px, not 200.
- **R2-N4 — "the same assumption the formula already made" (`:71`) is slightly generous.**
  - The §2.6 formula assumes the exit starts from rest. A drone at 220 px/s heading directly away from its chosen
    edge first decelerates at `acceleration` 600, because the desired 320 px/s is faster than its current speed, so
    `braking` is never selected. It then accelerates.
  - That costs about 0.76 s instead of the formula's 0.27 s, which is +0.49 s against the 0.5 s margin. The worst case
    comes to about 9.57 s, still under 10 s.
  - State this in DECISIONS. Changing the formula is not required.
