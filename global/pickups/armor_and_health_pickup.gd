# global/pickups/armor_and_health_pickup.gd
class_name ArmorAndHealthPickup
extends PickupBase

const HEAL_AMOUNT: int = 40

func _collect(player: PlayerBase) -> void:
	if player.health_component:
		player.health_component.increase(HEAL_AMOUNT)
	if player.shield_component:
		player.shield_component.restore_all_permanent()

func _get_dialog_text() -> String:
	return "Hull and shields restored!"
