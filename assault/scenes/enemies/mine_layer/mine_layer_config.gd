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

@export_group("Passes")
## Smoothing (s) of the player's velocity v-bar, and the speed (px/s) at or above which the player is "moving".
@export var velocity_smoothing: float = 0.5
@export var frame_speed: float = 60.0
## One pass: a `pass_length` px line of `mines_per_pass` mines, `mine_step` px apart along the axis.
@export var pass_length: float = 600.0
@export var mine_step: float = 100.0
@export var mines_per_pass: int = 6
## ZIGZAG puts the mines on the vertices at +-`zigzag_amplitude`; ARC bows them `arc_depth` toward the player.
@export var zigzag_amplitude: float = 35.0
@export var arc_depth: float = 110.0
## Chance a pass is an ARC rather than a ZIGZAG.
@export var arc_chance: float = 0.5
## LEAD form: the centre this far ahead of the predicted player (px). FENCE form: this far from the player toward the
## layer (px). Assault: this far above the player (px).
@export var ahead_distance: float = 260.0
@export var fence_distance: float = 320.0
@export var assault_ahead: float = 220.0
## LEAD form: the cap on the line's own lead time (s), and the latest arrival the scan tries (s).
@export var lead_horizon: float = 3.0
@export var lead_scan_cap: float = 6.0
## The run-in R is this far before the start S (px); the plan freezes within `commit_distance` of R; the run-in starts
## within `path_lookahead` of R, which is also how far ahead the run-in and LAY aim (px).
@export var run_in: float = 150.0
@export var commit_distance: float = 200.0
@export var path_lookahead: float = 60.0
## Open Space spread: a new centre this far (px) from every earlier pass that still has a live mine.
@export var min_pass_separation: float = 380.0
## Open Space backstop: an APPROACH this long (s) without a frozen plan takes the fence fallback.
@export var approach_max_seconds: float = 6.0
## Open Space BREAK_OFF: `break_speed` (px/s) for `break_seconds`; then REPOSITION at `standoff_range` (px) for a period
## drawn from `pass_period_min..pass_period_max` (s).
@export var break_speed: float = 260.0
@export var break_seconds: float = 1.2
@export var standoff_range: float = 600.0
@export var pass_period_min: float = 5.0
@export var pass_period_max: float = 7.0
## Tail drop: a player within `tail_range` (px) inside the rear `tail_cone_deg` cone gets a mine, at most every
## `tail_drop_cooldown` (s).
@export var tail_range: float = 280.0
@export var tail_cone_deg: float = 60.0
@export var tail_drop_cooldown: float = 2.5
## Assault: every mine stays this far (px) inside `EnemyWorld.view_rect()`.
@export var view_margin: float = 64.0
