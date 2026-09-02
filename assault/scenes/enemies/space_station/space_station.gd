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

## Emitted exactly once, the moment the last turret dies and the core stops being armoured.
## The phase-transition hook: `StationLaserPhase` starts the laser phase on it, and sub-item 4's
## escalating fire will hang off the same signal rather than a second fan-out over the turrets.
##
## Station-level rather than per-turret because the station owns the armour rule
## (`is_armored()` / `live_turret_count()`), so the *transition* is station-level knowledge.
##
## Zero arguments, deliberately — see the `Health.amount_changed` trap in `tests/README.md`,
## where a signal declared with zero parameters is emitted with one and every zero-arg handler
## raises an engine error.
signal armor_broken

@export var config: SpaceStationConfig = load("res://assault/scenes/enemies/space_station/space_station_config.tres")

@onready var turret_root: Node2D = $Turrets

## Latches true when `armor_broken` fires, so it fires exactly once.
##
## Its job is idempotence against re-entry through `destroyed` itself — a re-emit from a future
## caller, or a repairable/respawning turret driving the live count 0 -> 1 -> 0. It is NOT about
## the `Health` 0 -> 0 re-emit trap: `StationTurret._on_received_damage` already returns early
## when `not _alive`, so damage aimed at a dead turret never reaches `Health` at all.
var _armor_broken: bool = false


func _ready() -> void:
	super._ready()
	## Consumed by player targeting and AoE: ai_targeting_module.gd:49, plasma_nova_module.gd:34,
	## emp_blast_module.gd:39, warhead_missile_shooting_state.gd:61, beam_behavior.gd:75.
	## NOT what drives LevelSection.ENEMIES_CLEARED — level_director.gd:106 polls
	## wave_manager.enemy_container's child count instead.
	add_to_group("enemies")

	## Same child-before-parent ordering the config block below relies on: every turret has
	## already run its own _ready(), so `destroyed` is safe to connect here.
	for t in _turrets():
		t.destroyed.connect(_on_turret_destroyed)

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


## Takes the turret argument `StationTurret.destroyed` is declared AND emitted with — unlike
## `Health.amount_changed`, the two agree here, so a one-arg handler is the correct shape.
func _on_turret_destroyed(_turret: StationTurret) -> void:
	if _armor_broken:
		return
	if live_turret_count() > 0:
		return
	_armor_broken = true
	armor_broken.emit()


## Override: refuse damage to the core while any turret lives, but still register the hit.
func _on_received_damage(damage: int) -> void:
	if is_armored():
		armor_deflected.emit(damage)
		hit_flash_player.play("hit")
		return
	super._on_received_damage(damage)
