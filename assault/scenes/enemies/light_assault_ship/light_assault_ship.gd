class_name LightAssaultShip
extends BaseEnemy

func _ready() -> void:
	super._ready()
	add_to_group("enemies")
