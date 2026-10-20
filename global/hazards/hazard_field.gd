## The one script behind the gravity well, the energy anomaly, the gravity field and the reactor field:
## a scene sets the exports and adds its sprite (composition, not four subclasses).
##
## A field applies nothing itself. It registers with `Hazards` and writes its live `HazardInfo`; ships
## and enemies SAMPLE it. Its one direct effect is hull stress: every `stress_period` while ACTIVE it
## calls `Hazards.pulse_damage` around its centre. Plan §2.1.
##
## Cycle: with any `cycle_*` length above 0 the field runs TELEGRAPH -> ACTIVE -> QUIET on a loop (all 0 =
## always ACTIVE). Outside ACTIVE the forces, the slow and the stress are 0; TELEGRAPH keeps `avoid_weight`
## so the AI still keeps clear of what is about to light up.
##
## Clocks are accumulated `delta` in `_physics_process`, never a `Timer`, so tests hand-tick it.
class_name HazardField
extends Node2D

enum Phase { ACTIVE, TELEGRAPH, QUIET }

signal phase_changed(phase: int)
signal stressed(count: int)

@export var kind: StringName = &"gravity_well"
@export var radius: float = 300.0
@export var core_radius: float = 40.0
## Radial acceleration at the core, px/s², toward the centre.
@export var pull_force: float = 0.0
## Swirl acceleration at the core, px/s². The sign is the direction (+ = clockwise); a negative value flips it.
@export var tangential_force: float = 0.0
@export_range(0.0, 1.0) var movement_penalty: float = 0.0
@export_range(0.0, 1.0) var avoid_weight: float = 1.0
@export var damage_radius: float = 0.0
## Damage per hull-stress pulse (0 = none).
@export var stress_damage: int = 0
@export var stress_period: float = 1.0
## Seconds until the field frees itself (0 = permanent).
@export var duration: float = 0.0
@export var cycle_telegraph: float = 0.0
@export var cycle_active: float = 0.0
@export var cycle_quiet: float = 0.0

var _info := HazardInfo.new()
var _phase: int = Phase.ACTIVE
var _cycle_clock: float = 0.0
var _age: float = 0.0
var _stress_clock: float = 0.0
var _pending_transform: bool = false
var _at: Vector2 = Vector2.ZERO
var _rot: float = 0.0


## Adds the field to [param container] at the next message flush, at global position [param at] and
## rotation [param rot]. Safe to call inside an `area_entered` callback, where adding a body
## synchronously is refused. The deferred call is made on the FIELD (`ContactBlast.spawn` pattern): a deferred
## `add_child` whose target was freed first is silently dropped and the orphan would leak.
func spawn_into(container: Node, at: Vector2, rot: float = 0.0) -> void:
	_at = at
	_rot = rot
	_pending_transform = true
	_attach.call_deferred(container)


## Untyped on purpose: a typed `Node` parameter makes the deferred call itself fail on a freed container.
## `queue_free()`, not `free()`: an object cannot free itself from inside its own deferred call.
func _attach(container) -> void:
	if is_instance_valid(container) and (container as Node).is_inside_tree():
		(container as Node).add_child(self)
	else:
		queue_free()


## A parentless Node2D's `global_position` is only its local position, so the stored transform is applied
## here, once parented.
func _enter_tree() -> void:
	if _pending_transform:
		global_position = _at
		rotation = _rot
		_pending_transform = false
	_cycle_clock = 0.0
	_phase = _phase_at(0.0)
	_refresh_info()
	Hazards.register(self)


func _exit_tree() -> void:
	Hazards.unregister(self)


func _physics_process(delta: float) -> void:
	_age += delta
	if duration > 0.0 and _age >= duration:
		queue_free()
		return
	if _cycles():
		_cycle_clock = fposmod(_cycle_clock + delta, _cycle_length())
		var next := _phase_at(_cycle_clock)
		if next != _phase:
			_phase = next
			_stress_clock = 0.0
			phase_changed.emit(_phase)
	if _phase == Phase.ACTIVE and _stress_enabled() and is_inside_tree():
		_stress_clock += delta
		while _stress_clock >= stress_period:
			_stress_clock -= stress_period
			var hit := Hazards.pulse_damage(get_tree(), global_position, damage_radius, stress_damage)
			if hit > 0:
				stressed.emit(hit)
	_refresh_info()


func phase() -> int:
	return _phase


## 0..1 through the current phase, for art. 0 when the field has no cycle.
func phase_progress() -> float:
	if not _cycles():
		return 0.0
	var start := 0.0
	var length := 0.0
	match _phase:
		Phase.TELEGRAPH:
			length = cycle_telegraph
		Phase.ACTIVE:
			start = cycle_telegraph
			length = cycle_active
		_:
			start = cycle_telegraph + cycle_active
			length = cycle_quiet
	if length <= 0.0:
		return 0.0
	return clampf((_cycle_clock - start) / length, 0.0, 1.0)


func hazard_info() -> HazardInfo:
	_info.position = global_position if is_inside_tree() else position
	return _info


func try_claim(node: Node) -> bool:
	return _info.try_claim(node)


func release(node: Node) -> void:
	_info.release(node)


func _cycles() -> bool:
	return _cycle_length() > 0.0


func _cycle_length() -> float:
	return maxf(cycle_telegraph, 0.0) + maxf(cycle_active, 0.0) + maxf(cycle_quiet, 0.0)


func _phase_at(t: float) -> int:
	if not _cycles():
		return Phase.ACTIVE
	if t < cycle_telegraph:
		return Phase.TELEGRAPH
	if t < cycle_telegraph + cycle_active:
		return Phase.ACTIVE
	return Phase.QUIET


func _stress_enabled() -> bool:
	return stress_damage > 0 and stress_period > 0.0 and damage_radius > 0.0


func _refresh_info() -> void:
	var active := _phase == Phase.ACTIVE
	_info.position = global_position if is_inside_tree() else position
	_info.kind = kind
	_info.source = self
	_info.radius = radius
	_info.core_radius = core_radius
	_info.damage_radius = damage_radius
	_info.pull_force = pull_force if active else 0.0
	_info.tangential_force = tangential_force if active else 0.0
	_info.movement_penalty = movement_penalty if active else 0.0
	_info.avoid_weight = avoid_weight if _phase != Phase.QUIET else 0.0
	_info.damage_per_second = float(stress_damage) / stress_period if active and _stress_enabled() else 0.0
