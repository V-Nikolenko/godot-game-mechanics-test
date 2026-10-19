# The Missile Corvette fights (epic t8)

The design is the epic's approved plan (`docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.10, with §2.4 for the tow
refusal and §4.1 / §4.3 for the tests). This file pins only the build choices §2.10 leaves open, the build order and the
test layout. Nothing below changes a name, number or rule of the epic plan.

## Problem

After t7 a Missile Corvette closes to range and parks: it never shoots, never circles and never reacts to a player who
rushes it. The player should meet a ship that holds a broad, wandering arc at medium range with its nose on them, that
can only launch at a player in front of it (getting behind it is the counterplay), that shows a 0.7 s tube glow before
every salvo, and whose salvos cover where the player is heading (Dumb rockets along the predicted path, a Pursuit
volley at a fleeing player, Clusters at a far crossing one, a Warhead pair across the path of a close one).

## Design

All in `assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd` (requests only), plus one generalised reader
in `enemy_rocket_scenes.gd`.

### Public surface added to `MissileCorvetteBrain`

| Name | Meaning |
|---|---|
| `choose_kind(distance: float, player_speed: float, radial_speed: float) -> EnemyRocket.Kind` | §2.10.4, deterministic. `radial_speed` (required, R1 S3) = player velocity along corvette→player (> 0 = moving away). Tangential = `sqrt(max(speed² − radial², 0))`. Order: `distance < warhead_range` → WARHEAD; `player_speed >= pursuit_flee_speed and radial_speed > 0` → PURSUIT; `distance >= cluster_min_range and tangential > abs(radial_speed)` → CLUSTER; else DUMB. |
| `attack_window() -> float` | `salvo_telegraph + (max(salvo_count, warhead_salvo_count) − 1) × salvo_gap` from config (1.14 s shipped): the deferral bound and the gate. |
| `salvo_size(kind) -> int` | `warhead_salvo_count` for WARHEAD, else `salvo_count`. The only place the count is read. |
| `force_next_kind(kind)` | Test seam (the Razor's `force_next_window` idiom): the next TELEGRAPH uses `kind`, skipping choice and swap. Consumed. |
| `salvo_kind: EnemyRocket.Kind` | The kind of the salvo being telegraphed / fired. |
| `salvo_cooldown: float` | Seconds until a salvo may start; drawn `rng.randf_range(salvo_period_min, salvo_period_max)` at the first tick and again when a SALVO ends; decremented every tick in every phase, floored at 0. Public so the Assault gate rows can zero it. |
| `orbit_dir: float` | ±1, rng-chosen at the first tick; flipped on reversal. |
| `salvos_fired: int` | Completed salvos (tests). |
| `in_launch_cone(target_pos: Vector2, cone_deg: float) -> bool` | Angle between the nose (`RIGHT.rotated(rotation + sprite_forward_angle)`) and the line to the target ≤ `cone_deg / 2`. |

The 1-in-4 DUMB→PURSUIT swap is **outside** `choose_kind` (in `_roll_kind()`, drawn from `rng`), so `choose_kind` stays
a pure function the tests read directly.

### Phases

- **APPROACH** (t7): unchanged; enters HOLD_ARC once `|distance − held_range()| <= range_tolerance`.
- **HOLD_ARC**: `_arc_motion(delta, 1.0)`; then, if `salvo_cooldown <= 0`, there is a target, `in_launch_cone(player,
  launch_cone_deg)`, the attack gate passes and no expiry is pending → TELEGRAPH. Never returns to APPROACH: the orbit
  anchor follows the player, so a fleeing player is chased at up to `max_speed` anyway.
- **`_arc_motion(delta, scale)`** (shared by HOLD_ARC, TELEGRAPH, SALVO):
  - radius = `held_range() + drift`, `drift = range_drift × sin(TAU × arc_clock / drift_period + drift_phase)`, with
    `drift_period` = rng in [6, 9] s and `drift_phase` = 0 or π (rng sign), so the arc **starts on R** and wanders from
    there (a corvette entering HOLD_ARC is never put on the inner edge at once).
  - Orbit: on HOLD_ARC's first entry the angle is synced to the corvette's current bearing about the player; each tick
    `angle += orbit_dir × orbit_angular_speed × scale × delta`, then `mover.orbit(player, radius, angle, max_speed)`.
  - Reversal: a countdown drawn in [`reversal_min`, `reversal_max`] runs in every arc phase; on expiry `orbit_dir` flips
    and a new one is drawn (the Razor idiom, without its lerped REVERSE phase: the anchor simply turns back and the mover's
    acceleration smooths it).
  - **Inside `min_range`** the request is the **blend** `orbit request + Steering.break_contact(pos, player, player
    velocity, −orbit_dir, max_speed)` (one `request_velocity`; the mover caps the sum at `max_speed`). The orbit term,
    whose anchor recedes with a closing player, keeps the radial share high; the break term adds the sideways escape. On
    leaving `min_range` the orbit angle is re-synced to the current bearing, so the anchor is never left behind.
    **Side (R1 B2):** §2.10.2's "side = orbit direction" means *the sense the arc turns*. `break_contact`'s lateral is
    `away.orthogonal() × side` (a −90° turn for +1) while the orbit's +1 travels +90°, so that sense is `side =
    −orbit_dir`. Measured (scratch build, 350 px/s rusher, Assault): closest pass 250 px with `−orbit_dir`, 147 px with
    the literal `+orbit_dir`, 200 px with no blend; mean sideways speed in the arc's sense +34 px/s vs −13 px/s without
    the blend.
  - Nose: `mover.face_toward(player)` every tick (the mover's `max_turn_rate` 1.2 rad/s is the cap).
- **TELEGRAPH** (`salvo_telegraph`): entry rolls `salvo_kind`, `StateLight` CHARGING. Each tick: `_arc_motion(delta,
  0.5)`, tube glow = `phase_time / salvo_telegraph` (0→1). **Open Space only**: if the player is outside a cone of
  `2 × launch_cone_deg` (i.e. > 45° off the nose) the salvo is cancelled → HOLD_ARC, light OFF, glow 0 (cooldown stays
  0, so a returning player sees a fresh telegraph). At `phase_time >= salvo_telegraph` → SALVO, and SALVO's first tick
  runs in the same frame so the first rocket leaves exactly at the telegraph's end.
- **SALVO**: entry `BurstClock.start(salvo_size(salvo_kind), salvo_gap)`, `StateLight` ARMED. Each tick:
  `_arc_motion(delta, 0.5)`; for every shot `advance()` reports, `actor.fire(salvo_kind, _aim_point(i))` with `i` the
  shot index; tube glow flashes to 1 per launch and decays to 0.35 over `salvo_gap`. When the burst is done: `salvos_fired
  += 1`, a new `salvo_cooldown`, light OFF, glow 0, then DISENGAGE if an expiry is pending, else HOLD_ARC. Never COMMIT.
- **Aim points** (fresh `TargetInfo` per shot, intercept from that shot's tube — `MissileCorvette.next_tube_position()`,
  a new read-only getter beside `fire()` for the tube `fire()` will use next):
  - DUMB: `T = intercept(tube, cruise(DUMB)).time` (0 if not ok); aim = `predicted_position(T + i × salvo_lead_step)`.
  - PURSUIT / CLUSTER: aim = `intercept(tube, cruise(kind)).point`.
  - WARHEAD: base = `intercept(tube, cruise(WARHEAD)).point`; `across` is **fixed once per salvo at SALVO entry** (R1
    S1): the player velocity's perpendicular, normalised, or, for a still player, the perpendicular of the line from the
    hull's centre; aim = `base + across × warhead_offset × (+1 for i = 0, −1 for i = 1)`. The pair's separation along
    `across` is exactly `2 × warhead_offset` by construction.
  - `cruise(kind)` = the kind's scene export, read once at the first tick through a new
    `EnemyRocketScenes.export_of(kind, property, fallback)` (`PackedScene.get_state()`, no instantiation);
    `max_time_of()` becomes a one-line call of it.
- **Assault budget**: `budget.update()` turning true is seen once. In TELEGRAPH or SALVO it only sets
  `_disengage_pending` (the salvo finishes: ≤ `salvo_telegraph + (max(salvo_count, warhead_salvo_count) − 1) ×
  salvo_gap` = 1.14 s); in any other phase → DISENGAGE at once. **Attack gate**: TELEGRAPH starts only if
  `budget.remaining() >= attack_window() + ATTACK_GATE_MARGIN` (1.14 + 0.05; INF in Open Space), `ATTACK_GATE_MARGIN :=
  0.05` as on the Ram. Assault never cancels a started TELEGRAPH.
- **Tow**: `accepts_tow()` (already in t7) false in TELEGRAPH and SALVO. Row added to `_REFUSING_PHASES`.
- **Rails**: `on_suspended()` also clears the tube glow (a rail may take it mid-telegraph).

### Rejected alternatives

- Putting the 1-in-4 swap inside `choose_kind`: makes the function the tests pin non-deterministic.
- Freezing all three DUMB aim points at SALVO entry: the plan's formula is per rocket, from its own tube; per-shot is
  also correct for a player who turns mid-salvo.
- A separate REVERSE phase (Razor): the corvette is slow and broad; a flip of the anchor's direction is enough and keeps
  the append-only enum unchanged.
- Pure `break_contact` inside `min_range`: radial escape ≈ 134 px/s, which estimates put close to the 228 px bound in
  Assault; the blend keeps the sideways escape and gives ≈ 190 px/s radially.

## Build sequence

1. `EnemyRocketScenes.export_of()` (+ `max_time_of` on it); `MissileCorvette.next_tube_position()`.
2. Tests first: the §2.10 rows below in `test_missile_corvette.gd` and the `_REFUSING_PHASES` row; watch them fail.
3. Brain: arc motion, cone, kind, telegraph, salvo, aim points, budget gate/deferral.
4. Run the file, then `scripts/check-test-leaks.sh`, `scripts/gate-time.sh`, `/agent/verify.sh`.
5. ENEMY.md, DECISIONS t8 line, roster doc where the corvette's behaviour is described.

## Test plan

All in `tests/integration/test_missile_corvette.gd`, hand-ticked with `_tick` (brain + integrated velocity), dual-mode
(`use_parameters(["open_space", "assault"])`) unless marked, every corvette seeded (`rng_seed`). Rockets fired during a
hand-ticked row stay where `fire()` put them (no frames pass), which is what lets the aim rows read `aim_point()` and the
launch position; no row counts rockets across more than one salvo (the pools never refill without frames). A row that
builds several harnesses calls `_retire_players()` first: `TargetInfo.player()` takes the first node in group "player",
which would otherwise be an earlier iteration's stub. `salvo_cooldown` is zeroed only **after** the first tick (which draws
it). Budget rows use the Ram's idiom: `budget.seconds = elapsed + DT + left`, so `left` is what the gate reads on the
next tick (R1 B3).

| Test | Asserts |
|---|---|
| `test_approach_closes_to_the_held_range_in_each_mode` (t7 row, **changed**, R1 B1) | From 860 px it starts in APPROACH; at the tick HOLD_ARC takes over, `|d − R| <= range_tolerance`; after 15 s within `R ± (range_drift + range_tolerance)`. (The t7 form, "parked within 25 px of R", is exactly what t8 replaces with the drifting arc.) |
| `test_holds_a_broad_arc_at_range_from_1200_px` | Stationary stub; corvette 1200 px away (Assault: stub (640, 360), corvette straight above). After 6 s, for 10 s: distance within `R ± (range_drift + range_tolerance)` every tick; Σ\|Δbearing\| ≥ 60°. |
| `test_a_rushing_player_is_kept_at_bay` | Corvette at `R` on the stub's line (→ HOLD_ARC on its first tick), settled 0.5 s; stub closes straight at it at 200 px/s for 2.0 s, then stops. Closest approach ≥ 0.6 × `min_range`; back outside `min_range` within 3.0 s of the stop. Assault: stub at (640, 900) — corridor top 820 px behind the corvette. |
| `test_a_faster_rusher_gets_inside_and_is_sidestepped` (R1 B2, boundary) | Same, stub at 350 px/s: it does get inside `min_range` (sanity); while inside, mean outward radial velocity > 0 and mean tangential velocity in the arc's sense ≥ 15 px/s; closest ≥ 0.5 × `min_range`; back out within 3 s. Fails with no blend (−13 px/s) and with the literal side (147 px). |
| `test_the_orbit_reverses_within_15_s` (Open Space) | `orbit_dir` flips and the measured bearing rate (0.5 s windows) changes sign. |
| `test_no_salvo_at_a_player_held_behind_it` | Scripted follower keeps the stub at `R` exactly behind the nose for 6 s; on every tick HOLD_ARC, cooldown 0 and the gate open (R1 S4): zero TELEGRAPH entries, zero rockets. Control: the stub put in front → TELEGRAPH on the next tick. |
| `test_a_player_in_front_draws_a_telegraph_in_time` | Stub in front at `R`: first TELEGRAPH ≤ `salvo_period_max + 1` s. |
| `test_salvo_shape_per_kind` | For each kind (forced): first rocket `salvo_telegraph` ± 1 tick after the TELEGRAPH tick; `salvo_size(kind)` rockets (3/3/3/2) of that kind at `salvo_gap` ± 1 tick; light CHARGING → ARMED → OFF, never COMMIT; `accepts_tow()` false on every TELEGRAPH/SALVO tick and true in HOLD_ARC after. |
| `test_dumb_aim_points_lead_along_the_predicted_path` | DUMB forced; stub crossing at 250 px/s: each aim point within 1 px of `stub_pos + v × (intercept(tube, cruise).time + i × salvo_lead_step)` (recomputed by the test from a hand-built `TargetInfo` and the rocket's launch position) and within 1 px of the stub's line. |
| `test_kind_choice` | `choose_kind`: fleeing at 350 px/s at 600 px → PURSUIT; same speed closing → DUMB; 300 px → WARHEAD (also when fleeing); the 420 px edge → DUMB; crossing at 800 px → CLUSTER; crossing at 650 → DUMB; mostly radial at 800 → DUMB; fleeing at 200 → DUMB; `salvo_size` 3/3/3/2. |
| `test_a_fleeing_player_draws_a_pursuit_salvo` | A real stub fleeing at 350 px/s, in front, beyond `warhead_range`: the TELEGRAPH's `salvo_kind` is PURSUIT. |
| `test_a_close_player_gets_a_warhead_pair_across_its_path` | Stub at 300 px (moving at 150 px/s, and still). Setup through the seams (R1 S1): first tick, `enter_phase(HOLD_ARC)`, cooldown 0 — the kind is *chosen*, not forced. One salvo of 2 WARHEADs; separation across the velocity (moving) / its length (still) = 180 ± 1 px. |
| `test_one_dumb_choice_in_four_becomes_a_pursuit_salvo` (Open Space, R1 S2) | 200 seeded `enter_phase(TELEGRAPH)` rolls: in a DUMB situation the PURSUIT share is in [0.15, 0.35] and nothing else appears; WARHEAD and CLUSTER situations are never swapped. |
| `test_assault_salvo_started_with_1_2_s_left_completes` (Assault) | Gate reads 1.2 s on the TELEGRAPH tick: all 3 rockets fire, then DISENGAGE. |
| `test_assault_no_salvo_starts_with_1_0_s_left` (Assault) | Cooldown zeroed, stub in cone, gate reads 1.0 s and (R1 B3) 1.17 s: no TELEGRAPH before DISENGAGE, no rocket. |
| `test_the_attack_window_comes_from_the_config` | `attack_window()` = the config formula = 1.14 s. |
| `test_budget_expiry_mid_telegraph_defers_to_the_salvo` (Assault) | Expiry 0.3 s into a forced TELEGRAPH: phases SALVO then DISENGAGE, 3 rockets out first, DISENGAGE within `salvo_telegraph + 2 × salvo_gap + 2 ticks` of the TELEGRAPH start (R1 S4). |
| `test_a_telegraph_cancels_when_the_player_leaves_the_cone_only_in_open_space` | Stub jumped behind mid-TELEGRAPH: Open Space → HOLD_ARC, light OFF, no rocket for 0.8 s; Assault → the salvo fires (3 rockets). |
| `test_the_tubes_glow_up_through_the_telegraph_and_flash_per_launch` (Open Space, R1 S5) | `TubeLightL` alpha: 0 at TELEGRAPH start, never falls through it, ≈ half (0.425 ± 0.05) halfway, ≥ 0.8 at its end; 0.85 on each launch tick, below 0.85 and ≥ the 0.35 floor between launches; 0 after. |
| `test_a_rail_taking_the_corvette_mid_telegraph_darkens_its_tubes` (Open Space, R1 S5) | `suspend_ai()` mid-TELEGRAPH: alpha 0, light OFF. |
| `test_the_arc_is_within_the_hulls_turning_budget` | `max_speed² / R ≤ acceleration` for both ranges, read from the shipped `.tres`. |
| `test_export_of_reads_a_rocket_scenes_export_without_instantiating_it` | `export_of(kind, &"cruise_speed")` equals each instantiated scene's value; DUMB = 520; `max_time_of` unchanged; a missing export returns the fallback. |
| `test_base_enemy.gd` `_REFUSING_PHASES` | `"missile_corvette": ["TELEGRAPH", "SALVO"]` through the real `enter_phase`. |

Boundary cases: the 1.17 s and 1.0 s gate rows, the behind-the-nose row (with its in-front control), the faster-rusher
row (side and blend), the cancel row, the ramp's halfway value. Each was mutation-checked in a scratch build: cone always
open, gate margin 0, gate off, no deferral, no lead step, both warheads on one side, tow accepted, no cancel, no
reversal, no arc, literal side, no blend, swap chance 0, constant glow, no flash, glow kept on a rail, warhead count =
`salvo_count` and no PURSUIT branch each fail at least one row. The single-writer, signal-arity, project-load and
config-isolation sweeps see the new code with no edits.

## Risks

- **Bounded chase in Assault**: R 460 is close to `min_range` 380; if the blend still dips below 228 px the fix is a
  behaviour change inside §2.10 (e.g. break term weight), never a weaker assertion.
- **Hold-range from 1200 px in Assault** starts above the corridor (not yet entered): rule 1 of the constraint floors
  the inward speed, which can only help.
- **Gate time**: ≈ 1000 hand ticks × 2 modes for the long rows; well inside 5.0 s by the Ph4 per-case costs.

## Out of scope

Hub idle (t15), hub and level placement (t16/t17), art (t9), the Support Ship (t10–t14).

## Revision 1 (answers to review round 1)

- **B1** — the t7 approach row is rewritten (above); `test_enemy_dual_mode.gd`'s corvette case still holds (it starts
  at 700 px and only asserts it moves and closes).
- **B2** — side pinned to `−orbit_dir` with the sign derivation and measurements; new faster-rusher row fails without the
  blend and with the literal side.
- **B3** — budget idiom pinned; `attack_window()` from config with its own row; 1.17 s row added.
- **S1** — `across` frozen at SALVO entry from the hull's centre / the velocity; warhead row setup pinned through the
  seams; tolerance 1 px for both cases.
- **S2** — swap row added. **S3** — `radial_speed` required. **S4** — preconditions and control in the behind row;
  DUMB already forced in the aim row; deferral bound asserted. **S5** — glow ramp/flash and rail rows added.
- Minor: the same-frame SALVO tick runs `_tick_salvo(0.0)`, which skips `_arc_motion` (delta 0) and the cooldown
  decrement lives in `tick()` only, so nothing runs twice. The cone keeps its own nose maths through
  `EnemyMover.sprite_forward_angle_of` (`_nose()`); `relative_angle_from` needs a `TargetInfo`, the cone takes a point.
