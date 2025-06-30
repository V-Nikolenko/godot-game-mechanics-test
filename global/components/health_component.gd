class_name Health
extends Node

signal amount_changed

@export_category("Health")
@export var max_health: int = 100
@export var current_health: int = 100

@export_category("Invincibility")
@export var invincibility_frames_enabled: bool = false
@export var invincibility_time_in_sec: float = 0.5

@onready var invincibility_timer: Timer = Timer.new()

func _ready() -> void:
	current_health = clamp(current_health, 0, max_health)

	invincibility_timer.one_shot = true
	invincibility_timer.timeout.connect(_on_invincibility_timeout)
       add_child(invincibility_timer)


func increase(amount: int) -> void:
	var changed_health = clamp(current_health + amount, 0, max_health)
	set_health(changed_health)


func decrease(amount: int) -> void:
	if !invincibility_timer.is_stopped():
		return

	var changed_health = clamp(current_health - amount, 0, max_health)
	set_health(changed_health)
	if invincibility_frames_enabled:
		_start_invincibility()


func set_health(changed_health: int) -> void:
	current_health = changed_health
	amount_changed.emit(current_health)


func _start_invincibility() -> void:
	invincibility_timer.start(invincibility_time_in_sec)


func _on_invincibility_timeout() -> void:
	pass
