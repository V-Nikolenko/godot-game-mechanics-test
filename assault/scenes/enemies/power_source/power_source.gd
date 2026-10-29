## PowerSource - the reactor that powers a turret group (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.2; Phase 8 t9). Behaviour:
## `ENEMY.md` beside this file.
##
## A `BaseEnemy` with **no brain and no mover**: it never moves itself (in Assault an `AssaultDrift` child scrolls it), never fires, refuses tows
## and answers `provides_power() == true`, so the `TurretGroup` that spawns it registers it as a power provider. Killing it darkens every turret of
## the group in the same call (the group's job, on this node's `died`). Contact: `ContactProfile` NONE and no `ContactHitBox`. The player's mining
## beam treats it as a target, never a wall (`is_laser_blocking()` false). `counts_as_escape` is false in its `.tres`.
##
## Groups: `set_turret_group(group)`, before `add_child`, joins the group's `owner_group` (read duck-typed; so the group's own beams and rings
## spare it); alone it is `&"power_source_<instance id>"`. While its group is powered it draws one amber `Line2D` (code-built, `top_level`) to every
## live member that is not itself a provider; the lines go when the group goes dark.
class_name PowerSource
extends BaseEnemy

## The body / hurtbox circle's radius (the scene's shared `CircleShape2D`).
const BODY_RADIUS := 34.0
const LINE_WIDTH := 3.0
const LINE_COLOR := Color(1.0, 0.7, 0.2, 0.85)
const HOUSING_RADIUS := 36.0
const HOUSING_COLOR := Color(0.2, 0.2, 0.24, 1.0)
const RIM_COLOR := Color(0.55, 0.5, 0.4, 1.0)
const CORE_RADIUS := 16.0
const CORE_COLOR := Color(1.0, 0.72, 0.25, 1.0)
const GLOW_COLOR := Color(1.0, 0.6, 0.15, 0.35)

@export var config: PowerSourceConfig = load("res://assault/scenes/enemies/power_source/power_source_config.tres")

var _turret_group: Object = null
var _owner_group: StringName = &""
## Member -> its `Line2D`.
var _lines: Dictionary = {}

@onready var _drift: AssaultDrift = $AssaultDrift


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		_drift.speed = config.assault_drift_speed
	_owner_group = _resolve_owner_group()
	add_to_group(_owner_group)
	if _turret_group != null and _turret_group.has_signal("power_changed"):
		_turret_group.connect("power_changed", _on_power_changed)
	queue_redraw()


func _process(_delta: float) -> void:
	_refresh_lines()


## Duck-typed provider question (`TurretGroup.add_power_provider`, the Ph20 seam): a source powers its group while it lives.
func provides_power() -> bool:
	return true


## Call before `add_child`: the source joins `group.owner_group` (read duck-typed) and remembers the group for its lines.
func set_turret_group(group: Object) -> void:
	if is_node_ready():
		push_warning("PowerSource: set_turret_group() after _ready() is ignored; call it before add_child")
		return
	_turret_group = group


func turret_group() -> Object:
	return _turret_group


func owner_group() -> StringName:
	return _owner_group


## The player's mining beam passes over the source and burns it (it is a target, not a wall).
func is_laser_blocking() -> bool:
	return false


## The amber power lines, refreshed now: one per live, powered, non-provider member of the group; none when the group is dark.
func power_lines() -> Array[Line2D]:
	_refresh_lines()
	var out: Array[Line2D] = []
	for line: Line2D in _lines.values():
		out.append(line)
	return out


func _resolve_owner_group() -> StringName:
	if _turret_group != null and is_instance_valid(_turret_group):
		var named: Variant = _turret_group.get("owner_group")
		if named != null and StringName(named) != &"":
			return StringName(named)
	return StringName("power_source_%d" % get_instance_id())


func _refresh_lines() -> void:
	var wanted: Array = []
	var group := _turret_group
	if group != null and is_instance_valid(group) and group.has_method("members") and bool(group.call("is_powered")):
		for member: Node2D in group.call("members"):
			if member == self or (member.has_method("provides_power") and member.provides_power()):
				continue
			wanted.append(member)
	for member in _lines.keys():
		if not wanted.has(member):
			(_lines[member] as Line2D).free()
			_lines.erase(member)
	for member: Node2D in wanted:
		var line := _lines.get(member) as Line2D
		if line == null:
			line = Line2D.new()
			line.name = "PowerLine"
			line.top_level = true
			line.width = LINE_WIDTH
			line.default_color = LINE_COLOR
			line.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
			add_child(line)
			_lines[member] = line
		line.set_point_position(0, global_position)
		line.set_point_position(1, member.global_position)


func _on_power_changed(_powered: bool) -> void:
	_refresh_lines()


## Placeholder art (the art task replaces it): a dark reactor housing with an amber core glow.
func _draw() -> void:
	draw_circle(Vector2.ZERO, HOUSING_RADIUS, HOUSING_COLOR)
	draw_arc(Vector2.ZERO, HOUSING_RADIUS, 0.0, TAU, 32, RIM_COLOR, 3.0)
	draw_circle(Vector2.ZERO, CORE_RADIUS + 6.0, GLOW_COLOR)
	draw_circle(Vector2.ZERO, CORE_RADIUS, CORE_COLOR)
