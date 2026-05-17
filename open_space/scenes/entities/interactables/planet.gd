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
@export var arc_radius: float       = 80.0
@export var arc_bg_width: float     = 10.0
@export var arc_fill_width: float   = 10.0
@export var arc_bg_color: Color     = Color(1.0, 1.0, 1.0, 0.18)
@export var arc_fill_color: Color   = Color(0.2, 0.85, 1.0, 0.95)

@export_category("Interaction")
@export var dwell_duration_sec: float = 2.0

## ── Internal ──────────────────────────────────────────────────────────────
const _MENU_SCENE := preload("res://open_space/scenes/gui/mission_select_menu.tscn")

@onready var _sprite: Sprite2D = $Sprite2D

var _player_in_range: bool   = false
var _dwell_time: float        = 0.0
var _menu_open: bool          = false
var _menu: MissionSelectMenu  = null

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
	if _dwell_time >= dwell_duration_sec:
		_open_menu()

func _draw() -> void:
	if Engine.is_editor_hint() or not _player_in_range or _menu_open:
		return
	draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, -PI / 2.0 + TAU,
			64, arc_bg_color, arc_bg_width, true)
	if _dwell_time > 0.0:
		var progress := _dwell_time / dwell_duration_sec
		draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0,
				-PI / 2.0 + TAU * progress,
				64, arc_fill_color, arc_fill_width, true)

func _open_menu() -> void:
	if _menu_open or config == null or config.missions.is_empty():
		return
	_menu_open = true
	_dwell_time = 0.0
	queue_redraw()
	_menu = _MENU_SCENE.instantiate() as MissionSelectMenu
	get_tree().root.add_child(_menu)
	_menu.mission_confirmed.connect(_on_mission_confirmed)
	_menu.cancelled.connect(_on_menu_cancelled)
	_menu.open(config)
	get_tree().paused = true

func _close_menu() -> void:
	if _menu != null and is_instance_valid(_menu):
		_menu.close()
		_menu.queue_free()
		_menu = null
	_menu_open = false
	_dwell_time = 0.0
	queue_redraw()
	get_tree().paused = false

func _on_mission_confirmed(scene_path: String) -> void:
	get_tree().paused = false
	_menu = null
	_menu_open = false
	get_tree().change_scene_to_file(scene_path)

func _on_menu_cancelled() -> void:
	_close_menu()

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_dwell_time = 0.0
	queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	_close_menu()
	queue_redraw()
