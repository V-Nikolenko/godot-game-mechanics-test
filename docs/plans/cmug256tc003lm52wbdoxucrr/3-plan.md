# Enemy rework, phase 12: Dreadnought hunting boss

Revision 1 (2026-11-25). Epic `cmug256tc003lm52wbdoxucrr`, phase 12 of the enemy rework (idea `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`). Built on this directory's
`1-context.md` (what exists, requirements R1–R20) and `2-research.md` (scope check S1–S12, findings F1–F7, options). Code facts read on `agent/auto-dev` @ `1fee829`.

## Summary for the owner

- **For the player:** a new boss, the **Dreadnought**, a 450 px warship that *hunts* you: it closes in, then circles you on long, slow arcs with one side turned to you so its
  cannons sweep across you as it turns. Get behind it and it fires manoeuvring jets to swing round; its engines leave a burning wake you must not fly through.
- **Weapons:** heavy cannons down each side (the broadside sweep), a fan of five missiles, a slow energy torpedo you can shoot down, the engine wake, and once its core is badly
  damaged a telegraphed full-speed ram with a drawn lane and a long, punishable recovery.
- **You choose what to break first, nothing is locked:** a weapon (that attack stops, but two interceptors burst out of the wreck), an engine (one lost: it lists and turns badly
  one way; both: it stops dead in an extreme-weapons frenzy but can never ram), the shield generator (bubbles on core and engines drop), or the core (its death is the boss's).
- **Destruction shows:** wrecked parts stay as smaller stumps and fling off a chunk of debris, so the silhouette shrinks; lights show armed, charging, shielded.
- **Where:** a hunting zone at the far south-west of the Open Space hub (it gives up if you leave), and an Assault version built and tested in the corridor (it crosses the top of
  the screen broadside-on and dives at you when critical), ready for a level designer to place.
- **Built for later bosses:** bays that launch from their own wreck, a missile rack that fires a fan, a torpedo tube turret, a reusable engine-wake hazard.
- **Left out:** a level placement (phase 15), a boss health bar and sound (17), lasers hurting boss parts and wrecks as cover (18–19), difficulty tiers (16).
- **Main risks:** a 450 px ship crowds the Assault screen (fairness checks on every attack, bullets measured per phase against the fortress ceilings); the free order must stay a
  real choice (each target has a gain and a cost; nothing is play-tested); the test suite is ~12 s under its limit, so the first task wins time back.
- **Choices (default in brackets):** 1. Who bursts out of a destroyed weapon? [two Gatling Interceptors] 2. Let launch bays fire from their own wreck, changing phase 11's
  "bays stop when their part dies" for bays that opt in? [yes] 3. Does the wake hurt other enemies (bait-able) but not the Dreadnought or its interceptors? [yes]
  4. Place it in a level now? [no, phase 15] 5. Put it in the hub as a roaming hunter in its own zone? [yes] 6. Ram damage of your 50 HP / hull touch? [35 / 25]
  7. EMP lasts 40 % on it, like the fortress? [yes] 8. Spend the first task winning back test-suite time? [yes]

## For every task

Phase 12 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line here changes them.
- **Names.** The boss is the **Dreadnought**: `class_name Dreadnought` (root, `BaseEnemy`), `DreadnoughtBrain` (`EnemyBrain`), flat `DreadnoughtConfig` (`ShipConfig`), folder
  `assault/scenes/enemies/dreadnought/` (`dreadnought.tscn`, `dreadnought.gd`, `dreadnought_brain.gd`, `dreadnought_config.gd/.tres`, `ENEMY.md`), `WaveBuilder.dreadnought()` /
  `DREADNOUGHT`. Never "station" for a boss. "Ph12 owner choice N" = the owner summary's choice N.
- **Local axes (Carrier convention):** the nose is local **+y** (`EnemyMover` default `sprite_forward_angle` PI/2); **port = local +x**, **starboard = local −x**. In heading terms:
  starboard = heading rotated +90° in screen coordinates (`Vector2(-h.y, h.x)`), port = `Vector2(h.y, -h.x)`. A **starboard turn** increases the heading angle (screen
  clockwise), a **port turn** decreases it. A clockwise orbit keeps the centre on the starboard side. Mount bearings: 0° = local +x (port abeam), 90° = local +y (bow).
- **Part ids** (`const` on `Dreadnought`): `TORPEDO_TUBE` `&"torpedo_tube"`, `MISSILE_RACK` `&"missile_rack"`, `BROADSIDE_PORT` `&"broadside_port"`, `BROADSIDE_STARBOARD`
  `&"broadside_starboard"` (the four WEAPON parts), `SHIELD_GENERATOR` `&"shield_generator"` (WEAK_POINT), `CORE` `&"core"` (CORE), `ENGINE_PORT` `&"engine_port"`,
  `ENGINE_STARBOARD` `&"engine_starboard"` (ENGINE). All under the `Modules` node (`ModularHull`), **every part `starts_vulnerable` true** (no locks: the free order).
- **Hull rule: armoured** (Ph10 "one rule per boss"; the fortress / Carrier rule): the root refuses all damage (`armor_deflected`), `deflects_hit` / `is_armored` true, shots cross it
  to the parts; **the core's death is the boss's death**. Root layer 0 / mask 0. Body, root `HurtBox` and `ContactHitBox` share one `RectangleShape2D` 208 × 448.
- **Two phase tracks** (two `BossPhaseDriver` nodes, both ordinary one-way ladders, no driver change): `PhaseDriver` = hull track `hunting` (START) → `critical` (core ≤
  `critical_core_ratio` 0.35); `EngineDriver` = engine track `twin_engines` (START) → `listing` (1 of the two engines destroyed) → `crippled` (both). The root forwards each entry as
  `DreadnoughtBrain.on_boss_phase(track: StringName, phase_id: StringName)` with track `&"hull"` / `&"engines"`; nothing is applied once dying. `BossReinforcements` binds `PhaseDriver`.
- **Root API** (t6): `modular_hull()`, `part(id)`, `phase_driver()`, `engine_driver()`, `shield_sector()`, `reinforcements()`, `owner_group()` (`"dreadnought_%d" % instance id`),
  `is_assault()`, `is_dying()`, `engines_alive() -> int`, `dead_engine_side() -> int` (+1 port, −1 starboard, 0 none / both, written by the phase handler on `listing`),
  `phase_snapshot() -> Dictionary` (six keys `movement`, `attacks`, `vulnerable`, `arena`, `reinforcements`, `visuals`, **phase-driven fields only**, never which parts live);
  signals `armor_deflected(damage: int)`, `death_started`.
- **Brain API** (t6 stubs, filled by t7–t11): `bind(host, hull, reinforcements)`, `on_boss_phase(track, phase_id)`, `silence()`, `on_emp_started()`, `is_engaged()`, `attack_gate() -> bool`
  (zero-argument `telegraph_gate`), `movement_snapshot()`, `attacks_snapshot()`, `arena_snapshot()` (`[]` until built), `heading() -> Vector2`, `phase()`;
  `enum Phase { IDLE, NOTICING, RETURNING, ENTER, HUNT, LINE_UP, WIND_UP, CHARGE, RECOVER, HOLD }` (append-only). Engaged = HUNT, LINE_UP, WIND_UP, CHARGE, RECOVER, HOLD.
- **Single writers:** the brain only requests (`request_velocity`, `face_toward`, `boost`, `halt`); the `EnemyMover` writes `velocity` / `rotation` / `move_and_slide()`
  (`test_enemy_mover_single_writer.gd`). Paths bend **only** through the brain's own heading turn (Ph2: `max_turn_rate` turns the sprite only). The mover authors
  `turn_lerp` 0, `acceleration` / `braking` 0 (instant velocity) and a `max_turn_rate` above any rate the brain uses. After death starts `suspend_ai()` runs and
  `BossDeathSequence` alone writes the rotation.
- **Config:** every number in `dreadnought_config.tres` (flat; `test_config_instance_isolation.gd`); mount tuning in mount scenes / `TurretMountSlot` exports; bays on `ReinforcementBay`
  exports; phases as `BossPhase` sub-resources. Never write to a loaded resource. The config value wins over the scene's `Health`.
- **Shared-machinery changes are opt-in and bit-identical by default:** `ReinforcementBay.Trigger.ON_OWN_DESTROYED` (appended), `RocketBatteryMount.fan_count` 1 / `fan_spread_deg`
  0, `TurretMount.Variant.TORPEDO_TUBE` (appended, = 9), `HazardField.damage_exempt_group` &"" and `Hazards.pulse_damage(..., exempt_group := &"")`. Every existing suite
  (fortress, carrier, gunship, turrets, corvette, bomber, hazards) is the regression net and must stay green unchanged.
- **Clocks** are accumulated `delta` (`x -= delta`, over at `x <= 1e-6`); no `Timer` / `create_timer` in brains, weapons or hazards (a `Timer` *node* only for the death free).
- **Spawning** (escorts, wake puffs, debris) happens from the brain / root tick on the physics step or idle code, never inside a physics callback; hazards go deferred through
  `spawn_into(Hazards.container(tree), ...)` and nothing spawns when there is no container.
- **Mode:** `EnemyWorld.arena(get_tree()) != null` = Assault. In Assault nothing the Dreadnought owns fires outside `EnemyWorld.view_rect()`; no engagement budget, no exit
  (a boss); `world_anchored_x` true (`.at(x, y)` lands at world x `640 + 2x`). Open Space: world space, no camera maths.
- **Fairness and density (Ph11 convention):** inequalities read from **instantiated** nodes; measured Assault density in every phase state (`hunting`, `listing`, `crippled`,
  `critical`, `critical`+`crippled`): Dreadnought-owned launches mean ≤ 13.3 /s, peak ≤ 30 per half-open 2 s window, ≤ 2 committed attacks (3 in `critical` or `crippled`);
  a hand-ticked density row counts launches and returns each round to its pool at once; a count during which a pool reported empty fails. Tune in the stated lever order, never widen a bound.
- **Signals** declare exactly what they emit; per-frame / per-hit prints only behind `OS.is_stdout_verbose()`.
- **UIDs:** never hand-type or copy a `uid://`; leave references UID-less or mint with the `tests/README.md` snippet. Never run `update_project_uids`.
- **Tests:** GUT, tests first, both harnesses (`tests/helpers/enemy_ai_harness.gd`, `use_parameters(MODES)`) for every Dreadnought behaviour row; spawn through
  `tests/helpers/dreadnought_fixture.gd` (t6). Hand-ticked where possible (tick the **brain** then the mover); real-physics rows at 8× (16× only for tick-paced files). A hand-ticked
  boost row starts with `await _fresh_idle_delta()` (Ph10). Run `scripts/check-test-leaks.sh` after anything that awaits. Gate: `bash /agent/verify.sh`.
- **Gate time:** record GUT before/after (two-run mean of `scripts/gate-time.sh`) in `tests/README.md` → *Gate time*; stay inside your allotment (plan §2.14); escalate past a
  237 s two-run mean or 1.5× your allotment. Gate output stays well under 1 MiB.
- **Art:** invoke `pixel-art-generation` before any PixelLab call; strict top-down; save with `./scripts/pixellab.sh`; look at every image; no texture ≥ 90 % opaque. Until t12,
  placeholders reuse existing Carrier / fortress PNGs.
- **Docs:** each task keeps `dreadnought/ENEMY.md` (and any HAZARD.md / module doc it touches) true; t14 runs `updating-project-docs` for the phase. A departure later phases depend
  on goes into `DECISIONS.md` under `### Phase 12, built in tN`.

## 1. Problem

The roster has one boss, the Space Fortress: it holds a zone and makes the player circle *it*. The idea (IDEAS §9) asks for its opposite: a large ship that **hunts** the
player, moving on long arcs "like two enormous bodies trying to change position relative to each other", built from detachable modules, attacking with a broadside sweep, a
missile fan, an energy torpedo, an engine-wake hazard and a critical ram; the player picks what to disable first (weapons, engines, shields, core) with no prompt; losing one engine
makes it visibly lopsided, losing both makes it stationary with an extreme weapons phase (IDEAS §9, §24, §25, §26); destroying a weapon launches interceptors from that module
(§10); its art changes silhouette as parts become wreckage (§21–23); tests in both modes (§40).

### 1.1 Scope check (from `2-research.md` §1, re-validated @ `1fee829`)

| # | Finding | Effect on this plan |
|---|---|---|
| S1 | Ph10 `EnemyModule` / `ModularHull` / `TurretMountBuilder` and Ph11 `global/boss/` exist and are boss-agnostic | reused unchanged except the opt-in additions in §2.2–§2.5 |
| S2 | `BossPhaseDriver` is one ordered ladder ("a later phase never jumps its predecessor") and the fortress locks parts until earlier phases | free order = **two tracks** (§2.1) and **no locks**; the driver is unchanged |
| S3 | a bay whose part is destroyed is killed in the same call (`boss_reinforcements.gd` `_on_module_destroyed` → `_kill`) | **changes the Ph11 convention** for opt-in bays: `ON_OWN_DESTROYED` (§2.2, Ph12 owner choice 2) |
| S4 | no torpedo in any family; `RocketBatteryMount` has no spread; no wake hazard; `ContactProfile` deals one `collision_damage` | small additions §2.3–§2.5; ram damage by the Ram Corvette's runtime switch (§2.10) |
| S5 | the Carrier's engine loss sags the **facing**, not the path | the Dreadnought changes the **path** (asymmetric turn rates, yaw bias, drift), measured on positions (§2.7) |
| S6 | destroyed parts stay as wreckage (Ph10/11); capital wrecks / LOS wreckage are Ph19 | wreck **stumps** smaller than the intact art + a flung `DebrisFragment` chunk (§2.12) |
| S7 | the scope names no level placement; Ph15 owns Assault level migration | Assault mode built and tested in the harness, `WaveBuilder.dreadnought()`, **no level placement** (Ph12 owner choice 4) |
| S8 | hub draws 1–21 appended; `test_sector_hub_patrol.gd` sweeps footprints | draw 22 with a hunting leash (§2.13) |
| S9–S10 | fortress suites run both harnesses; `test_boss_phase_rules.gd` sweeps every driver in a boss | same pattern; the sweep must find the Dreadnought and both its drivers |
| S11 | GUT ≈ 225.2 s of 240 s (escalation 237 s) | **gate-room task first** (t1), allotments ≤ 13.8 s (§2.14) |
| S12 | deferred items unchanged (beams vs parts, capital wreck, Ph18 Carrier/Gunship migration, Ph13/14 encounters, Ph16 tiers, Ph17 HUD/audio) | out of scope (§6); death leaves no capital wreck |

### 1.2 Research used (from `2-research.md` §2; numbers marked *judgement* are starting values, nothing was play-tested)

- F1 (Starsector Conquest / Onslaught): a broadside capital is slow-turning (≈ 0.07–0.1× a fighter's turn rate) and needs a short **burst-turn** (Maneuvering Jets) and rear
  coverage, not a permanently higher rate → jets burst (§2.7) + the wake behind the stern (§2.9).
- F2 (Starsector AI notes, naval devlog): broadside AI thrashes at the side switch and when avoidance overrides intent → remember the engaged side, switch with hysteresis (§2.7).
- F3 (Starsector damageable modules): engine loss shows as movement in the world (speed, turn, drift toward the dead side) → §2.7 listing.
- F4 (Dark Souls 3 frame analysis, Death's Gambit): telegraph ≥ 0.34 s for melee, proportional to the opening → ram telegraph frozen-line ≥ clearance / player speed + 0.25 s, long recovery (§2.10).
- F5 (Battlesnake, Gungeon Wallmonger): trails decay, damage only while drawn → wake 3 s, no damage in its fade (§2.5).
- F6 / F7 (Everspace 2, Squadrons, Horizon): a free order needs a cost on every choice; reinforcements on part loss punish progress unless capped → the target matrix (§2.6.4) and caps (§2.11).

## 2. Design

### 2.1 Two phase tracks for a free destruction order (IDEAS §9, §25; t6)

The player may break weapons, engines, shields or the core in any order (R7). One ordered ladder cannot express that (a `critical` behind the engine phases would be unreachable
core-first). Rejected: one linear ladder (violates R7), an unordered driver mode (changes `BossPhaseDriver`'s core invariant for no gain), engines outside the ladder (the
one-/two-engine shifts would escape the §25 gate). **Chosen: two ordinary `BossPhaseDriver` nodes on one host**; weapons and the shield generator are not phase gates at all.

| Node | Track | Phases (`BossPhase` sub-resources, in order) | Declared `changes` |
|---|---|---|---|
| `PhaseDriver` | `&"hull"` | `hunting` START; `critical` HEALTH_AT_OR_BELOW `health_module` `core`, `health_ratio` 0.35 | `critical`: MOVEMENT, ATTACKS, VISUALS |
| `EngineDriver` | `&"engines"` | `twin_engines` START; `listing` PARTS_DESTROYED `module_ids` [`engine_port`, `engine_starboard`] `count` 1; `crippled` same ids `count` 2 | `listing`: MOVEMENT, ARENA, VISUALS; `crippled`: MOVEMENT, ATTACKS, ARENA, VISUALS |

- `DreadnoughtConfig.critical_core_ratio` 0.35 must equal the scene's `critical` `health_ratio` (a row pins it).
- The root binds both drivers in `_ready()` (after the hull and shields), connects each `phase_entered` with its track name bound, and calls `brain.on_boss_phase(track, id)`
  then its own visual handler; **nothing is applied once dying** (a part killed during the death sequence may still step a ladder).
- `BossReinforcements` takes one driver: pass `PhaseDriver` (the Dreadnought's bays use `ON_OWN_DESTROYED`, no phase gate).
- `tests/integration/test_boss_phase_rules.gd` already collects every driver in an instantiated boss: add a row that `dreadnought.tscn` is found with **two** drivers, both `validate(hull)` empty.

**What each phase does (consequences live in the brain / root; values in the config):**

| Phase | movement (t7, t10) | attacks (t8) | arena (t9) | visuals (t6) |
|---|---|---|---|---|
| `listing` | speed × `one_engine_speed` 0.65; turn toward the dead side × 1.0, toward the live side × `one_engine_live_turn` 0.35; yaw bias `one_engine_yaw_bias` 0.08 rad/s and drift `one_engine_drift` 18 px/s toward the dead side; jets keep the asymmetry | — | the live engine overburns: wake radius × `listing_wake_radius_factor` 1.3, life × `listing_wake_life_factor` 1.3 | `ListSmoke` overlay shown on the dead side |
| `crippled` | translation 0 (`request_velocity(ZERO)`; hazards may still drift it); rotation by thrusters only at `thruster_turn_rate` 0.12 rad/s; no jets, no ram | every live mount's `cooldown_seconds` × `crippled_cooldown_factor` 0.6 (once, guarded); attack cap 3; torpedo tube cooldown × the same | wake off | `EmergencyLights` mode `&"strobe"` |
| `critical` | engines overload: speed × `critical_speed_factor` 1.15 with ≥ 1 engine; the **ram cycle** enabled with ≥ 1 engine (t10); with both engines dead `thruster_turn_rate` × `critical_thruster_factor` 1.5 instead | cooldowns × `critical_cooldown_factor` 0.75 (once, guarded; compounds with crippled to 0.45); attack cap 3 | — | core light `&"blink"`, `CriticalOverlay` visible |

On the path where `critical` is entered with both engines dead the ram cannot happen; MOVEMENT still changes (thruster rate), and the Ph11 rule applies: that path gets its own
§25 row asserting ≥ 2 changes.

### 2.2 Bays that launch from their own wreck: `ReinforcementBay.Trigger.ON_OWN_DESTROYED` (IDEAS §10; t2)

**A deliberate change to the Ph11 convention "reinforcements come out of a bay on a live part and stop when that part is destroyed"**, for bays that opt in (Ph12 owner choice 2).
Every other trigger stays bit-identical. Files: `global/boss/reinforcement_bay.gd`, `global/boss/boss_reinforcements.gd`; tests `tests/integration/test_boss_reinforcements.gd`
(new rows appended, every existing row unchanged), `tests/helpers/fixture_boss_host.tscn` may gain a bay.

- `enum Trigger { PERIODIC, ON_SECTOR_LOSS, ON_PHASE, ON_OWN_DESTROYED }` (appended).
- `BossReinforcements._on_module_destroyed(part)`: for a live bay whose own part is `part`: if `trigger == ON_OWN_DESTROYED` **and** the bay is activated
  (`active_from_phase` empty or reached), queue one launch of `count_for(assault)` and mark the bay **breaching** (not dead); otherwise `_kill()` as today. A loss before
  activation is dropped (bay killed), the Ph11 t2 rule.
- A breaching bay runs the normal door cycle on the wreck: CLOSED → OPENING (`door_seconds`; the part's `Light` goes CHARGING, restored to its pre-open state = OFF on close)
  → LAUNCH at the bay's `Mouth` (still valid: wreckage stays) → OPEN for `open_hold_seconds` → CLOSED → `_kill()` (dead for good). If `_open()` refuses (no room under the
  live cap, or the Assault limit reached) the breach is spent: skipped is counted and the bay dies — **one chance, no retry** (F7: two quick kills cannot stack past the cap).
- `tick(delta, false)` holds a breaching bay exactly like any other (a launch caught mid-OPENING goes back to the front of its queue). `surge()` on a breaching bay returns 0.
- New query `is_breaching(bay_id) -> bool`. `is_dead()` is false while breaching, true after. `launched` / `door_changed` signals unchanged.
- The host's death: the host stops ticking its `BossReinforcements` and scuttles (Ph11), so a queued breach never launches — no new code, a row pins it.

**Rows** (`test_boss_reinforcements.gd`, fixture host): (1) a breach launches `count` escorts at the wreck's `Mouth` after `door_seconds`, announced on
`EventBus.boss_escort_spawned`, then `is_dead()`; (2) the light is CHARGING during OPENING and OFF after; (3) no room under the cap → nothing launched, `skipped` 1, bay dead;
(4) Assault limit reached → nothing, dead; (5) EMP hold (`tick(dt, false)`) mid-OPENING → launches after `active` returns; (6) host stops ticking (death) mid-breach → nothing ever
launches; (7) a non-breach trigger's part destroyed → killed in the same call as before (boundary); (8) `surge()` on a breaching bay returns 0; (9) a bay with
`active_from_phase` not yet reached → dropped and dead.

### 2.3 Missile fan: `RocketBatteryMount.fan_count` / `fan_spread_deg` (IDEAS §9 "missile fan"; t3)

`assault/scenes/enemies/defense_turret/mounts/rocket_battery_mount.gd` gains `@export var fan_count: int = 1` and `@export var fan_spread_deg: float = 0.0` (the Ph11 t3
`BurstCannonMount.pellets` precedent). Each salvo step launches `fan_count` rockets on the same tick, directions spread evenly over `[-fan_spread_deg / 2, +fan_spread_deg / 2]`
about the barrel (`fan_count` 1 → exactly the barrel, **bit-identical**: same rng draws, same direction). Each rocket draws its own kind (`pick_kind()`), each emits `round_fired`,
each refused one counts in `rockets_refused`. `pool_specs()`'s stand-in salvo becomes `salvo_count × fan_count`. The aim cone check stays once per salvo step.

**Rows** (`tests/integration/test_turret_mount_variants.gd`, hand-ticked): fan 1 / 0 launches one rocket along the barrel with the same draws as before (boundary);
fan 5 / 40° launches five rockets at −20, −10, 0, +10, +20° from the barrel on one tick; the pools hold `pool_size_for` with salvo × fan; a dry pool counts each refused rocket.

### 2.4 Energy torpedo and the torpedo tube (IDEAS §9 "energy torpedo"; t4)

**Torpedo = an `EnemyOrdnance` scene**, no new ordnance code: `assault/scenes/projectiles/enemy_ordnance/energy_torpedo.tscn`, `kind` PURSUIT_BOMB (it already has a
multi-hit `Health`, a proximity trigger, steer window / turn rate / lead / final speed, `ContactBlast`, `ProjectileLifetime`, hazard bending, shoot-down defuse). Authored
values (*judgement*, `2-research.md` §4): `Health.max_health` 3, `steer_window` 3.0, `turn_rate` 0.6, `steer_lead` 1.0, `final_speed` 320, `accel` 200, `arm_delay` 0.6,
`trigger_radius` 70, `warning_time` 0.5, `blast_radius` 72, `blast_damage` 25, `body_radius` 14, plus its own glowing sprite (blue-white plasma core, faction-red casing; art in
this task through `pixel-art-generation`, ≤ 90 % opaque). Launch speed 160 px/s. Its `ProjectileLifetime` `max_time` / `max_distance` cover the slow path (row).
Register it in `EnemyOrdnanceScenes` if that map is what lifetime / export rows read.

**Tube = `TurretMount.Variant.TORPEDO_TUBE` (appended, = 9)**: `TorpedoTubeMount extends TurretMount` in
`assault/scenes/enemies/defense_turret/mounts/torpedo_tube_mount.gd` + standalone `torpedo_tube_mount.tscn` (never inherited: `export_of()` reads only a scene's own state), wired
into the variant → scene map `TurretMountBuilder` uses. Exports: `charge_seconds` 1.0 (TELEGRAPH; host light CHARGING, muzzle glow white = "locked"), `launch_speed` 160,
`cooldown_seconds` 7.0, `fire_range` 1100, `traverse` set by the host's slot. One pool `TorpedoPool` of `energy_torpedo.tscn`, `persist` true, size
`ceil(torpedo max life / (period × pool_period_factor)) + 1`. `_fire_tick` launches one torpedo `launch(barrel dir, launch_speed, aim_point)` and emits `round_fired`; a dry pool
counts `torpedoes_refused`. `fires_past_cover()` true (it steers). UNPOWERED (part death) stops it like every mount.

**Rows:** `test_turret_mount_variants.gd` (telegraph = `charge_seconds`, one torpedo per cycle along the barrel, cooldown, UNPOWERED fires nothing, pool size formula);
`test_enemy_ordnance.gd` (torpedo: 2 player hits do not defuse, the 3rd does with no blast; steers only for 3.0 s then straight; blast radius / damage from the scene);
`test_enemy_bullet_lifetime.gd` (its `max_distance / slowest speed` fits `max_time`); transparency and project-load sweeps cover the new scene.

### 2.5 Engine wake hazard: `EngineWake` (IDEAS §9 "engine wake hazard", §24 "dangerous exhaust trails"; t5)

`assault/scenes/hazards/engine_wake/engine_wake.tscn` + `engine_wake.gd` (`class_name EngineWake extends HazardField`) + `HAZARD.md`. One wake **puff** is a short-lived stress
field (the `ReactorField` precedent): `kind` `&"engine_wake"`, `radius` 40, `core_radius` 0, `damage_radius` 40 (**= the drawn radius**), `stress_damage` 5, `stress_period` 0.5,
`duration` 3.0, `pull_force` 0, `movement_penalty` 0, `avoid_weight` 0.6. Script additions:
- `@export var damage_cutoff: float = 0.5`: no stress in the last `damage_cutoff` s (`_stress_enabled()` → `super() and _age < duration - damage_cutoff`); the drawing fades over
  exactly that window (F5: damage only while drawn bright).
- `set_owner_group(group: StringName)`: writes `damage_exempt_group` and the `HazardInfo.exempt_group` (avoidance) before `spawn_into()`.
- `set_scale_factors(radius_factor: float, life_factor: float)`: multiplies `radius` / `damage_radius` and `duration` before spawning (listing overburn).
- `_draw()`: a soft orange-white exhaust disc and a ring at `radius`, alpha 1 until `duration - damage_cutoff`, then linear to 0. Code-drawn (no texture).

**Shared change (bit-identical by default):** `global/hazards/hazard_field.gd` gains `@export var damage_exempt_group: StringName = &""` passed to
`Hazards.pulse_damage(tree, at, radius, damage, exempt_group := &"")` (`global/hazards/hazards.gd`), which skips any node in that group. Damage still goes by centre distance to
nodes in `enemies` / `player` through their root `HurtBox.received_damage` — the armoured Dreadnought refuses it anyway, and parts (group `enemy_parts`) are never reached.
Default (Ph12 owner choice 3): the wake hurts the player and other enemies, never the Dreadnought's own owner group (its interceptors).

**Rows** (`tests/integration/test_engine_wake.gd`, plus one row in `tests/unit/test_hazards.gd`): a player stub at 30 px takes 5 per 0.5 s; at 45 px nothing; nothing after
`duration - damage_cutoff`; freed at `duration`; an enemy in the exempt group is not hit, another enemy is; drawn ring radius == `damage_radius` (scaled too); a mover in the owner
group does not avoid it, another does; `pulse_damage` with no exempt group is bit-identical (existing rows green).

### 2.6 The Dreadnought shell (IDEAS §9, §14, §22, §40; t6)

#### 2.6.1 Files and scene

`assault/scenes/enemies/dreadnought/`: `dreadnought.tscn`, `dreadnought.gd` (`Dreadnought extends BaseEnemy`), `dreadnought_brain.gd` (stub API, §For every task), flat
`dreadnought_config.gd` / `.tres`, `ENEMY.md`. `WaveBuilder.dreadnought()` / `DREADNOUGHT` (`assault/scenes/systems/wave_builder.gd`, beside `space_fortress()`).
Test helper `tests/helpers/dreadnought_fixture.gd`: `spawn(harness, opts := {})` (seeded, `start_engaged` true by default, optional `quiet` that writes 1e6 cooldowns on the
private config so movement rows fire nothing), `kill_part(d, id)` (through the part's real damage path), `ladder(d, ids: Array)` (kills parts / drops core health in order).

Scene tree (root `CharacterBody2D`, `collision_layer` 0, `collision_mask` 0): `CollisionShape2D` (RectangleShape2D 208 × 448, shared), `HurtBox` (same shape, enemy hurtbox
layer, root mask as `BaseEnemy` sets it), `ContactHitBox` + `ContactProfile` mode ARMOR with `shove_speed` (fortress value), `Health`, `HitFlashAnimationPlayer`, `Sprite` (hull),
`Mover` (`EnemyMover`: `turn_lerp` 0, `acceleration` 0, `braking` 0, `max_turn_rate` 2.5, `hazard_avoidance` 0.3, `hazard_resistance` 0.85 — IDEAS §18.6 "a heavy dreadnought
partially resists"), `Brain`, `Modules` (`ModularHull`) with the eight parts, `PhaseDriver`, `EngineDriver`, overlays `ListSmoke` (two child sprites at the engines, hidden),
`EmergencyLights` (hidden), `CriticalOverlay` (hidden).

#### 2.6.2 Parts (local coordinates, nose +y, port +x; every hurtbox inside the hull rectangle x ±104, y ±224)

| id | role | position | hurtbox | HP (config field) | carries |
|---|---|---|---|---|---|
| `torpedo_tube` | WEAPON | (0, +196) | 40 × 48 | `torpedo_tube_health` 200 | 1 TORPEDO_TUBE mount (t8), bay (t11) |
| `missile_rack` | WEAPON | (0, +110) | 56 × 48 | `missile_rack_health` 220 | 1 ROCKET_BATTERY mount, fan (t8), bay (t11) |
| `broadside_port` | WEAPON | (+84, +20) | 40 × 176 | `broadside_health` 260 | 3 HEAVY_CANNON mounts (t8), bay (t11) |
| `broadside_starboard` | WEAPON | (−84, +20) | 40 × 176 | `broadside_health` 260 | same, mirrored |
| `shield_generator` | WEAK_POINT | (0, +30) | 48 × 48 | `shield_generator_health` 160 | the `ShieldSector` generator |
| `core` | CORE | (0, −70) | 72 × 72 | `core_health` 900 | death = the boss's death |
| `engine_port` | ENGINE | (+56, −192) | 64 × 64 | `engine_health` 240 | `Plume` + `WakePoint` (t9) |
| `engine_starboard` | ENGINE | (−56, −192) | 64 × 64 | `engine_health` 240 | same |

Every part: one `HurtBox` shape, `Sprite`, `Light` (`StateLight`), `starts_vulnerable` true, `damaged_ratio` 0.5. `_apply_config()` writes each part's HP (fortress pattern).
The hull's `HurtBox` covers the body within 1 px (`test_enemy_hurtbox_geometry.gd`).

#### 2.6.3 Armoured hull, core and death

Copy the `SpaceFortress` root pattern: `_on_received_damage` refuses and emits `armor_deflected(damage)`; `deflects_hit()` / `is_armored()` true; `is_laser_blocking()` false;
`accepts_ward()` false; `can_be_repaired()` false; tow refused in every phase; `homing_point(from)` = the nearest live part's homing point; `launch_velocity()` = the mover's own
velocity (a moving launcher); `rocket_clear_radius()` = half the hull diagonal + 8 (≈ 255 px). Core `destroyed` → `health.set_health(0)` → `_on_health_changed` death latch:
`death_started`, `brain.silence()`, `reinforcements.scuttle_all()`, `suspend_ai()`, `BossDeathSequence` (host contract `death_started`, `death_duration`,
`config.death_blast_count`), `_make_corpse_harmless()`, `_finish_death()` through a `Timer` node. No capital wreck (`wreck_chance` 0). EMP: `answers_emp()` true (also while dying),
`apply_emp(seconds × emp_factor 0.4)`, a no-op while dying (Ph11 owner choice 6 carried, Ph12 owner choice 7).

#### 2.6.4 Shields and the target matrix (no locks)

One `ShieldSector` (`global/boss/shield_sector.gd`): generator `shield_generator`, protected `[core, engine_port, engine_starboard]`, params from the config
(`shield_capacity` 120, `shield_regen_delay` 3.0, `shield_regen_seconds` 4.0, `shield_reboot_seconds` 6.0, `shield_pad` 10; the fortress's `_shield_params()` keys). The
generator's death exposes all three for good. "Core vulnerable only when intended" (§40) is met by the bubble, not a lock.

| Target | Gain | Cost (keeps the choice a trade, F6/F7) |
|---|---|---|
| a weapon | that attack goes silent for good (mount UNPOWERED) | two interceptors burst out of its wreck (t11) |
| an engine | one: lopsided, slow turn to the live side, half the wake; two: no movement, no wake, no ram | the stern means crossing the wake; two dead → `crippled` frenzy |
| the shield generator | bubbles drop on core and both engines | it sits amidships between both broadsides; nothing else changes |
| the core | the kill; ≤ 35 % → `critical` | bubbled while the generator lives; `critical` starts the ram |

#### 2.6.5 Phase handler, visuals and the snapshot

`_on_phase_entered(track, index, id)`: ignore if dying; `brain.on_boss_phase(track, id)`; visuals: `listing` → `_list_smoke_side` = `dead_engine_side()` (read once here: +1 port,
−1 starboard) and that side's `ListSmoke` sprite visible; `crippled` → `_emergency_lights` `&"strobe"` (the `EmergencyLights` node blinks from `_process`); `critical` →
`_core_light_mode` `&"blink"`, `CriticalOverlay.visible` true.

`phase_snapshot()` keys (Ph11 R1: phase-driven fields only): `movement` = `brain.movement_snapshot()`, `attacks` = `brain.attacks_snapshot()`, `arena` = `brain.arena_snapshot()`
(all `[]` until t7 / t8 / t9), `vulnerable` = `[]` (no phase changes vulnerability: no locks), `reinforcements` = `[reinforcements.activated_bay_ids(), 0]` (constant),
`visuals` = `[_list_smoke_side, _emergency_lights, _core_light_mode, _critical_overlay]`.

#### 2.6.6 Roster and invariant gates the Dreadnought joins (t6)

`test_enemy_contact_damage.gd` (ROSTER; `collision_damage` 25 at spawn), `test_contact_hitbox_geometry.gd` (ROSTER), `test_enemy_hurtbox_geometry.gd` (ROSTER),
`test_base_enemy.gd` (`_MIN_ROSTER_SIZE` + 1, `_EXCLUDED_FROM_GENERIC_DAMAGE_FLOW`, `_AUTHORED_CONTACT_MODES` ARMOR, every-phase tow refusers), `test_config_instance_isolation.gd`
(children row), `test_boss_phase_rules.gd` (found, two drivers), `test_entity_sprite_transparency.gd`, `test_signal_emit_arity.gd`, `test_enemy_mover_single_writer.gd`,
`test_collision_layer_names.gd`, `test_project_load_integrity.gd`, `test_resource_uid_integrity.gd`, `test_explosion_effect_placement.gd` if it lists bosses.

#### 2.6.7 Rows (t6; `tests/integration/test_dreadnought.gd`, both harnesses unless noted)

1. Scene: eight parts with the ids / roles / sizes / HP above, every hurtbox inside the hull, all vulnerable at spawn, config HP wins over scene `Health`.
2. Armour: a real player bullet through the hull hits a part behind it and the root reports `armor_deflected` and loses no HP (real physics, 8×).
3. Free order: each of the eight parts takes damage at spawn; the protected three take it through the bubble first; after the generator dies they take it directly.
4. Core death = boss death: `death_started`, escorts scuttled, the node freed after `death_duration`; a part killed during the sequence applies no phase consequence.
5. Two drivers: `twin_engines` / `hunting` at spawn; one engine → `listing`; the other → `crippled`; core at 35 % → `critical` (and at 36 % not); `critical_core_ratio` equals the scene ratio.
6. §25: for each pinned path — engines port→starboard then core; starboard → core → port; core → port → starboard — each phase entry's snapshot differs from the previous in
   every declared aspect built so far (`BUILT_KEYS`, extended by t7 / t8 / t9 / t10), and in ≥ 2 aspects on the crippled-then-critical path; boundary: a hit that leaves both
   engines alive changes no snapshot key. t6 builds `visuals` (and the constant `vulnerable` / `reinforcements`).
7. EMP 40 %, no-op while dying; homing point is a live part; tow refused; ward refused.

### 2.7 Movement: hunting on long arcs (IDEAS §9 Movement, §26, R2/R4/R8/R9; t7)

All in `dreadnought_brain.gd`; config group `Movement`. The brain keeps a unit `heading` and each tick computes a desired heading, turns `heading` toward it at the current
**per-side** rates, adds the yaw bias, then `mover.request_velocity(heading × speed + drift)` and `mover.face_toward(position + heading × FACE_REACH 10000)`. Velocity
always runs along the nose (a ship, not an orbit anchor: `Steering.orbit` would slide a 450 px hull sideways). `turn_asym(heading, desired, rate_port, rate_starboard, delta)`
is a static brain helper (signed angle, clamp by the rate of that side).

**Open Space** (`patrol_anchor`, `AnchorIdle` like the fortress / Carrier; `start_engaged` skips idle and leash):
- IDLE: `AnchorIdle` slow orbit at `idle_speed` 50; NOTICING → HUNT when the player is within `perceive_radius` 1100 of the hull.
- HUNT guidance: target T = the player's predicted position at `hunt_lead` 1.0 s (`TargetInfo`). If `|T − p|` > `loiter_radius` 700 + `close_band` 300: steer toward the
  tangent point of the loiter circle on the engaged side (it closes on a curve, never head-on). Otherwise: the circle's tangent in the orbit direction plus a radial correction
  `clamp((d − loiter_radius) × radial_gain 0.002, −0.6, 0.6)` rad. **Orbit direction = engaged side:** clockwise engages starboard, counter-clockwise engages port.
- Side choice (F2 hysteresis): prefer the side whose broadside part lives; if both or neither live: in `listing` the dead side (its fast turn), else keep the current side (seeded
  50/50 at spawn). Switch at most once per `side_switch_min` 6.0 s.
- Speed `cruise_speed` 120 px/s, `turn_rate` 0.35 rad/s (turn radius ≈ 343 px; a 420 px/s player out-circles it, the counterplay, F1).
- **Jets** (F1): the player inside ±`stern_arc_deg` 40° of the stern and within `loiter_radius` + 300 for `jets_trigger` 1.5 s and `jets_cooldown` 8.0 s ready → for
  `jets_seconds` 1.5 the turn rates × `jets_turn_factor` 2.5 (listing asymmetry kept). No jets while crippled. `jets_active()` is public (t8 holds broadsides then).
- RETURNING: the player farther than `lose_radius` 1800 from the hull for `lose_seconds` 4.0, or the hull farther than `hunt_leash_radius` 1400 from `patrol_anchor` → fly to the
  anchor at `return_speed` 90 (no wake, weapons cold), then IDLE.

**One engine (`listing`)**: dead side `s` from `on_boss_phase` (+1 port / −1 starboard, the root's `dead_engine_side()`): speed × `one_engine_speed` 0.65; the turn rate toward the
dead side × 1.0, toward the live side × `one_engine_live_turn` 0.35; every tick the heading also turns toward the dead side by `one_engine_yaw_bias` 0.08 rad/s; the velocity
gains `one_engine_drift` 18 px/s along the dead side's unit vector. Net effect: tight circles one way, wide the other, and a straight request curves.

**Both engines (`crippled`)**: phase HOLD: `request_velocity(ZERO)` every tick; the heading turns at `thruster_turn_rate` 0.12 rad/s (× `critical_thruster_factor` 1.5 in `critical`)
toward the bearing that puts the best live weapon on the player (engaged broadside abeam, else the bow).

**Critical** (≥ 1 engine): speed × `critical_speed_factor` 1.15 (the ram itself is t10).

**Assault** (`ConstraintMode` AUTO, the corridor filter): spawned above the view (`world_anchored_x`); ENTER heading straight down at `assault_enter_speed` 140 to world y
`assault_band_y` 360; HUNT = a racetrack: waypoints world x 640 ± `assault_sweep_half_width` 380 on that y, U-turns **through the top** at `assault_turn_rate` 0.55 rad/s (radius ≈
218, apex ≈ 76 px above the resting view top), so crossing right engages starboard downward and crossing left engages port. Listing / crippled / critical apply the same factors.
HOLD (crippled) stays where it stopped. No budget, no exit.

**Snapshot** `movement_snapshot()` = `[speed_factor, turn_factor_port, turn_factor_starboard, yaw_bias, translation_enabled, thruster_turn_rate, ram_enabled]` from fields set
in `on_boss_phase` only (`ram_enabled` stays false until t10 writes it).

**Rows** (`tests/integration/test_dreadnought_movement.gd`, both harnesses, hand-ticked brain + mover, `quiet` fixture). **Epic must-have: engine loss changes movement,
measured on positions, never the sprite:**
1. Two engines, a fixed full-port then full-starboard turn request for 6 s each: the two measured turn radii are equal within 2 %; speed = `cruise_speed`.
2. Port engine dead (the live side is starboard): the starboard-turn radius ÷ the port-turn radius ≈ 1 / 0.35 within 10 % (yaw bias included in the expected value); a
   straight request drifts the track toward port (net lateral displacement to port > 0 after 5 s); speed ≈ 0.65 × cruise. Mirror row for starboard dead.
3. Both dead: displacement over 5 s ≤ 1 px with no hazard; rotation still changes at `thruster_turn_rate` toward the player (and × 1.5 once `critical`).
4. Open Space hunt: from 1600 px it closes on a curve (the heading never points within 10° of the player while farther than 1000 px), then holds 700 ± 150 px for 20 s with the
   engaged broadside within 30° of abeam; the side switches when that broadside dies.
5. Jets: player parked in the stern arc → jets fire after 1.5 s, turn rate × 2.5 for 1.5 s, not again before 8 s; never while crippled.
6. Leash: player beyond `lose_radius` 4 s → RETURNING to the anchor; `start_engaged` never returns.
7. Assault: ENTER ends at y 360 ± 8; the racetrack stays inside the world rect and the apex never more than 120 px above the resting view top; crossing direction engages the downward side.
8. §25: `movement` joins `BUILT_KEYS` in `test_dreadnought.gd`.

### 2.8 Weapons, attack gate and the extreme-weapons phase (IDEAS §9, §24, §26; t8)

Mounts are authored as `MountSlots` under each WEAPON part and built by `ModularHull.build_mounts(self, brain.rng, owner_group, brain.attack_gate, 0)` in the root's `_ready()`
after `brain.bind()` (fortress order); a part's death UNPOWERS its mounts in the same call (R12 "module death disables attack" is the framework's).

| Part | Slots | Variant | Traverse / rest bearing | Tuning (slot / mount scene) |
|---|---|---|---|---|
| `broadside_port` | `Bow` (part-local y +60, toward the nose), `Mid` (0), `Stern` (−60) | HEAVY_CANNON (Heavy Shell 220 px/s) | 40° about abeam port (local +x, 0°) | `cooldown_seconds` 3.2, `fire_range` 900 |
| `broadside_starboard` | same, mirrored | HEAVY_CANNON | 40° about abeam starboard (180°) | same |
| `missile_rack` | one | ROCKET_BATTERY, `fan_count` 5, `fan_spread_deg` 40, `salvo_count` 1, `pursuit_chance` 0 | 360° | `cooldown_seconds` 6.0 |
| `torpedo_tube` | one | TORPEDO_TUBE | 30° about the bow (rest bearing 90°, local +y) | `cooldown_seconds` 7.0 |

Every slot authors `pool_period_factor` 0.45 = `crippled_cooldown_factor` 0.6 × `critical_cooldown_factor` 0.75 (a row pins it to the config product).

**Broadside sweep (§24 "a Dreadnought uses broadside cannons"):** narrow-traverse batteries fire roughly abeam while the hull's own arc turn walks the lanes across the player —
the arc and the broadside are the same geometry. A side's three mounts are **one volley**: the brain ticks each with `host_can_fire` true only once the side's volley clock ≥
`k × broadside_ripple_gap` 0.25 s (k = 0 bow, 1 mid, 2 stern; the clock starts when the side's first mount enters TELEGRAPH, resets when all three are in COOLDOWN), so shells
ripple bow → stern. Broadsides hold fire while `jets_active()` or while the brain's commanded turn rate exceeds `broadside_fire_turn_cap` 0.35 rad/s.
**Fairness:** a lane's tip speed at the mount's `fire_range` (`broadside_fire_turn_cap × fire_range` = 315 px/s) ≤ 0.8 × each player scene's max speed, read from instantiated nodes
(lever if it fails: lower `broadside_fire_turn_cap`).

**Attack gate** `attack_gate()`: committed attacks = WEAPON **parts** with a mount in TELEGRAPH or FIRE (a broadside side counts once); cap `max_concurrent_attacks` 2,
`critical_max_concurrent_attacks` 3 (also in `crippled`). During the ram's WIND_UP / CHARGE (t10) the gate opens nothing new.

**Extreme weapons** on `crippled` / `critical` entry: `_set_attacks()` multiplies each live mount's `cooldown_seconds` by the phase factor once (guarded per phase), raises the
cap; a mount built later is not involved (all are built in `_ready()`). Nothing fires outside the Assault view, nor while not engaged, nor under EMP (mounts `scan()`).

**Snapshot** `attacks_snapshot()` = `[cooldown_factor, max_concurrent_attacks, broadside_ripple_gap]`.

**Rows** (`tests/integration/test_dreadnought_weapons.gd`; brain-ticked, rounds returned to their pools at their own `max_time`). **Epic must-have: module death disables its attack:**
1. For each WEAPON part, both harnesses: destroy it → every mount of it UNPOWERED and no round / rocket / torpedo from it over 20 s while at least one other weapon still fires; the
   destroyed broadside's side gets no shell (a player abeam on that side is never hit by a broadside round).
2. Ripple: a volley's three shells leave bow → mid → stern `broadside_ripple_gap` apart.
3. Fan: one rack salvo = five rockets spread 40°.
4. Gate: never more than 2 committed parts (3 in `critical` / `crippled`) over a 60 s stress.
5. `crippled` / `critical` cut cooldowns once each (product 0.45 when both); the slots' `pool_period_factor` equals the product; no pool runs dry in a 30 s worst-case stress.
6. Broadsides hold fire while jets are active.
7. Fairness inequality (instantiated mounts and both player scenes).
8. **Measured Assault density** (Ph11 method, Assault harness only): states `hunting`, `listing`, `crippled`, `critical`, `critical`+`crippled` × the worst live-part set × five
   player positions, 11 s each at 1/60 s: mean ≤ 13.3 launches/s, peak ≤ 30 per half-open 2 s window; levers in order: (a) broadside `cooldown_seconds` up, (b) `fan_count` 5 → 4,
   (c) `crippled_cooldown_factor` 0.6 → 0.7 (and the slots' factor with it). Escort rounds are excluded (t11 records them).
9. §25: `attacks` joins `BUILT_KEYS`.

### 2.9 The engine wake on the Dreadnought (IDEAS §9, §24; t9)

Each engine part has a `WakePoint` (`Marker2D`, 40 px behind its nozzle). The brain (physics tick, engaged phases HUNT / LINE_UP / WIND_UP / CHARGE / RECOVER only — never IDLE,
NOTICING, RETURNING, ENTER, HOLD) accumulates the distance each **live** engine's `WakePoint` travelled and every `wake_spacing` 48 px spawns one `EngineWake` there:
`set_owner_group(owner_group)`, `set_scale_factors(radius_factor, life_factor)` (1.3 / 1.3 in `listing`, else 1 / 1), `spawn_into(Hazards.container(tree), point)` — skipped
(and counted in `wakes_skipped`) when there is no container or `wake_max_live` 40 of its own puffs live. A destroyed engine stops its own wake at once; `crippled` turns the wake off.
The Assault wake lives in world space while the camera pans.

**Snapshot** `arena_snapshot()` = `[wake_enabled, wake_radius_factor, wake_life_factor]`.

**Rows** (`tests/integration/test_dreadnought_wake.gd`, both harnesses, a hazard container added by the test): puffs appear every 48 px behind each live engine only while engaged;
none in IDLE / RETURNING / HOLD; one engine dead → only the live engine's puffs, radius × 1.3; crippled → none; no container → none and no error; the Dreadnought's own escorts are
not damaged by its wake, the player is; the hull never loses HP to its wake; `wake_max_live` respected; §25 `arena` joins `BUILT_KEYS` (`listing` and `crippled` declare ARENA).

### 2.10 The critical ram (IDEAS §9 "heavy ram when critically damaged", §25 "final ram"; t10)

The `RamCorvetteBrain` cycle on the boss, enabled only in `critical` with ≥ 1 engine (`ram_enabled`), never in `crippled`:
- **LINE_UP** (≤ `ram_line_up_cap` 3.0 s): turn the nose toward the player's predicted position (lead `Steering.clamped_lead_time`), at the current (lopsided if listing) turn rates.
- **WIND_UP** `ram_wind_up_seconds` 1.2 s: speed × 0.3, engines' lights CHARGING, a **lane** drawn (`RamLane` child drawing a rectangle the hull's beam 208 px wide from the bow along
  the charge line, length = charge distance + `ram_overshoot`); the aim tracks for the first `ram_track_fraction` 0.4, then **freezes** (`charge_dir`, `charge_point`).
- **CHARGE**: `mover.boost(charge_dir, ram_speed 560, min((dist + ram_overshoot 300) / 560, ram_max_time 2.0))` (a boost ignores avoidance: the Ph6 committed-run rule; the
  Assault corridor filter still applies); lights COMMIT; `contact_hit_box.damage = config.ram_damage` 35 during CHARGE only, restored to `collision_damage` 25 on exit (the Ram
  Corvette `exposed_collision_damage` precedent: the contact-damage gate reads the spawn value).
- **RECOVER** `ram_recover_seconds` 2.0: speed × 0.5, a wide turn back to HUNT — the punish window; next ram after `ram_cooldown` 8.0 s; the first `ram_first_delay` 2.0 s after `critical`.
- **Assault:** the charge direction is clamped to within `assault_ram_max_from_vertical` 50° of straight down (a diagonal corridor dive); RECOVER climbs back to the band.
- An engine lost mid-cycle keeps the cycle; both lost → cancel at once (CHARGE's boost ends, phase HOLD). EMP / death cancel it (`on_emp_started`, `silence`).
- **Fairness** (instantiated config and both player scenes): `ram_wind_up_seconds × (1 − ram_track_fraction)` ≥ (104 + player hurt radius) / player max speed + 0.25 s. Lever:
  raise `ram_wind_up_seconds`; never narrow the lane.
- `movement_snapshot()`'s `ram_enabled` is written on `critical` entry (true with ≥ 1 engine) and on `crippled` entry (false).

**Rows** (`tests/integration/test_dreadnought_ram.gd`, both harnesses; boost rows start with `await _fresh_idle_delta()`). **Epic must-have: the critical ram:**
1. Before `critical`: no ram over 30 s. In `critical`: LINE_UP → WIND_UP → CHARGE → RECOVER in order; the first WIND_UP ≥ `ram_first_delay` after entry.
2. The line freezes at `ram_track_fraction` (moving the player afterwards does not change `charge_dir`); the hull passes `charge_point` and stops ≥ 250 px beyond it (overshoot).
3. Contact damage is 35 only during CHARGE and 25 otherwise (a real hit in each state).
4. Boundary: `critical` with both engines dead → no ram ever (60 s); both engines lost mid-WIND_UP → cancelled, HOLD.
5. One engine: the LINE_UP turn toward the live side takes ≥ 2.5× as long as toward the dead side.
6. Assault: the charge direction is within 50° of down; the hull stays inside the world rect.
7. Fairness inequality; the lane is drawn exactly the beam wide along `charge_dir` during WIND_UP.
8. §25: the critical row's `movement` difference now includes `ram_enabled`.

### 2.11 Interceptors from a destroyed weapon (IDEAS §10; t11)

Each WEAPON part carries a `Bay` (`ReinforcementBay`, trigger `ON_OWN_DESTROYED` from t2) with a `Mouth` just outside the hull edge on that part's side (broadsides: abeam;
rack: dorsal-forward; tube: ahead of the bow): `bay_id` = the part id, `payload_scene` and `assault_payload_scene` = `gatling_interceptor.tscn` (Ph12 owner choice 1), `count` 2,
`assault_count` 2, `door_seconds` 0.8 (the breach telegraph: CHARGING light on the wreck, sparks), `open_hold_seconds` 0.6, `config_overrides` as needed for the Ph11 "escorts
fire within 3 s" rule (the gatling pair measured ≈ 1.8 s in Ph11 t8 with none). The root builds `BossReinforcements(host, hull, phase_driver, brain.rng, owner_group,
cap, escort_boost_speed 300, escort_boost_seconds 0.4)` with cap `escort_cap_open_space` 6 / `escort_cap_assault` 4; the brain ticks it with `active = is_engaged() and not EMP`
(and once with `false` from `on_emp_started()`); death scuttles. Escorts go into `<name>Escorts` (`EscortContainer`), announced on `EventBus.boss_escort_spawned`, never
`enemy_spawned_orphan`, scored by the Ph11 path; nothing writes their `counts_toward_wave_clear` / `counts_as_escape`.

**Rows** (`tests/integration/test_dreadnought_reinforcements.gd`, both harnesses): each weapon's death launches 2 interceptors from its own wreck's `Mouth` after 0.8 s; the light
is CHARGING through the breach; the cap holds (four weapons killed in 1 s → at most 6 / 4 alive, the rest skipped); a weapon killed during the death sequence launches nothing;
the core killed mid-breach launches nothing and scuttles the live ones; escorts fire within 3.0 s of launch (Assault, 16× tick-paced); the shield generator / engines / core have no
bay; a bay-launched escort pays score through `boss_escort_spawned`.

### 2.12 Art, detachment and visual states (IDEAS §21–23, R13/R14; t12)

`assault/assets/sprites/enemies/dreadnought/`, every texture at scale 1 and the size of its frozen hurtbox, strictly top-down, ≤ 90 % opaque, faction palette (dark navy hull, red /
maroon accents, cool blue edge light), gameplay lights left to `StateLight`.
- `dreadnought_hull.png` 208 × 448: a long ship outline (tapered bow, broad stern) with **empty sockets** for every part; `create_map_object` above 40 000 px paints a background —
  strip it (`./scripts/strip-sprite-bg.sh`) or hand-draw through `pixelart_workbench` (the Ph10 t9 / Ph11 t9 routes).
- Per part an intact and a **wreck stump** texture (the stump covers visibly less of the hurtbox, so the outline shrinks): `torpedo_tube` 40 × 48, `missile_rack` 56 × 48,
  `broadside` 40 × 176 (starboard `flip_h`), `shield_generator` 48 × 48, `core` 72 × 72, `engine` 64 × 64 (starboard `flip_h`); `engine_plume.png` (the `Plume` child of each engine,
  so it dies with it), `list_smoke.png`, `critical_overlay.png` 208 × 448 (mostly transparent), `torpedo` art is t4's.
- **Detach:** on a part's `destroyed` (not while dying) the root spawns one `DebrisFragment` chunk (`assault/scenes/hazards/wreck/` family, a new
  `dreadnought_chunk.tscn` like `ram_fragment.tscn`, textures = per-part chunk art) deferred into `Hazards.container(tree)` at the part's position, flung outward from the hull centre
  at 60–90 px/s with `deceleration`, `lifetime` 8 s, `source` = the Dreadnought (`source_clear_radius` = `rocket_clear_radius()`), so it never hits its own ship. No container → no chunk.
- Mount heads reuse the existing HEAVY_CANNON / ROCKET_BATTERY heads; the tube head is new (40 × 40).

**Rows** (`tests/integration/test_dreadnought_sprites.gd`, no physics): every file's size / corners / 15 % < opaque < 90 %; hull and parts wired at scale 1 with the art the size of
each hurtbox; each part's wreck swap on destroy and its stump's opaque area < its intact art's; plumes are children of the engines (gone with them); `ListSmoke` /
`CriticalOverlay` shown by their phases; one chunk per destroyed part, none while dying, none without a container, chunk never damages the Dreadnought.

### 2.13 Open Space hub placement (t13)

`open_space/scenes/levels/sector_hub.gd`: **draw 22** appended after the fortress (every earlier seed unchanged): `_spawn_dreadnought(_ring_anchor(dreadnought_ring_radius 4200,
dreadnought_anchor_bearing_deg 135.0), rng)` ≈ (−2970, 2970), `patrol_anchor` and `rng_seed` set before `add_child()`, not `start_engaged`, into `EnemyContainer`; its escorts land in
its own `<name>Escorts` container. `tests/integration/test_sector_hub_patrol.gd`: add it to `_patrol_groups()` with footprint `hunt_leash_radius` 1400 + `perceive_radius` 1100
(a hunter's reach is its leash), move every hard count by one (the Ph11 t13 precedent), and the sweep must stay green. **Pre-approved levers, in order:** bearing 135° ± 22.5°, ring
4200–4800, `hunt_leash_radius` 1400 → 1100. If none clears, stop and escalate.

### 2.14 Gate time (t1 and every task)

GUT ≈ 225.2 s after Ph11 (ceiling 240 s, escalation past a 237 s two-run mean). **t1 frees ≥ 12 s first**, by the `tests/README.md` → *Gate time* rules 1–3 only (tick-paced files
8× → 16× after checking wall ≫ CPU; a scenario replayed by several tests computed once; per-tick bookkeeping no assertion reads dropped) — never a shorter tick count, duration,
sample grid, a wider bound or a removed assertion. Allotments (two-run means): t2 0.5 s, t3 0.3, t4 0.8, t5 0.6, t6 2.5, t7 2.0, t8 3.0, t9 0.8, t10 1.5, t11 1.0, t12 0.3, t13 0.5
(total 13.8 s). Escalate past 1.5× an allotment or a 237 s mean.

### 2.15 Numbers and where they come from

| Value | Number | Source |
|---|---|---|
| Hull | 208 × 448 px | IDEAS §9 320–480; *judgement* beam (≈ the Carrier's ratio) |
| Cruise / turn | 120 px/s, 0.35 rad/s (radius ≈ 343) | F1 ratios to the 420 px/s player |
| Loiter radius / close band | 700 / 300 px | F2; broadside `fire_range` 900 |
| Jets | × 2.5 for 1.5 s, cooldown 8 s, stern arc ±40°, trigger 1.5 s | F1 *judgement* |
| One engine | speed 0.65, live-side turn 0.35, yaw bias 0.08 rad/s, drift 18 px/s | F3 *judgement*; Carrier `one_engine_*` precedent |
| Crippled | thrusters 0.12 rad/s (× 1.5 critical), cooldowns × 0.6, cap 3 | *judgement*; Ph11 critical × 0.6 / cap 3 |
| Critical | core ≤ 35 %, speed × 1.15, cooldowns × 0.75 | Ph11 40 % *judgement* |
| Ram | wind-up 1.2 s (track 40 %), 560 px/s, overshoot 300, max 2.0 s, recover 2.0 s, cooldown 8 s, damage 35 (touch 25) | F4 derived; Ram Corvette 0.65 s / 620 / 220 / 50; player HP 50 |
| Wake puff | r 40, life 3.0 s, every 48 px per live engine, 5 per 0.5 s, no damage in the last 0.5 s, ≤ 40 live | F5 *judgement*; `ReactorField` |
| Torpedo | 160 px/s, steers 3.0 s at 0.6 rad/s, then 320; 3 HP; blast 72 / 25; tube cooldown 7 s, telegraph 1.0 s | pursuit bomb scaled (*judgement*) |
| Broadside | 3 × Heavy Shell per side, 40° traverse, cooldown 3.2 s, ripple 0.25 s, fire turn cap 0.35 rad/s | Carrier 150° side batteries narrowed for §24 sweep |
| Missile fan | 5 rockets over 40°, cooldown 6 s | `BurstCannonMount.pellets` precedent |
| Part HP | tube 200, rack 220, broadsides 260, generator 160, core 900, engines 240 | *judgement* against the fortress (core 900 incl. bubble) |
| Shield | capacity 120, regen after 3 s over 4 s, reboot 6 s, pad 10 | Ph11 sector shields |
| Escorts | 2 Gatling Interceptors per weapon death, cap 6 / 4 | Ph11 fortress caps; F7 |
| EMP | × 0.4 | Ph11 owner choice 6 |
| Hub | draw 22, 4200 ring at 135°, leash 1400, perceive 1100, lose 1800 / 4 s | fortress mirror; `2-research.md` §6 Q9 |
| Density | ≤ 13.3 /s mean, ≤ 30 per 2 s, ≤ 2 committed (3 critical / crippled) | Ph11 convention |

### 2.16 Docs and phase close (t14)

Invoke `updating-project-docs`: `docs/architecture/modules/global.md` (*Boss reinforcements*: `ON_OWN_DESTROYED`; *Boss phase ladder*: a boss may run several tracks; hazards: `EngineWake`,
`damage_exempt_group`), `docs/architecture/modules/assault.md`, `docs/enemy-roster.md` (Dreadnought, `WaveBuilder.dreadnought()`), `assault/scenes/enemies/dreadnought/ENEMY.md`
(the §43 checklist answered: silhouette, preferred distance 700 px, movement signature, telegraphs, behind / boost-away behaviour, Assault adaptation), `docs/architecture/PROJECT.md`
conventions, `CLAUDE.md` (the key-conventions boss line and the gate list: the Dreadnought suites), `tests/README.md` gate time. Close the phase: `docs/epics-done/cmug256tc003lm52wbdoxucrr/`
(`PRD.md`, `SOURCES.md`, `REPORT.md`) and `## Phase 12 - as built (<date>)` in `DECISIONS.md` (what was built, deviations, owner choices as built, gaps).

## 3. Build sequence

| Step | Task | Depends on | Why this order |
|---|---|---|---|
| 1 | t1 gate room | — | the Dreadnought suites do not fit the 237 s line without it |
| 2 | t2 bay trigger, t3 missile fan, t4 torpedo + tube, t5 engine wake | — | shared machinery, each bit-identical by default, testable on fixtures; can run in any order |
| 3 | t6 shell (scene, parts, armour, shields, two drivers, snapshot, rosters) | t1 | everything else hangs off the root |
| 4 | t7 movement (incl. engine-loss rows) | t6 | weapons, wake and ram read the heading model |
| 5 | t8 weapons (incl. module-death rows, density) | t3, t4, t7 | mounts need the fan / tube and the brain's turn rate for the sweep |
| 6 | t9 wake on the boss | t5, t8 | brain file serialised after t8 |
| 7 | t10 critical ram | t9 | brain file serialised; needs movement and the gate |
| 8 | t11 interceptor bays | t2, t10 | scene and brain serialised; needs the weapons |
| 9 | t12 art + detachment | t6 | part sizes are frozen by t6; independent of behaviour |
| 10 | t13 hub draw 22 | t11 | the full behaviour (leash, escorts) is what the sweep covers |
| 11 | t14 docs and phase close | all | |

## 4. Test plan

| File | Task | What it proves |
|---|---|---|
| `tests/integration/test_boss_reinforcements.gd` (+9 rows) | t2 | §2.2 rows; every existing row unchanged |
| `tests/integration/test_turret_mount_variants.gd` (+ fan, + tube) | t3, t4 | §2.3 / §2.4 rows, fan 1 / 0 bit-identity |
| `tests/integration/test_enemy_ordnance.gd`, `test_enemy_bullet_lifetime.gd` | t4 | torpedo multi-hit defuse, steering window, lifetime fit |
| `tests/integration/test_engine_wake.gd`, `tests/unit/test_hazards.gd` | t5 | §2.5 rows, `pulse_damage` exempt group, default bit-identical |
| `tests/integration/test_dreadnought.gd`, `tests/helpers/dreadnought_fixture.gd`, roster gates | t6 | §2.6.7 rows, §25 paths, both drivers found |
| `tests/integration/test_dreadnought_movement.gd` | t7 | **engine loss changes movement** (both harnesses, measured on positions), hunting arcs, jets, leash, Assault racetrack |
| `tests/integration/test_dreadnought_weapons.gd` | t8 | **module death disables its attack** (both harnesses), ripple, fan, gate, extreme weapons, fairness, measured density |
| `tests/integration/test_dreadnought_wake.gd` | t9 | wake only behind live engines while engaged, never harms the boss or its escorts |
| `tests/integration/test_dreadnought_ram.gd` | t10 | **the critical ram** (both harnesses): order, frozen line, overshoot, damage window, no ram when crippled, Assault diagonal, fairness |
| `tests/integration/test_dreadnought_reinforcements.gd` | t11 | interceptors from the wreck, caps, none while dying, 3 s first fire |
| `tests/integration/test_dreadnought_sprites.gd` | t12 | art sizes, transparency, wreck stumps, chunks |
| `tests/integration/test_sector_hub_patrol.gd` | t13 | draw 22 clears every trigger, pickup and the spawn |

Boundary cases named in the sections: fan 1 / 0; a non-breach bay still dies with its part; 36 % core does not enter `critical`; a hit leaving both engines alive changes no
snapshot key; crippled + critical never rams; no hazard container → no wake / chunk; a part killed during the death sequence launches and applies nothing.

## 5. Risks

- **Assault crowding**: a 448 px hull crossing a 1280 × 720 view. Mitigation: the band y 360 racetrack, U-turns away from the player, measured density per phase, a ram lane
  with a fairness inequality. If the Assault feel is wrong it is a tuning lever, not a design change; nothing places it in a level this phase.
- **The free order collapses** to one best order (F6). Mitigation: the gain / cost matrix (§2.6.4); not play-tested — the report must say so.
- **Interceptor spikes** when two weapons die close together (F7): capped live escorts and the one-chance breach.
- **Hazard count** while the wake runs (≤ 40 puffs per Dreadnought; every mover queries `Hazards.around()` when any hazard exists): t9 measures it in its gate-time row; lever
  `wake_spacing` 48 → 64.
- **Shared-machinery regressions**: four opt-in additions; the fortress / carrier / turret / bomber / hazard suites must stay unchanged and green.
- **Gate time**: ≈ 13.8 s of allotments; t1 must free ≥ 12 s first.
- **Hub**: a hunter that wanders to the spawn or a mission trigger breaks the hub; the leash and the sweep's footprint guard it, with levers.

## 6. Out of scope

| Item | Owner | Reason |
|---|---|---|
| Placing the Dreadnought in a level (and an `ENEMIES_CLEARED` persistent-ordnance exception for it) | Ph15 (Ph12 owner choice 4) | Assault level migration is Ph15's; the Dreadnought's rack and tube pools persist, so a placement in an `ENEMIES_CLEARED` section would be a third allowlisted exception, decided then |
| Enemy beams / rings damaging parts; wrecked parts / capital wrecks blocking LOS | Ph18 / Ph19 | Ph10/11 deferrals |
| Carrier / Heavy Gunship onto the boss machinery | Ph18 | |
| Encounter compositions, escort leash in Open Space beyond the cap | Ph13 / Ph14 | |
| Difficulty tiers | Ph16 | |
| Boss / part HUD, per-part score, audio | Ph17 | IDEAS §6.11 "not one giant HP bar" |
| EMP dropping boss shields | Ph18 | Ph11 deferral |
| A capital wreck on the Dreadnought's death | Ph19 | `wreck_chance` 0 like the fortress |

## 7. Requirements coverage

| Requirement (from `1-context.md`) | Delivered by |
|---|---|
| R1 size 320–480 px | t6 (448 px hull), t12 art |
| R2 hunts the player (opposite of the fortress) | t7 |
| R3 central hull + detachable turret, missile, shield, engine modules | t6 parts, t12 detach chunks |
| R4 long arcs, two huge bodies manoeuvring | t7 heading model, loiter circle, jets |
| R5 broadside sweep, missile fan, energy torpedo, engine wake, critical ram | t8 (+ t3, t4), t9 (+ t5), t10 |
| R6 §24 broadside cannons, exhaust trails | t8 ripple sweep on the hull turn, t5 / t9 wake |
| R7 free order, no prompt | t6 (no locks, two tracks), §2.6.4 matrix |
| R8 one engine → visibly lopsided movement | t7 (measured on the path), t6 visuals |
| R9 both engines → stationary + extreme weapons | t7 HOLD, t8 crippled attacks |
| R10 interceptors from a destroyed weapon module | t2, t11 |
| R11 §25 every phase changes ≥ 2, incl. final ram | t6 drivers and rows, t7–t10 keys |
| R12 §26 destruction changes the battlefield | t8 (UNPOWERED), t7 (engines), t9 (wake), t6 (shields) |
| R13 art from modules, wreckage stays | t12 |
| R14 readability lights, edge light, no full recolour | t12, t6 / t8 `StateLight` |
| R15 §40 tests in both harnesses (engine loss, module death, ram, core vulnerable when intended, wreckage) | t7, t8, t10, t6, t12 |
| R16 §41 Phase 5 item 2: on the module architecture | t6 (`EnemyModule`, `ModularHull`, `global/boss/`) |
| R17 Assault adaptation in the corridor + Open Space placement | t7 / t8 / t10 Assault rows, t13 hub; level placement out of scope (Ph15) |
| R18 §43 checklist | t14 (`ENEMY.md`); audit Ph17 |
| R19 a heavy dreadnought partially resists a gravity well | t6 (`hazard_resistance` 0.85) |
| R20 torpedo family | t4 (an `EnemyOrdnance` scene) |
| Gate time (project constraint) | t1, §2.14 |
