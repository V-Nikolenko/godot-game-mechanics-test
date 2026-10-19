# Context — Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields

Epic `cmug23om70001m52wqfwclf3l`, research task `cmug23omg0005m52w238jt91z`, 2026-10-19. Facts read at `4126091` on
`agent/auto-dev`. `file:line` citations are to that commit; anything not read directly is marked **(inferred)**.
`2-research.md` (next to this file) holds the scope check, the outside findings, the candidate approaches and the
recommendations. This file is the inventory they are built on.

Sources read for this file: `CLAUDE.md`, `docs/architecture/PROJECT.md`, the idea's `DECISIONS.md` (Phase 1 plan +
roadmap §7, Phase 2 / 4 / 5 *as built*, Phase 4 planned names), `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §2.4 /
§7 / §8, `docs/plans/cmufs7elw001pnm2xr3b6fteb/2-research.md` (format and the Ph5 scope check), `tests/README.md` →
*Gate time*, and the code below.

---

## Requirements from the attached documents

`IDEAS` = `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`; `EPIC` = this phase's board text.
Only the sections this phase's scope names are listed; the scope check in `2-research.md` §0 says which of them an
earlier phase already covered or a later phase owns.

### Shared hazard perception (IDEAS §3.2.5)
- **R6.1** "All combat-capable enemies should have optional access to a lightweight hazard field query": `HazardInfo`
  with `position`, `radius`, `pull_force`, `damage_per_second`, `movement_penalty`, `disables_abilities`,
  `line_of_sight_blocker`.
- **R6.2** "The same AI [can] reason about gravity wells, mines, jammers, wreckage, laser walls, and other encounter
  structures. The enemy does not need a bespoke script for every hazard." The contract must fit Ph7 mines, Ph8 laser
  walls and Ph9 jammers without change, even though those hazards are built later.
- **R6.3** "Hazards affect enemies according to their physical rules too … an enemy that enters the field should also
  be dragged unless its movement profile explicitly provides resistance." (EPIC: "an enemy caught in a gravity well is
  really pulled in, unless its movement profile resists the pull".)

### Battlefield structures and avoidance (IDEAS §18.6)
- **R6.4** Structure categories in scope: *destructible / physical* (ship wrecks, drifting debris, damaged satellites,
  abandoned cargo platforms, broken station modules) and *energy / physics* (gravity wells, energy anomalies, unstable
  reactor fields, EMP zones), **except** mines, jammers, turrets and laser emitters / barriers (EPIC scope line).
- **R6.5** Placement principle: "Structures should form tactical spaces" (turret / wreck / wreck / gravity well
  sketch).
- **R6.6** "Enemies should understand these objects through the same perception/steering system used for the player
  … use cover, avoid damage zones, accidentally hit hazards, or deliberately push the player toward dangerous
  geometry."
- **R6.7** Soft avoidance: "Desired combat velocity + Hazard avoidance vector + Collision / steering constraints →
  Final movement intent". EPIC: "Research decides whether to use context steering."
- **R6.8** "The avoidance strength depends on the hazard and enemy profile. A tiny drone strongly avoids a gravity
  well. A heavy dreadnought partially resists it. A suicidal ram drone may ignore it during the final committed
  attack." EPIC: "Drones avoid strongly or skim the edge, heavy ships partly resist, and a rammer committed to its final
  run ignores hazards."
- **R6.9** Hazards as tools: "sniper hides behind wreckage; fighters use a wreck as cover before a pass; ram ships
  avoid the gravity well until a charge can force the player toward it; drones skim the edge of a danger field;
  carriers position escorts …; hackers stay outside …". EPIC names the first three plus edge-skimming.

### Gravity Well and Energy Anomaly (IDEAS §6.7)
- **R6.10** Gravity Well: "radial pull that becomes stronger near the center. Ships **and projectiles** are affected
  according to mass/strength rules."
- **R6.11** "normal ships try to avoid entering the danger radius; agile drones can deliberately skim the edge; heavy
  enemies can partially resist the pull; if an enemy is caught inside, it is actually dragged inward …; staying too
  close causes damage or hull stress." "This gives the player opportunities to bait enemies into the well."
- **R6.12** Energy Anomaly: "A less predictable field that can distort movement, projectiles, shields, or targeting.
  Use it sparingly and keep its rules visually readable."

### Wreck / Debris Field (IDEAS §6.8)
- **R6.13** "Destroyed ships should sometimes leave physical battlefield remnants": hard cover / LOS blocker, collision
  hazard, drifting debris, explosive wreck, "temporary obstacle around a destroyed capital ship".
- **R6.14** "A wreck can also become a temporary hiding location for the sniper or cover that a fighter circles
  around."

### Area-control weapons (IDEAS §11.4, the two this phase owns)
- **R6.15** Gravity Field: "Temporarily reduces movement/boost effectiveness."
- **R6.16** Debris Charge: "Enemy breaks off an armor fragment that becomes a moving hazard."

### Line of sight (IDEAS §28, EPIC "terrain and wreck occlusion feeding can_see_player()")
- **R6.17** `can_see_player()` as an optional perception rule (sniper, missile corvette, support ship, boss turrets);
  "Sniper refuses to fire if a large asteroid blocks the shot. Missile ship can still fire because its missiles can
  curve around obstacles." "Make Open Space terrain relevant to combat instead of decorative."

### Art (IDEAS §21–23, EPIC "Each hazard and structure owns its strict top-down art")
- **R6.18** Silhouette + faction accents + gameplay lights; cool edge highlights on dark hulls; state lights (yellow
  charging, cyan shield, orange overheating, dark/off destroyed); "destroyed modules visibly remain as wreckage" (§23,
  bosses → Ph19). Strict top-down orthographic for `assault/` and `open_space/` (CLAUDE.md, `pixel-art-generation`).

### Tests (IDEAS §40, EPIC)
- **R6.19** Deterministic tests "in both harnesses cover pull on enemies and on the player, avoidance strength per
  profile, wreck spawning and line-of-sight blocking." "The same behavior specification should be used in both tests,
  with only the movement constraint changed."

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/enemy_ai/enemy_mover.gd` | The single writer of an AI enemy's `velocity` / `rotation`; `request_velocity` (primary, :75), `add_nudge` (additive, :80), `face_toward`, `boost` (:92, ignores requests, nudges, `max_speed` and accel), `halt`, `release_constraint`. `step()` (:180-217): desired = boost or `(primary + nudge).limit_length(max_speed)` → `move_toward` at `acceleration` / `braking` → `constraint.filter()` → `velocity = v; move_and_slide()` → facing → clear requests. | The avoidance layer and the pull both have to enter here: the mover is the only legal writer (gate). It has **no external-force term** today; a pull fed through `add_nudge` would be ignored during every `boost()` and would be wiped each tick on a mover with `acceleration = 0` (instant). |
| `global/enemy_ai/enemy_brain.gd` | `tick(delta)`, `on_suspended()`, `accepts_tow()` (:84); resolves `actor` / `mover` / `attack`; seedable `rng`. No Timers. | Brains are where "hazards as tools" goes (cover choice, push-toward-well). |
| `global/enemy_ai/steering.gd` | Pure static primitives returning a desired velocity (seek … break_contact, plus `separation` / `alignment` / `cohesion` / `turn_toward`). No obstacle avoidance, no context steering. | Where a pure avoidance / context-map function belongs (pure, unit-testable). |
| `global/enemy_ai/line_of_sight.gd` | `LineOfSight.clear(space, from, to, exclude)`: one ray, mask `ENVIRONMENT \| HAZARD_CONTACT` (1 \| 1024), bodies only; blocks only if the collider is in group `asteroids` or answers `blocks_line_of_sight() == true`; other bodies excluded and the ray recast up to 4 times, then "clear". Physics step only. | Wrecks plug in by answering `blocks_line_of_sight()` on a body on layer 1 — the Ph4 decision. Enemy root bodies are on layer 1 too, which is why the recast exists. |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)` (:25), `predicted_position`, `intercept`, `aim_direction`, `line_of_sight(from, space, exclude)` (:119). | No `can_see_player()` exists anywhere; §28's name is a thin wrapper over this. |
| `global/enemy_ai/enemy_world.gd` | Static mode lookup via group `assault_arena` (ArenaCamera); `projectile_world_rect`, `cull_rect`, `view_rect`, `movement_constraint`. Open Space has no provider. | The model for a static `Hazards` registry lookup; Assault wreck lifetime can use `projectile_world_rect`. |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis corridor filter (`entry_speed` 60, `soft_band` 120, `hard_band` 450, `edge_pressure` 200), applied **after** the accel limit. | A pull must not be able to drag an Assault enemy out past the hard band; ordering of pull vs constraint is a design decision. |
| `assault/scenes/enemies/base_enemy.gd` | `_physics_process` (:107-112): `brain.tick` then `mover.step`; `suspend_ai()` (:120); `is_ai_driven()` (:140); `accept_tow(v)` (:149) → `add_nudge`; death in `_on_health_changed` (:226-240): `was_killed`, `died.emit()`, `explode()`, `queue_free()`. **No `apply_knockback`.** | Wreck spawning hooks into death; a duck-typed hazard-force entry point belongs here (forwarding to the mover). |
| 9 brains: `swarm_drone`, `razor_drone`, `fighter`, `gatling_interceptor`, `bomber`, `sniper`, `ram_corvette`, `missile_corvette`, `support_ship` (`assault/scenes/enemies/<x>/<x>_brain.gd`) | Every mover-driven enemy. Committed attacks use `mover.boost()`: Swarm BURST (:439), Ram CHARGE (:464), Razor dash / feint lunge (:515, :437) and an idle boost (:694). | "Committed run ignores hazards" falls out of `boost` if avoidance is skipped while boosting. Avoidance strength per profile must reach all nine. |
| Legacy enemies: `gunship/`, `bonus_drone/`, `space_station/` | Own `_physics_process` or rails; no mover. Station root is layer 0 / mask 0. | Not pulled unless handled; Gunship → Ph10, station → Ph11, rails → Ph15. |
| `assault/scenes/enemies/sniper/sniper_brain.gd` | `choose_firing_point()` (:398-463): bearing candidates → rect / cone / path filters → tiers + score (`w_sep`, `w_travel`) → `LineOfSight.clear` per survivor (:454); `_tick_settle` re-checks LOS (:473); LOCK re-checks two lines (`_line_clear` :589, `_line_clear_to` :598). | "Sniper hides behind wreckage" = a cover term or cover-derived candidates here. |
| `assault/scenes/enemies/fighter/fighter_brain.gd` | `_derive_pass()` (:515) picks the anchor, pass kind and start S; Dubins `_plan` / `_best_path` (:1119 / :1143) with `_segment_clears` (:1106); `_hold_station` / `_begin_hold` (:846 / :877) hold at S. No LOS check today. | "Fighter uses a wreck as cover before a pass" = choose / hold S behind a wreck. |
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | `_choose_side` (:343), `_predicted_aim` (:401, corridor-clamped), `_tick_wind_up` (:430, freezes `charge_dir`), `_enter_charge` (:452, `mover.boost`), `_evade` (:365, an `add_nudge` example). ARMOR contact shoves the touched ship along owner → target (`contact_profile.gd` `_shove` :139-148, `shove_speed` 260 while armoured). | "Ram pushes the player toward a well" = choose the side / approach so the charge and the shove point player → well. |
| `global/components/armor_plate.gd` | `ArmorPlate` (under `Plates/`): `broken(plate)` / `deflected(hit_box)`; `_break()` (:139-154) disables the hurtbox, hides the sprite, bursts, emits, frees. **No fragment.** Art `ram_plate_front.png` 44×18, `ram_plate_side.png` 36×18. | The Debris Charge's fragment is born here or in `RamCorvette._on_plate_broken` (`ram_corvette.gd:138`). |
| `global/components/contact_profile.gd`, `contact_blast.gd` | Contact modes `NONE, COLLISION, RAMMING, EXPLOSIVE, ARMOR`; `ContactBlast.spawn(container, at, radius, damage, frames)` (layer 256, reaches the player only). | Explosive wreck blast; a debris fragment's contact damage. |
| `assault/scenes/hazards/asteroid_base.gd`, `big_asteroid/`, `small_asteroid/` | `CharacterBody2D` on layer 1, group `asteroids`, contact `HitBox` on 1024; `died(world_position)`; `_on_destroyed()` hook (:69); small asteroids drift by position writes and free off-camera. | The pattern for a drifting physical hazard (wreck, debris) and the existing LOS blocker. |
| `assault/scenes/hazards/laser_ray/laser_ray.gd` | Segmented one-shot kill beam; direct `received_damage.emit` (:254, :264); can join `race_hazards`. | Direct-emitter damage precedent for hull stress. Laser walls are Ph8. |
| `assault/scenes/race/core/hazard_system.gd` + `sensors.gd` | Race mode: one system scans group `race_hazards` with duck-typed `danger_rect()` / `is_lethal_now()` and kills on overlap; AI `Sensors` read the same data. "What the AI dodges is exactly what kills it." | The house precedent for a group + duck-typed hazard contract read by both the effect and the AI. |
| `open_space/scenes/entities/player/player_ship.gd` | `_physics_process` (:202): rotation → `_handle_thrust` (:322; thrust 380, reverse 220, `max_speed` 420, `damping` 0.6 lerp when idle) → `_step_boost` (:368; `boost_exit_speed` 700, final ceiling clamp) → `move_and_slide`. `apply_knockback(impulse)` (:262) = `velocity += impulse`. | The player's pull and Gravity Field slow enter here (thrust / ceiling / boost multipliers). Damping bleeds an added velocity, so a pull reaches a terminal drift. |
| `assault/scenes/player/player_fighter.gd`, `states/move_state.gd`, `dash_state.gd`, `global/entities/player_base.gd` | Assault player: `move_state` sets `velocity = direction * move_speed` (360; :68) and clamps to x [-100, 1380], y [-380, 1100] (:73-74); knockback path `apply_knockback_motion` (:142) also clamps. `PlayerBase` multipliers are combat-only (`damage_multiplier`, `fire_rate_multiplier`, `damage_reduction`). | **No speed multiplier or status-effect system exists** on any ship. Velocity is reassigned every tick, so a pull must be an additive drift term, not an accumulated velocity. |
| `global/ship_modules/*` | The player's `use_ability` (H) modules (EMP, nova, warp, parry, shield overload, trajectory calc, …) via `ShipModuleBase.try_activate`. EMP stun sets `process_mode = DISABLED` on `enemies` for 5 s. `shield_overload_module.gd:56` duck-types `apply_knockback` on enemies (silently nothing today). | `disables_abilities` has a consumer only here; jammers are Ph9. |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd`, `enemy_rockets/enemy_rocket.gd`, `enemy_ordnance/enemy_ordnance.gd`, `bullets/bullet.gd`, `missiles/homing/`, `missiles/warhead/` | Every projectile moves itself by `global_position +=` (bullet: `_direction * speed`; rocket: `_heading * _speed`, `Steering.turn_toward`; player bullet and missiles: from `rotation`). | "Projectiles affected by the well" means each family samples the field itself; no shared velocity field exists. Lifetime rows assume straight-line travel. |
| `global/components/projectile_lifetime.gd` | `max_time`, `max_distance` (from origin), `use_world_rect`; emits the host's `expired`, never frees; arms lazily. | A drifting wreck / fragment needs a lifetime that obeys the one-owner rule. |
| `global/physics/collision_layers.gd`, `project.godot [layer_names]` | Named bits 1, 2, 4, 16, 32, 64, 128, 256, 512, 1024; bit 4 (8) deliberately unnamed; **bit 12 (2048) unused, reserved `area_control` for Ph6** (DECISIONS Ph1). | `test_collision_layer_names.gd` fails on any unnamed used bit. |
| `assault/scenes/systems/level_director/level_director.gd:170` | `ENEMIES_CLEARED` waits while `container.get_child_count() > 0`. | Anything spawned into the enemy container (a wreck, a fragment, an explosion's particles) holds a section open. |
| `open_space/scenes/levels/sector_hub.gd` / `.tscn` | Hub at the origin; three planets / mission triggers ((595, 342), (-530, -384), (-635, 385)); ~25 pickups and logs (one is `InfoLogVoeterWreck` at (-480, -300), text only); `_spawn_patrol()` puts groups on rings 1300 (swarm 90°, razor 270°), 1500 (fighter 180°, gatling 0°), 1700 (sniper 135°, bomber 45°, ram + support 225°), 1900 (missile corvette 315°). **No asteroids, hazards, physics bodies or world bounds.** Seeded rng draws are appended in a fixed order. | Shipped Open Space content for this phase goes here; every placement must clear `test_sector_hub_patrol.gd`. |
| Art: `assault/assets/sprites/environment/debris_1..6.png` (64×64, one 64×62) | Grey generic hull scraps, transparent background, top-down; **referenced nowhere**. `station_turret_destroyed.png` (64×64) is the only destroyed-state sprite. | Reusable for drifting debris; faction wrecks, the well, the anomaly and the field need new art through `pixel-art-generation`. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EnemyMover.add_nudge` / `boost` / `halt` | The legal entry points into enemy motion. Avoidance is a mover stage; boost = "committed", so skipping avoidance while boosting implements R6.8's rammer rule with no brain change. |
| `Steering` (pure statics) | Home for a pure `context_choose(...)` / avoidance function, unit-testable alone like every primitive. |
| `LineOfSight` + `blocks_line_of_sight()` duck type | Wreck occlusion is one method on the wreck's body; no mask change (Ph4 decision). |
| `TargetInfo.line_of_sight` | `can_see_player()` is a wrapper, not new maths. |
| Race `HazardSystem` / `Sensors` (group + duck-typed query) | Precedent for one hazard description read by both the effect and the AI. |
| `EnemyWorld` (static, group-resolved, duck-typed) | Shape for a static `Hazards` lookup; nothing in `global/` may reference `ArenaCamera`. |
| `AsteroidBase` (`CharacterBody2D`, layer 1, group `asteroids`, contact `HitBox` 1024, `died`, `_on_destroyed`) | Shape for a wreck / debris body that blocks movement, blocks LOS and hurts on contact. |
| `ContactBlast.spawn`, `ExplosionEffect.explode` | Explosive wreck and fragment detonation. |
| `ContactProfile` (COLLISION / ARMOR, `apply_knockback` duck type) | Fragment contact damage; the ram's shove toward a well. |
| `ArmorPlate` (`broken` signal, `texture`, `global_transform`) | Source of the Debris Charge fragment. |
| `ProjectileLifetime` (`max_time`, `max_distance`, world rect; emits, never frees) | Lifetime of drifting wrecks and fragments under the one-owner rule. |
| `OpenSpacePlayerShip.apply_knockback`, `PlayerBase.apply_knockback` | Existing ways to push the player; a continuous pull needs a new additive term, not repeated knockbacks (Assault's knockback path freezes steering while active). |
| Direct `HurtBox.received_damage.emit()` (laser ray, beam, wall impact) | Hull-stress damage without a physics overlap. |
| `StateLight` (`global/components/state_light.gd`) | State colours for hazards that telegraph (anomaly pulse, explosive wreck fuse). |
| `AnchorIdle`, `EngagementBudget` | Unchanged; avoidance must not break IDLE / RETURNING or budget exits. |
| `tests/helpers/enemy_ai_harness.gd`, `test_enemy_dual_mode.gd::_tick()` | Dual-mode, hand-ticked specs (build the harness from a label inside the body — the `use_parameters` leak footgun). |
| `scripts/gate-time.sh`, the 8× clock helpers in `test_level1_drone_exit.gd` | Required before/after timing for every task that adds an awaiting test. |
| `debris_1..6.png` | Ready-made drifting-debris sprites. |

## Conventions that constrain this

- **Single writer of motion.** Only `EnemyMover` writes an AI enemy's `velocity` / `rotation` or calls `move_and_slide()`
  (`test_enemy_mover_single_writer.gd`: brains, `global/enemy_ai/*` except the mover, mover-driven root scripts **and
  their ancestors**, i.e. `base_enemy.gd`). A hazard may never write an enemy's velocity; it must *ask* (a mover
  method or a duck-typed call that forwards to one). The player's `rotation` has its own single writer
  (`ShipTurnController`) — a pull must not rotate the player.
- **Requests are per step.** A brain that stops requesting brakes to zero; anything the mover keeps across steps
  (boost, a future pull velocity) is mover state, not a request.
- **No weighted blending of primitives** (Ph1 §2.4: "cancellation shows as stalls"); Ph1 named context steering as
  the Ph6 upgrade. Changing that needs an explicit note in `DECISIONS.md`.
- **Brains tick on physics**, clocks are accumulated `delta`, randomness only from `brain.rng`, the player only via
  `TargetInfo.player(tree)`, no `Timer` nodes.
- **Configs are flat** `@export_group` sections of a `ShipConfig` subclass (Movement / Attack / Defense / Tactics /
  Scoring); no nested resources, arrays or dictionaries (`test_config_instance_isolation.gd`). Per-profile hazard
  fields (avoidance, resistance, skim) are flat fields — on `ShipConfig` if every enemy gets a default.
- **Collision layers are named before use** (`test_collision_layer_names.gd`); no layer is allocated until something
  uses it (DECISIONS Ph1).
- **Every projectile has exactly one owner** (pool recycle or self-free); persistent things never enter `enemies` or
  `ScoreTracker` (Ph4). Anything in the enemy container holds `ENEMIES_CLEARED` open.
- **Armour is parts, not a mask; a part resolves each hit once** (Ph4). A fragment broken off a plate is a new object
  after the plate is gone, never the plate's hurtbox reused.
- **Design-unit coordinates** for anything authored in Assault waves (640×360 × `ArenaCamera.WORLD_SCALE`); nothing in
  `global/` references `ArenaCamera`.
- **Dual-mode specs** in `open_space` and `assault` harnesses, assertions relative to the constraint; parameterise on a
  label, never on a harness instance.
- **Gate time:** GUT ≤ 240 s after every task (wall cap ~300 s); last recorded 176.9 s (Ph5 t1), "about 200 s" at the
  end of Ph5 (DECISIONS Ph5). Real-physics rows run on the 8× clock; a hand-ticked dual-mode case costs ≈ 0.02–0.06 s,
  a real-physics case at 8× ≈ 0.25–0.4 s, a whole-section replay ≈ 5 s.
- **Art:** `pixel-art-generation` skill before any PixelLab call; strict top-down (`view: "high top-down"`,
  `isometric: false`); save with `scripts/pixellab.sh`; look at every image; no painted backgrounds
  (`test_entity_sprite_transparency.gd` sweeps `assault/scenes/{enemies,player,projectiles,hazards,allies}`).
- **Docs:** structural changes → `updating-project-docs`; new hazards get a `HAZARD.md` beside them.
- **Never hand-type a `uid://`.** Leave new references UID-less or mint with `ResourceUID.create_id()`.

## Dependencies and blast radius

- **`EnemyMover.step()` is on every AI enemy's hot path.** Any new stage (avoidance, pull) changes all nine brains'
  motion unless it is an exact pass-through when no hazard exists. Every Ph2–Ph5 behaviour spec, the
  attack-in-budget rows, `test_engagement_deadline.gd`, the level-1 density gates and `test_fighter_squad.gd`'s
  168-layout sweep (~63 s) run with no hazards; a non-identical pass-through would move every one of them.
- **Player ships** (`player_ship.gd`, `move_state.gd`, `player_base.gd`) are covered by many Open Space flight / boost /
  turn tests (`test_open_space_*`, `test_player_ship_turn_wiring.gd`); a pull or slow term must be zero by default.
- **Projectile families**: adding field sampling to `EnemyBullet` / `EnemyRocket` / `Bullet` touches the lifetime gates
  (`test_enemy_bullet_lifetime.gd`, `test_player_bullet_lifetime.gd`), whose bounds assume straight travel at constant
  speed.
- **Death flow** (`BaseEnemy._on_health_changed`): spawning a wreck there affects every `BaseEnemy` including level-1
  replays and density measurements (container child counts), unless wrecks live outside the enemy container.
- **Ram Corvette**: a fragment on plate break touches `test_ram_corvette.gd` (56 rows) and the plate-resolve-once rule.
- **Sniper / Fighter / Ram brains**: cover and push-toward-well terms change firing-point and pass selection; their
  attack-in-budget and deadline rows must stay green (the 73.2 s ram row has 0.40 s of margin).
- **Sector hub**: new bodies there change the sniper's LOS answers and the clearance sweep; seeded rng order must be
  appended, never reordered.
- **Collision layers**: a new named bit touches `project.godot`, `CollisionLayers`, `global.md` and the names gate.

## Risks, edge cases, testing requirements

- **Pass-through identity.** With zero hazards the mover must produce bit-identical velocity and rotation to today; one
  pinned row per mover configuration (instant, accel-limited, boosting, constrained).
- **Pull vs instant movers.** A mover with `acceleration = 0` rewrites velocity every tick; a pull modelled as an
  acceleration added to `velocity` would never accumulate. The pull must be its own term.
- **Pull vs boost.** A boost ignores requests and nudges; whether the pull still applies during a committed dash is a
  rule to decide (R6.8 says committed rammers ignore *avoidance*; R6.3 says physics still applies).
- **Pull vs the Assault corridor.** Pull applied before `constraint.filter()` can be cancelled by the corridor; after
  it, a well near the edge drags an enemy out of the band. Same question for the Assault player's position clamp.
- **Capture / orbit.** An inverse-square pull with no softening is singular at the centre and produces slingshots and
  stable orbits; a "drift speed" that exceeds a ship's max speed is an inescapable capture.
- **Avoidance traps.** A brain whose target sits inside or behind a hazard (the player hiding in the well; a firing
  point behind a wreck) can oscillate at the edge or stall; context steering's local-minimum problem.
- **Edge skimming** needs a margin rule that does not degenerate into touching the damage radius every frame.
- **Hull-stress damage** through a direct emit bypasses `area_entered` absorbers (`EnemyShield` sees only
  `area_entered`) — decide whether shields absorb stress.
- **Wreck count.** Assault kills hundreds of enemies per level; "sometimes" needs a chance and an alive cap, and wrecks
  must never hold `ENEMIES_CLEARED` open or enter `enemies`.
- **Wreck vs movers.** Enemy bodies (layer 1, mask 1) collide with layer-1 wrecks via `move_and_slide`; instant movers
  slide, boosting ones grind — avoidance should see wrecks as obstacles.
- **LOS cost.** The sniper casts up to `max_los_rays` per pick; more blockers mean more recasts (cap 4).
- **Projectiles in a well.** Bent bullets change the lifetime bounds and pooled-bullet `reset()` must clear any drift.
- **Determinism.** Everything must be hand-tickable (no physics overlap needed for pull/damage/penalty) so both
  harnesses can drive it; any Area2D-based detection needs real physics frames (8× clock).
- **Gate time.** ~40 s of headroom; this phase must budget per task.
- **Art.** New sprites must pass the transparency sweep; a wreck sprite must not read as a live ship (dark/off lights,
  broken silhouette).

Testing requirements (from R6.19 and the conventions): dual-mode specs for pull on enemies (per resistance) and on both
player ships, avoidance strength per profile (strong / skim / resist / ignore-while-committed), a pass-through identity
row, wreck spawning (chance, cap, container, lifetime, never in `enemies`), LOS blocking by a wreck (and not by debris
marked non-blocking), the Gravity Field slow on the player (movement and boost) and on enemies, the Debris Charge
fragment (born on plate break, moves, hurts, expires, one owner), hull stress, the anomaly's readable rule, cover use by
the sniper and fighter, the ram's push-toward-well choice, a layer-names row for any new bit, a transparency row for
every new sprite, and hub placement clearance.

## Open questions for the plan

1. Context steering in the mover, a repulsion nudge, or both? (`2-research.md` §2.2 recommends.)
2. Is the pull a persistent mover velocity term, a per-step drift, or an acceleration? Does it apply while boosting,
   and before or after the Assault corridor?
3. How is "mass / resistance" expressed — one flat `hazard_resistance` per config, or derived from `max_speed`?
4. Which projectiles does a well bend in this phase, if any?
5. What exactly does the Energy Anomaly distort (one rule or several variants), and how is it made readable?
6. Who fires the Gravity Field (§11.4), and is it a projectile, an ordnance kind or a deployed field?
7. Is the Debris Charge passive (a broken plate flies off) or an active attack (the ram jettisons a plate)?
8. Which ships leave wrecks, how often, how many may live at once, and how do wrecks end in each mode?
9. Does an explosive wreck's blast hurt enemies (Ph5 kept blasts player-only; Ph8 owns friendly fire generally)?
10. Where do hazards appear in shipped content: the Open Space hub, level 1, both, neither?
11. Does this phase allocate bit 12 `area_control`, or does a registry-based design leave it unallocated?
12. Do hazards affect rail-driven and legacy enemies (Gunship, Bonus Drone, station), or only mover-driven ones?
