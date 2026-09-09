# global/pickups/lore_log_pickup.gd
class_name LoreLogPickup
extends PickupBase

## Grants the next lore-log entry in catalogue order. Anonymous by design — LogState.collect_next()
## decides which entry a collection grants, not this pickup, so the reading order stays
## independent of where in the game world the player finds each one. No @export field: unlike
## ShipModuleUnlockerPickup/WeaponModeUnlockerPickup there is nothing per-instance to configure.

var _collected_id: StringName = &""


func _collect(_player: PlayerBase) -> void:
	_collected_id = LogState.collect_next()


func _get_dialog_text() -> String:
	if _collected_id == &"":
		return ""  # catalogue already exhausted - LogState.collect_next() was a no-op
	var entry := LogState.get_entry(_collected_id)
	if entry == null:
		return "Log recovered."
	return "Log recovered: %s" % entry.title
