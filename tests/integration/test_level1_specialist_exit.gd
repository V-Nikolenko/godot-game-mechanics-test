## Intent (Ph4 t22, epic docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.9.3; task plan
## docs/plans/cmuyk2qqp009loa2xb1k3py8o/3-plan.md §6): cloud_descent is an ENEMIES_CLEARED section, so
## `LevelDirector._wait_enemies_cleared` starts an `enemies_cleared_timeout` clock the moment its LAST wave triggers
## (`waves_complete`, 76.0 s) and polls `container.get_child_count()` until it reads 0. Since t22 its 9 snipers and 6
## rams fly off rails: nothing culls one at the screen edge, so each must fight, let its `EngagementBudget` expire
## (deferred at most to the end of a shot or a charge) and fly out of the world rect by itself in DISENGAGE — before
## that clock runs out.
##
## `test_engagement_deadline.gd` proves this on paper, per entry. This file runs it: the WHOLE section from 0.0 s
## (epic review N2 — a replay from 62.0 s would spawn 2 snipers and 1 ram, not all 15), through a real `WaveManager`,
## under a real `ArenaCamera` (corridor and world rect), against a stationary, hurtbox-less player stub at the lower
## centre of the view — nothing can end early by hitting it. `test_level1_fighter_exit.gd` covers the late mixed set
## (from 66.0 s, the 73.2 s ram included).
##
## Population: only the sniper and ram entries. Every wave is kept, in its `raw_waves` order, with the other entries
## filtered out — `WaveManager` triggers strictly in list order, so dropping an emptied wave could move a later one
## (the `test_level1_fighter_fire_density.gd` shape). The emptied 76.0 s wave still triggers, so `waves_complete`
## fires on the shipped tick.
##
## "Left in time" is not enough on its own — the old rails were also gone in time, culled by `EnemyPathMover`. So
## every sniper and ram must also leave in DISENGAGE with no `EnemyPathMover`, which only the rails-off AI can do;
## a ram given `.move()` again carries one (`test_a_rail_driven_ram_wave_is_rejected`).
##
## ── Time ─────────────────────────────────────────────────────────────────────────────────────────────────────────
##
## 86 s of game time, sped up `_SPEEDUP`x with the physics step kept at 1/60 game-second (the fire-density / bomber
## pattern): `Engine.time_scale`, `physics_ticks_per_second` and `max_physics_steps_per_frame` scaled together, the
## originals restored at the end of the run AND in `after_each`, so a run that breaks off cannot leak a fast clock
## into the rest of the suite. Three idle frames pass between scaling and `load_section()`, or wave 0 triggers after a
## catch-up burst (tests/README.md). Game time is summed physics delta, never wall clock. `waves_complete` is judged on
## `WaveManager`'s OWN clock (summed idle delta), with a tolerance of the largest idle delta seen during the run plus
## one tick — at 8x one idle frame can exceed the 1x file's fixed 0.1 s. Every brain is seeded from its spawn index
## before its `_ready()`, so this is one seeded scenario.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

const _SPEEDUP := 8
## Non-zero: an `rng_seed` of 0 means "randomize".
const _SEED_BASE := 2201
## Longer than the largest `delay()` of a replayed specialist line (1.5 s), so every WaveManager spawn timer has fired
## before a test returns — an unfired SceneTreeTimer is reported as a leak at process exit.
const _MIN_RUN_SECONDS := 2.0
const _TICK := 1.0 / 60.0

var _container: Node2D
var _wave_manager: WaveManager
var _t: float = 0.0
var _recording: bool = false
var _spawned: int = 0
var _snipers_spawned: int = 0
var _rams_spawned: int = 0
## Game time (summed physics delta) `waves_complete` fired at, or -1 before it does.
var _complete_at: float = -1.0
## `WaveManager`'s OWN clock when it fired.
var _complete_wm_clock: float = -1.0
## The largest idle delta seen while the run was recorded (the WM clock's step).
var _max_idle_delta: float = 0.0
## One `{ "kind", "phase", "disengage", "path_mover", "at" }` per sniper or ram that left the tree. Held on the test
## object, never on a node, so a late callback during teardown writes into live state.
var _exits: Array[Dictionary] = []

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_t = 0.0
	_recording = true
	_spawned = 0
	_snipers_spawned = 0
	_rams_spawned = 0
	_complete_at = -1.0
	_complete_wm_clock = -1.0
	_max_idle_delta = 0.0
	_exits = []


func after_each() -> void:
	_recording = false
	if get_tree().process_frame.is_connected(_on_process_frame):
		get_tree().process_frame.disconnect(_on_process_frame)
	_restore_clock()


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


func _cloud_descent() -> LevelSection:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	for s in d._build_sections():
		var section: LevelSection = s
		if section.section_name == &"cloud_descent":
			return section
	return null


func _is_specialist(entry: SpawnEntryResource) -> bool:
	return entry.ship_scene != null and (entry.ship_scene.resource_path == WaveBuilder.SNIPER
		or entry.ship_scene.resource_path == WaveBuilder.RAM)


## Every wave of the section, in list order and on its own trigger time, with only its sniper and ram entries. New
## `WaveResource`s: the section's own are never mutated.
func _specialist_waves(section: LevelSection) -> Array[WaveResource]:
	var out: Array[WaveResource] = []
	for w in section.waves:
		var wave: WaveResource = w
		var copy := WaveResource.new()
		copy.trigger_time = wave.trigger_time
		var entries: Array[SpawnEntryResource] = []
		for e in wave.entries:
			if _is_specialist(e):
				entries.append(e)
		copy.entries = entries
		out.append(copy)
	return out


## `[snipers, rams]` the waves spawn. No specialist line uses a formation (the t1 pin asserts it).
func _expected_counts(waves: Array[WaveResource]) -> Array[int]:
	var snipers := 0
	var rams := 0
	for wave in waves:
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene.resource_path == WaveBuilder.SNIPER:
				snipers += 1
			elif entry.ship_scene.resource_path == WaveBuilder.RAM:
				rams += 1
	return [snipers, rams]


func _build_world() -> void:
	var harness: RefCounted = HARNESS.assault()
	add_child_autofree(harness.root)
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	# Lower centre of the view, stationary. No hurtbox: nothing can detonate on it or shoot it down.
	harness.player.global_position = cam.global_position + Vector2(0.0, 250.0)

	_container = Node2D.new()
	_container.name = "EnemyContainer"
	harness.root.add_child(_container)
	_container.child_entered_tree.connect(_on_container_child_entered)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	harness.root.add_child(_wave_manager)
	_wave_manager.waves_complete.connect(_on_waves_complete)


## Scales the clock, lets three idle frames pass (no catch-up burst lands on wave 0), then loads the waves.
func _start(waves: Array[WaveResource]) -> void:
	_scale_clock()
	for i in 3:
		await get_tree().process_frame
	get_tree().process_frame.connect(_on_process_frame)
	_wave_manager.load_section(waves)
	_t = 0.0


func _on_process_frame() -> void:
	if _recording:
		_max_idle_delta = maxf(_max_idle_delta, get_process_delta_time())


## Seeds each ship's brain before its `_ready()` (`child_entered_tree` fires on `add_child`, before the subtree is
## ready) and records every sniper's and ram's exit.
func _on_container_child_entered(node: Node) -> void:
	if not _recording or not node is BaseEnemy:
		return
	var brain := node.get_node_or_null("Brain") as EnemyBrain
	if brain != null:
		brain.rng_seed = _SEED_BASE + _spawned
	_spawned += 1
	if node is Sniper:
		_snipers_spawned += 1
		node.tree_exiting.connect(_on_specialist_exiting.bind(node, "sniper"))
	elif node is RamCorvette:
		_rams_spawned += 1
		node.tree_exiting.connect(_on_specialist_exiting.bind(node, "ram"))


func _on_specialist_exiting(ship: Node, kind: String) -> void:
	if not _recording:
		return
	var has_path_mover := false
	for child in ship.get_children():
		if child is EnemyPathMover:
			has_path_mover = true
	var phase := -1
	var disengage := false
	if kind == "sniper":
		var brain := ship.get_node_or_null("Brain") as SniperBrain
		phase = brain.phase if brain else -1
		disengage = phase == SniperBrain.Phase.DISENGAGE
	else:
		var brain := ship.get_node_or_null("Brain") as RamCorvetteBrain
		phase = brain.phase if brain else -1
		disengage = phase == RamCorvetteBrain.Phase.DISENGAGE
	_exits.append({"kind": kind, "phase": phase, "disengage": disengage, "path_mover": has_path_mover, "at": _t})


func _on_waves_complete() -> void:
	if _recording:
		_complete_at = _t
		_complete_wm_clock = _wave_manager._time_elapsed


## Advances physics frames until `stop` returns true (checked only after `_MIN_RUN_SECONDS`) or `_t` reaches `until`.
func _advance(until: float, stop: Callable) -> void:
	while _t < until:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
		if _t >= _MIN_RUN_SECONDS and stop.call():
			break


func test_cloud_descents_snipers_and_rams_leave_under_ai_before_the_timeout() -> void:
	var section := _cloud_descent()
	assert_not_null(section, "sanity: level 1 has a cloud_descent section")
	if section == null:
		return
	assert_eq(section.end_condition, LevelSection.EndCondition.ENEMIES_CLEARED, "sanity")
	var waves := _specialist_waves(section)
	var expected := _expected_counts(waves)
	assert_eq(expected, [9, 6] as Array[int], "sanity: cloud_descent spawns 9 snipers and 6 rams")
	var timeout := section.enemies_cleared_timeout
	var last_trigger := waves[waves.size() - 1].trigger_time
	assert_almost_eq(last_trigger, 76.0, 0.001, "sanity: the last (emptied) wave is the shipped 76.0 s one")

	_build_world()
	await _start(waves)
	# The window is measured from `waves_complete` on the physics clock: the hard cap only guards a run in which it
	# never fires.
	await _advance(last_trigger + timeout + 1.0, func() -> bool:
		if _complete_at < 0.0:
			return false
		return _t - _complete_at >= timeout \
			or (_spawned == expected[0] + expected[1] and _container.get_child_count() == 0))
	_recording = false
	_restore_clock()

	var tolerance := _max_idle_delta + _TICK
	assert_gte(_complete_wm_clock, last_trigger, "waves_complete must not fire before the last wave triggers")
	assert_lt(_complete_wm_clock, last_trigger + tolerance,
		"waves_complete fires on the tick the last (76.0 s) wave triggers (tolerance %.3f s)" % tolerance)
	assert_gt(_complete_at, 0.0, "sanity: waves_complete fired")
	assert_eq(_snipers_spawned, expected[0], "every sniper of the section must have spawned")
	assert_eq(_rams_spawned, expected[1], "every ram of the section must have spawned")
	var cleared_after := _t - _complete_at
	assert_eq(_container.get_child_count(), 0, "%d node(s) still in the container %.2f s after waves_complete (timeout %.1f s)"
		% [_container.get_child_count(), cleared_after, timeout])
	assert_lt(cleared_after, timeout, "the container must empty BEFORE enemies_cleared_timeout")

	assert_eq(_exits.size(), expected[0] + expected[1], "every sniper's and ram's exit must have been recorded")
	var last_exit := {"sniper": -INF, "ram": -INF}
	for i in _exits.size():
		var exit: Dictionary = _exits[i]
		last_exit[exit["kind"]] = maxf(float(last_exit[exit["kind"]]), float(exit["at"]))
		assert_false(exit["path_mover"], "%s %d left on a rail (EnemyPathMover), not under AI" % [exit["kind"], i])
		assert_true(exit["disengage"], "%s %d left in phase %d, not DISENGAGE" % [exit["kind"], i, int(exit["phase"])])
	gut.p(("cloud_descent snipers and rams from 0.0 s: %d snipers, %d rams; container empty %.2f s after waves_complete, "
		+ "margin %.2f s of the %.1f s timeout; last sniper left %.2f s and last ram %.2f s after it (largest idle delta %.3f s)")
		% [_snipers_spawned, _rams_spawned, cleared_after, timeout - cleared_after, timeout,
			float(last_exit["sniper"]) - _complete_at, float(last_exit["ram"]) - _complete_at, _max_idle_delta])


## Boundary: the 28.0 s ram wave alone, re-timed to 0 with `.move()` put back on its entries (duplicated: the
## section's own resources are never mutated), spawns rams that carry an `EnemyPathMover` — the predicate the main case
## rejects. Runs just past the wave's last spawn (0.4 s) and stops; teardown frees the rest with recording off.
func test_a_rail_driven_ram_wave_is_rejected() -> void:
	var section := _cloud_descent()
	if section == null:
		fail_test("no cloud_descent section")
		return
	var ram_wave: WaveResource = null
	for w in section.waves:
		var wave: WaveResource = w
		if is_equal_approx(wave.trigger_time, 28.0):
			ram_wave = wave
	assert_not_null(ram_wave, "sanity: cloud_descent has its 28.0 s ram wave")
	if ram_wave == null:
		return
	var copy := WaveResource.new()
	copy.trigger_time = 0.0
	var entries: Array[SpawnEntryResource] = []
	for e in ram_wave.entries:
		var entry := (e as SpawnEntryResource).duplicate() as SpawnEntryResource
		entry.movement = StraightMovement.new()
		entries.append(entry)
	copy.entries = entries
	var waves: Array[WaveResource] = [copy]
	_build_world()
	await _start(waves)
	await _advance(_MIN_RUN_SECONDS, func() -> bool: return false)
	_recording = false
	_wave_manager.set_process(false)
	_restore_clock()

	var rams := 0
	for child in _container.get_children():
		if not child is RamCorvette:
			continue
		rams += 1
		var has_path_mover := false
		for c in child.get_children():
			if c is EnemyPathMover:
				has_path_mover = true
		assert_true(has_path_mover, "a .move() ram must carry an EnemyPathMover, which the main case rejects")
	assert_eq(rams, 2, "sanity: both rail rams spawned and are still in the container")
