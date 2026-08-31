# assault/scenes/gui/ability_chip.gd
class_name AbilityChip
extends Control

## Previously showed the active ability icon and cooldown fill.
## The ability system has been replaced by the ship module system (ShipModuleBase).
## This chip is currently unused — it will be repurposed for module HUD display
## in a future update. For now it stays in the scene but renders nothing.

@onready var _icon: TextureRect = $Icon
@onready var _cooldown_fill: ColorRect = $CooldownFill
@onready var _label: Label = $Label

func _ready() -> void:
	## Hide all child elements until this chip is repurposed for modules.
	_icon.visible = false
	_cooldown_fill.visible = false
	_label.visible = false
