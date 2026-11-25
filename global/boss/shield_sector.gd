## ShieldSector — one shield generator keeps a breakable 360 degree `EnemyShield` bubble on every protected part of its half of a boss, until
## the generator is destroyed (IDEAS §26; Phase 11 §2.5.4, docs/plans/cmug256so0031m52wbxomst72/3-plan.md; built in t15). Boss-agnostic: it
## reads `EnemyModule`s and a params dictionary, never a host type.
##
## ONE BUBBLE PER LIVE PROTECTED PART, a child of the part and attached to the part's own `HurtBox` (`sustain_mode` false: the bubble
## regenerates and reboots on `EnemyShield`'s own clock, no `Timer`). A part whose absorber slot is already taken keeps its absorber and gets
## no bubble from this sector (never displaced). A part that is already a wreck gets none. The bubble absorbs nothing while its part is
## armoured, so a locked part (a hangar with closed doors) is covered only while it is open.
##
## THE GENERATOR'S DEATH IS FOR GOOD: every bubble is detached from its hurtbox first (so a hit later in the same physics frame is not
## absorbed; the `queue_free` alone would free the slot only at the end of the frame), then freed, in the same call that `destroyed` fires.
## A protected part's own death frees its own bubble only. While the generator lives its `Light` shows `StateLight.State.SHIELDED`.
##
## Params (all optional, defaults are `EnemyShield`'s): `capacity`, `regen_delay`, `regen_seconds`, `reboot_seconds`, `radius_pad`.
##
## Tests: tests/integration/test_shield_sector.gd (fixture tests/helpers/fixture_modular_host.tscn).
class_name ShieldSector
extends RefCounted

var _generator: EnemyModule
## Part module_id -> the bubble on it.
var _shields: Dictionary = {}
## Part module_id -> the hurtbox its bubble holds the absorber slot of.
var _hurt_boxes: Dictionary = {}
## Every id passed in, in order, whether or not it got a bubble.
var _protected_ids: Array = []
var _exposed: bool = false


func _init(generator: EnemyModule, protected: Array[EnemyModule], params: Dictionary = {}) -> void:
	_generator = generator
	for part in protected:
		if part != null:
			_protected_ids.append(part.module_id)
	if generator == null or generator.is_destroyed():
		_exposed = true
		return
	for part in protected:
		_shield_part(part, params)
	generator.destroyed.connect(_on_generator_destroyed)
	var light := generator.get_node_or_null(^"Light") as StateLight
	if light != null:
		light.set_state(StateLight.State.SHIELDED)


## True once the generator is destroyed: the sector's parts are bare for good.
func is_exposed() -> bool:
	return _exposed


## The live bubble on [param module_id], or null (never built, the part died, or the sector is exposed).
func shield_of(module_id: StringName) -> EnemyShield:
	var shield := _shields.get(module_id) as EnemyShield
	return shield if is_instance_valid(shield) else null


func shields() -> Array:
	var out: Array = []
	for id in _shields:
		var shield := shield_of(id)
		if shield != null:
			out.append(shield)
	return out


func generator() -> EnemyModule:
	return _generator


## Ids of every part this sector was given, whether or not it got a bubble.
func protected_ids() -> Array:
	return _protected_ids.duplicate()


func _shield_part(part: EnemyModule, params: Dictionary) -> void:
	if part == null or part.is_destroyed() or part.hurt_box == null or _shields.has(part.module_id):
		return
	var shield := EnemyShield.new()
	shield.name = "SectorShield"
	shield.arc_deg = 360.0
	shield.sustain_mode = false
	shield.capacity = int(params.get("capacity", shield.capacity))
	shield.regen_delay = float(params.get("regen_delay", shield.regen_delay))
	shield.regen_seconds = float(params.get("regen_seconds", shield.regen_seconds))
	shield.reboot_seconds = float(params.get("reboot_seconds", shield.reboot_seconds))
	shield.radius = _hurt_radius(part.hurt_box) + float(params.get("radius_pad", 0.0))
	part.add_child(shield)
	shield.position = part.to_local(part.hurt_box.global_position)
	if not shield.attach(part.hurt_box):
		if OS.is_stdout_verbose():
			print("ShieldSector: absorber slot of ", part.module_id, " is taken; no bubble")
		part.remove_child(shield)
		shield.free()
		return
	_shields[part.module_id] = shield
	_hurt_boxes[part.module_id] = part.hurt_box
	part.destroyed.connect(_on_part_destroyed)


## A circle's radius, a rectangle's half-diagonal (other shapes: the half-diagonal of their bounding rect), times the shape node's scale.
func _hurt_radius(hurt_box: HurtBox) -> float:
	for child in hurt_box.get_children():
		var node := child as CollisionShape2D
		if node == null or node.shape == null:
			continue
		var base: float
		if node.shape is CircleShape2D:
			base = (node.shape as CircleShape2D).radius
		elif node.shape is RectangleShape2D:
			base = (node.shape as RectangleShape2D).size.length() * 0.5
		else:
			base = node.shape.get_rect().size.length() * 0.5
		return base * maxf(absf(node.scale.x), absf(node.scale.y))
	return 0.0


func _on_generator_destroyed(_module: EnemyModule) -> void:
	_exposed = true
	for id in _shields.keys():
		_release(id)


func _on_part_destroyed(module: EnemyModule) -> void:
	_release(module.module_id)


## Detaches first (the slot is free this instant), then frees.
func _release(module_id: StringName) -> void:
	var shield := _shields.get(module_id) as EnemyShield
	_shields.erase(module_id)
	if not is_instance_valid(shield):
		return
	var host_hurt_box := _hurt_boxes.get(module_id) as HurtBox
	_hurt_boxes.erase(module_id)
	if host_hurt_box != null and is_instance_valid(host_hurt_box):
		host_hurt_box.clear_absorber(shield)
	shield.queue_free()
