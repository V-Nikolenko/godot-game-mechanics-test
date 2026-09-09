## Characterization + intent tests for PickupState (global/autoloads/pickup_state.gd).
##
## Tracks which persistent-id pickups have ever been collected, independent of any specific
## physical node — the primitive a restart-safe one-time pickup (a future placed LoreLogPickup)
## needs so a mission reload doesn't re-grant it.
extends GutTest

const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const PickupStateScript := preload("res://global/autoloads/pickup_state.gd")

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


## Tree-less instance: _ready() never fires, so the caller decides when _load() runs.
func _fresh() -> Node:
	return PickupStateScript.new()


func test_has_collected_is_false_for_an_unknown_id() -> void:
	var ps := _fresh()
	assert_false(ps.has_collected(&"some_log"))
	ps.free()


func test_mark_collected_makes_has_collected_true() -> void:
	var ps := _fresh()
	ps.mark_collected(&"some_log")
	assert_true(ps.has_collected(&"some_log"))
	ps.free()


## Boundary: a scene reload respawns the same physical node, which fires mark_collected again
## for the same id — this must not error or do anything observable a second time.
func test_marking_the_same_id_twice_is_idempotent() -> void:
	var ps := _fresh()
	ps.mark_collected(&"some_log")
	ps.mark_collected(&"some_log")
	assert_true(ps.has_collected(&"some_log"))
	ps.free()


func test_collected_state_survives_a_save_load_round_trip() -> void:
	_sandbox.clear_all()
	var writer := _fresh()
	writer.mark_collected(&"log_a")
	writer.free()

	var reader := _fresh()
	reader._load()

	assert_true(reader.has_collected(&"log_a"))
	assert_false(reader.has_collected(&"log_b"))
	reader.free()
