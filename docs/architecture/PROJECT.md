# Project Knowledge Base

Authoritative map of the project's structure and game mechanics. This is the source of
truth that `CLAUDE.md` and the per-module docs derive from.


> A space action game built in **Godot 4.6 (Forward+)**. The player cycles between three
> distinct gameplay modes — a fast autoscroller shmup (**Assault**), a free-flight hub
> with mission select (**Open Space**), and isometric ground combat (**Infiltration**) —
> connected through a persistent hub and a boot/cutscene shell. Gameplay systems are
> isolated **per game mode**; all shared, reusable logic lives in a dedicated **global**
> module.

---

## Game loop

```
First launch:  Boot → Intro Cutscene → Assault L1 → Level-Exit Cutscene → Infiltration
Every launch:  Boot → Open Space Hub → (select mission) → play → return to Hub
```

`boot/boot.gd` routes the first frame: on first launch (checked via
`MissionState.has_cutscene_been_seen("intro_to_assault")`) it plays the intro cutscene,
otherwise it loads the Open Space hub. Full detail: [`docs/game-structure.md`](../game-structure.md).

---

## Module map

| Module | Path | Role | Doc |
|---|---|---|---|
| Assault Mission | `assault/` | Autoscroller shmup; hosts the race sub-mode | [assault.md](modules/assault.md) |
| Open Space | `open_space/` | Persistent hub world + mission select | [open_space.md](modules/open_space.md) |
| Infiltration | `infiltration/` | Isometric ground combat | [infiltration.md](modules/infiltration.md) |
| Global (shared) | `global/` | Components, entities, ship modules, state machine, pickups, interactables, resources, UI, autoloads | [global.md](modules/global.md) |
| Shell | `boot/`, `cutscenes/`, `dialog/` | Boot entry, cutscenes, dialog data | [shell.md](modules/shell.md) |
| Tests | `tests/` (+ `addons/gut/`) | GUT suite over the autoloads and `global/` | [tests/README.md](../../tests/README.md) |

The codebase is organised **by game mode**: each module holds only its mode-specific
scripts, scenes, and assets. Anything reused across modes belongs in `global/`.
`tests/` is not a gameplay module — it mirrors `global/` and is never imported by game code.

---

## Autoloads

Registered in `project.godot` `[autoload]` (load order matters). Full detail in
[global.md](modules/global.md).

| Autoload | Script | Responsibility |
|---|---|---|
| `MissionState` | `global/autoloads/mission_state.gd` | Mission completion, scores, and "cutscene seen" flags — persisted progression |
| `DialogPlayer` | `global/autoload/dialog_player.gd` | Plays `DialogScriptResource` dialogue; `is_active` gates gameplay input |
| `UpgradeState` | `global/autoloads/upgrade_state.gd` | Which main-weapon modes are unlocked. `STARTING_IDS` seeds a fresh profile; a `WeaponModeUnlockerPickup` in the world is the only other way in |
| `EventBus` | `global/systems/event_bus.gd` | Global typed signals (decoupled cross-system events) |
| `ShipModuleState` | `global/autoloads/ship_module_state.gd` | Which ship modules are equipped per slot, and which are unlocked — `equip()` refuses a locked module |
| `ShipProgressionState` | `global/autoloads/ship_progression_state.gd` | Ship progression / unlocks |
| `SessionState` | `global/autoloads/session_state.gd` | Per-run session data |
| `CameraShake` | `global/systems/camera_shake.gd` | Global camera-shake requests |
| `LogState` | `global/autoloads/log_state.gd` | Which lore-log entries are collected. Total is derived from a `LogEntryResource` `.tres` directory sweep, never hand-counted; `collect_next()` grants entries in catalogue order |
| `PickupState` | `global/autoloads/pickup_state.gd` | Which `persistent_id`-tagged `PickupBase` placements have ever been collected, independent of the physical node — so a one-time pickup placed in a replayable mission (assault restart reloads the scene) doesn't re-grant on reload. Opt-in: a pickup that leaves `persistent_id` empty (every pickup today) ignores this entirely |
| `SettingsState` | `global/autoloads/settings_state.gd` | Player-chosen settings. First key: `open_space_scheme` (`&"mouse"` / `&"keys"`), read by `OpenSpacePlayerShip` to seed and live-update its `ShipTurnController`; set by the ESC menu's Settings panel |

---

## Shared systems (`global/systems/`)

- **`EventBus`** — global signal hub; emit/connect for cross-system events without hard refs.
- **`CameraShake`** — `CameraShake.add(amount)` to shake the active camera.
- **`CameraDirector`** — camera framing/targeting helper.
- **`BackgroundController`** — parallax/scroll background driver (used by Assault & the race mode).

Detail and APIs: [global.md](modules/global.md).

---

## Conventions

- **Engine:** Godot 4.6, Forward+ renderer. Viewport 1280×720; window override 1920×1080.
- **Composition over inheritance:** entities are assembled from `global/components/`
  (Health, Hurtbox/Hitbox, Shield, Overheat, DamageReaction, effects). See the
  **integration recipes** in [global.md](modules/global.md) for how to wire them.
- **Config-driven enemies:** assault enemies read stats from a `*_config.tres`
  (`Resource`) applied in `_ready()`; the `.tres` value wins over the scene's Health node
  where they differ. The exception is `collision_damage`: the scene-authored `ContactHitBox`
  node defaults to `damage = 20` and knows nothing about the config, so each enemy must
  re-apply it in `_ready()` off `contact_hit_box`, or author a different default directly on
  its own scene node. `tests/integration/test_enemy_contact_damage.gd` asserts the whole
  roster does.
  Each entity holds a **private copy** of its config: `ShipConfig.privatise()` duplicates it from
  `BaseEnemy._init()`/`_enter_tree()` (and `AllyFighter`'s), because `ResourceLoader` caches by path
  and every entity of a type would otherwise share one object with each other and with every
  `preload()` in the test suite. Details and the two remaining windows: the `ShipConfig` section of
  [global.md](modules/global.md); pinned by `tests/integration/test_config_instance_isolation.gd`.
  **The object `load()`/`preload()` returns is still shared — never write to it.**
- **An AI-driven enemy has one writer of its motion.** When an enemy carries an `EnemyMover`
  (`global/enemy_ai/enemy_mover.gd`), that mover is the only writer of its `velocity` and `rotation`
  and the only caller of `move_and_slide()`; its `EnemyBrain` only *requests* movement, on the one
  physics tick `BaseEnemy._physics_process` owns. Rails (`EnemyPathMover`) take over through
  `suspend_ai()`. Recipe: [global.md](modules/global.md) → *Enemy AI*; gated by
  `tests/integration/test_enemy_mover_single_writer.gd`.
- **Touching an enemy is governed by an explicit contact profile, not a hard-coded hitbox.**
  `ContactProfile` (`global/components/contact_profile.gd`) is the offensive twin of
  `DefenseProfile`: `NONE` (no hitbox), `COLLISION` (today's always-on hitbox, the default —
  every legacy enemy), `RAMMING` (the hitbox is live only while the brain calls `set_armed(true)`)
  `ARMOR` (Ph4: armed from `setup()`, never detonates and never hurts its owner, with an optional `shove_speed` that hands the touched ship an `apply_knockback(impulse)`) or `EXPLOSIVE` (RAMMING, plus a `ContactBlast` — a separate `HitBox` re-homed into the *owner's
  parent* so it survives the owner's death, following `ExplosionEffect`'s pattern, since a child
  node dies with its parent in the same frame it would need to be detected in). `BaseEnemy.
  suspend_ai()` arms the profile, so a rail-driven rammer still hurts on contact. Recipe:
  [global.md](modules/global.md) → *ContactProfile and ContactBlast*.
- **Drones and fighters in a group share roles through a board, not a message bus.** `SquadController`
  (`global/enemy_ai/squad_controller.gd`, `RefCounted`) assigns `LEAD`/`FLANK_LEFT`/
  `FLANK_RIGHT`/`REAR` and reassigns them the instant the lead leaves — it moves nothing itself,
  members read it and request their own motion, so it never touches the single-writer rule above.
  `AnchorIdle` (`global/enemy_ai/anchor_idle.gd`) is the generic hysteresis-gated idle-around-an-
  anchor → combat handover any brain can own (Assault skips it — the level has already decided
  the fight is on), and a squad-wide version of it (`SquadController.set_engaged`/`is_engaged`)
  is how a whole hub patrol wakes and returns together. Recipes: [global.md](modules/global.md) →
  *SquadController*, *AnchorIdle*.
- **A shooter taken off its brain by a rail keeps firing its legacy weapon (Ph3).** `FighterBrain` and
  `GatlingInterceptorBrain` implement `on_suspended()` to leave their squad, switch their `StateLight` off, hand their
  `AttackController` back to self-timed fire and install a legacy-equivalent pattern **built from flat `rail_*` config
  fields** — so level 1 and the station's reinforcements stay armed on a path while level 1 itself no longer uses
  rails for these two. `aim_mode` / `shoot_forward()` / `shoot_at_player()` are rail-only inputs. Ph15 applies the same
  rule to every other shooter it migrates. Recipe: [global.md](modules/global.md) → *Enemy AI*.
  Ph4 extended the rule to the Sniper (`SniperTelegraph`'s own rail cycle at the legacy timings, never writing
  rotation), the Bomber (a root `_process` clock dropping gravity bombs straight down) and the Ram Corvette (its ARMOR
  contact stays armed).
- **Armour is a deflection rule on a full-size hurtbox, built from breakable parts (Ph4).** An armoured enemy keeps one
  full-size `HurtBox` and answers `is_armored()` / `deflects_hit(hit_box)`; the breakable parts are `ArmorPlate`s
  (`global/components/armor_plate.gd`) under a group node (`Plates`), never direct children of the enemy root, so the
  hurtbox-geometry gate still sees one hurtbox covering the body. A plate breaks on a rocket, or on a projectile that
  answers `is_high_impact()` (the player's Sniper Shot), and glances off anything else. A mask-based armour is rejected:
  it silently consumes bullets. Recipe: [global.md](modules/global.md) → *Armour that deflects bullets but breaks to rockets*.
- **An enemy can break contact and can ask whether a rock is in the way (Ph4).** `Steering.break_contact()` /
  `EnemyMover.break_contact()` back away from a threat at an angle, and `TargetInfo.line_of_sight()` casts a real ray
  through `LineOfSight` (`global/enemy_ai/line_of_sight.gd`): only the group `asteroids` or a collider answering
  `blocks_line_of_sight()` blocks it. Recipe: [global.md](modules/global.md) → *Enemy AI*.
- **Ordnance outlives its owner without breaking the one-owner rule (Ph4).** `BulletPool.persist_after_owner_death`
  hands every in-flight projectile over to self-freeing when the owning ship leaves the tree; the Bomber's gravity
  bombs, mines and pursuit bombs (`assault/scenes/projectiles/enemy_ordnance/`, `EnemyOrdnance`) are the first user; the Mine Layer (Ph7) is the second, its mines being `EnemyMine` (see *Mines, minefields and the Mine Layer* below).
  Ordnance is not an `EnemyBullet` and not a `BaseEnemy`: never in `enemies`, never scored, and any player hit defuses
  it. Detail: [assault.md](modules/assault.md) → *Projectiles & bullet pool*; [BULLET_POOL.md](../BULLET_POOL.md).
- **Enemy rockets hurt enemies by impact and the player by blast only (Ph5).** `EnemyRocket`
  (`assault/scenes/projectiles/enemy_rockets/`) puts its impact `HitBox` on layer 32 alone, which enemy, ordnance,
  plate and asteroid hurtboxes see and the player's does not; the `ContactBlast` it leaves is the player's only damage.
  A rocket arms only once clear of its launcher's current position, inherits the launcher's speed along its heading,
  and is shot down (no blast) by any player bullet or missile. Tuning lives in each rocket scene's exports. Detail:
  [assault.md](modules/assault.md) → *Projectiles & bullet pool*.
  One rocket is one hit against the player: the impact box never reaches the player's layer, so only the blast (layer 256,
  one hit through the player's 0.5 s i-frames) hurts. A player bullet or missile and a rocket destroy each other, rockets ignore
  each other, and an armoured hull lets a rocket through (`ArmorQuery`). Persistent rocket pools set
  `persist_after_owner_death`; cluster submunitions are unpooled and free themselves.
- **Enemy shields are a temporary resource on a `HurtBox` absorb hook, not a second health bar (Ph5).** `EnemyShield`
  (`global/components/enemy_shield.gd`) attaches through `HurtBox.set_absorber()`; its arc (360° = bubble), capacity,
  regeneration, reboot and lifetime are fields. A hit it absorbs emits `hit_absorbed` instead of `received_damage`, and a
  shielded enemy **consumes** a default player bullet (the shield counts as the hit, unlike a deflection). It never absorbs
  while its host answers `is_armored()`. Direct emitters (beam, nova, dash, overload, boost) bypass it as they bypass armour
  plates. `BaseEnemy` does **not** adopt `DamageReaction` (Ph1 P-15, closed in Ph5): `DamageReaction` stays a racer component.
  Allies act on enemies through `BaseEnemy.repair()` (never flashes) and `accept_tow()` (refused by the target's own brain in
  committed phases via `EnemyBrain.accepts_tow()`). Detail: [global.md](modules/global.md) → *Enemy shields*.
- **A large enemy is built from destructible parts that stay as wreckage (Ph10).** Each part is an `EnemyModule`
  (`global/components/enemy_module.gd`, group `enemy_parts`) under the host's `Modules` node, with its own `HurtBox`, `Health`,
  optional `DefenseProfile` and local `EnemyShield`; `ModularHull` (`global/components/modular_hull.gd`) collects them, forwards
  `hull_share` to the host and re-emits their signals. A part takes damage only through its `received_damage`; a locked part
  ignores every damage (the only guard against the beam, the nova and a `LaserRay`); a part killed this physics frame still
  consumes its killing shot; a destroyed part leaves `enemy_parts`, closes its hurtbox and stays on the hull with its wreck sprite.
  The player's beam and nova reach parts; enemy energy weapons do not. Recipe: [global.md](modules/global.md) → *Destructible
  parts of a large enemy*.
- **An enemy picks a round, it does not retune one bullet (Ph3).** The pooled `EnemyBullet` family —
  Pulse, Scatter, Gatling Stream, Rail (the Sniper's, Ph4), Heavy Shell (`assault/scenes/projectiles/enemy_bullet/rounds/`, `EnemyRounds`) — are
  inherited scenes of `enemy_bullet.tscn`, each with its own `ProjectileLifetime`; `EnemyBullet.reset()` restores the
  scene's authored speed and damage. **One pool per round per shooter, a direct child of the enemy root** (a pool under
  a controller would carry its live bullets with the ship), sized with `EnemyRounds.pool_size_for()` for the AI burst
  *and* the rail cadence. Every round's range must fit its lifetime at the slowest speed any shooter fires it at, read
  from config fields (`tests/integration/test_enemy_bullet_lifetime.gd`). Detail: [assault.md](modules/assault.md) →
  *Projectiles & bullet pool*; [BULLET_POOL.md](../BULLET_POOL.md).
- **A burst has an exact size, and "forward" is the nose.** `BurstClock` (`global/enemy_ai/burst_clock.gd`) is the one way
  a brain sequences N shots at a gap — never a free-running interval timer — and
  `EnemyMover.sprite_forward_angle_of(node)` is the one reader of an actor's `sprite_forward_angle`, so a "fire forward"
  pattern leaves the nose whichever way the art was drawn. A weapon mode is chosen **by distance, with hysteresis,
  latched for the whole burst — never by a spawn property**. `DubinsPath` plans an attack run's lead-in. Recipes:
  [global.md](modules/global.md) → *BurstClock*, *DubinsPath*.
- **A formation is a spawn layout; the squad board decides roles.** `WaveBuilder`'s V / W / wedge / line / diagonal /
  cluster only place ships in time and space; an AI enemy then reads its role (LEAD, FLANK_LEFT/RIGHT, REAR) from its
  `SquadController` and the layout is forgotten. At most three fighters attack at once (LEAD + the two flanks); a
  fourth and later are REARs. A Gatling pair shares `SquadController.convergence_point` / `convergence_stage`.
- **An Assault AI enemy leaves the arena on a budget, not when killed.** `EngagementBudget`
  (`global/enemy_ai/engagement_budget.gd`) is active only in Assault (`EnemyWorld.arena(tree) !=
  null`); on expiry the brain releases its movement constraint, raises its exit speed, and seeks
  the nearest point **outside `EnemyWorld.projectile_world_rect()`**, freeing itself once strictly
  past that edge — the corridor constraint otherwise forces re-entry forever, so without this an
  AI drone would live until killed and stall a level's `ENEMIES_CLEARED` section. Scored as an
  escape, same as a legacy rail enemy leaving the bottom of the screen. Recipe:
  [global.md](modules/global.md) → *EngagementBudget*.
- **`EnemyMover.max_turn_rate` turns the sprite only — a curved path is always a brain-side
  request.** `step()` moves `velocity` by `move_toward`, so bending a path (an overshoot after a
  missed attack, a wide turn-back) means calling `Steering.turn_toward(current_dir, desired_dir,
  max_rate, delta)` every tick from the actor's *current* velocity; the true heading then turns by
  at most `max_rate·delta` per tick, and a config that curves pins `turn_rate × speed ≤
  acceleration` so the mover can keep up. Recipe: [global.md](modules/global.md) → *Enemy AI*.
- **An enemy telegraphs its own attack state with one small light, never a recoloured hull.**
  `StateLight` (`global/components/state_light.gd`) is OFF / ARMED (red) / CHARGING (yellow) /
  COMMIT (white); COMMIT is reserved for a real, committed attack, so a feint or a fake can only
  ever show CHARGING. Its texture is a radial gradient built in code, never scene-authored, so it
  never trips the sprite-transparency gate below. Recipe: [global.md](modules/global.md) →
  *StateLight*.
- **Brains tick on physics, on one clock, with no `Timer` nodes.** `BaseEnemy._physics_process`
  calls `brain.tick(delta)` then `mover.step(delta)`, once per physics frame; a brain's clocks are
  accumulated `delta` values and its randomness comes only from its own seeded `rng`
  (`RandomNumberGenerator`), never the global RNG — `StateMachine` ticks in `_process` instead, and
  GUT's `simulate()` never fires a `Timer`. (The separate `"AIStateMachine"` name-lookup suspension
  `EnemyPathMover` still performs unconditionally existed for the old Light Assault Ship; since Ph3 it has no
  subject, is pinned on a test fixture, and is left for Ph15.)
- **The mode (Assault vs. Open Space) is declared by the world, found by duck type.**
  `ArenaCamera` joins group `&"assault_arena"`; `EnemyWorld` (`global/enemy_ai/enemy_world.gd`) is
  the *only* code that looks that group up, and does so via `has_method` rather than importing the
  Assault-only `ArenaCamera` class — nothing under `global/` may reference it by name. With no
  provider in the tree the mode is Open Space: no projectile rect, no cull rect, no movement
  constraint. See [global.md](modules/global.md) → *Enemy AI* and
  [assault.md](modules/assault.md) → *Enemy AI in Assault*.
- **Every physics collision layer bit in use has a name.** `project.godot [layer_names]` is the
  single place a bit gets a human name — Godot never checks that a bit actually used in a scene or
  resource has one — and `global/physics/collision_layers.gd`'s `CollisionLayers` mirrors it with
  one constant per named layer (`1 << (n-1)`), so code refers to a layer by name instead of a magic
  number. No layer's numeric value changes when it is named. Gated by
  `tests/integration/test_collision_layer_names.gd`, which sweeps every `.tscn`/`.tres` outside
  `addons/` for an unnamed bit and checks every named layer has a matching constant.
- **The mouse is read in exactly one line project-wide.** `player_ship.gd::_handle_rotation`'s
  `get_global_mouse_position()` is it. Everything downstream — the whole open-space turn model in
  `ShipTurnController` (see [open_space.md](modules/open_space.md) §3.2.1) — takes the cursor as an
  injected `Vector2`. This is not style: `Input.warp_mouse()` cannot place a cursor in a headless
  GUT run, so any logic that reads the mouse itself is untestable by this project's gate. Use
  `get_global_mouse_position()` (a `CanvasItem` method that honours the canvas transform and the
  project's `stretch/mode="canvas_items"`), never `DisplayServer.mouse_get_position()`.
- **One writer per transform.** In open space, `ShipTurnController` is the only thing that writes
  the player ship's `rotation`; a second writer (a ship module, a state) fights it invisibly at
  frame rate. Anything that needs to turn the ship goes through the controller's `face_instant()`.
- **State machines:** `global/statemachine/state_machine.gd` + `state.gd`; entities with
  complex behaviour keep one `State` node per file in a `states/` folder (player, racers).
  Enemies use a brain (`EnemyBrain` + `EnemyMover`) or in-script `enum` phases; the Fighter's `states/` folder was
  deleted in Ph3.
- **Signal arity:** a signal is declared with exactly the arguments it is emitted with.
  Godot does not enforce this — `Health.amount_changed` and `State.state_transition` were
  declared with zero parameters and emitted with one until 2026-09-03 — but a mismatch makes
  every handler's shape a guess, and a zero-argument handler on a one-argument emit is a
  hard runtime error. Pinned by `test_health_component.gd::test_amount_changed_declares_the_int_it_emits`
  and `test_state_machine.gd::test_state_transition_declares_the_state_it_emits`.
- **Logging:** anything that can print more than once per frame or once per hit goes behind
  `if OS.is_stdout_verbose():` — `Health.decrease()`, `StateMachine.change_state()` and
  `DialogPlayer` all do. Run Godot with `--verbose` to get the traces back. `push_warning` /
  `push_error` stay unconditional: they are for things that should not happen.
- **Coordinates:** waves and spawn offsets are authored in **design units** (640×360
  space) and scaled by `ArenaCamera.WORLD_SCALE` (2.0) at runtime — never pre-multiply.
- **Unlockable content needs a source in the world.** `ShipModuleState` and `UpgradeState` are
  both written only by a `PickupBase` subclass placed in a level —
  `ShipModuleUnlockerPickup` and `WeaponModeUnlockerPickup`, both benched in
  `open_space/scenes/levels/sector_hub.tscn`. Nothing else calls `unlock()`, so an entry added to
  `ShipModuleState.SLOT_MODULES` or `UpgradeState.ALL_IDS` without a matching pickup is content
  the player can see in the ship menu and can never reach, with no warning at runtime. That is how
  four tuned weapon modes sat unreachable behind a one-row weapon column. Both pairings are
  invariant-tested (`tests/integration/test_module_unlock_sources.gd`,
  `tests/integration/test_weapon_unlock_sources.gd`); the only exempt ids are
  `UpgradeState.STARTING_IDS`, which a fresh profile is seeded with.
- **Projectile lifetime — every projectile has exactly one owner.** Either a `BulletPool`
  recycles it (`docs/BULLET_POOL.md`: *the pool is smart, bullets are dumb*), or it frees itself
  when it leaves the world. There is no third option, and "nothing frees it" is the bug this rule
  exists to prevent: the player's bullets had no owner at all, so every shot ever fired stayed in
  the level for the whole mission. Player bullets go through `WeaponBehavior._launch()`, which
  calls `Bullet.free_when_offscreen()` and connects `Bullet.expired -> Bullet.queue_free`. **A
  default bullet stops on the first hit that actually deals damage; a *deflected* hit does not
  count** — `bullet.gd::_hit_is_deflected()` asks `ArmorQuery.deflects()`, which duck-types `deflects_hit(hit_box)` (hit-aware; `ArmorPlate`) and falls back to `is_armored()` on the hit
  target and, if it returns `true`, the bullet keeps flying at full damage with no pierce charge
  spent. This exists because the space-station boss's armoured core spans the whole hull, so a
  shot aimed at a turret has to survive crossing it undeflected, or the turrets — and the boss —
  are unkillable. The Ram Corvette's plates use the hit-aware `deflects_hit()` (rockets and `is_high_impact()`
  projectiles break a plate, bullets glance off) and `ArmorQuery` is the one place all three player projectiles
  (bullet, homing rocket, warhead) ask; a later heavy weapon opts in by answering `is_high_impact()`. `PierceModule` raises the number of damaging hits a bullet survives before it
  stops. An **enemy shield** is not a deflection: a hit its `EnemyShield` absorbs (through the `HurtBox` absorber
  slot, `hit_absorbed` instead of `received_damage`) **consumes** the bullet and the hull takes nothing; direct
  emitters (beam, nova, dash) bypass it (`global.md` → Enemy shields). Player bullets despawn at the *viewport* edge and `EnemyBullet` at the *arena* bound;
  that asymmetry is deliberate, because the player's weapons are also mounted in Open Space, which
  has no `ArenaCamera`. Gated by `tests/integration/test_player_bullet_lifetime.gd`.
- **Testing:** **GUT 9.7.1**, vendored in `addons/gut/`, enabled from the
  `[editor_plugins]` section of `project.godot`. Tests live in `tests/` and run headless:
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`.
  The suite is almost entirely **characterization**: it pins behaviour as it is today, bugs
  included, so any behaviour change shows up as a failing test rather than as silence. The
  exceptions are the integrity tests — `tests/integration/test_resource_uid_integrity.gd`
  (every `[ext_resource]` UID matches the UID its target declares, resolves to a file that
  actually declares it, is not claimed by two files at once, and the same for the UID-only
  references in `project.godot` / `export_presets.cfg`),
  `tests/integration/test_suite_integrity.gd` (every `tests/**/test_*.gd` compiles and extends
  `GutTest`, because GUT otherwise drops an unloadable test script with only a warning and still
  exits 0), `tests/integration/test_gut_local_patches.gd` (the two local patches
  `addons/gut/LOCAL_PATCHES.md` documents are still applied, since re-vendoring GUT drops them
  and the resulting breakage is silent) and `tests/integration/test_project_load_integrity.gd`
  (every `.tscn`/`.tres`/`.gd` outside `addons/` loads, instantiates and compiles, and the engine
  logs nothing while it happens — the gate's `--import` step never loads a scene at all and its
  `--quit` step boots only `res://boot/…`, so everything reachable only from an assault level,
  the race sub-mode, the hub or infiltration was previously unloaded by any gate step)
  and `tests/integration/test_enemy_contact_damage.gd` (the only one over **balance data**:
  every assault enemy's contact `HitBox` deals the damage its `*_config.tres` declares, which
  is otherwise dead the moment a subclass forgets the re-apply above)
  and `tests/integration/test_contact_hitbox_geometry.gd` (its geometry companion: a contact
  `HitBox` must carry the body `CollisionShape2D`'s transform, not just its `Shape2D` — copying
  the shape alone drops the scale that sizes it, so the gunship rammed with an 18 px box against
  a 41.5 px hull)
  and `tests/integration/test_entity_sprite_transparency.gd` (the only invariant over **art**:
  no texture an entity under `assault/scenes/{enemies,player,projectiles,hazards,allies}` draws
  over the game world may be 90%+ fully opaque, because a painted-in background renders as a card
  that cuts a hard rectangle out of the starfield — `station_core.png` shipped at 100% and no
  gate step could see it, since `--import` loads no scene and `--quit` boots only `res://boot/…`.
  It reads scenes through `PackedScene.get_state()` rather than instantiating them, and resolves
  `Sprite2D.texture`, `AnimatedSprite2D.sprite_frames` and `AtlasTexture.atlas` — a
  `Sprite2D`-only walk finds 9 textures and four of the five roots contribute nothing)
  and `tests/integration/test_enemy_hurtbox_geometry.gd` (the other side of the same collision
  pair: every assault entity's `HurtBox` must **cover** its body `CollisionShape2D`, so armour is
  a damage *rule* on a full-size hurtbox and never an absent one — it carries a permanent
  boundary test that applies the rejected "narrow the station core to 88 x 240" proposal to a live
  instance and asserts it fails)
  and `tests/integration/test_player_bullet_lifetime.gd` (the projectile-lifetime rule above:
  every `WeaponBehavior` subclass — enumerated from the project class list, so a *future* one is
  covered too — hands off its bullet's lifetime, a pooled bullet is **not** freed by the same
  change, a bullet is consumed by its first damaging hit, and a deflected hit does not consume it)
  and `tests/integration/test_config_instance_isolation.gd` (the config-copy rule above: no two
  entity instances share a config object, the copy is value-identical to the shipped `.tres`, and
  every config class stays flat enough for a shallow `duplicate()` to be a complete copy — the
  roster is a directory sweep, so a new enemy is covered the day it lands)
  and `tests/integration/test_signal_emit_arity.gd` (a signal's declared parameter list is never
  checked by the engine against how it is actually emitted — the 2026-09-03 honesty fix to
  `Health.amount_changed`/`State.state_transition` only helped a reader, not the engine — so this
  sweeps every self-emitted signal project-wide and asserts declared arity matches every
  `.emit()` call site; its first run caught the same drift live in `MovementController`'s
  `action_single_press`/`action_double_press`, fixed alongside it)
  and `tests/integration/test_collision_layer_names.gd` (every collision layer bit used anywhere
  is named in `project.godot [layer_names]`, and every named layer has a matching
  `CollisionLayers` constant)
  and the Phase 4 specialist gates (below)
  — plus the space-station family and `tests/integration/test_enemy_mover_single_writer.gd`
  (the AI single-writer rule above).
  The Phase 4 specialist gates: `test_level1_specialist_spawns.gd` (pins all 50 level-1 sniper / ram / bomber rows and
  caps the count at 2.5x frozen legacy peaks), `test_engagement_deadline.gd` (the sniper and ram deadline rows, plus a
  Bomber-in-an-`ENEMIES_CLEARED`-section boundary), `test_level1_specialist_exit.gd` (a real `WaveManager` replay of
  Cloud Descent) and, in `test_sniper.gd` / `test_ram_corvette.gd` / `test_bomber.gd`, an **attack-in-budget row** per
  specialist: from every level-1 spawn class it reaches its attack state before its Assault budget expires. The
  ordnance / armour / line-of-sight primitives are covered by `test_enemy_ordnance.gd`, `test_armor_query.gd`,
  `test_line_of_sight.gd` and the `ContactProfile` ARMOR rows in `test_contact_profile.gd`.
  A few characterization files also carry a handful of clearly-marked **intent** tests, which say
  so in a comment (e.g. `test_health_component.gd::test_amount_changed_declares_the_int_it_emits`).
  Read [`tests/README.md`](../../tests/README.md) before adding a test — it documents the
  save-file sandbox, and the signal-arity trap that will otherwise fail tests for reasons
  unrelated to the code under test.
- **Timers inside coroutines that can be abandoned:** prefer a `Time.get_ticks_msec()` deadline
  over `get_tree().create_timer()` when the wait can end early or the owner can be freed mid-wait.
  A `SceneTreeTimer` outlives an early `return` by its whole remaining duration, and a
  `GDScriptFunctionState` suspended when its object is freed is stranded outright; Godot only
  reports either at *process exit*, as `ObjectDB instances leaked` / `resources still in use`.
  **The gate cannot see those lines** — they arrive after GUT has set the exit code and they match
  none of `/agent/verify.sh`'s `FATAL` patterns, so a leaking suite still prints `GATE PASS`. Run
  `scripts/check-test-leaks.sh` (same arguments as gate step 3, plus a grep for the leak lines)
  after touching anything that awaits. `LevelDirector._wait_for_child_exit_or_timeout()` and
  `_wait_seconds()` are the worked example; `tests/integration/test_level_director_polling.gd` is
  the regression test.
- **Resource UIDs:** a UID is minted by the editor and cannot be written by hand, so a reference
  with no `uid=` is legal (Godot falls back to the `res://` path) but an *invented* one is a
  dangling reference that still loads. `tests/integration/test_resource_uid_integrity.gd` is the
  only tool for this: it reads UIDs from disk — never `ResourceUID`, whose answers depend on how
  warm the gitignored `.godot/uid_cache.bin` is, and which keeps dead UIDs alive as aliases —
  checks every `[ext_resource]` pairing, catches dangling and duplicated UIDs plus the UID-only
  references in `project.godot` / `export_presets.cfg`, and carries two canaries against a mass
  strip. **Do not run the Godot MCP `update_project_uids` tool** — as
  the MCP calls it it is a silent no-op (it searches `res:///work/repo/`), and pointed at `res://`
  by hand it resaves every scene, deleting all UIDs and all comments. Written up in
  [`tests/README.md`](../../tests/README.md).
- **Hazards (enemy rework phase 6):** (1) **hazards are sampled by the body** — a hazard node answers duck-typed
  `hazard_info() -> HazardInfo` and registers in `_enter_tree()` / unregisters in `_exit_tree()` (a *pooled* hazard, i.e. a mine, registers on `launch()` instead) with the static `Hazards`
  registry (`global/hazards/`); ships query `Hazards.accel_at / penalty_at / around`, no `Area2D` field, collision bit 12
  stays unallocated, and a hazard never writes a ship's velocity, position or rotation. A **wall is a segment** (Phase 8):
  `HazardInfo.segment_half != ZERO` makes `contains` / `penalty_at` / `around` measure to `closest_point()` and `context_avoid` steer round its
  ends; `exempt_group` lets an actor in that group (a twin pair) ignore its own wall. With no segment hazard every result is bit-identical. (2) **The mover owns enemy drift** —
  `EnemyMover` adds the pull as a decaying `HazardDrift`, applies the slow and the context-steering avoidance stage, and
  exposes `own_velocity()` (`actor.velocity − drift`); a brain's "am I stopped / settled" gate reads that, never raw
  `actor.velocity`. A committed attack is `mover.boost()` and ignores avoidance. With no hazard in reach, velocity and rotation
  are bit-identical to before. (3) **Runtime hazards are spawned deferred into the `HazardContainer`** — wrecks, debris
  fragments, Gravity Fields and reactor fields call `spawn_into(container, at, rot)` (a `call_deferred` attach, because kills
  happen inside a physics flush); the container is the node in group `hazard_container` (level 1 and the hub), never the enemy
  container; no container means nothing spawns and no rng is drawn. Randomness only from the dying enemy's seeded `rng`.
  Direct hazard damage is `Hazards.pulse_damage`. Details: [global.md](modules/global.md) → Hazards.
- **Mines, minefields and the Mine Layer (enemy rework phase 7):**
  1. **Mines are one family.** `EnemyMine extends EnemyOrdnance` (`assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`),
     `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }` (append-only). One scene per variant under `mines/`;
     PROXIMITY **is** the Bomber's `enemy_ordnance/mine.tscn` (same path, no UID). Variant numbers (trigger, warning, blast,
     effect) live in the scene; a dropper overrides only `arm_delay`, `eject_time` and the life. `EnemyMineScenes` reads scene
     exports without instancing, so gates never type a number. Warning rule for every scene:
     `(trigger_radius + effect_radius) / warning_time >= 440 + own_speed`. A mine is never in `enemies`, never scored, and a pooled
     mine never frees itself. `mine_life` 0 means "never fizzles".
  2. **Hostility.** `Hostility.PLAYER` (every mine an enemy lays) is set off by player hurtboxes only and blasts through
     `ContactBlast`. `Hostility.ALL` (placed mines) is also set off by a layer-512 area whose `get_parent()` is in group `enemies`
     and blasts through `Hazards.pulse_damage` (Ph6's rule that environmental blasts hurt both sides). `BaseEnemy` does not join
     `enemies`: a new enemy that placed mines must see joins it in its own `_ready()`.
  3. **A pooled hazard registers on `launch()`, not in `_enter_tree()`.** A mine sits idle in its `BulletPool`; it registers when a
     life starts and unregisters in `_mark_done()` and `_exit_tree()` (a fading mine is no hazard). Any later pooled hazard follows
     this. A mine never writes a ship's velocity, position or rotation.
  4. **The measured footprint.** `HazardInfo.kind = &"mine"`, `radius = trigger_radius + hazard_pad` (80 + 60), `avoid_weight` 1.0
     for every mine, `velocity` for moving mines (plus `carry_velocity`, set by a drifting parent), no pull, slow or LOS block.
     Measured with `Steering.context_avoid`: `hazard_avoidance` >= 0.8 keeps a ship >= 145 px from a mine centre, 0.6-0.7 skirts at
     90-110 px, 0.5 grazes. A smaller pad or weight lets a 0.6 ship cut inside the trigger.
  5. **Placed mines.** `placed = true` makes a mine self-owned (`expired -> queue_free`, no `ProjectileLifetime` backstop, `mine_life =
     placed_life`, default 0). The setup is a deferred `_start_if_placed()` queued by `_ready()`, and the `ProximityArea` mask is set
     from `hostility` in `launch()`, because Godot readies children before their parent: a `Minefield` configures its children in its
     own `_ready()`. A lone mine dropped in any scene arms, registers and triggers.
  6. **Chain.** A CHAIN detonation calls `chain_trigger(chain_delay)` on every live mine whose centre is within `chain_radius` (via
     `Hazards.around`, kind `&"mine"`); a chained mine skips its warning; only CHAIN mines propagate. **`enemy_mine.gd` must not name
     its own `class_name`** (`as EnemyMine`, `Array[EnemyMine]`): the self-reference leaks at exit and fails `verify.sh` with every test green.
  7. **Boost disruption and EMP are player hooks, applied by duck type.** `PlayerBase.apply_boost_disruption(strength, seconds)`
     (strongest and longest win, never stacked; `boost_efficiency()`, `boost_disruption_changed(efficiency: float)`,
     `MIN_BOOST_EFFICIENCY` 0.15). A disrupted speed scales only its **excess** over a floor: `PlayerBase.disrupted_speed(speed,
     floor)` = `floor + (speed - floor) * efficiency`, so a disruption never slows the ship below normal flight; efficiency is checked
     **before** a tank or charge is spent. `EmpPulse.emit(tree, at, radius, seconds, source) -> int` (`global/components/emp_pulse.gd`)
     is the one EMP entry point; Phase 9 (t5) gave it a trailing `targets` bitmask (default `TARGET_PLAYER`, so Ph7 calls are
     unchanged) and made `PlayerBase.apply_emp()` a full boost disruption **plus** a timed ability lock (see *Electronic warfare*).
  8. **The Mine Layer** (`assault/scenes/enemies/mine_layer/`) lays one line of 6 mines per pass across the player's path, never a
     spray, and builds unsafe regions gradually (one line per ~10-14 s in Open Space, one per Assault life). Its mines live in the enemy
     container through `BulletPool.persist_after_owner_death`, and in Open Space they never fizzle, so an area the player leaves and
     returns to is still dangerous. **Nothing that drops persistent mines goes in an `ENEMIES_CLEARED` section** (guard rows in
     `test_engagement_deadline.gd`). In LAY the layer skips the avoidance stage (it drives `mover.boost()`); entering DISENGAGE calls
     `mover.release_constraint()` so the Assault corridor never holds an exit in.
  Details: [assault.md](modules/assault.md) → *Mines and the Mine Layer*, [global.md](modules/global.md) → *Boost disruption* / *EMP*,
  `assault/scenes/enemies/mine_layer/ENEMY.md`, `assault/scenes/hazards/minefield/HAZARD.md`.
- **Enemy energy weapons (enemy rework phase 8, built from t2):**
  1. **One beam family, owner-driven.** `EnemyBeam extends Node2D` (`assault/scenes/projectiles/enemy_beams/enemy_beam.gd`,
     `enum Kind { BEAM, SWEEP, LANCE, TWIN }`, `enum Phase { OFF, TELEGRAPH, ACTIVE, FADE }`, both append-only) is a weapon
     component an owner holds: `setup(host, owner_group)`, `start()`, `tick(delta)` on the owner's physics tick, `cancel()`. **`tick()`
     is its only clock** — no `Timer`, `create_timer` or `_process` (`self_tick` exists for scene-placed props only). Emitter beams
     point along the node's **local +X**; the owner rotates the beam's parent, never the beam. `LaserRay` and the station's beam are
     not part of the family (Ph11 migrates the station). The old `LaserRay` has one opt-in, `registers_hazard` (Ph8 t17; level 1's columns and
     `LaserWallWave` set it): a `&"laser_wall"` segment from `start()` to the end of active, so enemies steer round a column it kills them in.
  2. **Tuning lives in the beam scenes** (`beam.tscn`, `sweep_beam.tscn`, `lance.tscn`, `twin_beam.tscn`; the Pulse Ring below),
     read through `EnemyBeamScenes.export_of()` — the Ph5/Ph7 rule, so a beam is identical whoever fires it and gates never type
     a number.
  3. **Friendly fire:** a beam hurts every node in `player`, `allies`, `enemies` and `asteroids` whose hurtbox **shape** meets it
     (`EnergyHitScan`, `Shape2D.collide`, exact for any shape, plus the triangles swept since the last tick), **except its owner
     set** (the host and every node in its `owner_group`). Enemy ordnance is never hit. Damage is a **direct emit**, so it bypasses
     `EnemyShield`, `ArmorPlate`s and `accepted_damage_types`; a plated Ram refuses it in its hull rule; the player's i-frames and
     shield apply. A beam kill scores like any kill.
  4. **Fairness is gated.** At most one hit per target per `rehit_interval` (0.55 s on every held beam: strictly above the player's
     0.5 s i-frames, because a re-hit on exactly 0.5 s lands before the idle-frame i-frame `Timer` expires); every beam draws a
     ≥ 3 px telegraph line on its path; static beams telegraph ≥ `0.25 + (hit_half_width + r_player) / 360` s, a sweep's tip never
     outruns 360 px/s, a lance commits ≥ 0.5 s with ≥ 0.25 s of uncommitted warning first. A later difficulty tier must stay
     inside them. Real-frame rows that race the player's i-frame `Timer` run at a **4×** clock, not 8×.
  Details: `assault/scenes/projectiles/enemy_beams/BEAMS.md`, [assault.md](modules/assault.md) → *Enemy energy weapons*;
  gates in `tests/integration/test_enemy_beams.gd`.
  5. **The Pulse Ring is the same family, not a beam kind.** `EnergyRing` (`energy_ring.tscn`, via `EnemyBeamScenes.ring_scene()`) is owner-ticked like a beam: a 0.8 s
     warning circle, then a 24 px band grows at 360 px/s to `max_radius` 280 (its outer edge never passes it) with two rotating 45 degree gaps; each target is hit once per
     ring, by the swept interval, by the same owner set and direct emit. Not `PulseRing` (Ph7's visual). Gate: `tests/integration/test_energy_ring.gd`.
  6. **Turret mounts are the aiming seam (t6).** Everything that aims and fires on a turret is a `TurretMount` (`assault/scenes/enemies/defense_turret/mounts/`),
     built at runtime from a host's `TurretMountSlot` markers by `TurretMountBuilder.build()`, one scene per `Variant` (`TurretMountScenes`; `HEAVY_CANNON` added in Ph10 t3), with an optional `traverse_deg` arc limit (360 = none). A mount **writes only its own `rotation`**, never reads its
     host's type (Ph10 bolts the same mounts onto ships), keeps its tuning in its scene's exports, and gets its pools as **root children of the host**
     (`pool_specs()`), so rounds land in the enemy container. Static structures (the `DefenseTurret` first) have no mover, never rotate their root, and scroll with
     the Assault corridor through `AssaultDrift` (`global/components/assault_drift.gd`), firing only inside `EnemyWorld.view_rect()`; their `.tres` sets
     `counts_as_escape = false`. Details: [assault.md](modules/assault.md) → *Stationary Defense Turret and the turret mount*; gate `tests/integration/test_defense_turret.gd`.
  7. **Turret groups are coordinators, not parents (t9).** `TurretGroup` (`assault/scenes/structures/turret_group/`; structures that are not enemies live in
     `assault/scenes/structures/`) spawns its members deferred as siblings in the enemy container, joins them to its `owner_group` and announces them as orphans; it is
     never in `enemies` and never scored. `set_powered(false)` on every member is the only power coupling: the last provider's (a `PowerSource`'s) `died` darkens the
     whole group in the same call, for good (`add_power_provider()` is the Ph20 seam). In Assault a wave-spawned group's x is **world-anchored** (`world_anchored_x`, the
     camera's horizontal pan removed in `_ready()` through `EnemyWorld`). Gate `tests/integration/test_turret_group.gd`.
  8. **A shield generator is a group member that bubbles the others (t9s).** `ShieldGenerator` (`assault/scenes/enemies/shield_generator/`, no mover, a brain) keeps a
     360° `EnemyShield` in sustain mode on every other live `BaseEnemy` member of its group (the power source included; never itself, never a member answering
     `is_fence_post()`), through the Support Ship's projected-shield path; a hurtbox whose absorber slot is already taken (a ward) is skipped, never displaced. No power
     (`set_powered(false)`) or no generator means no `sustain()`, so every bubble lapses after its heartbeat. Beams are direct emitters and bypass the bubbles. Gate
     `tests/integration/test_turret_group.gd` §13 on the test-only preset `tests/helpers/shielded_site.tscn`.
  9. **A laser fence is two destructible posts and a held or cycling beam (t10).** `LaserFence` (`assault/scenes/structures/laser_fence/`, a `Node2D`, never in `enemies`, never scored) owns two `LaserEmitter` posts (`assault/scenes/enemies/laser_emitter/`, no mover, no brain, `counts_as_escape` false, `is_fence_post()`) and one `twin_beam.tscn` `EnemyBeam` (damage 12, `avoid_weight` 1.0) that it ticks itself (`step(delta)`). `Mode.STATIC` warns once then holds; `Mode.CYCLE` flashes off 2.5 s / warn 0.9 s / on 3.0 s from `phase_offset`. The beam registers a `&"laser_wall"` hazard, so AI with `hazard_avoidance` steers round an end. A post's `died` (or exit) cancels the beam in the same call and the fence never relights; after the second post it lingers `linger_seconds` 1.0 (the posts' explosion particles spawn under it) then frees itself. Posts are never shielded. `world_anchored_x` as for groups; `AssaultDrift` carries it in Assault. `WaveBuilder.laser_fence()`. Gate `tests/integration/test_laser_fence.gd`.
  10. **A twin-laser pair is two drones, one rig and one clock (t12).** `TwinLaserPair` (`assault/scenes/enemies/twin_laser_drone/twin_laser_pair.gd`, a `RefCounted` both drones' brains hold, the `SquadController` precedent) binds two `TwinLaserDrone`s (and a controller, t13) into `owner_group` `&"twin_pair_<id>"` and owns one `twin_beam.tscn` as a **child of drone A** (one owner: A's death frees it). **Phase transitions happen only in the leader's tick** (A while it lives, else B); each brain mirrors the rig phase and moves itself through its own `EnemyMover` (ADVANCE = identical per-drone `boost()`, so a well's drift or a wreck strains the line). `| |A − B| − L | > length_tolerance` for `strain_seconds` collapses the beam; a drone's `died` / `tree_exiting` breaks the pair in the same call and the survivor never relights it. Assault frames are planned inside `inner_rect()` inset by `slot_tolerance`; one attack per life, deferred past TELEGRAPH / ADVANCE. Spawned by `TwinLaserPairSpawn` (`WaveBuilder.twin_laser_pair()`), never in an `ENEMIES_CLEARED` section. A hand-ticked drone test clears the body's `collision_mask` (no physics step between hand ticks, so the broadphase holds stale bodies). Gate `tests/integration/test_twin_laser_drones.gd`.
  11. **A Laser Tender launches a pair into a moving wall (t13).** `LaserTender` (`assault/scenes/enemies/laser_tender/`) is the rig's `controller`: `launch_pair(points)` (the Ph10 / Ph11 seam; **synchronous**, so call it on the physics step or from idle code, never from a physics callback) puts two drones at its cradles, binds them with the tender in the owner group (its own pair's beam never hurts it) and calls `TwinLaserPair.launch()`. LAUNCHED (appended to the rig's `Phase`) is a straight boost per drone to its point, a partial last step, a stop tick, and the rig leaves it `LAUNCH_SETTLE_TICKS` 2 ticks after the longer boost; then FORM on a **fixed** frame (`frame_fixed`, no player feed-forward), re-signed at the latch, advance capped at `standoff + overshoot`. At most one live pair; REARM 7 s; a SOLO drone it launched docks. Assault: an upper hold band reached by y, one launch per life, a budget expiring in the cradle telegraph lets the launch finish. Gate `tests/integration/test_laser_tender.gd`.
  12. **Twin drones and the tender idle in the hub; their Assault exits are measured once (t14).** Both the tender and a standalone pair idle round a `patrol_anchor` through `AnchorIdle` (Open Space only; `start_engaged` skips it). The pair's is updated by its leader only, the rig standing down into an appended `TwinLaserPair.Phase.IDLE` (`stand_down()` / `engage()`), and a stand-down never cuts a busy rig phase (an attack shown, its BREAK, a launch). The tender's duck-typed `recalls_drones()` (true in its idle phases) brings a launched pair home to dock. The two DISENGAGE exits are measured over `corridor_starts()` through `tests/helpers/ph8_exit_keys.gd` (`drone_exit()` / `tender_exit()`): the only place those probe keys are built, with the static `prepare_probe` hook (never a lambda: the memo keys on the Callable), so every caller after the first in a GUT run is a memo hit. Drone 5.37 s + 0.463 s reversal term, tender 3.82 s.
  13. **Phase 8 placement rules, in one place (t20).** (a) Static enemies (turret, heavy emplacement, shield generator, power source, fence post) set `counts_as_escape = false` in their
     `.tres`, so drifting off the bottom never breaks the combo; drones and the tender keep the default `true`. (b) A wave-spawned `TurretGroup` / `LaserFence` is world-anchored in x
     (`640 + 2 · design_x`, not camera-relative); a later placement author must not expect camera-relative x. (c) **No turret group, laser fence, twin pair or Laser Tender goes in an
     `ENEMIES_CLEARED` section** (persistent fire, persistent rockets, a pair that outlives being killed); guard rows in `test_engagement_deadline.gd`. (d) A static thing placed in
     deep_space must clear the level-start `LaserWallWave` as well as `Level1Director.laser_column_schedule()`. (e) Energy weapons hurt everything on the line except their owner set
     (item 4 above); a kill scores like any kill.
- **Electronic warfare (enemy rework phase 9, built from t1):**
  1. **The ability lock is a player hook, sampled by the body (t1).** `PlayerBase` locks the **H abilities and the K rockets only**:
     `abilities_locked()` is true inside a lit jammer field (`Hazards.jammer_at(global_position)`, a `HazardInfo` with `disables_abilities`),
     for that field's `stabilise_seconds` after the exit tick, and while a timed `apply_ability_lock(seconds, source)` runs (longest wins, never
     added, no stabilisation after it). Signals `ability_lock_changed(locked: bool)` (edges only) and `ability_press_refused()`;
     `ability_lock_fill()` for a HUD. It is checked in exactly three seams, each through `allow_ability_press()`: both ships' `_input` H
     loops (a locked press is refused, consumed, and spends nothing) and `RocketState._on_action` for `special_weapon` (after the cooldown
     check, before the launch). **Never locked:** thrust, turn, Shift boost and the Open Space Boost Drive on Shift, dash, warp, primary fire
     (`WeaponState` is not touched), `switch_weapon`, passive modules, effects already running, module `tick()` (cooldowns keep counting).
     **Clock rule:** every lock clock is `x -= delta`, over at `x <= 1e-6` (`PlayerBase._tick_clock`), so a lock of `s` seconds at 1/60 ends on
     tick `round(s · 60)`. A jammer is a `HazardField` with `disables_abilities` (written into its info **only while ACTIVE**, so a pulsed field's
     TELEGRAPH / QUIET count as outside) and `stabilise_seconds`. Gate `tests/integration/test_player_ability_lock.gd` (both real player scenes).
     **Tells (t2):** `AbilityLockStatic` on the ship, `JammedChip` + `LockGlyph` built by `MissionHud` (both HUD scenes), and the audio seam `EventBus.player_ability_lock_changed(locked)` (once per edge; `player_ordnance_hijacked(rocket, source)` declared for t4). No audio player. Gate `tests/integration/test_player_ability_lock_tells.gd`.
  2. **Seeking ordnance can be retargeted (t4); a player rocket never hits another player rocket.** The contract is duck-typed (the `is_armored()` precedent): a
     player seeker joins `SeekingOrdnance.GROUP` (`global/components/seeking_ordnance.gd`; `SeekingOrdnance.eligible(tree, at, reach)` nearest first) and answers
     `can_be_retargeted()`, `retarget(target, seconds, source)` (`seconds < 0` = the rocket's own `hijack_seconds`), `is_retargeted()`, `jam_guidance(source)`, signals
     `retargeted(source: Node)` / `retarget_ended()`. Only `homing_missile` implements it (a `WarheadMissile` is never eligible); a rocket is claimed at most once, never
     inside a lit jammer. A **hijacked** rocket turns at `hijack_turn_rate` 1.6 rad/s toward its new target, eases 500 → 380 px/s, fizzles after 2.5 s or at once when its
     source is freed, hurts the player **only through a `ContactBlast`** (18, r 40) once armed (0.25 s **and** once ≥ 60 px from the target), keeps its full 100 on enemies
     (the lure), and is shot down by one player bullet (`HurtBox` 512 / 64, open only while hijacked). Its HitBox and the warhead's ignore any area whose parent is a
     `homing_missile`. Every end goes through `_finish()` (the lifetime expiry too), so `retarget_ended` always fires for a hijack. Inside a lit jammer field every seeker
     flies straight. Tuning on `homing_missile.tscn`. Gate `tests/integration/test_seeking_ordnance.gd`.
  3. **EMP disrupts systems, never the hull, and is routed by `answers_emp()` (t5).** `EmpPulse.emit(tree, at, radius, seconds, source,
     targets := TARGET_PLAYER) -> int` (`TARGET_PLAYER` 1, `TARGET_ENEMIES` 2, `TARGET_SEEKERS` 4, `TARGET_ALL` 7; one centre-distance `<=` rule; returns ships
     reached, seekers never counted). **Player:** `apply_emp()` = `apply_boost_disruption(1.0, s)` + `apply_ability_lock(s, source)` (the lock ends on tick
     `round(s · 60)`, no stabilisation). **Enemies:** `BaseEnemy.answers_emp()` (default `is_ai_driven()`) is the one routing question every EMP source asks; an
     answering enemy's `apply_emp(seconds, source)` (longest wins) calls `mover.halt()` then `EnemyBrain.on_emp_started()` once, shows a code-built blue-white
     `EmpStatic` (`global/components/emp_static.gd`), and for the window `_physics_process` skips `brain.tick()` (no fire, no decision, the Assault budget frozen)
     while the mover still steps; hurtbox, body and health are untouched, so **an EMP'd enemy can be shot**. The clock (`<= 1e-6` rule) runs ahead of the no-brain
     return, so a brainless override still ends; `suspend_ai()` clears a live window. `TwinLaserDroneBrain.on_emp_started()` releases the pair (drone A's beam is
     freed), `LaserTenderBrain.on_emp_started()` drops a launch telegraph; any beam brain of a mover-driven ship must override it (sweep row). **Seekers:**
     `TARGET_SEEKERS` calls `jam_guidance(source)` on `SeekingOrdnance.GROUP` and `SeekingOrdnance.ENEMY_GROUP` (`&"enemy_seeking_ordnance"`: an `EnemyRocket` with
     `turn_rate > 0` from `launch()` to `_mark_done()` / `reset()`; jammed = `is_guiding()` false for the rest of its life). **The EMP mine** passes
     `TARGET_PLAYER | TARGET_SEEKERS` when enemy-laid and `TARGET_ALL` when placed (`Hostility.ALL`). Gates `tests/unit/test_emp_pulse.gd`,
     `tests/integration/test_enemy_emp.gd` (both harnesses), the EMP rows of `test_player_ability_lock.gd` / `test_player_boost_disruption.gd`.
  **The EMP zone (t11)** is a placed `EmpZone` (`assault/scenes/hazards/emp_zone/`, a `Node2D` composing a cycled `HazardField`) that makes one `EmpPulse.emit(..., TARGET_ALL)` per cycle; see [assault.md](modules/assault.md) → *EMP Zone*.
  **The Jamming Structure (t7)** is three static towers (`assault/scenes/enemies/jamming_structure/`, `sector_jammer/`, `pulsed_jammer/`; one `JammingStructure` script) whose child `HazardField` (kind `&"jammer"`, `avoid_weight` 0) is the lock's field; its EMP answer is `HazardField.suppress(seconds)` (field quiet, tower shootable), enemy seekers fly straight inside a lit field and the Missile Corvette fires Dumb at a player in one; see [assault.md](modules/assault.md) → *Jamming Structure*.
  **The Hacker Frigate (t8)** (`assault/scenes/enemies/hacker_frigate/`) holds medium-long range on a lopsided arc (0.18 / 0.30 rad/s), slides out of the player's nose and route cones toward the nearer edge, breaks off with committed boosts when rushed (Open Space) or a view-clamped request (Assault), stays inside `view_rect().grow(-60)` for a 9 s Assault budget and idles round an anchor in the hub. **Its Hijack Pulse (t9):** a TELEGRAPH any damage cancels, then a PULSE in which `HijackPulse` control darts (`assault/scenes/projectiles/hijack_pulse/`, no collision areas, pooled with no `persist_after_owner_death`) fly from its hull centre to up to 3 eligible player homing rockets within 650 px and in sight (Ph6 LOS: enemy bodies never block) and hand them to the player through the t4 retarget contract; the player must be within `pulse_trigger_range` 870 and in sight; one pulse per Assault life; the Disruptor hook (`pulse_lock_seconds`, 0 on the base ship) locks abilities at PULSE end through `HackerFrigate.lock_player_abilities()`. Measured: a salvo a still player fires at it is claimed heading away and never blasts that player. Its measured exit is built only in `tests/helpers/ph9_exit_keys.gd`; see [assault.md](modules/assault.md) → *Hacker Frigate*.
  **Level 1 (t14)** places one Hacker (planet_approach 42.0 s) and, after it has gone, one local jammer (62.0 s, world x 480), pinned as `EXPECTED_PH9` in the frozen 2.5× gate of `test_level1_specialist_spawns.gd` (lives never overlap, both end before the 98.0 s peak, the jammer clears every lit column), replayed in `test_level1_ph9_attacks.gd`; `test_engagement_deadline.gd` keeps every EMP source and the sector jammer out of Assault levels (a source scan).
  Details: [global.md](modules/global.md) → *Ability lock*, *Seeking ordnance* and *EMP hook*.
- **Git:** **never commit — the user handles all git.** Work on `main` unless asked.

---

## Per-entity behaviour docs

Each combat entity carries a behaviour doc **beside its scene**, mirroring a common format:

- **Racers:** `assault/scenes/race/racers/<name>/RACER.md` (6 racers)
- **Assault enemies:** `assault/scenes/enemies/<name>/ENEMY.md` (the wave enemies + the `space_station` mini-boss)
- **Assault hazards:** `assault/scenes/hazards/<name>/HAZARD.md` (9 hazard folders: big/small asteroid, laser_ray, gravity_well, energy_anomaly, gravity_field, reactor_field, wreck — wrecks, derelict structures and drifting debris — and minefield)
- **Assault structures:** `assault/scenes/structures/<name>/STRUCTURE.md` (Ph8: turret_group)
- **Race track hazards:** `assault/scenes/race/track/RACE_HAZARDS.md` (walls, asteroids, lasers + the lethal-hazard / AI-avoidance system)

Level 1's **finale** phase is still the `ENEMIES_CLEARED` section in
`assault/scenes/levels/edelia/1/level_1_director.gd`, documented in
[assault.md](modules/assault.md) — it is a wave, not an entity.

There is now one **discrete multi-part boss entity**:
`assault/scenes/enemies/space_station/` — a four-turret mini-boss whose core is invulnerable
until every turret is destroyed. It is placed in Level 1 by the `station_assault` section, between
`asteroid_belt` and `planet_approach`, which uses `EndCondition.ENEMIES_CLEARED` so the level
cannot continue until the station is destroyed. See
[`space_station/ENEMY.md`](../../assault/scenes/enemies/space_station/ENEMY.md).

It is also the project's first **two-phase** entity. Killing the last turret emits `armor_broken`,
which starts `StationLaserPhase` — a child node that rotates the station and fires telegraphed
`LaserRay` volleys — and simultaneously switches `StationGunnery`, a second child node, from aimed
per-turret fans to precessing full rings from the core. Both phases are separate nodes rather than
states on `space_station.gd`
(composition) and rather than a `global/statemachine/` `State` per phase: the transition is
one-way and there are only two phases, and this project reserves the node-per-file state machine
for genuinely complex entities. Revisit if a third phase appears.

A **third** child node, `StationReinforcements`, runs only during phase 1: it spawns squads of
existing enemy scenes from all four screen edges on a fixed cycle, and stops on `armor_broken`.
It is the project's first spawner that is not `WaveManager` — reinforcements go straight into
`enemy_container` as siblings of the station and register on `EventBus.enemy_spawned_orphan`,
the same channel `big_asteroid.gd` uses for its shards.

A **fourth** child node, `StationDeathSequence`, owns the boss's death spectacle. `SpaceStation`
overrides `BaseEnemy._on_health_changed` so that only `queue_free()` is delayed — `was_killed` and
`died` still fire the instant HP hits 0, because `ScoreTracker` discriminates kill from escape on
exactly those. The wreck then lingers for `death_duration` (1.8 s) while seven blasts roll across
the hull at deterministic offsets and it drifts and darkens. The handoff into `planet_approach`
needed **no** `LevelDirector` change: `_wait_enemies_cleared()` already polls the enemy container's
child count, so a wreck that stays parented holds its section open for free.

For spawning enemies via `WaveBuilder`, see [`docs/enemy-roster.md`](../enemy-roster.md).

---

## Related docs

- [`docs/game-structure.md`](../game-structure.md) — game loop & mode transitions
- [`docs/enemy-roster.md`](../enemy-roster.md) — WaveBuilder spawn reference
- [`docs/scoring_guide.md`](../scoring_guide.md) & [`docs/assault-spawning-scoring-internals.md`](../assault-spawning-scoring-internals.md) — scoring
- [`docs/BULLET_POOL.md`](../BULLET_POOL.md) — bullet pooling
- [`tests/README.md`](../../tests/README.md) — how to run and write tests
- [`addons/gut/LOCAL_PATCHES.md`](../../addons/gut/LOCAL_PATCHES.md) — the two changes GUT
  needs to load under Godot 4.6.3; re-apply on any GUT upgrade, and
  `tests/integration/test_gut_local_patches.gd` fails if you forget
- [`docs/plans/`](../plans/) — one directory per feature: context, research, plan, the
  independent review verdict, and the implementation log. The audit trail for unattended work
- [`docs/epics-done/`](../epics-done/) — one dossier per finished epic (`PRD.md` / `SOURCES.md` /
  `REPORT.md`). **Start here** for why a shipped system is built the way it is, where its tuning
  numbers came from, and what is known to be unfinished about it

---

## Keeping this current

After any structural change to scenes or scripts, invoke the **`updating-project-docs`**
skill (`.claude/skills/updating-project-docs/`) to keep this hub, the per-entity docs, and
`CLAUDE.md` in sync.
