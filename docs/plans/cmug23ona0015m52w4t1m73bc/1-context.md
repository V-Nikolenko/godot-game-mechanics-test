# Context — Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones

Epic `cmug23ona0015m52w4t1m73bc`, research task `cmug23onf0019m52wp7po891o`, written 2026-10-27 against
`agent/auto-dev` at `cd1b0b5` (Phase 7 closed). Idea folder: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`
(`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` = "IDEAS", `ENEMIES.md`, `DECISIONS.md`).

Read with `2-research.md`, which starts with the **scope check** (what changed against the phase's scope
as written) and holds the external findings, the candidate approaches and the recommended answers to
the open questions at the end of this file.

Every `file:line` below was read on this commit. Line numbers drift: cite the symbol when you build on one.

---

## Requirements from the attached documents

Quoted briefly; R-numbers are this phase's and are reused in `2-research.md` and (expected) in the plan's
coverage table.

### Energy weapons (IDEAS §11.3)
- **R8.1 Beam** — "Immediate line with telegraph."
- **R8.2 Sweeping Beam** — "Rotates continuously for a short window."
- **R8.3 Lance** — "Narrow high-damage line with very short active duration."
- **R8.4 Pulse Ring** — "Expanding radial attack that forces movement around the enemy."
- **R8.5 Twin-Beam / Endpoint Laser** — "Two drones or emitters define the endpoints of a continuous laser." It
  can "move the endpoints together, sweeping the beam through the player", "hold the endpoints while the host
  ship moves", "rotate the beam around an anchor point", "damage other enemies caught in the line". "This
  should be treated as a real projectile/beam family, not as a boss-only special effect."
- **R8.6 Moving Laser Wall** — "Two endpoint drones form a beam segment and translate that segment toward the
  player, producing a readable `|---|` moving wall. A controller ship can fire the endpoints toward predicted
  positions so the wall cuts off escape routes."
- **R8.7 (epic)** — "every beam damages anything crossing its line, other enemies included." The epic also
  says the family "generalises what the Space Station's laser phase and rotating hull already do".

### Stationary Defense Turret (IDEAS §6.5, all of it except mounting on large ships → Ph10)
- **R8.8 Role/size** — "persistent defensive structure placed around stations, wrecks, objectives, mining sites,
  or narrow routes. It is an enemy even though it does not move." "48–96 px for a standard turret; larger
  128–192 px variants can act as heavy emplacements."
- **R8.9 Movement/aim** — "None. The turret rotates its weapon mount and uses predictive targeting."
- **R8.10 Weapon variants** — "burst cannon", "sweeping beam", "rocket battery" (epic: "reusing phase 5's
  rockets"), "short-range pulse ring", "sniper lance".
- **R8.11 Groups** — "positioned so that the player cannot simply park in one safe direction. Groups of 2–4 can
  create overlapping fire lanes."
- **R8.12 Destruction** — standalone; "mounted on larger ships/stations" (→ **Ph10**); "protected by a shield
  generator"; "connected to a jamming or power structure" (jammer link → **Ph9/Ph20**). "Destroying the power
  source can disable the entire turret group."
- **R8.13 Assault** — "Turrets become static hazards in the scrolling corridor and can be mounted on large boss
  structures or encounter geometry." (Boss mounting → Ph10/Ph11.)

### Twin-Laser Drones (IDEAS §6.10)
- **R8.14 Role** — "Two small drones act together as a large moving laser weapon. The drones are the weapon
  endpoints."
- **R8.15 Attack A (closing laser)** — "move to opposite sides of the player, establish a beam between
  themselves, and then fly the beam through the player's position. The beam damages anything intersecting the
  line, including other enemies." "The beam length and relative spacing should remain stable during the
  attack."
- **R8.16 Attack B (V-launch → moving wall)** — "A controller ship launches two laser drones in a V-shaped spread
  toward two predicted points around the player's path. Once they reach those points, they align into a
  separated `|---|` beam segment and fly that entire segment toward the player together."
- **R8.17 Counterplay** — "move around the beam endpoints", "destroy one drone to collapse the laser", "bait the
  drones into terrain or a gravity well", "use the beam to damage the enemy formation".
- **R8.18 Assault** — "the endpoints can be constrained to the corridor while the beam sweeps upward/downward or
  across the player's lane."

### Structures (IDEAS §18.6)
- **R8.19 Defensive structures** — "stationary turrets, shield generators, jammer towers (→ Ph9), missile
  batteries, laser emitters".
- **R8.20 Energy structures** — "temporary laser barriers", "stationary laser walls".
- **R8.21 Enemies understand them** — "Enemies should understand these objects through the same
  perception/steering system used for the player … avoid damage zones, accidentally hit hazards". IDEAS
  §3.2.5 lists "laser walls" among the hazards the shared query must cover.

### Art (IDEAS §21–23), placement and tests (IDEAS §40, epic)
- **R8.22 Art** — strict top-down; silhouette + faction accents + gameplay lights ("red glow = armed, yellow =
  charging, white = locked shot, cyan/blue = shield, orange = overheating, dark/off = destroyed module");
  "Do not recolor the entire enemy according to state." §23: every specialist has "at least one visually
  readable state change". Sizes: 24–36 px swarm (the twin drones are "small"), 48–96 / 128–192 px turrets.
- **R8.23 Placement** — "join Assault waves and the hub's ambient spawn" (epic).
- **R8.24 Tests** — "Tests in both harnesses cover beam activation and telegraph timing, beam damage to allies,
  power-source shutdown of a turret group, and the moving wall keeping its length" (epic); IDEAS §40 "beam
  activation", "telegraph duration", "Every enemy should have at least one automated test in both Open Space /
  Assault".
- **R8.25 Design checklist (IDEAS §43)** applies to the turret and the twin drones (silhouette, preferred
  distance, telegraph, works alone, combines, deterministic tests).

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/hazards/laser_ray/laser_ray.gd` (`LaserRay`) + `laser_ray.tscn`, `laser_wall.tscn` | The only beam today. Area2D `HitZone` (one `RectangleShape2D` 56 × `segment_count`·128 px, default 1536 px along local +Y), phases `INIT → INCREASE → IDLE → DISSOLVE → DONE / OFF` advanced by **sprite `animation_finished`**, a 0.1 s **`Timer`** re-emitting on every overlapping hurtbox in IDLE; damage is `received_damage.emit(9999)` (`_KILL_DAMAGE`, a one-hit kill, `:73`, `:245-264`). Default mask `128 \| 256 \| 512` (`:79`) — **it already hits enemies**; `hit_mask_override` replaces it (`:47-56`, `:114`). Not blocked by anything, not in the `Hazards` registry; has a race-hazard contract (`is_lethal_now`, `is_safe_to_cross`, `danger_rect`). | The "generalise the station laser" starting point — and the reason a new component is needed: kill damage, animation-clocked phases (not hand-tickable, length fixed by sprite frames), `Timer`s (the brain rule forbids them), no blocking, no registry. Used by the race gauntlet, level 1 laser columns and the station, all pinned. |
| `assault/scenes/levels/edelia/1/level_1_director.gd:62-87,172-186`; `level_1.tscn:46-47` | Level 1 lights LaserRay **columns** on a schedule (`_spawn_laser_columns(columns, warn 3.0, active 4.0)`, 11 calls in deep_space / planet_approach / cloud_descent) and instances one static `LaserWallWave` (12 rays, `warn_duration` 3.0). | These are today's "temporary laser barriers" in Assault. They kill AI enemies (mask has 512) and no AI avoids them; **no test replays them** (the level-1 replays drive `WaveManager` only, `grep` finds no test touching `_spawn_laser_columns`). See scope check S3. |
| `assault/scenes/enemies/space_station/station_laser_phase.gd` (`StationLaserPhase`), `space_station_config.gd` | After `armor_broken`: volleys of `laser_beam_count` (2) LaserRays at `emitter_radius` 140, `hit_mask_override = 128` (player only), warn 1.4 s / active 2.0 s / interval 6.5 s; the **hull** rotates at 0.5 rad/s (`_station.rotation += …`, `:121-124`) and carries the beams. | The "rotating hull sweep" the epic names. Pinned by `test_station_laser_phase.gd` (lethal only when active, never hits the station, angles deterministic, config wins). The station rework is Ph11; keep byte-identical here. |
| `assault/scenes/enemies/space_station/station_turret.gd` (`StationTurret`, `Node2D`, not a `BaseEnemy`) + `station_gunnery.gd` | Four 64×64 turrets under a `Turrets` node, own `HurtBox` (512 / 1121, r 26) + `Health` (120), `destroyed(turret)`; on death they stay as wreckage sprites. They have **no aim logic**: `StationGunnery` sets `global_rotation = dir.angle() + PI/2` and fires a `RadialAttackPattern` (`aim_at_player`) from the station's pool. `SpaceStation.is_armored()` = any turret alive. | The project's only turret and its "group protects something" rule — the pattern Ph10 generalises to modules. The new turret is a standalone enemy; its mount is designed so Ph10 can mount it. |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd` | The player's mining beam: one `intersect_ray` (bodies, mask `1 \| 1024`, 1200 px), blocked unless the collider answers `is_laser_blocking() == false`; targets in groups `enemies` / `asteroids` whose centre is within 12 px of the segment; **direct emitter** `received_damage.emit(n)` from an accumulated `beam_dps · delta` (12 dps). | Precedent for a beam that is (a) blocked by bodies (wrecks, asteroids, armoured Ram) and (b) found by a group scan with a centre-distance test, not by `Area2D` overlap. A turret/structure root on layer 1 would block the player's beam (the station root sits on layer 0 for that reason). |
| `global/hazards/` (`Hazards`, `HazardInfo`, `HazardField`, `HazardDrift`) | Static registry; `around(pos, reach)`; `pulse_damage(tree, at, radius, damage)` (centre distance, groups `enemies` + `player`, direct emit — both sides); `HazardInfo` (`kind`, `radius`, `avoid_weight`, `velocity`, `line_of_sight_blocker`, claims …). **Geometry is circles only** (`contains`, `falloff`, `penalty_at` and `Steering.context_avoid` all use distance to `position`). | DECISIONS Ph6: "Ph8 laser walls (`&"laser_wall"`) … join the same registry with no change to the AI". A wall is a **segment**, so either `HazardInfo` gains segment geometry or a wall registers as a bead chain (S4). |
| `global/enemy_ai/steering.gd::context_avoid` (`:236-299`), `enemy_mover.gd::_avoid` (`:279-296`) | One danger cone per info from centre, `radius`, `avoid_weight`; skipped while boosting; "clear way returns `desired` bit-identical". | Where segment avoidance lands; the Ph6 pass-through rows must stay green. |
| `global/enemy_ai/` (`EnemyBrain`, `EnemyMover`, `TargetInfo`, `EngagementBudget`, `AnchorIdle`, `SquadController`, `BurstClock`, `LineOfSight`, `Steering`) | The Ph1–Ph7 AI stack. `BaseEnemy._physics_process` ticks the brain and calls `mover.step()` **only if a mover exists** (`base_enemy.gd:115-120`) — a brain-only enemy works. `is_ai_driven()` is false without a mover (`:148`), so it refuses tows. | A turret can be a brain-only `BaseEnemy` (or carry a mover only for the Assault drift, S6). Twin drones are ordinary mover-driven enemies; the pair coordination is a new object beside `SquadController`. |
| `assault/scenes/enemies/base_enemy.gd` | Damage → flash → `died` → explode → maybe wreck → `queue_free` in one call; `sprite_forward_angle`; `suspend_ai()`; `repair()`; does **not** join `enemies` (each subclass does). Default `DefenseProfile` mask 1121. | Turrets, generators, power sources and drones all need `died`, scoring and the roster gates; whether the generator/power source are `BaseEnemy`s is open question Q3. |
| `global/components/` — `HurtBox` (absorber slot, `hit_absorbed`), `HitBox` (`DamageType {LASER, ROCKET, CONTACT}`), `EnemyShield` (arc / bubble, `sustain_mode`, `heartbeat` 0.3 s), `ArmorQuery`, `ArmorPlate`, `ContactBlast` (layer 256, never hits enemies), `ContactProfile` (`NONE/COLLISION/RAMMING/EXPLOSIVE/ARMOR`), `StateLight` (`OFF/ARMED/CHARGING/COMMIT` = clear/red/yellow/white), `BulletPool` (`persist_after_owner_death`; container = `get_parent().get_parent()`, `:63`), `ProjectileLifetime`, `EmpPulse`, `AttackController` (`enabled`, `driven_by_brain`, `tick`, `fire_now`). | Everything the shield generator (sustained `EnemyShield` bubbles — the Support Ship's projected-shield path), the telegraph lights and the burst-cannon / rocket-battery turrets reuse. |
| `global/resources/attack/*_attack_pattern.gd` | `AimedAttackPattern`, `ForwardAttackPattern`, `GatlingAttackPattern`, `RadialAttackPattern` (`bullet_count`, `arc`, `aim_at_player`, `spawn_radius`; `base_angle` is world-space). | The burst-cannon turret is an `AimedAttackPattern`/`BurstClock` user; nothing beam-shaped exists here. |
| `assault/scenes/projectiles/enemy_rockets/` (`EnemyRocket`, `EnemyRocketScenes`) | Ph5 rocket family; launcher contract `launch_velocity()` + `rocket_clear_radius()`, `launch(dir, aim_point, launcher)`, pool sizes from `pool_size_for(kind, cfg)`; tuning lives in each rocket scene. | The rocket-battery turret fires these unchanged. |
| `assault/scenes/projectiles/enemy_ordnance/mines/pulse_ring.gd` (`PulseRing`) | Ph7's **visual-only** violet ring a PULSE mine leaves (0.3 s, no collision). | **Name collision**: the §11.3 Pulse Ring weapon cannot be `class_name PulseRing`. |
| `open_space/scenes/levels/sector_hub.gd::_spawn_patrol()` (`:71-89`), `sector_hub.tscn` `TacticalSpace` (`:91-267`) | 15 seeded draws (rings 1300/1500/1700/1900/2600); `TacticalSpace`: well (2956, 1225), anomaly (3656, 1225), station module (2457, 1203), cargo platform (2495, 1033), satellite (2588, 887), debris, minefield (3300, 560); `HazardContainer`. | Where the hub turret group and the twin-drone patrol go. New draws must append after draw 15. |
| `tests/integration/test_sector_hub_patrol.gd::_patrol_groups()` (`:814-835`), `_element_radius()` (`:838-855`) | Clearance sweep; `_element_radius()` knows `Minefield`, `HazardField`, `DebrisFragment`, `Wreck` and **returns 0.0 for anything else**. | A turret group / laser wall in the hub needs a case, or the sweep silently treats it as a point. |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Sections deep_space (DURATION 30 s), asteroid_belt (DURATION 30 s), station_assault (ENEMIES_CLEARED, timeout 180 s), planet_approach (DURATION 110 s), cloud_descent (ENEMIES_CLEARED). | Turrets (persistent structures) and anything leaving persistent beams/rockets stay out of `ENEMIES_CLEARED` sections, the Bomber/Mine Layer precedent. |
| `assault/scenes/systems/wave_builder.gd` | Fluent spawns; an entry with no `.move()` gets no path mover (`wave_manager.gd:217-231`): `b.space_station().at(0,-90)` is the static precedent; `b.laser()` exists (`:102`). | A turret group needs a `WaveBuilder` entry (and possibly a group scene). |
| Roster gates: `test_enemy_hurtbox_geometry.gd` (hand `ROSTER` + sweep `:358`), `test_contact_hitbox_geometry.gd` (`:280`), `test_enemy_contact_damage.gd` (`:246`), `test_config_instance_isolation.gd` (automatic; one `*config*.tres` per dir), `test_base_enemy.gd` (automatic; post-ready hurtbox mask must be 1121, generic lethal flow unless listed in `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`), `test_wreck.gd` (`_SHIP_SCENES` hand list; "no hurtbox larger than its body"), `test_entity_sprite_transparency.gd`, `test_enemy_mover_single_writer.gd` | Every `assault/scenes/enemies/<dir>/<dir>.tscn` with a `BaseEnemy` root is swept automatically. | Each new enemy dir (turret, twin drone, controller, and the generator / power source if they are `BaseEnemy`s) must satisfy all of these or be listed. A moverless root is not in the single-writer gate's roster B, so it may write its own rotation — but a turret should rotate a **child mount**, never the root (Ph10 mounts it on a moving hull). |
| `tests/README.md` → *Gate time* (from `:414`) | Ph7 closed at **GUT 218.44 s, 2344 tests**, ceiling 240 s; "Phase 8 should recover time first if it plans more than that." Slowest: `test_fighter_squad.gd` 63.7 s, `test_level1_fighter_fire_density.gd` 32.3 s. | Phase 8 is large (three new enemies, two structures, a weapon family); it will need a gate-room task first, like Ph5 t1 and Ph7 t1. |
| `docs/architecture/modules/global.md:246-247`, `PROJECT.md:274` | Define **direct emitters** (beam, nova, dash, shield overload, engine boost, laser ray): they call `received_damage.emit()` themselves and bypass shields and plates. | The enemy beam's damage path must be placed relative to this convention (S5). |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/enemy_ai/enemy_brain.gd` | `tick(delta)` on physics, `on_suspended()`, `accepts_tow()` (must be false in every telegraphed phase — DECISIONS Ph5), `can_see_player()`, seeded `rng`, no `Timer`s. Turret, drone and controller brains extend it. |
| `global/enemy_ai/enemy_mover.gd` | `request_velocity`, `face_toward`, **`boost(dir, speed, duration)` = a committed run that skips avoidance but keeps drift** (DECISIONS Ph6: "later committed runs (Ph8 twin-laser sweep …) use boost"), `release_constraint()`, `own_velocity()`, `max_turn_rate`, hazard profile. |
| `global/enemy_ai/target_info.gd` | `intercept(from, shot_speed)` (`{ok, point, time}`), `aim_direction(from, shot_speed, accuracy)` — the turret's predictive aim and the controller's "predicted points". |
| `global/enemy_ai/engagement_budget.gd`, `anchor_idle.gd` | Assault budget (active only under an `ArenaCamera`), hub idle/notice/return — the drone and controller shells copy the Mine Layer / Missile Corvette template. |
| `global/enemy_ai/squad_controller.gd` | Shared-coordinator precedent (RefCounted, roles, sides) for the twin-drone pair and the turret group's fire-lane assignment. |
| `global/enemy_ai/burst_clock.gd` | Burst-cannon cadence (count, gap). |
| `global/enemy_ai/line_of_sight.gd` | Opt-in blockers (`asteroids`, `blocks_line_of_sight()`); a beam clipped at cover uses the same rule. |
| `global/components/enemy_shield.gd` + `HurtBox.set_absorber` | A shield generator **sustains** a 360° `EnemyShield` bubble on each turret (`sustain_mode`, `heartbeat`, lapse on the generator's death) — exactly the Support Ship's `ProjectedShield` path (`support_ship_brain.gd::_make_shield`). Absorbed hits consume the bullet. |
| `global/components/state_light.gd` | Telegraph colours (yellow CHARGING, white COMMIT, red ARMED, off). |
| `global/components/contact_profile.gd` | `NONE` for structures (a turret base should not ram), `COLLISION` for drones. |
| `global/components/bullet_pool.gd` | `persist_after_owner_death` for the rocket battery; **container resolution is the grandparent** — matters if turrets are children of a group node (S7). |
| `global/hazards/hazards.gd` | Registry, `around()`, `container()`, `hurt_box_of(ship)`, and `pulse_damage()`'s both-sides group scan — the shape of the beam's target scan. |
| `assault/scenes/projectiles/enemy_rockets/` | Rocket battery ammunition; `EnemyRocketScenes.pool_size_for()`; launcher contract. |
| `assault/scenes/projectiles/enemy_bullet/rounds/` | Burst cannon rounds (Pulse 8 dmg, Heavy Shell 20 dmg, no consumer yet — Ph4 handed it to Ph10). |
| `assault/scenes/hazards/laser_ray/` sprites (`giant_lasser.png` 128×128 frames) | Possible beam art source; the beam's own draw is better a `Line2D` (the `PiercingBeam` / `RailTrail` / `MineWake` precedent) so length and width are free. |
| `assault/assets/sprites/enemies/laser_wall.png` (92×84, orphan, uid `uid://0xs2qflphxvm`) | Red/black-striped barrier art referenced nowhere; candidate emitter-post art after a transparency check. |
| `tests/helpers/enemy_ai_harness.gd` + `test_enemy_dual_mode.gd` | Dual-harness specs (`open_space()` / `assault()`, label-parameterised — never `use_parameters([HARNESS…])`). |
| `tests/helpers/fixture_enemy.tscn` | Fixture victim for "beam damages allies" rows (add a shape and `enemies` group at runtime — the Ph7 convention). |
| `tests/helpers/specialist_exit_probe.gd`, `level1_slice_replay.gd` | Measured exits and level-1 slice replays for the twin drones / controller in Assault. |
| `assault/scenes/enemies/mine_layer/` | The current specialist template: root + `EnemyMover` + `Brain` + `StateLight` + per-kind root `BulletPool`s, flat config (`@export_group`s), `_apply_config`, rail fallback in `_process` while suspended, `WaveBuilder` const + helper, `ENEMY.md`. |

## Conventions that constrain this

- **Composition, config-driven, flat configs.** Every new enemy gets a flat `*Config extends ShipConfig`
  (`@export_group` sections, no nested resources/arrays/dicts — `test_config_instance_isolation`), one
  `*config*.tres` per directory, privatised. **Weapon tuning lives in the weapon scene's exports** (the Ph5
  rocket rule, the Ph7 mine rule), so a beam/lance/ring kind is identical whoever fires it (turret, drone,
  Ph10 module, Ph11 fortress).
- **Brain/mover split.** Brains request; only `EnemyMover` writes `velocity`/`rotation` and calls
  `move_and_slide()` (`test_enemy_mover_single_writer.gd`, empty allowlist). A turret's aim is a child
  mount's rotation (allowed: the gate forbids `actor.rotation` / `self.rotation`). Ticks on physics, clocks
  are accumulated `delta`, randomness from `brain.rng`, **no `Timer` nodes** in AI code — so the beam
  component must be hand-tickable too, unlike `LaserRay`.
- **Telegraphs are protected.** `accepts_tow()` is false in every telegraphed/committed phase; a telegraph is
  never moved by anyone but its own brain. A committed run is `mover.boost()`.
- **Hazards.** A hazard is a node answering `hazard_info()`; registers in `_enter_tree()`/`_exit_tree()`, or
  on `launch()` if pooled (Ph7). Runtime hazards spawn **deferred** through `spawn_into()` into
  `Hazards.container(tree)` (group `hazard_container`), never into the enemy container, never in `enemies`.
  A hazard never writes a ship's velocity. Pass-through rule: with no hazard in reach, motion is
  bit-identical. Wall kind is `&"laser_wall"` (DECISIONS Ph6).
- **Friendly-fire record so far.** Rocket *impacts* hurt enemies, rocket *blasts* only the player (Ph5);
  environmental blasts and placed (`ALL`) mines hurt both sides through `Hazards.pulse_damage` (Ph6, Ph7);
  enemy-laid mines are player-only. **Beams and the rest of weapon blasts are explicitly Ph8's to decide**
  (`DECISIONS.md` Ph5 deferred table, Ph6 and Ph7 changes). The epic answers the beam half: R8.7.
- **Direct emitters bypass `EnemyShield` and `ArmorPlate`** (global.md); an armoured hull refuses them in its
  own `_on_received_damage` (Ram, station). Any later armoured entity uses `is_armored()` / `deflects_hit()`.
- **Every projectile has exactly one owner** (CLAUDE.md). A beam is not a projectile but its lifetime must
  still have one owner (the emitter), and persistent ordnance hand-over uses `persist_after_owner_death`.
- **Assault.** Design units 640×360 × `ArenaCamera.WORLD_SCALE` 2.0, never pre-multiplied. Static things
  drift down at 60 px/s (wreck, minefield precedent). One attack per specialist life, proven by an
  **attack-in-budget row**; persistent-ordnance enemies never in `ENEMIES_CLEARED` sections (guard rows in
  `test_engagement_deadline.gd`); specialists count in the frozen 2.5× density gate of
  `test_level1_specialist_spawns.gd`. `EnemyWorld.view_rect()` is the visible rect; nothing under `global/`
  references `ArenaCamera`.
- **Every new enemy joins group `enemies` in its own `_ready()`** (placed `ALL` mines and `pulse_damage` rely
  on it — DECISIONS Ph7 gap table).
- **Art.** PixelLab via the `pixel-art-generation` skill, strict top-down (`view: "high top-down"`,
  `isometric: false`), saved with `scripts/pixellab.sh`, each image opened and checked; hull art nose-down
  (`sprite_forward_angle` `PI/2`), rockets nose-up; no texture ≥ 90 % opaque
  (`test_entity_sprite_transparency.gd`); faction palette kept, only state lights change colour.
- **Logging** behind `OS.is_stdout_verbose()`; signals declared with their emitted arity
  (`test_signal_emit_arity.gd`).
- **UIDs.** Never hand-type or copy a `uid://`; leave references UID-less or mint one
  (`tests/README.md`).
- **Gate time** is budgeted: GUT ≤ 240 s; `scripts/gate-time.sh` before/after each task; real-physics waits
  on the 8× clock except `LevelDirector` waits (1×).

## Dependencies and blast radius

- **New global component(s) for beams** touch nothing existing if built beside `LaserRay`. Converting
  `LaserRay` itself would ripple into the race gauntlet (`race_hazard` contract), level 1 columns, the
  `LaserWallWave`, the station laser phase and `test_laser_ray_hit_mask.gd` / `test_station_laser_phase.gd`.
- **Segment hazards** change `HazardInfo`, `Hazards.around()` and `Steering.context_avoid()` — the code every
  mover-driven enemy runs every tick. Ph6's pass-through and avoidance rows (`test_context_avoidance.gd`,
  `test_hazards.gd`, `test_hazard_field.gd`) and every level-1 replay are the blast radius. A bead-chain
  registration avoids touching them.
- **Beams hitting enemies** change kill attribution: a beam kill goes through `_on_health_changed` and sets
  `was_killed`, so `ScoreTracker` would credit the player for an enemy killed by an enemy beam (as it
  already does today for LaserRay column kills, unverified in play). Decide whether that is wanted (Q8).
- **Turret groups** introduce the first *structure-group* relation (power source → turrets, generator →
  turrets). Ph9 jammers and Ph20 "jammer-linked turret groups" will hang off it; Ph10 mounts turrets on
  modules; Ph11 fortress outer batteries and shield nodes reuse the beam family, the turret mount and the
  generator rule. The group API is therefore a cross-phase contract.
- **Rocket-battery turret under a group node** is the first *nested* launcher if turrets are parented under a
  group: `BulletPool`'s grandparent container would resolve to the group node (S7). DECISIONS has deferred
  container injection three times "to the first nested launcher".
- **Hub**: new draws after draw 15 keep earlier seeds; `test_sector_hub_patrol.gd` needs `_element_radius()`
  cases for a turret group and a laser wall.
- **Level 1**: new placements move density peaks (`test_level1_specialist_spawns.gd`), deadline rows
  (`test_engagement_deadline.gd`) and possibly `test_level1_fighter_fire_density.gd` if turret rounds count as
  fighter-family shots (they would not unless placed in its sections' lists).
- **Gate time** — three enemies, two structures and a weapon family at Ph7's per-task cost (~2–5 s each)
  overruns the ~21.6 s headroom; a gate-room task is a prerequisite.

## Risks, edge cases, testing requirements

- **Continuous overlap.** `Area2D.area_entered` fires once per entry; a target that stays in a beam is only
  re-damaged by a re-emit loop (LaserRay's 0.1 s `Timer`). A beam that moves (sweep, twin drones) also needs
  its shape moved every tick, and Area2D overlaps refresh only on a physics step, so hand-ticked tests would
  see stale overlaps. A geometric scan (segment-vs-circle over groups, the player-beam and `pulse_damage`
  precedent) is deterministic in hand-ticked tests.
- **Damage cadence vs i-frames.** The player has 0.5 s invincibility after any hit (`player_base.gd:32`) and
  one shield charge absorbs one hit; enemies have no i-frames, so a 0.1 s re-emit that is harmless to the
  player shreds an enemy. Cadence must be per target, explicit, and the same for both sides.
- **Tunnelling.** A sweeping beam or a twin-beam moving at boost speed can jump over a small target between
  ticks (a 600 px beam rotating at 1 rad/s moves its tip 10 px/tick at 60 Hz; a wall advancing at 500 px/s
  moves 8.3 px/tick). The hit test should sweep the area between the previous and the current segment
  (quad/triangle), or cap angular/linear speed against the smallest hurtbox (Swarm Drone ≈ 12–14 px radius).
- **Self-hit and partner-hit.** The emitter, its own group's structures and the twin pair's endpoints sit on
  or next to the line; the beam must exclude its owner set (station precedent: `hit_mask_override = 128`).
- **Twin pair failure modes.** One drone dies, is railed, is towed, is dragged by a well, is blocked by a
  wreck, or lags behind → the beam must collapse (or go non-lethal) rather than stretch; "length stable" must
  be asserted as `|A − B| ∈ L ± tolerance` every active tick, in both harnesses and with drift applied.
- **Beam vs cover.** Whether a wreck/asteroid clips the beam (player beam precedent: yes) — needs a physics
  ray, so rows involving cover run on real physics (8× clock); the plain-geometry rows stay hand-ticked.
- **Shields/plates.** If beams are direct emitters, a projected/generator shield does not stop a beam, and a
  plated Ram refuses it (hull rule). If beams were `HitBox`es, shields would absorb them but a continuous
  `HitBox` overlap only reports once.
- **Power-source shutdown.** All turrets of a group stop firing in the same tick; beams mid-telegraph cancel,
  active beams dissolve, rockets already in flight persist (pool hand-over), lights go dark; the group must
  not restart. A turret killed before the source does not resurrect; a source killed while its turrets are
  rail-suspended or off-screen still disables them. Order of `died` vs `queue_free`.
- **Assault structures.** Static turrets must leave the corridor (drift 60 px/s and free past the bottom),
  must not hold an `ENEMIES_CLEARED` section, and their fire must not be counted as a fighter-density
  regression unless intended.
- **Telegraph fairness.** The warning must be at least the reaction window at both modes' speeds; the Ph4
  floor is `lock_seconds` 0.5 s ("the reactable floor"); the Ph7 warning rule is a speed inequality from
  scene exports. A beam needs an analogous, gate-asserted inequality (e.g. warning time ≥ the time the player
  needs to clear the beam's half-width at cruise speed, plus reaction).
- **Testing requirements (R8.24):** beam activation (not lethal in TELEGRAPH, lethal in ACTIVE, off after),
  telegraph timing from scene exports; beam damages a fixture ally (and does not damage its emitter / pair /
  own group if so decided); power-source death disables every group turret (fire stops, beams cancel), in
  both harnesses; moving wall keeps length within tolerance while advancing, in both harnesses; every new
  enemy: roster gates, dual-mode spec, hub clearance, attack-in-budget rows and density rows if placed in
  level 1, lifetime rows for any new projectile.

## Open questions for the plan

Recommended answers are in `2-research.md` §2.12.

- **Q1** Build a new beam component (`EnemyBeam`) beside `LaserRay`, or convert `LaserRay` into the family?
- **Q2** Beam hit detection: geometric group scan, `Area2D` with a re-emit loop, or a physics shape query?
- **Q3** Are the shield generator and the power source `BaseEnemy`s (scored, in `enemies`, swept by the roster
  gates), or plain structures (`Wreck`-like) with `Health` + `HurtBox`?
- **Q4** Friendly fire: do beams hit (a) every enemy, (b) every enemy except the emitter's own group /
  pair, (c) the emitter itself never? Does the Pulse Ring (a weapon blast) hit enemies too?
- **Q5** Damage model: per-target re-hit interval, damage numbers per kind; is the Lance a one-hit?
- **Q6** Are beams blocked by wrecks / asteroids (cover)?
- **Q7** Segment hazards: extend `HazardInfo`/`context_avoid`, or register a wall as a chain of circles?
- **Q8** Should a kill by an enemy beam score for the player?
- **Q9** What is the "controller ship" of Attack B: a new specialist, an existing ship (Missile Corvette,
  Support Ship), or a structure? Is it in this phase at all?
- **Q10** How do turrets behave in Assault: drift with the corridor (wreck rule) or hold?
- **Q11** Turret group shape: a `TurretGroup` parent node owning its members, or a non-parent coordinator
  (keeps the `BulletPool` grandparent rule intact)?
- **Q12** Should the level-1 LaserRay columns / `LaserWallWave` become registered `&"laser_wall"` hazards so
  AI enemies avoid them?
- **Q13** Which existing gates' rosters must each new scene join, and what is the gate-time budget for the
  phase?
