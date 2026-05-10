## Reusable weapon list column. Call [method populate] before querying
## [method get_count] or setting cursor/selection state.
class_name WeaponFrame
extends Node2D

const _WEAPON_OPTION_SCENE: PackedScene = preload("res://dialog/ui/playermenu/weapon_option.tscn")
const _ROW_HEIGHT: float = 30.0
const MAX_ITEMS: int = 8

## Local-space origin for the first list item relative to this node's position.
## Tune in the Inspector if items don't align with the frame background.
@export var item_origin: Vector2 = Vector2(0.0, -45.0)

var _options: Array[WeaponOption] = []

## Populate the list from parallel arrays of names and icons.
## Excess items beyond MAX_ITEMS are silently ignored.
## If [param icons] is shorter than [param display_names], missing icons
## default to null (no texture). Clears any previously created options first.
func populate(display_names: Array[String], icons: Array[Texture2D]) -> void:
	for opt: WeaponOption in _options:
		remove_child(opt)
		opt.queue_free()
	_options.clear()

	var count: int = mini(display_names.size(), MAX_ITEMS)
	for i: int in count:
		var opt := _WEAPON_OPTION_SCENE.instantiate() as WeaponOption
		assert(opt != null, "weapon_option.tscn root must be a WeaponOption")
		add_child(opt)
		opt.position = item_origin + Vector2(0.0, i * _ROW_HEIGHT)
		var icon: Texture2D = icons[i] if i < icons.size() else null
		opt.configure(display_names[i], icon)
		_options.append(opt)

## Move the cursor highlight to the item at idx. Pass -1 to clear all.
func set_cursor(idx: int) -> void:
	for i: int in _options.size():
		_options[i].set_cursor(i == idx)

## Mark the item at idx as selected (pink). Pass -1 to clear all.
func set_selected(idx: int) -> void:
	for i: int in _options.size():
		_options[i].set_selected(i == idx)

## Number of items currently in this frame.
func get_count() -> int:
	return _options.size()
