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

const _ITEM_SCENE    := preload("res://open_space/scenes/gui/mission_list_item.tscn")
const _POINT_TEXTURE := preload("res://assault/assets/sprites/ui/menu_mission_select_point.png")

const _ROW_STRIDE: float = 44.0

const _POINT_NORMAL   := Color(1.0, 1.0, 1.0, 0.5)
const _POINT_SELECTED := Color(0.2, 0.85, 1.0, 1.0)

@onready var _background:       Sprite2D = $Background
@onready var _planet_map:       Sprite2D = $PlanetMap
@onready var _points_container: Node2D   = $PlanetMap/PointsContainer
@onready var _mission_preview:  Sprite2D = $MissionImagePreview
@onready var _list_container:   Node2D   = $ListContainer
@onready var _name_label:       Label    = $Header/NameLabel
@onready var _class_label:      Label    = $Header/ClassLabel
@onready var _threat_label:     Label    = $Header/ThreatLabel
@onready var _desc_label:       Label    = $InfoPanel/DescLabel

var _config:  PlanetConfigResource   = null
var _items:   Array[MissionListItem] = []
var _points:  Array[Sprite2D]        = []
var _cursor:  int = 0

## Entry point called by MissionTrigger after adding this node to the tree.
func open(config: PlanetConfigResource) -> void:
	_config = config

	_background.texture = config.background_texture
	_planet_map.texture = config.sprite_texture
	_name_label.text    = config.display_name
	_class_label.text   = "PLANET CLASS: " + config.planet_class
	_threat_label.text  = "THREAT LEVEL: " + config.threat_level

	## Build list items.
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()

	for i: int in config.missions.size():
		var m: MissionConfigResource = config.missions[i]
		var locked: bool = _is_locked(m)
		var item := _ITEM_SCENE.instantiate() as MissionListItem
		_list_container.add_child(item)
		item.position = Vector2(0.0, i * _ROW_STRIDE)
		item.configure(m, locked)
		_items.append(item)

	## Build planet map points.
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()

	for i: int in config.missions.size():
		var sp := Sprite2D.new()
		sp.texture = _POINT_TEXTURE
		sp.modulate = _POINT_NORMAL
		sp.position = config.point_positions[i] \
				if i < config.point_positions.size() else Vector2.ZERO
		_points_container.add_child(sp)
		_points.append(sp)

	_cursor = 0
	_refresh()
	visible = true
	get_tree().paused = true

func close() -> void:
	get_tree().paused = false
	visible = false
	for item: MissionListItem in _items:
		item.queue_free()
	_items.clear()
	for p: Sprite2D in _points:
		p.queue_free()
	_points.clear()
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
		_points[i].modulate = _POINT_SELECTED if i == _cursor else _POINT_NORMAL
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
