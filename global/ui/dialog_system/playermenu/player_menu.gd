# global/ui/dialog_system/playermenu/player_menu.gd
## Weapon + ship-module selection menu overlay.
## Tab opens/closes; WASD navigates; Space/F selects.
## Col 0 = main weapons, Col 1 = sub-weapons, Col 2 = ship modules.
## In col 2, Space opens the ModuleList overlay for the hovered slot.
class_name PlayerMenu
extends CanvasLayer

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

const _WEAPON_ICONS: Dictionary = {
	&"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"piercing":     preload("res://assault/assets/sprites/ui/icon_ship_weapon_pierce.png"),
	&"spread":       preload("res://assault/assets/sprites/ui/icon_ship_weapon_spread.png"),
	&"gatling":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_gatling.png"),
	&"mining_laser": preload("res://assault/assets/sprites/ui/icon_ship_weapon_mining_laser.png"),
}

const _SUB_WEAPON_ICONS: Array[Texture2D] = [
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_missiles_barage.png"),
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_homming_misile.png"),
]
const _SUB_WEAPON_NAMES: Array[String] = ["Missiles Barrage", "Homing Missile"]

@onready var _main_frame:    WeaponFrame      = $ShipLayout/MainWeaponFrame
@onready var _sub_frame:     WeaponFrame      = $ShipLayout/SubWeaponFrame
@onready var _modules_panel: ShipModulesPanel = $ShipLayout/ShipModulesPanel
@onready var _module_list:   ModuleList       = $ModuleList

var _weapon_state: WeaponState  = null
var _rocket_state: RocketState  = null
var _was_paused_by_us: bool     = false

## Col 0 = main weapons, 1 = sub weapons, 2 = ship modules.
var _cursor_col: int = 0
var _cursor_row: int = 0

## True while the module detail list is open.
var _module_list_open: bool = false

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_module_list.confirmed.connect(_on_module_confirmed)
	_module_list.cancelled.connect(_on_module_cancelled)

func connect_states(weapon: WeaponState, rocket: RocketState) -> void:
	_weapon_state = weapon
	_rocket_state = rocket
	_populate_lists()
	_refresh_selection()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_player_menu"):
		if _module_list_open:
			_close_module_list()
		else:
			_toggle()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	## Esc while module list is open → close list, return to modules panel.
	if _module_list_open:
		if event.is_action_pressed("ui_cancel"):
			_close_module_list()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_up"):
			_module_list.navigate(-1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_down"):
			_module_list.navigate(1)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("menu_confirm"):
			_module_list.confirm()
			get_viewport().set_input_as_handled()
		return  ## All other input blocked while list open.

	if event.is_action_pressed("menu_up"):
		_cursor_row = clampi(_cursor_row - 1, 0, maxi(_current_max_row(), 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_cursor_row = clampi(_cursor_row + 1, 0, maxi(_current_max_row(), 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_cursor_col = maxi(0, _cursor_col - 1)
		_cursor_row = clampi(_cursor_row, 0, maxi(_current_max_row(), 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cursor_col = mini(2, _cursor_col + 1)
		_cursor_row = clampi(_cursor_row, 0, maxi(_current_max_row(), 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		_confirm_selection()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if not visible:
		if get_tree().paused:
			return
		visible = true
		get_tree().paused = true
		_was_paused_by_us = true
		_modules_panel.refresh_equipped()
		_init_cursor()
		_refresh_cursor()
	else:
		visible = false
		if _was_paused_by_us:
			get_tree().paused = false
			_was_paused_by_us = false

func _init_cursor() -> void:
	var ids := UpgradeState.unlocked_ids()
	if ids.is_empty():
		_cursor_col = 0
		_cursor_row = 0
		return
	var active_id: StringName = &""
	if _weapon_state != null:
		active_id = _weapon_state.get_active_id()
	var found_row: int = 0
	for i: int in ids.size():
		if ids[i] == active_id:
			found_row = i
			break
	_cursor_col = 0
	_cursor_row = found_row

## Max selectable row index for the current column.
func _current_max_row() -> int:
	match _cursor_col:
		0: return maxi(_main_frame.get_count() - 1, 0)
		1: return maxi(_sub_frame.get_count() - 1, 0)
		2: return maxi(_modules_panel.get_slot_count() - 1, 0)
		_: return 0

func _refresh_cursor() -> void:
	_main_frame.set_cursor(_cursor_row if _cursor_col == 0 else -1)
	_sub_frame.set_cursor(_cursor_row if _cursor_col == 1 else -1)
	_modules_panel.set_cursor(_cursor_row if _cursor_col == 2 else -1)

func _confirm_selection() -> void:
	match _cursor_col:
		0:
			var ids := UpgradeState.unlocked_ids()
			if _cursor_row < ids.size():
				_on_main_weapon_pressed(ids[_cursor_row])
		1:
			_on_sub_weapon_pressed(_cursor_row)
		2:
			_open_module_list()

func _open_module_list() -> void:
	var slot: StringName = ShipModuleState.SLOTS[_cursor_row]
	var current_id: StringName = ShipModuleState.get_equipped(slot)
	## Hide weapon frames while module list is showing.
	_main_frame.visible = false
	_sub_frame.visible = false
	_module_list.open(slot, current_id)
	_module_list_open = true

func _close_module_list() -> void:
	_module_list.close()
	_main_frame.visible = true
	_sub_frame.visible = true
	_module_list_open = false

func _on_module_confirmed(module_id: StringName) -> void:
	var slot: StringName = ShipModuleState.SLOTS[_cursor_row]
	ShipModuleState.equip(slot, module_id)
	_modules_panel.refresh_equipped()
	_close_module_list()

func _on_module_cancelled() -> void:
	_close_module_list()

func _populate_lists() -> void:
	var ids := UpgradeState.unlocked_ids()
	var main_names: Array[String] = []
	var main_icons: Array[Texture2D] = []
	for id: StringName in ids:
		var mode := _load_mode(id)
		main_names.append(mode.display_name if mode != null else String(id))
		main_icons.append(_WEAPON_ICONS.get(id, null) as Texture2D)
	_main_frame.populate(main_names, main_icons)
	_sub_frame.populate(_SUB_WEAPON_NAMES, _SUB_WEAPON_ICONS)

func _load_mode(id: StringName) -> WeaponModeResource:
	var path := _MODES_DIR + String(id) + ".tres"
	if ResourceLoader.exists(path):
		return load(path) as WeaponModeResource
	return null

func _refresh_selection() -> void:
	var active_id: StringName = &""
	if _weapon_state != null:
		active_id = _weapon_state.get_active_id()
	var ids := UpgradeState.unlocked_ids()
	var selected_main: int = -1
	for i: int in ids.size():
		if ids[i] == active_id:
			selected_main = i
			break
	_main_frame.set_selected(selected_main)

	var active_type: int = -1
	if _rocket_state != null:
		active_type = _rocket_state.get_type()
	_sub_frame.set_selected(active_type)

func _on_main_weapon_pressed(id: StringName) -> void:
	if _weapon_state != null:
		_weapon_state.select_weapon(id)
	_refresh_selection()

func _on_sub_weapon_pressed(type: int) -> void:
	if _rocket_state != null:
		_rocket_state.select_sub_weapon(type)
	_refresh_selection()
