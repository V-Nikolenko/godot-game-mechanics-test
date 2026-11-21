# EMP really disrupts (Phase 9 t5)

Builds epic plan §2.6 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`). This task plan does not redesign it; it pins the
details §2.6 leaves open and the build / test order.

## Problem
Today an EMP (only the Phase 7 EMP mine emits one) does a stand-in: it fully weakens the player's boost. Nothing else.
Enemies near an EMP are untouched, homing rockets of either side keep their lock, and a placed mine field cannot stun the
enemies that wander into it. After this task:
- The player hit by an EMP cannot boost **and** cannot fire H abilities or K rockets for the window (the ability lock's
  JAMMED tell from t2 shows); it ends exactly on time with no stabilisation delay. Movement and the main gun still work.
- An AI enemy hit by an EMP stops deciding (no shots, no new manoeuvres), stops dead (`mover.halt()`, which also cancels
  a committed dash / charge) and then drifts only with hazards, with a blue-white static ring on it, and can still be shot and killed. A twin-laser pair collapses rather than leaving a frozen beam; a Laser Tender
  charging its launch drops it.
- Seeking rockets (the player's homing rockets, enemy Pursuit rockets) in the burst lose their guidance and fly straight.
- An enemy-laid EMP mine never stuns enemies; a placed one (hub minefield) stuns everyone.

## Design

### 1. `EmpPulse.emit(tree, at, radius, seconds, source, targets: int = TARGET_PLAYER) -> int`
Constants `TARGET_PLAYER = 1`, `TARGET_ENEMIES = 2`, `TARGET_SEEKERS = 4`, `TARGET_ALL = 7`. Early return 0 on null
tree or `seconds <= 0` (unchanged). One distance rule (centre distance `<= radius`) for every set. Order: player, enemies,
seekers.
- PLAYER: the existing loop, byte-for-byte (so the default call is bit-identical).
- ENEMIES: group `enemies`; skip non-`Node2D`, `is_queued_for_deletion()`, no `answers_emp` or no `apply_emp` method,
  `answers_emp()` false; else `apply_emp(seconds, source)`, counted.
- SEEKERS: groups `SeekingOrdnance.GROUP` and new `SeekingOrdnance.ENEMY_GROUP = &"enemy_seeking_ordnance"`; skip
  queued / no `jam_guidance`; `jam_guidance(source)`; **not counted**.

### 2. Player (`PlayerBase.apply_emp`)
Replace the stand-in line with `apply_boost_disruption(1.0, seconds)` then `apply_ability_lock(seconds, source)`. `_emp_left`,
`emp_changed` and `_step_emp` unchanged (so every Ph7 row keeps its exact timing; the ability lock follows its own 1e-6
clock and ends on tick 120 for 2.0 s). Update the doc comment.

### 3. Enemy hook (`BaseEnemy`)
- `const EMP_CLOCK_EPSILON := 1e-6`, `var _emp_left := 0.0`, `var _emp_static: EmpStatic` (lazy).
- `answers_emp() -> bool: return is_ai_driven()`.
- `apply_emp(seconds, source)`: return if `seconds <= 0` or not `answers_emp()`. `starting := _emp_left <= 0`;
  `_emp_left = maxf(_emp_left, seconds)`. On a start only: `_show_emp_static(true)`, then (guarded for a subclass override
  of `answers_emp()` with no brain / mover) `_mover.halt()` first, then `_brain.on_emp_started()` (halt clears requests,
  so this order keeps anything the hook does). Never touches hurtbox, body, health, contact profile.
- `is_emp_disrupted() -> bool: return _emp_left > 0.0`.
- `_physics_process` (review round 1, finding 2: the clock runs **before** the no-brain return, so a brainless subclass
  that overrides `answers_emp()` true still comes out of its window):
  `if _ai_suspended: return` -> `if _emp_left > 0.0: _step_emp(delta)`; if still disrupted after that step,
  `mover.step(delta)` only when both a brain and a mover exist, and return -> `if _brain == null: return` -> the normal
  `brain.tick` + `mover.step`. So for 2.0 s: disrupted after tick 119, not after tick 120; the brain is skipped on ticks
  1..119 and ticks again on 120. A legacy enemy that overrides `_physics_process` never answers EMP (no brain), so it
  never reaches this.
- `_step_emp(delta)`: `_emp_left -= delta; if _emp_left <= EMP_CLOCK_EPSILON: _emp_left = 0; overlay hidden`; else
  `_emp_static.step(delta)`.
- `suspend_ai()`: after its idempotence guard, `_clear_emp()` (`_emp_left = 0`, overlay hidden) in the same call that
  hands the ship to its rail (a suspended ship never answers EMP again, so nothing can restart it).
- Assault budget is frozen for the window (no brain tick), as the epic plan's P1 decided.

### 4. `EmpStatic` (`global/components/emp_static.gd`, `class_name EmpStatic extends Node2D`)
Code-built, no scene/PNG. A closed jagged ring (16 points alternating `radius ± 3` with seeded jitter), colour
`Color(0.7, 0.85, 1.0)`, width 1.5, re-jittered every 0.08 s from a seeded rng; alpha pulses
`0.55 + 0.45 * |sin(t * 21)|` (the player ring's flicker). `radius` set at construction: BaseEnemy passes the body
`CollisionShape2D` circle radius × its scale + 8, fallback 24. Named `EmpStatic` (node name) so tests find it. `z_index`
1. No `rotation` writes in base_enemy.gd (single-writer sweep).

### 5. Brains
- `EnemyBrain.on_emp_started()`: virtual no-op, documented next to `on_suspended()`.
- `TwinLaserDroneBrain.on_emp_started()`: `if pair != null: pair.release(actor)`; light OFF (as `on_suspended`).
- `TwinLaserPair.release(d)`: free the beam when `d == drone_a` and drone A is suspended **or EMP-disrupted**
  (`has_method(&"is_emp_disrupted")`), because the beam is ticked only by A's brain and would otherwise freeze in FADE.
  Release already marks the drone gone and calls `_break_for_good()` (beam `cancel()`, `collapsed(false)`). After the
  window the drone ticks with a broken pair: Assault -> DISENGAGE, Open Space -> SOLO (existing `_decide`).
- `LaserTenderBrain.on_emp_started()`: `if phase == Phase.LAUNCH: enter_phase(Phase.DISENGAGE if _leave_after_launch
  else Phase.HOLD)`. The light leaves CHARGING on that call; after the window a fresh LAUNCH needs a full telegraph.

### 6. `EnemyRocket`
- `var _jammed := false`. `launch()`: after `_apply_exports()`, `if turn_rate > 0.0: add_to_group(SeekingOrdnance.ENEMY_GROUP)`.
- `_mark_done()` and `reset()`: `remove_from_group(...)` (if in it); `reset()` clears `_jammed`.
- `jam_guidance(_source: Node) -> void: _jammed = true`. `is_guiding()` adds `and not _jammed`. Blast, arming, warhead
  trigger and cluster split untouched; heading keeps its last value (`Hazards.bend_heading` still applies).

### 7. EMP mine (`enemy_mine.gd`)
`EmpPulse.emit(..., self, EmpPulse.TARGET_ALL if hostility == Hostility.ALL else EmpPulse.TARGET_PLAYER | EmpPulse.TARGET_SEEKERS)`.
No `EnemyMine` token added to the file (checked by grep before the gate).

Alternatives rejected: counting the EMP clock inside each brain (12 edits, and a railed ship's clock stops — the review's
M9); zeroing velocity directly in BaseEnemy (breaks the single-writer gate); keeping drone A's beam ticking from BaseEnemy
during the EMP (BaseEnemy would need to know about `TwinLaserPair`).

## Build sequence
1. Tests: `tests/unit/test_emp_pulse.gd` additions -> fail; implement `EmpPulse` + `SeekingOrdnance.ENEMY_GROUP` -> green.
2. Tests: player rows (`test_player_ability_lock.gd`, `test_player_boost_disruption.gd`) -> fail; `PlayerBase.apply_emp` -> green.
3. Tests: `tests/integration/test_enemy_emp.gd` enemy rows -> fail; `EnemyBrain.on_emp_started`, `EmpStatic`,
   `BaseEnemy` hook -> green.
4. Twin pair / tender rows + sweep row -> fail; brain overrides + `TwinLaserPair.release` -> green.
5. Seeker rows -> fail; `EnemyRocket` group + `jam_guidance` -> green.
6. Mine rows -> fail; `enemy_mine.gd` targets -> green.
7. Regression: Ph7 EMP rows (`test_enemy_mines.gd`, `test_player_boost_disruption.gd`), `test_enemy_rockets.gd`,
   `test_twin_laser_drones.gd`, `test_laser_tender.gd`, `test_enemy_mover_single_writer.gd`, `test_signal_emit_arity.gd`,
   `test_seeking_ordnance.gd`, `test_base_enemy.gd`, `test_minefield.gd` (its fixture enemies now answer a placed EMP mine); then `scripts/check-test-leaks.sh`, `scripts/gate-time.sh`, `verify.sh`.
8. Docs: `updating-project-docs` (CLAUDE.md, PROJECT.md electronic warfare, global.md, assault.md, the twin / tender
   ENEMY.md), DECISIONS "Phase 9, built in t5", tests/README gate row.

## Test plan
`tests/unit/test_emp_pulse.gd` (existing rows unchanged; the "never touches enemies in phase 7" row keeps asserting the
default set; its comment updated):
- `test_target_enemies_reaches_an_answering_enemy_at_the_radius_and_not_one_pixel_beyond` (boundary 190 / 191).
- `test_target_enemies_skips_a_non_answering_a_methodless_and_a_queued_enemy`.
- `test_seekers_are_jammed_within_the_radius_and_not_counted` (both groups; 191 px not jammed; return 0).
- `test_target_all_reaches_player_enemies_and_seekers`; `test_enemies_only_never_touches_the_player`.

`test_player_ability_lock.gd`:
- `test_an_emp_locks_abilities_for_exactly_120_ticks_with_no_stabilisation` (both modes; locked after 119, unlocked after
  120, fill 1.0 throughout then 0.0, `ability_lock_changed` [true, false], `emp_changed` [true, false] (the latter after 121
  ticks: Ph7 clock), `allow_ability_press()` false at tick 60).

`test_player_boost_disruption.gd`:
- `test_an_emp_is_a_full_boost_disruption_plus_a_timed_ability_lock` (both modes; efficiency 0 and `abilities_locked()`;
  an EMP shorter than a running 3 s timed lock does not shorten it).

`tests/integration/test_enemy_emp.gd` (new, both harnesses where behaviour):
- `test_answers_emp_follows_is_ai_driven` (AI Fighter true; `fixture_enemy.tscn` true (it has a brain and a mover); a
  legacy Gunship false; `ShieldGenerator` false (brain, no mover); a Fighter after `suspend_ai()` false).
- `test_a_brainless_enemy_that_answers_emp_still_comes_out_of_it` (`fixture_enemy.tscn` with its `Brain` freed before it
  enters the tree and a test script overriding `answers_emp()` true: disrupted after 119 ticks, not after 120, overlay
  hidden; the boundary for review finding 2).
- `test_emp_halts_a_committed_boost_on_the_call` (both harnesses; a Fighter whose mover is mid-`boost()` (test staging,
  one tick stepped): on `apply_emp` `is_boosting()` false and `velocity` zero; control: without the EMP it is still
  boosting on the next tick). Fails without `mover.halt()` (review finding 3).
- `test_a_non_answering_enemy_ignores_apply_emp` (Gunship, ShieldGenerator and railed Fighter: `is_emp_disrupted()` false, no
  `EmpStatic` child, health and brain state unchanged).
- `test_an_emp_d_fighter_fires_nothing_coasts_and_resumes` (per harness, spawned inside the Assault view so the corridor
  never pushes it: control run records first shot time T; EMP run
  with 2.0 s at tick 0: zero shots in ticks 1..119, speed < 5 px/s from tick 30 to 119, brain phase constant through the
  window, a shot within T + 2.0 + 1.0 s).
- `test_the_emp_window_is_exactly_120_ticks_and_the_longest_wins` (disrupted after 119 / not after 120; a 1.0 s re-hit at
  0.5 s changes nothing; a 3.0 s re-hit at tick 60 (longest remaining wins) extends it to tick 240; `EmpStatic` visible
  exactly while disrupted; `on_emp_started` called once per start, counted on `fixture_enemy.tscn` through a new
  `emp_started_count` on `tests/helpers/fixture_brain.gd` beside `suspended_count`).
- `test_a_real_player_bullet_kills_an_emp_d_fighter` (real physics 8x, both harnesses; fighter 1 HP; EMP 5 s; a real
  `bullet.tscn` from 110 px; fighter killed (`was_killed`) while `is_emp_disrupted()` was true).
- `test_suspend_ai_mid_emp_clears_the_window` (EMP 2.0 s, 30 ticks, `suspend_ai()`: on that call `is_emp_disrupted()`
  false and the overlay hidden; still so after 180 `_physics_process` ticks).
- `test_a_twin_pair_collapses_when_one_drone_is_emp_d` (both harnesses; drone B EMP'd in FORM: `is_broken()`, phase
  COLLAPSED on that call) and `test_an_emp_d_leader_frees_its_lit_beam` (run to ADVANCE, EMP drone A: the beam is freed / null,
  the pair is broken, and after the 2.0 s window drone A leaves FORM/ADVANCE).
- `test_a_tender_emp_d_in_its_launch_telegraph_drops_it` (both harnesses; `enter_phase(LAUNCH)`, EMP 2.0 s: phase HOLD
  and the light not CHARGING on that call; no launch over the window; `_leave_after_launch` -> DISENGAGE).
- `test_every_beam_brain_of_a_mover_driven_ship_overrides_on_emp_started` (sweep over `assault/scenes/enemies/*/*_brain.gd`
  whose source names `EnemyBeam` or `TwinLaserPair` and whose directory has a `.tscn` containing `enemy_mover.gd`; the
  override is detected by the source regex `^func on_emp_started\(`; boundary: the matcher finds both shipped brains, so an
  empty sweep cannot pass, and a synthetic source without the override is reported).
- `test_seekers_in_radius_lose_guidance_and_a_dumb_rocket_is_unchanged` (both harnesses; a player homing rocket with a
  target and an enemy Pursuit rocket in its guidance window: after `emit(TARGET_SEEKERS)` heading constant over 30 ticks,
  `is_guiding()` false; a DUMB rocket's positions over 30 ticks equal a control's; a guided rocket is in
  `enemy_seeking_ordnance` after launch, out of it once it detonates (`_mark_done()`), and out of it after `reset()`; a
  DUMB rocket never joins).
- `test_an_enemy_laid_emp_mine_never_reaches_enemies_and_a_placed_one_does` (both harnesses; real EMP mine hand-ticked,
  an AI Fighter at 60 px: enemy-laid -> not disrupted; `hostility = ALL` -> disrupted; the player beside it is disrupted in
  both).

## Risks
- A brain's own non-ticked children (e.g. an `AttackController` on `_process` with `driven_by_brain = false`) keep running:
  no brain-driven ship uses one (plan §2.6); accepted.
- `fixture_enemy.tscn` answers EMP (brain + mover): `test_minefield.gd` rows with placed EMP mines near fixtures may
  change; checked in step 7 and any fix recorded.
- Gate time: the real-physics bullet rows await; kept to two short rows at 8x. Allotment 2.0 s.
- `TwinLaserPair.release` change alters only the EMP path (`is_emp_disrupted()` is false everywhere else).

## Out of scope
t6 (`EMPBlastModule` routing through `answers_emp()`), t7 (jammer `answers_emp()` override, `HazardField.suppress`,
`EnemyRocket` flying straight in a lit field), any EMP placement in levels.
