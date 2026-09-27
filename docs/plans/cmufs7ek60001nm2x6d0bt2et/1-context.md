# Context — Enemy rework, phase 2: Swarm Drone, Razor Drone and squad roles

Epic `cmufs7ek60001nm2x6d0bt2et`, research task `cmufs7ekg0005nm2xzufhgq10`. Researched 2026-09-27 against
`agent/auto-dev` @ `7b5d034`. Every claim cites the current code; line numbers drift, so cite symbols in the plan.

Read with: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` (Phase 1 plan + *as built*),
`docs/epics-done/cmufklb100001p92xs1ey2fb1/REPORT.md`, `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §7–§8.
The *scope check* (what changed versus the Phase 1 roadmap) is at the top of `2-research.md`.

---

## Requirements from the attached documents

Quoted briefly from `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` (IDEAS) and
`ENEMIES.md` (AUDIT). Only the ones this phase's scope assigns. `R2.x` ids are used by `2-research.md` and should
be carried into the plan's coverage table.

| Id | Requirement (source) | Needs research? |
|---|---|---|
| R2.1 | Swarm Drone replaces Kamikaze Drone **and** Open Space PatrolDrone; 24–36 px (IDEAS §2, §5.1) | no — code |
| R2.2 | "lightweight swarm logic rather than expensive full boids": separation, alignment to squad velocity, cohesion to squad anchor, player avoidance until commit, lateral offset from the player's velocity (§5.1 Movement) | yes — finding 1 |
| R2.3 | "Each drone selects a different phase offset so ten drones do not trace identical curves" (§5.1) | yes — finding 1 |
| R2.4 | Coordinated ram: wide orbit → predict 0.4–0.8 s → pick an **unoccupied side** → acceleration burst → near miss overshoots and curves away → **one** second pass (§5.1 Attack) | yes — findings 4, 5 |
| R2.5 | Group of 3–6: one **lead attacker**, two **left/right flank** slots, the rest **orbit the rear**; lead dies → another takes its place (§5.1 Group, §17, §35) | yes — finding 2 |
| R2.6 | Swarm in Assault: same AI inside the corridor; may curve, circle partially, cross above/below the player, break formation, re-enter from the side; "a swarm inside a 2D lane rather than a row of sine-wave paths" (§5.1 Assault) | code |
| R2.7 | `spiral(target)` / `corkscrew(target)` primitives, only those the swarm needs (§3.2; scope) | judgement |
| R2.8 | Razor Drone evolves the Drone Interceptor; 40–56 px; APPROACH→ORBIT→FEINT(left/right)→DASH→OVERSHOOT→RETURN (§5.2) | code |
| R2.9 | Occasional **orbit reversal** before dashing (§5.2) | yes — finding 6 |
| R2.10 | **Fake dash**: points at the player, brakes, slides past, attacks from the opposite side (§5.2) | yes — finding 4 |
| R2.11 | Real dash has a **stronger** visual/audio cue than the fake (§5.2) | yes — findings 3, 4 |
| R2.12 | Contact damage **plus a pulse shot immediately after a missed dash** (§5.2 Attack) | code (BulletPool, AimedAttackPattern) |
| R2.13 | Razor in Assault: orbit centre constrained to a band around the player; attack diagonally from a side lane (§5.2) | code |
| R2.14 | Contact profiles **None, Collision, Ramming (high damage only during a committed state), Explosive collision** (§16). Armor collision → Ram Corvette phase | yes — finding 7 |
| R2.15 | SquadController with role assignment + reassignment for drones only (§17 "FormationSpawn → SquadController → role assignment → individual AI → dynamic regrouping", §35 "formation helpers kept only as spawn layouts") | yes — finding 2 |
| R2.16 | Razor idle: irregular orbit around a patrol anchor; accelerate, brake, reverse; on perception transitions *naturally* into combat "instead of instantly snapping" (§18.5); plus the generic anchor-idle→combat handover | yes — finding 8 |
| R2.17 | Idle must be cheaper than combat AI; "should not consume the same CPU budget" (§18.5) | judgement |
| R2.18 | Retire Kamikaze Drone and PatrolDrone; keep Bonus Drone exactly as the Assault reward target (§2, §38) | code |
| R2.19 | Readability: silhouette, faction accents (red/maroon/orange), **one gameplay light per state** (red armed / yellow charging / white locked); cool edge highlight on dark hulls; do not recolour the whole enemy (§21.1–21.2, §22 "24×24 or 32×32 with exaggerated silhouettes", §23) | yes — finding 9 |
| R2.20 | Deterministic tests, same spec in both harnesses: prediction, orbit radius, dash direction, fake vs real dash, overshoot + second pass, role reassignment, formation recovery (§40) | code |
| R2.21 | §41 Phase 2 items 1–2 (Swarm Drone, Razor Drone). Items 3–4 (Fighter, Gatling) belong to Phase 3 | — |
| R2.22 | SectorHub's ambient PatrolDrone spawn → a Swarm squad + a Razor Drone around the same anchor (epic text; **not** an EncounterDirector — §32 is Phase 13) | code |
| R2.23 | Level-1 Kamikaze and Drone Interceptor spawns migrated: spawn layouts kept, corridor constraint instead of `.move()`, wave timing preserved (epic text) | code — the hard part |
| R2.24 | Existing invariant gates must cover the new scenes (epic text) | code — see "Gates" below |

Out of this phase by scope (recorded so the plan's coverage table can cite them): squad *messages* §18 (Ph14),
idle profiles for other families (Ph14), EncounterDirector/leash (Ph13), Armor collision (Ph4), Salvage-drone
Open Space event (Ph13), difficulty tiers §29 (Ph16), hazard avoidance §18.6 (Ph6), the rest of the level-1
waves (fighters, interceptors, gunship… Ph3/Ph15).

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/enemy_ai/enemy_brain.gd` (`EnemyBrain`) | Brain base: `tick(delta)`, `on_suspended()`, `actor`, `mover`, `attack`, seedable `rng` (`rng_seed` export; 0 = `randomize()`). Header rules: clocks are accumulated `delta`, no `Timer`s, randomness only from `rng`, player only via `TargetInfo.player()`. State vocabulary SPAWN…DESTROYED incl. PANIC "leaderless" | Both new brains extend it. Squad membership is new state it does not model |
| `global/enemy_ai/enemy_mover.gd` (`EnemyMover`) | Single writer of `velocity`/`rotation`, one `move_and_slide()`. Exports `max_speed`, `acceleration`, `braking`, `turn_lerp`, `max_turn_rate`, `constraint_mode` (AUTO/NONE). Requests are **per step** (cleared every `step()`); `boost(dir, speed, duration)` ignores requests/accel but **not** the constraint; `halt()`. Constraint resolved **once** in `_ready()`; a pre-set `constraint` wins | Ram burst = `boost()`; brake/overshoot/fake-dash slide = `braking`/`acceleration`. The corridor filters every step incl. boosts |
| `global/enemy_ai/steering.gd` (`Steering`) | Pure static: seek, arrive (radius `v²/2a`), orbit (Interceptor formula, `clamp(dist·4, 60, max)`), intercept, retreat_from, evade, strafe, hold_position, drift | Add `spiral`/`corkscrew`/`formation_slot` and the three flocking terms here as pure functions. `drift`'s comment cites PatrolDrone — update on deletion |
| `global/enemy_ai/target_info.gd` (`TargetInfo`) | Snapshot: `has_target`, `position`, `velocity`, `facing`; `predicted_position(t)`, closed-form `intercept(from, speed) → {ok, point, time}`, `aim_direction(from, speed, accuracy)`, stub `line_of_sight` | The 0.4–0.8 s ram prediction and the pulse aim. "Unoccupied side" needs the player's velocity (present) |
| `global/enemy_ai/enemy_world.gd` (`EnemyWorld`) | Only lookup of the mode provider (`&"assault_arena"` group): `projectile_world_rect`, `cull_rect`, `movement_constraint` | The only legal way to know "am I in Assault". Nothing under `global/` may name `ArenaCamera` |
| `global/enemy_ai/movement_constraint.gd` | Identity `filter(pos, desired)` | Base for the corridor; a *release/exit* notion does not exist yet (see risk C1) |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis velocity filter over a **1480×1480** world square (x −100…1380, y −380…1100 = screen ± camera offset limits). Not-entered → inward only ≥ 60 px/s; soft band 0–120 px pressure `200·d/120`; outer band 120–450 scales outward to 0 + 200; beyond 450 outward removed. `_entered` latches, never resets | The first real AI enemies to fly through it. It **forces re-entry**, so an AI drone can never leave the arena on its own (C1). The rect is much taller than the screen (720 px): a drone can be "in corridor" but off-camera |
| `assault/scenes/systems/arena_camera.gd` | Provider: `projectile_world_rect()` (visible ± 64), `enemy_cull_rect()` (camera `global_position` ± viewport/2 ± 80 — **does not follow `offset`**), `enemy_movement_constraint()` (fresh instance) | Legacy dash cull; any new Assault exit rule |
| `assault/scenes/enemies/base_enemy.gd` (`BaseEnemy`) | `_physics_process`: `brain.tick` → `mover.step`, skipped when suspended/brainless. `suspend_ai()`; `sprite_forward_angle` (PI/2 default); `DefenseProfile` resolved or created (mask 1121); `contact_hit_box = get_node_or_null("ContactHitBox")`; death at 0 HP: `was_killed = true`, `died`, explode, `queue_free()` in the same call; copies scoring fields from `get("config")` | Both new enemies extend it (it still lives in `assault/` until Ph15). Contact profile must hook here or beside it |
| `assault/scenes/enemies/drone_interceptor/` | `DroneInterceptor` (BaseEnemy) + `DroneInterceptorBrain` (ENTER/ORBIT/DASH), `DroneInterceptorConfig`. `.tres`: HP 25, collision 30, score 40, orbit 130 px @ 1.8 rad/s, approach 200, correct 160, dash 480 px/s, prediction 0.2 s, `dash_max_distance` 1600. Scene: `drone_2.png` 64×64, circle r10 × scale 3.08 ≈ 30.8 px, `EnemyMover` `turn_lerp 7`, `constraint_mode NONE`, `ContactHitBox` 256/128 dmg 30 CONTACT. **No telegraph**: DASH starts the tick the 1–2 s timer expires. Culls **only in DASH** (cull rect in Assault, `dash_max_distance` in Open Space). Contact → `set_health(0)` → scored as a kill | The Razor Drone evolves this (R2.8). 64×64 art is above the 40–56 px target |
| `assault/scenes/enemies/kamikaze_drone/` | `KamikazeDrone` (BaseEnemy) overrides `_physics_process`: locks `_direction` at `_ready()` from the `"player"` group, writes `rotation` and `global_position` itself, culls only past the **bottom** edge (+60). `drone_config.tres` HP 30, collision 30 (**dead field** — scene hard-codes 30), score 10, speed 140 (ignored on rails). `drones.png` 126×84 = 3×2 sheet of 42×42 variants, picked with **global `randi()`**. Circle r10 unscaled. HitFlash animations empty; no shader | Retired (R2.18). Its 42 px cells are above the 24–36 px target |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | 4+1 sections. **119 `b.drone()` lines, all with `.move()`** (deep_space 42, planet_approach 46, cloud_descent 31), of which 13 are formations (cluster ×7, wedge ×6, line ×1 — one line is `line_formation(4, 60)`). Spawns at design `y = −400` (world 60 px above the corridor top), a few side entries (`at(±500,150)…free_after(5.0)`) and from-below (`at(x, 400).move(straight(…, PI))`). **2 `drone_interceptor()` lines** at `deep_space` t = 1.5 s, `at(∓160, −420)`, no `.move()` | R2.23. Sections: deep_space DURATION 30 s, asteroid_belt DURATION 30 s ("no enemies"), station_assault ENEMIES_CLEARED (timeout 180), planet_approach DURATION 110 s, **cloud_descent ENEMIES_CLEARED** (default `enemies_cleared_timeout` 10 s) |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | Spawn pos `cam.global_position + cam.offset + offset·WORLD_SCALE`; `on_spawned` props before `add_child`; `enemy_spawned(entity, wave_index)`; attaches `EnemyPathMover` **only if `movement is MovementResource`**; `_expand_formation()` turns a `FormationResource` into independent spawn dicts (offset + delay per slot) — the squad grouping is **lost** here | Omitting `.move()` is the supported "AI-driven" path. Squad grouping needs a hook here or in `WaveBuilder` |
| `assault/scenes/systems/wave_builder.gd` | DSL; `DRONE`, `DRONE_INTERCEPTOR`, `BONUS_DRONE` scene-path constants; formation helpers `v_/wedge_/line_/diagonal_/cluster_formation`; `SpawnConfig.free_after()` | Constants repoint to the new scenes; a squad hint (`.squad()`?) would live here |
| `assault/scenes/systems/level_director/level_director.gd` | Sections advance by DURATION/WAVES_COMPLETE/ENEMIES_CLEARED; **does not clear the enemy container between DURATION sections**; ENEMIES_CLEARED polls child count and force-frees survivors after the timeout | Long-lived AI drones carry over into the next section (incl. the enemy-free asteroid belt) and stall cloud_descent (C1, C2) |
| `assault/scenes/systems/score_tracker/score_tracker.gd` | On free: not `was_killed` → wave escaped; plus `counts_as_escape` → combo × 0.75 (`escape_combo_multiplier`) | Contact deaths score as kills today (the kamikaze "kill" by ramming pays score). An AI drone that disengages off-screen pays the escape penalty — same as a kamikaze leaving the bottom today |
| `assault/scenes/enemies/space_station/station_reinforcements.gd` | BOTTOM squad = 2 × `b.drone().at(±100, 290).move(straight(170, PI)).free_after(lifetime)`; `test_station_reinforcements.gd::test_no_squad_uses_a_self_managed_ai_enemy` forbids `GUNSHIP`/`DRONE_INTERCEPTOR` in squads | Retiring the Kamikaze scene touches the boss (not named in scope; see scope check S6) |
| `open_space/scenes/levels/sector_hub.gd` / `.tscn` | `_spawn_initial_drones()`: 3 × PatrolDrone at random angle, `randf_range(300, 600)` from **the origin, where the player spawns** (`PlayerShip` has no transform); global RNG; parented to `EnemyContainer` (one level under the root). Planets/mission triggers at ~650–740 px from origin | R2.22. A hunting squad 300–600 px from the spawn point attacks the player on frame 1 and interferes with the mission-trigger dwell (cancels above 150 px/s) |
| `open_space/scenes/entities/enemies/patrol_drone.gd/.tscn` | Not a BaseEnemy; 60 px/s drift; HP 50; HurtBox mask **64** (rocket-immune, pinned bug); body on layer 256; 16×16 `ColorRect`; contact `HitBox` dmg 10 never dies | Deleted (R2.1). `tests/integration/test_patrol_drone.gd` (8 tests) deleted with it |
| `global/components/bullet_pool.gd` | `_container = get_parent().get_parent()` (pool → ship → container) | P-18 moved "make it injectable" to this phase. SectorHub and both test harnesses already satisfy the depth |
| `global/components/attack_controller.gd` + `global/resources/attack/aimed_attack_pattern.gd` | `AttackController`: `enabled`, `driven_by_brain`, `tick()`, `fire_now()`. `AimedAttackPattern`: damage 10, speed 250, `accuracy`, fires one bullet on `TargetInfo.aim_direction` | The Razor's post-miss pulse = `driven_by_brain = true` + `fire_now()` — first real consumer of both (Phase 1 gap) |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn` | Pooled; HitBox 256/128; `ProjectileLifetime` 18 s / 2400 px, world rect when a provider exists | Works in Open Space already (Phase 1 t13) |
| `global/components/hitbox_component.gd`, `hurtbox_component.gd`, `defense_profile.gd` | `HitBox{damage, damage_type LASER/ROCKET/CONTACT}` pure data; `HurtBox` re-emits on `area_entered`, filters `accepted_damage_types`; `DefenseProfile` owns the hurtbox mask | Contact profiles are an *offensive* counterpart — none exists |
| `assault/scenes/enemies/bomber/bomb.gd` | Proximity area r80 → 1 s trigger → blast HitBox r28 dmg 40 monitoring for 0.15 s via `create_timer` → free | Only existing "explosive" damage precedent. `create_timer` in a brain would break the "no Timers" rule and is the pattern `test_level_director_polling` warns leaks |
| `global/entities/player_base.gd` | Player i-frames `invincibility_sec = 0.5` after a hit | Bounds how often any contact profile can hurt; a drone that survives contact cannot double-hit inside 0.5 s |
| `assault/scenes/enemies/bonus_drone/` | `BaseEnemy`, no brain, no `ContactHitBox` (asserted), `drone.png` 32×32 ×1.5 gold; spawned by `Level1Director._spawn_bonus_drone` with its own `EnemyPathMover` | Must not change (R2.18). Shares only `BaseEnemy`/`ShipConfig` with the drones |
| `docs/enemy-roster.md`, `docs/architecture/modules/{global,assault,open_space}.md`, per-enemy `ENEMY.md` | Roster/usage docs; "never `.move()` a drone_interceptor" | Updated by the `updating-project-docs` pass |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EnemyMover.boost(dir, speed, duration)` | The ram / real-dash acceleration burst, already constraint-aware and exempt from `max_speed` |
| `EnemyMover.braking` + `acceleration` | Overshoot and the fake-dash "brakes and slides past" come for free once the Razor/Swarm movers get non-zero accel (the Interceptor runs `acceleration = 0`, i.e. instant) |
| `EnemyMover.max_turn_rate` | The "curves away" turnaround after an overshoot — a capped turn rate produces the arc |
| `Steering.orbit` / `strafe` / `intercept` / `arrive` / `hold_position` | Wide orbit, flank-slot seeking, anchor idle; `orbit` is angle-driven by the caller, so reversal = negate the caller's angular speed |
| `TargetInfo.predicted_position(t)` / `intercept()` | 0.4–0.8 s ram prediction; `velocity` gives the player's heading for "lateral offset from player velocity" and "unoccupied side" |
| `AttackController` (`driven_by_brain`, `fire_now`) + `AimedAttackPattern` + `BulletPool` + `EnemyBullet` | The Razor's single post-miss pulse, no new weapon code |
| `DroneInterceptorBrain` | ENTER/ORBIT/DASH, dash lock, `_begin_dash()`/`_check_dash_end()` test seams — evolve rather than rewrite (DECISIONS P-8) |
| `tests/helpers/enemy_ai_harness.gd` + `test_enemy_dual_mode.gd`'s `_tick()` | Dual-mode spec; parameterize on a **string label** (`use_parameters(["open_space","assault"])`), never on built harnesses (leak trap in DECISIONS) |
| `tests/helpers/fixture_enemy.tscn` / `fixture_brain.gd` | Contract-level squad tests without real enemies |
| `FormationResource.compute_slots()` + `WaveManager._expand_formation()` | Spawn layouts stay; only the squad id needs threading through |
| `ShipConfig` + `privatise()` + `@export_group` flat fields | Configs for both drones; flatness enforced by `test_config_instance_isolation` |
| `HitEffect` / `ExplosionEffect` (created by `BaseEnemy._ready`) | Death visuals; an explosive profile adds a damage area, not new particles |
| `Health.invincibility_*`, `PlayerBase.invincibility_sec` | Contact-damage pacing already exists on the player side |
| `DefenseProfile` pattern (a Node child, resolved by `BaseEnemy`, default created when absent) | The shape to copy for a `ContactProfile` node, so the offensive side mirrors the defensive side |
| `scripts/strip-sprite-bg.sh`, `scripts/pixellab.sh`, `pixel-art-generation` skill | Sprite pipeline for the two new sprites |

## Conventions that constrain this

- **Single writer of motion** (`test_enemy_mover_single_writer.gd`): brains and `global/enemy_ai/*.gd` must not assign
  `velocity`/`rotation`/`velocity.x|y`, call `move_and_slide`/`move_and_collide`/`look_at`/`rotate`/`set_velocity`
  /`set_rotation`; the root script **and ancestors** of any scene with an `EnemyMover` likewise. A SquadController
  that pushed drones around directly would fail it — it may only hand out *slots/roles*; each brain requests.
- **Brain rules:** accumulated-`delta` clocks, no `Timer`/`create_timer`, randomness only from `brain.rng`
  (Kamikaze's `randi()` variant pick and SectorHub's `randf()` are legacy), player only through `TargetInfo`.
- **One tick:** `BaseEnemy._physics_process` → `brain.tick` → `mover.step`. A squad needs its own update point that
  does not become a second clock per drone (see research approach S-B).
- **Facing:** `rotation = heading.angle() − sprite_forward_angle`; nose-up art sets `sprite_forward_angle = −PI/2`.
- **Configs:** `.tres` wins over the scene; flat fields in `@export_group`s (Movement/Attack/Defense/Tactics/Scoring);
  private copy via `privatise()`; **never write to the loaded resource**.
- **Contact damage from config:** every concrete script must copy `config.collision_damage` onto its `ContactHitBox`
  (`test_enemy_contact_damage.gd`); contact hitbox must share the body's shape id **and** scale
  (`test_contact_hitbox_geometry.gd`); HurtBox must cover the body within 1 px (`test_enemy_hurtbox_geometry.gd`).
- **Design units:** Assault spawns are authored in 640×360 and scaled by `ArenaCamera.WORLD_SCALE`; never
  pre-multiply. AI behaviour, by contrast, is authored in **world px** (Phase 1: the Interceptor's orbit radius
  130 is world px). Both conventions meet at the spawn position only.
- **Dual-mode tests** state assertions relative to the constraint; drive mover-owned bodies with `_tick()`.
- **Signals** declared with their exact arity (`test_signal_emit_arity.gd`): a squad signal like
  `role_changed(drone: Node, role: int)` must match every `emit`.
- **UIDs:** never hand-type; moving files with `git mv` keeps `.uid` sidecars. Deleting scenes: check
  `test_resource_uid_integrity.gd` and `test_project_load_integrity.gd` (loads every `.tscn/.tres/.gd`).
- **Art:** strict top-down, `pixel-art-generation` skill, `scripts/pixellab.sh`, visual check, transparent
  background (`test_entity_sprite_transparency.gd`: < 90% opaque).
- **Logging:** anything per-frame behind `OS.is_stdout_verbose()` (the Kamikaze's despawn `print` is not).
- **Docs:** structural change → `updating-project-docs` skill; per-entity `ENEMY.md` beside each enemy.

## Gates and how they discover the roster (R2.24)

| Gate | Discovery | Covers a new `assault/scenes/enemies/<x>/<x>.tscn`? | Covers `open_space/…` or `global/…`? |
|---|---|---|---|
| `test_enemy_contact_damage.gd` | Hand-written `ROSTER`, no completeness guard | **No — must be added by hand** | No |
| `test_contact_hitbox_geometry.gd` | Hand-written `ROSTER`, no guard | **No — add by hand** | No |
| `test_enemy_hurtbox_geometry.gd` | Hand roster **plus** `test_every_enemy_scene_is_in_the_roster` (sweeps `assault/scenes/{enemies,allies}/<dir>/<dir>.tscn`) | Forced (the guard fails until added) | No |
| `test_entity_sprite_transparency.gd` | Recursive walk of `assault/scenes/{enemies,player,projectiles,hazards,allies}`; floors 12/12 | Yes | No |
| `test_config_instance_isolation.gd` | Sweep `<dir>/<dir>.tscn` + exactly one `*config*.tres`; floor 10 | Yes | No |
| `test_base_enemy.gd` | Sweep of `assault/scenes/enemies`, BaseEnemy roots, floor 10 | Yes (a Ramming profile whose hitbox is off at rest may need a case) | No |
| `test_enemy_mover_single_writer.gd` | Whole `res://` | Yes | Yes |
| `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`, `test_signal_emit_arity.gd` | Whole project | Yes | Yes |

Consequences: (1) the new enemy scenes should live under `assault/scenes/enemies/` (where `BaseEnemy` still is,
until Ph15) even though they also fly in Open Space — that is where five of the gates look; (2) the two hand-written
rosters need the new entries and **lose** `kamikaze_drone` (+ `drone_interceptor` if renamed); the floors
(`_MIN_ROSTER_SIZE = 10`, `_MIN_ENTITIES_WITH_CONFIG = 10`, `MIN_SCENES = 12`) must still hold after deleting one
directory and adding one (net 0 for the Swarm, net 0 for a rename); (3) a *completeness guard* on the two
hand-written rosters is the cheap way to make "gates must cover the new scenes" self-enforcing.

## Dependencies and blast radius

- **Deleting `kamikaze_drone/`** touches: `WaveBuilder.DRONE`, 119 level-1 lines, `station_reinforcements.gd`
  (2 lines + its tests' counts/composition), 4 gate rosters, `test_base_enemy.gd` expectations, `laser_ray.gd`
  comment, `docs/enemy-roster.md`, `docs/architecture/modules/assault.md`, `docs/game-structure.md`,
  `assault/DEVELOPMENT_PLAN.md` (historical — leave), `tests/README.md` mention.
- **Evolving `drone_interceptor/`** touches: `WaveBuilder.DRONE_INTERCEPTOR`, `test_drone_interceptor.gd`
  (15 pins), `test_enemy_dual_mode.gd` (3 interceptor cases), `test_station_reinforcements.gd` (the
  "never a self-managed AI in a squad" guard names `DRONE_INTERCEPTOR`), 4 gate rosters, `ENEMY.md`, roster doc.
  Turning the corridor on changes Assault behaviour → the "1:1 with the pre-port" pins must be re-pinned (DECISIONS).
- **Deleting PatrolDrone** touches: `sector_hub.gd`, `test_patrol_drone.gd`, `steering.gd` comment,
  `open_space.md`; tests that instantiate `sector_hub.tscn` *and add it to the tree* would now spawn a live squad
  (hub-log, module/weapon-unlock, boost-upgrade tests) — they must not start taking damage or gain `enemies`
  group members they count.
- **Level 1 balance:** removing rails turns 3–4 s fly-throughs into AI that stays until killed unless an exit rule
  exists — changes concurrency, section carry-over, cloud_descent's ENEMIES_CLEARED wait, and score (escape vs kill).
- **`BulletPool` change** (if done) touches every pool user: interceptor, gunship, light assault ship, ally
  fighter, station gunnery, racer weapon, player `weapon_behavior`.
- **`BaseEnemy`** is an ancestor script of every mover-driven scene → any contact-profile hook there is swept by the
  single-writer gate (it must not write motion) and by `test_base_enemy.gd`.

## Risks, edge cases, testing requirements

Risks are expanded, with mitigations, in `2-research.md` §4. Headlines:

- **C1 Assault lifetime.** The corridor forces re-entry and nothing culls a non-dashing AI enemy → migrated drones
  never leave. Needs an explicit Assault "disengage and exit" path (release the constraint, then the cull rect).
- **C2 Section flow.** DURATION sections do not clear survivors (they drift into the enemy-free asteroid belt);
  cloud_descent waits for them (10 s fallback then escape penalty).
- **C3 Concurrency/difficulty.** 119 lines within ~170 s of level time; with 3–4 s legacy lifetimes the concurrent
  count is low; AI drones that live 8–12 s multiply it 2–3×.
- **C4 Hub safety.** Player spawns *inside* the ambient spawn radius; mission-trigger dwell cancels above 150 px/s.
- **C5 Ramming hitbox toggling.** Enabling a `ContactHitBox` that already overlaps the player must register (Godot
  reports the overlap on the next physics step after `monitorable`/shape enable); disabling from inside a physics
  callback must use `set_deferred`.
- **C6 Squad bookkeeping.** Members freed mid-tick (`queue_free` on contact) → dangling references; last member
  dies → squad must free itself; a squad of 1 → no roles; rails suspend a member → it must drop its role.
- **C7 Determinism.** Every random choice (phase offsets, reversal timer, fake-vs-real, variant sprite) on
  `brain.rng`; the squad's own choices on a seeded RNG, or tests cannot pin reassignment.
- Edge cases for tests: no player (`TargetInfo.has_target == false`); player stationary (prediction = position,
  "unoccupied side" still decidable); both flank sides occupied; lead dies *during* its burst; squad of 1/2/7;
  corridor edge during a burst (boost is still filtered); dash that never "misses" because it hit (pulse must not
  fire after a hit); overshoot pass budget exhausted.

## Open questions for the plan

1. Rename `drone_interceptor/` → `razor_drone/` (`git mv`, class `RazorDrone`, keep UIDs) or add a new directory and
   delete the old one? (Research leans rename — §3 approach R-A.)
2. What does an Assault AI drone do when its pass budget/time is spent — exit (escape penalty, legacy parity) or
   stay (ENEMIES_CLEARED semantics)? Proposed: disengage and exit via the nearest side/bottom, time budget derived
   from the legacy path's on-screen time.
3. Which wave spawn groups become one squad: one formation = one squad, one `b.wave()` = one squad, or an explicit
   `.squad(&"id")` in `WaveBuilder`?
4. Where does the SquadController tick — its own node's `_physics_process` (a second clock) or driven by the first
   live member's brain? (Research leans a plain `Node` ticked by members with a frame guard — §3 approach S-B.)
5. Which enemy carries which contact profile, and does **Explosive** have a consumer in this phase? (Kamikaze
   lineage suggests the Swarm Drone's ram impact.) Does the blast hit other enemies?
6. Station reinforcements' BOTTOM squad: migrate to rail-driven Swarm Drones (scope creep but lets `kamikaze_drone/`
   be deleted) or keep the Kamikaze scene alive until Ph11?
7. `BulletPool` injectable container: needed at all, given every current parent chain already satisfies it?
8. Hub anchor: same origin anchor as today with a perception radius smaller than the spawn distance, or move the
   anchor away from the player spawn?
