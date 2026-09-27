## A squad's role board (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.4). Event-driven: roles
## are recomputed only inside join(), leave() and release_lead() — there is no clock and no
## _process/_physics_process. It moves nothing; members read it and request their own motion, so
## the single-writer gate is untouched.
##
## Membership is weak: join() connects member.tree_exiting -> leave(member) so a freed member is
## always dropped, but that connection does *not* itself keep this RefCounted alive — Godot 4.6
## does not retain a strong reference through a signal connection. The real strong reference is
## whatever the caller stores the board in (a member's own `squad`-shaped property, per §2.4.1),
## so once every member drops that reference — typically by being freed — nothing keeps the board
## alive and it is collected. A member freed without ever entering a tree cannot fire tree_exiting,
## so every read also prunes stale (!is_instance_valid) entries.
class_name SquadController
extends RefCounted

enum Role { NONE, LEAD, FLANK_LEFT, FLANK_RIGHT, REAR }
enum Side { LEFT, RIGHT, FRONT, BACK }

## claim_side()'s "nearest free sector" order per preferred side: the two ring neighbours before
## the opposite. [judgement] — the plan pins the fallback behaviour, not this exact order.
const _SIDE_RING := {
	Side.LEFT: [Side.LEFT, Side.FRONT, Side.BACK, Side.RIGHT],
	Side.RIGHT: [Side.RIGHT, Side.FRONT, Side.BACK, Side.LEFT],
	Side.FRONT: [Side.FRONT, Side.LEFT, Side.RIGHT, Side.BACK],
	Side.BACK: [Side.BACK, Side.LEFT, Side.RIGHT, Side.FRONT],
}

signal role_changed(member: Node, role: int)

## Set true by the LEAD entering BURST, so FLANKs can start their own windup (§2.7.2). Only ever
## written true by the current LEAD, so leave()/release_lead() clear it whenever the member giving
## up LEAD held it — otherwise a LEAD that self-destructs on a successful hit would leave this
## stuck open forever (round-2 review N13).
var attack_window_open: bool = false

var target_position_hint: Vector2 = Vector2.ZERO
var target_heading_hint: Vector2 = Vector2.ZERO

var _members: Array[Node2D] = []
var _roles: Dictionary = {}     # Node2D -> Role
var _sides: Dictionary = {}    # Node -> Side
var _engaged: Dictionary = {}  # Node -> bool, present only while true


func join(member: Node2D) -> void:
	if _members.has(member):
		return
	_members.append(member)
	member.tree_exiting.connect(leave.bind(member))
	_reassign()


## Explicit and idempotent — rail suspension calls this directly, same as a free.
func leave(member: Node) -> void:
	var idx := _members.find(member)
	if idx == -1:
		return
	var was_lead: bool = _roles.get(member, Role.NONE) == Role.LEAD
	_members.remove_at(idx)
	_roles.erase(member)
	_sides.erase(member)
	_engaged.erase(member)
	if was_lead:
		attack_window_open = false
	_reassign()


func role_of(member: Node) -> Role:
	_prune()
	return _roles.get(member, Role.NONE)


func members() -> Array[Node2D]:
	_prune()
	return _members.duplicate()


## 0..n-1 among REAR members, in join order, for ring spacing. -1 if member is not a valid REAR.
func rear_index(member: Node) -> int:
	_prune()
	var i := 0
	for m in _members:
		if _roles.get(m, Role.NONE) != Role.REAR:
			continue
		if m == member:
			return i
		i += 1
	return -1


## Returns an unclaimed sector nearest `preferred`, latched to `member` until release_side(). If
## every sector is taken, `preferred` is returned anyway (shared). Re-claiming replaces a member's
## own prior claim rather than blocking on it.
## `int`, not `Side`, at this boundary: Godot 4.6's static checker treats a nested enum named from
## outside its declaring script (`SquadController.Side`) as a distinct type from the same enum
## named from inside (`Side`), and rejects a caller's value at this function's own parameter check
## — the same reason `role_changed` above declares `role: int` rather than `Role`.
func claim_side(member: Node, preferred: int) -> int:
	_prune()
	_sides.erase(member)
	var taken: Array = _sides.values()
	for side in _SIDE_RING[preferred]:
		if not taken.has(side):
			_sides[member] = side
			return side
	_sides[member] = preferred
	return preferred


func release_side(member: Node) -> void:
	_sides.erase(member)


## The finishing LEAD drops to REAR regardless of how close it still is to the hint, and the
## closest remaining member becomes LEAD — a deliberate rotation, not the steady-state assignment
## (which would just re-elect the same member back).
func release_lead(member: Node) -> void:
	_prune()
	if _roles.get(member, Role.NONE) != Role.LEAD:
		return
	attack_window_open = false
	_reassign(member)


func update_target(position: Vector2, heading: Vector2) -> void:
	target_position_hint = position
	target_heading_hint = heading


func set_engaged(member: Node, on: bool) -> void:
	if on:
		_engaged[member] = true
	else:
		_engaged.erase(member)


func is_engaged() -> bool:
	_prune()
	for m in _members:
		if _engaged.get(m, false):
			return true
	return false


func _prune() -> void:
	var pruned := false
	for i in range(_members.size() - 1, -1, -1):
		if not is_instance_valid(_members[i]):
			var m := _members[i]
			_members.remove_at(i)
			_roles.erase(m)
			_sides.erase(m)
			_engaged.erase(m)
			pruned = true
	if pruned:
		_reassign()


## Full recompute from current membership and the target hint (§2.4's "Assignment"). `force_rear`
## excludes one still-valid member from LEAD/FLANK candidacy for this call only (release_lead()'s
## rotation) and is pinned to REAR regardless of its distance to the hint.
func _reassign(force_rear: Node = null) -> void:
	if _members.is_empty():
		return
	var eligible := _members.duplicate()
	if force_rear != null:
		eligible.erase(force_rear)
	eligible.sort_custom(_closer_to_hint)

	var flank_count := clampi(eligible.size() - 1, 0, 2)
	var heading := _effective_heading()
	var used_sides: Dictionary = {}
	for i in eligible.size():
		var m: Node2D = eligible[i]
		var role: Role
		if i == 0:
			role = Role.LEAD
		elif i <= flank_count:
			role = _side_for(m.global_position, heading, used_sides)
			used_sides[role] = true
		else:
			role = Role.REAR
		_set_role(m, role)

	if force_rear != null and _members.has(force_rear):
		_set_role(force_rear, Role.REAR)


## Strict weak order: closer to target_position_hint first, ties broken by join order.
func _closer_to_hint(a: Node2D, b: Node2D) -> bool:
	var da := a.global_position.distance_squared_to(target_position_hint)
	var db := b.global_position.distance_squared_to(target_position_hint)
	if da != db:
		return da < db
	return _members.find(a) < _members.find(b)


## target_heading_hint, or (a zero hint) the direction from the squad centroid to the target hint.
## Falls back again to Vector2.RIGHT in the fully degenerate case (centroid == hint too).
func _effective_heading() -> Vector2:
	if target_heading_hint != Vector2.ZERO:
		return target_heading_hint
	var centroid := Vector2.ZERO
	for m in _members:
		centroid += m.global_position
	centroid /= _members.size()
	var fallback := target_position_hint - centroid
	return fallback if fallback != Vector2.ZERO else Vector2.RIGHT


## Sign of heading.cross(pos - target_position_hint): >= 0 is FLANK_RIGHT, < 0 is FLANK_LEFT. If
## that side is already used this pass, the other one is returned when it is still free.
func _side_for(pos: Vector2, heading: Vector2, used_sides: Dictionary) -> Role:
	var cross := heading.cross(pos - target_position_hint)
	var side: Role = Role.FLANK_RIGHT if cross >= 0.0 else Role.FLANK_LEFT
	if used_sides.has(side):
		var other: Role = Role.FLANK_LEFT if side == Role.FLANK_RIGHT else Role.FLANK_RIGHT
		if not used_sides.has(other):
			return other
	return side


func _set_role(member: Node2D, role: Role) -> void:
	if _roles.get(member, Role.NONE) == role:
		return
	_roles[member] = role
	role_changed.emit(member, role)
