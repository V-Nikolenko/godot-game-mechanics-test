## BomberConfig - tuning resource for the Bomber (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.4).
## Extends ShipConfig (max_health, collision_damage, score_value).
##
## Flat by design (test_config_instance_isolation.gd): every field is a plain number, so the shallow
## `ShipConfig.privatise()` copy is complete. HP, contact damage and score are the legacy values; the rest
## are [judgement] starting defaults, tunable in the `.tres` without code changes.
##
## The ordnance fields (gravity bomb, mine, pursuit bomb, blast sizes) are what the bomber applies to a
## pooled `EnemyOrdnance` after `acquire()`, and what the round-lifetime sweep in
## `test_enemy_bullet_lifetime.gd` reads its per-kind speeds and times from.
class_name BomberConfig
extends ShipConfig

@export_group("Movement")
## Transit speed (px/s): APPROACH and the Assault exit's mover cap.
@export var max_speed: float = 240.0
@export var acceleration: float = 260.0
## Heading change cap (rad/s). The APPROACH plans its Dubins lead-in with the radius the mover can actually
## hold, `max_speed / min(max_turn_rate, acceleration / max_speed) x 1.1` (about 244 px): at `acceleration`
## 260 a 150 px circle at 240 px/s needs more than the mover gives (v^2 / a = 221 px).
@export var max_turn_rate: float = 1.6
## The slow, straight bombing run (px/s): the easy-to-hit window that is the Bomber's identity.
@export var run_speed: float = 170.0
## ESCAPE: turn away at `escape_turn_rate` (rad/s), accelerating to `escape_speed` for `escape_time` (s).
@export var escape_speed: float = 220.0
@export var escape_turn_rate: float = 1.4
@export var escape_time: float = 1.6
## Assault DISENGAGE speed (px/s).
@export var exit_speed: float = 260.0

@export_group("Prediction")
## Time constant of the player-velocity moving average (s).
@export var velocity_smoothing: float = 0.3
## Below this player speed the aim point is the player's position (px/s).
@export var min_lead_speed: float = 40.0
## Gravity bomb / pursuit aim point: `P + v * lead_factor * min(horizon, d / run_speed)`.
@export var lead_factor: float = 0.6
@export var horizon: float = 1.2
## Mine wall lead, undamped, on the bomber's own timeline: `t_wall = min(t_approach_left, approach_cap) + min(c,
## mine_horizon)`, `c = (run_length / 2) / run_speed + mine_arm_delay + wall_margin + (trigger_radius + arc_depth) / |v|`.
## The last term measures the margin to the middle mine's trigger EDGE (plan review B1c), so the middle mine is armed
## `wall_margin` seconds before the player reaches its trigger radius, at every speed. Only `c` is capped: the
## approach plans to where the wall will be on arrival, so a constant-velocity player's wall stands still.
@export var mine_horizon: float = 3.0
@export var wall_margin: float = 0.4

@export_group("Choice")
## A player moving between these speeds (px/s) gets a mine wall; faster gets a pursuit bomb.
@export var mine_speed_min: float = 150.0
@export var mine_speed_max: float = 440.0
## Below this range (px) a slower player gets a gravity bomb, else a pursuit bomb.
@export var gravity_range: float = 420.0
## Chance of taking the next ordnance type instead, so one response cannot be farmed.
@export var choice_jitter: float = 0.2

@export_group("Bombing line")
@export var run_length: float = 360.0
## Angled lead-in for a gravity / pursuit run (degrees).
@export var approach_angle: float = 35.0
## Assault: every endpoint and rest point stays this far inside the corridor rect (px).
@export var drop_margin: float = 64.0
@export var min_run_length: float = 160.0
## APPROACH re-plans from a fresh prediction this often until RUN entry (s), capped at `approach_cap`.
@export var replan_interval: float = 0.25
@export var approach_cap: float = 6.0
## A gravity bomb is released when the aim point is this far ahead along the run (px). At least
## `trigger_radius + gravity_bomb_speed * gravity_bomb_arm_delay` (116), or the bomb arms with a stationary player
## already inside its radius and goes off past them (asserted in test_bomber.gd).
@export var gravity_release_lead: float = 120.0
## A pursuit run passes BESIDE its aim point: the aim point is abeam the line's end, this far to the side (px), so
## the bomb launched at the midpoint has something to steer at and the bomber never overflies the player.
@export var pursuit_launch_range: float = 300.0
@export var mines_per_run_min: int = 3
@export var max_mines_per_run: int = 5
@export var mine_spacing: float = 70.0
## Largest lateral bow of the mine arc toward the oncoming player (px).
@export var arc_depth: float = 30.0

@export_group("Engagement")
## Assault: seconds before the bomber disengages (a running run defers it to the run's end).
@export var engage_seconds: float = 8.0
## Open Space: the orbit radius held between runs (px) and how long (s).
@export var standoff: float = 520.0
@export var reposition_min: float = 1.0
@export var reposition_max: float = 1.8

@export_group("Gravity bomb")
@export var gravity_bomb_speed: float = 120.0
@export var gravity_bomb_arm_delay: float = 0.3
@export var gravity_bomb_fuse: float = 1.0
@export var gravity_blast_radius: float = 48.0
@export var gravity_blast_damage: int = 40

@export_group("Mine")
## Ejection speed (px/s), decaying linearly to 0 over the ordnance's own eject time.
@export var mine_eject_speed: float = 160.0
## Seconds a mine's ejection decays over (applied to the mine by `Bomber.drop()`, so the brain's rest-point
## arithmetic and the ordnance share one number). `mine_eject_speed * mine_eject_time / 2` is the run distance past
## its rest point at which a mine is released.
@export var mine_eject_time: float = 0.3
@export var mine_arm_delay: float = 0.5
## Warning blink before a triggered mine goes off (s). Short on purpose: a player passing at
## `mine_speed_max` must still be inside the blast when it fires, so
## `(trigger_radius + mine_blast_radius) / mine_warning >= mine_speed_max` (asserted in test_bomber.gd).
@export var mine_warning: float = 0.25
@export var mine_life: float = 8.0
## Shortest time between two runs (s): sizes the mine pool with `EnemyOrdnanceScenes.pool_size_for()`.
@export var min_run_period: float = 4.0
## Proximity trigger radius shared by gravity bombs and mines (px).
@export var trigger_radius: float = 80.0
@export var mine_blast_radius: float = 48.0
@export var mine_blast_damage: int = 30

@export_group("Pursuit bomb")
@export var pursuit_launch_speed: float = 90.0
@export var pursuit_steer_window: float = 1.5
@export var pursuit_turn_rate: float = 1.2
@export var pursuit_final_speed: float = 380.0
## Look-ahead (s) of the point the bomb steers at.
@export var pursuit_lead: float = 0.6
@export var pursuit_trigger_radius: float = 48.0
@export var pursuit_blast_radius: float = 40.0
@export var pursuit_blast_damage: int = 30

@export_group("Idle")
## Open Space hub only (epic §2.10; task cmuyk2qqh0099oa2xbltzoust). The bomber patrols a slow ring round its
## `patrol_anchor` until the player comes within `perceive_radius`, and goes home once the player is further than
## `lose_radius` (px). `lose_radius` sits above the largest actor-player distance its own cycle deliberately opens
## (`max(standoff + escape_speed * escape_time, mine_horizon * mine_speed_max + run_length / 2) + 100`), so the
## cycle itself never counts as losing the player.
@export var perceive_radius: float = 650.0
@export var lose_radius: float = 1700.0
## The beat between perceiving the player and fighting (s).
@export var notice_time: float = 0.35
## The patrol ring's radius round `patrol_anchor` (px) and its angular speed (rad/s).
@export var idle_radius: float = 150.0
@export var idle_speed: float = 0.5

@export_group("Rail")
## While a rail owns the bomber: a gravity bomb DOWN at `rail_bomb_speed` every `rail_bomb_interval`
## seconds, today's bomb.
@export var rail_bomb_interval: float = 1.2
@export var rail_bomb_speed: float = 120.0
## How far below the bomber a rail bomb is aimed (px): the legacy 5 s fuse at `rail_bomb_speed`.
@export var rail_bomb_range: float = 600.0
