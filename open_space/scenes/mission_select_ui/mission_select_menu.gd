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

const _ITEM_SCENE               := preload("res://open_space/scenes/mission_select_ui/mission_list_item.tscn")
## Active/selected point — brighter sprite shown when cursor is here.
const _POINT_TEXTURE_ACTIVE    := preload("res://open_space/assets/sprites/mission_select_ui/menu/menu_mission_select_point.png")
## Inactive/unselected point — dimmer sprite shown for all other points.
const _POINT_TEXTURE_INACTIVE  := preload("res://open_space/assets/sprites/mission_select_ui/menu/menu_mission_select_point_unselected.png")
## X offset from sprite center to the diamond; line endpoints anchor here.
const _POINT_LINE_ANCHOR       := Vector2(-15.0, 0.0)
## Position of the number label inside the right text-box area of the icon.
const _POINT_LABEL_OFFSET      := Vector2(6.0, -4.0)
const _POINT_LABEL_FONT_SIZE   := 5

const _ROW_STRIDE: float = 34.0

const _POINT_NORMAL   := Color.WHITE
const _POINT_SELECTED := Color(1.4, 1.4, 1.0)
const _POINT_LOCKED   := Color(0.45, 0.45, 0.45)

@onready var _background:       Sprite2D = $Background
@onready var _overlay:          Sprite2D = $Overlay
@onready var _planet_map:       Sprite2D = $PlanetMap
@onready var _points_container: Node2D   = $PlanetMap/PointsContainer
@onready var _header:           Node2D   = $Header
@onready var _info_panel:       Node2D   = $InfoPanel
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

## Animation state — originals captured in _ready(), restored on close().
var _open_tween:         Tween   = null
var _orig_map_pos:       Vector2
var _orig_list_pos:      Vector2
var _orig_header_pos:    Vector2
var _orig_info_pos:      Vector2

func _ready() -> void:
	_orig_map_pos    = _planet_map.position
	_orig_list_pos   = _list_container.position
	_orig_header_pos = _header.position
	_orig_info_pos   = _info_panel.position

## Entry point called by MissionTrigger after adding this node to the tree.
func open(config: PlanetConfigResource) -> void:
	_config = config

	_background.texture  = config.background_texture
	_name_label.text     = config.display_name
	_class_label.text    = config.description
	_class_label.add_theme_font_size_override("font_size", config.description_font_size)

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
		## Skip if the destination mission has connect_line disabled.
		if not config.missions[i + 1].connect_line:
			continue
		## Hide line if either endpoint is locked (its point is hidden).
		if _is_locked(config.missions[i]) or _is_locked(config.missions[i + 1]):
			continue
		var a: Vector2 = config.point_positions[i] \
				if i     < config.point_positions.size() else Vector2.ZERO
		var b: Vector2 = config.point_positions[i + 1] \
				if i + 1 < config.point_positions.size() else Vector2.ZERO
		var line := Line2D.new()
		line.width         = _LINE_WIDTH
		line.antialiased   = true
		line.default_color = _LINE_COLOR_UNLOCKED
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
	_animate_open()

func close() -> void:
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()
	## Restore originals so next open() starts clean.
	_planet_map.position    = _orig_map_pos
	_planet_map.scale       = Vector2.ONE
	_list_container.position = _orig_list_pos
	_header.position        = _orig_header_pos
	_info_panel.position    = _orig_info_pos
	offset                  = Vector2.ZERO
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
		var selected: bool = i == _cursor
		var locked: bool   = _is_locked(_config.missions[i])
		_points[i].visible        = not locked
		_point_labels[i].visible  = not locked
		if locked:
			continue
		var color: Color = _POINT_SELECTED if selected else _POINT_NORMAL
		_points[i].texture        = _POINT_TEXTURE_ACTIVE if selected else _POINT_TEXTURE_INACTIVE
		_points[i].modulate       = color
		_point_labels[i].modulate = color
	var m: MissionConfigResource = _config.missions[_cursor]
	_mission_preview.texture = m.mission_image
	_desc_label.text = m.description if not _is_locked(m) \
			else _resolve_locked_description(m)

func _try_confirm() -> void:
	var m: MissionConfigResource = _config.missions[_cursor]
	if _is_locked(m):
		return
	close()
	mission_confirmed.emit(m.scene_path)

func _animate_open() -> void:
	if _open_tween and _open_tween.is_valid():
		_open_tween.kill()

	## ── Set displaced start states ──────────────────────────────────────────
	_planet_map.scale        = Vector2(0.25, 0.25)
	_planet_map.position     = _orig_map_pos
	_list_container.position = _orig_list_pos   + Vector2(-70.0, 0.0)
	_header.position         = _orig_header_pos + Vector2(0.0, -18.0)
	_info_panel.position     = _orig_info_pos   + Vector2(0.0, 14.0)
	offset                   = Vector2.ZERO

	_open_tween = create_tween().set_parallel(true)

	## Planet zooms in with springy overshoot — the hero element.
	_open_tween.tween_property(_planet_map, "scale", Vector2.ONE, 0.55) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	## Header slides down.
	_open_tween.tween_property(_header, "position", _orig_header_pos, 0.28) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## List slides in from the left, slightly delayed.
	_open_tween.tween_property(_list_container, "position", _orig_list_pos, 0.32) \
			.set_delay(0.07).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## Info panel rises from below, delayed a bit more.
	_open_tween.tween_property(_info_panel, "position", _orig_info_pos, 0.30) \
			.set_delay(0.10).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

	## Quick screen punch: knock right then settle — runs on the CanvasLayer offset.
	var shake_tween := create_tween()
	shake_tween.tween_property(self, "offset", Vector2(7.0, 0.0),  0.04)
	shake_tween.tween_property(self, "offset", Vector2(-4.0, 0.0), 0.06)
	shake_tween.tween_property(self, "offset", Vector2(2.0, 0.0),  0.05)
	shake_tween.tween_property(self, "offset", Vector2.ZERO,       0.05)

func _is_locked(m: MissionConfigResource) -> bool:
	# Gate 1: previous-mission completion (existing behaviour).
	if m.required_mission != 0 \
			and not MissionState.is_complete(m.required_mission):
		return true
	# Gate 2: high-score threshold on another mission (composes via AND).
	if m.required_score_mission != 0 \
			and MissionState.get_high_score(m.required_score_mission) < m.required_score:
		return true
	return false


## Returns the info-panel description shown for a locked mission.
##
## Priority:
##   1. Custom `locked_description` on the mission (designer-authored).
##   2. Auto-generated message based on which gate is failing.
##
## The auto path describes ALL failing gates, joined together, so a mission
## locked behind both completion AND score states both requirements.
func _resolve_locked_description(m: MissionConfigResource) -> String:
	if not m.locked_description.is_empty():
		return m.locked_description

	var reasons: PackedStringArray = []
	if m.required_mission != 0 \
			and not MissionState.is_complete(m.required_mission):
		var prereq_name: String = _mission_name_for_number(m.required_mission)
		if prereq_name.is_empty():
			reasons.append("Complete the previous mission to unlock.")
		else:
			reasons.append("Complete %s to unlock." % prereq_name)
	if m.required_score_mission != 0 \
			and MissionState.get_high_score(m.required_score_mission) < m.required_score:
		var score_mission_name: String = _mission_name_for_number(m.required_score_mission)
		if score_mission_name.is_empty():
			reasons.append("Reach %d points to unlock." % m.required_score)
		else:
			reasons.append("Reach %d on %s to unlock." % [m.required_score, score_mission_name])
	if reasons.is_empty():
		return "Locked."
	return "\n".join(reasons)


## Looks up a mission's display_name by its mission_number within the current
## hub config. Returns empty string if not found (e.g. cross-planet reference).
func _mission_name_for_number(num: int) -> String:
	if not _config:
		return ""
	for entry: MissionConfigResource in _config.missions:
		if entry.mission_number == num:
			return entry.display_name
	return ""
