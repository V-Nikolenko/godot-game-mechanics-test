# Context — t8: Carrier hangars (doors, launches, caps, emergency deployment)

Epic `cmug23oo90029m52wae4clve0` (Phase 10), plan §2.8 (with §2.6 shell, §2.7 PANIC hook, §2.9 lights, §2.16 numbers).
Builds on t6 (`docs/plans/cmwafsrb700afqs2yd3qqvvrb/`) and t7 (`docs/plans/cmwafsrb900ajqs2yb5jcl5ij/`).

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/carrier/carrier.gd` | Armoured root; owner group `carrier_<id>`; `_build_weapons()` builds mounts and binds the ring to the brain; `died` → `cancel_pulse` | t8 builds the `CarrierHangars` here (it knows the owner group) and hands it to the brain; adds `hangars()` accessor |
| `assault/scenes/enemies/carrier/carrier_brain.gd` | Phases; `tick()` = movement then `_tick_weapons()`; `_on_panic_entered()` calls the empty `_emergency_deploy()` hook (t7); `in_view` computed in `_tick_weapons` | t8 ticks the hangars after the weapons and fills `_emergency_deploy()` |
| `assault/scenes/enemies/carrier/carrier.tscn` | `Modules/HangarPort` (60, −56) / `HangarStarboard` (−60, −56): HANGAR, 220 HP, `starts_vulnerable` false, 64 × 56 hurtbox, placeholder `station_turret.png` sprite, no `Light` | t8 adds per hangar a `Light` (`StateLight`), a `Mouth` (`Marker2D`, outboard) and a code-drawn `Doors` node; no shape / position change (t9 / t11 / t12 rule) |
| `assault/scenes/enemies/carrier/carrier_config.gd/.tres` | Flat config | gains a `Hangars` group |
| `global/components/enemy_module.gd` | `set_vulnerable(on)` (no-op on a wreck; emits `vulnerability_changed`), `is_destroyed()`, `destroyed(module)`; destroy turns a `StateLight` `Light` OFF | doors drive vulnerability through it; a wreck ignores the call |
| `global/enemy_ai/squad_controller.gd` | Role board; a member's `squad` property is the strong ref; `join()` in the member's `_ready()` | one board per payload kind, set before `add_child` (WaveManager / SectorHub rule) |
| `assault/scenes/enemies/swarm_drone/swarm_drone.gd`, `fighter/fighter.gd` | `var squad: SquadController` (joined in `_ready()`); brains have `start_engaged`, `rng_seed`, `mover` | the payloads |
| `assault/scenes/enemies/laser_tender/laser_tender.gd::launch_pair()` | the runtime-children precedent: instantiate, place at a marker in the parent's space, seed the brain from the owner's rng, collision exceptions both ways, `parent.add_child`, `EventBus.enemy_spawned_orphan.emit` | copied shape |
| `global/systems/event_bus.gd:77` | `signal enemy_spawned_orphan(enemy: Node)`; `ScoreTracker` scores orphans | announcement |
| `global/enemy_ai/enemy_mover.gd` | `boost(dir, speed, duration)` committed | the outward launch push |
| `global/components/state_light.gd` | `State { OFF, ARMED, CHARGING, COMMIT, VENTING }` | hangar light yellow (CHARGING) while the doors are open |
| `tests/integration/test_carrier.gd` | t6 / t7 rows; helpers `_world`, `_spawn`, `_tick`, `_part`, `_expose_core` (destroys EnginePort + both hangars), real-physics `_shoot` at 16× | patterns for the new file; existing engaged rows will now see launches at 3.0 / 7.0 s (must stay green) |
| `tests/helpers/enemy_ai_harness.gd` | `open_space()` / `assault()` (ArenaCamera at (640, 360): view 0..1280 × 0..720) | both harnesses |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `LaserTender.launch_pair()` | the whole spawn sequence (synchronous, sibling, seeded, exceptions, orphan announcement) |
| `SquadController` | squads for the payload |
| `EnemyModule.set_vulnerable()` | the door-tied vulnerability (owner choice 4); the module's own rule already refuses bullets / beam / nova when locked |
| `StateLight` | the hangar light |
| `CarrierEnginePlume` | the code-drawn visual pattern (a `Node2D` with `_draw()`) for the placeholder doors |
| `test_carrier.gd` `_shoot` / `_scale_clock` | real-physics bullet probe for the "hittable only while open" row |

## Conventions that constrain this
- Brain requests only; a hangar launch is the brain's tick (physics step), never a physics callback; randomness from `brain.rng` only.
- Flat config (`test_config_instance_isolation.gd`): payload scenes are `String` paths, loaded at runtime.
- Signals declared with arity; per-frame prints behind `OS.is_stdout_verbose()`; no hand-typed `uid://`.
- No collision shape / module position / `HomingPoint` change (t9, t11, t12 measure against them); `Mouth` is a new marker only.
- Tests: hand-ticked at 1/60 in both harnesses (string-label `use_parameters(MODES)` like `test_carrier.gd`); projectile rows real physics at 16×; allotment 2.2 s.
- `carrier_*` files t6 → t7 → t8 (this task owns them now); `sector_hub.*` is t10, level 1 is t12.
