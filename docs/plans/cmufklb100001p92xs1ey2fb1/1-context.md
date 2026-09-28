# Context: Enemy rework, phase 1 (mode-neutral enemy AI architecture)

Epic `cmufklb100001p92xs1ey2fb1`, research task `cmufklb3q0007p92xgnjiyyr2`. Researched on 2026-09-24 against
`agent/auto-dev` @ `01f36f2`. Every claim below was re-read in the code during this run; `file:line` refs are
current, which is not true of every line reference in older docs (see "Stale refs" at the end). The companion
file `2-research.md` covers outside research, tradeoffs, and the improvements proposed to the owner's ideas.

Sources: `CLAUDE.md`, `docs/architecture/PROJECT.md`, `docs/enemy-rework/current-enemies.md` (the ENEMIES.md
audit), the attached `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`, plus a full sweep of `assault/scenes/enemies/`,
`global/components/`, `global/resources/attack/`, `global/statemachine/`, `assault/scenes/race/core/`,
`open_space/scenes/entities/enemies/`, `project.godot` and `tests/`.

---

## Requirements from the attached documents

Each is quoted briefly, with **[IDEAS]** = `ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` and **[AUDIT]** = `ENEMIES.md` /
`docs/enemy-rework/current-enemies.md`. **P1** marks this epic's implementation scope (IDEAS §41 Phase 1, as
the epic description scopes it). Everything else goes into the roadmap as follow-up epics.

### Phase 1 (this epic implements these)

| # | Requirement | Source |
|---|---|---|
| R1 | "Refactor `BaseEnemy` into a mode-neutral entity base" | IDEAS §41.1 |
| R2 | "Introduce `EnemyBrain`, `MovementController`, `AttackController`, and `DefenseProfile` contracts". The brain decides what the enemy wants; movement decides how it gets there; attack decides how it weaponises that | IDEAS §3.1, §41.2 |
| R3 | Movement primitives instead of authored paths: seek, arrive, orbit, intercept, evade, strafe, lead_target, break_contact, regroup, formation_slot, hold_position, retreat_from, spiral, corkscrew, drift, boost | IDEAS §3.2 |
| R4 | "Open Space AI → 2D movement intent → Assault movement constraint → actual movement"; an `AssaultMovementConstraint` with corridor bounds, max vertical/lateral travel, optional edge pressure | IDEAS §1.3, §34 |
| R5 | "Replace camera-specific projectile lifetime with world-aware lifetime": `ProjectileLifetime` with max_time, max_distance_from_owner, max_distance_from_player, world_bounds, explicit_destroy; `persist_after_owner_death` | IDEAS §12, §41.3 |
| R6 | "Name every collision layer currently used numerically". Keep existing numeric allocations where practical | IDEAS §15, §41.4; AUDIT §6.2 table |
| R7 | "Do not let `BaseEnemy._ready()` blindly overwrite an enemy hurtbox mask anymore … expose a `DamageProfile` / `DefenseProfile`" | IDEAS §15; AUDIT cross-cutting #1 |
| R8 | `TargetInfo`: position, velocity, facing, distance, relative_angle, predicted_position, line_of_sight | IDEAS §27, §41.5 |
| R9 | Keep: `ShipConfig.privatise`, shared components, attack patterns, bullet pools, the Drone Interceptor's orbit and dash, the Space Station's modular structure, the Bonus Drone as an Assault reward | IDEAS §38–39; epic description |
| R10 | Existing Assault waves keep working while the change lands | epic description; IDEAS §34 |
| R11 | Pass the current gates: config isolation, contact-damage and hurtbox geometry, player-bullet lifetime, signal arity | epic description |
| R12 | Deterministic GUT coverage for `BaseEnemy`, `EnemyPathMover`, `PatrolDrone` (they have none today), and tests that run the same behaviour in both modes | IDEAS §40; AUDIT §8 |
| R13 | Remove magic-number coupling: e.g. the sniper's `FLY_IN_TIME` must match the wave path duration; the `BulletPool` grandparent assumption; camera-relative spawn maths | IDEAS §31; AUDIT §7 |
| R14 | Group-based player lookups are scattered; centralise them behind TargetInfo | IDEAS §27; AUDIT §7 |

### Later phases (go into the roadmap, not built here)

| # | Requirement | Source | Phase in IDEAS §41 |
|---|---|---|---|
| L1 | Hazard perception (`HazardInfo`: position, radius, pull, dps, movement penalty, disables abilities, LOS blocker). Hazards affect enemies by the same physical rules as the player | §3.2.5, §18.6 | not phased; needs a slot |
| L2 | Open Space persistence: encounter ownership, leash, search/reacquire, and no screen-visibility lifetime | §3.3, §33 | 6 |
| L3 | Shared combat states (SPAWN … DESTROYED); each enemy uses 3–5 | §4 | 2 onward |
| L4 | Roster: Swarm Drone (replaces Kamikaze + PatrolDrone), Razor Drone, Fighter, Gatling Interceptor | §5.1–5.4 | 2 |
| L5 | Bomber, Sniper, Ram Corvette, Missile Corvette, Support/Shield ship | §5.5–5.7, §6.1–6.2 | 3 |
| L6 | Mine Layer, Hacker Frigate (hijacks the player's seeking weapons), Stationary Turret, Jamming Structure, Gravity Well / Energy Anomaly, Wreck / Debris, Minefield, Twin-Laser Drones | §6.3–6.10, §18.6 | **not in §41**; needs a slot |
| L7 | Heavy Gunship, Carrier (modular) | §6.11, §7 | 4 |
| L8 | Space Fortress 2.0 (Space Station rework), Dreadnought; boss reinforcement philosophy; phase rules; geometry-driven weapons; destruction changes the battlefield | §8–10, §24–26 | 5 |
| L9 | Weapon families: bullets, rockets, energy (beam, sweep, lance, pulse ring, twin-beam, laser wall), area control | §11 | spread across 2–5 |
| L10 | Armour, shields, weak points; modular large-enemy damage (per-module health, accepted types, disabled state) | §13, §14 | 3–4 |
| L11 | Contact-damage profiles: None, Collision, Ramming, Explosive, Armour | §16 | 2 (Phase 1 lays the groundwork) |
| L12 | Dynamic formations (FormationSpawn → SquadController → roles → individual AI → regroup); squad messages (TARGET_MARKED, BEGIN_ATTACK, …) | §17, §18, §35 | 2 onward |
| L13 | Idle / ambient movement profiles, cheaper than combat AI | §18.5 | 6 |
| L14 | EncounterDirector: budgets, semantic spawn positions (PLAYER_REAR, FLANK, OBJECTIVE …), cleanup | §19, §32 | 6 |
| L15 | Assault migration: WaveBuilder formations become spawn layouts plus AI constraints; level timing stays | §20, §34–35 | 7 |
| L16 | Readability art pass: silhouette + faction accents + gameplay lights, cool edge highlights, size language, sprite sizes, visual states | §21–23 | not in §41; runs with each roster phase |
| L17 | Line of sight / occlusion (`can_see_player()`) | §28 | 3 (the sniper needs it) |
| L18 | Difficulty scaling by behaviour, not HP (Easy / Normal / Hard / Very Hard) | §29 | open question; not in §41 |
| L19 | Config grouped by behaviour: MovementProfile / AttackProfile / DefenseProfile / TacticalProfile | §30 | clashes with the flat-config gate; see Conventions |
| L20 | Bonus Drone stays an Assault reward target; a Salvage Drone world event in Open Space | §2, §38 | 2 or 6 |
| L21 | Test strategy: movement, combat, behaviour, large enemies, and both modes for every enemy | §40 | every phase |

### Open questions carried by the epic

- Numeric layer allocation. A recommendation is in `2-research.md` §Improvements.
- Whether `DamageReaction` replaces the damage flow inside `BaseEnemy`.
- Difficulty tiers.

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` (86 lines) | `BaseEnemy extends CharacterBody2D`: `$Health`/`$HurtBox`/`$HitFlashAnimationPlayer`, optional `ContactHitBox`; scoring fields; privatise in `_init`/`_enter_tree` (40–45) | R1/R7 target. **Line 51** `hurt_box.collision_mask = 97 \| 1024`; **70–73** `_rotate_sprite()` flips any `AnimatedSprite2D` 180°; **82** unconditional death `print`; 64–68 config duck-type; 78–86 death and `queue_free()` in one call |
| 10 subclasses: bomber, bonus_drone, drone_interceptor, gunship, interceptor, kamikaze_drone, light_assault_ship, ram_ship, sniper_enemy, space_station | Concrete enemies; all call `super._ready()` first | Blast radius of every BaseEnemy change. Self-driven `_physics_process`: bomber 34, gunship 74, ram 56, drone_interceptor 64, kamikaze 50. sniper uses `_process` (51) *precisely to survive* the path mover. light_assault_ship has the only `AIStateMachine` (`.tscn:111`) |
| `assault/scenes/enemies/enemy_path_mover.gd` | Writes actor position from a `MovementResource` sample | 43 camera lookup; **62 `set_physics_process(false)`**; **63–65 disables a child literally named `AIStateMachine`**; **77, 83 `* ArenaCamera.WORLD_SCALE`**; 100–117 off-screen cull (80 px margin, ignores `cam.offset`) |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Time-driven spawner | 175 camera-relative spawn pos; **198 attaches `EnemyPathMover`** when a `MovementResource` is given |
| `assault/scenes/levels/level_1_director.gd`, `level_2_waves.gd` | Level content | **256 of 260 level-1 spawns and all 8 level-2 spawns use `.move()`.** Only the station (241), 2 drone interceptors (290–291) and 1 gunship (296) run their own AI. The light assault ship's state machine runs in no shipped level. The bonus drone (110–144) always gets a path mover (`StraightMovement` 560, `FREE_ON_DURATION` 4 s) |
| `assault/scenes/systems/arena_camera.gd` | `ArenaCamera`: `WORLD_SCALE=2.0` (39), `SCREEN_W/H` (40–41), `H_LIMIT=100`, `V_LIMIT=380` (42–43); global_position pinned, pans via `.offset` | The only honest source for an Assault corridor rectangle. `EnemyBullet`'s bounds are hand-copied from it |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd` | Pooled enemy bullet | 12–16 hardcoded bounds x∈[-164,1444], y∈[-444,1164]; 31–37 out-of-bounds emits `expired`; 39–40 any hit emits `expired`; 44–50 `become_friendly()` (unused). **Also fired by `RacerWeapon` (`race/core/racer_weapon.gd:5`) in race mode**, so a lifetime change affects races. The sniper bullet (`enemy_sniper_bullet.tscn`) reuses this script unpooled (`sniper_enemy.gd:99` connects `expired → queue_free`) |
| `assault/scenes/enemies/bomber/bomb.gd` | Bomber ordnance | Its own lifetime: 5 s fuse, proximity trigger on layer 128, `await create_timer(0.15)` before `queue_free` (86–88; the SceneTreeTimer-leak shape from tests/README), bottom-edge-only cull (91–97) |
| `global/components/bullet_pool.gd` | Pool that recycles on `expired` | **47 `_container = get_parent().get_parent()`**. Every user today (light_assault_ship, interceptor, gunship, ally_fighter, space_station, racer_weapon, station reinforcements) matches pool → ship → container. `cancel_active` 105–109 on `_exit_tree` |
| `global/components/attack_controller.gd` | **`AttackController` already exists**: `pattern: AttackPatternResource` + `bullet_pool`, accumulating timer in `_process` (24–30) | R2's AttackController is *already here*; extend it, don't add a second. Users: light_assault_ship:46, interceptor:42, ally_fighter:45. Gunship fires manually from a Timer; the station calls `RadialAttackPattern.fire` directly |
| `global/resources/attack/*.gd` | `AttackPatternResource.fire(ship, pool)` (15); Aimed, Gatling (`spread_angle`, `aim_at_player`), Forward, Radial | All aimed variants read `get_nodes_in_group("player")[0].global_position` with **no prediction**. Natural first consumers of TargetInfo |
| `global/components/hurtbox_component.gd`, `hitbox_component.gd` | `HurtBox.accepted_damage_types` filter (7, 16–17); `HitBox.DamageType {LASER, ROCKET, CONTACT}` (4) | The damage-type rule already exists and is unused by enemies (only `big_asteroid.tscn:39` sets it) |
| `assault/scenes/enemies/ram_ship/ram_ship.gd` | Missile-only armour | **Armour is a collision mask**: `mask = 33` (21) → `97` on first hit (45; drops 1024). `is_laser_blocking()` 52–54; joins `"ram_ships"`, not `"enemies"`. Pinned by `test_ram_ship.gd:45-61` on mask bit 64 |
| `assault/scenes/enemies/space_station/*` | Modular boss | Root layer and mask 0 (`.tscn:64-65`, load-bearing for the mining laser). Core HurtBox mask 1121. `station_turret.gd:34-35` writes 512/1121 itself. `is_armored()` 155; armour-as-damage-rule override 171–176. `BulletPool` must be a **direct child** (`test_station_gunnery.gd:108-118`). Reinforcements spawn into `_station.get_parent()` to keep the pool grandparent right (`station_reinforcements.gd:33-37,272`) |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd` | ENTER/ORBIT/DASH enum (20) | The code to keep (R9). Config: orbit_radius 130, orbit_speed 1.8 rad/s, approach 200, correct 160, dash 480, `dash_prediction_time` 0.2 (world px, **no** WORLD_SCALE). Only prediction in the project: `player.global_position + player.velocity * t` (113–123). Faces with `atan2(dir.x, -dir.y)`, nose-up (157–166), which is the **opposite** convention to the path mover's nose-down `atan2(-vel.x, vel.y)` (87) |
| `open_space/scenes/entities/enemies/patrol_drone.gd/.tscn` | The only Open Space enemy; not a BaseEnemy, no config | Straight drift forever (21–23), no culling. `received_damage` is wired in the `.tscn` (last line), not in code. Body layer **256** (enemy_hitbox, probably a mistake). **HurtBox mask 64 only**, so the player's rockets (32) pass through it in Open Space. Health node is `HealthComponent`, not `Health` |
| `open_space/scenes/levels/sector_hub.gd:18-26` | Spawns 3 drones into `$EnemyContainer` (direct child of the hub root) | Pool → ship → container depth works here too |
| `global/statemachine/state.gd`, `state_machine.gd` | `State.state_transition(new_state: State)`; `StateMachine` ticks in **`_process`** (16–18) | A brain built on this ticks in `_process`, not physics. That is why the path mover has to disable it via `process_mode` |
| `assault/scenes/race/core/racer_state_machine.gd`, `sensors.gd`, `lateral_mover.gd` | Race-mode AI: `RacerStateMachine` (explicit `tick(delta)`, `transition_to(&"Name")`), `Sensors` ("stateless perception … no strategy lives here"), `LateralMover` (critically damped glide + an *offered* `avoidance_nudge` that "each brain decides whether to add") | **An in-project precedent for exactly the brain / perception / locomotion split this epic wants**, already shipped and working. The shape to copy; the names to avoid (`host.brain` is informal usage there) |
| `assault/scenes/player/movement_controller.gd:1` | **`class_name MovementController`**: the *player's* input and double-press handler, and a node name in both player scenes | **Hard name collision with R2's `MovementController`.** The enemy contract needs another name (see `2-research.md`) |
| `global/entities/player_base.gd` | `PlayerBase extends CharacterBody2D`, joins `"player"` (56) | Every player (assault, open-space, and the infiltration `player.gd`) exposes a real `velocity`; the assault fighter's is written inside its state machine in `_process` |
| `global/ship_modules/ai_targeting_module.gd` | Nearest-in-`"enemies"` search (53–67), duck-typed `face_instant` (39) | Precedent for duck-typed facing; the reverse direction of TargetInfo |
| `project.godot [layer_names]` | Named layers 1, 2, 3 (typo `environemnt_player`), 7, 8, 9, 10 | R6 target (full bit table below) |

### Collision bits actually in use

| Bit (value) | Name today | Used by |
|---|---|---|
| 1 (1) | environment | default body layer; race walls; every enemy hurtbox mask; `beam_behavior._RAY_BLOCK_MASK` |
| 2 (2) | environment_interactable | info logs, mission trigger |
| 3 (4) | environemnt_player *(typo)* | player/ally bodies; pickup and interactable masks |
| 4 (8) | — | **unused** |
| 5 (16) | **unnamed** | all 12 pickups' layer (`global/pickups/scenes/*.tscn`). *Not listed in the audit.* |
| 6 (32) | **unnamed** | player rocket HitBoxes (`homing_missile.tscn:54`, `warhead_missile.tscn:60`); every enemy hurtbox mask; asteroid hurtboxes; race wall |
| 7 (64) | player_hitbox | player/ally bullets, reflected enemy bullet |
| 8 (128) | player_hurtbox | player/ally hurtboxes; enemy bullet, contact and bomb-proximity masks; laser override |
| 9 (256) | enemy_hitbox | enemy bullets, contact boxes, bombs; PatrolDrone *body* |
| 10 (512) | enemy_hurtbox | every enemy, turret, asteroid and racer hurtbox |
| 11 (1024) | **unnamed** | asteroid ContactHitBoxes; in enemy mask 1121, player mask 1281, racer masks 1088, beam ray |
| ≥12 | — | unused |

There are no `set_collision_*_value` calls anywhere; every write is a raw int. Dynamic writers: `base_enemy.gd:51`,
`ram_ship.gd:21,45`, `station_turret.gd:34-35`, `enemy_bullet.gd:49-50`, `space_station.gd:234`,
`laser_ray.gd:79,114`, `beam_behavior.gd:9,60`, `race_ship.gd:45-46`, `sensors.gd:10,27`, `station_laser_phase.gd:32`.

---

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/resources/ship_config.gd` + `privatise()` | Per-instance config; must stay flat (see Conventions) |
| `global/components/health_component.gd`, `hurtbox_component.gd`, `hitbox_component.gd` | Damage plumbing; `accepted_damage_types` is the ready-made armour-by-type rule for DefenseProfile |
| `global/components/damage_reaction.gd` | Shared hurt → shield → health → flash → die flow, with Shield support. Candidate replacement for BaseEnemy's inline flow (open question) |
| `global/components/shield_component.gd` | Discrete-charge shields, for later DefenseProfile/support-ship work |
| `global/components/attack_controller.gd` + `global/resources/attack/*` | **The AttackController contract already exists.** Needs: an optional aim source (TargetInfo), a pause/enable hook the brain can drive, and ticking under the same clock as the brain |
| `global/components/bullet_pool.gd` | Keep. Make the container injectable, falling back to the grandparent so every current user is unchanged |
| `global/components/hit_effect.gd`, `explosion_effect.gd` | Presentation, already mode-neutral |
| `assault/scenes/race/core/{racer_state_machine,sensors,lateral_mover}.gd` | The brain/perception/locomotion split with explicit `tick(delta)`; "avoidance is offered, the brain opts in" |
| `drone_interceptor.gd` orbit (95–109) and dash prediction (113–123) | The reference behaviour for `orbit()` and `intercept()` primitives, and the first real enemy to port onto them |
| `global/statemachine/` | For enemies with complex states. Note the `_process` tick |
| `ArenaCamera` constants | The corridor rectangle for the Assault constraint and the Assault world bounds for projectile lifetime, *derived* rather than copied (EnemyBullet copies them today) |
| `face_instant()` duck-type precedent (`player_fighter.gd:111`, `player_ship.gd:262`) and `is_armored()` (`bullet.gd::_hit_is_deflected`) | The project's accepted pattern for a cross-entity contract without a shared base class |
| `tests/helpers/save_sandbox.gd`, GUT `simulate()` | Test infrastructure for deterministic stepping |

---

## Conventions that constrain this

- **Composition over inheritance**: contracts should be child components (`Node`s) or stateless `Resource`s,
  not a deeper BaseEnemy hierarchy.
- **Flat configs, one config per entity dir.** `test_config_instance_isolation.gd` requires at most **one**
  `.tres` with `config` in its name per `<dir>/<dir>.tscn` entity dir (assert at 107), and
  `test_configs_are_flat_so_a_shallow_copy_is_complete` (209–227) rejects **any Object/Array/Dictionary
  field** on a config. So IDEAS §30's nested `MovementProfile`/`DefenseProfile` *inside* ShipConfig is
  forbidden as written. Options: flat prefixed fields on the config, separate exported resources on the
  script (then they are shared across instances and **must be treated as read-only**, the same trap
  privatise exists for), or component nodes with exports in the scene.
- **The object `load()`/`preload()` returns is shared; never write to it.** Any profile resource the ram ship
  would mutate (armour stripped) has to keep that state on the node, not in the resource.
- **Design-unit coordinates** (640×360 × `WORLD_SCALE`) apply to *Assault wave authoring*. New world-space AI
  must use world pixels (as drone_interceptor already does). The corridor constraint does the translation;
  AI parameters must never be pre-multiplied.
- **Signal arity**: declare exactly what is emitted (`test_signal_emit_arity.gd` sweeps every self-emit).
  Per-frame logs go behind `OS.is_stdout_verbose()`; this makes `base_enemy.gd:82` a convention violation to fix.
- **Projectile ownership**: exactly one owner, either a pool or self-free. World-aware lifetime must keep
  pooled enemy bullets *emitting `expired`* (never `queue_free` a pooled bullet), which is the boundary
  `test_player_bullet_lifetime.gd` already pins for player bullets.
- **Armour is a damage rule on a full-size hurtbox, never an absent or shrunken one**
  (`test_enemy_hurtbox_geometry.gd`). The ram ship's *mask-toggle* armour is the one exception in the roster:
  it is a mask rule, not a geometry one, so it passes, but a DefenseProfile should express it as data.
- **Single writer of rotation** is gated only for the player and `global/ship_modules/`. The same idea should
  apply to enemies: the movement component should be the only writer of an enemy's `rotation`/`velocity`,
  and **EnemyPathMover currently writes `global_position` and `rotation` directly**.
- **Timers**: GUT `simulate()` does not fire `Timer` nodes or SceneTreeTimers, and SceneTreeTimers awaited in
  coroutines leak at exit (tests/README; `scripts/check-test-leaks.sh`). Brain and lifetime clocks should be
  accumulated `delta` floats.
- **UIDs**: new scenes or resources are either left UID-less or get a headless-minted UID; never hand-typed,
  never copied, and never via MCP `update_project_uids`.
- **Docs**: a structural change requires the `updating-project-docs` skill (assault.md, global.md, PROJECT.md,
  per-entity ENEMY.md, CLAUDE.md).

---

## Dependencies and blast radius

- **`BaseEnemy._ready()` mask line.** Replacing 51 must reproduce `1121` for every enemy that doesn't opt out:
  `test_station_incoming_damage_paths` fails in 5 places if bit 32 or 1024 goes missing. The ram ship must still
  end up at 33, then 97 (`test_ram_ship`). The station turret writes its own mask.
- **`EnemyPathMover` is the movement system for 264 of 268 shipped spawns.** R10 means it stays working, and
  stays the default, until Phase 7. Phase 1 can re-route what it *does* (for example, feeding the movement
  component instead of disabling the AI), but any change there hits every wave. The low-risk option is to
  leave its position-writing mode untouched and add the new path alongside.
- **The magic `AIStateMachine` name.** Any new brain node is either deliberately *not* named that (so the path
  mover leaves it running, which would fight the path) or the mover switches to a duck-typed suspend
  (`suspend_ai()` / group). This is decided in the plan.
- **`EnemyBullet` is shared with race mode** (`RacerWeapon`). World-aware lifetime has to keep races working;
  race worlds scroll differently.
- **`BulletPool._container`**: making it injectable touches 7 users; the grandparent fallback keeps them unchanged.
- **Sprite facing**: `_rotate_sprite()` (180° on `AnimatedSprite2D`), path-mover nose-down and the interceptor
  nose-up are three conventions. A mode-neutral facing rule changes which way art points for any enemy migrated.
- **Scoring**: `ScoreTracker` hooks `WaveManager.enemy_spawned` + `BaseEnemy.died`. Open Space has no
  ScoreTracker; BaseEnemy's scoring fields must stay harmless there.
- **Roster sweeps**: a new entity dir `<dir>/<dir>.tscn` under `assault/scenes/enemies/` or `allies/` must be
  added to the hand rosters in `test_enemy_hurtbox_geometry.gd` (70–113; the completeness check is at 317–337)
  and `test_enemy_contact_damage.gd` (53–105), and gets a config sweep. Scenes in subdirectories, or loose
  scripts, are ignored. Put test-only fixture enemies under `tests/fixtures/`.
- **`test_project_load_integrity.gd`** loads, instantiates and compiles every file outside `addons/` with
  **zero engine errors**. A new component that `push_error`s when instantiated without a parent (as
  `EnemyPathMover._ready` does) fails the gate.

---

## Risks, edge cases, testing requirements

1. **Path mover and brain both active.** If the brain isn't suspended, two writers fight over position. If it
   is, the "tests in both modes" requirement can't use path-moved enemies. *Test:* spawn with `.move()` and
   assert the movement component's velocity output is ignored or suspended, with position equal to the path
   sample (characterization of today's behaviour).
2. **Mask regression.** *Tests:* every roster enemy's post-`_ready()` hurtbox mask equals today's value
   (1121, ram 33), as a characterization gate *before* DefenseProfile lands, then kept as the profile's
   acceptance test.
3. **Race regression from EnemyBullet lifetime.** *Test:* a racer bullet still expires in a race world.
4. **Pool semantics.** Lifetime expiry of a pooled bullet must emit `expired` exactly once and never free it;
   a double `expired` in one frame is already guarded (`bullet_pool.gd` `_recycle` guard), so pin it.
5. **Prediction edge cases.** Target velocity zero; projectile slower than target (no intercept solution);
   target at the shooter's position; `delta` = 0; a target freed mid-frame (TargetInfo must tolerate a
   stale/invalid target). Also the assault player's `velocity` is written in `_process` while the enemy
   reads it in physics, so it can lag one frame.
6. **Corridor edge cases.** Intent pointing out of the corridor → clamp or slide along the edge, never
   stall. An enemy spawned *outside* the corridor (every Assault wave spawns above the screen) must be
   allowed to enter; hard-clamping at spawn would teleport it.
7. **Open Space has no ArenaCamera.** Anything assuming `get_camera_2d() is ArenaCamera` must degrade to
   "no constraint" and never push_error.
8. **Freed player.** Group lookups return `[]` on the frame the player dies (Open Space reloads the scene
   1.2 s later). Every aimer must handle "no target".
9. **Determinism.** Randomness (drone-interceptor dash timer `randf_range(1,2)` at line 56; orbit direction)
   must come from an injectable `RandomNumberGenerator` for tests.
10. **PatrolDrone characterization first.** It is replaced in Phase 2, so Phase 1 pins its *current*
    behaviour (drift, `died`, `queue_free`, scene-wired damage, mask 64), including the rocket-immunity bug,
    marked as characterization.
11. **Leaks.** Any `await` in new code must run `scripts/check-test-leaks.sh`.

Required new coverage (R12): unit tests for TargetInfo/prediction, each movement primitive, the corridor
constraint and projectile lifetime; integration tests for BaseEnemy (mask/profile, death flow, sprite
rotation, scoring copy, verbose-gated print), EnemyPathMover (sample × scale, AI suspension, both exit modes,
off-screen cull with the never-on-screen case), PatrolDrone (characterization); and a **dual-mode test**
running one behaviour spec under "no constraint" and under the Assault corridor.

---

## Open questions for the plan

1. The name for the enemy movement component (`MovementController` is taken). Candidates: `EnemyMover`,
   `EnemyLocomotion`, `SteeringController`.
2. Brain as a `Node` with explicit `tick(delta)` driven by a single owner (race precedent), versus reusing
   `StateMachine` (ticks in `_process`, suspended by name).
3. How the path mover and the new stack coexist until Phase 7: suspend by duck-type, or make the path a
   movement *source* the component consumes.
4. DefenseProfile as a stateless Resource, flat config fields, or a Node component; and how the ram's
   mutable armour state fits.
5. Layer names and whether to fix the `environemnt_player` typo (display-only; safe) and name layer 5
   (`pickups`), which the audit missed.
6. Does Phase 1 port a real enemy (the Drone Interceptor is the obvious candidate: self-driven, no `.move()`,
   world-pixel params) to prove the stack, or only a test fixture?
7. `DamageReaction` versus BaseEnemy's inline flow.
8. Whether to fix PatrolDrone's rocket immunity now or leave it for Phase 2's replacement.

### Stale refs found in existing docs

`space_station/ENEMY.md:475` and `station_turret.gd:31` cite `base_enemy.gd:25` for the mask write; it is line 51.
`space_station.gd:184` cites `base_enemy.gd:65-73`; the death flow is 78–86. These are worth correcting when
the Phase 1 docs pass touches those files.
