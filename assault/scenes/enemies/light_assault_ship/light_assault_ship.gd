class_name LightAssaultShip
extends BaseEnemy

@export var config: FighterConfig = load("res://assault/scenes/enemies/light_assault_ship/fighter_config.tres")

const _BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

## Overrides config.aim_mode when set via SpawnConfig.shoot_forward() / shoot_at_player()
## before the node enters the tree. "FORWARD" or "PLAYER". Empty = use config default.
var aim_mode: String = ""

var bullet_pool: BulletPool

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break

	# Bullet pool
	bullet_pool = BulletPool.new()
	bullet_pool.bullet_scene = _BULLET_SCENE
	bullet_pool.pool_size = 10
	add_child(bullet_pool)

	# aim_mode set via spawn props takes priority over the config default.
	var effective_aim: String = aim_mode if not aim_mode.is_empty() \
			else (config.aim_mode if config else "PLAYER")
	var forward: bool = (effective_aim == "FORWARD")

	# Attack pattern built from config values.
	# Forward shooters fire faster with faster bullets — they can't lead their target,
	# so higher volume compensates.
	var pattern := AimedAttackPattern.new()
	pattern.fire_interval = 0.3 if forward else (config.fire_interval if config else 0.8)
	pattern.bullet_damage = config.bullet_damage if config else 8
	pattern.bullet_speed  = 420.0 if forward else 250.0
	pattern.aim_at_player = not forward
	pattern.spawn_offset  = Vector2(0.0, 10.0)

	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = bullet_pool
	add_child(controller)
