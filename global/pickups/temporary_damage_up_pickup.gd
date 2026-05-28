# global/pickups/temporary_damage_up_pickup.gd
class_name TemporaryDamageUpPickup
extends PickupBase

const DAMAGE_BONUS: float = 0.5
const DURATION_SEC: float = 15.0

func _collect(player: PlayerBase) -> void:
	player.apply_temp_damage_buff(DAMAGE_BONUS, DURATION_SEC)

func _get_dialog_text() -> String:
	return "Weapon output overcharged!"
