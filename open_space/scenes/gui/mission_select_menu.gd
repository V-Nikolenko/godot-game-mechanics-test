# open_space/scenes/gui/mission_select_menu.gd
## Full-screen mission select overlay driven entirely by a PlanetConfigResource.
## Pauses the scene tree while open so the ship cannot move.
## Emits signals back to MissionTrigger.
class_name MissionSelectMenu
extends CanvasLayer

signal mission_confirmed(scene_path: String)
signal cancelled
## Fires whenever the cursor row changes so point highlights can sync.
signal cursor_changed(index: int)

const _ITEM_SCENE               := preload("res://open_space/scenes/gui/mission_list_item.tscn")
## Active/selected point — brighter sprite shown when cursor is here.
const _POINT_TEXTURE_ACTIVE    := preload("res://assault/assets/sprites/ui/menu_mission_select_point.png")
## Inactive/unselected point — dimmer sprite shown for all other points.
const _POINT_TEXTURE_INACTIVE  := preload("res://assault/assets/sprites/ui/menu_mission_select_point_unselected.png")
## X offset from sprite center to the diamond; line endpoints anchor here.
const _POINT_LINE_ANCHOR       := Vector2(-15.0, 0.0)
## Position of the number label inside the right text-box area of the icon.
const _POINT_LABEL_OFFSET      := Vector2(6.0, -4.0)
const _POINT_LABEL_FONT_SIZE   := 5

const _ROW_STRIDE: float = 34.0

const _POINT_NORMAL   := Color.WHITE
const _POINT_SELECTED := Color(1.4, 1.4, 1.0)

@onready var _background:       Sprite2D = $Background
@onready var _planet_map:       Sprite2D = $PlanetMap
@onready var _points_container: Node2D   = $PlanetMap/PointsContainer
@onready var _mission_preview:  Sprite2D = $InfoPanel/MissionImagePreview
@onready var _list_container:   Node2D   = $ListContainer
@onready var _name_label:       Label    = $Header/NameLabel
@onready var _class_label:      Label    = $Header/DescriptionLabel
@onready var _desc_label:       Label    = $InfoPanel/DescLabel

const _LINE_COLOR_UNLOCKED := Color(0.2, 0.85, 1.0)
const _LINE_COLOR_LOCKED   := Color(0.45, 0.45, 0.45)
const _LINE_WIDTH: float   = 1.5

var _config:        PlanetConfigResource   = null
var _items:         Array[MissionListItem] = []
var _points:        Array[Sprite2D]        = []
var _point_labels:  Array[Label]           = []
var _lines:         Array[Line2D]          = []
var _cursor:        int = 0

## Entry point called by MissionTrigger after adding this node to the tree.
func open(config: PlanetConfigResource) -> void:
	_config = config

	_background.texture  = config.background_texture
	_planet_map.texture  = config.sprite_texture
	_name_label.text     = config.display_name
	_class_label.text    = config.description

	## Build list items.
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()

	for i: int in config.missions.size():
		var m: MissionConfigResource = config.missions[i]
		var locked: bool = _is_locked(m)
		var item := _ITEM_SCENE.instantiate() as MissionListItem
		_list_container.add_child(item)
		item.position = Vector2(93, 18 + i * _ROW_STRIDE)
		item.configure(m, locked)
		_items.append(item)

	## Build planet map points and connecting lines.
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
	for l: Line2D in _lines:
		l.queue_free()
	_lines.clear()

	## Lines first so they render beneath the point sprites.
	for i: int in config.missions.size() - 1:
		var a: Vector2 = config.point_positions[i] \
				if i     < config.point_positions.size() else Vector2.ZERO
		var b: Vector2 = config.point_positions[i + 1] \
				if i + 1 < config.point_positions.size() else Vector2.ZERO
		var line := Line2D.new()
		line.width         = _LINE_WIDTH
		line.antialiased   = true
		line.default_color = _LINE_COLOR_UNLOCKED \
				if not _is_locked(config.missions[i + 1]) else _LINE_COLOR_LOCKED
		## Anchor to diamond (left part of icon) instead of sprite center.
		line.add_point(a + _POINT_LINE_ANCHOR)
		line.add_point(b + _POINT_LINE_ANCHOR)
		_points_container.add_child(line)
		_lines.append(line)

	## Point sprites and number labels (labels as siblings so modulate is set independently).
	for l: Label in _point_labels:
		l.queue_free()
	_point_labels.clear()

	for i: int in config.missions.size():
		var pos: Vector2 = config.point_positions[i] \
				if i < config.point_positions.size() else Vector2.ZERO
		var sp := Sprite2D.new()
		sp.texture  = _POINT_TEXTURE_INACTIVE
		sp.modulate = _POINT_NORMAL
		sp.position = pos
		_points_container.add_child(sp)
		_points.append(sp)

		var lbl := Label.new()
		lbl.text     = "%02d" % config.missions[i].mission_number
		lbl.position = pos + _POINT_LABEL_OFFSET
		lbl.add_theme_font_size_override("font_size", _POINT_LABEL_FONT_SIZE)
		lbl.modulate = _POINT_NORMAL
		_points_container.add_child(lbl)
		_point_labels.append(lbl)

	_cursor = 0
	_refresh()
	visible = true

func close() -> void:
	visible = false
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
	for lbl: Label in _point_labels:
		lbl.queue_free()
	_point_labels.clear()
	for l: Line2D in _lines:
		l.queue_free()
	_lines.clear()
	_config = null

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("move_up"):
		_cursor = wrapi(_cursor - 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("move_down"):
		_cursor = wrapi(_cursor + 1, 0, _config.missions.size())
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_try_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		close()
		cancelled.emit()
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	cursor_changed.emit(_cursor)
	for i: int in _items.size():
		_items[i].set_hovered(i == _cursor)
	for i: int in _points.size():
		var selected: bool    = i == _cursor
		_points[i].texture    = _POINT_TEXTURE_ACTIVE if selected else _POINT_TEXTURE_INACTIVE
		_points[i].modulate   = _POINT_SELECTED if selected else _POINT_NORMAL
		_point_labels[i].modulate = _POINT_SELECTED if selected else _POINT_NORMAL
	var m: MissionConfigResource = _config.missions[_cursor]
	_mission_preview.texture = m.mission_image
	_desc_label.text = m.description if not _is_locked(m) \
			else "Complete the previous mission to unlock."

func _try_confirm() -> void:
	var m: MissionConfigResource = _config.missions[_cursor]
	if _is_locked(m):
		return
	close()
	mission_confirmed.emit(m.scene_path)

func _is_locked(m: MissionConfigResource) -> bool:
	return not m.required_mission.is_empty() \
			and not MissionState.is_complete(m.required_mission)
