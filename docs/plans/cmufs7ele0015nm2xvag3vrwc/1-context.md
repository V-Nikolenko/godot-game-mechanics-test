# Context — Enemy rework, phase 4: Bomber, Sniper and Ram Corvette

Epic `cmufs7ele0015nm2xvag3vrwc`, research task `cmufs7ell0019nm2xnsxx8z94`, 2026-10-07.

This file covers what is already in the code. `2-research.md`, next to it, covers the scope check, outside findings,
approaches and starting values.
- Facts were read on `agent/auto-dev` at `00aced5`. Line numbers are as of that commit.
- **(inferred)** marks anything not read directly.
- Ids `R4.x` (requirements) and `C1`–`C16` (risks) are reused in `2-research.md`.
- Read first:
  - `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`: the Phase 1, 2 and 3 *as built* sections;
  - `docs/epics-done/cmufs7ekv000lnm2x7nbswijy/REPORT.md` (Phase 3).

---

## Requirements from the attached documents

`IDEAS` = `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`. `AUDIT` = `docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES.md`.
The epic text adds the test list in R4.40.

### Bomber (IDEAS §5.5, §38, §1.1, §21–23)
| Id | Requirement (brief quote) |
|---|---|
| R4.1 | Size 88–120 px. A specialist silhouette that reads as **wide** (§22, "a bomber should be wide"). |
| R4.2 | "Deliberately approach at an angle, establish a bombing line, then escape." The escape is an arc (epic text). |
| R4.3 | Three ordnance types, "selected by behavior". **Gravity Bomb:** "slow projectile that keeps traveling in the current direction and detonates after a short proximity warning". **Mine Cluster:** "drops 3–5 stationary mines in an arc behind the bomber". **Pursuit Bomb:** "slowly rotates toward the player's future position before its final acceleration". |
| R4.4 | "The player should be able to shoot bombs before detonation." This applies to all three types (epic: "all of them can be shot down"). |
| R4.5 | Smart bombing: "predicts where the player is heading, not where the player is"; "if the player is boosting right, the bomber drops a mine chain ahead of the player's current trajectory". |
| R4.6 | Assault: "keep the exact same prediction logic but clamp bomb placement to the assault corridor … temporary walls, diagonals, and pockets instead of repeatedly dropping bombs straight down". |
| R4.7 | §38: "Scrap: fixed-screen Bomber movement — keep bomber's role, completely rewrite movement and ordnance." |
| R4.8 | §1.1 verb: "Where will the battlefield become dangerous next?" |

### Sniper (IDEAS §5.6, §1.2, §31, §38, §28, §3.2)
| Id | Requirement |
|---|---|
| R4.10 | Size 48–64 px. A **narrow** silhouette (§22). |
| R4.11 | Cycle step 1–2: choose a preferred engagement distance. "If the player is too close, **create distance first**; leaving the camera is a useful tactic, not a hard requirement." |
| R4.12 | Step 3: "move laterally/diagonally to an unexpected firing offset". Positions are varied "relative to the player's current velocity and facing": "60° left, 90° right, behind the player, far above/below, diagonal". "Do not make it appear at the same relative offset repeatedly." "Prefer a position that also creates a useful line of sight rather than blindly picking a random point." |
| R4.13 | Step 4: "become **stationary** at the firing point … the player can use the telegraph window to close the distance and attack". |
| R4.14 | Step 5: "telegraph the rail shot and lock the predicted player position". |
| R4.15 | Steps 6–8: fire, then "immediately leave the firing point and attempt to create distance … again", and choose a new firing position. "Never forced into a 'shoot → return to player' loop." |
| R4.16 | The readable windows: "MOVING / REPOSITIONING = hard to hit; STATIONARY + TELEGRAPH = vulnerable; POST-SHOT DISENGAGE = escaping." |
| R4.17 | Rail shot: "very low shot width, very high speed, high damage, one clear charge line, shot leaves a short residual trail". |
| R4.18 | "Optional advanced variant: … false/decoy telegraph before the real line, but only on higher difficulty." The scope says it goes **behind a difficulty flag**. |
| R4.19 | Assault: "replacing unlimited world-space distance with a tactical off-screen band … leave the visible corridor, create a firing offset, become stationary …, then break away and re-enter from a different angle. It should **not** instantly pop back." |
| R4.20 | §31: remove the `FLY_IN_TIME` ↔ wave-path coupling. "Sniper movement state owns its approach duration", or `approach_distance / movement_speed`. |
| R4.21 | §38: "Scrap: path-authored Sniper retreat — make relocation a native AI behavior." |
| R4.22 | §3.2: `break_contact(direction)` primitive. Phase 1 and Phase 3 deferred it to Ph4, for the Sniper. |
| R4.23 | §28: a real `can_see_player()`. "Sniper refuses to fire if a large asteroid blocks the shot." It replaces the Phase 1 stub `TargetInfo.line_of_sight()`. |
| R4.24 | §27: "sniper predicts further ahead" (than a fighter). |
| R4.25 | §1.1 verb: "Where is it hiding, and can I punish its firing position?" |

### Ram Corvette (IDEAS §5.7, §13.1, §16, §15)
| Id | Requirement |
|---|---|
| R4.30 | Size 72–96 px. |
| R4.31 | "Three armor plates around the hull" (front, left, right in the sketch), "each … damaged independently by rockets or high-impact weapons". |
| R4.32 | "After all plates break: main hull becomes vulnerable, top speed increases, contact damage increases slightly, ship becomes more evasive." |
| R4.33 | Charge: "rotates onto a predicted intercept course; engines charge for 0.5–0.8 s; armor glows; boosts through the player's projected position; overshoots; performs a wide turn. It should not instantly die if it misses." |
| R4.34 | Rocket choice: "use a rocket to strip an armor plate / use primary fire to damage the exposed hull / continue dodging the charge". |
| R4.35 | Assault: "the charge becomes a diagonal corridor attack instead of an unconditional vertical dive." §20: "predicts player's horizontal/diagonal movement inside the corridor". |
| R4.36 | §13.1 Armor: "bullets bounce/deflect; rockets damage armor plates; heavy weapons stagger armor; contact damage does not bypass armor unless explicitly designed". The epic adds: "a deflection rule on a full-size hurtbox … not the old layer-based bullet immunity". |
| R4.37 | §16 "Armor collision: deals high stagger/contact damage while partially protecting the enemy." |
| R4.38 | §1.1 verb: "How do I break its armor before it reaches me?" §27: "rammer predicts a shorter future position." |

### Cross-cutting
| Id | Requirement |
|---|---|
| R4.39 | §12 `persist_after_owner_death`: "useful for missiles, mines, and delayed beams". The epic: "mines and bombs outlive their owner without breaking the one-owner rule". |
| R4.40 | §40 and the epic: tests in **both harnesses** for each of these: mine/bomb placement against the predicted path; a new firing position every cycle; stationarity during the telegraph; post-shot disengage; the LOS refusal; plate-by-plate vulnerability; charge direction. |
| R4.41 | §23 visual states: "Sniper — weapon unfolds during charge"; "Ram Corvette — armor plates glow during charge and physically disappear when destroyed." §21: silhouette, faction accents, gameplay lights; cool edge highlight; do not recolour the hull by state. §22: specialists 80–128 px source. |
| R4.42 | Level-1 spawns of the old Bomber, Sniper and Ram Ship are migrated (scope text). |
| R4.43 | The three new enemies join the hub's ambient spawn (`SectorHub`; scope text). |
| R4.44 | §41 "Phase 3 — specialists" items 1–3. Those items are this phase's three enemies; items 4–5 (Missile Corvette, Support Ship) are Ph5. |
| R4.45 | §29, the sniper example: "a hard sniper … may relocate sooner and choose more varied firing angles". Only the decoy flag (R4.18) is in scope; tiers are Ph16. |
| R4.46 | §43 checklist questions ("what does it do when the player approaches from behind / boosts away", "can it fight off-screen"). The audit itself is Ph17. The behaviour should answer them anyway, and the plan should say how. |
| R4.47 | Ph1 roadmap "also owns": the Bonus Drone is **kept unchanged** as an Assault reward (§38). This phase must not touch it. |

---

## Modules and files involved

| Path | What it does today | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/bomber/bomber.gd` (51 lines), `bomber.tscn`, `bomber_config.gd/.tres` | Legacy `Bomber extends BaseEnemy`. Its own `_physics_process` sweeps horizontally (`velocity = (direction*speed, 0)`) with a camera off-screen cull. A child `Timer` drops a `bomb.tscn` every `bomb_interval` 1.2 s into `get_parent()`. HP 150 (scene 250 is overwritten), contact 35, score 80. Body/HurtBox/ContactHitBox share one circle r 22. Sprite2D rotated π. | Replaced by a brain-driven enemy. Every live spawn attaches `.move(b.straight(80–82))`, so the horizontal self-drive **never runs** in the game: a vertical rail suspends it. The bomb timer keeps firing on the rail. `shoot_at_player()` on both spawns is inert (no `aim_mode` reader). |
| `assault/scenes/enemies/bomber/bomb.gd` (97), `bomb.tscn` | `Bomb extends Area2D`: FALLING (120 px/s down, 5 s fuse), TRIGGERED (player hurtbox in an 80 px `ProximityDetector` → 1 s countdown, colour lerp), EXPLODED (HitBox r 28, damage 40, live for 0.15 s via `create_timer`, then `queue_free`). It culls below the camera. A `ColorRect` visual; **no HurtBox, so it cannot be shot**. Unpooled; added to the bomber's parent, so it already outlives the bomber. | Phase 1 deferred "`bomb.gd` lifetime" to Ph4. It breaks three conventions: a `create_timer` inside a projectile (the Ph2 `ContactBlast` rule is "own counter, never `create_timer`"); a camera-relative cull; and "down" as the only direction. |
| `assault/scenes/enemies/sniper_enemy/sniper_enemy.gd` (127), `.tscn` | `SniperEnemy extends BaseEnemy`. Logic runs in `_process`, so it survives `EnemyPathMover`'s `set_physics_process(false)` and overrides the rail's rotation every frame. `enum Phase {APPROACH, AIM, LOCK, FIRE, IDLE}`. `FLY_IN_TIME` 2.5, `AIM_DURATION` 2.0 (lerp-tracks at 4.0/s), `LOCK_DURATION` 0.5 (frozen), then fires `enemy_sniper_bullet.tscn` **unpooled** (`expired → queue_free`) along `Vector2.UP.rotated(rotation)`. `shot_count` 5, then IDLE (the rail carries it out). HP 60 from the scene; **no config**; contact 20 (default); `score_value = 50` hard-coded. Sprite2D `sniper.png` 64×64, nose up. Muzzle at (0, −20). | Replaced by a brain-driven enemy. **Two owners of rotation** (the rail and `_process`) is exactly what the single-writer gate forbids for mover-driven enemies. No config means the contact-damage roster entry is `config: ""` and the isolation test skips it. |
| `assault/scenes/projectiles/enemy_bullets/enemy_sniper_bullet.tscn` | `EnemyBullet` script, speed 1400, HitBox 256/128, damage 25, LASER (default), capsule r 2 × h 18. `ProjectileLifetime` 18 s / 2400 px. Two `Line2D`s (Glow, Beam). It carries its **own `WorldEnvironment`** (glow 1.8), as the player's `bullet.tscn` does. Scene uid `uid://cenemysnipblt` does not look editor-minted (inferred). | Becomes the rail shot, or is replaced by a new rail round. `test_enemy_bullet_lifetime.gd:112-115,140,286` reads its speed and lifetime and drives `SniperEnemy._phase_fire()` by name. **That test has to move with the rename.** |
| `assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd` | `SniperAimVisualizer extends Node2D`. `update_charge(t)` → `queue_redraw()`. Single-line mode draws a fixed 600 px `Vector2.UP` line from the muzzle: dim red at width 1 while tracking, orange-red at width 2 when locked. Cone mode is used by the player. Shared with the player's `sniper_behavior.gd`. | 600 px is shorter than any plausible Open Space firing range, so the telegraph would not reach an off-screen player (C9). It is shared code: changing it touches the player's weapon. |
| `assault/scenes/enemies/ram_ship/ram_ship.gd` (66), `.tscn`, `ram_config.gd/.tres` | `RamShip`: `_physics_process` dives straight down at `speed` 100, with a camera cull. Its scene-authored `DefenseProfile` gives HurtBox mask **33** (rockets + environment). The first received hit of any kind is swallowed and `_enter_damaged_state()` runs: damaged sprite, `apply_alternate()` → mask **97**, HP reset to 100/100. `is_laser_blocking()` returns `not _damaged`. Joins group **`ram_ships` only, not `enemies`**. HP 999, contact 50, score 35. AnimatedSprite2D 32×32 (flipped by BaseEnemy), circle r 36. | Replaced by the Ram Corvette. The armour is the **layer-exclusion** design the epic retires. Not being in `enemies` means homing missiles (`warhead_missile_shooting_state.gd:61`), dash, EMP, plasma nova, shield overload, AI targeting and the beam's target list **never select it** (C4). |
| `assault/scenes/enemies/base_enemy.gd` (191) | `_ready` resolves `DefenseProfile` and `ContactProfile` (scene-authored or default), the brain and the mover. `_physics_process` runs `brain.tick` then `mover.step`. `suspend_ai()` arms the contact profile, calls `on_suspended()` and `halt()`. Virtual hooks `_on_received_damage(damage)` and `_on_health_changed(current)`. `_rotate_sprite()` flips a child named `AnimatedSprite2D`. | The base for all three. The armour rule overrides `_on_received_damage`, as `SpaceStation` does. |
| `global/components/defense_profile.gd` (64) | Flags → HurtBox mask, plus `accepted_damage_types`. `apply_alternate()` is a **one-way** switch, explicitly "general multi-state armour is a later phase" (Ph4). | Ph4 owns multi-state armour (DECISIONS Ph1 "Deliberately deferred: Ram armour as deflection vs mask"). |
| `global/components/contact_profile.gd` (124) | `enum Mode {NONE, COLLISION, RAMMING, EXPLOSIVE}`; `set_armed()`; `contact_made`; `detonate()`. EXPLOSIVE spawns a `ContactBlast`. | DECISIONS Ph2: "Armour collision is Ph4's new mode on the same enum." Ordnance can reuse EXPLOSIVE + `ContactBlast` (Ph2: "Ph4–Ph7 explosive ordnance … should reuse it rather than `bomb.gd`'s timer-based blast"). |
| `global/components/contact_blast.gd` (75) | `ContactBlast.spawn(container, at, radius, damage, frames)`. Deferred self-attach; live for ≥ 2 frames on its own counter; layer 256, mask 0, CONTACT; never hits enemies. | The detonation for every bomb and mine. |
| `global/components/projectile_lifetime.gd` (105) | `max_time`, `max_distance` (from the origin), `use_world_rect`. Arms lazily. Emits the host's `expired` once and never frees. `expire_now()`. **`persist_after_owner_death` is documented only** ("becomes a `BulletPool` policy in Ph5"). | Ph4 scope pulls `persist_after_owner_death` forward (S2 in `2-research.md`). |
| `global/components/bullet_pool.gd` (116) | Pre-allocates; `acquire()` reparents into `get_parent().get_parent()`. Recycles on `expired` through a **per-bullet lambda** connected in `_prewarm()`. `_exit_tree()` → `cancel_active()` frees every in-flight bullet. `_recycle` while the pool is queued for deletion frees the bullet. | Pooled ordnance dies with its bomber unless the pool learns `persist_after_owner_death` (S2). The lambda is not stored, so "disconnect the pool's recycle" needs a stored `Callable` (C3). |
| `global/components/attack_controller.gd`, `global/enemy_ai/burst_clock.gd` | Brain-driven `tick()`/`fire_now()`; `BurstClock` sequences N shots at a gap. | The mine cluster is a 3–5-drop burst along an arc (BurstClock). The sniper's single shot is `fire_now()`. |
| `global/enemy_ai/target_info.gd` (118) | Snapshot: `position`, `velocity`, `facing` (`Vector2.UP.rotated(rotation)`); `predicted_position(t)`; `intercept()` returns `{ok, point, time}`; `aim_direction(from, speed, accuracy)`. **`line_of_sight(_from)` is a stub that returns `has_target`.** | R4.23 makes it real. A snapshot holds no world, so a real ray needs a `PhysicsDirectSpaceState2D` (or the actor) passed in (C7). |
| `global/enemy_ai/steering.gd` (179), `enemy_mover.gd` (247) | Pure primitives (seek, arrive, orbit, intercept, evade, retreat_from, strafe, hold_position, drift, spiral, corkscrew, formation_slot, separation, alignment, cohesion, clamped_lead_time, turn_toward). Mover: `request_velocity`, `add_nudge`, `face_toward`, `boost(dir, speed, duration)`, `halt()`, `release_constraint()`. | `break_contact` is the one primitive left for Ph4 (R4.22). Ph2 rule: a curved path is a brain-side `turn_toward` request, never the mover's turn cap, so the Ram's wide turn and the Bomber's escape arc use it. |
| `global/enemy_ai/dubins_path.gd` (174) | Shortest turn-radius-limited path between two poses (Ph3 t8b). | DECISIONS Ph3: "Ph4's attack-run enemies (Bomber, Ram) can plan with it." Candidates: the Bomber's angled approach onto its bombing line, and the Ram's lead-in. |
| `global/enemy_ai/engagement_budget.gd`, `anchor_idle.gd`, `squad_controller.gd` | Assault lifetime (`update`, `remaining`); hub idle handover; squad board. | Every migrated Assault spawn needs a budget and DISENGAGE (Ph2/Ph3 rule). Hub idle uses `AnchorIdle` (Ph3 "minimal hub idle" precedent). Squads are probably unneeded: none of the three spawns in formations in level 1. |
| `global/enemy_ai/enemy_world.gd`, `assault/scenes/systems/assault_corridor_constraint.gd` | Mode lookup. The corridor filter is per axis. `inner_rect()` is the corridor's "visible" rect = the **whole camera pan range**: 1480 × 1480, x −100…1380, y −380…1100, not the 1280 × 720 view. Soft band 120 px, hard band 450 px, edge pressure 200 px/s. | (1) "Clamp bomb placement to the corridor" (R4.6) clamps to `inner_rect()`. (2) The sniper's "off-screen band" (R4.19) exists **inside** the corridor rect: the camera shows 720 of the rect's 1480 px height, so a sniper can be off camera with no constraint pressure (S7). (3) A sniper holding still *outside* the rect is pushed in at up to 200 px/s, so it cannot be stationary there. |
| `global/components/state_light.gd` | OFF / ARMED / CHARGING / COMMIT (white = a real committed attack only); `blink_once()`. Code-built texture. | The Ram's charge (CHARGING → COMMIT), the sniper's lock (CHARGING → COMMIT at the shot?) and the bomber's drop window. The plate "glow" (R4.41) is a separate per-plate visual, not the one light. |
| `assault/scenes/projectiles/bullets/bullet.gd` | `_hit_is_deflected(area)`: the target's **parent** has `is_armored()` and it is true → the bullet keeps flying, no `expired`, no pierce spent. The unlimited-pierce (player sniper shot) branch runs first: parents in group **`asteroids` or `ram_ships`** zero the HitBox damage and stop the bullet. | The armour convention the epic names (CLAUDE.md). The `ram_ships` group rule is a second, older armour hook. |
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd:55-58`, `warhead/warhead_missile.gd:31-35` | Rockets copy the same `is_armored()` check: **a rocket passes through an armoured target too**. | A plate cannot simply say `is_armored() == true`: that also lets rockets through, and rockets are what must break plates (C1). |
| `global/components/hurtbox_component.gd`, `hitbox_component.gd` | `received_damage(damage: int)` carries **only the int**. A static `accepted_damage_types` filter applies on `area_entered`. Direct emitters (`beam_behavior:151`, `plasma_nova_module:41`, `shield_overload_module:62`, `engine_boost_module:146`, `dash_state:71`, `laser_ray:254/264`) call `received_damage.emit()` themselves and bypass the filter. | A plate tells a rocket from a bullet only by its own HurtBox filter (`[ROCKET]`), by reading the `HitBox` in its own `area_entered`, or by layer (32 vs 64). Direct emitters reach whatever HurtBox they pick, normally the root's `HurtBox` (C2). |
| `assault/scenes/player/weapons/behaviors/beam_behavior.gd:50-75` | The mining-laser beam rays forward (bodies only, mask `1\|1024`, 1200 px). Any body hit blocks it unless the collider's `is_laser_blocking()` returns false. Targets are groups `enemies` + `asteroids` near the segment. | **The only `intersect_ray` in the project**: the precedent for LOS (C7). Enemy bodies sit on layer 1 (no layer authored) and block the beam today. |
| `assault/scenes/systems/wave_builder.gd` | `ram()` → `RAM`; `sniper()` → `SNIPER`; **`sniper_enemy()` → `SNIPER_ENEMY := SNIPER`, an alias**, so the 24 `b.sniper()` lines are sniper-enemy spawns (the skimmer scene no longer exists); `bomber()` → `BOMBER`. `shoot_at_player()` only sets the `aim_mode` prop. | Migration surface. The AUDIT's "2 sniper spawns" missed the 24 aliased ones. |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | Five sections (table below). | R4.42. |
| `assault/scenes/systems/level_director/level_director.gd:159-189` | `_wait_enemies_cleared` polls `enemy_container.get_child_count() > 0`. On timeout it frees everything left (each freed child counts as an *escape* for `ScoreTracker`). | **Any ordnance in the container holds an ENEMIES_CLEARED section open** (C5). |
| `assault/scenes/enemies/space_station/space_station.gd:94,155,170-176`, `station_reinforcements.gd:187-191` | `is_armored()` is true while turrets live; `_on_received_damage` deflects (emits `armor_deflected`, flashes, returns). The hurtbox stays live because direct emitters bypass physics. Reinforcements **reject the ram-ship class** (mask 33 excludes 64). | The deflect pattern to copy. If the Corvette's hull ever accepts bullets, the reinforcement guard's reason changes. |
| `open_space/scenes/levels/sector_hub.gd` (`_spawn_patrol`, exports 26-37) | One seeded rng; Swarm (ring 1300 @90°), Razor (1300 @270°), fighter pair (1500 @180°), Gatling pair (1500 @0°). Sets `brain.rng_seed`, `brain.patrol_anchor` and a shared `squad` before `add_child`. Never sets `start_engaged`. **No physics bodies in the hub**: only Area2D triggers, pickups, `InfoLogInteractable`s and the player (inferred from the scene). | R4.43. The diagonals are free (below). The hub has **nothing that blocks line of sight**, so LOS in Open Space is exercised only by fixtures and Ph6 wrecks (S9). |
| `tests/integration/test_sector_hub_patrol.gd` | Sweeps every `MissionTrigger`/`PickupBase` child plus the player spawn. Asserts `distance − worst_idle_offset > perceive_radius` per group, anchors > 1000 px apart, ≥ 15 points. | Each new group needs a clearance row; seeds are drawn in spawn order (append, do not reorder). |
| Art: `assault/assets/sprites/enemies/` | `bomber.png` 92×42; `sniper.png` 64×64; `ram_ship.png` and `ram_ship_damaged.png` 32×32 (ram is the most opaque sprite in the sweep at 67.19%). Phase 2/3 art: swarm 32, razor 48, fighter 64, interceptor 64. | R4.41: three new sprites, plus variants for the visual states (S12). |

### Level-1 spawns of these three (`level_1_director.gd`)

Every spawn uses `.move()`. None uses `.prop()` or a formation. Speeds are design units/s ×2 (`WORLD_SCALE`).
- Angle convention: `straight` angle 0 = down, π = up, +π/2 = moving right.
- Sniper "seq" = `sequence([straight(150,0,2.5), hold(13.0), straight(220,π)])`, the only `FLY_IN_TIME`-matched spawns.
- Every other sniper flies a straight line and **aims while drifting**.

| Section | End | Snipers (seq + straight) | Rams | Bombers |
|---|---|---|---|---|
| deep_space (:254) | DURATION 30 s | 2 + 5 (0.5 s seq pair; 11.0, 19.5 `free_after 5.0`, 29.0) | 4 (7.5 down, 15.5 **up from below**, 26.0 pair) | 0 |
| asteroid_belt (:488) | DURATION 30 s | 0 (41 asteroids, no enemies) | 0 | 0 |
| planet_approach (:571) | DURATION 110 s | 10 (16, 32, 44 pair, 65 pair, 75 pair `fa 5.5`, 92 **side crossing**) | 12 (13, 28 ×3, 55 pair from below, 65, 88 ×3, 102 pair) | 2 (58, 98; straight(80–82) down) |
| cloud_descent (:809) | **ENEMIES_CLEARED, 10.0 s** (default) | 9 (11 from below; 32: side pair `fa 4.0` + top pair; 53 side pair `fa 5.0`; 62 pair d1.2) | 6 (28 pair from below, 38, 50 pair d1.5, **72 d1.2**) | 0 |
| station_assault (:237) | ENEMIES_CLEARED 180 s | 0 | 0 | 0 |

Totals: **26 snipers** (2 seq + 24 straight), **22 rams** (speed 260–350, i.e. 520–700 px/s), **2 bombers**.
- cloud_descent's last wave triggers at **76.0 s**.
- Inferred: the sniper fires its first shot 5.0 s after spawn (2.5 + 2.0 + 0.5). So the `free_after(4.0)` pair at cloud_descent 32 s **never fires**, and the `free_after(5.0)` spawns race their first shot. Several legacy snipers are inert today.

---

## Existing code to reuse

| Path | What it gives this phase |
|---|---|
| `global/enemy_ai/enemy_brain.gd`, `enemy_mover.gd`, `steering.gd`, `target_info.gd`, `enemy_world.gd` | The whole AI stack. A new enemy is a `BaseEnemy` root, a `Brain` child (an `EnemyBrain` subclass beside the enemy), an `EnemyMover` (AUTO) and a `StateLight`. Ticked from `BaseEnemy._physics_process`. |
| `fighter/fighter.gd` `_apply_config` (`:53-82`), `fighter_brain.gd` `_start` (`:399-409`), `on_suspended` (`:333-356`), `_enter_disengage` (`:1407`), `_set_light` (`:1494`) | The reusable skeleton: the root copies config onto mover/brain **after** the brain's `_ready()`, so the budget is built on the first tick; `patrol_anchor = Vector2.INF` sentinel; `start_engaged` test seam; `EngagementBudget` → DISENGAGE (release constraint, exit speed, nearest rect edge + 64); rail fallback installs a self-timed pattern from `rail_*` config fields. |
| `global/enemy_ai/dubins_path.gd` | Turn-limited lead-ins arriving on a heading: the Bomber's angled approach onto its line; the Ram's turn-in after an overshoot. |
| `global/enemy_ai/burst_clock.gd` | The mine cluster's 3–5 drops at a fixed gap along the arc. |
| `global/components/contact_profile.gd` + `contact_blast.gd` | RAMMING (armed only in the committed charge, Ph2 rule) for the Ram. EXPLOSIVE + `ContactBlast` for every bomb and mine detonation, "never a child of the thing that dies". |
| `global/components/projectile_lifetime.gd` | `max_time` / `max_distance` / world rect / `expire_now()` for all ordnance and the rail shot. |
| `global/components/defense_profile.gd` | The hurtbox mask and types. Extended for multi-state armour, or kept as-is with plates as separate hurtboxes (approach A3). |
| `space_station.gd` `is_armored()` / `_on_received_damage` deflect, and its turret pattern (`station_turret.gd`: independent child hurtboxes with their own Health) | **The existing "independently destructible part over an armoured core" pattern.** Plates are three small turrets with no gun. The hurtbox-geometry gate already accepts this shape (the core covers the body; parts are extra hurtboxes). |
| `bullet.gd::_hit_is_deflected`, `homing_missile.gd` / `warhead_missile.gd` copies | The deflection hook. Ph4 extends it to be hit-aware (C1). |
| `beam_behavior.gd:50-75` | The `intersect_ray` + duck-typed collider opt-out pattern for LOS. |
| `enemy_rounds.gd` (`EnemyRounds`, `pool_size_for`), `rounds/heavy_shell.tscn` | Pool sizing; the Heavy Shell (160 px/s, 20 dmg, 12 s / 1800 px), which has **no consumer** (Ph3: "first consumer Ph4 (Bomber/Ram) or Ph10"). |
| `assault/scenes/player/weapons/visualizers/sniper_aim_visualizer.gd` | Charge-line drawing; extend (length, optional decoy) or fork for the enemy. |
| `global/components/rocket_trail.gd` | Particle trail (`local_coords = false`): a model for a pursuit-bomb exhaust. **No residual-line effect exists anywhere**; the rail shot's trail is new. |
| `tests/helpers/enemy_ai_harness.gd`, `test_enemy_dual_mode.gd` (`_tick`), `fixture_enemy.tscn`, `player_stub.gd`, `level1_drone_concurrency.gd` (`worst_exit_after_speed`, `peak_window_rate`, …) | Dual-mode specs and density/deadline arithmetic. Use the label-parameter shape: `use_parameters(["open_space","assault"])`, never harness objects (Ph1 leak trap). |
| `tests/integration/test_engagement_deadline.gd`, `test_level1_fighter_exit.gd`, `test_level1_fighter_spawns.gd` (frozen-constant pattern), `test_level1_fighter_fire_density.gd` (measured gate) | The gate shapes this phase's migration must extend. Each filters by scene path, so **none covers a sniper, ram or bomber row today**. |

---

## Conventions that constrain this

- **Single writer of motion** (`test_enemy_mover_single_writer.gd`): brains, `global/enemy_ai/*` and the root script of
  any mover-driven scene, plus its ancestors, never write `velocity`/`rotation`/`velocity.x`, never call
  `move_and_slide`/`look_at`/`rotate`. The empty allowlist is permanent.
  - The sniper's `_process` rotation override and every legacy `_physics_process` must go.
  - Ordnance that moves (bombs, pursuit bombs) are `Area2D`s, not mover-driven `CharacterBody2D`s. The gate sweeps
    `*_brain.gd` and mover-driven roots. A bomb script moving its own `position` is legal under it, as `bomb.gd` and
    `EnemyBullet` already do. A pursuit bomb as a mover-driven body would fall under the gate (C6).
- **Brain clock:** physics tick, accumulated `delta`, randomness from `brain.rng` only, no `Timer` nodes.
  - Ordnance should follow the same rule.
  - `bomb.gd`'s `create_timer(0.15)` and the bomber's child `Timer` are both legacy and go.
- **Config:** flat `@export_group` fields on a `ShipConfig` subclass. No nested resources, arrays or dictionaries.
  - Exactly **one `*config*.tres` per entity directory** (`test_config_instance_isolation.gd:84-86`). Ordnance
    tuning therefore lives on the **bomber's** config, or in the ordnance scenes' exports, never as a second
    `*config*.tres` in `bomber/`.
  - The `.tres` value wins over the scene's Health node. `collision_damage` is re-applied in `_ready()` (the
    contact-damage gate).
- **The sniper needs a config** (new `SniperConfig`), which moves it from `config: ""` to a real `.tres` in the contact
  gate. `_MIN_ENTITIES_WITH_CONFIG` (10) still holds.
- **Facing:** `rotation = heading.angle() − sprite_forward_angle`.
  - Forward fire reads `EnemyMover.sprite_forward_angle_of(node)`.
  - New art should be drawn **nose-down** (`PI/2`, the default) or set the export.
  - A child named `AnimatedSprite2D` is flipped 180° by `BaseEnemy` (`test_base_enemy.gd:304` pins it for `fighter` and
    `ram_ship`). **Keep the sprite node type and name**, or update all three places (Ph3 art convention).
- **Armour is a damage rule on a full-size hurtbox** (`test_enemy_hurtbox_geometry.gd`: the root `HurtBox` covers the
  body within 1 px per edge; it carries a boundary case against shrinking the station core).
  - Deflect = flash and report 0, and the bullet keeps flying (CLAUDE.md, `bullet.gd`).
  - Never an absent or shrunken hurtbox, and never a silently consumed shot.
- **Contact:** `ContactHitBox` shares the body's shape sub-resource and scale (geometry gate). Its damage is
  `config.collision_damage` (damage gate) and its type is CONTACT (`test_contact_hitbox_geometry.gd:213-216`).
  - A scene-authored `ContactProfile` must be added to `test_base_enemy.gd::_AUTHORED_CONTACT_MODES` (`:339`).
- **Rammers are armed only in their committed state**, and the `StateLight` shows it. **COMMIT (white) is exclusive to a
  real attack**; a feint or decoy may show only CHARGING (Ph2). Neither Ph3 shooter uses COMMIT.
- **Rails:** a brain suspended on a rail installs a fallback weapon built from `rail_*` config fields (Ph3 X1, inherited
  by Ph15). Phase 4 removes these enemies from level-1 rails. The fallback is still owed if any rail spawn of them
  remains (none outside level 1; the station rejects the ram).
- **Assault lifetime:** each AI spawn has an `EngagementBudget`. ENEMIES_CLEARED sections are gated by
  `test_engagement_deadline.gd`, per entry:
  `(entry − last_trigger) + engage + deferral + worst_exit + 0.5 < timeout`, with the **curved-exit bound** for any enemy
  that turns its velocity (Ph3 deviation 18).
- **Dual-mode specs** run every behaviour row in `open_space` and `assault` harnesses, with assertions relative to the
  constraint.
- **Collision layers:** names only, no numeric change without a reason. Bit 4 (value 8) is unnamed and unallocated. Bit 12
  (2048, `area_control`) is reserved for Ph6.
- **Every projectile has exactly one owner** (CLAUDE.md): a pool recycles it, or it frees itself. A transfer of
  ownership must be explicit (S2).
- **Art:** PixelLab only, through the `pixel-art-generation` skill. Strict top-down (`view: "high top-down"`,
  `isometric: false`). Saved by `scripts/pixellab.sh`. Opened and looked at. ≤ 90% opaque
  (`test_entity_sprite_transparency.gd`; fix with `scripts/strip-sprite-bg.sh`).
- **Signals** declare exactly what they emit (`test_signal_emit_arity.gd`). Per-frame prints go behind
  `OS.is_stdout_verbose()`.
- **UIDs:** never hand-type or copy one. Leave references UID-less or mint one with the README snippet.

---

## Dependencies and blast radius

- **Renames.** Phase 2 and 3 did `git mv` + class rename (`drone_interceptor` → `razor_drone`,
  `light_assault_ship` → `fighter`).
  - Candidates: `ram_ship/` → `ram_corvette/` (`RamShip` → `RamCorvette`), `sniper_enemy/` → `sniper/`
    (`SniperEnemy` → `Sniper`). The Bomber keeps its name.
  - Every roster test lists the directory name. These **must be edited in the same task as the rename**:
    contact damage, contact geometry, hurtbox geometry, `test_base_enemy.gd`, `test_enemy_bullet_lifetime.gd`,
    `test_ram_ship.gd`, `test_defense_profile.gd:92,133-146`, `test_player_bullet_lifetime.gd:369-386`,
    `test_station_reinforcements.gd:410-433` (by mask).
  - `WaveBuilder` constants, `docs/enemy-roster.md`, `docs/architecture/modules/assault.md`, each `ENEMY.md` and
    CLAUDE.md also change.
- **Ram armour redesign touches player-weapon code.** `bullet.gd`, `homing_missile.gd`, `warhead_missile.gd` (the deflect
  query), the unlimited-pierce `ram_ships` group rule, and `beam_behavior.gd` (`is_laser_blocking`).
  - These are player weapons used in all modes. The station boss's behaviour must stay byte-identical, which
    `test_space_station.gd`, `test_station_incoming_damage_paths.gd` and `test_player_bullet_lifetime.gd` guard.
- **Joining the `enemies` group** (the Ram) changes homing targeting, dash, EMP, plasma nova, shield overload, AI
  targeting and the beam's target list. That is mostly desired, but it is a gameplay change (C4).
- **`persist_after_owner_death`** touches `BulletPool` and `ProjectileLifetime`, both used by every shooter and by the
  station. Default-off keeps them unchanged.
- **`TargetInfo.line_of_sight`** signature change. No production caller today; its only callers are the two stub
  assertions in `tests/unit/test_target_info.gd:130-132`, which change in the same task (`2-research.md` S3).
- **ENEMIES_CLEARED** (cloud_descent): 9 snipers + 6 rams move onto budgets. The section already runs at **0.53 s**
  analytic / **0.93 s** measured margin for fighters and drones (Ph3 t17).
- **Level-1 density gates** (`test_level1_fighter_spawns.gd`, `test_level1_drone_spawns.gd`, the measured shots/s gate)
  count only their own families, and are unaffected unless the plan widens them.
  - The real cloud_descent replay (`test_level1_fighter_exit.gd`) **includes the 72 s ram**, so it is affected.
- **The hub:** three new groups change the seeded rng draw order only if inserted before existing draws (append
  instead).
- **`SniperAimVisualizer`** is shared with the player's sniper weapon. A change there is a player-visible change unless
  it is additive (C9).

---

## Risks, edge cases, testing requirements

| Id | Risk / edge case | Note |
|---|---|---|
| C1 | **`is_armored()` is not hit-aware, and rockets honour it too.** A plate that says "armoured" lets rockets fly through, and rockets are the plate-breaker. A plate that does not say it, but filters bullets out, **silently consumes** the bullet with 0 damage (the bullet expires on overlap; the hurtbox filter drops it): the forbidden "swallows shots and reports nothing". | The query must be able to say "deflect a bullet, accept a rocket". See approach A3 in `2-research.md`. |
| C2 | **Direct emitters bypass hurtbox filters** (beam, modules, dash, laser ray). They hit the root `HurtBox`, normally the hull. | The hull's armour rule must live in `_on_received_damage` (the station pattern), not only in a mask or type filter, or the beam strips nothing but damages an "armoured" hull. |
| C3 | **Pool ownership transfer.** `BulletPool` connects an anonymous lambda per bullet and frees in-flight bullets on `_exit_tree`. Persisting a bullet means disconnecting that lambda (store the `Callable`), connecting `expired → queue_free`, and removing it from `_active`. `_recycle` must not run afterwards. | Edge cases: a bullet that expires in the same frame its owner dies (deferred `_recycle` already queued), and a persisted bullet whose container is freed (section end). |
| C4 | The old Ram is **not in `enemies`**. The new Corvette is, so homing rockets lock it, EMP and nova hit it, and the dash damages it. Homing rockets aim at the **root's centre**, so which plate a homing rocket meets depends on approach geometry. | A plate test should fire real rockets from front and side. |
| C5 | **Ordnance holds ENEMIES_CLEARED open** (`get_child_count() > 0`). A mine with a 10 s life laid at the end of a section blocks the director for its whole life. Today's bomb has a 5 s fuse, and bombers are only in DURATION sections. | Either bombers stay out of ENEMIES_CLEARED sections (a deadline boundary row, the Razor/Gatling precedent), or ordnance `max_time` enters the deadline formula. |
| C6 | **A pursuit bomb that steers.** As an `Area2D` moving itself it is outside the single-writer gate, like `EnemyBullet`. As a `CharacterBody2D` with a mover it is inside it. | Keep ordnance as `Area2D` projectiles with a pure steering helper; do not make them `BaseEnemy`s. |
| C7 | **LOS raycast specifics.** `TargetInfo` holds no world. `intersect_ray` hits **enemy bodies** too: every `BaseEnemy` body is on layer 1 with no authored layer, as are asteroids. Direct space queries are only reliable in the physics step, and a blocker added in a test is not in the broadphase until a physics frame has run. | Use an opt-in `blocks_line_of_sight()` (or group) with the excluded-and-recast loop of `beam_behavior`. Tests `await` physics frames after placing a blocker. |
| C8 | **A sniper's off-screen telegraph.** An Open Space firing range beyond the half-view (≈ 640 px, wider when speed-zoomed to 0.85) puts the sniper off camera. The player then sees only the line. In Assault a firing point in the corridor's upper band is off camera too. | The line must be long enough to reach and pass the player. The rail shot travels 1400 px/s or faster: at 900 px it lands 0.64 s after the lock ends, so the lock **is** the dodge window. |
| C9 | **`SniperAimVisualizer` is shared with the player weapon.** Its 600 px length is too short at sniper range. | Add an exported length or a "to point" mode with the default unchanged, or give the enemy its own visual. |
| C10 | **Stationary means `velocity == 0`.** In Assault the corridor filter adds edge pressure outside `inner_rect()`, so a firing point outside the rect is not stationary. `EnemyMover` braking leaves residual speed for a few frames. | The firing point must be inside `inner_rect()` (shrunk by a margin). "Stationary" is asserted as `velocity.length() < ε` from LOCK start (or AIM start) to the shot. |
| C11 | **ENEMIES_CLEARED deadline for the Sniper.** A shot already telegraphed should not be cut off: deferral = AIM + LOCK ≈ 2.5 s. A relocate leg is long. | cloud_descent's snipers enter at 11–63.2 s, against a last trigger at 76 s. They have ≥ 12.8 s of slack, so the arithmetic fits (see `2-research.md` §4). The real replay from 66 s does not include them. |
| C12 | **ENEMIES_CLEARED deadline for the Ram.** The 72 s + 1.2 s ram enters 2.8 s before the last trigger, so `engage + deferral + curved_exit + 0.5 < 12.3 s`. A charge (wind-up 0.5–0.8 s + boost + overshoot) is the deferral. A wide turn means the curved-exit bound applies. | Tight but feasible. The plan must compute it, and the real replay (`test_level1_fighter_exit.gd`) must still empty in time with the ram on AI. |
| C13 | **Level-1 density and character change.** 22 rams at 520–700 px/s dive across in about 2 s today. As AI, each lives for its budget and makes a charge. Assault becomes more crowded and slower-paced. The rams are also bullet-immune today and only rockets break them: the shipped level relies on that "missile target" role. | Freeze legacy baselines first (Ph3 frozen-constant pattern), then gate counts. A Ram budget of about one charge is the natural lever. |
| C14 | **Legacy sniper spawns differ from the legacy design.** 24 of 26 aim while drifting on a straight line, some never fire, and none hovers. A "timing preserved" pin would freeze broken behaviour. | Pin trigger/offset/delay only (Ph3 pin shape), not fire timing. Decide whether `free_after` lines keep a shorter budget (the `free_after` value is the natural budget). |
| C15 | **Determinism for "new firing position every cycle".** Sampling candidates with `rng` plus scoring is deterministic per seed. "Different from the last" must be asserted as an angular separation relative to the player's frame, not as inequality of floats. | Boundary: a player hugging a corridor corner (few legal candidates) must still yield a different position, or a documented fallback. |
| C16 | **The art budget is fine, the art count is not small.** Three ships, plus sniper unfolded/folded states, plus three ram plates (intact/glowing/gone, or plates as separate sprites), plus bomb/mine/pursuit-bomb visuals. | Ordnance can be code-drawn (the Ph3 rounds precedent). Plates as separate child sprites make "physically disappear" free (hide the node). |

**Testing requirements (minimum, from R4.40 plus gates):**
- **Dual-mode specs per enemy:**
  - Bomber: drop points lie on the predicted path and are clamped to `inner_rect()` in Assault.
  - Sniper: the firing position changes every cycle; stationary through telegraph and lock; post-shot distance
    increases; no shot with a blocker on the line.
  - Ram: each plate's break changes acceptance; the hull is vulnerable only after all three; charge direction
    vs intercept point; it survives a miss.
- **Unit tests:** `Steering.break_contact`; the real `line_of_sight`; the pool's `persist_after_owner_death` transfer;
  the armour query; ordnance lifetimes.
- **Invariant gates** updated for renames and new scenes:
  - contact damage, contact geometry, hurtbox geometry (plates are extra hurtboxes; the root covers the body);
  - config isolation (new `SniperConfig`), sprite transparency, base-enemy flips and contact modes;
  - single writer, signal arity, round lifetime sweep (new rounds and ordnance; stationary mines are time-bound only);
  - UID integrity and project load integrity.
- **Level 1:** a pin of all 50 rows (trigger, offset, delay, no `.move()`); deadline rows for cloud_descent's 15 entries
  plus a bomber boundary row; a real replay; density gates against frozen legacy constants.
- **Hub:** clearance rows for three new groups; frame-0 IDLE; ordnance landing in `EnemyContainer`.

---

## Open questions for the plan

1. **Names.** Keep `Bomber`. Rename `RamShip` → `RamCorvette` (`ram_corvette/`) and `SniperEnemy` → `Sniper` (`sniper/`)?
   Recommended: yes, via `git mv`, with `WaveBuilder.ram()`/`sniper()` kept and `sniper_enemy()` kept as an alias.
2. **The armour query** (C1, C2). Which hit-aware form: a duck-typed `deflects_hit(hit_box: HitBox) -> bool` beside
   `is_armored()`, per-plate type filters, or a layer split? Its effect on the station must be nil.
3. **Pooled or unpooled ordnance**, and so how `persist_after_owner_death` is built (a pool policy, or simply "ordnance
   is self-owned"). The scope asks for the flag.
4. **Bombers in ENEMIES_CLEARED sections:** barred by a boundary row, or ordnance life in the formula? (C5)
5. **What "high-impact weapons" break plates.** ROCKET only, or also the player's sniper shot (40 dmg, unlimited pierce,
   today stopped by `ram_ships` for 0)? The spread? The beam?
6. **Assault Ram budget.** One charge then exit, or two? This sets density (C13) and the deadline (C12).
7. **Sniper firing range** per mode, and whether an Assault firing point may be off camera but inside `inner_rect()`.
8. **The decoy telegraph flag.** Where it lives (a `SniperConfig` bool `decoy_telegraph`, default false) and its shape
   (a CHARGING-only line that cancels, never COMMIT).
9. **The rail shot.** Reuse `enemy_sniper_bullet.tscn` (speed 1400, which already "very high") plus a trail node, or a new
   `rail_round.tscn` under `rounds/`? Is it pooled (1 shot per 5+ s, so unpooled is fine, like today)?
10. **Hub placement:** ring and bearing per group (the diagonals are free) and perceive radii, especially the sniper's
    long one.
