## AimedAttackPattern — fires one bullet per shot.
##
## aim_at_player = true  → tracks nearest player each shot.
## aim_at_player = false → shoots in the ship's current look direction (direction of travel).
class_name AimedAttackPattern
extends AttackPatternResource

@export var bullet_damage: int = 10
@export var bullet_speed: float = 250.0   ## Travel speed of each bullet (px/s).
@export var aim_at_player: bool = true
## 0 = direct aim at the player (today's behaviour); 1 = lead the intercept point;
## in between blends the two. See TargetInfo.aim_direction.
@export var accuracy: float = 0.0
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)  ## Offset from ship position.
## Max random rotation offset per shot (radians). 0.0 = no jitter (legacy default — unaffected).
@export var spread_angle: float = 0.0
## Per-instance RNG for jitter. null (default) draws from the global `randf_range`, matching every
## existing consumer.
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
	var dir: Vector2
	if aim_at_player:
		if aim_point.is_finite():
			dir = (aim_point - (ship.global_position + spawn_offset)).normalized()
		else:
			dir = TargetInfo.player(ship.get_tree()).aim_direction(ship.global_position, bullet_speed, accuracy)
	else:
		# Vector2.RIGHT.rotated(rotation + PI/2) == Vector2.DOWN.rotated(rotation), the legacy
		# nose-down default — but reads the ship's own nose whichever way its art was drawn (X7).
		dir = Vector2.RIGHT.rotated(ship.rotation + EnemyMover.sprite_forward_angle_of(ship))
	if spread_angle > 0.0:
		var jitter := rng.randf_range(-spread_angle, spread_angle) if rng != null else randf_range(-spread_angle, spread_angle)
		dir = dir.rotated(jitter)
	bullet.set_direction(dir)
