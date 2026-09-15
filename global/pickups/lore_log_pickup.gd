# global/pickups/lore_log_pickup.gd
class_name LoreLogPickup
extends PickupBase

## No @export field — LogState's model is deliberately anonymous: collect_next() grants
## whichever catalogue entry has the lowest sequence and isn't collected yet, regardless of
## where in the world it was found, so there is nothing here for a level designer to configure.

var _collected_id: StringName = &""


func _collect(_player: PlayerBase) -> void:
	_collected_id = LogState.collect_next()


func _get_dialog_text() -> String:
	if _collected_id == &"":
		return ""  # nothing left in the catalogue - LogState.collect_next() was a no-op
	var entry := LogState.get_entry(_collected_id)
	if entry == null:
		return "Log recovered."
	return "Log recovered: %s" % entry.title
