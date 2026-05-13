# global/ui/dialog_system/playermenu/player_menu.gd
## Weapon selection menu overlay. Tab opens/closes; WASD navigates; Space/F selects.
## Delegates list UI to [WeaponFrame] components. Updates [WeaponState] and [RocketState].
class_name PlayerMenu
extends CanvasLayer

const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

const _WEAPON_ICONS: Dictionary = {
	&"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"long_range":   preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
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

@onready var _main_frame: WeaponFrame = $ShipLayout/MainWeaponFrame
@onready var _sub_frame: WeaponFrame = $ShipLayout/SubWeaponFrame

var _weapon_state: WeaponState = null
var _rocket_state: RocketState = null
var _was_paused_by_us: bool = false

## Cursor position: col 0 = main weapons, col 1 = sub weapons.
var _cursor_col: int = 0
var _cursor_row: int = 0

func _ready() -> void:
	visible = false
	## ALWAYS so _input fires even when SceneTree.paused = true.
	process_mode = Node.PROCESS_MODE_ALWAYS

## Called by hud.gd once the player state nodes are known.
## Pass null for either argument if the state does not exist in this scene.
func connect_states(weapon: WeaponState, rocket: RocketState) -> void:
	_weapon_state = weapon
	_rocket_state = rocket
	_populate_lists()
	_refresh_selection()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_player_menu"):
		_toggle()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event.is_action_pressed("menu_up"):
		_cursor_row = clampi(_cursor_row - 1, 0, maxi(_current_frame().get_count() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		_cursor_row = clampi(_cursor_row + 1, 0, maxi(_current_frame().get_count() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_cursor_col = 0
		_cursor_row = clampi(_cursor_row, 0, maxi(_main_frame.get_count() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cursor_col = 1
		_cursor_row = clampi(_cursor_row, 0, maxi(_sub_frame.get_count() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_confirm"):
		_confirm_selection()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if not visible:
		## Do not open over an already-paused scene (e.g. DialogPlayer active).
		if get_tree().paused:
			return
		visible = true
		get_tree().paused = true
		_was_paused_by_us = true
		_init_cursor()
		_refresh_cursor()
	else:
		visible = false
		if _was_paused_by_us:
			get_tree().paused = false
			_was_paused_by_us = false

## Place the cursor on the currently active weapon/sub-weapon when the menu opens.
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

## Apply cursor highlight to the option at (_cursor_col, _cursor_row),
## clear highlight from all others.
func _refresh_cursor() -> void:
	_main_frame.set_cursor(_cursor_row if _cursor_col == 0 else -1)
	_sub_frame.set_cursor(_cursor_row if _cursor_col == 1 else -1)

## Commit the highlighted option WITHOUT closing the menu.
## The menu is closed only by toggle_player_menu (Tab).
func _confirm_selection() -> void:
	if _cursor_col == 0:
		var ids := UpgradeState.unlocked_ids()
		if _cursor_row < ids.size():
			_on_main_weapon_pressed(ids[_cursor_row])
	else:
		_on_sub_weapon_pressed(_cursor_row)

## Returns the WeaponFrame for the currently focused column.
func _current_frame() -> WeaponFrame:
	return _main_frame if _cursor_col == 0 else _sub_frame

func _populate_lists() -> void:
	## Main weapons — only the ones currently unlocked in UpgradeState.
	var ids := UpgradeState.unlocked_ids()
	var main_names: Array[String] = []
	var main_icons: Array[Texture2D] = []
	for id: StringName in ids:
		var mode := _load_mode(id)
		main_names.append(mode.display_name if mode != null else String(id))
		main_icons.append(_WEAPON_ICONS.get(id, null) as Texture2D)
	_main_frame.populate(main_names, main_icons)

	## Sub weapons — always both options, regardless of unlock state.
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
