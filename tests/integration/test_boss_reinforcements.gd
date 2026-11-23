## Boss reinforcements: `ReinforcementBay`, `BossReinforcements`, `EscortContainer`, `EventBus.boss_escort_spawned` and ScoreTracker's escort
## path (IDEAS §10; Phase 11 §2.2, docs/plans/cmug256so0031m52wbxomst72/3-plan.md; built in t2). Intent tests; row numbers follow the plan.
##
## On `tests/helpers/fixture_boss_host.tscn` (its header lists the parts and bays). Hand-ticked at 1/60 through `BossReinforcements.tick()`
## (the brain's job in a real boss); escorts are real scenes (Swarm Drone, Razor Drone in Assault, Fighter for the second bay) added to the
## tree, but a hand-ticked loop runs inside one frame, so they neither move nor fire while it runs. Rows whose outcome depends on the mode run
## in both `enemy_ai_harness` worlds; the director row (11) runs a real `LevelDirector` on a bare container, as `test_station_assault_section.gd`
## builds it.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const HOST_SCENE: PackedScene = preload("res://tests/helpers/fixture_boss_host.tscn")
const SWARM: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const RAZOR: PackedScene = preload("res://assault/scenes/enemies/razor_drone/razor_drone.tscn")
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const HANGAR := &"hangar"
const SECTOR := &"sector"
const BOOST_SPEED := 300.0
const BOOST_SECONDS := 0.4
## A PERIODIC bay that must stay quiet for a row (s).
const NEVER := 1.0e6
const HOST_AT_OPEN := Vector2(400.0, 0.0)
const HOST_AT_ASSAULT := Vector2(640.0, 200.0)


# ── Builders ─────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


## A fixture boss in [param parent]. [param bays]: bay_id -> {property: value} written on that bay before the rig reads it. The hangar
## launches Swarm Drones (Razor Drones in Assault), the sector bay Fighters; both bays stay quiet unless a row says otherwise.
func _host(parent: Node, bays: Dictionary = {}, at: Vector2 = HOST_AT_OPEN) -> BaseEnemy:
	var host := HOST_SCENE.instantiate() as BaseEnemy
	host.position = at
	var hangar := host.get_node("Modules/Hangar/Bay") as ReinforcementBay
	hangar.payload_scene = SWARM
	hangar.assault_payload_scene = RAZOR
	hangar.first_delay = NEVER
	var sector := host.get_node("Modules/Sector/Bay") as ReinforcementBay
	sector.payload_scene = FIGHTER
	for id in bays:
		var bay := hangar if id == HANGAR else sector
		for key in bays[id]:
			bay.set(key, bays[id][key])
	parent.add_child(host)
	return host


func _rig(host: BaseEnemy, live_cap: int = 20, driver: BossPhaseDriver = null, seed: int = 7) -> BossReinforcements:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return BossReinforcements.new(host, host.get_node("ModularHull") as ModularHull, driver, rng,
		StringName("fixture_boss_%d" % host.get_instance_id()), live_cap, BOOST_SPEED, BOOST_SECONDS)


func _part(host: Node, part_name: String) -> EnemyModule:
	return host.get_node("Modules/" + part_name) as EnemyModule


func _light(host: Node, part_name: String) -> StateLight:
	return host.get_node("Modules/%s/Light" % part_name) as StateLight


## Ticks [param r] for [param seconds] (rounded to whole ticks).
func _run(r: BossReinforcements, seconds: float, active: bool = true) -> void:
	for i in _ticks(seconds):
		r.tick(DT, active)


func _ticks(seconds: float) -> int:
	return int(round(seconds / DT))


## Every launch of [param r]: [bay_id, escort count, tick] with the tick read from `clock[0]`.
func _launch_log(r: BossReinforcements, clock: Array[int]) -> Array:
	var log: Array = []
	r.launched.connect(func(id: StringName, escorts: Array) -> void: log.append([id, escorts.size(), clock[0]]))
	return log


func _phase(id: StringName, trigger: BossPhase.Trigger, ids: Array[StringName] = []) -> BossPhase:
	var p := BossPhase.new()
	p.phase_id = id
	p.trigger = trigger
	p.module_ids = ids
	p.changes = BossPhase.Change.MOVEMENT | BossPhase.Change.REINFORCEMENTS
	return p


## A driver on [param host] with START `start` then `later` (entered when part `other` is destroyed), bound.
func _driver(host: BaseEnemy) -> BossPhaseDriver:
	var d := BossPhaseDriver.new()
	d.name = "PhaseDriver"
	var phases: Array[BossPhase] = [_phase(&"start", BossPhase.Trigger.START), _phase(&"later", BossPhase.Trigger.PARTS_DESTROYED, [&"other"])]
	d.phases = phases
	host.add_child(d)
	d.bind(host.get_node("ModularHull") as ModularHull, host.get_node("Health") as Health)
	return d


# ── Row 1: PERIODIC ─────────────────────────────────────────────────────────────────────────────

func test_periodic_launches_at_first_delay_plus_doors_then_every_period() -> void:
	for mode in MODES:
		var h = _world(mode)
		var host := _host(h.root, {HANGAR: {first_delay = 1.0, door_seconds = 0.5, period = 2.0}})
		var r := _rig(host)
		var clock: Array[int] = [0]
		var log := _launch_log(r, clock)
		for i in _ticks(6.0):
			clock[0] = i
			r.tick(DT, true)
		var times: Array = log.map(func(e: Array) -> float: return float(e[2] + 1) * DT)
		assert_eq(times.size(), 3, "%s: launches at 1.5, 3.5 and 5.5 s in 6 s" % mode)
		for k in mini(times.size(), 3):
			assert_almost_eq(times[k], 1.5 + 2.0 * k, DT * 0.5, "%s: launch %d at first_delay + door_seconds + %d periods" % [mode, k, k])
		assert_eq(r.launches(HANGAR), 3, mode)


func test_active_from_phase_holds_a_periodic_bay_until_the_driver_reaches_it() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {first_delay = 1.0, door_seconds = 0.5, period = 2.0, active_from_phase = &"later"}})
	var driver := _driver(host)
	var r := _rig(host, 20, driver)
	var clock: Array[int] = [0]
	var log := _launch_log(r, clock)
	for i in _ticks(4.0):
		clock[0] = i
		r.tick(DT, true)
	assert_eq(log.size(), 0, "no launch before the boss reaches `later`")
	_part(host, "Other").destroy()
	assert_eq(driver.current_id(), &"later", "precondition: destroying `other` entered `later`")
	var entered := _ticks(4.0)
	for i in range(entered, entered + _ticks(1.6)):
		clock[0] = i
		r.tick(DT, true)
	assert_eq(log.size(), 1, "one launch after the phase is reached")
	if log.size() == 1:
		assert_almost_eq(float(log[0][2] + 1 - entered) * DT, 1.5, DT * 0.5, "first_delay + door_seconds counted from the phase entry")


# ── Row 2: door telegraph ───────────────────────────────────────────────────────────────────────

## [param hold] = open_hold_seconds. Returns per tick [vulnerable, light state, door_open].
func _door_trace(hold: float) -> Dictionary:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {first_delay = 0.5, door_seconds = 0.6, open_hold_seconds = hold, period = NEVER}})
	_light(host, "Hangar").set_state(StateLight.State.SHIELDED)
	var r := _rig(host)
	var clock: Array[int] = [0]
	var log := _launch_log(r, clock)
	var trace: Array = []
	for i in _ticks(2.5):
		clock[0] = i
		r.tick(DT, true)
		trace.append([_part(host, "Hangar").is_vulnerable(), _light(host, "Hangar").get_state(), r.door_open(HANGAR)])
	return {trace = trace, log = log}


func test_doors_telegraph_with_the_light_and_open_the_part_for_opening_plus_hold() -> void:
	for hold in [0.0, 0.4]:
		var run := _door_trace(hold)
		var trace: Array = run.trace
		var first := -1
		var open_ticks := 0
		for i in trace.size():
			var on: bool = trace[i][0]
			if on:
				open_ticks += 1
				if first < 0:
					first = i
				assert_eq(trace[i][1], StateLight.State.CHARGING, "hold %.1f: the light is CHARGING while the doors are open (tick %d)" % [hold, i])
				assert_true(trace[i][2], "hold %.1f: door_open() agrees with the part (tick %d)" % [hold, i])
			else:
				assert_eq(trace[i][1], StateLight.State.SHIELDED, "hold %.1f: the light keeps / returns to its earlier state (tick %d)" % [hold, i])
				assert_false(trace[i][2], "hold %.1f: door_open() false while shut (tick %d)" % [hold, i])
		assert_almost_eq(float(first + 1) * DT, 0.5, DT * 0.5, "hold %.1f: the doors open at first_delay" % hold)
		assert_eq(open_ticks, _ticks(0.6 + hold), "hold %.1f: hittable for exactly door_seconds + open_hold_seconds" % hold)
		assert_eq(run.log.size(), 1, "hold %.1f: one launch" % hold)
		if run.log.size() == 1:
			assert_almost_eq(float(run.log[0][2] + 1) * DT, 1.1, DT * 0.5, "hold %.1f: the launch comes at the end of OPENING" % hold)


# ── Row 3: ON_SECTOR_LOSS ───────────────────────────────────────────────────────────────────────

func test_sector_loss_queues_one_launch_per_destroyed_watched_part() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {SECTOR: {door_seconds = 0.5}})
	var r := _rig(host)
	_part(host, "Other").destroy()
	_run(r, 1.0)
	assert_eq(r.launches(SECTOR), 0, "an unwatched part's loss launches nothing")
	_part(host, "WatchA").destroy()
	_run(r, 1.0)
	assert_eq(r.launches(SECTOR), 1, "a watched part's loss launches once")
	assert_eq(r.live_count(), 2, "one launch of `count` 2")

	var host2 := _host(h.root, {SECTOR: {door_seconds = 0.5}}, Vector2(-400.0, 0.0))
	var r2 := _rig(host2)
	_part(host2, "WatchA").destroy()
	_part(host2, "WatchB").destroy()
	assert_eq(r2.pending(SECTOR), 2, "two watched losses queue two launches")
	_run(r2, 0.6)
	assert_eq(r2.launches(SECTOR), 1, "served one door cycle at a time")
	_run(r2, 0.6)
	assert_eq(r2.launches(SECTOR), 2, "then the second")


# ── Row 4: dead bay ─────────────────────────────────────────────────────────────────────────────

func test_a_destroyed_bay_part_drops_its_queue_and_cancels_a_launch_mid_opening() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {SECTOR: {door_seconds = 0.5}})
	var r := _rig(host)
	_part(host, "WatchA").destroy()
	_part(host, "WatchB").destroy()
	_run(r, 0.25)
	assert_eq(r.door(SECTOR), BossReinforcements.Door.OPENING, "precondition: the first launch is mid-OPENING")
	assert_eq(r.pending(SECTOR), 1, "precondition: one more queued")
	_part(host, "Sector").destroy()
	assert_true(r.is_dead(SECTOR), "the bay dies with its part")
	assert_eq(r.pending(SECTOR), 0, "pending launches are dropped")
	assert_false(r.door_open(SECTOR), "the cycle stops")
	_run(r, 2.0)
	assert_eq(r.launches(SECTOR), 0, "nothing comes out of a dead bay, not even the launch that was opening")
	assert_eq(r.live_count(), 0)
	assert_null(EscortContainer.of(host), "no escort container was ever needed")


# ── Row 5: cap ──────────────────────────────────────────────────────────────────────────────────

func test_the_live_cap_clamps_a_launch_and_skips_one_with_no_room() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}})
	var r := _rig(host, 4)
	r.surge(HANGAR, 3)
	_run(r, 0.2)
	assert_eq(r.live_count(), 3, "precondition: 3 alive")
	r.surge(HANGAR, 2)
	_run(r, 0.2)
	assert_eq(r.live_count(), 4, "a count-2 launch with room for 1 spawns 1")
	assert_eq(r.launches(HANGAR), 2)
	r.surge(HANGAR, 2)
	_run(r, 0.2)
	assert_eq(r.live_count(), 4, "at the cap nothing comes out")
	assert_eq(r.skipped(HANGAR), 1, "the launch is skipped and counted")
	assert_eq(r.launches(HANGAR), 2, "a skipped launch is not a launch")
	assert_eq(r.pending(HANGAR), 0, "and it is not kept")


# ── Row 6: the escort container, seeds, groups and the boost ────────────────────────────────────

func test_escorts_land_in_a_lazy_sibling_container_freed_with_the_host() -> void:
	for mode in MODES:
		var h = _world(mode)
		var host := _host(h.root, {HANGAR: {door_seconds = 0.1}}, HOST_AT_ASSAULT if h.is_assault else HOST_AT_OPEN)
		var r := _rig(host)
		var group := StringName("fixture_boss_%d" % host.get_instance_id())
		assert_null(EscortContainer.of(host), "%s: no container before the first launch" % mode)
		r.surge(HANGAR, 2)
		_run(r, 0.2)
		var container := EscortContainer.of(host)
		assert_not_null(container, "%s: created at the first launch" % mode)
		if container == null:
			continue
		assert_eq(container.name, "%sEscorts" % host.name, mode)
		assert_eq(container.get_parent(), host.get_parent(), "%s: a sibling of the host" % mode)
		assert_true(container.is_in_group(EscortContainer.GROUP), mode)
		assert_eq(EscortContainer.ensure(host), container, "%s: ensure() finds the same one" % mode)
		var escorts := r.escorts()
		assert_eq(escorts.size(), 2, mode)
		var mouth := (host.get_node("Modules/Hangar/Bay") as ReinforcementBay).mouth_position()
		var outward := (mouth - host.global_position).normalized()
		for e: BaseEnemy in escorts:
			assert_eq(e.get_parent(), container, "%s: in the escort container, not the host's parent" % mode)
			assert_true(e.is_in_group(group), "%s: in the owner group" % mode)
			var brain := e.get_node("Brain")
			assert_true(brain.get(&"start_engaged"), "%s: start_engaged" % mode)
			assert_ne(int(brain.get(&"rng_seed")), 0, "%s: seeded" % mode)
			assert_lt(e.global_position.distance_to(mouth), BossReinforcements.ESCORT_SPACING, "%s: out of the mouth" % mode)
			var mover := e.get_node("EnemyMover") as EnemyMover
			assert_true(mover.is_boosting(), "%s: boosted" % mode)
			assert_almost_eq((mover.get("_boost_velocity") as Vector2).normalized().dot(outward), 1.0, 1e-4, "%s: outward from the host through the mouth" % mode)
			assert_almost_eq((mover.get("_boost_velocity") as Vector2).length(), BOOST_SPEED, 1e-3, "%s: at the boost speed" % mode)
		host.queue_free()
		await wait_frames(2)
		assert_false(is_instance_valid(container), "%s: the container goes with the host" % mode)
		for e in escorts:
			assert_false(is_instance_valid(e), "%s: and its escorts with it" % mode)


func test_the_same_boss_seed_gives_the_same_escort_seeds() -> void:
	var h = _world("open_space")
	var seeds: Array = []
	for k in 2:
		var host := _host(h.root, {HANGAR: {door_seconds = 0.1}}, Vector2(-400.0 + 800.0 * k, 0.0))
		var r := _rig(host, 20, null, 99)
		r.surge(HANGAR, 3)
		_run(r, 0.2)
		seeds.append(r.escorts().map(func(e: Node) -> int: return int(e.get_node("Brain").get(&"rng_seed"))))
	assert_eq(seeds[0].size(), 3)
	assert_eq(seeds[0], seeds[1], "two bosses with one rng seed launch identically seeded escorts")


# ── Row 7: mode ─────────────────────────────────────────────────────────────────────────────────

func test_assault_launches_its_own_payload_and_honours_the_launch_limit() -> void:
	for mode in MODES:
		var h = _world(mode)
		var host := _host(h.root, {HANGAR: {door_seconds = 0.1, assault_launch_limit = 1}}, HOST_AT_ASSAULT if h.is_assault else HOST_AT_OPEN)
		var r := _rig(host)
		r.surge(HANGAR, 1)
		r.surge(HANGAR, 1)
		_run(r, 0.5)
		var want := RAZOR if h.is_assault else SWARM
		for e: Node in r.escorts():
			assert_eq(e.scene_file_path, want.resource_path, "%s: the mode's payload" % mode)
		assert_eq(r.launches(HANGAR), 1 if h.is_assault else 2, "%s: Assault stops at assault_launch_limit; Open Space ignores it" % mode)


# ── Row 8: inactive ─────────────────────────────────────────────────────────────────────────────

func test_inactive_freezes_the_periodic_clock() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {first_delay = 1.0, door_seconds = 0.5, period = NEVER}})
	var r := _rig(host)
	var clock: Array[int] = [0]
	var log := _launch_log(r, clock)
	var i := 0
	for k in _ticks(0.5):
		clock[0] = i
		r.tick(DT, true)
		i += 1
	for k in _ticks(2.0):
		clock[0] = i
		r.tick(DT, false)
		i += 1
	assert_eq(log.size(), 0, "no launch while inactive")
	for k in _ticks(1.5):
		clock[0] = i
		r.tick(DT, true)
		i += 1
	assert_eq(log.size(), 1)
	if log.size() == 1:
		assert_almost_eq(float(log[0][2] + 1) * DT, 3.5, DT * 0.5, "the 2 s inactive did not count: 1.5 s of active time + 2 s")


func test_inactive_closes_open_doors_and_holds_a_launch_that_was_opening() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {door_seconds = 0.5, open_hold_seconds = 1.0}})
	var r := _rig(host)
	_light(host, "Hangar").set_state(StateLight.State.ARMED)
	r.surge(HANGAR, 1)
	_run(r, 0.6)
	assert_eq(r.door(HANGAR), BossReinforcements.Door.OPEN, "precondition: launched, doors held open")
	r.tick(DT, false)
	assert_false(r.door_open(HANGAR), "inactive closes an open door")
	assert_false(_part(host, "Hangar").is_vulnerable(), "and locks the part")
	assert_eq(_light(host, "Hangar").get_state(), StateLight.State.ARMED, "and restores the light")

	r.surge(HANGAR, 1)
	_run(r, 0.2)
	assert_eq(r.door(HANGAR), BossReinforcements.Door.OPENING, "precondition: opening")
	r.tick(DT, false)
	assert_false(r.door_open(HANGAR), "inactive closes OPENING doors")
	assert_eq(r.pending(HANGAR), 1, "and holds the launch")
	_run(r, 1.0, false)
	assert_eq(r.launches(HANGAR), 1, "nothing launches while inactive")
	_run(r, 0.6)
	assert_eq(r.launches(HANGAR), 2, "the held launch comes out once active again")


# ── Row 9: surge ────────────────────────────────────────────────────────────────────────────────

func test_surge_queues_count_and_a_dead_bay_ignores_it() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}})
	var r := _rig(host)
	r.surge(HANGAR, 3)
	assert_eq(r.pending(HANGAR), 1)
	_run(r, 0.2)
	assert_eq(r.live_count(), 3, "a surge of 3 puts out 3")
	_part(host, "Hangar").destroy()
	r.surge(HANGAR, 3)
	assert_eq(r.pending(HANGAR), 0, "a dead bay ignores a surge")
	_run(r, 0.5)
	assert_eq(r.launches(HANGAR), 1)


# ── Row 10: ScoreTracker ────────────────────────────────────────────────────────────────────────

func test_score_tracker_pays_an_escort_kill_and_nothing_else() -> void:
	var h = _world("assault")
	var tracker := ScoreTracker.new()
	add_child_autofree(tracker)
	tracker.start_tracking()
	tracker.set_process(false)  # an undecayed-combo assertion (test_score_tracker_escape_penalty.gd)
	tracker.set("_combo", 2.0)
	var step: float = tracker.score_config.combo_step

	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}}, HOST_AT_ASSAULT)
	var r := _rig(host)
	r.surge(HANGAR, 3)
	_run(r, 0.2)
	var escorts := r.escorts()
	assert_eq(escorts.size(), 3, "precondition")
	var value: int = (escorts[0] as BaseEnemy).score_value
	assert_gt(value, 0, "precondition: the payload is worth something")

	(escorts[0] as BaseEnemy).health.set_health(0)
	assert_eq(tracker.get_total_score(), int(floor(value * 2.0)), "a kill pays score_value x combo")
	assert_almost_eq(float(tracker.get("_combo")), 2.0 + step, 1e-6, "and steps the combo")
	assert_true((tracker.get("_wave_state") as Dictionary).is_empty(), "no wave tally")

	escorts[1].queue_free()
	await wait_frames(2)
	assert_almost_eq(float(tracker.get("_combo")), 2.0 + step, 1e-6, "freeing an unkilled escort costs no combo")

	host.set(&"dying", true)
	(escorts[2] as BaseEnemy).health.set_health(0)
	assert_eq(tracker.get_total_score(), int(floor(value * 2.0)), "a kill after the boss is dying pays nothing")
	assert_eq(tracker.get_breakdown()["wave_clear"], 0, "the wave-clear bonus is never touched")


# ── Row 11: a real ENEMIES_CLEARED section ──────────────────────────────────────────────────────

func test_an_enemies_cleared_section_waits_on_the_host_only() -> void:
	var h = _world("open_space")
	var container := Node2D.new()
	h.root.add_child(container)
	var wave_manager := WaveManager.new()
	wave_manager.enemy_container = container
	add_child_autofree(wave_manager)
	var director := LevelDirector.new()
	director.wave_manager = wave_manager
	add_child_autofree(director)
	var started: Array = []
	director.section_started.connect(func(index: int, _n: StringName) -> void: started.append(index))
	var gated := LevelSection.new()
	gated.section_name = &"gated"
	gated.end_condition = LevelSection.EndCondition.ENEMIES_CLEARED
	gated.enemies_cleared_timeout = 30.0
	director.add_section(gated)
	var after := LevelSection.new()
	after.section_name = &"after"
	after.end_condition = LevelSection.EndCondition.DURATION
	after.duration = 999.0
	director.add_section(after)

	var host := _host(container, {HANGAR: {door_seconds = 0.1}})
	var r := _rig(host)
	r.surge(HANGAR, 3)
	_run(r, 0.2)
	var escort_box := EscortContainer.of(host)
	assert_eq(r.live_count(), 3, "precondition: host + 3 escorts")
	assert_eq(container.get_child_count(), 2, "the section sees the host and one escort container")

	director.start()
	wave_manager.waves_complete.emit()
	await wait_frames(10)
	assert_eq(started.size(), 1, "the section waits while the host lives")

	host.queue_free()
	await wait_until(func() -> bool: return started.size() == 2, 3.0)
	assert_eq(started.size(), 2, "freeing the host frees the escort container and the section advances")
	assert_false(is_instance_valid(escort_box), "the escort container went with the host")


# ── Row 12: no orphan signal ────────────────────────────────────────────────────────────────────

func test_a_bay_launch_never_emits_the_orphan_signal() -> void:
	var h = _world("assault")
	var orphans: Array = []
	var escorts: Array = []
	var on_orphan := func(e: Node) -> void: orphans.append(e)
	var on_escort := func(e: Node, b: Node) -> void: escorts.append([e, b])
	EventBus.enemy_spawned_orphan.connect(on_orphan)
	EventBus.boss_escort_spawned.connect(on_escort)
	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}, SECTOR: {door_seconds = 0.1}}, HOST_AT_ASSAULT)
	var r := _rig(host)
	r.surge(HANGAR, 2)
	_part(host, "WatchA").destroy()
	_run(r, 0.5)
	EventBus.enemy_spawned_orphan.disconnect(on_orphan)
	EventBus.boss_escort_spawned.disconnect(on_escort)
	assert_eq(r.live_count(), 4, "precondition: both bays launched")
	assert_eq(orphans.size(), 0, "no enemy_spawned_orphan")
	assert_eq(escorts.size(), 4, "one boss_escort_spawned per escort")
	for pair in escorts:
		assert_eq(pair[1], host, "with the boss")
		assert_true(r.escorts().has(pair[0]))


# ── Row 13: squads ──────────────────────────────────────────────────────────────────────────────

func test_one_squad_per_payload_scene_for_the_boss_life() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}, SECTOR: {door_seconds = 0.1, count = 1}})
	var r := _rig(host)
	r.surge(HANGAR, 1)
	_run(r, 0.2)
	r.surge(HANGAR, 1)
	_run(r, 0.2)
	_part(host, "WatchA").destroy()
	_run(r, 0.2)
	_part(host, "WatchB").destroy()
	_run(r, 0.2)
	var swarm: Array = r.escorts().filter(func(e: Node) -> bool: return e.scene_file_path == SWARM.resource_path)
	var fighters: Array = r.escorts().filter(func(e: Node) -> bool: return e.scene_file_path == FIGHTER.resource_path)
	assert_eq(swarm.size(), 2, "precondition: two swarm launches")
	assert_eq(fighters.size(), 2, "precondition: two fighter launches")
	assert_not_null(swarm[0].get(&"squad"))
	assert_eq(swarm[0].get(&"squad"), swarm[1].get(&"squad"), "two launches of one payload share one SquadController")
	assert_eq(fighters[0].get(&"squad"), fighters[1].get(&"squad"), "the second payload's launches share theirs")
	assert_ne(swarm[0].get(&"squad"), fighters[0].get(&"squad"), "a second payload scene gets its own")


# ── Row 14: escort flags ────────────────────────────────────────────────────────────────────────

func test_escort_wave_flags_are_the_configs_own() -> void:
	var h = _world("open_space")
	var host := _host(h.root, {HANGAR: {door_seconds = 0.1}, SECTOR: {door_seconds = 0.1, count = 1}})
	var r := _rig(host)
	r.surge(HANGAR, 1)
	_part(host, "WatchA").destroy()
	_run(r, 0.2)
	assert_eq(r.live_count(), 2, "precondition")
	for e: BaseEnemy in r.escorts():
		var cfg: ShipConfig = e.get(&"config")
		assert_eq(e.counts_toward_wave_clear, cfg.counts_toward_wave_clear, "%s: counts_toward_wave_clear untouched" % e.name)
		assert_eq(e.counts_as_escape, cfg.counts_as_escape, "%s: counts_as_escape untouched" % e.name)
