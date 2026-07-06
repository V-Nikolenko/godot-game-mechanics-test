# Race Track Hazards

Lethal, authored hazards placed as children of `Track/RaceTrack` (negative Y, like dash
panels) so they scroll with the world. Each one-shots any ship on contact and is sensed by
the AI for avoidance. See the system overview in
[assault.md → Race sub-mode](../../../../docs/architecture/modules/assault.md).

> **Phases 1–3 of the race hazard gauntlet** are implemented (breakable walls, asteroids,
> pulsing lasers, the player throttle/brake, and trapped-panel route refusal). Speed-feel FX
> is Phase 4 — see `docs/superpowers/specs/2026-06-14-race-hazard-gauntlet-design.md`.

---

## The hazard contract

Every hazard joins group **`race_hazards`** and implements (duck-typed):

| Method | Meaning |
|---|---|
| `danger_rect() -> Rect2` | World-space lethal rectangle. |
| `is_lethal_now() -> bool` | Whether contact kills right now (walls/asteroids: true until destroyed; lasers: only while the beam is active). |

Lasers add timing accessors the AI uses: `is_safe_to_cross()` (true only in the dark gap),
`is_full_width()` (a horizontal across-lane timing gate vs a vertical lateral band).

`core/hazard_system.gd` (`HazardSystem`, one per race level) polls every ship in
`["player","racers"]` against every lethal hazard each `_physics_process`. On overlap
(`danger_rect().grow(6)` contains the ship): **player →** `RaceDirector.fail_race()`
(instant restart); **AI →** `RaceShip.apply_lethal_hazard()` (explode + `queue_free`,
unregistered from standings = attrition). The kill **bypasses shields** (it is an obstacle,
not a combat hit). The same hazards feed `sensors.race_hazard_ahead()` / `sensors.safe_x()`,
which drive the pre-FSM dodge reflex in `race_ship.gd`.

---

## RaceWall — breakable partial wall

**Role:** Lethal bar that blocks part of the lane; weave around it, or shoot a rocket to
clear it.
**Threat:** Instant kill on contact. Narrower than the lane, so a gap always exists —
deadly only if you fly into it (or get lunged into it by a dash panel: a "trap", Phase 3).

| Property | Value |
|---|---|
| HP | 60 (rockets only) |
| Damage | lethal one-shot (via `HazardSystem`) |
| Footprint | `wall_size` = 256 × 65 px (partial; lane is ~1024 wide) |
| Sprite | `assault/assets/sprites/racers/race_track/walls/wall_1.png` (256×65) |
| Scene / script | `race_wall.tscn` / `race_wall.gd` (`class_name RaceWall`, `Node2D`) |

- **Break:** `HurtBox` (Area2D, layer 512 / mask 32, `accepted_damage_types = [ROCKET=1]`) →
  `Health.decrease` → at 0 HP: explosion, leaves `race_hazards`, frees after 0.7 s. Player
  **missiles** (warhead/homing, `damage_type 1`) break it; bullets (`damage_type 0`) do not.
- **No physics body** — ships pass through visually and die via the central poll (no bounce).

### Exports

| Export | Default | Meaning |
|---|---|---|
| `wall_size` | `Vector2(256, 65)` | Lethal/visual footprint; keep narrower than the lane. |
| `health_amount` | `60` | Rocket damage to break (≈1–2 warheads). |

---

## RaceAsteroid — static track asteroid

**Role:** Point hazard dropped on the track; dodge it or rocket it.
**Threat:** Instant kill on contact; small footprint, easy to thread but punishing to clip.

| Property | Value |
|---|---|
| HP | 100 (`AsteroidBase` default; rockets only) |
| Damage | lethal one-shot (via `HazardSystem`) |
| Footprint | `danger_size` = 56 × 56 px |
| Sprite | `assault/assets/sprites/environment/big_asteroid_tileset.png` (random 64×64 tile) |
| Scene / script | `race_asteroid.tscn` / `race_asteroid.gd` (`class_name RaceAsteroid extends AsteroidBase`) |

- Extends `AsteroidBase` for visuals + rocket-break (same `HurtBox` 512/32, ROCKET-only).
- **Static on track:** `set_physics_process(false)` (no drift/path movement) and the root
  `CharacterBody2D` is `collision_layer = 0` (no physical bounce); the per-asteroid
  `ContactHitBox` is disabled (lethal contact is handled centrally, shield-bypassing).
- `is_lethal_now()` = `not was_killed`.

### Exports

| Export | Default | Meaning |
|---|---|---|
| `danger_size` | `Vector2(56, 56)` | Lethal footprint (≈ the visible asteroid). |

(Inherited `AsteroidBase` exports — `health_amount`, `contact_damage`, `tileset_texture`,
etc. — still apply; `one_shot_speed_threshold` is unused here since contact is central.)

---

## RaceLaser — pulsing laser (timing gate / lateral band)

**Role:** A telegraphed beam that periodically becomes lethal. Read the warning and either
boost through before it fires or wait it out, then cross.
**Threat:** Indestructible. No gaps — you cannot dodge a horizontal beam laterally; you
**time** it.

| Property | Value |
|---|---|
| Scene | `race_laser.tscn` — an **inherited scene of** `assault/scenes/hazards/laser_ray/laser_ray.tscn` (reuses its `giant_lasser` textures + animation) |
| Script | `laser_ray.gd` (`class_name LaserRay`), shared with the assault laser |
| Damage | lethal one-shot while active (via `HazardSystem`) |
| Cycle | WARN (telegraph) → ACTIVE (lethal) → OFF (dark, safe), repeating |

- **Race mode** is enabled by exports on `laser_ray.gd` (default off → assault behaviour
  unchanged): `race_hazard = true` (join `race_hazards`, expose the contract, leave the
  built-in HurtBox `HitZone` disabled so `HazardSystem` does the shield-bypass kill) and
  `loop = true` (re-fire after `off_duration` instead of dissolving once).
- **Orientation** is set by the node's `rotation` (the laser aims its beam): ≈±90° =
  **horizontal** full-width timing gate (`is_full_width()` true); ≈0° = **vertical** lateral
  band, dodged via the normal `safe_x` reflex. `segment_count` × 128 px sets beam length.

### Key exports

| Export | Default (race) | Meaning |
|---|---|---|
| `warn_duration` | `1.1` | Telegraph seconds before the beam becomes lethal. |
| `active_duration` | `1.2` | Seconds the beam is lethal. |
| `off_duration` | `1.8` | Dark/safe seconds between pulses (the only cross window). |
| `segment_count` | `8` | Beam length in 128 px tiles. |

---

## Trapped panels & player throttle (Phase 2–3 mechanics)

- **Trapped panel** (no node — emergent from authoring): a wall placed within
  `RaceParticipant.panel_lunge` (650) **ahead** of a dash panel in the same lane. Crossing
  the panel lunges you into the wall → rocket it or skip the panel. `sensors.panel_is_trapped()`
  detects this and `sensors.nearest_panel_ahead()` skips trapped panels, so **all AI
  panel-seekers refuse the route** (lasers excluded — they pulse).
- **Player throttle/brake** (`race_brake`, default **Left Shift**): `PlayerRaceController`
  lowers the player's `RaceParticipant.cruise_factor` to `brake_throttle` (0.3) to slow the
  forward advance and time a laser; release = full speed. `RaceParticipant` applies
  `cruise_factor` to the player as well as AI.

---

## Files

```
race/track/
├── RACE_HAZARDS.md      ← this file
├── race_wall.gd / .tscn
├── race_asteroid.gd / .tscn
├── race_laser.tscn       (inherits assault hazards/laser_ray; race_hazard + loop)
├── dash_panel.gd         (boost pads + side-wall hits; "trapped" when a wall is placed ahead)
├── mine.gd, obstacle.gd, finish_line.gd
core/
├── hazard_system.gd      (central lethal-contact poll)
└── sensors.gd            (race_hazard_ahead / safe_x / blocking_laser_ahead / panel_is_trapped)
```
