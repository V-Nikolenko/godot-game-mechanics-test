## INTENT tests for the wiring between OpenSpacePlayerShip and AimCursor — the anti-inert
## gate for RET-1. Every case in tests/unit/test_aim_cursor.gd is green on a build where
## OpenSpacePlayerShip never calls AimCursor at all; this is the file that fails on that.
##
## AimCursor's applied flag is PROCESS-GLOBAL and STICKY, exactly like the real
## Input.set_custom_mouse_cursor() call it wraps — so every case here must leave it restored,
## or it leaks into whichever test (in this file or another) runs next.
extends GutTest

const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const AimCursor := preload("res://global/systems/aim_cursor.gd")

var _saved_scheme: StringName


func before_each() -> void:
	_saved_scheme = SettingsState.get_open_space_scheme()
	AimCursor.restore()


func after_each() -> void:
	## Restored directly, matching test_player_ship_turn_wiring.gd's pattern: going through
	## set_open_space_scheme() is a no-op (emits nothing) whenever the value already matches.
	SettingsState._open_space_scheme = _saved_scheme
	AimCursor.restore()


func _spawn_ship() -> OpenSpacePlayerShip:
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child_autofree(ship)
	ship.set_physics_process(false)
	return ship


func test_mouse_scheme_applies_the_cursor_on_ready() -> void:
	SettingsState._open_space_scheme = &"mouse"
	_spawn_ship()
	assert_true(AimCursor.is_applied(),
			"a ship flown with the mouse must swap the OS arrow for the crosshair")


func test_keys_scheme_never_applies_the_cursor() -> void:
	SettingsState._open_space_scheme = &"keys"
	_spawn_ship()
	assert_false(AimCursor.is_applied(),
			"under keyboard steering there is no cursor aiming to call out")


func test_freeing_the_ship_restores_the_cursor() -> void:
	SettingsState._open_space_scheme = &"mouse"
	var ship := SHIP_SCENE.instantiate() as OpenSpacePlayerShip
	add_child(ship)
	ship.set_physics_process(false)
	assert_true(AimCursor.is_applied())

	ship.queue_free()
	await get_tree().process_frame

	assert_false(AimCursor.is_applied(),
			"_exit_tree() must restore the OS arrow on every exit path")
