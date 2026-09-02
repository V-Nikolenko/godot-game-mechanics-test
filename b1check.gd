extends SceneTree

func _initialize() -> void:
	var container := Node2D.new()
	root.add_child(container)
	var station := (load("res://assault/scenes/enemies/space_station/space_station.tscn") as PackedScene).instantiate()
	# simulate the plan: author a BulletPool as a direct child of SpaceStation
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	pool.bullet_scene = load("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")
	pool.pool_size = 48
	station.add_child(pool)          # done BEFORE the station enters the tree = what a .tscn does
	pool.owner = station
	container.add_child(station)
	print("pool _container == container? ", pool._container == container)
	print("pool _container name: ", pool._container)
	print("idle count: ", pool._idle.size())
	station.global_position = Vector2(640, 180)
	var b = pool.acquire(Vector2(640, 300))
	print("acquired: ", b, " parent=", b.get_parent(), " container children=", container.get_child_count())
	# station.gd HitBox loop sanity
	print("collision_damage on hitbox ok; station children:")
	for c in station.get_children():
		print("  ", c.name, " ", c.get_class())
	quit()
