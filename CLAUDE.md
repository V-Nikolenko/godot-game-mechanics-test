# CLAUDE.md

A space action game in **Godot 4.6 (Forward+)**. The player cycles between three gameplay
modes — **Assault** (autoscroller shmup), **Open Space** (free-flight hub + mission
select), and **Infiltration** (isometric ground combat) — connected by a boot/cutscene
shell. Mode-specific code is isolated per module; shared logic lives in `global/`.

**Full knowledge base:** [`docs/architecture/PROJECT.md`](docs/architecture/PROJECT.md)

## Modules

| Module | Path | Role | Doc |
|---|---|---|---|
| Assault Mission | `assault/` | Autoscroller shmup; hosts the race sub-mode | [assault.md](docs/architecture/modules/assault.md) |
| Open Space | `open_space/` | Persistent hub world + mission select | [open_space.md](docs/architecture/modules/open_space.md) |
| Infiltration | `infiltration/` | Isometric ground combat | [infiltration.md](docs/architecture/modules/infiltration.md) |
| Global (shared) | `global/` | Components, entities, ship modules, state machine, pickups, interactables, resources, UI, autoloads | [global.md](docs/architecture/modules/global.md) |
| Shell | `boot/`, `cutscenes/`, `dialog/` | Boot entry, cutscenes, dialog data | [shell.md](docs/architecture/modules/shell.md) |
| Tests | `tests/` (+ `addons/gut/`) | GUT suite over the autoloads and `global/` | [tests/README.md](tests/README.md) |

## Key conventions

- **Engine:** Godot 4.6, Forward+. Viewport 1280×720.
- **Bosses are built from `global/boss/` and `EnemyModule` parts** — the Space Fortress (`assault/scenes/enemies/space_fortress/`, [ENEMY.md](assault/scenes/enemies/space_fortress/ENEMY.md)) is the one boss: an armoured hull whose death is its core part's, a `BossPhaseDriver` ladder where every phase must change at least two of six aspects (gated by `phase_snapshot()`), and escorts launched only by `BossReinforcements` into a `<boss>Escorts` container announced on `EventBus.boss_escort_spawned` (never `enemy_spawned_orphan`). Never call a boss a "station": Open Space has "Fortuna Space Station". See [global.md](docs/architecture/modules/global.md) → *Boss phase ladder* / *Boss reinforcements*.
- **Composition over inheritance** — entities are built from `global/components/`
  (Health, Hurtbox/Hitbox, Shield, Overheat, DamageReaction, effects).
- **Config-driven enemies** — assault enemies load stats from a `*_config.tres` applied in
  `_ready()` (the `.tres` value wins over the scene's Health node where they differ). Each entity
  holds a **private copy**: `ShipConfig.privatise()` duplicates it from `BaseEnemy._init()` *and*
  `_enter_tree()` (and `AllyFighter`'s), because `ResourceLoader` caches by path and every entity of
  a type would otherwise share one object with each other and with every `preload()` in the suite.
  **The object `load()`/`preload()` returns is still shared — never write to it.** Gated by
  `tests/integration/test_config_instance_isolation.gd`.
- **The mouse is read in exactly one line project-wide** — `player_ship.gd::_handle_rotation`'s
  `get_global_mouse_position()`. Open-space steering lives in `ShipTurnController`
  (`open_space/scenes/entities/player/ship_turn_controller.gd`), a child of `player_ship.tscn` and
  **the only writer of that ship's `rotation`**; it takes the cursor as an injected `Vector2` and
  reads no `Input`, because `Input.warp_mouse()` cannot place a cursor in a headless GUT run and
  anything that reads the mouse itself is untestable by the gate. Gated by
  `tests/integration/test_player_ship_turn_wiring.gd` (the anti-inert test — every unit test for
  the turn model is green on a build where the controller was never added to the scene) and
  `tests/unit/test_ship_turn_controller.gd`. Details in
  [open_space.md](docs/architecture/modules/open_space.md) → §3.2.1.
- **State machines** — `global/statemachine/`; one `State` node per file in a `states/`
  folder for complex entities; simpler enemies use in-script `enum` phases.
- **Signal arity & logging** — a signal is declared with exactly what it emits
  (`amount_changed(current_health: int)`, not a bare `signal amount_changed`), and anything
  that can print per-frame or per-hit sits behind `if OS.is_stdout_verbose()`. Both are
  spelled out in `docs/architecture/PROJECT.md` → Conventions.
- **Design-unit coordinates** — waves/spawns authored in 640×360 space, scaled by
  `ArenaCamera.WORLD_SCALE` (2.0) at runtime; never pre-multiply.
- **Every projectile has exactly one owner** — either a `BulletPool` recycles it, or it frees
  itself when it leaves the world. Player bullets are unpooled: spawn them through
  `WeaponBehavior._launch()`, which calls `Bullet.free_when_offscreen()` and connects
  `Bullet.expired -> Bullet.queue_free`. **A default bullet stops on the first hit that actually
  deals damage — a *deflected* hit does not count.** `bullet.gd::_hit_is_deflected()` asks
  `ArmorQuery.deflects(area, hit_box)` (`global/components/armor_query.gd`), which duck-types the target's
  `deflects_hit(hit_box: HitBox) -> bool` first (hit-aware) and falls back to `is_armored() == true` (hit-blind; no shared
  interface) and, if either refuses, returns without emitting `expired` or spending a pierce charge. The homing and
  warhead rockets ask the same query. **A shielded enemy consumes the bullet:** an `EnemyShield` (`global/components/enemy_shield.gd`) that absorbs a hit (`HurtBox.set_absorber()` hook, `hit_absorbed` instead of `received_damage`) counts as the hit that stops a default bullet, unlike a deflection; it never absorbs while its host answers `is_armored()`. This is load-bearing: the
  Space Fortress's armoured hull spans the whole boss, so a shot aimed at a battery has to
  survive crossing it, and the hull's `is_armored()` query is what tells the bullet the crossing
  was a deflection, not a kill — consuming the shot there makes the parts, and the boss,
  unkillable. `PierceModule` raises the number of *damaging* hits a bullet survives (via
  `Bullet.MAX_PIERCE`) before it stops. Any future entity that needs to deflect a bullet without
  consuming it must expose `is_armored()` or `deflects_hit()`. **Breakable armour is parts, not a mask** (Phase 4):
  the Ram Corvette's three `ArmorPlate`s (`global/components/armor_plate.gd`, under a `Plates` node, never direct
  children of the root) break on a rocket, or on a projectile that answers the duck-typed **`is_high_impact()`** opt-in
  (`Bullet.is_high_impact()` is `unlimited_pierce`, the player's Sniper Shot; a later heavy weapon opts in the same way),
  and glance off everything else. The hull stays a full-size `HurtBox` that deflects while any plate lives; a plate
  resolves each hit once (`_resolve`), because Godot orders the plate's `area_entered` and the rocket's query
  undefined. The armour's **shove** on touch is `ContactProfile` mode `ARMOR` with `shove_speed`, which calls the touched
  ship's duck-typed `apply_knockback(impulse)` (the Open Space ship adds it to `velocity`; never call
  `apply_knockback_motion()` there, it clamps to the Assault bounds). Persistent enemy ordnance (mines, bombs; the Mine Layer's `EnemyMine`s too) outlives
  its ship through `BulletPool.persist_after_owner_death`, which hands each projectile to its own `expired -> queue_free`
  — still exactly one owner at every instant. Spelled out in
  `docs/architecture/PROJECT.md` → Conventions; gated by
  `tests/integration/test_player_bullet_lifetime.gd`, `test_armor_query.gd` and `test_enemy_ordnance.gd`.
  **A large enemy is built from destructible parts (Phase 10 t2):** each part is an `EnemyModule` (`global/components/enemy_module.gd`, group
  `enemy_parts`) under the host's `Modules` node, with a `ModularHull` (`modular_hull.gd`) beside it forwarding `hull_share` and re-emitting part signals. A part takes
  damage only through its own `HurtBox.received_damage` (so a local `EnemyShield` covers it); a locked part ignores every damage (the only guard against the beam, the nova
  and a `LaserRay`); a part killed this physics frame still consumes its killing shot; a destroyed part stays on the hull as wreckage (out of `enemy_parts`, hurtbox
  closed, wreck sprite; the wreck tint goes on its `Sprite` child because the beam tints the part node). The player's beam and nova target `enemy_parts`; enemy energy
  weapons (`EnergyHitScan`) never do. Gate `tests/integration/test_enemy_module.gd` ([global.md](docs/architecture/modules/global.md) → *Destructible parts*).
  **A part carries guns (Phase 10 t3):** `ModularHull.build_mounts()` builds each part's `MountSlots` through `TurretMountBuilder.build()` (the one place a `TurretMount` and its root-child pools are built; `DefenseTurret` uses it too), attaches each mount to its part so it is UNPOWERED from the part's destroy call, and a mount's `traverse_deg` (360 = unlimited, bit-identical; `TurretMountSlot.traverse_deg_override`) limits the arc it aims, scans and fires in, turning along the arc and never through the blocked sector. `TurretMount.Variant.HEAVY_CANNON` (Heavy Shell) is the first shooter of that round. Gate `tests/integration/test_turret_mount_traverse.gd`.
  **The Heavy Gunship (Phase 10 t4) is the gunship rewritten in place** (`assault/scenes/enemies/heavy_gunship/`: `HeavyGunship`, `HeavyGunshipBrain`, flat `HeavyGunshipConfig`; `WaveBuilder.heavy_gunship()` / `HEAVY_GUNSHIP`, the old `gunship()` / `GUNSHIP` are gone): one 112 × 144 `RectangleShape2D` for body, root hurtbox and contact box, a 700 HP hull bar and six parts whose hurtboxes obey the **flush-edge rule** (each part's outer side lies exactly on the hull rectangle, so a shot through that edge hits part and hull in the same step; `HomingPoint` = the edge midpoint). APPROACH / BROADSIDE (a live battery side-on, the other side after it dies, the nose with none) / BREAK_AWAY; Assault: corridor, ±70° arc above the player, `EngagementBudget` 9.0 s, attack gate, curved DISENGAGE (no camera hold, no off-the-top retreat). **Build its exit-probe calls only through `tests/helpers/ph10_exit_keys.gd`** (`heavy_gunship_exit()`, static `prepare_probe`). The Bonus Drone is now the legacy (no-brain) test subject. Gate `tests/integration/test_heavy_gunship.gd`.
  **Its phases (t5):** `HullPhase` CONTROLLED ≥ 60 % > OVERHEAT ≥ 30 % > EMERGENCY, read off the root `Health`, one way (a repair never steps back). OVERHEAT: a gun mount entering COOLDOWN is 1 heat, the 4th VENTs for 2.2 s (vents `set_vulnerable(true)`, `hull_share` 1.0 so an open vent doubles a hit, `max_speed` × 0.6, `StateLight.State.VENTING` orange, appended; gun `can_fire` = normal ∧ `phase() == FIRE`, **not** `is_committed()`, so a started burst finishes and none starts); leaving VENT for any phase closes them. EMERGENCY: a `mover.boost` away every 5 s, the rear Missiles mount (own `telegraph_gate` `missile_gate_open()`) open 0.9–2.9 s after each boost at a player ≥ 80° off the nose, never despawning on health. **In Assault the pod fires only while the budget runs** (DISENGAGE `scan(0.0)`s it): the bounded exception to "persistent ordnance stays out of `ENEMIES_CLEARED`", so t11's deadline rows carry `engage_seconds` + the rocket `max_time`. The cannon's local `EnemyShield` (`Modules/Cannon/Shield`, 120°, config Defense group) covers the cannon's HP only. Its own rockets were measured never to hit it (no launcher guard). **A hand-ticked row with a boost starts with `await _fresh_idle_delta()`** (a hand-ticked `move_and_slide()` moves by the idle delta, which swings the hull off its facing; the helper scales `Engine.time_scale` by 1e-6 until `after_each`, so the delta is ≈ 0 on any machine; waiting for a short frame instead failed on a slow one).
  **The Carrier (Phase 10 t6) has an armoured hull** (`assault/scenes/enemies/carrier/`: `Carrier`, `CarrierBrain`, flat `CarrierConfig`; `WaveBuilder.carrier()` / `CARRIER`): the root answers `deflects_hit()` / `is_armored()` true and refuses all damage (`armor_deflected`), so shots cross it to seven parts (engines, guns, locked hangars, locked core) all within x ±100 px (`module_x_extent`); the core opens after `core_exposure_count` 3 outer wrecks (deferred) and **its death is the carrier's**. Engine loss cuts turn rate / speed and lists; Open Space SCREEN 600–950 px leashed 900 px to its anchor, PANIC inside the leash; Assault CROSS at a constant 90 px/s an EMP does not stop (`BaseEnemy.emp_seconds_left()`, `on_emp_refreshed()`), sway ±30 px of the world-anchored spawn x, freed below the projectile rect by the root. `accepts_ward()` false (Support Ship skips it). Never in `ENEMIES_CLEARED`. **Its weapons (t7):** `GunPort` / `GunStarboard` BURST_CANNONs with a 150° traverse on their own side (a dead battery leaves its side safe), `HullMounts/Bow` HEAVY_CANNON (70°) and `HullMounts/Dorsal` PURSUIT bank (beyond `missile_min_range` 450; cooldown and pursuit written by the root), built by `TurretMountBuilder` after `build_mounts()` with the running index; `AntiApproachRing` (`carrier_pulse_ring.tscn`, r 420) owned and ticked by `CarrierBrain` inside 340 px every 5 s, exempting the owner group, never reaching parts; nothing fires outside the Assault view; PANIC: battery cooldown × 0.7, pulse × 0.5, emergency deployment; an EMP, a rail or death ends the ring at once. **Its hangars (t8):** `CarrierHangars` (`carrier_hangars.gd`, ticked by the brain) opens a hangar's doors (hittable, yellow light) 0.8 s before each launch; children spawn synchronously from the brain tick at the hangar `Mouth` as siblings announced with `EventBus.enemy_spawned_orphan`, in the owner group, seeded, `start_engaged`, one squad per payload, outlive the carrier; Open Space every 9 s under caps 3 / 6 (live = valid and not queued), Assault swarm drones once per hangar at 3.0 / 7.0 s after view entry; a wrecked hangar never launches; PANIC deploys every live hangar that may still launch. `test_carrier.gd`'s `_spawn` keeps hangars quiet (`first_launch_delay` 1e6, launch counts 0). Gates `tests/integration/test_carrier.gd`, `test_carrier_hangars.gd`. **Art of both heavies (t9):** hand-drawn top-down sprites in `assault/assets/sprites/enemies/heavy_gunship/` and `carrier/`, drawn exactly to the frozen hurtbox sizes (scale 1, hulls with empty sockets, each part an intact and a wreck texture, ≤ 90 % opaque); a hangar has three door textures (`intact_texture` closed, `CarrierHangarDoors.open_texture`, `wreck_texture`; the starboard side mirrors with `flip_h` and `Doors.scale.x` −1) and the core three plating states (`core_open_texture` on exposure); gates `test_ph10_sprites.gd` and the transparency sweep, widened to every `Texture2D`-valued node property.
  **Hub placement (Phase 10 t10):** the sector hub patrols one Heavy Gunship (draw 19, 2600 ring at 157.5 degrees, about (-2402, 995)) and one Carrier (draw 20, 3400 ring at -112.5 degrees, about (-1301, -3141)), appended after the Hacker so every earlier seed is unchanged; `patrol_anchor` and `rng_seed` are set before `add_child()`, both idle on `AnchorIdle` (not `start_engaged`), and the Carrier's escorts land in `EnemyContainer`. `test_sector_hub_patrol.gd::_patrol_groups()` lists both (the Carrier's footprint is `idle_radius` + `leash_radius` 900), so every sweep covers them; pre-approved levers (none needed): gunship to -67.5 degrees (22.5 is unusable), carrier ring 3200-3800.
  **Level 1's Heavy Gunships (Phase 10 t11):** the four `b.heavy_gunship()` lines carry no rail (Deep Space 3.5 s at `.at(160, -500)`, clear of the wall's strip at spawn; Cloud Descent 50.0 s and the 62.0 s pair, which never fired on their rails), pinned as `EXPECTED_PH10_GUNSHIPS`, never more alive at once than the frozen `_LEGACY_PEAK_HEAVIES` (deep_space 1, cloud_descent 3), and gated per Cloud Descent entry against its 10 s net on an exit term and a rocket term (`test_engagement_deadline.gd`). **The Heavy Gunship's body `collision_mask` is 0** (the Carrier's and the station's rule; owner choice): a GROUNDED body that slid off another ship took its velocity as a platform's and was thrown into the level-start wall; it still steers round hazards and its layer, hurtbox and contact box are unchanged. `tests/helpers/level1_slice_replay.gd`'s opt-in `light_lasers` (`lit_section`, `lit_from`; default off, every older caller unchanged) lights the real `LaserWallWave` and the director's own `_spawn_laser_columns()` (defaults `COLUMN_WARN_SECONDS` / `COLUMN_ACTIVE_SECONDS`) on an idle clock, relights a row carried over the slice start by `warm_start()`, and reports `deaths` covered by a lethal ray; a lit run caps `max_physics_steps_per_frame` at 16 (README rule 1). Gate `tests/integration/test_level1_heavy_spawns.gd`.
  **Level 1's Carrier (Phase 10 t12):** one `b.carrier().at(55, -260)` in Planet Approach's 65.0 s wave (world x 750, worst life 20.61 s, parts sweeping x 620–880), pinned as `EXPECTED_PH10_CARRIER`; `_carrier_column_conflicts()` (not the specialists' `_column_conflicts()`) keeps every column lit while it lives at least the sweep + a beam's width away (only the 78.0 s set overlaps); its ≤ 4 swarm drones are C3 intervals from the carrier's spawn (an emergency deployment can launch at any moment). Its numbers live once in `tests/helpers/level1_carrier_timeline.gd`; the lit replay parks the stub high (`level1_slice_replay.gd`'s opt-in `player_offset`) so the carrier crosses from the highest view, else it is gone before the 78.0 s set turns lethal and the check is vacuous.
  **The Space Fortress's geometry weapons (Phase 11 t16)** are owner-ticked by `FortressBrain` like every `EnemyBeam` / `EnergyRing`: hull spokes (`HullBeams/Spoke0..3`, `fortress_spoke_beam.tscn`) whose volleys spin the hull (edge-triggered `begin_spin()` / `end_spin()`), the ring pulse (`fortress_pulse_ring.tscn`) and the core bullet ring (`CoreRingPool`, built in code in `_ready()` and sized by `EnemyRounds.pool_size_for` over the round's life: 72). Each inherited scene authors every gated value; the gates read instances. While the brain is not ticked (EMP, dying) `SpaceFortress._physics_process` finishes a cancelled one's FADE. A hand-ticked movement row of `test_space_fortress.gd` spawns through `_mover_spawn`, which silences them (`QUIET_GEOMETRY`); the measured Assault density row counts launches and returns each round at once. Gate `tests/integration/test_fortress_weapons.gd` (rows B7–B12).
  **Its art (t9)** lives in `assault/assets/sprites/enemies/space_fortress/`, every texture at scale 1 and the size of its frozen hurtbox (hull 384 × 384, batteries 44, hangar 36 × 56, generators 52, core 88); each part has intact and wreck art, and the three door states are `intact_texture` / an export / `wreck_texture` (`shutter_open_texture`, `core_open_texture`, and `hangar_open_texture`, which follows `BossReinforcements.door_changed` for the hangar's own bay and never draws over a wreck); the south generator is `flip_v`; `Thrusters/Thruster0..3` and `CriticalOverlay/Overlay` are child sprites of the phase-toggled parents. No station PNG is left in the scene. Gate `tests/integration/test_fortress_sprites.gd`.
  **A wreck is cover for both sides (Phase 6): an enemy round stops on a wreck.** `EnemyBullet`'s HitBox mask includes 1024 and a
  hit there expires the round only when the area's owner answers duck-typed `stops_enemy_rounds() == true` (only `Wreck` does;
  asteroids do not, so round behaviour against them is unchanged); the player's Sniper Shot ends on a parent answering
  `stops_piercing()` and spends its full damage. A runtime hazard (wreck, debris fragment, Gravity Field, reactor field) is
  spawned deferred through `spawn_into()` into `Hazards.container(tree)` — still exactly one owner, it frees itself.
  **Hazards are sampled by the body, the mover owns enemy drift, runtime hazards spawn deferred into the `HazardContainer`** —
  [PROJECT.md](docs/architecture/PROJECT.md) → Conventions. **A laser wall is a segment hazard (Phase 8):** `HazardInfo.segment_half` (ZERO = circle,
  every earlier hazard, bit-identical) and `exempt_group` (its own pair ignores it); gated by the segment rows of `test_hazards.gd`,
  `test_context_avoidance.gd` and `test_enemy_mover.gd`. Phase 6 gates: `tests/unit/test_hazards.gd`, `test_hazard_field.gd`,
  `tests/unit/test_context_avoidance.gd` (pass-through bit-identical with no hazard, avoidance per profile),
  `test_player_hazards.gd` (pull and slow on both players), `test_wreck.gd` (body, yield, LOS, "no hurtbox larger than its
  body"), `test_wreck_spawning.gd` (death rolls, caps, no container -> no rng, real-physics deferred spawn),
  `test_hazard_projectiles.gd` (rockets / bombs / missiles bend, bullets fly true), `test_hazard_art.gd`, the Sniper / Fighter /
  Ram cover and well rows, and the level-1 exit guard
  `test_level1_fighter_exit.gd::test_cloud_descent_clears_in_time_with_wrecks_left_behind` (pre-approved levers: Assault wreck
  `avoid_weight` 0.3, then halving Assault `wreck_chance`; never the timeout).
  **Mines are one family, `EnemyMine extends EnemyOrdnance` (Phase 7)** — `enemy_ordnance/mines/enemy_mine.gd`, `Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }`
  (append-only; PROXIMITY is the Bomber's `mine.tscn`, same path). A mine **registers as a `&"mine"` hazard on `launch()`, not in `_enter_tree()`** (a pooled mine idles in its
  pool) with the measured footprint `trigger_radius + hazard_pad` 60 at `avoid_weight` 1.0; its `Hostility` is `PLAYER` for every mine an enemy lays (layer-128 hurtboxes,
  `ContactBlast`) or `ALL` for a *placed* mine (also set off by a layer-512 area whose parent is in group `enemies`, blasting through `Hazards.pulse_damage`); `placed = true`
  makes it self-owned (`mine_life = placed_life`, 0 = never fizzles) through a **deferred** `_start_if_placed()`. A pulse mine's `PlayerBase.apply_boost_disruption()` scales only the
  **excess** over `cruise_speed()` and is checked before a tank is spent; an EMP mine goes through the one `EmpPulse.emit()` hook, whose Ph7 player effect is a stand-in Ph9 replaces
  without changing a signature. **The Mine Layer's mines persist, so neither it nor anything dropping persistent mines goes in an `ENEMIES_CLEARED` section.** Never name
  `EnemyMine` inside `enemy_mine.gd` (a self-reference leaks at exit and fails the gate with every test green). [PROJECT.md](docs/architecture/PROJECT.md) → Conventions →
  *Mines, minefields and the Mine Layer*. Phase 7 gates: `tests/integration/test_enemy_mines.gd` (each variant's trigger, scene numbers, the warning rule read from scene exports,
  chain ripple, pulse / EMP application, sprites; both harnesses), `test_minefield.gd` (patterns, seeds, the ready-order boundary, 60 s no-fizzle, Assault drift, avoidance at
  8x), `test_mine_layer.gd` (passes and trail placement, the planner's lead / fence forms, hub idle, persistence, hatch, `MineWake`, level-1 slice replays),
  `test_player_boost_disruption.gd` (both ships: efficiency, the excess rule, refused boosts spend nothing, EMP), `tests/unit/test_emp_pulse.gd`, and the Mine Layer rows of
  `test_level1_specialist_spawns.gd` (`EXPECTED_PH7`, peaks 8 / 7 against the frozen 2.5x gate), `test_engagement_deadline.gd` and `test_sector_hub_patrol.gd`
  (pre-approved levers on `mine.tscn`, in order: `hazard_pad = 0`, then `registers_hazard = false`; neither was needed).
  **Enemy lasers are one owner-ticked family, `EnemyBeam` (Phase 8)** — `assault/scenes/projectiles/enemy_beams/`, `Kind { BEAM, SWEEP, LANCE, TWIN }`,
  `Phase { OFF, TELEGRAPH, ACTIVE, FADE }` (append-only). The owner calls `setup(host, owner_group)`, `start()`, `tick(delta)` on its physics tick and `cancel()`;
  **`tick()` is the beam's only clock** (no `Timer`, `create_timer` or `_process`). An emitter beam points along its node's **local +X** (the owner rotates the parent).
  Tuning lives in `beam.tscn` / `sweep_beam.tscn` / `lance.tscn` / `twin_beam.tscn`, read through `EnemyBeamScenes.export_of()`. A beam hurts every `player` / `allies` / `enemies` /
  `asteroids` node whose hurtbox **shape** meets it (`EnergyHitScan`, `Shape2D.collide`, swept between ticks) **except its owner set**, never ordnance, by a direct
  emit (bypasses `EnemyShield` and plates). `rehit_interval` 0.55 > the player's 0.5 s i-frames; telegraph line ≥ 3 px; static / sweep / lance fairness inequalities —
  [BEAMS.md](assault/scenes/projectiles/enemy_beams/BEAMS.md). Gate: `tests/integration/test_enemy_beams.gd` (its real-player cadence rows run at **4×**, not 8×: at 8×
  one headless idle frame outlasts the 0.05 s i-frame margin and refuses re-hits).
  **Endpoint half (t5):** `twin_beam.tscn` takes `set_endpoints(a, b)` every tick; cover clips a beam through `LineOfSight.first_blocker()` **only on the physics step** (a hand-ticked beam never casts; cover rows run on real physics at 8×) and an endpoint beam leaves a safe shadow behind a blocker; `set_strained(true)` = non-lethal flicker; a `registers_hazard` beam is a `&"laser_wall"` segment `HazardInfo` from TELEGRAPH start to FADE start (full `a..b`, `exempt_group` = its owner group).
  **The Pulse Ring is `EnergyRing`** (`enemy_beams/energy_ring.tscn`, `EnemyBeamScenes.ring_scene()` / `ring_export()`; `class_name PulseRing` stays Ph7's visual): owner-ticked
  TELEGRAPH -> EXPANDING -> FADE, a 24 px band at 360 px/s whose outer edge stops at `max_radius` 280, two 45 degree gaps turning at 30 degrees/s, each target hit once per ring over
  the swept interval. Gate: `tests/integration/test_energy_ring.gd`.
  **Level 1's laser columns (Phase 8 t17):** `Level1Director.laser_column_schedule()` is the column schedule as data (`_build_schedules()` binds `_spawn_laser_columns` to it); they killed AI enemies, so `LaserRay` gained the opt-in `registers_hazard` (default false; the race unaffected), set by the director's columns and all 12 rays of `laser_wall.tscn`. Gate `tests/integration/test_level1_laser_columns.gd`; re-measure with `scripts/measure-level1-columns.sh` (manual, `tests/helpers/level1_column_replay.gd`).
  **Turret groups (Phase 8 t9) are coordinators, not parents:** `TurretGroup` (`assault/scenes/structures/turret_group/`, never in `enemies`, never scored) spawns its members deferred as siblings in the enemy container (announced with `EventBus.enemy_spawned_orphan`); a `PowerSource`'s `died` darkens every member through `set_powered(false)` in the same call, for good; a wave-spawned group's Assault x is world-anchored (`world_anchored_x`, via `EnemyWorld` only). Gate `tests/integration/test_turret_group.gd`. **A `ShieldGenerator` (t9s) is a member that sustains a 360 degree `EnemyShield` bubble on the others** (never itself, never a fence post, never displacing a ward already in the absorber slot); no `sustain()` after its death or the group going dark, so bubbles lapse; beams bypass them. **A `LaserFence` (t10) is two `LaserEmitter` posts and one twin-beam `EnemyBeam`** (`assault/scenes/structures/laser_fence/`, `assault/scenes/enemies/laser_emitter/`; the fence is not an enemy, the posts are, and answer `is_fence_post()`): `Mode { STATIC, CYCLE }`, ticked by its own `step(delta)`, registers a `&"laser_wall"` hazard while warning or lit, collapses for good on a post's `died` and lingers `linger_seconds` 1.0 so the posts' explosion particles (spawned under the fence) finish; a wave-spawned fence is world-anchored like a group. Gate `tests/integration/test_laser_fence.gd`.
  **Twin-Laser Drones (t12) are two drones, one rig, one clock:** `TwinLaserPair` (`assault/scenes/enemies/twin_laser_drone/`, a `RefCounted` both brains hold) owns the `twin_beam.tscn` as a child of drone A and advances its phase only in the leader's tick (A while it lives); a separation error past `length_tolerance` for `strain_seconds` collapses the beam, a drone's death breaks the pair in the same call; Assault frames are planned inside `inner_rect()` and allow one attack per life. Spawn with `WaveBuilder.twin_laser_pair()`, never in an `ENEMIES_CLEARED` section. A hand-ticked drone test clears the body `collision_mask` (the broadphase is stale between hand ticks). Gate `tests/integration/test_twin_laser_drones.gd`.
  **A Laser Tender (t13) launches its pair in a V into a moving wall (Attack B):** `LaserTender.launch_pair(points)` (`assault/scenes/enemies/laser_tender/`, the Ph10 / Ph11 seam) adds the two drones **synchronously** (physics step or idle code only, never a physics callback), binds them with the tender in the owner group and puts the rig in `TwinLaserPair.Phase.LAUNCHED` (appended): a straight boost to each point, a stop tick, then FORM on a fixed frame. One live pair, rearm, docking; Assault: one launch per life from the upper band. Spawn with `WaveBuilder.laser_tender()`, never in an `ENEMIES_CLEARED` section. Gate `tests/integration/test_laser_tender.gd`.
  **Hub idle and measured exits (t14):** a hub pair and the tender idle through `AnchorIdle` (the pair's ticked by its leader only, rig `TwinLaserPair.Phase.IDLE` appended; `start_engaged` skips it; a stand-down never cuts a busy rig phase; the tender's duck-typed `recalls_drones()` docks a launched pair). Their Assault exits are measured once per GUT run: **build those probe calls only through `tests/helpers/ph8_exit_keys.gd`** (`drone_exit()` / `tender_exit()`, static `prepare_probe`, never a lambda: the memo keys on the Callable); a source sweep in `test_laser_tender.gd` fails a hand-built one.
  **Level 1 (t19)** places an `assault_pair` turret group (`.at(64, -220)`, deep_space 3.0 s: world x 718 / 768 / 818, clear of every scheduled column *and* the
  level-start `LaserWallWave`, x 0–672, which the plan's −64 sat in), a twin pair (deep_space 29.0 s) and a tender (planet_approach 2.0 s), pinned as `EXPECTED_PH8` and
  counted per ship in the frozen 2.5× gate of `test_level1_specialist_spawns.gd` (with `test_ph8_static_members_clear_every_lit_column`); attacks replayed at 16× in
  `test_level1_ph8_attacks.gd`.
  **The ability lock (Phase 9 t1) locks H abilities and K rockets only, and is read in exactly three seams** — both ships' `_input` H loops and
  `RocketState._on_action` (`special_weapon`, after the cooldown check) — each through `PlayerBase.allow_ability_press()`; a refused press spends nothing.
  Movement, Shift boost, dash, warp, primary fire (`WeaponState` never reads it), `switch_weapon` and module `tick()` are never locked. Sources: a lit jammer
  `HazardField` (`disables_abilities`, true only while ACTIVE; `Hazards.jammer_at()`, then `stabilise_seconds` after the exit tick) or a timed
  `apply_ability_lock(seconds, source)` (longest wins). Every lock clock is `x -= delta`, over at `x <= 1e-6`. Gate `tests/integration/test_player_ability_lock.gd`
  **Its tells (t2):** `PlayerBase._report_lock()` also shows `AbilityLockStatic` (code-built overlay) and emits `EventBus.player_ability_lock_changed(locked)`; `MissionHud` builds `JammedChip` and `LockGlyph` for both HUD scenes. Gate `tests/integration/test_player_ability_lock_tells.gd`.
  **Seeking ordnance (t4):** a player seeker joins `SeekingOrdnance.GROUP` and answers the duck-typed `can_be_retargeted()` / `retarget(target, seconds, source)` / `is_retargeted()` / `jam_guidance()`; only `homing_missile` does (never a warhead). A hijacked rocket turns at 1.6 rad/s, hurts the player **only by an 18-damage `ContactBlast`** once armed (0.25 s and 60 px), keeps 100 on enemies, is shot down by one bullet (`HurtBox` 512 / 64, open only while hijacked), and every end goes through `_finish()` (lifetime expiry too). **A player rocket never hits another player rocket** (homing and warhead HitBoxes ignore a `homing_missile` parent). Seekers fly straight in a lit jammer. Gate `tests/integration/test_seeking_ordnance.gd`.
  **EMP (t5):** `EmpPulse.emit(..., targets := TARGET_PLAYER)` (`TARGET_ENEMIES` 2, `TARGET_SEEKERS` 4, `TARGET_ALL` 7; the default is the Ph7 call). The player effect is a full boost disruption **plus** `apply_ability_lock(seconds)`. **`BaseEnemy.answers_emp()` (default `is_ai_driven()`) is the one routing question every EMP source asks**; an answering enemy halts, its brain gets `on_emp_started()` once and is not ticked for the window (its mover still steps), an `EmpStatic` overlay shows, and it **stays tangible**; the window is counted ahead of the no-brain return and `suspend_ai()` clears it. A beam brain of a mover-driven ship must override `on_emp_started()` (sweep row). Steering `EnemyRocket`s are in `SeekingOrdnance.ENEMY_GROUP` for one life and answer `jam_guidance()`. The EMP mine reaches enemies only when placed. Gate `tests/integration/test_enemy_emp.gd`, `tests/unit/test_emp_pulse.gd`.
  **Jamming Structure (t7):** three static towers (`jamming_structure/` local, `sector_jammer/` Open Space only, `pulsed_jammer/` 0.8 / 3.0 / 2.5 s; one `JammingStructure` script, a scene + `.tres` each) whose child `HazardField` (kind `&"jammer"`, `avoid_weight` 0, config written in `_ready()` then `restart_cycle()`) is the lock's field. Its EMP answer is `HazardField.suppress(seconds)` (field quiet, tower still shootable, cycle running); an `EnemyRocket` skips `_steer()` in a lit field; `MissileCorvetteBrain._roll_kind()` turns PURSUIT / CLUSTER into DUMB at a player in one; Sniper / Fighter spot selectors skip `&"jammer"` infos. `WaveBuilder.jammer(variant)`, never in `ENEMIES_CLEARED`. Gate `tests/integration/test_jamming_structure.gd`.
  **Hacker Frigate (t8, t9):** `assault/scenes/enemies/hacker_frigate/` (`HackerFrigate`, `HackerFrigateBrain`, flat `HackerFrigateConfig`). HOLD_ARC is the corvette's target-angle orbit, lopsided (`orbit_dir` +1 = clockwise 0.18 rad/s, -1 = 0.30), forced toward the nearer edge of the player's nose / route cone at 0.30 rad/s (cone sizes read every tick); BREAK_OFF inside 420 px is committed `mover.boost` bursts in Open Space and a view-clamped request in Assault (`_clamp_into_view()` pads `view_margin` by 8 px so the hull stays inside `grow(-60)`). **Build its probe calls only through `tests/helpers/ph9_exit_keys.gd`** (`hacker_exit()`, static `prepare_probe`; a source sweep in `test_hacker_frigate.gd` fails a hand-built one). Never in `ENEMIES_CLEARED`. Gate `tests/integration/test_hacker_frigate.gd`.
  **Its Hijack Pulse (t9):** TELEGRAPH 0.9 s (any damage, an EMP or the Assault expiry cancels it) then PULSE 1.6 s, in which `HijackPulse` darts (`assault/scenes/projectiles/hijack_pulse/`: **no collision areas**, claim by distance, pooled in `DartPool` with no `persist_after_owner_death`, so killing the Hacker cancels them) fly from the hull centre at up to 3 `SeekingOrdnance.eligible` rockets within `hijack_range` 650 in sight; the player must be within `pulse_trigger_range` 870 in sight; LOS is cast on the physics step only (a hand-ticked row counts it clear). One pulse per Assault life. **The Disruptor hook** is `pulse_lock_seconds` (0 on the base Hacker) applied at PULSE end through `HackerFrigate.lock_player_abilities()`. **A long Hacker movement row must write `first_pulse_delay = 1000`** or expect the pulse. Gate `tests/integration/test_hijack_pulse.gd`.
  **Level 1 (t14)** places one Hacker (planet_approach 42.0 s, alive 42.00–58.30 s) and, after it has gone, one local jammer (62.0 s, `.at(-80, -220)`: world x 480,
  alive 62.00–89.23 s, clear of every lit column), pinned as `EXPECTED_PH9` and counted in the frozen 2.5× gate (peak stays 7 of 7.5); replayed at 16× in
  `test_level1_ph9_attacks.gd`. `test_engagement_deadline.gd` keeps the Disruptor out of `ENEMIES_CLEARED` and scans every Assault level source for an EMP zone, an EMP mine,
  a non-zero `w_emp` or a sector jammer.
  **Phase 9 gates not named above:** `tests/integration/test_homing_missile_lifetime.gd` (the player homing missile's `ProjectileLifetime` replaces the Assault-only box, so it
  flies anywhere in Open Space and still expires in Assault), `test_emp_blast_module.gd` (the player's EMP Blast routes by `answers_emp()`: brain-driven ships and jammers stay
  tangible, legacy enemies keep the process-disable stun), `test_emp_zone.gd` (`EmpZone` arm / pulse cycle, `TARGET_ALL`, composed child `HazardField`), `test_ph9_sprites.gd`
  (the Hacker, Disruptor fin, dish, three jammer towers and EMP beacon art load and are not opaque cards), plus `test_jamming_structure.gd`, `test_hacker_frigate.gd`,
  `test_hijack_pulse.gd`, `test_seeking_ordnance.gd`, `test_enemy_emp.gd` and the lock gates above. **Scenes:** `jamming_structure/` (+ `JammerFieldArt`), `sector_jammer/`,
  `pulsed_jammer/`, `hacker_frigate/`, `hacker_disruptor/` (not placed), `hijack_pulse/`, `hazards/emp_zone/`; builders `WaveBuilder.jammer()` / `hacker_frigate()`.
  ([PROJECT.md](docs/architecture/PROJECT.md) → Conventions → *Electronic warfare*).
- **Tests are GUT, in `tests/`** — run them headless with
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
  (this is step 3 of `/agent/verify.sh`). The suite is almost entirely **characterization**: it
  pins today's behaviour, bugs included. The exceptions are
  `tests/integration/test_resource_uid_integrity.gd`, an invariant check over `[ext_resource]`
  UIDs and the UID-only references in `project.godot` / `export_presets.cfg` (read from disk, so
  it is immune to the stale aliases a warm `.godot/uid_cache.bin` keeps alive) that also asserts
  every UID we write is one the editor could have minted and detects collisions by decoding
  rather than by string match — `uid://` is base-34 text for a 64-bit int, so a hand-typed UID is
  usually an alias for one owned elsewhere, which no text comparison can see,
  `tests/integration/test_suite_integrity.gd`, which asserts every `tests/**/test_*.gd`
  compiles and extends `GutTest` (GUT otherwise drops an unloadable test script with only a
  warning and still exits 0, so the gate stays green while a test file silently vanishes),
  `tests/integration/test_gut_local_patches.gd`, which asserts the three hand-applied patches
  `addons/gut/LOCAL_PATCHES.md` documents are still in place (re-vendoring GUT drops them, and
  the resulting breakage is silent — parse errors on stderr, suite still exit 0, doubler gone;
  the third patch guards a leaked `SceneTreeTimer` on every headless run instead),
  `tests/integration/test_project_load_integrity.gd`, which loads every `.tscn`/`.tres`/`.gd`
  outside `addons/` and asserts each one loads, instantiates and compiles with no engine error or
  warning logged (the gate's `--import` step never loads a scene and its `--quit` step boots only
  `res://boot/…`, so most of the project was previously unloaded by every gate step),
  and the boss family — `tests/integration/test_station_assault_section.gd`, `test_laser_ray_hit_mask.gd`,
  `test_radial_attack_pattern.gd`, `test_boss_death_sequence.gd` and `test_fortress_incoming_damage_paths.gd`,
  plus the boss-machinery and fortress gates: `tests/unit/test_boss_phase_driver.gd` (ladder one-way, snapshot diff),
  `test_boss_phase_rules.gd` (the §25 intent gate: every fortress phase changes at least two of six aspects, read off `phase_snapshot()`),
  `test_boss_reinforcements.gd` (escort container, `boss_escort_spawned` scoring path, scuttle), `test_shield_sector.gd` (a generator's bubbles lapse with it),
  `test_turret_mount_variants.gd` (spread cannon / rapid pulse), `test_space_fortress.gd` (shell, parts, phases, movement in both harnesses),
  `test_fortress_weapons.gd`, `test_fortress_reinforcements.gd`, `test_fortress_sprites.gd` and `test_level1_fortress_section.gd` (the replayed section)
  (the space station's own files were retired with it in Phase 11 t11; their intent lives in the fortress suites) —
  which cover new code and so
  assert intent. The last of those closes the boss's collision-layer coverage gap: real missiles,
  a real asteroid and a real `BeamBehavior` prove the `HurtBox` mask bits 32 and 1024 and the
  layer-0 root (plus `is_laser_blocking()` false) that keeps the hull from blocking the player's mining laser. `tests/integration/test_module_unlock_sources.gd` is a second invariant check
  (every module in `ShipModuleState.SLOT_MODULES` has an unlocker pickup in the sector hub, so
  the unlock gate cannot strand content), and `tests/integration/test_module_list_lock.gd`
  asserts intent for the ship menu's locked rows.
  `tests/integration/test_weapon_unlock_sources.gd` is the same check over the *other* unlock
  store, and is the one that closed the hole: `UpgradeState` seeds `STARTING_IDS` (`&"default"`)
  and `unlock()` had exactly one caller project-wide — `unlock_all()`, which nothing invokes — so
  `sniper_shot`, `spread`, `gatling` and `mining_laser` were tuned, implemented, iconed and
  **unreachable**, and the player flew the Standard gun for the whole game. Every non-starting id
  now needs a `WeaponModeUnlockerPickup` in the sector hub. Two of its cases go past placement:
  one collects a real pickup against the live autoload (every placement test passes on a pickup
  whose `_collect()` is empty), and one proves `PlayerMenu` rebuilds its weapon column on
  `UpgradeState.unlocked_changed` — without that the menu is stale for the rest of the scene the
  pickups live in. It also asserts every mode `.tres` sets `WeaponModeResource.icon`, now the
  single id→icon map for both the ship menu and the HUD chip.
  `tests/integration/test_enemy_contact_damage.gd` is a third invariant check, over the balance
  data rather than the files: every assault enemy's contact `HitBox` must deal the damage its
  `*_config.tres` declares. Every `BaseEnemy` subclass's scene authors a `ContactHitBox` node
  defaulting to `damage = 20`, which knows nothing about the subclass's own `.tres`, so an enemy
  that forgets to re-apply `collision_damage` in `_ready()` leaves the field dead with no visible
  symptom — which is exactly how the gunship rammed for 20 while its config said 30.
  `tests/integration/test_contact_hitbox_geometry.gd` is a fourth invariant check, over the same
  hitboxes' *geometry*: a `ContactHitBox` node's `CollisionShape2D` must reference the same
  `SubResource` shape id as the body `CollisionShape2D` and copy its `scale`, not just its bare
  shape. A `Shape2D` holds the radius but not the node scale that multiplies it, so a mismatched
  scale once built the gunship's ram box at 18 px against a 41.5 px hull — now every contact
  hitbox is scene-authored next to the body it has to match, the same pattern the asteroid family
  established (`assault/scenes/hazards/big_asteroid/big_asteroid.tscn`), and there is no runtime
  construction left to get wrong.
  `tests/integration/test_enemy_hurtbox_geometry.gd` is a fifth, over the *other* side of that
  collision pair: every assault entity's `HurtBox` must **cover** the body `CollisionShape2D`,
  within 1 px per edge. Armour is a damage rule on a full-size hurtbox — deflect, flash, report 0 —
  never an absent hurtbox, because a shrunken one leaves visible hull that swallows shots and
  reports nothing. It carries a permanent boundary test that applies the rejected "narrow the
  boss hurtbox to its core" proposal (first made as "narrow the station core to 88 x 240") to a live Space Fortress — its hull hurtbox shrunk to the core's circle — and asserts it fails, so that decision is a
  gate rather than prose someone re-litigates.
  `tests/integration/test_player_bullet_lifetime.gd` is a sixth, over projectile *ownership*. It
  states the two rules that used to be implied by the space-station fight: a player bullet is not
  consumed by a hurtbox it overlaps (the premise the boss's armoured core rests on), and an
  unpooled player bullet frees itself off-screen — which nothing did, so every shot ever fired
  stayed in the level for the whole mission. Its invariant enumerates `WeaponBehavior` subclasses
  from the project class list rather than a hand-written list, so a *sixth* behaviour is covered
  the day it lands, and its boundary case asserts the same free must **not** reach a pooled bullet
  (checked on `BulletPool.acquire()`, never on `_idle.size()`, which reads healthy even on the
  broken build).
  `tests/integration/test_level_director_polling.gd` is a seventh, over the ENEMIES_CLEARED poll: it
  asserts the poll ends on `child_exiting_tree`, honours its fallback window, and leaves nothing
  alive behind an early return. That last one is the reason it exists — the poll used to abandon a
  `SceneTreeTimer` on every early return, and a leak is reported only at *process exit*, after GUT
  has set the exit code and in words the gate's `FATAL` regex does not match, so **the gate prints
  `GATE PASS` on a leaking suite**. `scripts/check-test-leaks.sh` runs gate step 3 and additionally
  greps for the leak lines; run it after touching anything that awaits. It is a separate script
  because `/agent` is mounted read-only, so the gate itself cannot be changed from in here.
  `tests/integration/test_entity_sprite_transparency.gd` is an eighth, and the only one over the
  **art**: no texture an entity under `assault/scenes/{enemies,player,projectiles,hazards,allies}`
  draws over the game world may be 90%+ fully opaque, because a painted-in background renders as a
  card that cuts a hard rectangle out of the starfield. The retired space station's `station_core.png` shipped at
  65536/65536 px opaque and survived two cycles, because **no gate step renders a scene** —
  `--import` loads no `.tscn` and `--quit` boots only `res://boot/…`. It reads scenes through
  `PackedScene.get_state()` instead of instantiating them, and resolves `Sprite2D.texture`,
  `AnimatedSprite2D.sprite_frames` and `AtlasTexture.atlas` — a `Sprite2D`-only walk finds 9
  textures and four of its five roots contribute nothing. Fix a sprite that trips it with
  `./scripts/strip-sprite-bg.sh <png>` (border flood fill, then `--import`) rather than a
  regeneration, which gives a different sprite and so breaks a set drawn to match it.
  `tests/integration/test_config_instance_isolation.gd` is a ninth, over resource **ownership**:
  no two entity instances may share a `*_config.tres` object, the private copy must be
  value-identical to the shipped `.tres`, and every config class must stay flat enough for the
  shallow `duplicate()` to be a complete copy. Its roster is a directory sweep rather than a hand
  list, so a new enemy is covered the day it lands, and its boundary cases pin the two things the
  fix rests on: the copy survives a re-parent (idempotence), and it exists before any **child's**
  `_ready()` — checked by identity from inside a probe child, because comparing values is green
  even on the `_ready()`-time design the test exists to reject.
  `tests/integration/test_signal_emit_arity.gd` is a tenth, over signal **declarations**: Godot
  never checks a `signal` line's declared parameters against how it is actually emitted — the
  only place the declared arity is visible at all is `Object.get_signal_list()`, which is exactly
  why `Health.amount_changed` and `State.state_transition` drifted silently until the 2026-09-03
  fix. This generalizes that fix's two hand-written assertions into a project-wide sweep over
  every **self-emit** (`name.emit(...)` where `name` is a signal declared in the same file — a
  member-access emit like `hb.received_damage.emit(...)` needs cross-file type resolution and is
  out of scope). Its first real run caught a live instance of the exact drift it exists to
  prevent — `MovementController.action_single_press`/`action_double_press` declared bare while
  every emit and every connected handler already agreed on one `String` argument — fixed
  alongside the test, same shape as the original fix.
  `tests/integration/test_ship_rotation_single_writer.gd` is an eleventh, over the open-space
  ship's **single writer of `rotation`**: after the mouse-aiming epic, `ShipTurnController` is the
  only thing allowed to write `OpenSpacePlayerShip.rotation` (and `AssaultPlayer`'s own one-liner
  is the only writer of the fighter's), and a ship module that assigns `actor.rotation` directly
  fights whichever one owns it — exactly what `ai_targeting_module.gd:38` did until it was
  rewritten to call the duck-typed `face_instant()` every player class now exposes (same precedent
  as `Bullet.is_armored()`, above). It sweeps every `global/ship_modules/*.gd` for a direct
  `.rotation =`/`+=`/`-=` with an empty, permanent allowlist; reverting the duck-typed call back to
  a raw rotation write makes it fail, which is the proof it can.
  `tests/integration/test_enemy_mover_single_writer.gd` is a twelfth, over the enemy AI stack's
  **single writer of motion**: an enemy with an `EnemyMover` (`global/enemy_ai/`) must leave its
  `velocity`, `rotation` and `move_and_slide()` to that mover — its `EnemyBrain` only requests,
  on the one tick `BaseEnemy._physics_process` owns. It sweeps every `*_brain.gd` and
  `global/enemy_ai/*.gd` (receiver writes) and every mover-driven scene's root script plus its
  ancestors (bare writes), with an empty, permanent allowlist and boundary cases that prove it
  fires. Rails still win: `EnemyPathMover` calls `suspend_ai()` *in addition to* its unconditional
  physics switch-off and `"AIStateMachine"` lookup — never instead of it.
  `tests/integration/test_collision_layer_names.gd` is a thirteenth, over collision-layer
  **naming**: `project.godot [layer_names]` is the one place a physics layer bit gets a human
  name, and Godot never checks that a bit actually used in a scene or resource has one there. It
  sweeps every `.tscn`/`.tres` outside `addons/` for a `collision_layer`/`collision_mask` value,
  decomposes each into its set bits, and asserts every bit found is named — plus that
  `global/physics/collision_layers.gd`'s `CollisionLayers` declares one matching constant
  (`1 << (layer_number - 1)`) per named layer, so code can refer to a layer by name instead of a
  magic number. A synthetic-bit boundary case (bit 4, unnamed today) proves the check can reject.
  `tests/integration/test_enemy_contact_damage.gd::test_every_baseenemy_scene_is_in_the_roster`
  and `tests/integration/test_contact_hitbox_geometry.gd::test_every_baseenemy_scene_is_in_the_roster`
  are a fourteenth and fifteenth, **roster completeness guards**: each sweeps
  `assault/scenes/enemies/` for every `<dir>/<dir>.tscn` with a `BaseEnemy` root and fails if it is
  missing from that file's hand-maintained `ROSTER`, following the same sweep shape
  `tests/integration/test_enemy_hurtbox_geometry.gd::test_every_enemy_scene_is_in_the_roster`
  already used — so a new enemy scene added under that directory and never wired into a gate's
  roster fails loudly instead of silently shipping unchecked contact damage or geometry.
  `tests/integration/test_engagement_deadline.gd` is a sixteenth, over **Assault AI timing**: for
  every Swarm Drone or Razor Drone spawn in every `ENEMIES_CLEARED` section of level 1, the
  worst-case time from the section's last wave triggering to that enemy actually leaving the
  level (its engagement budget, plus its own worst-case exit — the Razor's formula also covers a
  dash deferring its budget's expiry) must clear the section's own `enemies_cleared_timeout`, so
  an AI enemy that outlives being killed can never stall a level the way an un-exiting rail enemy
  would. A boundary case pins that a Razor placed in an `ENEMIES_CLEARED` section (it ships only
  in `deep_space`, a `DURATION` section) would miss the timeout. The companion **concurrency**
  check lives inside the otherwise-characterization `tests/integration/test_level1_drone_spawns.gd`:
  once AI drones can outlive a single ramming pass, `tests/helpers/level1_drone_concurrency.gd`'s
  peak-alive computation is asserted as a genuine ceiling — the attack-capable peak (lead plus
  flanks) at most 2.0× and the all-drones peak at most 2.5× the legacy per-section peak — rather
  than merely pinned, so a later spawn change that pushes level-1 density past the pre-approved
  levers (documented in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`) fails the gate instead
  of degrading play quietly.
  `tests/integration/test_sector_hub_patrol.gd` is a seventeenth, the **hub clearance check**: for
  the Open Space hub's ambient Swarm squad and Razor Drone, it sweeps every `MissionTrigger` and
  `PickupBase` child of the real `sector_hub.tscn` plus the player's spawn point and asserts each
  one clears that group's own idle ring plus its `perceive_radius` — a planet or a pickup placed
  later within reach of a patrol's anchor fails it instead of ambushing the player mid-dwell. The
  same file also sweeps the whole project to confirm no `PatrolDrone` reference survives. The
  Phase 3 shooters joined it: the hub also patrols a fighter pair and a Gatling pair, and the same
  sweep now also asserts each of those groups clears its own ring (the Gatling's margin is only
  +88.7 px, so a pickup added closer than that fails it).
  Phase 7 added the Mine Layer to `_patrol_groups()` and the hub `Minefield` to `_element_radius()` (`radius` + the drift leash + the PROXIMITY trigger = 400 px), so a later placed
  field or patrol is covered by the same sweep (Mine Layer +585.6 px from the field, Gatling +775.1 px).
  Phase 8 (t18) added the Laser Tender (draw 16) and a twin pair (draw 17, a `TwinLaserPairSpawn` that stays a *queued* `EnemyContainer` child for the
  frame: count live children) to `_patrol_groups()`, and the defended derelict site `EnemyContainer/HubDefenseSite` (`hub_defense_site.tscn`) with two
  sweeps over every `TurretGroup` / `LaserFence` child of `EnemyContainer`: **A**, its fire reach (1360 px) clears the spawn, triggers and pickups by
  more than 300 px; **B**, every patrol's idle ring clears its footprint (416 px). A later placed site or patrol is covered by both.
  Phase 9 (t13) added the Hacker Frigate (draw 18, 2600 ring at 67.5 degrees) to `_patrol_groups()` and **sweep C**: every `JammingStructure` child of `EnemyContainer` (the hub's
  `SectorJammer` beside the site and its `PulsedJammer`; a jammer belongs there, never in `TacticalSpace`, where `_element_radius()` would read it as 0) keeps its `Field.radius` + 300 px
  clear of the spawn, triggers and pickups. The hub `EmpZone` in `TacticalSpace` is read as radius 260 and covered by the Ph6 sweep.
  `tests/integration/test_enemy_bullet_lifetime.gd` is an eighteenth, the **round lifetime sweep**,
  and `tests/integration/test_enemy_rounds.gd` its companion over the bullet family (Pulse, Scatter,
  Gatling Stream, Heavy Shell under `assault/scenes/projectiles/enemy_bullet/rounds/`): for every
  round, `max_distance / the slowest speed any shooter fires it at` must fit its `max_time`, with
  those speeds read from `FighterConfig` / `GatlingInterceptorConfig` fields (`aimed_speed`,
  `forward_speed`, `round_speed` and the `rail_*` speeds) — never a regex or a typed number, so a
  retuned shooter cannot quietly outrun its round's life. A synthetic 100 px/s round with the shared
  18 s / 2400 px caps proves the sweep can reject. `test_enemy_rounds.gd` pins what a round *is*
  (an `EnemyBullet` with a `ProjectileLifetime`, `reset()` restoring the scene's own speed and
  damage, the Scatter round expiring at 450 px) and `EnemyRounds.pool_size_for()`; the Heavy Shell,
  which no enemy fires yet, is exercised by a fixture shooter.
  `tests/integration/test_level1_fighter_spawns.gd` and `test_level1_fighter_fire_density.gd` are a
  nineteenth and twentieth, the level-1 **fighter pin and density gates**: the pin freezes all 64
  fighter / Gatling spawn rows (trigger, offset, delay, formation, and that none has `.move()`,
  `.free_after()` or an `aim_mode` any more), so the migration off rails can only change *how* they
  fight, never when or where they arrive; `_LEGACY_PEAK_FIGHTERS` and `_LEGACY_PEAK_SHOTS_PER_S`
  are **frozen constants** (computed from the live rails before they were deleted) that the count
  gates divide by — attack-capable at most 1.5× and all-alive at most 2.0×. The shots/s gate is
  **measured**, not computed: the density test runs each section's fighters and Gatlings through a
  real `WaveManager` and asserts the peak shots in any 2 s window is at most 1.25× the legacy peak.
  Boundary cases show a fighter line given `.move()` again, a changed delay, a dense burst and an
  extra formation at the peak each fail. Read the "wave-order quirk" in the Phase 3 DECISIONS
  before touching a section's wave list.
  The sixteenth gate was extended for the same migration: `test_engagement_deadline.gd` gains
  **per-entry fighter rows** for cloud_descent (engagement budget + the 0.8 s burst deferral + a
  *curved-exit* bound of 5.37 s, gated on the real `fighter.tscn` over 404 starts — the straight-line
  Razor term would under-report by 2.5 s), a boundary derived from the config rather than a fixed
  delay, and a Gatling boundary plus a "no `ENEMIES_CLEARED` section contains a Gatling" row.
  `tests/integration/test_level1_fighter_exit.gd` replays cloud_descent through a real
  `WaveManager`: the container is empty 9.07 s after `waves_complete` of a 10 s timeout.
  `tests/integration/test_fortress_reinforcements.gd::test_assault_escorts_fire_soon_after_launch` is a twenty-first,
  the **escort-fire test** (it replaced the retired space station's rail-fire test): a fighter pair and a Gatling pair the
  Space Fortress launches in Assault must each put a round into the escort container soon after launch. It exists because the
  fighter and the Gatling are brain-driven: a squad that looks dangerous but never fires would pass every other gate. A rail
  still **suspends** the brain, and the rail-fallback weapon (`on_suspended()`, built from `rail_*` config fields) keeps a
  railed fighter or Gatling firing.
  `tests/integration/test_level1_specialist_spawns.gd` is a twenty-second, the level-1 **specialist pin
  and density gate**: it pins all 50 sniper / ram / bomber rows (trigger, offset, delay), and for every
  section in `MIGRATED_SECTIONS` (all three since Phase 4 t22: deep_space and planet_approach in t21,
  cloud_descent in t22) asserts no line has
  a rail left and that peak alive specialists stay at most 2.5× the frozen `_LEGACY_PEAK_SPECIALISTS`.
  Each lifetime is config budget + deferral + a **measured** exit (`tests/helpers/specialist_exit_probe.gd`
  runs the real scene's curved DISENGAGE over the Ph3 404-start grid), never a straight-line exit.
  Boundaries: a `.move()` put back and an extra ram triple at the peak each fail.
  Phase 5 t17 added a separate `EXPECTED_PH5` pin for level 1's 3 Missile Corvettes and 2 Support Ships (DURATION sections
  only), counted as specialists in the same frozen 2.5x gate with exits measured once in `before_all()` over
  `corridor_starts()`. A boundary shows an extra corvette at planet_approach's measured peak (7 at 98.0 s) fails, and a
  spill-over row shows no specialist (a corvette's last rocket included) outlives the next `ENEMIES_CLEARED` section's last
  trigger. The corvette / support attack-in-budget rows replay only `rel - 1 s .. rel + engage + 2 s` of a section
  (`tests/helpers/level1_slice_replay.gd`).
  The sixteenth gate gained **per-entry sniper and ram rows** for cloud_descent in t22 (sniper: engage + aim + lock +
  measured exit; ram: engage + wind_up + charge_max_time + max(straight, measured)). The ram's curved exit is measured
  over the probe's second start set, `corridor_starts()`: the whole 1480 × 1480 corridor, because the view-only grid
  under-reports it by about 2 s. The 73.2 s ram is the tight row (9.60 s of 10, after both pre-approved levers: ram
  `exit_speed` 560, `engage_seconds` 4.0). Boundaries: a ram at 76.0 + 1.2 s, a ram forced to expire on its first
  LINE_UP tick, and a Bomber in an ENEMIES_CLEARED section (none may contain one).
  `tests/integration/test_level1_specialist_exit.gd` replays the whole of cloud_descent from 0.0 s with only its 9 snipers
  and 6 rams, through a real `WaveManager` at 8× clock. The container must empty inside the timeout, and every ship
  must leave in DISENGAGE with no `EnemyPathMover`.
  **Every Phase 4 specialist also has an attack-in-budget row** (`test_sniper.gd`, `test_ram_corvette.gd`,
  `test_bomber.gd`): from every level-1 spawn class, through a real `WaveManager`, it reaches its attack state (Sniper
  AIM, Ram WIND_UP, Bomber RUN) before its Assault budget expires, one attack per life. A budget counts from spawn, so a
  density or deadline lever (ram `exit_speed` / `engage_seconds`) is legal only while those rows stay green. Behaviour
  specs for the three (`test_sniper.gd`, `test_ram_corvette.gd`, `test_bomber.gd`, `test_enemy_ordnance.gd`, plus their
  cases in `test_enemy_dual_mode.gd` and `test_sector_hub_patrol.gd`) are intent tests in both harnesses; the
  primitives under them have `test_armor_query.gd`, `test_line_of_sight.gd`, and the `ContactProfile` ARMOR /
  `BulletPool.persist_after_owner_death` rows in `tests/unit/`.
  The Phase 5 enemy rockets (`EnemyRocket`, `assault/scenes/projectiles/enemy_rockets/`) have an intent spec,
  `tests/integration/test_enemy_rockets.gd`: guidance and dodging hand-ticked in both harnesses, and real-physics rows
  for shoot-down, friendly fire (impact hurts enemies, plates and asteroids; the real player scenes take the blast only)
  and the pool hand-over. t6 adds the Cluster split (exactly at `split_distance`, at `split_time`, a 36° fan of 4 unpooled
  self-freeing submunitions, no blast, nothing if shot first, survives a freed launcher) and the Delayed Warhead
  (poll-armed trigger, stops dead, blinks, fairness (trigger + blast) / warning >= 420 and the 420 / 700 px/s crossers);
  their lifetime rows are in `test_enemy_bullet_lifetime.gd`.
  `tests/integration/test_missile_corvette.gd` (t7) covers the Missile Corvette shell: pool sizes 3 / 6 / 3 / 4 pinned and equal to `pool_size_for`, `fire()` alternating tubes without touching a rocket field, the rail fallback, a real corvette on a 330 px/s rail never hitting itself (8x), `launch_velocity()` observed per physics tick, and the Assault budget exit; the rocket inequality rows in `test_enemy_rockets.gd` now read `missile_corvette_config.tres`. t8 adds the fight, hand-ticked in both harnesses: range held on a broad arc from 1200 px, a 200 px/s rush kept at bay and a 350 px/s one sidestepped by the min-range break-off, orbit reversals, no salvo at a player behind the nose (with an in-front control), salvo shape per kind (3 / 3 / 3 / 2 at `salvo_gap` after `salvo_telegraph`, CHARGING -> ARMED -> OFF, tow refused), Dumb aim points along the predicted path, kind choice and the 1-in-4 swap, the Warhead pair 180 px across the path, the Assault gate at 1.2 / 1.17 / 1.0 s and the deferral bound, the Open Space-only cancel, the tube glow and the turn inequality.
  `tests/integration/test_support_ship.gd` (t10) covers the Support Ship shell (`assault/scenes/enemies/support_ship/`): one r 34 circle shared by body, hurtbox and contact box, a folded `Projector` and a hidden world-space `Tether`, every plan §2.11 config field, a `ContactProfile` in mode NONE that deals 0 on touch in both harnesses (with a control that an opened box does hurt), `can_be_repaired()` false, holding `follow_distance` from the nearest live ally (never another support), the Assault budget's DISENGAGE, and `suspend_ai()` folding the projector and dropping the ward. t11 adds the ward rows, dual-mode and hand-ticked: the §2.12 filter (bomber over fighter, a hurt fighter by the player wins, never a support, a railed enemy, a claimed ward, a lone swarm drone, a non-combatant, or a real Bonus Drone beside a fighter (Ph10 t4: a real Heavy Gunship beside them is the ward); the 890 / 910 px search edge), 1.2x never / 1.4x after `min_ward_seconds`, a new ward the tick after the old one is freed, killed or railed, the Assault grace (from entering the view), the soft anchor, the jink (control: none), evasion of a 200 px/s stub over four seeds (control: `evade_speed` 0 is caught) and the Assault view clamp with `is_supporting()` read the same frame the camera `offset` pans.
  The Phase 5 shield, tow and view gates: `tests/unit/test_enemy_shield.gd` (the component: arc, capacity, break, reboot,
  regeneration, sustain/lapse, the local-module fixture row) and `tests/integration/test_enemy_shield_hits.gd` (real bullets,
  missiles, rockets and an armoured host against a shielded hurtbox; direct emitters bypass it); `tests/integration/test_base_enemy.gd`
  §6 (`repair()` never flashes, `accept_tow()` refused unless `is_ai_driven()` and `EnemyBrain.accepts_tow()`) and
  `tests/unit/test_enemy_world.gd` (`EnemyWorld.view_rect()` / `ArenaCamera.enemy_view_rect()`). The level-1 placement of the two
  enemies adds `EXPECTED_PH5` and the corvette / support attack-in-budget rows to `test_level1_specialist_spawns.gd`, a replay helper
  `tests/helpers/level1_slice_replay.gd`, and "no `ENEMIES_CLEARED` section holds a corvette or a support" rows in
  `test_engagement_deadline.gd`. `scripts/gate-time.sh` times the three gate steps and the slowest test files; every Phase 5 task
  reported before / after (see `tests/README.md` → *Gate time*), and GUT time must stay <= 240 s. **The whole gate output must stay well under 1 MiB** (the harness reads it through Node `exec`, whose default `maxBuffer` kills a longer gate with every test green; the script's `output` line; Phase 10 t5).
  The Phase 3 behaviour specs for the Fighter and the Gatling (`test_fighter.gd`, `test_fighter_squad.gd`,
  `test_gatling_interceptor.gd`, `test_gatling_convergence.gd`, plus their cases in
  `test_enemy_dual_mode.gd`) are intent tests that run in both the Assault and Open Space harnesses.
  A few characterization files also carry individually-marked intent tests
  (`test_health_component.gd`, `test_state_machine.gd`, `test_ship_module_state.gd`); each says
  so in a comment.
  **Read [`tests/README.md`](tests/README.md) before writing a
  test** — it covers the `user://` save-file sandbox, the signal-arity trap, and the
  `LevelDirector` coroutine-leak trap, all of which cause failures (or silent leaks) unrelated to
  the code under test.
- **Resource UIDs — never run the Godot MCP `update_project_uids` tool.** As the MCP calls it it
  is a silent no-op (it searches `res:///work/repo/` and reports success); pointed at `res://` by
  hand it resaves every scene and strips all UIDs and all comments. Use
  `tests/integration/test_resource_uid_integrity.gd`, which reports instead of rewriting; the
  reasoning is in [tests/README.md](tests/README.md).
- **Never hand-type a `uid://` and never copy one from a sibling file.** A copy is a duplicate
  declaration; a typed one is usually an *alias* decoding to a UID another resource owns, and both
  fail silently. Leave the reference UID-less (legal — Godot falls back to the path) or mint one
  with the headless `ResourceUID.create_id()` snippet in [tests/README.md](tests/README.md).
- **`agent/auto-dev` is the working branch for all Claude work**, whether that is an AI-Kanban
  run on the NAS or an interactive session. You do not need to ask to commit there.
  - Check you are on it first (`git branch --show-current`). If you are not, switch — do not
    start committing wherever you happen to be.
  - **Get a green gate before you commit**: `bash /agent/verify.sh` in the container, or
    `godot --headless --path . --import` plus the GUT suite locally. Never commit work you have not
    verified.
  - **In an AI-Kanban run, do not push.** The worker has no GitHub credentials; the harness runs
    the same gate after you and commits whatever you left, only if it passes. The owner pushes.
    In an interactive session, commit and push as usual — don't leave finished work sitting
    uncommitted for the user to stage by hand.
  - Write a real commit subject that names what changed.
  - No other branches and no worktrees unless asked.
  - **`main` stays off-limits.** Never commit to it, never push to it, never merge into it,
    never force-push or rewrite history on any branch. **The user merges `agent/auto-dev` to
    `main` by hand — that is the only human-only git operation here.**

## Where things live

- Shared components / autoloads / ship modules → `global/` (map: [global.md](docs/architecture/modules/global.md)).
- **How to wire a component (Health/Hurtbox/Shield/state machine/ship module) into an
  entity** → the integration recipes in [global.md](docs/architecture/modules/global.md).
- Per-entity behaviour → `RACER.md` / `ENEMY.md` / `HAZARD.md` **beside each entity**
  (`assault/scenes/race/racers/*/`, `assault/scenes/enemies/*/`, `assault/scenes/hazards/*/`).
- Spawning enemies via `WaveBuilder` → [`docs/enemy-roster.md`](docs/enemy-roster.md).
- Game loop / mode transitions → [`docs/game-structure.md`](docs/game-structure.md).
- **What a shared component actually does, edge cases included** → its test in `tests/unit/`
  (one file per component and per autoload). Faster and more precise than re-reading the source.

## MANDATORY — generating game art

Before generating **any** sprite, tile, or other asset with PixelLab, invoke the
**`pixel-art-generation`** skill. `assault/` and `open_space/` are **strict top-down
orthographic and NEVER isometric** — the skill enforces this with explicit PixelLab
parameters (`view: "high top-down"`, `isometric: false`), not just prompt wording. It also
covers tool choice per asset type, safe binary saving via `scripts/pixellab.sh` (the Write
tool corrupts PNGs), and the mandatory visual check on every generated image.

`infiltration/` is the one genuinely isometric mode and is out of scope for that skill.
A wrong-angle sprite cannot be fixed in code; it has to be regenerated. Do not skip the check.

**Use PixelLab freely.** The plan gives about 1,500 generations a month and the project uses a
handful a week. Generate candidates for important art, regenerate what is wrong, and refine what
is only acceptable until it is good; do not settle for the first result to save generations. The
skill's §5 and §7 say how far to go and when to stop.

## MANDATORY — match the process to the work

Invoke the **`feature-workflow`** skill at the start of every work item. It is a router, not one
fixed pipeline: it reads the item's `kind`, `type` and `complexity` and picks how much process the
work actually warrants.

- **Preparation** (an epic's research / plan / plan-review tasks) — the full pipeline: read the
  code, research how shipped games solve the same problem, write a plan to `docs/plans/<epicId>/`,
  have an **independent subagent review it**, then hand the epic to the user for approval.
- **Direct** (small and medium implementation) — the epic's plan is already written, reviewed and
  approved, so: failing test → implement → verify. No new plan, no second review.
- **Escalated** (large or architectural implementation) — its own plan directory and its own
  independent review before any code.

Implementation of a large item starts only on `VERDICT: APPROVED`. A rejected plan is a legitimate
outcome: it means wrong work was avoided cheaply.

**Running the heavyweight pipeline on a one-line fix is as much a failure as skipping it on a
system change.** If a small item turns out to need architectural work, stop and end the run with
`Result: ESCALATE` and why (see the `feature-workflow` skill) rather than quietly switching
tracks — the owner re-sizes the task on the board, so it shows what is actually happening.

## MANDATORY — keep the docs current

After **any structural change** to scenes or scripts — adding, renaming, moving, or
deleting an **entity, component, module, or mechanic** — you **MUST** invoke the
**`updating-project-docs`** skill before finishing the task. It walks you through updating
the affected module doc, `docs/architecture/PROJECT.md`, the relevant per-entity doc, and
this file. Do not skip it; the knowledge base only stays useful if it is updated alongside
the code.
