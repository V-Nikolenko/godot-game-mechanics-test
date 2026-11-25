## BossPhaseDriver — walks a boss through its ordered `BossPhase` ladder (IDEAS §25; Phase 11 §2.1, docs/plans/cmug256so0031m52wbxomst72/3-plan.md;
## built in t1). A `Node` child of the host root named `PhaseDriver`, the phases authored as sub-resources in the scene.
##
## `bind(hull, host_health)` enters phase 0 at once and starts listening to the hull's `module_destroyed` / `module_damaged` and to the
## `Health.amount_changed` of the host and of every part a HEALTH rule names. `evaluate()` enters each NEXT phase whose condition holds, in
## order, one `phase_entered` per phase, so one hit that satisfies two rules enters both inside the same call. One way: a phase is never left
## (a repair does not undo it), and a later phase never jumps its predecessor.
##
## **The driver never applies a consequence.** The host listens to `phase_entered` and changes itself (speed, guns, shields, bays, art);
## it holds no gameplay rule of any boss, so Phase 12 and Phase 18 reuse it unchanged. A part already destroyed when `bind()` runs counts.
##
## Tests: tests/unit/test_boss_phase_driver.gd, tests/integration/test_boss_phase_rules.gd.
class_name BossPhaseDriver
extends Node

## Once per phase entered, in ladder order. [param index] indexes `phases`.
signal phase_entered(index: int, phase_id: StringName)

## Float slack for `current <= ratio * max` (0.29 * 100 is 28.999999999999996).
const _RATIO_EPSILON := 1e-6

@export var phases: Array[BossPhase] = []

var _hull: ModularHull
var _host_health: Health
var _index: int = -1
var _evaluating: bool = false


## Enters phase 0 (emitting `phase_entered`), then `evaluate()`s. [param host_health] may be null when no rule reads the root.
func bind(hull: ModularHull, host_health: Health) -> void:
	_hull = hull
	_host_health = host_health
	if _hull != null:
		if not _hull.module_destroyed.is_connected(_on_module_destroyed):
			_hull.module_destroyed.connect(_on_module_destroyed)
		if not _hull.module_damaged.is_connected(_on_module_damaged):
			_hull.module_damaged.connect(_on_module_damaged)
	_watch(_host_health)
	for p in phases:
		if p != null and p.trigger == BossPhase.Trigger.HEALTH_AT_OR_BELOW and p.health_module != &"" and _hull != null:
			var part := _hull.module(p.health_module)
			if part != null:
				_watch(part.health)
	if _index < 0 and not phases.is_empty():
		_enter(0)
	evaluate()


## Enters every consecutive next phase whose condition holds. Safe to call from any listener (a host reacting to `phase_entered`
## re-enters it; the outer loop picks the change up).
func evaluate() -> void:
	if _evaluating or _index < 0:
		return
	_evaluating = true
	while _index + 1 < phases.size() and _holds(phases[_index + 1]):
		_enter(_index + 1)
	_evaluating = false


## -1 before `bind()`.
func current_index() -> int:
	return _index


func current_id() -> StringName:
	return phases[_index].phase_id if _index >= 0 and _index < phases.size() else &""


## True once [param phase_id] has been entered (the current phase and every earlier one).
func has_reached(phase_id: StringName) -> bool:
	for i in range(mini(_index + 1, phases.size())):
		if phases[i] != null and phases[i].phase_id == phase_id:
			return true
	return false


func phase(index: int) -> BossPhase:
	return phases[index] if index >= 0 and index < phases.size() else null


## The ladder's authoring errors, empty when it is well formed. The rules that read the hull (counts, ids) run only with [param hull].
func validate(hull: ModularHull = null) -> PackedStringArray:
	var errors := PackedStringArray()
	if phases.is_empty():
		errors.append("no phases")
		return errors
	var seen := {}
	for i in phases.size():
		var p := phases[i]
		if p == null:
			errors.append("phase %d is null" % i)
			continue
		var label := "phase %d '%s'" % [i, p.phase_id]
		if i == 0 and p.trigger != BossPhase.Trigger.START:
			errors.append("%s: the first phase must be a START trigger" % label)
		if i > 0 and p.trigger == BossPhase.Trigger.START:
			errors.append("%s: a START trigger is only legal at index 0" % label)
		if seen.has(p.phase_id):
			errors.append("%s: duplicate phase_id" % label)
		seen[p.phase_id] = true
		if i > 0 and BossPhase.change_count(p.changes) < 2:
			errors.append("%s: changes %d aspect(s), a phase must change at least 2" % [label, BossPhase.change_count(p.changes)])
		match p.trigger:
			BossPhase.Trigger.PARTS_DESTROYED:
				errors.append_array(_validate_parts(label, p, hull))
			BossPhase.Trigger.HEALTH_AT_OR_BELOW:
				if not (p.health_ratio > 0.0 and p.health_ratio < 1.0):
					errors.append("%s: health_ratio %s must be inside (0, 1)" % [label, p.health_ratio])
				if hull != null and p.health_module != &"" and hull.module(p.health_module) == null:
					errors.append("%s: health_module '%s' is not a part of the hull" % [label, p.health_module])
	return errors


func _validate_parts(label: String, p: BossPhase, hull: ModularHull) -> PackedStringArray:
	var errors := PackedStringArray()
	if p.count < 1:
		errors.append("%s: count %d must be at least 1" % [label, p.count])
	if hull == null:
		return errors
	var countable := 0
	if not p.module_ids.is_empty():
		for id in p.module_ids:
			if hull.module(id) == null:
				errors.append("%s: module id '%s' is not a part of the hull" % [label, id])
			else:
				countable += 1
	else:
		for part in hull.modules():
			if p.roles.is_empty() or p.roles.has(part.role):
				countable += 1
	if p.count > countable:
		errors.append("%s: count %d is more than the %d part(s) it can count" % [label, p.count, countable])
	return errors


func _watch(health: Health) -> void:
	if health != null and not health.amount_changed.is_connected(_on_health_changed):
		health.amount_changed.connect(_on_health_changed)


func _enter(index: int) -> void:
	_index = index
	phase_entered.emit(index, phases[index].phase_id)


func _holds(p: BossPhase) -> bool:
	if p == null:
		return false
	match p.trigger:
		BossPhase.Trigger.START:
			return true
		BossPhase.Trigger.PARTS_DESTROYED:
			return _hull != null and _destroyed_among(p) >= p.count
		BossPhase.Trigger.HEALTH_AT_OR_BELOW:
			var health := _host_health
			if p.health_module != &"":
				var part := _hull.module(p.health_module) if _hull != null else null
				health = part.health if part != null else null
			return health != null and health.max_health > 0 \
					and float(health.current_health) <= p.health_ratio * float(health.max_health) + _RATIO_EPSILON
	return false


func _destroyed_among(p: BossPhase) -> int:
	if not p.module_ids.is_empty():
		var n := 0
		for id in p.module_ids:
			var part := _hull.module(id)
			if part != null and part.is_destroyed():
				n += 1
		return n
	return _hull.destroyed_count(p.roles)


func _on_module_destroyed(_part: EnemyModule) -> void:
	evaluate()


func _on_module_damaged(_part: EnemyModule, _amount: int) -> void:
	evaluate()


func _on_health_changed(_current_health: int) -> void:
	evaluate()
