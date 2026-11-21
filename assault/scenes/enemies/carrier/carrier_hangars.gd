## CarrierHangars - the Carrier's two hangars: doors, launches, caps and emergency deployment (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.8;
## Phase 10 t8, task plan docs/plans/cmwafsrbc00anqs2y9y0ovll4/3-plan.md). One per carrier, built by `Carrier` (it knows the owner group) and ticked
## by `CarrierBrain` on its physics tick; it drives the HANGAR `EnemyModule`s and never reads the hull's type.
##
## THE DOOR CYCLE, per live hangar: CLOSED -> OPENING (`door_open_seconds`: doors sliding apart, light yellow, the hangar HITTABLE, owner choice 4)
## -> LAUNCH (the children come out; passed through inside one tick) -> OPEN (`door_hold_seconds`, still hittable) -> CLOSED (sealed again). A new
## OPENING needs the clock to be running (`tick(delta, active)`: Assault from the hull centre's first moment in the view, Open Space while engaged)
## and the hangar's `due` time reached; a cycle already under way runs on regardless.
##   Open Space: the port hangar first at `first_launch_delay`, the starboard `starboard_launch_delay` after it, then each every `launch_period`
##     from its previous OPENING, and only with room under the caps (`hangar_live_cap` live children of this hangar, `carrier_live_cap` of the
##     carrier): a hangar at its cap keeps its doors shut until a child is gone.
##   Assault: the same two first times, and ONE launch per hangar per life.
## A DESTROYED HANGAR NEVER LAUNCHES AGAIN: its cycle stops where it was, its doors hang open and broken; killed mid-OPENING, nothing comes out.
##
## SPAWNING (the `LaserTender.launch_pair()` rule): synchronous, from the brain's tick, never from a physics callback. Each child is placed at the
## hangar's `Mouth`, spread along the hull axis, seeded from the carrier brain's rng, `start_engaged` where its brain has it, given the payload's
## squad (one `SquadController` per payload scene, held here), collision exceptions both ways with the carrier, added as a SIBLING of the carrier,
## put in the carrier's owner group (its ring passes them), pushed outward by a committed `boost`, and announced once with
## `EventBus.enemy_spawned_orphan`. Children keep their own config, never dock, and outlive the carrier.
##
## EMERGENCY DEPLOYMENT (`emergency_deploy()`, PANIC entry, once): every live hangar that may still launch (Open Space: room under the caps;
## Assault: not launched yet) launches at once from whatever door state it is in, without the telegraph, then holds OPEN.
class_name CarrierHangars
extends RefCounted

## Append-only. LAUNCH is passed through inside one tick (`door_changed` reports it).
enum Door { CLOSED, OPENING, LAUNCH, OPEN }

## Every door transition, with the hangar's `module_id` and the state entered.
signal door_changed(module_id: StringName, door: int)
## Every launch, with the hangar's `module_id` and the children it put out.
signal launched(module_id: StringName, children: Array)

const PORT := &"hangar_port"
const STARBOARD := &"hangar_starboard"
## Children of one launch are spread this far apart along the hull axis (px).
const CHILD_SPACING := 28.0
## The project clock rule: a limit is reached at >= limit - this.
const CLOCK_EPS := 1e-6


## One hangar's state.
class Bay extends RefCounted:
	var module: EnemyModule
	var doors: CarrierHangarDoors
	var light: StateLight
	var mouth: Node2D
	var door: int = Door.CLOSED
	## Seconds in the current door state.
	var door_time: float = 0.0
	## The hangar clock time its next OPENING may start.
	var due: float = 0.0
	var launches: int = 0
	var children: Array[Node2D] = []
	var dead: bool = false


## True in Assault; written by the brain's `_start()`.
var assault: bool = false

var _host: Node2D
var _config: CarrierConfig
var _rng: RandomNumberGenerator
var _owner_group: StringName
var _bays: Dictionary = {}  # module_id -> Bay, port first
var _clock: float = 0.0
var _squads: Dictionary = {}  # scene path -> SquadController
var _scenes: Dictionary = {}  # scene path -> PackedScene


func _init(host: Node2D, hull: ModularHull, config: CarrierConfig, rng: RandomNumberGenerator, owner_group: StringName) -> void:
	_host = host
	_config = config
	_rng = rng
	_owner_group = owner_group
	var ordered: Array[EnemyModule] = []
	for part in hull.modules():
		if part.role == EnemyModule.Role.HANGAR:
			ordered.append(part)
	ordered.sort_custom(func(a: EnemyModule, b: EnemyModule) -> bool: return a.module_id == PORT and b.module_id != PORT)
	for i in ordered.size():
		var part := ordered[i]
		var bay := Bay.new()
		bay.module = part
		bay.doors = part.get_node_or_null(^"Doors") as CarrierHangarDoors
		bay.light = part.get_node_or_null(^"Light") as StateLight
		bay.mouth = part.get_node_or_null(^"Mouth") as Node2D
		bay.due = config.first_launch_delay + (config.starboard_launch_delay if i > 0 else 0.0)
		bay.dead = part.is_destroyed()
		part.destroyed.connect(_on_hangar_destroyed.bind(bay))
		_bays[part.module_id] = bay


## One step. [param active]: the schedule's clock runs (Assault: the hull has entered the view; Open Space: engaged).
func tick(delta: float, active: bool) -> void:
	if active:
		_clock += delta
	for bay: Bay in _bays.values():
		if bay.dead:
			continue
		bay.door_time += delta
		match bay.door:
			Door.CLOSED:
				if bay.doors != null:
					bay.doors.open_amount -= delta / maxf(_config.door_open_seconds, 0.01)
				if active and _clock >= bay.due - CLOCK_EPS and _may_launch(bay):
					_open(bay)
			Door.OPENING:
				if bay.doors != null:
					bay.doors.open_amount = bay.door_time / maxf(_config.door_open_seconds, 0.01)
				if bay.door_time >= _config.door_open_seconds - CLOCK_EPS:
					_launch(bay)
			Door.OPEN:
				if bay.door_time >= _config.door_hold_seconds - CLOCK_EPS:
					_set_door(bay, Door.CLOSED)
					bay.module.set_vulnerable(false)
					if bay.light != null:
						bay.light.set_state(StateLight.State.OFF)


## PANIC entry (the brain calls it once): every live hangar that may still launch launches now, with no telegraph.
func emergency_deploy() -> void:
	for bay: Bay in _bays.values():
		if bay.dead or not _may_launch(bay):
			continue
		if bay.door == Door.CLOSED:
			bay.module.set_vulnerable(true)
			if bay.light != null:
				bay.light.set_state(StateLight.State.CHARGING)
		if not assault:
			bay.due = _clock + _config.launch_period
		_launch(bay)


## Test hook: the doors of [param id] open for `door_hold_seconds` (hittable) without a launch and without spending one.
func force_open(id: StringName) -> void:
	var bay: Bay = _bays.get(id)
	if bay == null or bay.dead:
		return
	bay.module.set_vulnerable(true)
	if bay.light != null:
		bay.light.set_state(StateLight.State.CHARGING)
	if bay.doors != null:
		bay.doors.open_amount = 1.0
	_set_door(bay, Door.OPEN)


## The door state of hangar [param id] (CLOSED for an unknown id).
func door(id: StringName) -> int:
	var bay: Bay = _bays.get(id)
	return bay.door if bay != null else Door.CLOSED


## Launches hangar [param id] has made (an emergency deployment counts).
func launches(id: StringName) -> int:
	var bay: Bay = _bays.get(id)
	return bay.launches if bay != null else 0


## The live children hangar [param id] launched (valid and not queued for deletion).
func children_of(id: StringName) -> Array[Node2D]:
	var bay: Bay = _bays.get(id)
	if bay == null:
		return []
	_prune(bay)
	return bay.children.duplicate()


## Every live child of this carrier.
func live_count() -> int:
	var n := 0
	for bay: Bay in _bays.values():
		_prune(bay)
		n += bay.children.size()
	return n


## The schedule clock (s; runs only while active).
func clock() -> float:
	return _clock


## The hangars' module ids, port first.
func hangar_ids() -> Array:
	return _bays.keys()


func _may_launch(bay: Bay) -> bool:
	if assault:
		return bay.launches == 0
	return _room(bay) > 0


## Open Space: how many more children this hangar may have out now.
func _room(bay: Bay) -> int:
	_prune(bay)
	return mini(_config.hangar_live_cap - bay.children.size(), _config.carrier_live_cap - live_count())


func _open(bay: Bay) -> void:
	bay.module.set_vulnerable(true)
	if bay.light != null:
		bay.light.set_state(StateLight.State.CHARGING)
	if not assault:
		bay.due = _clock + _config.launch_period
	_set_door(bay, Door.OPENING)


## LAUNCH then OPEN, in one call. The count is read now: Assault's fixed one, or Open Space's clamped to the room left.
func _launch(bay: Bay) -> void:
	if bay.dead or bay.module.is_destroyed():
		return
	_set_door(bay, Door.LAUNCH)
	var n := _config.assault_launch_count if assault else mini(_config.launch_count, _room(bay))
	var path := _payload_path(bay)
	var out: Array[Node2D] = []
	var parent := _host.get_parent()
	if n > 0 and parent != null and not path.is_empty():
		var scene := _scene(path)
		if scene != null:
			out = _spawn(bay, scene, path, n, parent)
	bay.launches += 1
	bay.children.append_array(out)
	if bay.doors != null:
		bay.doors.open_amount = 1.0
	_set_door(bay, Door.OPEN)
	launched.emit(bay.module.module_id, out)
	if OS.is_stdout_verbose():
		print("[CarrierHangars] %s launched %d (%s)" % [bay.module.module_id, out.size(), path.get_file()])


func _spawn(bay: Bay, scene: PackedScene, path: String, n: int, parent: Node) -> Array[Node2D]:
	var mouth := bay.mouth.global_position if bay.mouth != null else bay.module.global_position
	var outward := mouth - bay.module.global_position
	outward = outward.normalized() if outward.length_squared() > 1e-6 else Vector2.RIGHT.rotated(_host.global_rotation)
	var along := outward.orthogonal()
	var out: Array[Node2D] = []
	for i in n:
		var child := scene.instantiate() as Node2D
		if child == null:
			continue
		var at := mouth + along * (float(i) - float(n - 1) * 0.5) * CHILD_SPACING
		child.position = (parent as Node2D).to_local(at) if parent is Node2D else at
		var brain := child.get_node_or_null(^"Brain")
		if brain != null:
			if &"rng_seed" in brain:
				brain.set(&"rng_seed", _rng.randi_range(1, 0x7FFFFFFF))
			if &"start_engaged" in brain:
				brain.set(&"start_engaged", true)
		if &"squad" in child:
			child.set(&"squad", _squad(path))
		if child is PhysicsBody2D and _host is PhysicsBody2D:
			(child as PhysicsBody2D).add_collision_exception_with(_host)
			(_host as PhysicsBody2D).add_collision_exception_with(child)
		out.append(child)
	for child in out:
		parent.add_child(child)
		child.add_to_group(_owner_group)
		var mover := child.get_node_or_null(^"EnemyMover") as EnemyMover
		if mover != null:
			mover.boost(outward, _config.launch_boost_speed, _config.launch_boost_seconds)
		EventBus.enemy_spawned_orphan.emit(child)
	return out


func _payload_path(bay: Bay) -> String:
	if assault:
		return _config.assault_hangar_scene
	return _config.hangar_port_scene if bay.module.module_id == PORT else _config.hangar_starboard_scene


func _scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) as PackedScene
	return _scenes[path]


func _squad(path: String) -> SquadController:
	if not _squads.has(path):
		_squads[path] = SquadController.new()
	return _squads[path]


func _set_door(bay: Bay, state: int) -> void:
	bay.door = state
	bay.door_time = 0.0
	door_changed.emit(bay.module.module_id, state)


func _prune(bay: Bay) -> void:
	for i in range(bay.children.size() - 1, -1, -1):
		var c: Variant = bay.children[i]
		if not is_instance_valid(c) or (c as Node).is_queued_for_deletion():
			bay.children.remove_at(i)


## The hangar's own destroy already turned its light OFF; the doors hang open, broken, and the cycle stops for good.
func _on_hangar_destroyed(_part: EnemyModule, bay: Bay) -> void:
	bay.dead = true
	if bay.doors != null:
		bay.doors.broken = true
		bay.doors.open_amount = 1.0
