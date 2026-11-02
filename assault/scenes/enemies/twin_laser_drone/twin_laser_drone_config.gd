## TwinLaserDroneConfig - a Twin-Laser Drone's flat stats (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12; Phase 8 t12).
## Extends ShipConfig (max_health, collision_damage, score_value, the hazard and wreck fields).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow `ShipConfig.privatise()` copy is
## complete. Values are the plan's [judgement] starting values (§2.21). The rig reads the "Rig" group from drone A's private copy, so a
## pair is always tuned by one config; the beam's own numbers (telegraph, damage, widths) live in `twin_beam.tscn`, never here.
class_name TwinLaserDroneConfig
extends ShipConfig

@export_group("Movement")
## Cap on the drone's own (non-boost) speed, px/s: FORM and the hold.
@export var max_speed: float = 300.0
@export var acceleration: float = 900.0

@export_group("Rig")
## The beam's length L: the distance the two drones hold between them (px).
@export var rig_length: float = 420.0
## Largest | |A - B| - L | that still counts as holding the length (px). Past it in TELEGRAPH / ADVANCE the beam strains.
@export var length_tolerance: float = 16.0
## A strain held this long collapses the beam (s).
@export var strain_seconds: float = 0.15
## The wall's advance speed (px/s); slower than the player's cruise speed (the §2.3 twin fairness row).
@export var advance_speed: float = 240.0
## Distance from the player to the line when it forms (px).
@export var standoff: float = 260.0
## How far past the player's latched position the line keeps advancing (px).
@export var overshoot: float = 200.0
## A drone within this of its slot is "on the slot" (px).
@export var slot_tolerance: float = 24.0
## FORM gives up after this long (s) and the pair BREAKs and retries.
@export var form_timeout: float = 3.0
## BREAK: the drones separate along the axis for this long (s), at this speed (px/s).
@export var break_seconds: float = 1.2
@export var break_speed: float = 260.0
## Open Space: the pause between attacks, drawn from the leader's rng (s).
@export var attack_period_min: float = 4.0
@export var attack_period_max: float = 6.0

@export_group("Assault")
## Seconds before an Assault drone disengages (one attack per life; a budget that runs out in TELEGRAPH or ADVANCE lets it finish).
@export var engage_seconds: float = 8.0
## DISENGAGE speed (px/s).
@export var exit_speed: float = 420.0
