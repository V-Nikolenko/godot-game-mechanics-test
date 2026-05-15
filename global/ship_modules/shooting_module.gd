# global/ship_modules/shooting_module.gd
class_name ShootingModule
extends ShipModuleBase

## Passive only. Increases fire_rate_multiplier so weapon cooldowns are shorter.
## WeaponState uses: _cooldown = fire_interval / fire_rate_multiplier
const _FIRE_RATE_BONUS: float = 0.65  ## +65% fire rate (1.0 → 1.65).

func get_display_name() -> String: return "Targeting Matrix"
func get_description() -> String:
	return "Passive: precision targeting algorithms increase weapon fire rate by 65%%."
func get_icon() -> Texture2D:
	return preload("res://assault/assets/sprites/ui/icon_ship_module_overclock.png")
func get_slot() -> StringName: return &"weapons"

func apply(player: Node) -> void:
	var current: float = float(player.get("fire_rate_multiplier"))
	player.set("fire_rate_multiplier", current + _FIRE_RATE_BONUS)

func remove(player: Node) -> void:
	var current: float = float(player.get("fire_rate_multiplier"))
	player.set("fire_rate_multiplier", maxf(1.0, current - _FIRE_RATE_BONUS))
