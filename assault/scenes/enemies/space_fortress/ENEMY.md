# Space Fortress — the 360 degree boss you take apart sector by sector

**Role:** Phase 11's boss (Space Fortress 2.0), built to be fought by circling it rather than from below. It replaces level 1's legacy space station
(t10 places it in `station_assault`; t13 adds it to the Open Space hub). **Never call it a "station"** in code, nodes or docs: Open Space already has
"Fortuna Space Station" (a `MissionTrigger`).
**Fantasy / threat:** a ring fortress whose hull is armour. Five gun batteries sit on the ring, each with its own attack and its own angle; two shield
generators keep a bubble on the batteries and the hangar of their half; the core stays plated until both generators are gone. Destroying a battery
removes an attack angle; destroying a generator bares a whole sector; every phase changes how the fight plays.

Plan: `docs/plans/cmug256so0031m52wbxomst72/3-plan.md` §2.5 (t5, this shell), §2.6 (t6 movement), §2.7 (t7 batteries, t16 geometry weapons), §2.8 (t8 bays),
§2.9 (t9 art). Task plan of the shell: `docs/plans/cmwt4y3hg00soqs2ybvglujbs/3-plan.md`.

**Built so far (t5, the shell):** hull, parts, sector shields, phase ladder with its vulnerability and visual consequences, death, EMP, homing, roster
gates. **Not yet:** it does not move (t6), fire (t7, t16) or launch escorts (t8); `FortressBrain.is_engaged()` and `attack_gate()` are stubs answering
false; art is placeholder station PNGs (t9).

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

| # | Phase | Trigger | Declared changes | Consequences built so far (t5) |
|---|---|---|---|---|
| 0 | `batteries` | START | — | shutters closed, plating closed, generator lights SHIELDED |
| 1 | `shields_exposed` | 2 WEAPON parts destroyed (`shields_exposed_battery_losses`) | VULNERABLE, ATTACKS, MOVEMENT, REINFORCEMENTS, VISUALS | both generators open (deferred), shutter art opens |
| 2 | `core_exposed` | both generators destroyed | VULNERABLE, MOVEMENT, ARENA, VISUALS | core opens (deferred), plating art opens (never over a wreck), `Thrusters` shown |
| 3 | `critical` | core ≤ 40 % (`critical_core_ratio`) | MOVEMENT, ATTACKS, REINFORCEMENTS, VISUALS | `CriticalOverlay` shown, core light blinks COMMIT / OFF every `core_blink_period` 0.25 s |

The scene's `count` / `health_ratio` must equal the config's (a row checks it). Movement, attack, arena and reinforcement consequences arrive with t6, t7,
t16 and t8 through `FortressBrain.on_boss_phase()`. A phase stepped while the fortress is dying applies nothing.

**`phase_snapshot()`** — six keys (`movement`, `attacks`, `vulnerable`, `arena`, `reinforcements`, `visuals`) built only from phase-driven state, never
from which parts are alive, so the kill that triggers a phase never counts as one of its changes. `visuals` reads the fortress's own fields (shutter and
plating textures, the generator light it keeps, the core light *mode*), not the live sprites or lights: a wreck turns its own light off and a blinking light
alternates. `movement` / `attacks` / `arena` are `[]` and `reinforcements` `[[], 0]` until their tasks build them.

## Death

Latched once: `was_killed`, `died` (the kill score), the corpse made harmless (hurtbox monitoring and contact layer off, deferred), `suspend_ai()`, every
mount powered down, `FortressBrain.silence()`, `BossReinforcements.scuttle_all()` (every escort killed), `death_started` (the blast chain, spin and burnt
tint of `BossDeathSequence`), then `death_duration` later the escort container (`<name>Escorts`) and the hull are freed. `death_duration` 0 frees at once.

## EMP, homing, ward, tow

`answers_emp()` is true while alive and while dying; `apply_emp()` scales every window by `emp_factor` (a 5 s pulse is 2 s) and does nothing while dying,
so an EMP Blast never process-disables the wreck mid-sequence. The brain's `on_emp_started()` scans every mount down and gives the bays one inactive tick.
It stays tangible through the window. `homing_point(from)` = the nearest live vulnerable part's centre, else the core's. Never repaired, warded or towed.

## Brain (`FortressBrain`, shell)

`enum Phase { IDLE, NOTICING, RETURNING, ENTER, HOLD, REPOSITION }` (append-only; the movement phase, never mixed with the boss ladder). Its tick only ticks
the `BossReinforcements` (built by the root: escort cap 6 in Open Space, 4 in Assault). It never writes velocity or rotation.

## Spawning

`b.space_fortress()` (`WaveBuilder.SPACE_FORTRESS`); no `.delay()`, no `.move()`. `world_anchored_x` (a wave spawn's x is world-anchored, the Carrier's rule).

## Tests

`tests/integration/test_space_fortress.gd` (rows 1–11 of plan §2.5.7, both harnesses; the armour, lane and locked-part rows on real physics at 8×), plus the
roster gates: `test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_base_enemy.gd`,
`test_config_instance_isolation.gd` (sweep + the children identity row), `test_boss_phase_rules.gd`, and the automatic sweeps (transparency, signal arity,
single writer, layer names, project load).

## Files

```
space_fortress/
├── ENEMY.md                     ← this file
├── space_fortress.tscn          root SpaceFortress, Modules/* (nine EnemyModules), ModularHull, PhaseDriver, DeathSequence, Thrusters, CriticalOverlay
├── space_fortress.gd            SpaceFortress (armour, sectors, ladder consequences, phase_snapshot, death, EMP, homing)
├── fortress_brain.gd            FortressBrain (shell: bays tick, phase / EMP / death hooks)
└── space_fortress_config.gd / .tres   SpaceFortressConfig (flat)
```
