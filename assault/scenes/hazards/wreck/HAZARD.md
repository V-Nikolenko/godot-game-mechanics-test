# Wrecks, derelict structures and drifting debris — cover and collision hazards

**Role / threat:** A dead hull or a derelict structure is **cover for both sides**. It is solid for every ship, opaque to
sight lines, and stops shots from the player and from enemies. It is harmless while it sits still and hurts when it
drifts into a ship. Drifting debris is the opposite: no cover at all, but it hurts on touch. Plan §2.8
(`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`); build choices in `docs/plans/cmvg30aax007rqs2x14trnuf9/3-plan.md`.

## Scenes

| Scene | Body (circle) | HP | Open Space life | Art (`assault/assets/sprites/wrecks/`) |
|---|---|---|---|---|
| `wreck_small.tscn` | r 13 | 200 | 40 s | `wreck_small.png` (~40 px) |
| `wreck_medium.tscn` | r 25 | 200 | 40 s | `wreck_medium.png` (~72 px) |
| `wreck_large.tscn` | r 40 | 200 | 40 s | `wreck_large.png` (~110 px) |
| `structure_satellite.tscn` | r 28 | 800 | permanent | `structure_satellite.png` (~96 px) |
| `structure_cargo_platform.tscn` | r 55 | 800 | permanent | `structure_cargo_platform.png` (~128 px) |
| `structure_station_module.tscn` | r 45 | 800 | permanent | `structure_station_module.png` (~128 px) |
| `debris_drift.tscn` | contact r 12, no body | — | 30 s | `environment/debris_1..6.png` at 0.5 scale |

All six wreck and structure scenes run on `wreck.gd` (`Wreck`). The debris scene runs on `debris_fragment.gd`
(`DebrisFragment`). `WreckScenes.scene_for(size, explosive)` (`wreck_scenes.gd`) maps `WreckScenes.Size` to the three
wreck scenes. Explosive wrecks return `null` until t12. Spawning on death is t11's, and hub placement is t18's.

## `Wreck` — behaviour

- **Solid body.** It is a `CharacterBody2D` on layer 1 (`ENVIRONMENT`) with mask 0, in group `wrecks`. Every ship body
  stops on it.
- **Blocks sight lines.** `blocks_line_of_sight()` returns `blocks_los` (true), so `LineOfSight.clear()` stops at it.
  Its `HazardInfo` sets `line_of_sight_blocker` true as well.
- **Shots from both sides stop on it:**
  - The `HurtBox` (layer 512, mask 96) uses the body's own shape. It takes player bullets, player rockets and enemy
    rockets (impact mask 640 includes 512) into `Health`.
  - Enemy rounds stop on the `ContactHitBox` (1024). `EnemyBullet`'s HitBox masks `128 | 1024`, and a 1024 area ends
    a round only when its owner answers `stops_enemy_rounds() == true`. A wreck does; an asteroid does not, so rounds
    still pass asteroids.
  - **The player's Sniper Shot stops on it too and deals its full damage.** `Bullet`'s piercing branch ends on a parent
    answering `stops_piercing() == true` without zeroing the damage.
- **The player's beam:** the mining laser stops at any layer-1 body and damages only groups `enemies` and `asteroids`.
  So **a wreck blocks the beam and cannot be cut by it.** This is intended, because it is cover. Use guns or rockets to
  destroy one.
- **Contact: only a moving wreck hurts.** The `ContactHitBox` (layer 1024, damage 10, `CONTACT`) shares the body's
  shape and transform. No ship's hurtbox is larger than its body (gated in `test_wreck.gd`), so a ship that flies into
  a still wreck comes to rest touching it and never reaches the box. A drifting wreck that runs into a ship overlaps it
  for one physics step, and that step hurts the ship.
- **Arming:** the contact box is born unmonitorable, with its shape disabled. It arms `contact_arm_delay` (0.6 s) after
  entering the tree, so a wreck born where a ship died against the player does not hurt the player at once. Arming
  also switches the shape on: Godot never reports an overlap for an area pair it built while the box was
  unmonitorable, and a freshly enabled shape gets fresh pairs.
- **Yield (the clamp-edge rule).** A drifting wreck never keeps pushing into a ship body (groups `player` and
  `enemies`). Once the ship's hurtbox has registered the hit, or the wreck is `YIELD_DEPTH` (1.5 px) deep along its
  drift, it backs off and holds. It resumes when its next step is clear. This exists because the Assault player
  at the bottom clamp edge is never depenetrated by anything. Without the yield, a wreck would sit on that player for
  the whole crossing.
  - Ships the wreck overlapped on its first tick (a wreck born on a ship) are ignored until they separate.
  - The depth cap is measured along the drift. A near-sideways brush (more than ~79° off the drift) can therefore stop
    the wreck before it hurts.
  - A medium wreck born on the idle Assault player drifts clear of it in about 1.3 s; a large one takes about 1.8 s.
- **Hazard, not enemy.** It registers with `Hazards`, with `kind = &"wreck"`, `radius` = body radius,
  `avoid_weight` 0.6, `velocity` = the drift it applied, and no forces. `try_claim` / `release` / `is_claimed_by`
  delegate to its `HazardInfo`, which gives one cover user at a time (t13 / t14). It is never in `enemies`, never
  scored, never a homing target and never in the enemy container.

## Lifetime (one owner)

- **Open Space:** it drifts at `drift_velocity` (default zero). At `lifetime − lifetime_fade` (38 s) it calls
  `retire(2.0)`, so it is gone at 40 s. `lifetime` 0 means permanent; every structure uses that. The
  `ProjectileLifetime` is inert here (`max_time` 0): Open Space has no world rect, and its 30 s cap must not cut the
  40 s life.
- **Assault** (`EnemyWorld.arena()` is non-null when the wreck enters the tree): velocity is
  `(drift_velocity.x, assault_drift)`. A wreck always drifts down at 60 px/s, whatever y velocity it inherited.
  `ProjectileLifetime` (world rect plus a 30 s cap) emits `expired`, which calls `retire()`.
  - **The mode is read once, in `_enter_tree()`.** In an Assault scene a wreck must enter the tree after the
    `ArenaCamera` (a note for t18).
- **`retire(fade := 0.5)`** takes the wreck out of play without it vanishing on screen. It unregisters at once and
  drops any claim. It sets the body's and both areas' layers to 0, and switches monitoring off (deferred). It then fades
  `modulate.a` to 0 and calls `queue_free()`. A retiring wreck takes no damage and never emits `destroyed`. t11's
  alive cap uses it too (`Wreck._enforce_cap()`, Assault 4 / Open Space 8, oldest first).
- **HP 0:** `ExplosionEffect`, `destroyed(world_position)` (t12 hangs the explosive blast on it), then `queue_free()`.
- **Runtime spawns** use `spawn_into(container, at, rot)`. It is deferred, and the wreck frees itself if the container
  is gone. It sets `spawned = true`, so t11's cap counts only runtime wrecks and never retires a placed structure.

## `DebrisFragment` — behaviour

- An `Area2D` with no body, so it is **not cover**. Ships fly into it, and sight lines and shots pass it. Its
  `ContactHitBox` (1024, damage 8) hurts any ship whose hurtbox it touches, **whatever its own speed**: no body stops
  the ship first.
- It moves itself: `speed` falls by `deceleration`·dt, it travels along `direction` (never along its rotation), and its
  sprite turns at `spin`. `configure(rng)` picks the texture, a speed in `[speed_min, speed_max]` (20–40 px/s) and a
  direction from the caller's seeded rng.
- An optional `source` plus `source_clear_radius` keeps the contact box disarmed until the fragment's centre is farther
  than that from a still-valid source. A freed source arms it at once. t15's Ram plate uses this.
- Hazard `kind = &"debris"`, `avoid_weight` 0.4, no LOS blocking. `lifetime` (30 s; 0 = permanent) drives
  `ProjectileLifetime`, which also ends it on leaving the Assault world rect, via `expired → queue_free`.

## Files

```
wreck/
├── HAZARD.md                       ← this file
├── wreck.gd                        ← Wreck: cover, contact, yield, lifetime, retire, spawn_into
├── wreck_small.tscn / wreck_medium.tscn / wreck_large.tscn
├── structure_satellite.tscn / structure_cargo_platform.tscn / structure_station_module.tscn
├── debris_fragment.gd              ← DebrisFragment
├── debris_drift.tscn
└── wreck_scenes.gd                 ← WreckScenes.scene_for()
```

Tests: `tests/integration/test_wreck.gd`, which uses real physics on the 8× clock for the collision rows. The six
scenes are also in the rosters of `test_enemy_hurtbox_geometry.gd` and `test_contact_hitbox_geometry.gd`.
`test_entity_sprite_transparency.gd` sweeps `assault/scenes/hazards/` itself.
