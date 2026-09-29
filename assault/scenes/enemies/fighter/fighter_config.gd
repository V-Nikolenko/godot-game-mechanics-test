## FighterConfig — tuning resource for the Fighter (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md
## §2.4.2; task t8a-fighter-shell). Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number or string, so
## the shallow `ShipConfig.privatise()` copy is complete. All values are [judgement] starting
## defaults except the legacy ones (HP, contact, score, and the Rail group), so they can be tuned in
## the `.tres` without code changes.
class_name FighterConfig
extends ShipConfig

@export_group("Movement")
@export var max_speed: float = 300.0
@export var acceleration: float = 700.0
@export var braking: float = 700.0
## Heading change cap, rad/s. Pinned: `turn_rate × max_speed ≤ acceleration`, so the mover's
## acceleration limit can follow the curve. The turn radius is `max_speed / turn_rate`.
@export var turn_rate: float = 1.8

@export_group("Geometry")
## Distance from the player a pass starts at (px).
@export var standoff_radius: float = 480.0
## Lane distance: how far beside the player a pass goes (px).
@export var pass_offset: float = 160.0
## The second flank's extra lane distance, so two flanks never share a line (px).
@export var flank_lane_gap: float = 100.0
## RUN_IN seeks this far ahead along the pass line (px).
@export var lookahead: float = 220.0
## How far off its start point a run may begin (px).
@export var start_tolerance: float = 80.0
## Assault: the shortest flank run the corridor may leave (px).
@export var min_run_length: float = 200.0
## REPOSITION never routes within this of the player (px).
@export var reposition_min_radius: float = 288.0
## REPOSITION hands over to RUN_IN after this long whatever the position (s).
@export var reposition_max: float = 3.0
## Passes per cycle.
@export var passes: int = 2

@export_group("Attack")
## A burst opportunity opens inside this distance to the player (px).
@export var fire_range: float = 520.0
## Below this distance the burst is FORWARD; at `forward_range + mode_hysteresis` or more it is
## AIMED; in between the last mode holds (px).
@export var forward_range: float = 300.0
@export var mode_hysteresis: float = 60.0
## A FORWARD burst needs the nose within this of the player (deg).
@export var nose_cone_deg: float = 12.0
## The yellow light shows this long before a burst (s).
@export var burst_telegraph: float = 0.3
## The fewest seconds between the starts of two bursts (s). Sizes the pools and the level-1
## shots-per-second gate, so the brain enforces it and the tests read it.
@export var min_burst_period: float = 1.2
@export var aimed_min: int = 3
@export var aimed_max: int = 5
@export var aimed_gap: float = 0.10
@export var aimed_speed: float = 300.0
@export var aimed_damage: int = 8
## 0 = direct aim at the player, 1 = lead the intercept (`TargetInfo.aim_direction`).
@export var aimed_accuracy: float = 0.7
## Per-shot jitter, half-angle in radians.
@export var aimed_spread: float = 0.035
@export var forward_min: int = 5
@export var forward_max: int = 7
@export var forward_gap: float = 0.05
@export var forward_speed: float = 420.0
@export var forward_damage: int = 6
@export var forward_spread: float = 0.13

@export_group("Tactics")
## Assault only: seconds in the fight before DISENGAGE.
@export var engage_seconds: float = 6.0
@export var exit_speed: float = 520.0
## Squad REARs hold a ring at this distance (px).
@export var rear_standoff_radius: float = 560.0
## A flank with no window from its leader attacks after this long at its start point (s).
@export var flank_wait_max: float = 2.0

@export_group("Rail")
## The rail fallback (plan §2.8): what a fighter does while an `EnemyPathMover` owns its motion.
## Read only by `FighterBrain.on_suspended()`; an AI fighter ignores `aim_mode`.
@export var fire_interval: float = 0.8
@export var bullet_damage: int = 8
## "PLAYER" = aimed rail fire, "FORWARD" = fire along the nose (spawn prop `shoot_forward()`).
@export var aim_mode: String = "PLAYER"
@export var rail_aimed_speed: float = 250.0
@export var rail_forward_speed: float = 420.0
@export var rail_forward_interval: float = 0.3
