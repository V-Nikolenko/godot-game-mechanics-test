## ScoreTracker's escape-combo penalty must honour `counts_as_escape`.
##
## `assault/scenes/enemies/bonus_drone/bonus_drone.gd`'s header comment promised "no penalty for
## missing it", but `score_tracker.gd:210-211` applied the penalty unconditionally on every
## `tree_exited`, `counts_toward_wave_clear` only gates the wave-clear tally, not the escape
## multiply. Fixed by a second, independent flag (`counts_as_escape`, mirroring
## `counts_toward_wave_clear`'s config → BaseEnemy → ScoreTracker plumbing).
##
## Companion to `test_station_reinforcements.gd`'s
## `test_a_squad_that_flies_through_costs_two_escape_combo_penalties`, which pins the OPPOSITE,
## deliberately-kept case (reinforcements still pay the penalty) and must stay untouched.
extends GutTest

const BONUS_DRONE_SCENE: PackedScene = preload("res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn")

var _container: Node2D
var _tracker: ScoreTracker


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_tracker = ScoreTracker.new()
	add_child_autofree(_tracker)
	_tracker.start_tracking()
	## Same remedy as test_station_reinforcements.gd:404-406 — an undecayed-combo assertion needs
	## the frame-based decay tick off, or _process resets it to 1.0 on the first idle frame.
	_tracker.set_process(false)
	_tracker.set("_combo", 4.0)


func test_bonus_drone_escaping_does_not_cost_combo() -> void:
	var drone: Node = BONUS_DRONE_SCENE.instantiate()
	_container.add_child(drone)
	_tracker._on_orphan_spawned(drone)

	drone.queue_free()
	await wait_physics_frames(2)

	assert_almost_eq(float(_tracker.get("_combo")), 4.0, 0.001,
		"a missed bonus drone must not cost any combo — counts_as_escape = false on its config")


## Boundary: an enemy with no `counts_as_escape` property at all (a bare Node, like
## `AsteroidBase` or any enemy with no config override) must still pay the penalty. Proves the new
## flag's default preserves today's behaviour instead of silently exempting every ad-hoc spawn.
func test_enemy_with_no_escape_flag_still_pays_the_penalty() -> void:
	var enemy := Node2D.new()
	_container.add_child(enemy)
	_tracker._on_orphan_spawned(enemy)

	enemy.queue_free()
	await wait_physics_frames(2)

	assert_almost_eq(float(_tracker.get("_combo")), 3.0, 0.001,
		"an enemy with no counts_as_escape property must still pay the default penalty (4.0 * 0.75)")
