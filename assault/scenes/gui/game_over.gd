extends CanvasLayer

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("shoot"):
		queue_free()
		get_tree().call_deferred("reload_current_scene")
