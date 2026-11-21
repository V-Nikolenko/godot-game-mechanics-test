# The Hijack Pulse (Phase 9 t9) — revision 2

Epic plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.11 (approved). This task plan only fixes what §2.11 leaves open; where the two
differ, §2.11 wins unless a line below says **Deviation** (each is listed in §7 and logged in `DECISIONS.md`). Revision 2 answers review round 1
(`4-review.md`); see "Response to review round 1" at the end.

## Problem

Today the Hacker Frigate (t8) only moves: it holds range on lopsided arcs, slides out of the player's nose and breaks off when rushed. Its
TELEGRAPH and PULSE phases are stubs. After this task the player sees it charge (yellow light, the dish unfolding, a ring of six dashes closing
in) and then pulse (white light, ripples from the dish). During the pulse, small white-amber darts fly from the hull to the player's homing rockets
within 650 px, both those already in flight and those launched during the window. Each dart that reaches its rocket turns it against the player
(t4's hijacked rocket). The counters:
- **Hit it while it charges:** any damage during TELEGRAPH cancels the pulse.
- **Hold fire:** with no rockets in flight there is nothing to claim.
- **Fire away from it at range:** a dart cannot catch a rocket receding at full range, so those rockets keep their own target.
- **Kill it:** its darts vanish and its claimed rockets fizzle.

**What a hijack threatens, measured (review B1).** With t4's hijack tuning (380 px/s, 1.6 rad/s, 2.5 s, armed at 0.25 s and 60 px), a rocket
claimed while heading away from the player, anywhere from 0° to 60° off "away" and 100–550 px out, fizzles before it can come back. That is the
usual case: the salvo was fired at the Hacker, the nearest enemy, so `RocketState` locked onto it.
- A still or strafing player who fires at the Hacker loses the salvo but is never blasted (closest approach ≈ 305 px in Open Space, ≈ 188 px in
  Assault).
- The blast threatens a player who **flies after their own rockets**, or rockets claimed while **already heading back toward the player** from
  ≥ 350 px. That happens, for example, to rockets locked on an enemy behind the player as they pass the Hacker.

This task pins that limit with a row (22a), so a later retune flips a visible row. Whether to retune `hijack_turn_rate` / `hijack_seconds` /
`hijack_speed` is an **owner decision**, asked in the task report. It is not changed here: t4's numbers are the approved §2.5 values.

Warheads and primary fire are never touched. A Disruptor hook (`pulse_lock_seconds`, 0 on the base Hacker) locks the player's abilities when a
pulse ends; t10 only adds the Disruptor's scene and config.

## Design

### 1. The dart: `assault/scenes/projectiles/hijack_pulse/`

`hijack_pulse.gd` (`class_name HijackPulse extends Node2D`) and `hijack_pulse.tscn`. The scene is a root `Node2D` with the script and a
`ProjectileLifetime` child (`max_time` 1.6, `max_distance` 1400, `use_world_rect` true). It has **no `Area2D` and no `CollisionShape2D` anywhere**,
and claims by distance.

- Exports: `speed` 900.0 and `claim_radius` 16.0.
- `signal expired` (no arguments). It is emitted only through the lifetime's latch (`ProjectileLifetime.expire_now()`), so it fires once per flight.
  The dart's own `_ready()` connects `expired` → `_on_expired()` (`_flying = false`), so a lifetime trip also stops it.
- `reset()` (called by `BulletPool.acquire()`): clears the rocket, source, trail and flags, and re-arms the lifetime.
- `launch(rocket: Node2D, source: Node)`:
  - Places the dart at `(source as Node2D).global_position` when the source is a `Node2D` (the hull centre, never the dish).
  - Re-arms the lifetime there (`_lifetime.reset()`, so the 1400 px rule measures from the hull centre).
  - Stores the rocket and source, sets `_flying` and turns the dart toward the rocket. A null rocket ends the dart at once.
- `_physics_process(delta)`, while flying:
  1. **No claim** if any of the following holds; `_end()` without claiming:
     - the source was given and is now freed or queued for deletion;
     - the rocket is not a valid instance, is outside the tree or is queued for deletion;
     - the rocket does not answer `can_be_retargeted() == true` (claimed by another, inside a lit jammer, done).
  2. **Move:** push the current position into the trail (3 points), then move `min(speed · delta, distance)` straight at the rocket's current
     position. It homes exactly, with no turn limit.
  3. **Claim:** if within `claim_radius` (≤) of the rocket, take `players[0]` of group `player`, the same rule as `TargetInfo.player()`
     (no extra filter). If it is a valid `Node2D`, call `rocket.retarget(player, -1.0, source)` (the rocket uses its own `hijack_seconds`).
     Then `_end()` on the same tick, whether or not the claim succeeded.
  4. Otherwise `queue_redraw()`.
- `_end()`: `_flying = false`, `_lifetime.expire_now()`. The pool recycles the dart on `expired`. The dart never frees itself and never draws
  the tether (that is the rocket's, t4).
- Read-only seams: `is_flying() -> bool`, `rocket() -> Node2D`, `source() -> Node`.
- `_draw()`: a 6 px diamond (core `Color(1.0, 0.95, 0.85)`, rim amber `Color(1.0, 0.7, 0.3)`) along its heading, plus 3 trail points drawn as
  fading dots (alpha 0.6 / 0.4 / 0.2) in local space. Code-drawn, no texture.

### 2. The Hacker scene and script

- **`hacker_frigate.tscn`:** gains a `DartPool` root child, a `BulletPool` with `bullet_scene = hijack_pulse.tscn`, `pool_size` 4 and
  `persist_after_owner_death` false. Its container is the Hacker's parent, so a dying Hacker's darts are freed with it.
- **`hacker_frigate.gd`:**
  - `dart_pool() -> BulletPool`.
  - `fire_dart(rocket: Node2D) -> HijackPulse`: `acquire(global_position)`, then `launch(rocket, self)`. Returns null when the pool is exhausted.
  - `lock_player_abilities(seconds: float) -> void`: calls the duck-typed `apply_ability_lock(seconds, self)` on `players[0]` of group `player`
    (the `TargetInfo.player()` rule), guarded by `has_method` (the harness stub has none).
    This is the projectile / `EmpPulse` resolution; brains never read the group, so this lives on the ship.
  - **The tell (IDEAS §21, on parts and the light, never the hull):**
    - `set_dish_open(f: float)`: `Dish.scale = lerp(DISH_FOLDED_SCALE 0.6, 1.0, f)`; folded in `_ready()`.
    - `show_charge(f: float)`: a ring of 6 yellow dashes at `r = lerp(60, 40, f)`, turning slowly.
    - `show_pulse(t: float)`: white-amber ripple rings from the dish, a new one every 0.4 s, each growing 12 → 92 px and fading over 0.4 s.
      `ripple_count()` = ripples emitted this PULSE = `floor(t / 0.4 + 1e-6) + 1`, so 1 / 2 / 4 at t = 0.0 / 0.41 / 1.21 s; 0 outside PULSE.
    - `clear_tell()`.
    - All are drawn in the ship's own `_draw()`. `Hull` is `show_behind_parent`, so the rings sit above the hull; `Dish` draws above them.
    - Read-only: `dish_open()`, `tell_kind()` (`&""`, `&"charge"`, `&"pulse"`), `charge_ring_radius()`, `ripple_count()`.
  - `_ready()`: after `_apply_config`, `_hacker_brain.watch_health(health)`.
  - No motion writes (the single-writer sweep reads this script).

### 3. Config (`HackerFrigateConfig`, new `@export_group("Pulse")`; values in `.tres`)

| Field | Value | Meaning |
|---|---|---|
| `pulse_trigger_range` | 870.0 | The player must be within this distance (≤) to start TELEGRAPH, and for the PULSE-end lock. |
| `hijack_range` | 650.0 | Rocket-claim reach round the hull (`SeekingOrdnance.eligible`, inclusive). |
| `max_claims_per_pulse` | 3 | Darts per pulse (the cap). |
| `pulse_telegraph` | 0.9 | |
| `pulse_seconds` | 1.6 | |
| `pulse_period_min` / `pulse_period_max` | 6.0 / 8.0 | The cooldown after a PULSE or a cancel, from `rng`. |
| `first_pulse_delay` | 2.0 | The cooldown at the start, and again on NOTICING. |
| `assault_pulses_per_life` | 1 | PULSE entries allowed while the Assault budget is active. |
| `pulse_lock_seconds` | 0.0 | The Disruptor hook (t10's config: 1.5). |

All fields are flat (`test_config_instance_isolation.gd`).

### 4. Brain (`HackerFrigateBrain`)

New public state, all read-only for tests and docs:
- `pulse_cooldown: float`
- `pulses_fired: int` (PULSE entries)
- `telegraphs: int`, `telegraph_cancels: int`
- `darts_fired: int`, `claims_this_pulse: int` (darts launched this PULSE)
- `live_darts() -> Array[HijackPulse]` (the brain's darts still flying)

- **Clock:** `pulse_cooldown` counts down every tick in every phase (`x -= delta`, 0.0 at `<= 1e-6`), ahead of the phase dispatch.
  - `_start()` sets it to `first_pulse_delay`, so the first TELEGRAPH is on the tick the clock reaches 0: tick 120 at the shipped 2.0 s.
  - **NOTICING** entry sets it to `first_pulse_delay` again (the corvette's rule: a calm ship does not attack the instant it notices).
- **`_want_pulse(target)`**, checked in HOLD_ARC after `_arc_motion` and never on a tick BREAK_OFF was entered. All must hold:
  - `pulse_cooldown <= 0`;
  - not `_disengage_pending`;
  - Assault cap: `budget.active` implies `pulses_fired < assault_pulses_per_life`;
  - distance to `target.position` ≤ `pulse_trigger_range`;
  - LOS: `not Engine.is_in_physics_frame() or can_see_player()` — the `LaserTenderBrain` precedent. Off the physics step (a hand-ticked row) no
    ray is cast and the line counts as clear; on the step it is the Ph6 rule, where only asteroids and wrecks block.
- **TELEGRAPH:**
  - Entry: `telegraphs += 1`, light CHARGING (yellow).
  - Each tick: `_arc_motion` (the Hacker keeps moving); dish open = `_phase_time / pulse_telegraph`; `show_charge(same)`.
  - At `_phase_time >= pulse_telegraph - 1e-6`: enter PULSE and run the first dart pass on that same tick, so in-flight rockets are picked up on
    PULSE's first tick (the corvette's "first rocket on the telegraph's last tick").
  - **Cancel** (`_cancel_telegraph()`): `telegraph_cancels += 1`; `pulse_cooldown = rng.randf_range(min, max)`; dish folded; tell cleared. Then
    DISENGAGE if the budget is pending or has expired, else HOLD_ARC. It runs on any of:
    - **damage:** the health watch sees a decrease while in TELEGRAPH;
    - **budget expiry** in TELEGRAPH (`_on_budget_expired()`, no longer deferred for TELEGRAPH);
    - **lost target:** no player while in TELEGRAPH;
    - **EMP** (`on_emp_started()`).
- **PULSE:**
  - Entry: `pulses_fired += 1`, `claims_this_pulse = 0`, light COMMIT (white), dish open 1.
  - Each tick: `_arc_motion`; `show_pulse(_phase_time)`.
  - If `_phase_time >= pulse_seconds - 1e-6`: `_end_pulse()`. Otherwise run the dart pass. Darts therefore go out on ticks 0..95 (96 ticks = 1.6 s).
- **Dart pass (`_fire_darts()`):**
  - Prune darts no longer flying.
  - For each rocket in `SeekingOrdnance.eligible(tree, actor.global_position, hijack_range)` (nearest first), while
    `claims_this_pulse < max_claims_per_pulse`, skip a rocket that:
    - is already the `rocket()` of a live dart;
    - is behind cover: on the physics step only, `LineOfSight.clear(space, hull, rocket, [actor rid])` is false.
  - Otherwise `fire_dart(rocket)`. A null (exhausted pool) stops the pass. Then `claims_this_pulse += 1`, `darts_fired += 1`.
  - **Interpretation:** "claims" in §2.11's cap counts darts launched. A dart that misses (rocket freed, out-run, jammed) still used its slot, so
    six eligible rockets give exactly three darts per pulse.
- **`_end_pulse()`:**
  - `pulse_cooldown = rng.randf_range(min, max)`; dish folded; tell cleared.
  - **Lock hook:** if `pulse_lock_seconds > 0`, there is a target, the distance is ≤ `pulse_trigger_range`, and LOS holds (the same gate as
    above), then `lock_player_abilities(pulse_lock_seconds)`.
  - Then DISENGAGE if `_disengage_pending`, else HOLD_ARC. A budget expiry during PULSE is deferred to here (the window finishes), and the hook
    still fires.
- **`on_emp_started()`** (**Deviation D2**, an addition to §2.11): in TELEGRAPH, `_cancel_telegraph()`; in PULSE, the window ends without the lock hook (the
  source was disrupted), with a fresh cooldown, then HOLD_ARC or DISENGAGE. Darts already flying finish their flight; they are the pool's.
  - **Why:** `EnemyBrain.on_emp_started()`'s contract is that a shown telegraph must not freeze for the EMP window. Without this the yellow
    light and charge ring would hang for up to 5 s and then pulse.
- **`on_suspended()`:** also folds the dish and clears the tell.
- **`watch_health(h: Health)`:** records `h.current_health` and connects `h.amount_changed` → `_on_health_changed(current: int)`, which
  cancels a TELEGRAPH on any decrease (a repair is an increase and does not cancel).
- `accepts_tow()` is unchanged (false in TELEGRAPH / PULSE). `_is_committed()` stays TELEGRAPH or PULSE: the hub idle never interrupts them, and
  BREAK_OFF is never entered from them (no break-off check runs in those ticks). Plan §2.11's "Hacker keeps moving (HOLD_ARC steering)" is
  satisfied by `_arc_motion`.

### 5. Existing rows that change

- **`test_hacker_frigate.gd`:** t8's rows test movement, so `_spawn()` also writes `first_pulse_delay = 1000.0` by default. Its `props` may put
  the shipped value back.
  - `_life()` does put it back, so the Assault life row runs with its real pulse (at 2.0–4.5 s, before the 9.0 s expiry).
  - The stub row becomes "TELEGRAPH and PULSE refuse a tow; HOLD_ARC accepts". "Never entered from HOLD_ARC" moves to `test_hijack_pulse.gd`
    as the cadence rows.
  - `test_a_budget_expiring_in_telegraph_goes_straight_to_disengage` stays as is (a cancel goes straight to DISENGAGE); its doc comment
    (line 756, "the deferral t9's real telegraph uses") becomes "the cancel t9's real telegraph uses".
  - Movement during TELEGRAPH / PULSE is no longer covered by these rows (the pulse is off in them), so `test_hijack_pulse.gd` row 23 covers it
    (review B2).
- **`hacker_frigate_brain.gd`** header comment line 19 ("A TELEGRAPH / PULSE finishes first") becomes "a TELEGRAPH is cancelled, a PULSE finishes
  first"; the TELEGRAPH / PULSE lines of the header are rewritten from "stub" to the real phases.
- **`test_enemy_dual_mode.gd`:** the Hacker's "closes to its held range" row asserts HOLD_ARC at 4.0 s, while the shipped pulse is in PULSE at
  4.0 s. The row writes `first_pulse_delay = 1000.0` (it is a movement row).

### 6. Docs

- The Hacker's `ENEMY.md` (TELEGRAPH / PULSE, the dart, the counters and the hook). The threat is stated as measured (§Problem, review B1c):
  a still or strafing player who fired at the Hacker loses the salvo but is not blasted; a player who follows their rockets, or rockets claimed
  heading back toward the player from ≥ 350 px, are. `PROJECT.md` says the same.
- A new `assault/scenes/projectiles/hijack_pulse/PROJECTILE.md`, or a section in the Hacker's `ENEMY.md`; the `updating-project-docs` skill decides
  which.
- `CLAUDE.md`, `PROJECT.md` (electronic warfare), `assault.md`, `docs/enemy-roster.md`.
- `DECISIONS.md` ("Phase 9, built in t9") and the `tests/README.md` gate row.

### Alternatives rejected

- **A dart with an `Area2D` claiming on overlap.** It needs a layer pair. A claim inside a physics callback would also defer the rocket's HurtBox
  opening, which t4 already handles, but it makes tick order implicit. §2.11 says no areas.
- **Counting only successful claims against the cap.** A missed dart would then free its slot and the Hacker could fire a fourth and a fifth dart
  in one pulse. The cap would stop meaning "three darts a pulse" and the cap row could not pin it.
- **Casting LOS in hand-ticked rows.** `LineOfSight` is physics-step only (F12). The tender precedent is to skip the cast off the step and to
  test LOS on real physics.

## Build sequence

1. Tests first: `tests/integration/test_hijack_pulse.gd` (all rows below) and the `test_enemy_bullet_lifetime.gd` row. Run them and watch them
   fail (no `HijackPulse`, stubs).
2. `hijack_pulse.gd` / `.tscn` (the dart rows pass).
3. Config fields + `.tres`.
4. `hacker_frigate.tscn` `DartPool`; `hacker_frigate.gd` (`fire_dart`, `lock_player_abilities`, the tell, `watch_health`).
5. Brain: the clock, `_want_pulse`, TELEGRAPH, PULSE, the dart pass, the cancel, `_end_pulse` with the hook, `on_emp_started`, `on_suspended`.
6. Adjust `test_hacker_frigate.gd` and `test_enemy_dual_mode.gd` (§5). Run the Hacker, dual-mode, base-enemy, seeking-ordnance, roster and
   lifetime files.
7. Pre-run rows 4, 6 and 22. Record the claim ticks, closest approaches, heading errors and the pinned damage in `DECISIONS.md`. Run the
   row-23 mutation check once (remove `_arc_motion` from TELEGRAPH / PULSE, see the row fail, restore it).
8. Docs (`updating-project-docs`), the gate-time row, `verify.sh`, `check-test-leaks.sh`.

## Test plan — `tests/integration/test_hijack_pulse.gd` (both harnesses, label-parameterised `use_parameters(["open_space", "assault"])`)

**Two kinds of row.**

- **Hand-ticked at 1/60.** The test ticks the Hacker, its darts and the rockets itself, in this order:
  1. the Hacker (`_physics_process`, then its position integrated from its velocity: the `test_hacker_frigate.gd` shape);
  2. the rockets (the rocket, then its lifetime);
  3. the live darts (the dart, then its lifetime).

  - Darts and rockets have their own physics off. After spawn, the test disables physics processing on every pooled dart and on its lifetime.
  - No hand-ticked row yields before its last tick, except row 15, which awaits only after everything is off.
  - Each hand-ticked row fires at most 4 darts, because the pool's recycle is deferred.
  - **Frozen** means the Hacker's brain and mover are ticked but its position is not integrated, so it stays exactly where it was placed. Every row
    that needs exact geometry freezes it.
  - Real player scenes in hand rows have their own physics and process off; the test moves them by hand.
- **Real physics at the 8× clock** (the `test_seeking_ordnance.gd` clock helpers), only for LOS, a real player bullet and real blast damage.
  - The Hacker runs on its own physics, **parked**: a test config with `max_speed` 0.001. `EnemyMover.step` limits every request to that, so it
    moves ≤ 0.001 px/s, while `face_toward` still turns the nose.
  - Each run ends on its own condition, never on a fixed long wait.

**Placements.**
- Default (from `test_hacker_frigate.gd`): the Open Space player at (0, 0), the Assault player at (640, 620).
- Rows with exact distances place every point **axis-aligned** from the hull, so float32 positions give the exact distance against
  `eligible()`'s inclusive `<=`.

Rows (every behaviour row has a control that switches the behaviour off and fails the same assertion):

1. **Structure.**
   - **Dart scene:** `HijackPulse` is a `Node2D` with no `CollisionObject2D` / `CollisionShape2D` anywhere in its subtree.
   - **Dart numbers:** `speed` 900, `claim_radius` 16, lifetime 1.6 / 1400 / world rect; `expired` declared with 0 arguments.
   - **Hacker scene:** `DartPool` is a `BulletPool` root child with `pool_size` 4, `persist_after_owner_death` false and the dart scene.
   - **Shipped config:** every §3 value, read off the `.tres`.
     - `pulse_trigger_range` = `preferred_range + range_drift + 60`.
     - The earliest second Assault TELEGRAPH (`first_pulse_delay + pulse_telegraph + pulse_seconds + pulse_period_min` = 10.5 s) is past
       `engage_seconds` 9.0, which pins why the cap is 1.
2. **Darts launch from the hull centre and claim on the tick they arrive** (hand, frozen Hacker, PULSE entered with `enter_phase`; the rocket held
   at hull + (0, 300)):
   - On its launch tick the dart is at the hull's `global_position` (the dish sits 14 px off it). Its lifetime origin is that point: the
     `max_distance` row 5 depends on it.
   - On the claim tick the rocket's `retargeted(source == hacker)` fires and the dart's `expired` fires once, on the same tick.
   - The claimed rocket's `is_tether_visible()` is true (the rocket owns the tether).
3. **A refused or vanished target ends a dart with no claim** (hand, frozen Hacker, rocket held at hull + (0, 400)):
   - **Freed:** the rocket is freed mid-flight; the dart's `expired` fires on its next tick, with no claim.
   - **Claimed first:** a fixture claimer takes the rocket first; the dart expires and `retargeted` fired only once, with the fixture as source.
   - **Jammed:** a lit jammer `HazardField` placed round the rocket after launch; the dart expires, with no claim.
   - **Control:** the same rocket untouched is claimed.
4. **In flight** (hand, Hacker on the shipped cycle with `first_pulse_delay` 0.5, `range_drift` 0, both cones 0; Hacker at its held range above the
   player):
   - Three rockets cross the Hacker's front 0.3 s before PULSE. They start 300 px left of the hull's x, 250 px nearer the player than the hull, 30 px
     apart along y, flying +x at static targets 900 px to the right.
   - Each is claimed by a dart during PULSE, `source == hacker`.
   - After its claim each rocket's heading changes by ≤ `hijack_turn_rate · DT + 1e-4` per tick, and the angle between its heading and the
     direction to the player falls below 10° before its window ends.
   - **Pre-run:** the geometry is pre-run in this task. The per-rocket claim tick, minimum heading error and closest approach are recorded in
     `DECISIONS.md` (review m8). If a rocket circles without lining up, the start points move further from the player and the change is logged.
   - **Control:** the same rockets with no Hacker are never retargeted.
   - **As built (pre-run):** the start points moved to the hull's level and 30 / 60 px beyond it (away from the player). At 250 px nearer the
     player the Assault claims were 250-310 px from the player, inside two hijacked turn radii (238 px), and the rockets circled it (heading
     error never under 55°). Moved: claims on ticks 91-92, heading error 0°, all three blast in both modes. Logged in `DECISIONS.md`.
5. **Receding rocket (the documented limit)** (hand, frozen Hacker at (0, 300) in both harnesses):
   - The rocket starts at (650, 300) and recedes along +x at 500 px/s. The Assault projectile rect is x −164…1444, so the rocket ends at
     ≈ 1433 px and the dart at 1410 px, both inside it (review m2).
   - It is held there until the Hacker's PULSE-entry tick has run, so it is eligible on PULSE's first tick (650.0 ≤ 650) and gets one dart.
   - The dart never claims it: the gap is > `claim_radius` on every tick.
   - The dart expires by the 1400 px rule on tick 94 (1.567 s; the plan's continuous figure is 1.556 s) with its clock < 1.6 s. The gap at expiry is
     ≥ 20 px (23.3 px with this tick order; 27.8 px continuous).
   - `darts_fired == 1` at the end of PULSE: there is no second dart.
   - **Control:** the same rocket at (650, 300) flying −x, toward the hull, is claimed.
6. **Newly launched + the measured limit** (hand, both real player scenes in place of the stub; review B1a):
   - **Setup:** the Hacker starts at the player + (0, −held range) on the shipped cycle with `first_pulse_delay` 0, so TELEGRAPH is at tick 1 and
     PULSE at 0.9 s. A real `RocketState` homing salvo (3 rockets, locked on the Hacker as the nearest enemy) is launched 0.5 s into PULSE.
   - **Main:** 3 darts, 3 claims (newly launched rockets are picked up).
   - **The measured limit, still player:** no `ContactBlast` is ever created, and every rocket's closest approach to the player is
     > `hijack_trigger_radius`. The approaches are recorded (review measured ≈ 305 px in Open Space, ≈ 188 px in Assault).
   - **Control A, a following player:** the same run, but the player flies after its rockets toward the Hacker's start at 420 px/s from the launch
     tick. It is blasted (≥ 1 `ContactBlast`). Pre-run in both harnesses; the measured blast time is recorded.
   - **Control B, a late salvo:** a second salvo launched 0.2 s after PULSE ends gets no dart (`darts_fired` stays 3).
7. **Cap** (hand, frozen Hacker): six held rockets at hull + (0, 300 / 350 / 400 / 450 / 500 / 550) during one PULSE give exactly 3 darts and
   3 claims, at 300 / 350 / 400. **Control:** `max_claims_per_pulse` 4 gives 4 darts and 4 claims. That is the pool size, so there is no exhaustion
   warning, and it shows the cap is what binds.
8. **No darts outside PULSE** (hand): with rockets held in range, `darts_fired == 0` and no dart is live during:
   - HOLD_ARC with the cooldown running;
   - BREAK_OFF (the player re-placed 400 px from the hull);
   - the whole TELEGRAPH.

   The first dart comes on PULSE's first tick.
9. **Ranges** (hand, frozen Hacker, `first_pulse_delay` 0):
   - **Trigger:** the player is re-placed every tick at hull + (0, 871); no TELEGRAPH in 60 ticks. At hull + (0, 869), TELEGRAPH on the first tick.
   - **Claim reach:** in PULSE, rocket A held at hull + (649, 0) and rocket B held at hull + (−651, 0), neither ticked. A is claimed; B gets no dart
     for the whole window (96 ticks).
10. **Cadence (Open Space)** (hand, `range_drift` 0, still player, Hacker starting 720 px away):
    - The first TELEGRAPH is on tick 120 (2.0 s), and there are ≥ 2 PULSEs in 20 s.
    - The second TELEGRAPH is ≤ 12.5 s, and each interval from a PULSE end to the next TELEGRAPH is in [6.0, 8.0] s.
    - **Control:** `pulse_trigger_range` 650 gives 0 TELEGRAPHs in 20 s (the Hacker holds ≈ 720 px).
11. **Disruptor hook** (hand, both real player scenes, the `test_player_boost_disruption.gd` shape):
    - **Main:** a test config with `pulse_lock_seconds` 1.0 and `first_pulse_delay` 0. `abilities_locked()` is false through TELEGRAPH and the whole
      PULSE, and true on the PULSE → HOLD_ARC tick. After 59 player ticks (`_step_disruption(DT)` each) it is still true; after 60 it is false.
    - **Controls:**
      - the shipped 0.0 never locks through a whole pulse;
      - with 1.0 and the player moved to 871 px for the PULSE-end tick, there is no lock.
12. **Jammer** (hand, frozen Hacker): a held rocket at hull + (0, 300) inside a lit jammer `HazardField` (r 120, the t4 fixture) gets no dart for the
    whole PULSE, while the Hacker still enters PULSE. **Control:** the same field 2000 px away, and the rocket is claimed.
13. *(Merged into 14(c), review m4: the telegraph cancel by a real bullet.)*
14. **Line of sight** (real physics 8×, parked Hacker; both harnesses). The wrecks are **real** `wreck_medium.tscn` with physics off (**Deviation D3**:
    §2.11's `fixture_wreck` has no body, and `LineOfSight` casts a bodies-only ray, so it can never block; the `test_sniper.gd` `_wreck()`
    precedent):
    - **(a) Enemy bodies never block, and the no-hit control for the cancel** (`first_pulse_delay` 0.1):
      - **Setup:** a `fixture_enemy.tscn` with a 30 px body `CollisionShape2D` (layer 1), its physics off, parked midway between the hull and the
        player. Two physics frames are awaited before the Hacker is added.
      - **Precondition:** a raw `intersect_ray` on `LineOfSight.BLOCK_MASK` from the hull to the player, with `exclude = [hacker rid]`, returns
        `collider == fixture` (review m3).
      - **Result:** TELEGRAPH starts, and PULSE starts 54 ticks later with no hit.
    - **(b) Rocket cover, in the same run:**
      - **Setup:** two rockets held 400 px from the hull, both off the hull–player line. One has a real wreck 150 px from the hull on the line to it;
        the other's line is clear.
      - **Result:** the clear one is claimed, and the covered one gets no dart. The run ends 10 ticks after the claim, with `darts_fired == 1`.
    - **(c) A wreck between the Hacker and the player, then the cancel** (`first_pulse_delay` 0.1):
      - **No TELEGRAPH** for 1.0 s with the wreck midway.
      - **Then the wreck is freed:** TELEGRAPH follows within 3 physics ticks.
      - **Then a real player `Bullet`** (`bullet.tscn`, 50 damage) is spawned 70 px from the hull, flying at it. Within 2 ticks of the hit:
        - the phase is HOLD_ARC and `telegraph_cancels == 1`;
        - no PULSE comes before the tick it would have come (TELEGRAPH entry + 54) plus 3;
        - `pulse_cooldown >= pulse_period_min - (seconds since the hit) - DT`.
15. **Source death** (hand, frozen Hacker, PULSE entered, three rockets held at hull + (0, 150 / 300 / 600)):
    - The darts claim the 150 and 300 px rockets by tick 20, while the 600 px dart is still flying. Then the test kills the Hacker
      (`health.decrease(9999)`) and awaits 2 process frames. Then:
      - every dart is freed, and the 600 px rocket is never retargeted;
      - each claimed rocket fizzles on its next hand tick: `retarget_ended` once, no `ContactBlast`.
    - **Control:** the same run without the kill claims the 600 px rocket.
16. **Holding fire** (hand): a full TELEGRAPH + PULSE with no rocket in flight gives `pulses_fired == 1`, `darts_fired == 0`, and no live dart.
17. **Warheads** (hand, real ship, frozen Hacker 500 px above it): a real warhead salvo (`RocketState` type 0), launched on PULSE's first tick and
    hand-ticked through PULSE, gets no dart. Each warhead's heading is constant and it moves `speed · DT` per tick. **Control:** a homing salvo from
    the same ship, launched at the same point, is darted.
18. **Primary fire bit-identical** (both real ships, every `UpgradeState.ALL_IDS`, the `test_seeking_ordnance.gd` lockstep shape):
    - Ship B has a Hacker running TELEGRAPH + PULSE (`first_pulse_delay` 0), and a homing salvo from B is claimed at PULSE start.
    - Ship A has no Hacker, and its salvo launches unclaimed.
    - A is taken out of group `player`, so the Hacker reads B.
    - 150 ticks of `WeaponState` with `shoot` held for the first 60 give identical shot logs (tick, damage, rotation) on both ships.
    - `pulses_fired == 1` on B's Hacker, and its darts claimed B's rockets.
19. **Assault: one pulse per life** (hand):
    - **(a) Shipped config, Assault:** `engage_seconds` 9.0, the player 520 px off. `pulses_fired == 1` over the whole life, and DISENGAGE comes on
      the expiry tick.
    - **(b) Boundary config:** `engage_seconds` 30, `first_pulse_delay` 0.5, `pulse_period_min = pulse_period_max = 1.0`, `range_drift` 0.
      - Assault: exactly 1 PULSE in 20 s.
      - Open Space: ≥ 3 (the control: the cap, not the timings, is what stops Assault).
      - Assault with `assault_pulses_per_life` 2: exactly 2.
    - **(c) Budget expiry in PULSE** (`first_pulse_delay` 0.5, so TELEGRAPH runs 0.5–1.4 s and PULSE 1.4–3.0 s): `engage_seconds` 2.0 expires 0.6 s
      into PULSE. The window still runs its full 96 ticks, then DISENGAGE on the end tick. The lock hook is still applied there
      (`pulse_lock_seconds` 1.0, real player).
    - **(d) Budget expiry in TELEGRAPH:** `engage_seconds` 1.0 expires 0.5 s into TELEGRAPH. The TELEGRAPH is cancelled on the expiry tick, then
      DISENGAGE, with no PULSE.
20. **EMP** (hand, **Deviation D2**):
    - `apply_emp(2.0, null)` in TELEGRAPH ends it: `telegraph_cancels` +1, light OFF, dish folded.
    - In PULSE it ends the window with no lock (`pulse_lock_seconds` 1.0 config; the real player is not locked).
    - Each comes back to HOLD_ARC with a fresh cooldown once the window ends.
    - **Control:** with no EMP, the same TELEGRAPH reaches PULSE.
21. **Tell** (hand):
    - **HOLD_ARC:** light OFF, `dish_open() == 0`, `tell_kind() == &""`, `ripple_count() == 0`.
    - **TELEGRAPH:** CHARGING; the dish opens monotonically from 0 to 1; `charge_ring_radius()` goes 60 → 40 monotonically.
    - **PULSE:** COMMIT, the dish at 1.0, `tell_kind() == &"pulse"`, and `ripple_count()` is 1 / 2 / 4 at t = 0.0 / 0.41 / 1.21 s.
    - **After:** everything back to rest.
22. **Fairness** (both real player scenes; **Deviation D4**, see §7).
    - **Geometry** (fixed; review B3):
      - Player P: Open Space (0, 0), Assault (640, 560).
      - Three homing rockets start at P + (−7, −450), P + (0, −450) and P + (7, −450), flying +y and locked on a static `Node2D` at P + (0, 400).
        They fly toward the player.
      - Hacker: frozen (hand) or parked (real) at P + (300, −450), in PULSE from tick 0. Hand rows enter it with `enter_phase`; the real row uses a
        `pulse_telegraph` 0.05 test config and `first_pulse_delay` 0, and launches the rockets on the PULSE-entry tick.
      - Pre-run in both harnesses; the claim ticks and closest approaches are recorded in `DECISIONS.md`.
      - **Precondition:** every claim happens ≥ 0.3 s before the still player's first blast tick.
    - **(a) Hand-ticked, real player moved by the test from tick 0:**
      - Open Space: the ship cruises +x at 420 px/s, then turns 90° to +y after 0.6 s.
      - Assault: the fighter cruises +x at 360 px/s, then turns 90° to −y (up) after 0.6 s.
      - Result: all three rockets are claimed, no `ContactBlast` is ever created, and the closest approach is > `hijack_trigger_radius`.
      - **Control:** the same with the player still: ≥ 1 `ContactBlast`.
      - No fallback dodge shape (review B3). If a turn run is blasted, the geometry changes (the Hacker's or the rockets' start) and the change is
        logged.
    - **(b) Real physics 8×, the still-player control on the real scene with its hurtbox:**
      - The three blasts land within ≤ 3 ticks of each other, so the 0.5 s i-frames refuse the 2nd and 3rd regardless of `Timer` granularity.
      - HP lost equals the pinned value (expected 18 = one blast), ≤ 54.
      - The HurtBox log holds only `hijack_blast_damage` entries, never 100.
      - It stays at 8×, never 16× (review m4).
23. **The arc continues through TELEGRAPH and PULSE** (hand, review B2):
    - **Setup:** both harnesses, cones 0, `range_drift` 0, reversals held (`reversal_min = reversal_max = 30`), `force_orbit_direction(1)`, the
      shipped `first_pulse_delay` 2.0. The Hacker starts straight above the still player at its held range. Assault: the clamp never binds, asserted
      every tick.
    - **Main:**
      - The bearing rate round the player over the whole TELEGRAPH + PULSE (2.0–4.5 s) equals its HOLD_ARC rate over 1.0–2.0 s within
        ±0.02 rad/s.
      - On every tick of the window the nose (`RIGHT.rotated(rotation + sprite_forward_angle)`) is within 5° of the direction to the player.
    - **Control:** the same with `max_speed` 0.001 (parked) fails the rate equality.
    - **Mutation check** (done once in this task and recorded, not shipped): removing `_arc_motion` from TELEGRAPH / PULSE fails both assertions.
    - **Cone leg (Open Space):**
      - **Setup:** t8's snap procedure on the TELEGRAPH entry tick: the 0.18 rad/s far-way case, the player's facing set to the hull's bearing −10°,
        `nose_cone_deg` 30.
      - **Main:** the hull leaves the ±30° cone through the near edge within 2.2 s, before PULSE ends (2.5 s).
      - **Control:** cone 0 means it is still inside at 2.2 s.
    - **Committed leg:** the player is re-placed 400 px from the hull for every tick from TELEGRAPH entry onward.
      - **Main:** no BREAK_OFF during TELEGRAPH or PULSE, then BREAK_OFF on the first HOLD_ARC tick after the PULSE-end tick.
      - **Control:** the same placement from a HOLD_ARC with the cooldown running breaks off on its first tick.

`test_enemy_bullet_lifetime.gd`: `test_the_hijack_pulse_dart_clears_its_lifetime()`.
- Reads the dart scene's `speed` and its lifetime's `max_distance` / `max_time`, and asserts `_round_clears_its_lifetime(...)` (1400 / 900 ≤ 1.6).
- **Boundary:** the same caps at 870 px/s fail (1.609 s).

**Gate time:** measure with `scripts/gate-time.sh` (before: 219.817 s).
- **Real-physics budget per harness:**
  - 14(a)+(b) ≈ 0.1 + 0.9 + 0.5 s;
  - 14(c), cancel included, ≈ 1.0 + 0.1 + 0.95 s;
  - 22(b) ≈ 0.05 + 2.6 s (it ends when all three rockets are gone).

  That is ≈ 6.2 s of game time per harness, ≈ 12.4 s per pair, ≈ 1.6 s wall at 8×.
- **Hand rows:** ≈ 0.6 s. The heaviest is row 18's real-ship pairs; the 20 s cadence and boundary runs are about 6000 brain ticks in all.
- **If over 2.5 s:** share more scenarios. Row 6's late-salvo control can ride on row 16's run, and row 21 on row 23's run. 22(b) never moves to
  16×. A run that would take GUT past 238 s escalates.

## 7. Deviations from §2.11 (each logged in `DECISIONS.md`)

- **D1 — the cap counts darts.** "`claims_this_pulse < max_claims_per_pulse`" is read as darts launched, because a missed dart still used its slot
  (§4, "Alternatives rejected").
- **D2 — EMP ends a TELEGRAPH or a PULSE.** `on_emp_started()` cancels a TELEGRAPH, and ends a PULSE **without** the lock hook. §2.11 only names a
  PULSE end and a budget-expiry end for the lock. t10's Disruptor rows inherit this.
- **D3 — LOS rows use a real wreck.** `fixture_wreck.gd` has no body, so it cannot block a ray. The rows use a real `wreck_medium.tscn` on real
  physics. Handed to t10: §2.12's "behind a `fixture_wreck` at PULSE end is not locked" row must do the same.
- **D4 — the fairness geometry.** §2.11 does not fix it. A salvo fired at the Hacker never reaches a still player (review B1 and §Problem), so the
  fairness row uses rockets in flight toward the player, which makes its still-player control real. The epic's literal reading ("a still player who
  fired at the Hacker takes 0 ≤ 54") is pinned by row 6's measured-limit leg.

## Risks

- **The hijack is toothless against a still or strafing player who fired at the Hacker** (Problem; row 6). This is an owner question in the task
  report (retune t4's `hijack_*` numbers or not). It is not decided here.
- **The cap interpretation** (D1) and **the EMP addition** (D2) are small and logged.
- **Hand-ticked rows yield nothing,** so the pool never recycles in them. Each row stays ≤ 4 darts.
- **t8 movement rows** are protected by `first_pulse_delay` 1000 in their spawn helper. Row 23 now covers movement during the pulse. A later task
  that spawns the Hacker in a long movement row must also switch the pulse off, or expect it.
- **Gate time** is tight (≈ 2.2 s estimated for a 2.5 s allotment); see the gate-time note above.

## Out of scope

- The Disruptor scene and config, and its rows (t10).
- Art: the dish sprite and hull (t12).
- Hub and level placement (t13 / t14).
- Audio (EventBus seams only; `player_ordnance_hijacked` already fires per claim, from t4).
- Enemy bodies blocking LOS (§6, Ph19).

## Response to review round 1

| Finding | Change |
|---|---|
| **B1:** the hijack can't hurt a still or strafing player who fired at the Hacker; the plan buried it | **Problem:** a measured-threat paragraph replaces the wrong "toward or across" wording. **Row 6:** gains the measured-limit leg (still player: all claimed, no blast) and a following-player control that is blasted. **Row 22:** labelled Deviation D4 (§7). **Docs (§6):** state the measured threat. **Task report:** asks the owner explicitly. |
| **B2:** nothing pinned movement during TELEGRAPH / PULSE | **New row 23:** the bearing rate and the nose through the window, with a parked control and a once-off mutation check; an Open Space cone leg with a cone-0 control; a committed leg (no BREAK_OFF until the PULSE ends, then on the next HOLD_ARC tick). **§5:** notes the t8 rows no longer cover it. |
| **B3:** fairness geometry not fixed; the fallback was backwards | **Row 22:** fixed coordinates, pre-run and recorded; precondition claim ≥ 0.3 s before the still player's blast; the strafe-and-reverse fallback is dropped (a blasted turn run changes the geometry and the change is logged). |
| **m1:** unlabelled deviations | **§7:** D3 (a real wreck, handed to t10) and D2 (EMP), labelled at rows 14 and 20. |
| **m2:** exact placement | **Rows 5, 7, 9, 12, 15:** axis-aligned coordinates, rockets held; row 5's Assault x range checked against the rect. |
| **m3:** row 14(a) precondition | **Row 14(a):** `exclude = [hacker rid]` and `collider == fixture`. |
| **m4:** gate time | **Row 13** merged into 14(c), with 14(a) as the no-hit control. **Real-physics runs:** end on their condition; parked with `max_speed` 0.001 for exact geometry. **22(b):** stays at 8×, with a ≤ 3-tick blast-spread assertion. **Estimate:** recomputed. |
| **m5:** `ripple_count()` | **§2:** defined. **Row 21:** expected values 1 / 2 / 4. |
| **m6:** player resolver | **§1 and §2:** `players[0]`, the `TargetInfo.player()` rule; `has_method` guard on the lock. |
| **m7:** stale comments | **§5:** both comments listed for rewording. |
| **m8:** in-flight pre-run | **Row 4:** pre-run and recorded; the start points move if a rocket circles. |
