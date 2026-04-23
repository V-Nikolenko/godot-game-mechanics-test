## CurveMovement — follows a Curve2D drawn in the Godot editor.
##
## Usage:
##   1. In the FileSystem dock: right-click → New Resource → Curve2D.
##      Edit waypoints in the Godot curve editor.
##   2. Create a CurveMovement .tres and assign the Curve2D to `path`.
##   3. Set `duration` to control total travel time over the curve's full length.
##
## Curve coordinates are in screen space (+Y = down).
## The curve's origin (0,0) maps to the ship's spawn position.
## Set `loop = true` for patrol paths that repeat indefinitely.
class_name CurveMovement
extends MovementResource

@export var path: Curve2D
@export_range(0.01, 60.0, 0.1) var duration: float = 4.0
@export var loop: bool = false

func sample(t: float) -> Vector2:
	if not is_instance_valid(path) or path.point_count < 2:
		return Vector2.ZERO
	if duration <= 0.0:
		return Vector2.ZERO
	var effective_t: float = fmod(t, duration) if loop else t
	var progress: float = clampf(effective_t / duration, 0.0, 1.0)
	return path.sample_baked(path.get_baked_length() * progress)

func total_duration() -> float:
	return INF if loop else duration
