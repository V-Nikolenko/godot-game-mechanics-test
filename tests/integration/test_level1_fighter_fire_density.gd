## Intent (Ph3 t16, docs/plans/cmulwkarm00cpqj2xfwq3ue8h/3-plan.md, Revision 2; t17,
## docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md): level 1's deep_space, planet_approach and cloud_descent
## must not become noisier than they were on rails. Their fighters and Gatling pair
## fight off rails since t16 (cloud_descent: t17), so their fire density is a property of the AI's behaviour, not of a
## timer, and this file MEASURES it: the section's real waves through a real `WaveManager`, under a
## real `ArenaCamera` (corridor and world rect), against a stationary, hurtbox-less player stub at the
## lower centre of the view — the `test_level1_drone_exit.gd` shape.
##
## ── Why measured, not computed (the owner's option A, 2026-10-06) ──────────────────────────────
##
## The epic's analytic shots/s figure (every attack-capable ship firing at its burst ceiling for its
## whole life) computed 1.86x / 1.90x the legacy value, while a real run fired about a fifth of the
## legacy shots: in Assault each fighter fires about one burst before its budget sends it home
## (docs/plans/cmulwkarm00cpqj2xfwq3ue8h/5-escalation.md). The owner chose to keep the two analytic
## COUNT gates (`test_level1_fighter_spawns.gd`) and gate shots/s on this measurement instead. The
## analytic figure is still printed there.
##
## ── What is measured ─────────────────────────────────────────────────────────────────────────
##
## - Population: only the fighter and Gatling entries, the same population the frozen
##   `_LEGACY_PEAK_SHOTS_PER_S` counts. Every wave is kept, in its `raw_waves` order, with the other
##   entries filtered out — `WaveManager` triggers strictly in list order, so dropping an emptied wave
##   would move a later-listed wave (deep_space's "2.0 s" V5 really triggers at 3.5 s, behind the
##   3.5 s gunship wave). `test_waves_trigger_on_the_shipped_schedule` pins that.
## - A shot is an `EnemyBullet` entering the enemy container: `BulletPool.acquire()` reparents every
##   fired round there and a recycled one goes back under its pool, so each fired round counts once.
## - The gate: the most shots in any 2 s window, / 2, must be <= 1.25x the frozen constant (read from
##   the pin's script, never copied). 2 s is the window that reproduced the frozen constants on the old
##   rails (31.0 / 35.0 measured against 31.25 / 33.33).
## - One seeded scenario: every brain's `rng_seed` is set from its spawn index before its `_ready()`.
##   Physics and idle-frame ordering can still shift a spawn by a frame between runs; the margin is
##   about 3x.
##
## ── Time ─────────────────────────────────────────────────────────────────────────────────────
##
## Game time is summed physics delta, never wall clock. The run is sped up 4x with the physics step
## kept at 1/60 game-second: `Engine.time_scale`, `physics_ticks_per_second` and
## `max_physics_steps_per_frame` are scaled together, and the captured originals are restored at the
## end of the run AND in `after_each`, so a run that breaks off cannot leak a fast clock into the
## rest of the suite.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")
## The pin owns the frozen legacy constants; this file only reads them, through `_frozen_shots_per_s()`.
const _PIN_PATH := "res://tests/integration/test_level1_fighter_spawns.gd"

const _FIGHTER_CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")
const _GATLING_CONFIG: GatlingInterceptorConfig = \
	preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")

const _WINDOW := 2.0
const _RATIO := 1.25
const _SPEEDUP := 4
## Non-zero: an `rng_seed` of 0 means "randomize".
const _SEED_BASE := 1601
## Run cap past the last spawn's worst-case lifetime: room for the exits to be observed.
const _TAIL := 5.0
## How late a wave may trigger against the shipped schedule (idle-frame granularity at 4x).
const _TRIGGER_TOLERANCE := 0.1

var _container: Node2D
var _wave_manager: WaveManager
var _t: float = 0.0
var _recording: bool = false
var _spawned: int = 0
var _waves_done: bool = false
## Game time of each counted shot, and how many came from each kind ("fighter" / "gatling").
var _shot_times: Array[float] = []
var _shots_by_kind: Dictionary = {}
## Round scene path -> kind, filled from each ship's own `BulletPool`s as it enters.
var _round_kind: Dictionary = {}
## Game time each wave index actually triggered at.
var _triggered_at: Dictionary = {}
## One `{ "kind", "phase", "disengage", "path_mover" }` per ship that left the tree.
var _exits: Array[Dictionary] = []

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_each() -> void:
	_t = 0.0
	_recording = true
	_spawned = 0
	_waves_done = false
	_shot_times = []
	_shots_by_kind = {"fighter": 0, "gatling": 0}
	_round_kind = {}
	_triggered_at = {}
	_exits = []


func after_each() -> void:
	_recording = false
	_restore_clock()


func _scale_clock() -> void:
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


## The pin's frozen `_LEGACY_PEAK_SHOTS_PER_S[name]`. Loaded at the call, never held in a `const`: a
## preloaded GutTest script kept alive by this one holds GUT open at process exit (a leak).
func _frozen_shots_per_s(name: StringName) -> float:
	var pin: GDScript = load(_PIN_PATH)
	return float(pin.get_script_constant_map()["_LEGACY_PEAK_SHOTS_PER_S"][name])


func _section(name: StringName) -> LevelSection:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	for s in d._build_sections():
		var section: LevelSection = s
		if section.section_name == name:
			return section
	return null


func _is_shooter(entry: SpawnEntryResource) -> bool:
	return entry.ship_scene != null and (entry.ship_scene.resource_path == WaveBuilder.FIGHTER
		or entry.ship_scene.resource_path == WaveBuilder.GATLING_INTERCEPTOR)


## Every wave of `section`, in order, holding only its fighter / Gatling entries. New resources: the
## section's own are never mutated.
func _shooter_waves(section: LevelSection) -> Array[WaveResource]:
	var out: Array[WaveResource] = []
	for w in section.waves:
		var wave: WaveResource = w
		var copy := WaveResource.new()
		copy.trigger_time = wave.trigger_time
		var entries: Array[SpawnEntryResource] = []
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if _is_shooter(entry):
				entries.append(entry)
		copy.entries = entries
		out.append(copy)
	return out


func _exit_distance() -> float:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := cam.projectile_world_rect()
	return minf(rect.size.x, rect.size.y) / 2.0


## Seeds each ship's brain before its `_ready()`, and records its rounds' scenes and its exit.
## `child_entered_tree` fires on `add_child`, before the subtree's `_ready()`.
func _on_container_child_entered(node: Node) -> void:
	if not _recording:
		return
	if node is EnemyBullet:
		_shot_times.append(_t)
		var kind: String = _round_kind.get(node.scene_file_path, "?")
		_shots_by_kind[kind] = int(_shots_by_kind.get(kind, 0)) + 1
		return
	if not node is BaseEnemy:
		return
	var brain := node.get_node_or_null("Brain") as EnemyBrain
	if brain != null:
		brain.rng_seed = _SEED_BASE + _spawned
	_spawned += 1
	var kind := "gatling" if node is GatlingInterceptor else "fighter"
	for child in node.get_children():
		if child is BulletPool:
			_round_kind[(child as BulletPool).bullet_scene.resource_path] = kind
	node.tree_exiting.connect(_on_ship_exiting.bind(node, kind))


func _on_ship_exiting(ship: Node, kind: String) -> void:
	if not _recording:
		return
	var has_path_mover := false
	for child in ship.get_children():
		if child is EnemyPathMover:
			has_path_mover = true
	var brain := ship.get_node_or_null("Brain")
	var phase := -1
	var disengage := false
	if brain is FighterBrain:
		phase = (brain as FighterBrain).phase
		disengage = phase == FighterBrain.Phase.DISENGAGE
	elif brain is GatlingInterceptorBrain:
		phase = (brain as GatlingInterceptorBrain).phase
		disengage = phase == GatlingInterceptorBrain.Phase.DISENGAGE
	_exits.append({"kind": kind, "phase": phase, "disengage": disengage, "path_mover": has_path_mover})


func _on_wave_triggered(wave_index: int) -> void:
	if _recording:
		_triggered_at[wave_index] = _t


func _ships_alive() -> int:
	var n := 0
	for child in _container.get_children():
		if child is BaseEnemy and not child.is_queued_for_deletion():
			n += 1
	return n


## Speeds the clock up, lets a few idle frames (main-loop iterations, not physics steps, which a
## catch-up burst runs several of inside one iteration) absorb the hitch of building the world and
## rescaling the clock (otherwise the first idle frame — and so wave 0 — lands after a burst of
## catch-up physics steps), then loads `waves` and starts game time at 0 with the `WaveManager`.
func _start(waves: Array[WaveResource]) -> void:
	_scale_clock()
	for i in 3:
		await get_tree().process_frame
	_wave_manager.load_section(waves)
	_t = 0.0


## Runs `section`'s fighter / Gatling waves to completion and returns the expected ship count.
func _run(section: LevelSection) -> int:
	var intervals := DroneConcurrency.shooter_squad_intervals(section, DroneConcurrency.ai_shooter_kinds(
		_FIGHTER_CONFIG, _GATLING_CONFIG, _exit_distance()))
	var expected := intervals.size()
	var cap := 0.0
	for iv: Dictionary in intervals:
		cap = maxf(cap, float(iv["end"]))
	cap += _TAIL

	var harness: RefCounted = HARNESS.assault()
	add_child_autofree(harness.root)
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	harness.player.global_position = cam.global_position + Vector2(0.0, 250.0)

	_container = Node2D.new()
	_container.name = "EnemyContainer"
	harness.root.add_child(_container)
	_container.child_entered_tree.connect(_on_container_child_entered)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	harness.root.add_child(_wave_manager)
	_wave_manager.wave_triggered.connect(_on_wave_triggered)
	_wave_manager.waves_complete.connect(func() -> void: _waves_done = true)

	await _start(_shooter_waves(section))
	while _t < cap:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
		if _waves_done and _spawned == expected and _ships_alive() == 0:
			break
	_restore_clock()
	_recording = false
	return expected


func _assert_measured_gate(name: StringName) -> void:
	var section := _section(name)
	assert_not_null(section, "sanity: level 1 has %s" % name)
	if section == null:
		return
	var expected: int = await _run(section)
	var measured := DroneConcurrency.peak_window_rate(_shot_times, _WINDOW)
	var frozen := _frozen_shots_per_s(name)
	gut.p("%s measured: %d ships, %d shots (fighter %d, Gatling %d), peak %.2f shots/s over %.0f s "
		% [name, _spawned, _shot_times.size(), _shots_by_kind["fighter"], _shots_by_kind["gatling"],
			measured, _WINDOW]
		+ "(limit %.2f = %.2fx frozen %.2f); run %.1f s of game time"
		% [_RATIO * frozen, _RATIO, frozen, _t])

	assert_eq(_spawned, expected, "%s: every fighter / Gatling must have spawned" % name)
	assert_gt(_shot_times.size(), 0, "%s: no shot was counted — a silent build must not pass" % name)
	assert_eq(int(_shots_by_kind.get("?", 0)), 0, "%s: a counted round came from no known pool" % name)
	assert_lte(measured, _RATIO * frozen,
		"%s: measured peak shots/s over %.2fx the frozen legacy value" % [name, _RATIO])

	assert_eq(_ships_alive(), 0, "%s: %d ship(s) still in the container after %.1f s" % [name, _ships_alive(), _t])
	assert_eq(_exits.size(), expected, "%s: every ship's exit must have been recorded" % name)
	for i in _exits.size():
		var exit: Dictionary = _exits[i]
		assert_false(exit["path_mover"], "%s: %s %d left on a rail (EnemyPathMover)" % [name, exit["kind"], i])
		assert_true(exit["disengage"], "%s: %s %d left in phase %d, not DISENGAGE"
			% [name, exit["kind"], i, int(exit["phase"])])


func test_deep_space_measured_shots_per_s_within_1_25x() -> void:
	await _assert_measured_gate(&"deep_space")
	assert_gt(int(_shots_by_kind["fighter"]), 0, "deep_space: fighter rounds must be counted")
	assert_gt(int(_shots_by_kind["gatling"]), 0, "deep_space: Gatling Stream rounds must be counted")


func test_planet_approach_measured_shots_per_s_within_1_25x() -> void:
	await _assert_measured_gate(&"planet_approach")


## t17 (docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md): cloud_descent's fighters are off rails too, so
## its gate is the same measurement against its own frozen constant (15.0 shots/s).
func test_cloud_descent_measured_shots_per_s_within_1_25x() -> void:
	await _assert_measured_gate(&"cloud_descent")


## The measured run follows the shipped schedule: each wave triggers at its own trigger time, or at the previous wave's (list order — `WaveManager` never triggers a later-listed wave first), within
## `_TRIGGER_TOLERANCE`. Short: only deep_space's first 10 s of waves are driven.
func test_waves_trigger_on_the_shipped_schedule() -> void:
	var section := _section(&"deep_space")
	assert_not_null(section, "sanity: level 1 has deep_space")
	if section == null:
		return
	var waves := _shooter_waves(section)
	var harness: RefCounted = HARNESS.assault()
	add_child_autofree(harness.root)
	(harness.root.get_node("ArenaCamera") as Camera2D).make_current()
	_container = Node2D.new()
	_container.name = "EnemyContainer"
	harness.root.add_child(_container)
	_container.child_entered_tree.connect(_on_container_child_entered)
	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	harness.root.add_child(_wave_manager)
	_wave_manager.wave_triggered.connect(_on_wave_triggered)

	await _start(waves)
	const RUN := 10.0
	while _t < RUN:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
	_restore_clock()
	_recording = false
	_wave_manager.set_process(false)

	var expected_at := 0.0
	var checked := 0
	for i in waves.size():
		expected_at = maxf(expected_at, waves[i].trigger_time)
		# Leave the last second's waves out: their spawn delays may still be running at RUN.
		if expected_at > RUN - 1.0:
			break
		checked += 1
		assert_true(_triggered_at.has(i), "wave %d (%.1f s) never triggered" % [i, waves[i].trigger_time])
		assert_almost_eq(float(_triggered_at.get(i, -1.0)), expected_at, _TRIGGER_TOLERANCE,
			"wave %d (listed at %.1f s) must trigger at %.2f s" % [i, waves[i].trigger_time, expected_at])
	assert_gt(checked, 3, "sanity: several waves were checked, including the out-of-order 2.0 s V5")
	# The quirk the run must reproduce: the "2.0 s" V5 is listed after the 3.5 s wave.
	var v5_index := -1
	for i in waves.size():
		if is_equal_approx(waves[i].trigger_time, 2.0):
			v5_index = i
	assert_ne(v5_index, -1, "sanity: deep_space has a 2.0 s wave")
	if v5_index != -1:
		assert_almost_eq(float(_triggered_at.get(v5_index, -1.0)), 3.5, _TRIGGER_TOLERANCE,
			"deep_space's 2.0 s V5 triggers behind the 3.5 s wave in the shipped game")
	# Let every delayed spawn of the triggered waves fire before teardown: an unfired
	# SceneTreeTimer is reported as a leak at process exit.
	var guard := 0.0
	while guard < 1.5:
		await get_tree().physics_frame
		guard += get_physics_process_delta_time()


## Boundary for the gate's arithmetic: 80 shots inside 2 s is 40.0 shots/s, over deep_space's
## 1.25 x 31.25 = 39.06 limit; the same 80 shots spread over 4 s is 20.0 and passes.
func test_peak_window_rate_rejects_a_dense_burst() -> void:
	var limit := _RATIO * _frozen_shots_per_s(&"deep_space")
	var dense: Array[float] = []
	var spread: Array[float] = []
	for i in 80:
		dense.append(10.0 + i * 0.025)
		spread.append(10.0 + i * 0.05)
	var dense_rate := DroneConcurrency.peak_window_rate(dense, _WINDOW)
	var spread_rate := DroneConcurrency.peak_window_rate(spread, _WINDOW)
	assert_almost_eq(dense_rate, 40.0, 0.001)
	assert_gt(dense_rate, limit, "80 shots in 2 s must be rejected")
	assert_almost_eq(spread_rate, 20.0, 0.001)
	assert_lte(spread_rate, limit, "80 shots over 4 s must pass")


func test_peak_window_rate_of_no_shots_is_zero() -> void:
	var none: Array[float] = []
	assert_eq(DroneConcurrency.peak_window_rate(none, _WINDOW), 0.0)
