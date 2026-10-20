## A decaying drift: the velocity a hazard adds to a ship without ever writing the ship's own velocity.
## The caller feeds it the field acceleration each physics tick and adds the returned velocity to its motion.
## Terminal drift in a constant field is `a * (1 - resistance) / k` with `k = ln 2 / half_life` (1.98 /s).
class_name HazardDrift
extends RefCounted

## Drift below this speed (px/s) snaps to zero, so the pass-through rule holds once a field is left.
const SNAP_SPEED := 0.5

var velocity: Vector2 = Vector2.ZERO
var half_life: float = 0.35


func step(accel: Vector2, resistance: float, delta: float) -> Vector2:
	velocity += accel * (1.0 - resistance) * delta
	velocity *= pow(0.5, delta / half_life)
	if velocity.length() < SNAP_SPEED:
		velocity = Vector2.ZERO
	return velocity


func reset() -> void:
	velocity = Vector2.ZERO
