## assault/scenes/gui/game_over.gd
## Full-screen "GAME OVER" overlay added to the scene-tree root on player death.
##
## The tree is paused while this overlay is visible, so PROCESS_MODE_ALWAYS is
## required for _input() to fire.  On continue the tree is unpaused BEFORE the
## queue_free / reload so the new scene starts in a clean running state.
extends CanvasLayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot"):
		get_viewport().set_input_as_handled()
		## Unpause first — reload_current_scene must start with a running tree.
		get_tree().paused = false
		queue_free()
		get_tree().call_deferred("reload_current_scene")
