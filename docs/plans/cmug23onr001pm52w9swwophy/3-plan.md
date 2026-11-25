# Enemy rework, phase 9: electronic warfare - Jamming Structure, Hacker Frigate and EMP

Revision 3 (2026-11-07), answering round 2 of the plan review in `4-review.md` (1 blocking, 9 minor findings) and the owner's return of revision 2 (no written comment came
with it, so the round-2 findings are the changes answered; every one is listed in §8, after the round-1 table). Revision 2 (2026-11-06) answered round 1 (2 blocking, 14 minor). Built on this
directory's `1-context.md` (requirements R9.1–R9.25, files, conventions, open questions Q1–Q16) and `2-research.md` (scope check S1–S18, findings
F1–F12, starting values, recommendations). Every research recommendation is adopted unless §1.1 says otherwise. Code facts below were re-read on
`agent/auto-dev` @ `f40de9d`.

## Summary for the owner

- **For the player:** two new enemies attack your tools, not your hull. A **Jamming Structure** projects a visible static field; inside it your special abilities (the H module abilities) and your K rockets are locked, and they come back a moment after you leave. Movement, boost, dash and your main gun are never touched, so you can always shoot the tower or fly out.
- **Three jammers:** a small local one, a large sector one around an objective, and a pulsed one that switches on and off so you can time a crossing. Enemies fight inside the field freely (it is their ground), and inside it every homing rocket, theirs and yours, flies straight.
- **Hacker Frigate:** a fragile specialist that keeps its distance on lopsided arcs, stays out of your nose and off your flight line, and charges up a visible pulse. During the pulse it fires small control darts at your homing rockets, in flight or just launched; a hit rocket flashes amber, turns slowly back toward you and explodes for a small blast. Counters: kill the Hacker (its turned rockets fizzle at once), hold your rockets while it pulses, shoot the turned rocket down with your gun, hit the Hacker while it charges (cancels the pulse), break line of sight behind an asteroid or wreck (other enemy ships do not block it this phase), or lead the rocket into another enemy (it still hits them at full damage).
- **EMP becomes real:** an EMP now locks your abilities as well as your boost for its short window, and makes homing rockets in range lose their lock. Enemies can be hit by EMP too: they stop attacking and drift for a few seconds but can still be shot. A new neutral **EMP zone** in the hub pulses on a cycle and hits everyone inside.
- **Where:** the hub gets a Hacker on patrol, a sector jammer over the defended derelict site, a pulsed jammer and an EMP zone; level 1 gets one Hacker and one small jammer in Planet Approach, apart from each other.
- **Built but not placed:** a "Disruptor" Hacker that also locks your abilities for 1.5 s when its pulse ends (for later encounters and difficulty tiers).
- **Your own EMP Blast** also switches a jammer's field off for its 5 s, so the tower can be shot while it is quiet. Fire it from outside the field: inside, it is jammed like every ability (its reach is the whole scene, so outside always works).
- **Left out:** jammers switching off turret groups (phase 20), sound (a hook is left for phase 17), Hacker squad tactics (phase 14).
- **Main risks:** turned rockets must be dodgeable (they are slower than you and turn slowly, and the numbers are gated by tests, but nothing is play-tested); the player-side changes touch both ships, so every player test is in the blast radius; test-time budget (about 22 s of the 27.6 s left).
- **Choices for you (default in brackets):**
  1. Does the jammer also lock your K rockets, or only H abilities? [Both]
  2. Change your own EMP Blast ability so stunned enemies can still be shot (today they turn untouchable for 5 s)? Same 5 s / 15 s numbers; the three old-style enemies keep today's stun. [Yes]
  3. Should the hub's minefield EMP mines also hit enemies (mines enemies lay never do)? [Yes]
  4. Sound: leave a hook for phase 17 rather than build the game's first audio now? [Hook only]
  5. Place the Disruptor Hacker now, or only in later encounter / difficulty phases? [Later]
  6. Your homing rockets currently die almost at once away from the hub's centre; fix that (needed for hijacks there)? [Fix]
  7. Killing the Hacker defuses every rocket it has turned? [Yes]

## For every task

Phase 9 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line below changes them.
- **Ability lock (player, `global/entities/player_base.gd`):** `signal ability_lock_changed(locked: bool)` (edges only), `signal ability_press_refused()`, `apply_ability_lock(seconds: float,
  source: Node)` (timed; longest wins, nothing stacks, no stabilisation after it), `abilities_locked() -> bool`, `ability_lock_fill() -> float` (1 while held, then the stabilisation
  fraction left, 0 unlocked), `allow_ability_press() -> bool` (false and `ability_press_refused` when locked). Stepped inside `_step_disruption(delta)`, which both ships already call
  first in their physics tick. **Locked:** every H `try_activate()` (both ships' `_input` loops) and the K launch in `RocketState._on_action` (`special_weapon` only). **Never locked:**
  thrust, turn, Shift boost, Boost Drive's Shift path, dash, warp, primary fire (`WeaponState` is not edited), `switch_weapon`, passive modules, effects already running, module
  `tick()` (cooldowns keep counting). A refused press spends nothing (no module cooldown, no `CooldownTimer`, no launch) and is consumed. **Clock rule:** every lock clock
  counts down with `x -= delta` and is over when `x <= 1e-6` (then set to 0.0), so a 1.5 s lock at 1/60 ends on tick 90 exactly, not tick 91 (float drift).
- **Jammer field = a hazard sampled by the body** (the Ph6 rule): `HazardInfo.disables_abilities` (exists, reserved) and new `HazardInfo.stabilise_seconds: float`; `HazardField` gains
  exports `disables_abilities := false` and `stabilise_seconds := 0.0`, written into its info, with `disables_abilities` true **only while ACTIVE**. `Hazards.jammer_at(pos: Vector2) ->
  HazardInfo` returns the containing info with `disables_abilities` and the largest `stabilise_seconds`, else null. Kind `&"jammer"`, `avoid_weight` 0 (enemies ignore it).
- **Seekers inside a lit jammer field fly straight** (both sides): the player's homing missile and an `EnemyRocket` skip guidance while `Hazards.jammer_at(global_position) != null`.
  DUMB rockets and warheads are unaffected. A rocket is never claimed by a Hacker inside a field.
- **Retarget contract (duck-typed, like `is_armored()`):** an eligible player seeking projectile joins group `&"player_seeking_ordnance"` (const `SeekingOrdnance.GROUP`,
  `global/components/seeking_ordnance.gd`) and answers `can_be_retargeted() -> bool`, `retarget(target: Node2D, seconds: float, source: Node) -> bool`, `is_retargeted() -> bool`,
  `jam_guidance(source: Node) -> void`, signals `retargeted(source: Node)` and `retarget_ended()`. Only `homing_missile` implements it; `WarheadMissile` is never eligible.
- **A hijacked homing missile** (exports on `homing_missile.tscn`): turn-limited (`Steering.turn_toward`, `hijack_turn_rate` 1.6 rad/s) toward the player at `hijack_speed` 380,
  for `hijack_seconds` 2.5, then fizzles (no blast). It hurts the player **only by a `ContactBlast`** (layer 256, 18 dmg, r 40), armed after `hijack_arm_seconds` 0.25 and
  once it has been ≥ `hijack_arm_clearance` 60 px from the player; it keeps full damage against enemies; it is shot down by one player bullet (HurtBox layer 512 / mask 64, enabled
  only while hijacked); it fizzles at once if its `source` is freed. No new collision bit. **Its HitBox ignores any area whose parent is a `homing_missile`** (its own shoot-down
  HurtBox and salvo-mates; the `enemy_rocket.gd` `area.get_parent() is EnemyRocket` rule), and `warhead_missile.gd` gets the same guard, so player rockets never hit each other and only primary fire shoots a hijacked one down.
  A `ProjectileLifetime` expiry goes through `_on_expired()`, which ends a live hijack (`retarget_ended`, no blast) before the free. The rocket, not the dart, owns the tether flash.
- **EMP:** `EmpPulse.emit(tree, at, radius, seconds, source, targets := TARGET_PLAYER) -> int`; `TARGET_PLAYER = 1`, `TARGET_ENEMIES = 2`, `TARGET_SEEKERS = 4`. Existing calls stay
  bit-identical. The player effect = `apply_ability_lock(seconds)` + the Ph7 `apply_boost_disruption(1.0, seconds)`. Enemies: duck-typed `BaseEnemy.answers_emp() -> bool`
  (default `is_ai_driven()`), `apply_emp(seconds, source)`, `is_emp_disrupted()`; the enemy always stays tangible; `suspend_ai()` clears a live window. Brain-driven ships stop attacking; a `JammingStructure`
  overrides `answers_emp()` true and its `apply_emp` switches its field off for the window (`HazardField.suppress(seconds)`); other structures and legacy enemies ignore it.
  Both `EmpPulse` `TARGET_ENEMIES` and the player's `EMPBlastModule` route by `answers_emp()`.
- **New names and places:** `assault/scenes/enemies/jamming_structure/` (`JammingStructure`, `JammingStructureConfig`, `JammerFieldArt`), `sector_jammer/` and `pulsed_jammer/`
  (scene + config, same scripts; the `heavy_emplacement/` precedent), `hacker_frigate/` (`HackerFrigate`, `HackerFrigateBrain`, `HackerFrigateConfig`), `hacker_disruptor/` (scene +
  config, same scripts), `assault/scenes/projectiles/hijack_pulse/` (`HijackPulse`, the control dart), `assault/scenes/hazards/emp_zone/` (`EmpZone extends Node2D` with a child `HazardField`, composed
  like the jammer, never a `HazardField` subclass). `WaveBuilder.jammer()`, `hacker_frigate()`. One `*config*.tres` per directory (`test_config_instance_isolation.gd`).
- **Audio is a seam only** (owner choice 4): `EventBus.player_ability_lock_changed(locked: bool)` and `EventBus.player_ordnance_hijacked(rocket: Node2D, source: Node)`. No
  `AudioStreamPlayer` in this phase.
- **Static structures** (all three jammers) follow Ph8: `BaseEnemy`, no mover, no brain, `AssaultDrift` (60 px/s, frees below the projectile world rect), `ContactProfile` NONE, no
  `ContactHitBox`, `is_laser_blocking() == false`, `counts_as_escape = false` in `.tres`, joins `enemies` in its own `_ready()`, export `world_anchored_x := true` for a wave spawn
  (`x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x`, once in `_ready()`).
- **No jammer, Hacker or EMP zone in an `ENEMIES_CLEARED` section** (guard rows in `test_engagement_deadline.gd`); no EMP zone and no placed EMP mine in any Assault level in Ph9.
- **Conventions kept:** brains tick on physics through `BaseEnemy._physics_process`; only `EnemyMover` writes an AI body's velocity / rotation; committed moves are `mover.boost()`;
  randomness only from `brain.rng`; `accepts_tow()` false in TELEGRAPH / PULSE; `TargetInfo` for the player; hull art nose-down (`sprite_forward_angle` `PI/2`); IDEAS §21: a state
  shows on a light or part, never a recoloured hull (amber = hacked, white = pulsing, yellow = charging, never cyan = shield); signals declared with their arity; per-frame prints behind
  `OS.is_stdout_verbose()`; never hand-type a `uid://`, never run `update_project_uids`; art only through the `pixel-art-generation` skill and `./scripts/pixellab.sh`.
  **`enemy_mine.gd` never names its own `class_name` `EnemyMine`** (no `as EnemyMine`, no `is EnemyMine`): the self-reference leaks at exit and fails the gate with every test green.
- **Tests first, GUT.** Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`, `open_space()` / `assault()`, label-parameterised, never
  `use_parameters([HARNESS…])`). Lock and blast rows use **both real player scenes** (`open_space/scenes/entities/player/player_ship.tscn`, `assault/scenes/player/player_fighter.tscn`)
  in the shape of `tests/integration/test_player_boost_disruption.gd` (hand-ticked, fixed delta 1/60). Physics queries (LOS) only on the physics step; such rows run on real physics at
  the 8× clock. Per-tick drivers are a child `_Ticker` node. Run `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget:** GUT was 212.4 s at the Ph8 close. Measure with `scripts/gate-time.sh` before and after each task, report both in the task report and the `tests/README.md`
  → Gate time table. Allotments (new GUT seconds): t1 2.0 · t2 0.5 · t3 0.8 · t4 2.5 · t5 2.0 · t6 0.5 · t7 2.7 · t8 4.0 · t9 2.5 · t10 0.6 · t11 0.8 · t12 0.2 · t13 1.0 · t14 2.5 ·
  t15 0 = 22.6 s, so the phase ends ≤ 235.0 s. An overrun is fixed by sharing a scenario, the 8×/16× clock or a memoised probe, never by cutting an assertion; a task that would take GUT
  past 238 s stops with `Result: ESCALATE`.
- **Task order:** tasks that edit the same files are chained: `player_base.gd` t1 → t2 → t5; `homing_missile.gd` t3 → t4 → t5 (`warhead_missile.gd` only t4); `enemy_rocket.gd` t5 → t7; `base_enemy.gd` /
  `emp_blast_module.gd` t5 → t6 → t7; `hazard_field.gd` t1 → t7; `test_sector_hub_patrol.gd` t11 → t13; the roster gates, `test_base_enemy.gd`,
  `test_enemy_dual_mode.gd` and `wave_builder.gd` t7 → t8 → t9 → t10; `sector_hub.gd` / `.tscn` only t13; `level_1_director.gd` only t14. `DECISIONS.md` and the `tests/README.md` gate table
  are append-only and shared.
- Numbers marked *starting value* (§2.19) are judgement, not play-tested; keep them unless a row forces a change, and log any change in `DECISIONS.md`.
- Every task appends its "Phase 9, built in tN" notes and any deviation to `DECISIONS.md`. Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

## 1. Problem

Every enemy so far attacks the player's hull. Nothing changes **what the player is allowed to use**: the H module abilities and the K rockets
work everywhere, the homing rockets are pure upside, and the EMP the Ph7 mine delivers is a stand-in that only weakens boosting. The idea
(`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.4, §6.6, §11.2, §11.4, §18.6, §21–23, §40) asks for:

- a **Jamming Structure** that suppresses special abilities inside a visible field, with a stabilisation delay after leaving, in local / sector /
  pulsed variants, that enemies fight around and also respect;
- a **Hacker Frigate** (80–120 px) that keeps medium / long range on asymmetric arcs, stays outside the player's easiest attack angle and route, and
  fires the **Hijack Pulse**, a non-damaging control projectile that turns the player's seeking rockets (in flight and newly launched) against the
  player with a clear tell and a short duration;
- the **EMP Pulse** area weapon and §18.6 **EMP zones**, and the Ph7 EMP mine, disrupting systems through the same hooks where they fit;
- the player-side **ability lock** and **seeking-rocket retarget** hooks, built and pinned before any enemy uses them;
- their own top-down art, placement in Assault waves and the hub, and tests in both harnesses covering lock / unlock timing, in-flight hijack and
  retargeting, and that primary fire is never affected.

### 1.1 Scope check (re-validated against the code @ `c1ba45e`)

`2-research.md` §1 (S1–S18) is adopted. Plan-stage additions and the answers it left open:

| # | Finding / decision | Effect |
|---|---|---|
| S1 | No lock exists; the three press seams are `OpenSpacePlayerShip._input`, `PlayerFighter._input` (both loop `_module_pool` and call `try_activate()`) and `RocketState._on_action` (`special_weapon` branch, `cooldown_timer.is_stopped()`). | t1 builds the lock on `PlayerBase` and one `allow_ability_press()` check per seam (§2.1). |
| S3 | `homing_missile.gd` frees itself outside a hard-coded Assault box (`_ARENA_*`), so in the Open Space hub it dies on its first tick almost everywhere. | t3 replaces the box with `ProjectileLifetime` (§2.4); owner choice 6. |
| S5 | `EMPBlastModule` disables enemy processing, which removes their bodies and hurtboxes from physics for 5 s. | t5 builds a tangible enemy EMP hook; t6 re-routes the module (owner choice 2). |
| P1 | **Research said the Assault `EngagementBudget` keeps running under an enemy EMP.** Brains own their budgets privately (12 brains each call `_budget.update(delta)` inside `tick()`), so keeping it running needs an edit in every brain. | **Changed:** an EMP'd enemy's brain is not ticked, so its budget is frozen for the EMP window (≤ 5 s, the EMP Blast's). Today's EMP Blast already freezes enemies entirely, so nothing gets worse, and no Ph9 EMP source that reaches enemies is placed in any Assault level (guard row). Recorded in DECISIONS. |
| P2 | `HazardField` already owns the TELEGRAPH → ACTIVE → QUIET cycle, registration in `_enter_tree()`, unregistration in `_exit_tree()`, and per-phase info fields. | The jammer's field **is** a child `HazardField` (kind `&"jammer"`) with two new exports, not a new hazard class (§2.8). Its death frees the child, which unregisters: the next player tick finds no field. |
| P3 | `ContactBlast.spawn(container, at, radius, damage, frames)` is how `EnemyRocket` hurts the player (`_detonate()` uses `get_parent()`). | The hijacked rocket uses the same call with its own parent (`RocketState`, a plain `Node`, so the blast's position is global). No new layer. |
| P4 | One `*config*.tres` per enemy directory is enforced by `test_config_instance_isolation.gd`. | Jammer variants and the Disruptor each get a directory (the `heavy_emplacement/` precedent: scene + config, shared scripts). |
| P5 | Level-1 density: deep_space is at 12 of 12.5 in the frozen 2.5× specialist gate from 3.5 s to the end (the Ph8 turret group lives 28.1 s); planet_approach peaks at 7 of 7.5 at 28.4–32.0 s and 98.0 s; asteroid_belt has no frozen constant. | Both level-1 placements go in **planet_approach**, off its peaks, measured (§2.17). |
| P6 | `TurretGroup.add_power_provider()` is the Ph20 seam. | Not used. The hub sector jammer is placed **beside** the Ph8 defense site (placement, not linkage). |
| P7 | `MissionHud` (`global/ui/mission_hud.gd`) is shared by both HUDs and already polls in `_process`. | The JAMMED chip and the lock glyph live there, reading the player duck-typed (§2.3). |

## 2. Design

### 2.1 The ability lock on `PlayerBase` (R9.1, R9.3, R9.6; Q1–Q4)

All in `global/entities/player_base.gd`, beside the Ph7 boost disruption, using the same discipline: accumulated `delta`, hand-steppable,
signal on change only, and an **unlocked path that is a cheap early return** so every existing player test stays bit-identical.

**API**
- `signal ability_lock_changed(locked: bool)`: fires once on each edge (locked → unlocked, unlocked → locked). Never on a refresh.
- `signal ability_press_refused()`: a press arrived while locked (HUD / ship tell flash, §2.3).
- `apply_ability_lock(seconds: float, source: Node) -> void`: a timed lock (EMP, Disruptor). `seconds <= 0` is a no-op. `_timed_left = maxf(_timed_left, seconds)`: the longest wins,
  two never add. A timed lock ends with **no stabilisation delay**.
- `abilities_locked() -> bool`: `_in_field or _stabilise_left > 0.0 or _timed_left > 0.0`.
- `ability_lock_fill() -> float`: 1.0 while in a field or a timed lock runs; while only stabilising, `_stabilise_left / _stabilise_total`; 0.0 unlocked.
- `allow_ability_press() -> bool`: `true` when not locked; otherwise emits `ability_press_refused` and returns `false`.
- `_step_ability_lock(delta)`: called at the top of `_step_disruption(delta)` (both ships already call `_step_disruption` first in their physics tick: `player_fighter.gd`,
  `player_ship.gd`). Early return when `Hazards.count() == 0 and not abilities_locked()`.

**Field sampling, per tick.** `var info := Hazards.jammer_at(global_position)`.
- `info != null` → `_in_field = true`, `_stabilise_left = 0.0`, remember `_field_stabilise = info.stabilise_seconds`.
- `info == null` and `_in_field` was true (the **exit tick**) → `_in_field = false`, `_stabilise_left = _stabilise_total = _field_stabilise`. No decrement on the exit tick.
- otherwise, `_stabilise_left = _tick_clock(_stabilise_left, delta)`.
- `_timed_left = _tick_clock(_timed_left, delta)`.
- **Clock rule** (`_tick_clock(x, delta)`): `x -= delta; return 0.0 if x <= 1e-6 else x` (the `EnemyRocket` `- 1e-6` idiom). Summing `1.0 / 60.0` in doubles leaves 3.3e-16 after 90
  steps from 1.5 and 2.1e-15 after 120 steps from 2.0; without the epsilon a 1.5 s lock would end on tick 91 and a 2.0 s one on tick 121. With it, a lock of `s` seconds at 1/60
  ends on tick `round(s · 60)` exactly, so the 1.5 s / 2.0 s rows can assert exact ticks.
- After the update, compare `abilities_locked()` with the previous value and emit `ability_lock_changed` (and `EventBus.player_ability_lock_changed`, added by t2) on a change.

So with `stabilise_seconds` 0.75 at 60 Hz: the first tick sampled inside is locked; the exit tick T starts the delay; ticks T+1 … T+44 are still locked; T+45 (0.75 s after T) is
unlocked. Re-entering during the delay sets `_stabilise_left = 0` and `_in_field = true` (locked), and the full delay restarts on the next exit. A pulsed field's TELEGRAPH and QUIET
phases report `disables_abilities = false`, so they count as "outside": the delay applies when a pulsed field switches off. A destroyed jammer unregisters; the next tick is an exit
tick. Overlapping fields: `jammer_at` returns the largest `stabilise_seconds` of the fields containing the point, so leaving the inner of two fields does not start a delay at all
(still inside the outer one). A timed lock and a field never shorten each other.

**`Hazards.jammer_at(pos: Vector2) -> HazardInfo`** (`global/hazards/hazards.gd`): loops the registry like `around()` (no allocation), returns the containing info with
`disables_abilities == true` and the largest `stabilise_seconds`, or null. Uses `info.contains(pos)` (centre distance `<= radius`, the existing rule).

**`HazardInfo.stabilise_seconds: float = 0.0`** (new field). **`HazardField`** gains `@export var disables_abilities := false` and `@export var stabilise_seconds := 0.0`;
`_refresh_info()` writes `_info.disables_abilities = disables_abilities and active` and `_info.stabilise_seconds = stabilise_seconds`. Defaults keep every Ph6–Ph8 field
bit-identical.

**The three seams (the only places the lock is checked):**
- `OpenSpacePlayerShip._input` (`open_space/scenes/entities/player/player_ship.gd`): after `if not event.is_action_pressed("use_ability"): return` and before the module loop:
  `if not allow_ability_press(): get_viewport().set_input_as_handled(); return`.
- `PlayerFighter._input` (`assault/scenes/player/player_fighter.gd`): the same, after the `DialogPlayer.is_active` return.
- `RocketState._on_action` (`assault/scenes/player/states/warhead_missile_shooting_state.gd`): the `special_weapon` branch checks `actor.allow_ability_press()` (duck-typed:
  `actor.has_method(&"allow_ability_press")`, so a test actor without it is never locked) **before** `_launch()` and `cooldown_timer.start()`. Order: `cooldown_timer.is_stopped()`
  first (a press during cooldown is not a refusal and gives no feedback), then the lock. `switch_weapon` is never checked.

**Locked although it moves the ship:** the Assault Boost Drive, because Assault fires it from H like any other module (the Open Space ship skips it on H and fires it from Shift,
which is not locked).

**Not locked, by decision:** thrust, turn, Shift boost and the Open Space Boost Drive on Shift (`_step_boost`), dash and warp (`dash_state.gd`), primary fire (`WeaponState`, not edited), passive modules (Pierce, Overclock, Shooting, Armor Plating, Warp flag), effects already running
(a Shield Overload window finishes), module `tick()` (cooldowns keep counting while locked, so a lock never costs time afterwards; finding F11).

**Ship tell and HUD:** t2 (§2.3). t1 only emits the signals.

### 2.2 Ability-lock test rows (t1: `tests/integration/test_player_ability_lock.gd`, `tests/unit/test_hazards.gd` additions)

Both real player scenes, hand-ticked at 1/60 like `test_player_boost_disruption.gd`. The field is a plain `HazardField` node (`kind = &"jammer"`, `radius` 240, `avoid_weight` 0,
`disables_abilities = true`, `stabilise_seconds` 0.75, optionally `cycle_*` for the pulsed rows) added to the test tree; no jammer enemy is needed.

| Row | Asserts |
|---|---|
| `jammer_at` (unit) | null with no hazard; null for a non-jammer field; the info at `radius` exactly, null 1 px beyond; the larger `stabilise_seconds` of two overlapping fields; null while a pulsed field is in TELEGRAPH / QUIET. Every existing `test_hazards.gd` row unchanged (defaults). |
| Lock on entry | locked on the first tick the ship's centre is inside; `ability_lock_changed(true)` exactly once. |
| Unlock timing | after the exit tick T: locked at T+44, unlocked at T+45 (0.75 s); `ability_lock_changed(false)` exactly once; fill goes 1 → 0 monotonically. |
| Re-entry resets | exit, re-enter at T+20, exit again at T2: unlocked exactly at T2+45. |
| Pulsed | ACTIVE locks; TELEGRAPH never locks; the ACTIVE → QUIET edge starts the delay. |
| Death | freeing the field node while the ship is inside: the next tick is an exit tick; unlocked 0.75 s later. |
| Timed | `apply_ability_lock(1.5, src)`: locked after ticks 1 … 89, unlocked after tick 90 (the 1e-6 clock rule of §2.1), no stabilisation; a shorter second call does not shorten; a field + a timed lock: unlocked only when both are over. Boundary: `_tick_clock(1.5)` stepped 90 times returns exactly 0.0 (fails without the epsilon). |
| H refused, nothing spent | for **every** module id in `ShipModuleState.SLOT_MODULES` that overrides `try_activate`, equipped on each ship: an H press while locked leaves its cooldown / state unchanged (module-specific readable: e.g. `EMPBlastModule._cooldown_left == 0`), emits `ability_press_refused`, marks the event handled; the same press one tick after the unlock activates it. Boundary: a press on T+44 is refused, on T+45 accepted. |
| K refused, nothing spent | in both ships, both rocket types: a K press while locked starts no `CooldownTimer` and adds no rocket child; a K press during the cooldown (unlocked) gives no `ability_press_refused`; `switch_weapon` while locked still switches. |
| Cooldowns keep ticking | a module with 10 s cooldown left, locked for 3 s: 7 s left at the unlock. |
| Primary fire never affected | in both ships, for all five weapon modes (`WeaponModeResource`s used by `WeaponState`): shots fired, cadence and damage over 120 ticks inside a lit field equal the same 120 ticks with no field (bit-identical counts and damage). |
| Movement never affected | thrust / turn / Shift boost (Open Space), move / dash / warp (Assault): position and velocity after 60 ticks inside a lit field equal the run without the field. |
| No hazard = bit-identical | `Hazards` is a `RefCounted` of `static func`s, which GUT cannot spy, so assert the observable: with `Hazards.count() == 0`, over 120 ticks of both ships, `abilities_locked()` stays false, `ability_lock_fill()` stays 0.0, neither lock signal is emitted, and every H / K press goes through; plus the existing bit-identity rows (primary fire, movement) above. |

### 2.3 Lock tells: ship overlay, HUD chip, glyph and the audio seam (R9.5, R9.6, Q14, Q16; t2)

- **Ship overlay** (`PlayerBase`, code-built like `BoostDisruptionRing`): `AbilityLockStatic`, a `Node2D` child that draws 6 short jagged arcs (2 px, amber-white
  `Color(1.0, 0.85, 0.55)`) around the hull at r 30, re-jittered every 0.08 s from a seeded rng, alpha 0.9 while held and `0.3 + 0.6 · fill` while stabilising. Created on the first
  lock, `visible` follows `abilities_locked()` exactly (shown on the lock tick, hidden on the unlock tick). A refused press flashes it to full alpha for 0.15 s.
- **HUD** (`global/ui/mission_hud.gd`, shared by `assault/scenes/gui/hud.tscn` and `open_space/scenes/gui/hud.tscn`): a `JammedChip` (`Label` "JAMMED" + a thin bar whose width is
  `ability_lock_fill()`) next to the special-weapon `WeaponContainer`, and a `LockGlyph` (a code-drawn padlock, 12×12) over `WeaponIcon`. Both read the first node in group `player`
  in `_process`, duck-typed (`has_method(&"abilities_locked")`); hidden when there is no player. A refusal (`ability_press_refused`, connected when the player is found) flashes
  the chip red for 0.2 s (finding F1). Nothing lingers after the unlock (finding F3).
- **Audio seam:** `global/systems/event_bus.gd` gains `signal player_ability_lock_changed(locked: bool)` and `signal player_ordnance_hijacked(rocket: Node2D, source: Node)`.
  `PlayerBase` emits the first on each edge. The second is declared here and emitted by t4's `retarget()`. Phase 17 connects audio to them.

Rows (`tests/integration/test_player_ability_lock_tells.gd`, both real ship scenes, and one HUD scene instance per mode): the overlay and the chip are visible on the lock tick and hidden
on the unlock tick; the chip's bar width tracks `ability_lock_fill()` within 1 px; a refused press flashes the chip; `EventBus.player_ability_lock_changed` fires once per edge with
the right value; with no player the HUD shows nothing and errors nothing.

### 2.4 Homing missile lifetime (S3, Q9; t3)

`assault/scenes/projectiles/missiles/homing/homing_missile.gd` / `.tscn`:
- Delete the `_ARENA_*` constants and the box check. Add `signal expired` and a `ProjectileLifetime` child (`max_time` 6.0, `max_distance` 2400, `use_world_rect` true) and wire
  `expired → _on_expired()` in `_ready()`; in t3 `_on_expired()` is just `queue_free()` (one handler, so t4 can end a live hijack in it before the free). In Assault the rect is `EnemyWorld.projectile_world_rect()` (the same box the constants hard-coded, so Assault behaviour is unchanged apart
  from the new time and distance caps); in Open Space the rect rule is a no-op.
- Nothing else changes in t3: speed 500, straight-at-target steering, damage 100, HitBox layer 32 / mask 513, frees on a non-deflected hit.

Rows (`tests/integration/test_homing_missile_lifetime.gd`, plus one row in `test_player_bullet_lifetime.gd`):
- Open Space harness: a rocket launched at (20000, 15000) with a target 600 px away lives and reaches it (it died on its first tick before).
- Assault harness: a rocket leaving the projectile world rect emits `expired` once and is freed. **Only the rect rule can trip in Assault:** a rocket with no target crosses the
  1608 × 1608 rect in ≤ 4.55 s at 500 px/s, so it never reaches 6.0 s, and no point of the rect is 2400 px from another (2274 px diagonal).
- **6.0 s row (both harnesses):** a rocket locked on a **hurtbox-less static `Node2D`** 300 px away (inside the rect in Assault) reaches it and keeps re-crossing it (direct pursuit
  overshoots by one 8.3 px step and turns back), so it stays near the target, inside the rect and far from 2400 px; it emits `expired` once at `max_time` 6.0 (±1 tick) and is freed.
  This "hover on a hurtbox-less target" setup is the shared way to keep a rocket alive for a long time (t4's lifetime row reuses it).
- **2400 px row (Open Space only):** a rocket with no target flies straight; it emits `expired` once when its displacement first reaches 2400 px, at 4.8 s (±1 tick).
- Ownership row in `test_player_bullet_lifetime.gd`: every player rocket scene (`homing_missile.tscn`, `warhead_missile.tscn`) frees itself on its own (`expired → queue_free` or
  `screen_exited`), i.e. exactly one owner.
- Regression: `test_armor_query.gd`, `test_hazard_projectiles.gd`, the Ram plate rows and `test_enemy_rockets.gd` (player and enemy rockets destroy each other) stay green unchanged.

### 2.5 The seeking-ordnance retarget hook and the hijacked rocket (R9.2, R9.13–R9.17; Q6–Q8; t4)

**`global/components/seeking_ordnance.gd`** (`class_name SeekingOrdnance extends RefCounted`): `const GROUP := &"player_seeking_ordnance"`;
`static func eligible(tree: SceneTree, at: Vector2, reach: float) -> Array[Node2D]` returns every group member within `reach` of `at` (centre distance `<=`) whose
`can_be_retargeted()` is true, sorted by distance (ties by instance id, deterministic).

**Contract on `homing_missile`** (joins `SeekingOrdnance.GROUP` in `_ready()`):
- `can_be_retargeted() -> bool`: false once retargeted, fizzling or done, or while `Hazards.jammer_at(global_position) != null`.
- `retarget(target: Node2D, seconds: float, source: Node) -> bool`: refused (false) when `can_be_retargeted()` is false or `target` is null. Otherwise enters HIJACKED: `_hijack_left =
  seconds`, or the rocket's own `hijack_seconds` export when `seconds < 0` (the Hacker's dart passes -1.0, so the window is the rocket's tuning), `_hijack_target = target`, `_hijack_source = source`, `_since_claim = 0`, heading kept, emits `retargeted(source)` and
  `EventBus.player_ordnance_hijacked(self, source)`, shows the tell, enables the shoot-down HurtBox. Returns true.
- `is_retargeted() -> bool`; `signal retargeted(source: Node)`; `signal retarget_ended()` (on fizzle, blast, shoot-down or source death).
- `jam_guidance(_source: Node) -> void`: drops `locked_target` (the missile flies forward); on a hijacked rocket it also ends the hijack's guidance (it keeps flying straight and still
  fizzles at the end of its window). Used by EMP (§2.6).

**Hijacked flight** (exports on `homing_missile.tscn`, the Ph5 rule that weapon tuning lives in the projectile scene):
`hijack_speed` 380, `hijack_turn_rate` 1.6 rad/s, `hijack_seconds` 2.5, `hijack_blast_damage` 18, `hijack_blast_radius` 40, `hijack_blast_frames` 3, `hijack_trigger_radius` 30,
`hijack_arm_seconds` 0.25, `hijack_arm_clearance` 60.
- Each tick: if `_hijack_source` is not a valid instance → fizzle at once. Speed eases from 500 to `hijack_speed` over the first 0.5 s. Heading =
  `Steering.turn_toward(heading, target_pos - global_position, hijack_turn_rate, delta)`, unless `Hazards.jammer_at(global_position)` is set (fly straight) or guidance was jammed.
  `Hazards.bend_heading` still applies (rockets bend in wells). `rotation = heading.angle() + PI / 2` (the existing sprite convention).
- Arming: `_since_claim >= hijack_arm_seconds` **and** the rocket has been at least `hijack_arm_clearance` from the target's centre on some tick since the claim.
- Armed and within `hijack_trigger_radius` of the target's centre → `ContactBlast.spawn(get_parent(), global_position, hijack_blast_radius, hijack_blast_damage, hijack_blast_frames)`,
  then `_finish(true)`.
- `_hijack_left` reaching 0 (the `<= 1e-6` clock rule) → fizzle: `_finish(false)` (no blast).
- **One end of life, `_finish(blasted: bool)`:** latches `_done` first (so it runs once), pops, emits `retarget_ended` if the rocket was hijacked, closes every area deferred
  (`monitoring` / `monitorable` off and shapes disabled, the `EnemyRocket._mark_done()` pattern), hides, and `queue_free()`s two physics ticks later (the `EnemyRocket`
  `_end_after_overlaps()` pattern, so nothing re-reports an overlap). Every end goes through it: blast, fizzle, shoot-down, a hit on an enemy, source death, and **the
  `ProjectileLifetime` backstop** — t3's `_on_expired()` becomes `if not _done: _finish(false)`, so a rocket that has flown 4 s and is then hijacked still emits `retarget_ended`
  when its 6 s `max_time` ends the hijack early (the `EnemyRocket._on_expired` precedent). An unhijacked rocket's ends keep today's observable behaviour (it is freed; t3's rows stay green).
- **Collisions (the self-hit guard).** Its HitBox keeps layer 32 / mask 513 (1 `environment` + 512 `enemy_hurtbox`) and `damage` 100. Because mask 513 includes 512, the rocket's
  own shoot-down HurtBox (512) and every salvo-mate's would be reported the moment they turn monitorable (a salvo flies 7 px apart, `RocketState._launch_homing` spread 7.0). So
  `_on_hit_box_area_entered(area)` starts with `if _done or area.get_parent() is homing_missile: return` (the `enemy_rocket.gd` `if area.get_parent() is EnemyRocket: return`
  rule), before the `ArmorQuery` check. **The warhead gets the same guard:** `warhead_missile.tscn`'s HitBox is also layer 32 / mask 513 and `warhead_missile.gd::_on_hit_box_area_entered`
  frees it on any non-deflected hit, so a warhead crossing a hijacked rocket's HurtBox would die on it; it starts with the same `if area.get_parent() is homing_missile: return`.
  **Decision: a player rocket never hits another player rocket**, hijacked or not, homing or warhead; only primary fire (layer 64) shoots a hijacked one down.
  A hijacked rocket that crosses an enemy hurts it at full damage and ends (the lure, R9.17). An `EnemyRocket` (HitBox mask 640 = 128 + 512) that meets a hijacked rocket's
  HurtBox detonates as it does on any enemy hurtbox; harmless (both end) and accepted.
- **Shoot-down:** a `HurtBox` child (layer 512 `enemy_hurtbox`, mask 64 `player_hitbox`, a 7 px circle) with `monitoring` / `monitorable` false until hijacked; one
  `received_damage` → `_finish(false)`. A player bullet that hits it is consumed (a damaging hit).
- **Tell** (IDEAS §21: change a light, not the hull): the sprite's `self_modulate` warms to amber `Color(1.0, 0.7, 0.3)`, the `RocketTrail` turns amber, and a code-drawn target bracket
  (four 4 px corner ticks at r 12, rotating 3 rad/s) is drawn on the rocket while hijacked. **The tether flash is the rocket's too:** for `tether_seconds` 0.3 after a successful
  `retarget()`, the rocket draws a line from `source.global_position` (if still valid) to itself, white → amber, fading (code-drawn in its own `_draw`, so it lives and dies with
  the rocket; the claiming dart is recycled by its pool on the claim tick and cannot own it).
- Normal (unhijacked) flight is unchanged, except: inside a lit jammer field a rocket with a `locked_target` flies forward (`_fly_forward`) instead of steering (seekers jammed).

Rows (`tests/integration/test_seeking_ordnance.gd`, both harnesses, a fixture claimer node standing in for the Hacker; blast rows on both real player scenes):

| Row | Asserts |
|---|---|
| Group / eligibility | a homing rocket is in the group, a warhead is not; `eligible()` sorts by distance and drops a hijacked one and one inside a lit field; `retarget()` refused in each of those cases and with a null target. |
| In-flight turn | a rocket flying away from the player, claimed: its heading never turns more than `hijack_turn_rate · delta` + 1e-4 rad per tick, and it ends pointing at the player within 2.5 s. |
| Speed | 500 → 380 over 0.5 s, then constant. |
| Blast only | a claimed rocket reaching the real player: the player loses exactly 18 HP (no shield) once, from a `ContactBlast`, never 100; with a shield charge the charge is spent instead (existing rule). |
| Arming | claimed at 20 px from the player: no blast during the first 0.25 s and none until it has been 60 px away; claimed at launch (the rocket on the ship) it never blasts in its first 0.25 s. |
| Fizzle | unclaimed by any blast, it emits `retarget_ended` and `expired` once at 2.5 s (±1 tick) with no `ContactBlast` created. |
| Source death | freeing the claimer: the rocket fizzles on the next tick, no blast. |
| Lure | a hijacked rocket crossing a fixture enemy (`fixture_enemy.tscn` + 14 px hurtbox, in `enemies`) deals 100 to it and ends; the player takes nothing. |
| Shoot-down | one real player `Bullet` hitting a hijacked rocket ends it (no blast) and the bullet is consumed; an unhijacked rocket's HurtBox is inert (a bullet passes). |
| Self-hit guard (real physics, 8×) | a real 3-rocket salvo (`RocketState`, spread 7 px) with the middle rocket claimed: all three rockets are still alive 2, 10 and 30 physics ticks after the claim, and the claimed one's HurtBox is monitorable; a second unhijacked player rocket flown straight through a hijacked one leaves both alive. These rows fail on a build without the `area.get_parent() is homing_missile` guard (the claimed rocket frees itself on the claim tick). |
| Warhead guard (real physics, 8×) | a real player warhead (`warhead_missile.tscn`, launched by `RocketState`) flown straight through a hijacked homing rocket: both are still alive 10 physics ticks after the crossing, and the hijacked rocket's HurtBox stayed monitorable. Fails without the warhead's guard (the warhead frees itself on the HurtBox). |
| Lifetime ends a hijack | a rocket kept alive for 5.0 s by hovering on a **hurtbox-less static `Node2D`** (the t3 setup; a straight rocket would hit 2400 px at 4.8 s in Open Space and leave the Assault rect by 4.55 s), the player ≥ 700 px away, then claimed: `ProjectileLifetime`'s 6.0 s `max_time` ends it 1.0 s later (±1 tick; at 380 px/s it covers < 500 px, so it neither blasts nor leaves the rect) with `retarget_ended` emitted once, no `ContactBlast`, and it is freed; an unhijacked rocket hovering to 6.0 s emits no `retarget_ended`. |
| Tether | for 0.3 s after `retarget()` the rocket draws its tether (a `queue_redraw` flag readable as `is_tether_visible()`), then not; freeing the claimer during the 0.3 s hides the tether on the next tick (and the rocket fizzles, the Source death row); no error is logged for the freed source. |
| Jammed | inside a lit jammer field a hijacked rocket flies straight (heading constant over 30 ticks); an unhijacked rocket with a target also flies straight; outside, both steer. |
| Dodge (fairness, Ph5 dodge-row shape) | Open Space: the ship cruising at 420 px/s perpendicular to a rocket claimed 400 px away, then a 90° turn after 0.6 s, is never blasted. Assault: the fighter at 360 px/s strafing across a claim made 500 px above it, reversing once, is never blasted. Control: a stationary ship is blasted. |
| Primary fire during a hijack | in both ships, `WeaponState` shots and damage over 120 ticks with a hijacked rocket in flight equal the run without it. |
| EventBus | `player_ordnance_hijacked` fires once per successful claim with the rocket and the source. |

### 2.6 EMP: the real player effect, `EmpPulse` targets, the enemy hook and seekers (R9.19–R9.21; Q10; t5)

**Player effect** (`PlayerBase.apply_emp(seconds, source)`, signature unchanged): replace the Ph7 stand-in line with
`apply_boost_disruption(1.0, seconds)` **and** `apply_ability_lock(seconds, source)`. `is_emp_disrupted()` / `emp_changed(active: bool)` keep their meaning. Every Ph7 EMP row
(`test_enemy_mines.gd`, `test_player_boost_disruption.gd`) stays green as written.

**`EmpPulse.emit(tree, at, radius, seconds, source, targets: int = TARGET_PLAYER) -> int`** (`global/components/emp_pulse.gd`), constants `TARGET_PLAYER = 1`, `TARGET_ENEMIES = 2`,
`TARGET_SEEKERS = 4`, `TARGET_ALL = 7`. Same centre-distance `<= radius` rule for every target set; returns the number of ships reached (player + enemies; seekers are not counted).
- `TARGET_PLAYER`: today's loop over group `player`.
- `TARGET_ENEMIES`: group `enemies`, nodes whose duck-typed `answers_emp()` is true (`has_method(&"answers_emp")` first), skipping `is_queued_for_deletion()`.
- `TARGET_SEEKERS`: group `SeekingOrdnance.GROUP` (player homing rockets) and group `&"enemy_seeking_ordnance"` (an `EnemyRocket` joins it in `launch()` when `turn_rate > 0`
  and leaves it in `_mark_done()` / `reset()`): `jam_guidance(source)` on each. An `EnemyRocket.jam_guidance()` ends its guidance window at once (`is_guiding()` false from the next
  tick; it flies straight and keeps its blast).

**Enemy hook** (`assault/scenes/enemies/base_enemy.gd`): `answers_emp() -> bool`, `apply_emp(seconds: float, source: Node) -> void` and `is_emp_disrupted() -> bool`.
- `answers_emp()` is the one routing question every EMP source asks (`EmpPulse` `TARGET_ENEMIES` here, the player's `EMPBlastModule` in t6). Default: `return is_ai_driven()`
  (a brain and a mover that is not suspended). A subclass that has its own tangible EMP answer overrides it: `JammingStructure` returns true and its `apply_emp` switches its
  field off for the window (built by t7, `HazardField.suppress(seconds)`). Everything else (other structures with no mover, legacy enemies that override `_physics_process`, a
  railed enemy) answers false.
- `BaseEnemy.apply_emp` returns at once when `answers_emp()` is false. Longest wins. The window uses the `<= 1e-6` clock rule (`x -= delta`, over at `x <= 1e-6`).
- On the start: `_brain.on_emp_started()` (new virtual on `EnemyBrain`, default no-op), `mover.halt()`, and a code-built `EmpStatic` overlay on the enemy (blue-white jagged ring,
  the same shape as the player's, `Color(0.7, 0.85, 1.0)`).
- While `_emp_left > 0`: `BaseEnemy._physics_process` **skips `_brain.tick(delta)`** and still calls `_mover.step(delta)` (hazard pull, drift and the corridor constraint keep
  working; nothing requests a new velocity, so the ship coasts to a stop). The hurtbox, body and health are untouched: **the enemy can be shot**. `AttackController`s with
  `driven_by_brain` do not fire (no brain tick); a legacy timer-driven controller is not used by any brain-driven ship.
- On the end: overlay hidden, the brain ticks again from the state it was in.
- **A rail ends it:** `BaseEnemy._physics_process` returns at once while `_ai_suspended`, so an EMP clock there would stop for good. `suspend_ai()` therefore clears a live window
  (`_emp_left = 0.0`, overlay hidden, `is_emp_disrupted()` false) in the same call that hands the ship to its rail; a railed ship answers `answers_emp()` false afterwards anyway.
- **Assault budget:** frozen for the EMP window (P1 in §1.1). Bounded by the 5 s EMP Blast; no Ph9 EMP zone or placed EMP mine goes into any Assault level.
- `TwinLaserDroneBrain.on_emp_started()` breaks its pair (`TwinLaserPair` collapse, the same call a drone death makes), so no lit beam is frozen in place; `LaserTenderBrain.on_emp_started()` cancels a
  launch telegraph in progress (a pair already launched is two drones with their own EMP handling). A sweep row asserts every brain script of a mover-driven ship that references
  `EnemyBeam` or `TwinLaserPair` overrides `on_emp_started()` (structures have no mover and ignore EMP).

**Callers:** the EMP mine (`enemy_mine.gd`, the `EmpPulse.emit` in its EMP branch; **never write `EnemyMine` inside `enemy_mine.gd`** — no `as EnemyMine` / `is EnemyMine`,
the CLAUDE.md trap: the self-reference leaks at exit and fails `verify.sh` with every test green; compare `hostility` against the enum through the unqualified `Hostility.PLAYER`) passes `TARGET_PLAYER | TARGET_SEEKERS` when `hostility == Hostility.PLAYER` (enemy-laid) and
`TARGET_ALL` when `Hostility.ALL` (placed, owner choice 3). The hub `Minefield` (EMP weight 0.15) therefore starts stunning enemies near it.

Rows (`tests/unit/test_emp_pulse.gd`, `tests/integration/test_enemy_emp.gd` both harnesses, `test_player_boost_disruption.gd` / `test_player_ability_lock.gd` additions):
- `test_emp_pulse.gd`: every existing row unchanged (the default set never touches `enemies`); `TARGET_ENEMIES` reaches a fixture enemy at the radius and not 1 px beyond and skips
  one whose `answers_emp()` is false; seekers are jammed but not counted.
- Player: an EMP of 2.0 s locks abilities for exactly 120 ticks (locked after tick 119, unlocked after tick 120: the `<= 1e-6` clock rule) with no stabilisation, refuses boosts (Ph7 rows), and `emp_changed` fires once each way.
- Enemy: an EMP'd Fighter (both harnesses) fires nothing for the window and resumes after it; it coasts to under 5 px/s; **a real player bullet kills an EMP'd enemy** (its hurtbox
  stays in physics; the counter-row to the EMP Blast bug); a structure (`ShieldGenerator`) and a railed enemy are unaffected; the twin pair collapses when one drone is EMP'd.
  **Railed mid-EMP:** a Fighter EMP'd for 2.0 s, then `suspend_ai()` at 0.5 s: on that call `is_emp_disrupted()` is false and the `EmpStatic` overlay is hidden, and both stay so for
  the next 180 ticks (fails on a build that only counts the clock down in the brain branch).
- Seekers: a player homing rocket and an enemy Pursuit rocket in radius lose guidance (heading constant afterwards); a DUMB rocket is unchanged.
- Mines: an enemy-laid EMP mine never reaches a fixture enemy beside the player; a placed (`ALL`) one does.

### 2.7 The player's EMP Blast re-routed (S5, Q11, owner choice 2; t6)

`global/ship_modules/emp_blast_module.gd`: `try_activate()` keeps its 15 s cooldown, its visual, its "every enemy in the scene" reach (no radius, unchanged) and its immune list. For
each non-immune enemy: if it answers the duck-typed `answers_emp()` true (`BaseEnemy`: default `is_ai_driven()`; `JammingStructure` overrides it true), call
`apply_emp(5.0, player)` (tangible, §2.6); otherwise (the legacy Gunship, Bonus Drone, Space Station and every brainless structure other than a jammer) keep today's
`PROCESS_MODE_DISABLED` + `create_timer` path unchanged. **Why the jammer must not take the old path:** a process-disabled jammer leaves the physics space (body and HurtBox
drop out) while its child `HazardField` stays registered with its last `disables_abilities` value, so for 5 s it could not be shot but would still lock the player. Through
`apply_emp` its field goes quiet instead and it stays shootable (built by t7; the jammer row of this module's test lives in t7). Its description stays truthful (no wording change).

Rows (`tests/integration/test_emp_blast_module.gd`): a brain-driven enemy hit by the module is EMP'd for 5 s and a real bullet still damages it; a legacy enemy is still
process-disabled for 5 s (characterisation of the unchanged branch); `RamCorvette` is still skipped (`test_ram_corvette.gd::test_emp_still_skips_the_corvette` unchanged); the
cooldown is still 15 s; a fixture enemy answering `answers_emp()` true without a brain (a stub overriding it) goes through `apply_emp`, not the process-disable path (the
routing the jammer relies on).

### 2.8 The Jamming Structure (R9.4–R9.6, R9.9, R9.10; t7)

**Scenes and scripts** (`assault/scenes/enemies/`):
- `jamming_structure/`: `jamming_structure.gd` (`class_name JammingStructure extends BaseEnemy`), `jamming_structure_config.gd` (`class_name JammingStructureConfig extends ShipConfig`,
  flat), `jamming_structure_config.tres` (local), `jamming_structure.tscn`, `jammer_field_art.gd` (`class_name JammerFieldArt extends Node2D`), `ENEMY.md`.
- `sector_jammer/`: `sector_jammer.tscn` (inherits or copies `jamming_structure.tscn`, same scripts) + `sector_jammer_config.tres`.
- `pulsed_jammer/`: `pulsed_jammer.tscn` + `pulsed_jammer_config.tres`.

**Structure:** root `JammingStructure` (CharacterBody2D, layer 1 like other enemy roots), `Health`, `HurtBox` covering the body (`test_enemy_hurtbox_geometry.gd`), `Sprite2D`
(placeholder `Polygon2D` until t12), `HitFlashAnimationPlayer`, a `StateLight` (`global/components/state_light.gd`) on the emitter, child **`Field`: a `HazardField`** with
`kind = &"jammer"`, `avoid_weight = 0.0`, `pull_force = 0`, `movement_penalty = 0`, `disables_abilities = true`, and `radius`, `stabilise_seconds`, `cycle_telegraph`,
`cycle_active`, `cycle_quiet` written from the config in `_ready()` (before the field's first refresh matters; the field registers in `_enter_tree()` with scene values, so the scene
values equal the config values and a row pins that they match). `JammerFieldArt` (child of `Field`) draws the field. No mover, no brain, no `ContactHitBox`, `ContactProfile` NONE.
- `is_laser_blocking() -> bool: return false`. Joins `enemies` in its own `_ready()`. `counts_as_escape = false` in each `.tres`.
- Death: `BaseEnemy` frees the root, the `Field` child unregisters in `_exit_tree()`; the player's next tick is an exit tick (stabilisation starts).
- **EMP answer ("EMP disrupts systems", R9.19):** `answers_emp()` returns true; `apply_emp(seconds, source)` calls `Field.suppress(seconds)` (longest wins) and shows the
  blue-white `EmpStatic` overlay built by t5; `is_emp_disrupted()` is true for the window. The jammer keeps processing and stays in physics (shootable), the pulsed cycle keeps
  running underneath. **`HazardField.suppress(seconds: float)`** (new, `global/hazards/hazard_field.gd`, default never suppressed): `_suppressed_left` counts down in
  `_physics_process` with the `<= 1e-6` clock rule, and `_refresh_info()` writes `disables_abilities = disables_abilities and active and _suppressed_left <= 0.0` (refreshed on the
  suppress call itself too, so the player's next tick already sees it). A suppressed field reads as "outside": the player's stabilisation delay starts. `JammerFieldArt` draws
  the QUIET look while suppressed. So the player's EMP Blast (5 s), the hub EMP zone and a placed EMP mine all switch a jammer off without making it untouchable.
- **The EMP Blast works on a jammer only from outside its field (R9.9, stated rule).** EMP Blast is an H ability, so a press inside a lit field is refused by the ability lock like
  every other H press. Its reach is scene-wide (no radius), so a player standing anywhere outside the field can switch it off; the counterplay is "step out, Blast, step back in".
- **Assault:** an `AssaultDrift` child (60 px/s, frees below the projectile world rect), export `world_anchored_x := true` applied once in `_ready()` when the jammer is a wave spawn
  (`x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x`; no effect without a view rect). The `Field` moves with the root.
- `WaveBuilder.JAMMER` / `SECTOR_JAMMER` / `PULSED_JAMMER` path constants and `WaveBuilder.jammer(variant := &"local")`.

**Config fields** (`JammingStructureConfig`): `field_radius`, `stabilise_seconds`, `cycle_telegraph`, `cycle_active`, `cycle_quiet` (all 0 = always on) plus the `ShipConfig` base.

| Variant | `max_health` | `field_radius` | cycle T / A / Q | `stabilise_seconds` | `score_value` | Art size | Modes |
|---|---|---|---|---|---|---|---|
| local (`jamming_structure`) | 140 | 240 | always on | 0.75 | 60 | 64×64 | both |
| sector (`sector_jammer`) | 260 | 640 | always on | 1.25 | 120 | 96×96 | Open Space only (never in an Assault wave: a guard row) |
| pulsed (`pulsed_jammer`) | 160 | 300 | 0.8 / 3.0 / 2.5 | 0.75 | 80 | 64×64 | both |

`collision_damage` 0 in all three (contact NONE).

**Field visual (`JammerFieldArt`, R9.5):** a code-drawn ring at `radius` made of 48 short dashed arcs (3 px wide, amber-white `Color(1.0, 0.85, 0.55)`, alpha 0.35) that crawl
(rotate 0.4 rad/s) plus a faint fill (alpha 0.05). TELEGRAPH: the ring flickers (alpha toggles every 0.1 s between 0.1 and 0.35). QUIET: only a 1 px outline at alpha 0.08. The
`StateLight` is lit while ACTIVE, blinks in TELEGRAPH, dark in QUIET. Never cyan (shield) or violet (boost disruption).

Rows (`tests/integration/test_jamming_structure.gd`, both harnesses, plus the real player scenes for the lock rows):
- Each variant: the registered info has `kind &"jammer"`, `avoid_weight` 0, the config's radius and stabilisation; the config and scene values match; pulsed phases follow 0.8 / 3.0
  / 2.5 s; `disables_abilities` only in ACTIVE.
- A real player ship inside the local jammer is locked; after killing the jammer with real bullets from inside the field the lock ends 0.75 s later (counterplay "destroy it"); primary
  fire still kills it (R9.9).
- Assault: it drifts at 60 px/s, frees below the world rect, and its world x is `640 + 2 · design_x` whatever the camera pan.
- Avoidance: a Fighter's path through a jammer field equals its path with no jammer (avoid weight 0; `Steering.context_avoid` skips it).
- EMP, three rows (in `tests/integration/test_emp_blast_module.gd`, t6's file, and `test_jamming_structure.gd`):
  - **From outside, through the real seam:** a real ship 120 px outside the local jammer's field (unlocked) presses H with `EMPBlastModule` equipped (the real `_input` path): the
    jammer's info reports `disables_abilities` false on the next tick, a real bullet still damages the jammer during the 5 s, and the field locks again after 5.0 s (±1 tick).
  - **Inside, refused:** the same ship inside the lit field presses H: `ability_press_refused` fires, the module's cooldown is untouched and the field stays lit.
  - **Unlock after suppression (direct call):** a real ship inside the field, the test calls `EMPBlastModule.try_activate(player)` **directly** (bypassing the seam, which would refuse
    it; documented in the test): the field goes quiet on the next tick and the player unlocks 0.75 s later (the stabilisation delay of a field that switched off).
  - A pulsed jammer suppressed in ACTIVE stays quiet; its cycle phase after the window equals an unsuppressed twin's (the clock kept running).
- It joins every roster gate (§2.15).

### 2.9 Enemies and the jammer: seekers jammed both ways, the corvette and the Hacker respect it (R9.7, R9.8, Q13; t7)

- **Fight around it:** the field has `avoid_weight` 0, so every enemy ship moves through it as if it were empty space (it is their ground). Placement puts shooters around jammers (§2.16,
  §2.17). Squad tactics that pin the player inside a field are Ph14.
- **Seekers jammed:** inside a lit field, `EnemyRocket._steer()` is skipped (the rocket keeps its heading; `is_guiding()` stays as-is so the Ph5 flight clock is unchanged), and the
  player's homing missile flies forward (§2.5). Implemented in `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd` behind `if Hazards.count() > 0`, so every Ph5 rocket row with no
  jammer is bit-identical.
- **Missile Corvette respects it:** `MissileCorvetteBrain` (`assault/scenes/enemies/missile_corvette/missile_corvette_brain.gd`) downgrades a chosen PURSUIT or CLUSTER salvo to DUMB
  when `Hazards.jammer_at(player position)` is set. The change sits in the kind roll after `choose_kind()` (whose signature and rows stay unchanged); `force_next_kind()` still wins.
- **The Hacker respects it:** a rocket inside a field is not eligible (`can_be_retargeted()`), so a Hacker never claims there (t9 row).
- **Not affected:** enemy shields, wards, shield generators, turrets, beams, mines (it is the faction's own jammer).

Rows (in `test_jamming_structure.gd` and `test_missile_corvette.gd`): an enemy Pursuit rocket entering a lit field keeps a constant heading inside it and steers again after leaving;
a DUMB rocket is unchanged; with the player inside a field the corvette's next PURSUIT / CLUSTER roll becomes DUMB, outside it is unchanged (control); a pulsed field in QUIET jams
nothing.

### 2.10 The Hacker Frigate: shell and movement (R9.11, R9.12, R9.18, Q15; t8)

**Scene** `assault/scenes/enemies/hacker_frigate/`: `hacker_frigate.gd` (`class_name HackerFrigate extends BaseEnemy`), `hacker_frigate_brain.gd`
(`class_name HackerFrigateBrain extends EnemyBrain`), `hacker_frigate_config.gd` (`class_name HackerFrigateConfig extends ShipConfig`, flat `@export_group`s),
`hacker_frigate_config.tres`, `hacker_frigate.tscn`, `ENEMY.md`. The Ph1 stack: `EnemyMover`, `Brain`, `Health`, `HurtBox` (covers the body), `ContactHitBox` sharing the body shape
(`test_contact_hitbox_geometry.gd`), `ContactProfile` COLLISION, a `StateLight` on the dish, a `Dish` node (the antenna part that unfolds in TELEGRAPH, IDEAS §23), a `Sprite2D`
(placeholder `Polygon2D` 96×96-ish until t12), body circle r 40. Joins `enemies` in `_ready()`. `WaveBuilder.HACKER_FRIGATE` and `WaveBuilder.hacker_frigate()`.

**Brain** `enum Phase { HOLD_ARC, TELEGRAPH, PULSE, BREAK_OFF, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only). t8 builds every phase but TELEGRAPH / PULSE, which t9 fills
(t8 leaves `_want_pulse()` returning false and the two phases as stubs that go straight back to HOLD_ARC).
- **HOLD_ARC** (composed from `MissileCorvetteBrain`'s HOLD_ARC; copy the pattern, do not inherit): orbit the player at `held_range()` = `preferred_range` (Open Space) or
  `assault_preferred_range` (Assault) ± `range_drift`, `Steering.orbit` with the **asymmetric** angular speed `orbit_speed_cw` 0.18 / `orbit_speed_ccw` 0.30 rad/s by the current
  direction, direction reversals at random `reversal_min..max` 3–6 s from `brain.rng`.
- **Bearing penalty (stay out of the easiest attack angle and off the route, §18.6).** Two cones around the player, measured from `TargetInfo`: the **nose cone** ± `nose_cone_deg`
  30 around `TargetInfo.facing`, and the **route cone** ± `route_cone_deg` 25 around `TargetInfo.velocity`, live only while the player moves faster than `route_min_speed` 80 px/s.
  While the Hacker's current bearing from the player lies inside a cone (nose cone checked first), HOLD_ARC (a) **forces the orbit direction toward the nearer edge** of that cone
  (exactly on the centre line: keep the current direction), (b) advances the orbit angle at `cone_escape_speed` 0.30 rad/s in either direction, and (c) holds the reversal clock
  (no random reversal while inside). Outside both cones the asymmetric 0.18 / 0.30 arcs and the 3–6 s reversals apply unchanged, so the identity is kept. The angle is the
  orbit **target** angle (`_orbit_angle`, the `MissileCorvetteBrain` pattern: `_orbit_angle += dir · speed · delta`, then `Steering.orbit(pos, player, radius, _orbit_angle,
  max_speed)`); the body follows it at up to `max_speed`, its velocity changing by at most `acceleration · delta` per tick (`EnemyMover.step`: `current.move_toward(desired,
  acceleration · delta)`; `braking` is not used). The brain reads `nose_cone_deg` / `route_cone_deg` / `cone_escape_speed` from `config` every tick (never cached in `_ready()`), so
  a test can switch a cone on after a warm-up.
- **Why `acceleration` is 700 px/s², not 260 (round-2 review B1).** The escape usually starts with the Hacker orbiting the *wrong* way, toward the far edge (the case the penalty
  exists for). At 0.30 rad/s and 720 px that is 216 px/s of tangential speed; at 260 px/s² the Hacker needs 0.83 s just to stop, drifts ~7° further into the cone and leaves it only
  after ≈ 2.7 s, later than if it had simply kept going (≈ 2.6 s). At 700 px/s² (the Ph5 Support Ship's value, `support_ship_config.tres`: the other fragile specialist that avoids
  confrontation) the stop takes 0.31 s and "nearer edge" is always the faster exit. A simulation of the exact mover rule (1/60 ticks, the `Steering.orbit` anchor correction
  `clamp(4 · dist, 60, 230)`, `range_drift` 0, the Hacker at bearing +10° inside a ± 30° cone) gives these exit times; the rows' bounds are set from them with ≈ 0.5 s margin:

  | Case (orbit before the cone appears) | 720 px, cone on | 720 px, cone off (control) | 520 px (Assault), cone on | Route row (± 25°, player 100 px/s), cone on / off |
  |---|---|---|---|---|
  | 0.18 rad/s toward the near edge | 1.40 s (near) | 2.18 s (near) | 1.40 s | 1.07 / 1.62 s |
  | 0.18 rad/s toward the far edge | 1.48 s (near); 0.20 s moving the far way | 4.12 s (far) | 1.40 s | 1.15 / 3.55 s |
  | 0.30 rad/s toward the far edge | 1.70 s (near); 0.32 s moving the far way | 2.57 s (far) | 1.42 s | 1.33 / 2.23 s |

  At 260 px/s² the two far-way rows read 2.15 s and 2.72 s, which is why the revision-2 bound of 1.76 s could never pass. **What this can and cannot do:** a player who keeps turning
  (150–220°/s) can always hold the Hacker in their nose; the Hacker does not out-turn a tracking player, it **slides out of a nose that stopped**, the short way, within about 1.7 s.
  A player faster than 230 px/s simply outruns it, which also leaves it off the route. The rows below test exactly that. If the measured exits in GUT differ from the table, the
  builder keeps the bounds (2.2 / 1.9 / 1.8 s) as long as every control still fails them, and records the measured values in `DECISIONS.md`; a bound that cannot be met with
  a failing control is a `Result: ESCALATE`, not a retune.
- **BREAK_OFF (a committed move).** Entered from HOLD_ARC when the player is inside `min_range` 420 and `break_rearm_seconds` 1.0 have passed since the last BREAK_OFF ended. **Open
  Space:** `mover.boost(dir, break_speed 360, break_burst_seconds 0.8)` with `dir = Steering.break_contact(pos, player_pos, player_vel, side, 1.0, break_lateral_weight 0.25).normalized()`
  (`side` from `brain.rng` on entry), re-issued each time the burst ends while still inside `min_range + 120` 540. `mover.boost()` ignores `max_speed` (230), so 360 px/s is real.
  `break_contact` doubles the lateral share against a closing threat (0.25 → 0.5), so the radial part is 360 / √1.25 ≈ 322 px/s: above a 300 px/s rusher (the gap opens at
  ≈ 22 px/s), below the player's 420 px/s cruise and 700 px/s boost, so a determined player still catches it. (The default lateral weight 0.6, doubled to 1.2, would leave only
  ≈ 218 px/s radial, and a 300 px/s rusher would close: that is why the Hacker sets its own.) **Assault:** no boost (the view clamp is a target clamp the boost
  would bypass): the request is `break_contact` at `max_speed` with the target point clamped into view (below). BREAK_OFF ends beyond 540 px **or** after `break_max_seconds` 3.0
  (a cornered or out-run Hacker goes back to HOLD_ARC rather than flee forever), then the 1.0 s rearm. No pulse while breaking.
- **Nose:** faces the player (`mover.face_toward`), `sprite_forward_angle` `PI/2`.
- **Assault:** the Ph5 Support Ship view clamp (`support_ship_brain.gd` `_clamp_into_view(p)`: the target point is clamped into `EnemyWorld.view_rect().grow(-view_margin)`,
  `view_margin` 60); an `EngagementBudget(engage_seconds 9.0)`; at expiry DISENGAGE (release the constraint, `exit_speed` 300, seek outside the projectile world rect, free). The exit
  is measured over `corridor_starts()` with `tests/helpers/specialist_exit_probe.gd` (memoised, built through a new `tests/helpers/ph9_exit_keys.gd`, static `prepare`, the Ph8
  `ph8_exit_keys.gd` rule).
- **Hub idle:** `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) around `patrol_anchor` (`idle_radius` 160, `idle_speed` 0.45, asymmetric like its combat arc), NOTICING on
  `perceive_radius` 760 for `notice_time` 0.35, RETURNING beyond `lose_radius` 1600. `start_engaged` export skips IDLE (tests, waves).
- **Test seam:** `force_orbit_direction(dir: int)` (±1) sets the orbit direction once (the penalty still overrides it inside a cone unless the cone is 0°). One sign is the cw
  arc (0.18 rad/s) and the other the ccw arc (0.30 rad/s), so a test picks the 0.18 or the 0.30 rad/s case by the direction it forces.
- `accepts_tow()` false in TELEGRAPH and PULSE. Add the brain to `test_base_enemy.gd`'s tow table.

**Config (starting values):** `max_health` 120, `collision_damage` 15, `score_value` 90, `max_speed` 230, `acceleration` **700** (the Support Ship's; see "Why `acceleration` is 700"), `max_turn_rate` 1.4, `preferred_range` 720,
`assault_preferred_range` 520, `range_drift` 90, `min_range` 420, `break_speed` 360, `break_lateral_weight` 0.25, `break_burst_seconds` 0.8, `break_max_seconds` 3.0, `break_rearm_seconds` 1.0,
`orbit_speed_cw` 0.18, `orbit_speed_ccw` 0.30, `cone_escape_speed` 0.30, `reversal_min` 3.0, `reversal_max` 6.0, `nose_cone_deg` 30, `route_cone_deg` 25, `route_min_speed` 80,
`view_margin` 60, `engage_seconds` 9.0, `exit_speed` 300, idle / perception fields above, hazard fields as the corvette (`hazard_avoidance` 0.7, `hazard_margin` 80,
`hazard_resistance` 0.4), `wreck_chance` 0.4, `wreck_size` 1. **The pulse fields (`pulse_trigger_range`, `hijack_range`, `pulse_*`, …) are not added here; t9 adds them** with TELEGRAPH / PULSE.

Rows (`tests/integration/test_hacker_frigate.gd`, both harnesses unless noted; hand-ticked at 1/60, the test writes config fields on the instance before `add_child()`). Every
behaviour row has a control that turns the behaviour off and must fail the same bound:
- **Holds range:** over 20 s against a still player, distance stays in `held_range() ± (range_drift + 60)`.
- **Asymmetric arcs:** with both cones set to 0°, measured angular speed of the target angle differs by direction (0.18 vs 0.30 rad/s ± 0.01); at least one reversal in 10 s
  over 4 seeds.
- **Cone-row procedure (shared by the nose and route rows).** `range_drift` 0 on the instance. **Warm-up:** both cones written to 0°, reversals held off
  (`reversal_min = reversal_max = 30`), `force_orbit_direction(d)`, 2.0 s of ticks with the cone axis pointing away from the Hacker, so it is in a steady orbit in direction `d`.
  **Snap:** set the cone axis (the player's facing for the nose row, its velocity direction for the route row) to the Hacker's current bearing ± 10°, the sign chosen so that its
  current motion is toward the **far** edge (or the near edge for the near-way case); in the main row write the cone back to its size (30° / 25°), in the control leave it at 0°.
  The **test** measures the bearing against the full ± 30° / ± 25° cone every tick by itself, independent of the config. Each case is a fresh instance. No 0.25 s monotonic check:
  the Hacker legitimately moves the far way while it stops.
- **Slides out of the nose (Open Space at 720 px; Assault at `assault_preferred_range` 520 px):** a still player (route cone off). Cases: 0.18 rad/s toward the far edge, 0.30
  rad/s toward the far edge, 0.18 rad/s toward the near edge. **Main (cone 30°):** in every case the Hacker leaves the cone **through the near edge** (sign of the exit bearing)
  within **2.2 s** of the snap at 720 px and **1.9 s** at 520 px, and the total time after the snap during which its tangential velocity points toward the far edge is ≤ **0.5 s**
  (the stop: 216 / 700 = 0.31 s). The same instance, re-snapped 3.5 s after its first exit (now moving the near way), exits again within the same bound. **Control (cone 0°, same
  warm-up and snap):** in both far-way cases the Hacker is **still inside** the ± 30° cone at the bound (simulated far-edge exits 4.12 s and 2.57 s). At the revision-2
  acceleration 260 the 0.30 rad/s far-way case fails both bounds (simulated 2.72 s at 720 px, 2.02 s at 520 px), so the 700 is pinned by it. **Assault placement:** the player
  sits centred 100 px above the view's bottom edge and the Hacker starts straight above it at 520 px; the 2.0 s warm-up moves it ≤ 0.6 rad, so at the snap it is within 35° of
  straight up and every position it reaches in the row (≤ 75° from straight up at 520 px) is inside `view_rect().grow(-60)`: the view clamp never binds (asserted each tick).
- **Off the route (Open Space, 720 px):** a player moving at 100 px/s, facing 90° away from the Hacker's side (so the nose cone never contains it), `nose_cone_deg` 0 in this row.
  Same cases and procedure with the route cone 25°: exits through the near edge within **1.8 s** (simulated worst 1.33 s), far-way time ≤ 0.5 s. **Control (route cone 0°):** still
  inside ± 25° at 1.8 s in both far-way cases (simulated 3.55 s / 2.23 s). Plus: a player cruising at 360 px/s outruns it (distance grows past `held_range() + range_drift`), the
  documented limit, asserted so a later speed change is visible.
- **Break-off (Open Space):** a player rushing straight at the Hacker at 300 px/s from 600 px for 4.0 s, then stopping: BREAK_OFF starts on the first tick inside 420 px, the
  distance never falls below **360 px**, and HOLD_ARC resumes within `(540 − d_min) / 322 + 1.0 s` of the stop. **Control:** `min_range` 0 (BREAK_OFF never fires): the distance
  falls below 340 px (a 230 px/s orbit cannot open on a 300 px/s rusher: ≥ 70 px/s closing over 4 s). **Chase:** a player chasing at 420 px/s: BREAK_OFF ends at 3.0 s (±1 tick),
  the next BREAK_OFF starts no sooner than 1.0 s later (no flip-flop).
- **Break-off (Assault):** a player moving inside 420 px: BREAK_OFF starts; the hull stays inside `view_rect().grow(-60)` throughout; it ends by 3.0 s.
- **Assault life:** the hull stays inside `view_rect().grow(-60)` for its whole budget; DISENGAGE at 9.0 s; it leaves the world rect within the measured exit.
- **Hub idle (Open Space):** idles inside `idle_radius` + 40 of its anchor until the player is inside 760 px, then NOTICING → HOLD_ARC.
- Roster gates (§2.15).

### 2.11 The Hijack Pulse (R9.13–R9.17; Q6; t9)

**Delivery: a PULSE window on the Hacker plus one visible control dart per claim.**

**Hacker phases** (`HackerFrigateBrain`): from HOLD_ARC, when the pulse cooldown has run out (`pulse_period_min..max` 6–8 s, from `brain.rng`) **and** `can_see_player()` **and** the
player is within `pulse_trigger_range` 870 of the Hacker **and** not in BREAK_OFF → TELEGRAPH for `pulse_telegraph` 0.9 s (yellow `StateLight`, the `Dish` unfolds, a slow inward-moving ring of 6 dashes
around the hull at r 60 → 40). **Damage during TELEGRAPH cancels the pulse** (connect `health.amount_changed`; any decrease) → HOLD_ARC with a fresh cooldown. Then PULSE for
`pulse_seconds` 1.6 (white light, an outward ripple ring from the dish every 0.4 s, code-drawn). In PULSE, every tick: for each rocket in
`SeekingOrdnance.eligible(tree, hacker position, hijack_range)` not already targeted by a live dart, with `LineOfSight.clear` from the hacker to the rocket (physics step only), while
`claims_this_pulse < max_claims_per_pulse` 3: fire a dart at it. Rockets launched during the window are picked up the same way on the next tick ("newly launched"); rockets already in
flight when PULSE starts are picked up on its first tick ("in flight"). After PULSE → HOLD_ARC with a new cooldown. The Hacker keeps moving (HOLD_ARC steering) in TELEGRAPH and PULSE.
**Two ranges, two jobs (round-2 review M1):** `pulse_trigger_range` 870 gates the *player* for TELEGRAPH and for the Disruptor lock; it is `preferred_range` 720 + `range_drift` 90
+ 60, so the whole Open Space held band (630–810 px) and the Assault one (430–610 px) are inside it and the pulse cadence is set by the cooldown, not by where the range drift
happens to be. `hijack_range` 650 is only the *rocket-claim* reach around the Hacker (`SeekingOrdnance.eligible(tree, hacker position, hijack_range)`): a rocket the player fires at
the Hacker from its held range enters it within a fraction of a second. (Revision 2 used 650 for the player gate too; the 720 ± 90 band is inside 650 only ≈ 22 % of the time.)
Assault: at most `assault_pulses_per_life` **1** pulse per life (one attack per life, the Ph4 / Ph8 Assault rule). The cap is set to 1 because it is the only value that can bind:
the earliest second TELEGRAPH is `first_pulse_delay` 2.0 + 0.9 + 1.6 + the 6.0 s minimum cooldown = 10.5 s, past `engage_seconds` 9.0. A budget expiring in TELEGRAPH cancels it,
in PULSE lets the window finish (≤ 1.6 s), then DISENGAGE.

**Line of sight is the Ph6 rule** (`EnemyBrain.can_see_player()` through `TargetInfo.line_of_sight`, and `LineOfSight.clear` for the rocket): only asteroids and wrecks block it.
**Enemy ship bodies never block it** ("a fighter body … never blocks", `enemy_brain.gd`), so IDEAS §6.4's "force the hacker behind other enemies" does not work in Ph9; it is
listed in §6 Out of scope.

**The dart** (`assault/scenes/projectiles/hijack_pulse/hijack_pulse.gd`, `class_name HijackPulse extends Node2D`, `hijack_pulse.tscn`; weapon tuning in its exports): non-damaging,
**no collision areas** (it claims by distance, so no layer is needed). `signal expired`, `reset()`, `launch(rocket: Node2D, source: Node)`. Flies at `speed` 900 px/s homing
exactly at its rocket (no turn limit: it must be reliable); when within `claim_radius` 16 of the rocket → `rocket.retarget(player, -1.0, source)` (a negative value makes the rocket use its own
`hijack_seconds`), then `expired` on the same tick. `launch()` places the dart at the Hacker's `global_position` (the hull centre, not the dish), so the claim geometry does not
depend on the art. **The tether flash is the rocket's, not the dart's:** the pool recycles the dart on `expired` (hidden, processing off), so a
tether owned by the dart would never show; the homing missile draws it for its own `tether_seconds` 0.3 after a successful `retarget()` (built by t4). If the rocket is freed,
refuses, or becomes ineligible first → `expired` with no claim. A `ProjectileLifetime` child (`max_time` **1.6**, `max_distance` 1400, `use_world_rect` true): 1400 / 900 =
1.56 s ≤ 1.6 s, so the round lifetime sweep (`test_enemy_bullet_lifetime.gd`, `max_distance / slowest speed <= max_time`) passes. **A receding rocket can outrun the dart, by
design:** a rocket 650 px away flying straight away at 500 px/s is caught only after 650 / (900 − 500) ≈ 1.63 s and ≈ 1460 px, past both caps, so the dart expires unclaimed.
Firing rockets *away* from a Hacker at range is a legitimate counter; the in-flight rows use rockets that are not receding at full range. Pooled: a `BulletPool` root child of the Hacker (`pool_size` 4), **without** `persist_after_owner_death`, so a dying Hacker's darts
are cancelled with it (killing the source mid-pulse stops pending claims). Visual: a 6 px white-amber diamond with a 3-point fading trail, code-drawn.

**Disruptor hook (built by t9, used by t10; round-2 review M8):** t9 adds the `pulse_lock_seconds` field (0.0 in `hacker_frigate_config.tres`) and this PULSE-end call; t10 adds only
the Disruptor's scene, its config (1.5) and its rows. At **PULSE end** (the tick PULSE → HOLD_ARC, also when a budget expiry ends the window), if `pulse_lock_seconds > 0` and the
player is within `pulse_trigger_range` 870 with LOS: `player.apply_ability_lock(pulse_lock_seconds, hacker)`. Not at PULSE start: the lock refuses K launches, so a lock during PULSE would stop the player
launching and the Disruptor would cancel its own "newly launched" hijack. At PULSE end the two effects come in sequence (hijack, then a short lock), never stacked.
`pulse_lock_seconds` is 0 in `hacker_frigate_config.tres`, so the base Hacker never locks.

**Config fields** (`HackerFrigateConfig`, pulse group): `pulse_trigger_range` 870, `hijack_range` 650, `max_claims_per_pulse` 3, `pulse_telegraph` 0.9, `pulse_seconds` 1.6, `pulse_period_min` 6.0,
`pulse_period_max` 8.0, `first_pulse_delay` 2.0, `assault_pulses_per_life` 1, `pulse_lock_seconds` 0.0. (These are t9's fields; t8 does not add them.)
The dart's own exports (`hijack_pulse.tscn`): `speed` 900, `claim_radius` 16, lifetime `max_time` 1.6 / `max_distance` 1400; `BulletPool` `pool_size` 4.

Rows (`tests/integration/test_hijack_pulse.gd`, both harnesses; LOS and real-bullet rows on real physics at 8×; a real `RocketState` on a player stub or the real ship for launch rows):
- In flight: three homing rockets launched toward fixture enemies before PULSE (crossing the Hacker's front, not receding from it at full range) are each claimed by a dart during
  PULSE and turn toward the player (heading change bounded per tick by `hijack_turn_rate · delta` + 1e-4 rad).
- Receding rocket (documented limit): a rocket **650 px** from the Hacker's hull centre (just eligible) flying directly away from it at 500 px/s is never claimed, and its dart
  (launched from the hull centre) expires through `ProjectileLifetime`'s 1400 px cap at 1.556 s with the gap still 650 + 500 · 1.556 − 1400 = 27.8 px, 11.8 px over `claim_radius`
  16 (revision 2's 640 px start left 1.8 px).
- Dart lifetime: `HijackPulse` is in the `test_enemy_bullet_lifetime.gd` sweep and passes (1400 / 900 ≤ 1.6).
- Newly launched: a salvo launched 0.5 s into PULSE is claimed (up to the cap).
- Cap: six eligible rockets → exactly 3 claims per pulse.
- Outside PULSE: no dart in HOLD_ARC, BREAK_OFF or TELEGRAPH; none without LOS (a `fixture_wreck` between Hacker and player: no TELEGRAPH starts).
- Ranges: no TELEGRAPH with the player 871 px away, TELEGRAPH with it at 869 px (`pulse_trigger_range`); during PULSE a rocket 649 px from the Hacker is claimed and one 651 px away
  is not (`hijack_range`).
- Cadence (Open Space): with `range_drift` 0 the Hacker holds 720 px from a still player and pulses at least twice in 20 s (first TELEGRAPH at `first_pulse_delay` 2.0 s, the next
  ≤ 2.0 + 0.9 + 1.6 + 8.0 = 12.5 s). **Control:** the same with `pulse_trigger_range` 650 never pulses (the revision-2 gate).
- Hook (t9): a test config with `pulse_lock_seconds` 1.0 locks the player on the PULSE → HOLD_ARC tick and unlocks it 60 ticks later; with the shipped 0.0 nothing locks.
- Inside a jammer field: a rocket inside a lit field is never claimed; the Hacker still pulses.
- Telegraph cancel: one player bullet during TELEGRAPH → no PULSE, HOLD_ARC, a fresh cooldown; control: no hit → PULSE.
- Source death: killing the Hacker mid-PULSE frees its live darts (no claim afterwards) and every rocket it had claimed fizzles on the next tick.
- Holding fire works: no rocket in flight during PULSE → no dart, no claim.
- Warheads never claimed (a warhead salvo during PULSE flies on).
- Primary fire never affected: `WeaponState` cadence and damage over a whole TELEGRAPH + PULSE equal a run with no Hacker.
- Assault: one pulse per life. **Boundary (can fail):** with a test config of `engage_seconds` 30, `first_pulse_delay` 0.5, `pulse_period_min = pulse_period_max` 1.0 and
  `range_drift` 0 (so nothing depends on the drift phase or the seed), the
  Assault harness sees exactly 1 PULSE in 20 s; the same config in Open Space sees at least 3 (control: the cap, not the timings, is what stops it); with `assault_pulses_per_life`
  2 the Assault harness sees exactly 2. A budget expiring in PULSE finishes the window then DISENGAGE; one expiring in TELEGRAPH cancels it.
- Bodies do not block: a fixture enemy (`fixture_enemy.tscn`) parked between the Hacker and the player does not stop TELEGRAPH (the Ph6 LOS rule, pinned so a later change is
  visible); a `fixture_wreck` there does.
- Fairness (real player scene, Open Space and Assault): a full 3-rocket hijack aimed back at a player who keeps cruising and makes one 90° turn deals no damage; a stationary player
  takes at most 3 × 18 = 54 minus i-frame refusals (pinned value), never more.

### 2.12 The Disruptor variant (R9.16, S14, Q5, owner choice 5; t10)

`assault/scenes/enemies/hacker_disruptor/`: `hacker_disruptor.tscn` (same scripts as `hacker_frigate/`) + `hacker_disruptor_config.tres` = the Hacker's values with
`pulse_lock_seconds` 1.5, `max_health` 130, `score_value` 110, and a distinct accent part (a second emitter fin, t12 art). **Not placed** in Ph9 (encounters Ph13, difficulty tiers
Ph16). Joins every roster gate.

**The lock fires at PULSE end, not start** (`pulse_lock_seconds` 1.5): a lock during PULSE would refuse the K launches the pulse exists to hijack. In sequence: up to 1.6 s of
hijack window, then a 1.5 s ability lock (H and K), never both at once.

Rows (in `test_hijack_pulse.gd`, both harnesses, real player scenes; the field, the PULSE-end call and `pulse_trigger_range` 870 come from t9): on the PULSE → HOLD_ARC tick a player at the Hacker's held range (inside `pulse_trigger_range` 870) with LOS becomes locked and is unlocked after exactly 90
ticks (the `<= 1e-6` clock rule; no stabilisation); during PULSE the player is **not** locked by it and a salvo launched 0.5 s into PULSE is claimed (the Disruptor still hijacks
newly launched rockets); a player beyond 870 px or behind a `fixture_wreck` at PULSE end is not locked; the base Hacker never locks (control: `abilities_locked()` stays false
through a whole base-Hacker pulse); primary fire unaffected during the lock.

### 2.13 The EMP zone (R9.19, R9.20; Q12; t11)

`assault/scenes/hazards/emp_zone/`: `emp_zone.gd` (`class_name EmpZone extends Node2D`), `emp_zone.tscn`, `HAZARD.md`. A placed, neutral, cycled area, **composed like the jammer,
never a `HazardField` subclass** (`global/hazards/hazard_field.gd`'s header: "the one script behind … a scene sets the exports and adds its sprite (composition, not
subclasses)"):
- `EmpZone` (root `Node2D`) with a child **`Field`: a `HazardField`** (`kind = &"emp_zone"`, `radius` 260, `avoid_weight` 0.6, no pull, no penalty, `disables_abilities` false — the
  lock comes from the EMP itself — and cycle `cycle_telegraph` 1.0 / `cycle_active` 0.25 / `cycle_quiet` 4.75, a pulse every 6 s). The field registers in its own `_enter_tree()`
  and unregisters in `_exit_tree()` (the inherited rule), and the `HazardField` rule makes its avoid weight count only while lit or telegraphing.
- `EmpZone` exports `emp_seconds` 2.0 and reads `radius` from its `Field` (`func radius() -> float`). In `_ready()` it connects `Field.phase_changed(phase: int)`; on each
  change **to** ACTIVE (from TELEGRAPH), once: `EmpPulse.emit(get_tree(), global_position, Field.radius, emp_seconds, self, EmpPulse.TARGET_ALL)`. A jammer it reaches answers
  `answers_emp()` and goes quiet for the 2 s (its field `suppress`), like every other EMP.
- Visual (an `EmpZoneArt` child of `Field`, code-drawn, reading `Field.phase()` / `phase_progress()`): QUIET a dim blue-white 1 px ring with a small beacon sprite at the centre (t12
  art); TELEGRAPH a ring contracting from `radius` to 0.6 · `radius` with brightening alpha (the arm time is the counterplay, finding F10); ACTIVE an expanding ring through
  `EmpRing.spawn(parent, at, radius)` (`enemy_ordnance/mines/emp_ring.gd`, the Ph7 visual).
- Scene-placed only in Ph9 (hub `TacticalSpace`). Never in an Assault level (guard rows, t14).
- **Hub sweep note:** `test_sector_hub_patrol.gd::_element_radius()` matches `node is HazardField` on `TacticalSpace` children, and an `EmpZone` is a `Node2D` parent, so t11 teaches it
  `if node is EmpZone: return (node as EmpZone).radius()`, checked before the `HazardField` branch (with a row that the helper returns 260 for the scene), so the Ph6 TacticalSpace sweep can never
  treat a placed zone as radius 0.

Rows (`tests/integration/test_emp_zone.gd`, both harnesses): the player inside at the edge is EMP'd (lock + boost refusal for 2.0 s), 1 px outside is not; a brain-driven enemy inside is
EMP'd and still shootable; a player homing rocket inside loses guidance; exactly one emit per cycle (a counter over 3 cycles = 3); avoid weight 0.6 lit, 0 quiet; a Fighter's path
bends around it (it avoids) while a jammer's would not; freeing the zone unregisters its field (`Hazards.count()` back to the previous value).

### 2.14 Art (R9.23; IDEAS §21–23; t12)

Every sprite through the `pixel-art-generation` skill (strict top-down, `view: "high top-down"`, `isometric: false`), saved with `./scripts/pixellab.sh`, opened and checked, and
passing `test_entity_sprite_transparency.gd` (fix a background with `./scripts/strip-sprite-bg.sh`). Faction palette (dark navy hull, red / maroon accents, a cool blue edge light);
states on lights and parts only.

| Asset | Size | Notes |
|---|---|---|
| Hacker Frigate hull | 96×96 | narrow hull with a large forward antenna dish (a silhouette unlike the corvette's tubes and the support's projector); nose-down; the dish drawn as a separate 32×32 part for the unfold |
| Hacker dish part | 32×32 | folded / unfolded via `scale` / rotation, lens light |
| Disruptor accent part | 32×32 | a second emitter fin, so the variant reads differently at range |
| Local jammer tower | 64×64 | top-down tower with three emitter vanes and a central lens |
| Pulsed jammer tower | 64×64 | same family, vanes in a ring (reads "on / off") |
| Sector jammer tower | 96×96 | larger, four vanes, an objective-scale structure |
| EMP zone beacon | 32×32 | a small neutral (grey / blue-white, not faction red) buoy |

The hijack dart, field rings, the hacked-rocket bracket and the EMP / lock overlays stay code-drawn. Rows: the transparency sweep covers every new texture; a `test_ph9_sprites.gd` row
per scene checks the sprite is assigned, its size, and that the dish part exists and moves between folded and unfolded.

### 2.15 Roster gates every new scene joins

Each new enemy directory (`jamming_structure/`, `sector_jammer/`, `pulsed_jammer/`, `hacker_frigate/`, `hacker_disruptor/`) is added to: the `ROSTER` of
`test_enemy_contact_damage.gd` (jammers: `no_hitbox`, the Bonus Drone / Ph8 structure exception; Hacker and Disruptor: 15), `test_contact_hitbox_geometry.gd` (Hacker and Disruptor
only; jammers are listed as no-hitbox like the Ph8 structures), `test_enemy_hurtbox_geometry.gd`, `test_config_instance_isolation.gd` (directory sweep, automatic),
`test_entity_sprite_transparency.gd` (automatic), `test_project_load_integrity.gd` (automatic), `test_base_enemy.gd`'s tow table (Hacker brain), `test_enemy_dual_mode.gd` (one dual-mode
spawn row each), and `test_enemy_mover_single_writer.gd` (automatic for the Hacker brain). `HijackPulse` joins the round lifetime sweep `test_enemy_bullet_lifetime.gd` (`max_distance`
/ `speed` ≤ `max_time`).

### 2.16 Hub placement (R9.22, S13; t13)

`open_space/scenes/levels/sector_hub.gd` / `sector_hub.tscn`:
- **Draw 18 (appended after draw 17, so every earlier seed is unchanged):** a Hacker Frigate on the 2600 ring at bearing **67.5°** (anchor ≈ (995, 2402); free: −22.5, 112.5 and
  −157.5 are taken), exports `hacker_ring_radius` 2600, `hacker_anchor_bearing_deg` 67.5, `patrol_anchor` and `rng_seed` set before `add_child()`. Added to
  `test_sector_hub_patrol.gd::_patrol_groups()` as `"Hacker": [anchor, idle_radius 160, perceive_radius 760]`, so **every existing sweep covers it** (interactables, the Ph6
  TacticalSpace sweep, the Ph7 minefield row, the Ph8 sweep B over turret-group / fence footprints).
- **Sector jammer at the defended derelict site:** a `SectorJammer` instance placed in `EnemyContainer` beside `HubDefenseSite` (origin ≈ (2520, 1040)), at the site's centre
  offset so the field (r 640) covers the turret group: the site's turrets fight the player inside the field (R9.7). Not linked to the group's power (Ph20).
- **Pulsed jammer: under `EnemyContainer`, like every other enemy** (it is a `BaseEnemy`), not in `TacticalSpace`. Reason: the Ph6 TacticalSpace sweep
  (`_space_elements()` / `_space_clearance_violations()`) reads each child's radius through `_element_radius()`, which returns 0 for a `BaseEnemy`, so a jammer there would be
  silently ignored. Placed near the Ph6 / Ph7 hazards so crossing it is a timing choice; covered by sweep C below.
- **EMP zone:** one `EmpZone` in `TacticalSpace` (a hazard, like the Ph6 wells). The **existing Ph6 TacticalSpace sweep applies to it unchanged**: it must clear every patrol's
  anchor (draws 1–18, the Hacker included) by > 100 px past that patrol's `idle_radius` + `perceive_radius`, and every interactable (spawn, `MissionTrigger`s, `PickupBase`s) by
  > 300 px past its radius 260. `_element_radius()` already knows `EmpZone` (t11 added `if node is EmpZone: return radius()`). Also ≥ 500 px (edge to edge) from both jammer fields.
- **Hacker vs jammers:** the Hacker's anchor ≥ `idle_radius` 160 + `preferred_range` 720 + the jammer's `field_radius` from each jammer (sector 640 → 1520 px; the 67.5° anchor is
  ≈ 2045 px from the site, so it holds; the pulsed jammer's spot is chosen to hold too).

Rows (`tests/integration/test_sector_hub_patrol.gd` extensions): the seed rows for draws 1–17 unchanged and draw 18 composition; the Hacker's idle ring + `perceive_radius` clears every
trigger, pickup and the spawn (the existing patrol sweep); the Ph6 TacticalSpace sweep passes with the EMP zone and the Hacker added; **sweep C (new):** every `JammingStructure`
child of `EnemyContainer` (any variant) keeps its `field_radius` + 300 px clear of the spawn point, every `MissionTrigger` and every `PickupBase` (the player is never jammed while
spawning or dwelling at a planet); a boundary row moves a synthetic jammer inside that margin and sees sweep C fail; a "no jammer in `TacticalSpace`" row (a later placement there would
dodge the radius-aware sweeps); the Hacker-vs-jammers distance row; sweeps A / B still pass with the new nodes; the sector jammer's field covers at least two of the site's turret members.

### 2.17 Level 1 placement (R9.22, P5; t14)

`assault/scenes/levels/edelia/1/level_1_director.gd`, **planet_approach only** (DURATION, 110 s), inside existing waves, never in `ENEMIES_CLEARED`. Planet_approach peaks at 7 of
7.5 in the frozen 2.5× specialist gate at 28.4–32.0 s and at 98.0 s, and has specialists in almost every wave, so both placements are **measured**, not computed by hand.

**Hard constraints (every candidate must meet all):**
1. The specialist count stays ≤ 7 at every instant of planet_approach (both new ships count, per ship, like the Ph8 structures).
2. **The Hacker's whole life ends before 98.0 s** (spawn + `engage_seconds` 9.0 + ≤ 1.6 s PULSE deferral + its measured exit), and **the jammer's whole life ends before 98.0 s**
   (spawn → below the world rect, ≈ 26 s at 60 px/s from y −220).
3. The Hacker's life and the jammer's life do not overlap (the "never a Hacker next to a jammer" rule: a jammed player cannot launch, so the hijack would be moot).
4. The jammer's world x clears every planet_approach column lit during its life by `28 + body radius` (`Level1Director.laser_column_schedule()`: 10.0 s 200 / 600 / 1000, 25.0 s
   400 / 800, 38.0 s 128 / 384 / 640 / 896 / 1152, 55.0 s 300 / 700 / 1100, 78.0 s 150 / 550 / 950, 98.0 s 450 / 850).

**Ordered placement options (pre-approved; take the first that meets constraints 1–4, and record which one and the measured peaks):**
- **A (default):** the Hacker first, in a 40–53 s wave (after the 32.0 s peak; gone by ≈ 55 s), at `b.hacker_frigate().at(±400, -180)`; then the jammer in a 55–70 s wave at
  `b.jammer().at(x, -220)` (world-anchored), gone by ≈ 96 s.
- **B:** the jammer first, in a 33–45 s wave; then the Hacker in a wave after the jammer has left the world rect and early enough to be gone before 98.0 s.
- **C:** option A or B with the jammer spawned at design y −120 instead of −220 (a ≈ 3.3 s shorter drift life), which widens both windows.
- **D:** option A or B with the Hacker spawned at the side band (`.at(±500, 50)`, the Ph4 side-entry snipers' offset) so its measured exit is shorter.
- **None fits:** stop with `Result: ESCALATE`, reporting the measured timeline. **Never** add a frozen constant for asteroid_belt, raise a frozen `_LEGACY_PEAK_*`, change the Hacker's
  or the jammer's config for the level, or place either in deep_space (12 of 12.5).
- Both are pinned as `EXPECTED_PH9` in `test_level1_specialist_spawns.gd` (section, wave trigger, offset, scene), like `EXPECTED_PH8`.

**How the guards detect each piece** (`tests/integration/test_engagement_deadline.gd`): a jammer (any variant), Hacker or Disruptor by `entry.ship_scene.resource_path` over every
section's wave entries (the existing `_section_has_scene()` shape); the **EMP zone and placed EMP mines by source scan**, because they are never spawned through `WaveBuilder`: no
`.tscn` under `assault/scenes/levels/` and no `.gd` under `assault/scenes/levels/` may contain the string `emp_zone.tscn` or `EmpZone`, and no level `.tscn` may instance
`emp_mine.tscn` (a placed EMP mine reaches enemies), plus no wave entry's scene path is `res://assault/scenes/hazards/emp_zone/emp_zone.tscn`. **Placed minefields that lay EMP mines
(round-2 review M7):** a `Minefield` (`assault/scenes/hazards/minefield/minefield.gd`, export `w_emp`, default 0.0) creates placed (`Hostility.ALL`) EMP mines at runtime when
`w_emp > 0`, and after t5 those reach enemies (`TARGET_ALL`) without any `emp_mine.tscn` text in the level. So the scan also fails on: a level `.tscn` with a `w_emp = <value>` line
whose value is not 0; a level `.gd` (or `wave_builder.gd`) containing the string `w_emp`; and a wave entry whose scene path is `res://assault/scenes/hazards/minefield/minefield.tscn`
with a non-zero `w_emp` in its `initial_props`. (The Mine Layer's own `w_emp` is not scanned: it lays enemy mines, `Hostility.PLAYER`, which never reach enemies.) Each guard has a
boundary row that feeds it a synthetic section or text containing the piece and sees it fail, including a synthetic level `.tscn` text with `w_emp = 0.15` and one with
`w_emp = 0.0` (which passes).

Rows: `test_level1_specialist_spawns.gd` stays green with `EXPECTED_PH9` (peak ≤ 7 of 7.5 in planet_approach, unchanged elsewhere) and a row asserts constraints 2 and 3 from the
measured lives; a boundary row shows the jammer moved onto a lit column fails the column-clearance check (extend `test_ph8_static_members_clear_every_lit_column` to Ph9 statics); a
boundary row shows the Hacker moved to spawn 2 s before the 98.0 s peak fails the count gate; guard rows above (no jammer, Hacker, Disruptor or EMP zone in an `ENEMIES_CLEARED`
section; no sector jammer, EMP zone, placed EMP mine or EMP-laying `Minefield` in any Assault section); an attack-in-budget replay (`tests/helpers/level1_slice_replay.gd`, 16×) shows the level-1 Hacker reaches PULSE before
its budget expires when the player fires homing rockets, and the jammer locks a player parked inside its field.

### 2.18 Gate time

GUT was 212.4 s at the Ph8 close (2634 tests), 27.6 s under the 240 s ceiling. Allotments (new GUT seconds per task): t1 2.0, t2 0.5, t3 0.8, t4 2.5, t5 2.0, t6 0.5, t7 2.7 (the jammer's EMP rows
added in revision 2), t8 4.0 (includes the Hacker's corridor exit probe, memoised through `ph9_exit_keys.gd`), t9 2.5, t10 0.6, t11 0.8, t12 0.2, t13 1.0, t14 2.5, t15 0 = **22.6 s**,
so the phase ends ≤ 235.0 s.
Every task measures before / after with `scripts/gate-time.sh` and adds a row to the `tests/README.md` → Gate time table. Overruns are fixed by sharing scenarios, the 8× / 16× clock
or memoisation, never by cutting an assertion; a task that would take GUT past 238 s stops with `Result: ESCALATE`.

### 2.19 Numbers and where they come from

| Value | Start | Source |
|---|---|---|
| Stabilisation local / pulsed / sector | 0.75 / 0.75 / 1.25 s | Judgement (no source gives a grace delay) |
| Jammer radius local / pulsed / sector | 240 / 300 / 640 px | Judgement: 480 px crossed in ~1.1 s at 420 px/s; sector ≈ half the 1280 px view |
| Pulsed cycle | 0.8 / 3.0 / 2.5 s | Ph6 anomaly cycle shape; judgement |
| Jammer HP local / pulsed / sector | 140 / 160 / 260 | Ph8 structures (shield generator 120, power source 150) |
| Timed lock: EMP / Disruptor | = EMP seconds (2.0) / 1.5 s at PULSE end | Ph7 `emp_mine.tscn`; finding F2 (1.0–1.75 s band); PULSE end so it never blocks the launches it hijacks |
| Hacker held range OS / Assault | 720 / 520 px | above the corvette's 620 / 460 |
| Hacker arcs | 0.18 / 0.30 rad/s, reversal 3–6 s; cone escape 0.30 rad/s | judgement; corvette 0.22 rad/s, 4–7 s; 0.30 · 720 = 216 px/s stays under `max_speed` 230 |
| Hacker break-off | `mover.boost` 360 px/s, lateral 0.25 (radial ≈ 322), 0.8 s bursts, ≤ 3.0 s, 1.0 s rearm | must beat a 300 px/s rusher radially and lose to the 420 px/s player cruise (review finding 2) |
| Hacker telegraph / pulse / cooldown | 0.9 / 1.6 / 6–8 s; 1 pulse per Assault life | judgement; corvette salvo telegraph 0.7 s; finding F9 (gated); the only cap that can bind in a 9 s budget |
| Pulse trigger range (player gate) | 870 px | `preferred_range` 720 + `range_drift` 90 + 60, so the held band never gates the pulse (round-2 review M1) |
| Hijack (rocket-claim) range / dart speed / claim cap / dart life | 650 px / 900 px/s / 3 / 1.6 s and 1400 px | judgement; `homing_count` 3; 1400 / 900 ≤ 1.6 (the round lifetime sweep) |
| Hacker acceleration | 700 px/s² | the Ph5 Support Ship's; the cone escape needs it (at 260 a wrong-way orbit takes 0.83 s to stop; round-2 review B1) |
| Hijacked rocket speed / turn / window | 380 px/s / 1.6 rad/s / 2.5 s | Ph5 Pursuit rocket band (440 / 1.6 / 3.0), lowered for three at once |
| Hijacked blast / arming | 18 dmg r 40 / 0.25 s and 60 px | Ph5 `pursuit_rocket.tscn` |
| Homing missile lifetime | 6 s / 2400 px | Ph5 shared caps |
| Hacker HP / contact / score | 120 / 15 / 90 | below the corvette's 160; judgement |
| EMP zone | r 260, 1.0 s arm, every 6 s, 2.0 s | EMP mine (190 px / 2.0 s) scaled up; finding F10 (arm time) |

All are *starting values*: keep them unless a row forces a change, and log any change in `DECISIONS.md`.

### 2.20 Docs and phase close (t15)

Invoke the `updating-project-docs` skill: `docs/architecture/PROJECT.md` → Conventions (the ability lock and its seams, the retarget contract, EMP targets, the enemy EMP hook, jammer
fields sampled by the body), `docs/architecture/modules/global.md` (`SeekingOrdnance`, `EmpPulse` targets, `HazardField` exports, `Hazards.jammer_at`, the lock on `PlayerBase`),
`assault.md`, `open_space.md` (hub additions), `docs/enemy-roster.md` (Hacker, Disruptor, three jammers, `WaveBuilder.jammer()` / `hacker_frigate()`), per-entity `ENEMY.md` /
`HAZARD.md`, and CLAUDE.md's gate list (the new gate files). Write the epic dossier `docs/epics-done/cmug23onr001pm52w9swwophy/` (`PRD.md`, `SOURCES.md`, `REPORT.md`) and append
`## Phase 9 - as built (<date>)` to `DECISIONS.md`.

## 3. Build sequence

1. **t1** The ability lock on `PlayerBase`, `Hazards.jammer_at`, `HazardInfo.stabilise_seconds`, `HazardField` exports, the three seams (§2.1, rows §2.2).
2. **t2** The ship overlay, HUD chip and glyph, EventBus seams (§2.3). After t1.
3. **t3** The homing missile's `ProjectileLifetime` (§2.4). Independent.
4. **t4** The retarget contract and the hijacked rocket, seekers jammed in a field (§2.5). After t1 (`jammer_at`), t2 (EventBus signal), t3.
5. **t5** EMP: player effect, `EmpPulse` targets, the enemy hook, seekers, mines (§2.6). After t2 and t4.
6. **t6** EMP Blast re-route (§2.7). After t5.
7. **t7** The Jamming Structure, three variants; seekers and the corvette respect it; its EMP answer (`HazardField.suppress`) (§2.8, §2.9). After t6 (the `answers_emp()` routing and
   `test_emp_blast_module.gd`; t6 follows t5, which also edits `enemy_rocket.gd`).
8. **t8** The Hacker Frigate shell, movement, Assault life, hub idle (§2.10). After t7 (shared roster gate files).
9. **t9** The Hijack Pulse: TELEGRAPH / PULSE, darts, claims (§2.11). After t8 and t4.
10. **t10** The Disruptor variant (§2.12). After t9.
11. **t11** The EMP zone, composed with a child `HazardField`; `_element_radius()` learns `EmpZone` (§2.13). After t5.
12. **t12** Art (§2.14). After t10 and t11.
13. **t13** Hub placement (§2.16). After t9 and t11 (and t7).
14. **t14** Level 1 placement and the EMP-zone guards (§2.17). After t9, t7 and t11 (the guards scan for `emp_zone.tscn`).
15. **t15** Docs, roster, dossier, phase record (§2.20). After everything.

## 4. Test plan

The rows live with their design sections so each task sees them: §2.2 (lock), §2.3 (tells), §2.4 (missile lifetime), §2.5 (retarget hook), §2.6 (EMP), §2.7 (EMP Blast), §2.8 / §2.9
(jammer and respect), §2.10 (Hacker movement), §2.11 (hijack pulse), §2.12 (Disruptor), §2.13 (EMP zone), §2.14 (art), §2.15 (roster gates), §2.16 / §2.17 (placement). New files:
`test_player_ability_lock.gd`, `test_player_ability_lock_tells.gd`, `test_homing_missile_lifetime.gd`, `test_seeking_ordnance.gd`, `test_enemy_emp.gd`, `test_emp_blast_module.gd`,
`test_jamming_structure.gd`, `test_hacker_frigate.gd`, `test_hijack_pulse.gd`, `test_emp_zone.gd`, `test_ph9_sprites.gd`, helper `tests/helpers/ph9_exit_keys.gd`. Extended: `test_hazards.gd`,
`test_emp_pulse.gd`, `test_player_boost_disruption.gd`, `test_player_bullet_lifetime.gd`, `test_missile_corvette.gd`, `test_enemy_bullet_lifetime.gd`, the roster gates,
`test_base_enemy.gd`, `test_enemy_dual_mode.gd`, `test_sector_hub_patrol.gd`, `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd`. Boundary cases named in the sections:
the T+44 / T+45 unlock, the radius ± 1 px rows, the cap of 3, the 650 px claim reach and the 870 px pulse trigger (± 1 px), the 6.0 s hover and 2400 px lifetime rows, the arming clearance, the column-clearance boundary, the 1-pulse-per-Assault-life boundary
(a short-cooldown test config), the nose / route escape bounds with their far-direction controls, the break-off rusher with its `min_range` 0 control, the self-hit guard rows,
the 1e-6 clock rule, the 98.0 s Hacker boundary.

## 5. Risks

- **Unfair hijack.** Three turned rockets at once. Mitigation: 380 px/s (below the Open Space cruise, just above the Assault fighter), 1.6 rad/s, 2.5 s, 18-damage blast, 0.5 s
  i-frames, shoot-down, and the dodge rows (§2.5, §2.11). Not play-tested.
- **Player blast radius.** `PlayerBase`, both ship scripts and `RocketState` are touched by t1, t2, t5; every player test is in range. The unlocked path is an early return and the rows
  pin bit-identity with no hazard.
- **Homing missiles change in Open Space** (they start working away from the origin, t3) and in fields. Owner choice 6.
- **Enemy EMP freezes the Assault budget** (P1). Bounded to 5 s by placement rules; documented.
- **The hub minefield stuns enemies** once placed EMP mines reach them (owner choice 3).
- **Gate time** 22.6 s of 27.6 s headroom.
- **The Hacker cannot out-turn a tracking player** (§2.10): it slides out of a nose that stops, the short way, within about 1.7 s. If play shows that reads as "it never avoids me",
  raise `cone_escape_speed` together with `max_speed` (the 216 ≤ 230 relation), not one alone. Its `acceleration` is 700 px/s² (the Support Ship's) because the escape has to stop a
  wrong-way orbit first; it makes the Hacker's arcs a little crisper than the corvette's (240). The cone bounds come from a simulation of the mover rule, so a GUT measurement could
  differ by a few ticks; the rows keep ≈ 0.5 s of margin and a failing control each, and a bound that cannot hold escalates rather than being retuned.
- **Level-1 window is tight** (§2.17): constraints 1–4 leave little room; the ordered options A–D are pre-approved, and the task escalates rather than touch a frozen constant.
- **Pulsed-field edge cases** (stabilisation starts when the field goes QUIET) can surprise a player who never left the circle; the QUIET outline and the chip fill show it.

## 6. Out of scope

| Item | Where | Why |
|---|---|---|
| Jammer-linked turret groups (`TurretGroup.add_power_provider`) | Ph20 | roadmap; the hub jammer is placed beside the site only |
| Hacker squad tactics, sniper / hacker mark-and-flank | Ph14 | squad communication |
| Disruptor placement; jammer / hacker numbers by difficulty | Ph13 / Ph16 | encounters and tiers |
| Audio (lock, hijack, EMP) | Ph17 | no audio pipeline; EventBus seams built here |
| A ship-mounted EMP weapon (Carrier anti-approach pulse) | Ph10 / Ph18 | first user is the Carrier; `EmpPulse` is ready |
| EMP on structures and legacy enemies (gunship, bonus drone, station, Ph8 turrets / fences) | Ph10 / Ph11 | reworked there; the EMP Blast keeps today's stun for them. **Exception built here:** a Ph9 jammer answers EMP by going quiet and stays shootable (§2.8) |
| Enemy ship bodies blocking line of sight (IDEAS §6.4 "force the hacker behind other enemies") | Ph19 (LOS for heavy ships), maybe Ph14 (escorts screening) | the Ph6 rule: only asteroids and wrecks block `TargetInfo.line_of_sight`; changing it moves every sniper / corvette / support LOS row. Ph9 pins the current rule with a row (§2.11) |
| Player rockets (homing or warhead) shooting down a hijacked rocket | rejected | a salvo flies 7 px apart, so friendly rocket-on-rocket hits would destroy whole salvos; both rocket scripts carry the self-hit guard; primary fire is the shoot-down tool |
| Placed jammers / EMP zones in Assault corridor layouts beyond level 1 | Ph15 | the Ph6 rule |
| A module / cooldown HUD | Ph17 | only the JAMMED chip and the rocket glyph here |
| Shield "hacked" drain (`Shield.set_hacked`) | rejected | drains every charge at once, not a brief disruption |
| Jammer wreckage | Ph19 | |

## 7. Requirements coverage

| Req | Delivered by |
|---|---|
| R9.1 ability lock, pinned before use | t1 (rows §2.2), tells t2 |
| R9.2 seeking-rocket retarget, pinned before use | t3, t4 |
| R9.3 primary fire never affected | t1, t4, t9, t10 rows |
| R9.4 jammer role (abilities only) | t1, t7 |
| R9.5 visible field | t7 (`JammerFieldArt`), t12 tower art |
| R9.6 locked state + stabilisation delay | t1, t2 |
| R9.7 enemies fight around it | t7 (avoid 0), t13 / t14 placement |
| R9.8 enemies respect it | t7 (seekers jammed both ways, corvette downgrade), t9 (no claims inside) |
| R9.9 counterplay | t7 (destroy it with primary fire, fly out, EMP it quiet with the player's EMP Blast fired from outside the field; a press inside is refused) |
| R9.10 local / sector / pulsed | t7 |
| R9.11 Hacker role / size | t8, t12 (96×96) |
| R9.12 movement, outside the route / easiest angle | t8 |
| R9.13 hijack in flight and newly launched | t4, t9 |
| R9.14 Hijack Pulse control projectile | t9 (`HijackPulse` dart) |
| R9.15 tell: visual, indicator, audio | t4 (rocket accent, bracket), t9 (dish, light, tether), t2 (audio seam); audio itself Ph17 (owner choice 4) |
| R9.16 base Hacker seekers only; variant decided | t9; Disruptor t10 (not placed) |
| R9.17 counterplay | t9 (kill source, telegraph cancel, LOS behind asteroids / wrecks, hold fire, fire rockets away at range), t4 (shoot-down with primary fire, lure); "behind other enemies" out of scope (§6, Ph19) |
| R9.18 Assault clamp | t8 (view clamp, budget, exit), t7 (jammer drift, anchoring) |
| R9.19 EMP Pulse weapon | t5 (`EmpPulse` targets), t11 (EMP zone); ship-mounted Ph10 / Ph18 |
| R9.20 EMP zones | t11, t13 |
| R9.21 Ph7 hand-over | t5 (real player effect, enemies, seekers, mines), t6 |
| R9.22 Assault waves + hub ambient | t13, t14 |
| R9.23 own art | t12 |
| R9.24 tests both modes | every task's rows (both harnesses; both real ship scenes) |
| R9.25 design checklist | t8 / t9 rows (approach from behind = break-off; boost away = range hold; off-screen = LOS rule), t15 records it in `ENEMY.md` |

## 8. Response to feedback

### 8.1 Round 1 (revision 2)

Revision 2 answers every finding of the AI plan review (`4-review.md`, CHANGES_REQUESTED). Numbers are the review's.

| # | Finding | What changed | Where |
|---|---|---|---|
| 1 (blocking) | A hijacked rocket's HitBox (mask 513 ⊃ 512) hits its own shoot-down HurtBox and its salvo-mates | The homing missile's `_on_hit_box_area_entered` returns first when `area.get_parent() is homing_missile` (the `EnemyRocket` rule). Decision: player rockets never hit each other; only primary fire shoots a hijacked one down; an enemy rocket meeting a hijacked one detonates, accepted. New real-physics self-hit rows on a real 7 px salvo that fail without the guard. | For every task; §2.5; §6 |
| 2 (blocking) | Nose row unreachable, route row cannot fail, `break_speed` > `max_speed` | The penalty is restated as what the physics allows: inside a cone the orbit is forced toward the nearer edge at `cone_escape_speed` 0.30 rad/s (216 px/s at 720 px, under 230) with reversals held. Rows now time the escape from a stopped nose (1.76 s) and from the route of a 100 px/s player (1.67 s), each with a far-direction control that must fail (≥ 2.33 s / ≥ 2.04 s); the 360 px/s outrun is asserted as the documented limit. BREAK_OFF is a committed `mover.boost` at 360 px/s with lateral weight 0.25 (radial ≈ 322 > 300, derived from `break_contact`'s doubling), ≤ 3.0 s, 1.0 s rearm; Assault uses the clamped request. Rusher row bound 360 px with a `min_range` 0 control below 340 px; a 420 px/s chase row. | §2.10; §2.19; §5 |
| 3 | Exact-tick unlocks drift a tick late | One clock rule for every lock / EMP / suppress clock: `x -= delta`, over at `x <= 1e-6`. Rows keep exact ticks (90 / 120) and a boundary row proves the epsilon matters. | For every task; §2.1; §2.2; §2.6; §2.12 |
| 4 | Dart fails the lifetime sweep; receding rockets; tether vanishes | Dart `max_time` 1.6 (1400 / 900 = 1.56). A receding rocket at full range outrunning the dart is stated as by design, with a row. The tether moves to the rocket (`tether_seconds` 0.3, its own `_draw`); the dart expires on the claim tick. | §2.5; §2.11; §2.19 |
| 5 | 2 pulses per Assault life can never bind | Cap is 1 (with the arithmetic). The boundary row uses a short-cooldown test config: Assault 1, Open Space ≥ 3, cap 2 → exactly 2. | §2.11; §2.19 |
| 6 | EMP Blast makes jammers untouchable while still jamming | `BaseEnemy.answers_emp()` (default `is_ai_driven()`) routes every EMP source; `JammingStructure` answers true and its `apply_emp` calls the new `HazardField.suppress(seconds)` (field quiet, tower shootable, cycle keeps running). EMP Blast rows for it in t7; t7 now depends on t6. | For every task; §2.6; §2.7; §2.8; tasks t6, t7 |
| 7 | `EmpZone extends HazardField` breaks the composition rule | `EmpZone extends Node2D` with a child `HazardField` and a `phase_changed` listener, mirroring the jammer; `_element_radius()` learns `EmpZone`. | For every task; §2.13 |
| 8 | Spy on a static function | Replaced by observable assertions (lock state, fill, signals, presses) with `Hazards.count() == 0`. | §2.2 |
| 9 | Lifetime expiry mid-hijack skips `retarget_ended` | One `_finish(blasted)` end of life; t3 wires `expired → _on_expired()`, which t4 turns into `_finish(false)`. New row. | For every task; §2.4; §2.5 |
| 10 | Level-1 Hacker window overlaps the 98.0 s peak, no fallback | Hard constraints (both lives end before 98.0 s, no overlap, count ≤ 7, column clearance), ordered pre-approved options A–D (Hacker first 40–53 s is the default), then `Result: ESCALATE`; never a frozen-constant change. Boundary row at 96 s. | §2.17; §5 |
| 11 | Hub placement ignores the Ph6 TacticalSpace sweep | The pulsed jammer goes under `EnemyContainer` like every enemy (sweep C covers jammers, plus a "no jammer in TacticalSpace" row); the EMP zone stays in `TacticalSpace` and the Ph6 sweep applies to it via `_element_radius()`; the Hacker joins `_patrol_groups()`. | §2.13; §2.16 |
| 12 | t8 told to create fields of a section it cannot see | §2.10 now says the pulse fields are t9's; §2.11 lists them as t9's. | §2.10; §2.11 |
| 13 | t14's EMP-zone guards lack the t11 dependency and are vacuous | t14 depends on t11; the guard scans level scenes and scripts for `emp_zone.tscn` / `EmpZone` and placed `emp_mine.tscn`, plus wave scene paths, each with a failing boundary row. | §2.17; tasks t14 |
| 14 | "Behind other enemies" counterplay dropped silently | Listed in §6 (Ph19 / Ph14) with the reason; a row pins that a fixture enemy does not block the pulse and a wreck does. | §2.11; §6; §7 |
| 15 | The Disruptor's lock blocks the launches it hijacks | The lock fires at PULSE end (hijack, then lock, never stacked); rows show a salvo launched mid-PULSE is still claimed and the lock lands on the PULSE → HOLD_ARC tick. | §2.11; §2.12; §2.19 |
| 16 | The `enemy_mine.gd` self-reference trap is missing from t5's brief | Added to For every task (Conventions kept) and to §2.6's Callers paragraph, with the unqualified `Hostility.PLAYER` form. | For every task; §2.6 |

### 8.2 Round 2 (revision 3)

Revision 3 answers round 2 of the AI plan review (`4-review.md`, *Round 2*: 1 blocking, 9 minor) and the owner's return of revision 2, which carried no written comment; the owner's
seven choices in the summary keep their defaults. Numbers are the review's unless stated.

| # | Finding | What changed | Where |
|---|---|---|---|
| B1 (blocking) | The nose / route escape rows ignore the Hacker's 260 px/s² acceleration; a wrong-way orbit needs up to 0.83 s to stop, so the 1.76 s / 1.67 s bounds fail, and "nearer edge" is slower than no rule at 0.30 rad/s | `acceleration` raised to **700 px/s²** (the Ph5 Support Ship's value), stated and justified; the nearer-edge rule kept (at 700 it is always the faster exit). The mover rule was simulated (1/60 ticks, the `Steering.orbit` anchor clamp, `move_toward` at `acceleration`) and the table is in §2.10. Rows restated with a shared procedure: a warm-up into a steady orbit in a forced direction with reversals off and `range_drift` 0, a snap of the cone axis so the Hacker moves toward the far edge, three cases (0.18 / 0.30 rad/s far way, 0.18 near way), a fresh instance each, the re-snap 3.5 s after the exit. Bounds 2.2 s (720 px), 1.9 s (520 px), 1.8 s (route), from simulated worst cases 1.70 / 1.42 / 1.33 s; wrong-way time ≤ 0.5 s replaces the 0.25 s monotonic clause; controls (cone 0°) still inside at the bound (simulated 4.12 / 2.57 s and 3.55 / 2.23 s); the 260 value fails the main row (2.72 s at 720 px, 2.02 s at 520 px). The Assault row places the player so the view clamp never binds. | §2.10; §2.19; §5 |
| M1 | The player gate of 650 px sits inside the Open Space held band 720 ± 90 | New `pulse_trigger_range` 870 (= 720 + 90 + 60) gates TELEGRAPH and the Disruptor lock; `hijack_range` 650 stays the rocket-claim reach. New range rows (869 / 871 px, 649 / 651 px), a cadence row (≥ 2 pulses in 20 s at 720 px) with a 650 px control that never pulses, and `range_drift` 0 in the cap boundary row. | §2.11; §2.12; §2.19 |
| M2 | The Assault 6.0 s / 2400 px rows and the "flown 5.0 s" setup are unreachable | The 6.0 s row and t4's 5.0 s pre-flight keep the rocket alive by hovering on a hurtbox-less static `Node2D`; the 2400 px row runs in Open Space only (4.8 s); Assault asserts only the rect expiry, with the arithmetic. | §2.4; §2.5 |
| M3 | A warhead is consumed by a hijacked homing rocket | `warhead_missile.gd::_on_hit_box_area_entered` gets the same `area.get_parent() is homing_missile` guard; real-physics row (both alive after the crossing, fails without the guard). | For every task; §2.5; §6 |
| M4 | The jammer EMP row presses EMP Blast inside the field, where it is locked | Stated rule: EMP Blast switches a jammer off only from outside its field. Three rows: through the real seam from outside, refused inside, and a direct `try_activate()` call for the unlock-after-suppression timing (documented as bypassing the seam). Summary and R9.9 say so. | Summary; §2.8; §7 |
| M5 | The receding-rocket row has a 1.8 px margin | 650 px start, dart launched from the hull centre (stated in the dart design): 27.8 px gap, 11.8 px over the claim radius. | §2.11 |
| M6 | DECISIONS.md puts the pulsed jammer in `TacticalSpace` | Corrected: jammers (every variant) under `EnemyContainer`, the EMP zone in `TacticalSpace`. | DECISIONS.md Phase 9 |
| M7 | The Assault EMP guard misses a `Minefield` with `w_emp > 0` | The source scan also fails on a non-zero `w_emp` in a level `.tscn`, the string `w_emp` in a level script or `wave_builder.gd`, and a `minefield.tscn` wave entry with a non-zero `w_emp`; boundary rows with `w_emp = 0.15` (fails) and `0.0` (passes). | §2.17; t14 |
| M8 | Who builds the Disruptor hook is stated two ways | t9 adds `pulse_lock_seconds` (0.0) and the PULSE-end call, with a hook row on a test config; t10 adds only the Disruptor scene, config and rows. | §2.11; §2.12; t9, t10 |
| M9 | An enemy railed while EMP'd keeps its EMP state forever | `suspend_ai()` clears a live EMP window (clock, overlay, `is_emp_disrupted()`), with a row that fails on a build that counts down only in the brain branch. | For every task; §2.6; t5 |
