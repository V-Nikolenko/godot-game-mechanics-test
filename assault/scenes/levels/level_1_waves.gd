## Level 1 — defines all 18 waves inline and builds LevelResource on the fly.
extends Node

@export var wave_manager: WaveManager

func _ready() -> void:
	print("[LEVEL] Level 1 started — building wave data")
	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate())

	var builder := WaveBuilder.new()
	var L := builder.ARC_LEFT
	var R := builder.ARC_RIGHT
	var DURATION := builder.EXIT_DURATION

	var waves: Array = [
		builder.wave(2.0, [
			builder.spawn_entry(builder.FIGHTER, Vector2(0, -180), builder.straight(100), 0.0, builder.EXIT_SCREEN, builder.v_formation(5)),
		]),
		builder.wave(3.0, [
			builder.spawn_entry(builder.ALLY, Vector2( 45, 180), builder.straight(130, PI), 0.0),
			builder.spawn_entry(builder.ALLY, Vector2(-35, 180), builder.straight(170, PI), 0.3),
		]),
		builder.wave(6.0, [
			builder.spawn_entry(builder.FIGHTER, Vector2(180, -28), builder.straight(160, -PI/3.6), 0.0, builder.EXIT_SCREEN, builder.diagonal_formation(5, 40, 14)),
		]),
		#builder.wave(7.0, [
			#builder.spawn_entry(builder.ALLY, Vector2(-180, 180), builder.straight(130, PI), 0.0),
		#]),
		#builder.wave(12.0, [
			#builder.spawn_entry(builder.FIGHTER, Vector2(-40, -180), builder.sequence([builder.straight(60, 0.0, 2.0), builder.hold(1.5), builder.straight(150, -PI/2)]), 0.0),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 40, -180), builder.sequence([builder.straight(60, 0.0, 2.0), builder.hold(1.5), builder.straight(150,  PI/2)]), 0.2),
		#]),
		#builder.wave(22.0, [
			#builder.spawn_entry(builder.DRONE, Vector2(-50, -180), builder.sine(140, 45), 0.0),
			#builder.spawn_entry(builder.DRONE, Vector2(  0, -180), builder.sine(140, 45), 0.0),
			#builder.spawn_entry(builder.DRONE, Vector2( 50, -180), builder.sine(140, 45), 0.0),
			#builder.spawn_entry(builder.DRONE, Vector2( 25, -165), builder.sine(140, 45), 0.2),
		#]),
		#builder.wave(38.0, [
			#builder.spawn_entry(builder.GUNSHIP, Vector2(  0, -180), builder.straight(50),         0.0),
			#builder.spawn_entry(builder.FIGHTER, Vector2(-60,   20), builder.arc(L, 130, 3.5), 0.4, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2(-20,   20), builder.arc(R, 130, 3.5), 0.4, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 20,   20), builder.arc(L, 130, 3.5), 0.4, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 60,   20), builder.arc(R, 130, 3.5), 0.4, DURATION),
		#]),
		#builder.wave(55.0, [
			#builder.spawn_entry(builder.FIGHTER, Vector2(0, 28), builder.straight(110, -PI/4), 0.0, builder.EXIT_SCREEN, builder.diagonal_formation(5, 40, 14)),
		#]),
		#builder.wave(68.0, [
			#builder.spawn_entry(builder.RAM,     Vector2(  0,  0), builder.straight(100),       0.0),
			#builder.spawn_entry(builder.FIGHTER, Vector2(-50, 10), builder.straight(110,  PI/4), 0.3),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 50, 10), builder.straight(110, -PI/4), 0.3),
		#]),
		#builder.wave(76.0, [
			#builder.spawn_entry(builder.ALLY, Vector2(-50, 180), builder.straight(120, PI - 0.25), 0.0),
			#builder.spawn_entry(builder.ALLY, Vector2(  0, 180), builder.straight(140, PI),        0.2),
			#builder.spawn_entry(builder.ALLY, Vector2( 50, 180), builder.straight(120, PI + 0.25), 0.4),
		#]),
		#builder.wave(85.0, [
			#builder.spawn_entry(builder.SNIPER,  Vector2(-320, -20), builder.straight(130,  PI/2), 0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			#builder.spawn_entry(builder.SNIPER,  Vector2( 320,  20), builder.straight(130, -PI/2), 0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			#builder.spawn_entry(builder.FIGHTER, Vector2( -40, -180), builder.straight(100,  PI/4), 0.6),
			#builder.spawn_entry(builder.FIGHTER, Vector2(   0,    0), builder.straight(100),        0.6),
			#builder.spawn_entry(builder.FIGHTER, Vector2(  40, -180), builder.straight(100, -PI/4), 0.6),
		#]),
		#builder.wave(103.0, [
			#builder.spawn_entry(builder.BOMBER,  Vector2(-320, -10), builder.straight(80, PI/2),     0.0, builder.EXIT_SCREEN, null, {"direction": 1.0}),
			#builder.spawn_entry(builder.FIGHTER, Vector2( -50,   0), builder.arc(L, 120, 3.8), 0.5, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2(   0, -180), builder.straight(95),           0.5),
			#builder.spawn_entry(builder.FIGHTER, Vector2(  50,   0), builder.arc(R, 120, 3.8), 0.5, DURATION),
		#]),
		#builder.wave(120.0, [
			#builder.spawn_entry(builder.FIGHTER, Vector2(-80,  12), builder.arc(L, 140, 3.5), 0.0, DURATION, builder.diagonal_formation(3,  40, 12, 0.0)),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 80,  12), builder.arc(R, 140, 3.5), 0.0, DURATION, builder.diagonal_formation(3, -40, 12, 0.0)),
			#builder.spawn_entry(builder.DRONE,   Vector2(-30, -180), builder.sine(150, 50),    0.8),
			#builder.spawn_entry(builder.DRONE,   Vector2(  0, -180), builder.sine(150, 50),    0.8),
			#builder.spawn_entry(builder.DRONE,   Vector2( 30, -180), builder.sine(150, 50),    0.8),
		#]),
		#builder.wave(136.0, [
			#builder.spawn_entry(builder.ALLY, Vector2(-60, 180), builder.straight(150, PI - 0.2),  0.00),
			#builder.spawn_entry(builder.ALLY, Vector2(-20, 180), builder.straight(110, PI - 0.05), 0.15),
			#builder.spawn_entry(builder.ALLY, Vector2( 20, 180), builder.straight(110, PI + 0.05), 0.30),
			#builder.spawn_entry(builder.ALLY, Vector2( 60, 180), builder.straight(150, PI + 0.2),  0.45),
		#]),
		#builder.wave(148.0, [
			#builder.spawn_entry(builder.GUNSHIP,  Vector2(-55, -180), builder.straight(50),          0.0),
			#builder.spawn_entry(builder.GUNSHIP,  Vector2( 55, -180), builder.straight(50),          0.0),
			#builder.spawn_entry(builder.RAM,      Vector2(-30,   10), builder.straight(110),         0.6),
			#builder.spawn_entry(builder.RAM,      Vector2( 30,   10), builder.straight(110),         0.6),
			#builder.spawn_entry(builder.FIGHTER,  Vector2(-80,   20), builder.straight(110,  PI/4),  1.0),
			#builder.spawn_entry(builder.FIGHTER,  Vector2(  0,   20), builder.straight(100),         1.0),
			#builder.spawn_entry(builder.FIGHTER,  Vector2( 80,   20), builder.straight(110, -PI/4),  1.0),
		#]),
		#builder.wave(166.0, [
			#builder.spawn_entry(builder.BOMBER,  Vector2(-320, -15), builder.straight(80,  PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction":  1.0}),
			#builder.spawn_entry(builder.BOMBER,  Vector2( 320,  15), builder.straight(80, -PI/2),    0.0, builder.EXIT_SCREEN, null, {"direction": -1.0}),
			#builder.spawn_entry(builder.FIGHTER, Vector2( -40, -180), builder.arc(L, 110, 3.5), 0.3, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2(   0,    0), builder.straight(95),            0.3),
			#builder.spawn_entry(builder.FIGHTER, Vector2(  40, -180), builder.arc(R, 110, 3.5), 0.3, DURATION),
			#builder.spawn_entry(builder.DRONE,   Vector2( -20, -180), builder.sine(150, 55),    0.9),
			#builder.spawn_entry(builder.DRONE,   Vector2(  20, -180), builder.sine(150, 55),    0.9),
		#]),
		#builder.wave(180.0, [
			#builder.spawn_entry(builder.ALLY, Vector2(  0, 180), builder.straight(160, PI),       0.0),
			#builder.spawn_entry(builder.ALLY, Vector2(-40,   0), builder.straight(140, PI - 0.18), 0.2),
			#builder.spawn_entry(builder.ALLY, Vector2( 40,   0), builder.straight(140, PI + 0.18), 0.2),
			#builder.spawn_entry(builder.ALLY, Vector2(-80, 180), builder.straight(125, PI - 0.32), 0.4),
			#builder.spawn_entry(builder.ALLY, Vector2( 80, 180), builder.straight(125, PI + 0.32), 0.4),
		#]),
		#builder.wave(190.0, [
			#builder.spawn_entry(builder.GUNSHIP, Vector2(  0,  0), builder.straight(35),           0.0),
			#builder.spawn_entry(builder.FIGHTER, Vector2(-50, 22), builder.arc(L, 120, 4.0), 0.8, DURATION),
			#builder.spawn_entry(builder.FIGHTER, Vector2(  0, 22), builder.straight(80),            0.8),
			#builder.spawn_entry(builder.FIGHTER, Vector2( 50, 22), builder.arc(R, 120, 4.0), 0.8, DURATION),
		#]),
	]

	var level = builder.level("Level 1", waves)
	wave_manager.load_level(level)
	wave_manager.waves_complete.connect(_on_waves_complete)

func _on_waves_complete() -> void:
	print("[LEVEL] All waves triggered — transitioning in 3 seconds")
	await get_tree().create_timer(3.0).timeout
	print("[LEVEL] Loading Level 2")
	get_tree().change_scene_to_file("res://assault/scenes/levels/level_2.tscn")
