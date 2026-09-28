# Razor Drone combat (t10) — task plan

Task `cmuj4y8rr007gp52xxs8dec5s`, epic `cmufs7ek60001nm2x6d0bt2et`. **Revision 2**: it answers task review round 1
(`4-review.md`: B1–B4, N1–N9), and the last section maps each finding to what changed.

It implements the epic plan's §2.8.2 and §2.8.3 (everything except idle, which is t11) and the §4
`test_razor_drone.gd` t10 row. The epic plan is approved, and this file does **not** redesign it. It pins down what the
epic plan left to the implementer, states the numbers and names the tests. Context: `1-context.md` beside this file.

Numbers marked **[measured]** were replayed headless with an exact copy of `EnemyMover.step()`'s `move_toward`
accel/braking rule and the real `Steering` functions, over seeds 1, 2, 3, 4, 5, 42 and 100 (scripts in `/tmp`, not
committed). The tests re-measure them.

## Problem

Today the Razor Drone (the renamed Drone Interceptor) orbits for 1–2 s, then makes an un-telegraphed suicide dash.
Either it dies on contact or it is culled off-screen. Once you learn "dodge when it stops circling", it is harmless. It
flies with no acceleration and ignores the Assault corridor.

After this task the Razor Drone:
- circles you, and sometimes brakes and reverses its orbit direction;
- sometimes **fakes** a dash: a long yellow wind-up, then a lunge that passes beside you (not through you), a brake on
  the far side, and a real attack from there;
- shows the **white** flash only immediately before a **real** dash, and is only dangerous to touch (red) during that
  dash;
- survives its dash; if the dash missed, it fires **one** pulse shot at you while it curves back round;
- in Assault, stays inside the corridor, attacks diagonally from a side lane (real dashes and post-feint dashes alike),
  and leaves after 9 s.

## Design

### Mover and scene (D5 re-pin)

`razor_drone.tscn` changes:
- **`EnemyMover`:** `constraint_mode = AUTO` (0), `turn_lerp` 7 (unchanged). `acceleration` 900, `braking` 700 and
  `max_turn_rate` 6.0 come from the config, applied in `RazorDrone._apply_config()`. The scene authors the same values;
  the config wins where they differ (the Swarm precedent).
- **A new `ContactProfile`** child with `mode = RAMMING`. `ContactHitBox.damage` stays `config.collision_damage` (30),
  so `test_enemy_contact_damage.gd` is unchanged.
- **A new `StateLight`** child at the nose (`position = (0, -10)`; the art is nose-up). The position is provisional
  until t13.
- **A new `BulletPool`** child (`bullet_scene = enemy_bullet.tscn`, `pool_size` 4) and **a new `AttackController`**
  child (`driven_by_brain = true`, `enabled = false`, `bullet_pool` → the pool). Both are scene-authored:
  - `EnemyBrain._ready()` finds the `AttackController` sibling as `attack`.
  - The pool resolves its container as its grandparent, which is the drone's parent. D4 is unchanged; t16 pins it for
    the hub.
- **The `AimedAttackPattern` is built in code**, in `RazorDrone._apply_config()`, from `pulse_damage` and
  `pulse_speed`, with `accuracy 0`, `aim_at_player true` and `spawn_offset Vector2.ZERO`.
  - It is not a scene sub-resource: sub-resources are shared between instances of a PackedScene unless marked
    local-to-scene. This follows the `light_assault_ship.gd` precedent.
  - `AttackController.fire_now()` guards against a null pattern.
- **The contact self-kill (`_on_contact_hit`) is removed.** `RazorDrone` connects `contact_profile.contact_made` to
  `RazorDroneBrain.on_contact()`, which marks the current dash as a hit.

### Config (`RazorDroneConfig`, flat)

Kept fields, unchanged: `orbit_radius` 130, `orbit_speed` 1.8, `approach_speed` 200, `dash_speed` 480 and
`dash_prediction_time` 0.2.

**`orbit_correct_speed` changes from 160 to 260** (rev 2, B3):
- At 160 the drone cannot keep up with the orbit anchor, which moves at 1.8 × 130 = 234 px/s. It lagged inside the
  ring at 82–110 px, and by a different amount per seed.
- At 260 it settles at 118–120 px on every seed **[measured]**, so the feint geometry is the same from any start.
- The centripetal demand is 234² / 130 ≈ 421 px/s², within the 900 px/s² acceleration.

`dash_max_distance` is **removed** from the script, the `.tres` and the brain.

New fields, with the values from the epic plan §2.8.2 (all marked **[judgement]** there), except
`feint_clearance_px`:

| Field | Value | Field | Value |
|---|---|---|---|
| `acceleration` | 900 | `overshoot_px` | 120 |
| `braking` | 700 | `max_dash_seconds` | 0.9 |
| `max_turn_rate` | 6.0 | `overshoot_speed` | 200 |
| `reverse_chance` | 0.35 | `overshoot_turn_rate` | 3.0 |
| `reverse_seconds` | 0.25 | `overshoot_max_seconds` | 1.2 |
| `fake_chance` | 0.35 | `pulse_damage` | 10 |
| `fake_windup_scale` | 1.5 | `pulse_speed` | 250 |
| `feint_lunge_speed` | 360 | `engage_seconds` | 9.0 |
| `feint_lunge_seconds` | 0.45 | `exit_speed` | 320 |
| **`feint_clearance_px`** | **70** (replaces `feint_offset_deg` 25°, B3) | `side_lane_min_deg` | 30 |
| `windup_seconds` | 0.5 | `side_lane_max_deg` | 75 |
| `commit_flash_seconds` | 0.12 | | |

Two config pins:
- The acceptance criteria's steady-state pin: `overshoot_turn_rate × overshoot_speed ≤ acceleration`
  (3.0 × 200 = 600 ≤ 900).
- Epic review round 2 B5's braking-inclusive pin:
  `overshoot_turn_rate × (overshoot_max_seconds − (dash_speed − overshoot_speed) / braking) ≥ deg_to_rad(60)`
  (3.0 × (1.2 − 0.4) = 2.4 rad).

### Brain (`RazorDroneBrain`)

```
enum Phase { ENTER, ORBIT, DASH, REVERSE, FEINT_WINDUP, FEINT_LUNGE, FEINT_BRAKE, WINDUP, OVERSHOOT, RETURN, DISENGAGE }
signal phase_changed(new_phase: int)
func enter_phase(p: Phase) -> void          # the one transition path and the test seam (Swarm precedent)
func force_next_choice(choice: StringName)  # &"real" | &"fake" | &"reverse"; consumed by the next window roll
func on_contact(area: Area2D) -> void       # from ContactProfile.contact_made; marks a DASH hit
```

**Enum order.** ENTER, ORBIT and DASH keep the values 0–2. New phases are appended, so t11 appends IDLE, NOTICING and
RETURNING the same way.

**Public read-only state for tests:** `phase`, `orbit_dir` (±1), `angular_speed` (rad/s, the orbit anchor's),
`orbit_centre`, `dash_direction`, `dash_hit`, `pulses_fired`, `lunge_side` and `budget`.

**Start-up.** As in the Swarm, the root copies tunables onto the brain after the brain's `_ready()`. So the
`EngagementBudget` and the first orbit window are built on the first tick, in `_start()`. `_ready()` still draws
`_orbit_angle` and then the first window length from `rng`, in that order, then `orbit_dir`.

**Transitions** go through `enter_phase()`. `tick()` runs a bounded chain (`for _i in 4`) so that a transition hands
over to the new phase's handler in the same tick.

#### ENTER [APPROACH]
`seek(target, approach_speed)` and face the player. At `distance ≤ orbit_radius` → ORBIT.

#### ORBIT [POSITION]
Each tick: `_orbit_angle += angular_speed · δ` with `angular_speed = orbit_dir · orbit_speed`, then
`mover.orbit(orbit_centre, orbit_radius, _orbit_angle, orbit_correct_speed)`, facing the player.

- **`orbit_centre`** is the player's position. In Assault it is clamped into
  `mover.constraint.inner_rect().grow(−orbit_radius)` when that rect has area. This is the Swarm's `_ring_centre()`
  (R2.13).
- **The window roll.** Window length is drawn from `rng` (1–2 s). When the window runs out:
  1. A forced choice wins and is consumed.
  2. Otherwise, if no reversal has happened since the last attack began and `rng.randf() < reverse_chance`, go to
     **REVERSE**.
  3. Otherwise `rng.randf() < fake_chance` gives **fake**, else **real**.
- **Side lane** (Assault only, `budget.active`; rev 2, B2 and B4). The lane is checked against the point **the real
  dash will start from**, predicted at decision time, not the drone's current position.
  - The lane is `side_lane_min_deg`–`side_lane_max_deg` off the vertical axis, measured as `acos(|rel.y| / |rel|)`
    about the player.
  - The check uses the band narrowed by `LANE_MARGIN_DEG` (3°) at each end. The margin absorbs the hold tolerance
    (4 px) and the prediction error. The test asserts the full band.
  - **Real attack:** the start point is `_hold_at`, the stopping point `pos + v̂ · |v|² / (2 · braking)` that WINDUP
    holds at.
  - **Fake:** the start point is the predicted far-side stop. Starting from `_hold_at`, take side `s`'s lunge direction
    (see FEINT_LUNGE) times `feint_lunge_speed · feint_lunge_seconds + (feint_lunge_speed² − FEINT_STOP_SPEED²) /
    (2 · braking)`. The default side is tried first, then the other; the first one in the lane is taken and sets
    `lunge_side`.
  - When no candidate is in the lane, ORBIT continues with the choice pending, until one is, or until one more window
    has elapsed. Then the drone attacks anyway, from the default side.
  - Why the fallback is rare: the anchor sweeps at least 103° per 1 s window, and so does every predicted start point.
    Every 103° arc contains part of a lane (the gaps are 60° around the vertical and 30° around the horizontal), so the
    fallback is only reached when the orbit is blocked.
  - Open Space has no lane: a fake always uses the default side.

#### REVERSE
`angular_speed` ramps linearly from `orbit_dir · orbit_speed` to `−orbit_dir · orbit_speed` over `reverse_seconds`,
passing through 0 (a visible brake). The orbit request continues throughout. At the end: `orbit_dir = −orbit_dir`, a
new window starts, and reversal is barred until the next attack begins.

**Deviation (rev 2, N2):** the epic says "at most once per window". Read literally, every window could reverse again:
an endless back-and-forth. The bar lasts until the next attack instead, so the roll after a reversal is always fake or
real. This goes in DECISIONS.

#### FEINT_WINDUP [ATTACK, fake]
CHARGING (yellow) for `windup_seconds × fake_windup_scale` (0.75 s). The drone holds at its stopping point (`_hold_at`,
as in the Swarm's WINDUP) and faces the player.

#### FEINT_LUNGE (rev 2, B3 and N3)
`boost(dir, feint_lunge_speed, feint_lunge_seconds)`.
- `dir` aims at a point **beside** the player, not at a fixed angle:
  `aside = target + to_player.rotated(s · PI/2) · feint_clearance_px` and `dir = (aside − pos).normalized()`.
- The side `s = lunge_side` defaults to `orbit_dir` (the lane rule may flip it in Assault). With the anchor at
  `RIGHT.rotated(angle)`, the lunge passes on the side of the direction the drone was orbiting, and it sweeps round
  in the `−s` sense.
- It lasts as long as the boost and faces along the velocity. The light stays CHARGING and the profile is never armed.
- **Why a fixed clearance:** it does not depend on the start distance, so clearance and end bearing trade off in one
  number instead of against the orbit's real radius. **This is a deviation from the board's "25°"** and goes in
  DECISIONS.

#### FEINT_BRAKE
Request zero velocity (the mover's `braking` 700 stops the drone) and face the player.
- When the speed drops below 40 px/s (`FEINT_STOP_SPEED`), re-anchor `_orbit_angle` to the drone's current bearing and
  set `orbit_dir = −s`, so the new orbit continues the sweep. Then enter **WINDUP at once**: no orbit leg, no roll.
  The lane was already guaranteed by the far-side prediction.
- A 1.0 s cap (`FEINT_BRAKE_MAX_SECONDS`) guards against a drone pinned by the corridor.
- **Measured geometry** (`orbit_correct_speed` 260, `feint_clearance_px` 70) **[measured]**:
  - the feint starts about 119 px from the player;
  - closest approach is **61.7 px**, 17 px clear of the 30.8 px contact radius plus the 13.5 px player hurtbox
    (44.3 px);
  - it ends about 155 px away at a bearing **128.3°** from the start, against the > 120° criterion;
  - for comparison, a 60 px clearance gives 54.5 px and 133.8°.

#### WINDUP [ATTACK, real]
CHARGING for `windup_seconds` (0.5), then COMMIT (white) for `commit_flash_seconds` (0.12), then DASH. The drone holds
at `_hold_at` throughout.
- The dash point is **locked on the first COMMIT tick**: `target.predicted_position(dash_prediction_time)`. With no
  target it is the facing × 200 px. The drone then faces that point.
- COMMIT is set here and nowhere else: this is the only code path that shows white.

#### DASH [ATTACK]
- `set_armed(true)`, light ARMED (red), `dash_hit = false`.
- `dash_direction` is the locked point minus the position, normalized. If DASH is entered without a WINDUP (the test
  seam), the point is locked at entry.
- `boost(dash_direction, dash_speed, min((|locked − pos| + overshoot_px) / dash_speed, max_dash_seconds))`.
- The drone faces along its velocity (no `face_toward`, the Phase 1 fix).
- When the boost ends → OVERSHOOT.

#### OVERSHOOT [REPOSITION]
- On entry: `set_armed(false)` and light OFF. If `not dash_hit`: `attack.fire_now()` once, and `pulses_fired += 1`.
- Every tick it requests `turn_toward(actor.velocity.normalized(), to_player, overshoot_turn_rate, δ) ×
  overshoot_speed`, rebuilt from the **current** velocity (D7).
- It ends for RETURN when the heading is within 20° (`OVERSHOOT_EXIT_DEG`) of the bearing to the player, or after
  `overshoot_max_seconds`.
- **[measured]** It turns about 145° in 1.2 s, stays at ≥ 200 px/s, and never turns more than `3.0·δ` in a tick. From a
  dash straight through the player it exits on the time cap about 308 px out.

#### RETURN
`arrive` at the ring point `orbit_centre + (pos − orbit_centre).normalized() × orbit_radius` at `approach_speed`,
facing the player.

Within 20 px of the ring (`RETURN_TOLERANCE`), or after 2.0 s (`RETURN_MAX_SECONDS`): re-anchor `_orbit_angle` to the
current bearing, draw a new window and go to ORBIT.

#### DISENGAGE (Assault only)
Entered when the budget expires. This is the Swarm's code, copied:
- disarm, light OFF, `release_constraint()`, `max_speed = exit_speed`;
- the nearest edge of `projectile_world_rect()` is picked once, and the drone seeks 64 px past it;
- it is freed once strictly outside the rect.

Expiry is deferred while the mover is boosting (DASH or FEINT_LUNGE): the check fires on the first tick after the
boost. Razors spawn only in DURATION sections, and the deadline test now proves that the deferral cannot cost an
ENEMIES_CLEARED deadline (B1).

A budget that expires during a DASH goes to DISENGAGE on the first tick after the boost. That dash's OVERSHOOT, and its
pulse, are skipped. This is intended (N9): the drone is leaving.

#### Other cases
- **Rail suspension (N7):** `on_suspended()` sets the light to ARMED, which matches `BaseEnemy.suspend_ai()` arming
  the RAMMING profile. No Razor rides a rail today; `test_station_reinforcements.gd` forbids it.
- **No target (N4):**
  - ENTER, ORBIT, REVERSE and RETURN request zero.
  - FEINT_WINDUP and WINDUP keep holding, and WINDUP locks along the facing.
  - DASH, FEINT_LUNGE and FEINT_BRAKE finish on their own.
  - OVERSHOOT has nothing to turn toward, so it keeps its heading and ends on its time cap.
- **"Missed"** means that *the boost ended with no `contact_made`* (the DECISIONS convention), never a distance.

### What is removed
- `_begin_dash()`, replaced by `enter_phase(DASH)`.
- `_check_dash_end()`: the legacy cull-rect free and the Open Space `dash_max_distance` free.
- `RazorDrone._on_contact_hit` (the self-kill).
- `EnemyWorld.cull_rect()` is **not** removed; legacy users keep it.
- The stale `swarm_drone_brain.gd` comment that cites `RazorDroneBrain._check_dash_end()` is repointed, and the
  Phase 1 headers of `razor_drone.gd` and `razor_drone_brain.gd` are rewritten (N8).

### Rejected alternatives
- **A separate COMMIT phase.** The light state is what the player sees. One WINDUP phase with two sub-periods keeps the
  task's WINDUP → DASH sequence and a smaller enum.
- **A lane check after the feint.** It would need an orbit leg, which contradicts the epic's "WINDUP at once". The
  far-side prediction guarantees the lane without one (B4).
- **A fixed 25° lunge offset [measured]:** the drone passes through the player, at 37–46 px against 44.3. Any fixed
  angle trades clearance against end bearing, and the trade depends on the orbit radius.
- **Disarming on the first hit.** The player's i-frames already stop a double hit. Staying armed for the whole DASH
  keeps "armed ⇔ DASH" a clean invariant.

## Build sequence
1. **Config.** Add the `.gd` and `.tres` fields, remove `dash_max_distance`, and set `orbit_correct_speed` to 260. The
   config pin cases come first and fail until the fields exist.
2. **Scene.** Add `ContactProfile`, `StateLight`, `BulletPool` and `AttackController`, and set the mover to AUTO.
   `RazorDrone._apply_config()` builds the pattern and wires `contact_made`. In `test_base_enemy.gd`, add
   `razor_drone → RAMMING` to `_AUTHORED_CONTACT_MODES`.
3. **Brain.** The state machine above.
4. **Tests.**
   - Rewrite `test_razor_drone.gd` and the Razor cases in `test_enemy_dual_mode.gd`.
   - **Fix `test_engagement_deadline.gd` (B1).** It currently evaluates every spawn with `SWARM_CONFIG`. It will pick
     the config per scene, and the Razor gets its own formula:

     `last_delay + engage_seconds + max_dash_seconds + dash_speed / braking + exit_distance / exit_speed +
     exit_speed / (2 · acceleration) + margin`

     The two added terms are the boost deferral and shedding the dash's speed.
   - Add a boundary case to that test: a synthetic Razor in cloud_descent's last wave evaluates to about 14.6 s (0.8 + 9.0 + 0.9 + 0.69 + 2.51 + 0.18 + 0.5) and
     must **exceed** the 10 s timeout, so the guard cannot silently regress.
   - Run the suite and `scripts/check-test-leaks.sh`.
5. **Docs.** `razor_drone/ENEMY.md`, the Razor entry in `docs/enemy-roster.md`, the Razor paragraphs in `assault.md`,
   and a t10 section in DECISIONS (the two deviations, plus `orbit_correct_speed`).

## Test plan

In `tests/integration/test_razor_drone.gd`, rewritten:
- Dual-mode cases use `use_parameters(["open_space", "assault"])` on a label, with the harness built in the body.
- The player sits mid-corridor at (640, 360) unless a case says otherwise.
- Drones are hand-ticked with the exact-integration `_tick()`.
- Every case sets `rng_seed` or uses `force_next_choice`.

| Case | Asserts |
|---|---|
| `test_config_pins_the_steady_state_turn` | `overshoot_turn_rate × overshoot_speed ≤ acceleration` |
| `test_config_pins_the_turn_including_the_braking_phase` | B5's bound ≥ 60° |
| `test_config_keeps_the_orbit_catchable` | `orbit_correct_speed ≥ orbit_speed × orbit_radius` (rev 2: this is the reason for 260) |
| `test_config_flows_through_to_every_node` | Changed values reach the health, the hitbox damage, the mover (accel, braking, turn), the brain, and the pattern (pulse damage and speed). The profile is RAMMING |
| `test_the_scene_authors_the_d5_mover` | `constraint_mode == AUTO`; in the Assault harness `mover.constraint` is an `AssaultCorridorConstraint` (the D5 re-pin) |
| `test_no_player_requests_zero` | Unchanged pin |
| `test_enter_accelerates_toward_the_player` (dual) | The first tick's velocity is `acceleration·δ` toward the player (it used to be an instant `approach_speed`), and it reaches `approach_speed` |
| `test_orbit_holds_the_radius` (dual, 7 seeds) | After 1 s of settling, the distance stays within `orbit_radius` − 15 to + 15 px for 1 s (measured: 118–120) |
| `test_the_reversal_passes_through_zero` (dual) | Forced `reverse`: `angular_speed` goes from `+d·s` to `−d·s` monotonically, and some tick has \|ω\| ≤ one ramp step; `orbit_dir` flips. **Boundary (N1):** the drone's actual angular velocity about the player changes sign, and its per-tick \|Δv\| ≤ `max(acceleration, braking)·δ` + 1e-3 (no snap) |
| `test_no_second_reversal_before_an_attack` | `reverse_chance` 1.0 on the private config: after one REVERSE, the next unforced roll is an attack (N2) |
| `test_the_fake_never_commits_or_arms` (dual) | Forced `fake`: from FEINT_WINDUP until WINDUP entry, the light is never COMMIT and the profile is never armed; CHARGING lasts `windup × 1.5` ± 1 tick |
| `test_the_fake_passes_beside_and_ends_on_the_far_side` (dual) | The bearing about the player at WINDUP entry differs from the bearing at FEINT_WINDUP entry by > 120°. The minimum centre distance during FEINT_LUNGE/FEINT_BRAKE is ≥ the contact radius + 13.5 px (B3). The phase log is `FEINT_WINDUP, FEINT_LUNGE, FEINT_BRAKE, WINDUP`, consecutive (no ORBIT). `orbit_dir == −lunge_side`, and the sweep sign matches (N3) |
| `test_the_real_dash_is_charging_commit_armed` (dual) | Forced `real`: the light states in order are exactly `[CHARGING, COMMIT, ARMED]`, armed only in DASH, CHARGING ≈ 0.5 s and COMMIT ≈ 0.12 s (± 1 tick) |
| `test_dash_direction_is_the_locked_prediction` (dual) | A player with velocity (100, 0) and a fixed position: the DASH velocity direction equals `(pos_at_lock + v·0.2 − drone_pos).normalized()`, at `dash_speed` |
| `test_the_overshoot_curves_toward_the_player` (open_space) | A dash through a stationary player (a miss: no physics step). During OVERSHOOT, each tick's heading change is ≤ `overshoot_turn_rate·δ` + 0.001, never away from the bearing, with speed ≥ 0.5 × `overshoot_speed`. The total turn is ≥ 60°, and it exits into RETURN |
| `test_the_overshoot_keeps_moving_inside_the_corridor` (assault) | The same DASH → OVERSHOOT → RETURN sequence mid-corridor, with the speed floor |
| `test_a_miss_fires_exactly_one_pulse` (dual) | Right after OVERSHOOT entry, and again after RETURN: `pulses_fired == 1` and exactly one bullet has left the pool (`pool_size − pool.get_child_count()`), parented in the drone's container. The bullet's `HitBox.damage == pulse_damage` and its direction points at the player (N5) |
| `test_a_hit_fires_no_pulse` (dual) | `contact_hit_box.area_entered` emitted mid-DASH (armed) sets `dash_hit`; `pulses_fired == 0` and no bullet leaves the pool |
| `test_contact_outside_the_dash_is_ignored` | An emit during ORBIT: no `contact_made`, `dash_hit` stays false, health unchanged (N6) |
| `test_the_drone_survives_its_dash` (dual) | On a hit and on a miss: not queued for deletion, health unchanged, back in ORBIT within 4 s |
| `test_a_real_dash_hurts_a_real_player_and_orbit_contact_does_not` | Real physics with the `contact_fixture` player: an orbiting drone pushed onto the player deals 0; a DASH into it lowers health by `collision_damage`; the drone survives |
| `test_the_assault_dash_bearing_is_in_the_side_lane` | Assault, 7 seeds, forced `real`: at DASH entry, the dash direction's angle off vertical is in [30°, 75°]. **Boundary control:** the same seeds in open_space give at least one dash outside the lane (the lane is Assault-only) |
| `test_the_assault_post_feint_dash_is_in_the_side_lane` | Assault, 7 seeds, forced `fake`: the WINDUP → DASH after the feint has a dash angle in [30°, 75°] (B4) |
| `test_the_orbit_centre_stays_inside_the_shrunk_inner_rect` | Assault, with the player 50 px inside the corridor's left edge: over 3 s of ORBIT, `orbit_centre` stays inside `inner_rect().grow(−orbit_radius)` (± 0.01) and `orbit_centre.x > player.x` (the clamp is live). Open-space control: `orbit_centre == player` |
| `test_the_assault_budget_exit` | Assault: DISENGAGE no earlier than `engage_seconds`, then freed only strictly outside `projectile_world_rect()` within 4 s, with the constraint released |
| `test_budget_expiry_waits_for_the_dash_to_end` | Assault, a short private `engage_seconds`, DASH entered just before expiry: the phase stays DASH until the boost ends, then DISENGAGE on the next tick (N4) |
| `test_open_space_never_disengages` | 12 s: no DISENGAGE, `budget.remaining() == INF` |
| `test_the_player_vanishing_mid_attack_is_safe` | The player is freed in WINDUP, then in OVERSHOOT: no error, and it still reaches DASH (along its facing) and RETURN (N4) |
| `test_the_feint_brake_cap` | A drone whose brake is prevented (the lunge speed cannot drop below 40 because the private config's braking is 1) enters WINDUP after `FEINT_BRAKE_MAX_SECONDS` (N4) |
| `test_the_first_tick_facing_is_capped` | The rotation pin re-derived for `max_turn_rate` 6: `min(lerp_angle(0, target, 7δ), 6δ)` |

In `tests/integration/test_enemy_dual_mode.gd`, the three Razor cases are re-pinned; the fixture cases are untouched:
- The mid-corridor orbit is identical in both modes with the same seed. This is now "identical relative to the
  constraint": the corridor never engages mid-screen and the orbit-centre clamp is a no-op there.
- The dash direction is identical in both modes (via `enter_phase(DASH)`).
- The Open Space `dash_max_distance` free becomes "the drone survives its dash in both modes".

In `tests/integration/test_engagement_deadline.gd` (B1):
- the config is picked per scene, with the Razor formula above;
- **boundary:** a synthetic Razor in cloud_descent's last wave exceeds the timeout.

**Mutation checks**, run by hand once and recorded in `5-progress.md`. Each must fail at least one case:
- set COMMIT in FEINT_WINDUP;
- fire the pulse even on a hit;
- skip the inner-rect clamp;
- make REVERSE flip instantly;
- check the lane at the current position instead of the start point;
- lunge at the player instead of beside them;
- remove the Razor term from the deadline test.

## Risks
| Risk | Mitigation |
|---|---|
| Hand ticks vs real physics (`move_and_slide` delta drift) | The exact-integration `_tick()`, as in every AI test. The one real-physics case only asserts health |
| The feint end bearing is 128° against 120° (8° of margin) | Measured on 7 seeds with a settled orbit. The test forces the feint from a settled orbit, and `orbit_correct_speed` 260 removes the seed spread |
| The BulletPool grandparent assumption in tests | The harness root is the grandparent, and the pulse case asserts it |
| The Assault corridor clips a lunge or a dash | The cases run mid-corridor. The edge behaviour is covered by the inner-rect case, and the brake cap covers a pinned drone |
| Level-1 Razors (above-screen spawns, no `.move()`) now go through the corridor's entry rule | The t1 pin is data-only and stays green. Entry is the same mechanism the Swarm uses, and its spawn-entry case covers it |

## Out of scope
- Idle, NOTICING and the patrol anchor (t11).
- Sprites (t13).
- The hub spawn (t16).
- The level-1 wave migration (t15).
- Audio.

## Response to review round 1
| Finding | Change |
|---|---|
| B1 deadline test uses the Swarm config for Razors | Per-scene config; the Razor formula with deferral and shedding terms; a boundary case that must exceed the timeout |
| B2 lane checked before the hold drift | The lane is checked at the predicted dash start point (`_hold_at`), with a 3° inner margin |
| B3 the 25° lunge goes through the player; the orbit really sits at 82–110 px | `orbit_correct_speed` 260 (orbit 118–120 px); the lunge aims `feint_clearance_px` 70 beside the player (closest 61.7 px, sweep 128.3°, measured); a clearance assertion; the orbit band restated; deviation logged |
| B4 the post-feint dash skips the lane | In Assault the lunge side is chosen so the predicted far-side stop is in the lane (the attack waits otherwise); a forced-fake Assault lane case |
| N1 the angular-velocity bound is not real | Assert per-tick \|Δv\| plus the sign change |
| N2 reversal frequency | Stated as a deviation, with a test case |
| N3 sign convention | Spelled out: `s = orbit_dir` side, sweep `−s`, `orbit_dir = −s` after; asserted |
| N4 untested mechanisms | Cases for deferral through the dash, the brake cap, and the player vanishing mid-attack. The RETURN cap is covered by a dash through the player, which exits 308 px out, under 2 s at 200 px/s |
| N5 pulse aim and damage | Asserted |
| N6 Razor wiring for off-dash contact | `dash_hit` and health asserted |
| N7 `on_suspended` | Light ARMED |
| N8 stale comments | Repointed and rewritten |
| N9 pulse lost to DISENGAGE | Stated as intended |

## Amendments from review round 2 (binding; APPROVED with A1–A5)
- **A1:** measure the feint's > 120° sweep from the bearing at **FEINT_LUNGE entry** (the hold point it lunges
  from), not from FEINT_WINDUP entry. Measured 128.3°. From FEINT_WINDUP entry the default side gives only 111°,
  because the hold drifts about 17° along the orbit first. Recorded in DECISIONS.
- **A2:** ENTER → ORBIT re-anchors `_orbit_angle = (pos − orbit_centre).angle()`. The `_ready()` draw is kept, so the
  rng sequence is unchanged. The orbit case measures from 0.5 s after ORBIT entry until ORBIT is first left, with a
  band of `orbit_radius` ± 15.
- **A3:** FEINT_WINDUP and WINDUP hold with `mover.hold_position(_hold_at, 4.0, orbit_correct_speed)`.
- **A4:** the Razor deadline is `last_delay + engage_seconds + max_dash_seconds + (dash_speed + exit_speed) /
  min(acceleration, braking) + (exit_distance + dash_speed² / (2·braking)) / exit_speed + margin`, which is about
  15.4 s in the boundary case (it must still be > 10 s).
- **A5:** the brake-cap case writes `mover.braking = 1.0` on the mover only once FEINT_BRAKE is entered (through
  `phase_changed`), then asserts WINDUP at `FEINT_BRAKE_MAX_SECONDS` ± 1 tick.
- **Prose fix:** the lunge passes on the side *opposite* the orbit tangent. The formula, the `−s` sweep and
  `orbit_dir = −s` are unchanged. The lunge runs 28 ticks rather than 27 (float accumulation), and the 3° lane margin
  absorbs this; do not tighten it.
