## The Carrier's hangars: doors, launches, caps and emergency deployment (docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.8; Phase 10 t8, task plan
## docs/plans/cmwafsrbc00anqs2y9y0ovll4/3-plan.md, whose row names H1-H7 the tests follow). Intent tests.
##
## Hand-ticked at 1/60 (`_tick`: `_physics_process(dt)`, then the position integrated from the velocity, the `test_carrier.gd` driver), in both
## harnesses unless a row says otherwise; several carriers share one world and one loop where a row compares scenarios. The launched children are
## real nodes in the tree, but a hand-ticked loop runs inside one frame, so they neither move nor fire while it runs.
## Placement. Assault: inside the view at y 60, so the view is entered on the first tick. Open Space: engaged, on the 775 px circle round the still
## player at the origin, rotated so the port side (local +x) faces the player: that is the brain's own `desired_nose()` (no turn), inside the
## 600-950 px band (no movement) and beyond the 340 px pulse trigger (no ring). H2 runs on real physics at the 16x clock.
##
## Frame: the art is nose-down, so the nose is local +y, port (the hull's left) local +x, the stern local -y.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/carrier/carrier.tscn")
const SHIPPED: CarrierConfig = preload("res://assault/scenes/enemies/carrier/carrier_config.tres")  # read only
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const Door := CarrierHangars.Door
const RingPhase := EnergyRing.Phase

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const PORT := &"hangar_port"
const STARBOARD := &"hangar_starboard"
const ASSAULT_PLAYER := Vector2(640.0, 620.0)
const ASSAULT_Y := 60.0
const RING_RADIUS := 775.0
const BULLET_DAMAGE := 50
const VICTIM_RADIUS := 14.0
const VICTIM_HP := 1000
## A control victim sits this much further out than the child it guards (px).
const CONTROL_OUT := 20.0
## H7: the starboard hangar's delay after the port on that row's private config (s).
const STARBOARD_SOON := 0.5
## No child or control may sit within half a gap plus this of a gap when the band arrives (degrees; the round-2 fix-check note).
const GAP_MARGIN_DEG := 10.0
const _SPEEDUP := 16  # tests/README.md -> Gate time rule 1

var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()
	_roots.clear()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = ASSAULT_PLAYER if h.is_assault else Vector2.ZERO
	return h


## A carrier: Assault at x [param slot] (px) and y 60; Open Space on the 775 px circle at bearing [param slot] (degrees) from the player, its port
## side to the player. Hand-ticked unless [param physics]. [param props] are written on its private config before it enters the tree.
func _spawn(h, slot: float, props: Dictionary = {}, physics: bool = false) -> Carrier:
	var c := SCENE.instantiate() as Carrier
	(c.get_node("Brain") as CarrierBrain).start_engaged = true
	for key in props:
		c.config.set(key, props[key])
	if h.is_assault:
		c.global_position = Vector2(slot, ASSAULT_Y)
	else:
		var at := Vector2.from_angle(deg_to_rad(slot)) * RING_RADIUS
		c.global_position = at
		c.rotation = (h.player.global_position - at).angle()
	h.root.add_child(c)
	c.set_physics_process(physics)
	return c


func _tick(c: Carrier) -> void:
	if not is_instance_valid(c) or c.is_queued_for_deletion():
		return
	var before := c.global_position
	c._physics_process(DT)
	c.global_position = before + c.velocity * DT


## The time (s) at the end of tick [param i] (0-based).
func _t(i: int) -> float:
	return float(i + 1) * DT


func _ticks(seconds: float) -> int:
	return int(round(seconds / DT))


func _part(c: Node, part_name: String) -> EnemyModule:
	return c.get_node("Modules/" + part_name) as EnemyModule


func _light(c: Node, part_name: String) -> StateLight:
	return c.get_node("Modules/%s/Light" % part_name) as StateLight


func _doors(c: Node, part_name: String) -> CarrierHangarDoors:
	return c.get_node("Modules/%s/Doors" % part_name) as CarrierHangarDoors


## Every door transition and launch of [param c], stamped with the row's clock (`clock[0]` = the current tick index).
class Log extends RefCounted:
	var doors: Array = []      # [module_id, door, tick]
	var launches: Array = []   # [module_id, count, tick]
	var children: Array = []   # [module_id, child, tick, mouth global position, module global position]


func _log(c: Carrier, clock: Array[int]) -> Log:
	var log := Log.new()
	var hg := c.hangars()
	hg.door_changed.connect(func(id: StringName, d: int) -> void: log.doors.append([id, d, clock[0]]))
	hg.launched.connect(func(id: StringName, out: Array) -> void:
		log.launches.append([id, out.size(), clock[0]])
		var part_name := "HangarPort" if id == PORT else "HangarStarboard"
		var part := _part(c, part_name)
		var mouth := (part.get_node("Mouth") as Node2D).global_position
		for child in out:
			log.children.append([id, child, clock[0], mouth, part.global_position]))
	return log


## The ticks at which hangar [param id] entered door [param d].
func _door_ticks(log: Log, id: StringName, d: int) -> Array:
	var out: Array = []
	for e in log.doors:
		if e[0] == id and e[1] == d:
			out.append(e[2])
	return out


## [tick, count] of each launch of hangar [param id].
func _launches(log: Log, id: StringName) -> Array:
	var out: Array = []
	for e in log.launches:
		if e[0] == id:
			out.append([e[2], e[1]])
	return out


func _children_total(log: Log) -> int:
	var n := 0
	for e in log.launches:
		n += e[1]
	return n


## Exposes the core by wrecking the three named parts (three outer wrecks = `core_exposure_count`, read from the .tres by every row's precondition).
func _wreck(c: Carrier, part_names: Array) -> void:
	for part_name in part_names:
		_part(c, part_name).destroy()


## Force a hangar open (the test hook) and shoot it to death through its own hurtbox.
func _shoot_down_hangar(c: Carrier, id: StringName, part_name: String) -> void:
	c.hangars().force_open(id)
	var part := _part(c, part_name)
	part.hurt_box.received_damage.emit(part.max_health)


func _near_tick(actual: int, expected_seconds: float) -> bool:
	return absi(actual - (_ticks(expected_seconds) - 1)) <= 1


# ══ Config ══════════════════════════════════════════════════════════════════════════════════════

func test_the_shipped_hangar_numbers() -> void:
	var expected := {
		"hangar_port_scene": "res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn",
		"hangar_starboard_scene": "res://assault/scenes/enemies/fighter/fighter.tscn",
		"assault_hangar_scene": "res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn",
		"launch_count": 2, "assault_launch_count": 2, "door_open_seconds": 0.8, "door_hold_seconds": 2.0, "launch_period": 9.0,
		"hangar_live_cap": 3, "carrier_live_cap": 6, "first_launch_delay": 3.0, "starboard_launch_delay": 4.0, "launch_boost_speed": 300.0,
		"launch_boost_seconds": 0.4,
	}
	for key in expected:
		assert_eq(SHIPPED.get(key), expected[key], "carrier_config.tres %s" % key)
	assert_eq(CarrierHangars.Door.keys(), ["CLOSED", "OPENING", "LAUNCH", "OPEN"], "the append-only door order")
	assert_eq(SHIPPED.core_exposure_count, 3, "the exposure count the emergency rows wreck three parts for")


# ══ H1. The door telegraph and the hittable window ══════════════════════════════════════════════

func test_the_doors_open_before_the_children_come_out(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var c := _spawn(h, 640.0 if h.is_assault else 0.0)
	var clock: Array[int] = [0]
	var log := _log(c, clock)
	var port := _part(c, "HangarPort")
	var light := _light(c, "HangarPort")
	var doors := _doors(c, "HangarPort")
	var vulnerable: Array[bool] = []
	var lights: Array[int] = []
	var opens: Array[float] = []
	var lives: Array[int] = []
	for i in _ticks(SHIPPED.first_launch_delay + SHIPPED.door_open_seconds + SHIPPED.door_hold_seconds + 0.5):
		clock[0] = i
		_tick(c)
		vulnerable.append(port.is_vulnerable())
		lights.append(light.get_state())
		opens.append(doors.open_amount)
		lives.append(c.hangars().live_count())
	var opening: Array = _door_ticks(log, PORT, Door.OPENING)
	var closed: Array = _door_ticks(log, PORT, Door.CLOSED)
	var fired: Array = _launches(log, PORT)
	assert_eq(opening.size(), 1, "%s: one port OPENING" % mode)
	assert_eq(fired.size(), 1, "%s: one port launch" % mode)
	assert_eq(closed.size(), 1, "%s: the doors close once" % mode)
	if opening.size() != 1 or fired.size() != 1 or closed.size() != 1:
		return
	var o: int = opening[0]
	var l: int = fired[0][0]
	var cl: int = closed[0]
	assert_true(_near_tick(o, SHIPPED.first_launch_delay), "%s: OPENING at first_launch_delay (tick %d)" % [mode, o])
	assert_true(absi(l - o - _ticks(SHIPPED.door_open_seconds)) <= 1, "%s: the children come out door_open_seconds after the doors open (%d -> %d)" % [mode, o, l])
	assert_true(absi(cl - l - _ticks(SHIPPED.door_hold_seconds)) <= 1, "%s: and the doors close door_hold_seconds later (%d -> %d)" % [mode, l, cl])
	assert_eq(fired[0][1], SHIPPED.assault_launch_count if h.is_assault else SHIPPED.launch_count, "%s: two children" % mode)
	assert_eq(lives[o], 0, "%s: no child exists while the doors open" % mode)
	assert_eq(lives[l - 1], 0, "%s: none on the tick before the launch" % mode)
	for i in vulnerable.size():
		var window := i >= o and i < cl
		if vulnerable[i] != window:
			fail_test("%s: tick %d: the port hangar is hittable exactly from OPENING to the end of OPEN (window %d..%d)" % [mode, i, o, cl])
			return
		if (lights[i] == StateLight.State.CHARGING) != window:
			fail_test("%s: tick %d: the hangar light is yellow exactly while the doors are open" % [mode, i])
			return
	assert_eq(opens[o - 1], 0.0, "%s: the doors are shut before" % mode)
	for i in range(o + 1, l):
		if opens[i] <= opens[i - 1]:
			fail_test("%s: the doors slide open through OPENING (tick %d)" % [mode, i])
			return
	assert_eq(opens[l], 1.0, "%s: wide open at the launch" % mode)
	assert_lt(opens[opens.size() - 1], 1.0, "%s: closing again after OPEN" % mode)
	for e in log.children:
		var child: Node2D = e[1]
		assert_lte(child.global_position.distance_to(e[3]), CarrierHangars.CHILD_SPACING, "%s: a child appears at the port mouth" % mode)
		var mover := child.get_node("EnemyMover") as EnemyMover
		var outward: Vector2 = (e[3] - e[4]).normalized()
		assert_true(mover.is_boosting(), "%s: pushed out by a committed boost" % mode)
		assert_almost_eq(mover._boost_velocity.normalized().dot(outward), 1.0, 1e-3, "%s: outward, away from the hull" % mode)
		assert_almost_eq(mover._boost_velocity.length(), SHIPPED.launch_boost_speed, 1e-3, "%s: at launch_boost_speed" % mode)


# ══ H2. Hittable only while open (real physics) ═════════════════════════════════════════════════

## A real player bullet at [param target] from [param shot] px out along [param from_dir], its range ending [param beyond] px past the target; the
## record's `consumed` is true when it expired on a hit (range left), false at its range (it flew on). The `test_carrier.gd` probe.
func _shoot(target: Vector2, from_dir: Vector2, beyond: float, shot: float) -> Dictionary:
	var b := BULLET_SCENE.instantiate() as Bullet
	var notifier := b.get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier != null:
		b.remove_child(notifier)
		notifier.free()
	b.range_px = shot + beyond
	var rec := {"done": false, "consumed": false}
	b.expired.connect(func() -> void:
		rec["done"] = true
		rec["consumed"] = b._traveled < b.range_px)
	b.expired.connect(b.queue_free)
	_roots[0].add_child(b)
	b.global_position = target + from_dir * shot
	b.rotation = Vector2.UP.angle_to(-from_dir)
	return rec


func _await_until(cond: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if cond.call():
			return true
		await get_tree().physics_frame
	return cond.call()


## One shot at the port hangar from outboard (the carrier's port side), its range ending 40 px past the hangar centre: inside the hangar, short of
## the core and the starboard hangar. Waits for it to end.
func _shot_at_port(c: Carrier) -> Dictionary:
	var port := _part(c, "HangarPort")
	var out := Vector2.RIGHT.rotated(c.rotation)
	var rec := _shoot(port.global_position, out, 40.0, 300.0)
	await _await_until(func() -> bool: return rec["done"], 240)
	return rec


func test_a_hangar_takes_a_bullet_only_while_its_doors_are_open() -> void:
	_scale_clock()
	var h = _world("open_space")
	var c := _spawn(h, 0.0, {"missile_min_range": 1.0e6, "launch_count": 0, "first_launch_delay": 1.0}, true)
	var port := _part(c, "HangarPort")
	var hg := c.hangars()
	var hp := port.max_health
	await get_tree().physics_frame
	var before: Dictionary = await _shot_at_port(c)
	assert_true(before["done"] and not before["consumed"], "CLOSED: the bullet flies on")
	assert_eq(port.health.current_health, hp, "CLOSED: no damage")
	assert_true(await _await_until(func() -> bool: return hg.door(PORT) == Door.OPENING, 600), "precondition: the doors open")
	var opening: Dictionary = await _shot_at_port(c)
	assert_eq(hg.door(PORT), Door.OPENING, "precondition: the shot landed inside OPENING")
	assert_true(opening["done"] and opening["consumed"], "OPENING: the bullet is consumed")
	assert_eq(port.health.current_health, hp - BULLET_DAMAGE, "OPENING: the hangar takes it")
	assert_true(await _await_until(func() -> bool: return hg.door(PORT) == Door.OPEN, 120), "precondition: OPEN")
	var open: Dictionary = await _shot_at_port(c)
	assert_eq(hg.door(PORT), Door.OPEN, "precondition: the shot landed inside OPEN")
	assert_true(open["done"] and open["consumed"], "OPEN: the bullet is consumed")
	assert_eq(port.health.current_health, hp - 2 * BULLET_DAMAGE, "OPEN: the hangar takes it")
	assert_eq(hg.live_count(), 0, "precondition: launch_count 0 put no child on the line")
	assert_true(await _await_until(func() -> bool: return hg.door(PORT) == Door.CLOSED, 240), "precondition: CLOSED again")
	var after: Dictionary = await _shot_at_port(c)
	assert_true(after["done"] and not after["consumed"], "CLOSED again: the bullet flies on")
	assert_eq(port.health.current_health, hp - 2 * BULLET_DAMAGE, "CLOSED again: no damage")


# ══ H3. Open Space: the period and the caps over 60 s ═══════════════════════════════════════════

func test_open_space_launches_on_its_period_under_its_caps() -> void:
	var h = _world("open_space")
	var c := _spawn(h, 0.0)
	var hg := c.hangars()
	var clock: Array[int] = [0]
	var log := _log(c, clock)
	var freed_at := _ticks(30.0) - 1
	var cap_breach := ""
	for i in _ticks(60.0):
		clock[0] = i
		if i == freed_at:
			var kids := hg.children_of(PORT)
			assert_eq(kids.size(), SHIPPED.hangar_live_cap, "precondition: the port hangar holds its cap at 30 s")
			for k in 2:
				kids[k].queue_free()
		_tick(c)
		var p := hg.children_of(PORT).size()
		var s := hg.children_of(STARBOARD).size()
		if cap_breach.is_empty() and (p > SHIPPED.hangar_live_cap or s > SHIPPED.hangar_live_cap or hg.live_count() > SHIPPED.carrier_live_cap):
			cap_breach = "tick %d: %d / %d / %d live" % [i, p, s, hg.live_count()]
	assert_eq(cap_breach, "", "never more than hangar_live_cap per hangar or carrier_live_cap in all")
	for id in [PORT, STARBOARD]:
		var opens := _door_ticks(log, id, Door.OPENING)
		for k in range(1, opens.size()):
			assert_gte(opens[k] - opens[k - 1], _ticks(SHIPPED.launch_period) - 1, "%s: OPENINGs at least launch_period apart" % id)
	var port := _launches(log, PORT)
	var star := _launches(log, STARBOARD)
	var t0 := SHIPPED.first_launch_delay + SHIPPED.door_open_seconds
	assert_eq(port.size(), 3, "port: 3.8 s, 12.8 s, then capped until two of its children go, then 30.8 s: %s" % [port])
	assert_eq(star.size(), 2, "starboard: 7.8 s and 16.8 s, then capped: %s" % [star])
	if port.size() == 3 and star.size() == 2:
		assert_true(_near_tick(port[0][0], t0) and port[0][1] == 2, "port 2 at 3.8 s")
		assert_true(_near_tick(port[1][0], t0 + SHIPPED.launch_period) and port[1][1] == 1, "port 1 at 12.8 s (clamped to its cap)")
		assert_true(absi(port[2][0] - freed_at - _ticks(SHIPPED.door_open_seconds)) <= 1 and port[2][1] == 2, "port 2 again, the tick after two were freed + the telegraph")
		var st := t0 + SHIPPED.starboard_launch_delay
		assert_true(_near_tick(star[0][0], st) and star[0][1] == 2, "starboard 2 at 7.8 s")
		assert_true(_near_tick(star[1][0], st + SHIPPED.launch_period) and star[1][1] == 1, "starboard 1 at 16.8 s")
	# Boundary: a hangar at its cap keeps its doors shut (no OPENING between the 12.0 s one and the free).
	for o in _door_ticks(log, PORT, Door.OPENING):
		assert_false(o > _ticks(SHIPPED.first_launch_delay + SHIPPED.launch_period) and o < freed_at, "the port doors never open while it holds its cap (tick %d)" % o)
	assert_eq(hg.children_of(PORT).size(), 3, "the port hangar ends at its cap")
	assert_eq(hg.live_count(), SHIPPED.carrier_live_cap, "the carrier ends at its cap")


# ══ H4. Open Space: a destroyed hangar stops launching ══════════════════════════════════════════

func test_a_destroyed_hangar_never_launches_again_in_open_space() -> void:
	var h = _world("open_space")
	var a := _spawn(h, 0.0)    # HangarPort destroyed at 1.0 s, CLOSED
	var b := _spawn(h, 120.0)  # both destroyed at 1.0 s
	var c := _spawn(h, 240.0)  # HangarPort destroyed at 3.4 s, mid-OPENING
	var cars: Array[Carrier] = [a, b, c]
	var clock: Array[int] = [0]
	var logs: Array = cars.map(func(k: Carrier) -> Log: return _log(k, clock))
	var rockets: Array = cars.map(func(k: Carrier) -> Array[int]:
		var n: Array[int] = [0]
		k.missile_mount().round_fired.connect(func(_p: Node2D) -> void: n[0] += 1)
		return n)
	var early := _ticks(1.0) - 1
	var mid := _ticks(3.4) - 1
	var light_lit_after := -1
	for i in _ticks(40.0):
		clock[0] = i
		if i == early:
			_part(a, "HangarPort").destroy()
			_part(b, "HangarPort").destroy()
			_part(b, "HangarStarboard").destroy()
		if i == mid:
			assert_eq(c.hangars().door(PORT), Door.OPENING, "precondition: carrier C's port doors are opening at 3.4 s")
			_part(c, "HangarPort").destroy()
		for k in cars:
			_tick(k)
		if i > mid and light_lit_after < 0 and _light(c, "HangarPort").get_state() != StateLight.State.OFF:
			light_lit_after = i
	# (a) one destroyed while closed.
	assert_gt(logs[0].launches.size(), 0, "A: the starboard hangar still launches")
	for e in logs[0].launches:
		assert_eq(e[0], STARBOARD, "A: every launch came out of the starboard hangar")
	assert_eq(a.hangars().children_of(PORT).size(), 0, "A: no port child")
	# (b) both destroyed.
	assert_eq(logs[1].launches.size(), 0, "B: no launch at all")
	assert_eq(b.hangars().live_count(), 0, "B: no child ever")
	for k in 2:
		var car: Carrier = cars[k]
		assert_eq((car.get_node("Brain") as CarrierBrain).phase, CarrierBrain.Phase.SCREEN, "%s: still screening" % ["A", "B"][k])
		assert_gt(rockets[k][0], 0, "%s: and fighting (the missile bank fired)" % ["A", "B"][k])
	# (c) destroyed mid-OPENING.
	assert_eq(_launches(logs[2], PORT).size(), 0, "C: killed mid-OPENING, the port never launches")
	assert_eq(c.hangars().door(PORT), Door.OPENING, "C: its cycle stopped where it was")
	assert_true(_doors(c, "HangarPort").broken and _doors(c, "HangarPort").open_amount == 1.0, "C: its doors hang open, broken")
	assert_eq(light_lit_after, -1, "C: the wreck's light stays OFF on every later tick")
	var star := _launches(logs[2], STARBOARD)
	assert_eq(star.size(), 2, "C: the starboard launches as normal (7.8 s, 16.8 s): %s" % [star])
	if star.size() == 2:
		assert_true(star[0][1] == 2 and star[1][1] == 1, "C: 2 then 1 (its cap)")


# ══ H5. Assault: one launch per hangar, and a destroyed one never launches ══════════════════════

func test_assault_launches_once_per_hangar_and_never_from_a_wreck() -> void:
	var h = _world("assault")
	var a := _spawn(h, 250.0)   # port forced open and shot at 2.0 s
	var b := _spawn(h, 640.0)   # both at 2.0 s
	var c := _spawn(h, 1030.0)  # undisturbed
	var cars: Array[Carrier] = [a, b, c]
	var clock: Array[int] = [0]
	var logs: Array = cars.map(func(k: Carrier) -> Log: return _log(k, clock))
	var at := _ticks(2.0) - 1
	var most := 0
	for i in _ticks(16.0):
		clock[0] = i
		if i == at:
			_shoot_down_hangar(a, PORT, "HangarPort")
			_shoot_down_hangar(b, PORT, "HangarPort")
			_shoot_down_hangar(b, STARBOARD, "HangarStarboard")
		var alive := false
		for k in cars:
			if is_instance_valid(k) and not k.is_queued_for_deletion():
				alive = true
				_tick(k)
		most = maxi(most, _children_total(logs[2]))
		if not alive:
			break
	assert_true(_part(a, "HangarPort").is_destroyed() if is_instance_valid(a) else true, "precondition: A's port hangar was shot down")
	# (a)
	assert_eq(_launches(logs[0], PORT).size(), 0, "A: no port launch at 3.0 s or ever")
	var a_star := _door_ticks(logs[0], STARBOARD, Door.OPENING)
	assert_eq(a_star.size(), 1, "A: the starboard opens once")
	if a_star.size() == 1:
		assert_true(_near_tick(a_star[0], SHIPPED.first_launch_delay + SHIPPED.starboard_launch_delay), "A: at 7.0 s")
	assert_eq(_children_total(logs[0]), SHIPPED.assault_launch_count, "A: 2 children in all")
	# (b)
	assert_eq(logs[1].launches.size(), 0, "B: no child in the whole crossing")
	# (c)
	var cp := _launches(logs[2], PORT)
	var cs := _launches(logs[2], STARBOARD)
	assert_eq(cp.size(), 1, "C: exactly one port launch")
	assert_eq(cs.size(), 1, "C: exactly one starboard launch")
	if cp.size() == 1 and cs.size() == 1:
		assert_true(_near_tick(cp[0][0], SHIPPED.first_launch_delay + SHIPPED.door_open_seconds), "C: port at 3.8 s")
		assert_true(_near_tick(cs[0][0], SHIPPED.first_launch_delay + SHIPPED.starboard_launch_delay + SHIPPED.door_open_seconds), "C: starboard at 7.8 s")
	assert_eq(_children_total(logs[2]), 2 * SHIPPED.assault_launch_count, "C: 4 children")
	assert_eq(most, 2 * SHIPPED.assault_launch_count, "C: never more")
	for e in logs[2].children:
		assert_eq((e[1] as Node).scene_file_path, SHIPPED.assault_hangar_scene, "C: swarm drones only in Assault")


# ══ H6. Emergency deployment ════════════════════════════════════════════════════════════════════

## The PANIC tick's door sequence for hangar [param id]: CLOSED -> LAUNCH -> OPEN on one tick, no OPENING before it.
func _deployed_without_telegraph(log: Log, id: StringName, tick: int) -> bool:
	return _door_ticks(log, id, Door.OPENING).is_empty() and _door_ticks(log, id, Door.LAUNCH) == [tick] and _door_ticks(log, id, Door.OPEN) == [tick]


func test_panic_empties_every_live_hangar_at_once(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var slots := [160.0, 480.0, 800.0, 1120.0] if h.is_assault else [0.0, 180.0]
	var cars: Array[Carrier] = []
	for s in slots:
		cars.append(_spawn(h, s))
	var clock: Array[int] = [0]
	var logs: Array = cars.map(func(k: Carrier) -> Log: return _log(k, clock))
	var panic_tick: Array = cars.map(func(_k: Carrier) -> int: return -1)
	for k in cars.size():
		var idx := k
		(cars[k].get_node("Brain") as CarrierBrain).phase_changed.connect(func(p: int) -> void:
			if p == CarrierBrain.Phase.PANIC:
				panic_tick[idx] = clock[0])
	var early := _ticks(1.0) - 1
	var mid := _ticks(3.4) - 1
	var late := _ticks(5.0) - 1
	for i in _ticks(9.0 if h.is_assault else 2.0):
		clock[0] = i
		if i == early:
			_wreck(cars[0], ["EnginePort", "EngineStarboard", "GunPort"])         # (a) both hangars live
			_wreck(cars[1], ["HangarPort", "EnginePort", "EngineStarboard"])      # (b) the port destroyed
		if h.is_assault and i == mid:
			assert_eq(cars[3].hangars().door(PORT), Door.OPENING, "precondition: D's port doors are opening")
			_wreck(cars[3], ["EnginePort", "EngineStarboard", "GunPort"])         # (d) mid-OPENING
		if h.is_assault and i == late:
			assert_eq(cars[2].hangars().launches(PORT), 1, "precondition: C's port launched at 3.8 s")
			_wreck(cars[2], ["EnginePort", "EngineStarboard", "GunPort"])         # (c) the port already launched
		for k in cars:
			_tick(k)
	var kids := SHIPPED.assault_launch_count if h.is_assault else SHIPPED.launch_count
	# (a)
	assert_eq(panic_tick[0], early, "%s A: PANIC on the first tick after exposure" % mode)
	assert_true(_deployed_without_telegraph(logs[0], PORT, panic_tick[0]), "%s A: the port deploys on the PANIC tick, no telegraph: %s" % [mode, logs[0].doors])
	assert_true(_deployed_without_telegraph(logs[0], STARBOARD, panic_tick[0]), "%s A: the starboard too" % mode)
	assert_eq(_children_total(logs[0]), 2 * kids, "%s A: both payloads at once" % mode)
	# (b)
	assert_eq(panic_tick[1], early, "%s B: PANIC on the first tick after exposure" % mode)
	assert_eq(_launches(logs[1], PORT).size(), 0, "%s B: the destroyed port deploys nothing" % mode)
	assert_true(_deployed_without_telegraph(logs[1], STARBOARD, panic_tick[1]), "%s B: only the starboard deploys" % mode)
	assert_eq(_children_total(logs[1]), kids, "%s B: one payload" % mode)
	if not h.is_assault:
		return
	# (c)
	assert_eq(panic_tick[2], late, "C: PANIC after the port's launch")
	assert_eq(cars[2].hangars().launches(PORT), 1, "C: an Assault hangar that already launched deploys nothing")
	assert_eq(_launches(logs[2], PORT).size(), 1, "C: one port launch in all")
	assert_true(_deployed_without_telegraph(logs[2], STARBOARD, panic_tick[2]), "C: the starboard deploys")
	assert_eq(cars[2].hangars().launches(STARBOARD), 1, "C: and never opens again at 7.0 s")
	# (d)
	assert_eq(panic_tick[3], mid, "D: PANIC while the port doors open")
	var dp := _launches(logs[3], PORT)
	assert_eq(dp.size(), 1, "D: the port launches once (on the PANIC tick, not again at 3.8 s): %s" % [dp])
	if dp.size() == 1:
		assert_eq(dp[0][0], panic_tick[3], "D: on the PANIC tick")
	assert_eq(cars[3].hangars().launches(PORT), 1, "D: one launch spent")
	assert_eq(_launches(logs[3], STARBOARD).size(), 1, "D: the starboard deploys too")
	assert_eq(_children_total(logs[3]), 2 * kids, "D: 4 children")


# ══ H7. The children ════════════════════════════════════════════════════════════════════════════

func _victim(h, at: Vector2) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = VICTIM_RADIUS
	cs.shape = circle
	e.get_node("HurtBox").add_child(cs)
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = VICTIM_HP
	health.current_health = VICTIM_HP
	h.root.add_child(e)
	e.set_physics_process(false)
	e.global_position = at
	return e


## A gap start (degrees) for which no bearing of [param targets] ([bearing rad, distance px]) lies within half a gap + `GAP_MARGIN_DEG` of a gap
## centre when the band arrives (the ring's own telegraph, speed and spin), or NAN.
func _clear_gap_start(ring: EnergyRing, targets: Array) -> float:
	var step := 360.0 / float(maxi(ring.gap_count, 1))
	for g in range(0, 360, 5):
		var ok := true
		for t in targets:
			var at_clock: float = ring.telegraph_seconds + float(t[1]) / ring.ring_speed
			for k in ring.gap_count:
				var centre := deg_to_rad(float(g) + step * k + ring.gap_spin_deg * at_clock)
				if absf(rad_to_deg(angle_difference(centre, float(t[0])))) <= ring.gap_deg * 0.5 + GAP_MARGIN_DEG:
					ok = false
		if ok:
			return float(g)
	return NAN


func test_children_are_announced_siblings_in_the_owner_group_and_outlive_the_carrier(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	# The starboard follows the port by 0.5 s here (its private config), so in Assault both launches come out within 45 px of descent and every child
	# is well inside the ring's 420 px reach when it is started below.
	if h.is_assault:
		h.player.global_position = Vector2(1240.0, 700.0)  # beyond pulse_trigger_range all along the descent: the row starts the only ring
	var c := _spawn(h, 640.0 if h.is_assault else 0.0, {"starboard_launch_delay": STARBOARD_SOON})
	var announced := {}
	var spy := func(e: Node) -> void: announced[e] = int(announced.get(e, 0)) + 1
	EventBus.enemy_spawned_orphan.connect(spy)
	var clock: Array[int] = [0]
	var log := _log(c, clock)
	for i in _ticks(SHIPPED.first_launch_delay + STARBOARD_SOON + SHIPPED.door_open_seconds + 0.1):
		clock[0] = i
		_tick(c)
	EventBus.enemy_spawned_orphan.disconnect(spy)
	var kids: Array[Node2D] = []
	for e in log.children:
		kids.append(e[1])
	assert_eq(kids.size(), 2 * SHIPPED.launch_count, "%s: precondition: both hangars launched" % mode)
	var squads := {}
	for e in log.children:
		var child: Node2D = e[1]
		var id: StringName = e[0]
		assert_eq(child.get_parent(), c.get_parent(), "%s: a child is the carrier's sibling" % mode)
		assert_eq(announced.get(child, 0), 1, "%s: announced exactly once" % mode)
		assert_true(child.is_in_group(c.owner_group()), "%s: in the carrier's owner group" % mode)
		var brain := child.get_node("Brain") as EnemyBrain
		assert_ne(brain.rng_seed, 0, "%s: seeded from the carrier's rng" % mode)
		assert_true(brain.get(&"start_engaged"), "%s: engaged from launch" % mode)
		assert_true((child as PhysicsBody2D).get_collision_exceptions().has(c), "%s: a collision exception with the carrier" % mode)
		var squad: SquadController = child.get(&"squad")
		assert_not_null(squad, "%s: in a squad" % mode)
		squads[id] = squads.get(id, []) + [squad]
	assert_eq(announced.size(), kids.size(), "%s: nothing else announced" % mode)
	for id in squads:
		assert_eq(squads[id][0], squads[id][1], "%s: a launch shares its payload's squad (%s)" % [mode, id])
	if h.is_assault:
		assert_eq(squads[PORT][0], squads[STARBOARD][0], "assault: one payload kind, one squad")
	else:
		assert_ne(squads[PORT][0], squads[STARBOARD][0], "open_space: drones and fighters fly in their own squads")

	# The ring passes its children: one control outside the owner group beside each child, every one hurt.
	var centre := c.global_position
	var controls: Array[BaseEnemy] = []
	var targets: Array = []
	for kid in kids:
		var off := kid.global_position - centre
		controls.append(_victim(h, centre + off.normalized() * (off.length() + CONTROL_OUT)))
		targets.append([off.angle(), off.length()])
		targets.append([off.angle(), off.length() + CONTROL_OUT])
	var ring := c.pulse_ring()
	assert_eq(ring.phase(), RingPhase.OFF, "%s: precondition: no ring of the carrier's own is running" % mode)
	var gap := _clear_gap_start(ring, targets)
	assert_false(is_nan(gap), "%s: precondition: a gap start clear of every child and control" % mode)
	var hp: Array = kids.map(func(k: Node2D) -> int: return (k.get_node("Health") as Health).current_health)
	ring.start(gap)
	var reached: Array[bool] = []
	reached.resize(kids.size())
	reached.fill(false)
	for i in _ticks(4.0):
		ring.tick(DT)
		for k in kids.size():
			if not reached[k] and ring.phase() == RingPhase.EXPANDING and ring.radius() >= float(targets[2 * k][1]):
				reached[k] = true
				assert_false(ring.in_gap(float(targets[2 * k][0])), "%s: child %d is not in a gap when the band reaches it" % [mode, k])
		if ring.phase() == RingPhase.OFF:
			break
	for k in kids.size():
		assert_true(reached[k], "%s: the band passed child %d" % [mode, k])
		assert_eq((kids[k].get_node("Health") as Health).current_health, hp[k], "%s: the ring passes child %d" % [mode, k])
		assert_eq((controls[k].get_node("Health") as Health).current_health, VICTIM_HP - ring.damage, "%s: and hurts the control beside it" % mode)

	# They outlive the carrier.
	_part(c, "Core").destroy()
	assert_true(c.is_queued_for_deletion(), "%s: the core's death kills the carrier" % mode)
	await get_tree().process_frame
	assert_false(is_instance_valid(c), "%s: the carrier is gone" % mode)
	for kid in kids:
		assert_true(is_instance_valid(kid) and not kid.is_queued_for_deletion(), "%s: a child outlives its carrier" % mode)
