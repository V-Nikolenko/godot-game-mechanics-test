class_name homing_missile
extends Area2D

## Arena bounds matching arena_camera.gd — same constants as EnemyBullet.
## x ∈ [-50, 690], y ∈ [-190, 550] plus a 32 px margin.
const _ARENA_MARGIN : float = 32.0
const _ARENA_LEFT   : float = -50.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float =  690.0 + _ARENA_MARGIN
const _ARENA_TOP    : float = -190.0 - _ARENA_MARGIN
const _ARENA_BOTTOM : float =  550.0 + _ARENA_MARGIN

@export var speed: float = 250.0
@export var locked_target: Node

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	animated_sprite.play("default")
	add_child(RocketTrail.new())


func _physics_process(delta: float) -> void:
	if locked_target and locked_target.is_inside_tree():
		_fly_to_target(delta)
	else:
		_fly_forward(delta)

	var p := global_position
	if p.x < _ARENA_LEFT or p.x > _ARENA_RIGHT \
			or p.y < _ARENA_TOP or p.y > _ARENA_BOTTOM:
		queue_free()


func _fly_to_target(delta: float) -> void:
	var direction = (locked_target.global_position - global_position).normalized()
	rotation = direction.angle() + PI / 2
	global_position += direction * speed * delta


func _fly_forward(delta: float) -> void:
	var forward := Vector2.UP.rotated(rotation)
	global_position += forward * speed * delta


func _on_hit_box_area_entered(area: Area2D) -> void:
	queue_free()
