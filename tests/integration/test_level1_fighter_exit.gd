## Intent (Ph3 t17, epic docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.9.3; task plan
## docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md): cloud_descent is an ENEMIES_CLEARED section, so
## `LevelDirector._wait_enemies_cleared` starts an `enemies_cleared_timeout` clock the moment its LAST
## wave triggers (`waves_complete`, 76.0 s) and polls `container.get_child_count()` until it reads 0.
## Since t17 its fighters fly off rails: nothing culls one at the screen edge, so each must fight, let
## its `EngagementBudget` expire (deferred at most to the end of a running burst) and fly out of the
## world rect by itself in DISENGAGE — before that clock runs out, or the level stalls to its
## forced-free fallback.
##
## `test_engagement_deadline.gd` proves this on paper, per fighter entry. This file runs it: every wave
## of cloud_descent from 66.0 s onward (the 66 s and 72 s fighter waves, the 68 s and 76 s drone waves,
## the 72 s rail ram), through a real `WaveManager`, under a real `ArenaCamera` (corridor and world
## rect), against a stationary player stub with no hurtbox — nothing can end early by hitting it.
## No fighter spawned before 66.0 s can still be alive at 76.0 s: its worst-case life after entry is
## ≈ 12.2 s (engage 6.0 + burst deferral 0.8 + the curved-exit bound 5.37, which the deadline test gates
## on the real scene), and the latest earlier fighters — the 59.0 s wedge — enter by 59.1 s, so are gone
## by ≈ 71.3 s.
##
## The waves are re-timed by −66 s, keeping their list order and spacing, so the run is 20 s of game
## time instead of 86. "Cleared" is what the director checks — the container has no child at all,
## in-flight rounds included (they die with their ship: `BulletPool._exit_tree()`).
##
## "Left in time" is not enough on its own — the old rails were also gone in time, culled by
## `EnemyPathMover`. So every fighter must also leave in DISENGAGE and with no `EnemyPathMover`,
## which only the rails-off AI can do; a fighter given `.move()` again fails here
## (`test_a_rail_driven_fighter_wave_is_rejected`).
##
## Game time is summed physics delta, never wall clock. Every brain is seeded from its spawn index
## before its `_ready()`, so this is one seeded scenario.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

## The first wave this run replays (the 66.0 s fighter pair); see the header for why earlier ones
## cannot matter.
const _FROM := 66.0
## Non-zero: an `rng_seed` of 0 means "randomize".
const _SEED_BASE := 1701
## Longer than the largest `delay()` + formation slot delay in the replayed waves (0.8 s), so every
## WaveManager spawn timer has fired before a test returns — an unfired SceneTreeTimer is reported as
## a leak at process exit.
const _MIN_RUN_SECONDS := 1.0

var _container: Node2D
var _wave_manager: WaveManager
var _t: float = 0.0
var _recording: bool = false
var _spawned: int = 0
var _fighters_spawned: int = 0
## Game time (summed physics delta) `waves_complete` fired at, or -1 before it does.
var _complete_at: float = -1.0
## `WaveManager`'s OWN clock (summed idle delta) when it fired. The two clocks can differ by a
## start-up hitch: the first idle frame's delta includes scene set-up time no physics step covers.
var _complete_wm_clock: float = -1.0
## One `{ "phase", "disengage", "path_mover", "at" }` per fighter that left the tree. Held on the test
## object, never on a node, so a late callback during teardown writes into live state.
var _fighter_exits: Array[Dictionary] = []


func before_each() -> void:
	_t = 0.0
	_recording = true
	_spawned = 0
	_fighters_spawned = 0
	_complete_at = -1.0
	_complete_wm_clock = -1.0
	_fighter_exits = []


func after_each() -> void:
	_recording = false


func _cloud_descent() -> LevelSection:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	for s in d._build_sections():
		var section: LevelSection = s
		if section.section_name == &"cloud_descent":
			return section
	return null


## cloud_descent's waves from `_FROM` on, in list order, re-timed by −`_FROM`. New `WaveResource`s:
## the section's own are never mutated. `rail_fighters` gives every fighter entry a straight rail
## (duplicated entries) for the boundary case.
func _replayed_waves(section: LevelSection, rail_fighters: bool = false) -> Array[WaveResource]:
	var out: Array[WaveResource] = []
	for w in section.waves:
		var wave: WaveResource = w
		if wave.trigger_time < _FROM:
			continue
		var copy := WaveResource.new()
		copy.trigger_time = wave.trigger_time - _FROM
		var entries: Array[SpawnEntryResource] = []
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if rail_fighters and _is_fighter(entry):
				entry = entry.duplicate() as SpawnEntryResource
				entry.movement = StraightMovement.new()
			entries.append(entry)
		copy.entries = entries
		out.append(copy)
	return out


func _is_fighter(entry: SpawnEntryResource) -> bool:
	return entry.ship_scene != null and entry.ship_scene.resource_path == WaveBuilder.FIGHTER


## Ships the replayed waves spawn, formations expanded: `[all, fighters]`.
func _expected_counts(waves: Array[WaveResource]) -> Array[int]:
	var all := 0
	var fighters := 0
	for wave in waves:
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene == null:
				continue
			var n := entry.formation.compute_slots().size() if entry.formation else 1
			all += n
			if _is_fighter(entry):
				fighters += n
	return [all, fighters]


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


## Seeds each ship's brain before its `_ready()` (`child_entered_tree` fires on `add_child`, before
## the subtree is ready) and records every fighter's exit.
func _on_container_child_entered(node: Node) -> void:
	if not _recording or not node is BaseEnemy:
		return
	var brain := node.get_node_or_null("Brain") as EnemyBrain
	if brain != null:
		brain.rng_seed = _SEED_BASE + _spawned
	_spawned += 1
	if node is Fighter:
		_fighters_spawned += 1
		node.tree_exiting.connect(_on_fighter_exiting.bind(node))


func _on_fighter_exiting(fighter: Node) -> void:
	if not _recording:
		return
	var has_path_mover := false
	for child in fighter.get_children():
		if child is EnemyPathMover:
			has_path_mover = true
	var brain := fighter.get_node_or_null("Brain") as FighterBrain
	var phase: int = brain.phase if brain else -1
	_fighter_exits.append({"phase": phase, "disengage": phase == FighterBrain.Phase.DISENGAGE,
		"path_mover": has_path_mover, "at": _t})


func _on_waves_complete() -> void:
	if _recording:
		_complete_at = _t
		_complete_wm_clock = _wave_manager._time_elapsed


## Advances physics frames until `stop` returns true (checked only after `_MIN_RUN_SECONDS`) or
## `_t` reaches `until`.
func _advance(until: float, stop: Callable) -> void:
	while _t < until:
		await get_tree().physics_frame
		_t += get_physics_process_delta_time()
		if _t >= _MIN_RUN_SECONDS and stop.call():
			break


func test_cloud_descents_fighters_leave_under_ai_before_the_timeout() -> void:
	var section := _cloud_descent()
	assert_not_null(section, "sanity: level 1 has a cloud_descent section")
	if section == null:
		return
	assert_eq(section.end_condition, LevelSection.EndCondition.ENEMIES_CLEARED, "sanity")
	var waves := _replayed_waves(section)
	var expected := _expected_counts(waves)
	assert_gt(expected[1], 0, "sanity: the replayed waves spawn fighters")
	var timeout := section.enemies_cleared_timeout
	var last_trigger := waves[waves.size() - 1].trigger_time

	_build_world()
	_wave_manager.load_section(waves)
	# The window is measured from `waves_complete` on the physics clock (task review round 2): the hard cap
	# only guards a run in which it never fires.
	await _advance(last_trigger + timeout + 1.0, func() -> bool:
		if _complete_at < 0.0:
			return false
		return _t - _complete_at >= timeout or (_spawned == expected[0] and _container.get_child_count() == 0))
	_recording = false

	# Judged on WaveManager's own clock: it emits in the same `_process` call that triggers the last
	# wave. Everything measured after it is on one clock (physics), so a start-up offset cannot leak in.
	assert_gte(_complete_wm_clock, last_trigger, "waves_complete must not fire before the last wave triggers")
	assert_lt(_complete_wm_clock, last_trigger + 0.1,
		"waves_complete fires on the tick the last (76.0 s) wave triggers")
	assert_gt(_complete_at, 0.0, "sanity: waves_complete fired")
	assert_eq(_spawned, expected[0], "every ship of the replayed waves must have spawned")
	assert_eq(_fighters_spawned, expected[1], "every fighter of the replayed waves must have spawned")
	var cleared_after := _t - _complete_at
	assert_eq(_container.get_child_count(), 0,
		"%d node(s) still in the container %.2f s after waves_complete (timeout %.1f s)"
			% [_container.get_child_count(), cleared_after, timeout])
	assert_lt(cleared_after, timeout, "the container must empty BEFORE enemies_cleared_timeout")

	var last_fighter_exit := -INF
	assert_eq(_fighter_exits.size(), expected[1], "every fighter's exit must have been recorded")
	for i in _fighter_exits.size():
		var exit: Dictionary = _fighter_exits[i]
		last_fighter_exit = maxf(last_fighter_exit, float(exit["at"]))
		assert_false(exit["path_mover"], "fighter %d left on a rail (EnemyPathMover), not under AI" % i)
		assert_true(exit["disengage"], "fighter %d left in phase %d, not DISENGAGE" % [i, int(exit["phase"])])
	gut.p(("cloud_descent from %.1f s: %d ships (%d fighters); container empty %.2f s after waves_complete, "
		+ "margin %.2f s of the %.1f s timeout; last fighter left %.2f s after it (margin %.2f s)")
		% [_FROM, _spawned, _fighters_spawned, cleared_after, timeout - cleared_after, timeout,
			last_fighter_exit - _complete_at, timeout - (last_fighter_exit - _complete_at)])


## Boundary: the same waves with every fighter given `.move()` again are rejected by the predicate the
## main case relies on — each such fighter carries an `EnemyPathMover`. Duplicated entries: the
## section's own resources are never mutated. Runs just past the 72 s wave's last spawn (6.8 s re-timed)
## and stops there; teardown frees the rest with recording off.
func test_a_rail_driven_fighter_wave_is_rejected() -> void:
	var section := _cloud_descent()
	if section == null:
		fail_test("no cloud_descent section")
		return
	var waves := _replayed_waves(section, true)
	_build_world()
	_wave_manager.load_section(waves)
	await _advance(7.5, func() -> bool: return false)
	_recording = false
	_wave_manager.set_process(false)

	var fighters := 0
	for child in _container.get_children():
		if not child is Fighter:
			continue
		fighters += 1
		var has_path_mover := false
		for c in child.get_children():
			if c is EnemyPathMover:
				has_path_mover = true
		assert_true(has_path_mover, "a .move() fighter must carry an EnemyPathMover, which the main case rejects")
	assert_gt(fighters, 0, "sanity: the rail fighters spawned and are still in the container")
