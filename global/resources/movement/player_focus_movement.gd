## PlayerFocusMovement — makes a ship fly straight toward the player's position
## at spawn time, then continue in that direction until it exits the screen.
##
## `direction` is injected by EnemyPathMover._ready() after duplicating the resource.
## Do NOT export `direction` — each ship must get its own instance with its own direction.
class_name PlayerFocusMovement
extends MovementResource

## Fly speed in px/s.
@export var speed: float = 220.0
## Set at runtime by EnemyPathMover. Not exported — never shared between ships.
var direction: Vector2 = Vector2.DOWN

func sample(t: float) -> Vector2:
	return direction * speed * t
