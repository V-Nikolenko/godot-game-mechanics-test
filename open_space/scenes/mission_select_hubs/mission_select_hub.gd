# open_space/scenes/entities/interactables/planet.gd
## Generic mission trigger — works for planets, space stations, giant ships,
## or any Area2D in the open-space world.
##
## Assign a PlanetConfigResource to `config` in the Inspector.
## The sprite, menu background, missions list, and point positions all
## come from that resource — change the resource, change everything.
##
## @tool lets the sprite update live when you swap the resource in the editor.
@tool
class_name MissionTrigger
extends Area2D

## ── Inspector exports ─────────────────────────────────────────────────────
@export var config: PlanetConfigResource = null:
	set(value):
		config = value
		_apply_sprite()

@export_category("Arc")
## Offset from the node origin to the arc centre. Use this to align the arc
## with the visible planet in the sprite (each sprite may be positioned differently).
@export var arc_offset: Vector2     = Vector2.ZERO:
	set(value):
		arc_offset = value
		queue_redraw()
@export var arc_radius: float       = 75.0:
	set(value):
		arc_radius = value
		queue_redraw()
@export var arc_bg_width: float     = 10.0:
	set(value):
		arc_bg_width = value
		queue_redraw()
@export var arc_fill_width: float   = 10.0:
	set(value):
		arc_fill_width = value
		queue_redraw()
@export var arc_bg_color: Color     = Color(1.0, 1.0, 1.0, 0.18):
	set(value):
		arc_bg_color = value
		queue_redraw()
@export var arc_fill_color: Color   = Color(0.2, 0.85, 1.0, 0.95):
	set(value):
		arc_fill_color = value
		queue_redraw()

@export_category("Interaction")
@export var dwell_duration_sec: float = 2.0

## ── Internal ──────────────────────────────────────────────────────────────
const _MENU_SCENE := preload("res://open_space/scenes/mission_select_ui/mission_select_menu.tscn")

@onready var _sprite: Sprite2D = $Sprite2D

var _player_in_range: bool   = false
var _dwell_time: float        = 0.0
var _menu_open: bool          = false
var _menu: MissionSelectMenu  = null
var _zoom_tween: Tween        = null
var _camera: Camera2D         = null  ## Cached when player enters; used for zoom.

func _ready() -> void:
	_apply_sprite()
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _apply_sprite() -> void:
	if not is_node_ready():
		return
	if _sprite and config and config.sprite_texture:
		_sprite.texture = config.sprite_texture

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or config == null or config.missions.is_empty() or _menu_open:
		return
	if not _player_in_range:
		if _dwell_time > 0.0:
			_dwell_time = 0.0
			queue_redraw()
		return
	_dwell_time = min(_dwell_time + delta, dwell_duration_sec)
	queue_redraw()
	_update_zoom(_dwell_time / dwell_duration_sec)
	if _dwell_time >= dwell_duration_sec:
		_open_menu()

func _draw() -> void:
	if Engine.is_editor_hint() or not _player_in_range or _menu_open:
		return
	draw_arc(arc_offset, arc_radius, -PI / 2.0, -PI / 2.0 + TAU,
			64, arc_bg_color, arc_bg_width, true)
	if _dwell_time > 0.0:
		var progress := _dwell_time / dwell_duration_sec
		draw_arc(arc_offset, arc_radius, -PI / 2.0,
				-PI / 2.0 + TAU * progress,
				64, arc_fill_color, arc_fill_width, true)

## Sets camera zoom and offset proportional to dwell progress (0.0–1.0).
## Called every frame while the player is dwelling; stopped when player leaves.
func _update_zoom(progress: float) -> void:
	if _camera == null:
		return
	var target: Vector2 = global_position + arc_offset
	var dir: Vector2    = (target - _camera.get_parent().global_position).normalized()
	_camera.zoom   = Vector2.ONE.lerp(Vector2(1.2, 1.2), progress)
	_camera.offset = dir * 40.0 * progress

func _open_menu() -> void:
	if _menu_open or config == null or config.missions.is_empty():
		return
	_menu_open = true
	_dwell_time = 0.0
	queue_redraw()
	## Zoom is already at 1.2 — open the menu directly.
	_menu = _MENU_SCENE.instantiate() as MissionSelectMenu
	get_tree().root.add_child(_menu)
	_menu.mission_confirmed.connect(_on_mission_confirmed)
	_menu.cancelled.connect(_on_menu_cancelled)
	_menu.open(config)
	get_tree().paused = true

## Smoothly returns the camera to its default zoom/offset.
func _zoom_out() -> void:
	if _camera == null:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	_zoom_tween = create_tween().set_parallel(true)
	_zoom_tween.tween_property(_camera, "zoom",   Vector2.ONE,  0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_zoom_tween.tween_property(_camera, "offset", Vector2.ZERO, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)

func _close_menu() -> void:
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	if _menu != null and is_instance_valid(_menu):
		_menu.close()
		_menu.queue_free()
		_menu = null
	_menu_open = false
	_dwell_time = 0.0
	queue_redraw()
	get_tree().paused = false
	_zoom_out()

func _on_mission_confirmed(scene_path: String) -> void:
	get_tree().paused = false
	_menu = null
	_menu_open = false
	get_tree().change_scene_to_file(scene_path)

func _on_menu_cancelled() -> void:
	_player_in_range = false
	_close_menu()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_camera = body.get_node_or_null("Camera2D") as Camera2D
	_player_in_range = true
	_dwell_time = 0.0
	queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_close_menu()
	queue_redraw()
