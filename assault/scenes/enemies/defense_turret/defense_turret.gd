## DefenseTurret - the Stationary Defense Turret (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7; Phase 8 t6). Behaviour:
## `ENEMY.md` beside this file.
##
## A `BaseEnemy` with a `DefenseTurretBrain` and **no `EnemyMover`**: `is_ai_driven()` is false, it refuses tows, and its root never rotates
## (`rotation` stays 0). Everything that aims and fires is a `TurretMount` the turret builds at runtime, one per `TurretMountSlot` under
## `MountSlots`; each mount writes only its own rotation. Contact: `ContactProfile` NONE and no `ContactHitBox` (the Bonus Drone precedent).
## The player's mining beam treats it as a target, never a wall (`is_laser_blocking()` false). In Assault an `AssaultDrift` child scrolls it down
## with the corridor and frees it below the projectile world rect; `counts_as_escape` is false in its `.tres`, so that never breaks the combo.
##
## `_ready()` runs after every child's: config first, then the owner group, then the mounts. For each slot it instantiates
## `TurretMountScenes.scene_for(variant)` (the slot's, or this node's `variant` export for the first slot when >= 0), copies the slot's
## `rest_bearing_deg` and a non-negative `turn_rate_override`, hands it the brain's rng, adds it under the slot, builds the `BulletPool`s its
## `pool_specs()` asks for as **root children** (so their container - the pool's grandparent - is this turret's parent, the enemy container) and
## calls `setup()`. The brain gets the list.
##
## Power: `set_powered(false)` powers every mount down for good (a later `set_powered(true)` is ignored in this phase; Ph20 may lift that).
## Groups: `set_turret_group(group)`, before `add_child`, joins the group's `owner_group`; without one the turret is its own owner group
## `&"turret_<instance id>"`, so its mounts share one exempt set. A group that answers `request_telegraph(member)` (a `TurretGroup`, t9) becomes every
## mount's `telegraph_gate`, so the group staggers its members' telegraph starts; a lone turret is never held.
##
## Spawn with `b.defense_turret().at(x, y)`; `.prop("variant", TurretMount.Variant.X)` picks the first slot's weapon.
class_name DefenseTurret
extends BaseEnemy

## The body / hurtbox circle's radius (the scene's shared `CircleShape2D`; a row pins it).
const BODY_RADIUS := 28.0
## Px past the body a rocket's launcher clear radius adds.
const ROCKET_CLEARANCE := 4.0
const BASE_RADIUS := 30.0
const BASE_COLOR := Color(0.2, 0.22, 0.26, 1.0)
const RIM_COLOR := Color(0.5, 0.55, 0.62, 1.0)

@export var config: DefenseTurretConfig = load("res://assault/scenes/enemies/defense_turret/defense_turret_config.tres")
## When >= 0, the first mount slot's variant (a `TurretMount.Variant`); one property a wave or a group slot can set.
@export var variant: int = -1
## When not NAN, the first mount slot's `rest_bearing_deg` (degrees). Not an export: a `TurretGroupSlot` or a wave's `.prop()` sets it before
## `add_child`, as with `variant`.
var rest_bearing_override: float = NAN

var _powered: bool = true
var _turret_group: Object = null
var _owner_group: StringName = &""
var _mounts: Array[TurretMount] = []

@onready var _turret_brain: DefenseTurretBrain = $Brain
@onready var _drift: AssaultDrift = $AssaultDrift
@onready var _slots: Node2D = $MountSlots


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	_owner_group = _resolve_owner_group()
	add_to_group(_owner_group)
	_build_mounts()
	_turret_brain.bind_mounts(_mounts)
	if not _powered:
		_turret_brain.power_down()
	queue_redraw()


func _apply_config(cfg: DefenseTurretConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	_drift.speed = cfg.assault_drift_speed
	_turret_brain.config = cfg


## Off for good: every mount powers down and the light goes OFF. `true` (and any call once off) is ignored in this phase.
func set_powered(on: bool) -> void:
	if on or not _powered:
		return
	_powered = false
	if is_node_ready():
		_turret_brain.power_down()


func is_powered() -> bool:
	return _powered


## Call before `add_child`: the turret joins `group.owner_group` (read duck-typed) and remembers the group.
func set_turret_group(group: Object) -> void:
	if is_node_ready():
		push_warning("DefenseTurret: set_turret_group() after _ready() is ignored; call it before add_child")
		return
	_turret_group = group


func turret_group() -> Object:
	return _turret_group


func owner_group() -> StringName:
	return _owner_group


func mounts() -> Array[TurretMount]:
	return _mounts.duplicate()


## The player's mining beam passes over a turret root and burns it (it is a target, not a wall).
func is_laser_blocking() -> bool:
	return false


## Duck-typed launcher question (`EnemyRocket.launch`, the rocket battery): a static host adds nothing to a rocket's speed.
func launch_velocity() -> Vector2:
	return Vector2.ZERO


## Duck-typed launcher question: the body radius + 4, so a rocket arms only once clear of the hull and never hits its own turret.
func rocket_clear_radius() -> float:
	return BODY_RADIUS + ROCKET_CLEARANCE


func _resolve_owner_group() -> StringName:
	if _turret_group != null and is_instance_valid(_turret_group):
		var named: Variant = _turret_group.get("owner_group")
		if named != null and StringName(named) != &"":
			return StringName(named)
	return StringName("turret_%d" % get_instance_id())


func _build_mounts() -> void:
	var index := -1
	for child in _slots.get_children():
		var slot := child as TurretMountSlot
		if slot == null:
			continue
		index += 1
		var wanted: int = variant if index == 0 and variant >= 0 else int(slot.variant)
		var scene := TurretMountScenes.scene_for(wanted)
		if scene == null:
			push_warning("DefenseTurret: mount variant %d is not built yet; slot %s stays empty" % [wanted, slot.name])
			continue
		var mount := scene.instantiate() as TurretMount
		mount.rest_bearing_deg = rest_bearing_override if index == 0 and not is_nan(rest_bearing_override) else slot.rest_bearing_deg
		if slot.turn_rate_override >= 0.0:
			mount.turn_rate = slot.turn_rate_override
		mount.rng = _turret_brain.rng
		if _turret_group != null and is_instance_valid(_turret_group) and _turret_group.has_method("request_telegraph"):
			mount.telegraph_gate = Callable(_turret_group, "request_telegraph").bind(self)
		slot.add_child(mount)
		var pools := {}
		for spec in mount.pool_specs():
			var pool := BulletPool.new()
			pool.name = "%s_%d" % [spec["name"], index]
			pool.bullet_scene = spec["scene"]
			pool.pool_size = spec["size"]
			pool.persist_after_owner_death = spec["persist"]
			add_child(pool)
			pools[spec["name"]] = pool
		mount.setup(self, pools, _owner_group)
		_mounts.append(mount)


## Placeholder art (the art task replaces it): the base plate the head turns on.
func _draw() -> void:
	draw_circle(Vector2.ZERO, BASE_RADIUS, BASE_COLOR)
	draw_arc(Vector2.ZERO, BASE_RADIUS, 0.0, TAU, 32, RIM_COLOR, 3.0)
