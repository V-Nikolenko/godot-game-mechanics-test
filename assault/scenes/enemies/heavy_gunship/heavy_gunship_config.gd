## HeavyGunshipConfig - tuning for the Heavy Gunship (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.4, §2.16; Phase 10 t4, task plan
## docs/plans/cmwafsrb100a7qs2yvre9y1o2/3-plan.md). Extends ShipConfig (max_health = the hull's phase bar, collision_damage, score_value, hazards).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is complete.
## The values are [judgement] starting values (§2.16) except the Assault budget and exit, which are derived from the Cloud Descent deadline
## (§2.4.3). The parts' HP and the guns' tuning live in the scene: each `EnemyModule`'s `max_health`, each mount scene's exports and each
## `TurretMountSlot`'s `traverse_deg_override`. The Phases and Defense groups (overheat, vent, emergency, cannon shield) are t5's (task plan
## docs/plans/cmwafsrb400abqs2yt38khcyu/3-plan.md), all §2.16 starting values.
class_name HeavyGunshipConfig
extends ShipConfig

@export_group("Movement")
## Cruise cap (px/s): APPROACH, the arc and the hub idle. A heavy hull: slower than the Missile Corvette's 210.
@export var max_speed: float = 140.0
@export var acceleration: float = 120.0
## Deceleration cap (px/s^2): slow to get going, quick to shed speed (retro thrust), so the arc and the end of a break-away boost do not
## overshoot the held range. [judgement, t4: the 120 px/s^2 seek alone swung the range by ±250 px against a moving player]
@export var braking: float = 360.0
## Heading change cap (rad/s): a full side swap (180 degrees) takes about 3.5 s, readable.
@export var max_turn_rate: float = 0.9

@export_group("Range")
## Open Space: the distance it holds from the player (px).
@export var preferred_range: float = 560.0
## Assault: the distance it holds (px).
@export var assault_preferred_range: float = 420.0
## The held range drifts by up to this much (px) over a 7-10 s period.
@export var range_drift: float = 90.0
## APPROACH hands over to BROADSIDE inside this slack round the held range (px).
@export var range_tolerance: float = 100.0
## Closer than this the player triggers a break-away boost (px).
@export var min_range: float = 260.0

@export_group("Arc")
## Open Space: the wide arc it strafes round the player (rad/s).
@export var orbit_angular_speed: float = 0.16
## Assault: the arc's speed (rad/s). Faster than the open sky's so the corridor sweep never parks (§2.12 lever 4 halves it).
@export var assault_orbit_angular_speed: float = 0.26
## Assault: the arc stays within this many degrees either side of straight above the player and reverses at its ends.
@export var assault_arc_half_deg: float = 70.0
## It reverses the arc after a random time in this range (s).
@export var reversal_min: float = 5.0
@export var reversal_max: float = 8.0

@export_group("Tactics")
## BREAK_AWAY: one committed boost this fast (px/s) for this long (s) when the player comes inside `min_range`, then no other for `break_rearm` s.
@export var break_speed: float = 360.0
@export var break_seconds: float = 0.7
@export var break_rearm: float = 3.0

@export_group("Phases")
## The hull phase is read off the root `Health` fraction: CONTROLLED at or above `overheat_ratio`, OVERHEAT at or above `emergency_ratio`,
## EMERGENCY below. Entering a band is one way (a repair never steps back).
@export var overheat_ratio: float = 0.6
@export var emergency_ratio: float = 0.3
## OVERHEAT: each gun burst adds 1 heat when it ends; at `heat_limit` the hull VENTs for `vent_seconds` (both vents open: vulnerable and
## orange), its `max_speed` scaled by `vent_speed_factor`.
@export var heat_limit: int = 4
@export var vent_seconds: float = 2.2
@export var vent_speed_factor: float = 0.6
## EMERGENCY: a committed boost away (`emergency_boost_speed` px/s for `emergency_boost_seconds` s) every `emergency_period` s; from each
## boost's end the rear Missiles mount may fire for `missile_window` s at a player inside the rear `missile_rear_arc_deg`.
@export var emergency_period: float = 5.0
@export var emergency_boost_speed: float = 420.0
@export var emergency_boost_seconds: float = 0.9
@export var missile_window: float = 2.0
@export var missile_rear_arc_deg: float = 200.0
## EMERGENCY's held range: `emergency_range` in Open Space (px), `assault_preferred_range` + `emergency_assault_extra` in Assault.
@export var emergency_range: float = 800.0
@export var emergency_assault_extra: float = 120.0

@export_group("Defense")
## The nose cannon's local `EnemyShield` (Ph5), written onto `Modules/Cannon/Shield`: a frontal arc that protects the cannon's own HP only.
@export var shield_arc_deg: float = 120.0
@export var shield_capacity: int = 60
@export var shield_regen_delay: float = 2.0
@export var shield_regen_seconds: float = 4.0
@export var shield_reboot_seconds: float = 5.0

@export_group("Engagement")
## Assault: seconds before the gunship disengages. Derived from the Cloud Descent deadline (§2.4.3).
@export var engage_seconds: float = 9.0
## Assault DISENGAGE speed (px/s) and acceleration (px/s^2), both written onto the mover (the cruise 120 px/s^2 would make the exit too slow).
@export var exit_speed: float = 300.0
@export var exit_acceleration: float = 240.0

@export_group("Idle")
## Open Space hub only: it patrols a slow ring round `patrol_anchor` until the player comes within `perceive_radius`, and goes home once the
## player is further than `lose_radius` (px). `lose_radius` sits above `preferred_range + range_drift + range_tolerance` (750), so its own arc
## never reads as losing the player.
@export var perceive_radius: float = 900.0
@export var lose_radius: float = 1500.0
## The beat between perceiving the player and fighting (s).
@export var notice_time: float = 0.6
## The patrol ring's radius round `patrol_anchor` (px) and its angular speed (rad/s).
@export var idle_radius: float = 180.0
@export var idle_speed: float = 0.4
