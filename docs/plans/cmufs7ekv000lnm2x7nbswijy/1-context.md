# Context — Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family

Epic `cmufs7ekv000lnm2x7nbswijy`, research task `cmufs7el2000pnm2x80pf0jig`. Researched 2026-09-28 against
`agent/auto-dev` @ `d6f7cf0`. Every claim cites the current code. Line numbers drift, so the plan should cite symbols.

Read this with:
- `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`, especially "Phase 1 - as built", the Phase 2 plan section, the
  "Built in tX" notes and "Phase 2 - as built";
- `docs/epics-done/cmufs7ek60001nm2x6d0bt2et/REPORT.md`;
- `docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §7 (roadmap row "3 Fighter, Gatling Interceptor, bullet family").

The *scope check* (what changed against the roadmap and the scope text) is at the top of `2-research.md`.

---

## Requirements from the attached documents

These are quoted briefly from `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` (IDEAS) and
`ENEMIES.md` (AUDIT), and cover only what this phase's scope assigns. The plan's coverage table should carry the `R3.x`
ids.

| Id | Requirement (source) | Needs research? |
|---|---|---|
| R3.1 | **Fighter** replaces the Light Assault Ship. Size 56–72 px (IDEAS §2, §5.3) | code |
| R3.2 | The Fighter flies an **attack run**: approach → pass left of the player → fire a burst → wide turn → reposition → second pass. It has "acceleration and turn radius so the player can anticipate the curve" (§5.3 Movement) | yes: findings 1 and 3 |
| R3.3 | Fighter weapons have two modes. **Aimed burst:** 3–5 bullets toward the *predicted* position. **Forward burst:** 5–7 *fast* bullets along the nose. The fighter switches **by distance, not by a spawn property** (§5.3 Weapons) | yes: findings 2 and 4 |
| R3.4 | Fighter group: three fighters form a **pincer** and a fourth makes a **frontal pass** (§5.3 Group) | yes: findings 1 and 5 |
| R3.5 | Fighter in Assault: stays in the vertical corridor, but uses lateral attack runs and curved exits. "Formations should be a starting arrangement, not the complete behavior" (§5.3 Assault) | code |
| R3.6 | **Gatling Interceptor** replaces the Interceptor. Size 56–72 px. It is "a suppression unit, not a chase unit" (§5.4) | code |
| R3.7 | Gatling movement: it keeps **side-on range** and repeatedly moves through the player's flank, fires a stream, brakes, swings around and attacks from the other side (§5.4 Movement) | yes: finding 1 |
| R3.8 | **Pressure windows** replace the constant 11 shots/s: 0.25 s spin-up, an 8–12 round stream, 0.4 s cooldown, reposition, repeat. This gives "visible attack rhythm" (§5.4 Attack) | yes: findings 3 and 4 |
| R3.9 | Settle whether the Gatling fires forward or at the player: "the redesign should remove that ambiguity" (§5.4 Source; AUDIT) | code (see S1) |
| R3.10 | **Convergence fire:** "two nearby interceptors aim from slightly different angles so their streams overlap around the player's likely future position" (§5.4 New weapon effect) | yes: findings 2 and 4 |
| R3.11 | Gatling in Assault: the same flank logic, with "the side of the arena" as the temporary flank reference (§5.4 Assault) | code |
| R3.12 | **Bullet family** (§11.1): Pulse Round (basic, accurate); Scatter Round (short-range spread); Gatling Stream (many low-damage projectiles with a visible stream rhythm); Heavy Shell (slow, large, high impact). Built on the pooled `EnemyBullet` with `ProjectileLifetime` (epic text) | yes: findings 4 and 6 |
| R3.13 | "Later enemies can pick a round instead of retuning one bullet" (epic text) | code |
| R3.14 | Formations become dynamic groups: "FormationSpawn → SquadController → role assignment → individual AI → dynamic regrouping". When F1 dies, F3 becomes left flank, the formation contracts, and one ship may switch to the attack role (§17) | yes: finding 5 |
| R3.15 | V, **W**, wedge, line, diagonal and cluster helpers are kept only as spawn layouts, and their job ends when the enemies activate: assign Leader → Flanker L/R → Support (§35, §17) | code (**no W helper exists**, see S7) |
| R3.16 | Readability (§21–23): silhouette, faction accents, **one** gameplay light per state (red armed, yellow charging, white locked). Dark hull, cool edge highlight, red stripe, one bright weapon indicator. Fighters are authored at 64×64 or 72×72, "increase contrast between cockpit, hull, engine, and weapon pods" (§22) | yes: finding 6 |
| R3.17 | Combat tests (§40) for fire cadence and weapon selection, in **both** harnesses (Open Space and Assault), using the same spec with only the constraint changed. The epic adds pass geometry, pressure-window rhythm, role reassignment and formation-to-role handoff | code |
| R3.18 | §41 Phase 2 items 3–4 (Fighter, Gatling Interceptor) | — |
| R3.19 | Level-1 Light Assault Ship and Interceptor spawns move to the new enemies as a spawn layout plus the corridor constraint, **with timing preserved** (epic text) | code, and the hardest part |
| R3.20 | Both enemies join the Open Space **SectorHub ambient spawn** (epic text) | code (see S9) |
| R3.21 | The design checklist (§43) should be answerable for both enemies: preferred distance, movement signature, reaction to the player boosting away or coming from behind, telegraph, works alone, works in combination | judgement |

These are out of this phase by scope, listed so the coverage table can cite them:
- squad **messages** (§18), Ph14;
- idle profiles as a general system (§18.5), Ph14 (but see S9);
- the EncounterDirector (§32), Ph13;
- rockets (§11.2), Ph5;
- energy weapons (§11.3), Ph8;
- `max_distance_from_owner` and `persist_after_owner_death` (§12), Ph5;
- difficulty tiers (§29), Ph16, where only the `accuracy` hook exists;
- line of sight (§28), Ph4;
- other level-1 enemies coming off rails, Ph15;
- enemy audio telegraphs, Ph17. No enemy SFX pipeline exists.

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/light_assault_ship/` (`light_assault_ship.gd/.tscn`, `fighter_config.gd/.tres`, `states/approach_state.gd`, `states/strafe_exit_state.gd`, `ENEMY.md`) | `LightAssaultShip extends BaseEnemy`. `_ready()` builds a `BulletPool` (20 × `enemy_bullet.tscn`) and an `AimedAttackPattern`: `fire_interval` = 0.3 when forward, else `config.fire_interval` 0.8; `bullet_speed` = the literal `420.0 if forward else 250.0`; `aim_at_player = not forward`; damage 8. It also adds a plain `_process`-driven `AttackController`. `aim_mode` is a String prop, `"PLAYER"`/`"FORWARD"`, and a spawn prop overrides the config. Its `AIStateMachine` (Approach → StrafeExit, camera-relative) runs only with no path mover. Config: HP 60, contact 20, score 25. Sprite `assault/assets/sprites/enemies/assault.png` (64×64) is flipped 180° by `_rotate_sprite()`; `light_assault_ship.png` (34×34) is unused. There is one shared `CircleShape2D` (r 13, scale 2.2 ≈ 28.6 px) for the body, HurtBox and ContactHitBox, and no authored Contact/DefenseProfile | The Fighter replaces it. It is the **last user** of the path mover's `"AIStateMachine"` name lookup |
| `assault/scenes/enemies/interceptor/` (`interceptor.gd/.tscn`, `interceptor_config.gd/.tres`, `ENEMY.md`) | `Interceptor extends BaseEnemy`. It builds a pool of 20 and a `GatlingAttackPattern` (`fire_interval` 0.09 ≈ 11 shots/s, damage 4, speed 220, spread ±0.08 rad) behind a plain `AttackController`. Config: HP 70, score 75. It never re-applies `collision_damage`; the scene's 20 equals the ShipConfig default. Sprite `interceptor.png` is **64×74**, just outside 56–72. Its circle is r 14 × 1.8 ≈ 25 px. It has no `aim_mode`, so `.shoot_forward()` on it is a silent no-op | The Gatling Interceptor replaces it |
| `global/resources/attack/gatling_attack_pattern.gd` | `aim_at_player = true` by default. Its direction is `TargetInfo.player(tree).aim_direction(pos, speed, accuracy)`, otherwise `Vector2.DOWN.rotated(ship.rotation)`, then rotated by the **global** `randf_range(-spread, spread)` | This settles R3.9: **the shipped Interceptor aims at the player.** `interceptor/ENEMY.md:24` and `docs/enemy-roster.md:233` ("always fires forward") are wrong. The unseeded `randf` makes the spread non-deterministic under test |
| `global/resources/attack/aimed_attack_pattern.gd`, `attack_pattern_resource.gd`, `forward_attack_pattern.gd` (allies only, player `Bullet`), `radial_attack_pattern.gd` | `fire(ship, pool)` shoots **one bullet per call**. The base class has `fire_interval` and `start_delay`. There is **no burst, salvo, spin-up or per-bullet visual config** in any pattern | Bursts and pressure windows are new. The plan must choose between a pattern-level burst and brain-sequenced `fire_now()` (see `2-research.md` §3) |
| `global/components/attack_controller.gd` | Exports `pattern`, `bullet_pool`, `enabled`, `driven_by_brain`. `tick(delta)` accumulates and subtracts `fire_interval`, and fires only while `enabled`; the phase keeps running while disabled. `fire_now()` ignores both `enabled` and the timer. It has no signals | Brain-driven fire is the Razor precedent. **On a rail the brain is suspended, so a `driven_by_brain` controller stops firing** (DECISIONS, t10 note) |
| `assault/scenes/projectiles/enemy_bullet/enemy_bullet.gd/.tscn` | `EnemyBullet`: `speed` 250, `set_direction()`, `reset()`, `expired`. `reset()` restores direction, rotation and speed but **not** the HitBox damage or layers. Scene: `ProjectileLifetime` (18 s / 2400 px / world rect); `Visual` is a `Line2D` of 12 px × 3 px, **orange** `(1, 0.4, 0.1)`; `HitBox` 256/128, damage 10, `CapsuleShape2D` r 2 h 10. The only other bullet scene is `enemy_bullets/enemy_sniper_bullet.tscn` | The bullet family is built on this. Orange is the colour the research says to avoid for bullets (finding 6) |
| `global/components/bullet_pool.gd` | `bullet_scene`, `pool_size`. `_container = get_parent().get_parent()`, hardcoded. `acquire(pos)` returns null with a warning when the pool is empty. `cancel_active()` in `_exit_tree` frees in-flight bullets | One pool = one scene. Container injection stays Ph5 (DECISIONS). An empty pool fails silently, which matters for 8–12-round streams |
| `global/components/projectile_lifetime.gd` | `max_time`, `max_distance` (from the origin), `use_world_rect` (Assault only). It arms lazily, emits the host's `expired` and never frees | The Scatter Round's "short range" is a per-scene `max_distance` |
| `global/enemy_ai/` | `EnemyBrain` (`tick`, `on_suspended`, `actor`, `mover`, `attack`, seeded `rng`); `EnemyMover` (single writer, requests cleared every step, `boost`, `halt`, `release_constraint`, wrappers including `strafe`/`intercept`); `Steering` (static primitives including `strafe`, `intercept`, `turn_toward`, `clamped_lead_time`, `formation_slot`, flocking; **no `lead_target`, no `break_contact`**); `TargetInfo` (`predicted_position`, `intercept() -> {ok, point, time}`, `aim_direction(from, speed, accuracy)`, `facing`); `SquadController` (roles LEAD/FLANK_LEFT/FLANK_RIGHT/REAR, sides, `attack_window_open`, `rear_ring_angle`, `member_index/count`, engagement); `EngagementBudget`; `AnchorIdle`; `MovementConstraint.inner_rect()`; `EnemyWorld` | The whole stack is reused. Nothing new is needed at the architecture level |
| `assault/scenes/enemies/swarm_drone/`, `razor_drone/` | Phase 2 templates. A root script with no `_physics_process` copies flat config fields onto the brain in `_ready()`, so the brain builds its budget on its **first tick**. `var squad` is the duck-typed slot. `StateLight` is a child. The Razor builds its `AimedAttackPattern` **per instance** in code, never as a scene sub-resource, with a scene `BulletPool` (4) and `AttackController` (`enabled = false`, `driven_by_brain`). Swarm `sprite_forward_angle` is `PI/2`; Razor's is `-PI/2` | Copy this shape exactly |
| `assault/scenes/systems/wave_builder.gd` | `FIGHTER` / `INTERCEPTOR` constants and `fighter()` / `interceptor()`. `SpawnConfig` has `at`, `move`, `delay`, `free_after`, `formation`, `squad(id)`, `shoot_forward()`/`shoot_at_player()` (these write `aim_mode`), and `prop`. Helpers: `v_formation`, `wedge_formation`, `line_formation`, `diagonal_formation`, `cluster_formation`. **There is no W.** | Formations-as-layouts and the `aim_mode` props |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | The squad key is `"<wave> <squad_id or spawn_index>"`, taken before the formation is expanded, so a formation is one squad. It sets `entity.squad` before `add_child` when `"squad" in entity`, and attaches `EnemyPathMover` only when `movement` is set | Handoff point. Already done in Ph2 |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | **62 `b.fighter()` lines, 15 of them formations, 106 fighters in all, every one with `.move()`**: 55 `straight`, 4 `arc`, 3 `u_sweep`, plus `free_after` of 4.0–12 s on the loose side runs. They appear in `deep_space` (DURATION 30 s), `planet_approach` (DURATION 110 s) and `cloud_descent` (**ENEMIES_CLEARED**, default 10 s timeout). `cloud_descent`'s 72 s wave has 4 side fighters plus a V3 (lines ~983–987). There are **2 interceptors**, both in `deep_space` (lines 269–270, `.move(b.player_focus(240))`). Level 1 contains no W formation | R3.19: the migration inventory |
| `assault/scenes/systems/level_director/level_director.gd::_wait_enemies_cleared` | Polls until `wave_manager.enemy_container` is empty, then frees everything left at the timeout, which counts as escapes and costs combo. **In-flight enemy bullets live in that container** (pool → ship → container) | The ENEMIES_CLEARED wait also waits on bullets. `EnemyBullet.max_time` is 18 s; in Assault, `use_world_rect` ends a bullet sooner |
| `assault/scenes/enemies/space_station/station_reinforcements.gd` | LEFT/RIGHT squads have 2 `b.interceptor()` each, `straight(200, ±PI/2)`. TOP has 2 `b.fighter().shoot_forward()`, `straight(170, ±0.5)`. All use `.free_after(reinforcement_lifetime)`, all are on rails, and none sets `squad` | Same trap as Ph2's S6. Repointing `WaveBuilder.FIGHTER`/`INTERCEPTOR` puts the new scenes on rails here, and a rail suspends the brain |
| `assault/scenes/enemies/enemy_path_mover.gd` | Writes `rotation = atan2(-vel.x, vel.y)` (nose-down art), **ignoring `sprite_forward_angle`**. Suspends through `set_physics_process(false)`, the `"AIStateMachine"` lookup and `suspend_ai()` | A nose-up sprite on a rail faces backwards. Phase 2's Swarm is nose-down, which hid this |
| `open_space/scenes/levels/sector_hub.gd` | `_spawn_patrol()` builds a Swarm squad at bearing 90° and a Razor at 270°, on ring 1300, with `patrol_seed` | R3.20 |
| `assault/scenes/levels/level_2/level_2_waves.gd` | Uses `builder.fighter()`, but `level_2.tscn` is unreferenced | It only has to keep compiling (project-load integrity) |
| `assault/scenes/allies/ally_fighter/` | `AllyFighter` + `ForwardAttackPattern`, using the player `Bullet` | Not touched. Its name is close to "Fighter" (see naming, below) |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `Steering.strafe(pos, target, side, max)` | A velocity perpendicular to the target line. It is the core of a side-on flank pass (R3.7) |
| `Steering.intercept(pos, TargetInfo, speed, lookahead)` + `Steering.clamped_lead_time` | Reynolds pursuit with a bounded lead. The approach leg of the attack run |
| `Steering.turn_toward(current_dir, desired_dir, max_rate, delta)` | **The required way to fly a curve** (DECISIONS Ph2: `EnemyMover.max_turn_rate` turns only the sprite). The wide turn uses it. Turn radius = speed / rate |
| `TargetInfo.aim_direction(from, shot_speed, accuracy)` / `intercept()` | **This is `lead_target`** (DECISIONS Ph1: "lead_target → Ph3 … it is `TargetInfo.aim_direction`"). The aimed burst and convergence aim. `intercept()` returns `ok = false` when no solution exists |
| `TargetInfo.facing`, `relative_angle_from()`, `velocity` | "Pass beside the player" and "the player's flank" are both relative to the player's velocity or facing (R3.2, R3.7) |
| `SquadController` | Roles, side claims, `attack_window_open`, `member_index/count`, `role_changed`, full-recompute reassignment. Pincer = FLANK_LEFT + FLANK_RIGHT; frontal pass = LEAD (R3.4, R3.14) |
| `EngagementBudget` + the Swarm/Razor DISENGAGE shape (`release_constraint()`, `exit_speed`, seek past the nearest edge of `projectile_world_rect()`, free when outside) | The Assault exit rule. Required so AI fighters cannot stall `cloud_descent` |
| `AnchorIdle` + the `patrol_anchor = Vector2.INF` sentinel + the `start_engaged` test seam | Hub idle → combat handover (R3.20) |
| `StateLight` (OFF / ARMED / CHARGING / COMMIT, `blink_once`) | Gatling spin-up = CHARGING (yellow), stream = ARMED/COMMIT; fighter burst telegraph. COMMIT (white) is only for a real attack |
| `ContactProfile` (COLLISION default) | Neither enemy rams, so both keep the default COLLISION profile (IDEAS §16 "normal ship body damage"), and `test_base_enemy._AUTHORED_CONTACT_MODES` stays unchanged |
| `AttackController` (`enabled`, `driven_by_brain`, `tick`, `fire_now`) | Stream cadence = `tick()` while `enabled`. Burst shots = `fire_now()` from brain clocks |
| `AimedAttackPattern` / `GatlingAttackPattern` `accuracy` | 0 = aim at the current position (legacy), 1 = full intercept. The aimed-burst lead and the Ph16 difficulty hook |
| `BulletPool` + `EnemyBullet` + `ProjectileLifetime` | A round is a bullet **scene** (one pool per round per shooter). `max_distance` gives the Scatter Round its short range |
| `tests/helpers/enemy_ai_harness.gd`, `test_enemy_dual_mode.gd` (`use_parameters` on a **label**, `_tick()` re-integration) | R3.17 dual-mode specs. The GUT default-argument leak trap is recorded in DECISIONS (t12 note) |
| `tests/helpers/level1_drone_concurrency.gd` (`spawn_times`, `peak_concurrency`, `worst_exit_seconds`, `squad_intervals`, `peak_intervals`) | R3.19 concurrency ceiling for fighters, as the Ph2 C3 check did for drones |
| `tests/integration/test_level1_drone_spawns.gd` (t1 pin, computed from `_build_sections()` data) | Template for a **fighter-spawn characterization pin** before migration |
| `tests/integration/test_engagement_deadline.gd` | Extend it with fighter and Gatling formulas for ENEMIES_CLEARED sections |
| `scripts/pixellab.sh` + the `pixel-art-generation` skill | Two sprites, strict top-down |

## Conventions that constrain this

- **Single writer of motion** (`test_enemy_mover_single_writer.gd`, with an empty permanent allowlist). The brains and
  root scripts never write `velocity` or `rotation`. Curves are requested by the brain with `turn_toward` from the
  current velocity every tick, with `turn_rate × speed ≤ acceleration` pinned per config (Ph2 convention).
- **Config-driven, flat `ShipConfig` subclasses** with `@export_group` Movement / Attack / Defense / Tactics / Scoring
  sections. There are no nested resources, arrays or dictionaries (`test_config_instance_isolation.gd`, floor 10
  configs). A pattern is built **per instance in code** from flat config fields, never as a shared scene sub-resource
  (Razor precedent).
- **Brains tick on physics, with accumulated-`delta` clocks, no `Timer` nodes, and randomness only from `brain.rng`.**
  `GatlingAttackPattern`'s global `randf` breaks the last rule for any deterministic spread test.
- **Assault skips idle** (a provider exists). Open Space enemies start in `AnchorIdle`.
- **The Assault AI exit** frees a live enemy outside `projectile_world_rect()`, not `cull_rect()`. A leaving enemy is an
  *escape* for `ScoreTracker`.
- **Design-unit coordinates** for spawns (640×360 × `WORLD_SCALE` 2). Formation offsets remain design units.
- **One owner per projectile.** Enemy bullets are always pooled. The pool frees in-flight bullets when its ship exits.
- **Signal arity:** any new signal (for example `phase_changed(new_phase: int)`, `weapon_mode_changed(mode: int)`) is
  declared with its arguments (`test_signal_emit_arity.gd`).
- **Verbose-gated logging** for anything that prints per shot.
- **Facing:** `rotation = heading.angle() - sprite_forward_angle`. Nose-up art uses `-PI/2`.
- **Naming:** `Fighter*` is taken (`FighterConfig`, `FighterApproachState`, `FighterStrafeExitState`), and so are
  `AllyFighter`, `Interceptor` and `InterceptorConfig`. A clean `class_name` choice (for example `EnemyFighter`, or
  retiring the old classes in the same task) must be made **before** the files exist, because Godot rejects duplicate
  global class names at load time.
- **UIDs:** never hand-type them (CLAUDE.md). A `git mv` of a directory keeps each `.uid` sidecar next to its file.

## Dependencies and blast radius

Tests that break the moment the old scenes or scripts change or disappear:

| Test | What it pins today |
|---|---|
| `test_enemy_bullet_lifetime.gd` | **Regex-parses `light_assault_ship.gd`'s source** for `bullet_speed = X if forward else Y` and asserts it matched. It builds `InterceptorConfig.new().bullet_speed`. Its speed-source list derives `min_speed = 150` → `max_time 18 s`, `max_distance 2400`, and checks both bullet scenes. **A Heavy Shell slower than 150 px/s breaks the derivation.** A new round scene is not checked until it is added to that loop |
| `test_enemy_path_mover.gd` | Preloads `light_assault_ship.tscn` and pins that the `"AIStateMachine"` lookup suspends it |
| `test_base_enemy.gd` | The sprite-flip case hardcodes `["light_assault_ship", "ram_ship"]`. `_MIN_ROSTER_SIZE = 10` |
| `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` | Hand-written rosters, each with a directory-completeness sweep. Every new or renamed enemy folder must be added to all three |
| `test_config_instance_isolation.gd` | Floor of 10 entities with a config. Replace-one-with-one keeps it neutral |
| `test_station_reinforcements.gd` | Asserts every squad ship has an `EnemyPathMover`. Its spawn margin assumes the interceptor sprite's **37 px half-extent** (64×74). `test_no_squad_uses_a_self_managed_ai_enemy` forbids GUNSHIP and RAZOR_DRONE |
| `test_sector_hub_patrol.gd` | `container.get_child_count() == swarms.size() + 1`, which **breaks as soon as the hub spawns more**. Its clearance sweep must gain per-group rows for the new patrols |
| `test_entity_sprite_transparency.gd` | New ship **and bullet** sprites fall under its ≤ 90 % opaque rule (floors 12/12) |
| `test_engagement_deadline.gd` | Lists only the swarm and razor scenes. AI fighters in `cloud_descent` need their own formula |
| `test_level1_drone_spawns.gd` | Pins only drone and razor entries, so fighter changes leave it alone unless drone lines move |

Other dependencies:
- **Docs:** `docs/enemy-roster.md` (fighter §, interceptor § "Always fires forward", the "Always `.move()`" list,
  the reinforcement table), `docs/architecture/modules/assault.md` (roster, the contact-damage re-apply list, the
  bullet section), `global.md` (attack patterns), both `ENEMY.md` files, `CLAUDE.md`'s gate paragraph if a new gate is
  added, and `docs/BULLET_POOL.md`.
- **Score:** `ScoreTracker` escape and combo accounting applies once fighters exit by DISENGAGE instead of by rail
  cull. This follows the legacy parity already decided for drones.

## Risks, edge cases, testing requirements

| # | Risk | Why it is real here |
|---|---|---|
| C1 | **Forward fire goes backwards on nose-up art.** Aimed and Gatling forward fire use `Vector2.DOWN.rotated(ship.rotation)`, which is only correct for `sprite_forward_angle = PI/2`. `EnemyPathMover` also ignores `sprite_forward_angle` | The forward burst (R3.3) must derive "nose" from the heading (`Vector2.RIGHT.rotated(rotation + sprite_forward_angle)`), and a test must pin it for a nose-up actor. Otherwise the new sprite must be nose-down |
| C2 | **Rails silence brain-driven weapons.** The station reinforcements (2 TOP fighters, 4 interceptors) stay on rails. A suspended brain stops ticking a `driven_by_brain` controller | `on_suspended()` must hand the controller back to self-timed `_process` fire with a legacy-equivalent pattern (a rail fighter fires forward at the legacy cadence), or the station squads become harmless. `test_station_reinforcements` has no fire assertion today, so this would be silent. It needs a new assertion |
| C3 | **Deadline in `cloud_descent`** (ENEMIES_CLEARED, 10 s). Its 72 s wave has 6 fighters, whose legacy `free_after` is 4.5 s. The section's timeout clock starts when waves complete, and **in-flight bullets also hold the container open** | Fighter `engage_seconds` + worst exit + **the last shot's bullet flight** must fit. A bullet's Assault lifetime is bounded by the world rect: diagonal ≈ 2274 px / its speed. At 150 px/s that is up to ≈ 15 s, which alone exceeds 10 s. So a Heavy Shell must never be fired in an ENEMIES_CLEARED section, or the shooters must stop firing ≥ rect-crossing time before their budget ends. The deadline test must gain a bullet term. Phase 2's formula had none (drones fire nothing, and the Razor is DURATION-only) |
| C4 | **Density.** 106 rail fighters with 4–6 s lifetimes become AI fighters that make second passes. Bullets on screen scale with alive shooters × burst size | The concurrency ceiling (Ph2 C3 pattern: pin the legacy peak, cap attack-capable and all-alive ratios) must cover fighters. A second ceiling on **shots per second in flight** is worth considering, because 3–5-round bursts at 1 burst per pass are *fewer* shots per second than today's 0.8 s aimed interval, but forward bursts of 5–7 are *more* than today's 0.3 s forward cadence per pass |
| C5 | **Corridor geometry for turns.** Turn radius r = v/ω. A 260 px/s fighter turning at 1.5 rad/s needs a ≈ 350 px diameter. The corridor's hard band lets an AI go 450 px outside the visible rect | A wide turn may happen off screen in Assault. That is legal, but reads as "left the fight". The plan must pick v and ω so the turn fits inside the soft band, or prefer lateral reversals in Assault (IDEAS: "lateral attack runs and curved exits") |
| C6 | **Pool starvation.** A 12-round stream of Gatling Stream bullets at 220 px/s crossing ≈ 1500 px lives ≈ 7 s. Two windows fit in that time, so ≥ 24 bullets can be live | `acquire()` returns null with only a warning, which would silently shorten a stream. Pool size must be derived from `rounds × ceil(lifetime / window period)` and pinned by a test |
| C7 | **Weapon-mode flip-flop at the distance threshold** | Hysteresis (two thresholds) and latching the mode at burst start. A boundary test at exactly the threshold ± epsilon |
| C8 | **Convergence needs a partner.** `SquadController` has no pairing concept, and a convergent pair must be two Gatlings within some radius | Options: a squad of 2 Gatlings, where the LEAD opens a window and the FLANK answers (the Swarm's `attack_window_open` precedent), or a new board field. Neither may add a clock to the board ("event-driven, no clock" is a Ph2 decision) |
| C9 | **Mixed squads.** `_reassign()` sorts every member by distance, so a squad mixing drones and fighters would hand a drone a fighter's LEAD | Squads stay per-family: formation = one squad; a loose line needs its own `squad(&"…")` id. The plan should state it |
| C10 | **Hub scope conflict:** idle profiles for other families are Ph14 (DECISIONS), but R3.20 puts both enemies in the hub ambient spawn now | See S9. A minimal `AnchorIdle` orbit or drift for both, reusing Ph2 code, with the clearance check extended |
| C11 | **Determinism:** the global `randf` in the Gatling spread | Tests on stream spread must inject the brain's `rng`, or the pattern gains an `rng` parameter |
| C12 | **Class-name collisions** (see Conventions) | Decide before creating files |
| C13 | **Station test margins** assume a 74 px interceptor sprite | A new 64 px sprite changes the half-extent. Update the test from the scene rather than a literal |

Testing requirements (R3.17), at minimum:
- the pass geometry: closest approach within a band beside the player, on the claimed side;
- the wide turn's radius ≈ v/ω, never crossing the player;
- a second pass happens;
- weapon selection by distance, with a hysteresis boundary and latch-at-burst-start;
- burst sizes within [3, 5] and [5, 7];
- forward fire along the nose for **both** sprite conventions;
- Gatling rhythm: CHARGING for ≈ 0.25 s, then N ∈ [8, 12] shots at the stream interval, then 0 shots for ≈ 0.4 s, then a reposition, then a repeat;
- convergence: two streams' aim lines meet within X px of the predicted point, from bearings differing by ≥ Y°;
- role handoff: a V formation spawns → roles assigned → the LEAD dies → a FLANK or REAR is reassigned in the same call;
- every behaviour spec in both harnesses;
- the level-1 fighter pin, deadline and concurrency;
- the rail fallback still fires;
- each round's lifetime and speed are inside the derivation.

## Open questions for the plan

1. **Directory and class names.** Options: `git mv light_assault_ship → fighter` and `interceptor → gatling_interceptor`
   with renamed classes (the Razor precedent), or new folders plus deletion. Also which `class_name`s to use given the
   collisions above.
2. **Pattern-level burst vs brain-sequenced shots.** See `2-research.md` §3.
3. **One bullet scene per round, or one scene with variant data?** Research recommends a scene per round.
4. **Which rounds have a consumer this phase?** Pulse (fighter aimed burst), and Gatling Stream (Gatling). The forward
   burst could use a fast Pulse or its own round. **Scatter and Heavy Shell have no in-scope consumer.** Either they
   ship tested but unused (a family "later enemies pick from"), or one current enemy adopts one. Candidates: the
   fighter's close-range forward burst as a narrow Scatter, or the Gunship on Heavy Shell (but the Gunship is Ph10).
   See S5.
5. **How far the Assault migration goes:** all 106 fighters, or formations only? The scope says "Light Assault Ship
   spawns move", meaning all of them, with timing preserved (triggers, offsets and delays kept; `.move()`/`.free_after()`
   dropped; `shoot_*` props become ignored or removed).
6. **What the rail fallback fires** (C2).
7. **Attack-token cap:** how many fighters fire at once. Research finding 1 suggests 2 firing plus 2 dry passes as the
   default.
8. **W formation:** add a `w_formation` helper, or record W as "two V's" and drop it. No level uses W today.
