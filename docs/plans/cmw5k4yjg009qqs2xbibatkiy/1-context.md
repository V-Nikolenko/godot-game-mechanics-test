# Context — Phase 9 t1: the player-side ability lock

Builds the epic plan's §2.1 / §2.2 (`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`, approved, revision 3). The design is fixed there; this
directory only fixes the choices it leaves open and the order of work.

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/entities/player_base.gd` | `PlayerBase`: components, damage chain, Ph7 boost disruption + EMP (`_step_disruption(delta)` → `_step_emp`) | The lock lives here, beside the Ph7 disruption, stepped at the top of `_step_disruption()` |
| `open_space/scenes/entities/player/player_ship.gd` | `OpenSpacePlayerShip`. `_physics_process` calls `_step_disruption` first; `_input` runs the H module loop (skips `is_open_space_boost_verb()` = Boost Drive) | Seam 1 (H) |
| `assault/scenes/player/player_fighter.gd` | `AssaultPlayer`. `_physics_process` calls `_step_disruption` first (before the dialog / knockback / boost returns); `_input` runs the H loop after a `DialogPlayer.is_active` return | Seam 2 (H) |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` | `RocketState`, child of both ships' `AttackStateMachine`. `_on_action(key_name)` from `MovementController.action_single_press`: `switch_weapon` toggles, `special_weapon` launches 3 warheads or `homing_count` homing rockets as its own children and starts `$CooldownTimer` | Seam 3 (K). `test_ram_corvette.gd` builds one on a bare `CharacterBody2D` actor (no lock API) and calls `_launch_*` directly |
| `assault/scenes/player/states/weapon_state.gd` | `WeaponState`: primary fire, 5 modes from `UpgradeState.ALL_IDS` (`default`, `sniper_shot`, `spread`, `gatling`, `mining_laser`); reads `Input` itself in `_physics_process` | **Not edited.** The primary-fire rows drive it by hand |
| `global/hazards/hazards.gd` | Static registry; `count()`, `around()`, `accel_at()`, `penalty_at()` loop `_nodes` and call duck-typed `hazard_info()` | Gains `jammer_at(pos)` |
| `global/hazards/hazard_info.gd` | Shared description; `disables_abilities` reserved since Ph6 ("no producer or consumer"); `contains(pos, margin)` is centre distance `<= radius` | Gains `stabilise_seconds`; comment updates |
| `global/hazards/hazard_field.gd` | One field script; `_refresh_info()` in `_enter_tree()` and `_physics_process`; cycle TELEGRAPH → ACTIVE → QUIET | Gains exports `disables_abilities`, `stabilise_seconds` (written only while ACTIVE) |
| `global/ship_modules/*_module.gd` | 15 modules; 10 override `try_activate`: `trajectory_calc`, `emp_blast`, `ai_targeting`, `cockpit_heal`, `parry`, `shield_overload`, `final_resort`, `plasma_nova`, `overheat_nullifier`, `engine_boost` | The H-refused rows need one readable "spent" probe per module |
| `assault/scenes/player/movement_controller.gd` | Reads `Input` in `_process` and emits `action_single_press("special_weapon" / "switch_weapon")` | Why the K rows call `RocketState._on_action` directly |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `tests/integration/test_player_boost_disruption.gd` | The test shape: both real player scenes, `set_physics_process(false)`, hand-ticked `_step_disruption(1/60)`, `use_parameters(["open_space", "assault"])`, `_h_press()`, a `box` parent for the warp ghost, `SaveSandbox` + `ShipModuleState` snapshot for the engines slot, an anti-inert row through the ship's own `_physics_process` |
| `tests/integration/test_player_hazards.gd` | Real players inside hazards, `add_child_autofree` + hand ticks |
| `tests/unit/test_hazard_field.gd` | Building a `HazardField` from a props dictionary before it enters the tree; hand-ticking its cycle |
| `tests/unit/test_hazards.gd` | The registry rows the `jammer_at` rows join |
| `PlayerBase.apply_emp` / `_step_emp` | The edge-signal discipline (signal on a start and an end, never on a refresh) |
| `EnemyRocket` `- 1e-6` | The clock-epsilon idiom the plan's `_tick_clock` follows |
| `Viewport.push_input(event)` | Probed in this run (Godot 4.6.3 headless): it clears the viewport's handled flag, dispatches `_input` synchronously to every node in the tree, and `is_input_handled()` afterwards tells whether anything consumed the event. No test in the suite uses it yet |

## Conventions that constrain this
- Ph7 discipline (DECISIONS Ph7): accumulated `delta`, hand-steppable, signal only on a change, an undisturbed path that is a cheap early return so every
  existing player test stays bit-identical.
- Hazards are sampled by the body (Ph6): nothing writes a ship from a hazard; no physics layer.
- Signals declared with their arity (`test_signal_emit_arity.gd` sweeps self-emits).
- `Input.is_action_just_pressed/released` in 4.6 (non-legacy) compare the press/release frame only, not the current state, so inside one synchronous test
  a press or release in one run leaks into a second run of the same frame. Two runs that must see identical input therefore run **in lockstep** (one tick of
  each per loop iteration), never one after the other.
- `push_input` reaches every node in the tree: only one player may be in the tree when an H press is pushed.
- Accepted module side effects that outlive the test must be cleaned: `trajectory_calc` sets `Engine.time_scale` 0.3, `plasma_nova` adds a `CanvasLayer`
  to the tree root, `emp_blast` creates a 5 s `SceneTreeTimer` per enemy in the tree (a leak at exit if the suite ends first).
- GUT gate time: 212.4 s at the Ph8 close; t1's allotment is 2.0 s.
