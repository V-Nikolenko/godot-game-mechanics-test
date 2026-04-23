class_name KamikazeDrone
extends BaseEnemy

@export var config: DroneConfig = load("res://assault/scenes/enemies/kamikaze_drone/drone_config.tres")

@export var speed: float = 140.0

var _direction: Vector2

func _ready() -> void:
	super._ready()
	add_to_group("enemies")

	if config:
		health.max_health = config.max_health
		health.current_health = config.max_health
		speed = config.movement_speed

	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		_direction = ((players[0] as Node2D).global_position - global_position).normalized()
	else:
		_direction = Vector2(0, 1)
	# drone.png naturally faces UP, so offset by +PI/2 to align with _direction.
	rotation = _direction.angle() + PI / 2

func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_check_off_screen()

# Override so the contact HitBox also monitors the player HurtBox layer,
# letting the drone detect the hit and trigger death through the health system.
func _add_contact_hitbox() -> void:
	var col := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if not col:
		return
	var hb := HitBox.new()
	hb.collision_layer = 256
	hb.collision_mask  = 128   # player HurtBox layer — fires area_entered on contact
	hb.damage = 30
	var shape_node := CollisionShape2D.new()
	shape_node.shape = col.shape
	hb.add_child(shape_node)
	hb.area_entered.connect(_on_contact_hit)
	add_child(hb)

func _on_contact_hit(_area: Area2D) -> void:
	# Guard against the signal firing twice before queue_free is processed.
	if health.current_health > 0:
		health.set_health(0)

func _check_off_screen() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return
	var bottom := cam.global_position.y + viewport_size.y * 0.5 + 60.0
	if global_position.y > bottom:
		print("[Enemy] KamikazeDrone DESPAWNED (off-screen) at position %.0f, %.0f" % [global_position.x, global_position.y])
		queue_free()
