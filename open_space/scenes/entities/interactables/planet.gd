# open_space/scenes/entities/interactables/planet.gd
class_name Planet
extends Area2D

## Mission-select hub planet. The missions array is populated at runtime
## by the parent level (sector_hub.gd). When the player enters the Area2D
## overlap and holds [E] on an unlocked mission, the arc fills and the
## scene transitions to that mission's scene_path.

@export var arc_radius: float = 100.0
@export var hold_duration_sec: float = 1.2

## Injected by sector_hub.gd after the scene tree is ready.
var missions: Array[MissionConfigResource] = []

@onready var mission_label: Label = $MissionLabel

var _player_in_range: bool = false
var _selected_index: int = 0
var _hold_time: float = 0.0
var _launching: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	mission_label.visible = false

func _process(delta: float) -> void:
	if _launching or missions.is_empty():
		return

	if not _player_in_range:
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()
		return

	_handle_navigation()
	_handle_hold(delta)

func _handle_navigation() -> void:
	var changed := false
	if Input.is_action_just_pressed("move_up"):
		_selected_index = wrapi(_selected_index - 1, 0, missions.size())
		changed = true
	if Input.is_action_just_pressed("move_down"):
		_selected_index = wrapi(_selected_index + 1, 0, missions.size())
		changed = true
	if changed:
		_hold_time = 0.0
		_refresh_display()
		queue_redraw()

func _handle_hold(delta: float) -> void:
	var mission: MissionConfigResource = missions[_selected_index]
	if _is_locked(mission):
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()
		return

	if Input.is_action_pressed("interact"):
		_hold_time = min(_hold_time + delta, hold_duration_sec)
		queue_redraw()
		if _hold_time >= hold_duration_sec:
			_start_launch(mission)
	else:
		if _hold_time > 0.0:
			_hold_time = 0.0
			queue_redraw()

func _draw() -> void:
	if not _player_in_range or missions.is_empty():
		return

	var mission: MissionConfigResource = missions[_selected_index]
	var locked := _is_locked(mission)

	# Background ring (full circle)
	draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, -PI / 2.0 + TAU,
			64, Color(1.0, 1.0, 1.0, 0.18), 4.0, true)

	# Fill arc clockwise from top
	if _hold_time > 0.0 and not locked:
		var progress := _hold_time / hold_duration_sec
		var end_angle := -PI / 2.0 + TAU * progress
		draw_arc(Vector2.ZERO, arc_radius, -PI / 2.0, end_angle,
				64, Color(0.2, 0.85, 1.0, 0.95), 6.0, true)

func _is_locked(mission: MissionConfigResource) -> bool:
	if mission.required_mission.is_empty():
		return false
	return not MissionState.is_complete(mission.required_mission)

func _refresh_display() -> void:
	if missions.is_empty():
		mission_label.text = ""
		return

	var lines: PackedStringArray = []
	for i: int in missions.size():
		var m: MissionConfigResource = missions[i]
		var prefix := "> " if i == _selected_index else "  "
		var stars := _stars_text(MissionState.get_stars(m.mission_id))
		var status := ""
		if _is_locked(m):
			status = "  [LOCKED]"
		elif MissionState.is_complete(m.mission_id):
			status = "  [DONE]"
		lines.append("%s%s  %s%s" % [prefix, m.display_name, stars, status])

	var selected: MissionConfigResource = missions[_selected_index]
	if _is_locked(selected):
		lines.append("   (Complete Assault first)")
	else:
		lines.append("   Hold [E] to launch")

	mission_label.text = "\n".join(lines)

func _stars_text(stars: int) -> String:
	return "★".repeat(stars) + "☆".repeat(3 - stars)

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	_selected_index = 0
	_hold_time = 0.0
	mission_label.visible = true
	_refresh_display()
	queue_redraw()

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = false
	mission_label.visible = false
	_hold_time = 0.0
	_launching = false
	queue_redraw()

func _start_launch(mission: MissionConfigResource) -> void:
	_launching = true
	get_tree().change_scene_to_file(mission.scene_path)
