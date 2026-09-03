## End-to-end test for Level 1's full section sequence (EPIC sub-item 5's done-condition).
##
## This is THE test the sub-item rests on: a headless run of the real five-section sequence —
## deep_space -> asteroid_belt -> station_assault -> planet_approach -> cloud_descent — with a
## REAL SpaceStation killed for real in the middle of it, reaching `level_complete`.
##
## ── Four things this file has to get right ───────────────────────────────────────────────────
##
## 1. **Zero `spawn_delay` as well as `trigger_time`.** `level_1_director.gd` calls `.delay()` 182
##    times, up to 1.5 s, and `wave_manager.gd:151-155` turns each into
##    `await get_tree().create_timer(delay).timeout`. With trigger_time zeroed, a section can
##    reach `level_complete` while ~30 spawn coroutines still hold timers — and a test that
##    returns while those are suspended leaks SceneTreeTimers that Godot reports as
##    `ObjectDB instances leaked` at exit. That line does NOT match the gate's fatal-error regex,
##    so the gate would stay GREEN while leaking. See tests/README.md.
##    Safe to mutate: `wave_builder.gd:196-197` builds a fresh SpawnEntryResource per call and
##    `:211-212` a fresh WaveResource, so nothing shipped is shared.
## 2. **The station must be in the container BEFORE `waves_complete` can fire.**
##    `_advance()` emits `section_started` at `level_director.gd:60` but calls
##    `wave_manager.load_section()` at `:66`, so the `section_started` handler runs first — which
##    is the only window in which the station can be added synchronously. Add it later and the
##    director sees an empty container and advances straight past the boss.
## 3. **`enemies_cleared_timeout` is left untouched.** The point is that sections end because they
##    FINISH, not because the safety net fires. The elapsed-time assertion is what proves it.
## 4. **Return only after `level_complete`**, so no `_wait_enemies_cleared()` coroutine is left
##    suspended — the same leak trap as (1).
extends GutTest

const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const STATION_SCENE := preload("res://assault/scenes/enemies/space_station/space_station.tscn")

const EXPECTED_SECTIONS: Array[StringName] = [
	&"deep_space", &"asteroid_belt", &"station_assault", &"planet_approach", &"cloud_descent",
]

var _container: Node2D
var _wave_manager: WaveManager
var _director: LevelDirector
var _started: Array[StringName] = []
var _station: SpaceStation
var _advanced_past_station_while_wreck_present := false


func before_each() -> void:
	_started = []
	_station = null
	_advanced_past_station_while_wreck_present = false

	_container = Node2D.new()
	add_child_autofree(_container)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	add_child_autofree(_wave_manager)

	_director = LevelDirector.new()
	_director.wave_manager = _wave_manager
	add_child_autofree(_director)


## The REAL sections, compressed so the test runs in seconds. `_build_sections()` touches only
## LevelSection.new(), preload and WaveBuilder (a RefCounted), so it is safe on a bare instance
## that never entered the tree.
func _compressed_level_1_sections() -> Array:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	var sections: Array = d._build_sections()

	for s in sections:
		var section: LevelSection = s
		if section.end_condition == LevelSection.EndCondition.DURATION:
			section.duration = 0.1
		section.transition_in_duration = 0.0
		for w in section.waves:
			var wave: WaveResource = w
			wave.trigger_time = 0.0
			for e in wave.entries:
				var entry: SpawnEntryResource = e
				## The leak guard — see rule 1 in the header.
				entry.spawn_delay = 0.0
				## And the SECOND half of it, which cost a debugging round to find:
				## `wave_manager.gd:143` expands a formation as `base_delay + slot.delay`, so
				## zeroing `spawn_delay` alone still leaves every formation's own stagger — and
				## Level 1 uses formations heavily (v, wedge, line, diagonal and cluster ALL
				## stagger their slots). Safe to mutate for the same reason as the rest:
				## `wave_builder.gd:154-192` builds each formation with `.new()` per call, so
				## nothing shipped is shared.
				if entry.formation != null:
					entry.formation.set(&"stagger_delay", 0.0)
	return sections


func test_level_1_runs_all_five_sections_end_to_end_with_a_real_station() -> void:
	var sections := _compressed_level_1_sections()
	assert_eq(sections.size(), 5, "Level 1 ships five sections")

	for s in sections:
		_director.add_section(s)

	var complete := [false]
	_director.level_complete.connect(func() -> void: complete[0] = true)

	_director.section_started.connect(
		func(_index: int, section_name: StringName) -> void:
			_started.append(section_name)

			## Synchronously, inside the handler — see rule 2 in the header.
			if section_name == &"station_assault":
				_station = STATION_SCENE.instantiate() as SpaceStation
				## Short, but non-zero: the wreck must genuinely linger, because "the wreck holds
				## the section open" is half of what this test proves. The shipped 1.8 s is pinned
				## by test_station_death_sequence.gd instead; here it only has to be observable.
				_container.add_child(_station)
				_station.death_duration = 0.2

			## If the boss's wreck is still parented when the NEXT section starts, the handoff is
			## broken — the level walked past a living boss.
			if section_name == &"planet_approach":
				if _station != null and is_instance_valid(_station) \
						and _station.get_parent() == _container:
					_advanced_past_station_while_wreck_present = true
	)

	var start_ms := Time.get_ticks_msec()
	_director.start()

	## Walk to the boss.
	var guard := 0
	while not _started.has(&"station_assault") and guard < 600:
		await get_tree().process_frame
		guard += 1
	assert_true(_started.has(&"station_assault"), "the run must reach the station_assault section")
	assert_not_null(_station, "a real station must have been placed in the container")

	## The section must NOT advance while the boss is alive.
	await get_tree().create_timer(0.3).timeout
	assert_false(_started.has(&"planet_approach"),
		"station_assault must not advance while the station is alive")

	## Kill it for real: four turrets, then the core.
	for t in _station.turrets():
		t.hurt_box.received_damage.emit(9999)
	await get_tree().process_frame
	_station.hurt_box.received_damage.emit(_station.health.max_health)
	await get_tree().process_frame

	assert_true(_station.was_killed, "the boss must be scored as a kill, not an escape")

	## Now let the whole rest of the level play out. Budget: the death sequence, the director's
	## ~1.0 s poll and 0.2 s settle, then two short sections.
	guard = 0
	while not complete[0] and guard < 1200:
		await get_tree().process_frame
		guard += 1

	var elapsed_s := float(Time.get_ticks_msec() - start_ms) / 1000.0

	assert_true(complete[0], "the level must reach level_complete")
	assert_eq(_started, EXPECTED_SECTIONS,
		"all five sections must run, in order, ending at cloud_descent")
	assert_false(_advanced_past_station_while_wreck_present,
		"planet_approach must not start while the boss's wreck is still in the container")
	assert_false(is_instance_valid(_station), "the wreck must be gone by the end of the run")

	## The sections ended because they FINISHED, not because a safety net expired. The station
	## section's own timeout is 180 s and cloud_descent's is 10 s, so a run this fast cannot have
	## been driven by either.
	assert_lt(elapsed_s, 10.0,
		"the run must complete well inside the timeouts — %.2f s elapsed" % elapsed_s)

	## Nothing may be left holding the container open after the level is done.
	assert_eq(_container.get_child_count(), 0,
		"the enemy container must be empty once the level completes")

	## Drain the director's last poll timer before returning.
	##
	## `_wait_for_child_exit_or_timeout()` (level_director.gd:85-101) races a 1.0 s SceneTreeTimer
	## against the container's `child_exiting_tree`. When the wreck leaves first — which is the
	## whole point of this test — the helper returns immediately and that timer keeps ticking with
	## nobody awaiting it. If the process exits before it fires, Godot reports
	## `ObjectDB instances leaked`, and the gate's fatal-error regex does NOT match that line, so
	## the gate would stay green while leaking.
	##
	## Measured status, so nobody deletes this on a wrong assumption: with the suite as it stands
	## today the leak does NOT reproduce without this await — the ~10 s of tests that happen to run
	## afterwards outlive the timer and it fires in time. That is ordering luck, not a guarantee:
	## it depends on this file not being the last one GUT runs. 1.1 s against a ~14 s suite is a
	## cheap way to stop depending on it.
	##
	## (The `ObjectDB instances leaked` line the gate DOES print comes from step 1, the headless
	## import, and predates this work — see BACKLOG.md under Discovered. It is not this test.)
	await get_tree().create_timer(1.1).timeout
