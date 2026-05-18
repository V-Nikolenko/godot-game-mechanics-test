## Level 1 — defines waves using the fluent WaveBuilder API.
extends Node

@export var wave_manager: WaveManager

func _ready() -> void:
	# Keep this node alive so the _on_waves_complete coroutine can resume
	# even after get_tree().paused = true is called inside it.
	process_mode = PROCESS_MODE_ALWAYS

	print("[LEVEL] Level 1 started — building wave data")
	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate())

	var b := WaveBuilder.new()
	var L := b.LEFT
	var R := b.RIGHT

	var waves: Array = [
		b.wave(2.0, [
			b.fighter().at(-150, -150).move(b.straight(120)).delay(0.5).formation(b.v_formation(5)).shoot_forward(),
		]),

		b.wave(5.0, [
			b.fighter().at(220, -150).move(b.u_sweep(420, 600, 9)).delay(0.5).free_after(10).formation(b.v_formation(3)).shoot_forward(),
		]),

		b.wave(8.0, [
			b.fighter().at(300, -200).move(b.straight(200, -PI/3.6)).formation(b.diagonal_formation(5, 30, 35)).shoot_forward(),
			b.ally().at(  0, 180).move(b.straight(140, PI)).delay(0.2),
		]),

		b.wave(14.0, [
			b.fighter().at(-300, -200).move(b.straight(200, PI/3.6)).formation(b.diagonal_formation(5, -30, 35)).shoot_forward(),
		]),

		b.wave(20.0, [
			b.fighter().at(220, -150).move(b.u_sweep(180, 300, 4)).delay(0.5).free_after(5).shoot_forward(),
			b.fighter().at(-220, -150).move(b.u_sweep(-180, 300, 4)).delay(0.5).free_after(5).shoot_forward()
		]),


		b.wave(22.0, [
			b.drone().at(-50, -180).move(b.sine(140, 45)),
			b.drone().at(  0, -180).move(b.sine(140, 45)),
			b.drone().at( 50, -180).move(b.sine(140, 45)),
			b.drone().at( 25, -165).move(b.sine(140, 45)).delay(0.2),
		]),

		b.wave(26.0, [
			b.big_asteroid().at(-140, -180).move(b.straight(210)),
			b.big_asteroid().at( 190, -180).move(b.straight(260)).delay(0.7),
			b.big_asteroid().at(90, -180).move(b.straight(230)).delay(1),
			b.big_asteroid().at(160, -180).move(b.straight(210)).delay(1.6),
			b.big_asteroid().at(-150, -180).move(b.straight(260)).delay(1.6),
			b.big_asteroid().at(10, -180).move(b.straight(210)).delay(1),
		]),

		#b.wave(28.0, [
			#b.fighter().at(-40, -180).move(b.sequence([b.straight(60, 0.0, 2.0), b.hold(1.5), b.straight(150, -PI/2)])),
			#b.fighter().at( 40, -180).move(b.sequence([b.straight(60, 0.0, 2.0), b.hold(1.5), b.straight(150,  PI/2)])).delay(0.2),
		#]),

		#b.wave(22.0, [
			#b.drone().at(-50, -180).move(b.sine(140, 45)),
			#b.drone().at(  0, -180).move(b.sine(140, 45)),
			#b.drone().at( 50, -180).move(b.sine(140, 45)),
			#b.drone().at( 25, -165).move(b.sine(140, 45)).delay(0.2),
		#]),


		#b.wave(38.0, [
			#b.gunship().at(  0, -180).move(b.straight(50)),
			#b.fighter().at(-60,   20).move(b.arc(L, 130, 3.5)).delay(0.4).free_after(3.5),
			#b.fighter().at(-20,   20).move(b.arc(R, 130, 3.5)).delay(0.4).free_after(3.5),
			#b.fighter().at( 20,   20).move(b.arc(L, 130, 3.5)).delay(0.4).free_after(3.5),
			#b.fighter().at( 60,   20).move(b.arc(R, 130, 3.5)).delay(0.4).free_after(3.5),
		#]),

		#b.wave(55.0, [
			#b.fighter().at(0, 28).move(b.straight(110, -PI/4)).formation(b.diagonal_formation(5, 40, 14)),
		#]),

		#b.wave(68.0, [
			#b.ram()    .at(  0,  0).move(b.straight(100)),
			#b.fighter().at(-50, 10).move(b.straight(110,  PI/4)).delay(0.3),
			#b.fighter().at( 50, 10).move(b.straight(110, -PI/4)).delay(0.3),
		#]),

		#b.wave(76.0, [
			#b.ally().at(-50, 180).move(b.straight(120, PI - 0.25)),
			#b.ally().at(  0, 180).move(b.straight(140, PI))        .delay(0.2),
			#b.ally().at( 50, 180).move(b.straight(120, PI + 0.25)) .delay(0.4),
		#]),

		#b.wave(85.0, [
			#b.sniper().at(-320, -20).move(b.straight(130,  PI/2)).prop("direction",  1.0),
			#b.sniper().at( 320,  20).move(b.straight(130, -PI/2)).prop("direction", -1.0),
			#b.fighter().at(-40, -180).move(b.straight(100,  PI/4)).delay(0.6),
			#b.fighter().at(  0,    0).move(b.straight(100))       .delay(0.6),
			#b.fighter().at( 40, -180).move(b.straight(100, -PI/4)).delay(0.6),
		#]),

		#b.wave(103.0, [
			#b.bomber() .at(-320, -10).move(b.straight(80, PI/2)).prop("direction", 1.0),
			#b.fighter().at( -50,   0).move(b.arc(L, 120, 3.8)).delay(0.5).free_after(3.8),
			#b.fighter().at(   0, -180).move(b.straight(95))    .delay(0.5),
			#b.fighter().at(  50,   0).move(b.arc(R, 120, 3.8)).delay(0.5).free_after(3.8),
		#]),

		#b.wave(120.0, [
			#b.fighter().at(-80, 12).move(b.arc(L, 140, 3.5)).free_after(3.5).formation(b.diagonal_formation(3,  40, 12, 0.0)),
			#b.fighter().at( 80, 12).move(b.arc(R, 140, 3.5)).free_after(3.5).formation(b.diagonal_formation(3, -40, 12, 0.0)),
			#b.drone()  .at(-30, -180).move(b.sine(150, 50)).delay(0.8),
			#b.drone()  .at(  0, -180).move(b.sine(150, 50)).delay(0.8),
			#b.drone()  .at( 30, -180).move(b.sine(150, 50)).delay(0.8),
		#]),

		#b.wave(136.0, [
			#b.ally().at(-60, 180).move(b.straight(150, PI - 0.20)) .delay(0.00),
			#b.ally().at(-20, 180).move(b.straight(110, PI - 0.05)) .delay(0.15),
			#b.ally().at( 20, 180).move(b.straight(110, PI + 0.05)) .delay(0.30),
			#b.ally().at( 60, 180).move(b.straight(150, PI + 0.20)) .delay(0.45),
		#]),

		#b.wave(148.0, [
			#b.gunship().at(-55, -180).move(b.straight(50)),
			#b.gunship().at( 55, -180).move(b.straight(50)),
			#b.ram()    .at(-30,   10).move(b.straight(110)).delay(0.6),
			#b.ram()    .at( 30,   10).move(b.straight(110)).delay(0.6),
			#b.fighter().at(-80,   20).move(b.straight(110,  PI/4)).delay(1.0),
			#b.fighter().at(  0,   20).move(b.straight(100))       .delay(1.0),
			#b.fighter().at( 80,   20).move(b.straight(110, -PI/4)).delay(1.0),
		#]),

		#b.wave(166.0, [
			#b.bomber() .at(-320, -15).move(b.straight(80,  PI/2)).prop("direction",  1.0),
			#b.bomber() .at( 320,  15).move(b.straight(80, -PI/2)).prop("direction", -1.0),
			#b.fighter().at(-40, -180).move(b.arc(L, 110, 3.5)).delay(0.3).free_after(3.5),
			#b.fighter().at(  0,    0).move(b.straight(95))    .delay(0.3),
			#b.fighter().at( 40, -180).move(b.arc(R, 110, 3.5)).delay(0.3).free_after(3.5),
			#b.drone()  .at(-20, -180).move(b.sine(150, 55)).delay(0.9),
			#b.drone()  .at( 20, -180).move(b.sine(150, 55)).delay(0.9),
		#]),

		b.wave(75.0, [
			b.ally().at(  0, 180).move(b.straight(160, PI)),
			b.ally().at(-40,   0).move(b.straight(140, PI - 0.18)).delay(0.2),
			b.ally().at( 40,   0).move(b.straight(140, PI + 0.18)).delay(0.2),
			b.ally().at(-80, 180).move(b.straight(125, PI - 0.32)).delay(0.4),
			b.ally().at( 80, 180).move(b.straight(125, PI + 0.32)).delay(0.4),
		]),

		b.wave(80.0, [
			b.gunship().at(  0, -150).move(b.straight(35)),
			b.fighter().at(-50, -150).move(b.arc(L, 120, 4.0)).delay(0.8).free_after(4.0),
			b.fighter().at(  0, -150).move(b.straight(80))    .delay(0.8),
			b.fighter().at( 50, -150).move(b.arc(R, 120, 4.0)).delay(0.8).free_after(4.0),
		]),
	]

	var level := b.level("Level 1", waves)
	wave_manager.load_level(level)
	wave_manager.waves_complete.connect(_on_waves_complete)

func _on_waves_complete() -> void:
	wave_manager.waves_complete.disconnect(_on_waves_complete)
	print("[LEVEL] All waves triggered — waiting for enemies to clear")

	var container: Node = wave_manager.enemy_container
	var _waited := 0.0
	while container.get_child_count() > 0 and _waited < 5.0:
		await get_tree().create_timer(0.15).timeout
		_waited += 0.15
	print("[LEVEL] Enemy container cleared (%.1fs) — %d remaining" % [_waited, container.get_child_count()])

	await get_tree().create_timer(0.2).timeout

	print("[LEVEL] All enemies cleared — showing post-battle dialog")

	await DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))

	LevelExitCutscene.go_to_hub = MissionState.is_complete(1)
	MissionState.complete(1, 1)

	var hud := get_tree().root.get_node_or_null("HUD")
	if hud:
		hud.queue_free()

	get_tree().change_scene_to_file("res://cutscenes/level_exit/level_exit_cutscene.tscn")
