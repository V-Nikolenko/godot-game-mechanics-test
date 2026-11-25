# t1 — Inside a jamming field the player cannot fire H abilities or K rockets, and gets them back a moment after leaving

Builds the epic plan's §2.1 / §2.2 / §2.18 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`, approved revision 3). This file is the task-level build
plan: it fixes what §2.1 / §2.2 leave open (field names, the edge-signal mechanics, how each row is driven headless) and the order of work. It does
not re-decide the design. Context: `1-context.md`.

## Problem
Today nothing can stop the player's special abilities. Phase 9's jammers, EMP and the Disruptor all need one hook that switches off the H key
(every active ship module) and the K key (both rocket types) for a while, and gives them back a moment after the player leaves a jamming field,
while movement, boost, dash, warp and the main gun keep working exactly as before. No enemy uses the hook yet; this task builds it and pins it.

## Design

### `PlayerBase` (`global/entities/player_base.gd`), beside the Ph7 disruption
```
signal ability_lock_changed(locked: bool)   # edges only
signal ability_press_refused()

const LOCK_CLOCK_EPSILON: float = 1e-6

var _in_field: bool = false          # sampled inside a lit jammer field on the last lock tick
var _field_stabilise: float = 0.0    # that field's stabilise_seconds (largest of the fields containing the ship)
var _stabilise_left: float = 0.0
var _stabilise_total: float = 0.0
var _timed_left: float = 0.0
var _lock_reported: bool = false     # the state last announced by ability_lock_changed
```
- `apply_ability_lock(seconds: float, _source: Node) -> void`: `seconds <= 0.0` → return. `_timed_left = maxf(_timed_left, seconds)`, then
  `_report_lock()`. The source is unused in t1 (kept for the signature later tasks call; DECISIONS names it).
- `abilities_locked() -> bool`: `_in_field or _stabilise_left > 0.0 or _timed_left > 0.0`.
- `ability_lock_fill() -> float`: `1.0` if `_in_field or _timed_left > 0.0`; else `_stabilise_left / _stabilise_total` when both > 0; else `0.0`.
- `allow_ability_press() -> bool`: `true` when not locked; otherwise `ability_press_refused.emit()` and `false`.
- `static func _tick_clock(x: float, delta: float) -> float`: `x -= delta; return 0.0 if x <= LOCK_CLOCK_EPSILON else x`. Static so the boundary row
  can call it without a ship.
- `_step_ability_lock(delta: float) -> void`:
  ```
  if Hazards.count() == 0 and not abilities_locked():
      return
  var info := Hazards.jammer_at(global_position)
  if info != null:
      _in_field = true; _stabilise_left = 0.0; _stabilise_total = 0.0; _field_stabilise = info.stabilise_seconds
  elif _in_field:                                   # the exit tick: no decrement
      _in_field = false; _stabilise_left = _field_stabilise; _stabilise_total = _field_stabilise
  else:
      _stabilise_left = _tick_clock(_stabilise_left, delta)
  _timed_left = _tick_clock(_timed_left, delta)
  _report_lock()
  ```
  `_tick_clock(0.0, delta)` returns 0.0, so the clocks that are not running stay at 0.
- `_report_lock()`: `var now := abilities_locked(); if now != _lock_reported: _lock_reported = now; ability_lock_changed.emit(now)`. Called from
  `_step_ability_lock` and `apply_ability_lock`, so a timed lock announces itself at the call (like `apply_emp`'s `emp_changed(true)`), a field on the
  first tick sampled inside, and each edge fires exactly once. `EventBus.player_ability_lock_changed` is t2's, not added here.
- `_step_disruption(delta)`: first line becomes `_step_ability_lock(delta)` (then `_step_emp(delta)` as today). Both ships already call
  `_step_disruption` first in `_physics_process`, so no ship's physics tick changes.
- With no hazard and no lock the step is one `count()` call and one bool expression, and no state is written: every existing player test stays
  bit-identical.

### Hazards
- `HazardInfo.stabilise_seconds: float = 0.0` (new field). The `disables_abilities` comment becomes "true while a jammer field is lit (Ph9); the
  player samples it through `Hazards.jammer_at()`"; `&"jammer"` joins the `kind` comment list.
- `HazardField`: `@export var disables_abilities := false`, `@export var stabilise_seconds := 0.0`; `_refresh_info()` writes
  `_info.disables_abilities = disables_abilities and active` and `_info.stabilise_seconds = stabilise_seconds`. Defaults keep every Ph6–Ph8 field
  bit-identical (`disables_abilities` was never written before, so it stays false).
- `Hazards.jammer_at(pos: Vector2) -> HazardInfo` (static, no allocation): loop `_nodes` like `penalty_at()`; keep the info with
  `disables_abilities and contains(pos)` and the largest `stabilise_seconds` (the first one on a tie); return it or null.

### The three seams (only places the lock is read)
- `OpenSpacePlayerShip._input`: after `if not event.is_action_pressed("use_ability"): return`:
  `if not allow_ability_press(): get_viewport().set_input_as_handled(); return`, then the module loop as today.
- `AssaultPlayer._input`: the same two lines after `if DialogPlayer.is_active: return` (a press during a dialog is still ignored, not refused).
- `RocketState._on_action`: the `special_weapon` branch keeps `cooldown_timer.is_stopped()` as its condition and, inside it, before `_launch()` and
  `cooldown_timer.start()`: `if actor.has_method(&"allow_ability_press") and not actor.allow_ability_press(): return`. A press during the cooldown never
  reaches the lock (no refusal, no feedback). `switch_weapon` is untouched. `WeaponState` is not edited.

## Build sequence
1. **Tests first.** `tests/unit/test_hazards.gd` gains the `jammer_at` rows; `tests/unit/test_hazard_field.gd` gains one export-mirror row; new
   `tests/integration/test_player_ability_lock.gd` (rows below). Run them: they fail to parse/compile against the current API (red).
2. `HazardInfo.stabilise_seconds`, `HazardField` exports, `Hazards.jammer_at` → the unit rows go green.
3. `PlayerBase` lock + `_step_disruption` call → lock / timing / signal rows go green.
4. The three seams → H / K rows go green.
5. Full suite through `scripts/gate-time.sh` (before figure measured on a clean `git archive HEAD` copy), `scripts/check-test-leaks.sh`, then
   `bash /agent/verify.sh`.
6. Docs: `updating-project-docs` (global.md: `PlayerBase` lock API, `Hazards.jammer_at`, `HazardField` exports; PROJECT.md conventions line), the
   `tests/README.md` gate-time row, `DECISIONS.md` "Phase 9, built in t1".

## Test plan

### `tests/unit/test_hazards.gd` (new rows, existing rows untouched)
Fixture: a `HazardField` built from props before entering the tree (`kind &"jammer"`, `radius` 240, `avoid_weight` 0, `disables_abilities` true,
`stabilise_seconds` 0.75), freed by `add_child_autofree`.
- `test_jammer_at_is_null_with_no_hazard` (asserts `Hazards.count() == 0` first).
- `test_jammer_at_ignores_a_field_that_does_not_disable_abilities` (a gravity well with a pull, same radius, centre point → null).
- `test_jammer_at_finds_the_field_at_its_radius_and_not_one_px_beyond` (`contains` boundary, `<=`).
- `test_jammer_at_returns_the_larger_stabilise_of_two_overlapping_fields` (0.75 and 1.25 overlapping at the point → the 1.25 info; just inside only
  the smaller one → that one).
- `test_jammer_at_is_null_while_a_pulsed_field_telegraphs_or_is_quiet` (cycle 1.0 / 1.0 / 1.0, ticked by hand at 0.25 s: null in TELEGRAPH, the
  info in ACTIVE, null in QUIET).
### `tests/unit/test_hazard_field.gd` (one new row)
- `test_disables_abilities_is_written_only_while_active_and_stabilise_always` (defaults false / 0.0; cycling field: false in TELEGRAPH and QUIET,
  true in ACTIVE; `stabilise_seconds` mirrored in every phase).

### `tests/integration/test_player_ability_lock.gd` (new; intent tests)
Shape of `test_player_boost_disruption.gd`: both real player scenes, own `_physics_process` off, every step hand-ticked at `D = 1/60`, `MODES =
["open_space", "assault"]` through `use_parameters`. Every ship is parented in its own `box` (`Node2D`) so module visuals and the warp ghost land in
something the test frees. The jammer is a plain `HazardField` (the unit fixture above), built from props **before** it enters the tree. `before_all` /
`after_all`: `SaveSandbox` + a snapshot of all four `ShipModuleState` slots (equipped and unlocked); `before_each` clears every slot's equipped id, so
no ship starts with a module from the live profile. `after_each`: release every pressed action, `DialogPlayer.is_active = false`,
`Engine.time_scale = 1.0`, `randomize()`. Modules are put on a ship by `ShipModuleBase.create(id)` + `apply(p)` + `p._module_pool[id] = mod`
(the exact dictionary both H loops walk), except the Open Space Boost Drive Shift row, which equips through `ShipModuleState` as the Ph7 file does.

**Timing (both ships; driven through `_step_disruption(D)` unless stated)**
| Test | Asserts |
|---|---|
| `test_the_signals_are_declared_with_their_arity` | `ability_lock_changed` one `TYPE_BOOL` arg, `ability_press_refused` none (`get_signal_list()`). |
| `test_locked_on_the_first_tick_inside` | outside (radius + 1 px): a tick leaves it unlocked; at exactly `radius` the first tick locks; `ability_lock_changed` == `[true]`; fill 1.0. Before the first tick inside, unlocked (sampled by the tick). |
| `test_unlocks_exactly_45_ticks_after_the_exit_tick` | exit tick T (ship moved out): locked at T, T+1 … T+44; unlocked at T+45; signals `[true, false]`; fill 1.0 at T, strictly decreasing each tick, 0.0 at T+45. |
| `test_re_entry_restarts_the_delay` | exit at T, re-enter at T+20 (fill back to 1.0, still locked, no extra signal), exit at T2: locked at T2+44, unlocked at T2+45; signals `[true, false]`. |
| `test_a_pulsed_field_locks_only_while_active` | cycle 1.0 / 2.0 / 1.0, field then ship ticked each step: never locked while the field reads TELEGRAPH (first pass); locked on the first ACTIVE tick; with Q the tick the field turns QUIET: locked at Q+44, unlocked at Q+45. Edges are read from `field.phase()`, never from a tick count (the field's own cycle clock drifts by a tick at 1/60). |
| `test_a_freed_field_starts_the_delay` | inside and locked; `remove_child` + `free()` the field (`Hazards.count() == 0`); the next tick is the exit tick: locked through +44, unlocked at +45. |
| `test_a_timed_lock_ends_on_tick_90_with_no_stabilisation` | `apply_ability_lock(1.5, null)`: `[true]` at the call; locked after ticks 1 … 89, unlocked after tick 90, fill 1.0 then 0.0 (never a stabilisation fraction); `[true, false]`. |
| `test_timed_locks_longest_wins_and_never_add` | 1.5 then 0.5 at tick 30: still locked after tick 89, unlocked after 90; 1.0 then 2.0 at tick 30: unlocked after tick 150, not 60 or 180; one `true`, one `false` each. |
| `test_zero_or_negative_seconds_is_no_lock` | `apply_ability_lock(0.0)` / `(-1.0)`: unlocked, no signal. |
| `test_a_field_and_a_timed_lock_never_shorten_each_other` | (a) timed 1.5 inside a field, exit at tick 30: unlocked after tick 90, not 75; (b) timed 0.5 inside a field, exit at tick 20: unlocked after tick 65, not 30. One `true`, one `false` each. |
| `test_tick_clock_reaches_exactly_zero_on_tick_90` (no ship) | `PlayerBase._tick_clock` from 1.5, 90 steps → exactly `0.0`; 2.0, 120 steps → `0.0`; control: plain `x -= D` from 1.5, 90 steps is `> 0.0` (the premise the epsilon exists for). |
| `test_the_ships_own_physics_tick_steps_the_lock` (anti-inert) | through the ship's own `_physics_process(D)` only: locked on the first tick inside, unlocked 45 ticks after the exit tick. Assault: also with `DialogPlayer.is_active` true (the dialog's early return comes after the clock). |

**H and K (both ships)**
| Test | Asserts |
|---|---|
| `test_every_active_module_is_in_the_spend_table` | the module ids whose script source declares `func try_activate(` (every non-empty id in `ShipModuleState.SLOT_MODULES`) equal the test's `_SPENT` table keys (the 10 above), so a new active module fails here until it gets a readable probe. |
| `test_h_is_refused_while_locked_with_nothing_spent_for_every_module` | for each id, a fresh boxed ship in a lit field, ticked once: an H press pushed through `get_viewport().push_input()` (the engine's own dispatch, one ship in the tree at a time) leaves the module's probe "not spent", emits `ability_press_refused` once, and `is_input_handled()` is true. Out of the field 45 ticks later, the same press is accepted (probe "spent", handled). Exception: the Open Space Boost Drive, which H never fires (`is_open_space_boost_verb()`): refused and handled while locked; unlocked, H still neither fires it nor is handled (unchanged). Probes: `_active` (trajectory_calc, final_resort), `_cooldown_left > 0` (emp_blast, plasma_nova, overheat_nullifier, ai_targeting), `_active or _cooldown_left > 0` (parry), `_passive_lockout > 0` (cockpit_heal), a pre-added temporary shield gone (shield_overload), `engine_boost_active` (engine_boost). Preconditions: a dummy `enemies` node 300 px ahead only for ai_targeting; heat 50 for overheat_nullifier. Cleanup per id: `mod.remove(p)`, free new tree-root children (plasma_nova's flash), free the box. |
| `test_h_boundary_refused_on_t44_accepted_on_t45` | EMP Blast equipped; exit tick T; a press after tick T+44 is refused (cooldown 0, refusal signal); after T+45 accepted (cooldown 15). |
| `test_a_locked_press_with_no_active_module_is_still_handled` | locked ship with no module: H handled + refusal; unlocked control: H not handled, no refusal (the press is not consumed when nothing could use it). |
| `test_k_is_refused_while_locked_for_both_rocket_types` | `RocketState._on_action("special_weapon")` while locked, warhead and homing: `CooldownTimer` stopped, no rocket child added, one refusal each; after the unlock the same call launches (3 rockets, timer running). |
| `test_k_during_the_cooldown_is_not_a_refusal` | unlocked launch, a second press during the cooldown: no refusal, no launch. Then locked with the cooldown still running: no refusal either (cooldown is checked first). |
| `test_switch_weapon_still_switches_while_locked` | `_on_action("switch_weapon")` while locked toggles `get_type()` and emits `weapon_changed` once. |
| `test_module_cooldowns_keep_ticking_while_locked` | EMP Blast with `_cooldown_left` 10.0, `apply_ability_lock(3.0)`, 180 ticks of the ship's own `_physics_process`: unlocked after tick 180 with `_cooldown_left` ≈ 7.0 (1e-6). |

**Never affected (both ships, two ships stepped in lockstep so `Input`'s just-pressed / just-released frames are the same for both)**
| Test | Asserts |
|---|---|
| `test_primary_fire_is_identical_inside_a_lit_field` | ships A (no field) and B (field on it), 1200 px apart, one per-ship `enemies` dummy 300 px ahead for the beam. For each of the five `UpgradeState.ALL_IDS` modes (`ws._active_id` set directly, no save write): `Input` "shoot" held for ticks 0–59 and released at 60, 120 ticks of `_step_disruption(D)` + `ws._physics_process(D)` per ship, `seed(tick)` before each ship's weapon tick. Recorded per ship: every bullet entering `WeaponState` (tick, `damage`, `rotation`) and every damage the dummy's `HurtBox` receives (tick, amount). A == B exactly; B locked on every tick; each mode records at least one shot or damage (non-vacuous). |
| `test_movement_is_identical_inside_a_lit_field` | ships A and B at the **same** start, `collision_layer` / `collision_mask` 0 (they never touch), field moved onto B before B's tick and 5000 px away before A's. Open Space: keys turn scheme on both turn controllers, "move_up" + "move_left" held, "boost" (Shift) pressed at tick 10, 60 ticks of the ship's own `_physics_process`. Assault: "move_right" held through `MoveState`, a forward dash at tick 20 (`DashState.start_state_transition("move_up")`), 60 ticks of `_physics_process` + the movement machine's `_process`; plus a warp pair (`WarpModule`) blinking right. `global_position`, `velocity` and `rotation` equal exactly; B locked on every tick. |
| `test_open_space_boost_drive_on_shift_fires_while_locked` | Boost Drive equipped through `ShipModuleState` (3 tanks); locked; `_step_boost(true, true, D)` fires it (`engine_boost_active`, one tank spent). |
| `test_no_hazard_leaves_every_lock_observable_untouched` | `Hazards.count() == 0` asserted; 120 ticks of each ship's own `_physics_process`: `abilities_locked()` false and `ability_lock_fill()` 0.0 on every tick, neither signal emitted; an H press (EMP Blast equipped) is accepted and handled; a K press launches. |

### Boundary cases
- `jammer_at` at exactly `radius` vs `radius + 1` px; the T+44 / T+45 rows (field) and tick 89 / 90 (timed); the epsilon row that fails without the
  epsilon; the T+44 refused / T+45 accepted H press.

## Risks
- **`push_input` in GUT:** it reaches every node with `_input`. Mitigated by one ship in the tree per push (each per-module iteration frees its box
  before the next) and by `use_ability` having no other consumer in the project (`grep`).
- **Accepted-module side effects** (`Engine.time_scale`, the plasma flash on the root, timers): cleaned per iteration; `after_each` resets
  `Engine.time_scale`; no `enemies` node exists during the EMP Blast / Plasma Nova acceptances, so no `SceneTreeTimer` is created.
- **`seed()`** changes the global RNG for later files; `after_each` calls `randomize()`.
- **Gate time:** ~40 ships instantiated and ~2400 hand ticks; estimate ≈ 1.5 s, inside the 2.0 s allotment. If over, the per-module rows share one ship per
  mode (swap `_module_pool` contents) before any assertion is cut.

## Out of scope
- The ship tell, the HUD chip and `EventBus.player_ability_lock_changed` (t2); any jammer enemy (t7); EMP's use of the lock (t5); seekers flying
  straight in a field (t4 / t5).

## As built (2026-11-07)
No production deviation. Test-side changes against the tables above, all from the review (`4-review.md`) or found while running:
- Review findings 1–4 absorbed: the movement row asserts non-vacuity on ship A (boost on tick 10 past cruise, turned, flying; MoveState's 360 px/s until
  tick 20, `DashState` with `velocity.y < 0` from tick 20, the warp blink exactly 120 px); both lockstep rows start with one awaited idle frame; every
  area-effect acceptance asserts no `enemies` node first and the ai_targeting dummy lives in the per-id box; the K row uses a fresh ship per rocket type and
  asserts the cooldown is stopped before each locked press.
- Review finding 7's two optional rows added: `test_leaving_the_inner_of_two_fields_starts_no_delay`, `test_assault_a_locked_press_during_a_dialog_is_ignored`.
  The anti-inert row's Assault dialog case is its own test, `test_assault_lock_clock_runs_through_a_dialog`.
- **No distance assertions in the movement row:** `move_and_slide()` off a physics frame moves by the real frame delta, so a draft that asserted a
  displacement flaked 4 / 20; A == B still holds exactly because both ships move in the same frame. The row asserts velocities instead.
- Every field in the H / K rows lives in the ship's box, so freeing the box per module also unregisters its field.
- Measured: the new file (27 test functions, most run in both ships) takes ≈ 0.85 s on its own.
- **Gate repair outside the plan (attempt 3):** the run's first gate failed on an intermittent exit leak from `tests/helpers/level1_slice_replay.gd`
  (it freed its `WaveManager` before a delayed spawn's timer fired; unrelated to the lock). The helper now counts arrivals before freeing; see
  `DECISIONS.md` (Phase 9, built in t1) and `tests/README.md` → *The third half*.
