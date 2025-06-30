class_name Overheat
extends Node

signal overheat(overheat_percentage: float)

@export_category("Overheat Configuration")
@export var heat_limit: float = 20.0
@export var cooldown_time: float = 10.0

var heat: float = 0.0
@onready var overheat_timer: Timer = Timer.new()

func _ready() -> void:
	overheat_timer.wait_time = 0.1
	overheat_timer.autostart = true
	overheat_timer.one_shot = false
	overheat_timer.timeout.connect(_on_overheat_timer_timeout)
	add_child(overheat_timer)

func increase_heat(heat_amount: float) -> void:
	heat = min(heat + heat_amount, heat_limit)
	_emit_heat()

func _on_overheat_timer_timeout() -> void:
	if heat > 0.0:
		var dissipation_rate = heat_limit / cooldown_time
		heat = max(heat - dissipation_rate * overheat_timer.wait_time, 0.0)
		_emit_heat()

func _emit_heat() -> void:
	var overheat_percentage = heat / heat_limit * 100
	print("Overheating: " + str(overheat_percentage))
	overheat.emit(overheat_percentage)
