# Enemy rework, phase 12: Dreadnought hunting boss

Revision 4 (2026-11-26), answering the round-3 review (`4-review.md`: P1–P8) and the owner's second CHANGES_REQUESTED; revision 3 answered round 2 (N1–N11), revision 2
round 1 (B1–B4, M1–M10). Every round point by point in §8. Epic `cmug256tc003lm52wbdoxucrr`, phase 12 of the enemy rework
(idea `docs/ideas/cmufkkgmx0001o02y6bnf52bq/`). Built on this directory's `1-context.md` (what exists, requirements R1–R20) and `2-research.md` (scope check S1–S12, findings
F1–F7, options). Code facts re-read on `agent/auto-dev` @ `572ae54` (round-3 facts @ `86496f7`); test times measured on 2026-11-25 (§2.15).

## Summary for the owner

- **For the player:** a new boss, the **Dreadnought**, a 450 px warship that *hunts* you: it closes in on a curve, then circles you on long, slow arcs with one side turned to you,
  so its cannons ripple down that side and sweep across you as it turns. Get behind it and it fires manoeuvring jets to swing round; its engines leave a burning wake.
- **Weapons:** three heavy cannons down each side (the broadside), a fan of five missiles, a slow bow torpedo you can shoot down (three Standard shots; it fires when you are
  ahead of it), the engine wake, and, once its core is badly damaged, a ram: it swings its nose onto you on its jets, draws its lane, charges, then sits open to punishment
  (if it cannot get its nose onto you in time, it gives up and tries again a little later).
- **You choose what to break first, nothing is locked:** a weapon (that attack stops for good, but two interceptors burst out of its wreck), an engine (one lost: it lists, drifts and
  can only circle tightly one way; both: it stops dead in an extreme-weapons frenzy but can never ram), the shield generator (core and engines lose their bubble), or the core (the kill).
- **Destruction shows:** wrecked parts stay as smaller stumps and throw off a tumbling chunk, so the silhouette shrinks; lights show armed, charging and shielded.
- **Where:** a hunting zone far south-west in the Open Space hub (it gives up if you leave), and an Assault version tested in the corridor (an oval loop in the top half of the
  screen, broadside down; if you fly low the camera follows you and the top of the loop, where it holds fire, goes off-screen — phase 15 fixes that when it places it in a level).
- **Built for later bosses:** launch bays that fire from their own wreck, a missile-fan rack, a torpedo-tube turret, a reusable engine-wake hazard. **Left out:** a level
  placement (phase 15), a boss health bar and sound (17), lasers hurting boss parts and wrecks as cover (18–19), difficulty tiers (16).
- **Main risks:** a 450 px ship crowds the Assault screen (fairness checks on every attack, bullets measured per phase against the fortress's ceilings); the free order must stay a
  real choice (each target has a gain and a cost; nothing is play-tested); the test suite has about 12 s of room before its warning line and this phase adds about 18.4 s, so one
  task wins at least 8 s back first (possibly by making game code faster without changing what it does); only the weapons work waits for it; the end margin is thin (≈ 1.4 s).
- **Choices (default in brackets):** 1. Who bursts out of a destroyed weapon? [two Gatling Interceptors] 2. Let launch bays fire from their own wreck, changing phase 11's
  "bays stop when their part dies" for bays that opt in? [yes] 3. Does the wake hurt other enemies (bait-able) but not the Dreadnought or its interceptors? [yes]
  4. Place it in a level now? [no, phase 15] 5. Put it in the hub as a roaming hunter in its own zone? [yes] 6. Ram damage of your 50 HP / hull touch? [35 / 25]
  7. EMP lasts 40 % on it, like the fortress? [yes] 8. May the test-time task speed up game code, proven to behave identically? [yes] 9. Standard shots to kill a torpedo? [3]
  10. Your last two change requests had no text; did they mean anything beyond the AI review's points? [taken to mean "fix the review's points"; please write it if not]

## For every task

Phase 12 of the enemy rework. Read `CLAUDE.md`. Earlier phases' rules in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` stand unless a line here changes them.
- **Names.** `class_name Dreadnought` (root, `BaseEnemy`), `DreadnoughtBrain` (`EnemyBrain`), flat `DreadnoughtConfig` (`ShipConfig`), folder `assault/scenes/enemies/dreadnought/`
  (`dreadnought.tscn`, `dreadnought.gd`, `dreadnought_brain.gd`, `dreadnought_config.gd/.tres`, `ENEMY.md`), `WaveBuilder.dreadnought()` / `DREADNOUGHT`. Never "station" for a
  boss. "Ph12 owner choice N" = the owner summary's choice N.
- **Local axes (Carrier convention):** nose = local **+y** (`EnemyMover` `sprite_forward_angle` PI/2); **port = local +x**, **starboard = local −x**. From a heading `h`: starboard =
  `Vector2(-h.y, h.x)`, port = `Vector2(h.y, -h.x)`. A **starboard turn** increases the heading angle (screen clockwise), a **port turn** decreases it. A clockwise orbit keeps the
  centre on the starboard side (engages starboard). Mount bearings: 0° = local +x (port abeam), 90° = local +y (bow), 180° = starboard abeam.
- **Part ids** (`const` on `Dreadnought`): `TORPEDO_TUBE` `&"torpedo_tube"`, `MISSILE_RACK` `&"missile_rack"`, `BROADSIDE_PORT` `&"broadside_port"`, `BROADSIDE_STARBOARD`
  `&"broadside_starboard"` (the four WEAPON parts), `SHIELD_GENERATOR` `&"shield_generator"` (WEAK_POINT), `CORE` `&"core"` (CORE), `ENGINE_PORT` `&"engine_port"`,
  `ENGINE_STARBOARD` `&"engine_starboard"` (ENGINE). Under `Modules` (`ModularHull`); **every part `starts_vulnerable` true** (no locks: the free order).
- **Hull rule: armoured** (the fortress / Carrier rule): the root refuses all damage (`armor_deflected`), `deflects_hit` / `is_armored` true, shots cross it to the parts; **the core's
  death is the boss's death**. Root layer 0 / mask 0. Body, root `HurtBox` and `ContactHitBox` share one `RectangleShape2D` 208 × 448.
- **Two phase tracks** (two ordinary `BossPhaseDriver` nodes, no driver change): `PhaseDriver` hull track `hunting` → `critical` (core ≤ `critical_core_ratio` 0.35); `EngineDriver`
  engine track `twin_engines` → `listing` (1 engine destroyed) → `crippled` (both). The root forwards each entry as `DreadnoughtBrain.on_boss_phase(track: StringName, phase_id:
  StringName)`, track `&"hull"` / `&"engines"`; nothing is applied once dying. `BossReinforcements` binds `PhaseDriver`.
- **Root API** (t6): `modular_hull()`, `part(id)`, `phase_driver()`, `engine_driver()`, `shield_sector()`, `reinforcements()`, `owner_group()` (`"dreadnought_%d" % instance id`),
  `is_assault()`, `is_dying()`, `engines_alive() -> int`, `dead_engine_side() -> int` (+1 port, −1 starboard, 0 none / both; written on `listing`), `phase_snapshot() -> Dictionary`
  (six keys `movement`, `attacks`, `vulnerable`, `arena`, `reinforcements`, `visuals`, **phase-driven fields only**); signals `armor_deflected(damage: int)`, `death_started`.
- **Brain API** (t6 stubs, filled by t7–t11): `bind(host, hull, reinforcements)`, `on_boss_phase(track, phase_id)`, `silence()`, `on_emp_started()`, `is_engaged()`,
  `attack_gate_for(part_id: StringName) -> bool`, `committed_parts() -> int`, `jets_active()`, `movement_snapshot()`, `attacks_snapshot()`, `arena_snapshot()` (`[]` until built),
  `heading() -> Vector2`, `phase()`; `enum Phase { IDLE, NOTICING, RETURNING, ENTER, HUNT, LINE_UP, WIND_UP, CHARGE, RECOVER, HOLD }` (append-only). Engaged = HUNT … HOLD.
- **Per-part attack gate:** `TurretMount` still calls a zero-argument `telegraph_gate` (Ph11 contract); after `ModularHull.build_mounts()` the root sets
  `mount.telegraph_gate = brain.attack_gate_for.bind(part_id)` on every mount of each WEAPON part, so the gate knows which part asks and a broadside side counts once. **Its own
  fan rockets and its own torpedoes are never in flight together** (the gate's separation rule, §2.8): its rockets can hit its torpedo, so they are kept apart in time.
- **Single writers:** the brain only requests (`request_velocity`, `face_toward`, `boost`, `halt`); the `EnemyMover` writes `velocity` / `rotation` / `move_and_slide()`. Paths bend
  **only** through the brain's own heading turn. Mover: `turn_lerp` 0, `acceleration` / `braking` 0, `max_turn_rate` above any rate the brain uses. Once dying, `suspend_ai()` runs
  and `BossDeathSequence` alone writes the rotation.
- **Config:** every number in `dreadnought_config.tres` (flat); mount tuning in **standalone** mount scenes (`TurretMountScenes`), slot overrides on `TurretMountSlot`, bays on
  `ReinforcementBay` exports, phases as `BossPhase` sub-resources. Never write to a loaded resource. Config wins over the scene's `Health`.
- **Shared-machinery additions, opt-in and bit-identical by default:** `ReinforcementBay.Trigger.ON_OWN_DESTROYED` (appended, t2); `RocketBatteryMount.fan_count` 1 /
  `fan_spread_deg` 0 and **`TurretMount.Variant.MISSILE_FAN` = 9** on its own `missile_fan_mount.tscn` (t3); **`TurretMount.Variant.TORPEDO_TUBE` = 10** (t4, after t3); every
  variant has its **own, distinct head PNG** (`test_ph8_sprites.gd` `HEADS`: `turret_head_missile_fan.png` drawn in t3, `turret_head_torpedo_tube.png` in t4);
  `HazardField.damage_exempt_group` &"" and `Hazards.pulse_damage(..., exempt_group := &"")` (t5). Every existing suite is the regression net and stays green unchanged.
- **Clocks** are accumulated `delta` (`x -= delta`, over at `x <= 1e-6`); no `Timer` / `create_timer` in brains, weapons or hazards (a `Timer` *node* only for the death free).
- **Spawning** (escorts, wake puffs, chunks) from the brain / root tick or idle code, never inside a physics callback (defer it); hazards go deferred through
  `spawn_into(Hazards.container(tree), ...)` and nothing spawns when there is no container.
- **Mode:** `EnemyWorld.arena(get_tree()) != null` = Assault. In Assault nothing the Dreadnought owns fires outside `EnemyWorld.view_rect()`; no engagement budget, no exit;
  `world_anchored_x` true (`.at(x, y)` lands at world x `640 + 2x`). Open Space: world space, no camera maths.
- **Fairness and density (Ph11 convention):** inequalities read from **instantiated** nodes; a player's speed is its `cruise_speed()` (fighter 360, Open Space ship 420); in Assault
  the hull rectangle stays inside `EnemyWorld.projectile_world_rect()` (x −164…1444, y −444…1164) from the end of ENTER on; measured Assault density (t12) in every phase state: Dreadnought-owned launches mean
  ≤ 13.3 /s, peak ≤ 30 per half-open 2 s window, ≤ 2 committed WEAPON parts (3 in `critical` or `crippled`); a count during which a pool reported empty fails.
- **Signals** declare exactly what they emit; per-frame / per-hit prints only behind `OS.is_stdout_verbose()`.
- **UIDs:** never hand-type or copy a `uid://`; leave references UID-less or mint with the `tests/README.md` snippet. Never run `update_project_uids`.
- **Tests:** GUT, tests first, both harnesses (`tests/helpers/enemy_ai_harness.gd`, `use_parameters(MODES)`) for every Dreadnought behaviour row; spawn through
  `tests/helpers/dreadnought_fixture.gd` (t6): `spawn(h, opts)`; `opts.quiet` silences **through the fields the brain reads** (`max_concurrent_attacks` /
  `critical_max_concurrent_attacks` 0, `escort_cap_open_space` / `escort_cap_assault` 0, `ram_first_delay` 1e6 unless the row asks for the ram). A hand-ticked movement row uses the
  fortress tick: `set_physics_process(false)`, then per tick `before := d.global_position; d._physics_process(dt); d.global_position = before + d.velocity * dt` (a hand-ticked
  `move_and_slide()` moves by the idle delta). A hand-ticked boost row starts with `await _fresh_idle_delta()` (Ph10). Real-physics rows at 8×, 16× only for tick-paced files.
  Run `scripts/check-test-leaks.sh` after anything that awaits. Gate: `bash /agent/verify.sh`.
- **Gate time:** record GUT before / after (two-run mean of `scripts/gate-time.sh`) in `tests/README.md` → *Gate time*; stay inside your allotment (§2.15 table, repeated in each
  task); escalate past a 237 s two-run mean or 1.5× your allotment. Gate output stays well under 1 MiB.
- **Art:** invoke `pixel-art-generation` before any PixelLab call; strict top-down; save with `./scripts/pixellab.sh`; look at every image; no texture ≥ 90 % opaque. Until t13,
  placeholders reuse existing Carrier / fortress PNGs.
- **Docs:** each task keeps `dreadnought/ENEMY.md` (and any HAZARD.md / module doc it touches) true; t15 runs `updating-project-docs`. A departure later phases depend on goes
  into `DECISIONS.md` under `### Phase 12, built in tN`.

## 1. Problem

The roster has one boss, the Space Fortress: it holds a zone and makes the player circle *it*. The idea (IDEAS §9) asks for its opposite: a large ship that **hunts** the
player, moving on long arcs "like two enormous bodies trying to change position relative to each other", built from detachable modules, attacking with a broadside sweep, a
missile fan, an energy torpedo, an engine-wake hazard and a critical ram; the player picks what to disable first (weapons, engines, shields, core) with no prompt; losing one engine
makes it visibly lopsided, losing both makes it stationary with an extreme weapons phase (IDEAS §9, §24, §25, §26); destroying a weapon launches interceptors from that module
(§10); its art changes silhouette as parts become wreckage (§21–23); tests in both modes (§40).

### 1.1 Scope check (from `2-research.md` §1, re-validated @ `572ae54`)

| # | Finding | Effect on this plan |
|---|---|---|
| S1 | Ph10 `EnemyModule` / `ModularHull` / `TurretMountBuilder` and Ph11 `global/boss/` exist and are boss-agnostic | reused unchanged except the opt-in additions in §2.2–§2.5 |
| S2 | `BossPhaseDriver` is one ordered ladder and the fortress locks parts until earlier phases | free order = **two tracks** (§2.1) and **no locks**; the driver is unchanged |
| S3 | a bay whose part is destroyed is killed in the same call (`boss_reinforcements.gd` `_on_module_destroyed` → `_kill`) | **changes the Ph11 convention** for opt-in bays: `ON_OWN_DESTROYED` (§2.2, Ph12 owner choice 2) |
| S4 | no torpedo; `RocketBatteryMount` has no spread and its one scene (`rocket_battery_mount.tscn`) authors salvo 2 / pursuit 0.333 / cooldown 5.5; `TurretMountSlot` cannot override salvo, fan or cooldown and pools are sized at build time | a **new standalone variant scene** for the fan (§2.3); the torpedo is an `EnemyOrdnance` scene (§2.4); a wake hazard (§2.5) |
| S5 | the Carrier's engine loss sags the **facing**, not the path | the Dreadnought changes the **path** (asymmetric turn rates, yaw bias, drift), measured on positions (§2.7) |
| S6 | destroyed parts stay as wreckage (Ph10/11); capital wrecks / LOS wreckage / boss hazards are Ph19 | wreck **stumps** smaller than the intact art + a purely visual tumbling chunk (§2.13) |
| S7 | the scope names no level placement; Ph15 owns Assault level migration | Assault mode built and tested in the harness, `WaveBuilder.dreadnought()`, **no level placement** (Ph12 owner choice 4) |
| S8 | hub draws 1–21 appended; `test_sector_hub_patrol.gd` sweeps footprints | draw 22 with a hunting leash (§2.14) |
| S9–S10 | fortress suites run both harnesses; `test_boss_phase_rules.gd` sweeps every driver in a boss | same pattern; the sweep must find the Dreadnought and both its drivers |
| S11 | GUT ≈ 225.2 s of 240 s (escalation 237 s); the slowest files are CPU-bound (measured, §2.15) | gate-room task t1 frees ≥ 8 s (target 10), may use a bit-identical code speed-up; only t8 waits on it (§2.15) |
| S12 | deferred items unchanged (beams vs parts, capital wreck, Ph18 Carrier/Gunship migration, Ph13/14 encounters, Ph16 tiers, Ph17 HUD/audio) | out of scope (§6) |

### 1.2 Research used (from `2-research.md` §2; numbers marked *judgement* are starting values, nothing was play-tested)

- F1 (Starsector Conquest / Onslaught): a broadside capital is slow-turning and needs a short **burst-turn** (Maneuvering Jets) and rear coverage → jets (§2.7) + the wake (§2.9).
- F2 (Starsector AI notes, naval devlog): broadside AI thrashes at the side switch → remember the engaged side, switch with hysteresis (§2.7).
- F3 (Starsector damageable modules): engine loss shows as movement in the world (speed, turn, drift toward the dead side) → §2.7 listing.
- F4 (Dark Souls 3 frame analysis, Death's Gambit): telegraph proportional to the opening → ram frozen-line ≥ clearance / player speed + 0.25 s, long recovery (§2.10).
- F5 (Battlesnake, Gungeon Wallmonger): trails decay, damage only while drawn → wake 3 s, no damage in its fade (§2.5).
- F6 / F7 (Everspace 2, Squadrons, Horizon): a free order needs a cost on every choice; reinforcements on part loss punish progress unless capped → §2.6.4 matrix, §2.11 caps.

## 2. Design

### 2.1 Two phase tracks for a free destruction order (IDEAS §9, §25; t6)

The player may break weapons, engines, shields or the core in any order (R7). One ordered ladder cannot express that (a `critical` behind the engine phases would be unreachable
core-first). Rejected: one linear ladder (violates R7), an unordered driver mode (changes `BossPhaseDriver`'s core invariant for no gain), engines outside the ladder (the
one-/two-engine shifts would escape the §25 gate). **Chosen: two ordinary `BossPhaseDriver` nodes on one host**; weapons and the shield generator are not phase gates.

| Node | Track | Phases (`BossPhase` sub-resources, in order) | Declared `changes` |
|---|---|---|---|
| `PhaseDriver` | `&"hull"` | `hunting` START; `critical` HEALTH_AT_OR_BELOW `health_module` `core`, `health_ratio` 0.35 | `critical`: MOVEMENT, ATTACKS, VISUALS |
| `EngineDriver` | `&"engines"` | `twin_engines` START; `listing` PARTS_DESTROYED `module_ids` [`engine_port`, `engine_starboard`] `count` 1; `crippled` same ids `count` 2 | `listing`: MOVEMENT, ARENA, VISUALS; `crippled`: MOVEMENT, ATTACKS, ARENA, VISUALS |

- `DreadnoughtConfig.critical_core_ratio` 0.35 must equal the scene's `critical` `health_ratio` (a row pins it).
- The root binds both drivers in `_ready()` (after the hull and shields), connects each `phase_entered` with its track name bound, and calls `brain.on_boss_phase(track, id)`
  then its own visual handler; **nothing is applied once dying** (a part killed during the death sequence may still step a ladder).
- `BossReinforcements` takes one driver: pass `PhaseDriver` (the Dreadnought's bays use `ON_OWN_DESTROYED`, no phase gate).
- `tests/integration/test_boss_phase_rules.gd` already collects every driver in an instantiated boss: add a row that `dreadnought.tscn` is found with **two** drivers, both
  `validate(hull)` empty.

**What each phase does (consequences in the brain / root; values in the config):**

| Phase | movement (t7, t10) | attacks (t8) | arena (t9) | visuals (t6) |
|---|---|---|---|---|
| `listing` | speed × `one_engine_speed` 0.65; turn toward the dead side × 1.0, toward the live side × `one_engine_live_turn` 0.5; yaw bias `one_engine_yaw_bias` 0.05 rad/s and drift `one_engine_drift` 18 px/s toward the dead side; the Open Space orbit is forced to the dead side | — | the live engine overburns: wake radius × `listing_wake_radius_factor` 1.3, life × `listing_wake_life_factor` 1.3 | `ListSmoke` shown on the dead side |
| `crippled` | translation 0; rotation by thrusters only at `thruster_turn_rate` 0.12 rad/s; no jets, no ram | every live mount's `cooldown_seconds` × `crippled_cooldown_factor` 0.6 (once, guarded); attack cap 3 | wake off | `EmergencyLights` mode `&"strobe"` |
| `critical` | speed × `critical_speed_factor` 1.15 with ≥ 1 engine; the **ram cycle** enabled with ≥ 1 engine (t10); with both engines dead `thruster_turn_rate` × `critical_thruster_factor` 1.5 instead | cooldowns × `critical_cooldown_factor` 0.75 (once, guarded; compounds with crippled to 0.45); attack cap 3 | — | core light `&"blink"`, `CriticalOverlay` visible |

On the path where `critical` is entered with both engines dead the ram cannot happen; MOVEMENT still changes (thruster rate), and the Ph11 rule applies: that path gets its own
§25 row asserting ≥ 2 changes.

### 2.2 Bays that launch from their own wreck: `ReinforcementBay.Trigger.ON_OWN_DESTROYED` (IDEAS §10; t2)

**A deliberate change to the Ph11 convention "reinforcements come out of a bay on a live part and stop when that part is destroyed"**, for bays that opt in (Ph12 owner choice 2).
Every other trigger stays bit-identical. Files: `global/boss/reinforcement_bay.gd`, `global/boss/boss_reinforcements.gd`; tests `tests/integration/test_boss_reinforcements.gd`
(new rows appended, every existing row unchanged), `tests/helpers/fixture_boss_host.tscn` may gain a bay.

- `enum Trigger { PERIODIC, ON_SECTOR_LOSS, ON_PHASE, ON_OWN_DESTROYED }` (appended).
- `BossReinforcements._on_module_destroyed(part)`: for a live bay whose own part is `part`: if `trigger == ON_OWN_DESTROYED` **and** the bay is activated (`active_from_phase` empty
  or reached), queue one launch of `count_for(assault)` and mark the bay **breaching** (not dead); otherwise `_kill()` as today. A loss before activation is dropped (bay killed).
- A breaching bay runs the normal door cycle on the wreck: CLOSED → OPENING (`door_seconds`; the part's `Light` goes CHARGING, restored to its pre-open state = OFF on close) →
  LAUNCH at the bay's `Mouth` (still valid: wreckage stays) → OPEN for `open_hold_seconds` → CLOSED → `_kill()` (dead for good). If `_open()` refuses (no room under the live cap,
  or the Assault limit reached) the breach is spent: skipped is counted and the bay dies — **one chance, no retry** (F7: two quick kills cannot stack past the cap).
- `tick(delta, false)` holds a breaching bay like any other (a launch caught mid-OPENING goes back to the front of its queue). `surge()` on a breaching bay returns 0.
- New query `is_breaching(bay_id) -> bool`. `is_dead()` is false while breaching, true after. `launched` / `door_changed` signals unchanged.
- The host's death: the host stops ticking its `BossReinforcements` and scuttles (Ph11), so a queued breach never launches — no new code, a row pins it.

**Rows** (`test_boss_reinforcements.gd`, fixture host): (1) a breach launches `count` escorts at the wreck's `Mouth` after `door_seconds`, announced on
`EventBus.boss_escort_spawned`, then `is_dead()`; (2) the light is CHARGING during OPENING and OFF after; (3) no room under the cap → nothing launched, `skipped` 1, bay dead;
(4) Assault limit reached → nothing, dead; (5) EMP hold (`tick(dt, false)`) mid-OPENING → launches after `active` returns; (6) host stops ticking (death) mid-breach → nothing ever
launches; (7) a non-breach trigger's part destroyed → killed in the same call as before (boundary); (8) `surge()` on a breaching bay returns 0; (9) a bay with `active_from_phase`
not yet reached → dropped and dead.

Gate-time allotment: 0.5 s.

### 2.3 Missile fan: `RocketBatteryMount.fan_count` and the `MISSILE_FAN` variant (IDEAS §9 "missile fan"; t3)

**Why a variant, not a slot override:** `TurretMountSlot` can override only `variant`, `rest_bearing_deg`, `turn_rate_override`, `traverse_deg_override` and `pool_period_factor`;
`TurretMountScenes.scene_for()` maps each variant to exactly one scene; and `TurretMountBuilder.build()` sizes every pool from `mount.pool_specs()` at build time. Writing `fan_count`
or `salvo_count` on an instanced mount afterwards would leave its pools sized for a one-wide fan and refuse rockets (the Carrier's write-after-build precedent only works for
changes that lengthen the period). So the fan gets its own **standalone** scene, exactly as `HEAVY_CANNON` has its own scene on `burst_cannon_mount.gd` (Ph11 rule: standalone,
never inherited, because `export_of()` reads only a scene's own state).

- `assault/scenes/enemies/defense_turret/mounts/rocket_battery_mount.gd` gains `@export var fan_count: int = 1` and `@export var fan_spread_deg: float = 0.0`. Each salvo step
  launches `fan_count` rockets on the same tick, directions spread evenly over `[-fan_spread_deg / 2, +fan_spread_deg / 2]` about the barrel. `fan_count` 1 → exactly the barrel,
  **bit-identical** (same rng draws, same direction). Each rocket draws its own kind (`pick_kind()`), emits `round_fired` and, if refused, counts in `rockets_refused`.
  `pool_specs()`'s stand-in salvo becomes `salvo_count × fan_count`. The aim-cone check stays once per salvo step.
- `TurretMount.Variant` gains **`MISSILE_FAN` = 9** (appended to `enum Variant { BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE, BEAM_CANNON, HEAVY_CANNON,
  SPREAD_CANNON, RAPID_PULSE }`). `TurretMountScenes.MISSILE_FAN` = new standalone `missile_fan_mount.tscn` on `rocket_battery_mount.gd`, with **its own head**
  `turret_head_missile_fan.png` (below), authoring: `fan_count` 5, `fan_spread_deg` 40, `salvo_count` 1, `pursuit_chance` 0 (all DUMB: a readable fan of straight lines),
  `charge_seconds` 0.5, `cooldown_seconds` 6.0, `fire_range` 900, `turn_rate` 2.0, `lead_blend` 0.6, `fire_cone_deg` 8, `scan_arc_deg` 90, `scan_speed` 0.4. The shipped
  `rocket_battery_mount.tscn` is untouched.
- **Its own head art (this task draws it; round-2 N1).** `tests/integration/test_ph8_sprites.gd` forbids a shared head: `test_no_two_heads_share_a_texture` asserts every
  `HEADS` PNG is used once **and** `HEADS.size() == TurretMount.Variant.size()`, and `test_no_two_heads_share_a_silhouette` asserts every pair's alpha masks differ by at least
  `MIN_MASK_DIFF` 0.08. So t3 invokes `pixel-art-generation`, generates `assault/assets/sprites/enemies/turret_head_missile_fan.png` (strict top-down, nose-down art like every
  head, 48 × 48 like the rocket battery head: a **wide five-tube rack**, its tube mouths in a shallow arc so the silhouette reads as "fan" and differs from the rocket battery's
  two-tube box), saves it with `./scripts/pixellab.sh`, looks at it, and wires it as the scene's `Head` exactly as the other heads are (`rotation` −PI/2, `show_behind_parent`,
  `centered` false, an `offset` whose pixel is opaque — alpha > 0.99 — and the art's far end within 6 px of the `Muzzle` marker's x). Card-free (≤ 90 % opaque). Add
  `TurretMount.Variant.MISSILE_FAN: "turret_head_missile_fan.png"` to `HEADS`; all three head tests then pass unchanged. Any "every built variant" sweep that needs it gains it.

**Rows** (`tests/integration/test_turret_mount_variants.gd`, hand-ticked): (1) boundary: the shipped `ROCKET_BATTERY` scene launches one rocket per salvo step along the barrel with
the same rng draws as before (fan 1 / 0); (2) `MISSILE_FAN` launches five rockets at −20, −10, 0, +10, +20° from the barrel on one tick; (3) its pools are built at
`EnemyRocketScenes.pool_size_for(kind, {salvo_count: 1 × 5, warhead_salvo_count: 0, salvo_period_min: period × pool_period_factor})` for a `pool_period_factor` of 1.0 and 0.45; (4) a
dry pool counts each refused rocket; (5) `export_of(MISSILE_FAN, &"fan_count", 1)` reads 5 without instantiating. `test_ph8_sprites.gd`: the three head tests above, now
parameterised over ten variants, pass with the new head (a distinct texture and silhouette). Gate-time allotment: 0.4 s.

### 2.4 Energy torpedo and the torpedo tube (IDEAS §9 "energy torpedo"; t4, after t3)

**Torpedo = an `EnemyOrdnance` scene**, no new ordnance code: `assault/scenes/projectiles/enemy_ordnance/energy_torpedo.tscn`, `kind` PURSUIT_BOMB (a multi-hit `Health`, proximity
trigger, steer window / turn rate / lead / final speed, `ContactBlast`, `ProjectileLifetime`, hazard bending, shoot-down defuse). It is **not** added to
`EnemyOrdnanceScenes.scene_for()` (keyed by `Kind`; `PURSUIT_BOMB` already maps to `pursuit_bomb.tscn`): a named const `EnemyOrdnanceScenes.ENERGY_TORPEDO` preloads it, and
`TorpedoTubeMount` and the rows read that const.

**Health is in damage units.** `EnemyOrdnance._on_hurt(damage)` subtracts the hit's damage, so the torpedo's `Health.max_health` = `current_health` = **120** (Ph12 owner choice 9):
hits to defuse = `ceil(120 / damage)` from the shipped weapon modes (`assault/scenes/player/weapons/modes/*.tres` `damage`): Standard (`default.tres`, 50) **3**, Sniper Shot
(40) 3, Spread (25 per pellet) 5, Gatling (14) 9. Other authored values (*judgement*, `2-research.md` §4): `steer_window` 3.0, `turn_rate` 0.6, `steer_lead` 1.0, `final_speed`
320, `accel` 200, `arm_delay` 0.6, `trigger_radius` 70, `warning_time` 0.5, `blast_radius` 72, `blast_damage` 25, `body_radius` 14; `ProjectileLifetime` `max_time` 10.0,
`max_distance` 2400 (slow path: 3 s at 160 px/s, then up to 320); launch speed 160 px/s. Its own glowing sprite (blue-white plasma core, faction-red casing).

**Tube = `TurretMount.Variant.TORPEDO_TUBE` = 10** (appended after t3's `MISSILE_FAN` = 9): `TorpedoTubeMount extends TurretMount` in
`assault/scenes/enemies/defense_turret/mounts/torpedo_tube_mount.gd` + standalone `torpedo_tube_mount.tscn`, `TurretMountScenes.TORPEDO_TUBE` and its `scene_for()` arm. Exports:
`charge_seconds` 1.0 (TELEGRAPH; host light CHARGING, muzzle glow white = "locked"), `launch_speed` 160, `cooldown_seconds` 7.0, `fire_range` 1100; traverse set by the host's
slot. One pool `TorpedoPool` of `EnemyOrdnanceScenes.ENERGY_TORPEDO`, `persist` true, size `ceil(max_time / (period × pool_period_factor)) + 1` (period = `charge_seconds` +
`cooldown_seconds`; 4 at a factor of 0.45). `_fire_tick` launches one torpedo `launch(barrel dir, launch_speed, aim point)` and emits `round_fired`; a dry pool counts
`torpedoes_refused`. `fires_past_cover()` true (it steers). UNPOWERED (part death) stops it like every mount. **This task also draws the tube head** `turret_head_torpedo_tube.png`
(40 × 40) and the torpedo sprite through `pixel-art-generation` (≤ 90 % opaque) and adds `TORPEDO_TUBE` to `test_ph8_sprites.gd` `HEADS`. The head rules that file enforces
(the same ones t3's missile-fan head meets, §2.3; round-3 P4): strict top-down, nose-down art saved with `./scripts/pixellab.sh` and looked at; wired as the scene's `Head` with
`rotation` −PI/2, `show_behind_parent`, `centered` false, an `offset` whose pixel is opaque (alpha > 0.99) and the art's far end within 6 px of the `Muzzle` marker's x; its
texture used by no other head (`test_no_two_heads_share_a_texture`, `HEADS.size() == TurretMount.Variant.size()`) and its silhouette different from every other head's by at
least `MIN_MASK_DIFF` 0.08 (`test_no_two_heads_share_a_silhouette`): a single long launch tube with a glowing muzzle ring, unlike the fan's wide five-tube rack.

**Rows:** `test_turret_mount_variants.gd`: telegraph = `charge_seconds`; one torpedo per cycle along the barrel; cooldown; UNPOWERED fires nothing; the pool size formula.
`test_enemy_ordnance.gd`: (a) defuse on **real player bullets** (real physics at that file's 16×): a parked torpedo takes two real `bullet.tscn` shots fired with `default.tres`
damage and is not defused, the third defuses it with no blast; (b) hand-emitted hits whose damage is **read from each mode `.tres`** defuse after exactly `ceil(max_health / damage)`
hits for Standard, Sniper Shot, Spread and Gatling (boundary: one hit fewer leaves it live); (c) it steers only for `steer_window` then flies straight; (d) blast radius / damage
from the scene. `test_enemy_bullet_lifetime.gd`: a row that instantiates `EnemyOrdnanceScenes.ENERGY_TORPEDO` directly (the sweep's `_ordnance_lifetime(kind)` cannot key a second
PURSUIT_BOMB scene) and checks it through the file's existing **two-speed** helper, as the pursuit bomb's row does: `_two_speed_kind_clears(steer_window, launch_speed,
final_speed, max_distance, max_time)` with `steer_window` / `final_speed` and the `ProjectileLifetime` caps read from the torpedo scene and `launch_speed` from the instantiated
`torpedo_tube_mount.tscn` — 3.0 + (2400 − 160 × 3.0) / 320 = 9.0 s ≤ 10 (the 200 px/s² ramp adds ≈ 0.2 s: ≈ 9.2 s, still inside; the message prints both). The single-speed
formula (2400 / 160 = 15 s) is the wrong model for a two-speed kind and is not used (round-2 N2). The transparency and project-load sweeps cover the new scenes. Gate-time allotment: 0.8 s.

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
nodes in `enemies` / `player` through their root `HurtBox.received_damage` — an armoured boss refuses it, and parts (group `enemy_parts`) are never reached. Default (Ph12 owner
choice 3): the wake hurts the player and other enemies, never its owner group.

**Rows** (`tests/integration/test_engine_wake.gd`, plus one row in `tests/unit/test_hazards.gd`): a player stub at 30 px takes 5 per 0.5 s; at 45 px nothing; nothing after
`duration - damage_cutoff`; freed at `duration`; an enemy in the exempt group is not hit, another enemy is; drawn ring radius == `damage_radius` (scaled too); a mover in the owner
group does not avoid it, another does; `pulse_damage` with no exempt group is bit-identical (existing rows green). Gate-time allotment: 0.6 s.

### 2.6 The Dreadnought shell (IDEAS §9, §14, §22, §40; t6)

#### 2.6.1 Files and scene

`assault/scenes/enemies/dreadnought/`: `dreadnought.tscn`, `dreadnought.gd` (`Dreadnought extends BaseEnemy`), `dreadnought_brain.gd` (stub API, see *For every task*), flat
`dreadnought_config.gd` / `.tres`, `ENEMY.md`. `WaveBuilder.dreadnought()` / `DREADNOUGHT` (`assault/scenes/systems/wave_builder.gd`, beside `space_fortress()`).

Test helper `tests/helpers/dreadnought_fixture.gd`:
- `spawn(harness, opts := {})`: seeded, `start_engaged` true by default, positioned, added to the harness root. `opts.quiet` (true by default for movement rows) silences the boss
  **through fields the brain actually reads**, on the private config copy before `add_child()`: `max_concurrent_attacks` 0 and `critical_max_concurrent_attacks` 0 (the per-part
  gate refuses every telegraph), `escort_cap_open_space` 0 and `escort_cap_assault` 0 (no breach launches), `ram_first_delay` 1e6 (unless `opts.ram` is true). Mount cooldowns
  live in the mount scenes, so writing config cooldowns would not silence anything. With no hazard container in the harness no wake puff spawns. t6 declares these five
  config fields with their shipped values (`max_concurrent_attacks` 2, `critical_max_concurrent_attacks` 3, `escort_cap_open_space` 6, `escort_cap_assault` 4, `ram_first_delay`
  2.0) so the fixture writes real properties from the start (the fixture asserts each `set` target exists); t8 / t10 / t11 consume them.
- `hand_tick(d, dt)`: the fortress pattern — the fixture calls `set_physics_process(false)` once; each tick `var before := d.global_position; d._physics_process(dt);
  d.global_position = before + d.velocity * dt` (a hand-ticked `move_and_slide()` moves by the idle delta, so every "measured on positions" row depends on this).
- `kill_part(d, id)` (through the part's real damage path, after its shield bubble if any), `ladder(d, ids: Array)` (kills parts / drops core health in order).
- `opts.bare` (added by t8 only if its gate-time delta needs it; pre-approved lever, round-3 P7): frees every `MountSlots` node before `add_child()` so no mount or pool is
  built; used only by rows that assert nothing about weapons (the t7 movement rows). Weapon, density, ram and reinforcement rows never use it.

Scene tree (root `CharacterBody2D`, `collision_layer` 0, `collision_mask` 0): `CollisionShape2D` (RectangleShape2D 208 × 448, shared), `HurtBox` (same shape, enemy hurtbox
layer, root mask as `BaseEnemy` sets it), `ContactHitBox` + `ContactProfile` mode ARMOR with `shove_speed` (fortress value), `Health`, `HitFlashAnimationPlayer`, `Sprite` (hull),
`Mover` (`EnemyMover`: `turn_lerp` 0, `acceleration` 0, `braking` 0, `max_turn_rate` 2.5, `hazard_avoidance` 0.3, `hazard_resistance` 0.85 — IDEAS §18.6 "a heavy dreadnought
partially resists"), `Brain`, `Modules` (`ModularHull`) with the eight parts, `PhaseDriver`, `EngineDriver`, overlays `ListSmoke` (two child sprites at the engines, hidden),
`EmergencyLights` (hidden), `CriticalOverlay` (hidden).

#### 2.6.2 Parts and hull geometry (local coordinates, nose +y, port +x; hull rectangle 208 × 448, x ±104, y ±224; every part hurtbox inside it)

| id | role | position | hurtbox | HP (config field) | carries |
|---|---|---|---|---|---|
| `torpedo_tube` | WEAPON | (0, +196) | 40 × 48 | `torpedo_tube_health` 200 | 1 TORPEDO_TUBE mount (t8), bay (t11), Mouth ahead of the bow (0, +250) |
| `missile_rack` | WEAPON | (0, +110) | 56 × 48 | `missile_rack_health` 220 | 1 MISSILE_FAN mount (t8), bay (t11), Mouth beside it on the port side, outside the hull (+130, +110) |
| `broadside_port` | WEAPON | (+84, +20) | 40 × 176 | `broadside_health` 260 | 3 HEAVY_CANNON mounts (t8), bay (t11), Mouth abeam (+132, +20) |
| `broadside_starboard` | WEAPON | (−84, +20) | 40 × 176 | `broadside_health` 260 | same, mirrored, Mouth (−132, +20) |
| `shield_generator` | WEAK_POINT | (0, +30) | 48 × 48 | `shield_generator_health` 160 | the `ShieldSector` generator |
| `core` | CORE | (0, −70) | 72 × 72 | `core_health` 900 | death = the boss's death |
| `engine_port` | ENGINE | (+56, −192) | 64 × 64 | `engine_health` 240 | `WakePoint` (t9) at (+56, −264), `Plume` sprite (t13) |
| `engine_starboard` | ENGINE | (−56, −192) | 64 × 64 | `engine_health` 240 | `WakePoint` (−56, −264), `Plume` (t13) |

Every part: one `HurtBox` shape, `Sprite`, `Light` (`StateLight`), `starts_vulnerable` true, `damaged_ratio` 0.5. `_apply_config()` writes each part's HP (fortress pattern).
The hull's `HurtBox` covers the body within 1 px (`test_enemy_hurtbox_geometry.gd`). Mouths and wake points sit **outside** the hull rectangle (|x| > 104 or |y| > 224) so an escort
or a puff never starts inside the hull. (t11 may move a Mouth if a row needs it, staying outside the hull.)

#### 2.6.3 Armoured hull, core and death

Copy the `SpaceFortress` root pattern: `_on_received_damage` refuses and emits `armor_deflected(damage)`; `deflects_hit()` / `is_armored()` true; `is_laser_blocking()` false;
`accepts_ward()` false; `can_be_repaired()` false; tow refused in every phase; `homing_point(from)` = the nearest live part's homing point; `launch_velocity()` = the mover's own
velocity (a moving launcher); `rocket_clear_radius()` = half the hull diagonal + 8 (≈ 255 px). Core `destroyed` → `health.set_health(0)` → `_on_health_changed` death latch:
`death_started`, `brain.silence()`, `reinforcements.scuttle_all()`, `suspend_ai()`, `BossDeathSequence` (host contract `death_started`, `death_duration`,
`config.death_blast_count`), `_make_corpse_harmless()`, `_finish_death()` through a `Timer` node. No capital wreck (`wreck_chance` 0). EMP: `answers_emp()` true (also while dying),
`apply_emp(seconds × emp_factor 0.4)`, a no-op while dying (Ph12 owner choice 7).

#### 2.6.4 Shields and the target matrix (no locks)

One `ShieldSector` (`global/boss/shield_sector.gd`): generator `shield_generator`, protected `[core, engine_port, engine_starboard]`, params from the config (`shield_capacity` 120,
`shield_regen_delay` 3.0, `shield_regen_seconds` 4.0, `shield_reboot_seconds` 6.0, `shield_pad` 10; the fortress's `_shield_params()` keys). The generator's death exposes all
three for good. "Core vulnerable only when intended" (§40) is met by the bubble, not a lock.

| Target | Gain | Cost (keeps the choice a trade, F6/F7) |
|---|---|---|
| a weapon | that attack goes silent for good (mount UNPOWERED) | two interceptors burst out of its wreck (t11) |
| an engine | one: lopsided, can only circle tightly toward the dead side, half the wake; two: no movement, no wake, no ram | the stern means crossing the wake; two dead → `crippled` frenzy |
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
6. §25: for each pinned path — engines port → starboard then core; starboard → core → port; core → port → starboard — each phase entry's snapshot differs from the previous in every
   declared aspect built so far (`BUILT_KEYS`, extended by t7 / t8 / t9 / t10), and in ≥ 2 aspects on the crippled-then-critical path; boundary: a hit that leaves both engines alive
   changes no snapshot key. t6 builds `visuals` (and the constant `vulnerable` / `reinforcements`).
7. EMP 40 %, no-op while dying; homing point is a live part; tow refused; ward refused.

#### 2.6.8 Incoming damage paths (t6; new `tests/integration/test_dreadnought_incoming_damage_paths.gd`)

A mirror of `tests/integration/test_fortress_incoming_damage_paths.gd` (same structure and constants kept duplicated on purpose; real physics at 8×, both harnesses, the
Dreadnought's own physics off so every shot meets the authored geometry), proving the authored values that fail silently: (a) a player **homing rocket** crosses the armoured hull
and hits the weapon part it steers at (HurtBox mask bit 32 on parts); (b) a **warhead** does the same; (c) a real **asteroid** is refused by the hull (`armor_deflected`), and
(d) damages a bare weapon part (bit 1024); (e) the player's **mining laser** is not blocked by the hull (root layer 0 and `is_laser_blocking()` false) and (f) burns a part
inside the hull; (g) boundary: a plain layer-1 hull-sized body would block the beam. Weapon parts are unshielded, so no generator needs destroying; a row that targets the core or an
engine destroys `shield_generator` first.

Gate-time allotment for t6: 4.5 s (the shell file ≈ 2.5 s + this file ≈ 2.0 s: its fortress original measures 1.5–2.0 s of GUT time, §2.15 inventory; round-2 N8).

### 2.7 Movement: hunting on long arcs (IDEAS §9 Movement, §26, R2/R4/R8/R9; t7)

All in `dreadnought_brain.gd`; config group `Movement`. The brain keeps a unit `heading` and each tick computes a desired heading, turns `heading` toward it at the current
**per-side** rates, adds the yaw bias, then `mover.request_velocity(heading × speed + drift)` and `mover.face_toward(position + heading × FACE_REACH 10000)`. Velocity always runs
along the nose (a ship, not an orbit anchor: `Steering.orbit` would slide a 450 px hull sideways). `turn_asym(heading, desired, rate_port, rate_starboard, delta)` is a static brain
helper (signed angle, clamp by the rate of that side).

#### 2.7.1 Open Space hunt

`patrol_anchor`, `AnchorIdle` like the fortress / Carrier; `start_engaged` skips idle and leash.
- IDLE: `AnchorIdle` slow orbit at `idle_speed` 50; NOTICING → HUNT when the player is within `perceive_radius` 1100 of the hull.
- HUNT guidance: target T = the player's predicted position at `hunt_lead` 1.0 s (`TargetInfo`). If `|T − p|` > `loiter_radius` 700 + `close_band` 300: steer toward the tangent
  point of the loiter circle on the engaged side (it closes on a curve, never head-on). Otherwise: the circle's tangent in the orbit direction plus a radial correction
  `clamp((d − loiter_radius) × radial_gain 0.002, −0.6, 0.6)` rad. **Orbit direction = engaged side:** clockwise (starboard turns) engages starboard, counter-clockwise (port
  turns) engages port.
- Side choice in `twin_engines` / `critical` (F2 hysteresis): prefer the side whose broadside part lives; if both or neither live, keep the current side (seeded 50/50 at spawn).
  Switch at most once per `side_switch_min` 6.0 s. **In `listing` the orbit is forced toward the dead side** (that turn is the only tight one; no hysteresis): port engine dead →
  counter-clockwise, engaging port; starboard dead → clockwise. If that side's broadside is already dead it orbits with its silent side to the player (the reward for that combo).
- Speed `cruise_speed` 120 px/s, `turn_rate` 0.35 rad/s (radius ≈ 343 px; a 420 px/s player out-circles it, the counterplay, F1).
- **Jets** (F1): the player inside ±`stern_arc_deg` 40° of the stern and within `loiter_radius` + 300 for `jets_trigger` 1.5 s and `jets_cooldown` 8.0 s ready → for `jets_seconds`
  1.5 the turn rates × `jets_turn_factor` 2.5 (the listing asymmetry and bias kept). No jets while crippled. `jets_active()` is public (t8 holds broadsides then).
- RETURNING: the player farther than `lose_radius` 1800 from the hull for `lose_seconds` 4.0, or the hull farther than `hunt_leash_radius` 1400 from `patrol_anchor` → fly to the
  anchor at `return_speed` 90 (weapons cold, no wake), then IDLE.

#### 2.7.2 Engine loss

**One engine (`listing`)**, dead side `s` from the root's `dead_engine_side()` (+1 port / −1 starboard): speed v = `cruise_speed` × `one_engine_speed` 0.65 = 78 px/s; the turn rate
toward the dead side ω_dead = `turn_rate` × 1.0 + `one_engine_yaw_bias` 0.05 = 0.40 rad/s; toward the live side ω_live = `turn_rate` × `one_engine_live_turn` 0.5 −
`one_engine_yaw_bias` = 0.125 rad/s; every tick the heading also turns toward the dead side by the bias; the velocity gains `one_engine_drift` 18 px/s along the dead side's unit
vector. Because the drift is perpendicular to the heading and turns with it, a constant full turn traces a circle of radius `sqrt(v² + drift²) / ω` (≈ 200 px toward the dead side,
≈ 640 px toward the live side), so the expected radius ratio is exactly **ω_dead / ω_live = (turn_rate + bias) / (turn_rate × one_engine_live_turn − bias)** (3.2 with the shipped
values). **Config invariants** (a row): ω_live > 0 (it can still turn both ways), and ω_dead ≥ v / `loiter_radius` (the forced dead-side orbit at 700 px needs 0.111 rad/s).

**Both engines (`crippled`)**: phase HOLD: `request_velocity(ZERO)` every tick; the heading turns at `thruster_turn_rate` 0.12 rad/s (× `critical_thruster_factor` 1.5 in
`critical`) toward the bearing that puts the best live weapon on the player (engaged broadside abeam, else the bow).

**Critical** (≥ 1 engine): speed × `critical_speed_factor` 1.15 (the ram itself is t10).

#### 2.7.3 Assault: a stadium loop in the top half of the view

`ConstraintMode` AUTO (the corridor filter). The resting view is world y 0–720 (the camera pans up to ±380 vertically and ±100 horizontally after the player). Spawned above the
view (`world_anchored_x`, centre x = the spawn's world x, default 640). ENTER: heading straight down at `assault_enter_speed` 140 to world y `assault_leg_high_y` 160 ± 8, then HUNT.

HUNT follows a **stadium** (two straight legs joined by semicircles), not a two-waypoint racetrack on one line (a 180° turn at the old 218 px radius put the whole return leg above
the view): upper leg y `assault_leg_high_y` 160, lower leg y `assault_leg_low_y` 400, straight legs over x = centre ± `assault_sweep_half_width` 380; the end radius is derived,
r = (400 − 160) / 2 = 120 px (IDEAS §31: no duplicated magic numbers). Speed `assault_cruise_speed` 90 px/s; the needed turn rate v / r = 0.75 rad/s must not exceed
`assault_turn_rate` 0.9 (a config row). The brain steers by pure pursuit: the nearest point on the stadium plus `assault_track_lookahead` 120 px along the travel direction, turned
toward at the side rates. Default loop direction counter-clockwise (port turns): the lower leg heads right with **starboard facing down**, the upper leg heads left with **port
facing down**, so both legs engage the player below and the sides alternate. Hull extents: upper leg y 56–264, lower leg y 296–504, x 36–1244 at the leg ends: the whole loop is
inside the resting view. Broadsides hold fire through the U-turns (0.75 rad/s > `broadside_fire_turn_cap` 0.30, §2.8), so the legs are the broadside windows; mid-way through
the **left-end** U-turn (heading left → down → right) the bow points down at the player, which is the bow-chasing torpedo tube's window (§2.8); at the right end it points up.

Listing in Assault keeps the loop direction (a reversal would need a 180° turn below the lower leg, toward the player): when the loop's turns are toward the live side the end turns
are slower (ω_live = 0.9 × 0.5 − 0.05 = 0.40 rad/s at v = 58.5 → radius ≈ 146 > 120), so the hull visibly **overshoots** the stadium at each end and pursuit pulls it back; toward the
dead side it holds the track. Crippled = HOLD where it stopped; critical speeds up and rams (t10). No budget, no exit.

**Known Assault limit: the camera's vertical pan** (round-3 P3; t7 writes it into `ENEMY.md` → *Assault*, t15 carries it into `DECISIONS.md` and the report). "Inside the
resting view" holds only while the camera rests. `ArenaCamera` follows the player with a ±30 px vertical dead zone and pans up to 380 px, so a low-flying player drags the view
down: with the player at y 650 the view top is ≈ y 260, and at level 1's player start (y 542) ≈ y 152. The upper leg's hull centre is at y 160 (hull y 56–264), so for much of
the loop the upper leg is partly or wholly above the view and, by the in-view rule, the mounts up there are silent; roughly half its loop is then a quiet climb. The fortress
(hold y 180) shares this. It is accepted for this phase: the stadium is world-anchored, and fitting it to the moving view (or to the player's x) is corridor-constrained AI,
which Ph15 owns when it places the Dreadnought in a level. The hand-ticked rows never move the camera, which is the worst case for density (the whole loop in view), so the t12
density bounds stay conservative. No real-physics lap row is added for it (one lap is ≈ 25 s of game time, ≈ 3 s of gate time at 8×, for a behaviour the plan does not
change); the limit is documented, not tested.

**Snapshot** `movement_snapshot()` = `[speed_factor, turn_factor_port, turn_factor_starboard, yaw_bias, translation_enabled, thruster_turn_rate, ram_enabled]` from fields set in
`on_boss_phase` only (`ram_enabled` stays false until t10 writes it).

#### 2.7.4 Rows (`tests/integration/test_dreadnought_movement.gd`, both harnesses unless noted, `quiet` fixture, `hand_tick`)

**Epic must-have: engine loss changes movement, measured on positions, never the sprite:**
1. Two engines, a fixed full-port then full-starboard turn request for 6 s each: the two fitted turn radii are equal within 2 % and equal `cruise_speed / turn_rate` within 3 %.
2. Port engine dead: fitted radius toward starboard ÷ toward port equals **(turn_rate + one_engine_yaw_bias) / (turn_rate × one_engine_live_turn − one_engine_yaw_bias)** read
   from the config, within 5 %; each radius equals `sqrt(v² + one_engine_drift²) / ω` within 5 %; a straight request drifts the track toward port (net lateral displacement
   > 0.5 × `one_engine_drift` × 5 s after 5 s); speed ≈ `one_engine_speed` × cruise. Mirror row for starboard dead. The config-invariant row (ω_live > 0, ω_dead ≥ v / loiter).
3. Both dead: displacement over 5 s ≤ 1 px with no hazard; rotation still changes at `thruster_turn_rate` toward the player (× `critical_thruster_factor` once `critical`).
4. Open Space hunt: from 1600 px it closes on a curve (the heading never within 10° of the player while farther than 1000 px), then holds 700 ± 150 px for 20 s with the engaged
   broadside within 30° of abeam; the side switches when that broadside dies; in `listing` the orbit runs toward the dead side (both dead sides).
5. Jets: player parked in the stern arc → jets after 1.5 s, turn rate × 2.5 for 1.5 s, not again before 8 s; never while crippled.
6. Leash: player beyond `lose_radius` for 4 s → RETURNING to the anchor; `start_engaged` never returns.
7. Assault (Assault harness): ENTER ends at y 160 ± 8; over two laps the hull centre stays within y [152, 408] and x centre ± (380 + 120 + 8); the downward-facing side alternates
   per leg (starboard on the rightward leg, port on the leftward); the hull rectangle stays inside `EnemyWorld.projectile_world_rect()` from the end of ENTER; listing with the live side as the turn side overshoots the upper
   leg by more than 8 px at an end turn, listing with the dead side as the turn side does not. Config row: `assault_cruise_speed / r ≤ assault_turn_rate`.
8. §25: `movement` joins `BUILT_KEYS` in `test_dreadnought.gd`.

Gate-time allotment: 2.0 s.

### 2.8 Weapons, the per-part attack gate and the extreme-weapons phase (IDEAS §9, §24, §26; t8)

Mounts are authored as `MountSlots` under each WEAPON part and built by `ModularHull.build_mounts(self, brain.rng, owner_group, Callable(), 0)` in the root's `_ready()` after
`brain.bind()` (fortress order); a part's death UNPOWERS its mounts in the same call (R12 "module death disables attack" is the framework's). Right after the build the root
binds each mount's gate to its own part: `for id in WEAPON_PARTS: for m in hull.mounts_of(id): m.telegraph_gate = brain.attack_gate_for.bind(id)`.

| Part | Slots (in tick order) | Variant | Traverse / rest bearing (slot overrides) | Tuning |
|---|---|---|---|---|
| `broadside_port` | `Bow` (part-local y +60), `Mid` (0), `Stern` (−60) | HEAVY_CANNON (Heavy Shell 220 px/s, `burst_count` 2, `burst_gap` 0.35, `charge_seconds` 0.7, scene cooldown 3.2) | `traverse_deg_override` 40 about port abeam (`rest_bearing_deg` 0) | `broadside_cooldown_seconds` 3.2 (config, written after build, ≥ the scene's 3.2) |
| `broadside_starboard` | same, mirrored | HEAVY_CANNON | 40 about starboard abeam (180) | same |
| `missile_rack` | one | **MISSILE_FAN** (t3: 5 × DUMB over 40°, salvo 1, cooldown 6.0, all in `missile_fan_mount.tscn`) | 360 (no override) | scene |
| `torpedo_tube` | one | **TORPEDO_TUBE** (t4: telegraph 1.0, cooldown 7.0, in `torpedo_tube_mount.tscn`) | `traverse_deg_override` **110** about the bow, i.e. ±55° (`rest_bearing_deg` 90) | scene |

**The torpedo tube is a bow-chaser** (round-2 N6; say so in `ENEMY.md`). `traverse_deg` is the whole arc (`TurretMount` uses half of it each way), so 110 = ±55° about the nose.
**Every angle and range below is measured from the tube's own pivot** (round-3 P2): `TurretMount._target_in_arc()` and `fire_range` use the mount's global position, which is
the `torpedo_tube` part at (0, +196), **196 px ahead of the hull centre** — not the hull centre. In a steady orbit the player is abeam (≈ 90° off the nose) and the tube is
silent; it fires when the player is ahead of the bow:
- **Open Space approach curve:** the brain steers to the tangent point of the 700 px loiter circle, so the player sits 700 px off the heading line, `f = sqrt(d² − 700²)` ahead
  of the hull centre at hull distance `d`, i.e. `f − 196` ahead of the tube. From the tube the player is at `atan(700 / (f − 196))` off the nose and
  `sqrt(700² + (f − 196)²)` away. In range (≤ 1100 from the tube) from d ≈ 1257 (39.5° off); inside ±55° down to d ≈ 980 — but the brain stops tangent-steering at
  `loiter_radius + close_band` = 1000 and starts orbiting, so the window is **d ≈ 1257 → ≈ 1000, ≈ 2.6 s** at the approach's ≈ 97 px/s closing speed: room for the tube's 1.0 s
  telegraph. (At the earlier ±45° it was d ≈ 1257 → 1137, ≈ 1.2 s, barely one telegraph; that is why the slot was widened to 110.)
- whenever the player crosses ahead of the bow; during the ram's LINE_UP (nose coming onto the player; t10); in `crippled` HOLD once no broadside lives (the thrusters turn the bow
  on); and in **Assault** through the left-end U-turn (heading left → down → right, §2.7.3): with the player below the leg end the bow is within ±55° of it for ≈ 110° of the
  180° turn, ≈ 2.6 s of the ≈ 4.2 s U-turn at 0.75 rad/s.
It is the weapon that fills the broadsides' silences, not a steady stream (its 7.0 s cooldown caps it at ≤ 0.125 launches/s in any case).

Every slot authors `pool_period_factor` 0.45 = `crippled_cooldown_factor` 0.6 × `critical_cooldown_factor` 0.75 (a row pins it to the config product). The broadside cooldown is
written onto the six mounts after the build only **upward** from the scene's own value (the Carrier precedent: a longer period keeps the build-time pools sufficient); a row asserts
`broadside_cooldown_seconds ≥` the HEAVY_CANNON scene's `cooldown_seconds` read through `TurretMountScenes.export_of()`.

**Per-part gate** `attack_gate_for(part_id) -> bool` (asked only on a mount's TRACK → TELEGRAPH step), rules in this order:
1. **Ram:** false for every part while the ram is in WIND_UP or CHARGE, and for `missile_rack` also in LINE_UP (t10 fills `_ram_phase()`; t8 leaves it IDLE) — so no own
   rocket is ever launched into the path of the charging hull (§2.10);
2. **Own-ordnance separation** (round-2 N5): `missile_rack` false while `torpedo_tube` is committed or **any own torpedo is live**; `torpedo_tube` false while `missile_rack` is
   committed or **any own fan rocket is live**. "Live" = launched (the mount's `round_fired(projectile)`) and not yet `expired` (the brain connects that projectile's `expired`
   one-shot and keeps two counters, `live_own_rockets()` / `live_own_torpedoes()`, both public). Why: a Dreadnought rocket's `HitBox` (layer 32, mask 128 | 512) sees its own
   torpedo's `HurtBox` (512, mask 96 — `EnemyOrdnance._on_hurt` takes the rocket's `impact_damage` 16) and detonates on it; the torpedo crawls off the bow at 22–40 px/s relative
   for its 3 s steer window, so a fan fired after it overtakes it. A rocket-side owner-group skip would **not** fix it: the torpedo's `HurtBox._on_area_entered` applies the damage
   on its own, whatever the rocket does. So they are kept apart in time (a rocket lives ≤ 4.0 s, `dumb_rocket.tscn` `max_time`; a torpedo ≤ 10 s), with no shared-code change;
3. **Ripple spacing:** for a broadside part, false if a mount of that side entered TELEGRAPH less than `broadside_ripple_gap` 0.25 s ago (the brain records entries from each
   mount's `phase_changed`);
4. **Already committed:** true if the part is already committed (any of its mounts in TELEGRAPH or FIRE) — a broadside side counts **once**;
5. **Cap:** else `committed_parts() < _max_attacks` (`max_concurrent_attacks` 2; `critical_max_concurrent_attacks` 3 in `critical` or `crippled`).

`committed_parts()` counts WEAPON parts with a mount in TELEGRAPH or FIRE. **One-salvo mounts are committed only in TELEGRAPH:** with `salvo_count` 1 the rack (and the tube,
one torpedo per cycle) spends no tick in FIRE — on the TELEGRAPH-end tick `_fire_tick(0)` launches the salvo, reports done and `_end_fire()` runs in the same tick
(`turret_mount.gd` TELEGRAPH → FIRE → COOLDOWN) — so their committed windows are their charges, 0.5 s (rack) and 1.0 s (tube). A HEAVY_CANNON mount is committed through its
0.7 s TELEGRAPH and its 0.35 s two-shell FIRE.

**Broadside sweep (§24 "a Dreadnought uses broadside cannons"):** narrow-traverse batteries fire roughly abeam while the hull's own arc turn walks the lanes across the player — the
arc and the broadside are the same geometry. The brain ticks a side's mounts bow → mid → stern, so with all three ready the spacing rule ripples them: telegraph entries at
0, 0.25, 0.5 s; each mount fires its `burst_count` 2 shells (`charge_seconds` 0.7, `burst_gap` 0.35), so **a full side volley is 6 shells**, first shells at 0.70, 0.95, 1.20 s.
The bow's 0.7 s telegraph keeps the side committed past the stern's entry, so a volley never needs a second slot. Broadsides get `host_can_fire` false while `jets_active()` or
while the brain's commanded turn rate exceeds **`broadside_fire_turn_cap` 0.30 rad/s** (a telegraph in progress drops back to TRACK; a burst stops). The hunting orbit asks
0.171–0.197 rad/s and the forced `listing` orbit 0.111 rad/s, all under the cap; jets (0.875 rad/s) and the Assault U-turns (0.75 rad/s) are over it.
**Fairness** (round-2 N3): a lane's tip speed at `fire_range`, `broadside_fire_turn_cap × fire_range` = 0.30 × 900 = **270 px/s**, must be ≤ 0.8 × each player scene's
**`cruise_speed()`**, read from instantiated nodes: the Assault fighter 360 (`MoveState.move_speed`, the reading the fortress fairness rows use) → 288, the Open Space ship 420 →
336. Both pass (at the old 0.35 the fighter failed: 315 > 288). Lever if it fails: lower `broadside_fire_turn_cap` (never raise `fire_range`).

**Extreme weapons** on `crippled` / `critical` entry: `_set_attacks()` multiplies each live mount's `cooldown_seconds` by the phase factor once (guarded per phase) and raises the cap.
Nothing fires outside the Assault view, nor while not engaged, nor under EMP (mounts `scan()`).

**Own fire never hits the Dreadnought (static half; the moving half is t10's row 8):** every round scene its mounts fire — Heavy Shell (`EnemyBullet` HitBox mask), the DUMB rocket,
the torpedo — read from the scenes: no enemy-hurtbox bit on a shell; a rocket's impact box opens only beyond the launcher's `rocket_clear_radius()` (√(104² + 224²) + 8 = 255 px);
the torpedo's `ContactBlast` is PLAYER-hostile, its proximity area masks only 128 and its `HurtBox` mask 96 never sees a part (parts are hurtboxes on 512, the hull's
`ContactHitBox` is on 256). The one own-on-own collision that exists — a fan rocket on its own torpedo — is prevented by gate rule 2 (rows 11 and 12).

**Snapshot** `attacks_snapshot()` = `[cooldown_factor, max_concurrent_attacks, broadside_ripple_gap]`.

**Rows** (`tests/integration/test_dreadnought_weapons.gd`; brain-ticked unless noted, rounds returned to their pools at their own `max_time`; spawned and driven through
`tests/helpers/dreadnought_fixture.gd`'s `spawn(h, opts)`, `hand_tick(d, dt)`, `kill_part(d, id)` and `ladder(d, ids)`, §2.6.1). **Epic must-have: module death
disables its attack:**
1. For each WEAPON part, both harnesses, **with an alive control** (round-2 N6): the player is placed inside that part's arc, cone and range (abeam for a broadside; 600 px dead
   ahead of the bow for the tube; any bearing for the rack) and the other weapon parts are destroyed first so the cap never blocks it. Control: with the part alive it launches at
   least one round / rocket / torpedo within 20 s. Then destroy it → every mount of it UNPOWERED and nothing from it over the next 20 s with the player still in its arc; the
   destroyed broadside's side gets no shell (a player abeam on that side is never hit by a broadside round). A part that never fired in the control fails the row.
2. Ripple: a side volley is 6 shells (`3 × burst_count` read from the instantiated mounts); the **first shell of each mount** leaves bow → mid → stern at least
   `broadside_ripple_gap` − one tick apart.
3. **Volley stays whole while another weapon is busy** (round-2 N7): with the cap at 2, the missile rack is put into **TELEGRAPH** (its 0.5 s charge) so that its charge overlaps
   the port volley's 0.5 s ripple (rack TELEGRAPH entry 0.1 s after the port bow's entry); the port volley still leaves all three mounts (6 shells). Boundary: with the cap at 2,
   the rack in TELEGRAPH and the starboard side committed, an uncommitted port side gets no telegraph.
4. Fan: one rack salvo = five rockets spread 40°.
5. Gate: never more than 2 committed parts (3 in `critical` / `crippled`) over a 60 s stress.
6. `crippled` / `critical` cut cooldowns once each (product 0.45 when both); the slots' `pool_period_factor` equals the product; `broadside_cooldown_seconds` ≥ the scene's; no pool
   reports empty in a 30 s worst-case stress (`critical` + `crippled`, all weapons live).
7. Broadsides hold fire while jets are active and while the commanded turn exceeds the cap.
8. Fairness inequality (instantiated mounts and both player scenes' `cruise_speed()`).
9. Own-fire static row (above).
10. §25: `attacks` joins `BUILT_KEYS`.
11. **Separation, both orders** (hand-ticked, both harnesses): rack-then-tube — after a fan salvo the tube is refused while `live_own_rockets() > 0` and telegraphs within one
    tick of the last rocket's `expired` when the player is in its arc; tube-then-rack — after a torpedo the rack is refused while `live_own_torpedoes() > 0`, and a torpedo shot
    down early frees it on that tick; rack and tube are never committed on the same tick. Stress: 60 s in `critical` + `crippled` with the player 600 px ahead of the bow (both
    want to fire): on **no tick** is there both a live own rocket and a live own torpedo.
12. **Why rule 2 is load-bearing** (real physics, 16×, a short window, Assault harness): with the rack's gate bypassed for this row only (the test sets
    that mount's `telegraph_gate` to a Callable returning true), an armed DUMB rocket fired by the Dreadnought's own rack through a parked live own torpedo detonates on it and the torpedo loses the rocket's `impact_damage` — characterising the collision the separation rule prevents (if a later change makes them pass
    through each other, this row says so and rule 2 may be relaxed in that change).

Gate-time allotment: **2.8 s** (round-3 P7), measured as the whole-suite delta, not only this file's time: once t8 authors eight mounts and their pools (≈ 80 rounds) in
`dreadnought.tscn`, **every earlier Dreadnought spawn** builds them too (the t6 shell and incoming-damage files and the t7 movement file, both harnesses); Ph11 t7's five fortress
mounts added ≈ 0.75 s to `test_space_fortress.gd` alone. Pre-approved lever if the delta overruns: the fixture gains `opts.bare` (default false), which frees every `MountSlots`
node before `add_child()` so no mount or pool is built, used only by rows that assert nothing about weapons (the t7 movement rows, quiet anyway), and recorded in
`tests/README.md` → *Gate time*; weapon, density, ram and reinforcement rows never use it. (The measured density is its own task, t12, §2.12.)

### 2.9 The engine wake on the Dreadnought (IDEAS §9, §24; t9)

Each engine part has a `WakePoint` (`Marker2D`) 72 px behind its centre, outside the hull: port (+56, −264), starboard (−56, −264) in Dreadnought-local coordinates (nose +y; the
engine parts sit at (±56, −192), 64 × 64; the hull rectangle is 208 × 448, y ±224). The brain (physics tick, engaged phases HUNT / LINE_UP / WIND_UP / CHARGE / RECOVER only —
never IDLE, NOTICING, RETURNING, ENTER, HOLD) accumulates the distance each **live** engine's `WakePoint` travelled and every `wake_spacing` 48 px spawns one `EngineWake` (t5)
there: `set_owner_group(owner_group)`, `set_scale_factors(radius_factor, life_factor)` (`listing_wake_radius_factor` 1.3 / `listing_wake_life_factor` 1.3 in `listing`, else 1 / 1),
`spawn_into(Hazards.container(tree), point)` — skipped (counted in `wakes_skipped`) when there is no container or `wake_max_live` 40 of its own puffs live. A destroyed engine stops
its own wake at once; `crippled` turns the wake off. The Assault wake lives in world space while the camera pans. This task adds only the `WakePoint` markers; the engine `Plume`
sprite belongs to t13 (art).

**Snapshot** `arena_snapshot()` = `[wake_enabled, wake_radius_factor, wake_life_factor]`.

**Rows** (`tests/integration/test_dreadnought_wake.gd`, both harnesses, a hazard container added by the test): puffs appear every 48 px behind each live engine only while engaged;
none in IDLE / RETURNING / HOLD; one engine dead → only the live engine's puffs, radius × 1.3; crippled → none; no container → none and no error; the Dreadnought's own escorts are
not damaged by its wake, the player is; the hull never loses HP to its wake; `wake_max_live` respected; every puff spawns outside the hull rectangle; §25 `arena` joins `BUILT_KEYS`
(`listing` and `crippled` declare ARENA). Gate-time allotment: 0.8 s (risk lever if the hazard count costs: `wake_spacing` 48 → 64).

### 2.10 The critical ram (IDEAS §9 "heavy ram when critically damaged", §25 "final ram"; t10)

The `RamCorvetteBrain` cycle on the boss, enabled only in `critical` with ≥ 1 engine (`ram_enabled`), never in `crippled`:
- **Start:** the cycle leaves HUNT for LINE_UP only when `ram_enabled`, `ram_first_delay` 2.0 s after `critical` entry / `ram_cooldown` 8.0 s after the last completed cycle / `ram_retry_delay` 2.0 s after an abort have passed,
  **and no own fan rocket is live** (`live_own_rockets() == 0`, the counter t8 added; a rocket lives ≤ 4.0 s). Together with the gate refusing the missile rack from LINE_UP to
  the end of CHARGE (t8 gate rule 1), the charging hull never meets one of its own armed rockets (round-2 N5).
- **LINE_UP — the nose comes on at the jets rate** (round-3 P1; §25 "engines overload"): the aim = the player's predicted position (lead `Steering.clamped_lead_time`), in
  Assault clamped to within `assault_ram_max_from_vertical` 50° of straight down. The heading turns toward the aim at the **current side rates × `jets_turn_factor` 2.5** (in
  `listing` the per-side rates ω_dead = `rate + one_engine_yaw_bias` and ω_live = `rate × one_engine_live_turn − one_engine_yaw_bias`, each × 2.5, with no separate bias turn
  added in LINE_UP; this does not start or consume the HUNT jets' cooldown, and `jets_active()` reads true through LINE_UP), at speed × 
  `ram_line_up_speed_factor` 0.5. LINE_UP ends → WIND_UP on the first tick the nose is within `ram_aim_tolerance_deg` 8° of the aim. Resulting 90° turn times (π/2 ÷ rate):
  Open Space both engines 0.875 rad/s → 1.80 s; listing, toward the dead side 1.0 → 1.57 s, toward the live side 0.3125 → 5.03 s; Assault both engines 2.25 → 0.70 s,
  listing dead side 2.375 → 0.66 s, live side 1.0 → 1.57 s. In the Open Space `listing` orbit the player is on the dead side (the orbit is forced that way, §2.7.1), so the slow
  live-side turn happens only when the player has crossed over — staying on its live side is a real way to deny the ram.
- **`ram_line_up_cap` 5.5 s, sized from the config** (a config row): `ram_line_up_cap ≥ (π/2) / (ω_live × jets_turn_factor) + 0.25` for each mode, with ω_live =
  `rate × one_engine_live_turn − one_engine_yaw_bias` and `rate` = `turn_rate` 0.35 (Open Space: 5.03 + 0.25 = 5.28 s) or `assault_turn_rate` 0.9 (Assault: 1.82 s).
- **At the cap, not aimed → abort and retry** (never a crooked charge): if the nose is still more than `ram_aim_tolerance_deg` off the aim when the cap runs out, the cycle
  returns to HUNT (no lane drawn, no damage change), counts `ram_aborts()` (public), and may start LINE_UP again after `ram_retry_delay` 2.0 s (the other start conditions still
  apply; the `ram_cooldown` 8.0 s is not charged by an abort).
- **WIND_UP** `ram_wind_up_seconds` 1.2 s: speed × 0.3, engines' lights CHARGING, a **lane** drawn (`RamLane` child drawing a rectangle the hull's beam 208 px wide **from the
  bow along the heading**, length = the charge length below); for the first `ram_track_fraction` 0.4 the heading keeps turning toward the (clamped) aim at the LINE_UP rate, then
  the line **freezes**: `charge_dir` = **the heading at that tick** (in Assault clamped to 50° of down; the clamp moves it by at most `ram_aim_tolerance_deg`, asserted), and
  `charge_point` = the hull centre + `charge_dir` × max(0, (aim − hull centre) · `charge_dir`), the aim's projection onto the charge line. The charge therefore always runs straight
  along the nose; it never follows an aim the nose is not on (the Ram Corvette's "charge follows the aim" rule is for a 0.5 s-turning ship and is not copied).
- **CHARGE**: the heading is held at `charge_dir` (the brain does not turn it; `face_toward` along `charge_dir` every tick), and
  `mover.boost(charge_dir, ram_speed 560, charge_length / 560)` with `charge_length = min(dist + overshoot, ram_speed × ram_max_time 2.0, edge_limit)`, `dist` = |`charge_point` −
  hull centre at the freeze|, where
  `overshoot` = `ram_overshoot` 300 in Open Space and **`assault_ram_overshoot` 150** in Assault, and `edge_limit` (Assault only, +∞ in Open Space) = the distance along
  `charge_dir` at which the first corner of the hull rectangle (208 × 448, oriented on `charge_dir`) would reach `EnemyWorld.projectile_world_rect()` (x −164…1444,
  y −444…1164) shrunk by `assault_ram_edge_margin` 16 px — a ray-against-rectangle test on the four corners, computed once when the line freezes (round-2 N10). The mover runs
  `acceleration` / `braking` 0, so the hull stops when the boost ends (no coast). A boost ignores avoidance (the Ph6 committed-run rule); the Assault corridor filter still
  applies. Lights COMMIT; `contact_hit_box.damage = config.ram_damage` 35 during CHARGE only, restored to `collision_damage` 25 on exit (the Ram Corvette
  `exposed_collision_damage` precedent: the contact-damage gate reads the spawn value).
- **RECOVER** `ram_recover_seconds` 2.0: speed × 0.5, a wide turn back to HUNT — the punish window.
- The per-part attack gate opens nothing new during WIND_UP / CHARGE, and nothing for the missile rack from LINE_UP on (`_ram_phase()`, t8 gate rule 1).
- **Assault:** the charge direction is clamped to within `assault_ram_max_from_vertical` 50° of straight down (a diagonal corridor dive); RECOVER climbs back to the stadium
  (pure pursuit to its nearest point).
- An engine lost mid-cycle keeps the cycle; both lost → cancel at once (CHARGE's boost ends, phase HOLD). EMP / death cancel it (`on_emp_started`, `silence`).
- **Fairness** (instantiated config and both player scenes): `ram_wind_up_seconds × (1 − ram_track_fraction)` ≥ (104 + player hurt radius) / player `cruise_speed()` + 0.25 s
  (1.2 × 0.6 = 0.72 ≥ (104 + ≈ 20) / 360 + 0.25 ≈ 0.59 for the fighter). Lever: raise `ram_wind_up_seconds`; never narrow the lane.
- `movement_snapshot()`'s `ram_enabled` is written on `critical` entry (true with ≥ 1 engine) and on `crippled` entry (false).

**Rows** (`tests/integration/test_dreadnought_ram.gd`, both harnesses unless noted; spawned through `tests/helpers/dreadnought_fixture.gd` with `opts.ram` true, phases reached
with its `ladder()` / `kill_part()`, hand-ticked with its `hand_tick(d, dt)`; boost rows start with `await _fresh_idle_delta()`). **Epic must-have: the critical ram:**
1. Before `critical`: no ram over 30 s. In `critical`: LINE_UP → WIND_UP → CHARGE → RECOVER in order; the first WIND_UP ≥ `ram_first_delay` after entry; LINE_UP ends on the
   first tick the nose is within `ram_aim_tolerance_deg` of the aim.
2. The line freezes at `ram_track_fraction` (moving the player afterwards does not change `charge_dir`); on every CHARGE tick the hull's nose (read from its `rotation`) is within
   1° of `charge_dir` and the lane runs from the bow along it; the **hull centre** passes `charge_point` and stops at least **that mode's overshoot − 50 px** beyond it (Open
   Space `ram_overshoot` 300 → ≥ 250; Assault `assault_ram_overshoot` 150 → ≥ 100). The player is placed so neither cap binds (round-3 P8): Open Space **700 px** from the hull
   centre (≤ 800, because `ram_speed × ram_max_time` = 1120 px binds beyond ≈ 820 px), Assault 200 px below the lower leg at the hull's x; the row asserts `charge_length` <
   `ram_speed × ram_max_time` and, in Assault, `charge_length` < `edge_limit`.
3. Contact damage is 35 only during CHARGE and 25 otherwise (a real hit in each state).
4. Boundary: `critical` with both engines dead → no ram ever (60 s); both engines lost mid-WIND_UP → cancelled, HOLD.
5. One engine (round-2 N4, round-3 P1): a LINE_UP needing a 90° turn toward the live side and one toward the dead side (Open Space: the player placed abeam on each side in
   turn; Assault: the hull hand-placed heading right and then heading left with the player directly below, so the clamped aim is straight down). Over the **first 0.5 s** of
   LINE_UP (before even the fastest case, Assault dead side 2.375 rad/s, finishes 90°) the measured turn rate toward each side equals `ω_side × jets_turn_factor` within 5 %,
   ω_dead = `rate + one_engine_yaw_bias`, ω_live = `rate × one_engine_live_turn − one_engine_yaw_bias`, `rate` = `turn_rate` (Open Space) or `assault_turn_rate` (Assault), all
   read from the config; so `rate_dead / rate_live` equals the formula (3.2 Open Space, 2.375 Assault with the shipped values) within 10 % and is > 1. No fixed number. Both
   LINE_UPs reach the tolerance before `ram_line_up_cap` and go on to WIND_UP.
6. Assault (Assault harness): the charge direction is within 50° of down; from five player positions (below centre, left, right, under each leg end) **and the lowest**
   (the player at the corridor's bottom, y 1100 − its hurt radius) the hull rectangle's four corners stay inside `EnemyWorld.projectile_world_rect()` on every tick from LINE_UP
   to the end of RECOVER; boundary: from the lowest position `edge_limit` binds (asserted) and the bow stops ≥ `assault_ram_edge_margin` inside the rect. Pre-approved levers,
   in order, if the row fails or the dive reads too long: `assault_ram_overshoot` 150 → 100, then `assault_ram_max_from_vertical` 50° → 40°; never widen the rect.
7. Fairness inequality; the lane is drawn exactly the beam wide along `charge_dir` during WIND_UP, its length = `charge_length`.
8. **Own fire never hits it while it moves** (round-2 N5, the realistic setup): (a) hand-ticked, both harnesses, 60 s in `critical` with the player 700 px ahead of the bow so
   the rack, the tube and the ram all want to act: on no tick of LINE_UP / WIND_UP / CHARGE is `live_own_rockets() > 0`, and a fan fired just before `ram_first_delay` runs out
   delays LINE_UP until its last rocket's `expired`. (b) Real physics at 16×, Open Space harness, a short window: in `critical` with every part live and the player 700 px dead
   ahead, the tube fires a torpedo at the player through the normal gate flow, then the ram (`ram_first_delay` set so WIND_UP starts within 1.5 s of the launch) charges
   along the same line and overtakes it; the row asserts the hull rectangle overlapped the torpedo's position on some tick (not vacuous), no part lost HP, the torpedo's
   `Health` is unchanged. Pre-approved fallback if (b) fails: the tube is also refused from LINE_UP to the end of CHARGE and LINE_UP also waits for
   `live_own_torpedoes() == 0`.
9. §25: the critical row's `movement` difference now includes `ram_enabled`.
10. **Cap and abort** (round-3 P1): config row — `ram_line_up_cap ≥ (π/2) / (ω_live × jets_turn_factor) + 0.25` in each mode (read from the config). Abort row (hand-ticked,
    both harnesses): the test writes `ram_line_up_cap` 0.5 s on the private config copy and places the player abeam (coming within 8° of a 90° aim needs ≥ 0.60 s even at the fastest LINE_UP rate, Assault dead side 2.375 rad/s) → at the cap the
    cycle returns to HUNT with `ram_aborts()` 1, no lane was drawn, `contact_hit_box.damage` stayed 25 and no boost ran; the next LINE_UP starts no earlier than
    `ram_retry_delay` after the abort. Boundary: with the shipped cap the same setup reaches WIND_UP with `ram_aborts()` 0.

Gate-time allotment: 1.7 s.

### 2.11 Interceptors from a destroyed weapon (IDEAS §10; t11)

Each WEAPON part carries a `Bay` (`ReinforcementBay`, trigger `ON_OWN_DESTROYED` from t2) with a `Mouth` outside the hull rectangle (208 × 448, x ±104, y ±224) on that part's side:
`torpedo_tube` (part at (0, +196)) Mouth (0, +250), ahead of the bow; `missile_rack` (0, +110) Mouth (+130, +110); `broadside_port` (+84, +20) Mouth (+132, +20);
`broadside_starboard` (−84, +20) Mouth (−132, +20). `bay_id` = the part id, `payload_scene` and `assault_payload_scene` = `gatling_interceptor.tscn` (Ph12 owner choice 1),
`count` 2, `assault_count` 2, `door_seconds` 0.8 (the breach telegraph: CHARGING light on the wreck, sparks), `open_hold_seconds` 0.6, `config_overrides` as needed for the Ph11
"escorts fire within 3 s" rule (the gatling pair measured ≈ 1.8 s in Ph11 t8 with none). The root builds `BossReinforcements(host, hull, phase_driver, brain.rng, owner_group,
cap, escort_boost_speed 300, escort_boost_seconds 0.4)` with cap `escort_cap_open_space` 6 / `escort_cap_assault` 4; the brain ticks it with `active = is_engaged() and not EMP`
(and once with `false` from `on_emp_started()`); death scuttles. Escorts go into `<name>Escorts` (`EscortContainer`), announced on `EventBus.boss_escort_spawned`, never
`enemy_spawned_orphan`, scored by the Ph11 path; nothing writes their `counts_toward_wave_clear` / `counts_as_escape`.

**Rows** (`tests/integration/test_dreadnought_reinforcements.gd`, both harnesses; weapons destroyed with `tests/helpers/dreadnought_fixture.gd`'s `kill_part(d, id)` through
their real damage path, phases reached with its `ladder(d, ids)`, §2.6.1): each weapon's death launches 2 interceptors from its own wreck's `Mouth` after 0.8 s (each
spawn point outside the hull rectangle); the light is CHARGING through the breach; the cap holds (four weapons killed in 1 s → at most 6 / 4 alive, the rest skipped); a weapon
killed during the death sequence launches nothing; the core killed mid-breach launches nothing and scuttles the live ones; escorts fire within 3.0 s of launch (Assault, 16×,
tick-paced); the shield generator / engines / core have no bay; a bay-launched escort pays score through `boss_escort_spawned`; the wake never damages an escort (owner group).
Gate-time allotment: 1.0 s.

### 2.12 Measured Assault density in every phase state (Ph11 convention; t12)

Split out of the weapons task (round-1 review M10) and placed after the interceptors so it measures the final mount set and phase consequences. Assault harness only, in a new
`tests/integration/test_dreadnought_density.gd` (or appended to `test_dreadnought_weapons.gd` if the agent prefers; one file either way).

- **States:** `hunting`, `listing` (each dead side), `crippled`, `critical`, `critical`+`crippled` — each × the worst live-part set for that state (all weapons live) × five player
  positions (below centre, left, right, under each leg end), 11 s each at 1/60 s, hand-ticked (brain + mover, the fixture's `hand_tick`), the boss not quiet. Geometry
  (§2.7.3): the Assault stadium has legs at world y `assault_leg_high_y` 160 / `assault_leg_low_y` 400 and leg ends at x = spawn x ± `assault_sweep_half_width` 380 (world x 260 /
  1020 at the default spawn x 640); the player sits 250 px below the lower leg. Each state is reached with the fixture's `ladder()` / `kill_part()` (§2.6.1) — the real
  phase-driver path, never by writing the brain's fields.
- **Counting:** Dreadnought-owned launches only (shells, rockets, torpedoes: each mount's `round_fired`); each round is returned to its pool at once after being counted (Ph11
  t16 method) so pools never empty by test artefact; escort rounds are excluded (the escort caps are 0 in this row).
- **Bounds (frozen, Ph11):** mean ≤ 13.3 launches/s; peak ≤ 30 in any half-open 2 s window; committed WEAPON parts ≤ 2 (3 in `critical` / `crippled`) on every tick; a count during
  which any pool reported empty fails the row.
- **Levers, in order, never widening a bound:** (a) `broadside_cooldown_seconds` up (config; stays ≥ the scene value), (b) `missile_fan_mount.tscn` `fan_count` 5 → 4,
  (c) `crippled_cooldown_factor` 0.6 → 0.7 (and every slot's `pool_period_factor` to the new product). A lever used is recorded in `DECISIONS.md` and `ENEMY.md`.
- Expected from the shipped values (a sanity figure the row prints, not an assertion; round-2 N6): `hunting` ≈ 2.2 /s (one side's 6 shells per 4.25 s = 1.41, 5 rockets per
  6.5 s = 0.77; the torpedo term ≈ 0 in a steady orbit, because the tube is a bow-chaser with a ±55° arc (measured from the tube's pivot, 196 px ahead of the hull centre) that fires only when the player is ahead of the bow — in Assault mid-way
  through the left-end U-turn — and the rack additionally waits out any live own torpedo), `critical`+`crippled` ≈ 4 /s (one side's 6 shells per ≈ 2.5 s, 5 rockets per ≈ 3.2 s).

Gate-time allotment: 2.5 s (round-2 N8: 6 states × 5 positions × 660 ticks = 19 800 full ticks; at Ph11's measured ≈ 1.4 s per 13 200-tick row that is ≈ 2.1 s, and the
Dreadnought ticks more mounts than the fortress).

### 2.13 Art, detachment and visual states (IDEAS §21–23, R13/R14; t13)

`assault/assets/sprites/enemies/dreadnought/`, every texture at scale 1 and the size of its frozen hurtbox (t6, §2.6.2: hull 208 × 448; `torpedo_tube` 40 × 48, `missile_rack`
56 × 48, broadsides 40 × 176, `shield_generator` 48 × 48, `core` 72 × 72, engines 64 × 64), strictly top-down, ≤ 90 % opaque, faction palette (dark navy hull, red / maroon accents,
cool blue edge light), gameplay lights left to `StateLight`.
- `dreadnought_hull.png` 208 × 448: a long ship outline (tapered bow, broad stern) with **empty sockets** for every part; `create_map_object` above 40 000 px paints a background —
  strip it (`./scripts/strip-sprite-bg.sh`) or hand-draw through `pixelart_workbench` (the Ph10 t9 / Ph11 t9 routes).
- Per part an intact and a **wreck stump** texture (the stump's opaque area is visibly less than the intact art's, so the outline shrinks); broadside and engine starboard copies
  `flip_h`. `engine_plume.png` on a `Plume` `Sprite2D` **child of each engine part** (this task creates the node; it dies with the engine), `list_smoke.png`,
  `critical_overlay.png` 208 × 448 (mostly transparent). The torpedo sprite and the tube head are t4's; the MISSILE_FAN head (`turret_head_missile_fan.png`) is t3's; broadside heads are HEAVY_CANNON's. Every mount variant keeps its own
  distinct head (`test_ph8_sprites.gd`), so this task draws no turret head.
- **Detach chunk (purely visual):** on a part's `destroyed` (not while dying) the root adds one `DreadnoughtChunk` (new `dreadnought_chunk.gd` + `.tscn`: a `Sprite2D` root with
  `top_level = true`, per-part chunk texture) as a **child of the Dreadnought**, deferred (`add_child.call_deferred`, never inside the physics callback that destroyed the part), at
  the part's global position, flung outward from the hull centre at 60–90 px/s (seeded from the brain rng) with spin, decelerating, fading over its last 1.0 s, freeing itself after
  `lifetime` 2.5 s. **No collision areas, no hazard registration, no damage** (boss hazards and debris are Ph19's scope); as a child it is freed with the boss, so it has exactly one
  owner and needs no container.

**Rows** (`tests/integration/test_dreadnought_sprites.gd`, no physics): every file's size / corners / 15 % < opaque < 90 %; hull and parts wired at scale 1 with the art the size of
each hurtbox; each part's wreck swap on destroy and its stump's opaque area < its intact art's; plumes are children of the engines (gone with them); `ListSmoke` / `CriticalOverlay`
shown by their phases; one chunk per destroyed part, none while dying, the chunk has no `Area2D` / `CollisionObject2D` descendant and never registers with `Hazards`, it frees itself
after `lifetime`. Gate-time allotment: 0.3 s.

### 2.14 Open Space hub placement (t14)

`open_space/scenes/levels/sector_hub.gd`: **draw 22** appended after the fortress (every earlier seed unchanged): `_spawn_dreadnought(_ring_anchor(dreadnought_ring_radius 4800,
dreadnought_anchor_bearing_deg 135.0), rng)` ≈ (−3394, 3394) (round-2 N11: at the earlier 4200 ring it sat ≈ 2055 px from two neighbours, inside its own 2500 px reach), `patrol_anchor` and `rng_seed` set before `add_child()`, not `start_engaged`, into `EnemyContainer`; its escorts land
in its own `<name>Escorts` container. `tests/integration/test_sector_hub_patrol.gd`: add it to `_patrol_groups()` with footprint `hunt_leash_radius` 1400 + `perceive_radius` 1100
(a hunter's reach is its leash), move every hard count by one (the Ph11 t13 precedent), and the sweep must stay green.

**Neighbouring patrols (round-2 N11).** Its south-west neighbours are the Heavy Gunship (2600 ring at 157.5°, ≈ (−2402, 995)) and the Laser Tender (2600 ring at 112.5°,
≈ (−995, 2402)); from (−3394, 3394) each is ≈ 2596 px away, outside the Dreadnought's reach `hunt_leash_radius` 1400 + `perceive_radius` 1100 = 2500 (every other patrol anchor is
farther: the sniper's (−1202, 1202) ≈ 3100 px). New row in `test_sector_hub_patrol.gd`: **every other `_patrol_groups()` anchor lies outside the Dreadnought's footprint**
(leash + perceive, read from its config), so a player fighting at a neighbour's anchor cannot be noticed by it. What stays possible, and is intended: once engaged, it follows the
player up to `lose_radius` 1800 / its leash, so a chase can drag it into a neighbour's fight — an emergent mixed fight, not a bug; who owns an encounter is Ph13 / Ph14's (say so
in `ENEMY.md` and `DECISIONS.md`). **Pre-approved levers, in order, each keeping both rows green:** ring 4800–5200, then `hunt_leash_radius` 1400 → 1100, then a bearing of
135° ± 10° **only together with a ring of at least 5200** (round-3 P6: at 4800 a 145° bearing puts the Heavy Gunship anchor ≈ 2331 px away and 125° the Laser Tender's, both inside
the 2500 px reach; at 5200 / 145° the Gunship's is ≈ 2721 px and at 5200 / 125° the Tender's ≈ 2721 px). If none clears, stop and escalate. Gate-time allotment: 0.5 s.

### 2.15 Gate time (t1 and every task)

**Where it stands.** GUT ≈ 225.2 s after Ph11 (two-run mean at the Ph11 t11 close; ceiling 240 s, escalation past a 237 s two-run mean). The allotments below total 18.4 s, so
the phase would end ≈ 243.6 s without help. ≈ 6.6 s is strictly needed to stay under 237 s; t1's floor is 8 s and its target 10 s because run noise is ±1–3 s.

**Measured inventory (2026-11-25, this container, warm import cache; each file run alone with `time godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
-ginclude_subdirs -gselect=<file> -gexit`; wall includes ≈ 1 s of engine start).**

| File | Clock | Wall | user + sys (CPU) | GUT `Time` | What dominates | Route |
|---|---|---|---|---|---|---|
| `test_fighter_squad.gd` | hand-ticked | 46.9 s | 46.4 s | 45.8 s | `test_members_never_come_within_two_hull_radii` 41.1 s (168 distinct layouts, the fighters' own tick) | **rule 4** (below): a bit-identical speed-up of the fighter tick (Ph8 t1 already did `_give_way()`; profile first) |
| `test_level1_specialist_spawns.gd` | hand-ticked probes | 31.7 s | 31.4 s | 30.2 s | `before_all()` ≈ 15 s (corvette / support / Mine Layer corridor probes), `test_migrated_sections_peak_alive_specialists_within_2_5x` 8.8 s and `test_measured_exits_are_real` 4.7 s (the first `_measured_exits()` calls) | **rule 4**: a cheaper probe step (`tests/README.md`: ≈ 7–11 µs per hand-ticked step; `EnemyWorld.projectile_world_rect()` looks the arena group up twice per call); rule 2 if a row recomputes a figure another already has |
| `test_missile_corvette.gd` | 8× | 7.07 s | 4.93 s | 5.79 s | `test_every_level1_corvette_spawn_telegraphs_and_fires_inside_its_budget` 3.6 s | rule 1 (16×) on the paced rows, ≈ 0.5–1 s |
| `test_fortress_weapons.gd` | 8× | 6.03 s | 5.09 s | 4.55 s | measured density row 1.4 s (CPU) | little |
| `test_sniper.gd` | 8× | 5.95 s | 3.91 s | 4.60 s | `test_every_level1_sniper_spawn_class_aims_inside_its_budget` 1.5 s, real-physics cover row 0.8 s | rule 1, ≈ 0.5–1 s |
| `test_space_fortress.gd` | 8× | 5.85 s | 3.79 s | 4.34 s | many 0.4–0.6 s rows | rule 1, ≈ 0.5–1 s |
| `test_hijack_pulse.gd` | 8× | 4.93 s | 2.80 s | 3.69 s | real line-of-sight rows (1.35 s, 0.5 s) | rule 1 (Ph10 found it 0.8 s faster at 16×, left at 8×) |
| `test_fighter.gd` | 8× | 4.09 s | 3.11 s | 3.02 s | — | little |
| `test_twin_laser_drones.gd`, `test_seeking_ordnance.gd`, `test_enemy_beams.gd`, `test_fortress_incoming_damage_paths.gd` | 8× | 2.8–3.2 s | 1.5–2.2 s | 1.5–2.0 s | — | ≤ 0.3 s each |

So rules 1–3 alone reach ≈ 2–4 s (Ph8 t1 and Ph10 t1 found the same: "rules 1–3 had nothing left to give"); the rest is CPU in code under test.

**t1's routes** (all keep every tick count, duration, sample grid, start set, bound and assertion unchanged):
- rules 1–3 of `tests/README.md` → *Gate time* (16× for a file whose wall ≫ CPU and whose rows tolerate a 16× idle frame; a replayed scenario computed once; per-tick bookkeeping no
  assertion reads dropped);
- **rule 4 (new, the Ph8 t1 route, Ph12 owner choice 8):** a production-code speed-up that is **bit-identical**, proven by (a) every figure the affected hand-ticked files print
  unchanged before / after and (b) a throw-away differential run (old against new code path over the files' own inputs, 0 mismatches), recorded in `tests/README.md` as rule 4
  and in `DECISIONS.md` (`### Phase 12, built in t1`). A cache must never go stale inside a hand-ticked loop (key on the node / input identity, never on the frame counter).
  Not a lever: `low_processor_mode_sleep_usec` / `override.cfg` (a behaviour change, Ph10 t1).

**t1 acceptance:** GUT two-run mean (`scripts/gate-time.sh`) ≥ **8 s** below the two-run mean measured at the task's start (target 10 s; raised from 6 s in revision 3 and
from 7 s in revision 4 because the allotments now total 18.4 s, round-2 N8 and round-3 P7), tests and asserts unchanged in number, the
gate green and leak-free (`scripts/check-test-leaks.sh`). If the inventory is exhausted below 7 s: keep what was freed if it is green and bit-identical, write the new measurements
into §*Gate time* of `tests/README.md`, and end the run with `Result: ESCALATE` naming what is left. **Only t8 depends on t1**: t2–t7 together add ≈ 8.8 s (225.2 → ≈ 234.0 s,
under 237 s), so the shared machinery, the shell and the movement can proceed while t1 runs or escalates.

**Allotments** (two-run means, new GUT seconds; revision 3 raised t3 0.3 → 0.4 for the head-test variant, t6 3.5 → 4.5 and t12 1.5 → 2.5 to match the measurements quoted in
§2.6.8 and §2.12, round-2 N8): t2 0.5 · t3 0.4 · t4 0.8 · t5 0.6 · t6 4.5 · t7 2.0 · t8 2.8 · t9 0.8 · t10 1.7 · t11 1.0 · t12 2.5 · t13 0.3 · t14 0.5 · t15 0
= **18.4 s** (revision 4 raised t8 2.0 → 2.8 for the mount-build cost in every earlier Dreadnought spawn, round-3 P7). Projection: 225.2 + 18.4 − t1. At t1's 8 s floor the
phase ends ≈ 235.6 s (≈ 1.4 s under 237); at its 10 s target ≈ 233.6 s. The margin is thin, so t1 writes
its result and the projection into `tests/README.md` → *Gate time*, every later task records its own measured cost there, and the existing rule holds: escalate past 1.5× an
allotment or a 237 s two-run mean (the owner then decides; nothing in this phase widens the 240 s ceiling).

### 2.16 Numbers and where they come from

| Value | Number | Source |
|---|---|---|
| Hull | 208 × 448 px | IDEAS §9 320–480; *judgement* beam (≈ the Carrier's ratio) |
| Cruise / turn | 120 px/s, 0.35 rad/s (radius ≈ 343) | F1 ratios to the 420 px/s player |
| Loiter radius / close band | 700 / 300 px | F2; broadside `fire_range` 900 |
| Jets | × 2.5 for 1.5 s, cooldown 8 s, stern arc ±40°, trigger 1.5 s | F1 *judgement* |
| One engine | speed 0.65, live-side turn 0.5, yaw bias 0.05 rad/s, drift 18 px/s → radii ≈ 200 / 640 px, ratio 3.2 | F3 *judgement*; Carrier `one_engine_*` precedent; chosen so the live side still turns (round-1 M1) |
| Crippled | thrusters 0.12 rad/s (× 1.5 critical), cooldowns × 0.6, cap 3 | *judgement*; Ph11 critical × 0.6 / cap 3 |
| Critical | core ≤ 35 %, speed × 1.15, cooldowns × 0.75 | Ph11 40 % *judgement* |
| Assault stadium | legs y 160 / 400, half-width 380, r 120 (derived), 90 px/s, turn cap 0.9 rad/s, lookahead 120 | fits the resting view 0–720 with the hull beam ±104 (round-1 M2) |
| Ram | wind-up 1.2 s (track 40 %), 560 px/s, overshoot 300, max 2.0 s, recover 2.0 s, cooldown 8 s, damage 35 (touch 25) | F4 derived; Ram Corvette 0.65 s / 620 / 220 / 50; player HP 50 |
| Ram line-up | turn at side rates × `jets_turn_factor` 2.5, speed × 0.5, aimed within 8°, cap 5.5 s (≥ 90° at the slowest rate + 0.25 s), abort → retry after 2.0 s; the charge runs along the nose | round-3 P1: the hull's own rates (0.125–0.35 rad/s) need 4.5–12.6 s for 90°; *judgement* tolerance / retry |
| Wake puff | r 40, life 3.0 s, every 48 px per live engine, 5 per 0.5 s, no damage in the last 0.5 s, ≤ 40 live | F5 *judgement*; `ReactorField` |
| Torpedo | 160 px/s, steers 3.0 s at 0.6 rad/s, then 320; **120 HP = 3 Standard shots** (Sniper 3, Spread 5, Gatling 9); blast 72 / 25; life 10 s / 2400 px; tube cooldown 7 s, telegraph 1.0 s | pursuit bomb scaled (*judgement*); HP from the shipped weapon-mode damages (round-1 B3) |
| Broadside | 3 HEAVY_CANNON per side (2 shells each: 6 per volley), 40° traverse, cooldown 3.2 s, ripple 0.25 s, fire turn cap 0.30 rad/s | Carrier 150° side batteries narrowed for the §24 sweep; cap from the fairness inequality 0.30 × 900 = 270 ≤ 0.8 × 360 (round-2 N3) |
| Missile fan | MISSILE_FAN: 5 DUMB over 40°, salvo 1, cooldown 6 s, own head `turret_head_missile_fan.png` 48 × 48 | `BurstCannonMount.pellets` precedent; head required by `test_ph8_sprites.gd` (round-2 N1) |
| Torpedo tube arc | ±55° about the bow (`traverse_deg_override` 110), bow-chaser, angles from the tube's pivot 196 px ahead of the hull centre | widened 30 → 90 (round-2 N6) → 110 so the Open Space approach window (d ≈ 1257 → 1000) is ≈ 2.6 s, not ≈ 1.2 s (round-3 P2) |
| Own-ordnance separation | own rockets (≤ 4 s) and own torpedoes (≤ 10 s) never in flight together; no own rocket live from LINE_UP to the end of CHARGE | collision facts of `enemy_rocket.gd` / `EnemyOrdnance` (round-2 N5) |
| Assault ram | overshoot 150 (Open Space 300), edge margin 16 px inside `EnemyWorld.projectile_world_rect()` | round-2 N10; levers overshoot 100, then 40° from vertical |
| Part HP | tube 200, rack 220, broadsides 260, generator 160, core 900, engines 240 | *judgement* against the fortress (core 900 incl. bubble) |
| Shield | capacity 120, regen after 3 s over 4 s, reboot 6 s, pad 10 | Ph11 sector shields |
| Escorts | 2 Gatling Interceptors per weapon death, cap 6 / 4 | Ph11 fortress caps; F7 |
| EMP | × 0.4 | Ph11 owner choice 6 |
| Hub | draw 22, 4800 ring at 135°, leash 1400, perceive 1100, lose 1800 / 4 s | fortress mirror; `2-research.md` §6 Q9; ring moved out so neighbours' anchors are ≈ 2596 px away, outside its 2500 px reach (round-2 N11) |
| Density | ≤ 13.3 /s mean, ≤ 30 per 2 s, ≤ 2 committed parts (3 critical / crippled) | Ph11 convention |
| Chunk | 60–90 px/s, life 2.5 s (fade 1.0 s), no collision | *judgement*; visual only (round-1 M9) |

### 2.17 Docs and phase close (t15)

Invoke `updating-project-docs`: `docs/architecture/modules/global.md` (*Boss reinforcements*: `ON_OWN_DESTROYED`; *Boss phase ladder*: a boss may run several tracks; hazards:
`EngineWake`, `damage_exempt_group`; mounts: `MISSILE_FAN`, `TORPEDO_TUBE`, per-part gates), `docs/architecture/modules/assault.md`, `docs/enemy-roster.md` (Dreadnought,
`WaveBuilder.dreadnought()`), `assault/scenes/enemies/dreadnought/ENEMY.md` (the IDEAS §43 checklist answered: silhouette, preferred distance 700 px, movement signature,
telegraphs, behind / boost-away behaviour, Assault adaptation), `docs/architecture/PROJECT.md` conventions, `CLAUDE.md` (the key-conventions boss line and the gate list: the
Dreadnought suites, the gate-time rule 4), `tests/README.md` gate time. Close the phase: `docs/epics-done/cmug256tc003lm52wbdoxucrr/` (`PRD.md`, `SOURCES.md`, `REPORT.md`) and
`## Phase 12 - as built (<date>)` in `DECISIONS.md` (what was built, deviations, owner choices as built, gaps; say plainly that nothing was play-tested).

## 3. Build sequence

| Step | Task | Depends on | Why this order |
|---|---|---|---|
| 1 | t1 gate room | — | frees ≥ 8 s (target 10); only t8 waits for it (t2–t7 fit under 237 s without it) |
| 2 | t2 bay trigger, t3 missile fan, t5 engine wake | — | shared machinery, bit-identical by default, testable on fixtures |
| 3 | t4 torpedo + tube | t3 | `TORPEDO_TUBE` = 10 is appended after `MISSILE_FAN` = 9 (one enum, one scene map) |
| 4 | t6 shell (scene, parts, armour, shields, two drivers, snapshot, rosters, incoming damage paths) | — | everything else hangs off the root; reuses only Ph10 / Ph11 machinery |
| 5 | t7 movement (incl. engine-loss rows, Assault stadium) | t6 | weapons, wake and ram read the heading model |
| 6 | t8 weapons (mounts, per-part gate, ripple, extreme phase, module-death rows) | t1, t3, t4, t7 | mounts need the fan and the tube and the brain's turn rate for the sweep |
| 7 | t9 wake on the boss | t5, t8 | brain file serialised after t8 |
| 8 | t10 critical ram (incl. the moving own-fire row) | t9 | brain file serialised; needs movement, weapons and the gate |
| 9 | t11 interceptor bays | t2, t10 | scene and brain serialised; needs the weapons |
| 10 | t12 measured density | t11 | measures the final mount set and every phase consequence |
| 11 | t13 art + detachment | t4, t12 | part sizes frozen by t6; edits `dreadnought.tscn` / `.gd` after every behaviour task (and after t12's possible lever edits) |
| 12 | t14 hub draw 22 | t11 | the full behaviour (leash, escorts) is what the sweep covers; independent of art |
| 13 | t15 docs and phase close | all | |

## 4. Test plan

| File | Task | What it proves |
|---|---|---|
| gate-time measurements, `tests/README.md` *Gate time* (rule 4) | t1 | ≥ 8 s freed, every assertion and figure unchanged |
| `tests/integration/test_boss_reinforcements.gd` (+9 rows) | t2 | §2.2 rows; every existing row unchanged |
| `tests/integration/test_turret_mount_variants.gd` (+ fan, + tube), `test_ph8_sprites.gd` HEADS | t3, t4 | §2.3 / §2.4 rows, ROCKET_BATTERY bit-identity, pool sizes for salvo × fan; each new variant's own distinct head (texture and silhouette) |
| `tests/integration/test_enemy_ordnance.gd`, `test_enemy_bullet_lifetime.gd` | t4 | torpedo defuse in damage units with real bullets and mode damages, steering window, lifetime fit read from the torpedo scene |
| `tests/integration/test_engine_wake.gd`, `tests/unit/test_hazards.gd` | t5 | §2.5 rows, `pulse_damage` exempt group, default bit-identical |
| `tests/integration/test_dreadnought.gd`, `test_dreadnought_incoming_damage_paths.gd`, `tests/helpers/dreadnought_fixture.gd`, roster gates | t6 | §2.6.7 / §2.6.8 rows, §25 paths, both drivers found, rockets / asteroids / mining laser reach parts |
| `tests/integration/test_dreadnought_movement.gd` | t7 | **engine loss changes movement** (both harnesses, on positions, ratio from the config formula), hunting arcs, jets, leash, Assault stadium |
| `tests/integration/test_dreadnought_weapons.gd` | t8 | **module death disables its attack** (both harnesses), 6-shell ripple, whole volley under a busy gate, fan, cap, extreme weapons, fairness at `cruise_speed()`, own-fire static row, an alive control per weapon, own rockets and torpedoes never in flight together |
| `tests/integration/test_dreadnought_wake.gd` | t9 | wake only behind live engines while engaged, outside the hull, never harms the boss or its escorts |
| `tests/integration/test_dreadnought_ram.gd` | t10 | **the critical ram** (both harnesses): order, frozen line, overshoot, damage window, no ram when crippled, Assault diagonal inside `projectile_world_rect()`, per-mode LINE_UP turn rates (side rates × `jets_turn_factor`) from the config, the charge always along the nose, the line-up cap sized from the config, abort and retry at the cap, fairness, no own rocket live while it rams, it overtakes its own torpedo harmlessly |
| `tests/integration/test_dreadnought_reinforcements.gd` | t11 | interceptors from the wreck, caps, none while dying, 3 s first fire |
| `tests/integration/test_dreadnought_density.gd` | t12 | measured Assault density per phase state against the frozen Ph11 bounds |
| `tests/integration/test_dreadnought_sprites.gd` | t13 | art sizes, transparency, wreck stumps, visual-only chunks |
| `tests/integration/test_sector_hub_patrol.gd` | t14 | draw 22 clears every trigger, pickup and the spawn; every other patrol anchor lies outside its reach |

Boundary cases named in the sections: ROCKET_BATTERY fan 1 / 0 bit-identical; a LINE_UP with a 0.5 s cap aborts, the shipped cap does not; a torpedo one hit short of its damage stays live; a non-breach bay still dies with its part; 36 %
core does not enter `critical`; a hit leaving both engines alive changes no snapshot key; with rack and tube committed an uncommitted broadside gets nothing; crippled + critical
never rams; no hazard container → no wake; a part killed during the death sequence launches and applies nothing; a plain layer-1 body blocks the beam.

## 5. Risks

- **Assault crowding**: a 448 px hull in a 1280 × 720 view. Mitigation: the stadium in the top half (hull ≤ y 504 at rest), broadsides silent in the U-turns, measured density per
  phase (t12), a ram lane with a fairness inequality. If the Assault feel is wrong it is a tuning lever; nothing places it in a level this phase.
- **The torpedo is rare** by design (a ±55° bow-chaser that also waits out the boss's own rockets): if play shows it almost never appears, widen `traverse_deg_override` on
  the tube slot (a config-free scene edit; t8 row 1's alive control and t12's density rows re-run). **Own-ordnance separation** costs some rack and tube shots and can delay a
  ram by up to a rocket's 4 s life; it is the price of a guarantee made without a shared-code change (a rocket-side skip cannot stop the target hurtbox's own damage).
- **The free order collapses** to one best order (F6). Mitigation: the gain / cost matrix (§2.6.4); not play-tested — the report must say so.
- **Interceptor spikes** when two weapons die close together (F7): capped live escorts and the one-chance breach.
- **Hazard count** while the wake runs (≤ 40 puffs per Dreadnought; every mover queries `Hazards.around()` when any hazard exists): t9 measures it; lever `wake_spacing` 48 → 64.
- **Shared-machinery regressions**: four opt-in additions; the fortress / carrier / turret / bomber / hazard suites must stay unchanged and green.
- **Gate time**: t1 may fall short of 8 s (the inventory shows most time is CPU in code under test); rule 4 needs a careful differential proof. Only t8 onward waits on it. Even at
  8 s the phase ends ≈ 235.6 s, ≈ 1.4 s under the 237 s escalation line: a task that overruns its allotment can push the gate over it and stop the chain for an owner decision.
  The largest single new cost, the eight mounts built in every Dreadnought spawn, is charged to t8 (2.8 s) and has a pre-approved lever (`opts.bare` for movement rows).
- **Ram line-up**: the nose comes on at the jets rate, but a listing Dreadnought turning toward its live side needs ≈ 5 s for 90° in Open Space; a player who keeps to its live side
  can make it abort (`ram_aborts()`) and retry every ≈ 7.5 s. That is intended counterplay for killing one engine, not a defect; if play shows the ram almost never lands, the
  lever is `jets_turn_factor` for LINE_UP only (a new `ram_line_up_turn_factor`), never a charge off the nose.
- **Per-part gate**: a mount that misses its ripple slot (cone, arc) starts later inside the same committed side, so a volley may arrive as fewer than six shells; row 2 sets up a
  player in every mount's arc and cone so the six-shell figure is deterministic.
- **Hub**: a hunter that wanders to the spawn or a mission trigger breaks the hub; the leash and the sweep's footprint guard it, with levers.

## 6. Out of scope

| Item | Owner | Reason |
|---|---|---|
| Placing the Dreadnought in a level (and an `ENEMIES_CLEARED` persistent-ordnance exception for it) | Ph15 (Ph12 owner choice 4) | Assault level migration is Ph15's; the rack and tube pools persist, so an `ENEMIES_CLEARED` placement would be a third allowlisted exception, decided then |
| Enemy beams / rings damaging parts; wrecked parts / capital wrecks blocking LOS; damaging boss debris | Ph18 / Ph19 | Ph10 / Ph11 deferrals; the detach chunk is visual only |
| Carrier / Heavy Gunship onto the boss machinery | Ph18 | |
| Encounter compositions, escort leash in Open Space beyond the cap | Ph13 / Ph14 | |
| Difficulty tiers | Ph16 | |
| Boss / part HUD, per-part score, audio | Ph17 | IDEAS §6.11 "not one giant HP bar" |
| EMP dropping boss shields | Ph18 | Ph11 deferral |
| A capital wreck on the Dreadnought's death | Ph19 | `wreck_chance` 0 like the fortress |
| Assault stadium following the player's x or the camera's vertical pan (with a low player the upper leg leaves the view and holds fire, round-3 P3) | Ph15 | corridor-constrained AI is Ph15's; the stadium is world-anchored; documented as a known limit in `ENEMY.md` |

## 7. Requirements coverage

| Requirement (from `1-context.md`) | Delivered by |
|---|---|
| R1 size 320–480 px | t6 (448 px hull), t13 art |
| R2 hunts the player (opposite of the fortress) | t7 |
| R3 central hull + detachable turret, missile, shield, engine modules | t6 parts, t13 wreck stumps and detach chunks |
| R4 long arcs, two huge bodies manoeuvring | t7 heading model, loiter circle, jets |
| R5 broadside sweep, missile fan, energy torpedo, engine wake, critical ram | t8 (+ t3, t4), t9 (+ t5), t10 |
| R6 §24 broadside cannons, exhaust trails | t8 ripple sweep on the hull turn, t5 / t9 wake |
| R7 free order, no prompt | t6 (no locks, two tracks), §2.6.4 matrix |
| R8 one engine → visibly lopsided movement | t7 (measured on the path), t6 visuals |
| R9 both engines → stationary + extreme weapons | t7 HOLD, t8 crippled attacks, t12 measured |
| R10 interceptors from a destroyed weapon module | t2, t11 |
| R11 §25 every phase changes ≥ 2, incl. final ram | t6 drivers and rows, t7–t10 keys |
| R12 §26 destruction changes the battlefield | t8 (UNPOWERED), t7 (engines), t9 (wake), t6 (shields) |
| R13 art from modules, wreckage stays | t13 |
| R14 readability lights, edge light, no full recolour | t13, t6 / t8 `StateLight` |
| R15 §40 tests in both harnesses (engine loss, module death, ram, core vulnerable when intended, wreckage) | t7, t8, t10, t6, t13 |
| R16 §41 Phase 5 item 2: on the module architecture | t6 (`EnemyModule`, `ModularHull`, `global/boss/`) |
| R17 Assault adaptation in the corridor + Open Space placement | t7 / t8 / t10 / t12 Assault rows, t14 hub; level placement out of scope (Ph15) |
| R18 §43 checklist | t15 (`ENEMY.md`); audit Ph17 |
| R19 a heavy dreadnought partially resists a gravity well | t6 (`hazard_resistance` 0.85) |
| R20 torpedo family | t4 (an `EnemyOrdnance` scene) |
| Gate time (project constraint) | t1, §2.15 |

## 8. Response to feedback (plan reviews, `4-review.md`)

### 8.1 Round 1 (B1–B4, M1–M10), answered in revision 2

| # | Finding | What changed |
|---|---|---|
| B1 | The fan rack had no authoring path before its pools are sized | New `TurretMount.Variant.MISSILE_FAN` = 9 with a standalone `missile_fan_mount.tscn` on `rocket_battery_mount.gd` (the `HEAVY_CANNON` precedent); t3 builds it and pins its pool sizes for salvo × fan at factors 1.0 and 0.45; `TORPEDO_TUBE` moves to 10 and t4 depends on t3 (§2.3, §2.4, §2.8) |
| B2 | One shared zero-argument gate shrank the broadside | Per-part gates: after `build_mounts()` the root sets `mount.telegraph_gate = brain.attack_gate_for.bind(part_id)`; a committed part is allowed, spacing enforces the ripple; new row 3 (whole 6-shell volley while the rack fires, boundary with rack + tube) (§2.8, *For every task*) |
| B3 | Torpedo health was in hits, not damage | `max_health` 120 in damage units: 3 Standard / 3 Sniper / 5 Spread / 9 Gatling; defuse rows with real player bullets and with damages read from the mode `.tres` files, plus a one-hit-short boundary (§2.4; owner choice 9) |
| B4 | Gate-room target ungrounded and blocking the chain | Measured inventory in §2.15 (wall vs CPU per file); target ≥ 6 s (need ≈ 3.7 s) with an explicit escalation path; rule 4 (bit-identical code speed-up, the Ph8 t1 route) allowed (owner choice 8); only t8 depends on t1, t6 no longer does |
| M1 | One-engine ratio contradicted the numbers; listing could pick an unholdable orbit | Expected ratio is the config formula `(turn_rate + bias) / (turn_rate × live − bias)`; live turn 0.35 → 0.5 and bias 0.08 → 0.05 so the live side still turns; in `listing` the orbit is forced toward the dead side; config-invariant row (§2.7.2, §2.7.4) |
| M2 | Assault racetrack return leg above the screen | Replaced by a stadium (legs y 160 / 400, derived radius 120, pure pursuit), fully inside the resting view; listing overshoot measured (§2.7.3) |
| M3 | A side volley is 6 shells, not 3 | Rows count `3 × burst_count` read from the mounts and time the first shell of each mount (§2.8) |
| M4 | `quiet` wrote cooldowns the brain does not read | `quiet` = attack caps 0, escort caps 0, `ram_first_delay` 1e6; the fortress `_tick` pattern named in the fixture (`hand_tick`) and in *For every task* (§2.6.1) |
| M5 | t12 dependencies incomplete; plume owned twice | Art (now t13) depends on t4 and t12 (after every scene/brain edit); the tube head moves into t4; `Plume` belongs to t13 alone, t9 adds only `WakePoint`s (§2.9, §2.13) |
| M6 | No incoming-damage or self-hit rows | New `test_dreadnought_incoming_damage_paths.gd` in t6 mirroring the fortress file (§2.6.8); own-fire static row in t8 and a moving real-physics row in t10 (§2.8, §2.10) |
| M7 | Wake and interceptor tasks lacked the geometry section | §2.9 and §2.11 now repeat the part positions, hull rectangle, wake points and mouths; t9 and t11 also list §2.6.2 |
| M8 | Torpedo registration vague | Named const `EnemyOrdnanceScenes.ENERGY_TORPEDO`, not in `scene_for()`; a lifetime row instantiates it directly (§2.4) |
| M9 | Detach chunk was a damaging hazard | The chunk is a purely visual `top_level` child of the Dreadnought: no collision, no hazard, no damage, self-freeing (§2.13) |
| M10 | Weapons task close to two tasks | Measured density split out as t12 after the interceptors (§2.12); t8 keeps mounts, gate, ripple, extreme phase, fairness and module-death rows |

### 8.2 Round 2 (N1–N11) and the owner's CHANGES_REQUESTED, answered in revision 3

The owner's CHANGES_REQUESTED carried no text of its own; it is read as endorsing the round-2 AI review, and every point of that review is answered below. Nothing else in the
design changed.

| # | Finding | What changed |
|---|---|---|
| N1 | `MISSILE_FAN` reused the rocket battery head, which `test_ph8_sprites.gd` forbids | t3 draws its own `turret_head_missile_fan.png` (48 × 48, a wide five-tube rack, distinct silhouette) through `pixel-art-generation` and wires it like every head; t3 is now **medium**; §2.3, §2.13, §2.16, *For every task* |
| N2 | Torpedo lifetime row used the one-speed formula (15 s > 10 s) | The row uses the file's `_two_speed_kind_clears()` with values read from the torpedo scene and the tube: 3.0 + 1920 / 320 = 9.0 s (≈ 9.2 s with the ramp) ≤ 10 (§2.4) |
| N3 | Broadside sweep fairness failed for the Assault fighter (315 > 288) | `broadside_fire_turn_cap` 0.35 → **0.30** (270 px/s); player speed defined as `cruise_speed()` (fighter 360, Open Space 420) in *For every task*, §2.8, §2.10, §2.16 |
| N4 | Ram row 5's fixed ≥ 2.5 failed in Assault (2.375) | Row 5 asserts the per-mode config formula `(rate + bias) / (rate × live − bias)` with `rate` = `turn_rate` / `assault_turn_rate`, within 10 %, plus ratio > 1 (§2.10) |
| N5 | Own rockets can hit the own torpedo and the charging hull; row 8 vacuous or unsatisfiable | Gate rule 2 keeps own rockets and own torpedoes **never in flight together**; the rack is refused from LINE_UP to the end of CHARGE and LINE_UP waits for no live own rocket; rows: separation both orders + a stress (t8 row 11), a characterisation that the collision is real (t8 row 12), a realistic ram-overtakes-own-torpedo row with a not-vacuous check and a pre-approved fallback (t10 row 8). The reviewer's second fallback (an owner-group skip on the rocket) is rejected with the reason: the target's `HurtBox` applies the damage itself (§2.8, §2.10) |
| N6 | Tube arc rarely holds the player; row 1 could not fail for it; density figure wrong | Tube arc widened to ±45° and documented as a **bow-chaser** (when it fires, in both modes); row 1 has an alive control per weapon with the player placed in its arc; sanity figures corrected to ≈ 2.2 /s and ≈ 4 /s (§2.8, §2.12, §2.7.3, §5) |
| N7 | "Rack committed (in FIRE)" is impossible for a one-salvo mount | One-salvo mounts are committed only in TELEGRAPH (stated with the mechanism); row 3 puts the rack in TELEGRAPH overlapping the port ripple; its boundary rewritten because rule 2 forbids rack + tube together (§2.8) |
| N8 | t6 and t12 allotments below their own measurements | t6 3.5 → 4.5 s, t12 1.5 → 2.5 s, t3 0.3 → 0.4 s; total 17.6 s; t1's floor raised 6 → 7 s (target 9) so the phase ends ≈ 235.8 s at worst; risk restated (§2.6.8, §2.12, §2.15, §5, owner summary) |
| N9 | t12 lacked the Assault geometry and the fixture sections | t12's planSections gain 2.6.1 and 2.7, and §2.12 repeats the stadium numbers and names `ladder()` / `kill_part()` |
| N10 | Assault ram overshoot unbounded, rect unnamed | `assault_ram_overshoot` 150 and an `edge_limit` that stops the charge with the bow 16 px inside `EnemyWorld.projectile_world_rect()` (x −164…1444, y −444…1164); row 6 checks the four hull corners from six player positions incl. the lowest; levers overshoot 100, then 40° (§2.10) |
| N11 | Hub hunting zone 2055 px from two patrol anchors | Ring 4200 → **4800** (≈ (−3394, 3394)): both neighbours ≈ 2596 px away, outside its 2500 px reach; a new sweep row keeps every other anchor outside it; a chase dragging it into a neighbour's fight is stated as intended (Ph13 / Ph14 own encounters); levers re-ordered so none breaks the new row (§2.14) |

### 8.3 Round 3 (P1–P8) and the owner's second CHANGES_REQUESTED, answered in revision 4

The owner's second CHANGES_REQUESTED again carried no text. The round-3 reviewer pointed out that reading the first one as "fix the AI review's points" was an assumption; this
revision makes the same reading of the second one, says so, and asks the owner directly (owner summary, choice 10) to write down anything else they meant. Nothing outside
P1–P8 changed in the design.

| # | Finding | What changed |
|---|---|---|
| P1 | The ram's 3.0 s LINE_UP could not turn a 0.125–0.35 rad/s hull 90° (4–12 s), the cap's outcome was undefined, row 5 could not pass | LINE_UP turns at the side rates × `jets_turn_factor` 2.5 (90°: 0.66–5.03 s) at speed × 0.5 and ends when the nose is within 8° of the (Assault-clamped) aim; `ram_line_up_cap` 3.0 → **5.5 s**, sized by a config row (≥ π/2 ÷ the slowest LINE_UP rate + 0.25 s, per mode); at the cap and not aimed the cycle **aborts to HUNT** (`ram_aborts()`, no lane, no damage change) and retries after `ram_retry_delay` 2.0 s; `charge_dir` = the heading at the freeze and the heading is held through CHARGE, so the charge always runs along the nose and the lane from the bow; row 5 compares the measured turn rates over the first 0.5 s against the config formula per side and mode; new row 10 (cap config row, abort with a 0.5 s cap, boundary with the shipped cap); a risk line on live-side denial (§2.10, §2.16, §4, §5) |
| P2 | The torpedo window was computed from the hull centre, not the tube's pivot 196 px ahead | Every tube angle and range now measured from the tube's pivot, with the formula; the slot is widened 90 → **110** (±55°), so the Open Space approach window is d ≈ 1257 → 1000, ≈ 2.6 s (≈ 1.2 s at ±45°); the Assault left-end window restated (≈ 2.6 s of the 4.2 s U-turn); `ENEMY.md` gets the same text (§2.8, §2.12, §2.16, §5) |
| P3 | The Assault stadium leaves the view when the camera pans down with a low player | Recorded as a known Assault limit in §2.7.3 (with the view-top figures at y 650 and the level-1 start), in `ENEMY.md` by t7 and in `DECISIONS.md` / the report by t15, and in §6 as Ph15's; no real-physics lap row (≈ 3 s of gate time for unchanged behaviour), and the hand-ticked density rows are noted as the conservative worst case |
| P4 | t4 lacked the head-art rules of §2.3 | §2.4 repeats them (wiring, transparency, texture and silhouette distinctness, `MIN_MASK_DIFF` 0.08) and t4's planSections gain 2.3 |
| P5 | t8, t10, t11 lacked the fixture section | §2.8, §2.10 and §2.11 rows name the fixture helpers; all three tasks' planSections gain 2.6.1 |
| P6 | The bearing lever always broke the neighbour row | Allowed only together with a ring of at least 5200 (≈ 2721 px to the nearer neighbour at 125° / 145°), §2.14 |
| P7 | t8's 2.0 s left out the eight mounts built in every earlier Dreadnought spawn | t8's allotment 2.0 → **2.8 s**, measured as the whole-suite delta; a pre-approved `opts.bare` fixture lever for movement rows; t1's floor 7 → **8 s** (target 10); total 18.4 s; projection ≈ 235.6 s at the floor (§2.6.1, §2.8, §2.15, §5, owner summary) |
| P8 | Ram row 2's charge cap (1120 px) bound beyond ≈ 820 px | Row 2 places the player 700 px from the hull centre (≤ 800), asserts neither cap bound, and names the **hull centre** as the point that passes `charge_point` (the aim's projection onto the charge line) (§2.10) |
