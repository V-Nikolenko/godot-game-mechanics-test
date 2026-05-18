## USweepMovement — U-shaped sweep path.
##
## Phase 1 (0 → curve_duration):
##   Half-ellipse arc from the spawn point, dipping downward and sweeping left.
##   Spawn at top-right off-screen; the arc dips below the screen and exits
##   at the left, at the same Y level as entry.
##
## Phase 2 (curve_duration → ∞):
##   Straight upward from the arc exit point at the same speed the arc ends with,
##   so the transition is seamless — no separate exit_speed parameter.
##
## Exit speed is derived from the arc tangent at θ = π:
##   speed = sweep_depth * π / curve_duration
##
## Coordinate convention: +X = right, +Y = down.
##
## Typical usage in WaveBuilder:
##   builder.spawn_entry(builder.FIGHTER, Vector2(320, -60),
##       builder.u_sweep(400, 500, 3.0))
##   — spawns off-screen top-right; sweeps 400 px left, dips 500 px down,
##     takes 3 s, then continues upward at the arc's exit speed.
class_name USweepMovement
extends MovementResource

## Horizontal distance between entry and exit of the U (px).
@export var sweep_width: float  = 400.0
## Depth of the U bend below the spawn Y (px). Make this large enough to dip off-screen.
@export var sweep_depth: float  = 500.0
## Seconds to complete the U curve phase.
@export_range(0.01, 60.0, 0.1) var curve_duration: float = 3.0

func sample(t: float) -> Vector2:
	if t <= curve_duration:
		## Parametric half-ellipse: θ goes 0 → π as t goes 0 → curve_duration.
		## x: 0 → -sweep_width   (sweeps left)
		## y: 0 → sweep_depth → 0  (dips down and returns to same level)
		var theta: float = (t / curve_duration) * PI
		var x: float     = -sweep_width * 0.5 * (1.0 - cos(theta))
		var y: float     = sweep_depth * sin(theta)
		return Vector2(x, y)
	else:
		## Straight up from the arc exit point (-sweep_width, 0).
		## Speed matches the arc tangent at θ = π: sweep_depth * π / curve_duration.
		var exit_speed: float = sweep_depth * PI / curve_duration
		var post: float = t - curve_duration
		return Vector2(-sweep_width, -exit_speed * post)

func total_duration() -> float:
	return INF
