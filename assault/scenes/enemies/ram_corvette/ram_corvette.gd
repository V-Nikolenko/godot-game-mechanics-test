class_name RamCorvette
extends BaseEnemy

## The Ram Corvette (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.6; task t16): a hull under three
## independently breakable `ArmorPlate`s (`Plates/PlateFront`, `PlateLeft`, `PlateRight`). A
## `RamCorvetteBrain` decides and an `EnemyMover` moves it through `BaseEnemy`'s shared tick, so this
## script defines no `_physics_process`.
##
## ARMOUR IS A DEFLECTION RULE ON A FULL-SIZE HURTBOX, never a narrowed mask (the hurtbox-geometry gate;
## the space station's precedent). While any plate lives:
##   - the hull answers `is_armored()` / `deflects_hit()` true, so EVERY player projectile crossing it
##     (bullets, rockets, the Sniper Shot) is not consumed and flies on - rockets to reach a plate;
##   - `_on_received_damage` refuses every hit with a flash and `armor_deflected`, which also covers the
##     direct emitters (beam, engine boost, nova, dash) that call `received_damage.emit()` themselves;
##   - the beam stops at it (`is_laser_blocking()`).
## The plates decide for themselves (`ArmorPlate._resolve`): a rocket or a Sniper Shot damages the plate
## it meets, a bullet glances off it.
##
## EXPOSURE IS DEFERRED to the end of the physics step the last plate breaks in. `HurtBox.received_damage`
## carries no hit, and Godot gives no order between the plate's `area_entered` and the hull's, so the
## rocket that breaks the last plate may also be overlapping the hull in the same step. Flipping at once
## would let that hull callback land the plate's rocket on the hull as well; deferred, everything the hull
## sees in that step is still a deflection, and the next step sees an exposed hull.
##
## Contact: the ARMOR `ContactProfile` (armed at setup and for life on a rail) deals `collision_damage`
## and shoves the player while armoured; exposed, `exposed_collision_damage` and no shove, and the brain arms it
## only during CHARGE (on a rail it stays armed for life).
##
## Spawn with b.ram().at(x, y); `.move()` is only needed until level 1 leaves its rails.

## A hit the armour refused (hull, while a plate lives). Feedback hook, the station's signal shape.
signal armor_deflected(damage: int)
## One plate broke; carries its node name (`PlateFront` / `PlateLeft` / `PlateRight`).
signal plate_broken(plate_name: StringName)
## The last plate broke and the hull is exposed. Emitted once, one step after that plate broke.
signal armor_broken

const RAM_FRAGMENT: PackedScene = preload("res://assault/scenes/hazards/wreck/ram_fragment.tscn")

@export var config: RamCorvetteConfig = load("res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres")

var _armored: bool = true
var _plates: Array[ArmorPlate] = []

@onready var _ram_brain: RamCorvetteBrain = $Brain
@onready var _ram_mover: EnemyMover = $EnemyMover


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	for child in $Plates.get_children():
		var plate := child as ArmorPlate
		if plate == null:
			continue
		_plates.append(plate)
		plate.broken.connect(_on_plate_broken)
		plate.deflected.connect(_on_plate_deflected)
	_ram_brain.contact = contact_profile
	if config:
		_apply_config(config)


func _apply_config(cfg: RamCorvetteConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	contact_profile.shove_speed = cfg.armor_shove_speed

	for plate in _plates:
		plate.health.max_health = cfg.plate_health
		plate.health.current_health = cfg.plate_health

	_ram_mover.max_speed = cfg.cruise_speed
	_ram_mover.acceleration = cfg.acceleration
	_ram_mover.max_turn_rate = cfg.max_turn_rate

	_ram_brain.config = cfg


## True while any plate lives (and for the rest of the step the last one breaks in - see the class doc).
func is_armored() -> bool:
	return _armored


## The `ArmorQuery` hook for the HULL's hurtbox: while armoured every hit passes through, rockets
## included, so they reach a plate. Each plate answers for its own hurtbox.
func deflects_hit(_hit_box: HitBox) -> bool:
	return is_armored()


## Read by `beam_behavior.gd`: the beam stops at an armoured Corvette and passes once it is exposed.
func is_laser_blocking() -> bool:
	return is_armored()


## Read by `homing_missile.gd`: the live plate nearest `from`, else the hull centre.
func homing_point(from: Vector2) -> Vector2:
	var best := global_position
	var best_d := INF
	for plate in _plates:
		if not is_instance_valid(plate) or not plate.is_alive():
			continue
		var d := from.distance_squared_to(plate.global_position)
		if d < best_d:
			best_d = d
			best = plate.global_position
	return best


## The wind-up glow (0..1) on every live plate; the brain drives it.
func set_plate_glow(amount: float) -> void:
	for plate in _plates:
		if is_instance_valid(plate) and plate.is_alive():
			plate.set_glow(amount)


func live_plate_count() -> int:
	var n := 0
	for plate in _plates:
		if is_instance_valid(plate) and plate.is_alive():
			n += 1
	return n


func _on_received_damage(damage: int) -> void:
	if is_armored():
		armor_deflected.emit(damage)
		hit_flash_player.play("hit")
		return
	super._on_received_damage(damage)


func _on_plate_deflected(_hit_box: HitBox) -> void:
	hit_flash_player.play("hit")


func _on_plate_broken(plate: ArmorPlate) -> void:
	_throw_fragment(plate)
	plate_broken.emit(plate.name)
	_ram_brain.on_plate_broken()
	if live_plate_count() == 0 and _armored:
		call_deferred("_expose")


## Debris Charge (plan cmug23om70001m52wqfwclf3l §2.13): the broken plate tumbles off outward as a `DebrisFragment`.
## Position, rotation and look are captured at once (the plate's sprite is still valid at `broken.emit`); the spawn is
## deferred by `spawn_into`, because a plate breaks inside a rocket's `area_entered` flush. No hazard container, no
## fragment. `source = self` keeps its contact box disarmed until it is clear of this hull, so it never hits the Ram the
## third plate exposed.
func _throw_fragment(plate: ArmorPlate) -> void:
	var container := Hazards.container(get_tree())
	if container == null:
		return
	var fragment := RAM_FRAGMENT.instantiate() as DebrisFragment
	var out := plate.global_position - global_position
	fragment.direction = out.normalized() if out.length_squared() > 0.0 else Vector2.DOWN.rotated(rotation)
	fragment.source = self
	var sprite := fragment.get_node("Sprite2D") as Sprite2D
	if plate.sprite != null:
		sprite.texture = plate.sprite.texture
		sprite.flip_h = plate.sprite.flip_h
	fragment.source_clear_radius = _body_radius() + fragment.contact_radius()
	fragment.spawn_into(container, plate.global_position, plate.global_rotation)


func _body_radius() -> float:
	var shape := $CollisionShape2D as CollisionShape2D
	var circle := shape.shape as CircleShape2D if shape != null else null
	return circle.radius * absf(shape.scale.x) if circle != null else 0.0


func _expose() -> void:
	if not _armored:
		return
	_armored = false
	if contact_hit_box and config:
		contact_hit_box.damage = config.exposed_collision_damage
	contact_profile.shove_speed = 0.0
	armor_broken.emit()
	_ram_brain.on_exposed()
