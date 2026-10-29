# Laser Fence — a laser wall between two destructible posts

**Role:** A stationary laser wall (always on) or a temporary barrier (switching on and off) between two `LaserEmitter` posts. Enemies steer round its
ends; the player flies round them or shoots a post, which drops the whole fence.
**Fantasy / threat:** A pylon gate. Clear, fair and cheap to beat if you look at the posts; ruinous if you fly through the wall.

> **Build state (Phase 8, t10).** `LaserFence`, `laser_fence.tscn`, [`LaserEmitter`](../../enemies/laser_emitter/ENEMY.md). Next: art (t15), the hub site
> (t18, a `CYCLE` barrier) and level 1 (t19). Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` §2.11.

---

## What it is

- **`LaserFence extends Node2D`** (`laser_fence.gd`): two `LaserEmitter` children (`PostA` at (−150, 0), `PostB` at (150, 0)), one `EnemyBeam` built from
  `twin_beam.tscn` with fence overrides on the instance (`damage` 12, `avoid_weight` 1.0, `registers_hazard` true) and an `AssaultDrift`.
- Not an enemy: never in `enemies`, never scored (`counts_toward_wave_clear` / `counts_as_escape` false); `is_laser_blocking()` false. Its posts are the
  enemies; the fence announces them with `EventBus.enemy_spawned_orphan` from `_ready()`.
- **The fence ticks its own beam**: `_physics_process` → `step(delta)` (hand-tickable), which feeds `set_endpoints(PostA, PostB)` and calls
  `beam.tick()`. The beam's phases are the beam's own (TELEGRAPH 0.9 s, ACTIVE held, FADE 0.15 s); the fence only decides when to `start()` and `cancel()`.

## Modes

| Mode | Behaviour |
|---|---|
| `STATIC` | TELEGRAPH once on the first step, then ACTIVE held until a post dies or `set_powered(false)` |
| `CYCLE` | OFF `off_seconds` 2.5 → TELEGRAPH 0.9 → ACTIVE `on_seconds` 3.0 → cancel (the beam's 0.15 s FADE runs inside the next OFF) → … ; `cycle_period()` = off + telegraph + on; `phase_offset` starts it that many seconds into the cycle (into the warning it warns for the rest of it; into the lit part it starts lit), so several barriers can alternate |

## Collapse and linger

- The first post to emit `died` or leave the tree cancels the beam at once (FADE; a warning goes straight OFF) and the fence **never relights**
  (`is_collapsed()`, `collapsed` signal). The surviving post stays a target.
- When the second post goes the fence does not free itself at once: a dying post's `ExplosionEffect` spawns its particles into the post's parent, this
  node. It unregisters its hazard (the collapse already did), keeps ticking the beam down to OFF (non-lethal) and frees itself `linger_seconds` (1.0 s,
  longer than the particles' 0.5 s lifetime) later, counted on its own physics step (no `Timer`).

## Power and groups

- `set_powered(false)`: beam cancelled, posts' lights OFF, never restarts (a later `true` is ignored). A fence can be a `TurretGroup` member (the group's
  `power_changed` coupling reaches it through `set_powered`; the hub barrier is one).
- `set_turret_group(group)`, before `add_child`: the fence's `owner_group` becomes the group's and the world anchor is skipped (the group placed it).
  Alone it is `&"laser_fence_<instance id>"`. Both posts join `owner_group`; the beam's owner set is that group, so it never hurts the posts or the
  group's turrets. A shield generator never shields a post.

## Hazard

The beam registers a `&"laser_wall"` segment `HazardInfo` (`registers_hazard`) from TELEGRAPH start to FADE start, spanning the posts, `avoid_weight` 1.0,
`exempt_group` = the owner group. AI enemies with `hazard_avoidance` steer round an end; one with none flies into it. In Assault the hazard's `velocity`
is the drift's `(0, 60)`, so the avoidance stage leads the carried wall.

## Assault

- `AssaultDrift` (speed `drift_speed` 60) carries the fence and both posts down and frees the fence below the projectile world rect.
- **World-anchored x.** A fence a wave spawns (no `set_turret_group`) removes the camera's horizontal pan from its x once in `_ready()` (`world_anchored_x`,
  default true), exactly as `TurretGroup` does: design x lands at world `640 + 2·x`. y stays camera-relative.
- Never goes in an `ENEMIES_CLEARED` section (persistent fire); the guard rows live in `test_engagement_deadline.gd`.

## Exports

| Export | Default | Meaning |
|---|---|---|
| `mode` | STATIC | `Mode.STATIC` or `Mode.CYCLE` (append-only) |
| `off_seconds` / `on_seconds` | 2.5 / 3.0 | CYCLE dark and lit durations |
| `phase_offset` | 0 | CYCLE: seconds into the cycle at the first step |
| `linger_seconds` | 1.0 | Life after the last post dies |
| `world_anchored_x` | true | Assault: remove the camera pan from x in `_ready()` |
| `drift_speed` | 60 | Assault drift, px/s |

Tests: `tests/integration/test_laser_fence.gd`, the fence row of `test_enemy_dual_mode.gd`, the generator-preset row (`tests/helpers/shielded_site.tscn`).
