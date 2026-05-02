class_name PatrolDrone
extends CharacterBody2D

signal died

@export var move_speed: float = 60.0
@export var initial_direction: Vector2 = Vector2.RIGHT

@onready var health_component: Health = $HealthComponent
@onready var hurt_box: HurtBox = $HurtBox

var _direction: Vector2 = Vector2.RIGHT

func _ready() -> void:
	add_to_group("enemies")
	_direction = initial_direction.normalized()
	if _direction == Vector2.ZERO:
		_direction = Vector2.RIGHT
	health_component.amount_changed.connect(_on_health_changed)

func _physics_process(_delta: float) -> void:
	velocity = _direction * move_speed
	move_and_slide()

func _on_received_damage(damage: int) -> void:
	health_component.decrease(damage)

func _on_health_changed(current: int) -> void:
	if current == 0:
		died.emit()
		queue_free()
