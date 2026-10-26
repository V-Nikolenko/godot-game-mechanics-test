# t5 — Both player ships can have their boost weakened for a few seconds

Builds epic plan `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.6 and §2.17 (approved). This file does not redesign
them; it fixes the concrete code shape and the test list. Where it says "§2.6", the epic plan wins.

## Problem
Phase 7's pulse mine (t6) and EMP mine (t7) need to weaken the player's boost for a few seconds. Today nothing can: the
Open Space Shift boost, the Boost Drive burst, the Assault barrel-roll dash and the Warp blink all run at full strength
always, and there is no tell for "your boost is weakened". After this task either ship can be handed a disruption
(strength, seconds); while it lasts every boost verb buys less above normal flight (never less than normal flight), below
15 % efficiency the verb is refused with nothing spent, and the ship shows a violet spark ring (and, in Open Space, a
violet flickering boost bar). No mine is built in this task.

## Design

### `PlayerBase` (`global/entities/player_base.gd`)
```gdscript
signal boost_disruption_changed(efficiency: float)
const MIN_BOOST_EFFICIENCY: float = 0.15
var _disruption_strength: float = 0.0   ## live strength, 0 when none
var _disruption_left: float = 0.0       ## seconds left, accumulated delta
var _disruption_clock: float = 0.0      ## drives the ring's flicker only
var _disruption_ring: Line2D = null     ## built lazily on the first disruption
```
- `apply_boost_disruption(strength, seconds)`: clamps strength to 0..1; ignores `strength <= 0` or `seconds <= 0`.
  `_disruption_strength = max(live, new)`, `_disruption_left = max(live, new)` (never stacked). Emits
  `boost_disruption_changed(boost_efficiency())` when the efficiency differs from before the call (start, or a stronger
  one); a longer-only re-apply changes no efficiency and emits nothing. Shows the ring.
- `boost_efficiency()` = `1.0 - _disruption_strength` while `_disruption_left > 0`, else `1.0`.
- `cruise_speed()` virtual, base returns `0.0`.
- `disrupted_speed(speed, floor_speed) -> float` — **additive helper** (not named in §2.6; logged in DECISIONS): returns
  `speed` unchanged when `boost_efficiency() >= 1.0` (bit-identical, so every existing row is untouched), else
  `floor_speed + (speed - floor_speed) * boost_efficiency()`. It is the one implementation of §2.6's excess rule, used by
  the Shift boost, the Drive and the dash.
- `_step_disruption(delta)`: returns if none active; `_disruption_left -= delta`; at `<= 0` zeroes both, hides the ring and
  emits `boost_disruption_changed(1.0)`; otherwise flickers/turns the ring from `_disruption_clock`.
- The ring: a code-built `Line2D` child named `BoostDisruptionRing`, closed, 24 points alternating radius 20/23 px (a jagged
  "spark" ring, no PNG), width 1.5, violet `Color(0.72, 0.4, 1.0)`. Visible only while active; alpha flickers and it turns
  slowly (its own `rotation`, never the ship's). Drawn above the hull (added after the scene's children).

### `OpenSpacePlayerShip`
- `cruise_speed()` returns `max_speed` (read, 420).
- `_physics_process`: `_step_disruption(delta)` first.
- `_ready()`: when the bar exists, `boost_disruption_changed.connect(_boost_bar._on_boost_disruption_changed)`.
- `_boost_speed()` = `disrupted_speed(boost_exit_speed, cruise_speed())`.
- `_step_boost`:
  1. Drive branch: `boost_pressed and boost_efficiency() >= MIN_BOOST_EFFICIENCY and drive.can_activate() and
     (_boost_meter == null or _boost_meter.try_spend_tank())`. The `if drive != null:` / `elif` structure already keeps a
     refused Drive press out of the default branch.
  2. Default press: `boost_efficiency() >= MIN_BOOST_EFFICIENCY` joins the condition after the hold-window floor and before
     the meter check. Start writes `velocity = nose * _boost_speed() * hazard_speed_factor()`, `_speed_ceiling = _boost_speed()`.
  3. Sustain: `if boost_efficiency() < MIN_BOOST_EFFICIENCY` -> no drain, no velocity write, stop exactly as the empty-meter
     stop does (flag off, flame released, rig told). Otherwise unchanged except `_boost_speed()` replaces `boost_exit_speed`.
  4. Cruise, damping, the decay branch and the tail clamp are untouched.

### `EngineBoostModule`
- `try_activate(player)`: after the `_active`/cooldown refusal, refuse when `player.has_method("boost_efficiency") and
  player.boost_efficiency() < PlayerBase.MIN_BOOST_EFFICIENCY` (the Assault H path, which spends nothing first).
- New `_start_speed` / `_end_speed`, set once at activation: `player.disrupted_speed(_BOOST_SPEED, player.cruise_speed())`
  and the same for `_BOOST_END_SPEED` when the player has `disrupted_speed`; otherwise the raw exports. `try_activate()`
  writes `_start_speed`; `tick()` lerps `_end_speed .. _start_speed`. At efficiency 1.0 these equal the exports exactly.
- `can_activate()` keeps its expression; its comment now says the player-side efficiency guard is the caller's, checked
  before the spend in `_step_boost()`.

### `DashState`
- `start_state_transition`: after the timer/key checks and **before** the warp branch, if the actor's
  `boost_efficiency()` is below the floor: trace (verbose only), `state_transition.emit(transition_state)`, return — the
  cooldown's refusal shape; refuses both roll and warp.
- `process_physics`: roll speed `actor.disrupted_speed(dash_speed, move_speed)` (when the actor has it), then × the hazard
  factor as today. Lateral steering unchanged.
- `_execute_warp`: distance `_WARP_DISTANCE * efficiency` (`1.0` exactly when undisrupted).

### `AssaultPlayer`
- `cruise_speed()` = `MovementStateMachine/MoveState`'s `move_speed`, read per call (0 if the node is missing).
- `_physics_process`: `_step_disruption(_delta)` first, before the dialog return, so a disruption's clock runs in a dialog too.

### `BoostBar`
- `_efficiency := 1.0`, `_flicker_clock`; `_on_boost_disruption_changed(efficiency: float)` stores it, resets `modulate`
  when back to 1, `queue_redraw()`.
- `_fill_color()` returns `_FILL_COLOR_DISRUPTED` (violet) when `_efficiency < 1.0`, else today's tier colours.
- `_process(delta)`: only while disrupted, flickers `modulate.a` from the accumulated clock (no Timer).

### Alternatives rejected
- Scaling the whole boost speed by efficiency (`700 × 0.4 = 280`): a disrupted boost would brake the ship below cruise; §2.6
  chose the excess rule.
- Writing the exports (`boost_exit_speed`, `dash_speed`) for the duration: forbidden by §2.6 ("no export is ever written") and
  would race the hazard factor's own reads.
- A `Timer` for the duration: forbidden (accumulated delta only), and a hand-steppable seam is what the tests drive.

## Build sequence
1. Write `tests/integration/test_player_boost_disruption.gd` (all rows below); watch it fail.
2. `PlayerBase` hook + ring; both ships' `cruise_speed()` and `_step_disruption` calls.
3. `OpenSpacePlayerShip._step_boost` guards and speeds; `EngineBoostModule`; `DashState`.
4. `BoostBar` tint + flicker and its connection.
5. Gate-time after, `verify.sh`, DECISIONS "built in t5", `tests/README.md` Gate time row, docs.

## Test plan (`tests/integration/test_player_boost_disruption.gd`, new, hand-ticked, no await)
Both real scenes, `set_physics_process(false)`, `D = 1/60`, set up as `test_player_hazards.gd`; Drive rows equip the real
module through `ShipModuleState` under `SaveSandbox` with the snapshot/restore of `test_open_space_boost_verb.gd`. Shared rows
are parameterised on a mode label (`"open_space"`, `"assault"`).
- **Clock (both):** default 1.0; after `apply_boost_disruption(0.6, 2.5)` and 149 `_step_disruption(D)` ticks efficiency is
  0.4, and it is 1.0 by tick 151 (± 1 tick).
- **Never stacked (both):** `(0.6, 1.0)` then `(0.3, 3.0)` -> 0.4 at 2.0 s (strongest + longest), not `0.4 × 0.7`; and
  `(0.3, 1.0)` then `(0.6, 0.5)` -> 0.4, still live at 0.9 s.
- **Signal (both):** `get_signal_list()` declares one arg; a start emits `[0.4]`, a stronger re-apply emits `[0.1]`, the end
  emits `[1.0]`; a longer-only re-apply emits nothing.
- **Boundary (both):** strength 0 or seconds 0 does nothing (efficiency 1.0, no emit).
- **The clock is wired (review r1 B1, anti-inert):** on both ships a 0.1 s disruption ends when only the ship's own
  `_physics_process(D)` is called (never `_step_disruption` by hand); the Assault fighter's clock also runs with
  `DialogPlayer.is_active = true` and during an active knockback (both early returns come after the call).
- **`cruise_speed()`:** 420 / 360, and it follows `max_speed` / `MoveState.move_speed` when they change (read, never cached).
- **OS default boost:** at 0.6, `_step_boost(true, true, D)` -> speed 532 ± 1; 10 sustain ticks keep 532 ± 1 and leave
  `charges` equal to an undisrupted twin's (normal drain). At 0.9 -> refused: velocity and `charges` unchanged, `_boosting`
  false and no hold window left behind (`_boost_hold_left == 0`). **Boundary:** at strength 0.85 (efficiency 0.15, the floor
  is inclusive) the boost starts; at 0.86 (0.14) it is refused.
- **OS sustain cut:** a running boost, then `apply_boost_disruption(1.0, 1.0)` -> on the next tick `_boosting` is false,
  `charges` unchanged on that tick, and the velocity's *direction* is not re-asserted along the (turned) nose (its length may
  fall to the decaying ceiling, as on the empty-meter stop); control: an undisrupted twin's sustain does re-assert along it.
- **OS Boost Drive:** equipped, 0.9 -> `charges` and `tanks` unchanged, `engine_boost_active` false, `_boosting` false (did not
  fall into the default branch). 0.6 -> one tank spent, start 852 ± 1, tick the module to its end: last speed 452 ± 1, minimum
  over the burst ≥ 420.
- **Assault dash:** at 0.6 `process_physics` gives 248 ± 1 (≥ `move_speed` 180); at 0.9 `start_state_transition("move_right")`
  leaves `dashing_timer` stopped and the machine not in `DashState`; control: undisrupted the same call enters the dash.
- **Warp:** `WarpModule.apply()`; at 0.6 the blink moves 48 ± 0.5 px; at 0.9 it moves 0 px; control: undisrupted 120 px.
- **H-key Drive:** `_input(h_press)` refused at 0.9 (`engine_boost_active` false); at 0.6 speed 816 ± 1.
- **Controls:** OS thrust from rest for 30 ticks and the ceiling clamp of a 900 px/s velocity equal an undisrupted twin's
  bit-for-bit; Assault `MoveState.move()` velocity equals 360 while disrupted.
- **Readability:** the ring is visible while active and hidden after, on both ships; the Open Space `BoostBar._fill_color()`
  is violet while disrupted and back to the tier colour after, with `modulate` reset to white (both through the real signal).
- Emitted values are compared with `assert_almost_eq`.
- Every existing `test_open_space_boost_verb.gd` / `test_open_space_boost_wiring.gd` / `test_player_hazards.gd` /
  `test_boost_bar.gd` row passes unchanged.
- Gate time measured before (GUT `Time` 204.62 s, 2165 tests) and after, both reported.

## Risks
- **Float drift at efficiency 1.0** would move existing pinned rows: mitigated by `disrupted_speed()`'s short-circuit and the
  warp's `× 1.0`.
- **The Drive's speeds are now read at activation** instead of every tick: a test that edits `_BOOST_SPEED` mid-burst would
  differ. No test does (`grep _BOOST_SPEED tests/` is empty).
- Gate time: ~35 hand-ticked rows on two scene instantiations each, estimated well under 1.5 s.

## Out of scope
The pulse mine (t6), the EMP hook `apply_emp` / `EmpPulse` (t7), any mine art (t9), docs beyond the hook's own entries (t16).

## Revision 1 (after review round 1)
- B1: added the "clock is wired" rows (both ships through their own `_physics_process`; Assault under a dialog and a knockback).
- N1 line numbers fixed in `1-context.md`; N2 the sustain-cut row asserts direction only; N3 0.86 refused paired with 0.85, emitted
  values compared approximately; N4 no hold window after a refused press; N5 bar `modulate` reset asserted; N6
  `test_open_space_boost_wiring.gd` named; N7 the before measurement is recorded above.
