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

## ── Gunnery (EPIC sub-item 4a) ────────────────────────────────────────────────
##
## Read ONCE by `StationGunnery._ready()`, which copies them into its own fields and never reads
## this resource again — same discipline as the laser block above, and for the same reason: this
## `.tres` is a single process-wide instance, so anything reading through it at runtime is
## reading mutable global state.
##
## The two `spawn_radius` values are NOT here — they are scene geometry, not stats, so they live
## as exports on the gunnery node, exactly as `laser_emitter_radius` does on the phase node.

## Seconds between turret volleys. All live turrets fire on the same tick: a legible chunk beats
## four independently drifting cadences, and it makes "one fewer gun" instantly readable. At full
## strength this is 4 turrets x 3 bullets / 1.8 s = 6.7 bullets/s, decaying to 1.7 with one gun.
@export var turret_fire_interval: float = 1.8

## Bullets in each turret's fan. Three is the smallest chunk that reads as a line rather than a
## stray shot.
@export var turret_burst_count: int = 3

## Angular width of each turret's fan, in radians (~20 deg). Wide enough that strafing does not
## dodge all three, narrow enough to still read as one fan.
@export var turret_burst_arc: float = 0.35

## Damage per turret bullet. Between the interceptor's 4 and the gunship's 15 — four turrets
## firing at once must not out-damage the station's own 40-damage contact hit.
@export var turret_bullet_damage: int = 12

## Turret bullet speed (px/s). 60 % of the player's 400 px/s top speed (`move_state.gd:21`),
## inside the shipped 220-260 band.
@export var turret_bullet_speed: float = 240.0

## Seconds between core rings, once the armour is broken. Ten bullets per ring = 5 bullets/s,
## running alongside the 6.5 s laser cycle, so the combined phase-2 attack changes every ~2 s.
@export var core_ring_interval: float = 2.0

## Bullets per core ring. Spacing is TAU/10 = 36 deg; at 300 px from the hull that is a ~188 px
## gap, dodgeable at the player's 400 px/s.
@export var core_ring_count: int = 10

## Radians the ring's base angle advances between rings, so successive rings do not re-tread the
## same radial lanes and leave a permanent safe lane.
##
## Derived from the golden angle: `spacing * 0.381966` = `(TAU/10) * 0.381966` = 0.24, i.e. a
## spacing-to-step ratio of 2.618. The golden ratio is the irrational least well approximated by
## small rationals, which is exactly the "maximal lane coverage per ring" property wanted here.
##
## This value was 0.21 during planning and that was WRONG: 3 x 0.21 = 0.63 against a 0.6283
## spacing, so the ring collapsed onto three lanes and stayed there. Measured over 20 rings, 0.21
## leaves a largest lane gap of 31.8 % of the spacing; 0.24 leaves 9.0 %.
## `test_station_gunnery.gd` pins this — do not "tidy" it to a round fraction of TAU.
@export var core_ring_step: float = 0.24

## Damage per core ring bullet. Lower than the turret fan: ring bullets cannot be avoided by
## position alone, so they hit softer.
@export var core_bullet_damage: int = 10

## Core bullet speed (px/s). 52 % of player speed — the slowest of the three, because phase 2
## already has sweeping beams to dodge.
@export var core_bullet_speed: float = 210.0

## ── Reinforcements (EPIC sub-item 4b) ─────────────────────────────────────────
##
## Read ONCE by `StationReinforcements._ready()`, which copies them into its own fields and never
## reads this resource again — the same discipline as the laser and gunnery blocks above, and for
## the same reason: this `.tres` is a single process-wide instance, so anything reading through it
## at runtime is reading mutable global state.
##
## The squad TABLE is not here — which ships come from which edge, at what offsets, on what
## movement — because that is scene/level geometry rather than a stat, the same split that keeps
## `laser_emitter_radius` and the two gunnery `spawn_radius` values on their nodes.

## Seconds from the station spawning to the FIRST reinforcement squad.
##
## The opening belongs to the boss alone. Research finding 1 (the Flunky-Boss critique) is that
## adds arriving during a boss's introduction are the main way a boss ends up overshadowed by its
## own minions, and 8 s is roughly two turret volleys plus the time to read the hull.
@export var reinforcement_first_delay: float = 8.0

## Seconds between squads after the first.
##
## The top of research finding 4's 5-10 s attack-switch band, so a squad lands as an *event* that
## punctuates the 1.8 s turret cadence instead of blurring into it. Over a phase 1 of ~25-35 s that
## is 2-3 squads, 4-6 ships.
@export var reinforcement_interval: float = 10.0

## Hard ceiling on live reinforcements, i.e. two squads' worth.
##
## `spawn_next_squad()` skips the WHOLE squad when `alive + squad_size` would exceed this, never
## spawning half of one — so the real ceiling is exactly this number, not this number plus a squad.
## At a 10 s interval against a ~4 s transit it should never bind in normal play; it is the valve
## for a stalled fight where the player is killing nothing, and it is what stops the screen becoming
## unreadable next to a four-turret fan volley (research finding 2's tradeoff).
@export var reinforcement_max_alive: int = 4
