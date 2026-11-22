# Enemy rework, phase 11: Space Fortress 2.0 and machine-driven boss reinforcements

Revision 2 (2026-11-22; answers review 1, see §8). Epic `cmug256so0031m52wbxomst72`, phase 11 of the enemy rework (idea `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`). **This directory had no
`1-context.md` / `2-research.md`:** the research task is marked done but left no files (the Phase 10 precedent), so this plan carries the scope check (§1.1), the research
and judgement calls (§1.2) and the code facts (§1.3) itself. Code facts were read on `agent/auto-dev` @ `cba0e7b`.

## Summary for the owner

- **For the player:** the level-1 station boss becomes the **Space Fortress**, a bigger (about 350 px) ring fortress you fight by circling it. It has five outer gun batteries, each with its own attack (spread cannon, rapid pulse, laser sweep, missiles, slow artillery), two shield generators that each protect one half of the hull, a hangar, and an armoured core.
- **Four phases you can see:** (1) the batteries fire from their corners in diagonal crossfire, each behind a breakable shield; (2) after two batteries die, the shield generators open up, hull lasers start sweeping as the fortress spins, and defenders launch; (3) once both generators are gone the core opens, the fortress starts moving and sends expanding pulse rings; (4) at low core health the reactor goes critical: faster spin, four lasers, a bullet ring, a last wave of defenders.
- **Destruction changes the fight:** a dead battery takes away its line of fire, a dead generator strips the shields from its half, a dead hangar stops the drone launches, and losing a battery makes its half of the fortress launch defenders (fighters on one side, gatlings on the other) for as long as that half's generator lives. Wrecked parts stay on the hull.
- **Defenders belong to the fortress:** they come out of specific doors, no longer fly in on rails from the screen edges, explode when the fortress dies, and no longer cost you combo for "escaping".
- **Built for later bosses:** a reusable phase ladder (which also checks the rule that every phase changes at least two things), reusable launch bays for defenders, a shared boss death sequence and two new turret types. The Dreadnought (phase 12) and the Carrier and Heavy Gunship rework (phase 18) build on them.
- **Also:** the fortress waits at the far edge of the Open Space hub as an optional fight; turrets, laser-fence posts and shield generators react to EMP like ships do (silenced, still shootable).
- **Left out:** a boss health bar (the spec says not to make one big health bar), enemy lasers hurting boss parts and wrecks you can hide behind (phases 18–19), difficulty tiers (16), sound (17).
- **Main risks:** the Assault screen is small for a 350 px boss with sweeping lasers; fairness rows check that you can always outrun or dodge each attack, and the number of enemy bullets on screen is measured in every phase (the frenzy included) against a fixed ceiling. The test suite is about 27 s under its time limit. Retiring the station rewrites about 25 test files.
- **Choices for you (default in brackets):**
  1. Remove the old space station completely once the fortress replaces it? [yes]
  2. Phase 2 starts after how many of the 5 batteries are destroyed? [2]
  3. Place the fortress as a permanent optional fight at the far north-east edge of the Open Space hub? [yes]
  4. Defenders pay their normal score when shot, never cost an escape penalty or count toward wave bonuses, and pay nothing when they explode with the fortress? [yes]
  5. Raise the station section's time limit before the boss "escapes" from 180 s to 240 s? [240 s]
  6. Shorten every EMP to 40 % on the fortress (the player's 5 s EMP Blast becomes 2 s)? [yes]
  7. Should turrets, fence posts and shield generators go silent but stay shootable under EMP, while the bonus drone keeps today's freeze? [yes]

## For every task

Phase 11 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line here changes them.
- **Names.** The boss is the **Space Fortress**: `class_name SpaceFortress` (root, `BaseEnemy`), `FortressBrain`, flat `SpaceFortressConfig`, folder `assault/scenes/enemies/space_fortress/`,
  `WaveBuilder.space_fortress()` / `SPACE_FORTRESS`. **Never call it a "station"** in new code, nodes or docs: Open Space already has "Fortuna Space Station" (a `MissionTrigger`). The
  level-1 section keeps its internal name `station_assault`. The legacy `SpaceStation` is retired by t11 (Ph11 owner choice 1); until then it stays behaviour-identical. "Owner choice N" in this plan means the Phase 11 summary list (write "Ph11 owner choice N" in DECISIONS: Phase 10 has its own numbers).
- **Shared boss machinery lives in `global/boss/`** (new folder): `BossPhase` (Resource), `BossPhaseDriver` (Node `PhaseDriver`), `ReinforcementBay` (Node2D on a part),
  `BossReinforcements` (RefCounted, ticked by the brain), `EscortContainer` (static helper), `ShieldSector` (RefCounted), `BossDeathSequence` (Node2D `DeathSequence`).
  Phase 12 and Phase 18 reuse all of them; keep them free of fortress names.
- **Phase-11 framework built on Phase 10:** parts are `EnemyModule`s under `Modules`, coordinated by `ModularHull` (`module_destroyed(module)`, `live(role)`,
  `destroyed_count(roles)`, `build_mounts(host, rng, owner_group, telegraph_gate, first_index) -> int`). Mounts are `TurretMount`s built only by `TurretMountBuilder.build()`;
  their pools are **host root children** (container = the host's parent). `TurretMount.tick(delta, target: TargetInfo, host_can_fire: bool)`, `scan(delta)`, `power_down()`.
- **Hull rule: armoured hull** (the Carrier's): the fortress root answers `deflects_hit()` / `is_armored()` true, refuses all root damage (`armor_deflected`), so shots cross the hull
  to parts anywhere; **its death is the CORE part's death** (`health.set_health(0)` on the root). Root body layer 0 / mask 0 (the station rule: never block the player's mining laser).
- **Part ids (StringName) and node names:** `battery_spread` `BatterySpread`, `battery_pulse` `BatteryPulse`, `battery_sweep` `BatterySweep`, `battery_artillery`
  `BatteryArtillery`, `battery_missiles` `BatteryMissiles`, `hangar` `Hangar`, `shield_north` `ShieldNorth`, `shield_south` `ShieldSouth`, `core` `Core`.
  Sectors: **north** = `shield_north` protects `battery_artillery`, `battery_missiles`, `hangar`; **south** = `shield_south` protects `battery_spread`, `battery_pulse`, `battery_sweep`.
- **Boss phases** (`BossPhase.phase_id`, in order, one way): `&"batteries"` (START) → `&"shields_exposed"` (2 WEAPON parts destroyed) → `&"core_exposed"` (both shield
  parts destroyed) → `&"critical"` (core health ≤ 40 %). Every non-start phase must change ≥ 2 of MOVEMENT, ATTACKS, VULNERABLE, ARENA, REINFORCEMENTS, VISUALS, and
  `SpaceFortress.phase_snapshot()` must show every declared change (§25 as a gate).
- **Two phase enums, never mixed:** the boss phase ladder (above, owned by `BossPhaseDriver`) and the brain's movement phase `FortressBrain.Phase { IDLE, NOTICING, RETURNING,
  ENTER, HOLD, REPOSITION }` (append-only).
- **Escorts (boss reinforcements):** spawned only by `BossReinforcements` from a `ReinforcementBay` on a live part, into the boss's **escort container** (a `Node2D` sibling of the
  boss named `<boss name>Escorts`, group `&"boss_escorts"`), never straight into the enemy container and never announced with `EventBus.enemy_spawned_orphan`. They are announced
  with the new `EventBus.boss_escort_spawned(escort: Node, boss: Node)`; `ScoreTracker` pays a kill its `score_value` × combo and nothing else (no wave tally, no escape
  penalty) and pays nothing for a kill after the boss `is_dying()`. Escorts keep their own config's `counts_toward_wave_clear` / `counts_as_escape` (nothing writes them; the
  escort path never reads them). Squads: one `SquadController` per payload scene per boss, cached for the boss's life (the `CarrierHangars._squad(path)` rule). Escorts are in the boss's owner group, `start_engaged`, seeded from the boss rng, scuttled
  (`health.set_health(0)`) when the boss's death starts; the container is freed with the boss. One `<boss>Escorts` child is all the escorts add to `ENEMIES_CLEARED`.
- **Owner group:** `&"fortress_<instance_id>"`; mounts, spoke beams, the pulse ring and escorts use it (an enemy beam never hurts its owner set).
- **Mount gate:** `TurretMount.telegraph_gate` is a zero-argument `Callable` (`telegraph_gate.call() -> bool`, shared unbound by `ModularHull.build_mounts`); the fortress's is
  `FortressBrain.attack_gate() -> bool`.
- **Persistent ordnance in `ENEMIES_CLEARED`:** the fortress's `ROCKET_BATTERY` pools are `persist_after_owner_death`; the fortress is the **second bounded exception** (after
  the Ph10 Heavy Gunship) to "persistent-ordnance enemies stay out of `ENEMIES_CLEARED`", with tail term `death_duration` + rocket `max_time`; `test_engagement_deadline.gd` names it.
- **Scenes a gate reads:** `export_of()` / `export_of_scene()` read only a scene's own `SceneState`, so an inherited scene returns script defaults for values it does not
  re-author. New mount scenes are **standalone** (the `heavy_cannon_mount.tscn` precedent); an inherited beam / ring scene authors every value a gate reads, and the gate reads an
  instantiated node.
- **Spawn calling rule:** escorts are added synchronously from the brain tick (physics step or idle code), never inside a physics callback.
- **Coordinates:** Assault offsets in 640×360 design units via `WaveBuilder` (`.at(x, y)` → world `640 + 2x`, `360 + 2y`); the fortress is `world_anchored_x` like the Carrier.
  Open Space: world space, no camera maths. Local part bearings: 0° = local +x, 90° = local +y (screen-clockwise).
- **Mode detection:** `EnemyWorld.arena(get_tree()) != null` = Assault. Nothing the fortress owns fires outside `EnemyWorld.view_rect()` in Assault.
- **Single writers:** the fortress's `velocity` / `rotation` / `move_and_slide()` belong to its `EnemyMover` (the brain only requests: `face_toward`, `request_velocity`,
  `arrive`, `hold_position`); a spin is `face_toward` a point ahead of the current facing with `max_turn_rate` = the spin rate. After death starts, `suspend_ai()` runs and
  `BossDeathSequence` alone writes the dying hull's rotation (it lives in `global/boss/`, outside the single-writer sweep, by design).
- **Config:** every tuning number in `space_fortress_config.tres` (flat, no sub-resources — `test_config_instance_isolation.gd`); mount tuning in mount scenes; bay
  tuning on the `ReinforcementBay` node exports; phase rules as `BossPhase` sub-resources on the `PhaseDriver` node in the scene. **Never write to a loaded resource**
  (`BossPhase`, mount scenes' resources, the shared `.tres`).
- **Signals** declare exactly what they emit (`test_signal_emit_arity.gd`); anything per-frame or per-hit prints only behind `OS.is_stdout_verbose()`.
- **UIDs:** never hand-type or copy a `uid://`; leave references UID-less or mint with the `tests/README.md` snippet. Never run `update_project_uids`.
- **Tests:** GUT, tests first, both harnesses (`enemy_ai_harness` Open Space and Assault) for every fortress behaviour row; hand-ticked where possible; real-physics rows at 8× (16×
  only after checking wall vs CPU, `tests/README.md` → *Gate time*). A hand-ticked boost row starts with `await _fresh_idle_delta()` (Ph10 rule). Run `scripts/check-test-leaks.sh`
  after anything that awaits. Gate: `bash /agent/verify.sh`. Record GUT time before/after (two-run mean of `scripts/gate-time.sh`) in `tests/README.md`; stay inside your
  allotment (§2.15) and escalate past a 237 s mean or 1.5× your allotment. Gate output stays well under 1 MiB.
- **Art:** invoke the `pixel-art-generation` skill before any PixelLab call; strict top-down, never isometric; save with `./scripts/pixellab.sh`; look at every image; no texture
  ≥ 90 % opaque. Placeholders until t9 reuse existing station PNGs; t9 replaces them.
- **Docs:** after a structural change invoke `updating-project-docs` (t14 does the phase pass; each task keeps its own `ENEMY.md` / module-doc lines true).
- **Deviation log:** a departure later phases depend on goes into `DECISIONS.md` under a `### Phase 11, built in tN` heading.

## 1. Problem

Today's boss is the level-1 **Space Station**: a 256 px static square in the top of the Assault view with four corner turrets (120 HP each, aimed 3-bullet fans every 1.8 s),
an armoured 600 HP core, a phase-2 hull spin that sweeps two `LaserRay`s, a precessing 10-bullet ring, rail-driven reinforcement squads from the screen edges and a 1.8 s death
sequence. It was designed to be fought from below; it never moves; its reinforcements are generic Assault spawns (in the enemy container, scored as orphans, charged as escapes,
their AI switched off by rails); its turrets are bespoke `StationTurret` nodes outside the Phase 10 module framework; it does not answer EMP (the player's EMP Blast freezes the
whole node) and has no `homing_point` (rockets park in the hull centre).

The owner wants a 360° boss built from coherent modules (IDEAS §8, §8.1, §22–26, §39), whose phases each change how the fight plays (§25), whose weapons come from its shape
(§24), and whose reinforcements are part of the machine (§10) — a reusable mechanism, not a fortress one-off — fought by circling in Open Space and by moving round it in Assault.

### 1.1 Scope check (re-validated against the code @ `cba0e7b`)

| Scope item | State in the code | Effect on this plan |
|---|---|---|
| §8.1 module framework | Built in Ph10: `EnemyModule`, `ModularHull`, `TurretMountBuilder`, `traverse_deg`, `HEAVY_CANNON`; two hull rules | Reused as is; the fortress picks the armoured-hull rule |
| Outer batteries' five attacks | Mounts exist for laser sweep (`SWEEP_BEAM`), missiles (`ROCKET_BATTERY`), slow artillery (`HEAVY_CANNON`); **no spread or rapid-pulse mount** | t3 appends `SPREAD_CANNON` and `RAPID_PULSE` |
| Shield nodes | `EnemyShield` (arc ≥ 360 = bubble, capacity, regen, reboot) and the absorber slot exist; `ShieldGenerator` sustains bubbles for turret groups only | t5 builds a generic `ShieldSector` on `EnemyShield` (no `ShieldGenerator` reuse: that is a `BaseEnemy` turret-group member, not a part) |
| Geometry weapons | `EnemyBeam` (owner-ticked), `EnergyRing`, `RadialAttackPattern` exist; the station still uses `LaserRay` (Ph8 deferred its move to Ph11) | t7 builds spoke beams on `EnemyBeam`, a ring pulse on `EnergyRing`, keeps the precessing bullet ring |
| §10 reinforcement mechanism | `CarrierHangars` (Ph10) spawns hangar children into the enemy container with `enemy_spawned_orphan`; `StationReinforcements` uses rails + orphans | t2 builds the reusable mechanism; **the Carrier is not migrated here** (Ph18 owns that, Ph1 roadmap) |
| "Out of the generic container and scoring" | `LevelDirector._wait_enemies_cleared` counts every enemy-container child; `ScoreTracker` handles orphans as wave −1 tally + escape penalty | escort container + dedicated `boss_escort_spawned` path (§2.2) |
| Boss phases (§25) | Only bespoke per-heavy code (`HeavyGunshipBrain.HullPhase`, Carrier core exposure) | t1 builds `BossPhaseDriver` with the ≥ 2-changes rule as a gate |
| Death sequence | `StationDeathSequence` (station-specific node) | t4 moves it to `global/boss/BossDeathSequence` unchanged in behaviour |
| Station `homing_point` (Ph4/Ph5 deferral) | Missing | The fortress has `homing_point(from)`; retired with the station |
| EMP on structures (Ph9/Ph10 deferral to Ph11: bonus drone, station, Ph8 turrets / fences) | Not done: `DefenseTurret` and `ShieldGenerator` have a brain but no mover, `LaserEmitter` (fence post) has neither; so `answers_emp()` is false and EMP Blast process-disables them. `BaseEnemy.apply_emp` already guards a null mover / brain and `_physics_process` already counts a brainless structure's window | **Debt that belongs here**: t12 (turrets, fence posts, shield generators); the station goes with t11; the bonus drone deliberately keeps the legacy freeze (rail enemy) |
| Ph8 "endpoint rig rotating about an anchor" for the fortress | `EnemyBeam` TWIN takes endpoints per tick | Not needed: the fortress's rotating beams are hull-mounted BEAM emitters turned by the hull; the twin-rig mode stays unbuilt (recorded) |
| Open Space appearance | No combat-zone concept; hub `sector_hub.gd` patrol draws 1–20; Fortuna Space Station is a `MissionTrigger` | t13: hub draw 21 with an internal combat zone (anchor + radius) |
| Boss HUD bar | None exists | Out of scope (IDEAS §6.11: "do not make it one giant HP bar"; part HUD is Ph17) |
| Station test family (9 files, ~100 tests) + 16 other files referencing the station | Pins station structure (4 turrets, Timer gunnery, `LaserRay`, rails) | t11 maps every file to keep / re-point / delete-with-replacement (§2.11) |

### 1.2 Research and judgement

No new web research was done: the design questions are answered by the owner's spec (IDEAS §8.1, §10, §21–26, §39–41) and by Phases 1–10's recorded decisions. The
following are **judgement calls, labelled as such**:
- **Ring fortress with corner bastions** (a star-fort plan): it gives the spec's three geometry weapons a body to come from — corners → diagonal crossfire (limited mount
  traverse), ring → radial pulses, hull axes → rotating beams — and two halves for two shield generators.
- **Shields as a breakable per-part bubble, generators locked until phase 2.** IDEAS §13.2 says shields are a temporary combat resource, not a second health bar; a 360° bubble
  (not an outward arc) closes the exploit of shooting a far-side battery through the transparent armoured hull from behind its shield.
- **"Weak side" = the side with the fewest live, shielded batteries;** the fortress turns its strongest side to the player at a turn rate below a circling player's angular speed,
  so circling wins and the weak side keeps changing as parts die (IDEAS §8.1 "change orientation so its weak side changes").
- **Escorts die with their boss** (shmup convention; keeps `ENEMIES_CLEARED` a boss-only condition) and keep the score they pay when shot (Ph11 owner choice 4).
- **Fairness is checked by inequalities read from scene exports** (the Ph8 beam rule): beam tip speed at the player's working radius below the player's speed; ring gaps; at most
  two batteries telegraphing at once.

### 1.3 Code facts every design section relies on

- **Station** (`assault/scenes/enemies/space_station/`): root `CharacterBody2D` layer 0 / mask 0; 240×240 rect body = hurtbox = contact (damage 40); `Turrets/Turret0..3` at
  (±76, ±76), r 26, 120 HP; `LaserPhase` (`LaserRay`, `hit_mask_override` 128, hull `rotation += 0.5 rad/s`); `Gunnery` (Timers, two runtime `RadialAttackPattern`s, `BulletPool`
  48 as a direct root child); `Reinforcements` (rails, `free_after`, container = station parent, `enemy_spawned_orphan`); `DeathSequence` (1.8 s, 7 blasts, spin, burnt tint;
  the station frees itself in `_finish_death()`). Config `space_station_config.tres` (score 1000). Placed once: level 1 `_build_station_assault()`
  (`level_1_director.gd:313`), `b.space_station().at(0, -90)`, `ENEMIES_CLEARED`, timeout 180, **no `.delay()` / `.move()`** (load-bearing: `waves_complete` fires when the wave
  triggers; a path mover would free the boss off-screen). No laser columns are scheduled in `station_assault` (`Level1Director.laser_column_schedule()`).
- **`LevelDirector._wait_enemies_cleared`** polls `wave_manager.enemy_container.get_child_count()`; on timeout it frees every child (escape penalties). Bullets reparent into the
  container (`BulletPool` container = pool's grandparent).
- **`ScoreTracker`** (`assault/scenes/systems/score_tracker/score_tracker.gd`) listens to `WaveManager.enemy_spawned` and `EventBus.enemy_spawned_orphan` (→ wave −1 tally,
  `died` kill path, `tree_exited` escape path × 0.75 combo); it never disconnects the orphan signal.
- **`TurretMount.telegraph_gate`** is called as `telegraph_gate.call()` (no argument, `turret_mount.gd:279`); `ModularHull.build_mounts` passes one unbound Callable to every mount.
- **Inherited scenes:** `EnemyBeamScenes.export_of_scene()` (and so `TurretMountScenes.export_of()`) reads only the scene's own `SceneState`; Ph10's one inherited ring was
  checked by instantiating it. `scatter_round.tscn` `max_distance` 450; the burst-cannon `Muzzle` sits at (28, 0).
- **`CarrierHangars`** (`carrier_hangars.gd`): doors (CLOSED / OPENING `door_open_seconds` 0.8 / LAUNCH / OPEN `door_hold_seconds` 2.0), `set_vulnerable` on the hangar while open, light
  CHARGING, children seeded, `start_engaged`, one `SquadController` per payload scene cached for the carrier's life (`_squad(path)`), collision exceptions both ways, `host.get_parent().add_child`, owner group, `mover.boost(outward, 300, 0.4)`, orphan signal.
- **`EnemyShield`** (`global/components/enemy_shield.gd`): `attach(hurt_box) -> bool` (single absorber slot), `arc_deg ≥ 360` = bubble, `capacity`, `regen_delay`,
  `regen_seconds`, `reboot_seconds`, `radius`; absorbs nothing while its host (the hurtbox's parent) `is_armored()` — an `EnemyModule` is armoured while locked or wrecked.
  Direct emitters (player beam, nova, `LaserRay`) bypass it.
- **`EnemyBeam`**: `setup(host, owner_group)`, `start()`, `tick(delta)` (its only clock), `cancel()`, emitter along local +X, `registers_hazard` (`&"laser_wall"`, exempt = owner
  group); victims = `EnergyHitScan.VICTIM_GROUPS` (`player`, `allies`, `enemies`, `asteroids`) minus the owner set; parts are never victims. **`EnergyRing`**: `setup`, `start()`,
  `tick`, `cancel`, centre fixed at start, `max_radius`, `gap_count` / `gap_deg`, each target hit once per ring.
- **`EnemyMover.step()`**: with a face point, rotation turns toward it capped at `max_turn_rate` × delta (constant-rate spin by facing a point ahead); `constraint_mode` NONE for
  heavies; `hold_position`, `arrive`, `request_velocity`, `boost`, `halt`.
- **`BaseEnemy`**: `answers_emp()` = `is_ai_driven()` (brain ∧ mover ∧ not suspended); `apply_emp(seconds, source)` returns unless `answers_emp()`, halts the mover if any and calls
  `brain.on_emp_started()` if any (both null-guarded); `is_emp_disrupted()`, `emp_seconds_left()`; `_ready()` copies `counts_toward_wave_clear` / `counts_as_escape` from the config
  (a pre-`add_child` write to them is overwritten);
  `suspend_ai()`; brain and mover resolved as the first `EnemyBrain` / `EnemyMover` children (named `Brain` / `EnemyMover`).
- **Player tools:** default bullet 50 damage / 0.18 s; homing missiles lock group `enemies` and steer at `homing_point(from)`; warheads cross armour via `ArmorQuery`; beam and nova
  reach group `enemy_parts`; EMP Blast (5 s / 15 s cooldown) uses `answers_emp()` else process-disables the node.
- **Hub** (`open_space/scenes/levels/sector_hub.gd`): patrol draws 1–20 appended in order (`_spawn_patrol()`, seeds set before `add_child`); draw 19 Heavy Gunship (2600 ring,
  157.5°), draw 20 Carrier (3400 ring, −112.5°). `test_sector_hub_patrol.gd`: `_patrol_groups()` (15 groups), `_element_radius()`, clearance sweeps (interactables, TacticalSpace
  +100 / +300, defense site A/B, jammers C, Ph10 anchor spacing > 1000), hard counts `groups.size() == 15`, `seeds.size() == 21`, `_expected_seeds()` 20 draws, live children 21.
- **Gate time:** last recorded GUT 210.34 s (Ph10 t12); ceiling 240 s; escalate past a 237 s two-run mean.

## 2. Design

### 2.1 Boss phase ladder: `BossPhase` and `BossPhaseDriver` (IDEAS §25; t1)

**Files:** `global/boss/boss_phase.gd`, `global/boss/boss_phase_driver.gd`; tests `tests/unit/test_boss_phase_driver.gd`, `tests/integration/test_boss_phase_rules.gd`.

`class_name BossPhase extends Resource` (flat, scene-authored as sub-resources of the driver; **never written at runtime**):
- `enum Trigger { START, PARTS_DESTROYED, HEALTH_AT_OR_BELOW }` (append-only)
- `enum Change { MOVEMENT = 1, ATTACKS = 2, VULNERABLE = 4, ARENA = 8, REINFORCEMENTS = 16, VISUALS = 32 }` (append-only bit flags)
- exports: `phase_id: StringName`, `trigger: Trigger`, `module_ids: Array[StringName]` (PARTS_DESTROYED: count destroyed parts among these), `roles: Array[int]`
  (`EnemyModule.Role` values; used when `module_ids` is empty; both empty = any part), `count: int = 1`, `health_module: StringName` (HEALTH_AT_OR_BELOW: that part's `Health`;
  empty = the host root `Health`), `health_ratio: float = 0.5`, `@export_flags("Movement", "Attacks", "Vulnerable", "Arena", "Reinforcements", "Visuals") changes: int`.
- `static func change_count(mask: int) -> int`.

`class_name BossPhaseDriver extends Node` (a host root child named `PhaseDriver`):
- `@export var phases: Array[BossPhase]`.
- `signal phase_entered(index: int, phase_id: StringName)`.
- `bind(hull: ModularHull, host_health: Health) -> void`: connects `hull.module_destroyed`, `hull.module_damaged`, and `health_changed`-equivalents (`Health.amount_changed`) of
  the host and of every part named by a HEALTH rule; enters index 0 synchronously (emits `phase_entered(0, id)`), then `evaluate()`.
- `evaluate() -> void` (public; also called by the listeners): while the **next** phase's condition holds, enter it (emit). Conditions are checked only for the next phase, in
  order, so one hit that satisfies two rules enters both, in order, with two signals in the same call. One way: never steps back (a repair never undoes a phase).
- `current_index() -> int`, `current_id() -> StringName`, `has_reached(phase_id) -> bool`, `phase(index) -> BossPhase`.
- `validate(hull: ModularHull = null) -> PackedStringArray`: errors for: no phases; index 0 not START; a START after index 0; duplicate `phase_id`; a non-START phase with
  `change_count(changes) < 2`; a PARTS_DESTROYED with `count` < 1 or more than the parts it can count (needs `hull`); a `module_ids` / `health_module` the hull lacks; a
  `health_ratio` outside (0, 1).
- The driver **never applies a consequence**; the host listens to `phase_entered` and changes itself. A part already destroyed when `bind()` runs counts.

Rows (`test_boss_phase_driver.gd`, on `tests/helpers/fixture_modular_host.tscn` with a driver added in the test):
1. START entered on bind, `current_id()` correct, one signal.
2. PARTS_DESTROYED by role counts only that role; by ids counts only those ids; a locked part's deflected hit does not count.
3. Two rules satisfied by one `destroy()` enter both in order (two signals, same frame).
4. HEALTH_AT_OR_BELOW on a part (`health_module`) and on the host root; exactly at the ratio enters (boundary: `ratio × max` rounded the way `Health` stores it; one point above
   does not).
5. One way: `Health.increase()` after a HEALTH phase does not step back.
6. A later phase whose condition holds before its predecessor does not enter until the predecessor has.
7. `validate()` rejects each listed error (one row per error, parameterised) and accepts a well-formed ladder.

Gate (`test_boss_phase_rules.gd`, intent): sweeps every `.tscn` under `assault/` and `open_space/` whose state contains a `BossPhaseDriver` node, instantiates it, and asserts
`validate(hull)` is empty; a synthetic ladder with a one-change phase fails it (boundary). Empty sweep (before t5) passes with an explicit "0 scenes" note asserted ≥ 0 and
becomes ≥ 1 once t5 lands (t5 changes the expectation to "contains `space_fortress.tscn`").

### 2.2 Boss reinforcements and the escort path (IDEAS §10; t2)

**Files:** `global/boss/reinforcement_bay.gd`, `global/boss/boss_reinforcements.gd`, `global/boss/escort_container.gd`; `global/systems/event_bus.gd` (new signal);
`assault/scenes/systems/score_tracker/score_tracker.gd` (new handler). Tests `tests/integration/test_boss_reinforcements.gd` (+ a fixture `tests/helpers/fixture_boss_host.tscn`
built from `fixture_modular_host.tscn`'s pattern with a `Bay` on two parts).

`class_name ReinforcementBay extends Node2D` — a child named `Bay` of an `EnemyModule` (the part that launches), optional child `Mouth` (`Marker2D`; default the bay origin).
- `enum Trigger { PERIODIC, ON_SECTOR_LOSS, ON_PHASE }` (append-only).
- exports: `bay_id: StringName`, `trigger`, `payload_scene: PackedScene` (Open Space), `assault_payload_scene: PackedScene` (null = `payload_scene`), `count: int = 2`,
  `period: float = 12.0` (PERIODIC), `first_delay: float = 3.0` (PERIODIC, from the bay becoming active), `active_from_phase: StringName = &""` (empty = active from the start),
  `watch_ids: Array[StringName]` (ON_SECTOR_LOSS: each destroyed part among these queues one launch), `on_phase: StringName` (ON_PHASE: one launch on entering that phase),
  `door_seconds: float = 0.8` (telegraph before each launch), `open_hold_seconds: float = 0.0` (doors stay OPEN after the launch, the Carrier's `door_hold_seconds`), `opens_part: bool = false` (true: the part is vulnerable only while its doors are open — the Carrier hangar rule),
  `assault_launch_limit: int = -1` (−1 = no limit per life).
- `part() -> EnemyModule` (its parent), `mouth_position() -> Vector2` (global), `launch_direction() -> Vector2` (from the host centre through the mouth, normalised).

`class_name BossReinforcements extends RefCounted`:
- `_init(host: Node2D, hull: ModularHull, driver: BossPhaseDriver, rng: RandomNumberGenerator, owner_group: StringName, live_cap: int, boost_speed: float, boost_seconds: float)`;
  collects every `Modules/*/Bay`; connects `hull.module_destroyed` and `driver.phase_entered`.
- `tick(delta: float, active: bool) -> void` — the only clock (no `Timer`, no `create_timer`). `active` false (player not engaged, EMP window, host dying) freezes periodic clocks,
  holds queued launches and closes open doors.
- Door cycle per bay: a due launch → doors OPENING for `door_seconds` (part `Light` CHARGING; `opens_part` → `part.set_vulnerable(true)`) → LAUNCH (spawn) → OPEN for
  `open_hold_seconds` (still vulnerable; 0 passes straight through) → CLOSED (light back, `opens_part` → `set_vulnerable(false)`, deferred if inside a physics callback).
- A bay whose part is destroyed is **dead**: pending launches are dropped, it never launches again; a part destroyed mid-OPENING cancels that launch.
- ON_SECTOR_LOSS: a watched part's destruction queues one launch (several queue several, served one door cycle at a time).
- ON_PHASE: entering `on_phase` queues one launch of `count`.
- `surge(bay_id: StringName, count: int) -> void` — queue an emergency launch (dead bay: no-op).
- Cap: a launch spawns `min(count, live_cap - live_count())` escorts; 0 → the launch is skipped and counted (`skipped(bay_id)`); a PERIODIC clock keeps running.
- Mode: `EnemyWorld.arena(tree) != null` → Assault payload and `assault_launch_limit`.
- Spawn (one escort): instantiate the payload; if its `Brain` exposes `rng_seed` / `start_engaged`, set `rng_seed = rng.randi()` (non-zero) and `start_engaged = true`; if it has
  a `squad` property, give it the `SquadController` cached for its payload scene path on this `BossReinforcements` (one per payload scene for the boss's life, created at that
  scene's first launch: the `CarrierHangars._squad(path)` rule). **No write to `counts_toward_wave_clear` / `counts_as_escape`**: `BaseEnemy._ready()` would overwrite them from
  the escort's config anyway, `false` would make the Support Ship treat escorts as non-combatants, and the escort scoring path never reads them. Position `mouth_position()`; collision exceptions both ways with the host; add to `EscortContainer.ensure(host)`; `add_to_group(owner_group)`;
  `mover.boost(launch_direction(), boost_speed, boost_seconds)`; `EventBus.boss_escort_spawned.emit(escort, host)`.
- `escorts() -> Array` = the live (not queued-for-deletion) `BaseEnemy` children of `EscortContainer.of(host)` (empty when there is none), so the container is the one source of
  truth. `scuttle_all() -> void` — `health.set_health(0)` on every one of them (their normal death: explosion, squad bookkeeping); `live_count()` = `escorts().size()`,
  `bay_ids()`, `launches(bay_id) -> int`, `skipped(bay_id) -> int`, `pending(bay_id) -> int`, `door_open(bay_id) -> bool`, `is_dead(bay_id) -> bool`.
- Signals: `launched(bay_id: StringName, escorts: Array)`, `door_changed(bay_id: StringName, open: bool)`.

`class_name EscortContainer` (static helper, `extends RefCounted`): `static func ensure(host: Node2D) -> Node2D` — finds or creates (lazily, at the first launch) a `Node2D`
named `<host.name>Escorts` as a sibling of the host (child of `host.get_parent()`), group `&"boss_escorts"`, meta `boss` = the host; connects `host.tree_exiting` → the container's
`queue_free`. `static func of(host) -> Node2D` (null if none). The host's `_finish_death()` frees it explicitly too. Escort pools resolve their container as the escort's parent
(the escort container), so escort bullets and explosion particles live and die there.

**Why a container node:** `LevelDirector` keeps counting the enemy container's children (unchanged); the boss, its bullets and one escort container are all the section waits
for, and the container goes with the boss. Escorts keep `enemies` group membership, so homing locks, the nova, EMP and squad logic see them as normal ships.

`EventBus`: `signal boss_escort_spawned(escort: Node, boss: Node)`. `ScoreTracker`: connects it in `start_tracking()` (beside the orphan signal; no disconnect, as for the orphan signal) to
`_on_boss_escort_spawned(escort, boss)`: connects `escort.died` (one-shot) to award `floor(score_value × combo)` and the normal combo step **unless** `boss` is freed or
`boss.is_dying()` (duck-typed); no wave tally, no `tree_exited` escape path.

Rows (`test_boss_reinforcements.gd`, hand-ticked on the fixture host, both harnesses where mode matters):
1. PERIODIC: first launch at `first_delay` + `door_seconds`, then every `period`; `active_from_phase` holds it until the driver reaches that phase.
2. Door telegraph: light CHARGING and (with `opens_part`) part vulnerable exactly during OPENING + OPEN (`open_hold_seconds`; 0 = OPENING only); closed after.
3. ON_SECTOR_LOSS: destroying a watched part launches once; an unwatched part launches nothing; two watched parts queue two launches.
4. Dead bay: destroying the bay's own part drops pending launches; a part destroyed mid-OPENING launches nothing.
5. Cap: with `live_cap` 4 and 3 alive, a count-2 launch spawns 1; at 4 alive it is skipped and counted.
6. Escorts land in `<host>Escorts` (sibling of the host), not in the host's parent directly; the container is created lazily (none before the first launch) and freed when the host
   is freed; escorts are in the owner group, `start_engaged`, seeded (two hosts with the same rng seed give the same escort seeds), boosted outward from the mouth.
7. Mode: the Assault harness spawns `assault_payload_scene` and honours `assault_launch_limit`.
8. `active == false` freezes the periodic clock and closes an open door.
9. `surge()` queues `count`; a dead bay ignores it.
10. ScoreTracker: an escort kill pays `score_value × combo` and steps the combo; freeing an unkilled escort costs no combo; no wave tally is created (`section` wave-clear bonus
    unaffected); a kill after the host `is_dying()` pays nothing.
11. An `ENEMIES_CLEARED` director row (real `LevelDirector`, bare container, as `test_station_assault_section.gd` builds it): host + 3 escorts → the section waits on the host
    only; freeing the host frees the escort container and the section advances.
12. No `enemy_spawned_orphan` is emitted by a bay launch (spy).
13. Squads: two launches of one payload scene share one `SquadController`; a second payload scene gets its own.
14. Escort flags: an escort's `counts_toward_wave_clear` / `counts_as_escape` equal its config's after `_ready()` (nothing overwrites them).

### 2.3 Mount variants: spread cannon and rapid pulse (IDEAS §8.1 battery list; t3)

**Files:** `assault/scenes/enemies/defense_turret/mounts/turret_mount.gd` (enum), `burst_cannon_mount.gd` (exports), new `spread_cannon_mount.tscn`, `rapid_pulse_mount.tscn`,
`turret_mount_scenes.gd`, head art in the mount art directory used by `tests/integration/test_ph8_sprites.gd` (`HEADS`).
- `TurretMount.Variant`: append `SPREAD_CANNON` (7) and `RAPID_PULSE` (8). `TurretMountScenes` gains both (`scene_for`, `export_of`, `reach_of`).
- `BurstCannonMount`: new exports `pellets: int = 1`, `pellet_spread_deg: float = 0.0`; each shot of a burst fires `pellets` rounds evenly across `pellet_spread_deg` centred on
  the aim. **At `pellets` 1 every existing mount is bit-identical** (a recorded trace row like `TRACE_360` in `test_turret_mount_traverse.gd`). Pool size from `pool_specs()`
  scales with `pellets`.
- **Both new mount scenes are standalone** (built like `heavy_cannon_mount.tscn`: their own root with the `BurstCannonMount` script, `Head`, `Muzzle` at (28, 0), every export
  authored), **never inherited from `burst_cannon_mount.tscn`**: `TurretMountScenes.export_of()` reads only a scene's own `SceneState`, so an inherited scene would report script
  defaults for every value it does not re-author, and the lifetime sweep reads mount speeds that way.
- `spread_cannon_mount.tscn`: Scatter round (`EnemyRounds.SCATTER`, expires at `max_distance` 450 px), `pellets` 5, `pellet_spread_deg` 40, `burst_count` 2,
  `burst_gap` 0.45, `charge_seconds` 0.5, `round_speed` 260, **`fire_range` 420** (inside the round's reach: 450 + the 28 px muzzle offset ≈ 478 px from the mount), `cooldown_seconds` 2.8.
- `rapid_pulse_mount.tscn`: Pulse round, `burst_count` 10, `burst_gap` 0.07, `charge_seconds` 0.3, `round_speed` 340, `fire_range` 760,
  `cooldown_seconds` 2.6, `turn_rate` 2.6.
- Head art: one 64×64 head per new variant (pivot (32, 32)), generated with PixelLab (`pixel-art-generation` skill), ≤ 90 % opaque; `HEADS` gains both rows.
- `test_enemy_bullet_lifetime.gd`: both mounts' round speeds join `_every_shipped_enemy_bullet_speed()`; Scatter at 260 px/s fits its lifetime.

Rows (`tests/integration/test_turret_mount_variants.gd`, hand-ticked fixture mount like `test_turret_mount_traverse.gd`): a spread burst fires 2 × 5 rounds, the outer pellets
±20° from the aim, each a Scatter round; a rapid burst fires 10 rounds 0.07 s apart; `pellets` 1 trace unchanged; `TurretMountBuilder.build()` builds both variants with their pools;
**reach:** for every `TurretMount.Variant` that fires `EnemyBullet` rounds, `fire_range ≤ round max_distance` (round scene instantiated) — a spread mount at 520 fails it (boundary);
`export_of()` on both new scenes returns the authored values (`round_speed`, `fire_range`, `pellets`), not script defaults.

### 2.4 Shared boss death sequence (t4)

`git mv assault/scenes/enemies/space_station/station_death_sequence.gd global/boss/boss_death_sequence.gd` **and** its sidecar `station_death_sequence.gd.uid` →
`global/boss/boss_death_sequence.gd.uid` (same UID, moved, never re-minted), `class_name BossDeathSequence` (was `StationDeathSequence`); the station's `DeathSequence` node uses it:
update the `ext_resource` path in `space_station.tscn` (line 13 today). **Behaviour-identical, not byte-identical:** the script holds `var _station: SpaceStation` and casts
`get_parent() as SpaceStation`; both become a duck-typed host (`_host: Node2D`, checked with `has_signal(&"death_started")` and `"death_duration" in host`), and the "not a
SpaceStation" warning text becomes "host lacks death_started / death_duration". Every other reference to `StationDeathSequence` (`test_station_death_sequence.gd`, comments in
`explosion_effect.gd` and `tests/unit/test_explosion_effect.gd`) follows the rename. The host contract becomes explicit in the doc comment and duck-typed: signal `death_started`, property
`death_duration: float`, optional `config.death_blast_count`; exports unchanged (`blast_spread_radius` 96, `blast_particle_amount` 18, `blast_shake` 0.25, `final_shake` 1.0,
`death_spin` 1.2, `burnt_tint`). Rows: `test_station_death_sequence.gd` stays green with only the class name changed, `test_resource_uid_integrity.gd` and
`test_project_load_integrity.gd` stay green (the moved `.uid` is the proof), and one new row: a host without `death_started` gets the warning and no crash. Later, t11 renames `test_station_death_sequence.gd` (it renames the file to `test_boss_death_sequence.gd` and points it
at the fortress). Allowed writer note: it writes the dying host's `rotation` / `modulate` after the host has called `suspend_ai()` (documented in the script).

### 2.5 Space Fortress shell (IDEAS §8.1, §22–23, §26, §39; t5)

#### 2.5.1 Files and scene

`assault/scenes/enemies/space_fortress/`: `space_fortress.tscn`, `space_fortress.gd` (`SpaceFortress extends BaseEnemy`), `fortress_brain.gd` (`FortressBrain extends EnemyBrain`;
t5 builds its shell — phase wiring, EMP hooks — t6 its movement, t7 its weapons, t8 its bays), `space_fortress_config.gd` / `.tres` (flat `SpaceFortressConfig extends ShipConfig`),
`ENEMY.md`. `WaveBuilder.space_fortress()` / `SPACE_FORTRESS`.

Scene (root `SpaceFortress`, `CharacterBody2D`, **layer 0, mask 0**):
- `Sprite2D` (hull; placeholder `station_core.png` scaled to the hull until t9), `CollisionShape2D` (`CircleShape2D` r 176, shared sub-resource), `HurtBox` (layer 512,
  mask 1121, same shape), `Health`, `HitFlashAnimationPlayer`, `ContactHitBox` (layer 256, damage from `collision_damage` 40, same shape and scale), `ContactProfile` (mode
  ARMOR, `shove_speed` 260), `EnemyMover` (`constraint_mode` NONE), `Brain` (`FortressBrain`), `StateLight`, `ModularHull`, `PhaseDriver` (§2.5.5), `DeathSequence`
  (`BossDeathSequence`, `blast_spread_radius` 150), `Modules` (§2.5.2), `HullBeams` (t7), `PulseRing` (t7), `Thrusters` (t6/t9 visual), `CriticalOverlay` (t9 visual).
- Owner group `&"fortress_<instance_id>"` joined in `_ready()`; `world_anchored_x` true (the Carrier's rule: `global_position.x -= view_rect.center.x -
  projectile_world_rect.center.x` once in Assault).

#### 2.5.2 Parts

Hull circle r 176 (sprite canvas 384 × 384). Local bearing 0° = +x, 90° = +y.

| Node / id | Role | Local centre | Hurtbox | HP (config) | Starts vulnerable | Mount slot (t7): variant, rest, traverse | Sector |
|---|---|---|---|---|---|---|---|
| `BatterySpread` / `battery_spread` | WEAPON | 45°, r 140 → (99, 99) | circle r 22 | `battery_health` 260 | yes | SPREAD_CANNON, 45°, 100° | south |
| `BatteryPulse` / `battery_pulse` | WEAPON | 135° → (−99, 99) | circle r 22 | 260 | yes | RAPID_PULSE, 135°, 100° | south |
| `BatteryArtillery` / `battery_artillery` | WEAPON | 225° → (−99, −99) | circle r 22 | 260 | yes | HEAVY_CANNON, 225°, 100° | north |
| `BatteryMissiles` / `battery_missiles` | WEAPON | 315° → (99, −99) | circle r 22 | 260 | yes | ROCKET_BATTERY, 315°, 100° | north |
| `BatterySweep` / `battery_sweep` | WEAPON | 0° → (150, 0) | circle r 22 | 260 | yes | SWEEP_BEAM, 0°, 140° | south |
| `Hangar` / `hangar` | HANGAR | 180° → (−150, 0) | rect 36 × 56 | `hangar_health` 300 | no (doors, §2.8) | — | north |
| `ShieldNorth` / `shield_north` | WEAK_POINT | (0, −120) | circle r 26 | `shield_node_health` 360 | no (opens in `shields_exposed`) | — | — |
| `ShieldSouth` / `shield_south` | WEAK_POINT | (0, 120) | circle r 26 | 360 | no | — | — |
| `Core` / `core` | CORE | (0, 0) | circle r 44 | `core_health` 1500 | no (opens in `core_exposed`) | — | — |

Every part: `Sprite` (placeholder until t9), `HurtBox`, `Health`, `HomingPoint` (the part centre), `Light` (`StateLight`), wreck texture; batteries carry `MountSlots/Slot0`
(`TurretMountSlot`); `Hangar`, `ShieldNorth`, `ShieldSouth` carry a `Bay` (t8). Parts sit fully inside the hull circle; with an armoured hull a projectile crosses the hull to
whichever part lies on its path (no flush-edge rule). `hull_share` 0 everywhere. `homing_point(from)` on the root = the nearest live **vulnerable** part's `homing_point()`
(the core's centre once nothing else is vulnerable).

#### 2.5.3 Armoured hull, core and death

- Root `deflects_hit()` and `is_armored()` → true; `_on_received_damage` emits `armor_deflected(damage: int)` and flashes, never touches `Health`; `is_laser_blocking()` false;
  `launch_velocity()` = mover velocity; `rocket_clear_radius()` = 176 + 8; `accepts_ward()` false; `can_be_repaired()` false; `accept_tow()` refused (brain `accepts_tow()` false).
- Root `Health.max_health` = `config.core_health` (the death plumbing; never decreased by hits). Core `destroyed` → `health.set_health(0)`.
- Death (`_on_health_changed` at 0, latched once, the station's order kept): `was_killed = true`, emit `died`, corpse harmless (hurtbox monitoring off, contact layer 0, both
  deferred), `suspend_ai()`, every mount `power_down()`, spoke beams and ring `cancel()`, core-ring pool `cancel_active()`, `reinforcements.scuttle_all()` (t5 creates the
  fortress's `BossReinforcements` from t2's class with the fortress's bays absent until t8, so `scuttle_all()` is a no-op until then; `EscortContainer.of(self)` is null until a
  launch), emit `death_started`,
  start the death timer (`death_duration` = `config.death_sequence_duration` 2.4) → `_finish_death()`: explode, free the escort container, `queue_free()`. `is_dying()` true from
  the latch. `death_duration` 0 behaves like `BaseEnemy` (immediate). t5 depends on t2 for `BossReinforcements` / `EscortContainer` (§2.2: `scuttle_all()`, `EscortContainer.of(host)`,
  `ensure(host)`; the container is a `<host name>Escorts` `Node2D` sibling of the host, freed with it).
- Score `score_value` 1500 (station 1000), `counts_toward_wave_clear` true, `counts_as_escape` true (a timeout escape costs combo, as the station did).

#### 2.5.4 Shield sectors

`class_name ShieldSector extends RefCounted` (`global/boss/shield_sector.gd`): `_init(generator: EnemyModule, protected: Array[EnemyModule], params: Dictionary)` with
`capacity`, `regen_delay`, `regen_seconds`, `reboot_seconds`, `radius_pad`.
- On construction builds one `EnemyShield` per live protected part: `arc_deg` 360 (bubble), the params, `radius` = part hurtbox radius (or half-diagonal) + `radius_pad`,
  `attach(part.hurt_box)` (skip with a verbose note if the slot is taken), added as a child of the part.
- Generator `destroyed` → every shield of the sector is freed (`clear_absorber`) in the same call: **the sector is exposed for good**. A protected part's `destroyed` frees its
  own shield. Generator alive → shields regenerate / reboot by `EnemyShield`'s own clock (no sustain mode).
- `is_exposed() -> bool`, `shield_of(id) -> EnemyShield`, `shields() -> Array`, `generator()`.
- The generator's `Light` shows `StateLight.State.SHIELDED` (appended, cyan) while it lives.
- Fortress config: `sector_shield_capacity` 120, `sector_shield_regen_delay` 3.0, `sector_shield_regen_seconds` 2.0, `sector_shield_reboot_seconds` 5.0, `sector_shield_pad` 8.
  (The hangar's bubble absorbs only while its doors are open, because a locked part is armoured.)

#### 2.5.5 Phase ladder and consequences

`PhaseDriver.phases` (scene sub-resources):

| # | `phase_id` | Trigger | Declared `changes` |
|---|---|---|---|
| 0 | `batteries` | START | — |
| 1 | `shields_exposed` | PARTS_DESTROYED, roles [WEAPON], `count` = `config.shields_exposed_battery_losses` 2 (**the scene value must equal the config value; a row checks it**) | VULNERABLE, ATTACKS, MOVEMENT, REINFORCEMENTS, VISUALS |
| 2 | `core_exposed` | PARTS_DESTROYED, ids [`shield_north`, `shield_south`], count 2 | VULNERABLE, MOVEMENT, ATTACKS, ARENA, VISUALS |
| 3 | `critical` | HEALTH_AT_OR_BELOW, `health_module` `core`, ratio 0.4 | MOVEMENT, ATTACKS, REINFORCEMENTS, VISUALS |

Consequences, applied by `SpaceFortress._on_phase_entered(index, phase_id)` (t5 builds the vulnerability and visual ones; t6, t7, t8 add theirs to the same handler):
- `shields_exposed`: both shield parts `set_vulnerable(true)` (deferred), generator shutter texture opens (t9 art), spoke beam volleys + spin armed (t7, t6), hangar bay active (t8).
- `core_exposed`: core `set_vulnerable(true)` (deferred), core plating texture opens, thrusters visible, movement starts (t6), pulse ring armed (t7).
- `critical`: `CriticalOverlay` visible, core light blinks (`StateLight` COMMIT), continuous spin + 4 spokes, cooldowns × 0.6, core bullet ring (t7), hangar surge (t8).

`SpaceFortress.phase_snapshot() -> Dictionary` with keys `&"movement"`, `&"attacks"`, `&"vulnerable"`, `&"arena"`, `&"reinforcements"`, `&"visuals"`, each a comparable value:
movement = brain movement phase + current speed / spin limits; attacks = sorted armed weapon ids + cooldown factor + spoke count + ring period + core-ring flag; vulnerable =
sorted ids of live vulnerable parts; arena = pulse ring armed + registered hazard count; reinforcements = sorted active bay ids + their periods; visuals = part textures +
light states + `Thrusters.visible` + `CriticalOverlay.visible`. **The §25 row** (built in t5 for the keys t5 owns, extended by t6–t8 as they land; final form in t8): for each
phase entry, the keys whose value changed ⊇ the declared `changes` and number ≥ 2.

#### 2.5.6 EMP, homing, ward, tow

- `answers_emp()` → `is_dying() or super()`: true while alive (brain + mover) **and while dying** (after `suspend_ai()` `is_ai_driven()` is false, and `EMPBlastModule` would
  otherwise process-disable the wreck, pausing the death timer and `BossDeathSequence` and holding the section 5 s; the station had this gap). `apply_emp(seconds, source)` is
  overridden: a no-op while `is_dying()`; otherwise `super(seconds * config.emp_factor, source)` (`emp_factor` 0.4 scales **every** EMP source; Ph11 owner choice 6). The
  brain's `on_emp_started()` silences everything it ticks: mounts `scan(0.0)`, beams and ring `cancel()`, bays inactive; shields are passive and stay. The fortress stays
  tangible. The window is the `BaseEnemy` clock; nothing restarts a cancelled attack before the window ends.
- `homing_point(from)` as §2.5.2. Not wardable, not towable, not repairable.

#### 2.5.7 Rows (t5; `tests/integration/test_space_fortress.gd`, both harnesses unless noted)

1. Geometry: hull circle r 176 shared by body / hurtbox / contact; parts at the table's centres (0.01 px) and sizes; every part inside the hull circle; layer 0 / mask 0 root.
2. Armour: a real `bullet.tscn` (8×) fired at the bare hull between parts is deflected (`armor_deflected`, root `Health` unchanged) and keeps flying; a bullet on a battery lane
   hits the battery's shield first, then (shield broken) the battery, never the core (the station's lane rows, re-expressed).
3. Locked parts: core, shields and hangar ignore bullets, the player beam (`BeamDriver`) and the nova while locked (the Ph10 locked-part rule).
4. Sector shields: a bubble on every battery and the hangar; capacity / reboot from config; killing `shield_north` frees the north bubbles in the same call and leaves the south
   ones; a destroyed battery's bubble is freed; a hit on the hangar's bubble while its doors are closed is not absorbed (the part is armoured).
5. Phase ladder: two batteries destroyed → `shields_exposed`, generators vulnerable (one frame later, deferred), one battery is not enough; both generators → `core_exposed`,
   core vulnerable; core at 40 % → `critical`; the scene's `count` equals `config.shields_exposed_battery_losses`.
6. §25 row (keys owned by t5: `vulnerable`, `visuals`) — later tasks extend it. **Its scripted path is pinned:** destroy `battery_spread` and `battery_pulse` (→ `shields_exposed`),
   then `shield_north` and `shield_south` (→ `core_exposed`), then damage the core to 40 % (→ `critical`) **with the hangar alive** (t8's `critical` hangar surge is a declared
   REINFORCEMENTS change that needs a live hangar). A second row, added by t8, runs the same path with the hangar destroyed first and asserts only ≥ 2 observed changes per phase.
7. Death: core destroyed → `died` once, `was_killed`, `death_started`, contact layer 256 → 0, wreck in the tree for `death_duration`, then freed; escort container freed with it;
   duration 0 frees at once.
8. EMP: `EmpPulse.emit(..., TARGET_ENEMIES)` reaches it (`answers_emp()`), window = 5 × 0.4 = 2.0 s, mover halted, still tangible (a bullet still hits a battery).
   **While dying:** a real `EMPBlastModule` pulse during the death sequence leaves `process_mode` unchanged, starts no EMP window, and the fortress is freed on time
   (`death_duration` after the core's death).
9. `homing_point` returns the nearest live vulnerable part; the core once only it remains.
10. Config: `.tres` values win over the scene's `Health` nodes; `SpaceFortressConfig` is flat (the isolation sweep covers it); the `PhaseDriver` / `DeathSequence` children read the
    private config copy in their `_ready()` (identity check, the station row re-expressed).
11. `WaveBuilder.space_fortress()` returns the scene; the roster gates of §2.14 include it.

### 2.6 Fortress movement (IDEAS §8.1 Open Space movement and Assault adaptation; t6)

`FortressBrain.Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }` (append-only). `assault = EnemyWorld.arena(get_tree()) != null`, read in `_start()`.

**Facing rule (both modes, every phase but spins):** `present_side()`: for each sector, strength = live batteries of that sector with a live shield (×1.0) or without (×0.5);
the strongest sector's centre bearing (north 270°, south 90°) is turned toward the player: `face_toward(pos + Vector2.from_angle(bearing_to_player - local_bearing +
sprite_forward_angle) * 100)`. `max_turn_rate` = `turn_rate` (OS 0.22 rad/s, Assault `assault_turn_rate` 0.30). Ties keep the current side. A circling player at 500 px and
420 px/s moves at 0.84 rad/s, ~4× the turn rate, so circling reaches the weak side (row checks `turn_rate × 500 < 0.5 × player max speed`, speed read from the player scene).

**Spins:** during a spoke volley (t7 calls `brain.begin_spin(direction)` / `end_spin()`) and continuously in `critical`, the brain faces a point 1 rad ahead of the current facing
with `max_turn_rate` = `beam_spin_rate` 0.5 (`critical_spin_rate` 0.6); direction alternates per volley.

**Open Space:** `patrol_anchor` (INF = spawn position) is the **combat zone** centre; `AnchorIdle(anchor, perceive_radius 1400, lose_radius 2600, notice_time 0.8,
idle_radius 8)`. IDLE: hold the anchor, slow idle spin `idle_spin_rate` 0.08, weapons and bays inactive. NOTICING → HOLD. HOLD (`batteries`, `shields_exposed`): `hold_position(
station_point, 24, 40)`; `station_point` starts at the anchor. REPOSITION (`core_exposed`, `critical`): every `reposition_period` (8.0 s; `critical` 5.0 s) pick a new station
point: 8 candidates on the circle of radius `0.6 × zone_radius` (zone 600) around the anchor, the one farthest from the player's position 1 s ahead, at least 250 px from the
current point; `arrive()` there at `reposition_speed` 60 (`critical` 90), `Thrusters` visible while travelling. Leash: a station point never lies outside the zone; the player
beyond `lose_radius` → RETURNING (arrive at the anchor, weapons / bays inactive, damage and boss phase kept) → IDLE. `start_engaged` skips IDLE.

**Assault:** no `EngagementBudget`, no exit (the section timeout is the only end besides death). ENTER: `request_velocity(0, assault_enter_speed 90)` until world y ≥
`assault_hold_y` 180, then HOLD (`batteries`, `shields_exposed`): hold at (anchor x, 180). From `core_exposed`: vertical bob between `assault_hold_y ± assault_bob_amplitude`
(100) at `assault_bob_speed` 35 (`critical` 55), reversing at the ends; **x never moves** (x velocity = a correction to the anchored x only, ≤ 20 px/s). Facing rule and spins as
above. EMP in Assault: the mover is halted (base rule); the fortress just stops — nothing must cross.

Rows (`test_space_fortress.gd` movement block; hand-ticked, both harnesses unless noted):
1. OS idle: holds the anchor ± 8 px for 20 s, spins at `idle_spin_rate`, perceives the player inside 1400 px after `notice_time`, not at 1450.
2. Facing: with the north sector strongest the north side turns to the player at ≤ `turn_rate`; after both north batteries die it turns the south side (the weak side changes);
   a player circling at 0.84 rad/s keeps a growing angle to the presented side (circling wins).
3. Phases: no translation in `batteries` / `shields_exposed` (OS ≤ 24 px from the station point); in `core_exposed` each new station point **is the rule's pick**: among the 8
   candidates on the 0.6 × `zone_radius` circle that lie ≥ 250 px from the current point, the one farthest from the player's position 1 s ahead (ties: lowest candidate index),
   recomputed independently by the test from the same inputs; it lies inside the zone, ≥ 250 px from the old point (it need **not** be farther from the player than the old one:
   when the old point was already the farthest, the winner is nearer); never outside the zone over 60 s of a chasing stub; `critical` repositions every 5 s at 90.
4. Leash: a player beyond `lose_radius` → RETURNING → IDLE at the anchor; boss phase unchanged.
5. Assault: enters from above to y 180 and holds; from `core_exposed` bobs within 180 ± 100; world x constant (± 1 px) for 60 s in every phase; rotation still follows the
   facing rule (the side presented changes when a sector dies).
6. Spin: a volley spin turns at `beam_spin_rate`, alternating direction; `critical` spins continuously.
7. EMP: no motion and no rotation for the window (both modes).
8. Extend the §25 row with `movement`.

### 2.7 Fortress weapons and geometry weapons (IDEAS §8.1 batteries, §24, §26; t7)

**Batteries:** `ModularHull.build_mounts(self, rng, owner_group, brain.attack_gate, 0)` builds the five battery mounts (part table in §2.5.2: spread SPREAD_CANNON at 45°, pulse
RAPID_PULSE at 135°, artillery HEAVY_CANNON at 225°, missiles ROCKET_BATTERY at 315°, all with a 100° traverse; sweep SWEEP_BEAM at 0° with 140°). `brain._tick_weapons(delta)` (the Carrier's
rule): target = `TargetInfo` of the player; `host_can_fire` = engaged (OS COMBAT / Assault after ENTER) ∧ not EMP ∧ (Assault: hull centre inside `EnemyWorld.view_rect()`) ∧
(`can_see_player()` on a physics frame or `mount.fires_past_cover()`); otherwise `scan(delta)`.
- `attack_gate() -> bool` — **zero arguments**: `TurretMount` calls `telegraph_gate.call()` and `build_mounts` hands the same unbound Callable to every mount. True iff fewer
  than `max_concurrent_attacks` 2 (`critical_max_concurrent_attacks` 3 in `critical`) of the fortress's battery mounts are in TELEGRAPH or FIRE (the asking mount is still in TRACK, so it is not counted) — never a
  wall of five bursts at once.
- **Diagonal crossfire:** the four corner mounts rest on their outward diagonals with a 100° traverse, so each covers its own diagonal lane; the sweep covers 140° around
  local 0°. A destroyed battery's mount is UNPOWERED by its part (Ph10), so **its lane goes quiet** (§26: a destroyed battery removes an attack angle).
- `critical`: every live battery's `cooldown_seconds` × `critical_cooldown_factor` 0.6, applied once to the instanced mount nodes (never to a resource).

**Spoke beams (rotating hull beams, the station's laser phase moved onto `EnemyBeam`):** `HullBeams/Spoke0..3` (Node2D emitters on the hull edge, r 176, pointing outward along
local 270°, 90°, 0°, 180°), each with a child `fortress_spoke_beam.tscn` (inherits `enemy_beams/beam.tscn` and **authors in its own scene every value a gate reads**:
`telegraph_seconds` 1.2, `active_seconds` 2.5, `length` 900,
`damage` 14, `rehit_interval` 0.55, `registers_hazard` true). From `shields_exposed`: a volley every `spoke_period` 8.0 s fires Spoke0 + Spoke1; `critical`: all four every
`critical_spoke_period` 6.0 s. A volley calls `brain.begin_spin(dir)` at ACTIVE start and `end_spin()` at FADE. Owner-ticked by the brain; the owner set (fortress + escorts) is
exempt. The hull spin sweeps them (geometry).

**Ring pulse (radial pulses from the ring):** `PulseRing` (`fortress_pulse_ring.tscn`, inherits `enemy_beams/energy_ring.tscn`, authoring every gated value itself: `max_radius` 640, `ring_speed` 300,
`band` 24, `gap_count` 2, `gap_deg` 50, `damage` 14, `telegraph_seconds` 1.0), from `core_exposed`, every `ring_period` 6.0 s (`critical` 3.5 s), centred on the hull at start.

**Core bullet ring (the station's precessing ring, kept per §39):** `CoreRingPool` (`BulletPool`, `enemy_bullet.tscn`, `pool_size` 48, a **direct root child**) and a runtime
`RadialAttackPattern` (`bullet_count` 12, full ring, `bullet_damage` 10, `bullet_speed` 210, `spawn_radius` 60, `base_angle` += `core_ring_step` 0.24 per ring), `critical` only,
every `core_ring_period` 2.0 s, ticked by the brain (no Timer).

**EMP / death:** EMP cancels beams and the ring, scans mounts; death powers mounts down, cancels beams and the ring, `cancel_active()` on the core-ring pool. Persistent rockets
(`ROCKET_BATTERY` pools, `persist_after_owner_death`) outlive the fortress by at most their `max_time` (6 s; read it from the rocket scene, do not type it).
**This makes the fortress the second bounded exception** (after the Ph10 Heavy Gunship) to the recorded rule "persistent-ordnance enemies stay out of `ENEMIES_CLEARED`
 sections": its tail after death is `death_duration` + the rocket `max_time`, all inside the section's poll. t7 records it in `ENEMY.md` and in `DECISIONS.md` under
`### Phase 11, built in t7`; t10 adds the `test_engagement_deadline.gd` row (§2.10).

**Fairness rows (inequalities read from instantiated nodes — the spoke beam, the pulse ring, the mounts and both player scenes — never from `export_of()` on an inherited scene):**
- Spoke tip: `beam_spin_rate × (176 + 250) ≤ 0.8 ×` the Assault player's max speed and the Open Space ship's `max_speed` (a player 250 px off the hull can outrun a sweep);
  same for `critical_spin_rate`.
- Spoke telegraph ≥ 1.0 s and drawn ≥ 3 px (Ph8 rule); `rehit_interval` > player i-frames (0.5 s).
- Ring gap, **where it is narrowest**: a gap is a fixed angle, so its arc is shortest at the smallest radius a player can occupy, the hull edge plus the player's hurtbox radius.
  Row: `deg_to_rad(gap_deg) × (176 + r_player) ≥ 2 × (2 × r_player)` for both players, `r_player` = the `HurtBox` circle radius × its node scale (the Assault fighter: 5 × 2.7 =
  13.5 px, so 50° gives ≈ 165 px against 54). Boundary: a 15° gap fails it. (Measured at `max_radius` the row could never fail: 50° at 640 px is ≈ 558 px.)
- **Density (Assault, measured, every boss phase).** Count every round the fortress itself launches (`EnemyBullet`s from its battery and core-ring pools and `EnemyRocket`s;
  escorts excluded, as the station's legacy rate excluded its reinforcements; escort rounds are recorded beside it in `ENEMY.md`). The real `space_fortress.tscn` in the Assault
  harness, hand-ticked at 1/60 s, engaged, no EMP; for each boss phase with its **worst live-battery set** (`batteries`: all five; `shields_exposed`, `core_exposed`, `critical`:
  `battery_sweep` and `battery_missiles` destroyed, leaving the three highest-rate batteries; `critical` entered by damaging the core to 40 %), and for each of **five player-stub
  positions** in the view around the hull at world (640, 180) — S (640, 600), SW (240, 560), SE (1040, 560), W (160, 200), E (1120, 200) — run 1 s to settle, then count over
  10 s. Ceilings, every phase and every position: **mean ≤ 13.3 rounds/s** (2.0 × the station's legacy turret rate, 4 turrets × 3 bullets / 1.8 s = 6.67 /s) and **peak in any
  half-open 2 s window ≤ 30 rounds** (1.25 × the station's legacy peak: 4 × 3 × 2 volleys = 24; the Ph3 peak-window factor). Recorded per phase (worst position) in `ENEMY.md`.
  Planned upper bounds with no gate and every mount in arc (cycle = charge + (burst − 1) × gap + cooldown): `batteries` ≈ 6.3 /s (spread 2.67, rapid 2.83, artillery 0.47,
  rockets 0.31); `shields_exposed` / `core_exposed` ≈ 6.0 /s; **`critical` ≈ 14.5 /s** (cooldowns × 0.6: spread 3.80, rapid 4.02, artillery 0.67, plus the core ring 12 / 2.0 s =
  6.0) and a possible 34-round window — **above both ceilings**, so the `critical` rows can fail and the measurement decides. If one fails, tune, **never widen a ceiling**;
  levers in order: `core_ring_period` 2.0 → 2.5, `critical_cooldown_factor` 0.6 → 0.7, `critical_max_concurrent_attacks` 3 → 2; anything else stops the task and asks.

Rows (`tests/integration/test_fortress_weapons.gd`, hand-ticked unless noted, both harnesses):
1. Five battery mounts, variants and arcs per the table; pools are root children; `attack_gate` is callable with no argument (a real TRACK → TELEGRAPH transition through
   `telegraph_gate.call()`), and never lets a third mount telegraph (`critical`: a fourth).
2. Crossfire: a player on each corner diagonal is fired on by that corner's mount only; after the battery dies that bearing gets no battery fire for 20 s.
3. Nothing fires before ENTER ends (Assault) or before COMBAT (OS idle); nothing fires with the hull outside the view (Assault).
4. Spokes: none in `batteries`; in `shields_exposed` two spokes per volley, period 8.0 s, the hull spins only while they are ACTIVE; in `critical` four, period 6.0 s; a spoke hits
   the player (real physics, 8×) and not an escort in the owner group; no spoke damages a part or the root.
5. Ring: none before `core_exposed`; period 6.0 / 3.5 s; it hurts the player and an enemy outside the owner group; never the fortress or its parts.
6. Core ring: only in `critical`; 12 bullets; base angle advances 0.24 per ring; no bearing stays a safe lane for 5 rings (the station row re-expressed); bullets live in the enemy
   container (pool grandparent).
7. EMP silences all four weapon families for the window; death stops them and cancels the core-ring pool's bullets; a rocket already in flight survives the fortress (≤ 6 s).
8. Fairness rows above (spoke tip, telegraph, ring gap at the hull edge with its 15° boundary) and the density rows: 4 phases × 5 positions, mean and peak ceilings each.
9. Extend the §25 row with `attacks` and `arena`.

### 2.8 Fortress reinforcements (IDEAS §10 applied, §26; t8)

Bays (scene-authored, `ReinforcementBay`, §2.2):

| Part / bay | Trigger | Open Space payload × count | Assault payload × count | Other |
|---|---|---|---|---|
| `Hangar/Bay` `hangar` | PERIODIC, `active_from_phase` `shields_exposed` | `swarm_drone.tscn` × 3, period 12 | `swarm_drone.tscn` × 2, period 14 | `first_delay` 2, `opens_part` true, `door_seconds` 0.8, `open_hold_seconds` 2.0 (Carrier `door_hold_seconds` parity) |
| `Hangar/Bay` surge | `critical` entry → `surge(&"hangar", 4)` (the brain calls it) | swarm drones | swarm drones | only if the hangar lives |
| `ShieldNorth/Bay` `north_defenders` | ON_SECTOR_LOSS, watch `battery_artillery`, `battery_missiles`, `hangar` | `fighter.tscn` × 2 | `fighter.tscn` × 2 | `door_seconds` 1.0 |
| `ShieldSouth/Bay` `south_defenders` | ON_SECTOR_LOSS, watch `battery_spread`, `battery_pulse`, `battery_sweep` | `gatling_interceptor.tscn` × 2 | `gatling_interceptor.tscn` × 2 | `door_seconds` 1.0 |

- `BossReinforcements.new(self, hull, driver, rng, owner_group, live_cap, config.launch_boost_speed 300, config.launch_boost_seconds 0.4)` with `live_cap` =
  `config.escort_live_cap` 6 (OS) / `config.assault_escort_live_cap` 4 (Assault; the station's cap). Ticked by the brain with `active` = engaged ∧ not EMP ∧ not dying.
- **The hangar is killable while its generator lives** (§26 needs it reachable): it is hittable for `door_seconds` + `open_hold_seconds` = 2.8 s per launch, behind the north
  bubble (`sector_shield_capacity` 120). Feasibility row (config and scene values, player numbers read from the player scenes): `(door_seconds + open_hold_seconds) ×` the default
  gun's DPS (50 damage / 0.18 s ≈ 278 /s) `≥ sector_shield_capacity + hangar_health` (2.8 × 278 ≈ 778 ≥ 120 + 300 = 420): focused fire kills it in one open window. Boundary: with
  `open_hold_seconds` 0 the inequality fails (0.8 × 278 ≈ 222 < 420), which is the trap this row prevents.
- Meaning for the player (§26): killing the hangar stops the drones for good; killing a generator first stops its half's defenders; losing a battery while its generator lives
  calls that half's defenders; nothing launches in `batteries` unless a battery dies (the first loss launches its sector's defenders).
- Escorts are ordinary AI ships: in Assault they keep their own `EngagementBudget` and exit; in Open Space they fight in the zone (hub cleanup of escorts is Ph13 / Ph14; the cap
  bounds them). They are scuttled when the fortress's death starts.

Rows (`tests/integration/test_fortress_reinforcements.gd`, both harnesses):
1. No launch in `batteries` without a loss; the first battery lost launches its sector's pair after `door_seconds` (fighters north, gatlings south).
2. Hangar: first launch `first_delay` + door after `shields_exposed`, then every period; vulnerable exactly while the doors are OPENING or held OPEN (2.8 s); a real-bullet
   row kills it inside one open window with the generator alive (hand-fed 50-damage hits every 0.18 s); the feasibility inequality and its `open_hold_seconds` 0 boundary;
   destroyed → no further launch; `critical` surge only with a live hangar.
3. A generator destroyed → its bay never launches again (a later battery loss in its sector launches nothing).
4. Caps: OS 6, Assault 4; skipped launches counted.
5. Escorts land in `SpaceFortressEscorts` (the container name follows the node name), not the enemy container; the Assault section's `ENEMIES_CLEARED` waits only for the
   fortress; scuttled on death (each escort's `died` fires; the score row pays nothing for them); escorts fire within 3 s of launch in Assault (the station's rail-fire gate
   re-expressed for AI escorts: a TOP-equivalent fighter pair and a gatling pair each put ≥ 1 round in the escort container).
6. Bay launches ignore the camera pan (world-space mouth; the station's `test_spawn_camera_pan.gd` rows re-expressed).
7. Extend the §25 row with `reinforcements` (final form, on its pinned path with the hangar alive: every declared change observed, ≥ 2 per phase). Add the **dead-hangar
   row**: the same path with `hangar` destroyed before `critical`; assert ≥ 2 observed changes per phase (MOVEMENT, ATTACKS and VISUALS still change at `critical`) without
   requiring REINFORCEMENTS there.
8. Death order (from §2.5.3, built in t5): every live escort's `died` fires when the fortress's death starts (`reinforcements.scuttle_all()`), then the `SpaceFortressEscorts`
   container is freed with the fortress. "Engaged" (the bays' `active`) is the brain's notion from §2.6: Open Space COMBAT / HOLD / REPOSITION (not IDLE, NOTICING, RETURNING),
   Assault after ENTER ends.

### 2.9 Visual states and art (IDEAS §21–23; t9)

Light vocabulary (Ph10 convention, appended): red ARMED, yellow CHARGING (doors opening, beams telegraphing), white COMMIT (core blink in `critical`), orange VENTING (unused here),
**cyan `SHIELDED` (appended to `StateLight.State`, t5)**, dark OFF = wreck. The hull is never recoloured.

Art (`assault/assets/sprites/enemies/space_fortress/`, invoke `pixel-art-generation`; strict high top-down; drawn **to the frozen hurtbox sizes of §2.5.2 at scale 1**, every
texture ≤ 90 % opaque; the Ph10 workbench route is allowed):
- `fortress_hull.png` 384 × 384: dark ring hull with four corner bastions, two mid-side mounts, two generator wells and a core well as **empty sockets**, cool edge highlights
  (§21.2), red faction stripes.
- Per battery (5): intact + wreck (the mount head is the mount's own art). Hangar: closed / open / wreck. Each generator: shutter closed (`batteries`) / open (`shields_exposed`) /
  wreck. Core: plated / open / wreck (`core_open_texture` on exposure). `Thrusters` (4 small exhaust sprites, visible while repositioning). `CriticalOverlay` (crack-and-glow
  overlay ≤ 90 % opaque, visible in `critical`). Two mount heads (t3 made them; t9 may redraw in place).
- Visual phase changes: `shields_exposed` (shutters open, cyan lights), `core_exposed` (core plating open, thrusters), `critical` (overlay, core blink). Destroyed parts stay as
  wrecks (Ph10).
- Gate: `tests/integration/test_fortress_sprites.gd` (every texture loads, sizes match the hurtboxes, not an opaque card) and the transparency sweep (already walks every
  `Texture2D` property).

### 2.10 Level 1: the fortress replaces the station (t10)

`level_1_director.gd::_build_station_assault()`: the one wave becomes `b.wave(0.0, [b.space_fortress().at(0, -230)])` (world (640, −100): it descends to y 180), **still no
`.delay()` and no `.move()`**; section name `station_assault`, background, transition unchanged; `enemies_cleared_timeout` 180 → **240** (Ph11 owner choice 5). No laser column is
scheduled in this section; none may be added while the fortress lives.

Rows:
- `test_station_assault_section.gd`: the entry row now expects a path ending `space_fortress.tscn`, `spawn_delay` 0, `movement` null; the timeout row pins 240 (and keeps
  `cloud_descent` 10); the four generic `LevelDirector` rows unchanged.
- `test_level_1_sequence.gd`: the real fortress (`death_duration` 0.2) killed through `destroy()` on two batteries, both generators and the core → `was_killed`,
  `level_complete` reached.
- New `tests/integration/test_level1_fortress_section.gd` (real `WaveManager` + director, wall clock 1×, the `station_assault` section only, `death_duration` 0.2):
  (a) the section waits while the fortress lives with escorts alive (two swarm drones the test adds straight into `EscortContainer.ensure(fortress)` right after spawn: bays launch only once the fortress is engaged, after ENTER), and advances within `death_duration` + 0.5 s of the core's
  death with every escort scuttled — the parts are killed through `destroy()` **right after spawn**, before any rocket can be in flight, so the row never waits out the rocket
  tail (that tail is arithmetic, in the deadline row below); (b) with the fortress never killed, the timeout frees the fortress and its escort container (one escape penalty,
  the fortress's): the replay **overrides `enemies_cleared_timeout` on its own built copy of the section to 2.0 s** (`_wait_enemies_cleared` is a wall-clock deadline, so
  the shipped 240 s cannot be waited out in the gate); the shipped 240 s stays pinned by `test_station_assault_section.gd`.
- `test_engagement_deadline.gd` (the persistent-ordnance exception): a new row lists every `ENEMIES_CLEARED` section spawn whose scene builds a `persist_after_owner_death`
  pool (mount scenes read through `TurretMountScenes`, `BulletPool.persist_after_owner_death` on scene nodes) and asserts the set is exactly the allowlist {Heavy Gunship
  (Ph10), Space Fortress (Ph11)}; for the fortress it asserts `death_duration` + the rocket scene's `max_time` < the section's `enemies_cleared_timeout`. Boundary: a
  synthetic `ENEMIES_CLEARED` section holding a Missile Corvette fails the allowlist.
- Remove nothing else from level 1; the drone-density helper (`level1_drone_concurrency.gd`) ignores escorts (not WaveManager rows); its station BOTTOM-squad row goes with
  t11.

### 2.11 Retiring the space station and migrating its tests (Ph11 owner choice 1; t11)

Delete `assault/scenes/enemies/space_station/` (scripts, scenes, config, `ENEMY.md`), `WaveBuilder.space_station()` / `SPACE_STATION`, and the station PNGs no longer referenced
(retexture `tests/helpers/fixture_modular_host.tscn` with fortress part art first; keep any PNG still referenced). Update comments that cite the station as the load-bearing case
(`bullet.gd`, `enemy_module.gd`) to cite the fortress's armoured hull.

| File | Fate |
|---|---|
| `test_space_station.gd` | delete; intent lives in `test_space_fortress.gd` rows 2–3, 10 (t5) |
| `test_station_laser_phase.gd` | delete; intent in `test_fortress_weapons.gd` row 4 (t7) |
| `test_station_gunnery.gd` | delete; intent in `test_fortress_weapons.gd` rows 1, 6, 7 (t7) |
| `test_station_reinforcements.gd` | delete; intent in `test_boss_reinforcements.gd` (t2) and `test_fortress_reinforcements.gd` (t8), including the escorts-fire row replacing the rail-fire gate |
| `test_station_death_sequence.gd` | rename `test_boss_death_sequence.gd`, re-point at the fortress (blasts on the 176 px hull, spin, tint, config 2.4 s / 10 blasts) |
| `test_station_incoming_damage_paths.gd` | rename `test_fortress_incoming_damage_paths.gd`, re-point: homing missile (steers to `homing_point`) and warhead reach a battery, are refused by the hull; asteroid contact (bit 1024) deflected; mining laser not blocked by the layer-0 root; a layer-1 root would block it (boundary) |
| `test_station_assault_section.gd`, `test_laser_ray_hit_mask.gd`, `test_radial_attack_pattern.gd` | keep (generic; t10 already updated the first) |
| `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd` | drop the station roster entries (the fortress joined in t5); re-express the 88 × 240 boundary as "shrinking the fortress hull hurtbox to the core's circle fails the sweep" and the "core hurtbox spans the hull" row as "the hull hurtbox covers every part" |
| `test_entity_sprite_transparency.gd` | the station-corner row → the fortress hull's four corners are transparent; the control texture → a fortress part |
| `test_config_instance_isolation.gd` | the station-children row → removed (t5 added the fortress row) |
| `test_spawn_camera_pan.gd` | delete the two reinforcement-origin rows (t8 row 6 replaces them) |
| `test_explosion_effect_placement.gd` | the turret row → a fortress part's wreck blast lands outside the hull |
| `test_level1_drone_spawns.gd` | drop the station BOTTOM-squad row |
| `test_base_enemy.gd` | station exclusion / refuse-repair rows → the fortress |
| `test_enemy_bullet_lifetime.gd` | drop the `StationGunnery.new()` fallback (150) and `space_station_config.tres` speeds (the fortress core-ring speed 210 and both new mounts joined in t3 / t7). **Re-derive, never delete the checks:** `test_every_shipped_speed_source_is_at_or_above_150` becomes "the slowest shipped source is <whatever `speeds.min()` is after the deletion>, at its value" (read it, then pin the name and value in the assertion message and the number); `test_enemy_bullet_defaults_are_derived_from_every_shipped_speed_source` re-pins `expected_max_time` = `ceil(2274 / new_min) + 2` (it will be below 18) and `expected_max_distance` 2400 as the computed values, and keeps asserting the shipped `enemy_bullet.tscn` `max_time` 18 s / `max_distance` 2400 px ≥ them (the shipped values stay; they now have headroom) |
| `test_engagement_deadline.gd` | the source scans of `station_reinforcements.gd` → `global/boss/*.gd` and `space_fortress/*.gd` |
| comments citing the station: `base_enemy.gd`, `bullet.gd`, `enemy_module.gd`, `laser_ray.gd`, `arena_camera.gd`, `bullet_pool.gd`, `explosion_effect.gd`, `radial_attack_pattern.gd`, `level_1_director.gd`, `wave_builder.gd`; tests `test_suite_integrity.gd`, `test_signal_emit_arity.gd`, `test_armor_query.gd`, `test_enemy_path_mover.gd`, `test_player_bullet_lifetime.gd` (its stand-in for the station's armoured core → the fortress's armoured hull), `test_laser_ray_hit_mask.gd`, `tests/unit/test_explosion_effect.gd` | re-word to cite the fortress (or drop the historical reference); no behaviour change |
| any other hit of the acceptance pattern below | re-point or delete with a replacement named in the commit |

Acceptance — the pattern is **anchored on the enemy's paths and class names**, because Fortuna's Open Space mission data lives under directories named `space_stations/`
(`open_space/scenes/mission_select_hubs/space_stations/…`, `open_space/scenes/mission_data/space_stations/…`, referenced from `sector_hub.tscn`) and is **out of scope: never
rename or touch it**:
`grep -rnE "enemies/space_station/|space_station(_config)?\.(gd|tscn|tres)|SpaceStation|Station(Turret|Gunnery|LaserPhase|Reinforcements|DeathSequence)|SPACE_STATION|space_station\(" --include=*.gd --include=*.tscn --include=*.tres . | grep -v '^./docs/'`
returns nothing (checked @ `5cbfd29`: it matches the station's own files and the comment / test files in the table above, and none of Fortuna's). The gate is green; GUT time
drops (record it).

### 2.12 EMP on structures (Ph9 / Ph10 debt; Ph11 owner choice 7; t12)

- `DefenseTurret` (and the heavy emplacement), `LaserEmitter` (fence post) and `ShieldGenerator` override `answers_emp()` → true. What exists already (code facts, no change
  needed): `BaseEnemy.apply_emp` null-guards the mover and the brain (`base_enemy.gd:185-188`), and `BaseEnemy._physics_process` counts a brainless structure's window
  (`base_enemy.gd:121-133`); `is_emp_disrupted()` / `emp_seconds_left()` read it. `DefenseTurret` and `ShieldGenerator` have a brain (it gets `on_emp_started()` once and is not
  ticked for the window: the base rule) and no mover; **`LaserEmitter` has neither**.
  - Turret brain: every mount `scan(0.0)` for the window (no fire, no telegraph); stays tangible.
  - Fence post (no brain, so nothing is called on it): **the fence polls its posts.** `LaserFence.step(delta)` checks `post.is_emp_disrupted()` on both posts each tick; while
    either is disrupted it cancels a running beam once (the `&"laser_wall"` hazard unregisters with it), lights the posts' lamps OFF and does not advance its schedule; when
    neither is disrupted any more it restarts its schedule from the warning phase (STATIC: warn, then lit; CYCLE: from the cycle start), so the player always gets the telegraph
    again. A post's EMP darkens the whole fence. A collapsed or unpowered fence ignores this (it is down for good).
  - Shield generator: stops `sustain()` for the window, so its bubbles lapse after their heartbeat and return after.
- `EMPBlastModule` therefore stops process-disabling these; the **bonus drone keeps the legacy freeze** (a rail reward target; recorded decision).
- Rows (`test_enemy_emp.gd` / `test_emp_blast_module.gd` / `test_laser_fence.gd` additions): each structure answers EMP, stays tangible (a bullet still damages it), is silent
  for exactly the window, resumes after; a lit fence whose post is EMP'd goes dark the same tick, unregisters its hazard, and relights only through a fresh warning phase after the
  window; an EMP on the *other* post while the first is still disrupted extends the dark period to the later window end; `apply_emp` on a brainless, moverless `LaserEmitter`
  raises no error and starts its window (the null-guard, pinned); `EMPBlastModule` no longer sets `PROCESS_MODE_DISABLED` on them; the bonus drone still freezes (boundary).

### 2.13 Open Space hub placement (t13)

`sector_hub.gd`: **draw 21**, appended after the Carrier so every earlier seed is unchanged: one Space Fortress, anchor on the 4200 ring at −45° (≈ (2970, −2970)), `patrol_anchor`
and `rng_seed` set before `add_child()`, idle on `AnchorIdle` (not `start_engaged`). Its footprint for the sweeps = `zone_radius` 600 + body radius 176 + `perceive_radius` 1400.
- `test_sector_hub_patrol.gd`: `_patrol_groups()` gains the fortress (worst idle offset = `zone_radius` 600), so every interactable / TacticalSpace / defense-site / jammer sweep
  covers it; anchor spacing > 1000 from every other group; frame-0 row (nobody perceives the player); the hard counts move: groups 15 → 16, seeds 21 → 22, `_expected_seeds()` 20
  → 21 draws, live children 21 → 22 (the escort container is created lazily, so none at frame 0).
- Pre-approved levers if a sweep fails: ring 3800–4600, bearing −45° ± 22.5°; anything else stops the task and asks.
- Name: the hub node and every doc call it the Space Fortress; nothing near "Fortuna Space Station" vocabulary.

### 2.14 Roster and invariant gates the fortress joins (t5)

`test_enemy_contact_damage.gd` (contact 40 = config), `test_contact_hitbox_geometry.gd` (contact shape = body shape id + scale), `test_enemy_hurtbox_geometry.gd` (hull
hurtbox covers the body), the three roster-completeness guards (they sweep `<dir>/<dir>.tscn` with a `BaseEnemy` root), `test_config_instance_isolation.gd` (directory sweep:
flat config, private copy before children's `_ready()`), `test_entity_sprite_transparency.gd`, `test_signal_emit_arity.gd`, `test_enemy_mover_single_writer.gd` (the fortress
root script and `fortress_brain.gd` never write `velocity` / `rotation` / `move_and_slide()`), `test_collision_layer_names.gd`, `test_project_load_integrity.gd`,
`test_boss_phase_rules.gd` (t1).

### 2.15 Gate time

Start: GUT 210.34 s (Ph10 t12). Allotments (seconds of GUT time each task may add): t1 0.3 · t2 1.0 · t3 0.5 · t4 0 · t5 2.5 · t6 2.0 · t7 4.0
(the density rows: 4 phases × 5 positions × 11 s hand-ticked) · t8 1.5 · t9 0.3 · t10 4.5 (a 1× wall-clock section replay; its timeout row overrides the section timeout to
2.0 s) · t11 ≤ 0 (it removes the station files; record the saving) · t12 0.5 · t13 0.5 · t14 0 → +17.6 s, phase end ≤ 227.9 s before t11's saving.
Each task records a before / after two-run mean (`scripts/gate-time.sh`) in `tests/README.md` → *Gate time*; escalate past a 237 s mean or 1.5× the task's own allotment.
Rule 1 clocks: real-physics rows 8× by default; the section replay cannot be scaled (wall-clock director), so it uses one fortress life with `death_duration` 0.2 and scripted
part kills. Gate output stays well under 1 MiB (no per-tick prints).

### 2.16 Numbers and where they come from

| Number | Value | Source |
|---|---|---|
| Hull | circle r 176, sprite 384 | IDEAS §8.1 320–512 px; fits 1280 × 720 Assault view with ≥ 450 px each side (judgement) |
| Part HP | battery 260, hangar 300, generator 360, core 1500 | station 120 / 600 scaled for ~5 s of focused default fire per battery (50 dmg / 0.18 s), core ≈ 1.5× the Carrier core (judgement) |
| Sector shield | capacity 120, regen delay 3, regen 2 s, reboot 5 | `EnemyShield` defaults scaled to ≈ 3 default bullets (judgement) |
| Phase 2 | 2 batteries | Ph11 owner choice 2 default |
| Critical | core ≤ 40 % | Heavy Gunship bands 0.6 / 0.3 (Ph10) between (judgement) |
| Turn | OS 0.22, Assault 0.30 rad/s | ≤ ¼ of a circling player's 0.84 rad/s (§2.6) |
| Spins | volley 0.5, critical 0.6 rad/s | station `laser_rotation_speed` 0.5; fairness row bounds both |
| Zone | radius 600, station points at 360, reposition 8 / 5 s at 60 / 90 px/s | Carrier leash 900 and speed 70 (Ph10), smaller for a fortress (judgement) |
| Assault | enter 90 px/s, hold y 180, bob ± 100 at 35 / 55 | station y 180; Carrier crossing 90 |
| Spokes | telegraph 1.2, active 2.5, length 900, damage 14, period 8 / 6 | station warn 1.4 / active 2.0 / interval 6.5; Ph8 telegraph ≥ 1.0 |
| Ring pulse | max r 640, 300 px/s, gaps 2 × 50°, damage 14, period 6 / 3.5 | Carrier ring 420 / Ph8 `EnergyRing` |
| Core ring | 12 bullets, 10 dmg, 210 px/s, step 0.24, every 2.0 s | station core ring (10 / 2.0 s / 0.24) |
| Attack gate | 2 (critical 3) | judgement; density ceilings: mean 2.0 × station (13.3 /s), peak 2 s window 1.25 × 24 = 30 |
| Hangar open hold | 2.0 s | Carrier `door_hold_seconds` 2.0; one open window kills it (2.8 s × 278 DPS ≥ 420) |
| Spread `fire_range` | 420 | Scatter round `max_distance` 450 (+ 28 px muzzle) |
| Escort caps | OS 6, Assault 4 | Carrier cap 6; station cap 4 |
| EMP | × 0.4, every source; no-op while dying | Ph11 owner choice 6 |
| Death | 2.4 s, 10 blasts, spread 150 | station 1.8 / 7 / 96 scaled to the hull |
| Score | 1500 | station 1000 (judgement) |
| Section timeout | 240 s | Ph11 owner choice 5 |

### 2.17 Docs and phase close (t14)

Invoke `updating-project-docs`: `space_fortress/ENEMY.md` (behaviour, parts, phases, numbers, measured density), `docs/architecture/modules/global.md` (*Boss machinery*:
`global/boss/` API), `assault.md` (fortress replaces the station section text), `open_space.md` (draw 21), `docs/enemy-roster.md` (builder, the station section gone, the naming
note resolved), `docs/architecture/PROJECT.md` Conventions (escort path, phase ladder rule), `CLAUDE.md` (the station test family paragraph → the fortress family and the boss
machinery gates; the "rail-fire" 21st gate → the escorts-fire row; key conventions bullet for bosses), `tests/README.md` gate-time table. Then write the dossier
`docs/epics-done/cmug256so0031m52wbxomst72/` (PRD, SOURCES, REPORT) and append `## Phase 11 - as built (<date>)` to `DECISIONS.md`.

## 3. Build sequence

1. t1 phase ladder; t2 reinforcements machinery (needs t1's driver API); t3 mount variants; t4 death sequence move; t12 EMP on structures (independent).
2. t5 fortress shell (t1, t2, t4: its death order calls t2's `scuttle_all()` and frees t2's escort container).
3. t6 movement (t5) → t7 weapons (t6, t3) → t8 reinforcements on the fortress (t7, t2). These three edit `fortress_brain.gd` and the fortress phase handler, so they are serial.
4. t9 art after t8 (it wires textures and the `Thrusters` / `CriticalOverlay` / door / shutter visuals into `space_fortress.tscn`, which t6–t8 also edit; serial on purpose).
5. t10 level 1 swap (t8); t13 hub (t8).
6. t11 station retirement (t10, t9).
7. t14 docs and phase close (all).

## 4. Test plan

New files: `tests/unit/test_boss_phase_driver.gd` (t1), `tests/integration/test_boss_phase_rules.gd` (t1, intent gate), `test_boss_reinforcements.gd` (t2),
`test_turret_mount_variants.gd` (t3), `test_space_fortress.gd` (t5, t6), `test_fortress_weapons.gd` (t7), `test_fortress_reinforcements.gd` (t8), `test_fortress_sprites.gd` (t9),
`test_level1_fortress_section.gd` (t10); renamed `test_boss_death_sequence.gd`, `test_fortress_incoming_damage_paths.gd` (t11). Extended: roster gates (t5), `test_ph8_sprites.gd`
and `test_enemy_bullet_lifetime.gd` (t3, t7), `test_station_assault_section.gd` and `test_level_1_sequence.gd` (t10), `test_enemy_emp.gd` / `test_emp_blast_module.gd` (t12),
`test_sector_hub_patrol.gd` (t13).

Boundaries that prove the rows can fail: a one-change phase fails `test_boss_phase_rules.gd`; one destroyed battery does not enter `shields_exposed`; a core one point above 40 %
is not `critical`; a cap of 4 skips the fifth escort; a dead bay ignores `surge()`; a shrunken hull hurtbox fails the hurtbox sweep; a layer-1 root blocks the mining laser; a
kill after `is_dying()` pays nothing; `pellets` 1 trace unchanged; the bonus drone still freezes under EMP Blast; a spread mount at `fire_range` 520 fails the reach row; a
15° ring gap fails the gap row at the hull edge; the `critical` density rows' planned upper bound (≈ 14.5 /s, a 34-round window) exceeds both ceilings, so they can fail;
`open_hold_seconds` 0 fails the hangar feasibility row; a Missile Corvette in an `ENEMIES_CLEARED` section fails the persistent-ordnance allowlist; the dead-hangar §25 row
still finds ≥ 2 changes per phase.

Both harnesses: every fortress behaviour row in `test_space_fortress.gd`, `test_fortress_weapons.gd`, `test_fortress_reinforcements.gd` runs in Open Space and Assault (IDEAS §40).

## 5. Risks

- **Assault crowding:** a 352 px boss, 900 px spokes and a 640 px ring in a 1280 × 720 view. Mitigations: the attack gate, the fairness inequalities and the measured density
  ceilings, measured in every boss phase at five player positions (§2.7); the `critical` frenzy's planned upper bound is above the ceilings, so tuning there is expected — in
  the stated lever order, never by widening a bound.
- **Gate time:** +17.6 s planned against ~27 s headroom; t11 gives some back. Escalation rule §2.15.
- **Test-family surgery (t11)** touches ~25 files; the mapping table (§2.11) names each file's fate so no intent is lost silently.
- **Escorts in a sub-container:** code that assumes enemies are direct children of the enemy container (e.g. `_live_children` counts, density helpers) sees one container
  instead; t2 row 11 and t13's counts cover the two known readers.
- **ScoreTracker change touches an autoload-adjacent contract** (`EventBus` gains a signal): `test_signal_emit_arity.gd` and the score rows cover it.
- **Shield bubbles vs player tools:** beam and nova bypass shields (direct emitters, Ph5 rule); this makes the beam strong against phase 1. Accepted (recorded); tuning lever is
  `sector_shield_capacity`, not the bypass.
- **Play feel is untested headless** (spin readability, how long the fight takes); the owner should play the section once after t10.

## 6. Out of scope

| Item | Where | Why |
|---|---|---|
| Carrier hangars and Heavy Gunship phases moved onto `BossReinforcements` / `BossPhaseDriver` | Ph18 | Ph1 roadmap; the machinery is built here, the migration is theirs |
| Dreadnought | Ph12 | next phase; reuses `global/boss/` |
| Enemy beams / rings damaging parts (owner-of-part exemption) | Ph18 / Ph19 | Ph10 deferral |
| Wrecked parts blocking line of sight, capital wrecks on death, heavy mass rules | Ph19 | |
| Encounter director, escort cleanup in Open Space beyond the cap | Ph13 / Ph14 | |
| Boss / part HUD, per-part score, audio | Ph17 | IDEAS §6.11 "not one giant HP bar" |
| Difficulty tiers | Ph16 | |
| Twin-rig "endpoint beam rotating about an anchor" | dropped for the fortress (hull-mounted spokes cover §24); still available to a later boss | |
| EMP knocking sector shields down | later (Ph18 with ship-mounted EMP) | scope; shields are passive here |
| Level 2 | Ph15 | not in the game flow |

## 7. Requirements coverage

| Requirement (IDEAS / scope line) | Task(s) |
|---|---|
| §8 bosses designed for 360° | t5, t6, t7 |
| §8.1 size 320–512 px | t5 (r 176 hull, 384 sprite), t9 |
| §8.1 4–6 outer batteries, each distinct (spread, sweep, missile, rapid pulse, artillery) | t3, t5, t7 |
| §8.1 2–3 shield nodes protecting sectors | t5 (`ShieldSector`, 2 nodes) |
| §8.1 core hidden / armoured until enough outer systems destroyed | t5 |
| §8.1 four phases (batteries; shields exposed; core + moving; critical frenzy) | t1, t5, t6, t7, t8 |
| §8.1 Open Space: slow rotation, reposition in a combat zone, shift orbit centre, weak side changes, encourage circling | t6 |
| §8.1 Assault: vertical movement only, still rotates to show sides | t6 |
| §10 reinforcements tied to modules / sectors / hangars, reusable | t2, t8 |
| §10 out of the generic Assault enemy container and scoring path | t2, t8, t10 |
| §24 geometry weapons: rotating hull beams, radial ring pulses, diagonal corner crossfire | t7 |
| §25 every phase changes ≥ 2 of six aspects | t1 (gate), t5–t8 (§25 row) |
| §22 / §23 coherent modules, destroyed modules stay as wreckage | t5, t9 |
| §21–23 fortress art, light vocabulary, visual phase changes | t9 (+ `SHIELDED` light in t5) |
| §26 destroyed shield generator exposes a sector; destroyed battery removes an attack angle | t5, t7, t8 |
| §39 keep the station's modular structure (turrets, armoured core, beams, rings, reinforcements, death) | t4, t5, t7, t8 |
| §40 large-enemy and boss tests in both harnesses | t5–t8 |
| §41 Phase 5 item 1 (Space Fortress rework) | t5–t11 |
| Replace the Assault station section | t10, t11 |
| May appear in Open Space under a non-colliding name | t13 (names rule in *For every task*) |
| Keep the station test family green or deliberately update it | t4, t10, t11 (§2.11 table) |
| ENEMIES.md naming-collision note | names rule; t14 roster doc |
| Ph4 / Ph5 deferral: station `homing_point` | t5 (fortress), t11 (station retired) |
| Ph8 deferral: station lasers onto `EnemyBeam` | t7 |
| Ph9 / Ph10 deferral: EMP on structures (station, bonus drone, Ph8 turrets / fences) | t5 (fortress), t12 (turrets, fence posts, generators), bonus drone kept legacy (decision) |
| Ph8 deferral: twin-rig rotating beam for the fortress | out of scope (§6), reason given |
| Dreadnought (§9) | later phase 12 |
| Carrier / Gunship on boss machinery | later phase 18 |

## 8. Response to feedback (review 1, CHANGES_REQUESTED)

| # | Finding | What changed |
|---|---|---|
| 1 | t5 uses t2's API without depending on it | t5 now depends on t2 and lists §2.2; §2.5.3 says what t5 takes from t2 and that `scuttle_all()` is a no-op until t8 adds bays; §3 step 2 updated |
| 2 | t11's grep matches Fortuna's `space_stations/` files | §2.11: anchored pattern (paths, `SPACE_STATION`, `space_station(`, every `Station*` class incl. `StationDeathSequence`), checked against the tree @ `5cbfd29`; Fortuna's files named out of scope; the comment / test files the pattern hits are listed in the table |
| 3 | density ceiling vacuous in `batteries`, `critical` unmeasured | §2.7: measured in all four phases with the worst live-battery set, at five player positions, mean ≤ 13.3 /s and peak 2 s window ≤ 30; the planned `critical` upper bound (≈ 14.5 /s) is above the ceiling, so the row can fail; lever order stated, "never widen" kept; t7 allotment 2.5 → 4.0 s |
| 4 | `attack_gate(mount)` vs `telegraph_gate.call()` | `attack_gate() -> bool`, zero-argument (For every task, §1.3, §2.7, row 1 drives a real TRACK → TELEGRAPH) |
| 5 | `LaserEmitter` has no brain; null-mover already guarded | §1.1, §1.3 and §2.12 corrected; `LaserFence.step()` polls `post.is_emp_disrupted()` and relights through a fresh warning phase; the null guard became a test row |
| 6 | inherited scenes and `export_of()` | new mounts are standalone (`heavy_cannon_mount.tscn` precedent) with an `export_of()` row; inherited spoke beam / pulse ring author every gated value; fairness rows read instantiated nodes (For every task, §2.3, §2.7) |
| 7 | escort flag writes overwritten; disconnect clause points at nothing | both writes dropped (reason stated), disconnect clause dropped; row 14 pins that the flags equal the escort's config |
| 8 | fortress's persistent rockets in an `ENEMIES_CLEARED` section | recorded as the second bounded exception (For every task, §2.7, DECISIONS); t10 adds an allowlist + tail row in `test_engagement_deadline.gd` with a Missile Corvette boundary |
| 9 | lifetime test pins 150 / 18 | §2.11: re-derive and re-pin the slowest source and `ceil(2274 / min) + 2`; shipped 18 s / 2400 px stay and are asserted ≥ the derived values |
| 10 | 240 s wall-clock timeout row | §2.10: row (b) overrides the timeout on its own copy of the section to 2.0 s; row (a) kills right after spawn so no rocket tail is waited out; 240 s stays pinned elsewhere |
| 11 | hangar barely killable | `ReinforcementBay.open_hold_seconds` (Carrier parity, 2.0 on the hangar); feasibility inequality + real-hit row + `open_hold_seconds` 0 boundary (§2.2, §2.8) |
| 12 | ring-gap row checks the widest point | evaluated at the hull edge + player radius (radius × node scale), 15° boundary fails (§2.7) |
| 13 | spread `fire_range` beyond the Scatter reach | `fire_range` 420; a reach row over every bullet-firing variant, 520 as the failing boundary (§2.3) |
| 14 | EMP Blast freezes the dying wreck | `answers_emp()` true while dying, `apply_emp` a no-op then; row 8 extended (§2.5.6, §2.5.7) |
| 15 | movement row 3 asserts more than the rule | row 3 recomputes the rule's pick and asserts it, explicitly not "farther than before" (§2.6) |
| 16 | §25 row path-dependent at `critical` | the scripted path is pinned (hangar alive); t8 adds a dead-hangar row asserting ≥ 2 changes (§2.5.7 row 6, §2.8 row 7) |
| 17 | missing plan sections | t6 gains 2.5.4, 2.5.6; t8 gains 2.5.3, 2.6; t5 gains 2.2 (and the needed facts are repeated in place: §2.8 row 8 defines "engaged") |
| 18 | t9 and t6–t8 edit the same scene unordered | t9 depends on t8 (§3 step 4) |
| 19 | t4 understated | §2.4: behaviour-identical, the `.uid` sidecar moves, the scene's `ext_resource` path, the `SpaceStation` type and cast become a duck-typed host, renamed references, UID / load-integrity rows |
| 20 | squad wording, owner-choice numbering, choice 6 wording | one `SquadController` per payload scene per boss (For every task, §2.2, t2, DECISIONS, row 13); "Ph11 owner choice N" everywhere; choice 6 says "every EMP" |

