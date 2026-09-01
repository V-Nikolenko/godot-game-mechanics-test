## SpaceStation — the Level 1 space-station mini-boss (EPIC sub-item 1: the entity only).
##
## Four turrets, each on its own HP bar, mounted on a 256x256 hull. The core refuses ALL damage
## while any turret is alive, then becomes damageable when the last one dies.
##
## The armour refuses damage inside `_on_received_damage` rather than by disabling the HurtBox,
## because two shipped systems drive damage straight into the signal with no physics involved —
## `plasma_nova_module.gd:39-41` and `beam_behavior.gd:99-102` both do
## `get_node_or_null("HurtBox").received_damage.emit(...)` over group "enemies". A disabled
## hurtbox would leak both of them. Keeping it live also means the hit still registers visually,
## which is what teaches the player to shoot the guns first.
##
## Extends BaseEnemy like all nine other enemies (BaseEnemy itself composes from
## global/components/), which gives the HurtBox->Health wiring, hit flash, HitEffect,
## ExplosionEffect, the contact HitBox, `died`, and score_value propagation for free. Refusing
## damage via a `_on_received_damage` override is a shipped pattern — see ram_ship.gd:27.
class_name SpaceStation
extends BaseEnemy

## Emitted when the armoured core absorbs a hit. Feedback hook (sfx/sparks) and the observable
## that proves the core is armoured rather than merely unhittable.
signal armor_deflected(damage: int)

@export var config: SpaceStationConfig = load("res://assault/scenes/enemies/space_station/space_station_config.tres")

@onready var turret_root: Node2D = $Turrets


func _ready() -> void:
	super._ready()
	## Consumed by player targeting and AoE: ai_targeting_module.gd:49, plasma_nova_module.gd:34,
	## emp_blast_module.gd:39, warhead_missile_shooting_state.gd:61, beam_behavior.gd:75.
	## NOT what drives LevelSection.ENEMIES_CLEARED — level_director.gd:106 polls
	## wave_manager.enemy_container's child count instead.
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health

		## Godot readies children before parents, so every turret's Health already exists and has
		## run its own _ready() (which only clamps). Same ordering gunship.gd:36-37 relies on.
		for t in _turrets():
			t.health.max_health = config.turret_health
			t.health.current_health = config.turret_health

		## BaseEnemy._add_contact_hitbox() hardcodes damage = 20 and never reads the config
		## (base_enemy.gd:56), so it has to be re-applied here. bomber.gd:18-26,
		## light_assault_ship.gd:23 and ram_ship.gd:20-23 all do this; the gunship forgot to,
		## which is why gunship_config.tres's collision_damage = 30 is silently ignored.
		for child in get_children():
			if child is HitBox:
				(child as HitBox).damage = config.collision_damage
				break


func _turrets() -> Array[StationTurret]:
	var out: Array[StationTurret] = []
	for child in turret_root.get_children():
		var t := child as StationTurret
		if t != null and is_instance_valid(t):
			out.append(t)
	return out


## Read live from the container on every call rather than cached in an array or tracked by a
## counter, so it cannot desync from reality and cannot double-decrement. Four children make the
## iteration free.
func live_turret_count() -> int:
	var n := 0
	for t in _turrets():
		if t.is_alive():
			n += 1
	return n


func is_armored() -> bool:
	return live_turret_count() > 0


## Override: refuse damage to the core while any turret lives, but still register the hit.
func _on_received_damage(damage: int) -> void:
	if is_armored():
		armor_deflected.emit(damage)
		hit_flash_player.play("hit")
		return
	super._on_received_damage(damage)
