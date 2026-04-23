## AimedAttackPattern — fires one bullet aimed at the nearest player.
## Falls back to straight-down (Vector2.DOWN) if no player is in the scene tree.
class_name AimedAttackPattern
extends AttackPatternResource

@export var bullet_damage: int = 10
@export var aim_at_player: bool = true
@export var spawn_offset: Vector2 = Vector2(0.0, 10.0)  ## Offset from ship position.

func fire(ship: Node2D, pool: BulletPool) -> void:
	var bullet := pool.acquire(ship.global_position + spawn_offset) as EnemyBullet
	if not bullet:
		return
	var hb := bullet.get_node_or_null("HitBox") as HitBox
	if hb:
		hb.damage = bullet_damage
	if aim_at_player:
		var players := ship.get_tree().get_nodes_in_group("player")
		if players.size() > 0:
			var dir: Vector2 = ((players[0] as Node2D).global_position - ship.global_position).normalized()
			bullet.set_direction(dir)
		else:
			bullet.set_direction(Vector2.DOWN)
	else:
		bullet.set_direction(Vector2.DOWN)
