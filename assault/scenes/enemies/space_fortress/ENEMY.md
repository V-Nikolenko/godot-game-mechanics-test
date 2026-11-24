# Space Fortress — the 360 degree boss you take apart sector by sector

**Role:** Phase 11's boss (Space Fortress 2.0), built to be fought by circling it rather than from below. It replaces level 1's legacy space station
(t10 places it in `station_assault`; t13 adds it to the Open Space hub). **Never call it a "station"** in code, nodes or docs: Open Space already has
"Fortuna Space Station" (a `MissionTrigger`).
**Fantasy / threat:** a ring fortress whose hull is armour. Five gun batteries sit on the ring, each with its own attack and its own angle; two shield
generators keep a bubble on the batteries and the hangar of their half; the core stays plated until both generators are gone. Destroying a battery
removes an attack angle; destroying a generator bares a whole sector; every phase changes how the fight plays.

Plan: `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.5 (t5, this shell), §2.6 (t6 movement), §2.7 (t7 batteries, t16 geometry weapons), §2.8 (t8 bays),
§2.9 (t9 art). Task plans: the shell `docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md`, the movement `docs/plans/cmwt4y3hk00ssqs2ybengu81w/3-plan.md`, the geometry
weapons `docs/plans/cmwt4y3hq00t0qs2ysigzomnw/3-plan.md`.

**Built so far:** t5 the shell (hull, parts, sector shields, phase ladder with its vulnerability and visual consequences, death, EMP, homing, roster
gates); t6 the movement (facing rule, spins, Open Space combat zone, Assault hold and bob; `is_engaged()`); t7 the five batteries and the attack gate;
t16 the geometry weapons (hull spokes, ring pulse, core bullet ring), their fairness rows and the measured Assault density; t8 the reinforcements (§Reinforcements).
**Not yet:** art is placeholder station PNGs (t9); the spokes and the ring are code-drawn (`Line2D` / `_draw`).

---

## Stats

| Property | Value |
|---|---|
| Hull | circle r 176 (`CircleShape2D`, one sub-resource shared by the body, the root `HurtBox` and the `ContactHitBox`); root body layer 0 / mask 0 (blocks nothing, the mining laser included) |
| Hull HP | `core_health` 1500 (root `Health`, the death plumbing): no hit ever lowers it; it drops to 0 only when the core dies |
| Contact | 40, `ContactProfile` ARMOR with `shove_speed` 260 |
| Score | 1500, `counts_toward_wave_clear` / `counts_as_escape` true, `wreck_chance` 0 |
| Death | `death_sequence_duration` 2.4 s, `death_blast_count` 10, `DeathSequence` (`BossDeathSequence`) `blast_spread_radius` 150 |
| EMP | every source's window × `emp_factor` 0.4; a no-op while dying |
| Scene / config | `space_fortress.tscn`, `space_fortress_config.tres` (`SpaceFortressConfig`, flat) |

## Parts (`Modules/*`, `EnemyModule`s; `ModularHull` beside them)

Local bearing 0 degrees = +x, 90 = +y (screen-clockwise). Every part lies inside the hull circle. Each part has `Sprite`, `HurtBox`, `HomingPoint`
(its centre) and `Light` (`StateLight`); `hull_share` 0 everywhere. HP comes from the config (written by the root over the scene's values).

| Part | id | Role | Centre | Hurtbox | HP | Starts | Sector |
|---|---|---|---|---|---|---|---|
| `BatterySpread` | `battery_spread` | WEAPON | (99, 99) | circle r 22 | `battery_health` 260 | open | south |
| `BatteryPulse` | `battery_pulse` | WEAPON | (−99, 99) | circle r 22 | 260 | open | south |
| `BatteryArtillery` | `battery_artillery` | WEAPON | (−99, −99) | circle r 22 | 260 | open | north |
| `BatteryMissiles` | `battery_missiles` | WEAPON | (99, −99) | circle r 22 | 260 | open | north |
| `BatterySweep` | `battery_sweep` | WEAPON | (150, 0) | circle r 22 | 260 | open | south |
| `Hangar` | `hangar` | HANGAR | (−150, 0) | rect 36 × 56 (x radial) | `hangar_health` 300 | locked (doors, t8) | north |
| `ShieldNorth` | `shield_north` | WEAK_POINT | (0, −120) | circle r 26 | `shield_node_health` 360 | locked until `shields_exposed` | — |
| `ShieldSouth` | `shield_south` | WEAK_POINT | (0, 120) | circle r 26 | 360 | locked until `shields_exposed` | — |
| `Core` | `core` | CORE | (0, 0) | circle r 44 | `core_health` 1500 | locked until `core_exposed` | — |

**The armoured hull** (the Carrier's rule). `deflects_hit()` / `is_armored()` always answer true, so a player projectile crossing the hull is never consumed
by it and reaches whichever part lies on its path; the root refuses every hit with a white flash and `armor_deflected(damage)`. A locked part pings and
refuses bullets, rockets, the beam and the nova alike. **The core's death is the fortress's** (`health.set_health(0)` on the root).

**Sector shields** (`ShieldSector`, `global/boss/shield_sector.gd`). `shield_north` keeps a 360 degree bubble on the artillery, missile and hangar parts,
`shield_south` on the spread, pulse and sweep batteries: `sector_shield_capacity` 120 (about three default bullets; a shield stops the bullet it absorbs),
regen after `sector_shield_regen_delay` 3 s over `sector_shield_regen_seconds` 2 s, reboot `sector_shield_reboot_seconds` 5 s after a break, radius = hurtbox +
`sector_shield_pad` 8. A generator's death bares its sector for good, in the same call; a protected part's death frees its own bubble. A locked part's bubble
absorbs nothing (the hangar is covered only while its doors are open). The player beam and the nova bypass bubbles (direct emitters, the Ph5 rule). The
generator's light shows `SHIELDED` (cyan) while it lives.

## Phase ladder (`PhaseDriver`, `BossPhaseDriver` + four `BossPhase` sub-resources)

One way, in order; IDEAS §25: every phase changes at least two aspects (`test_boss_phase_rules.gd`), and `phase_snapshot()` shows each one.

| # | Phase | Trigger | Declared changes | Consequences built so far (t5, t6) |
|---|---|---|---|---|
| 0 | `batteries` | START | — | shutters closed, plating closed, generator lights SHIELDED; hold, facing rule |
| 1 | `shields_exposed` | 2 WEAPON parts destroyed (`shields_exposed_battery_losses`) | VULNERABLE, ATTACKS, MOVEMENT, REINFORCEMENTS, VISUALS | both generators open (deferred), shutter art opens; spin mode `volley`; spoke volleys armed (Spoke0 + Spoke1 every 8 s, the hull spinning while they are lit) |
| 2 | `core_exposed` | both generators destroyed | VULNERABLE, MOVEMENT, ARENA, VISUALS | core opens (deferred), plating art opens (never over a wreck), `Thrusters` shown; translation starts (Open Space REPOSITION every 8 s at 60 px/s, Assault bob at 35 px/s); the ring pulse armed (every 6 s) |
| 3 | `critical` | core ≤ 40 % (`critical_core_ratio`) | MOVEMENT, ATTACKS, REINFORCEMENTS, VISUALS | `CriticalOverlay` shown, core light blinks COMMIT / OFF every `core_blink_period` 0.25 s; continuous spin at 0.6 rad/s, REPOSITION every 5 s at 90 / bob at 55; battery cooldowns x 0.6, gate cap 3; all four spokes every 6 s, the ring every 3.5 s, the core bullet ring every 2 s |

The scene's `count` / `health_ratio` must equal the config's (a row checks it). Attack and arena consequences (t7, t16) and reinforcement ones (t8)
go through `FortressBrain.on_boss_phase()`. A phase stepped while the fortress is dying applies nothing.

**`phase_snapshot()`** — six keys (`movement`, `attacks`, `vulnerable`, `arena`, `reinforcements`, `visuals`) built only from phase-driven state, never
from which parts are alive, so the kill that triggers a phase never counts as one of its changes. `visuals` reads the fortress's own fields (shutter and
plating textures, the generator light it keeps, the core light *mode*), not the live sprites or lights: a wreck turns its own light off and a blinking light
alternates. `movement` is `[translation_mode, spin_mode, reposition_period, travel_speed]` — the brain's per-boss-phase settings: Open Space `[hold, face,
0, 0]` → `[hold, volley, 0, 0]` → `[reposition, volley, 8, 60]` → `[reposition, continuous, 5, 90]`, Assault the same with `[bob, volley, 0, 35]` →
`[bob, continuous, 0, 55]` (t6). `attacks` = `[cooldown_factor, max_concurrent_attacks, spoke_count, spoke_period, core_ring_armed, core_ring_period]`:
`[1.0, 2, 0, 0, false, 0]` → `[1.0, 2, 2, 8, false, 0]` → (unchanged in `core_exposed`) → `[0.6, 3, 4, 6, true, 2]`; `arena` = `[ring_pulse_armed, ring_period]`:
`[false, 0]` → `[false, 0]` → `[true, 6]` → `[true, 3.5]` (t7, t16). `reinforcements` = `[sorted ids of the bays the ladder has activated, escorts the surge queued on entering this phase]`: `[[north_defenders, south_defenders], 0]` → `[[hangar, north_defenders, south_defenders], 0]` (the hangar bay activates) → unchanged → `[[...], 4]` (the `critical` surge; `0` with the hangar dead, a dead bay stays listed) (t8).

## Batteries (t7)

Five battery mounts, one per battery part, built by `ModularHull.build_mounts(self, rng, owner_group, brain.attack_gate, 0)` from each battery's `MountSlots/Slot0`
(`TurretMountSlot`). Pools are root children of the fortress (their container is its parent); indices run 0..4 in module order.

| Battery | Variant | Rest | Traverse | Pools |
|---|---|---|---|---|
| `battery_spread` | SPREAD_CANNON | 45° | 100° | `PulsePool_0` (Scatter) |
| `battery_pulse` | RAPID_PULSE | 135° | 100° | `PulsePool_1` (Pulse) |
| `battery_artillery` | HEAVY_CANNON | 225° | 100° | `PulsePool_2` (Heavy Shell) |
| `battery_missiles` | ROCKET_BATTERY | 315° | 100° | `DumbPool_3`, `PursuitPool_3` (persist) |
| `battery_sweep` | SWEEP_BEAM | 0° | 140° | none (owner-ticked beam) |

- **Diagonal crossfire.** The four corner mounts cover their own diagonal lanes (100° arcs; straight north, south, east of the ring fall between arcs by
  design); a destroyed battery is UNPOWERED by its part, so **its lane goes quiet** (§26). A 300 px player on a diagonal is fired on by that corner only.
- **`attack_gate()`** (zero arguments: `TurretMount` calls `telegraph_gate.call()`): true while fewer than `max_concurrent_attacks` 2 (`critical_max_concurrent_attacks`
  3 in `critical`) battery mounts are in TELEGRAPH or FIRE (the asking mount is still in TRACK). Never a wall of five bursts.
- **Who may fire** (`FortressBrain._tick_weapons`, the Carrier's rule): only `is_engaged()` (HOLD / REPOSITION, both modes), not inside an EMP window, in Assault only with
  the hull centre inside `EnemyWorld.view_rect()`, and with line of sight (physics frame only; a hand-ticked row counts it clear) or a mount that
  `fires_past_cover()` (the rocket battery). Otherwise every mount scans.
- **`critical`**: every live battery mount's `cooldown_seconds` x `critical_cooldown_factor` 0.6, once, on the instanced nodes (the shipped mount scenes are untouched).
  **Pools are sized for that period**: each battery slot authors `TurretMountSlot.pool_period_factor` 0.6 (equal to the config factor, pinned by a row), the
  builder copies it onto `TurretMount.pool_period_factor` (default 1.0, bit-identical for every other mount) and every `pool_specs()` multiplies its period by it
  (the heavy cannon needs 10 shells at its 2.97 s critical period, not 6). 30 s of critical fire per battery refuses no shot (`shots_refused` / `rockets_refused` 0).
- **EMP**: `on_emp_started()` scans every mount (`scan(0.0)`); nothing fires until the window ends. **Death**: every mount `power_down()`s.
- **Persistent ordnance — the second bounded exception.** The `ROCKET_BATTERY` pools are `persist_after_owner_death`, so a rocket in flight outlives the fortress by at
  most its `max_time`. Like the Ph10 Heavy Gunship, the fortress is therefore an exception to the rule that persistent-ordnance enemies stay out of `ENEMIES_CLEARED`;
  its tail after death is `death_duration` + the rocket `max_time` (t10 adds the `test_engagement_deadline.gd` row that names it).
- `phase_snapshot()[&"attacks"]` = `[cooldown_factor, max_concurrent_attacks, spoke_count, spoke_period, core_ring_armed, core_ring_period]`: the batteries own the first two
  (`[1.0, 2, ...]` until `critical`, `[0.6, 3, ...]` in it); the geometry weapons the rest.

## Geometry weapons (t16): the shape is the weapon

All three are owner-ticked by `FortressBrain` (no `Timer`, no `_process`), fire only while `is_engaged()` with a target and, in Assault, the hull centre in
`EnemyWorld.view_rect()`, and spare the owner set (the fortress and its owner group `fortress_<id>`, escorts included; parts are never victims: they are in
`enemy_parts` only). **Clocks:** a weapon armed by a phase waits one full period before its first shot; a period that shortens (`critical`) keeps the countdown
already run (min of the two); a due weapon that may not fire waits at 0. **Tick order** in `FortressBrain.tick()`: battery mounts, then every spoke and the ring
(`tick(delta)`, their only clock), then the countdowns (a new shot's first tick is the next frame), then the volley spin.

| Weapon | Nodes / scene | From | Period | Tuning (authored in its own scene, gated from an instance) |
|---|---|---|---|---|
| **Hull spokes** (rotating hull beams) | `HullBeams/Spoke0..3` (`Node2D` emitters on the hull edge r 176 at local 270° / 90° / 0° / 180°, each pointing outward) + a `Beam` child, `fortress_spoke_beam.tscn` (inherits `enemy_beams/beam.tscn`) | `shields_exposed`: Spoke0 + Spoke1 (`spoke_count` 2) | `spoke_period` 8.0 s; `critical`: all four every `critical_spoke_period` 6.0 s | BEAM, telegraph 1.2 s, active 2.5 s, fade 0.15, length 900, damage 14, `rehit_interval` 0.55, telegraph line 4 px, `registers_hazard` (a `&"laser_wall"`, exempting the owner group) |
| **Ring pulse** (arena control, §25 ARENA) | `PulseRing`, `fortress_pulse_ring.tscn` (inherits `enemy_beams/energy_ring.tscn`), centred on the hull at its start | `core_exposed` | `ring_period` 6.0 s; `critical` 3.5 s | `max_radius` 640, 300 px/s, band 24, two 50° gaps turning at 30°/s (start drawn from the brain's rng), damage 14, telegraph 1.0 s |
| **Core bullet ring** (the station's, kept per IDEAS §39) | `CoreRingPool` (`BulletPool` of `enemy_bullet.tscn`, a direct root child built in code in `_ready()`, so its rounds live in the fortress's parent container) + a runtime `RadialAttackPattern` | `critical` only | `core_ring_period` 2.0 s | 12 rounds (`core_ring_count`), 10 damage, 210 px/s, from 60 px off the centre; the base angle (absolute, world) advances `core_ring_step` 0.24 rad per ring, so five rings fall on five lanes with the widest gap 0.375 of the spacing |

- **Volley spin** (edge-triggered): when a spoke the volley's `start()` actually moved to TELEGRAPH turns ACTIVE, the brain calls `begin_spin(0)` (alternating direction)
  and the hull sweeps the beams at `beam_spin_rate` 0.5 rad/s; when none of them is ACTIVE any more, `end_spin()`. A spin started by hand is never ended by it. In
  `critical` the continuous spin (0.6 rad/s) owns the facing.
- **`CoreRingPool` size** = `EnemyRounds.pool_size_for(core_ring_count, life, core_ring_period)`, `life` = min(the round's `max_time` 18, `max_distance` 2400 / 210) = 11.43 s,
  read from `enemy_bullet.tscn` (`SpaceFortress.core_ring_pool_size()`): **72** (a fixed 48 would run dry; sized on `max_time` alone it would need 108).
- **EMP**: `on_emp_started()` also cancels every spoke and the ring (a telegraph goes OFF, a lit one fades) and ends the volley spin; the core ring is left alone (its rounds keep
  flying; its clock freezes because the brain is not ticked). **Death**: `silence()` cancels the spokes and the ring and frees every core-ring round in flight
  (`cancel_active()`). **The fade tick:** `SpaceFortress._physics_process` runs `BaseEnemy`'s tick and then, while the brain is not ticked (an EMP window or the death
  sequence), ticks each spoke and the ring that is in FADE (`FortressBrain.tick_fades()`) on to OFF.
- **Fairness** (gated from instances): a spoke tip 250 px off the hull moves at `spin_rate × (176 + 250)` = 213 / 256 px/s ≤ 0.8 × either player's cruise speed;
  telegraphs ≥ 1.0 s and ≥ 3 px; `rehit_interval` 0.55 > the players' 0.5 s i-frames; a ring gap at its narrowest (the hull edge + the player's hurtbox radius: 11 px ship,
  13.5 px fighter) is ≥ two player widths (a 15° gap fails for the fighter).
- **Measured Assault density** (§2.7.6; the real fortress at (640, 180), hand-ticked, engaged, every launch counted from the battery, rocket and core-ring pools and returned at
  once; ceilings: mean ≤ 13.3 rounds/s, peak in any half-open 2 s window ≤ 30). Worst of the five player positions (S, SW, SE, W, E) per phase (identical over
  repeated runs):

  | Phase (live batteries) | Worst position | Mean (rounds/s) | Peak 2 s window |
  |---|---|---|---|
  | `batteries` (all five) | W | 1.9 | 10 |
  | `shields_exposed` (sweep + missiles dead) | E | 2.5 | 10 |
  | `core_exposed` (sweep + missiles dead) | E | 2.1 | 10 |
  | `critical` (sweep + missiles dead) | E | 8.2 | 23 |

  Every row is inside both ceilings with the shipped tuning, so no lever was pulled (the order would have been `core_ring_period` 2.0 → 2.5, `critical_cooldown_factor`
  0.6 → 0.7, `critical_max_concurrent_attacks` 3 → 2). The planned upper bound (14.5 /s in `critical`) assumed every mount in arc and in range at once; from any one
  position the 100° arcs and ranges leave at most two or three batteries on the player, and the gate spaces them. Escort rounds are not in this count (the station's
  legacy rate excluded its reinforcements too); the escorts are bounded by their caps (6 / 4) and their own configs, not measured here.

## Reinforcements (t8)

Three scene-authored `ReinforcementBay`s on parts (`BossReinforcements`, §2.2 of the shared machinery in [global.md](../../../../docs/architecture/modules/global.md)),
ticked by the brain with `active` = `is_engaged()` and not EMP and not dying. Escorts are ordinary AI ships in the fortress's owner group, born at the bay's `Mouth` (world space,
so a panned Assault camera changes nothing), in `SpaceFortressEscorts`, never in the enemy container; they are scuttled when the death starts.

| Bay | Part | Trigger | Open Space | Assault | Door |
|---|---|---|---|---|---|
| `hangar` | `Hangar` | PERIODIC from `shields_exposed`, `first_delay` 2 | 3 swarm drones / 12 s | 2 swarm drones / 14 s (`assault_count`, `assault_period`) | 0.8 s open, then held 2.0 s; **the hangar is hittable exactly then** (`opens_part`) |
| `hangar` surge | — | `critical` entry: `FortressBrain._set_reinforcements` → `surge(&"hangar", config.hangar_surge_count 4)` | swarm drones | swarm drones | only while the hangar lives |
| `north_defenders` | `ShieldNorth` | ON_SECTOR_LOSS: `battery_artillery`, `battery_missiles`, `hangar` | 2 fighters | 2 fighters | 1.0 s |
| `south_defenders` | `ShieldSouth` | ON_SECTOR_LOSS: `battery_spread`, `battery_pulse`, `battery_sweep` | 2 gatling interceptors | 2 gatling interceptors | 1.0 s |

- **Caps:** `escort_cap_open_space` 6 / `escort_cap_assault` 4; a launch without room is skipped and counted (`skipped(bay_id)`).
- **Meaning for the player (§26):** nothing launches in `batteries` until a battery dies (its sector's pair, one door cycle later); a lost generator ends its half's bay for good (a
  launch mid-door is cancelled); killing the hangar stops the drones (and the surge) for good; losing the hangar calls the north defenders.
- **Why the hangar holds its doors:** behind the north bubble (capacity 120) it needs 420 damage; the default gun does 50 / 0.18 s, so the 0.8 s telegraph alone gives ≈ 222 and the
  held 2.0 s makes the window 2.8 s ≈ 778. A row checks the inequality and its `open_hold_seconds` 0 boundary, and a real-hit row kills it in one window.
- **Escort fire:** a launched gatling pair puts a round in the escort container in ≈ 2.9 s; a fighter pair in ≈ 3.9–4.5 s (its lead-in and attack slot), bounded at 5 s in the gate.

Gate `tests/integration/test_fortress_reinforcements.gd`; the §25 `reinforcements` key and the dead-hangar row are in `test_space_fortress.gd`.

## Death

Latched once: `was_killed`, `died` (the kill score), the corpse made harmless (hurtbox monitoring and contact layer off, deferred), `suspend_ai()`, every
mount powered down, `FortressBrain.silence()` (spokes and ring cancelled, every core-ring round freed), `BossReinforcements.scuttle_all()` (every escort killed), `death_started` (the blast chain, spin and burnt
tint of `BossDeathSequence`), then `death_duration` later the escort container (`<name>Escorts`) and the hull are freed. `death_duration` 0 frees at once.

## EMP, homing, ward, tow

`answers_emp()` is true while alive and while dying; `apply_emp()` scales every window by `emp_factor` (a 5 s pulse is 2 s) and does nothing while dying,
so an EMP Blast never process-disables the wreck mid-sequence. The brain's `on_emp_started()` scans every mount down, cancels the spokes and the ring and gives the bays one inactive tick.
It stays tangible through the window. `homing_point(from)` = the nearest live vulnerable part's centre, else the core's. Never repaired, warded or towed.

## Brain (`FortressBrain`) and movement (t6)

`enum Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }` (append-only; the movement phase, never mixed with the boss ladder).
**`is_engaged()`** = HOLD or REPOSITION, both modes: the weapons (t7, t16) fire and the bays (`BossReinforcements`, built by the root: escort cap 6 in Open
Space, 4 in Assault) run only then. It only requests (`face_toward`, `request_velocity`, `arrive`, `hold_position`, `max_turn_rate` writes); the
`EnemyMover` authors `turn_lerp` 0 and acceleration 0, so the turn cap alone sets every turn rate and every hold ends exactly.

- **Facing rule** (`present_side()`): each sector's strength is its live batteries (north: artillery, missiles; south: spread, pulse, sweep), halved once its
  generator is destroyed; the stronger sector's centre (north local −y, south local +y) is turned toward the player at `turn_rate` 0.22 rad/s (Assault
  `assault_turn_rate` 0.30); a tie keeps the side. A circling player at 500 px out-turns it (0.84 rad/s in Open Space), so circling reaches the weak side.
- **Spins**: t16 calls `begin_spin(direction := 0)` (0 alternates, the first is +1) / `end_spin()` for a volley spin at `beam_spin_rate` 0.5; in `critical`
  it spins continuously at `critical_spin_rate` 0.6. A spin faces a point 1 rad ahead of the current facing (the face lever is `FACE_REACH` 10 000 px).
- **Open Space**: `patrol_anchor` (spawn when unset) is the combat zone's centre (`zone_radius` 600). Hub idle through `AnchorIdle(anchor, 1400, 2600, 0.8,
  home_radius 8)`: IDLE holds the anchor and spins at `idle_spin_rate` 0.08; NOTICING; then HOLD at the station point (the anchor) in `batteries` /
  `shields_exposed`, ±`hold_tolerance` 24 at `hold_speed` 40. From `core_exposed` REPOSITION: every `reposition_period` 8 s (`critical` 5 s) a new station
  point, the one of 8 points on the 360 px circle round the anchor that is ≥ 250 px from the current point and farthest from the player 1 s ahead (lowest
  index on a tie), reached at 60 px/s (`critical` 90). The player beyond `lose_radius` → RETURNING to the anchor at 60 → IDLE (boss phase and damage kept).
  `start_engaged` (a test seam) skips the idle and so the leash.
- **Assault**: no engagement budget, no exit. ENTER straight down at `assault_enter_speed` 90 to `assault_hold_y` 180, HOLD there; from `core_exposed` a
  vertical bob of ± `assault_bob_amplitude` 100 at `assault_bob_speed` 35 (`critical_bob_speed` 55), reversing on each end. x never moves: only a correction
  back to the anchored x at ≤ `assault_x_correct_speed` 20.
- **EMP**: the base rule halts the mover and skips the brain: no motion and no rotation for the window.
- **Thrusters**: `Thrusters.visible` is the root's phase flag (from `core_exposed`; the snapshot reads it); the brain writes only `Thrusters.modulate.a`, 1.0
  while travelling (REPOSITION en route, RETURNING, ENTER, the bob) and `THRUSTER_IDLE_ALPHA` 0.35 holding.

## Spawning

`b.space_fortress()` (`WaveBuilder.SPACE_FORTRESS`); no `.delay()`, no `.move()`. `world_anchored_x` (a wave spawn's x is world-anchored, the Carrier's rule).

## Tests

`tests/integration/test_fortress_weapons.gd` (rows A1–A6 and B7–B12 of plan §2.7.7, both harnesses: the five mounts, pools and gate, crossfire and dead lanes, when the guns may fire, the critical cooldowns and pools, 30 s of critical fire, EMP and death with a rocket outliving the fortress; the spokes and ring as authored, by phase / period / spin, hitting the real player and an outsider but never the owner set (real physics 8×), the core ring (critical only, 12 rounds, the 0.24 precession and its lane boundary, the parent container, 72-round pool), EMP and death cancelling them with the fade tick, the fairness rows with the 15° gap boundary, the measured Assault density in every phase at five positions, and the `attacks` / `arena` keys), `tests/integration/test_space_fortress.gd` (rows 1–11 of plan §2.5.7, both harnesses; the armour, lane and locked-part rows on real physics at 8×; the t6
movement block: idle, facing at exactly the turn rate, halving and ties, circling wins (player speeds read from their scenes), hold, the reposition pick
recomputed from the config, the leash, the Assault entry / hold / bob / fixed x, spins, EMP and thrusters, all hand-ticked), plus the
roster gates: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd`,
`test_config_instance_isolation.gd` (sweep + the children identity row), `test_boss_phase_rules.gd`, and the automatic sweeps (transparency, signal arity,
single writer, layer names, project load).

## Files

```
space_fortress/
├── ENEMY.md                     ← this file
├── space_fortress.tscn          root SpaceFortress, Modules/* (nine EnemyModules), ModularHull, PhaseDriver, DeathSequence, Thrusters, CriticalOverlay, HullBeams/Spoke0..3, PulseRing
├── fortress_spoke_beam.tscn     the hull spoke (inherits enemy_beams/beam.tscn, authors every gated value)
├── fortress_pulse_ring.tscn     the ring pulse (inherits enemy_beams/energy_ring.tscn, authors every gated value)
├── space_fortress.gd            SpaceFortress (armour, sectors, ladder consequences, phase_snapshot, death, EMP, homing, CoreRingPool, the fade tick)
├── fortress_brain.gd            FortressBrain (movement: facing rule, spins, Open Space zone, Assault hold / bob; the batteries and attack gate; the geometry weapons; bays tick; phase / EMP / death hooks)
└── space_fortress_config.gd / .tres   SpaceFortressConfig (flat)
```
