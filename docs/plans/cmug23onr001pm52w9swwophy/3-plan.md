# Enemy rework, phase 9: electronic warfare - Jamming Structure, Hacker Frigate and EMP

Revision 1 (2026-11-06). Built on this directory's `1-context.md` (requirements R9.1–R9.25, files, conventions, open questions
Q1–Q16) and `2-research.md` (scope check S1–S18, findings F1–F12, starting values, recommendations). Every research recommendation is
adopted unless §1.1 says otherwise. Code facts below were re-read on `agent/auto-dev` @ `c1ba45e`.

## Summary for the owner

- **For the player:** two new enemies attack your tools, not your hull. A **Jamming Structure** projects a visible static field; inside it your special abilities (the H module abilities) and your K rockets are locked, and they come back a moment after you leave. Movement, boost, dash and your main gun are never touched, so you can always shoot the tower or fly out.
- **Three jammers:** a small local one, a large sector one around an objective, and a pulsed one that switches on and off so you can time a crossing. Enemies fight inside the field freely (it is their ground), and inside it every homing rocket, theirs and yours, flies straight.
- **Hacker Frigate:** a fragile specialist that keeps its distance on lopsided arcs, stays out of your nose and off your flight line, and charges up a visible pulse. During the pulse it fires small control darts at your homing rockets, in flight or just launched; a hit rocket flashes amber, turns slowly back toward you and explodes for a small blast. Counters: kill the Hacker (its turned rockets fizzle at once), hold your rockets while it pulses, shoot the turned rocket down, hit the Hacker while it charges (cancels the pulse), break line of sight, or lead the rocket into another enemy (it still hits them at full damage).
- **EMP becomes real:** an EMP now locks your abilities as well as your boost for its short window, and makes homing rockets in range lose their lock. Enemies can be hit by EMP too: they stop attacking and drift for a few seconds but can still be shot. A new neutral **EMP zone** in the hub pulses on a cycle and hits everyone inside.
- **Where:** the hub gets a Hacker on patrol, a sector jammer over the defended derelict site, a pulsed jammer and an EMP zone; level 1 gets one Hacker and one small jammer in Planet Approach, apart from each other.
- **Built but not placed:** a "Disruptor" Hacker whose pulse also locks your abilities for 1.5 s (for later encounters and difficulty tiers).
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
  `tick()` (cooldowns keep counting). A refused press spends nothing (no module cooldown, no `CooldownTimer`, no launch) and is consumed.
- **Jammer field = a hazard sampled by the body** (the Ph6 rule): `HazardInfo.disables_abilities` (exists, reserved) and new `HazardInfo.stabilise_seconds: float`; `HazardField` gains
  exports `disables_abilities := false` and `stabilise_seconds := 0.0`, written into its info, with `disables_abilities` true **only while ACTIVE**. `Hazards.jammer_at(pos: Vector2) ->
  HazardInfo` returns the containing info with `disables_abilities` and the largest `stabilise_seconds`, else null. Kind `&"jammer"`, `avoid_weight` 0 (enemies ignore it).
- **Seekers inside a lit jammer field fly straight** (both sides): the player's homing missile and an `EnemyRocket` skip guidance while `Hazards.jammer_at(global_position) != null`.
  DUMB rockets and warheads are unaffected. A rocket is never claimed by a Hacker inside a field.
- **Retarget contract (duck-typed, like `is_armored()`):** an eligible player seeking projectile joins group `&"player_seeking_ordnance"` (const `SeekingOrdnance.GROUP`,
  `global/components/seeking_ordnance.gd`) and answers `can_be_retargeted() -> bool`, `retarget(target: Node2D, seconds: float, source: Node) -> bool`, `is_retargeted() -> bool`,
  `jam_guidance(source: Node) -> void`, signals `retargeted(source: Node)` and `retarget_ended()`. Only `homing_missile` implements it; `WarheadMissile` is never eligible.
- **A hijacked homing missile** (exports on `homing_missile.tscn`): turn-limited (`Steering.turn_toward`, `hijack_turn_rate` 1.6 rad/s) toward the player at `hijack_speed` 380,
  for `hijack_seconds` 2.5, then fizzles (`expired`, no blast). It hurts the player **only by a `ContactBlast`** (layer 256, 18 dmg, r 40), armed after `hijack_arm_seconds` 0.25 and
  once it has been ≥ `hijack_arm_clearance` 60 px from the player; it keeps full damage against enemies; it is shot down by one player bullet (HurtBox layer 512 / mask 64, enabled
  only while hijacked); it fizzles at once if its `source` is freed. No new collision bit.
- **EMP:** `EmpPulse.emit(tree, at, radius, seconds, source, targets := TARGET_PLAYER) -> int`; `TARGET_PLAYER = 1`, `TARGET_ENEMIES = 2`, `TARGET_SEEKERS = 4`. Existing calls stay
  bit-identical. The player effect = `apply_ability_lock(seconds)` + the Ph7 `apply_boost_disruption(1.0, seconds)`. Enemies: duck-typed `BaseEnemy.apply_emp(seconds, source)`,
  `is_emp_disrupted()`; brain-driven ships only (structures, legacy enemies ignore it); the enemy stays tangible.
- **New names and places:** `assault/scenes/enemies/jamming_structure/` (`JammingStructure`, `JammingStructureConfig`, `JammerFieldArt`), `sector_jammer/` and `pulsed_jammer/`
  (scene + config, same scripts; the `heavy_emplacement/` precedent), `hacker_frigate/` (`HackerFrigate`, `HackerFrigateBrain`, `HackerFrigateConfig`), `hacker_disruptor/` (scene +
  config, same scripts), `assault/scenes/projectiles/hijack_pulse/` (`HijackPulse`, the control dart), `assault/scenes/hazards/emp_zone/` (`EmpZone`). `WaveBuilder.jammer()`,
  `hacker_frigate()`. One `*config*.tres` per directory (`test_config_instance_isolation.gd`).
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
- **Tests first, GUT.** Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`, `open_space()` / `assault()`, label-parameterised, never
  `use_parameters([HARNESS…])`). Lock and blast rows use **both real player scenes** (`open_space/scenes/entities/player/player_ship.tscn`, `assault/scenes/player/player_fighter.tscn`)
  in the shape of `tests/integration/test_player_boost_disruption.gd` (hand-ticked, fixed delta 1/60). Physics queries (LOS) only on the physics step; such rows run on real physics at
  the 8× clock. Per-tick drivers are a child `_Ticker` node. Run `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget:** GUT was 212.4 s at the Ph8 close. Measure with `scripts/gate-time.sh` before and after each task, report both in the task report and the `tests/README.md`
  → Gate time table. Allotments (new GUT seconds): t1 2.0 · t2 0.5 · t3 0.8 · t4 2.5 · t5 2.0 · t6 0.5 · t7 2.5 · t8 4.0 · t9 2.5 · t10 0.6 · t11 0.8 · t12 0.2 · t13 1.0 · t14 2.5 ·
  t15 0 = 22.4 s, so the phase ends ≤ 235 s. An overrun is fixed by sharing a scenario, the 8×/16× clock or a memoised probe, never by cutting an assertion; a task that would take GUT
  past 238 s stops with `Result: ESCALATE`.
- **Task order:** tasks that edit the same files are chained: `player_base.gd` t1 → t2 → t5; `homing_missile.gd` t3 → t4 → t5; `enemy_rocket.gd` t5 → t7; the roster gates, `test_base_enemy.gd`,
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
- otherwise, `_stabilise_left = maxf(0.0, _stabilise_left - delta)`.
- `_timed_left = maxf(0.0, _timed_left - delta)`.
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
| Timed | `apply_ability_lock(1.5, src)`: locked for 90 ticks, unlocked on tick 90, no stabilisation; a shorter second call does not shorten; a field + a timed lock: unlocked only when both are over. |
| H refused, nothing spent | for **every** module id in `ShipModuleState.SLOT_MODULES` that overrides `try_activate`, equipped on each ship: an H press while locked leaves its cooldown / state unchanged (module-specific readable: e.g. `EMPBlastModule._cooldown_left == 0`), emits `ability_press_refused`, marks the event handled; the same press one tick after the unlock activates it. Boundary: a press on T+44 is refused, on T+45 accepted. |
| K refused, nothing spent | in both ships, both rocket types: a K press while locked starts no `CooldownTimer` and adds no rocket child; a K press during the cooldown (unlocked) gives no `ability_press_refused`; `switch_weapon` while locked still switches. |
| Cooldowns keep ticking | a module with 10 s cooldown left, locked for 3 s: 7 s left at the unlock. |
| Primary fire never affected | in both ships, for all five weapon modes (`WeaponModeResource`s used by `WeaponState`): shots fired, cadence and damage over 120 ticks inside a lit field equal the same 120 ticks with no field (bit-identical counts and damage). |
| Movement never affected | thrust / turn / Shift boost (Open Space), move / dash / warp (Assault): position and velocity after 60 ticks inside a lit field equal the run without the field. |
| No hazard = bit-identical | with `Hazards.count() == 0` the lock code never runs (a spy on `Hazards.jammer_at` sees zero calls). |

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
  `expired → queue_free` in `_ready()`. In Assault the rect is `EnemyWorld.projectile_world_rect()` (the same box the constants hard-coded, so Assault behaviour is unchanged apart
  from the new time and distance caps); in Open Space the rect rule is a no-op.
- Nothing else changes in t3: speed 500, straight-at-target steering, damage 100, HitBox layer 32 / mask 513, frees on a non-deflected hit.

Rows (`tests/integration/test_homing_missile_lifetime.gd`, plus one row in `test_player_bullet_lifetime.gd`):
- Open Space harness: a rocket launched at (20000, 15000) with a target 600 px away lives and reaches it (it died on its first tick before).
- Assault harness: a rocket leaving the projectile world rect emits `expired` once and is freed; one flying in-rect with no target expires at `max_time` 6.0 (±1 tick); one at
  2400 px from its origin expires.
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
  pop, `retarget_ended`, end of life through `expired`.
- `_hijack_left` reaching 0 → fizzle: pop (no blast), `retarget_ended`, `expired`.
- Its HitBox keeps layer 32 / mask 513 and `damage` 100: a hijacked rocket that crosses an enemy hurts it at full damage and ends (the lure, R9.17).
- **Shoot-down:** a `HurtBox` child (layer 512 `enemy_hurtbox`, mask 64 `player_hitbox`, a 7 px circle) with `monitoring` / `monitorable` false until hijacked; one
  `received_damage` → pop, `retarget_ended`, end. A player bullet that hits it is consumed (a damaging hit). Close every area deferred and end two ticks later, the `EnemyRocket`
  `_end_after_overlaps()` pattern, so nothing re-reports an overlap.
- **Tell** (IDEAS §21: change a light, not the hull): the sprite's `self_modulate` warms to amber `Color(1.0, 0.7, 0.3)`, the `RocketTrail` turns amber, and a code-drawn target bracket
  (four 4 px corner ticks at r 12, rotating 3 rad/s) is drawn on the rocket while hijacked. The tether flash from the Hacker is t9's.
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
- `TARGET_ENEMIES`: group `enemies`, nodes answering `apply_emp`, skipping `is_queued_for_deletion()`.
- `TARGET_SEEKERS`: group `SeekingOrdnance.GROUP` (player homing rockets) and group `&"enemy_seeking_ordnance"` (an `EnemyRocket` joins it in `launch()` when `turn_rate > 0`
  and leaves it in `_mark_done()` / `reset()`): `jam_guidance(source)` on each. An `EnemyRocket.jam_guidance()` ends its guidance window at once (`is_guiding()` false from the next
  tick; it flies straight and keeps its blast).

**Enemy hook** (`assault/scenes/enemies/base_enemy.gd`): `apply_emp(seconds: float, source: Node) -> void` and `is_emp_disrupted() -> bool`.
- Applies only to an enemy with a brain and a mover that is not suspended (`is_ai_driven()`); everything else (structures with no mover, legacy enemies that override
  `_physics_process`, a railed enemy) returns at once. Longest wins.
- On the start: `_brain.on_emp_started()` (new virtual on `EnemyBrain`, default no-op), `mover.halt()`, and a code-built `EmpStatic` overlay on the enemy (blue-white jagged ring,
  the same shape as the player's, `Color(0.7, 0.85, 1.0)`).
- While `_emp_left > 0`: `BaseEnemy._physics_process` **skips `_brain.tick(delta)`** and still calls `_mover.step(delta)` (hazard pull, drift and the corridor constraint keep
  working; nothing requests a new velocity, so the ship coasts to a stop). The hurtbox, body and health are untouched: **the enemy can be shot**. `AttackController`s with
  `driven_by_brain` do not fire (no brain tick); a legacy timer-driven controller is not used by any brain-driven ship.
- On the end: overlay hidden, the brain ticks again from the state it was in.
- **Assault budget:** frozen for the EMP window (P1 in §1.1). Bounded by the 5 s EMP Blast; no Ph9 EMP zone or placed EMP mine goes into any Assault level.
- `TwinLaserDroneBrain.on_emp_started()` breaks its pair (`TwinLaserPair` collapse, the same call a drone death makes), so no lit beam is frozen in place; `LaserTenderBrain.on_emp_started()` cancels a
  launch telegraph in progress (a pair already launched is two drones with their own EMP handling). A sweep row asserts every brain script of a mover-driven ship that references
  `EnemyBeam` or `TwinLaserPair` overrides `on_emp_started()` (structures have no mover and ignore EMP).

**Callers:** the EMP mine (`enemy_mine.gd`, the `EmpPulse.emit` in its EMP branch) passes `TARGET_PLAYER | TARGET_SEEKERS` when `hostility == Hostility.PLAYER` (enemy-laid) and
`TARGET_ALL` when `Hostility.ALL` (placed, owner choice 3). The hub `Minefield` (EMP weight 0.15) therefore starts stunning enemies near it.

Rows (`tests/unit/test_emp_pulse.gd`, `tests/integration/test_enemy_emp.gd` both harnesses, `test_player_boost_disruption.gd` / `test_player_ability_lock.gd` additions):
- `test_emp_pulse.gd`: every existing row unchanged (the default set never touches `enemies`); `TARGET_ENEMIES` reaches a fixture enemy at the radius and not 1 px beyond; seekers are
  jammed but not counted.
- Player: an EMP of 2.0 s locks abilities for exactly 120 ticks with no stabilisation, refuses boosts (Ph7 rows), and `emp_changed` fires once each way.
- Enemy: an EMP'd Fighter (both harnesses) fires nothing for the window and resumes after it; it coasts to under 5 px/s; **a real player bullet kills an EMP'd enemy** (its hurtbox
  stays in physics; the counter-row to the EMP Blast bug); a structure (`ShieldGenerator`) and a railed enemy are unaffected; the twin pair collapses when one drone is EMP'd.
- Seekers: a player homing rocket and an enemy Pursuit rocket in radius lose guidance (heading constant afterwards); a DUMB rocket is unchanged.
- Mines: an enemy-laid EMP mine never reaches a fixture enemy beside the player; a placed (`ALL`) one does.

### 2.7 The player's EMP Blast re-routed (S5, Q11, owner choice 2; t6)

`global/ship_modules/emp_blast_module.gd`: `try_activate()` keeps its 15 s cooldown, its visual, its "every enemy in the scene" reach (no radius, unchanged) and its immune list. For
each non-immune enemy: if it answers `is_ai_driven()` true, call `apply_emp(5.0, player)` (tangible, §2.6); otherwise (the legacy Gunship, Bonus Drone, Space Station and every
brainless structure) keep today's `PROCESS_MODE_DISABLED` + `create_timer` path unchanged. Its description stays truthful (no wording change needed).

Rows (`tests/integration/test_emp_blast_module.gd`): a brain-driven enemy hit by the module is EMP'd for 5 s and a real bullet still damages it; a legacy enemy is still
process-disabled for 5 s (characterisation of the unchanged branch); `RamCorvette` is still skipped (`test_ram_corvette.gd::test_emp_still_skips_the_corvette` unchanged); the
cooldown is still 15 s.

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
- **Bearing penalty (stay out of the easiest attack angle and off the route, §18.6):** the orbit target angle is pushed out of the player's nose cone (± `nose_cone_deg` 30 around
  `TargetInfo.facing`) and off the player's velocity line (± `route_cone_deg` 25 around `TargetInfo.velocity` when the player moves faster than 80 px/s): when the current bearing
  from the player lies inside either cone, the orbit direction is forced toward the nearer cone edge (and the reversal clock is reset). The SniperBrain scoring precedent.
- **BREAK_OFF:** the player inside `min_range` 420 → `Steering.break_contact` at `break_speed` until beyond `min_range + 120`, then HOLD_ARC. No pulse while breaking.
- **Nose:** faces the player (`mover` facing request), `sprite_forward_angle` `PI/2`.
- **Assault:** the Ph5 Support Ship view clamp (`support_ship_brain.gd` `_clamp_into_view()`: the request is clamped so the hull stays inside `EnemyWorld.view_rect().grow(-view_margin)`,
  `view_margin` 60); an `EngagementBudget(engage_seconds 9.0)`; at expiry DISENGAGE (release the constraint, `exit_speed` 300, seek outside the projectile world rect, free). The exit
  is measured over `corridor_starts()` with `tests/helpers/specialist_exit_probe.gd` (memoised, built through a new `tests/helpers/ph9_exit_keys.gd`, static `prepare`, the Ph8
  `ph8_exit_keys.gd` rule).
- **Hub idle:** `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) around `patrol_anchor` (`idle_radius` 160, `idle_speed` 0.45, asymmetric like its combat arc), NOTICING on
  `perceive_radius` 760 for `notice_time` 0.35, RETURNING beyond `lose_radius` 1600. `start_engaged` export skips IDLE (tests, waves).
- `accepts_tow()` false in TELEGRAPH and PULSE. Add the brain to `test_base_enemy.gd`'s tow table.

**Config (starting values):** `max_health` 120, `collision_damage` 15, `score_value` 90, `max_speed` 230, `acceleration` 260, `max_turn_rate` 1.4, `preferred_range` 720,
`assault_preferred_range` 520, `range_drift` 90, `min_range` 420, `break_speed` 300, `orbit_speed_cw` 0.18, `orbit_speed_ccw` 0.30, `reversal_min` 3.0, `reversal_max` 6.0,
`nose_cone_deg` 30, `route_cone_deg` 25, `view_margin` 60, `engage_seconds` 9.0, `exit_speed` 300, the pulse fields of §2.11, idle / perception fields above, hazard fields as the
corvette (`hazard_avoidance` 0.7, `hazard_margin` 80, `hazard_resistance` 0.4), `wreck_chance` 0.4, `wreck_size` 1.

Rows (`tests/integration/test_hacker_frigate.gd`, both harnesses unless noted):
- Holds range: over 20 s against a still player, distance stays in `held_range() ± (range_drift + 60)`.
- Asymmetric arcs: measured angular speed differs by direction (≈ 0.18 vs 0.30 rad/s); at least one reversal in 10 s over 4 seeds.
- Out of the nose: against a player turning to face it every 2 s, the fraction of ticks inside the ± 30° nose cone is under 25 % (control: with `nose_cone_deg` 0 it is higher).
- Off the route: against a player cruising at 360 px/s, it is inside the ± 25° velocity cone less than 25 % of ticks.
- Break-off: a player rushing at 300 px/s triggers BREAK_OFF inside 420 px; it returns to HOLD_ARC beyond 540.
- Assault: the hull stays inside `view_rect().grow(-60)` for its whole budget; DISENGAGE at 9.0 s; it leaves the world rect within the measured exit.
- Hub idle (Open Space): idles inside `idle_radius` + 40 of its anchor until the player is inside 760 px, then NOTICING → HOLD_ARC.
- Roster gates (§2.15).

### 2.11 The Hijack Pulse (R9.13–R9.17; Q6; t9)

**Delivery: a PULSE window on the Hacker plus one visible control dart per claim.**

**Hacker phases** (`HackerFrigateBrain`): from HOLD_ARC, when the pulse cooldown has run out (`pulse_period_min..max` 6–8 s, from `brain.rng`) **and** `can_see_player()` **and** the
player is within `hijack_range` 650 **and** not in BREAK_OFF → TELEGRAPH for `pulse_telegraph` 0.9 s (yellow `StateLight`, the `Dish` unfolds, a slow inward-moving ring of 6 dashes
around the hull at r 60 → 40). **Damage during TELEGRAPH cancels the pulse** (connect `health.amount_changed`; any decrease) → HOLD_ARC with a fresh cooldown. Then PULSE for
`pulse_seconds` 1.6 (white light, an outward ripple ring from the dish every 0.4 s, code-drawn). In PULSE, every tick: for each rocket in
`SeekingOrdnance.eligible(tree, hacker position, hijack_range)` not already targeted by a live dart, with `LineOfSight.clear` from the hacker to the rocket (physics step only), while
`claims_this_pulse < max_claims_per_pulse` 3: fire a dart at it. Rockets launched during the window are picked up the same way on the next tick ("newly launched"); rockets already in
flight when PULSE starts are picked up on its first tick ("in flight"). After PULSE → HOLD_ARC with a new cooldown. The Hacker keeps moving (HOLD_ARC steering) in TELEGRAPH and PULSE.
Assault: at most `assault_pulses_per_life` 2 pulses per life; a budget expiring in TELEGRAPH cancels it, in PULSE lets the window finish (≤ 1.6 s), then DISENGAGE.

**The dart** (`assault/scenes/projectiles/hijack_pulse/hijack_pulse.gd`, `class_name HijackPulse extends Node2D`, `hijack_pulse.tscn`; weapon tuning in its exports): non-damaging,
**no collision areas** (it claims by distance, so no layer is needed). `signal expired`, `reset()`, `launch(rocket: Node2D, source: Node)`. Flies at `speed` 900 px/s homing
exactly at its rocket (no turn limit: it must be reliable); when within `claim_radius` 16 of the rocket → `rocket.retarget(player, rocket's hijack_seconds, source)` (the rocket reads
its own `hijack_seconds` when the caller passes a negative value; pass -1.0), draw a 0.3 s tether flash (a `Line2D` from the source to the rocket, white → amber, owned by the
dart and freed with it), then `expired`. If the rocket is freed, refuses, or becomes ineligible first → `expired` with no claim. A `ProjectileLifetime` child (`max_time` 1.5,
`max_distance` 1400, `use_world_rect` true). Pooled: a `BulletPool` root child of the Hacker (`pool_size` 4), **without** `persist_after_owner_death`, so a dying Hacker's darts
are cancelled with it (killing the source mid-pulse stops pending claims). Visual: a 6 px white-amber diamond with a 3-point fading trail, code-drawn.

**Disruptor hook (filled by t10):** at PULSE start, if `pulse_lock_seconds > 0` and the player is within `hijack_range` with LOS: `player.apply_ability_lock(pulse_lock_seconds, hacker)`.
`pulse_lock_seconds` is 0 in `hacker_frigate_config.tres`, so the base Hacker never locks.

**Config fields** (`HackerFrigateConfig`, pulse group): `hijack_range` 650, `max_claims_per_pulse` 3, `pulse_telegraph` 0.9, `pulse_seconds` 1.6, `pulse_period_min` 6.0,
`pulse_period_max` 8.0, `first_pulse_delay` 2.0, `assault_pulses_per_life` 2, `pulse_lock_seconds` 0.0.

Rows (`tests/integration/test_hijack_pulse.gd`, both harnesses; LOS and real-bullet rows on real physics at 8×; a real `RocketState` on a player stub or the real ship for launch rows):
- In flight: three homing rockets launched toward fixture enemies before PULSE are each claimed by a dart during PULSE and turn toward the player (heading change bounded per tick as in
  §2.5).
- Newly launched: a salvo launched 0.5 s into PULSE is claimed (up to the cap).
- Cap: six eligible rockets → exactly 3 claims per pulse.
- Outside PULSE: no dart in HOLD_ARC, BREAK_OFF or TELEGRAPH; none without LOS (a `fixture_wreck` between Hacker and player: no TELEGRAPH starts); none beyond 650 px.
- Inside a jammer field: a rocket inside a lit field is never claimed; the Hacker still pulses.
- Telegraph cancel: one player bullet during TELEGRAPH → no PULSE, HOLD_ARC, a fresh cooldown; control: no hit → PULSE.
- Source death: killing the Hacker mid-PULSE frees its live darts (no claim afterwards) and every rocket it had claimed fizzles on the next tick.
- Holding fire works: no rocket in flight during PULSE → no dart, no claim.
- Warheads never claimed (a warhead salvo during PULSE flies on).
- Primary fire never affected: `WeaponState` cadence and damage over a whole TELEGRAPH + PULSE equal a run with no Hacker.
- Assault: at most 2 pulses per life; a budget expiring in PULSE finishes the window then DISENGAGE.
- Fairness (real player scene, Open Space and Assault): a full 3-rocket hijack aimed back at a player who keeps cruising and makes one 90° turn deals no damage; a stationary player
  takes at most 3 × 18 = 54 minus i-frame refusals (pinned value), never more.

### 2.12 The Disruptor variant (R9.16, S14, Q5, owner choice 5; t10)

`assault/scenes/enemies/hacker_disruptor/`: `hacker_disruptor.tscn` (same scripts as `hacker_frigate/`) + `hacker_disruptor_config.tres` = the Hacker's values with
`pulse_lock_seconds` 1.5, `max_health` 130, `score_value` 110, and a distinct accent part (a second emitter fin, t12 art). **Not placed** in Ph9 (encounters Ph13, difficulty tiers
Ph16). Joins every roster gate.

Rows (in `test_hijack_pulse.gd`, both harnesses, real player scenes): at PULSE start a player within 650 px with LOS is locked for exactly 1.5 s (90 ticks) with no stabilisation; a
player beyond 650 or behind cover is not; the base Hacker never calls `apply_ability_lock` (control); primary fire unaffected during the lock.

### 2.13 The EMP zone (R9.19, R9.20; Q12; t11)

`assault/scenes/hazards/emp_zone/`: `emp_zone.gd` (`class_name EmpZone extends HazardField`), `emp_zone.tscn`, `HAZARD.md`. A placed, neutral, cycled area:
- `kind = &"emp_zone"`, `radius` 260, `avoid_weight` 0.6 (lit and telegraph; the `HazardField` rule makes it 0 in QUIET), no pull, no penalty, `disables_abilities` false (the
  lock comes from the EMP itself).
- Cycle `cycle_telegraph` 1.0 / `cycle_active` 0.25 / `cycle_quiet` 4.75 (a pulse every 6 s). On each TELEGRAPH → ACTIVE edge (`phase_changed`), once:
  `EmpPulse.emit(get_tree(), global_position, radius, emp_seconds 2.0, self, EmpPulse.TARGET_ALL)`.
- Visual (code-drawn): QUIET a dim blue-white 1 px ring with a small beacon sprite at the centre (t12 art); TELEGRAPH a ring contracting from `radius` to 0.6 · `radius` with
  brightening alpha (the arm time is the counterplay, finding F10); ACTIVE an expanding ring like `EmpRing` (`enemy_ordnance/mines/`), reused if its API allows.
- Scene-placed only in Ph9 (hub). Registers in `_enter_tree()` (the inherited rule).

Rows (`tests/integration/test_emp_zone.gd`, both harnesses): the player inside at the edge is EMP'd (lock + boost refusal for 2.0 s), 1 px outside is not; a brain-driven enemy inside is
EMP'd and still shootable; a player homing rocket inside loses guidance; exactly one emit per cycle; avoid weight 0.6 lit, 0 quiet; a Fighter's path bends around it (it avoids) while a
jammer's would not.

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
- **Draw 18 (appended after draw 17, so every earlier seed is unchanged):** a Hacker Frigate on the 2600 ring at bearing **67.5°** (free: −22.5, 112.5 and −157.5 are taken), exports
  `hacker_ring_radius` 2600, `hacker_anchor_bearing_deg` 67.5, `patrol_anchor` and `rng_seed` set before `add_child()`.
- **Sector jammer at the defended derelict site:** a `SectorJammer` instance placed in `EnemyContainer` beside `HubDefenseSite` (origin ≈ (2520, 1040)), at the site's centre
  offset so the field (r 640) covers the turret group: the site's turrets fight the player inside the field (R9.7). Not linked to the group's power (Ph20).
- **Pulsed jammer:** one `PulsedJammer` at a free spot of `TacticalSpace` near the Ph6 / Ph7 hazards, so crossing it is a timing choice.
- **EMP zone:** one `EmpZone` in `TacticalSpace`, at least `radius` + 300 px from the spawn, every `MissionTrigger` and every pickup, and ≥ 500 px from both jammers.
- Keep the Hacker away from both jammers: its anchor ≥ `idle_radius` + `preferred_range` + jammer radius from each.

Rows (`tests/integration/test_sector_hub_patrol.gd` extensions): the seed rows for draws 1–17 unchanged and draw 18 composition; the Hacker's idle ring + `perceive_radius` clears every
trigger, pickup and the spawn (the existing patrol sweep); **sweep C (new):** every jammer and EMP zone child of `EnemyContainer` / `TacticalSpace` keeps its `radius` + 300 px clear of
the spawn point, every `MissionTrigger` and every `PickupBase` (the player is never jammed or EMP'd while spawning or dwelling at a planet); sweep A / B still pass with the new nodes;
the sector jammer's field covers at least two of the site's turret members.

### 2.17 Level 1 placement (R9.22, P5; t14)

`assault/scenes/levels/edelia/1/level_1_director.gd`, **planet_approach only** (DURATION, 110 s), inside existing waves, never in `ENEMIES_CLEARED`:
- **One local jammer** (`b.jammer().at(x, -220)`, world-anchored) in a wave whose drift life (spawn → below the world rect, ≈ 26 s at 60 px/s) avoids the 28.4–32.0 s and 98.0 s
  peaks with the specialist count ≤ 7 throughout, and whose world x clears every planet_approach column lit during that life (`Level1Director.laser_column_schedule()`: 10.0 s 200 /
  600 / 1000, 25.0 s 400 / 800, 38.0 s 128 / 384 / 640 / 896 / 1152, 55.0 s 300 / 700 / 1100, 78.0 s 150 / 550 / 950, 98.0 s 450 / 850) by `28 + body radius`. Candidate window
  **55–70 s** (measure; the task picks the time and x and records the measured peak).
- **One Hacker Frigate** (`b.hacker_frigate().at(±400, -180)`) in a later wave whose life (spawn + `engage_seconds` 9.0 + measured exit) does not overlap the jammer's life (the
  "never Hacker next to a jammer" rule) and keeps the count ≤ 7. Candidate window **after the jammer has drifted out, before 95 s**.
- Both count as specialists in the frozen 2.5× gate. Pin them as `EXPECTED_PH9` in `test_level1_specialist_spawns.gd` (section, wave trigger, offset, scene), like `EXPECTED_PH8`.

Rows: `test_level1_specialist_spawns.gd` stays green with `EXPECTED_PH9` (peak ≤ 7 of 7.5 in planet_approach, unchanged elsewhere); a boundary row shows the jammer moved onto a lit column
fails the column-clearance check (extend `test_ph8_static_members_clear_every_lit_column` to Ph9 statics); guard rows in `test_engagement_deadline.gd`: no jammer (any variant), Hacker,
Disruptor or EMP zone in an `ENEMIES_CLEARED` section, and no sector jammer or EMP zone in any Assault section; an attack-in-budget replay
(`tests/helpers/level1_slice_replay.gd`, 16×) shows the level-1 Hacker reaches PULSE before its budget expires when the player fires homing rockets, and the jammer locks a player
parked inside its field.

### 2.18 Gate time

GUT was 212.4 s at the Ph8 close (2634 tests), 27.6 s under the 240 s ceiling. Allotments (new GUT seconds per task): t1 2.0, t2 0.5, t3 0.8, t4 2.5, t5 2.0, t6 0.5, t7 2.5, t8 4.0
(includes the Hacker's corridor exit probe, memoised through `ph9_exit_keys.gd`), t9 2.5, t10 0.6, t11 0.8, t12 0.2, t13 1.0, t14 2.5, t15 0 = **22.4 s**, so the phase ends ≤ 235 s.
Every task measures before / after with `scripts/gate-time.sh` and adds a row to the `tests/README.md` → Gate time table. Overruns are fixed by sharing scenarios, the 8× / 16× clock
or memoisation, never by cutting an assertion; a task that would take GUT past 238 s stops with `Result: ESCALATE`.

### 2.19 Numbers and where they come from

| Value | Start | Source |
|---|---|---|
| Stabilisation local / pulsed / sector | 0.75 / 0.75 / 1.25 s | Judgement (no source gives a grace delay) |
| Jammer radius local / pulsed / sector | 240 / 300 / 640 px | Judgement: 480 px crossed in ~1.1 s at 420 px/s; sector ≈ half the 1280 px view |
| Pulsed cycle | 0.8 / 3.0 / 2.5 s | Ph6 anomaly cycle shape; judgement |
| Jammer HP local / pulsed / sector | 140 / 160 / 260 | Ph8 structures (shield generator 120, power source 150) |
| Timed lock: EMP / Disruptor | = EMP seconds (2.0) / 1.5 s | Ph7 `emp_mine.tscn`; finding F2 (1.0–1.75 s band) |
| Hacker held range OS / Assault | 720 / 520 px | above the corvette's 620 / 460 |
| Hacker arcs | 0.18 / 0.30 rad/s, reversal 3–6 s | judgement; corvette 0.22 rad/s, 4–7 s |
| Hacker telegraph / pulse / cooldown | 0.9 / 1.6 / 6–8 s | judgement; corvette salvo telegraph 0.7 s; finding F9 (gated) |
| Hijack range / dart speed / claim cap | 650 px / 900 px/s / 3 | judgement; `homing_count` 3 |
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
7. **t7** The Jamming Structure, three variants; seekers and the corvette respect it (§2.8, §2.9). After t5 (both edit `enemy_rocket.gd`; t5 already follows t1 and t4).
8. **t8** The Hacker Frigate shell, movement, Assault life, hub idle (§2.10). After t7 (shared roster gate files).
9. **t9** The Hijack Pulse: TELEGRAPH / PULSE, darts, claims (§2.11). After t8 and t4.
10. **t10** The Disruptor variant (§2.12). After t9.
11. **t11** The EMP zone (§2.13). After t5.
12. **t12** Art (§2.14). After t10 and t11.
13. **t13** Hub placement (§2.16). After t9 and t11 (and t7).
14. **t14** Level 1 placement (§2.17). After t9.
15. **t15** Docs, roster, dossier, phase record (§2.20). After everything.

## 4. Test plan

The rows live with their design sections so each task sees them: §2.2 (lock), §2.3 (tells), §2.4 (missile lifetime), §2.5 (retarget hook), §2.6 (EMP), §2.7 (EMP Blast), §2.8 / §2.9
(jammer and respect), §2.10 (Hacker movement), §2.11 (hijack pulse), §2.12 (Disruptor), §2.13 (EMP zone), §2.14 (art), §2.15 (roster gates), §2.16 / §2.17 (placement). New files:
`test_player_ability_lock.gd`, `test_player_ability_lock_tells.gd`, `test_homing_missile_lifetime.gd`, `test_seeking_ordnance.gd`, `test_enemy_emp.gd`, `test_emp_blast_module.gd`,
`test_jamming_structure.gd`, `test_hacker_frigate.gd`, `test_hijack_pulse.gd`, `test_emp_zone.gd`, `test_ph9_sprites.gd`, helper `tests/helpers/ph9_exit_keys.gd`. Extended: `test_hazards.gd`,
`test_emp_pulse.gd`, `test_player_boost_disruption.gd`, `test_player_bullet_lifetime.gd`, `test_missile_corvette.gd`, `test_enemy_bullet_lifetime.gd`, the roster gates,
`test_base_enemy.gd`, `test_enemy_dual_mode.gd`, `test_sector_hub_patrol.gd`, `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd`. Boundary cases named in the sections:
the T+44 / T+45 unlock, the radius ± 1 px rows, the cap of 3, the 650 px reach, the arming clearance, the column-clearance boundary, the 2-pulses-per-life budget boundary.

## 5. Risks

- **Unfair hijack.** Three turned rockets at once. Mitigation: 380 px/s (below the Open Space cruise, just above the Assault fighter), 1.6 rad/s, 2.5 s, 18-damage blast, 0.5 s
  i-frames, shoot-down, and the dodge rows (§2.5, §2.11). Not play-tested.
- **Player blast radius.** `PlayerBase`, both ship scripts and `RocketState` are touched by t1, t2, t5; every player test is in range. The unlocked path is an early return and the rows
  pin bit-identity with no hazard.
- **Homing missiles change in Open Space** (they start working away from the origin, t3) and in fields. Owner choice 6.
- **Enemy EMP freezes the Assault budget** (P1). Bounded to 5 s by placement rules; documented.
- **The hub minefield stuns enemies** once placed EMP mines reach them (owner choice 3).
- **Gate time** 22.4 s of 27.6 s headroom.
- **Pulsed-field edge cases** (stabilisation starts when the field goes QUIET) can surprise a player who never left the circle; the QUIET outline and the chip fill show it.

## 6. Out of scope

| Item | Where | Why |
|---|---|---|
| Jammer-linked turret groups (`TurretGroup.add_power_provider`) | Ph20 | roadmap; the hub jammer is placed beside the site only |
| Hacker squad tactics, sniper / hacker mark-and-flank | Ph14 | squad communication |
| Disruptor placement; jammer / hacker numbers by difficulty | Ph13 / Ph16 | encounters and tiers |
| Audio (lock, hijack, EMP) | Ph17 | no audio pipeline; EventBus seams built here |
| A ship-mounted EMP weapon (Carrier anti-approach pulse) | Ph10 / Ph18 | first user is the Carrier; `EmpPulse` is ready |
| EMP on structures and legacy enemies (gunship, bonus drone, station) | Ph10 / Ph11 | reworked there; the EMP Blast keeps today's stun for them |
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
| R9.9 counterplay | t7 (destroy it with primary fire, fly out) |
| R9.10 local / sector / pulsed | t7 |
| R9.11 Hacker role / size | t8, t12 (96×96) |
| R9.12 movement, outside the route / easiest angle | t8 |
| R9.13 hijack in flight and newly launched | t4, t9 |
| R9.14 Hijack Pulse control projectile | t9 (`HijackPulse` dart) |
| R9.15 tell: visual, indicator, audio | t4 (rocket accent, bracket), t9 (dish, light, tether), t2 (audio seam); audio itself Ph17 (owner choice 4) |
| R9.16 base Hacker seekers only; variant decided | t9; Disruptor t10 (not placed) |
| R9.17 counterplay | t9 (kill source, telegraph cancel, LOS, hold fire), t4 (shoot-down, lure) |
| R9.18 Assault clamp | t8 (view clamp, budget, exit), t7 (jammer drift, anchoring) |
| R9.19 EMP Pulse weapon | t5 (`EmpPulse` targets), t11 (EMP zone); ship-mounted Ph10 / Ph18 |
| R9.20 EMP zones | t11, t13 |
| R9.21 Ph7 hand-over | t5 (real player effect, enemies, seekers, mines), t6 |
| R9.22 Assault waves + hub ambient | t13, t14 |
| R9.23 own art | t12 |
| R9.24 tests both modes | every task's rows (both harnesses; both real ship scenes) |
| R9.25 design checklist | t8 / t9 rows (approach from behind = break-off; boost away = range hold; off-screen = LOS rule), t15 records it in `ENEMY.md` |
