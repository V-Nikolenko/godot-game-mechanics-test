# global/ui/dialog_system/playermenu/ship_modules_panel.gd
## Visual panel for the ship-modules column.
## Shows 4 scheme sprites (overlaid to form the ship) and 4 item frames.
## Call set_cursor(row) to highlight one slot.
## Call refresh_equipped() to update icons and scheme tints from ShipModuleState.
class_name ShipModulesPanel
extends Node2D

## Modulate colours.
const _NORMAL_COLOR  := Color.WHITE            ## Equipped = full colour.
const _EMPTY_COLOR   := Color(0.4, 0.4, 0.4)  ## Nothing equipped = grey.
const _HOVER_COLOR   := Color(0.5, 1.5, 0.5)  ## Cursor on this slot = green (dim R+B, boost G).

## Slot order: 0=cockpit, 1=armor, 2=weapons, 3=engines.
## Must match ShipModuleState.SLOTS order.
@onready var _scheme_cockpit:  Sprite2D = $SchemeCockpit
@onready var _scheme_armor:    Sprite2D = $SchemeArmor
@onready var _scheme_weapons:  Sprite2D = $SchemeWeapons
@onready var _scheme_engine:   Sprite2D = $SchemeEngine

@onready var _item_frame_cockpit:  Sprite2D = $ItemFrameCockpit
@onready var _item_frame_armor:    Sprite2D = $ItemFrameArmor
@onready var _item_frame_weapons:  Sprite2D = $ItemFrameWeapons
@onready var _item_frame_engine:   Sprite2D = $ItemFrameEngine

@onready var _item_icon_cockpit:   Sprite2D = $ItemFrameCockpit/Icon
@onready var _item_icon_armor:     Sprite2D = $ItemFrameArmor/Icon
@onready var _item_icon_weapons:   Sprite2D = $ItemFrameWeapons/Icon
@onready var _item_icon_engine:    Sprite2D = $ItemFrameEngine/Icon

## Module icon textures by module id.
const _MODULE_ICONS: Dictionary = {
	&"armor_plating":   preload("res://assault/assets/sprites/ui/icon_ship_module_armor_increased_plating.png"),
	&"trajectory_calc": preload("res://assault/assets/sprites/ui/icon_ship_module_cockpit_time_slow_down.png"),
	&"warp":            preload("res://assault/assets/sprites/ui/icon_ship_module_engine_warp.png"),
	&"overclock":       preload("res://assault/assets/sprites/ui/icon_ship_module_weapon_oveclock.png"),
}

var _cursor_row: int = -1

func _ready() -> void:
	refresh_equipped()

## Set which slot the cursor is on (-1 = none).
func set_cursor(row: int) -> void:
	_cursor_row = row
	_update_visuals()

## Re-read ShipModuleState and update all scheme + icon visuals.
func refresh_equipped() -> void:
	_update_visuals()

func get_slot_count() -> int:
	return 4

func _update_visuals() -> void:
	var scheme_sprites: Array[Sprite2D] = [_scheme_cockpit, _scheme_armor, _scheme_weapons, _scheme_engine]
	var item_frames: Array[Sprite2D] = [_item_frame_cockpit, _item_frame_armor, _item_frame_weapons, _item_frame_engine]
	var item_icons: Array[Sprite2D] = [_item_icon_cockpit, _item_icon_armor, _item_icon_weapons, _item_icon_engine]

	for i: int in 4:
		var slot: StringName = ShipModuleState.SLOTS[i]
		var equipped_id: StringName = ShipModuleState.get_equipped(slot)
		var has_module: bool = equipped_id != &""
		var is_hovered: bool = i == _cursor_row

		## Scheme sprite colour.
		if is_hovered:
			scheme_sprites[i].modulate = _HOVER_COLOR
		elif has_module:
			scheme_sprites[i].modulate = _NORMAL_COLOR
		else:
			scheme_sprites[i].modulate = _EMPTY_COLOR

		## Item frame colour — yellow on hover, white if equipped, grey if empty.
		if is_hovered:
			item_frames[i].modulate = _HOVER_COLOR
		elif has_module:
			item_frames[i].modulate = _NORMAL_COLOR
		else:
			item_frames[i].modulate = _EMPTY_COLOR

		## Item icon.
		var icon: Texture2D = _MODULE_ICONS.get(equipped_id, null)
		item_icons[i].texture = icon
		item_icons[i].visible = icon != null
