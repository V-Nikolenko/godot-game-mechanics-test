## LaserEmitter - a destructible laser fence post (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.11; Phase 8 t10). Behaviour: `ENEMY.md` beside
## this file; the fence it belongs to is `assault/scenes/structures/laser_fence/`.
##
## A `BaseEnemy` with **no brain and no mover**: it never moves itself (the fence's `AssaultDrift` carries both posts), never fires and refuses tows.
## Contact: `ContactProfile` NONE and no `ContactHitBox`. The player's mining beam treats it as a target, never a wall (`is_laser_blocking()` false).
## `counts_as_escape` is false in its `.tres`.
##
## It answers the duck-typed `is_fence_post() -> true`, so a `ShieldGenerator` never shields it ("shoot a post to drop the fence" stays the cheap
## counterplay, plan §2.10.5). The fence owns the beam between its two posts, the posts' owner group and their `StateLight`.
class_name LaserEmitter
extends BaseEnemy

## The body / hurtbox circle's radius (the scene's shared `CircleShape2D`).
const BODY_RADIUS := 18.0
const HOUSING_COLOR := Color(0.2, 0.2, 0.24, 1.0)
const RIM_COLOR := Color(0.6, 0.35, 0.35, 1.0)
const LENS_RADIUS := 7.0
const LENS_COLOR := Color(1.0, 0.3, 0.3, 1.0)

@export var config: LaserEmitterConfig = load("res://assault/scenes/enemies/laser_emitter/laser_emitter_config.tres")


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
	queue_redraw()


## A fence post: a shield generator never bubbles one.
func is_fence_post() -> bool:
	return true


## The player's mining beam passes over the post and burns it (it is a target, not a wall).
func is_laser_blocking() -> bool:
	return false


## The post's `StateLight`, driven by its fence.
func state_light() -> StateLight:
	return get_node_or_null("StateLight") as StateLight


## Placeholder art (the art task replaces it): a dark post with a red lens.
func _draw() -> void:
	draw_circle(Vector2.ZERO, BODY_RADIUS, HOUSING_COLOR)
	draw_arc(Vector2.ZERO, BODY_RADIUS, 0.0, TAU, 24, RIM_COLOR, 2.0)
	draw_circle(Vector2.ZERO, LENS_RADIUS, LENS_COLOR)
