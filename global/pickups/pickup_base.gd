# global/pickups/pickup_base.gd
class_name PickupBase
extends Area2D

## Base class for all collectible pickups.
## Subclasses override _collect(player) and optionally _get_dialog_text().
## On body_entered: find player, collect, show dialog if text non-empty, queue_free.

func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	var player := body as PlayerBase
	if player == null:
		return
	_collect(player)
	var text: String = _get_dialog_text()
	if not text.is_empty():
		_show_notification(text)
	queue_free()


## Override: apply pickup effect to player.
func _collect(_player: PlayerBase) -> void:
	pass


## Override: return notification text, or "" for no dialog.
func _get_dialog_text() -> String:
	return ""


func _show_notification(text: String) -> void:
	## Skip silently if another dialog is already running (cutscene, NPC, or
	## another pickup picked up in the same frame). Effect still applied.
	if DialogPlayer.is_active:
		return
	var line := DialogLineResource.new()
	line.text = text
	line.side = DialogLineResource.Side.INNER_THOUGHT
	line.reveal = DialogLineResource.Reveal.INSTANT
	line.post_delay = 0.4
	var script_res := DialogScriptResource.new()
	script_res.lines = [line]
	script_res.pause_gameplay = false
	DialogPlayer.play(script_res)
