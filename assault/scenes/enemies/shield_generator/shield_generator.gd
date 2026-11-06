## ShieldGenerator - puts a shield bubble on every member of its turret group (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.5; Phase 8 t9s).
## Behaviour: `ENEMY.md` beside this file.
##
## A `BaseEnemy` with a `ShieldGeneratorBrain` and **no `EnemyMover`**: `is_ai_driven()` is false and it refuses tows. It never moves itself (in Assault
## an `AssaultDrift` child scrolls it), never fires and has no weapon. Contact: `ContactProfile` NONE and no `ContactHitBox` (the power source / turret
## precedent). The player's mining beam treats it as a target, never a wall (`is_laser_blocking()` false). `counts_as_escape` is false in its `.tres`.
##
## Groups: `set_turret_group(group)`, before `add_child`, joins `group.owner_group` (read duck-typed, so the group's own beams and rings spare it); the
## brain reads the group's `members()`. A generator with no group shields nothing. `set_powered(false)` (the group's `power_changed` coupling, the same
## call as the power source's death) stops the projection for good: every bubble lapses after its heartbeat and fades. Killing the generator does the same.
class_name ShieldGenerator
extends BaseEnemy

## The body / hurtbox circle's radius (the scene's shared `CircleShape2D`).
const BODY_RADIUS := 30.0
const LENS_RADIUS := 13.0
const LENS_OFF_COLOR := Color(0.1, 0.12, 0.16, 1.0)

@export var config: ShieldGeneratorConfig = load("res://assault/scenes/enemies/shield_generator/shield_generator_config.tres")

var _powered: bool = true
var _turret_group: Object = null
var _owner_group: StringName = &""

@onready var _gen_brain: ShieldGeneratorBrain = $Brain
@onready var _drift: AssaultDrift = $AssaultDrift


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	_owner_group = _resolve_owner_group()
	add_to_group(_owner_group)
	if not _powered:
		_gen_brain.power_down()
	queue_redraw()


func _apply_config(cfg: ShieldGeneratorConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	_drift.speed = cfg.assault_drift_speed
	_gen_brain.config = cfg


## Off for good: the projection stops and the tethers go; the bubbles lapse by themselves. `true` (and any call once off) is ignored in this phase.
func set_powered(on: bool) -> void:
	if on or not _powered:
		return
	_powered = false
	queue_redraw()
	if is_node_ready():
		_gen_brain.power_down()


func is_powered() -> bool:
	return _powered


## Call before `add_child`: the generator joins `group.owner_group` (read duck-typed) and remembers the group for its members.
func set_turret_group(group: Object) -> void:
	if is_node_ready():
		push_warning("ShieldGenerator: set_turret_group() after _ready() is ignored; call it before add_child")
		return
	_turret_group = group


func turret_group() -> Object:
	return _turret_group


func owner_group() -> StringName:
	return _owner_group


## The cyan tethers, refreshed now: one per member it currently shields; none when unpowered.
func tethers() -> Array[Line2D]:
	return _gen_brain.tethers()


## The player's mining beam passes over the generator and burns it (it is a target, not a wall).
func is_laser_blocking() -> bool:
	return false


func _resolve_owner_group() -> StringName:
	if _turret_group != null and is_instance_valid(_turret_group):
		var named: Variant = _turret_group.get("owner_group")
		if named != null and StringName(named) != &"":
			return StringName(named)
	return StringName("shield_generator_%d" % get_instance_id())


## The dish lens (baked into `Sprite2D`, which draws behind this node) goes dark under a cap once the generator is unpowered; the hull is never tinted.
func _draw() -> void:
	if not _powered:
		draw_circle(Vector2.ZERO, LENS_RADIUS, LENS_OFF_COLOR)
