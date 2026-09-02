## SpaceStationConfig — tuning for the Level 1 space-station mini-boss.
##
## `max_health`, `collision_damage`, `score_value` and `counts_toward_wave_clear` come from
## ShipConfig. Applied in SpaceStation._ready(), where the .tres wins over the values authored
## on the scene's Health nodes — the project-wide config-driven rule.
##
## There is deliberately NO per-turret score field: nothing could pay it out. ScoreTracker
## registers kills via WaveManager.enemy_spawned + BaseEnemy.died (score_tracker.gd:55-75), and
## a turret is a plain Node2D that is never spawned through WaveManager and never leaves the
## tree. Per-turret scoring needs a payout path that does not exist yet.
class_name SpaceStationConfig
extends ShipConfig

## HP of each individual turret. SpaceStation._ready() writes this into every turret's Health.
@export var turret_health: int = 120

## ── Laser phase (EPIC sub-item 3) ─────────────────────────────────────────────
##
## Read ONCE by `StationLaserPhase._ready()`, which copies them into its own fields and never
## reads this resource again. That is deliberate: this `.tres` is a single process-wide instance
## (`space_station.gd` `load()`s it and ResourceLoader caches), so anything reading through it at
## runtime is reading mutable global state. See `space_station_laser_phase.gd`.
##
## `laser_emitter_radius` is NOT here — it is scene geometry, not a stat, so it lives as an
## export on the phase node.

## Seconds the beam holds its warning line before it can hurt anything. Time-to-lethal is
## `warn + ~0.56 s` (the `laser_increase` charge-up), so 1.4 gives ~1.9-2.0 s of tell — roughly
## the Danmakufu delay-laser convention for a screen-covering beam, and ~6x the 0.3 s human
## reaction floor. Deliberately shorter than the 3.0 s Level 1's static laser columns use, which
## would not fit twice inside a volley cycle.
@export var laser_warn_duration: float = 1.4

## Seconds the beam stays lethal once armed.
@export var laser_active_duration: float = 2.0

## Seconds from one volley's start to the next. Must exceed the full beam lifetime
## (warn + 0.56 charge + active + 0.84 dissolve = ~4.8 s at the values above) or volleys overlap;
## 6.5 leaves ~1.7 s of clear screen, inside the 5-10 s attack-switch cadence.
@export var laser_volley_interval: float = 6.5

## Radians per second the whole station rotates during the laser phase. Constant rate, no easing
## — a predictable sweep is what makes it dodgeable. 0.5 rad/s is ~29 deg/s; at the ~400 px the
## player sits from the station the beam edge moves ~200 px/s, half the player's 400 px/s top
## speed (`move_state.gd:21`).
@export var laser_rotation_speed: float = 0.5

## Beams fired per volley, spread evenly around the station. Two opposed beams sweep the plane
## while always leaving two large clear quadrants.
@export var laser_beam_count: int = 2
