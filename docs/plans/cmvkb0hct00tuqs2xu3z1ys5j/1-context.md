# Context — t5 boost disruption on both player ships

Builds epic plan `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.6 (approved) under the §2.17 gate budget (t5: 1.5 s).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/entities/player_base.gd` | `PlayerBase`: shared player state, `hazard_speed_factor()` (Ph6, "read, never cached") | Gets the hook: signal, constant, `apply_boost_disruption`, `boost_efficiency`, `cruise_speed`, `_step_disruption`, the ring |
| `open_space/scenes/entities/player/player_ship.gd` | `OpenSpacePlayerShip`; `_physics_process` (l.202), `_step_boost` (l.380-466), Drive branch l.409-415, default press l.421-434, sustain l.440-455 | Efficiency guards before every spend; disrupted boost speed; sustain stop |
| `global/ship_modules/engine_boost_module.gd` | Boost Drive: `can_activate()` l.55, `try_activate()` l.61 (sets `velocity = dir * _BOOST_SPEED`), `tick()` eased lerp `_BOOST_END_SPEED..._BOOST_SPEED` l.97 | Efficiency guard in `try_activate` (Assault H path); burst speeds by the excess rule |
| `assault/scenes/player/states/dash_state.gd` | `start_state_transition` l.43 (warp branch before the cooldown refusal), `_execute_warp` l.60 (`_WARP_DISTANCE` 120), `process_physics` l.124 (`dash_speed` 350, lateral `move_speed` 180, × hazard factor) | Refusal below the floor; roll speed by the excess rule; warp distance × efficiency |
| `assault/scenes/player/states/move_state.gd` | No `class_name`; `move_speed` 360 (not overridden in `player_fighter.tscn`) | Assault `cruise_speed()` reads it by node path `MovementStateMachine/MoveState` |
| `assault/scenes/player/player_fighter.gd` | `AssaultPlayer._physics_process` l.72 (dialog / knockback early returns), `_input` H loop l.129 | Calls `_step_disruption`; overrides `cruise_speed()` |
| `open_space/scenes/gui/boost_bar.gd` | `BoostBar`, `_fill_color()` pure helper l.70, redraws on meter signals | Violet tint + flicker while disrupted |
| `global/statemachine/state_machine.gd` | `change_state` is synchronous on `state_transition`; `_process` drives `process_physics` | A refused dash emits `transition_state` (as the cooldown does) and never enters `DashState` |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `PlayerBase.hazard_speed_factor()` | The "read where used, never cached, no export written" pattern the efficiency follows |
| `BoostMeter.step()` | The hand-steppable clock seam `_step_disruption(delta)` copies |
| `tests/integration/test_player_hazards.gd` | Real `player_ship.tscn` / `player_fighter.tscn` set-up with `set_physics_process(false)`, hand ticks at `D = 1/60` |
| `tests/integration/test_open_space_boost_verb.gd` | `SaveSandbox` + `ShipModuleState` snapshot pattern for equipping the real Boost Drive; the H-press `InputEventAction` |
| `WarpModule.apply()` | Sets `warp_module_active` on the fighter |

## Conventions that constrain this
- Clocks are accumulated delta; no `Timer`, no `create_timer` (epic "For every task").
- Signals declared with their arity (`test_signal_emit_arity.gd` sweeps self-emits).
- A shared component read must not alter any existing row: efficiency 1.0 must leave every speed **bit-identical** (`floor + (s − floor) × 1.0` is not guaranteed to equal `s` in floats, so the helper short-circuits at 1.0).
- `ShipTurnController` is the only writer of the Open Space ship's `rotation` — the ring is a child `Line2D`, its own `rotation` only.
- No PNG for the ring (plan §2.6); per-frame prints behind `OS.is_stdout_verbose()`.
