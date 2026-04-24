## Level 2 — defines all 13 waves inline and builds LevelResource on the fly.
extends Node

@export var wave_manager: WaveManager

func _ready() -> void:
	print("[LEVEL] Level 2 started — building wave data")

	var builder := WaveBuilder.new()
	var L := builder.ARC_LEFT
	var R := builder.ARC_RIGHT
	var DURATION := builder.EXIT_DURATION

	var waves: Array = [
		# Wave 1 — t=2.0: Large V formation to open
		builder.wave(2.0, [
			builder.spawn_entry(builder.FIGHTER, Vector2(0, -180), builder.straight(120), 0.0, builder.EXIT_SCREEN, builder.v_formation(7, 45.0, 14.0, 0.08)),
		]),
		# Wave 2 — t=12.0: Sniper crossfire from both sides
		builder.wave(12.0, [
			builder.spawn_entry(builder.SNIPER, Vector2(-320, -10), builder.straight(140, PI/2),  0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2( 320,  10), builder.straight(140, -PI/2), 0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2(-320,  30), builder.straight(140, PI/2),  0.4, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2( 320, -30), builder.straight(140, -PI/2), 0.4, builder.EXIT_SCREEN, null, {"direction": -1.0}),
		]),
		# Wave 3 — t=25.0: Gunship + arc fighter escort
		builder.wave(25.0, [
			builder.spawn_entry(builder.GUNSHIP,  Vector2(  0, -180), builder.straight(55),            0.0),
			builder.spawn_entry(builder.FIGHTER,  Vector2(-70,   15), builder.arc(L, 140, 3.5), 0.4, DURATION),
			builder.spawn_entry(builder.FIGHTER,  Vector2(-30,   15), builder.arc(R, 140, 3.5), 0.4, DURATION),
			builder.spawn_entry(builder.FIGHTER,  Vector2( 30,   15), builder.arc(L, 140, 3.5), 0.4, DURATION),
			builder.spawn_entry(builder.FIGHTER,  Vector2( 70,   15), builder.arc(R, 140, 3.5), 0.4, DURATION),
		]),
		# Wave 4 — t=40.0: Dense sine drone swarm
		builder.wave(40.0, [
			builder.spawn_entry(builder.DRONE, Vector2(-75, -180), builder.sine(150, 50), 0.0),
			builder.spawn_entry(builder.DRONE, Vector2(-40, -180), builder.sine(150, 50), 0.0),
			builder.spawn_entry(builder.DRONE, Vector2(  0, -180), builder.sine(150, 50), 0.0),
			builder.spawn_entry(builder.DRONE, Vector2( 40, -180), builder.sine(150, 50), 0.0),
			builder.spawn_entry(builder.DRONE, Vector2( 75, -180), builder.sine(150, 50), 0.0),
			builder.spawn_entry(builder.DRONE, Vector2(-40, -165), builder.sine(150, 50), 0.25),
			builder.spawn_entry(builder.DRONE, Vector2( 40, -165), builder.sine(150, 50), 0.25),
		]),
		# Wave 4b — t=45.0: Asteroid hazard wave
		builder.wave(45.0, [
			builder.spawn_entry(builder.BIG_ASTEROID, Vector2(-60, -180), builder.straight(90),  0.0),
			builder.spawn_entry(builder.BIG_ASTEROID, Vector2(  0, -180), builder.straight(110), 0.3),
			builder.spawn_entry(builder.BIG_ASTEROID, Vector2( 60, -180), builder.straight(90),  0.6),
		]),
		# Wave 5 — t=55.0: Ram rush + diagonal fighter escort
		builder.wave(55.0, [
			builder.spawn_entry(builder.RAM,     Vector2(-30,   0), builder.straight(130),          0.0),
			builder.spawn_entry(builder.RAM,     Vector2( 30,   0), builder.straight(130),          0.0),
			builder.spawn_entry(builder.FIGHTER, Vector2(-80, -180), builder.straight(110,  PI/4),  0.5),
			builder.spawn_entry(builder.FIGHTER, Vector2(  0, -180), builder.straight(110),         0.5),
			builder.spawn_entry(builder.FIGHTER, Vector2( 80, -180), builder.straight(110, -PI/4),  0.5),
		]),
		# Wave 6 — t=72.0: Bomber run + arc fighters
		builder.wave(72.0, [
			builder.spawn_entry(builder.BOMBER,  Vector2(-320, -15), builder.straight(90,  PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.BOMBER,  Vector2( 320,  15), builder.straight(90, -PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.FIGHTER, Vector2( -50, -180), builder.arc(L, 120, 3.5), 0.5, DURATION),
			builder.spawn_entry(builder.FIGHTER, Vector2(   0,    0), builder.straight(100),            0.5),
			builder.spawn_entry(builder.FIGHTER, Vector2(  50, -180), builder.arc(R, 120, 3.5), 0.5, DURATION),
		]),
		# Wave 7 — t=88.0: Double gunship + drone cover
		builder.wave(88.0, [
			builder.spawn_entry(builder.GUNSHIP, Vector2(-60, -180), builder.straight(55),          0.0),
			builder.spawn_entry(builder.GUNSHIP, Vector2( 60, -180), builder.straight(55),          0.0),
			builder.spawn_entry(builder.DRONE,   Vector2(-30, -180), builder.sine(155, 50),  0.6),
			builder.spawn_entry(builder.DRONE,   Vector2(  0, -180), builder.sine(155, 50),  0.6),
			builder.spawn_entry(builder.DRONE,   Vector2( 30, -180), builder.sine(155, 50),  0.6),
		]),
		# Wave 8 — t=105.0: Pincer + sniper crossfire
		builder.wave(105.0, [
			builder.spawn_entry(builder.FIGHTER, Vector2(-80,  12), builder.arc(L, 150, 3.5), 0.0, DURATION, builder.diagonal_formation(3,  40, 12, 0.0)),
			builder.spawn_entry(builder.FIGHTER, Vector2( 80,  12), builder.arc(R, 150, 3.5), 0.0, DURATION, builder.diagonal_formation(3, -40, 12, 0.0)),
			builder.spawn_entry(builder.SNIPER,  Vector2(-320, -20), builder.straight(140,  PI/2), 0.6, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.SNIPER,  Vector2( 320,  20), builder.straight(140, -PI/2), 0.6, builder.EXIT_SCREEN, null, {"direction": -1.0}),
		]),
		# Wave 9 — t=120.0: Heavy bomber pair + fighter screen
		builder.wave(120.0, [
			builder.spawn_entry(builder.BOMBER,  Vector2(-320, -20), builder.straight(90,  PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.BOMBER,  Vector2( 320,  20), builder.straight(90, -PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.FIGHTER, Vector2(-40, -180), builder.straight(115),          0.5),
			builder.spawn_entry(builder.FIGHTER, Vector2(  0, -180), builder.straight(115),          0.5),
			builder.spawn_entry(builder.FIGHTER, Vector2( 40, -180), builder.straight(115),          0.5),
			builder.spawn_entry(builder.DRONE,   Vector2(-20, -180), builder.sine(160, 55),   1.0),
			builder.spawn_entry(builder.DRONE,   Vector2( 20, -180), builder.sine(160, 55),   1.0),
		]),
		# Wave 10 — t=138.0: Triple ram + arc fighter wave
		builder.wave(138.0, [
			builder.spawn_entry(builder.RAM,     Vector2(-60,   5), builder.straight(140),           0.0),
			builder.spawn_entry(builder.RAM,     Vector2(  0,   0), builder.straight(140),           0.0),
			builder.spawn_entry(builder.RAM,     Vector2( 60,   5), builder.straight(140),           0.0),
			builder.spawn_entry(builder.FIGHTER, Vector2(-90,  20), builder.arc(L, 130, 4.0), 0.5, DURATION),
			builder.spawn_entry(builder.FIGHTER, Vector2( 90,  20), builder.arc(R, 130, 4.0), 0.5, DURATION),
		]),
		# Wave 11 — t=155.0: Quad sniper + dense drone swarm
		builder.wave(155.0, [
			builder.spawn_entry(builder.SNIPER, Vector2(-320, -30), builder.straight(145, PI/2),  0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2( 320,  30), builder.straight(145, -PI/2), 0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2(-320,  10), builder.straight(145, PI/2),  0.5, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.SNIPER, Vector2( 320, -10), builder.straight(145, -PI/2), 0.5, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.DRONE,  Vector2(-50, -180), builder.sine(160, 55), 0.8),
			builder.spawn_entry(builder.DRONE,  Vector2(-20, -180), builder.sine(160, 55), 0.8),
			builder.spawn_entry(builder.DRONE,  Vector2( 20, -180), builder.sine(160, 55), 0.8),
			builder.spawn_entry(builder.DRONE,  Vector2( 50, -180), builder.sine(160, 55), 0.8),
		]),
		# Wave 12 — t=170.0: Double bomber + double gunship
		builder.wave(170.0, [
			builder.spawn_entry(builder.BOMBER,  Vector2(-320, -10), builder.straight(90, PI/2),  0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			builder.spawn_entry(builder.BOMBER,  Vector2( 320,  10), builder.straight(90, -PI/2), 0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			builder.spawn_entry(builder.GUNSHIP, Vector2(-50, -180), builder.straight(55),        0.3),
			builder.spawn_entry(builder.GUNSHIP, Vector2( 50, -180), builder.straight(55),        0.3),
		]),
		# Wave 13 — t=185.0: Final assault — 3 gunships + ram + arc fighters + drones
		builder.wave(185.0, [
			builder.spawn_entry(builder.GUNSHIP,  Vector2(  0, -180), builder.straight(45),            0.0),
			builder.spawn_entry(builder.GUNSHIP,  Vector2(-80, -180), builder.straight(45),            0.0),
			builder.spawn_entry(builder.GUNSHIP,  Vector2( 80, -180), builder.straight(45),            0.0),
			builder.spawn_entry(builder.RAM,      Vector2(-30,   10), builder.straight(145),           0.5),
			builder.spawn_entry(builder.RAM,      Vector2( 30,   10), builder.straight(145),           0.5),
			builder.spawn_entry(builder.FIGHTER,  Vector2(-60,   25), builder.arc(L, 130, 4.0), 1.0, DURATION),
			builder.spawn_entry(builder.FIGHTER,  Vector2(  0,   25), builder.straight(90),            1.0),
			builder.spawn_entry(builder.FIGHTER,  Vector2( 60,   25), builder.arc(R, 130, 4.0), 1.0, DURATION),
			builder.spawn_entry(builder.DRONE,    Vector2(-25, -180), builder.sine(165, 55),    1.5),
			builder.spawn_entry(builder.DRONE,    Vector2( 25, -180), builder.sine(165, 55),    1.5),
		]),
	]

	var level = builder.level("Level 2", waves)
	wave_manager.load_level(level)
	wave_manager.waves_complete.connect(_on_waves_complete)

func _on_waves_complete() -> void:
	print("[LEVEL] All waves triggered — waiting for enemies to clear...")
	var container := get_node("../EnemyContainer") as Node2D
	while container and is_instance_valid(container) and container.get_child_count() > 0:
		await get_tree().create_timer(1.0).timeout
	await get_tree().create_timer(2.0).timeout
	print("[LEVEL] Level 2 complete!")
	# Could add level 3 transition here, or show victory screen
