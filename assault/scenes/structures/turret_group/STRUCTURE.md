# Turret Group — turrets placed together, with one power source

**Role:** A coordinator that places a small group of turrets (2–4) and a power source with overlapping fire lanes, staggers their warnings so the
crossfire stays readable, and shuts every turret down the moment the power source dies.
**Fantasy / threat:** A defended position: guns whose lanes cross, wired to a reactor. Fight through the crossfire, or find the lane to the reactor
and switch the whole position off.

> **Build state (Phase 8, t9).** `TurretGroup`, `TurretGroupSlot`, the `assault_pair` preset and `WaveBuilder.turret_group()`. Next: the shield generator
> and its test preset (t9s), the hub site preset (t18), level-1 placement (t19). Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.10; task plan
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

`assault_pair` is a diagonal stagger so its three members (x spread 100 px) fit in one gap between level 1's laser columns: `.at(-64, -220)` puts them
at world x 462 / 512 / 562.

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
    └── assault_pair.tscn
```
