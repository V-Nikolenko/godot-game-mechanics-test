## TurretGroup - a coordinator for turrets placed together with overlapping fire (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.10.1;
## task plan docs/plans/cmvqw0vnl0183qs2xbphzonu7/3-plan.md; Phase 8 t9). Behaviour: `STRUCTURE.md` beside this file.
##
## **A coordinator, not a parent.** A preset scene authors `TurretGroupSlot` children; `spawn_members()` (deferred from `_ready()`, because a wave may
## spawn the group inside a physics flush) instantiates each slot's member, hands it this group (`set_turret_group`, the slot's `variant` /
## `rest_bearing_deg`) **before** `add_child`, adds it to this group's own parent (the enemy container) and announces it with
## `EventBus.enemy_spawned_orphan`. Members are therefore ordinary enemies: their pools' container is the container, `ScoreTracker` scores them, they
## are in group `enemies` and in every roster gate. They also join `owner_group`, which every beam and ring of the group exempts.
## The group itself is never in `enemies` and never scored (no `died` signal; `counts_toward_wave_clear` and `counts_as_escape` false). It frees
## itself the frame its last member leaves. It does not drift; its members do.
##
## **World-anchored x (Assault).** A wave spawns at a camera-relative point. With `world_anchored_x` (the default) and an Assault arena, `_ready()`
## first removes the camera's horizontal pan from x (the view's centre minus the pinned corridor centre, read through `EnemyWorld`), so a spawn at
## design x lands at world `640 + 2·x` whatever the player did - the rule level 1's `LaserRay` columns follow. y stays camera-relative. A member that
## has `world_anchored_x` (a nested group, a laser fence) is spawned with it off: a slot position is already a world position.
##
## **Power (R8.12).** A member answering `provides_power() == true` (a `PowerSource`) is registered with `add_power_provider()`; any node with
## `provides_power()` and a `died` signal can be (the Ph20 jammer seam). The group is powered while any provider lives, or always if it never had
## one. On the last provider's `died` - in that same call, before its `queue_free()` - every live member gets `set_powered(false)` and
## `power_changed(false)` fires once. It never reverses in this phase (a later provider is ignored). A provider that leaves without dying (drifted
## out of Assault) is only forgotten; it does not darken the group.
##
## **Stagger.** `request_telegraph(member)` (every member turret's mount `telegraph_gate`) grants at most one TELEGRAPH start per `stagger_seconds`
## on the group's own clock, advanced by `tick(delta)` from `_physics_process` (the group is its members' earlier sibling, so it ticks first). A
## refused mount asks again next tick.
##
## **Coverage (R8.11).** `coverage_holes()` lists the points of `coverage_points()` (every 10 degrees at `coverage_radius`, local to the origin) that
## fewer than `coverage_min` mounts reach (`TurretMountScenes.reach_of`). Computed from the slots alone, so it works on an off-tree preset.
class_name TurretGroup
extends Node2D

signal power_changed(powered: bool)
signal member_left(member: Node)

## Spacing of the coverage points, degrees.
const COVERAGE_STEP_DEG := 10

## Every point at this distance from the origin must be reached by at least `coverage_min` mounts, px.
@export var coverage_radius: float = 180.0
@export var coverage_min: int = 2
## At most one member TELEGRAPH start per this many seconds across the group.
@export var stagger_seconds: float = 0.3
## Assault: remove the camera's horizontal pan from x in `_ready()` (see the class doc).
@export var world_anchored_x: bool = true

## Read by `ScoreTracker` for a wave spawn: the group is never in a wave tally and never an escape.
var counts_toward_wave_clear: bool = false
var counts_as_escape: bool = false
var score_value: int = 0
## The set every member joins; the group's beams and rings exempt it.
var owner_group: StringName = &""

var _members: Array[Node2D] = []
var _providers: Array[Node] = []
var _powered: bool = true
var _spawned: bool = false
var _clock: float = 0.0
var _last_grant: float = -INF


func _init() -> void:
	owner_group = StringName("turret_group_%d" % get_instance_id())


func _ready() -> void:
	var tree := get_tree()
	if world_anchored_x and EnemyWorld.has_view_rect(tree) and EnemyWorld.has_projectile_world_rect(tree):
		global_position.x -= EnemyWorld.view_rect(tree).get_center().x - EnemyWorld.projectile_world_rect(tree).get_center().x
	spawn_members.call_deferred()


func _physics_process(delta: float) -> void:
	tick(delta)


## Advances the stagger clock (hand-tickable).
func tick(delta: float) -> void:
	_clock += delta


## Spawns every slot's member as a sibling (see the class doc). Idempotent; a no-op outside the tree. The deferred call from `_ready()` is the
## production path; a hand-ticked test calls it directly.
func spawn_members() -> void:
	if _spawned or not is_inside_tree() or is_queued_for_deletion():
		return
	var parent := get_parent()
	if parent == null:
		return
	_spawned = true
	for child in get_children():
		var slot := child as TurretGroupSlot
		if slot == null or slot.member_scene == null:
			continue
		var member := slot.member_scene.instantiate() as Node2D
		if member == null:
			push_warning("TurretGroup: slot %s's scene has no Node2D root; skipped" % slot.name)
			continue
		var at := slot.global_position
		member.position = (parent as Node2D).to_local(at) if parent is Node2D else at
		if slot.variant >= 0 and "variant" in member:
			member.set("variant", slot.variant)
		if not is_nan(slot.rest_bearing_deg) and "rest_bearing_override" in member:
			member.set("rest_bearing_override", slot.rest_bearing_deg)
		if "world_anchored_x" in member:
			member.set("world_anchored_x", false)
		if member.has_method("set_turret_group"):
			member.call("set_turret_group", self)
		parent.add_child(member)
		_members.append(member)
		member.tree_exiting.connect(_on_member_exiting.bind(member), CONNECT_ONE_SHOT)
		if member.has_method("provides_power") and member.call("provides_power"):
			add_power_provider(member)
		EventBus.enemy_spawned_orphan.emit(member)
	if _members.is_empty():
		queue_free()


## The live members (spawned, not freed, not queued for deletion), in slot order.
func members() -> Array[Node2D]:
	var out: Array[Node2D] = []
	for member in _members:
		if is_instance_valid(member) and not member.is_queued_for_deletion():
			out.append(member)
	return out


func is_powered() -> bool:
	return _powered


## Registers a power provider: any node with `provides_power()` and a `died` signal. Ignored once the group is dark (no re-power in this phase).
func add_power_provider(node: Node) -> void:
	if node == null or not _powered or _providers.has(node) or not node.has_signal("died"):
		return
	_providers.append(node)
	node.connect("died", _on_provider_died.bind(node), CONNECT_ONE_SHOT)
	node.tree_exiting.connect(_forget_provider.bind(node), CONNECT_ONE_SHOT)


## The stagger gate (a member mount's `telegraph_gate`): true at most once per `stagger_seconds` across the group.
func request_telegraph(_member: Node) -> bool:
	if _clock - _last_grant + TurretMount.CLOCK_EPS < stagger_seconds:
		return false
	_last_grant = _clock
	return true


## The structures' answer to the player's mining beam: a group is never a wall.
func is_laser_blocking() -> bool:
	return false


## The coverage rule's points: every `COVERAGE_STEP_DEG` degrees at `coverage_radius`, local to the group origin.
func coverage_points() -> PackedVector2Array:
	var out := PackedVector2Array()
	for deg in range(0, 360, COVERAGE_STEP_DEG):
		out.append(Vector2.from_angle(deg_to_rad(deg)) * coverage_radius)
	return out


## One `{position, reach}` per turret mount the slots would spawn (local to the group origin), read from the member scenes off-tree.
func mount_reaches() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for child in get_children():
		var slot := child as TurretGroupSlot
		if slot == null or slot.member_scene == null:
			continue
		var probe := slot.member_scene.instantiate()
		var mount_slots := probe.get_node_or_null("MountSlots") as Node2D
		if mount_slots != null:
			var index := -1
			for marker in mount_slots.get_children():
				var mount_slot := marker as TurretMountSlot
				if mount_slot == null:
					continue
				index += 1
				var v: int = slot.variant if index == 0 and slot.variant >= 0 else int(mount_slot.variant)
				out.append({
					"position": slot.position + mount_slots.position + mount_slot.position,
					"reach": TurretMountScenes.reach_of(v),
				})
		probe.free()
	return out


## The coverage points that fewer than `coverage_min` mounts reach. Empty = the preset meets the rule.
func coverage_holes() -> PackedVector2Array:
	var reaches := mount_reaches()
	var holes := PackedVector2Array()
	for point in coverage_points():
		var covering := 0
		for r: Dictionary in reaches:
			if float(r["reach"]) >= (r["position"] as Vector2).distance_to(point):
				covering += 1
		if covering < coverage_min:
			holes.append(point)
	return holes


func _on_member_exiting(member: Node2D) -> void:
	_members.erase(member)
	member_left.emit(member)
	if _spawned and _members.is_empty() and is_inside_tree() and not is_queued_for_deletion():
		queue_free()


func _on_provider_died(node: Node) -> void:
	_forget_provider(node)
	if _powered and _providers.is_empty():
		_go_dark()


func _forget_provider(node: Node) -> void:
	_providers.erase(node)


func _go_dark() -> void:
	_powered = false
	for member in members():
		if member.has_method("set_powered"):
			member.call("set_powered", false)
	power_changed.emit(false)
