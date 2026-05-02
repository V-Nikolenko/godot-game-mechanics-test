class_name Planet
extends Area2D

## Hold-E to launch a mission. While the player overlaps the Area2D and holds
## the "interact" action, a progress bar fills. When it completes, the scene
## transitions to `target_scene_path`.

signal launch_started
signal launch_progress(ratio: float)  ## 0.0 .. 1.0
signal launch_canceled

@export var target_scene_path: String = "res://assault/scenes/levels/level_1.tscn"
@export var hold_duration_sec: float = 1.0

@onready var prompt_label: Label = $PromptLabel
@onready var progress_bar: ProgressBar = $ProgressBar

var _player_in_range: bool = false
var _hold_time: float = 0.0
var _launching: bool = false

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	prompt_label.visible = false
	progress_bar.visible = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0

func _process(delta: float) -> void:
	if _launching:
		return

	var holding: bool = _player_in_range and Input.is_action_pressed("interact")
	if holding:
		_hold_time += delta
		progress_bar.visible = true
		progress_bar.value = clamp(_hold_time / hold_duration_sec, 0.0, 1.0)
		launch_progress.emit(progress_bar.value)
		if _hold_time >= hold_duration_sec:
			_start_launch()
	else:
		if _hold_time > 0.0:
			launch_canceled.emit()
		_hold_time = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		prompt_label.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		prompt_label.visible = false
		_hold_time = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false

func _start_launch() -> void:
	_launching = true
	launch_started.emit()
	prompt_label.text = "Launching..."
	get_tree().change_scene_to_file(target_scene_path)
