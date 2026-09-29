class_name EnemyBullet
extends Area2D

signal expired

@export var speed: float = 250.0

var _direction: Vector2 = Vector2.DOWN

## Captured in _ready() from the scene's own authored values (speed above, HitBox.damage below),
## so reset() restores THIS round's identity rather than a hardcoded legacy default — a round
## picked from EnemyRounds keeps its own speed/damage across pool reuse (3-plan.md §2.2).
var _authored_speed: float = 250.0
var _authored_damage: int = 0

## Present on every EnemyBullet-derived scene (see enemy_bullet.tscn and
## enemy_sniper_bullet.tscn); null-checked so a scene that forgot the child fails safe rather than
## erroring on reset(). See global/components/projectile_lifetime.gd for the world-space rules
## this used to hardcode (arena bounds matching arena_camera.gd's legacy visible rect).
@onready var _lifetime: ProjectileLifetime = get_node_or_null("ProjectileLifetime") as ProjectileLifetime
@onready var _hit_box: HitBox = get_node_or_null("HitBox") as HitBox

func _ready() -> void:
	_authored_speed = speed
	if _hit_box:
		_authored_damage = _hit_box.damage

func reset() -> void:
	_direction = Vector2.DOWN
	rotation = 0.0
	speed = _authored_speed
	if _hit_box:
		_hit_box.damage = _authored_damage
	if _lifetime:
		_lifetime.reset()

func set_direction(dir: Vector2) -> void:
	_direction = dir.normalized()
	rotation = _direction.angle() - PI / 2.0

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta

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
