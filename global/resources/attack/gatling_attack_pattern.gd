## GatlingAttackPattern — high-cadence weapon with slight random scatter.
## Designed for Interceptor: fast fire rate, low damage, moderate range.
## fire_interval is inherited from AttackPatternResource (default 0.8 — override per ship).
class_name GatlingAttackPattern
extends AttackPatternResource

## Damage dealt per bullet.
@export var bullet_damage: int = 4
## Travel speed of each bullet (px/s). Lower speed = shorter effective range.
@export var bullet_speed: float = 220.0
## Max random rotation offset per shot (radians). 0.08 ≈ ±4.5°.
@export var spread_angle: float = 0.08
## true = aim each shot at the nearest player; false = fire in ship's facing direction.
@export var aim_at_player: bool = true
## Spawn offset relative to the ship's position.
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	bullet.speed = bullet_speed

	var base_dir: Vector2
	if aim_at_player:
		var players := ship.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			base_dir = ((players[0] as Node2D).global_position - ship.global_position).normalized()
		else:
			base_dir = Vector2.DOWN
	else:
		base_dir = Vector2.DOWN.rotated(ship.rotation)

	bullet.set_direction(base_dir.rotated(randf_range(-spread_angle, spread_angle)))
