# Context — Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship

Epic `cmufs7elw001pnm2xr3b6fteb`, research task `cmufs7em1001tnm2xsfqqybxp`, 2026-10-14. Facts were read at `59f4abe` on
`agent/auto-dev` (Phase 4 closed). `2-research.md` (next to this file) holds the scope check, the outside findings, the
candidate approaches and the starting values; this file is the code inventory the plan builds on. Anything not read
directly, or a judgement with no citable source, is labelled **(judgement)** or **(inferred)**.

## Requirements from the attached documents

Ids `R5.x` are used by `2-research.md` and should be used by the plan's coverage table. Source: `IDEAS` =
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`, `ENEMIES` =
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`, `EPIC` = the epic description (the phase's scope paragraph).

### Missile Corvette (IDEAS §6.1, §1.1, §36, §41 Ph3 item 4)
| Id | Requirement (quoted briefly) | Source |
|---|---|---|
| R5.1 | "Mid-weight ranged enemy that controls space with rockets"; combat verb "Can I survive the salvo and get behind it?" | IDEAS §6.1, §1.1 |
| R5.2 | Size 80–112 px | IDEAS §6.1, §2 table, §21.3 |
| R5.3 | "Maintains medium distance and uses broad arcs instead of closing directly" | IDEAS §6.1; EPIC "holds medium range on broad arcs" |
| R5.4 | "fires predicted salvos" | EPIC |
| R5.5 | The rocket "should prefer the player's **future path**, not the current position" | IDEAS §6.1 |
| R5.6 | A rocket "behaves differently from a bullet": visible launch, acceleration phase, mild steering, warning audio, "possible flare/decoy reaction", explosion radius | IDEAS §6.1; EPIC (no audio named) |
| R5.7 | Counterplay: outrun it, turn sharply, destroy it, make it collide with environment / other enemies, "bait it into a carrier escort" | IDEAS §6.1; EPIC "outrun, out-turned, shot down, or made to hit other enemies and the environment" |
| R5.8 | Assault: "Rockets remain fully functional but are limited by the corridor … a new threat that is not just another bullet stream" | IDEAS §6.1 |
| R5.9 | Combination: "Missile Corvette + Fighter — rockets force turns; fighters attack the new direction"; heavy patrol uses one | IDEAS §37, §19 (encounters → Ph13/Ph14) |

### Enemy rocket family (IDEAS §11.2 except the Hijack Pulse)
| Id | Requirement | Source |
|---|---|---|
| R5.10 | **Dumb Rocket** — "Fast and predictable" | IDEAS §11.2 |
| R5.11 | **Pursuit Rocket** — "Mild steering for several seconds" | IDEAS §11.2 |
| R5.12 | **Cluster Rocket** — "Splits into 3–5 small missiles" | IDEAS §11.2; EPIC "splitting" tests |
| R5.13 | **Delayed Warhead** — "Slower projectile that detonates after entering a proximity radius" | IDEAS §11.2; EPIC "proximity detonation" tests |
| R5.14 | The Hijack Pulse is **out** (Phase 9) | EPIC scope |
| R5.15 | "All of this sits on the collision layer that phase 1 named for rockets" | EPIC |
| R5.16 | World-space lifetime; `persist_after_owner_death` "useful for missiles" | IDEAS §12; Ph1 P-12 |

### Support / Shield Ship (IDEAS §6.2, §1.1, §36, §41 Ph3 item 5)
| Id | Requirement | Source |
|---|---|---|
| R5.17 | "Support enemy that makes formations more dangerous without being a direct damage dealer"; verb "Can I kill the support unit before the formation becomes overwhelming?" | IDEAS §6.2, §1.1 |
| R5.18 | Size 72–104 px | IDEAS §6.2 |
| R5.19 | "Stays behind the highest-threat enemy. Uses a soft formation anchor rather than direct player pursuit." | IDEAS §6.2 |
| R5.20 | **Repair beam**: "restores a small amount of HP to a nearby ally" | IDEAS §6.2 |
| R5.21 | **Shield projector**: "creates a directional shield arc around another enemy" | IDEAS §6.2 |
| R5.22 | **Emergency escort**: "if the supported target reaches low HP, the support ship pulls the target away and becomes the closer target itself" | IDEAS §6.2 |
| R5.23 | "low HP but high evasiveness. Killing it first makes the rest of the formation much easier." | IDEAS §6.2 |
| R5.24 | Switches target when its ally dies | EPIC; IDEAS §40 "support ship changes target when ally dies" |
| R5.25 | Assault: "support range is clamped so it cannot hide permanently above the camera" | IDEAS §6.2 |
| R5.26 | Contact profile **None** for support ships | IDEAS §16 |
| R5.27 | §37 "Support + Ram — support keeps the ram ship alive long enough to make multiple attack attempts": **made possible**, not an encounter director | EPIC scope |
| R5.28 | §37 "Carrier + Support + Drones" | out (Carrier is Ph10/Ph18) |

### Shields on enemies (IDEAS §13.2, §15) and the deferred decision
| Id | Requirement | Source |
|---|---|---|
| R5.29 | "Shields should be a temporary combat resource rather than a second HP bar" | IDEAS §13.2; EPIC |
| R5.30 | Kinds: directional shield, local module shield, regenerating shield, shield bubble projected by support ships | IDEAS §13.2; EPIC |
| R5.31 | Settle "adopting DamageReaction with Shield support for enemies" (Ph1 P-15, deferred to Ph5) | EPIC; DECISIONS Ph1 deferred table |
| R5.32 | Interaction rules via a `DamageProfile`/`DefenseProfile`, never a blind mask overwrite | IDEAS §15 |

### Visuals (IDEAS §21–23)
| Id | Requirement | Source |
|---|---|---|
| R5.33 | Three visual layers: silhouette, faction accents (red/maroon/orange), gameplay lights; cool edge highlight; **cyan/blue = shield** | IDEAS §21.1–21.2 |
| R5.34 | "Specialists 80×80 to 128×128 … clearly identifiable silhouettes" | IDEAS §22 |
| R5.35 | Support Ship: "shield projector unfolds while supporting another unit" | IDEAS §23; EPIC "unfolding projector state" |
| R5.36 | Strict top-down sprites, 72–112 px, for both enemies | EPIC; CLAUDE.md art rule |

### Placement and tests
| Id | Requirement | Source |
|---|---|---|
| R5.37 | Both enemies added to existing Assault waves | EPIC |
| R5.38 | Both enemies added to the hub's ambient spawn | EPIC |
| R5.39 | Tests in both harnesses: rocket steering toward the predicted point, splitting, proximity detonation, repair and shield application, retargeting when an ally dies, the escort trigger | EPIC; IDEAS §40 |
| R5.40 | Every enemy has a test in Open Space and Assault with only the constraint changed | IDEAS §40 "Mode compatibility" |
| R5.41 | §43 checklist questions (silhouette, preferred distance, movement signature, behind/boost reaction, off-screen, telegraph, works alone / in combination, deterministic tests) | IDEAS §43 (audit → Ph17; answered per enemy in the plan) |

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy`: Health/HurtBox wiring, `DefenseProfile`/`ContactProfile` resolution, brain→mover tick, `suspend_ai()`, virtual `_on_received_damage(damage)` (:176) and `_on_health_changed(current)` (:183) | Shields hook into the damage path here. **`_on_health_changed` plays the hit flash and the hit burst on every change** (:183-192), so a repair through `Health.increase()` would flash like a hit. There is no heal path for enemies anywhere today. |
| `global/components/hurtbox_component.gd` | `HurtBox.received_damage(damage: int)`, emitted from its own `area_entered`, filtered only by `accepted_damage_types` | **The signal carries no `HitBox`**, so nothing downstream of it knows a hit's direction or type. A directional shield needs a hit-aware path (2-research §2.4). |
| `global/components/armor_query.gd`, `armor_plate.gd` | `ArmorQuery.deflects(area, hit_box)`: duck-typed `deflects_hit(hit_box)` then `is_armored()`; `ArmorPlate` resolves each `HitBox` once (`_resolve`, per instance id) from its own `area_entered` and from `deflects_hit` | The only hit-aware damage decision in the project, and the idempotent-resolve shape any shield arc must copy (Ph4 deviation 7: Godot orders the hurtbox's `area_entered` and the projectile's query undefined). Called by `bullet.gd`, `homing_missile.gd`, `warhead_missile.gd`. |
| `global/components/defense_profile.gd` | Hurtbox mask from `accepts_*` flags; every `BaseEnemy` without an authored profile gets mask **1121** (1 + 32 + 64 + 1024) at runtime, whatever the scene says (bomber scene 65, sniper 97 are overwritten) | Every enemy hurtbox already accepts bit 32 (`player_rockets`). |
| `global/components/shield_component.gd` | `Shield`: discrete charges (one charge absorbs one whole hit), permanent charges regen 1 per `REGEN_INTERVAL_SEC` 5.0 s via a `Timer`, temp stack, `is_hacked`, `shield_state_changed(snapshot)` | Player/racer resource. No direction, no projection, a `Timer` (brains use accumulated clocks), progression binding. Candidate for reuse in the decision (§2.4). |
| `global/components/damage_reaction.gd` | `DamageReaction.setup(health, shield, hurt_box, sprite)`: hit → `on_hit` → tween flash → `shield.consume_one()` or `health.decrease()`; death → explode → `get_parent().queue_free()` | **Used only by race ships** (`race_ship.gd:24`, five racer scenes). The P-15 question is whether BaseEnemy adopts it. |
| `global/components/bubble_shield.gd/.tscn` | Player-only `AnimatedSprite2D` reacting to `Shield.shield_state_changed` (pickup / break / idle animations) | Visual precedent; created only by `PlayerBase._setup_bubble_shield()`. |
| `global/components/health_component.gd` | `increase(amount)` clamps to `max_health` and **always** emits `amount_changed`; `decrease()` respects i-frames | Repair = `increase()`. Emits even at full health. |
| `global/components/contact_blast.gd` | `ContactBlast.spawn(container, at, radius, damage, frames)`: layer 256, mask 0, CONTACT, 2-3 frames, deferred self-attach | Rocket explosion radius. **Hits the player only**: enemy hurtbox masks have no bit 256, so a blast never damages an enemy. |
| `global/components/bullet_pool.gd` | `persist_after_owner_death` (Ph4, `_hand_over_active()` → `expired → queue_free`), container = grandparent, `cancel_active()` on exit when not persisting | Rockets persist after their corvette dies. Pools must be root children. Container injection is still unbuilt (deferred Ph2 → Ph5); see 2-research S4. |
| `global/components/projectile_lifetime.gd` | `max_time`, `max_distance` **from the origin**, `use_world_rect` (Assault only); lazy arm; `expire_now()` (no callers) | Rockets' fuel/lifetime. **No owner-distance rule exists** (Ph1 assigned `max_distance_from_owner` to Ph5). |
| `assault/scenes/projectiles/enemy_ordnance/` | `EnemyOrdnance extends Area2D`, `Kind { GRAVITY_BOMB, MINE, PURSUIT_BOMB }`, `launch(dir, speed, target_point)`, `reset()`, `expired`; HurtBox (512 / mask 96) + Health 1 = any player hit defuses; `ProximityArea` (mask 128) polled with `get_overlapping_areas()`; detonates via `ContactBlast`; `_draw()` primitives, **no `rotation`** | Closest existing thing to a rocket. Pursuit bomb steers with `Steering.turn_toward` toward `TargetInfo.predicted_position(steer_lead)` (a linear lead, not `intercept()`) for `steer_window`, then freezes heading and accelerates to `final_speed` (:183-195). `EnemyOrdnanceScenes.pool_size_for` is keyed on `BomberConfig` fields. |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd`, `.../warhead/warhead_missile.gd`, `global/components/rocket_trail.gd` | Player rockets: HitBox **layer 32**, mask 513 (environment + enemy hurtbox), ROCKET; homing snaps direction every frame (no turn rate), hard-coded Assault arena bounds; `RocketTrail` particle trail (emits along local +Y) | Layer 32 semantics; `RocketTrail` reusable for enemy rockets (needs a node `rotation`). Player rockets crossing enemy ordnance are already consumed by its HurtBox (mask 96). |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd:60-76` | Homing targets = `get_nodes_in_group("enemies")` sorted by distance, round-robin over 3 rockets | If enemy rockets or a projected shield node joined `enemies`, player homing would lock onto them. |
| `global/enemy_ai/target_info.gd` | `TargetInfo.player(tree)`, `predicted_position(t)`, `intercept(from, shot_speed) → {ok, point, time}`, `aim_direction(from, speed, accuracy)`, `line_of_sight(from, space, exclude)` | Rocket aim points and the corvette's predicted salvo. No velocity smoothing (the Bomber smooths brain-side with an EMA). |
| `global/enemy_ai/steering.gd`, `enemy_mover.gd`, `enemy_brain.gd` | 18 static primitives (`turn_toward`, `orbit`, `formation_slot`, `break_contact`, `evade`, `separation`, `clamped_lead_time`, …); mover single writer (`request_velocity`, `add_nudge`, `face_toward`, `boost`, `release_constraint`, `halt`); brain `tick` / `on_suspended` / `rng` | The two new brains are built from these. A curve is always a brain-side `turn_toward` request (Ph2 decision). |
| `global/enemy_ai/` `engagement_budget.gd`, `anchor_idle.gd`, `squad_controller.gd`, `burst_clock.gd`, `dubins_path.gd`, `line_of_sight.gd`, `global/components/state_light.gd` | Assault budget + DISENGAGE; hub idle handover; role board; N shots at a gap; turn-limited paths; LOS rays; the one gameplay light (OFF / ARMED red / CHARGING yellow / COMMIT white) | Salvos reuse `BurstClock`; hub idle reuses `AnchorIdle`; the corvette's broad arcs can reuse `orbit` / `DubinsPath`. `StateLight` has **no cyan/shield state** (IDEAS §21.1 "cyan/blue = shield"). |
| `assault/scenes/enemies/bomber/`, `sniper/`, `ram_corvette/` | The Ph4 specialist template: root script (`add_to_group("enemies")`, `_apply_config`, rail fallback in `_process` while suspended, an actor API like `Bomber.drop()`), `<x>_brain.gd` (Phase enum, combat phases then `IDLE, NOTICING, RETURNING` appended, `start_engaged` seam, budget built on first tick), flat `<x>_config.gd/.tres` with `@export_group`s | The two new enemies follow this shape exactly. Ram: `is_armored()` / `deflects_hit()` / `homing_point()` / `_on_received_damage` override; the "Support + Ram" pairing's other half. |
| `assault/scenes/enemies/fighter/fighter_brain.gd:1531-1541` | `_mates()`: scans group `enemies`, filters self / other squad / queued-for-deletion, reads `Brain` | The only ally scan in the project; a support ship's ward selection is the second. |
| `assault/scenes/enemies/gunship/gunship.gd:21,109-120` | Legacy RETREAT at `retreat_hp_ratio` 0.3 | Only "low HP → leave" precedent (for the escort trigger threshold). |
| `assault/scenes/systems/assault_corridor_constraint.gd` | Per-axis velocity filter; `inner_rect()` = the camera's whole pan range **1480 × 1480** (x −100…1380, y −380…1100), of which the camera shows 1280 × 720 | "Cannot hide above the camera" (R5.25) is not satisfied by the corridor: a ship can sit inside `inner_rect()` up to ~380 px above the current view with zero pressure. **No provider returns the current camera view rect** (`EnemyWorld.cull_rect()` ignores the camera `offset`). |
| `global/enemy_ai/enemy_world.gd` | `arena`, `projectile_world_rect`, `cull_rect`, `movement_constraint` — the only mode lookup | A view-rect query, if the plan wants one, is added here (+ `ArenaCamera`), never by naming `ArenaCamera` from `global/`. |
| `assault/scenes/levels/edelia/1/level_1_director.gd`, `assault/scenes/systems/level_director/level_director.gd`, `level_section.gd` | Five sections: deep_space DURATION 30 s, asteroid_belt DURATION 30 s, station_assault ENEMIES_CLEARED 180 s, planet_approach DURATION 110 s, cloud_descent ENEMIES_CLEARED (default **10 s** timeout). `_wait_enemies_cleared` waits until the **container has no children** (:170) | Persisting rockets in the container hold an ENEMIES_CLEARED section open. cloud_descent's ram row already passes by only 0.40 s. |
| `assault/scenes/systems/wave_builder.gd` | One-line constructors (`bomber()`) + scene constants (`BOMBER`) | Two new constructors/constants. |
| `assault/scenes/enemies/space_station/station_reinforcements.gd`, `assault/scenes/levels/level_2_waves.gd` | Rail-driven reinforcements (fighters, Gatlings, drones) / unreferenced level 2 | Untouched unless the plan places a new enemy there (then a rail fallback is mandatory, Ph3/Ph4 rule). |
| `open_space/scenes/levels/sector_hub.gd` | `_spawn_patrol()`: rings 1300 (swarm 90°, razor 270°), 1500 (fighter 180°, gatling 0°), 1700 (sniper 135°, bomber 45°, ram 225°); **12 seeded `randi()` draws** in a fixed order; 315° on 1700 left free "nearest the pickup bench" | Two more groups append after draw 12. Bearing room is the hard part (2-research §3.2). |
| `global/ship_modules/emp_blast_module.gd`, `plasma_nova_module.gd`, `shield_overload_module.gd`, `engine_boost_module.gd`, `ai_targeting_module.gd`, `assault/scenes/player/states/dash_state.gd`, `.../weapons/behaviors/beam_behavior.gd` | Player systems that iterate group `enemies`; EMP stuns by `process_mode = DISABLED` for 5 s (immune: asteroids, `RamCorvette`); nova / dash / shield overload call `received_damage.emit()` directly | Direct emitters bypass any `HitBox`-based shield rule (like they bypass armour plates). An EMP-stunned support ship freezes mid-beam. |
| `docs/enemy-roster.md` | Spawn reference; one section per enemy, "Enemy ordnance (Ph4)", Quick Rules | Docs task adds both enemies and the rocket family. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/enemy_ordnance.gd`) | The whole ordnance contract a rocket needs: `launch()` / `reset()` / `expired`, HurtBox + Health 1 (shoot-down = defuse, no blast), proximity poll, `ContactBlast` detonation, `ProjectileLifetime`, `_mark_done()` latch, `_RESET_PROPS` capture, pursuit steering via `turn_toward` + predicted point. Ph4 said Ph7 *extends* it; Ph5 can extend it or sibling it (2-research §2.2). |
| `ContactBlast.spawn()` | Explosion radius damage to the player, never a child of the dying thing. |
| `BulletPool.persist_after_owner_death` | Rockets outlive their corvette with one owner at every instant. |
| `ProjectileLifetime` | Fuel time / range; `max_distance` from origin. |
| `TargetInfo.intercept()` / `predicted_position()` | The predicted salvo point and the rocket's aim point. |
| `Steering.turn_toward(current, desired, max_rate, delta)` | Mild steering with a hard turn-rate cap: the rocket's whole guidance law. |
| `BurstClock` | A salvo of N rockets at a gap (Ph3: "later enemies with bursts or salvos (… Missile Corvette …) reuse it"). |
| `Steering.orbit` / `DubinsPath` / `Steering.formation_slot` / `Steering.break_contact` / `Steering.evade` | Broad arcs (corvette); a soft anchor behind a ward (support); evasion (support). |
| `EngagementBudget`, `AnchorIdle` (+ `start_engaged` seam), `StateLight` | Assault life + DISENGAGE, hub idle, the gameplay light. |
| `ArmorQuery` / `ArmorPlate._resolve` pattern | Hit-aware, once-per-HitBox decisions; the template for a shield arc or a hull `deflects_hit` answer. |
| `Shield` | Discrete-charge "absorbs one hit" model (a candidate data model for an enemy shield, 2-research §2.4). |
| `Health.increase()` | Repair. |
| `RocketTrail` + `assault/assets/sprites/projectiles/rocket.png`, `Rocket_blue.png` | Rocket visuals. |
| Sniper barrel unfold (`SniperBrain._tick_barrel`, `barrel_open`, `scale.y` lerp, ease-out) / `ArmorPlate.set_glow` (modulate lerp) | The "projector unfolds while supporting" visual state and a cyan tint, with no frame animation. |
| `SpecialistExitProbe` (`tests/helpers/specialist_exit_probe.gd`), `tests/helpers/level1_drone_concurrency.gd`, `tests/helpers/enemy_ai_harness.gd`, `test_enemy_dual_mode.gd` `_tick()` | Measured exits, density helpers, both harnesses. |
| `SectorHub._spawn_patrol()` + `test_sector_hub_patrol.gd` `_clearance_violations()` | Hub placement and its clearance gate. |

## Conventions that constrain this

- **AI stack (Ph1–Ph4):** a brain decides, `EnemyMover` is the single writer of `velocity` / `rotation` and the one
  `move_and_slide()` (gated by `test_enemy_mover_single_writer.gd`, empty allowlist, also sweeping the root script and
  its ancestors). Clocks are accumulated `delta`, randomness only from `brain.rng`, the player only via `TargetInfo`.
  A curved path is a brain-side `turn_toward` request; `turn_rate × speed ≤ acceleration` is pinned for any config that
  curves.
- **Projectiles:** exactly one owner (pool or `expired → queue_free`). Pools are direct root children, sized by formula
  and pinned. Persistent ordnance has its own lifetime cap, is never in `enemies`, never scored. Ordnance speeds never
  enter `_every_shipped_enemy_bullet_speed()` (round family only); each ordnance kind has its own row in
  `test_enemy_bullet_lifetime.gd`, speeds read from config.
- **Armour is parts plus a hull rule, never a mask**; a breakable part resolves each hit once. Direct emitters (beam,
  nova, dash, shield overload) call `received_damage.emit()` and bypass hit-aware rules.
- **Configs are flat** `ShipConfig` subclasses with `@export_group` sections; `.tres` values win; `privatise()` on
  `_init` and `_enter_tree`; contact damage = `config.collision_damage` via `ContactProfile`.
- **Assault:** a specialist's life is one attack; a telegraphed attack is never cut off by its budget (the budget
  defers to it, bounded); an attack starts only with enough budget left; every budgeted specialist has an
  **attack-in-budget row** through a real `WaveManager`; `ENEMIES_CLEARED` deadlines use measured (curved) exits;
  persistent-ordnance enemies stay out of `ENEMIES_CLEARED` sections (Bomber, Gatling precedent). Level density is
  gated against frozen legacy constants; a new enemy kind added to existing waves has **no legacy baseline** (§Risks).
- **Rails:** a shooter or area-denier moved to a brain needs a rail fallback (`on_suspended()`), mandatory since Ph3.
- **Hub:** groups append after the existing 12 rng draws; each group's anchor clears every `MissionTrigger` /
  `PickupBase` / the player spawn by `idle_radius + perceive_radius`; each `lose_radius` exceeds the largest distance
  the enemy's own cycle opens, by an asserted inequality.
- **Lights:** `StateLight` COMMIT (white) is exclusive to a real committed attack; a decoy/feint is CHARGING only;
  lights indicate state, hulls are never recoloured (IDEAS §21.1).
- **Facing:** `rotation = heading.angle() − sprite_forward_angle` via the mover; art nose-down is the default `PI/2`.
- **Dual-mode tests:** parameterise on a bare label (`use_parameters(["open_space", "assault"])`), build the harness in
  the body (the GUT default-argument leak), drive with `_tick()`.
- **Signals** are declared with the arguments they emit (`test_signal_emit_arity.gd`).
- **UIDs** never hand-typed or copied; new references UID-less or minted headlessly.
- **Art:** PixelLab via the `pixel-art-generation` skill, strict top-down, saved with `scripts/pixellab.sh`, ≤ 90 %
  opaque (`test_entity_sprite_transparency.gd`); keep a sprite node's type and name once tests reference it.
- **Gate wall clock:** ~300 s cap, at ~257 s after Ph4. Tests that await real physics scale the clock (8×), restored in
  `after_each`.

## Dependencies and blast radius

- **Hit-aware damage for shields** touches `HurtBox` (every hurtbox in the project, including the player's) or
  `BaseEnemy._on_received_damage` (every enemy) or the projectile side (`bullet.gd`, `homing_missile.gd`,
  `warhead_missile.gd`, `beam_behavior.gd`). Whichever is chosen, `test_hitbox_hurtbox.gd`, `test_base_enemy.gd`
  (`_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`), `test_player_bullet_lifetime.gd` and `test_armor_query.gd` are in range.
- **Repair** changes what `BaseEnemy._on_health_changed` does on an increase (no flash), and touches every
  `_on_health_changed` override (the station's death sequence; anything else that overrides it).
- **Enemy rockets on bit 32** reach every enemy hurtbox (runtime mask 1121), every enemy-ordnance hurtbox (mask 96 —
  bombs, mines, sibling rockets), the Ram's plates (mask 96, and they *break* on `ROCKET`), and asteroid hurtboxes
  (big asteroid 512 / mask 32). They do **not** reach the player (hurtbox mask 1281 = 1 + 256 + 1024) or allies (1281)
  unless the HitBox is also on 256.
- **Group `enemies`** feeds eight player systems (homing targeting, dash, beam, nova, EMP, AI targeting indicator,
  shield overload, engine boost). Rockets and shield nodes must stay out of it; the support ship itself joins it.
- **Level 1:** adding a new kind to existing waves changes section density, the ENEMIES_CLEARED deadline rows
  (cloud_descent margin 0.40 s on the ram row; the Swarm drones' 76 s rows), and `test_level1_specialist_spawns.gd`'s
  `EXPECTED` pin (50 rows) if it is extended to the new kinds.
- **Rosters a new enemy directory must join:** `test_enemy_contact_damage.gd` `ROSTER`, `test_contact_hitbox_geometry.gd`
  `ROSTER`, `test_enemy_hurtbox_geometry.gd` `ROSTER` (each guarded by a completeness sweep), `test_base_enemy.gd`
  `_AUTHORED_CONTACT_MODES` (a support with contact `NONE`) and possibly `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`; directory
  sweeps (config isolation, sprite transparency, single writer) pick it up automatically.
- **Hub:** `test_sector_hub_patrol.gd` asserts `anchors.size() == 7` and > 1000 px apart, and the seed order.
- **Docs:** `docs/enemy-roster.md`, `docs/architecture/modules/assault.md` / `global.md` / `open_space.md`,
  `PROJECT.md`, CLAUDE.md gate paragraph, per-enemy `ENEMY.md`.

## Risks, edge cases, testing requirements

| Id | Risk / edge case | Note |
|---|---|---|
| C1 | **A rocket hits its own launcher** the frame it leaves the tube (bit 32 reaches every enemy hurtbox, including the corvette's own) | Arm the rocket's damage only after it clears its launcher (arming distance / time, or an owner exclusion). Must be tested. |
| C2 | **Sibling rockets kill each other** (a cluster's children, a salvo in close order) because enemy-ordnance hurtboxes mask 96 include bit 32 | The rocket's own hurtbox mask must exclude 32, or rockets must not sit on 32. |
| C3 | Enemy rockets **break Ram plates** (`ArmorPlate.breaks_on` = ROCKET) and are "deflected" by an armoured hull only for *player* projectiles (`ArmorQuery` is called by player projectiles, not enemy ones) | Decide whether friendly rockets strip a Ram (emergent, maybe desirable) and what the hull does to an enemy rocket. |
| C4 | `ContactBlast` never hurts enemies, so "made to hit other enemies" via the explosion radius needs a new rule | Either the impact only, or an enemy-damaging blast variant. Ph2 left enemy friendly fire "undecided (Ph8 at the earliest)"; this phase must decide it for rockets explicitly. |
| C5 | Persisting rockets hold an `ENEMIES_CLEARED` section open (`container.get_child_count() > 0`) | Keep corvettes out of `ENEMIES_CLEARED` sections with a deadline boundary row (Bomber precedent), or add a rocket-flight term. |
| C6 | The player's homing rockets snap direction every frame and cull at the Assault rect; enemy rockets must be **dodgeable** — a turn-rate cap and a finite steer window | `turn_toward`'s rate × speed sets the turn radius; tests pin "a player turning at max rate escapes". |
| C7 | Repair through `Health.increase()` triggers the hit flash / hit burst and `amount_changed` fires even at full HP | A heal path that never flashes; tests on a full-HP ward. |
| C8 | `HurtBox.received_damage` has no hit, and direct emitters bypass hit-aware rules | A directional shield cannot be implemented in `_on_received_damage` alone; decide what nova / dash / beam / EMP do to a shielded enemy (likely: they ignore shields, as they ignore plates — or the beam stops at a shield). |
| C9 | Godot orders `area_entered` callbacks undefined: a fast bullet can overlap a shield arc and the hull in the same frame | Resolve per HitBox once (`ArmorPlate._resolve` shape). |
| C10 | The support ship's ward dies, is freed, leaves (DISENGAGE), is suspended on a rail, or is queued for deletion mid-beam | Ward references must be weak / validity-checked each tick; "retarget when the ally dies" is an explicit test. |
| C11 | Two supports on one ward, a support supporting another support, a support with no allies | Rules needed (no self-support; supports can't ward each other, or can; idle with no ward). |
| C12 | Escort "pulls the target away": the ward's own brain/mover is the single writer of its motion | The support may not move the ward. It must *request* (duck-typed, e.g. a retreat hint the ward's brain honours), or the "pull" is the support placing itself between ward and player. |
| C13 | "Cannot hide permanently above the camera" in Assault: `inner_rect()` includes ~380 px above the view | Needs a view-relative clamp (a new `EnemyWorld` query, or a player-relative band). |
| C14 | EMP stuns a support (`process_mode = DISABLED`): a projected shield on a ward keeps running unless it is owned by the support | Decide ownership of the projected shield (support-owned node vs ward-owned component). |
| C15 | New enemies in existing level-1 waves have **no frozen legacy baseline** for the density gates | The Ph3/Ph4 gates divide by frozen per-kind constants; a new kind needs its own absolute cap or joins the specialist count. |
| C16 | Gate wall clock (~257 s of ~300 s) | Two enemies × two harnesses × real-physics rows. Scale clocks; prefer hand-ticked `_tick()` over awaited frames. |
| C17 | Rockets in Open Space must not live forever or travel unbounded (no world rect there) | `max_time` + `max_distance` per kind, derived and gated in `test_enemy_bullet_lifetime.gd`. |
| C18 | The player cannot "flare" — no decoy/countermeasure exists in the player kit | "possible flare/decoy reaction" has no consumer; see 2-research S9. |

**Testing requirements (from R5.39–R5.41):** both harnesses for rocket steering toward the predicted point (and a
turn-rate bound — a hard-turning player escapes), cluster splitting (count, fan, timing, children's ownership after the
corvette dies), proximity detonation (radius, arming, warning), shoot-down (defuse, no blast), friendly-fire rules,
launcher self-hit; repair (rate, cap, no flash, out of range stops), shield application (directional absorb from the
front, pass from behind, expiry/regen, break feedback), retarget on ward death (and on ward freed/suspended), the escort
trigger at the HP threshold; per-kind lifetime rows; the Assault view clamp; attack-in-budget rows for both enemies;
hub clearance rows; roster gates; level-1 placement pins and deadline rows.

## Open questions for the plan

1. **DamageReaction (P-15):** adopt it in `BaseEnemy`, or keep BaseEnemy's flow and add a separate enemy-shield
   component? (2-research §2.4 recommends the latter.)
2. **Where the shield decision is made** (hit-aware): a new `HurtBox` hook, a hull `deflects_hit`/`absorbs_hit` duck
   type on the projectile side, or a separate shield-arc `Area2D` part? (2-research §2.4.)
3. **Enemy rockets' collision layers and friendly fire:** HitBox on 32 + 256 (hits enemies by impact) — and does the
   blast hurt enemies? (2-research §2.3.)
4. **Rocket class:** new `Kind`s on `EnemyOrdnance`, or a sibling `EnemyRocket` with the same contract? (2-research §2.2.)
5. **Owner-distance lifetime** (`max_distance_from_owner`, assigned to Ph5 by Ph1): build it, or drop it with a reason?
6. **"Highest-threat ally"**: how is threat scored (config field, `score_value`, attack state, distance to player)?
7. **Escort**: how does the support "pull" a ward away without writing the ward's motion?
8. **Assault view clamp**: new `EnemyWorld` view query vs a player-relative band.
9. **Level 1 placement**: which sections, which waves, and how the density/deadline gates treat a kind with no legacy
   baseline; keep both out of `cloud_descent` (ENEMIES_CLEARED, 0.40 s margin)?
10. **Hub placement**: where two more groups fit (315° is the only free bearing on the 1700 ring) and whether the
    support patrols with the Ram (R5.27).
11. **Visual state**: a `StateLight` shield colour (cyan) or a separate projector indicator?
