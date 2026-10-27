# Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones

Revision 1 (2026-10-27). Built on this directory's `1-context.md` (requirements R8.1–R8.25, files, conventions, open questions
Q1–Q13) and `2-research.md` (scope check S1–S16, findings F1–F8, recommendations). Every recommendation there is adopted unless
§1.1 says otherwise. Code facts below were re-read on `agent/auto-dev` @ `5915b4d`.

## Summary for the owner

- **For the player:** lasers become a real enemy weapon. Every laser first shows a thin warning line on its exact path, then fires; it hurts anything on its line, other enemies included, so you can lure enemies into it.
- **Defense turrets:** stationary gun emplacements that turn to track you and lead their shots. Six weapons: a burst cannon, a sweeping beam, a beam cannon, a rocket battery, a short-range pulse ring and a long sniper lance. A larger "heavy emplacement" carries two weapons at once.
- **Turret groups:** turrets come in groups of 2–4 placed so no direction around them is safe. A power source feeds the group: destroy it and every turret goes dark at once and never restarts. A shield generator puts a shield bubble on each member, the power source included, so you must break the generator or go around it.
- **Laser fences:** two emitter posts with a laser between them, either always on or switching on and off. Shoot a post and the fence drops.
- **Twin-Laser Drones:** two small drones hold a laser between them and sweep it through you; kill either drone and the laser collapses. A new launcher ship, the Laser Tender, fires a pair in a V toward where you are heading; they line up into a moving laser wall across your path.
- **In Assault** turrets and fences scroll down the corridor like wreckage; drones and the tender attack once and leave.
- **Where:** a defended site in the hub (every structure shown once), a twin-drone pair and a tender on hub patrol; in level 1 a two-turret group and a drone pair in Deep Space and a tender in Planet Approach, all in sections that do not wait for a clear.
- **Left out:** turrets mounted on big ships and bosses (phase 10–11), jammer-linked groups (phases 9 and 20), difficulty tiers (16), sound (17). The space station keeps its own laser for now (phase 11 moves it over).
- **Main risks:** (1) the tests are near their time limit, so the first task must win back 10 s; (2) lasers that hurt enemies can kill level-1 enemies early; (3) the drone pair's laser must keep its length while both drones move; (4) nothing is play-tested yet.
- **Choices for you (default in brackets):**
  1. Add the Laser Tender, a new small ship, to launch drone pairs (the ideas name no launcher)? [Yes]
  2. Should a laser spare the enemies of its own group or pair (its turrets, power source, partner drone) while still hurting every other enemy? [Spare its own group]
  3. When the power source dies, should turrets go dark but stay as targets, rather than blow up? [Go dark]
  4. Build the heavy emplacement now rather than in phase 10? [Now]
  5. Should an enemy killed by an enemy laser still score for you? [Yes]
  6. Level 1's existing laser columns: make enemies steer round them only if a measurement shows they currently die in them? [Measure first]
  7. Like every laser in the game, your mining beam passes through enemy shield bubbles: keep that as a way past the shield generator? [Keep]

## For every task

Phase 8 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line below changes them.
- **Energy weapons** live in `assault/scenes/projectiles/enemy_beams/`: `EnemyBeam extends Node2D` (`enum Kind { BEAM, SWEEP, LANCE, TWIN }`, `enum Phase { OFF, TELEGRAPH, ACTIVE, FADE }`,
  both append-only), `EnergyRing extends Node2D` (the Pulse Ring; `class_name PulseRing` is Ph7's visual ring and is not touched), `EnergyHitScan` (static target scan) and
  `EnemyBeamScenes` (`scene_for(kind)`, `export_of(kind, property, fallback)`). Scenes: `beam.tscn`, `sweep_beam.tscn`, `lance.tscn`, `twin_beam.tscn`, `energy_ring.tscn`.
  **Weapon tuning lives in those scene exports** (the Ph5 rocket / Ph7 mine rule), so a beam is identical whoever fires it. Gates read numbers from scenes, never typed numbers.
- **Owner-driven clock:** the owner calls `start()`, `tick(delta)` and `cancel()`; no `Timer`, no `create_timer`, no `_process` clock (a `self_tick` export exists only for scene-placed
  props). Signals `phase_changed(phase: int)` and `target_hit(target: Node2D, damage: int)`. Emitter beams point along the node's **local +X** (`Vector2.RIGHT.rotated(global_rotation)`);
  endpoint beams take `set_endpoints(a, b)` every tick.
- **Friendly fire (decided here):** every energy weapon (beam, sweep, lance, twin beam, laser fence, Pulse Ring) hurts every target in groups `player`, `allies`, `enemies` and `asteroids`
  whose hurtbox shape meets the weapon, **except its owner set**: the host node and every node in its `owner_group` (a turret group, a twin pair and its tender). Enemy ordnance
  (rockets, mines) is never hit. Rocket and mine blast rules from Ph5/Ph7 are unchanged.
- **Damage is a direct emit** (`HurtBox.received_damage.emit(damage)` through `Hazards.hurt_box_of()`), like every beam in the project: it bypasses `EnemyShield` bubbles and
  `ArmorPlate`s; a plated Ram refuses it in its own hull rule; the player's i-frames and shield charge apply. At most one hit per target per `rehit_interval` (≥ 0.5 s, the player's
  i-frames, so both sides see the same cadence); the Lance hits once per activation. A kill by an enemy weapon scores like any kill.
- **Segment hazards:** `HazardInfo` gains `segment_half: Vector2` (ZERO = circle, every existing hazard) and `exempt_group: StringName` (an actor in that group skips it in avoidance).
  A lit laser wall registers `kind = &"laser_wall"`. With no segment hazard, every Ph6/Ph7 avoidance result stays bit-identical.
- **New enemies** (each a `BaseEnemy` subclass with a flat `*Config extends ShipConfig`, one `*config*.tres` per directory, `.tres` wins, joins group `enemies` in its own `_ready()`):
  `defense_turret/` (`DefenseTurret`, `DefenseTurretBrain`, `DefenseTurretConfig`), `heavy_emplacement/` (same scripts, its own config `.tres`), `shield_generator/` (`ShieldGenerator`),
  `power_source/` (`PowerSource`), `laser_emitter/` (`LaserEmitter`, a fence post), `twin_laser_drone/` (`TwinLaserDrone`, `TwinLaserDroneBrain`, rig `TwinLaserPair`, spawner
  `TwinLaserPairSpawn`), `laser_tender/` (`LaserTender`, `LaserTenderBrain`), all under `assault/scenes/enemies/`.
- **Structures that are not enemies** live in `assault/scenes/structures/`: `turret_group/` (`TurretGroup`, `TurretGroupSlot`, presets) and `laser_fence/` (`LaserFence`). Never in `enemies`,
  never scored; `counts_toward_wave_clear` and `counts_as_escape` are false on the node.
- **Turret mount (the Ph10 seam):** `TurretMount extends Node2D` (`defense_turret/mounts/`), `enum Variant { BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE, BEAM_CANNON }`
  (append-only), one scene per variant (`TurretMountScenes.scene_for(variant)`), owns aim, muzzle, weapon and telegraph, and writes **only its own `rotation`**. Never the root's.
  Pools are root children of the host (`BulletPool`'s grandparent rule); the host builds them from `TurretMount.pool_specs()`.
- **Groups:** a `TurretGroup` is a **coordinator, not a parent**: it spawns its members deferred as siblings in its own parent (the enemy container) and joins them to its
  `owner_group`. `set_powered(on: bool)` on every member is the only power coupling (the Ph9/Ph20 seam). Members it spawns are announced with `EventBus.enemy_spawned_orphan`.
- **Assault structures** drift down at 60 px/s through the shared `AssaultDrift` component (`global/components/assault_drift.gd`) and free themselves below the projectile world
  rect; they fire only while inside `EnemyWorld.view_rect()`. Nothing under `global/` references `ArenaCamera`.
- **No turret group, fence, twin pair or Laser Tender goes in an `ENEMIES_CLEARED` section** (persistent fire, rockets that persist). Guard rows in `test_engagement_deadline.gd`.
- **Conventions kept:** brains tick on physics through `BaseEnemy._physics_process`; only `EnemyMover` writes an AI-driven body's velocity/rotation (`test_enemy_mover_single_writer.gd`);
  committed runs are `mover.boost()` (it skips avoidance, keeps drift and the corridor constraint); "stopped" gates read `own_velocity()`; randomness only from `brain.rng` or a node's own
  seeded rng; `accepts_tow()` is false in every telegraphed or committed phase (add each new brain to `test_base_enemy.gd`'s tow table); `TargetInfo` for the player; hull art nose-down
  (`sprite_forward_angle` `PI/2`); signals declared with their arity; per-frame prints behind `OS.is_stdout_verbose()`; never hand-type a `uid://`.
- **Physics queries only on the physics step:** cover rays run only when `Engine.is_in_physics_frame()`; hand-ticked rows therefore never cast, and every row with a blocker runs on real
  physics at the 8× clock (`_scale_clock()` / `_restore_clock()` from `test_level1_drone_exit.gd`).
- **Every structure root and turret root answers `is_laser_blocking() == false`** (the player's mining beam treats it as a target, not a wall).
- **Tests:** GUT, written first. Behaviour specs run in both harnesses (`tests/helpers/enemy_ai_harness.gd`, `open_space()` / `assault()`, parameterised on a label string, never
  `use_parameters([HARNESS…])`). Fixture victims: `tests/helpers/fixture_enemy.tscn` with a 14 px `CircleShape2D` added to its `HurtBox` and `add_to_group("enemies")` at runtime (the
  shared scene is not edited). Per-tick drivers are a child `_Ticker` node, not a lambda on `physics_frame`. Run `scripts/check-test-leaks.sh` after anything that awaits.
- **Gate time is a budget:** measure GUT with `scripts/gate-time.sh` before and after each task, report both in the task report and in `tests/README.md` → Gate time. Allotments are in
  plan §2.20; GUT must stay ≤ 240 s. An overrun is fixed by sharing a scenario or the 8× clock, never by cutting an assertion.
- Numbers marked *starting value* (plan §2.21) are judgement, not play-tested; keep them unless a row forces a change, and log any change in `DECISIONS.md`.
- Every task appends its "Phase 8, built in tN" notes and any deviation to `DECISIONS.md`. Finish with `bash /agent/verify.sh` green. Stay on `agent/auto-dev`.

## 1. Problem

Today the only laser in the game is `LaserRay`: a one-hit-kill hazard column in level 1 and the race, and the space station's boss laser. No ordinary
enemy has an energy weapon, nothing stationary fights the player except the station, and nothing makes the player think about *where* fire comes from
around a fixed position. The idea (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/ENEMIES_OPEN_SPACE_REWORK_IDEAS.md` §6.5, §6.10, §11.3, §18.6, §21–23, §40) asks for:

- a shared energy-weapon family (Beam, Sweeping Beam, Lance, Pulse Ring, Twin-Beam / Endpoint Laser, Moving Laser Wall) that hurts anything on its line;
- a stationary defense turret with predictive aim and five weapon variants, placed in groups with overlapping lanes, protected by a shield generator and
  switched off by a power source;
- stationary laser walls and temporary laser barriers that enemies understand through the phase-6 hazard sense;
- Twin-Laser Drones with a closing laser (Attack A) and a V-launch into a moving wall (Attack B), with counterplay;
- strict top-down art and readable telegraphs; placement in Assault waves and the hub; tests in both harnesses.

### 1.1 Scope check (re-validated against the code on `agent/auto-dev` @ `5915b4d`)

`2-research.md` §0 (S1–S16) is adopted in full. Plan-stage additions and the answers it left open:

| # | Finding / decision | Effect |
|---|---|---|
| S1 | `LaserRay` cannot be the base (kill damage, sprite-clocked phases, `Timer`, pinned users). | New `EnemyBeam` beside it (§2.1). `LaserRay`, `StationLaserPhase`, the station and the race stay byte-identical except the one opt-in export of §2.16. The station moves onto the family in Ph11. |
| S2 / S5 | Friendly fire decided by the epic; enemy beams are direct emitters. | §2.2: owner-set rule, direct emit, shields and plates behave as for every beam. Recorded in DECISIONS. |
| S3 / S12 | Level 1's 11 column volleys and the `LaserWallWave` already kill AI enemies; nothing avoids them. | §2.16: measure once with a throw-away replay; register them as `&"laser_wall"` hazards only if enemies die in them. |
| S4 | `HazardInfo` is circles only. | §2.6: segment geometry + `exempt_group`, a stated change to Ph6's "no change to the AI" promise. |
| S6 / S13 | A brain-only `BaseEnemy` works (`base_enemy.gd` `_physics_process` steps a mover only if one exists); enemy roots sit on physics layer 1, so the player's mining beam stops at them and skips them as targets (`beam_behavior.gd` `tick()`). | Turrets and structures are brain-only (or brainless) `BaseEnemy`s with no `EnemyMover`; every new root answers `is_laser_blocking() == false`. The same skip on existing enemies is a follow-up, not this phase. |
| S7 | `BulletPool` resolves its container as its grandparent. | Pools are always root children of the host; `TurretGroup` spawns members as container siblings (§2.10). Container injection stays with Ph10. |
| S9 | The Ph1 roadmap expected telegraphs on `AttackController.fire_now`. | Beams own their telegraph; `AttackController` stays the round/rocket driver. |
| S10 | `class_name PulseRing` is taken. | The weapon is `EnergyRing`. |
| S11 | Attack B needs a launcher no roster names. | The Laser Tender (§2.13), owner choice 1. |
| P1 | **No plain Beam consumer** among the five turret variants the ideas list. | A sixth mount variant, `BEAM_CANNON` (appended), carried by the heavy emplacement, so the Beam kind (R8.1) ships in play, not only in tests. |
| P2 | `ScoreTracker` tracks every `WaveManager` spawn and any `EventBus.enemy_spawned_orphan` emit (`score_tracker.gd` `_on_enemy_spawned`). | A `TurretGroup` / `TwinLaserPairSpawn` spawned by a wave sets `counts_toward_wave_clear = false` and `counts_as_escape = false`; the members it spawns are announced as orphans (the station-reinforcement precedent), so their kills score. |
| P3 | The shield bubble a generator projects is the Support Ship's sustained `EnemyShield` path (`support_ship_brain.gd` `_make_shield()`): `attach()` to the member's hurtbox, `sustain()` every tick, lapse after `heartbeat` 0.3 s. One absorber per hurtbox. | Reused unchanged; a Support Ship's ward and a generator's bubble cannot stack (the second `attach()` fails and is skipped). |
| P4 | Gate time: Ph7 closed at GUT 218.44 s; `test_fighter_squad.gd` (63.7 s) is one sweep of 168 distinct layouts and the 1× files Ph7 converted are gone. | t1 must free **≥ 10 s** (a hard floor) and may, as its last lever, speed up production code only if every printed figure stays bit-identical. Allotments total 26.4 s (§2.20). |
| P5 | The Heavy Shell still has no consumer (Ph4 handed it to Ph10). | Not used here. The burst cannon fires Pulse rounds. |
| P6 | Turret groups, fences and the Laser Tender bring the first runtime-spawned *pair* (`TwinLaserPair`) and *group* coordinators. | Both are `RefCounted` / plain-`Node2D` coordinators with documented seams for Ph10 (Carrier hangars), Ph11 (fortress batteries, shield nodes) and Ph20 (jammer-linked groups). |

## 2. Design

### 2.1 The energy-weapon family: `EnemyBeam` (R8.1–R8.3, R8.5, R8.7)

A new component beside `LaserRay`, which stays byte-identical (it is a one-hit kill, its phases advance on sprite `animation_finished`, it
re-damages on a `Timer`, and the race, level 1 and the station pin it). Directory `assault/scenes/projectiles/enemy_beams/` (the rockets and
ordnance precedent). Notes file `enemy_beams/BEAMS.md`.

**Class.** `class_name EnemyBeam extends Node2D`.
- `enum Kind { BEAM, SWEEP, LANCE, TWIN }` and `enum Phase { OFF, TELEGRAPH, ACTIVE, FADE }`, both append-only.
- Signals: `phase_changed(phase: int)`, `target_hit(target: Node2D, damage: int)`.
- `setup(host: Node2D, owner_group: StringName = &"")`: the owner set (§2.2). Called once by the owner before the first `start()`.
- `start(telegraph_override := -1.0, active_override := -1.0)`: OFF/FADE → TELEGRAPH. A negative override uses the scene export. Clears the
  per-target re-hit table.
- `tick(delta: float)`: advances the clock, the phase, the drawing and the hit scan. The only clock; called by the owner's brain on the physics
  tick, or by a hand-ticked test. An export `self_tick := false` makes `_physics_process` call it for scene-placed props only.
- `cancel()`: TELEGRAPH → OFF at once (no damage was ever possible); ACTIVE → FADE; FADE / OFF unchanged.
- `set_endpoints(a: Vector2, b: Vector2)`: world endpoints for the TWIN kind (and any endpoint use), set every tick before `tick()`.
- `set_strained(on: bool)`: while true the beam is never lethal and flickers (the twin rig's strain, §2.12).
- Queries: `phase() -> int`, `is_lethal() -> bool`, `is_committed() -> bool` (LANCE: inside the last `commit_seconds` of TELEGRAPH),
  `hit_segments() -> Array[PackedVector2Array]` (the lethal parts after tips and cover; empty when not lethal), `hazard_info() -> HazardInfo`.

**Geometry.** Emitter kinds (BEAM, SWEEP, LANCE): the beam starts at its own `global_position` and points along **local +X**,
`Vector2.RIGHT.rotated(global_rotation)`, for `length` px. The owner rotates the beam's parent (a turret mount, later a module or a hull — the
station's "rotating hull" is this case), never the beam. Endpoint kind (TWIN): the segment `a`–`b` given by `set_endpoints()`. The hit segment is
the drawn one shortened by `tip_grace_px` at the free tip (emitter kinds) or at both ends (TWIN; the endpoints are the drones or posts, which are
in the owner set anyway).

**Timeline.** TELEGRAPH for `telegraph_seconds` (never lethal) → ACTIVE for `active_seconds` (0 = hold until `cancel()`; the twin rig and the
laser fence use 0) → FADE for `fade_seconds` (never lethal) → OFF. Inside ACTIVE the beam is lethal only after `ignite_grace` seconds and only while
not strained. Every phase change emits `phase_changed` once.

**Exports (one scene per kind; starting values, §2.21):**

| Export | `beam.tscn` (BEAM) | `sweep_beam.tscn` (SWEEP) | `lance.tscn` (LANCE) | `twin_beam.tscn` (TWIN) |
|---|---|---|---|---|
| `telegraph_seconds` | 0.9 | 0.9 | 1.0 | 0.8 |
| `commit_seconds` | 0 | 0 | 0.5 | 0 |
| `active_seconds` | 1.2 | 2.0 | 0.2 | 0 (held) |
| `fade_seconds` | 0.15 | 0.15 | 0.1 | 0.15 |
| `ignite_grace` | 0.1 | 0.1 | 0.0 | 0.1 |
| `length` | 700 | 400 | 1100 | (endpoints) |
| `hit_half_width` / `draw_half_width` | 12 / 16 | 10 / 14 | 8 / 10 | 10 / 14 |
| `tip_grace_px` | 24 | 24 | 24 | 0 |
| `damage` / `rehit_interval` | 10 / 0.5 | 10 / 0.5 | 24 / INF | 12 / 0.5 |
| `sweep_arc_deg` / `sweep_rate` | – | 100 / 0.8727 rad/s | – | – |
| `blocked_by_cover` | true | true | true | true |
| `registers_hazard` / `avoid_weight` / `hazard_pad` | false | false | false | true / 0.5 / 24 |

`sweep_arc_deg` and `sweep_rate` are read by whatever rotates the sweep (the mount), so the sweep's tuning stays in the weapon scene.
`EnemyBeamScenes` (`enemy_beam_scenes.gd`): `scene_for(kind) -> PackedScene` (null with no error for a kind not built yet), and
`export_of(kind, property, fallback, node_path := ^".")`, reading `PackedScene.get_state()` (the `EnemyMineScenes.export_of` shape), so gates never type a number.

**Drawing.** Code-built `Line2D` children, no PNG (the `PiercingBeam` / `RailTrail` / `MineWake` precedent), not anti-aliased: a 2 px telegraph line on
the exact hit path during TELEGRAPH (yellow `Color(1.0, 0.85, 0.3, 0.55)`, white while `is_committed()`), then a core (white-hot, width
`hit_half_width`) and a glow (faction red, width `2 * draw_half_width`) whose width eases in over `ignite_grace` and out over `fade_seconds`. The
drawn half-width is wider than the hit half-width (F1: a graze that looks safe is safe). The beam draws `top_level` from its own global geometry.

**Rows** (`tests/integration/test_enemy_beams.gd`, hand-ticked, both harnesses unless marked):
- timeline: a fixture on the line is not hit at TELEGRAPH end − 1 tick, is not hit before `ignite_grace`, is hit on the first ACTIVE tick past it,
  is not hit during FADE or OFF; `phase_changed` fires once per change with one `int`; `cancel()` in TELEGRAPH goes OFF with zero hits; in ACTIVE goes FADE.
- re-hit: a fixture held on the line for 2.0 s of ACTIVE takes `floor(2.0 / rehit_interval) + 1` hits ± 1; the Lance hits a held fixture once.
- swept hit: a 14 px fixture between two consecutive tick positions of a fast-rotating beam (a test-only rate making the tip jump 40 px per tick) is hit.
- tips: a fixture inside `tip_grace_px` of the free tip is not hit; one just inside the hit length is.
- width: a fixture whose hurtbox edge is `hit_half_width + 1` px from the line is not hit (the drawn glow covers it); at `hit_half_width − 1` it is.
- exact shapes: a 96 × 44 rectangle hurtbox (the Bomber's) whose centre is 40 px off the line but whose wing crosses it is hit.
- every number in the export table is read through `EnemyBeamScenes.export_of` and matches the scene (no typed copies elsewhere in the suite).
- the fairness rows of §2.3.

### 2.2 Hit scan, damage and the owner set (R8.7; Q2, Q4, Q5, Q8)

**`EnergyHitScan`** (`enemy_beams/energy_hit_scan.gd`, static, shared by `EnemyBeam` and `EnergyRing`):
- `candidates(tree) -> Array[Node2D]`: every live node in groups `player`, `allies`, `enemies`, `asteroids` (de-duplicated, skipping queued-for-deletion).
- `is_exempt(target, host, owner_group) -> bool`: `target == host`, or `owner_group != &""` and `target.is_in_group(owner_group)`.
- `hits_band(band: Shape2D, band_xform: Transform2D, target) -> bool`: for each enabled `CollisionShape2D` under the target's hurtbox
  (`Hazards.hurt_box_of(target)`), `band.collide(band_xform, shape, cs.global_transform)` — Godot's pure shape test, so circle, rectangle and capsule
  hurtboxes at any scale and rotation are exact, and it needs no physics step (hand-tickable).
- `bounding_radius(target) -> float`: the target hurtbox's circumscribed radius (the ring's band test).
- `deliver(target, damage) -> bool`: `Hazards.hurt_box_of(target).received_damage.emit(damage)`; false with no hurtbox.
- A cheap broad phase first: skip a candidate whose centre is farther than `hit_half_width + 200` px from the segment.

**Swept test (tunnelling).** Each tick the beam tests the current band (a `RectangleShape2D` `hit_length × 2·hit_half_width` on the hit segment)
and the two triangles `(a0, b0, b1)` and `(a0, b1, a1)` spanned by the previous and current hit segments (`ConvexPolygonShape2D`, skipped when
degenerate), so a target the line crossed between two ticks is hit. A sweep tip moving 6.5 px/tick and a wall advancing 4 px/tick are below the
smallest hurtbox (~12 px), but a later boss beam would not be.

**Damage.** A direct emit, like every beam in the project (global.md's "direct emitters"): it bypasses another enemy's `EnemyShield` bubble and its
`ArmorPlate`s; a plated Ram Corvette refuses it in `RamCorvette._on_received_damage` (`is_armored()`); the station core refuses while armoured; the
player's `PlayerBase` applies its i-frames (0.5 s) and shield charge. Per target, at most one hit per `rehit_interval`, keyed by instance id, cleared
by `start()`. `target_hit` is emitted per delivered hit.

**Owner set.** `EnergyHitScan.is_exempt` targets are never hit:
- the host (the node passed to `setup()`: the turret, the drone, the fence's post pair through the fence);
- every node in `owner_group`: a `TurretGroup`'s `&"turret_group_<instance id>"` (turrets, generator, power source, fence posts), a `TwinLaserPair`'s
  `&"twin_pair_<instance id>"` (both drones and the tender that launched them).
Everything else is hit: other formations, escorts, patrols, the player, the player's allies, asteroids. Enemy ordnance is not in those groups and is
never hit.

**Scoring.** A kill by an enemy weapon goes through `BaseEnemy._on_health_changed`, sets `was_killed` and scores for the player, as rocket-impact and
level-1 column kills already do. No attribution system is built (owner choice 5).

**Rows** (`test_enemy_beams.gd`, both harnesses): an active beam hurts a fixture enemy, a real `player_ship.tscn` / `player_fighter.tscn` (respecting
i-frames: two hits 0.3 s apart deal one), a real `ally_fighter.tscn` in the Assault harness, an asteroid; never its host, never a member of its
`owner_group` (control: the same fixture outside the group is hit); a plated real `ram_corvette.tscn` takes 0 health damage; a fixture wearing a
sustained `EnemyShield` takes full damage (shields are bypassed); a live `EnemyMine` and an `EnemyRocket` on the line are untouched; an enemy killed
by a beam has `was_killed == true`.

### 2.3 Telegraph timing and fairness rules (R8.1–R8.3, R8.24)

Telegraph readability (IDEAS §21.1, F1): during TELEGRAPH the host's `StateLight` is CHARGING (yellow) and the beam draws its thin line on the exact
hit path; a Lance shows COMMIT (white, "locked shot") for its last `commit_seconds`; ACTIVE is ARMED (red); OFF is OFF. `StateLight` is reused
unchanged; the beam does not own the light — the host sets it from `phase_changed` / `is_committed()`.

**Fairness inequalities**, one gate row each in `test_enemy_beams.gd`, reading every term from scene exports (`EnemyBeamScenes.export_of`, the player's
`HurtBox` shape and `MoveState.move_speed` from `player_fighter.tscn`, never typed numbers). Reaction time `R = 0.25 s`; `v_c` = the slower mode's cruise
speed (Assault 360 px/s); `r_p` = the player hurtbox's circumscribed radius.
- **Static beams (BEAM, SWEEP start bearing, TWIN before it moves):** `telegraph_seconds ≥ R + (hit_half_width + r_p) / v_c`.
- **Sweep:** `sweep_rate × length ≤ v_c` — the tip never outruns the player (F2). (The station's 0.5 rad/s × 1536 px is a boss beam outside this rule; Ph11.)
- **Lance:** `commit_seconds ≥ 0.5` (Ph4's reactable floor, the Sniper's `lock_seconds`) and `telegraph_seconds − commit_seconds ≥ R`.
- **Twin / moving wall:** `advance_speed < v_c` and `(L / 2) / v_c + R ≤ telegraph_seconds + standoff / advance_speed` — the player can reach an end
  before the wall arrives (F6). `advance_speed`, `L` and `standoff` come from `twin_laser_drone_config.tres`.
- **Pulse Ring:** the gap arc at `max_radius / 2` is ≥ `3 × r_p`, and `telegraph_seconds ≥ R` (§2.5).
Each row also has a synthetic boundary case (a scene copy with the term pushed past the bound) that fails, so the inequality can reject.
**Which task adds which row:** the static, sweep and lance rows land with the `EnemyBeam` core (they read `beam.tscn`, `sweep_beam.tscn`,
`lance.tscn`); the Pulse Ring rows with `EnergyRing` (`energy_ring.tscn`); the twin / moving-wall row with the Twin-Laser Drone (it needs
`twin_laser_drone_config.tres`). All of them live in `test_enemy_beams.gd` except the ring rows (`test_energy_ring.gd`).

### 2.4 Endpoint beams, cover and laser-wall registration (R8.5, R8.6, R8.20, R8.21; Q6)

Builds on §2.1 and §2.6.

**Endpoint geometry.** `twin_beam.tscn` (TWIN) takes `set_endpoints(a, b)` every tick; its drawn and hit segment is `a`–`b`; `length` is ignored.
Two users in this phase: the twin pair (§2.12) and the laser fence (§2.11). One owner at every instant: the beam is a child of drone A or of the
`LaserFence`; it is freed with that owner.

**Cover (Q6).** With `blocked_by_cover` true, and **only when `Engine.is_in_physics_frame()`**, the beam clips at line-of-sight blockers using
`LineOfSight`'s opt-in rule (group `asteroids`, or `blocks_line_of_sight() == true`, i.e. wrecks): a ray on `LineOfSight.BLOCK_MASK` with the same
recast-past-non-blockers loop as `LineOfSight.clear()`, excluding the host's body. Emitter kinds: one ray origin → tip; the lethal segment ends at the
first blocker. Endpoint kinds: rays a → b and b → a; the lethal parts are `a`–`hit_a` and `hit_b`–`b` and the shadow between is safe. Expose the
blocker test as a public `LineOfSight.blocks(collider) -> bool` (the private `_blocks` becomes a call to it; behaviour identical). The drawn beam
is clipped the same way. Hand-ticked rows never cast (no physics frame), so they are deterministic; cover rows run on real physics at 8×.

**Laser-wall hazard.** With `registers_hazard` true the beam registers in `Hazards` from TELEGRAPH start to FADE start (and unregisters on
`cancel()`, FADE, OFF and `_exit_tree()`), the "registers while lit" rule. Its one `HazardInfo`, updated in place every tick:
`kind = &"laser_wall"`, `position` = the segment midpoint, `segment_half` = (b − a) / 2, `radius = draw_half_width + hazard_pad`,
`avoid_weight` (scene export: 0.5 on `twin_beam.tscn`, 1.0 on a fence's beam, §2.11), `velocity` = midpoint motion per second over the last tick
(the Ph7 `carry_velocity` lesson: the avoidance stage leads a moving wall), `source = self`, `exempt_group = owner_group` (the pair never avoids its
own wall), no pull, slow or LOS block.

**Strain.** `set_strained(true)` makes the beam non-lethal and flicker (alpha pulsing at 15 Hz from its own clock); the rig decides strain and
collapse (§2.12).

**Rows** (`test_enemy_beams.gd`): endpoint segment follows `set_endpoints()` each tick (hand-ticked, both harnesses); strained beams never hit;
registration exactly while TELEGRAPH/ACTIVE with segment, velocity and exempt group right; unregistered after `cancel()` and on free; real physics
at 8×: a `Wreck` across an emitter beam stops it (a fixture behind it is not hit, one in front is); a wreck between twin endpoints leaves a safe
shadow and both lit parts still hurt; an asteroid clips a beam; a fixture enemy body (not a blocker) does not clip it.

### 2.5 Pulse Ring: `EnergyRing` (R8.4)

`class_name EnergyRing extends Node2D` in `enemy_beams/energy_ring.gd`, scene `energy_ring.tscn`. Not `PulseRing` (Ph7's visual ring keeps that name).
- `enum Phase { OFF, TELEGRAPH, EXPANDING, FADE }` (append-only); signals `phase_changed(phase: int)`, `target_hit(target: Node2D, damage: int)`.
- `setup(host, owner_group)`, `start()`, `tick(delta)`, `cancel()`, `radius() -> float`, `is_lethal() -> bool`; owner-ticked, the same clock rule as `EnemyBeam`.
- TELEGRAPH (`telegraph_seconds` 0.8): a charge glow on the host plus a faint circle at `max_radius`; then EXPANDING from 0 at `ring_speed` 360 px/s to
  `max_radius` 280 px (0.78 s); FADE `fade_seconds` 0.15.
- An annulus of thickness `band` 24 px with `gap_count` 2 gaps of `gap_deg` 45°, rotating at `gap_spin_deg` 30°/s from a start angle drawn from the
  host brain's `rng` (passed to `start()` as an optional `gap_start_deg`).
- A target is hit **once per ring** when its centre distance `d` lies in `[r_prev − band/2 − R_t, r + band/2 + R_t]` (the swept interval since the last
  tick; `R_t` = `EnergyHitScan.bounding_radius`) and its bearing from the ring centre is not inside a gap. Owner set, victims and damage path exactly as
  §2.2 (`damage` 12). The centre is fixed at `start()`. Drawn with `draw_arc`, `top_level`.
- Counterplay: stay outside `max_radius` (short range "forces movement around the enemy"), or pass through a gap; boost does not guarantee a crossing.

**Rows** (`tests/integration/test_energy_ring.gd`, hand-ticked, both harnesses): not lethal during TELEGRAPH; hits a fixture at 150 px once when the
band passes, never twice; a fixture at `max_radius + R_t + 1` is never hit; a fixture inside a gap's bearing is not hit, the same fixture 30° outside it
is; the gaps rotate at `gap_spin_deg` (bearing at t = 0 and t = 0.5 s); swept interval: a ring advancing past a fixture between two ticks hits it; owner
set and victims as §2.2; `cancel()` stops it; the two fairness rows of §2.3.

### 2.6 Segment hazards: `HazardInfo` and `context_avoid` (R8.20, R8.21; Q7)

A change to Ph6's "walls join the registry with no change to the AI" promise: the registry is unchanged, but a wall is a segment, not a circle.
Files: `global/hazards/hazard_info.gd`, `global/hazards/hazards.gd` (unchanged code paths through `contains`), `global/enemy_ai/steering.gd`,
`global/enemy_ai/enemy_mover.gd`.

**`HazardInfo` additions.**
- `segment_half: Vector2 = Vector2.ZERO`: half the segment from `position` to one end. ZERO means a circle (every existing hazard).
- `exempt_group: StringName = &""`: an actor in this Godot group drops this info in its avoidance stage.
- `closest_point(pos: Vector2) -> Vector2`: `position` for a circle; the clamped projection on `position ± segment_half` for a segment.
- `contains(pos, margin)` and `penalty_at(pos)` use the distance to `closest_point(pos)` **only when `segment_half != Vector2.ZERO`**; the circle branch is the
  existing expression, untouched, so every existing result is bit-identical. `falloff` / `accel_at` are unchanged (a segment hazard has no pull; a row
  pins that `accel_at` of a segment info with `pull_force` 0 is ZERO).

**`Steering.context_avoid` segment branch** (only for an info with `segment_half != ZERO`; the circle loop body is not edited):
- lead the segment by `info.velocity * lookahead` (both ends), as the circle centre is led;
- `d` = distance from `pos` to the led segment's closest point; skirt exactly as the circle (`outside = max(0, d − radius)`, `skirt_reach = margin + speed · lookahead`);
- danger cones (same formula as a circle: half-width `asin(min(1, (radius + margin) / d_i)) + slot`, weight `avoid_weight · skirt`) at the closest point and at both ends;
- plus every slot whose bearing lies on the shorter arc between the two ends' bearings (as seen from `pos`) gets `avoid_weight · skirt` — the wall as a
  whole is in the way, so the clear headings are round its ends;
- merge per slot by MAX, then the existing threshold / clear-way / pick logic, unchanged.

**`EnemyMover._avoid`** additionally drops an info whose `exempt_group != &""` and `actor.is_in_group(info.exempt_group)` (next to the existing "own claimed
blocker" drop). With no such info nothing changes.

**Rows.** `tests/unit/test_hazards.gd`: `closest_point` / `contains` / `around()` for a segment (a point beside the middle, beyond an end, on the line);
circle rows untouched and green. `tests/unit/test_context_avoidance.gd`: a 420 px wall 200 px ahead across the path is avoided from 0°, 45° and 90°
approach bearings at `hazard_avoidance` 1.0 / 0.8 / 0.6 (the output heading points past an end; a hand-integrated 200 px/s path with an
accel-limited mover keeps its closest approach to the hit segment ≥ `hit_half_width` + 14 px for 1.0 and 0.8 — the task measures and prints the figures per
level, as Ph7 §2.3 did; the rows use a segment info of `radius` 38 = the twin beam's `draw_half_width` 14 + `hazard_pad` 24, the footprint §2.4 registers; **pre-approved lever** if 0.8 cannot
meet the bound: `hazard_pad` 48 (radius 62), recorded in DECISIONS so the endpoint-beam task authors it; no bound moves), a wall parallel to the path 150 px beside it leaves `desired` bit-identical, a moving wall (`velocity` 240 px/s toward the ship) is led,
an actor in `exempt_group` gets `desired` back bit-identical, and the existing pass-through and circle-avoidance rows are unchanged (they run as they are).

### 2.7 Stationary Defense Turret: shell, `TurretMount` and `AssaultDrift` (R8.8, R8.9, R8.13)

Directory `assault/scenes/enemies/defense_turret/` (`defense_turret.tscn`, `defense_turret.gd`, `defense_turret_brain.gd`, `defense_turret_config.gd/.tres`,
`ENEMY.md`, `mounts/`).

**Root.** `class_name DefenseTurret extends BaseEnemy`, **no `EnemyMover`** (so `is_ai_driven()` is false and it refuses tows). Body: one circle (r 28 for the
64–72 px standard art) on physics layer 1 (the enemy-root default; ships bump it), shared by `CollisionShape2D` and the `HurtBox` shape (so the
hurtbox-geometry gate holds). `ContactProfile` mode NONE and **no `ContactHitBox`** (`no_hitbox` in the contact-damage roster, the Bonus Drone precedent;
`collision_damage` 0). Answers `is_laser_blocking() == false`. Joins group `enemies` in `_ready()`. `StateLight` child. `sprite_forward_angle` irrelevant (the
root never rotates; `rotation` stays 0).
- `@export var variant: int = -1` — when ≥ 0, overrides the first mount slot's variant (one property a wave's `initial_props` or a group slot can set).
- `MountSlots` (Node2D) holds one or more `TurretMountSlot extends Marker2D` children (`@export var variant: TurretMount.Variant`, `@export var rest_bearing_deg`).
  In `_ready()` the turret instantiates `TurretMountScenes.scene_for(slot.variant)` at each slot and, for each mount, builds the pools its
  `TurretMount.pool_specs()` returns as **root children** (`BulletPool`, `bullet_scene`, `pool_size`, `persist_after_owner_death`), so the pools' grandparent
  is the enemy container (S7). Then it calls `mount.setup(self, pools, owner_group)`. The standard turret has one slot; the heavy emplacement two (§2.9).
- `set_powered(on: bool)`, `is_powered() -> bool`: false → every mount `power_down()`; never re-powered in this phase (a later `set_powered(true)` is ignored
  once off; Ph20 may lift that).
- `set_turret_group(group)` (before `add_child`): joins `group.owner_group` and remembers the group for staggering (§2.10); without a group the owner group
  is `&"turret_<instance id>"` so the turret's own mounts share an exempt set.

**`TurretMount`** (`mounts/turret_mount.gd`, `class_name TurretMount extends Node2D`) — **the Ph10 / Ph11 seam**: everything that aims and fires lives here,
and it never reads its host's type, so a ship module or a fortress can carry it unchanged.
- `enum Variant { BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE, BEAM_CANNON }` (append-only).
- `enum Phase { SCAN, TRACK, TELEGRAPH, FIRE, COOLDOWN, UNPOWERED }` (append-only); `signal phase_changed(phase: int)`.
- `setup(host: Node2D, pools: Dictionary, owner_group: StringName)`, `tick(delta: float, target: TargetInfo, can_fire: bool)`, `scan(delta)`, `power_down()`,
  `pool_specs() -> Array[Dictionary]` (`{name, scene, size, persist}`), `muzzle_position() -> Vector2`, `aim_error() -> float`, `phase() -> int`.
- Writes **only its own `rotation`** (local to the host; the single-writer gate forbids `actor.` / `self.` writes in brains and root writes in mover-driven
  roots, and the mount is neither). Rotation is turn-rate-limited (`turn_rate` rad/s); `rest_bearing_deg` is the scan centre and the droop target.
- **Aim (R8.9, F5):** projectile variants aim at `P.lerp(TargetInfo.intercept(muzzle, shot_speed).point, lead_blend)` (`lead_blend` 0.6; the plain
  position when `intercept` fails); beam variants aim at `P + v · lead_horizon · lead_blend` where `lead_horizon` is the beam's `telegraph_seconds`
  (the moment it can first hurt). A mount fires only when `aim_error() ≤ fire_cone_deg / 2` (8°) and `can_fire` is true. A beam never re-aims after
  its TELEGRAPH starts (the shown line is the line that fires), except the sweep's own rotation.
- **Scan idle (IDEAS §18.5 "turret scanning arcs"):** with no target the mount sweeps `scan_arc_deg` 90° about `rest_bearing_deg` at `scan_speed` 0.4 rad/s,
  starting at a phase offset from the host's `rng`.
- **`power_down()`:** any TELEGRAPH beam / ring → `cancel()` (OFF, never lethal); an ACTIVE beam → FADE; an in-progress burst or salvo stops (no further
  `acquire()`); rounds and rockets already in flight live on under their pools' rules; light OFF; phase UNPOWERED; the mount eases to `rest_bearing_deg`
  and stays there (the "droop" state, §2.15). Idempotent.
- Weapon tuning per variant lives in the **mount scene's exports** (`mounts/<variant>_mount.tscn`) and in the weapon scene it fires, never in the
  turret config (Ph10 reuses the mounts with other hosts).
- `TurretMountScenes` (`mounts/turret_mount_scenes.gd`): `scene_for(variant)` (null with no error until built), `export_of(variant, property, fallback, node_path)`.

**Brain.** `DefenseTurretBrain extends EnemyBrain` (no mover): `enum Phase { SCAN, NOTICING, ENGAGED, UNPOWERED }` (append-only),
`signal phase_changed(new_phase: int)`. Each tick: perception (Open Space: player within `perceive_radius` 900 px, kept until beyond `lose_radius` 1100 px,
after `notice_time` 0.3 s of NOTICING with a `StateLight.blink_once()`; Assault: the turret's centre is inside `EnemyWorld.view_rect()` — it never perceives or
fires from off-screen); `can_fire = powered and (can_see_player() or mount fires curving ordnance)` — the rocket battery fires past cover (the Missile
Corvette rule), every other variant holds fire without line of sight; then `mount.tick(delta, target, can_fire)` for each mount (or `mount.scan()` in
SCAN). `accepts_tow()` is false always (moot: no mover). The brain owns the host's `StateLight`: CHARGING while any mount is in TELEGRAPH, COMMIT while a
lance `is_committed()`, ARMED while any mount is in FIRE or TRACK with `can_fire`, OFF when SCAN or UNPOWERED.

**Config.** `DefenseTurretConfig extends ShipConfig` (flat, `@export_group`s): `max_health` 90, `collision_damage` 0, `score_value` 60, group "Perception"
(`perceive_radius` 900, `lose_radius` 1100, `notice_time` 0.3), group "Assault" (`assault_drift_speed` 60), hazard fields left at 0 (no mover),
`wreck_chance` 0 (static structures leave no wreck in this phase; "destroyed modules remain as wreckage" is Ph19).

**`AssaultDrift`** (`global/components/assault_drift.gd`, `class_name AssaultDrift extends Node`): the shared "static things scroll with the corridor"
rule, used by the turret, the heavy emplacement, the shield generator, the power source and the laser fence (the Wreck and Minefield keep their own
code). `@export var speed := 60.0`; `step(delta)` (hand-tickable; `_physics_process` calls it) moves the parent's `global_position.y` by `speed · delta` only
when `EnemyWorld.arena(tree)` exists, and frees the parent once its position is below `EnemyWorld.projectile_world_rect(tree).end.y`; it also exposes
`velocity() -> Vector2` (`(0, speed)` in Assault, ZERO otherwise) for anything that must lead a carried hazard. Position writes only: the parents have no
mover, so the single-writer gate is untouched. The turret copies `config.assault_drift_speed` onto it in `_ready()`.

**Burst cannon (the first mount, built with the shell).** `mounts/burst_cannon_mount.tscn`: `range` 700, `turn_rate` 2.0 rad/s, `charge_seconds` 0.4
(TELEGRAPH: light CHARGING, no line), a burst of `burst_count` 4 Pulse rounds (`assault/scenes/projectiles/enemy_bullet/rounds/pulse_round.tscn`, 8
damage, reused) at `burst_gap` 0.12 s and `round_speed` 300 px/s, from a `BurstClock`, then `cooldown_seconds` 2.2. Pool spec: name `PulsePool`, size
`EnemyRounds.pool_size_for(burst_count, round max_time, charge + burst + cooldown)` (the Ph3 helper; the round max_time is read from `pulse_round.tscn`).
**`test_enemy_bullet_lifetime.gd` gains the mount's `round_speed`** (read through `TurretMountScenes.export_of`) as a shooter of the Pulse round, so its
`max_distance / speed ≤ max_time` row covers the turret.

**`WaveBuilder`:** `DEFENSE_TURRET` const + `defense_turret()`; a variant is set with the existing `SpawnConfig.prop("variant", TurretMount.Variant.X)`
(applied before `add_child`, inside `BaseEnemy._init()`'s privatisation window).

**Rows** (`tests/integration/test_defense_turret.gd`, both harnesses unless marked): the root never rotates and has no mover; the mount turns at no more
than `turn_rate`; predictive aim: against a 200 px/s crossing stub the burst's aim point is `lead_blend` of the way to the intercept (± 2 px); no round
outside `fire_cone`; burst count, gap and cooldown from exports; scan arc and speed with no target; NOTICING blink then ENGAGED in Open Space at 899 px,
nothing at 901 px, kept until 1100 px; Assault: no round while the turret is above `view_rect()`, rounds once inside; drift 60·t in Assault and 0 in Open
Space, freed below the projectile world rect; `power_down()` stops the burst mid-way (no further acquire) with rounds in flight unaffected, light OFF,
mount at rest within `π / turn_rate`; LOS (real physics 8×): a wreck between turret and player holds fire, removing it resumes; the player's real mining
beam (`BeamBehavior`) damages the turret (it is not a blocker); the pools are root children and a round lands in the enemy container.

### 2.8 Turret weapon variants (R8.10)

Each variant is one mount scene `defense_turret/mounts/<variant>_mount.tscn` on the `TurretMount` script (or a small subclass where the cycle differs),
tuned by its own exports, fired by the shared `TurretMount.tick()` cycle SCAN → TRACK → TELEGRAPH → FIRE → COOLDOWN.

| Variant | Weapon (reused) | Cycle and starting values |
|---|---|---|
| `BURST_CANNON` (0) | Pulse rounds, `BurstClock` (§2.7) | TRACK → 0.4 s charge → 4 rounds @ 0.12 s, 300 px/s → 2.2 s cooldown; range 700 |
| `SWEEP_BEAM` (1) | `EnemyBeam` SWEEP (`sweep_beam.tscn`, length 400) | TRACK → TELEGRAPH 0.9 s with the line at the **start bearing** `aim − s · sweep_arc/2`, where `s` is the sign of the player's angular velocity about the turret (still player: `s` from the brain's `rng`), so the beam sweeps toward and through the player (F2) → ACTIVE 2.0 s turning at `s · sweep_rate` (0.8727 rad/s, 100°) → 3.5 s cooldown; range 400. The mount's `turn_rate` cap does not apply during the sweep (the sweep rate is the weapon's). |
| `ROCKET_BATTERY` (2) | Ph5 `EnemyRocket` DUMB and PURSUIT scenes from `EnemyRocketScenes`, root pools with `persist_after_owner_death = true` | TRACK → tube glow 0.5 s (light CHARGING) → salvo of 2 at 0.35 s, each PURSUIT with probability 1/3 from `rng`, else DUMB → 5.5 s cooldown; range 900; fires without line of sight. Launcher contract: the host answers `launch_velocity() -> Vector2.ZERO` and `rocket_clear_radius()` = body radius + 4; `launch(dir, aim_point, launcher)` with the mount's predicted aim point. Pool sizes from `EnemyRocketScenes.pool_size_for()` where its inputs fit, else a `pool_size` export pinned by a row to the worst-case live count. |
| `PULSE_RING` (3) | `EnergyRing` (`energy_ring.tscn`) | idle until the player is within `trigger_range` 300 → ring TELEGRAPH 0.8 s → EXPANDING to 280 → 3.5 s cooldown. The mount does not need to aim (it may keep scanning); `fire_cone` is ignored. |
| `LANCE` (4) | `EnemyBeam` LANCE (`lance.tscn`, length 1100) | TRACK → TELEGRAPH 1.0 s: the first 0.5 s the mount keeps aiming at the predicted point, the last 0.5 s (`commit_seconds`, COMMIT white) it is frozen → ACTIVE 0.2 s, 24 damage once → 4.0 s cooldown; range 1100. |
| `BEAM_CANNON` (5) | `EnemyBeam` BEAM (`beam.tscn`, length 700) | TRACK → TELEGRAPH 0.9 s on the predicted bearing (frozen at TELEGRAPH start) → ACTIVE 1.2 s holding that bearing → 3.0 s cooldown; range 700. The plain Beam's consumer (P1). |

Beams and rings are **children of the mount**, `top_level` for drawing, and set up with the turret as host and the turret's `owner_group`, so a turret
group never burns its own members (§2.2). Killing the turret frees its beam at once (F6: kill the emitter, the beam ends).

**Rows** (`test_defense_turret.gd`, both harnesses, hand-ticked unless marked; R8.24 "beam activation and telegraph timing" in both modes):
- sweep: the TELEGRAPH line is at `aim − s · 50°` with `s` following a stub moving clockwise / counter-clockwise; ACTIVE turns 100° in 2.0 s (± 1 tick) toward the
  player; a stub standing at the aim bearing is hit; the mount's turn-rate cap is not applied during ACTIVE; the beam's tip speed `sweep_rate · length` row of §2.3.
- lance: aim tracks during the first 0.5 s, frozen for the last 0.5 s (a stub that moves during COMMIT changes nothing); one 24-damage hit; StateLight COMMIT then ARMED.
- beam cannon: bearing frozen at TELEGRAPH start; lethal 1.2 s; a stub that steps out during TELEGRAPH is not hit.
- rocket battery: salvo of 2, kinds from a seeded rng (DUMB/PURSUIT counts over 30 salvos within the 1/3 binomial bound), fires with a wreck between (real
  physics 8×), rockets persist after the turret dies (real physics 8×), and the rocket clears the turret body on launch (it does not hit its own host).
- pulse ring: no ring with the player at 301 px; a ring at 299 px; cooldown; the ring never hurts the turret or its group.
- every variant: `power_down()` mid-TELEGRAPH → no hit ever; mid-ACTIVE → FADE within one tick; never restarts.

### 2.9 Heavy emplacement (R8.8 "128–192 px variants can act as heavy emplacements")

Directory `assault/scenes/enemies/heavy_emplacement/`: `heavy_emplacement.tscn` with the **same root script** `DefenseTurret` and brain, and its own
`heavy_emplacement_config.tres` (class `DefenseTurretConfig`; one config per directory for the isolation gate): `max_health` 260, `score_value` 150, the same
perception and drift. Body circle r 64 (144 px art). Two `TurretMountSlot`s: a `BEAM_CANNON` mount at (0, −30) and a `BURST_CANNON` mount at (0, 34), each
with `turn_rate` 1.2 rad/s (an export override on the slot's mount instance). Both mounts share the turret's owner group, so its beam never hits its own
cannon. One `StateLight`. `WaveBuilder.HEAVY_EMPLACEMENT` + `heavy_emplacement()`.

**Rows** (`test_defense_turret.gd`, both harnesses): two mounts aim independently; both fire in one engagement; its beam does not hit itself; HP and score
from its own `.tres`; `power_down` reaches both mounts; the roster gates of §2.19.

### 2.10 Turret groups, the power source and the shield generator (R8.11, R8.12, R8.19; Q3, Q11)

**`TurretGroup`** (`assault/scenes/structures/turret_group/turret_group.gd`, `class_name TurretGroup extends Node2D`) — a **coordinator, not a parent**.
- Authored as a scene with `TurretGroupSlot extends Marker2D` children: `@export var member_scene: PackedScene`, `@export var variant: int = -1` (turret
  variant override), `@export var rest_bearing_deg: float`. Presets in `turret_group/presets/`: `assault_pair.tscn`, built with the group (a BURST_CANNON turret at (−110, 0), a PULSE_RING turret at
  (110, 0), a power source at (0, −60), no generator; `coverage_radius` 180; level 1 places it), and `hub_defense_site.tscn`, built by the hub task once the
  heavy emplacement and the laser fence exist (§2.17). The group task also authors a test-only preset under `tests/helpers/` with a shield generator.
- `_ready()` queues a deferred `_spawn_members()` (the `spawn_into` / `ContactBlast._attach` precedent: a wave may spawn the group inside a physics
  flush) that instantiates each slot's scene, sets its `global_position` to the slot's, calls `set_turret_group(self)` and the variant override **before**
  `add_child`, adds it to the group's own parent (the enemy container) and emits `EventBus.enemy_spawned_orphan(member)` so `ScoreTracker` scores it.
  Members are therefore ordinary enemies to `BulletPool` (grandparent = container), `ScoreTracker`, group `enemies` and every roster gate.
- `owner_group: StringName` = `&"turret_group_%d" % get_instance_id()`; every member joins it (beams and rings exempt it, §2.2).
- `members() -> Array[Node2D]` (live), `is_powered() -> bool`, `add_power_provider(node: Node)`, `signal power_changed(powered: bool)`,
  `signal member_left(member: Node)`, `request_telegraph(member) -> bool` (stagger), `coverage_points() -> PackedVector2Array` (for the coverage row).
- Members leave on `tree_exiting`; the group frees itself on the tick its last member leaves (the Minefield precedent). It is never in `enemies`, never
  scored; `counts_toward_wave_clear = false`, `counts_as_escape = false` (a wave may spawn it; P2).
- **Power (R8.12):** a member answering `provides_power() == true` (a `PowerSource`) registers itself as a provider. The group is powered while **any**
  provider is alive, or always when it never had one. On the last provider's `died`, in that same call, the group calls `set_powered(false)` on every
  live member and emits `power_changed(false)`. `set_powered(false)` only sets flags and cancels beams (no physics adds), so it is safe inside the bullet
  flush that killed the source. Unpowered members stay **dark, harmless and destructible**, still score and never restart (owner choice 3). **Ph20 seam:**
  `add_power_provider()` takes any node with `provides_power()` and `died`; a jammer joins as a second provider without touching turrets.
- **Stagger:** `request_telegraph(member)` grants at most one TELEGRAPH start per `stagger_seconds` 0.3 across the group; a refused mount retries next
  tick. Overlapping fire stays readable. A lone turret (no group) always gets true.
- **Coverage rule (R8.11):** for each preset, for every bearing in 10° steps at `coverage_radius` from the group origin, at least `coverage_min` 2 turret
  mounts have `range ≥` their distance to that point (mounts rotate 360°, so range is the test). `assault_pair` uses `coverage_radius` 180,
  `hub_defense_site` 450.

**`PowerSource`** (`assault/scenes/enemies/power_source/`, `PowerSource extends BaseEnemy`, `PowerSourceConfig`): no brain, no mover; `provides_power() -> true`;
body circle r 34 (≈ 80 px reactor art), `max_health` 150, `score_value` 80, `collision_damage` 0, ContactProfile NONE, no ContactHitBox, `is_laser_blocking()`
false, group `enemies`, `AssaultDrift`. Draws an amber power line (`Line2D`, code-built, `top_level`) to every powered member, removed when the group
goes dark. Its reactor glow (a child sprite) goes dark on death — it is freed anyway; the lines are what readers see.

**`ShieldGenerator`** (`assault/scenes/enemies/shield_generator/`, `ShieldGenerator extends BaseEnemy`, `ShieldGeneratorBrain`, `ShieldGeneratorConfig`):
no mover; body r 30 (≈ 72 px dish art), `max_health` 120, `score_value` 80, NONE contact, no ContactHitBox, `is_laser_blocking()` false, `enemies`, `AssaultDrift`.
Each tick while powered it sustains a **360° `EnemyShield` bubble** on every live member of its group **except itself**, power source included, through the
Support Ship's projected-shield path: `EnemyShield.new()`, `sustain_mode = true`, `arc_deg = 360`, `capacity` 50, `regen_delay` 3.0, `regen_seconds` 2.0,
`reboot_seconds` 5.0, `radius` = member body radius + 8, `attach(member.hurt_box)` (skipped if the slot is taken, e.g. a Support Ship's ward), added to
the member, then `sustain(player position)` every tick. Unpowered or dead → no more `sustain()` → every bubble lapses after `heartbeat` 0.3 s and fades.
Cyan tethers (`Line2D`, the Support Ship's tether colour) to every shielded member. Bubbles absorb bullets and rockets (an absorbed hit consumes a default
bullet) but not beams (direct emitters, owner choice 7). A lone generator (no group) shields nothing.

**Rows** (`tests/integration/test_turret_group.gd`, both harnesses; R8.24 "power-source shutdown of a turret group"):
- spawn: a preset spawns every slot's member as a sibling (same parent), at the slot positions, in `enemies` and in `owner_group`, announced as orphans; the
  group is not in `enemies`; it frees itself after its last member is freed.
- shutdown (hand-ticked; deaths by direct `received_damage.emit` of lethal damage): with one burst turret mid-burst, one beam turret mid-TELEGRAPH and one
  beam turret ACTIVE, killing the power source puts every live member UNPOWERED in the same call: the TELEGRAPH beam goes OFF and never hits, the ACTIVE
  beam goes FADE, no pool `acquire()` for 5 s, lights OFF, `power_changed(false)` once; rounds already in flight still exist; 10 s later nothing has
  restarted; a turret killed before the source stays dead; a source killed while a turret is above the Assault view still disables it.
- shields (the test preset with a generator): every powered member except the generator has an up `EnemyShield` in its hurtbox's absorber slot (the power source included); a real Standard
  bullet (real physics 8×) is absorbed by a shielded turret and consumed; killing the generator lapses every bubble within `heartbeat + fade_seconds`;
  killing the power source lapses them too; a beam still hurts a shielded member.
- stagger: three turrets acquiring the target on the same tick start their TELEGRAPHs ≥ 0.3 s apart.
- coverage: `assault_pair` and the test preset meet the coverage rule; a synthetic preset with one turret removed fails it (boundary). The row iterates
  every `.tscn` under `turret_group/presets/`, so the hub preset joins it when the hub task builds it.
- friendly fire: a group's own sweep beam crossing its power source does not hurt it; the same beam crossing a fixture enemy outside the group does.

### 2.11 Laser fences: stationary laser walls and temporary barriers (R8.20, R8.21, R8.19 "laser emitters")

**`LaserEmitter`** (`assault/scenes/enemies/laser_emitter/`, `LaserEmitter extends BaseEnemy`, `LaserEmitterConfig`): a destructible fence post. No brain, no
mover; body circle r 18 (≈ 40 px post art; the orphan `assault/assets/sprites/enemies/laser_wall.png` is a candidate after a transparency check, else
PixelLab), `max_health` 140, `score_value` 40, `collision_damage` 0, ContactProfile NONE, no ContactHitBox, `is_laser_blocking()` false, group `enemies`. A
`StateLight` shows the fence's state.

**`LaserFence`** (`assault/scenes/structures/laser_fence/`, `class_name LaserFence extends Node2D`, `laser_fence.tscn`, `STRUCTURE.md`): **two `LaserEmitter`
children** (`PostA`, `PostB`) and one `EnemyBeam` built from `twin_beam.tscn` with fence overrides on the instance (`damage` 12, `avoid_weight` 1.0,
`registers_hazard` true). The fence ticks the beam itself (`_physics_process` → `step(delta)`, hand-tickable), feeding `set_endpoints(PostA, PostB)`.
- `enum Mode { STATIC, CYCLE }` (append-only). STATIC: TELEGRAPH (0.9 s) once, then ACTIVE held. CYCLE (a temporary barrier): OFF `off_seconds` 2.5 →
  TELEGRAPH 0.9 → ACTIVE `on_seconds` 3.0 → FADE → OFF …, starting at `phase_offset` seconds into the cycle (an export, so several barriers can alternate).
- The fence's owner group: a group member's `owner_group`, else `&"laser_fence_%d" % get_instance_id()`; both posts join it, so the beam never hurts them.
- **Collapse (F6):** when either post leaves the tree the beam is cancelled at once (FADE) and never restarts; the surviving post stays a target. The fence
  frees itself when both posts are gone.
- `set_powered(on)`: off → beam cancelled, posts' lights OFF, no restart (a fence can be a `TurretGroup` member; the hub barrier is).
- `set_turret_group(group)` before `add_child`, like a turret; the fence announces its two posts with `EventBus.enemy_spawned_orphan` when spawned by a
  group or a wave.
- Assault: an `AssaultDrift` on the fence node carries both posts; the beam's `HazardInfo.velocity` includes the drift (the fence passes
  `AssaultDrift.velocity()` as the carried velocity).
- Not in `enemies`, not scored; `counts_toward_wave_clear = false`, `counts_as_escape = false`. `WaveBuilder.LASER_FENCE` + `laser_fence()`.

**Rows** (`tests/integration/test_laser_fence.gd`, both harnesses, hand-ticked unless marked): STATIC lights after 0.9 s and stays lit for 30 s; CYCLE
timeline (OFF 2.5 / TELEGRAPH 0.9 / ACTIVE 3.0) with `phase_offset`; a fixture enemy crossing the lit fence is hurt; posts are never hurt by their own beam;
killing one post collapses the beam within one tick and it never relights; the hazard is registered exactly while TELEGRAPH / ACTIVE with the segment
between the posts; an AI fixture with `hazard_avoidance` 1.0 driven straight at a lit STATIC fence (real `EnemyMover`, hand-ticked) passes round an end
and is never hit (R8.21); an AI fixture with avoidance 0 is hit (the "accidentally hit hazards" half); `set_powered(false)` drops it; Assault drift 60·t
carries both posts and the hazard velocity reads (0, 60); real physics 8×: a wreck between the posts shadows the middle.

### 2.12 Twin-Laser Drones and the `TwinLaserPair` rig: Attack A (R8.5, R8.14, R8.15, R8.17, R8.18; F6)

Directory `assault/scenes/enemies/twin_laser_drone/`: `twin_laser_drone.tscn`, `twin_laser_drone.gd` (`TwinLaserDrone extends BaseEnemy`),
`twin_laser_drone_brain.gd` (`TwinLaserDroneBrain extends EnemyBrain`), `twin_laser_pair.gd` (`TwinLaserPair extends RefCounted`), `twin_laser_pair_spawn.tscn/.gd`
(`TwinLaserPairSpawn extends Node2D`), `twin_laser_drone_config.gd/.tres`, `ENEMY.md`.

**Drone.** A small `BaseEnemy` (28–32 px art, body circle r 13 shared by body, hurtbox and contact box), `EnemyMover` + brain, `ContactProfile` COLLISION
(`collision_damage` 8), `StateLight` (the lens light), group `enemies`. Config (flat, starting values): `max_health` 30 (one Standard or Sniper shot, two
Spread pellets, three Gatling rounds — the "destroy one drone" counterplay is cheap), `score_value` 30, `max_speed` 300, `acceleration` 900, hazards
`hazard_avoidance` 0.6, `hazard_margin` 16, `hazard_resistance` 0.1 (they are the well-bait), `wreck_chance` 0; rig group "Rig": `rig_length` 420,
`length_tolerance` 16, `strain_seconds` 0.15, `advance_speed` 240, `standoff` 260, `overshoot` 200, `slot_tolerance` 24, `form_timeout` 3.0, `break_seconds` 1.2,
`break_speed` 260, `attack_period_min` / `_max` 4.0 / 6.0 (Open Space repeat); group "Assault": `engage_seconds` 8.0, `exit_speed` 420.

**Brain phases.** `TwinLaserDroneBrain.Phase { FORM, TELEGRAPH, ADVANCE, BREAK, WAIT, SOLO, DISENGAGE, LAUNCHED, IDLE, NOTICING, RETURNING }` (append-only;
declared in full here, LAUNCHED is played from §2.13, IDLE / NOTICING / RETURNING from §2.14). `signal phase_changed(new_phase: int)`.
`accepts_tow()` is false in TELEGRAPH, ADVANCE and LAUNCHED.

**The rig.** `TwinLaserPair` (RefCounted, the `SquadController` precedent):
- `static func bind(a, b, controller: Node2D = null) -> TwinLaserPair`: both drones (and the controller, if any) join `owner_group` =
  `&"twin_pair_%d" % <rig instance id>`; each brain gets `pair`. A `TwinLaserPairSpawn` (a wave / hub spawner, `rng_seed` export) instantiates two drones
  deferred as siblings in its own parent at ± `rig_length / 2` along its local X, binds them, announces them with `EventBus.enemy_spawned_orphan`, then
  frees itself; it sets `counts_toward_wave_clear` / `counts_as_escape` false on itself.
- Frame: `centre`, `axis` u (unit, A → B), `normal` n (unit, the advance direction is `−n`), `phase` (`enum Phase { FORM, TELEGRAPH, ADVANCE, BREAK, COLLAPSED }`,
  append-only), `advance_left`.
- `leader()`: drone A while valid, else B. **Phase transitions happen only in the leader's tick** (`pair.tick(delta, caller)` advances the rig clock only when
  `caller == leader()`); each drone applies the current phase's motion in its own tick. A one-frame skew between the two drones is at most
  `advance_speed / 60` = 4 px, inside `length_tolerance` 16.
- `slot_of(drone) = centre ∓ u · L/2` (A at −u). `separation_error() = | |A − B| − L |`. `is_intact()`: both valid, not suspended, not queued for deletion.
- The beam: one `EnemyBeam` from `twin_beam.tscn`, a child of drone A, `setup(A, owner_group)`; A's brain calls `set_endpoints(A, B)` and `tick()` every tick.
  If A dies the beam is freed with it; if B dies A's brain cancels it. One owner at every instant.

**Attack A — closing laser.**
- FORM: the frame follows the player: `n = (mid(A, B) − P).normalized()` (smoothed: a turn of at most 90°/s), `centre = P + n · standoff`, `u = n.orthogonal()` signed so A's slot is the
  nearer one (no crossing). Each drone `arrive(slot, max_speed)` plus the player's velocity as feed-forward; both face their partner (`face_toward`). When both
  are within `slot_tolerance` of their slots and `separation_error() ≤ length_tolerance` → TELEGRAPH. After `form_timeout` → BREAK (retry later).
- TELEGRAPH: the frame is **latched** (the shown line is the line that advances); drones hold slots; the beam TELEGRAPHs for its `telegraph_seconds` 0.8.
- ADVANCE: both drones call their own `mover.boost(−n, advance_speed, advance_left)` every tick (boost skips avoidance but keeps hazard drift and the corridor
  constraint) for `(standoff + overshoot) / advance_speed` = 1.92 s; the beam is ACTIVE (held), sweeping through the player's latched position.
- BREAK: beam `cancel()`; drones separate along ± u at `break_speed` for `break_seconds`; then WAIT a fresh `attack_period` (Open Space) → FORM.
- **Strain and collapse:** in TELEGRAPH and ADVANCE, `separation_error() > length_tolerance` → `beam.set_strained(true)`; continuously for `strain_seconds`
  → COLLAPSED (beam cancelled; survivors BREAK and re-FORM). Back within tolerance sooner → unstrained. This makes the counterplay emergent: a well's drift
  (it applies during boost) or a wreck stopping one drone strains and collapses the beam; killing a drone collapses it at once.
- A drone without a partner is SOLO: it cannot attack; with a live controller it flies to it and docks (§2.13); in Assault it goes DISENGAGE; in Open
  Space it returns to its anchor and idles (§2.14).

**Assault (R8.18).** Frames are clamped so both slots and the whole advance stay inside `mover.constraint.inner_rect()` (the corridor's identity region,
so the constraint never bends one end). Horizontal rig above the player advancing down (`n = UP`), unless the room above the player inside the inner
rect is < `standoff`; then a vertical rig beside the player advancing across (`n = ±RIGHT`, toward the side with more room). If neither fits, BREAK. The
`EngagementBudget` (`engage_seconds` 8.0) allows **one attack per life**: after the first ADVANCE ends (or the budget runs out) → DISENGAGE
(`mover.release_constraint()`, `max_speed = exit_speed`, exit along `−n`), freed outside the projectile world rect.

**Rows** (`tests/integration/test_twin_laser_drones.gd`, both harnesses, hand-ticked; R8.24 "moving wall keeps its length"):
- length: on every TELEGRAPH and ADVANCE tick of Attack A, `separation_error() ≤ length_tolerance`, against a standing stub and a 200 px/s crossing stub, in both
  modes; the beam is lethal through ADVANCE and hits the stub once per `rehit_interval`.
- frame latch: a stub that moves during TELEGRAPH does not move the line; the line passes through the latched point.
- kill one drone during ADVANCE → beam not lethal within one tick and never relit by the survivor; kill A → beam freed; kill B → A cancels it.
- strain: a well placed beside drone B's path (both harnesses) strains the beam; it collapses after `strain_seconds`; control: no well, no strain.
- friendly fire: the beam hurts a fixture enemy on its line; never A, B or the controller.
- Assault: the rig stays inside `inner_rect()`; vertical rig when the player is near the top; one ADVANCE per life, then DISENGAGE with `constraint_released()`.
- `accepts_tow()` false in TELEGRAPH / ADVANCE (the `test_base_enemy.gd` tow table gains the brain).
- real physics 8×: a wreck in front of drone B stops it, the beam strains and collapses ("bait into terrain").

### 2.13 Laser Tender and Attack B: V-launch into a moving wall (R8.6, R8.16; Q9)

Directory `assault/scenes/enemies/laser_tender/`: `laser_tender.tscn`, `laser_tender.gd` (`LaserTender extends BaseEnemy`), `laser_tender_brain.gd`,
`laser_tender_config.gd/.tres`, `ENEMY.md`. A new roster entry (owner choice 1): the "controller ship" of IDEAS §6.10.

**Ship.** ≈ 96 px art, body circle r 40 (body, hurtbox and contact box), `EnemyMover` + brain, ContactProfile COLLISION, no gun, two visible docking
cradles (`CradleL` at (−30, 10), `CradleR` at (30, 10), each a `Marker2D` with a docked-drone sprite that hides after launch — its §23 state), `StateLight`,
group `enemies`. Config (flat, starting values): `max_health` 160, `score_value` 120, `collision_damage` 15, `max_speed` 200, `acceleration` 400,
`hazard_avoidance` 0.8, `hazard_margin` 24, `hazard_resistance` 0.3, `wreck_chance` 0.35 / `wreck_size` medium (the Mine Layer's); group "Launch":
`preferred_range` 650, `launch_telegraph` 0.6, `launch_speed` 520, `launch_max_seconds` 1.4, `lead_time_max` 1.5, `rearm_seconds` 7.0, `assault_wall_lead` 180;
group "Idle": `perceive_radius` 700, `lose_radius` 1600, `notice_time` 0.35, `idle_radius` 160, `idle_speed` 0.5; group "Assault": `engage_seconds` 10.0, `exit_speed` 380.

**Brain.** `LaserTenderBrain.Phase { APPROACH, HOLD, LAUNCH, WAIT, REARM, DISENGAGE, IDLE, NOTICING, RETURNING }` (append-only),
`signal phase_changed(new_phase: int)`; `accepts_tow()` false in LAUNCH.
- APPROACH / HOLD: hold `preferred_range` from the player on a broad arc (the Missile Corvette's HOLD idea, written fresh, not its code), facing the player.
- LAUNCH (needs a docked pair and line of sight): cradle lights CHARGING for `launch_telegraph` 0.6 s, then **`launch_pair(points)`**.
- WAIT while its pair lives; when no live pair → REARM for `rearm_seconds` (cradles empty) → HOLD with a docked pair again. **At most one live pair.**

**`LaserTender.launch_pair(points: PackedVector2Array) -> TwinLaserPair`** — the Ph10 (Carrier hangars) / Ph11 (fortress bays) seam: instantiates two
`twin_laser_drone.tscn` at the cradles (deferred, as siblings in the tender's parent, announced with `EventBus.enemy_spawned_orphan`, seeded from the tender
brain's `rng`), binds them with `TwinLaserPair.bind(a, b, self)` and puts both in LAUNCHED toward `points[0]` / `points[1]`. A docked drone that returns
(SOLO, §2.12) is re-absorbed (freed) and counts as docked.

**Attack B points (Open Space).** `P̂ = P + v · min(lead_time_max, |P − tender| / launch_speed)` (a standing player: `P + facing · 120`); `u` ⟂ the player's
heading (standing: ⟂ `(P − tender)`); `Q± = P̂ ± u · L/2`, assigned so the left cradle's drone takes the left point (the V never crosses). The wall is
placed **across the escape route** (IDEAS: "cuts off escape routes rather than simply aiming at the current player location").
- LAUNCHED: each drone `boost()`s from its cradle toward its point at `launch_speed` for `min(|Q − start| / launch_speed, launch_max_seconds)` — the two
  diverging boosts are the V. On arrival: the rig frame is `centre = mid(Q+, Q−)`, `u`, `n = (centre − P).normalized()` → FORM (short, they are at their
  slots) → TELEGRAPH (latched) → ADVANCE toward the player as one `|---|` wall for `|P − centre| + overshoot`. Then the pair continues with Attack A
  cycles (§2.12) until killed.

**Assault.** The tender enters from the top and holds in the upper band of the corridor's inner rect; **one launch per life**. Points: if the player's
`|v.x| ≥ 60` px/s, a vertical wall at `x = P.x + sign(v.x) · assault_wall_lead` centred on `P.y`, advancing horizontally toward the player; else a
horizontal wall `standoff` above the player advancing down. Both clamped into `inner_rect()`. The pair does that one attack, then DISENGAGE; the tender
DISENGAGEs after its launch or its budget (`release_constraint()`, `max_speed = exit_speed`).

**Rows** (`tests/integration/test_laser_tender.gd`, both harnesses, hand-ticked unless marked):
- the cradle telegraph shows `launch_telegraph` before the drones appear; the drones leave on diverging paths (the angle between their launch directions is
  > 20° and < 160°: a V);
- points: against a 200 px/s stub the wall centre lies on the stub's predicted path within 30 px and the wall axis is ⟂ its heading within 5°; a standing stub
  gets the facing rule;
- `|A − B|` within `length_tolerance` on every TELEGRAPH / ADVANCE tick of Attack B (R8.24 "moving wall keeps its length", for the V-launched wall too);
- the wall advances toward the stub and hits it if it stands still; a stub that runs round an end (360 px/s) is not hit;
- one live pair: no launch while a pair lives; rearm after both drones die; a lone surviving drone returns and docks;
- the tender is never hit by its pair's beam (owner group);
- Assault: vertical wall for a strafing stub, horizontal for a still one, both inside `inner_rect()`; one launch per life.

### 2.14 Twin drones and the tender: hub idle and Assault lives (R8.18, R8.23; IDEAS §18.5)

- **Hub idle.** A standalone pair (`TwinLaserPairSpawn` with `patrol_anchor`) idles as a slow rig orbit: both drones on a circle of `idle_radius` 140 about the
  anchor, opposite each other, beam OFF, through `AnchorIdle` built in the leader's brain (`perceive_radius` 650, `lose_radius` 1500, `notice_time` 0.35; config
  group "Idle"). NOTICING (a `StateLight.blink_once()`) → FORM. RETURNING when the player passes `lose_radius`: BREAK, return, IDLE.
  The tender idles round its own anchor with a docked pair (`AnchorIdle`, config group "Idle" of §2.13); NOTICING → APPROACH. A launched pair returning
  flies back to its tender and docks.
- The two radii are sized by the Ph4 inequality (the cycle's farthest actor–player distance + margin): pair: `standoff + overshoot + L/2 + break_speed · break_seconds`
  = 260 + 200 + 210 + 312 = 982 ≤ `lose_radius` 1500; tender: `preferred_range + launch_speed · launch_max_seconds` = 650 + 728 = 1378 ≤ 1600. A config row asserts both.
- `start_engaged` on both brains (default false) skips the idle, for behaviour rows (the Ph7 convention).
- **Assault lives.** Both obey the one-attack-per-life rule of §2.12 / §2.13; their DISENGAGE exits are **measured** with `tests/helpers/specialist_exit_probe.gd`
  over `corridor_starts()` (the Ram's start set), never a straight-line bound; the figures go into `test_level1_specialist_spawns.gd` lifetimes (§2.18).
- **Rows** (`test_twin_laser_drones.gd`, `test_laser_tender.gd`): idle orbit stays within `idle_radius` + 8 for 30 s with the beam OFF; notice at 649 px / not at 651;
  RETURNING beyond 1500; the radius inequalities; `accepts_tow()` rows; measured exits printed and asserted < 10 s.

### 2.15 Art (R8.22; IDEAS §21–23)

Every image comes from PixelLab under the **`pixel-art-generation` skill** (strict top-down: `view: "high top-down"`, `isometric: false`), is saved only
through `scripts/pixellab.sh`, imported, and opened and looked at (at 6× and in an in-game composite) before use. Faction palette kept (dark hull, cool
edge light, red/maroon accents); **state is shown only by lights and moving parts**, never by recolouring a hull. No texture may be ≥ 90 % opaque
(`test_entity_sprite_transparency.gd`; fix a background with `./scripts/strip-sprite-bg.sh`, not a regeneration). Hull art nose-down. Beams, rings,
telegraph lines, power lines and tethers stay code-drawn. Several candidates per important sprite; keep the best.

| Asset | Size | Path (`assault/assets/sprites/enemies/…`) | Readable state (§23) |
|---|---|---|---|
| Turret base | 64–72 px | `defense_turret_base.png` | — (static) |
| Turret heads, one per variant (burst cannon, sweep emitter, rocket pod, ring coil, lance barrel, beam cannon) | 40–56 px | `turret_head_<variant>.png` | the head rotates (aim is visible); unpowered = head darkened by `modulate` on the head only and drooped to rest |
| Heavy emplacement base | 144 px | `heavy_emplacement_base.png` (heads reused) | two heads |
| Shield generator | ≈ 72 px | `shield_generator.png` (cyan dish) | dish light off when unpowered |
| Power source | ≈ 80 px | `power_source.png` (reactor core, amber) | amber glow child sprite `power_source_glow.png`, hidden when the group goes dark |
| Laser emitter post | ≈ 40 px | `laser_emitter.png` (or the orphan `laser_wall.png` if it passes the check) | lens light (StateLight) |
| Twin-Laser Drone | 28–32 px | `twin_laser_drone.png` | lens lit red while the beam is up (StateLight) |
| Laser Tender | ≈ 96 px | `laser_tender.png` + `laser_tender_cradle_drone.png` (the docked drone, ≈ 28 px) | cradles visibly empty after launch |

**Rows:** each scene's sprite has an opaque centre and transparent corners; no two turret heads share a silhouette (pixel-diff threshold, the Ph7 mine-sprite
row); `test_entity_sprite_transparency.gd` covers every new scene through its existing sweep of `assault/scenes/enemies` (and `structures` if the sweep
roots are extended — the art task adds `structures` to the sweep roots if any structure scene draws a texture).

### 2.16 Level 1's existing laser columns: measure, then opt in (S3; Q12)

Level 1 lights `LaserRay` columns on a schedule (`level_1_director.gd` `_section_schedules`, `_spawn_laser_columns()`: deep_space 6 / 14 / 22 s, planet_approach
10 / 25 / 38 / 55 / 78 / 98 s, cloud_descent 8 / 18 / 34 s; warn 3.0 s, active 4.0 s) and a static 12-ray `LaserWallWave` (`level_1.tscn`). Their mask includes
512, so they already kill AI enemies, and since Ph2 nothing avoids them. No test replays them.

1. **Measure** with a throw-away script (not a permanent test; GUT time is precious): replay each of the three sections through a real `WaveManager` with the
   column schedule and the `LaserWallWave`, 8× clock, and count AI enemies killed by a `LaserRay` (connect each ray's hits, or `was_killed` with no player shot).
   Record the counts per section in `DECISIONS.md`.
2. **If any AI enemy dies in a column:** add an opt-in `@export var registers_hazard := false` to `LaserRay` (default false: the race gauntlet and the station are
   unaffected, byte-identical behaviour) that registers one `&"laser_wall"` segment `HazardInfo` (the ray's hit rect's long axis, `radius` = half its width +
   24, `avoid_weight` 1.0) from warn start to the end of active; `_spawn_laser_columns()` and the `LaserWallWave` set it true. Then every level-1 gate must stay
   green unchanged. **Pre-approved lever:** if any level-1 gate turns red, `registers_hazard` stays false in level 1 and the finding is handed to Ph15 in
   DECISIONS (no gate bound moves).
3. **If none dies:** change nothing; record the counts and hand the question to Ph15.

**Rows** (only in case 2; `tests/integration/test_laser_ray_hit_mask.gd` or a new small file): a `LaserRay` with `registers_hazard` registers exactly from warn
start to the end of active with the right segment; with the default it never registers; `test_laser_ray_hit_mask.gd` and `test_station_laser_phase.gd`
unchanged and green.

### 2.17 Hub placement (R8.23)

`open_space/scenes/levels/sector_hub.tscn` / `sector_hub.gd`; the clearance sweep `tests/integration/test_sector_hub_patrol.gd`.
- **Defense site:** the hub task builds `assault/scenes/structures/turret_group/presets/hub_defense_site.tscn` (a `TurretGroup` preset with `coverage_radius` 450) and instances it **under `EnemyContainer`** (so its members spawn into `EnemyContainer`),
  guarding the derelicts of `TacticalSpace` (station module, cargo platform, satellite at world ≈ (2457–2588, 887–1203)). Members (positions relative to
  the group, starting values): a heavy emplacement (BEAM_CANNON + BURST_CANNON) at (0, 0); a SWEEP_BEAM turret at (−240, 160); a ROCKET_BATTERY turret at
  (240, 160); a LANCE turret at (0, −260); a shield generator at (−120, −120); a power source at (120, −120); and one CYCLE `LaserFence` between two
  derelicts (posts ≈ 300 px apart). That is four shooters (the "2–4" of IDEAS §6.5) and every Ph8 structure rule once. The group's `rng_seed` is a scene
  export, so it draws nothing from the hub's patrol rng.
- **Pre-approved lever:** if any existing hub row turns red because the site shoots or blocks something it tests (a Ph6 battleground row with a stub inside the
  `TacticalSpace`, a patrol's idle), move the site to its own position on a 3000 px ring at the bearing the task finds clear, and say so in DECISIONS.
- **Patrol draws:** the Laser Tender is **draw 16** and a standalone `TwinLaserPairSpawn` is **draw 17** in `_spawn_patrol()`, appended after the Mine Layer (draw
  15), so every earlier seed is unchanged. Anchors on a 2600 px ring at bearings the task picks such that each anchor is ≥ 1000 px from every other patrol
  anchor and the clearance sweep passes (candidates 112.5° and −157.5°); `patrol_anchor` and the seeds are set before `add_child()`.
- **Clearance sweep:** `_patrol_groups()` gains the tender and the pair (each with its own idle ring + `perceive_radius`); `_element_radius()` gains a
  `TurretGroup` case (the max over members of member offset + its mount's largest `range`, read through `TurretMountScenes.export_of`) and a `LaserFence`
  case (half the post separation + the beam's `draw_half_width` + `hazard_pad`); the site must clear the player spawn, every `MissionTrigger` and every
  `PickupBase` by the sweep's existing margin, and the new patrols must clear the site. The site, being a group of turrets, also gets a row that no
  turret's `perceive_radius` (900) reaches the player spawn or a `MissionTrigger`.
- **Rows:** the hub preset passes `test_turret_group.gd`'s coverage row (it sweeps every preset) at `coverage_radius` 450; the seed row (draws 16 and 17; every earlier seed unchanged), composition / container-count / frame-0 IDLE rows, the site rows (members spawned
  into `EnemyContainer`, powered, shielded), clearances with a rejecting boundary, and a hub frame-time note (`Performance.TIME_PHYSICS_PROCESS + TIME_PROCESS`,
  600 frames, with and without the site), the Ph7 precedent.

### 2.18 Level 1 placement (R8.23)

`assault/scenes/levels/edelia/1/level_1_director.gd`; gates `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd`.
- **deep_space (DURATION 30 s):** `b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR).at(0, -220)` inside the existing **3.0 s** wave. The `assault_pair`
  preset: a BURST_CANNON turret at (−110, 0), a PULSE_RING turret at (110, 0), a power source at (0, −60); no generator (Assault keeps it simple; the hub shows
  the generator). It drifts in from above at 60 px/s, crosses the view in ≈ 13 s, and fires only while inside the view.
- **deep_space:** `b.twin_laser_pair().at(-250, -220)` inside the existing **20.0 s** wave (Attack A from above, one attack, then leaves).
- **planet_approach (DURATION 110 s):** `b.laser_tender().at(-300, -200)` inside the existing **62.0 s** wave (one V-launch wall, then leaves).
- AI spawns, no `.move()` / `.free_after()`, **no new wave**, so no other wave's effective trigger moves. None is in an `ENEMIES_CLEARED` section.
- **Gates:** `test_level1_specialist_spawns.gd` gains `EXPECTED_PH8` (the three rows: trigger, offset, delay, no rail, shared wave); each turret-group member,
  each drone and the tender counts as a specialist in the frozen 2.5× gate (deep_space peak today 8 of 12.5, planet_approach 7 of 7.5 at 98.0 s; the new
  lives must not raise either above its limit). Lives: a turret member = drift time to leave the projectile world rect from its spawn (computed from the
  world rect and `assault_drift_speed`, read from scene/config); a drone = `engage_seconds` + the Attack A cycle bound + `_TICK_SLACK` + measured exit; the
  tender = `engage_seconds` + launch telegraph + measured exit, and its drones' lives from their launch time. A spill-over row: no Ph8 enemy or rocket
  outlives the next `ENEMIES_CLEARED` section's last trigger. `test_engagement_deadline.gd` gains "no `ENEMIES_CLEARED` section spawns a turret group, a
  laser fence, a twin pair or a Laser Tender", a detection row and a boundary each (e.g. a tender at delay 0 in cloud_descent computes a life past its 10 s timeout).
- **Attack-in-budget rows** (slice replays through `tests/helpers/level1_slice_replay.gd`, the 16× clock confined to clock-bound rows as Ph7 did): from its
  deep_space spawn the pair reaches ADVANCE before its budget ends, once per life; from its planet_approach spawn the tender reaches LAUNCH and its pair
  reaches ADVANCE; the turret group's two turrets each fire (a round acquired / a ring started) while inside `view_rect()`, and all three members have left
  the world rect by the computed drift time.
- **Pre-approved levers, in order, if a density or deadline row turns red:** move a Ph8 spawn to another existing wave of the same DURATION section
  (never a new wave), then drop the pulse-ring turret from `assault_pair`. No gate bound moves.

### 2.19 Roster gates every new scene joins

Every new `assault/scenes/enemies/<dir>/<dir>.tscn` (defense_turret, heavy_emplacement, shield_generator, power_source, laser_emitter, twin_laser_drone,
laser_tender) must, in the task that creates it:
- be added to the hand `ROSTER`s of `test_enemy_hurtbox_geometry.gd`, `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` (each file's
  "every BaseEnemy scene is in the roster" sweep fails until it is). Structures and turrets are `no_hitbox: true` with `collision_damage` 0; the drone and
  the tender author a `ContactHitBox` sharing the body's `SubResource` shape and scale (COLLISION idiom: layer 256, mask 0);
- be added to `test_wreck.gd`'s `_SHIP_SCENES` ("no hurtbox larger than its body");
- pass the automatic sweeps: `test_config_instance_isolation.gd` (flat config, one `*config*.tres` per dir), `test_base_enemy.gd` (post-ready hurtbox mask 1121,
  the generic lethal flow; `_MIN_ROSTER_SIZE` raised to the new count), `test_entity_sprite_transparency.gd`, `test_enemy_mover_single_writer.gd` (drone and tender
  roots are mover-driven: no bare velocity / rotation writes; turret mounts write only their own rotation), `test_signal_emit_arity.gd`,
  `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`;
- add its brain to `test_base_enemy.gd::test_each_brain_refuses_a_tow_in_exactly_its_committed_phases` if it has one;
- have a dual-mode case in `test_enemy_dual_mode.gd` (both harnesses) and an `ENEMY.md` beside it.
`TurretGroup`, `LaserFence` and `TwinLaserPairSpawn` are not `BaseEnemy`s and live outside `assault/scenes/enemies/` (or are not `<dir>/<dir>.tscn` there), so
the BaseEnemy sweeps never see them; `test_project_load_integrity.gd` still loads them.

### 2.20 Gate time

Ph7 closed at **GUT 218.44 s** (2344 tests); the ceiling is 240 s; run-to-run noise ≈ ± 1 s.

**t1 (gate room) must free ≥ 10 s** (a hard floor; if it cannot, it ends `ESCALATE` with what it measured), using `tests/README.md` → Gate time rules 1–3 (8×
clock on any remaining awaiting 1× file, one shared scenario per file, drop per-tick bookkeeping no assertion reads, memoise a probe or replay several files
share). **Last lever:** a production speed-up of code a slow file exercises (the four-fighter tick behind `test_fighter_squad.gd`'s 168-layout sweep is the
obvious candidate), allowed only if every figure that file prints is bit-identical before and after. Never by lowering a tick count, duration, sample count or
grid, never by widening a bound, never by removing an assertion.

**Allotments (new GUT seconds):** t2 2.0 · t3 1.0 · t4 1.5 · t5 1.5 · t6 1.5 · t7 1.5 · t8 1.5 · t9 2.0 · t10 1.5 · t11 0.5 · t12 2.5 · t13 2.0 · t14 1.0 ·
t15 0.2 · t16 0.2 · t17 0.3 · t18 1.2 · t19 5.0 · t20 0 = **26.4 s**, so the phase ends ≤ 218.4 − 10 + 26.4 = **234.8 s**. Costs to plan with: a hand-ticked
dual-mode case ≈ 0.02–0.06 s; a real-physics case at 8× ≈ 0.25–0.4 s; a level-1 slice replay at 16× ≈ 0.6 s; a measured exit probe ≈ 1–7 s (memoised per
input set). A task over its allotment shares a scenario or converts a row to hand-ticked form first.

### 2.21 Numbers and where they come from

| Number | Value | Origin |
|---|---|---|
| Beam telegraph | 0.9 s | F1 (1.0 s for a 512 × 24 laser), shortened because our warning line is drawn on the exact path; passes the §2.3 static rule (≥ 0.34 s) |
| Ignite grace | 0.1 s | F1 (Moon Lord 0.33 s), judgement |
| Hit vs drawn half-width | 12 / 16 px | F1 (hitbox narrower than art), judgement |
| Re-hit interval | 0.5 s | the player's 0.5 s i-frames (`player_base.gd`), F3 |
| Sweep | 100° over 2.0 s, length 400 | F2 (Moon Lord 40°/s); tip 349 px/s ≤ Assault cruise 360 |
| Lance | commit 0.5 s, active 0.2 s, 24 dmg | Ph4 reactable floor; F1's 0.33 s lance; Sniper rail 28 dmg for scale |
| Pulse Ring | 360 px/s to 280 px, band 24, 2 × 45° gaps at 30°/s | F4 (rings passed through gaps), judgement |
| Turret cadence | burst 4 @ 0.12 s, 2.2 s cooldown; rockets 2 per 5.5 s | F5 (Helldivers 2 shots / 5 s), judgement |
| `lead_blend` | 0.6 | F5 (perfect lead is lethal to an evader), judgement |
| Turret HP | 90 / heavy 260 / generator 120 / source 150 / post 140 | judgement against the Standard gun's 50 per shot (2–6 shots) |
| Group stagger | 0.3 s | judgement |
| Twin rig | L 420, tolerance 16, strain 0.15 s, advance 240 px/s, standoff 260 | F6 rule (fixed length, slower than the player), judgement; advance < 360 |
| Drone HP | 30 | one Standard (50) or Sniper (40) shot, two Spread (25), three Gatling (14) — `assault/scenes/player/weapons/modes/*.tres` |
| Tender | rearm 7.0 s, launch 520 px/s ≤ 1.4 s, lead ≤ 1.5 s | judgement; the lead horizon follows the Mine Layer's capped lead (Ph7) |
| Assault drift | 60 px/s | Wreck / Minefield precedent |
| Gate floor | ≥ 10 s | P4 |

Every value marked judgement is a *starting value*: not play-tested.

### 2.22 Docs

The docs task invokes the `updating-project-docs` skill and updates: `docs/architecture/modules/assault.md` (energy weapons, turrets, structures, drones,
tender), `docs/architecture/modules/global.md` (segment `HazardInfo`, `exempt_group`, `AssaultDrift`, the beam as a direct emitter), `docs/architecture/PROJECT.md`
→ Conventions (the energy-weapon friendly-fire rule and owner set; "a turret mount writes only its own rotation"; "structures drift with `AssaultDrift`"; "no
turret group / fence / twin pair / tender in `ENEMIES_CLEARED`"), `docs/enemy-roster.md` (new `WaveBuilder` helpers), each `ENEMY.md` / `STRUCTURE.md` /
`BEAMS.md`, `CLAUDE.md` (the Phase 8 gates paragraph, in the style of the Phase 7 one), `tests/README.md` (Gate time table), the epic dossier
`docs/epics-done/cmug23ona0015m52w4t1m73bc/` (`PRD.md`, `SOURCES.md`, `REPORT.md`) and the `## Phase 8 - as built` section of `DECISIONS.md`.

## 3. Build sequence

Each step is one task in `tasks.json` (same keys). Dependencies only where the order matters.

| Key | Outcome | Depends on | Sections |
|---|---|---|---|
| t1 | Gate room: GUT −10 s or more, nothing weakened | – | 2.20 |
| t2 | `EnemyBeam` core: emitter beams (BEAM, SWEEP, LANCE scenes), timeline, hit scan, damage, owner set, fairness rows | t1 | 2.1, 2.2, 2.3 |
| t3 | `EnergyRing` (Pulse Ring) | t2 | 2.2, 2.3, 2.5 |
| t4 | Segment hazards in `HazardInfo` / `context_avoid` / `EnemyMover._avoid` | t1 | 2.6 |
| t5 | Endpoint beams (`twin_beam.tscn`), cover clipping, strain, laser-wall registration | t2, t4 | 2.1, 2.2, 2.4, 2.6 |
| t6 | Defense turret shell, `TurretMount`, burst cannon, `AssaultDrift`, roster gates | t1 | 2.7, 2.19 |
| t7 | Beam turret variants: sweep, lance, beam cannon | t5, t6 | 2.1, 2.3, 2.7, 2.8 |
| t8 | Rocket-battery and pulse-ring turret variants | t3, t6 | 2.5, 2.7, 2.8 |
| t9 | `TurretGroup`, power source, shield generator, the `assault_pair` preset | t7, t8 | 2.7, 2.8, 2.10, 2.19 |
| t10 | `LaserEmitter` posts and `LaserFence` (static walls, temporary barriers) | t5, t9 | 2.4, 2.7, 2.10, 2.11, 2.19 |
| t11 | Heavy emplacement | t7 | 2.7, 2.8, 2.9, 2.19 |
| t12 | Twin-Laser Drone, `TwinLaserPair`, `TwinLaserPairSpawn`, Attack A in both modes | t5 | 2.1, 2.3, 2.4, 2.12, 2.19 |
| t13 | Laser Tender and Attack B | t12 | 2.12, 2.13, 2.19 |
| t14 | Hub idle and Assault lives for the drones and the tender (measured exits) | t13 | 2.12, 2.13, 2.14 |
| t15 | Art: turret bases and heads, heavy emplacement, generator, power source, emitter posts | t9, t10, t11 | 2.7, 2.9, 2.10, 2.11, 2.15 |
| t16 | Art: Twin-Laser Drone and Laser Tender | t13 | 2.12, 2.13, 2.15 |
| t17 | Level-1 laser columns: measure, then opt-in `registers_hazard` | t4 | 2.6, 2.16 |
| t18 | Hub: the `hub_defense_site` preset and site, tender and pair patrols, clearance sweep | t10, t11, t14 | 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13, 2.14, 2.17 |
| t19 | Level 1: turret group, pair and tender placed; density, deadline and attack-in-budget rows | t9, t14 | 2.7, 2.10, 2.12, 2.13, 2.14, 2.18 |
| t20 | Docs, roster, dossier and the phase's as-built record | t15–t19 | 1.1, 2.21, 2.22, 3, 4, 5, 6, 7 |

Parallel lanes once t1 is in: {t2 → t3, t5}, {t4}, {t6}; then {t7, t8} → t9 → {t10, t11}; {t12 → t13 → t14}; art and placement last.

## 4. Test plan

The detailed rows sit under each design section so a task's agent sees them; this is the index.

| File (new unless marked) | Section | Harness |
|---|---|---|
| `tests/integration/test_enemy_beams.gd` | 2.1, 2.2, 2.3, 2.4 | both (hand-ticked); cover rows real physics 8× |
| `tests/integration/test_energy_ring.gd` | 2.5 | both |
| `tests/unit/test_hazards.gd`, `tests/unit/test_context_avoidance.gd` (extended) | 2.6 | unit; circle and pass-through rows unchanged |
| `tests/integration/test_defense_turret.gd` | 2.7, 2.8, 2.9 | both; LOS / rocket persistence rows 8× |
| `tests/integration/test_turret_group.gd` | 2.10 | both; the absorbed-bullet row 8× |
| `tests/integration/test_laser_fence.gd` | 2.11 | both; the cover row 8× |
| `tests/integration/test_twin_laser_drones.gd` | 2.12, 2.14 | both; the wreck row 8× |
| `tests/integration/test_laser_tender.gd` | 2.13, 2.14 | both |
| `test_enemy_bullet_lifetime.gd` (extended) | 2.7 | turret round speed |
| `test_enemy_dual_mode.gd`, `test_base_enemy.gd` tow table, roster files (extended) | 2.19 | — |
| `test_laser_ray_hit_mask.gd` or a new small file (only if §2.16 case 2) | 2.16 | — |
| `test_sector_hub_patrol.gd` (extended) | 2.17 | — |
| `test_level1_specialist_spawns.gd`, `test_engagement_deadline.gd` (extended), slice replays | 2.18 | 16× clock for clock-bound rows only |

**The R8.24 requirements map to:** beam activation and telegraph timing in both harnesses → §2.1 timeline rows, §2.8 per-variant rows; beam damage to allies
→ §2.2 rows, §2.10 friendly-fire row, §2.12 row; power-source shutdown of a turret group → §2.10 shutdown rows (both harnesses); the moving wall keeping its
length → §2.12 length rows and §2.13 Attack B length row (both harnesses). Every new enemy also has a dual-mode case (§2.19).

**Boundary cases that prove the gates can fail:** each §2.3 fairness inequality (a synthetic scene past the bound); the hit-width ±1 px rows; the ring's
`max_radius + R_t + 1`; perceive 899 / 901 px; the coverage rule with a turret removed; strain with a well vs no well; a laser fence with avoidance 0;
Ph8 spawns in an `ENEMIES_CLEARED` section; hub clearance with a rejecting element.

## 5. Risks

- **Gate time** (P4): the phase adds ≈ 26 s; t1 must free ≥ 10 s first, and the fighter-squad sweep may need a bit-identical production speed-up. If t1
  cannot reach the floor it escalates rather than letting later tasks run over.
- **Friendly fire in level 1:** turret beams and the drones' wall can kill level-1 enemies early. Density gates count alive enemies (fewer is fine), but a
  kill changes `ScoreTracker` totals and could move an exit or a characterization row; the §2.18 levers move a spawn, never a bound.
- **Segment avoidance** touches `Steering.context_avoid`, run by every AI enemy every tick. The circle branch is untouched and the pass-through rows stay;
  the risk is the new branch producing oscillation along a long wall (mitigated by the existing `prev_dir` blend; rows integrate a path).
- **Twin rig stability:** two independent movers must keep a fixed separation. Identical boosts make it exact by construction, but drift, the corridor
  constraint and a one-frame skew can strain it; the tolerance (16 px) and strain window (0.15 s) are judgement and may need tuning against the rows.
- **Hub crowding:** a defended site near the Ph6 battleground could shoot stubs in existing hub rows; the §2.17 lever moves the site.
- **Hand-ticked vs physics:** cover and LOS only exist on the physics step. Rows involving blockers must run on real physics, or they silently pass.
- **Nothing is play-tested.** Numbers marked judgement need an owner play-through; readability of six head silhouettes at 48 px is the most likely art redo.

## 6. Out of scope

| Item | Owner | Reason |
|---|---|---|
| Turrets mounted on large ships, stations and bosses | Ph10 / Ph11 | Scope line; `TurretMount` is the seam |
| The space station's laser phase and hull sweep on `EnemyBeam` | Ph11 | Station stays byte-identical (S1) |
| Turret groups linked to jammers; `disables_abilities` | Ph9 / Ph20 | `add_power_provider()` / `set_powered()` are the seam |
| Placed Assault encounter geometry (turrets as corridor layouts beyond level 1's three spawns) | Ph15 | Ph6 rule for placed Assault structures |
| Encounter compositions around a defense site; squad use of beams | Ph13 / Ph14 | |
| Difficulty variants (telegraph lengths, lead, cadence; the Lance's decoy telegraph) | Ph16 | The fairness rows keep any tier inside the bounds |
| Beam and turret audio | Ph17 | No enemy SFX pipeline |
| Destroyed turrets left as wreckage | Ph19 | `wreck_chance` 0 here |
| Beams shooting down enemy ordnance; a re-pairing of lone drones | owner option / Ph14 | |
| The player's mining beam stopping at every layer-1 enemy root (S13) | follow-up | Only new roots answer `is_laser_blocking()` false here |
| Heavy Shell consumer | Ph10 | P5 |

## 7. Requirements coverage

| Req | What | Task(s) |
|---|---|---|
| R8.1 Beam | immediate line with telegraph | t2 (BEAM kind), t7 (BEAM_CANNON consumer), t11 |
| R8.2 Sweeping Beam | rotates for a short window | t2 (SWEEP scene), t7 (sweep mount) |
| R8.3 Lance | narrow, high damage, very short active | t2 (LANCE scene), t7 (lance mount) |
| R8.4 Pulse Ring | expanding radial attack | t3, t8 |
| R8.5 Twin-Beam / Endpoint Laser | endpoints define the laser; sweep through the player; hold while host moves; rotate about an anchor; hurt enemies | t5 (endpoints, cover, registration), t12 (drones), t10 (fence); "rotate about an anchor" = an emitter beam on a rotating mount (t7) — the station's case moves in Ph11 |
| R8.6 Moving Laser Wall | a `\|---\|` wall translated toward the player; controller fires endpoints at predicted points | t12, t13 |
| R8.7 Beams hurt anything on the line, enemies included | owner-set rule | t2, t3, t5 (and every consumer) |
| R8.8 Turret role and sizes | standard 48–96 px, heavy 128–192 px | t6, t11, t15 |
| R8.9 No movement, rotating mount, predictive aim | | t6 |
| R8.10 Weapon variants (burst, sweep, rocket battery, pulse ring, lance) | | t6, t7, t8 |
| R8.11 Groups of 2–4, overlapping lanes | coverage rule, stagger | t9, t18, t19 |
| R8.12 Standalone / shield generator / power source disables the group; mounted on ships; jammer link | | t6, t9; mounting → Ph10; jammer link → Ph9 / Ph20 |
| R8.13 Assault: static corridor hazards; mounted on boss structures | drift, view-only fire | t6, t19; boss mounting → Ph10 / Ph11 |
| R8.14 Twin drones as one weapon | | t12 |
| R8.15 Attack A, stable length | | t12 |
| R8.16 Attack B, V-launch → wall | | t13 |
| R8.17 Counterplay (go round the ends, kill one, bait into terrain / a well, beam hurts the formation) | strain/collapse, friendly fire | t12, t13 |
| R8.18 Assault: endpoints constrained to the corridor | | t12, t13 |
| R8.19 Defensive structures (turrets, shield generators, missile batteries, laser emitters; jammer towers → Ph9) | | t6–t11 |
| R8.20 Temporary laser barriers, stationary laser walls | | t10; level 1's existing columns t17 |
| R8.21 Enemies understand them (avoid damage zones, accidentally hit) | segment hazards | t4, t5, t10, t17 |
| R8.22 Art and readable states | | t15, t16 |
| R8.23 Assault waves and the hub's ambient spawn | | t18, t19 |
| R8.24 Tests in both harnesses (activation and telegraph timing, beam damage to allies, power-source shutdown, wall keeps its length) | | t2, t7, t9, t12, t13 |
| R8.25 Design checklist (IDEAS §43) | answered per entity in each `ENEMY.md` | t6, t11, t12, t13, t20 |
| §11.3 "a real projectile/beam family, not a boss-only effect" | | t2 (station migration → Ph11) |
| §18.6 "missile batteries" | the ROCKET_BATTERY turret | t8 |
| IDEAS §18.5 "turret scanning arcs" | scan idle | t6 |
