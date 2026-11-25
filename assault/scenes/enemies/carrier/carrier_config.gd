## CarrierConfig - tuning for the Carrier (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.6, §2.16; Phase 10 t6, task plan
## docs/plans/cmwafsrb700afqs2yd3qqvvrb/3-plan.md). Extends ShipConfig (max_health = the armoured hull's bar, which only the core's death empties;
## collision_damage = the ARMOR touch; score_value; the explicit hazard profile 0.5 / 120 / 1.0: a capital ship shrugs off pull and slow).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number (or, for the hangar payloads, a scene path `String`), so the shallow `ShipConfig.privatise()` copy is complete.
## Starting values [judgement] (§2.16) unless marked. The parts' HP live in the scene (each `EnemyModule.max_health`); weapons (t7: mount and ring
## tuning lives in their scenes, these are the host's own numbers) and hangars (t8: payload paths, door timings, caps, the launch schedule)
## add their own groups.
class_name CarrierConfig
extends ShipConfig

@export_group("Movement")
## Open Space cruise cap (px/s) with both engines.
@export var max_speed: float = 70.0
@export var acceleration: float = 40.0
@export var braking: float = 40.0
## Heading change cap (rad/s) with both engines: a 90 degree turn takes about 4.5 s.
@export var max_turn_rate: float = 0.35

@export_group("Engines")
## Turn-rate factors with one / no engine left (module death changes movement).
@export var one_engine_turn: float = 0.5
@export var no_engine_turn: float = 0.15
## Open Space speed factors with one / no engine left.
@export var one_engine_speed: float = 0.8
@export var no_engine_speed: float = 0.4
## With exactly one engine lost the hull sags toward the dead side at this rate (rad/s) while it holds a heading ...
@export var list_rate: float = 0.06
## ... until it is this far off (degrees), then it turns back (the list's deadband, t6 D3).
@export var list_hold_deg: float = 10.0

@export_group("Screen")
## Open Space: the band it holds the player in (px). It closes only from beyond the band and opens only from inside it.
@export var screen_range_min: float = 600.0
@export var screen_range_max: float = 950.0
## It never strays further than this from `patrol_anchor` (px), in SCREEN and in PANIC alike.
@export var leash_radius: float = 900.0

@export_group("Core")
## The core opens (becomes vulnerable, PANIC) once this many outer parts (engines, guns, hangars) are wrecks. Owner choice 1.
@export var core_exposure_count: int = 3

@export_group("Assault")
## The constant crossing speed, straight down (px/s): engines, panic, hazards and EMP never change it.
@export var assault_cross_speed: float = 90.0
## The mover's cap in Assault (px/s): above the hypotenuse of the crossing and the sway, so it never slows the descent.
@export var assault_max_speed: float = 110.0
## The lateral sway that keeps the player in a live battery's arc (px/s), times 1 / `one_engine_sway` / `no_engine_sway` with 2 / 1 / 0 engines ...
@export var assault_sway_speed: float = 30.0
@export var one_engine_sway: float = 0.5
@export var no_engine_sway: float = 0.1
## ... leashed to this far either side of the spawn x (px): the level-1 column lanes are narrow (§2.13).
@export var assault_sway_leash: float = 30.0

@export_group("Geometry")
## Every part's hurtbox stays within this far of the hull centre in x (px). Level 1's lane maths (§2.13) depend on it; pinned by test_carrier.gd.
@export var module_x_extent: float = 100.0

@export_group("Idle")
## Open Space hub only: a slow orbit round `patrol_anchor` until the player comes within `perceive_radius`; home again beyond `lose_radius` (px).
@export var perceive_radius: float = 1100.0
@export var lose_radius: float = 1800.0
## The beat between perceiving the player and screening (s).
@export var notice_time: float = 0.6
## The idle orbit's radius (px) and angular speed (rad/s).
@export var idle_radius: float = 220.0
@export var idle_speed: float = 0.12

@export_group("Weapons")
## The anti-approach pulse (`carrier_pulse_ring.tscn`) starts when the player is strictly closer than this to the hull centre (px) ...
@export var pulse_trigger_range: float = 340.0
## ... and no sooner than this after the previous ring's start (s).
@export var pulse_cooldown: float = 5.0
## The dorsal missile bank fires only at a player farther than this from the hull centre (px): rockets punish standing off, the pulse punishes hugging.
@export var missile_min_range: float = 450.0
## Written onto the bank's mount when it is built (s; the rocket battery scene's own is 5.5) ...
@export var missile_cooldown: float = 7.0
## ... with this share of PURSUIT rockets (1 = PURSUIT only).
@export var missile_pursuit_chance: float = 1.0

@export_group("Panic")
## In PANIC the pulse cooldown is multiplied by this ...
@export var panic_pulse_factor: float = 0.5
## ... and each side battery's `cooldown_seconds` by this (the bow and the bank keep theirs).
@export var panic_battery_factor: float = 0.7

@export_group("Hangars")
## The payload of each hangar, as scene paths (flat: a String, loaded once at the first launch). Open Space: swarm drones from the port hangar,
## fighters from the starboard one ...
@export var hangar_port_scene: String = "res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn"
@export var hangar_starboard_scene: String = "res://assault/scenes/enemies/fighter/fighter.tscn"
## ... and swarm drones from both in Assault (owner choice 6: they are counted in level 1's drone gate).
@export var assault_hangar_scene: String = "res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn"
## Children per launch, Open Space (clamped to the caps) / Assault.
@export var launch_count: int = 2
@export var assault_launch_count: int = 2
## The door telegraph (s): OPENING (doors sliding apart, light yellow, the hangar hittable) before the children come out ...
@export var door_open_seconds: float = 0.8
## ... and OPEN after them (still hittable), then CLOSED (sealed again).
@export var door_hold_seconds: float = 2.0
## Open Space: a hangar's next OPENING no sooner than this after its previous one (s) ...
@export var launch_period: float = 9.0
## ... and only while it has fewer live children than this, and the carrier fewer than `carrier_live_cap` (a hangar at its cap keeps its doors shut).
@export var hangar_live_cap: int = 3
@export var carrier_live_cap: int = 6
## The port hangar's first OPENING this long after the hull centre first enters the Assault view, or after it engages in Open Space (s) ...
@export var first_launch_delay: float = 3.0
## ... and the starboard hangar's this long after that (s): 7.0 s. In Assault each hangar launches once per life.
@export var starboard_launch_delay: float = 4.0
## A child leaves the hangar mouth with this committed outward boost (px/s, s).
@export var launch_boost_speed: float = 300.0
@export var launch_boost_seconds: float = 0.4
