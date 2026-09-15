# global/pickups/pickup_base.gd
class_name PickupBase
extends Area2D

## Base class for all collectible pickups.
## Subclasses override _collect(player) and optionally _get_dialog_text().
## On body_entered: find player, collect, show dialog if text non-empty, queue_free.

## Empty by default — this pickup respawns fresh every time its scene loads, which is what
## health/shield/module pickups already want on a mission restart. Set to a level-unique id to
## make a one-time pickup (e.g. a lore-log placement) remember "already granted" across a scene
## reload, so replaying the mission does not collect it again.
@export var persistent_id: StringName = &""


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if persistent_id != &"" and PickupState.has_collected(persistent_id):
		queue_free()
		return
	var player := body as PlayerBase
	var handled := true
	if player != null:
		_collect(player)
	else:
		handled = _collect_any(body)
	if not handled:
		return
	if persistent_id != &"":
		PickupState.mark_collected(persistent_id)
	var text: String = _get_dialog_text()
	if not text.is_empty():
		_show_notification(text)
	queue_free()


## Override: apply pickup effect to player.
func _collect(_player: PlayerBase) -> void:
	pass


## Fallback hook for a body that is in group "player" but is not a PlayerBase (e.g. the
## infiltration CharacterBody2D). Returning false (the default) means "not for me" — the pickup
## does not consume itself, mark persistent_id, or notify, exactly as if detection had never
## widened. A pickup meant to work against a non-PlayerBase body overrides this and returns true.
func _collect_any(_body: Node2D) -> bool:
	return false


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
