## MineLayerConfig - tuning resource for the Mine Layer (docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.11).
## Extends ShipConfig (max_health, collision_damage, score_value, the hazard and wreck fields).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. The values are [judgement] starting defaults, tunable in the `.tres`.
##
## There are NO trigger, warning or blast fields on purpose: the mine variant scenes own those numbers
## (`EnemyMineScenes.export_of`), and `MineLayer.drop_mine()` overrides only arm delay, eject and life.
## `max_live_mines` and the `w_<variant>` weights are what `EnemyMineScenes.pool_size_for()` reads.
class_name MineLayerConfig
extends ShipConfig

@export_group("Movement")
## Transit speed (px/s): APPROACH and the mover's cap.
@export var max_speed: float = 240.0
@export var acceleration: float = 420.0
## Heading change cap (rad/s).
@export var max_turn_rate: float = 2.4
## Speed while laying (px/s): the slow, readable line.
@export var lay_speed: float = 170.0
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 300.0

@export_group("Mines")
@export var mine_arm_delay: float = 0.5
## Ejection speed (px/s) decaying to 0 over `mine_eject_time` (s); the rest point is `speed * time / 2` away.
@export var mine_eject_speed: float = 120.0
@export var mine_eject_time: float = 0.3
## A laid mine's life in Assault (s).
@export var assault_mine_life: float = 9.0
## In Open Space a mine never fizzles (0), and `open_space_mine_backstop` (s) is its lifetime backstop.
@export var open_space_mine_life: float = 0.0
@export var open_space_mine_backstop: float = 240.0
## Live mines the layer may have out at once, per mode (Open Space / Assault).
@export var max_live_mines: int = 18
@export var assault_max_live_mines: int = 8
## Variant weights: a PROXIMITY pool is `max_live_mines + 2`, any other variant with a weight above 0 gets
## `ceil(max_live_mines * w / sum of weights) + 2`, a weight of 0 builds no pool.
@export var w_proximity: float = 0.5
@export var w_chain: float = 0.2
@export var w_pulse: float = 0.15
@export var w_homing: float = 0.15
@export var w_drifting: float = 0.0
@export var w_emp: float = 0.0

@export_group("Engagement")
## Assault: seconds before the layer disengages.
@export var engage_seconds: float = 9.0

@export_group("Rail")
## While a rail owns the layer: a proximity mine at the dispenser every `rail_mine_interval` seconds.
@export var rail_mine_interval: float = 1.6
