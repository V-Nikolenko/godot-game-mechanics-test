## ForwardAttackPattern — fires one bullet straight ahead (upward, rotation=0).
## Used by ally fighters whose bullets travel toward the top of the screen.
class_name ForwardAttackPattern
extends AttackPatternResource

@export var bullet_damage: int = 10
@export var spawn_offset: Vector2 = Vector2(0.0, -10.0)

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as Bullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	bullet.rotation = 0.0
