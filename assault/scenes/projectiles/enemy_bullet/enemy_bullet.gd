class_name EnemyBullet
extends Area2D

signal expired

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

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
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
