## INTENT test for §2.5 (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md): the W formation.
## `WFormation` is new code (`global/resources/formation/w_formation.gd`), so this pins its
## slot geometry and delay schedule directly, then reuses the Ph2 squad fixture
## (`tests/helpers/squad_fixture.tscn`, see `test_wave_squads.gd`) to prove a `WaveManager`
## expansion of it is one shared squad, the same contract every other formation already has.
extends GutTest

const SQUAD_FIXTURE_PATH := "res://tests/helpers/squad_fixture.tscn"

var _container: Node2D
var _wm: WaveManager
var _builder: WaveBuilder


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)

	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = Vector2(640.0, 360.0)
	cam.make_current()

	_wm = WaveManager.new()
	_wm.enemy_container = _container
	add_child_autofree(_wm)

	_builder = WaveBuilder.new()


func _load_section(waves: Array) -> void:
	var typed: Array[WaveResource] = []
	typed.assign(waves)
	_wm.load_section(typed)


# ── Slot geometry (§2.5) ─────────────────────────────────────────────────────

func test_w5_offsets_and_delays_match_the_spec() -> void:
	var f := _builder.w_formation()
	var slots: Array = f.compute_slots()

	assert_eq(slots.size(), 5)
	var expected_offsets: Array[Vector2] = [
		Vector2(-120.0, 0.0), Vector2(-60.0, -40.0), Vector2(0.0, 0.0),
		Vector2(60.0, -40.0), Vector2(120.0, 0.0),
	]
	var expected_delays: Array[float] = [0.2, 0.1, 0.0, 0.1, 0.2]
	for i in slots.size():
		assert_eq(slots[i].offset, expected_offsets[i], "slot %d offset" % i)
		assert_almost_eq(slots[i].delay, expected_delays[i], 0.0001, "slot %d delay" % i)


func test_w_formation_of_one_is_a_single_slot_at_the_origin_with_no_delay() -> void:
	var f := _builder.w_formation(1)
	var slots: Array = f.compute_slots()

	assert_eq(slots.size(), 1)
	assert_eq(slots[0].offset, Vector2.ZERO)
	assert_almost_eq(slots[0].delay, 0.0, 0.0001)


func test_w_formation_defaults_match_the_spec_values() -> void:
	var f := _builder.w_formation()
	assert_eq(f.count, 5)
	assert_almost_eq(f.spread, 60.0, 0.0001)
	assert_almost_eq(f.depth, 40.0, 0.0001)
	assert_almost_eq(f.stagger_delay, 0.1, 0.0001)


# ── Squad expansion (reuse of the Ph2 fixture) ───────────────────────────────

func test_w_formation_expands_into_one_board_shared_by_every_slot() -> void:
	# stagger 0.0: a nonzero stagger makes every non-centre slot spawn through an awaited
	# `SceneTreeTimer` (wave_manager.gd's `_spawn_with_delay`), which a single `_process()` call
	# below cannot observe and which the leak trap in tests/README.md warns against anyway.
	var entry := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).formation(_builder.w_formation(5, 60.0, 40.0, 0.0))
	_load_section([_builder.wave(0.0, [entry])])
	_wm._process(0.0)

	assert_eq(_container.get_child_count(), 5)
	var boards: Array = []
	for child in _container.get_children():
		boards.append(child.get("squad"))
	for board in boards:
		assert_not_null(board, "every formation slot must receive a board")
		assert_eq(board, boards[0], "a W formation is automatically one squad")
