## BonusDrone — rare, fast, non-shooting medal target.
##
## Awards a large score chunk on kill, with no penalty for missing it
## (counts_toward_wave_clear = false on its config). Movement is supplied by
## EnemyPathMover via the WaveBuilder .move() call — no internal physics here.
##
## Visual: existing drone sprite, gold modulate, 50% scaled up.
class_name BonusDrone
extends BaseEnemy

@export var config: BonusDroneConfig = load("res://assault/scenes/enemies/bonus_drone/bonus_drone_config.tres")

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health

	# Bonus drones should be obvious targets — gold tint + larger.
	var sprite := get_node_or_null("Sprite2D") as Node2D
	if sprite:
		sprite.modulate = Color(1.4, 1.15, 0.4, 1.0)
		sprite.scale = Vector2(1.5, 1.5)

# Override: bonus drones do not damage the player on contact. The base helper
# would otherwise add a contact HitBox with damage=20.
func _add_contact_hitbox() -> void:
	pass
