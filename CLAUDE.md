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
  deals damage — a *deflected* hit does not count.** `bullet.gd::_hit_is_deflected()` checks
  whether the target reports `is_armored() == true` (duck-typed, no shared interface) and, if so,
  returns without emitting `expired` or spending a pierce charge. This is load-bearing: the
  space-station boss's armoured core spans the whole hull, so a shot aimed at a turret has to
  survive crossing it, and the core's `is_armored()` query is what tells the bullet the crossing
  was a deflection, not a kill — consuming the shot there makes the turrets, and the boss,
  unkillable. `PierceModule` raises the number of *damaging* hits a bullet survives (via
  `Bullet.MAX_PIERCE`) before it stops. Any future entity that needs to deflect a bullet without
  consuming it must expose its own `is_armored()`-shaped query. Spelled out in
  `docs/architecture/PROJECT.md` → Conventions; gated by
  `tests/integration/test_player_bullet_lifetime.gd`.
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
  and the space-station family — `tests/integration/test_space_station.gd`,
  `test_station_assault_section.gd`, `test_station_laser_phase.gd`, `test_laser_ray_hit_mask.gd`,
  `test_station_gunnery.gd`, `test_station_reinforcements.gd`,
  `test_station_incoming_damage_paths.gd` and `test_radial_attack_pattern.gd` —
  which cover new code and so
  assert intent. The last of those closes the boss's collision-layer coverage gap: real missiles,
  a real asteroid and a real `BeamBehavior` prove the `HurtBox` mask bits 32 and 1024 and the
  layer-0 root that keeps the hull from blocking the player's mining laser. `tests/integration/test_module_unlock_sources.gd` is a second invariant check
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
  station core to 88 x 240" proposal to a live instance and asserts it fails, so that decision is a
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
  card that cuts a hard rectangle out of the starfield. `station_core.png` shipped at
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
  `tests/integration/test_station_reinforcements.gd::test_rail_reinforcements_fire` is a twenty-first,
  the **rail-fire test**: every TOP fighter and LEFT/RIGHT Gatling the space station spawns on a rail
  must put at least one bullet in the container within 2 s, and a forward rail fighter's shot must
  leave along its travel. It exists because the fighter and the Gatling moved to brains and a rail
  now **suspends** the brain: without the rail-fallback weapon (`on_suspended()`, built from `rail_*`
  config fields) a squad that looks dangerous would never fire, with no other gate noticing.
  The behaviour specs for the two enemies themselves (`test_fighter.gd`, `test_fighter_squad.gd`,
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
