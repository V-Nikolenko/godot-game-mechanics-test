# dialog/ui/playermenu/player_menu.gd
class_name PlayerMenu
extends CanvasLayer

const _WEAPON_OPTION_SCENE: PackedScene = preload("res://dialog/ui/playermenu/weapon_option.tscn")
const _MODES_DIR := "res://assault/scenes/player/weapons/modes/"

## Starting position of the main weapon list (within the weapon selection block).
## Tune these if the items appear in the wrong place.
const _WEAPON_LIST_ORIGIN := Vector2(48.0, 115.0)
const _SUB_LIST_ORIGIN := Vector2(215.0, 115.0)
const _ROW_HEIGHT: float = 30.0

const _WEAPON_ICONS: Dictionary = {
	&"default":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"long_range":   preload("res://assault/assets/sprites/ui/icon_ship_weapon_pierce.png"),
	&"piercing":     preload("res://assault/assets/sprites/ui/icon_ship_weapon_laser.png"),
	&"spread":       preload("res://assault/assets/sprites/ui/icon_ship_weapon_spread.png"),
	&"gatling":      preload("res://assault/assets/sprites/ui/icon_ship_weapon_gatling.png"),
	&"mining_laser": preload("res://assault/assets/sprites/ui/icon_ship_weapon_mining_laser.png"),
}

const _SUB_WEAPON_ICONS: Array[Texture2D] = [
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_missiles_barage.png"),
	preload("res://assault/assets/sprites/ui/icon_ship_subweapon_homming_misile.png"),
]
const _SUB_WEAPON_NAMES: Array[String] = ["Missiles Barrage", "Homing Missile"]

var _weapon_state: WeaponState = null
var _rocket_state: RocketState = null
var _weapon_options: Array[WeaponOption] = []
var _sub_options: Array[WeaponOption] = []
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
		_cursor_row = maxi(_cursor_row - 1, 0)
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_down"):
		var col_size: int = _current_col_options().size()
		_cursor_row = mini(_cursor_row + 1, col_size - 1)
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_left"):
		_cursor_col = 0
		_cursor_row = clampi(_cursor_row, 0, maxi(_weapon_options.size() - 1, 0))
		_refresh_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("menu_right"):
		_cursor_col = 1
		_cursor_row = clampi(_cursor_row, 0, maxi(_sub_options.size() - 1, 0))
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
	for i: int in _weapon_options.size():
		_weapon_options[i].set_cursor(_cursor_col == 0 and i == _cursor_row)
	for j: int in _sub_options.size():
		_sub_options[j].set_cursor(_cursor_col == 1 and j == _cursor_row)

## Commit the highlighted option and close the menu.
func _confirm_selection() -> void:
	if _cursor_col == 0:
		var ids := UpgradeState.unlocked_ids()
		if _cursor_row < ids.size():
			_on_main_weapon_pressed(ids[_cursor_row])
	else:
		_on_sub_weapon_pressed(_cursor_row)
	_toggle()

## Returns the option array for the currently focused column.
func _current_col_options() -> Array[WeaponOption]:
	return _weapon_options if _cursor_col == 0 else _sub_options

func _populate_lists() -> void:
	## Clear previously created options (safe to call more than once).
	for opt: WeaponOption in _weapon_options:
		opt.queue_free()
	_weapon_options.clear()
	for sopt: WeaponOption in _sub_options:
		sopt.queue_free()
	_sub_options.clear()

	## Main weapons — only the ones currently unlocked in UpgradeState.
	var ids := UpgradeState.unlocked_ids()
	for i: int in ids.size():
		var id := ids[i]
		var opt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(opt)
		opt.position = _WEAPON_LIST_ORIGIN + Vector2(0.0, i * _ROW_HEIGHT)
		var icon: Texture2D = _WEAPON_ICONS.get(id, null) as Texture2D
		var mode := _load_mode(id)
		var dname: String = mode.display_name if mode != null else String(id)
		opt.configure(dname, icon)
		_weapon_options.append(opt)

	## Sub weapons — always both options, regardless of unlock state.
	for j: int in _SUB_WEAPON_NAMES.size():
		var sopt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		add_child(sopt)
		sopt.position = _SUB_LIST_ORIGIN + Vector2(0.0, j * _ROW_HEIGHT)
		sopt.configure(_SUB_WEAPON_NAMES[j], _SUB_WEAPON_ICONS[j])
		_sub_options.append(sopt)

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
	for i: int in _weapon_options.size():
		_weapon_options[i].set_selected(i < ids.size() and ids[i] == active_id)

	var active_type: int = 0
	if _rocket_state != null:
		active_type = _rocket_state.get_type()
	for j: int in _sub_options.size():
		_sub_options[j].set_selected(j == active_type)

func _on_main_weapon_pressed(id: StringName) -> void:
	if _weapon_state != null:
		_weapon_state.select_weapon(id)
	_refresh_selection()

func _on_sub_weapon_pressed(type: int) -> void:
	if _rocket_state != null:
		_rocket_state.select_sub_weapon(type)
	_refresh_selection()
