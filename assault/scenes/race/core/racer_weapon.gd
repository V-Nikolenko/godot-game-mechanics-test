## RacerWeapon — pooled forward/aimed firing for a racer. The brain decides target & timing.
class_name RacerWeapon
extends Node

@export var bullet_scene: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
@export var pool_size: int = 12

var _pool: BulletPool = null

func setup(host: RaceShip) -> void:
	_pool = BulletPool.new()
	_pool.bullet_scene = bullet_scene
	_pool.pool_size = pool_size
	## Parent under the racer so BulletPool resolves the EnemyContainer as grandparent.
	host.add_child.call_deferred(_pool)

func fire(from: Vector2, dir: Vector2, damage: int, speed: float) -> void:
	if _pool == null:
		return
	var bullet := _pool.acquire(from) as EnemyBullet
	if bullet == null:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = damage
	bullet.speed = speed
	bullet.set_direction(dir)

func fire_at(from: Vector2, _target: Node2D, damage: int, speed: float) -> void:
	fire(from, Vector2(0.0, -1.0), damage, speed)
