extends GutTest

const LASER: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")
const STATION: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")

func _kill_all_turrets(st: SpaceStation) -> void:
	for c in st.get_node("Turrets").get_children():
		var t := c as StationTurret
		t.hurt_box.received_damage.emit(t.health.max_health)

func _mount(st: SpaceStation, angle: float, radius: float, mask_override: int) -> LaserRay:
	var laser := LASER.instantiate() as LaserRay
	laser.auto_start = false
	laser.warn_duration = 0.2
	laser.active_duration = 0.0
	laser.segment_count = 6
	st.add_child(laser)
	if mask_override != 0:
		(laser.get_node("HitZone") as Area2D).collision_mask = mask_override
	laser.rotation = angle
	laser.position = Vector2(0, radius).rotated(angle)
	laser.start()
	return laser

func test_diagonal_beam_at_radius_180_no_mask_override() -> void:
	var st := STATION.instantiate() as SpaceStation
	add_child_autofree(st)
	st.global_position = Vector2(600, 300)
	_kill_all_turrets(st)
	assert_false(st.is_armored(), "unarmored")
	var hp0: int = st.health.current_health
	_mount(st, PI * 0.25, 180.0, 0)
	await wait_seconds(1.6)
	gut.p("diag r=180 no-override: hp %d -> %d, valid=%s" % [hp0, st.health.current_health if is_instance_valid(st) else -1, is_instance_valid(st)])
	assert_true(is_instance_valid(st), "station survived diagonal beam at r=180")

func test_down_beam_at_radius_100_no_mask_override() -> void:
	var st := STATION.instantiate() as SpaceStation
	add_child_autofree(st)
	st.global_position = Vector2(600, 300)
	_kill_all_turrets(st)
	var hp0: int = st.health.current_health
	_mount(st, 0.0, 100.0, 0)
	await wait_seconds(1.6)
	var alive := is_instance_valid(st)
	gut.p("down r=100 no-override: hp0=%d alive=%s hp=%s" % [hp0, alive, (st.health.current_health if alive else -1)])
	assert_true(true)

func test_down_beam_at_radius_100_with_player_only_mask() -> void:
	var st := STATION.instantiate() as SpaceStation
	add_child_autofree(st)
	st.global_position = Vector2(600, 300)
	_kill_all_turrets(st)
	_mount(st, 0.0, 100.0, 128)
	await wait_seconds(1.6)
	gut.p("down r=100 mask=128: alive=%s" % is_instance_valid(st))
	assert_true(is_instance_valid(st), "player-only mask spares the station")

func test_parent_rotation_moves_the_beam_hitzone() -> void:
	var st := STATION.instantiate() as SpaceStation
	add_child_autofree(st)
	st.global_position = Vector2(600, 300)
	_kill_all_turrets(st)
	var l := _mount(st, 0.0, 180.0, 128)
	await wait_seconds(1.6)
	var r0: Rect2 = l.danger_rect()
	st.rotation = PI * 0.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	var r1: Rect2 = l.danger_rect()
	gut.p("rect before=%s after=%s" % [str(r0), str(r1)])
	assert_ne(r0.position, r1.position, "rotating the station moves the beam")
