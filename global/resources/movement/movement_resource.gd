## MovementResource — abstract base for all path types.
##
## Concrete subclasses implement sample() and optionally override total_duration().
## EnemyPathMover calls sample(t) each frame instead of match-on-enum.
##
## Coordinate convention: +X = screen-right, +Y = screen-down.
## sample() returns a DISPLACEMENT from the spawn position (not an absolute world pos).
class_name MovementResource
extends Resource

## Returns the screen-space displacement at time t seconds from spawn.
## Override in each subclass.
func sample(_t: float) -> Vector2:
	return Vector2.ZERO

## Returns the total movement duration in seconds, or INF if unlimited.
## Used by EnemyPathMover to determine when FREE_ON_DURATION triggers.
## Override in subclasses that have a finite lifetime.
func total_duration() -> float:
	return INF
