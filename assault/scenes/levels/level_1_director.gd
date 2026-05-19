## Level1Director — wires four LevelSections for Level 1 and handles level completion.
##
## Section 1 (Deep Space)      — 30 s timed section, fighters/drones, no asteroids.
## Section 2 (Asteroid Belt)   — 30 s timed section, asteroid gauntlet, no enemies.
## Section 3 (Planet Approach) — 110 s cinematic, light enemy harassment.
## Section 4 (Cloud Descent)   — ENEMIES_CLEARED boss-area section with ally escort + gunship wave.
extends Node

@export var director: LevelDirector
@export var wave_manager: WaveManager


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	# ── HUD ──────────────────────────────────────────────────────────────────
	var existing: Node = get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child",
		(preload("res://assault/scenes/gui/hud.tscn") as PackedScene).instantiate())

	# ── Build sections ────────────────────────────────────────────────────────
	var s1:   LevelSection = _build_section_1()
	var s_ast: LevelSection = _build_section_asteroid()
	var s2:   LevelSection = _build_section_2()
	var s3:   LevelSection = _build_section_3()

	director.add_section(s1)
	director.add_section(s_ast)
	director.add_section(s2)
	director.add_section(s3)

	director.level_complete.connect(_on_level_complete)
	director.start()


# ── Section builders ──────────────────────────────────────────────────────────

func _build_section_1() -> LevelSection:
	var s := LevelSection.new()
	s.section_name        = &"deep_space"
	s.background_phase    = preload("res://assault/scenes/levels/phases/phase_deep_space.tres")
	s.transition_in_duration = 0.0
	s.end_condition       = LevelSection.EndCondition.DURATION
	s.duration            = 30.0

	var b := WaveBuilder.new()

	var raw_waves: Array = [
		# 2.0 s — V of 5 fighters, straight down
		b.wave(2.0, [
			b.fighter().formation(b.v_formation(5)).at(-150, -150).move(b.straight(120)).delay(0.5).shoot_forward(),
		]),

		# 5.0 s — 3 fighters, U-sweep right
		b.wave(5.0, [
			b.fighter().formation(b.v_formation(3)).at(220, -150).move(b.u_sweep(420, 600, 9)).delay(0.5).free_after(10).shoot_forward(),
		]),

		# 8.0 s — 5 fighters diagonal + 1 ally
		b.wave(8.0, [
			b.fighter().formation(b.diagonal_formation(5, 30, 35)).at(300, -200).move(b.straight(200, -PI / 3.6)).shoot_forward(),
			b.ally().at(0, 180).move(b.straight(140, PI)).delay(0.2),
		]),

		# 14.0 s — 5 fighters diagonal (mirrored)
		b.wave(14.0, [
			b.fighter().formation(b.diagonal_formation(5, -30, 35)).at(-300, -200).move(b.straight(200, PI / 3.6)).shoot_forward(),
		]),

		# 20.0 s — dual U-sweeps from both flanks
		b.wave(20.0, [
			b.fighter().at(220, -150).move(b.u_sweep(180, 300, 4)).delay(0.5).free_after(5).shoot_forward(),
			b.fighter().at(-220, -150).move(b.u_sweep(-180, 300, 4)).delay(0.5).free_after(5).shoot_forward(),
		]),

		# 22.0 s — 3 + 1 drones, sine weave
		b.wave(22.0, [
			b.drone().at(-50, -180).move(b.sine(140, 45)),
			b.drone().at(0,  -180).move(b.sine(140, 45)),
			b.drone().at(50, -180).move(b.sine(140, 45)),
			b.drone().at(25, -165).move(b.sine(140, 45)).delay(0.2),
		]),

		# 26.0 s — 2 ram ships from each flank as section closer
		b.wave(26.0, [
			b.ram().at(-200, -160).move(b.straight(300)),
			b.ram().at(200,  -160).move(b.straight(300)).delay(0.5),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_asteroid() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"asteroid_belt"
	s.background_phase       = preload("res://assault/scenes/levels/phases/phase_asteroid_belt.tres")
	s.transition_in_duration = 0.0
	s.end_condition          = LevelSection.EndCondition.DURATION
	s.duration               = 30.0

	var b := WaveBuilder.new()

	var raw_waves: Array = [
		# 0.0 s — left cluster, staggered
		b.wave(0.0, [
			b.big_asteroid().at(-180, -180).move(b.straight(200)),
			b.big_asteroid().at(-100, -180).move(b.straight(215)).delay(0.5),
			b.big_asteroid().at(-140, -180).move(b.straight(230)).delay(1.0),
			b.small_asteroid().at(-60, -180).move(b.straight(320)).delay(0.3),
		]),

		# 4.0 s — right side + small chaser
		b.wave(4.0, [
			b.big_asteroid().at(80,  -180).move(b.straight(200)),
			b.big_asteroid().at(180, -180).move(b.straight(225)).delay(0.4),
			b.small_asteroid().at(130, -180).move(b.straight(310)).delay(0.2),
			b.small_asteroid().at(210, -180).move(b.straight(340)).delay(0.8),
		]),

		# 8.0 s — center column spread
		b.wave(8.0, [
			b.big_asteroid().at(-200, -180).move(b.straight(195)),
			b.big_asteroid().at(  0,  -180).move(b.straight(210)).delay(0.3),
			b.big_asteroid().at( 200, -180).move(b.straight(200)).delay(0.6),
			b.small_asteroid().at(-100, -180).move(b.straight(290)),
			b.small_asteroid().at( 100, -180).move(b.straight(305)).delay(0.5),
		]),

		# 12.0 s — four-column wall
		b.wave(12.0, [
			b.big_asteroid().at(-160, -180).move(b.straight(220)),
			b.big_asteroid().at( -40, -180).move(b.straight(205)).delay(0.4),
			b.big_asteroid().at(  80, -180).move(b.straight(235)).delay(0.2),
			b.big_asteroid().at( 180, -180).move(b.straight(215)).delay(0.6),
			b.small_asteroid().at(-100, -180).move(b.straight(280)).delay(1.0),
			b.small_asteroid().at(  30, -180).move(b.straight(295)).delay(0.7),
		]),

		# 17.0 s — full-width sweep, peak density
		b.wave(17.0, [
			b.big_asteroid().at(-200, -180).move(b.straight(200)),
			b.big_asteroid().at(-100, -180).move(b.straight(220)).delay(0.3),
			b.big_asteroid().at(   0, -180).move(b.straight(210)).delay(0.6),
			b.big_asteroid().at( 100, -180).move(b.straight(225)).delay(0.9),
			b.big_asteroid().at( 200, -180).move(b.straight(205)).delay(0.3),
			b.small_asteroid().at( -50, -180).move(b.straight(290)).delay(0.5),
			b.small_asteroid().at(  50, -180).move(b.straight(310)).delay(1.2),
		]),

		# 22.0 s — staggered columns, gaps narrow
		b.wave(22.0, [
			b.big_asteroid().at(-150, -180).move(b.straight(230)),
			b.big_asteroid().at( -50, -180).move(b.straight(215)).delay(0.8),
			b.big_asteroid().at(  50, -180).move(b.straight(225)).delay(0.4),
			b.big_asteroid().at( 150, -180).move(b.straight(220)).delay(1.2),
			b.small_asteroid().at(-200, -180).move(b.straight(300)).delay(0.6),
			b.small_asteroid().at( 200, -180).move(b.straight(320)).delay(0.2),
			b.small_asteroid().at(   0, -180).move(b.straight(295)).delay(1.0),
		]),

		# 27.0 s — closing barrage
		b.wave(27.0, [
			b.big_asteroid().at(-180, -180).move(b.straight(240)),
			b.big_asteroid().at( -60, -180).move(b.straight(220)).delay(0.5),
			b.big_asteroid().at(  60, -180).move(b.straight(235)).delay(0.3),
			b.big_asteroid().at( 180, -180).move(b.straight(215)).delay(0.8),
			b.small_asteroid().at(-120, -180).move(b.straight(300)),
			b.small_asteroid().at(   0, -180).move(b.straight(285)).delay(0.7),
			b.small_asteroid().at( 120, -180).move(b.straight(315)).delay(1.0),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_2() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"planet_approach"
	s.background_phase       = preload("res://assault/scenes/levels/phases/phase_planet_approach.tres")
	s.transition_in_duration = 110.0
	s.end_condition          = LevelSection.EndCondition.DURATION
	s.duration               = 110.0

	var b := WaveBuilder.new()
	var L: ArcMovement.ArcDirection = WaveBuilder.LEFT
	var R: ArcMovement.ArcDirection = WaveBuilder.RIGHT

	var raw_waves: Array = [
		# 5.0 s — 3 fighters from the left flank
		b.wave(5.0, [
			b.fighter().formation(b.v_formation(3)).at(-220, -150).move(b.straight(110, PI / 5)).shoot_forward(),
		]),

		# 20.0 s — 3 fighters from the right flank
		b.wave(20.0, [
			b.fighter().formation(b.v_formation(3)).at(220, -150).move(b.straight(110, -PI / 5)).shoot_forward(),
		]),

		# 35.0 s — 4 drones, sine weave from left
		b.wave(35.0, [
			b.drone().at(-80, -180).move(b.sine(130, 40)),
			b.drone().at(-30, -180).move(b.sine(130, 40)).delay(0.3),
			b.drone().at( 20, -180).move(b.sine(130, 40)).delay(0.6),
			b.drone().at( 70, -180).move(b.sine(130, 40)).delay(0.9),
		]),

		# 50.0 s — 5 fighters V formation down the middle
		b.wave(50.0, [
			b.fighter().formation(b.v_formation(5)).at(0, -150).move(b.straight(115)).shoot_forward(),
		]),

		# 65.0 s — 2 snipers, one from each side
		b.wave(65.0, [
			b.sniper().at(-180, -100).move(b.straight(75, PI / 8)).shoot_at_player(),
			b.sniper().at( 180, -100).move(b.straight(75, -PI / 8)).shoot_at_player(),
		]),

		# 80.0 s — 5 fighters diagonal from the right
		b.wave(80.0, [
			b.fighter().formation(b.diagonal_formation(5, -30, 35)).at(300, -200).move(b.straight(180, PI / 4)).shoot_forward(),
		]),

		# 95.0 s — 4 drones, sine weave from right
		b.wave(95.0, [
			b.drone().at( 80, -180).move(b.sine(130, -40)),
			b.drone().at( 30, -180).move(b.sine(130, -40)).delay(0.3),
			b.drone().at(-20, -180).move(b.sine(130, -40)).delay(0.6),
			b.drone().at(-70, -180).move(b.sine(130, -40)).delay(0.9),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_3() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"cloud_descent"
	s.background_phase       = preload("res://assault/scenes/levels/phases/phase_cloud_descent.tres")
	s.transition_in_duration = 2.0
	s.end_condition          = LevelSection.EndCondition.ENEMIES_CLEARED
	s.duration               = 0.0

	var b := WaveBuilder.new()
	var L: ArcMovement.ArcDirection = WaveBuilder.LEFT
	var R: ArcMovement.ArcDirection = WaveBuilder.RIGHT

	var raw_waves: Array = [
		# 0.0 s — 5-ship ally escort arrowhead arriving from below
		b.wave(0.0, [
			b.ally().at(0,   180).move(b.straight(160, PI)),
			b.ally().at(-40,   0).move(b.straight(140, PI - 0.18)).delay(0.2),
			b.ally().at( 40,   0).move(b.straight(140, PI + 0.18)).delay(0.2),
			b.ally().at(-80, 180).move(b.straight(125, PI - 0.32)).delay(0.4),
			b.ally().at( 80, 180).move(b.straight(125, PI + 0.32)).delay(0.4),
		]),

		# 5.0 s — 3 fighters sweep left-to-right
		b.wave(5.0, [
			b.fighter().at(-350,  20).move(b.straight(220, PI / 2)).free_after(3.5).shoot_at_player(),
			b.fighter().at(-350,  60).move(b.straight(220, PI / 2)).delay(0.3).free_after(3.5).shoot_at_player(),
			b.fighter().at(-350, 100).move(b.straight(220, PI / 2)).delay(0.6).free_after(3.5).shoot_at_player(),
		]),

		# 14.0 s — 3 fighters sweep right-to-left
		b.wave(14.0, [
			b.fighter().at(350,  20).move(b.straight(220, -PI / 2)).free_after(3.5).shoot_at_player(),
			b.fighter().at(350,  60).move(b.straight(220, -PI / 2)).delay(0.3).free_after(3.5).shoot_at_player(),
			b.fighter().at(350, 100).move(b.straight(220, -PI / 2)).delay(0.6).free_after(3.5).shoot_at_player(),
		]),

		# 22.0 s — 3 drones rising from behind (below screen)
		b.wave(22.0, [
			b.drone().at(-60, 280).move(b.sine(140, -40, PI)),
			b.drone().at(  0, 280).move(b.sine(140, 40, PI)).delay(0.25),
			b.drone().at( 60, 280).move(b.sine(140, -40, PI)).delay(0.5),
		]),

		# 32.0 s — 2 snipers from sides + 2 from top
		b.wave(32.0, [
			b.sniper().at(-350,  50).move(b.straight(80, PI / 2)).free_after(3.0).shoot_at_player(),
			b.sniper().at( 350,  50).move(b.straight(80, -PI / 2)).free_after(3.0).shoot_at_player(),
			b.sniper().at(-100, -180).move(b.straight(75, PI / 6)).shoot_at_player(),
			b.sniper().at( 100, -180).move(b.straight(75, -PI / 6)).shoot_at_player(),
		]),

		# 42.0 s — 4 fighters simultaneous from both flanks
		b.wave(42.0, [
			b.fighter().at(-350,   0).move(b.straight(200, PI / 2)).free_after(3.0).shoot_at_player(),
			b.fighter().at(-350,  60).move(b.straight(200, PI / 2)).delay(0.4).free_after(3.0).shoot_at_player(),
			b.fighter().at( 350,   0).move(b.straight(200, -PI / 2)).free_after(3.0).shoot_at_player(),
			b.fighter().at( 350,  60).move(b.straight(200, -PI / 2)).delay(0.4).free_after(3.0).shoot_at_player(),
		]),

		# 50.0 s — gunship + 3 covering fighters
		b.wave(50.0, [
			b.gunship().at(0,   -150).move(b.straight(35)),
			b.fighter().at(-50, -150).move(b.arc(L, 120, 4.0)).delay(0.8).free_after(4.0),
			b.fighter().at(  0, -150).move(b.straight(80)).delay(0.8),
			b.fighter().at( 50, -150).move(b.arc(R, 120, 4.0)).delay(0.8).free_after(4.0),
		]),
	]
	s.waves.assign(raw_waves)
	return s


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_level_complete() -> void:
	print("[Level1Director] Level complete — showing debrief dialog")
	DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))
	await DialogPlayer.dialog_finished
	if not is_instance_valid(self):
		return
	LevelExitCutscene.go_to_hub = MissionState.is_complete(1)
	MissionState.complete(1, 1)
	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	get_tree().change_scene_to_file("res://cutscenes/level_exit/level_exit_cutscene.tscn")
