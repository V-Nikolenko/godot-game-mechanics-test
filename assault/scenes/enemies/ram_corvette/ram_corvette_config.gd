## RamCorvetteConfig - tuning resource for the Ram Corvette (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md
## §2.6; task t16). Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. The charge fields (LINE_UP / WIND_UP / CHARGE / WIDE_TURN)
## are appended by t17.
class_name RamCorvetteConfig
extends ShipConfig

@export_group("Armour")
## HP of each of the three `ArmorPlate`s: one rocket of either kind breaks one, two Sniper Shots (40) do.
@export var plate_health: int = 50
## Contact damage once every plate is gone (`collision_damage`, 50, is the armoured value).
@export var exposed_collision_damage: int = 60
## The ARMOR contact profile's shove (px/s) while armoured; 0 once exposed (the armour is what staggers).
@export var armor_shove_speed: float = 260.0

@export_group("Movement")
## APPROACH: the plain intercept's speed (px/s) and the mover's caps.
@export var cruise_speed: float = 280.0
@export var acceleration: float = 500.0
@export var max_turn_rate: float = 2.2

@export_group("Engagement")
## Assault: seconds before the Corvette disengages.
@export var engage_seconds: float = 4.5
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 500.0
