# assault/scenes/player/debug_unlock_all.gd
extends Node

func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.physical_keycode == KEY_U:
			UpgradeState.unlock_all()
			print("[DEBUG] All weapon upgrades unlocked.")
