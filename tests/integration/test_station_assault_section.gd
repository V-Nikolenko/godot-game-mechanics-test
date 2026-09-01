## Integration tests for the `station_assault` LevelSection (EPIC sub-item 2).
##
## Like `test_space_station.gd` these are NOT characterization tests — the section is new code, so
## they assert intended behaviour. Test 7 is the exception in spirit: it pins the *corrected*
## timeout path, which today advances with the boss still parented to the enemy container.
##
## The director tests build a `LevelDirector` + `WaveManager` + a bare `Node2D` container by hand.
## There is no camera and no level scene, so `WaveManager._spawn_ship()` returns early
## (`wave_manager.gd:160-162`) and nothing ever spawns — which is what we want: the gate is driven
## by emitting `waves_complete` and by adding/freeing container children directly.
##
## Timing note that governs tests 6 and 7: `LevelDirector._wait_enemies_cleared()` re-checks its
## deadline only *after* `_wait_for_child_exit_or_timeout(container, 1.0)` returns, and with no
## `child_exiting_tree` that helper always burns its full 1.0 s poll (`level_director.gd:85-102`).
## So a 0.3 s timeout really expires at ~1.0 s, and `_advance()` runs after a further 0.2 s settle
## (`:122`) — ~1.2 s. Budgets below are sized off that, not off the nominal timeout.
extends GutTest

const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

var _container: Node2D
var _wave_manager: WaveManager
var _director: LevelDirector
var _started: Array = []


func before_each() -> void:
	_started = []

	_container = Node2D.new()
	add_child_autofree(_container)

	_wave_manager = WaveManager.new()
	_wave_manager.enemy_container = _container
	add_child_autofree(_wave_manager)

	_director = LevelDirector.new()
	_director.wave_manager = _wave_manager
	add_child_autofree(_director)
	_director.section_started.connect(
		func(index: int, _section_name: StringName) -> void: _started.append(index)
	)


## Section 0 is the gated one; section 1 exists only so "did it advance?" is observable.
func _add_two_sections(timeout: float) -> void:
	var gated := LevelSection.new()
	gated.section_name            = &"gated"
	gated.end_condition           = LevelSection.EndCondition.ENEMIES_CLEARED
	gated.duration                = 0.0
	gated.enemies_cleared_timeout = timeout
	_director.add_section(gated)

	var after := LevelSection.new()
	after.section_name  = &"after"
	after.end_condition = LevelSection.EndCondition.DURATION
	after.duration      = 999.0
	_director.add_section(after)


func _add_live_enemy() -> Node2D:
	var enemy := Node2D.new()
	_container.add_child(enemy)
	return enemy


## `_build_sections()` touches only LevelSection.new(), preload and WaveBuilder (a RefCounted), so
## it is safe on a bare instance that never entered the tree. The script has no class_name, hence
## the preloaded GDScript rather than a type.
func _level_1_sections() -> Array:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	return d._build_sections()


# ── 4. The per-section timeout export ─────────────────────────────────────────

## The default must be exactly today's hardcoded constant (level_director.gd:108) so that
## `cloud_descent`, the only shipped ENEMIES_CLEARED section, is bit-identical after this change.
func test_enemies_cleared_timeout_defaults_to_ten_seconds() -> void:
	assert_eq(LevelSection.new().enemies_cleared_timeout, 10.0,
		"the default must match the 10 s constant it replaces")


# ── 5-7. The gate ─────────────────────────────────────────────────────────────

func test_section_does_not_advance_while_an_enemy_lives() -> void:
	_add_two_sections(30.0)
	var enemy := _add_live_enemy()

	_director.start()
	assert_eq(_started.size(), 1, "director should have started on section 0")
	assert_eq(_started[0], 0, "first section started should be index 0")

	_wave_manager.waves_complete.emit()
	await wait_seconds(0.5)

	assert_eq(_started.size(), 1,
		"must not advance while an enemy is still parented to the container")
	assert_eq(_container.get_child_count(), 1, "the enemy should still be alive")

	## Drain the director's still-suspended _wait_enemies_cleared() before teardown. It holds a
	## 1 s SceneTreeTimer, and freeing the director out from under the coroutine strands both —
	## which Godot reports at exit as "resources still in use". Tests 6 and 7 run the wait to
	## completion themselves, so only this one needs it.
	enemy.queue_free()
	await wait_seconds(0.5)


func test_section_advances_when_the_last_enemy_is_freed() -> void:
	_add_two_sections(30.0)
	var enemy := _add_live_enemy()

	_director.start()
	_wave_manager.waves_complete.emit()
	await wait_seconds(0.2)
	assert_eq(_started.size(), 1, "still gated before the enemy dies")

	enemy.queue_free()
	## child_exiting_tree ends the 1.0 s poll early, then the director settles for 0.2 s.
	await wait_seconds(1.0)

	assert_eq(_started.size(), 2, "director should advance once the container empties")
	assert_eq(_started[1], 1, "it should advance to the next section, index 1")


## Boundary: the safety net expires with the boss still alive. The director must not carry it into
## the next section — a station has no EnemyPathMover, so nothing else would ever free it, and
## `_wait_enemies_cleared` polls the same container, so a leftover would block the NEXT
## ENEMIES_CLEARED section forever.
##
## The escape-combo penalty is asserted rather than assumed: queue_free() emits no `died`, so
## ScoreTracker takes its escape path (`score_tracker.gd:197-215`) and multiplies the combo by
## `escape_combo_multiplier` (0.75).
func test_timeout_frees_leftover_enemies_then_advances() -> void:
	_add_two_sections(0.3)

	var tracker := ScoreTracker.new()
	tracker.wave_manager = _wave_manager
	add_child_autofree(tracker)
	tracker.start_tracking()
	## _process() decays any combo above 1.0 back to 1.0 as soon as _combo_decay_remaining hits
	## zero, which would mask the penalty entirely. This test is about the escape path only.
	tracker.set_process(false)
	## Must start above the 1/0.75 clamp floor (~1.334): score_tracker.gd:212-214 clamps the
	## product back up to 1.0, so from the default 1.0 the penalty is invisible.
	tracker.set("_combo", 2.0)

	var enemy := _add_live_enemy()
	## _on_enemy_freed is only ever connected from _on_enemy_spawned (score_tracker.gd:161-164),
	## which is driven by WaveManager.enemy_spawned — and this harness never reaches _spawn_ship.
	_wave_manager.enemy_spawned.emit(enemy, 0)

	_director.start()
	_wave_manager.waves_complete.emit()
	## ~1.2 s in practice (see the file header), so observe well past it.
	await wait_seconds(1.8)

	assert_eq(_started.size(), 2, "director must give up and advance after the timeout")
	assert_eq(_container.get_child_count(), 0,
		"leftover enemies must be freed on timeout, not carried into the next section")
	assert_almost_eq(float(tracker.get("_combo")), 1.5, 0.001,
		"letting the boss time out should cost one escape-combo penalty (x0.75)")


# ── 8-10. The Level 1 section list ────────────────────────────────────────────

func test_level_1_sections_are_in_order_with_station_assault_third() -> void:
	var sections: Array = _level_1_sections()
	var names: Array = []
	for s: LevelSection in sections:
		names.append(String(s.section_name))

	assert_eq(names.size(), 5, "Level 1 should have five sections after this change")
	assert_eq(names, ["deep_space", "asteroid_belt", "station_assault",
		"planet_approach", "cloud_descent"],
		"station_assault belongs between the asteroid belt and the planet approach")


func test_station_assault_is_enemies_cleared_with_a_long_timeout() -> void:
	var sections: Array = _level_1_sections()

	var station: LevelSection = sections[2]
	assert_eq(station.section_name, &"station_assault", "section 2 should be the station")
	assert_eq(station.end_condition, LevelSection.EndCondition.ENEMIES_CLEARED,
		"the encounter must block progress until the station dies")
	assert_true(station.enemies_cleared_timeout >= 60.0,
		"a boss safety net must be far longer than the 10 s straggler default, got %s"
			% station.enemies_cleared_timeout)

	var cloud: LevelSection = sections[4]
	assert_eq(cloud.section_name, &"cloud_descent", "section 4 should still be cloud_descent")
	assert_eq(cloud.enemies_cleared_timeout, 10.0,
		"cloud_descent must be untouched — its 10 s is correctly sized for its own job")


## Pins the two traps recorded in 1-context.md, both of which silently break the gate:
## a non-zero spawn delay lets waves_complete fire before the station is a child (so
## _wait_enemies_cleared sees an empty container and advances instantly), and a MovementResource
## would attach an EnemyPathMover that frees the station on screen exit.
func test_station_assault_spawns_one_station_at_zero_delay_with_no_movement() -> void:
	var station: LevelSection = _level_1_sections()[2]

	assert_eq(station.waves.size(), 1, "one wave: the station itself")
	var wave: WaveResource = station.waves[0]
	assert_eq(wave.trigger_time, 0.0, "the station should be there from the first frame")
	assert_eq(wave.entries.size(), 1, "exactly one spawn entry")

	var entry: SpawnEntryResource = wave.entries[0]
	assert_true(entry.ship_scene.resource_path.ends_with("space_station.tscn"),
		"expected the space station, got %s" % entry.ship_scene.resource_path)
	assert_eq(entry.spawn_delay, 0.0,
		"a delayed spawn lets waves_complete fire before the station exists")
	assert_null(entry.movement,
		"no MovementResource: an EnemyPathMover would free the station on screen exit")
