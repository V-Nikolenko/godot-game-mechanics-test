## INTENT tests for §2.4.1 (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md): where Assault squads
## come from. `WaveBuilder.SpawnConfig.squad(id)` / `SpawnEntryResource.squad_id` are new code, and
## `WaveManager` only ever writes a squad *key* string into a spawn dict — never a board — resolving
## it against a `_squads: Dictionary` of key -> WeakRef(SquadController) at spawn time. These assert
## that contract, not today's behaviour.
##
## Harness: a real `WaveManager` + `WaveBuilder`, a `Camera2D` (required by `_spawn_ship()`, see
## `test_spawn_camera_pan.gd`) and `tests/helpers/squad_fixture.tscn` — a bare `Node2D` with a
## `squad` property, the minimum shape the duck-typed `"squad" in entity` check looks for. Every
## wave uses `trigger_time = 0.0` and no `.delay()`/stagger, so `_spawn_with_delay()` never awaits a
## real `SceneTreeTimer` — the leak trap `tests/README.md` documents for this exact suite.
extends GutTest

const SQUAD_FIXTURE_PATH := "res://tests/helpers/squad_fixture.tscn"
const SQUAD_FIXTURE_SCENE: PackedScene = preload("res://tests/helpers/squad_fixture.tscn")

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


## A bare `PackedScene` wrapping an empty, script-less `Node2D` — no "squad" property at all.
func _blank_ship_scene() -> PackedScene:
	var root := Node2D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


func _load_section(waves: Array) -> void:
	var typed: Array[WaveResource] = []
	typed.assign(waves)
	_wm.load_section(typed)


# ── Where squads come from (§2.4.1) ─────────────────────────────────────────────

func test_formation_expands_into_one_board_shared_by_every_slot() -> void:
	var entry := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).formation(_builder.cluster_formation(4))
	_load_section([_builder.wave(0.0, [entry])])
	_wm._process(0.0)

	assert_eq(_container.get_child_count(), 4)
	var boards: Array = []
	for child in _container.get_children():
		boards.append(child.get("squad"))
	for board in boards:
		assert_not_null(board, "every formation slot must receive a board")
		assert_eq(board, boards[0], "a formation is automatically one squad")


func test_loose_entries_sharing_a_squad_id_form_one_board() -> void:
	var a := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"pair")
	var b := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"pair")
	_load_section([_builder.wave(0.0, [a, b])])
	_wm._process(0.0)

	var ships := _container.get_children()
	assert_eq(ships.size(), 2)
	assert_not_null(ships[0].get("squad"))
	assert_eq(ships[0].get("squad"), ships[1].get("squad"), "a shared squad() id must resolve to one board")


func test_loose_entries_with_no_id_each_get_a_squad_of_one() -> void:
	var a := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH)
	var b := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH)
	_load_section([_builder.wave(0.0, [a, b])])
	_wm._process(0.0)

	var ships := _container.get_children()
	assert_eq(ships.size(), 2)
	assert_not_null(ships[0].get("squad"))
	assert_not_null(ships[1].get("squad"))
	assert_ne(ships[0].get("squad"), ships[1].get("squad"), "no id means a squad of one each")


## Boundary: the same id reused in a later wave of the same section must not resolve to the
## earlier wave's board — the squad key is namespaced by wave index for exactly this reason.
func test_same_id_in_two_different_waves_makes_two_boards() -> void:
	var w0 := _builder.wave(0.0, [WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"alpha")])
	var w1 := _builder.wave(1.0, [WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"alpha")])
	_load_section([w0, w1])
	_wm._process(0.0)  # triggers w0 (trigger_time 0.0)
	_wm._process(1.0)  # elapsed now 1.0 -> triggers w1

	var ships := _container.get_children()
	assert_eq(ships.size(), 2)
	assert_not_null(ships[0].get("squad"))
	assert_not_null(ships[1].get("squad"))
	assert_ne(ships[0].get("squad"), ships[1].get("squad"),
		"the same squad() id in two different waves must give two boards")


func test_entity_without_a_squad_property_spawns_without_error() -> void:
	_wm.register_wave(0.0, [{"ship": {"scene": _blank_ship_scene()}, "offset": Vector2.ZERO}])
	_wm._process(0.0)

	assert_eq(_container.get_child_count(), 1, "an entity with no squad property must still spawn")


func test_spawn_dicts_never_hold_a_board_only_strings() -> void:
	var entry := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"only-strings")
	_load_section([_builder.wave(0.0, [entry])])
	_wm._process(0.0)

	assert_eq(_container.get_child_count(), 1)
	for wave: Dictionary in _wm._waves:
		for spawn: Dictionary in wave.spawns:
			for key in spawn:
				assert_false(spawn[key] is SquadController,
					"a spawn dict must never hold a board object, only its key string")
			if spawn.has("squad_key"):
				assert_typeof(spawn["squad_key"], TYPE_STRING)


func test_board_is_released_once_every_member_of_its_squad_is_freed() -> void:
	var entry := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"doomed")
	_load_section([_builder.wave(0.0, [entry])])
	_wm._process(0.0)

	var ship: Node2D = _container.get_child(0)
	var key := "0:doomed"
	assert_true(_wm._squads.has(key))
	var wr: WeakRef = _wm._squads[key]
	assert_ne(wr.get_ref(), null, "the board must be alive while its only member is")

	ship.free()
	assert_eq(wr.get_ref(), null, "no member remains -> nothing keeps the board alive")


## A member arriving after every one of its squad mates has already died (e.g. a long `.delay()`)
## must not be handed the now-dead board back — it starts a fresh squad of one. Driving `_spawn_ship`
## directly with the pre-resolved squad key is the deterministic stand-in for "arrives later": the
## real staggering already goes through a `SceneTreeTimer` that other tests cover, and awaiting one
## here for real would be exactly the leak trap `tests/README.md` documents for this file.
func test_a_late_arrival_whose_squad_already_died_gets_a_fresh_board() -> void:
	var entry := WaveBuilder.SpawnConfig.new(SQUAD_FIXTURE_PATH).squad(&"relay")
	_load_section([_builder.wave(0.0, [entry])])
	_wm._process(0.0)

	var first: Node2D = _container.get_child(0)
	# A weak reference only — anything holding a strong one (a local var included) would keep the
	# board alive itself and defeat the point of this test, the same reason
	# test_squad_controller.gd's release test nulls its own `board` var before checking.
	var original_ref: WeakRef = weakref(first.get("squad"))
	var original_id: int = (first.get("squad") as SquadController).get_instance_id()
	first.free()
	assert_eq(original_ref.get_ref(), null, "the old board must be fully gone before the late arrival spawns")

	_wm._spawn_ship({"ship": {"scene": SQUAD_FIXTURE_SCENE}, "offset": Vector2.ZERO, "squad_key": "0:relay"})

	assert_eq(_container.get_child_count(), 1)
	var second: Node2D = _container.get_child(0)
	var second_board: SquadController = second.get("squad")
	assert_not_null(second_board)
	assert_ne(second_board.get_instance_id(), original_id,
		"a squad whose members all died must not be resurrected for a late arrival")
