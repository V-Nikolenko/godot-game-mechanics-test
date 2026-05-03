extends Resource
class_name PlayerUpgradeLoadout

@export var applied_upgrades: Array[PlayerUpgrade] = []


func equip_upgrade(upgrade: PlayerUpgrade) -> void:
	if upgrade == null:
		return

	if upgrade is PlayerJumpUpgrade:
		_clear_upgrades_of_type(PlayerJumpUpgrade)

	if not applied_upgrades.has(upgrade):
		applied_upgrades.append(upgrade)


func clear_jump_upgrade() -> void:
	_clear_upgrades_of_type(PlayerJumpUpgrade)


func get_jump_upgrade() -> PlayerJumpUpgrade:
	for upgrade in applied_upgrades:
		if upgrade is PlayerJumpUpgrade:
			return upgrade as PlayerJumpUpgrade
	return null


func _clear_upgrades_of_type(base_type: Variant) -> void:
	var filtered: Array[PlayerUpgrade] = []
	for upgrade in applied_upgrades:
		if not is_instance_of(upgrade, base_type):
			filtered.append(upgrade)
	applied_upgrades = filtered
