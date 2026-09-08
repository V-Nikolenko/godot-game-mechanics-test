class_name homing_missile
extends Area2D

## Arena bounds matching arena_camera.gd — same constants as EnemyBullet.
## x ∈ [-100, 1380], y ∈ [-380, 1100] plus a 64 px margin.
const _ARENA_MARGIN : float = 64.0
const _ARENA_LEFT   : float = -100.0  - _ARENA_MARGIN
const _ARENA_RIGHT  : float = 1380.0  + _ARENA_MARGIN
const _ARENA_TOP    : float = -380.0  - _ARENA_MARGIN
const _ARENA_BOTTOM : float = 1100.0  + _ARENA_MARGIN

@export var speed: float = 500.0
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
	if _hit_is_deflected(area):
		return
	queue_free()


## True when the hurtbox we just overlapped refused to apply damage (e.g. the space-station core
## while any turret still lives). Duck-typed against `is_armored()`, same idiom as
## `bullet.gd::_hit_is_deflected` — a rocket gets the same exemption a bullet already has, so it
## survives crossing the boss's armoured core instead of detonating on it before reaching a turret.
func _hit_is_deflected(area: Area2D) -> bool:
	var target := area.get_parent()
	return target != null and target.has_method("is_armored") and target.is_armored()
