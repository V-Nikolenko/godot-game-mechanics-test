class_name Bomb
extends Area2D

@export var fall_speed: float = 60.0
@export var fuse_time: float = 1.5

var _timer: float = 0.0
var _exploded: bool = false

@onready var hitbox: HitBox = $HitBox

func _ready() -> void:
	hitbox.monitoring = false

func _physics_process(delta: float) -> void:
	if _exploded:
		return
	position.y += fall_speed * delta
	_timer += delta
	if _timer >= fuse_time:
		_explode()

func _explode() -> void:
	_exploded = true
	hitbox.monitoring = true
	await get_tree().create_timer(0.08).timeout
	queue_free()
