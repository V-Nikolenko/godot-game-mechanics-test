## Level 1's `station_assault` section holding the Space Fortress (Phase 11 t10; epic plan docs/plans/cmug256so0031m52wbxomst72/3-plan.md §2.10). Intent tests.
##
## A real `WaveManager` and `LevelDirector` on the section the shipped director builds (a fresh copy per test, never the shared list), in an Assault harness
## (a real `ArenaCamera`, so `WaveManager._spawn_ship()` really spawns the fortress). Wall clock, 1x: `LevelDirector._wait_enemies_cleared()` is a
## `Time.get_ticks_msec()` deadline, so it cannot be scaled; the replay keeps to one fortress life with `death_duration` 0.2 and scripted part kills
## (tests/README.md -> Gate time, rule 1).
##
## Row (a): the section waits while the fortress lives with escorts alive, and advances within `death_duration` + 0.5 s of the core's death with every escort
## scuttled. The parts are killed through `destroy()` right after spawn, before any rocket can be in flight, so the row never waits out the rocket tail (that tail
## is arithmetic, in test_engagement_deadline.gd).
## Row (b): with the fortress never killed, the timeout frees it and its escort container, at the cost of one escape penalty (the fortress's). The shipped 240 s is
## pinned by test_station_assault_section.gd; this row overrides `enemies_cleared_timeout` on its OWN built copy of the section to 2.0 s.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const REPLAY: GDScript = preload("res://tests/helpers/level1_slice_replay.gd")
const SWARM: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")

const SECTION := &"station_assault"
const DEATH_DURATION := 0.2
## What the director waits on after the fortress is freed: the final blast's particles stay in the enemy container for the effect's `lifetime` (0.5 s, read off the fortress's own `ExplosionEffect`; measured: the section advances 0.94 s after the core dies at `death_duration` 0.2), then the director's 0.2 s settle. The plan's "death_duration + 0.5 s" counted only the first, so the bound is `death_duration` + that lifetime + the settle + a frame margin.
const SETTLE := 0.2
const MARGIN := 0.25
const SHORT_TIMEOUT := 2.0

var _h = null
var _container: Node2D
var _wave_manager: WaveManager
var _director: LevelDirector
var _tracker: ScoreTracker
var _started: Array = []
var _started_ms: Array[int] = []
var _fortress: SpaceFortress = null
var _escorts: Array[Node] = []


func before_each() -> void:
	_started = []
	_started_ms = []
	_fortress = null
	_escorts = []


## The world: harness, container, manager, director (with the section under test and an `after` section that makes "did it advance?" observable), tracker.
func _world(timeout_override: float = -1.0) -> void:
	_h = HARNESS.assault()
	add_child_autofree(_h.root)
	_h.player.global_position = Vector2(640.0, 560.0)

	_container = Node2D.new()
	_container.name = "EnemyContainer"
	_h.root.add_child(_container)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	_h.root.add_child(_wave_manager)

	_director = LevelDirector.new()
	_director.wave_manager = _wave_manager
	_h.root.add_child(_director)
	_director.section_started.connect(func(index: int, _n: StringName) -> void:
		_started.append(index)
		_started_ms.append(Time.get_ticks_msec()))

	var section: LevelSection = REPLAY.section(SECTION)
	section.transition_in_duration = 0.0
	if timeout_override > 0.0:
		section.enemies_cleared_timeout = timeout_override
	_director.add_section(section)
	var after := LevelSection.new()
	after.section_name = &"after"
	after.end_condition = LevelSection.EndCondition.DURATION
	after.duration = 999.0
	_director.add_section(after)

	_tracker = ScoreTracker.new()
	_tracker.wave_manager = _wave_manager
	_h.root.add_child(_tracker)
	_tracker.start_tracking()
	## `_process()` decays a combo above 1.0 back to 1.0; this is about the escape path only. 2.0 clears the 1/0.75 clamp floor.
	_tracker.set_process(false)
	_tracker.set("_combo", 2.0)

	_wave_manager.enemy_spawned.connect(_on_spawned)


func _on_spawned(enemy: Node, _wave_index: int) -> void:
	if enemy is SpaceFortress and _fortress == null:
		_fortress = enemy
		_fortress.death_duration = DEATH_DURATION
		## Two escorts straight into the escort container: a bay launches only once the fortress is engaged (after ENTER), too late for this row.
		var box := EscortContainer.ensure(_fortress)
		for i in 2:
			var drone := SWARM.instantiate() as Node2D
			drone.global_position = _fortress.global_position + Vector2(120.0 * (i * 2 - 1), 200.0)
			box.add_child(drone)
			_escorts.append(drone)


func _start_and_wait_for_fortress() -> void:
	_director.start()
	await wait_until(func() -> bool: return _fortress != null, 3.0)
	assert_not_null(_fortress, "the section spawns the fortress")


func _kill_the_fortress() -> void:
	for id in [&"battery_spread", &"battery_pulse", &"shield_north", &"shield_south"]:
		_fortress.part(id).destroy()
	## The core opens one frame after the second generator dies (a deferred unlock).
	await get_tree().process_frame
	_fortress.part(&"core").destroy()


# ── (a) the fortress and its escorts hold the section; its death releases it ───────────────────

func test_the_section_waits_for_the_fortress_and_advances_after_its_death() -> void:
	_world()
	await _start_and_wait_for_fortress()
	assert_eq(_started, [0], "the section started")
	assert_eq(_escorts.size(), 2, "precondition: two escorts in the boss's escort container")
	assert_eq(_container.get_child_count(), 2, "the section sees the fortress and its one escort container")

	await wait_seconds(0.5)
	assert_eq(_started, [0], "the section waits while the fortress lives with escorts alive")
	assert_true(is_instance_valid(_fortress) and not _fortress.was_killed, "control: still alive")

	var blast := _blast_lifetime()
	await _kill_the_fortress()
	var killed_at := Time.get_ticks_msec()
	assert_true(_fortress.was_killed, "the core's death is the fortress's: a kill, not an escape")
	for e in _escorts:
		assert_true(not is_instance_valid(e) or e.is_queued_for_deletion() or (e as BaseEnemy).health.current_health <= 0,
				"every escort is scuttled when the death starts")

	await wait_until(func() -> bool: return _started.size() == 2, DEATH_DURATION + 2.0)
	var elapsed := float(_started_ms[1] - killed_at) / 1000.0
	assert_eq(_started, [0, 1], "the section advanced")
	var bound := DEATH_DURATION + blast + SETTLE + MARGIN
	assert_lt(elapsed, bound, "within death_duration + the final blast + the settle of the core's death (%.2f s of %.2f s)" % [elapsed, bound])
	assert_false(is_instance_valid(_fortress), "the fortress is gone")
	assert_eq(get_tree().get_nodes_in_group(EscortContainer.GROUP).size(), 0, "so is its escort container")
	for e in _escorts:
		assert_false(is_instance_valid(e), "and every escort")
	assert_gte(float(_tracker.get("_combo")), 2.0, "a kill is no escape penalty")


# ── (b) a fortress that is never killed is freed by the timeout ─────────────────────────────────

func test_a_never_killed_fortress_is_freed_by_the_timeout_with_its_escorts() -> void:
	_world(SHORT_TIMEOUT)
	await _start_and_wait_for_fortress()
	var box := EscortContainer.of(_fortress)
	assert_not_null(box, "precondition: the escort container exists")

	await wait_until(func() -> bool: return _started.size() == 2, SHORT_TIMEOUT + 3.0)
	assert_eq(_started, [0, 1], "the overridden 2.0 s timeout let the section advance")
	assert_false(is_instance_valid(_fortress), "the timeout freed the fortress")
	assert_false(is_instance_valid(box), "and its escort container")
	for e in _escorts:
		assert_false(is_instance_valid(e), "and every escort")
	assert_eq(_container.get_child_count(), 0, "nothing is carried into the next section")
	assert_almost_eq(float(_tracker.get("_combo")), 1.5, 0.001, "one escape penalty (x0.75), the fortress's: escorts are not wave enemies")


func _blast_lifetime() -> float:
	var effects := _fortress.find_children("*", "ExplosionEffect", true, false)
	assert_gt(effects.size(), 0, "the fortress has an ExplosionEffect")
	return (effects[0] as ExplosionEffect).lifetime if effects.size() > 0 else 0.5
