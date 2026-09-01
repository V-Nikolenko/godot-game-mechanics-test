extends GutTest

const LASER: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")

var _hits: Array = []

func _make_hurtbox(pos: Vector2) -> HurtBox:
	var hb := HurtBox.new()
	hb.collision_layer = 128
	hb.collision_mask = 0
	hb.monitoring = false
	hb.monitorable = true
	var cs := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(32, 32)
	cs.shape = rect
	hb.add_child(cs)
	hb.global_position = pos
	return hb

func test_spike() -> void:
	var hb := _make_hurtbox(Vector2(0, 300))
	add_child_autofree(hb)
	hb.received_damage.connect(func(d): _hits.append(d))

	var laser := LASER.instantiate() as LaserRay
	laser.auto_start = false
	laser.warn_duration = 0.5
	laser.active_duration = 0.0
	laser.segment_count = 6
	add_child_autofree(laser)
	laser.global_position = Vector2.ZERO
	laser.start()

	gut.p("t=0 lethal=%s hits=%s" % [laser.is_lethal_now(), _hits.size()])
	await wait_seconds(0.4)
	gut.p("t=0.4 lethal=%s hits=%s" % [laser.is_lethal_now(), _hits.size()])
	assert_eq(_hits.size(), 0, "no damage during warn")
	await wait_seconds(1.2)
	gut.p("t=1.6 lethal=%s hits=%s" % [laser.is_lethal_now(), _hits.size()])
	await wait_seconds(1.5)
	gut.p("t=3.1 lethal=%s hits=%s" % [laser.is_lethal_now(), _hits.size()])
	assert_gt(_hits.size(), 0, "damage after going live")
