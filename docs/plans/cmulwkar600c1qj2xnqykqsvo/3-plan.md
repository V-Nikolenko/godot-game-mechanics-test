# Gatling Interceptor pressure windows (t10-gatling-windows) — task plan, Revision 1

Task `cmulwkar600c1qj2xnqykqsvo`, epic `cmufs7ekv000lnm2x7nbswijy`. This plan builds §2.6 (solo Gatling) and §2.8 (the
Gatling rail fallback) of the epic's approved `3-plan.md` (Revision 2, "the epic plan" below). It does not re-derive
the epic plan. It says **how** each rule is built, and it names the one place where building it literally cannot work
(§D2), with the arithmetic. Convergence (§2.6.1, t11), hub idle (t12), art (t15) and level-1 migration (t16) are out of
scope.

## Problem

Today the Gatling Interceptor only exists on rails. It hoses a constant ~11 shots/s stream at the player while
sliding along a fixed path. Nothing in that gives the player a rhythm to read. Off rails (Open Space, and Assault once
t16 migrates level 1) it would be inert, because it has no brain.

After this task an AI Gatling does the following:
- It flies out to the player's side, about 380 px away, and its light turns yellow as it lines up and spins up.
- It fires one stream of 8–12 rounds at where the player is going, sliding along the flank as it fires (light red).
- It goes quiet for 0.4 s, then brakes and swings round to the **other** flank to do it again.
- In Assault, its first attack comes from the open half of the screen (the half the player is not in). It alternates
  sides after that, unless the player is hugging a wall.
- It leaves the corridor when its time is up, but never in the middle of a stream.

On rails (the station's LEFT/RIGHT reinforcements, and level 1 until t16) it still fires its constant stream, now
with Gatling Stream rounds.

## Design

### D1. Scene, config, script (the `fighter.tscn` shape)

**`gatling_interceptor.tscn`** keeps every existing node (Sprite2D, the three shapes sharing `CircleShape2D_int`,
HurtBox, Health, HitFlash, ContactHitBox) and adds:
- `EnemyMover` (`constraint_mode = AUTO`);
- `Brain` (`GatlingInterceptorBrain`);
- `StateLight` at (0, −10);
- `StreamPool`: a `BulletPool` whose `bullet_scene` is `gatling_stream_round.tscn`, `pool_size = 36`, a **direct
  child of the root**;
- `Attack`: an `AttackController` with `bullet_pool = ../StreamPool`, `enabled = false`, `driven_by_brain = true`.

New `ext_resource` lines are UID-less, as in `fighter.tscn`.

**`GatlingInterceptorConfig`** is flat, extends `ShipConfig`, and has these groups:
- legacy: HP 70, contact 20 (`collision_damage`), score 75, all in the `.tres`;
- Movement: `max_speed` 260, `acceleration` 600, `braking` 900, `turn_rate` 2.0;
- Geometry: `preferred_range` 380, `min_flank_range` 220, `approach_margin` 250 (APPROACH aims for within
  `preferred_range + approach_margin`), `swing_in_reach` 300 (new, §D2), `reposition_cap` 5.0 (new, §D2);
- Window: `swing_in_max` 1.5, `spin_up_seconds` 0.25, `sync_wait_max` 0.75 (read by t11; this task only uses it in the
  deferral bound), `stream_rounds_min/max` 8/12, `stream_interval` 0.09, `stream_strafe_speed` 140,
  `cooldown_seconds` 0.4, `reposition_min/max` 1.0/1.5;
- Rounds: `round_speed` 240, `round_damage` 4, `stream_spread` 0.05, `accuracy` 0.8;
- Tactics: `engage_seconds` 7.0, `exit_speed` 520;
- Rail: `rail_stream_interval` 0.09, `rail_stream_speed` 220, `rail_spread` 0.08, `rail_damage` 4. These are the legacy
  `fire_interval` / `bullet_speed` / `spread_angle` / `bullet_damage`, renamed as the epic plan says. Nothing else
  reads the old names: `test_enemy_bullet_lifetime.gd` is switched in this task.

The convergence fields (`convergence_*`) are t11's and are not added here.

**`gatling_interceptor.gd`** follows `fighter.gd`. `_ready()` calls `super._ready()`, adds the node to `enemies`, then
runs `_apply_config()`, which does the following:
- sets health, score and contact damage;
- sets the mover's `max_speed`, `acceleration`, `braking` and `max_turn_rate`;
- builds the AI `GatlingAttackPattern` per instance: `bullet_speed = round_speed`, `bullet_damage = round_damage`,
  `spread_angle = stream_spread`, `aim_at_player = true`, `accuracy`, `rng = brain.rng`, and `fire_interval =
  stream_interval` (unused while brain-driven);
- sets `brain.config = cfg`.

The script has no per-frame code. `BaseEnemy` ticks the brain and then the mover.

### D2. The one literal-plan problem: a swing to the other flank does not fit in REPOSITION + SWING_IN

The epic plan gives REPOSITION a fixed rng duration of 1.0–1.5 s, then SWING_IN, which hands over at 60 px of `F` or
after `swing_in_max` (1.5 s). So the swing has at most 3.0 s to cross to the other flank, at `max_speed` 260 px/s.

Crossing from one flank point to the other is not possible in that time:
- The two flank points are 2 × 380 = 760 px apart, and the straight line between them goes through the player.
- The shortest path that stays outside `min_flank_range` (220 px) is two tangents of √(380² − 220²) = 310 px plus an
  arc of 220 × (π − 2·acos(220/380)) = 271 px, so **891 px, or 3.4 s** at 260 px/s.
- Going round at `preferred_range` instead is ≈ 150° of a 380 px circle, ≈ 1000 px, or **3.8 s**.
- Both figures leave out acceleration, and they leave out the ≈ 20–30° the stream itself sweeps (D4).

Built literally, every window after the first would therefore start SPIN_UP mid-crossing, often almost in front of the
player. That is not the side-on stream R3.7 asks for, and it would fail the epic plan's own "angle within 90° ± 35°
during STREAM" test.

**Fix (two new config fields; every epic number is kept):**
- **REPOSITION** runs for at least its rng duration (1.0–1.5 s, as planned). It hands over to SWING_IN only when the
  new `F` is within `swing_in_reach` (300 px). It is capped by `reposition_cap` (5.0 s), after which it hands over
  wherever it is (liveness).
- **APPROACH** works the same way. It seeks the flank (§D4 routing) and hands over when `F` is within
  `swing_in_reach`. Once it is within `preferred_range + approach_margin` of the player, it also hands over after
  `reposition_cap`, so a player who cannot be caught still gets a window.
- With `F` within 300 px, SWING_IN reaches its 60 px handover in ≈ 1.0–1.3 s, inside `swing_in_max`. The CHARGING
  light stays exactly what the epic plan says: SWING_IN + SPIN_UP, ≤ 1.75 s, always followed by a stream (the budget
  rule in §D5).

**Consequence (recorded in DECISIONS for t16):** a window period is ≈ SPIN_UP 0.25 + STREAM 0.6–1.0 + COOLDOWN 0.4 +
REPOSITION ≈ 3.5 + SWING_IN ≈ 1.1 ≈ **5.8 s**. The average rate is ≈ 1.7 shots/s, against the epic plan's ≈ 3.5 (which
left SWING_IN out of its sum). Density is lower, which makes t16's 1.25× shots/s gate easier, not harder. In Assault,
with `engage_seconds` 7.0, a Gatling typically gets **one** window, plus a second only if APPROACH was short. The
research assumed two. Tuning `engage_seconds` is t16's call, with its density gates.

Rejected alternative: a faster swing (e.g. a 360 px/s REPOSITION speed). It fits 891 px in 2.5 s, but it breaks the
pinned `turn_rate × speed ≤ acceleration` (720 > 600) or needs a third speed/turn pair. It also makes a suppression
unit look like a chaser.

### D3. Phases

`GatlingInterceptorBrain extends EnemyBrain`:
- `enum Phase { APPROACH, SWING_IN, SPIN_UP, STREAM, COOLDOWN, REPOSITION, DISENGAGE }` (t12 appends IDLE, NOTICING,
  RETURNING);
- `signal phase_changed(new_phase: int)`;
- `enter_phase(p)` is the seam and the only place a transition happens.

Read-only for tests and t11: `phase`, `side` (±1), `flank_point` (this tick's `F`), `seek_target`, `stream_rounds`
(N of the current or last stream), `windows_done`, `budget`.

Per-tick order, as in the Fighter: lazy `_start()` (builds the `EngagementBudget`), the budget check, then the phase.

| Phase (IDEAS §4) | Movement | Light | Ends |
|---|---|---|---|
| APPROACH [APPROACH] | §D4 flank routing to `F` | OFF | `F` within `swing_in_reach`, or `reposition_cap` after first coming within `preferred_range + approach_margin` → `_begin_window()` |
| SWING_IN [POSITION] | §D4 routing to `F`, speed tapered `min(max_speed, √(2·braking·d))` | CHARGING | within 60 px of `F` (`SWING_IN_ARRIVE_PX`) or `swing_in_max` → SPIN_UP |
| SPIN_UP [ATTACK] | §D4 strafe at `stream_strafe_speed` (the mover's braking brings it down); nose on the player (`face_toward`) | CHARGING | `spin_up_seconds` → STREAM. A solo Gatling never waits; t11 adds the pair hold, capped by `sync_wait_max` |
| STREAM [ATTACK] | strafe; nose on the player | ARMED | the `BurstClock` (N = `rng.randi_range(8, 12)` at `stream_interval`) finishes → COOLDOWN, or DISENGAGE if one is pending |
| COOLDOWN [ATTACK] | keeps the strafe ("keeps drifting") | OFF | `cooldown_seconds` → REPOSITION |
| REPOSITION [REPOSITION] | on entry: the side rule (§D5); then §D4 routing to the new `F` | OFF | ≥ rng(`reposition_min`, `reposition_max`) **and** `F` within `swing_in_reach`, or `reposition_cap` → `_begin_window()` |
| DISENGAGE [DISENGAGE] | `FighterBrain`'s exit, verbatim in shape: release the corridor, `exit_speed`, curve to the nearest world-rect edge, free outside | OFF | freed |

`_begin_window()` enters SWING_IN if `can_start_window()` (`budget.remaining() ≥ swing_in_max`; always true in Open
Space, where `remaining()` is INF). Otherwise it holds in REPOSITION, seeking `F`, until the budget expires.

The stream fires one `attack.fire_now()` per round the `BurstClock` reports due. The per-instance pattern aims each
round at `TargetInfo.aim_direction(…, round_speed, accuracy 0.8)`, which leads the player, with ±`stream_spread`
jitter from the brain's `rng`. `aim_point` stays INF: that is t11's convergence hook.

### D4. Geometry

- **`h`** is `FighterBrain._heading_ref()`: `Vector2.UP` while the corridor has area, otherwise the player's velocity
  above 40 px/s, otherwise its facing.
- **`P̂`** = `target.predicted_position(lead)`, with `lead = Steering.clamped_lead_time(d, max_speed, 0.3, 0.8)`.
- **`F`** = `P̂ + right(h) × side × preferred_range`.
  - In Assault, `F.y = P̂.y − 60` (`ASSAULT_FLANK_AHEAD`), and `F` is clamped into
    `inner_rect().grow(−(hull + CORRIDOR_MARGIN 40))`.
  - `right(h) = h.rotated(π/2)`, which is `RIGHT` for `h = UP`.
- **The bearing** is `φ = h.angle_to(X − P̂)`: 0 is ahead and +90° is on the `right(h)` flank. "Side-on" means
  |φ| ∈ [55°, 125°]. That is the epic plan's 90° ± 35°, since the angle between the line to the player and `h` is
  180° − |φ|.
- **Flank routing** (APPROACH, SWING_IN, REPOSITION) never cuts across the player:
  - Let `φ_F` be the bearing of `F` and `Δ = φ_F − φ`.
  - Assault: `Δ` is the plain difference, both angles in (−π, π]. It never wraps through ±180°, so the swing always
    goes round **ahead** of the player, through the upper corridor, never below the player.
  - Open Space: `Δ` is the wrapped (shorter) difference.
  - If |Δ| ≤ 50° (`ROUTE_STEP_DEG`), seek `F`. Otherwise seek the ring waypoint
    `P̂ + h.rotated(φ + clamp(Δ, ±50°)) × preferred_range`, clamped into the corridor in Assault.
  - A chord between ring points 50° apart passes 380 × cos 25° = 344 px from `P̂`, outside `min_flank_range`.
  - The direction is `Steering.turn_toward(heading, desired, turn_rate)`. `desired` = (point − X) normalised × speed,
    plus the player's velocity (feed-forward, so a moving `F` can be held). The request is that direction × the
    desired length, and the mover caps it at `max_speed`.
- **The strafe** (SPIN_UP, STREAM, COOLDOWN), so that the Gatling "moves through the player's flank while firing":
  - `tangent` = (P̂ − X) normalised and rotated ±90°, taking the sign whose dot with `h` is ≤ 0. The Gatling arrives at
    `F` from ahead (the routing above) and keeps sliding the same way, from ahead-of-abeam toward behind.
  - The sign is latched at SPIN_UP entry.
  - The request is `target.velocity + tangent × stream_strafe_speed + radial`, where `radial` =
    `((d − preferred_range) × 2.0)` along the line to the player, capped at `stream_strafe_speed`. That holds the
    range.
- **Worked check (Open Space, holding player):**
  - SWING_IN hands over 60 px short of `F`, coming from ahead, so |φ| ≈ 81°.
  - SPIN_UP brakes from 260 toward 140 at 900 px/s² (≈ 0.13 s, ≈ 25 px) and then slides about 35 px more.
  - STREAM slides 140 × (0.63–0.99) s = 88–139 px.
  - That is ≈ 200 px of arc at r 380, or ≈ 30°, so |φ| ends at ≈ 111° ≤ 125°.
  - In Assault, `F` sits 60 px ahead (|φ| ≈ 81° at `F`, ≈ 72° at the handover), so |φ| ends at ≈ 102°.
  - Both are inside [55°, 125°]. The test measures it, and the numbers above are **[estimate]**.

### D5. Sides, the budget and deferral (epic §2.6, review B3/B4)

- **First window** (decided on APPROACH's exit, once):
  - Open Space: `side = sign(right(h)·(X − P̂))`, with 0 → +1.
  - Assault: the half of `inner_rect()` opposite the player's x, so `side = −1` if `P.x > centre.x`, else `+1` (the
    tie at exact centre → +1, review N7).
- **Every later window:** REPOSITION entered from COOLDOWN flips the side. A REPOSITION entered from APPROACH (budget
  too short) does not.
- **The Assault exception:** if the flipped `F` (clamped) would sit closer than `min_flank_range` horizontally to the
  live player (`|F′.x − P.x| < 220`), the flip is skipped for that window.
- **Worked check:**
  - Player at x = 490 (150 px left of the 640 centre): the first `F.x` = 870 (right half). The flip gives 110, and
    |110 − 490| = 380 ≥ 220, so it alternates.
  - Player 100 px from the right wall (x = 1280): the first side is −1 (`F.x` = 900). The flipped `F.x` clamps to
    1380 − 65 = 1315, and |1315 − 1280| = 35 < 220, so the flip is skipped and every window is on the left.
- **Budget:**
  - Expiry in APPROACH, COOLDOWN or REPOSITION → DISENGAGE on that tick.
  - Expiry in SWING_IN, SPIN_UP or STREAM → `_disengage_pending`. The stream finishes all N rounds, and the tick
    STREAM would enter COOLDOWN enters DISENGAGE instead.
  - SWING_IN needs `remaining ≥ swing_in_max`, and SWING_IN never lasts longer than that, so expiry can only land on
    SWING_IN's last tick.
  - The worst deferral is spin_up 0.25 + (12 − 1) × 0.09 = **1.24 s** solo. With t11's `sync_wait_max` it is
    0.25 + 0.75 + 1.08 = 2.08 s, the epic plan's bound.

### D6. Rail fallback (epic §2.8)

`on_suspended()` does the following:
- stops any stream and sets the light OFF;
- installs a fresh `GatlingAttackPattern` with `fire_interval = rail_stream_interval`, `bullet_speed =
  rail_stream_speed`, `bullet_damage = rail_damage`, `spread_angle = rail_spread`, `aim_at_player = true`,
  `accuracy = 0` and `rng = null` (the global `randf`, as legacy);
- sets `attack.driven_by_brain = false` and `attack.enabled = true`.

It fires from `StreamPool` (36). The rail need is `1 × ceil(6.36 / 0.09) = 71`, so a rail Gatling fires ≈ 36 rounds
and then stalls until rounds expire. That is the legacy starvation shape (the legacy pool was 20), and the test names
it as deliberate. A squad leave is t11's job (there is no `squad` field yet).

### D7. Existing tests this touches

- **`test_enemy_bullet_lifetime.gd`:**
  - `_gatling_speeds()` reads `round_speed` and `rail_stream_speed` from the shipped `.tres`;
  - the GATLING_STREAM sweep row gets `"speeds"`;
  - `GatlingInterceptorConfig.new().bullet_speed` is replaced by the two fields in `_every_shipped_enemy_bullet_speed()`.

  After this, no speed in the sweep is hand-typed or regex-read. The pattern-class defaults
  (`GatlingAttackPattern.new().bullet_speed`) are code defaults, not typed numbers.
- **`test_level1_fighter_spawns.gd::_attack_stats_of()`:** it now calls `suspend_ai()` on any `BaseEnemy` that has a
  `Brain` child, not only on fighters, so the Gatling is read through its rail pattern.
  - The live Gatling rail rate changes from `min(11.1, 20 / life)` to `min(11.1, 36 / life)`. If deep_space's peak
    window includes the pair, the live shots/s no longer equals the frozen `_LEGACY_PEAK_SHOTS_PER_S`.
  - That constant is the **legacy baseline**, and t16's gate divides by it, so it must not be re-frozen to the new
    value.
  - The equality is a "rails unchanged" guard, and this task changes the rail Gatling on purpose (epic §2.8 lists it as
    a visible change). So if it trips, the test keeps the frozen constant and asserts the live value equals the
    constant **plus the computed delta of the Gatling pool change** (`2 × (36 − 20) / life`, inside the peak window).
    The delta is derived, never typed, and is named in a comment and in DECISIONS.
  - If the peak window does not include the pair, nothing changes. The run decides which case applies, and
    `5-progress.md` records which.
- **`test_station_reinforcements.gd::test_rail_reinforcements_fire`:** no change is expected. `_bullet_pool_of()` finds
  `StreamPool`, and the rail stream fires within 0.09 s.
- **Gate rosters:** no change. The scene keeps its node names and shapes, and contact damage is applied from config.

## Build sequence

1. **Config + scene + script + a minimal brain** (APPROACH only, the rail fallback and DISENGAGE), plus the switch of
   the lifetime and level-1 tests. The scene and rail cases of `test_gatling_interceptor.gd` go first and fail first.
   Gate-check the existing suite here: station rail fire, level-1 pin, every gate.
2. **The window machine:** SWING_IN, SPIN_UP, STREAM, COOLDOWN, REPOSITION, the strafe and the routing. Rhythm,
   cadence and side-on cases, dual.
3. **Sides, the budget rule and deferral.** Their cases.
4. **Dual-mode cases** in `test_enemy_dual_mode.gd`; `scripts/check-test-leaks.sh`.
5. **Docs:** `gatling_interceptor/ENEMY.md` (behaviour and config; the "fires forward" correction is t18's), and the
   DECISIONS *built in t10* note (D2's deviation and the window period for t16, the config renames, the level-1
   constant handling).

## Test plan — `tests/integration/test_gatling_interceptor.gd` (new; INTENT)

Same harness as `test_fighter.gd`: built inside the body, hand-ticked `_tick()` re-integration, seeded brains, the
shipped `.tres` never written (a case that needs other values writes the instance's private `config`). A `_simulate()`
logs every tick (phase, light, side, `F`, position, shots) and recycles each shot back into `StreamPool`. Boundary cases
are in **bold**.

Scene and pool:
1. The scene has `Brain` (`GatlingInterceptorBrain`), `EnemyMover` (AUTO), `StateLight`, and exactly one
   `AttackController` (`driven_by_brain`, disabled). It has no `AIStateMachine`.
2. Every `BulletPool` is a direct child of the root, and `StreamPool` holds `GATLING_STREAM`.
3. Pool sizing:
   - `pool_size ≥ pool_size_for(stream_rounds_max, 1400 / round_speed, brain.min_window_period())`, which is 36. The
     minimum window period is spin_up + (min_rounds − 1) × interval + cooldown + reposition_min = 2.28 s, read from
     config.
   - `pool_size ≥ 20` (the legacy rail pool).
   - **`pool_size < pool_size_for(1, 1400 / rail_stream_speed, rail_stream_interval)` (71): the rail starvation, named
     as deliberate.**
4. Config:
   - pins `turn_rate × max_speed ≤ acceleration`;
   - reaches the mover, health and contact damage;
   - the pattern is per instance: two Gatlings hold different pattern objects, each with its own brain's `rng`.

Rail:

5. `suspend_ai()` installs the rail pattern from the config fields, self-timed and enabled, with the light OFF.
6. `tick(rail_stream_interval + ε)` × 3 gives 3 rounds in the world.

Rhythm (dual: `open_space`, `assault`):

7. The sequence APPROACH → SWING_IN → SPIN_UP → STREAM → COOLDOWN → REPOSITION → SWING_IN (a second window).
8. Light: CHARGING through SWING_IN and SPIN_UP, ARMED in STREAM, OFF in COOLDOWN, REPOSITION and APPROACH.
9. SPIN_UP lasts `spin_up_seconds` ± 1 tick with **0 shots**. STREAM fires N ∈ [8, 12] with every gap
   `stream_interval` ± 1 tick, and N equals `stream_rounds`. COOLDOWN lasts `cooldown_seconds` ± 1 tick with **0
   shots**.
10. **Seed sweep** (staged straight into SPIN_UP; seeds 1..40): N = 8 and N = 12 both occur, and no N outside [8, 12].
11. Side-on: during every STREAM tick, |φ| ∈ [55°, 125°]. This covers ≥ 2 windows in Open Space and the first window
    in Assault.
12. The stream leads a moving player: with the player at 150 px/s, the mean round direction points ahead of the
    player's current position along its velocity.

Sides:

13. **Assault first window:** the player is 150 px left of centre (N7), and the first SWING_IN's `F.x` > the corridor
    centre (the half opposite the player).
14. **Assault alternation:** with the same player, later windows' sides alternate (+1, −1, +1).
    `engage_seconds` is raised on the private config for this case.
15. **Assault wall exception:** with the player 100 px from the right wall, every window has `side = −1` and
    `F.x < P.x`. **The same run with the exception disabled (`min_flank_range = 0` on the private config) does
    flip**, which proves the case can fail.
16. Open Space: windows alternate sides.
17. Open Space routing: from the second window on, the body never comes within `min_flank_range` of a holding player.

Budget:

18. **With remaining budget < `swing_in_max`, the Gatling never enters SWING_IN and its light is never CHARGING.** It
    holds and then DISENGAGEs on expiry. Staged on the private config `engage_seconds`.
19. **Expiry during STREAM:** the stream still fires all N rounds. DISENGAGE starts on the tick STREAM ends, never
    COOLDOWN, and within `spin_up + sync_wait_max + max_rounds × interval` (2.08 s) of expiry.
20. Expiry in REPOSITION → DISENGAGE on the same tick.
21. The Assault DISENGAGE frees the Gatling outside the world rect. Open Space never disengages. In Assault it stays
    inside `inner_rect().grow(soft_band)` until DISENGAGE.
22. `phase_changed` carries the phase entered.

`test_enemy_dual_mode.gd`:

23. The Gatling's APPROACH mid-corridor is identical in both modes (30 ticks).
24. The Gatling's budget frees it in Assault only (parametrised).

Invariant gates: contact damage, contact geometry, hurtbox geometry, config isolation, single writer, signal arity,
sprite transparency, UID integrity, project load integrity. All green, unchanged.

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | The [estimate] side-on sweep exceeds 125° on some window | Case 11 measures it. The lever is the strafe sweep (`stream_strafe_speed`, a config value), not the bounds |
| R2 | The level-1 frozen shots/s equality trips on the pool change | §D7: keep the constant (it is the legacy baseline), assert the live value as constant + computed delta, and record it |
| R3 | A hand-ticked Gatling's shots never expire and starve its pool | `_simulate()` recycles each shot on the tick it is fired (the `test_fighter.gd` technique) |
| R4 | REPOSITION never reaching `swing_in_reach` (a fleeing Open Space player) | `reposition_cap` 5.0 s hands over anyway |
| R5 | Window period ≈ 5.8 s (D2) is slower than the epic's ≈ 2.8 s estimate | Recorded for t16. Lower density only eases its gates |

## Out of scope

- Squad membership, convergence and the `sync_wait_max` hold (t11).
- Hub idle (t12).
- The new sprite and `sprite_forward_angle` (t15). The legacy `interceptor.png` stays.
- Level-1 migration and the deadline rows (t16 / t17).
- The `ENEMY.md` "fires forward" correction and `docs/enemy-roster.md` (t18).
