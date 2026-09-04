# global/ui/dialog_system/playermenu/module_list.gd
## Overlay list that shows available modules for one slot.
## Caller: PlayerMenu shows this when Space is pressed in col 2.
## Emits confirmed(module_id) when Space selects an item, or cancelled on Esc/Tab.
class_name ModuleList
extends Node2D

signal confirmed(module_id: StringName)
signal cancelled

const _ITEM_SCENE: PackedScene = preload("res://global/ui/player_menu/module_list_item.tscn")
const _ROW_HEIGHT: float = 36.0
const MAX_ITEMS: int = 8
## Prepended to a locked row's description so the greyed row carries its own call to
## action rather than being a dead end.
const _LOCKED_PREFIX: String = "LOCKED — recover this module's unlocker to install it.\n"

## Local-space origin for the first list item. Tune to align with frame sprite.
@export var item_origin: Vector2 = Vector2(0.0, -100.0)

@onready var _description_lbl: RichTextLabel = $FrameBackground/ModuleDescription

var _items: Array[ModuleListItem] = []
var _ids:   Array[StringName] = []
var _descs: Array[String] = []
## One entry per created item (not per catalogue id) — open() creates
## mini(_ids.size(), MAX_ITEMS) of them, so every read bounds-checks against _locked.size().
var _locked: Array[bool] = []
var _cursor_row: int = 0

func _ready() -> void:
	visible = false

## Show the list populated with modules for the given slot.
## `current_id` is the currently equipped module id (or &"" if none).
func open(slot: StringName, current_id: StringName) -> void:
	_clear()
	var _raw: Array = ShipModuleState.SLOT_MODULES.get(slot, [&""])
	_ids.assign(_raw)
	var count: int = mini(_ids.size(), MAX_ITEMS)
	for i: int in count:
		var item := _ITEM_SCENE.instantiate() as ModuleListItem
		assert(item != null)
		add_child(item)
		item.position = item_origin + Vector2(-63.0, i * _ROW_HEIGHT)
		var id: StringName = _ids[i]
		if id == &"":
			## The "None" row is never locked: ShipModuleState.equip(slot, &"") is always
			## allowed, and this menu is the only way to take a module back out.
			item.configure("", null)
			_locked.append(false)
			_descs.append("Remove installed module.")
		else:
			var locked: bool = not ShipModuleState.is_unlocked(slot, id)
			var mod := _make_module(id)
			item.configure(
				mod.get_display_name() if mod else String(id),
				mod.get_icon() if mod else null,
				locked
			)
			_locked.append(locked)
			var desc: String = mod.get_description() if mod else ""
			_descs.append((_LOCKED_PREFIX + desc) if locked else desc)
		_items.append(item)

	## Initialise cursor on currently equipped item.
	_cursor_row = maxi(0, _ids.find(current_id))
	_refresh_cursor()
	_refresh_selected(current_id)
	visible = true

func close() -> void:
	visible = false
	_clear()

func navigate(delta: int) -> void:
	_cursor_row = clampi(_cursor_row + delta, 0, maxi(_items.size() - 1, 0))
	_refresh_cursor()

func confirm() -> void:
	if _cursor_row >= _ids.size():
		return
	## A locked row is a defined no-op: nothing is emitted and the list stays open, the
	## same as MissionSelectMenu._try_confirm() on a locked mission.
	if _cursor_row < _locked.size() and _locked[_cursor_row]:
		return
	confirmed.emit(_ids[_cursor_row])

func _clear() -> void:
	for item: ModuleListItem in _items:
		remove_child(item)
		item.queue_free()
	_items.clear()
	_ids.clear()
	_descs.clear()
	_locked.clear()

func _refresh_cursor() -> void:
	for i: int in _items.size():
		_items[i].set_cursor(i == _cursor_row)
	if _description_lbl != null and _cursor_row < _descs.size():
		_description_lbl.text = _descs[_cursor_row]

func _refresh_selected(current_id: StringName) -> void:
	for i: int in _items.size():
		_items[i].set_selected(_ids[i] == current_id)

func _make_module(id: StringName) -> ShipModuleBase:
	return ShipModuleBase.create(id)
