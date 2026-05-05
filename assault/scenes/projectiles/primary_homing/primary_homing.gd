# assault/scenes/projectiles/primary_homing/primary_homing.gd
class_name PrimaryHoming
extends Area2D

signal expired

@export var speed: float = 480.0
## Maximum turn rate, degrees per second.
@export var turn_rate_deg_per_sec: float = 90.0
@export var lifetime_sec: float = 1.6
@export var damage: int = 50

var locked_target: Node = null
var _age: float = 0.0

func _ready() -> void:
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = damage

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= lifetime_sec:
		expired.emit()
		queue_free()
		return

	if locked_target and is_instance_valid(locked_target) and (locked_target as Node2D).is_inside_tree():
		var to_target: Vector2 = (locked_target as Node2D).global_position - global_position
		var desired_angle := to_target.angle() + PI / 2.0
		var max_step := deg_to_rad(turn_rate_deg_per_sec) * delta
		rotation = rotate_toward(rotation, desired_angle, max_step)

	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta

func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	expired.emit()
	queue_free()

func _on_hit_box_area_entered(_area: Area2D) -> void:
	expired.emit()
	queue_free()
