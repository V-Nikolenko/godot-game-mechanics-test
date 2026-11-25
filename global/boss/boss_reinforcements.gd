## BossReinforcements — runs a boss's `ReinforcementBay`s: door cycles, launches, caps, dead bays and surges (IDEAS §10; Phase 11 §2.2,
## docs/plans/cmug256so0031m52wbxomst72/3-plan.md; built in t2). One per boss, built by the host and ticked by its brain on the physics tick;
## it holds no rule of any boss (Phase 12 and Phase 18 reuse it), so what a launch means is authored on the bays.
##
## THE CLOCK: `tick(delta, active)` is the only one (no `Timer`, no `create_timer`). `active` false (the player not engaged, an EMP window, the
## host dying) freezes the PERIODIC clocks, holds queued launches (a launch whose doors were OPENING goes back to the front of its queue) and
## closes open doors. Every door change runs from `tick()`, never from a physics callback, so `set_vulnerable()` is called directly.
##
## THE DOOR CYCLE, per bay, one launch at a time: a queued launch -> OPENING for `door_seconds` (the part's `Light` CHARGING; with `opens_part`
## the part is hittable) -> LAUNCH (the escorts come out; passed through inside the tick) -> OPEN for `open_hold_seconds` (still hittable;
## 0 closes at once) -> CLOSED (the `Light` back to the state it had when the doors started opening, so a generator's SHIELDED returns; with
## `opens_part` the part is locked again). `door_changed` reports open (OPENING) and closed.
##
## TRIGGERS (only while the bay is active: `active_from_phase` empty or reached): PERIODIC queues `count` every `period`, the first at
## `first_delay` from activation; ON_SECTOR_LOSS queues `count` per destroyed part among `watch_ids`; ON_PHASE queues `count` on entering
## `on_phase`. `surge()` queues an emergency launch whatever the trigger or activation. A bay whose own part is destroyed is DEAD: its queue
## is dropped (a launch mid-OPENING never comes out) and it never launches again.
##
## CAP: a launch puts out `min(count, live_cap - live_count())`; with no room it is skipped and counted (`skipped()`), whether found at the
## doors opening (they stay shut) or at LAUNCH. A PERIODIC clock keeps running through skips. Assault (`EnemyWorld.arena()` found) launches
## `assault_payload_scene` (else `payload_scene`) and at most `assault_launch_limit` launches per bay (-1 = no limit).
##
## SPAWNING (the `CarrierHangars` rule, synchronous, from the tick): each escort is seeded from the boss rng (`Brain.rng_seed`, non-zero),
## `start_engaged`, given the `SquadController` cached for its payload scene (one per scene for this object's life, created at that scene's
## first launch), spread across the launch direction at the bay's mouth, given collision exceptions both ways with the host, added to
## `EscortContainer.ensure(host)`, put in the boss's owner group, boosted outward and announced with `EventBus.boss_escort_spawned` — never
## `enemy_spawned_orphan`. Nothing writes `counts_toward_wave_clear` / `counts_as_escape` (`BaseEnemy._ready()` copies them from the escort's
## config; the escort scoring path never reads them).
##
## Tests: tests/integration/test_boss_reinforcements.gd (fixture tests/helpers/fixture_boss_host.tscn).
class_name BossReinforcements
extends RefCounted

## Each launch that put out at least one escort, with the escorts.
signal launched(bay_id: StringName, escorts: Array)
## A bay's doors started opening ([param open] true) or closed (false).
signal door_changed(bay_id: StringName, open: bool)

## Append-only. LAUNCH is passed through inside one tick.
enum Door { CLOSED, OPENING, OPEN }

## Escorts of one launch are spread this far apart across the launch direction (px; the `CarrierHangars` spacing).
const ESCORT_SPACING := 28.0
## The project clock rule: a limit is reached at >= limit - this.
const CLOCK_EPS := 1e-6
## A PERIODIC bay never re-queues faster than this (s), whatever its `period`.
const MIN_PERIOD := 0.01


## One bay's state.
class BayState extends RefCounted:
	var bay: ReinforcementBay
	var part: EnemyModule
	var light: StateLight
	var door: int = Door.CLOSED
	## Seconds in the current door state.
	var door_time: float = 0.0
	## Escorts asked for by the launch the doors are cycling for.
	var current: int = 0
	## The light's state when the doors started opening.
	var light_before: int = StateLight.State.OFF
	var activated: bool = false
	## PERIODIC: seconds active since activation, and the clock time the next launch is queued.
	var clock: float = 0.0
	var due: float = 0.0
	## Queued launches, each its escort count, served one door cycle at a time.
	var queue: Array[int] = []
	var launches: int = 0
	var skipped: int = 0
	var dead: bool = false


var _host: Node2D
var _driver: BossPhaseDriver
var _rng: RandomNumberGenerator
var _owner_group: StringName
var _live_cap: int
var _boost_speed: float
var _boost_seconds: float
var _bays: Dictionary = {}  # bay_id -> BayState
var _order: Array[BayState] = []
var _squads: Dictionary = {}  # payload scene key -> SquadController


func _init(host: Node2D, hull: ModularHull, driver: BossPhaseDriver, rng: RandomNumberGenerator, owner_group: StringName, live_cap: int,
		boost_speed: float, boost_seconds: float) -> void:
	_host = host
	_driver = driver
	_rng = rng if rng != null else RandomNumberGenerator.new()
	_owner_group = owner_group
	_live_cap = live_cap
	_boost_speed = boost_speed
	_boost_seconds = boost_seconds
	for part in _parts(host, hull):
		var bay := part.get_node_or_null(^"Bay") as ReinforcementBay
		if bay == null:
			continue
		var s := BayState.new()
		s.bay = bay
		s.part = part
		s.light = part.get_node_or_null(^"Light") as StateLight
		s.dead = part.is_destroyed()
		s.activated = bay.active_from_phase == &"" or (driver != null and driver.has_reached(bay.active_from_phase))
		s.due = bay.first_delay
		_bays[bay.bay_id] = s
		_order.append(s)
	if hull != null:
		hull.module_destroyed.connect(_on_module_destroyed)
	if driver != null:
		driver.phase_entered.connect(_on_phase_entered)


## One step. [param active]: the bays may run (see the file comment).
func tick(delta: float, active: bool) -> void:
	if not is_instance_valid(_host):
		return
	for s in _order:
		if s.dead:
			continue
		if not active:
			_hold(s)
			continue
		if s.activated and s.bay.trigger == ReinforcementBay.Trigger.PERIODIC:
			s.clock += delta
			while s.clock >= s.due - CLOCK_EPS:
				s.queue.append(s.bay.count_for(_is_assault()))
				s.due += maxf(s.bay.period_for(_is_assault()), MIN_PERIOD)
		s.door_time += delta
		match s.door:
			Door.CLOSED:
				if not s.queue.is_empty():
					_open(s)
			Door.OPENING:
				if s.door_time >= s.bay.door_seconds - CLOCK_EPS:
					_launch(s)
			Door.OPEN:
				if s.door_time >= s.bay.open_hold_seconds - CLOCK_EPS:
					_close(s)


## Queues an emergency launch of [param count] from bay [param bay_id] and returns how many escorts it asked for (a dead or unknown bay, or a
## count of 0: no-op, returns 0).
func surge(bay_id: StringName, count: int) -> int:
	var s: BayState = _bays.get(bay_id)
	if s == null or s.dead or count <= 0:
		return 0
	s.queue.append(count)
	return count


## The ids of the bays the boss phase ladder has activated (a bay with no `active_from_phase` counts from the start; a dead bay stays listed),
## sorted.
func activated_bay_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in _order:
		if s.activated:
			out.append(s.bay.bay_id)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## The live escorts: the `BaseEnemy` children of the host's escort container that are not queued for deletion (empty with no container).
func escorts() -> Array:
	var out: Array = []
	var container := EscortContainer.of(_host) if is_instance_valid(_host) else null
	if container == null:
		return out
	for child in container.get_children():
		if child is BaseEnemy and not child.is_queued_for_deletion():
			out.append(child)
	return out


## Kills every live escort (their normal death: explosion, squad bookkeeping). The host calls it when its death starts.
func scuttle_all() -> void:
	for escort: BaseEnemy in escorts():
		if escort.health != null:
			escort.health.set_health(0)


func live_count() -> int:
	return escorts().size()


## Every bay's id, in module order.
func bay_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for s in _order:
		out.append(s.bay.bay_id)
	return out


## Launches of [param bay_id] that put out at least one escort.
func launches(bay_id: StringName) -> int:
	var s: BayState = _bays.get(bay_id)
	return s.launches if s != null else 0


## Launches of [param bay_id] that found no room under the cap (or nothing to launch).
func skipped(bay_id: StringName) -> int:
	var s: BayState = _bays.get(bay_id)
	return s.skipped if s != null else 0


## Launches of [param bay_id] waiting for their door cycle (the one whose doors are opening not included).
func pending(bay_id: StringName) -> int:
	var s: BayState = _bays.get(bay_id)
	return s.queue.size() if s != null else 0


## True while [param bay_id]'s doors are OPENING or OPEN.
func door_open(bay_id: StringName) -> bool:
	var s: BayState = _bays.get(bay_id)
	return s != null and s.door != Door.CLOSED


## The door state of [param bay_id] (CLOSED for an unknown id).
func door(bay_id: StringName) -> int:
	var s: BayState = _bays.get(bay_id)
	return s.door if s != null else Door.CLOSED


func is_dead(bay_id: StringName) -> bool:
	var s: BayState = _bays.get(bay_id)
	return s != null and s.dead


func _parts(host: Node2D, hull: ModularHull) -> Array[EnemyModule]:
	if hull != null:
		return hull.modules()
	var out: Array[EnemyModule] = []
	var holder := host.get_node_or_null(^"Modules") if host != null else null
	if holder != null:
		for child in holder.get_children():
			if child is EnemyModule:
				out.append(child)
	return out


func _room() -> int:
	return _live_cap - live_count()


func _is_assault() -> bool:
	return EnemyWorld.arena(_host.get_tree()) != null


func _assault_limit_reached(s: BayState) -> bool:
	return s.bay.assault_launch_limit >= 0 and s.launches >= s.bay.assault_launch_limit and _is_assault()


## CLOSED -> OPENING for the front of the queue, unless the launch is refused first (Assault limit: the queue is dropped; no room: that one
## launch is skipped and the doors stay shut).
func _open(s: BayState) -> void:
	if _assault_limit_reached(s):
		s.queue.clear()
		return
	var asked: int = s.queue.pop_front()
	if _room() <= 0:
		s.skipped += 1
		return
	s.current = asked
	s.door = Door.OPENING
	s.door_time = 0.0
	if s.light != null:
		s.light_before = s.light.get_state()
		s.light.set_state(StateLight.State.CHARGING)
	if s.bay.opens_part:
		s.part.set_vulnerable(true)
	door_changed.emit(s.bay.bay_id, true)
	if s.bay.door_seconds <= CLOCK_EPS:
		_launch(s)


## LAUNCH then OPEN (then CLOSED at once when `open_hold_seconds` is 0). The count is clamped to the room left now.
func _launch(s: BayState) -> void:
	var n := mini(s.current, _room())
	var out: Array = _spawn(s, n) if n > 0 else []
	if out.is_empty():
		s.skipped += 1
	else:
		s.launches += 1
	s.door = Door.OPEN
	s.door_time = 0.0
	if not out.is_empty():
		launched.emit(s.bay.bay_id, out)
	if OS.is_stdout_verbose():
		print("[BossReinforcements] %s launched %d" % [s.bay.bay_id, out.size()])
	if s.bay.open_hold_seconds <= CLOCK_EPS:
		_close(s)


func _close(s: BayState) -> void:
	s.door = Door.CLOSED
	s.door_time = 0.0
	if s.light != null:
		s.light.set_state(s.light_before)
	if s.bay.opens_part:
		s.part.set_vulnerable(false)
	door_changed.emit(s.bay.bay_id, false)


## `active` false: a launch mid-OPENING goes back to the front of the queue and any open door closes.
func _hold(s: BayState) -> void:
	if s.door == Door.OPENING:
		s.queue.push_front(s.current)
	if s.door != Door.CLOSED:
		_close(s)


func _spawn(s: BayState, n: int) -> Array:
	var scene := s.bay.payload_scene
	if _is_assault() and s.bay.assault_payload_scene != null:
		scene = s.bay.assault_payload_scene
	var out: Array = []
	if scene == null:
		return out
	var container := EscortContainer.ensure(_host)
	if container == null:
		return out
	var mouth := s.bay.mouth_position()
	var outward := s.bay.launch_direction()
	var across := outward.orthogonal()
	for i in n:
		var escort := scene.instantiate() as Node2D
		if escort == null:
			continue
		_apply_overrides(escort, s.bay.config_overrides)
		escort.position = container.to_local(mouth + across * (float(i) - float(n - 1) * 0.5) * ESCORT_SPACING)
		var brain := escort.get_node_or_null(^"Brain")
		if brain != null:
			if &"rng_seed" in brain:
				brain.set(&"rng_seed", _rng.randi_range(1, 0x7FFFFFFF))
			if &"start_engaged" in brain:
				brain.set(&"start_engaged", true)
		if &"squad" in escort:
			escort.set(&"squad", _squad(scene))
		if escort is PhysicsBody2D and _host is PhysicsBody2D:
			(escort as PhysicsBody2D).add_collision_exception_with(_host)
			(_host as PhysicsBody2D).add_collision_exception_with(escort)
		out.append(escort)
	for escort: Node2D in out:
		container.add_child(escort)
		escort.add_to_group(_owner_group)
		var mover := escort.get_node_or_null(^"EnemyMover") as EnemyMover
		if mover != null:
			mover.boost(outward, _boost_speed, _boost_seconds)
		EventBus.boss_escort_spawned.emit(escort, _host)
	return out


## Writes [param overrides] on the escort's private `config` (`BaseEnemy._init()` already copied it; never the shared `.tres`).
func _apply_overrides(escort: Node, overrides: Dictionary) -> void:
	if overrides.is_empty():
		return
	var cfg: Variant = escort.get(&"config")
	if not cfg is Resource:
		return
	for key in overrides:
		if key in cfg:
			cfg.set(key, overrides[key])


## One board per payload scene for this object's life (the `CarrierHangars._squad(path)` rule).
func _squad(scene: PackedScene) -> SquadController:
	var key: Variant = scene.resource_path if not scene.resource_path.is_empty() else scene
	if not _squads.has(key):
		_squads[key] = SquadController.new()
	return _squads[key]


func _on_module_destroyed(part: EnemyModule) -> void:
	for s in _order:
		if s.dead:
			continue
		if s.part == part:
			_kill(s)
		elif s.activated and s.bay.trigger == ReinforcementBay.Trigger.ON_SECTOR_LOSS and s.bay.watch_ids.has(part.module_id):
			s.queue.append(s.bay.count_for(_is_assault()))


func _on_phase_entered(_index: int, phase_id: StringName) -> void:
	for s in _order:
		if not s.activated and s.bay.active_from_phase == phase_id:
			s.activated = true
			s.clock = 0.0
			s.due = s.bay.first_delay
	for s in _order:
		if not s.dead and s.activated and s.bay.trigger == ReinforcementBay.Trigger.ON_PHASE and s.bay.on_phase == phase_id:
			s.queue.append(s.bay.count_for(_is_assault()))


## The bay's part is a wreck: its queue goes, a launch mid-OPENING never comes out. The part's own `destroy()` already put its light out.
func _kill(s: BayState) -> void:
	s.dead = true
	s.queue.clear()
	if s.door != Door.CLOSED:
		s.door = Door.CLOSED
		door_changed.emit(s.bay.bay_id, false)
