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
## the rounds/ scenes); null-checked so a scene that forgot the child fails safe rather than
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

## The HitBox masks the player hurtbox (128) and hazard contact (1024). A hazard-contact area ends the round only when
## its owner answers duck-typed `stops_enemy_rounds() == true` (a wreck: cover from both sides); an asteroid's contact
## box does not, so rounds still pass asteroids (plan §2.8, docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md).
func _on_hit_box_area_entered(area: Area2D) -> void:
	if area.collision_layer & CollisionLayers.HAZARD_CONTACT and not _stops_rounds(area):
		return
	expired.emit()


static func _stops_rounds(area: Area2D) -> bool:
	var host: Node = area.owner if area.owner != null else area.get_parent()
	return host != null and host.has_method(&"stops_enemy_rounds") and host.call(&"stops_enemy_rounds") == true

## Reflect-mode flip: reverses this enemy bullet so it becomes a friendly projectile.
## Layers/mask are swapped to player-projectile (64) hitting enemy hurt (513).
func become_friendly() -> void:
	_direction = -_direction
	rotation += PI
	var hb := get_node_or_null("HitBox") as HitBox
	if hb:
		hb.collision_layer = 64
		hb.collision_mask = 513
