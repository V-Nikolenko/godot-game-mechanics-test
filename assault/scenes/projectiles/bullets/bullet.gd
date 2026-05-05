class_name Bullet
extends Area2D

signal expired

@export var speed: float = 500.0
## 0 = no cap (despawn only when off-screen).
@export var range_px: float = 0.0
## Damage applied via the child HitBox. Pushed in _ready().
@export var damage: int = 50

var _traveled: float = 0.0

func _ready() -> void:
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = damage

func reset() -> void:
	rotation = 0.0
	_traveled = 0.0

func _physics_process(delta: float) -> void:
	var step := speed * delta
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * step
	if range_px > 0.0:
		_traveled += step
		if _traveled >= range_px:
			expired.emit()
			queue_free()

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	expired.emit()

func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()
