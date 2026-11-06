# Turret Group — turrets placed together, with one power source

**Role:** A coordinator that places a small group of turrets (2–4) and a power source with overlapping fire lanes, staggers their warnings so the
crossfire stays readable, and shuts every turret down the moment the power source dies.
**Fantasy / threat:** A defended position: guns whose lanes cross, wired to a reactor. Fight through the crossfire, or find the lane to the reactor
and switch the whole position off.

> **Build state (Phase 8, t9 + t9s + t18 + t19).** `TurretGroup`, `TurretGroupSlot`, the `assault_pair` preset and `WaveBuilder.turret_group()`; the shield generator
> (t9s, [ENEMY.md](../../enemies/shield_generator/ENEMY.md)) is a member that wraps the others in bubbles; the hub's defended derelict site, `hub_defense_site.tscn`
> (t18, placed under `sector_hub.tscn`'s `EnemyContainer`). Level 1 (t19) places the `assault_pair` group `.at(64, -220)` in Deep Space's 3.0 s wave. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.10; task plan
> `docs/plans/cmvqw0vnl0183qs2xbphzonu7/3-plan.md`.

---

## What it is

- **`TurretGroup extends Node2D`** (`turret_group.gd`) — **a coordinator, not a parent.** It is never in `enemies`, has no `died` signal and is never
  scored (`counts_toward_wave_clear` / `counts_as_escape` false, `score_value` 0); `is_laser_blocking()` false. It does not drift; its members do.
- **`TurretGroupSlot extends Marker2D`** (`turret_group_slot.gd`): `member_scene`, `variant` (−1 keeps the member's own; ≥ 0 sets a turret's first-mount
  weapon), `rest_bearing_deg` (NAN keeps the member's own; else a turret's `rest_bearing_override`).

## Behaviour

- **Spawn.** `_ready()` queues a deferred `spawn_members()` (a wave may spawn the group inside a physics flush). For each slot it instantiates the
  member at the slot's world position, copies `variant` / `rest_bearing_deg`, turns off a member's own `world_anchored_x`, calls
  `set_turret_group(self)` — all before `add_child` — then adds it to the group's **own parent** (the enemy container), registers a
  `provides_power()` member as a provider and announces it with `EventBus.enemy_spawned_orphan` (so `ScoreTracker` scores it). Members join
  `owner_group` (`&"turret_group_<id>"`), which every beam and ring of the group exempts. `spawn_members()` is public and idempotent (hand-ticked tests
  call it).
- **Members leave** on `tree_exiting` (`member_left(member)`); the group frees itself the frame its last member leaves. `members()` lists the live ones.
- **World-anchored x (Assault).** With `world_anchored_x` (default true) and an arena, `_ready()` subtracts the camera's horizontal pan
  (`EnemyWorld.view_rect()` centre − `EnemyWorld.projectile_world_rect()` centre) from x before spawning, so `.at(x, y)` lands at world `640 + 2·x`
  whatever the player did. y stays camera-relative. Open Space: untouched.
- **Power.** `add_power_provider(node)` takes any node with `provides_power()` and `died` (the Ph20 jammer seam). Powered while any provider lives, or
  always with none. On the last provider's `died`, in that same call: `set_powered(false)` on every live member, then `power_changed(false)` once.
  Never reversed in this phase; a provider that leaves without dying is only forgotten.
- **Stagger.** `request_telegraph(member)` is each member turret mount's `telegraph_gate`: at most one TELEGRAPH start per `stagger_seconds` 0.3 on the
  group's clock (`tick(delta)` from `_physics_process`); a refused mount retries next tick.
- **Coverage (R8.11).** `coverage_points()` (every 10° at `coverage_radius`, local), `mount_reaches()` (`{position, reach}` per turret mount, read
  off-tree from the slots; reach = `TurretMountScenes.reach_of()`: a gun's `fire_range`, a pulse ring's `trigger_range`), `coverage_holes()` (points
  fewer than `coverage_min` 2 mounts reach). Every preset must have none.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `coverage_radius` | 180 | Radius of the coverage check, px |
| `coverage_min` | 2 | Mounts that must reach every coverage point |
| `stagger_seconds` | 0.3 | Minimum gap between member TELEGRAPH starts |
| `world_anchored_x` | true | Assault: remove the camera's horizontal pan from x in `_ready()` |

## Presets (`presets/`)

| Preset | Members | coverage_radius |
|---|---|---|
| `assault_pair.tscn` | BURST_CANNON turret at (−50, 60), PULSE_RING turret at (50, −60), power source at (0, 0) | 180 |
| `hub_defense_site.tscn` | heavy emplacement at (180, 20), SWEEP_BEAM turret at (−240, 160), ROCKET_BATTERY turret at (240, 160), LANCE turret at (0, −260), shield generator at (−120, −120), power source at (200, −120), `laser_fence/hub_barrier.tscn` (a CYCLE fence) at (44, 98) | 450 |

`assault_pair` is a diagonal stagger so its three members (x spread 100 px) fit in one gap between level 1's laser columns. **Level 1 (t19)** places it with
`b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR).at(64, -220)` in Deep Space's 3.0 s wave (effective 3.5 s), which, world-anchored, puts them
at world x 718 / 768 / 818: 78 px from the 640 and 896 columns for the turrets (need 28 + 28), 128 px for the power source (need 28 + 34), and
clear of the level-start `LaserWallWave` (x 0–672, lethal while the group spawns). The plan's `.at(-64, -220)` (462 / 512 / 562) cleared every scheduled column
but sat inside that wall, where `scripts/measure-level1-columns.sh` saw both turrets die; `test_ph8_static_members_clear_every_lit_column` reads the wall
too, and has boundaries for both the plan's x and revision 1's `(0, −220)`. The members drift out by 29.7–31.7 s (no rocket battery, so no ordnance tail);
`test_level1_ph8_attacks.gd` shows both turrets fire while in view.

`hub_defense_site` guards the Open Space hub's TacticalSpace derelicts from (2520, 1040) (plan §2.17; task plan `docs/plans/cmvqw0voe0197qs2xrgvobaky/3-plan.md`). Four
shooters and every structure rule once: the generator bubbles the five `BaseEnemy` members other than itself, never the barrier's posts, and the source
sits behind the wreck line, so the player flanks or slips a gap to switch the site off. The heavy emplacement and the power source sit off the plan's
(0, 0) and (120, −120), which overlap the cargo platform and the satellite. Its fire reach (the lance: 260 + 1100 = 1360 px) and its footprint
(416 px) are swept against the hub's safe places and patrols in `test_sector_hub_patrol.gd`. Only `TurretGroup` scenes may live in `presets/`: the
coverage row loads every file there as one, which is why the barrier lives in `laser_fence/`.

## Spawn notes

- `b.turret_group(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR).at(x, y)`.
- **Never in an `ENEMIES_CLEARED` section** (persistent fire; guard row in `test_engagement_deadline.gd`).

## Tests

`tests/integration/test_turret_group.gd` (both harnesses: spawn, world anchor, same-call shutdown, stagger, coverage, friendly fire, power lines, a real
`WaveManager` spawn, drift-out scoring, slot overrides); the power source's case in `test_enemy_dual_mode.gd`.

## Files

```
turret_group/
├── STRUCTURE.md             ← this file
├── turret_group.gd
├── turret_group_slot.gd
└── presets/
    ├── assault_pair.tscn
    └── hub_defense_site.tscn
```
