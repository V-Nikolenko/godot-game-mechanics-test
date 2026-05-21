class_name EnemyBullet
extends Area2D

signal expired

## Arena bounds matching arena_camera.gd (cam.global_position=(320,180),
## H_LIMIT=50, V_LIMIT=190, viewport 640×360):
##   x ∈ [-50, 690]   (640 + 2×50)
##   y ∈ [-190, 550]  (360 + 2×190)
## A small margin (32 px) lets bullets travel just past the edge before
## expiring, matching the visual boundary cleanly.
const _ARENA_MARGIN : float = 32.0
const _ARENA_LEFT   : float = -50.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float =  690.0 + _ARENA_MARGIN
const _ARENA_TOP    : float = -190.0 - _ARENA_MARGIN
const _ARENA_BOTTOM : float =  550.0 + _ARENA_MARGIN

@export var speed: float = 250.0

var _direction: Vector2 = Vector2.DOWN

func reset() -> void:
	_direction = Vector2.DOWN
	rotation = 0.0
	speed = 250.0

func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()
	rotation = _direction.angle() - PI / 2.0

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	# Expire when the bullet leaves the full 740×740 arena, not just the viewport.
	var p := global_position
	if p.x < _ARENA_LEFT or p.x > _ARENA_RIGHT \
			or p.y < _ARENA_TOP or p.y > _ARENA_BOTTOM:
		expired.emit()

func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()

## Reflect-mode flip: reverses this enemy bullet so it becomes a friendly projectile.
## Layers/mask are swapped to player-projectile (64) hitting enemy hurt (513).
func become_friendly() -> void:
	_direction = -_direction
	rotation += PI
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.collision_layer = 64
		hb.collision_mask = 513
