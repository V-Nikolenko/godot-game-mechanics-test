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
## 0 = direct aim at the player (today's behaviour); 1 = lead the intercept point;
## in between blends the two. See TargetInfo.aim_direction.
@export var accuracy: float = 0.0
## Spawn offset relative to the ship's position.
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)
## Per-instance RNG for jitter. null (default) draws from the global `randf_range`, matching every
## existing consumer (legacy rail streams, and the station).
var rng: RandomNumberGenerator = null
## When finite, the shot aims here instead of asking `TargetInfo` for the player. `Vector2.INF`
## (default) means unset.
var aim_point: Vector2 = Vector2.INF

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
		if aim_point.is_finite():
			base_dir = (aim_point - (ship.global_position + spawn_offset)).normalized()
		else:
			base_dir = TargetInfo.player(ship.get_tree()).aim_direction(ship.global_position, bullet_speed, accuracy)
	else:
		# Vector2.RIGHT.rotated(rotation + PI/2) == Vector2.DOWN.rotated(rotation), the legacy
		# nose-down default — but reads the ship's own nose whichever way its art was drawn (X7).
		base_dir = Vector2.RIGHT.rotated(ship.rotation + EnemyMover.sprite_forward_angle_of(ship))

	var jitter := rng.randf_range(-spread_angle, spread_angle) if rng != null else randf_range(-spread_angle, spread_angle)
	bullet.set_direction(base_dir.rotated(jitter))
