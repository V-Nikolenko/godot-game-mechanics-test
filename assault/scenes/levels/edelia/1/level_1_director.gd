## Level1Director — wires four LevelSections for Level 1 and handles level completion.
##
## Section 1 (Deep Space)      — 30 s timed section, fighters/drones, no asteroids.
## Section 2 (Asteroid Belt)   — 30 s timed section, asteroid gauntlet, no enemies.
## Section 3 (Planet Approach) — 110 s cinematic, light enemy harassment.
## Section 4 (Cloud Descent)   — ENEMIES_CLEARED boss-area section with ally escort + gunship wave.
##
## Also boots scoring: starts the ScoreTracker, schedules per-section bonus
## drones + skill challenges, and runs the post-mission debrief screen.
extends Node

const _MISSION_NUMBER: int = 1
const _MISSION_CONFIG_PATH := "res://open_space/scenes/mission_data/planets/edelia/edelia_01_assault_mission_break_enemy_blockade_resource.tres"
const _DEBRIEF_SCENE: PackedScene = preload("res://assault/scenes/gui/level_debrief.tscn")
@export var director: LevelDirector
@export var wave_manager: WaveManager
@export var score_tracker: ScoreTracker

# Section-relative timers (StringName → Array[Dictionary] of pending events).
# Each event: { "time": float, "callable": Callable }.
var _section_schedules: Dictionary = {}
var _current_section_name: StringName = &""
var _section_elapsed: float = 0.0


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

	# Per-section bonus drone + skill challenge schedules (section-relative time).
	# Wave manager handles enemy spawns from wave lists; everything else
	# (bonus drones, skill challenges) is scheduled here so it stays decoupled.
	_section_schedules = {
		&"deep_space": [
			{"time": 10.0, "callable": _trigger_skill_challenge_asteroid_corridor},
			{"time": 15.0, "callable": _spawn_bonus_drone_left_to_right},
		],
		&"planet_approach": [
			{"time": 40.0, "callable": _spawn_bonus_drone_right_to_left},
			{"time": 70.0, "callable": _trigger_skill_challenge_bullet_weave},
			{"time": 90.0, "callable": _spawn_bonus_drone_left_to_right},
		],
		&"cloud_descent": [
			{"time": 25.0, "callable": _spawn_bonus_drone_right_to_left},
		],
	}

	director.section_started.connect(_on_section_started)
	director.level_complete.connect(_on_level_complete)

	if score_tracker:
		score_tracker.start_tracking()
	director.start()


func _process(delta: float) -> void:
	if _current_section_name == &"":
		return
	var pending: Array = _section_schedules.get(_current_section_name, [])
	if pending.is_empty():
		return
	_section_elapsed += delta
	# Iterate in place; pop entries whose time has elapsed.
	var i: int = 0
	while i < pending.size():
		var event: Dictionary = pending[i]
		if _section_elapsed >= event["time"]:
			(event["callable"] as Callable).call()
			pending.remove_at(i)
		else:
			i += 1


func _on_section_started(_index: int, section_name: StringName) -> void:
	_current_section_name = section_name
	_section_elapsed = 0.0


# ── Bonus drone spawners (section-side, independent of waves) ─────────────────

func _spawn_bonus_drone_left_to_right() -> void:
	_spawn_bonus_drone(Vector2(-340, 30), PI / 2)

func _spawn_bonus_drone_right_to_left() -> void:
	_spawn_bonus_drone(Vector2(340, 30), -PI / 2)

func _spawn_bonus_drone(camera_offset: Vector2, angle: float) -> void:
	if not wave_manager:
		return
	# Spawn directly into the enemy container — bypassing the wave registry
	# keeps the wave clock undisturbed (bonus drones aren't part of any wave).
	# We still emit enemy_spawned so ScoreTracker hooks the medal's score signal.
	var container: Node2D = wave_manager.enemy_container
	if not container:
		return
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var scene: PackedScene = preload("res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn")
	var entity: Node = scene.instantiate()
	(entity as Node2D).global_position = cam.global_position + camera_offset
	container.add_child(entity)

	# Attach the same EnemyPathMover the wave manager would, so the drone
	# follows a fast horizontal straight line and despawns on screen exit.
	var movement := StraightMovement.new()
	movement.speed = 280.0
	movement.angle = angle
	var mover := EnemyPathMover.new()
	mover.movement = movement
	mover.exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
	mover.exit_time = 4.0
	entity.add_child(mover)

	# Wave index -1 = not part of any wave clear bonus.
	wave_manager.enemy_spawned.emit(entity, -1)
	print("[Level1Director] Spawned BonusDrone at offset (%.0f, %.0f)" % [camera_offset.x, camera_offset.y])


# ── Skill challenges ──────────────────────────────────────────────────────────

func _trigger_skill_challenge_asteroid_corridor() -> void:
	var res := SkillChallengeResource.new()
	res.challenge_name = "ASTEROID CORRIDOR"
	res.duration = 4.0
	res.clean_bonus = 500
	res.partial_bonus = 150
	_launch_skill_challenge(res)

func _trigger_skill_challenge_bullet_weave() -> void:
	var res := SkillChallengeResource.new()
	res.challenge_name = "BULLET WEAVE"
	res.duration = 5.0
	res.clean_bonus = 700
	res.partial_bonus = 200
	_launch_skill_challenge(res)

func _launch_skill_challenge(res: SkillChallengeResource) -> void:
	# SkillChallengeRunner.new() already attaches the script via class_name.
	var runner := SkillChallengeRunner.new()
	runner.challenge = res
	get_parent().add_child(runner)


# ── Section builders ──────────────────────────────────────────────────────────

func _build_section_1() -> LevelSection:
	var s := LevelSection.new()
	s.section_name        = &"deep_space"
	s.background_phase    = preload("res://assault/scenes/levels/edelia/1/phases/phase_deep_space.tres")
	s.transition_in_duration = 0.0
	s.end_condition       = LevelSection.EndCondition.DURATION
	s.duration            = 30.0

	var b := WaveBuilder.new()
	var L: ArcMovement.ArcDirection = WaveBuilder.LEFT
	var R: ArcMovement.ArcDirection = WaveBuilder.RIGHT

	var raw_waves: Array = [
		# 0.0 s — interceptor pair for early testing; self-managed movement, no .move() needed
		b.wave(0.0, [
			b.interceptor().at(-200, -420),
			b.interceptor().at( 200, -420).delay(0.4),
		]),

		# 0.5 s — sniper pair drops in, fires 5 times, then retreats
		# Sequence: fly in (2.5 s) → hold 13 s (covers 5 × 2.5 s shoot cycle) → fly out
		# Sprite faces down during approach; red line appears only once AIM begins.
		b.wave(0.5, [
			b.sniper_enemy().at(-120, -500).move(b.sequence([
				b.straight(150, 0.0, 2.5),
				b.hold(13.0),
				b.straight(220, PI),
			])),
			b.sniper_enemy().at( 120, -500).move(b.sequence([
				b.straight(150, 0.0, 2.5),
				b.hold(13.0),
				b.straight(220, PI),
			])).delay(0.5),
		]),

		# 1.0 s — opening drone pair, fast straight angles into the field
		b.wave(1.0, [
			b.drone().at(-260, -400).move(b.straight(180, PI / 4)),
			b.drone().at( 260, -400).move(b.straight(180, -PI / 4)).delay(0.2),
		]),

		# 2.0 s — V of 5 fighters, straight down (+ side drone screen from above)
		b.wave(2.0, [
			b.fighter().formation(b.v_formation(5)).at(-150, -400).move(b.straight(138)).delay(0.5).shoot_forward(),
			b.drone().at(-220, -400).move(b.sine(170, 30)).delay(0.1),
			b.drone().at( 220, -400).move(b.sine(170, -30)).delay(0.1),
		]),

		# 3.0 s — drone trio sine from right side
		b.wave(3.0, [
			b.drone().at(120, -400).move(b.sine(180, 45, 3.0)),
			b.drone().at(180, -400).move(b.sine(180, 45, 3.0)).delay(0.25),
			b.drone().at(240, -400).move(b.sine(180, 45, 3.0)).delay(0.5),
		]),

		# 4.0 s — pair of drones from edges (sine weave) + cluster center
		b.wave(4.0, [
			b.drone().at(-220, -400).move(b.sine(170, 38)),
			b.drone().at( 220, -400).move(b.sine(170, -38)).delay(0.3),
			b.drone().formation(b.cluster_formation(3, 30)).at(0, -400).move(b.straight(180)).delay(0.4),
		]),

		# 5.0 s — 3 fighters, U-sweep right + ally support from below
		b.wave(5.0, [
			b.fighter().formation(b.v_formation(3)).at(260, -400).move(b.u_sweep(510, 730, 10)).delay(0.5).free_after(12).shoot_forward(),
			b.ally().at(-180, 400).move(b.straight(165, PI - 0.2)).delay(0.4),
		]),

		# 6.5 s — fighter pair sweeping in from off-screen sides
		b.wave(6.5, [
			b.fighter().at(-500, -30).move(b.straight(230, PI / 2)).shoot_at_player().free_after(5.5),
			b.fighter().at( 500, -30).move(b.straight(230, -PI / 2)).shoot_at_player().free_after(5.5).delay(0.3),
		]),

		# 7.5 s — single ram from center as a wake-up
		b.wave(7.5, [
			b.ram().at(0, -400).move(b.straight(280)),
		]),

		# 8.0 s — 5 fighters diagonal + 1 ally + drone screen behind
		b.wave(8.0, [
			b.fighter().formation(b.diagonal_formation(5, 30, 35)).at(370, -400).move(b.straight(220, -PI / 3.6)).shoot_forward(),
			b.ally().at(0, 400).move(b.straight(155, PI)).delay(0.2),
			b.drone().at(-140, -400).move(b.straight(220)).delay(0.5),
			b.drone().at( 140, -400).move(b.straight(220)).delay(0.7),
		]),

		# 9.5 s — drone harassment trio before snipers arrive
		b.wave(9.5, [
			b.drone().at(-100, -400).move(b.sine(160, 30, 4.0)),
			b.drone().at(   0, -400).move(b.sine(160, 30, 4.0)).delay(0.2),
			b.drone().at( 100, -400).move(b.sine(160, -30, 4.0)).delay(0.4),
		]),

		# 11.0 s — sniper pair from above corners + drone cover
		b.wave(11.0, [
			b.sniper().at(-185, -400).move(b.straight(82, PI / 10)).shoot_at_player(),
			b.sniper().at( 185, -400).move(b.straight(82, -PI / 10)).shoot_at_player().delay(0.3),
			b.drone().at(   0, -400).move(b.sine(170, 50, 3.0)).delay(0.5),
		]),

		# 12.5 s — wedge of drones rushing down the middle
		b.wave(12.5, [
			b.drone().formation(b.wedge_formation(3, 45, 18)).at(0, -400).move(b.straight(175)),
		]),

		# 13.5 s — single fighter sweeping in from the left while snipers persist
		b.wave(13.5, [
			b.fighter().at(-500, 30).move(b.straight(220, PI / 2)).shoot_forward().free_after(5.0),
		]),

		# 14.0 s — 5 fighters diagonal (mirrored) + drone bracket
		b.wave(14.0, [
			b.fighter().formation(b.diagonal_formation(5, -30, 35)).at(-370, -400).move(b.straight(220, PI / 3.6)).shoot_forward(),
			b.drone().at( 200, -400).move(b.straight(220)).delay(0.5),
			b.drone().at(-200, -400).move(b.straight(220)).delay(0.5),
		]),

		# 15.5 s — surprise ram coming up from the bottom
		b.wave(15.5, [
			b.ram().at(0, 400).move(b.straight(260, PI)),
		]),

		# 16.0 s — line-formation drones across the top
		b.wave(16.0, [
			b.drone().formation(b.line_formation(4, 60)).at(0, -400).move(b.straight(175)),
		]),

		# 17.0 s — 4 drone cluster center + side fighter
		b.wave(17.0, [
			b.drone().formation(b.cluster_formation(4, 40)).at(0, -400).move(b.sine(160, 42)),
			b.fighter().at(-500, 30).move(b.straight(220, PI / 2)).shoot_at_player().free_after(5.0).delay(0.4),
		]),

		# 18.5 s — side fighter pair sweeping in from off-screen
		b.wave(18.5, [
			b.fighter().at(-500, 0).move(b.straight(230, PI / 2)).shoot_forward().free_after(5.5),
			b.fighter().at( 500, 0).move(b.straight(230, -PI / 2)).shoot_forward().free_after(5.5).delay(0.3),
		]),

		# 19.5 s — sniper from below right
		b.wave(19.5, [
			b.sniper().at(220, 400).move(b.straight(120, -PI / 2 - PI / 10)).shoot_at_player().free_after(5.0),
		]),

		# 20.0 s — dual U-sweeps from both flanks + drone chasers
		b.wave(20.0, [
			b.fighter().at( 260, -400).move(b.u_sweep( 225, 375, 5)).delay(0.5).free_after(6).shoot_forward(),
			b.fighter().at(-260, -400).move(b.u_sweep(-225, 375, 5)).delay(0.5).free_after(6).shoot_forward(),
			b.drone().at(0, -400).move(b.sine(170, 45, 3.0)).delay(0.3),
		]),

		# 21.0 s — drone cluster off-center
		b.wave(21.0, [
			b.drone().formation(b.cluster_formation(3, 35)).at(-110, -400).move(b.sine(170, -25, 3.0)),
		]),

		# 22.0 s — 3 + 1 drones, sine weave (extended with 2 more)
		b.wave(22.0, [
			b.drone().at(-60, -400).move(b.sine(160, 55)),
			b.drone().at(  0, -400).move(b.sine(160, 55)),
			b.drone().at( 60, -400).move(b.sine(160, 55)),
			b.drone().at( 30, -400).move(b.sine(160, 55)).delay(0.2),
			b.drone().at(-120, -400).move(b.sine(160, 55)).delay(0.35),
			b.drone().at( 120, -400).move(b.sine(160, 55)).delay(0.35),
		]),

		# 23.0 s — diagonal drone wash from upper-right
		b.wave(23.0, [
			b.drone().at(-180, -400).move(b.straight(230, PI / 12)),
			b.drone().at( 180, -400).move(b.straight(230, -PI / 12)).delay(0.15),
		]),

		# 24.0 s — wedge of 5 fighters + ally support
		b.wave(24.0, [
			b.fighter().formation(b.wedge_formation(5, 38, 14)).at(0, -400).move(b.straight(150)).shoot_forward(),
			b.ally().at(-60, 400).move(b.straight(170, PI - 0.15)).delay(0.5),
			b.ally().at( 60, 400).move(b.straight(170, PI + 0.15)).delay(0.5),
		]),

		# 25.0 s — side fighters sweeping in from off-screen, mid-altitude
		b.wave(25.0, [
			b.fighter().at(-500, -30).move(b.straight(240, PI / 2)).shoot_at_player().free_after(5.0),
			b.fighter().at( 500, -30).move(b.straight(240, -PI / 2)).shoot_at_player().free_after(5.0).delay(0.4),
		]),

		# 26.0 s — 2 ram ships from each flank + drone interlace
		b.wave(26.0, [
			b.ram().at(-255, -400).move(b.straight(350)),
			b.ram().at( 255, -400).move(b.straight(350)).delay(0.5),
			b.drone().at(   0, -400).move(b.sine(200, 50, 2.5)).delay(0.3),
		]),

		# 27.0 s — column of drones straight down
		b.wave(27.0, [
			b.drone().at(-100, -400).move(b.straight(220)),
			b.drone().at(   0, -400).move(b.straight(220)).delay(0.15),
			b.drone().at( 100, -400).move(b.straight(220)).delay(0.3),
		]),

		# 28.0 s — final drone swarm (extended)
		b.wave(28.0, [
			b.drone().at(-200, -400).move(b.sine(195, 60)),
			b.drone().at(-100, -400).move(b.sine(195, 60)).delay(0.1),
			b.drone().at( -50, -400).move(b.sine(195, 60)).delay(0.15),
			b.drone().at(   0, -400).move(b.sine(195, 60)).delay(0.25),
			b.drone().at(  50, -400).move(b.sine(195, 60)).delay(0.3),
			b.drone().at( 100, -400).move(b.sine(195, 60)).delay(0.35),
			b.drone().at( 200, -400).move(b.sine(195, 60)).delay(0.45),
		]),

		# 29.0 s — last burst: sniper crossfire + a fighter pair
		# Snipers use default EXIT_SCREEN so they're only freed once fully off-screen.
		b.wave(29.0, [
			b.sniper().at(-260, -400).move(b.straight(90, PI / 7)).shoot_at_player(),
			b.sniper().at( 260, -400).move(b.straight(90, -PI / 7)).shoot_at_player(),
			b.fighter().at(0, -400).move(b.straight(250)).delay(0.3).shoot_forward(),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_asteroid() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"asteroid_belt"
	s.background_phase       = preload("res://assault/scenes/levels/edelia/1/phases/phase_asteroid_belt.tres")
	s.transition_in_duration = 0.0
	s.end_condition          = LevelSection.EndCondition.DURATION
	s.duration               = 30.0

	var b := WaveBuilder.new()

	var raw_waves: Array = [
		# 0.0 s — left cluster, staggered
		b.wave(0.0, [
			b.big_asteroid().at(-195, -400).move(b.straight(210)),
			b.big_asteroid().at(-110, -400).move(b.straight(225)).delay(0.5),
			b.big_asteroid().at(-155, -400).move(b.straight(240)).delay(1.0),
			b.small_asteroid().at(-65, -400).move(b.straight(330)).delay(0.3),
		]),

		# 4.0 s — right side + small chaser
		b.wave(4.0, [
			b.big_asteroid().at( 85,  -245).move(b.straight(210)),
			b.big_asteroid().at(195, -400).move(b.straight(235)).delay(0.4),
			b.small_asteroid().at(140, -400).move(b.straight(320)).delay(0.2),
			b.small_asteroid().at(225, -400).move(b.straight(350)).delay(0.8),
		]),

		# 8.0 s — center column spread
		b.wave(8.0, [
			b.big_asteroid().at(-215, -400).move(b.straight(205)),
			b.big_asteroid().at(   0, -400).move(b.straight(220)).delay(0.3),
			b.big_asteroid().at( 215, -400).move(b.straight(210)).delay(0.6),
			b.small_asteroid().at(-110, -400).move(b.straight(300)),
			b.small_asteroid().at( 110, -400).move(b.straight(315)).delay(0.5),
		]),

		# 12.0 s — four-column wall
		b.wave(12.0, [
			b.big_asteroid().at(-175, -400).move(b.straight(230)),
			b.big_asteroid().at( -45, -400).move(b.straight(215)).delay(0.4),
			b.big_asteroid().at(  85, -400).move(b.straight(245)).delay(0.2),
			b.big_asteroid().at( 195, -400).move(b.straight(225)).delay(0.6),
			b.small_asteroid().at(-110, -400).move(b.straight(290)).delay(1.0),
			b.small_asteroid().at(  35, -400).move(b.straight(305)).delay(0.7),
		]),

		# 17.0 s — full-width sweep, peak density
		b.wave(17.0, [
			b.big_asteroid().at(-215, -400).move(b.straight(210)),
			b.big_asteroid().at(-110, -400).move(b.straight(230)).delay(0.3),
			b.big_asteroid().at(   0, -400).move(b.straight(220)).delay(0.6),
			b.big_asteroid().at( 110, -400).move(b.straight(235)).delay(0.9),
			b.big_asteroid().at( 215, -400).move(b.straight(215)).delay(0.3),
			b.small_asteroid().at( -55, -400).move(b.straight(300)).delay(0.5),
			b.small_asteroid().at(  55, -400).move(b.straight(320)).delay(1.2),
		]),

		# 22.0 s — staggered columns, gaps narrow
		b.wave(22.0, [
			b.big_asteroid().at(-165, -400).move(b.straight(240)),
			b.big_asteroid().at( -55, -400).move(b.straight(225)).delay(0.8),
			b.big_asteroid().at(  55, -400).move(b.straight(235)).delay(0.4),
			b.big_asteroid().at( 165, -400).move(b.straight(230)).delay(1.2),
			b.small_asteroid().at(-215, -400).move(b.straight(310)).delay(0.6),
			b.small_asteroid().at( 215, -400).move(b.straight(330)).delay(0.2),
			b.small_asteroid().at(   0, -400).move(b.straight(305)).delay(1.0),
		]),

		# 27.0 s — closing barrage
		b.wave(27.0, [
			b.big_asteroid().at(-195, -400).move(b.straight(250)),
			b.big_asteroid().at( -65, -400).move(b.straight(230)).delay(0.5),
			b.big_asteroid().at(  65, -400).move(b.straight(245)).delay(0.3),
			b.big_asteroid().at( 195, -400).move(b.straight(225)).delay(0.8),
			b.small_asteroid().at(-130, -400).move(b.straight(310)),
			b.small_asteroid().at(   0, -400).move(b.straight(295)).delay(0.7),
			b.small_asteroid().at( 130, -400).move(b.straight(325)).delay(1.0),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_2() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"planet_approach"
	s.background_phase       = preload("res://assault/scenes/levels/edelia/1/phases/phase_planet_approach.tres")
	s.transition_in_duration = 110.0
	s.end_condition          = LevelSection.EndCondition.DURATION
	s.duration               = 110.0

	var b := WaveBuilder.new()
	var L: ArcMovement.ArcDirection = WaveBuilder.LEFT
	var R: ArcMovement.ArcDirection = WaveBuilder.RIGHT

	var raw_waves: Array = [
		# 2.0 s — opening drone screen
		b.wave(2.0, [
			b.drone().at(-180, -400).move(b.sine(170, 35, 3.0)),
			b.drone().at( 180, -400).move(b.sine(170, -35, 3.0)).delay(0.2),
		]),

		# 5.0 s — 3 fighters from the left flank (+ drone screen)
		b.wave(5.0, [
			b.fighter().formation(b.v_formation(3)).at(-260, -400).move(b.straight(128, PI / 5)).shoot_forward(),
			b.drone().at(160, -400).move(b.sine(170, -25)).delay(0.4),
		]),

		# 8.0 s — drone cluster harassment
		b.wave(8.0, [
			b.drone().formation(b.cluster_formation(3, 35)).at(0, -400).move(b.sine(165, 40, 3.0)),
		]),

		# 11.0 s — fighter sweeping in from off-screen left, fast
		b.wave(11.0, [
			b.fighter().at(-500, -30).move(b.straight(225, PI / 2)).shoot_at_player().free_after(5.0),
		]),

		# 13.0 s — drone pair sine weave (+ ram surprise)
		b.wave(13.0, [
			b.drone().at(-60, -400).move(b.sine(160, 48)),
			b.drone().at( 60, -400).move(b.sine(160, -48)).delay(0.25),
			b.ram().at(  0, -400).move(b.straight(290)).delay(0.6),
		]),

		# 16.0 s — sniper from upper-right + drone column
		b.wave(16.0, [
			b.sniper().at(220, -400).move(b.straight(85, -PI / 12)).shoot_at_player().free_after(5.5),
			b.drone().at(-80, -400).move(b.straight(200)).delay(0.4),
			b.drone().at(  0, -400).move(b.straight(200)).delay(0.5),
			b.drone().at( 80, -400).move(b.straight(200)).delay(0.6),
		]),

		# 20.0 s — 3 fighters from the right flank (+ left-side fighter sweep)
		b.wave(20.0, [
			b.fighter().formation(b.v_formation(3)).at(260, -400).move(b.straight(128, -PI / 5)).shoot_forward(),
			b.fighter().at(-500, 30).move(b.straight(220, PI / 2)).shoot_forward().free_after(5.0).delay(0.5),
		]),

		# 24.0 s — wedge of drones rushing center
		b.wave(24.0, [
			b.drone().formation(b.wedge_formation(4, 42, 16)).at(0, -400).move(b.straight(180)),
		]),

		# 28.0 s — ram from above (extended with side rams)
		b.wave(28.0, [
			b.ram().at(0, -400).move(b.straight(300)),
			b.ram().at(-220, -400).move(b.straight(310, PI / 10)).delay(0.4),
			b.ram().at( 220, -400).move(b.straight(310, -PI / 10)).delay(0.4),
		]),

		# 32.0 s — sniper from upper-left, drone cover
		b.wave(32.0, [
			b.sniper().at(-220, -400).move(b.straight(85, PI / 12)).shoot_at_player().free_after(5.5),
			b.drone().at(120, -400).move(b.sine(170, -40)).delay(0.3),
		]),

		# 35.0 s — 4 drones, sine weave from left (+ 2 extras from right)
		b.wave(35.0, [
			b.drone().at(-95, -400).move(b.sine(150, 48)),
			b.drone().at(-36, -400).move(b.sine(150, 48)).delay(0.3),
			b.drone().at( 24, -400).move(b.sine(150, 48)).delay(0.6),
			b.drone().at( 84, -400).move(b.sine(150, 48)).delay(0.9),
			b.drone().at(180, -400).move(b.sine(150, -48)).delay(0.4),
			b.drone().at(240, -400).move(b.sine(150, -48)).delay(0.7),
		]),

		# 39.0 s — fighter pair sweeping in from off-screen sides (crossing)
		b.wave(39.0, [
			b.fighter().at(-500, 50).move(b.straight(230, PI / 2)).shoot_at_player().free_after(5.5),
			b.fighter().at( 500, 50).move(b.straight(230, -PI / 2)).shoot_at_player().free_after(5.5).delay(0.4),
		]),

		# 42.0 s — drone cluster from upper-right
		b.wave(42.0, [
			b.drone().formation(b.cluster_formation(3, 32)).at(140, -400).move(b.sine(170, -35, 3.0)),
		]),

		# 44.0 s — sniper duo + drone screen (extended)
		b.wave(44.0, [
			b.sniper().at(-145, -400).move(b.straight(82, PI / 12)).shoot_at_player(),
			b.sniper().at( 145, -400).move(b.straight(82, -PI / 12)).shoot_at_player().delay(0.2),
			b.drone().at(0, -400).move(b.straight(185)).delay(0.6),
			b.drone().at(-80, -400).move(b.straight(190)).delay(0.8),
			b.drone().at( 80, -400).move(b.straight(190)).delay(0.8),
		]),

		# 47.0 s — fighter finisher sweeping in from off-screen right
		b.wave(47.0, [
			b.fighter().at(500, -30).move(b.straight(225, -PI / 2)).shoot_at_player().free_after(5.0),
		]),

		# 50.0 s — 5 fighters V formation down the middle (+ flanking drones)
		b.wave(50.0, [
			b.fighter().formation(b.v_formation(5)).at(0, -400).move(b.straight(133)).shoot_forward(),
			b.drone().at(-200, -400).move(b.sine(160, 35)).delay(0.3),
			b.drone().at( 200, -400).move(b.sine(160, -35)).delay(0.3),
		]),

		# 53.0 s — wedge drones rolling in
		b.wave(53.0, [
			b.drone().formation(b.wedge_formation(3, 38, 14)).at(0, -400).move(b.sine(170, 30, 3.5)),
		]),

		# 55.0 s — twin rams from below corners
		b.wave(55.0, [
			b.ram().at(-200, 400).move(b.straight(280, PI - 0.3)),
			b.ram().at( 200, 400).move(b.straight(280, PI + 0.3)).delay(0.3),
		]),

		# 58.0 s — bomber + escort drones + side fighters sweeping in off-screen
		b.wave(58.0, [
			b.bomber().at(0, -400).move(b.straight(82)).shoot_at_player(),
			b.drone().at(-72, -400).move(b.sine(170, -30)).delay(0.4),
			b.drone().at( 72, -400).move(b.sine(170,  30)).delay(0.4),
			b.fighter().at(-500, -30).move(b.straight(220, PI / 2)).shoot_at_player().free_after(5.0).delay(0.6),
			b.fighter().at( 500, -30).move(b.straight(220, -PI / 2)).shoot_at_player().free_after(5.0).delay(0.6),
		]),

		# 62.0 s — drone weave during bomber harassment
		b.wave(62.0, [
			b.drone().at(-150, -400).move(b.sine(180, 50, 2.5)),
			b.drone().at( 150, -400).move(b.sine(180, -50, 2.5)).delay(0.3),
		]),

		# 65.0 s — 2 snipers from top corners (+ ram chaser)
		b.wave(65.0, [
			b.sniper().at(-240, -400).move(b.straight(88, PI / 8)).shoot_at_player(),
			b.sniper().at( 240, -400).move(b.straight(88, -PI / 8)).shoot_at_player(),
			b.ram().at(0, -400).move(b.straight(310)).delay(0.7),
		]),

		# 68.0 s — drone screen sweep
		b.wave(68.0, [
			b.drone().at(-220, -400).move(b.straight(200, PI / 14)),
			b.drone().at(-110, -400).move(b.straight(200, PI / 14)).delay(0.15),
			b.drone().at(   0, -400).move(b.straight(200)).delay(0.3),
			b.drone().at( 110, -400).move(b.straight(200, -PI / 14)).delay(0.45),
			b.drone().at( 220, -400).move(b.straight(200, -PI / 14)).delay(0.6),
		]),

		# 72.0 s — fighter pair, diagonal formations
		b.wave(72.0, [
			b.fighter().formation(b.diagonal_formation(3, 35, 30)).at(-220, -400).move(b.straight(180, PI / 6)).shoot_forward(),
			b.fighter().formation(b.diagonal_formation(3, -35, 30)).at( 220, -400).move(b.straight(180, -PI / 6)).shoot_forward().delay(0.3),
		]),

		# 75.0 s — 4 drones cluster down center (+ snipers from top corners)
		b.wave(75.0, [
			b.drone().formation(b.cluster_formation(4, 50)).at(0, -400).move(b.sine(170, 36)),
			b.sniper().at(-260, -400).move(b.straight(90, PI / 8)).shoot_at_player().free_after(5.5).delay(0.5),
			b.sniper().at( 260, -400).move(b.straight(90, -PI / 8)).shoot_at_player().free_after(5.5).delay(0.5),
		]),

		# 78.0 s — fighter pair sweeping in from off-screen sides, fast
		b.wave(78.0, [
			b.fighter().at(-500, 60).move(b.straight(250, PI / 2)).shoot_forward().free_after(4.5),
			b.fighter().at( 500, 60).move(b.straight(250, -PI / 2)).shoot_forward().free_after(4.5).delay(0.3),
		]),

		# 80.0 s — 5 fighters diagonal from the right (+ left mirror small)
		b.wave(80.0, [
			b.fighter().formation(b.diagonal_formation(5, -30, 35)).at(375, -400).move(b.straight(208, PI / 4)).shoot_forward(),
			b.fighter().formation(b.diagonal_formation(3, 30, 35)).at(-280, -400).move(b.straight(200, -PI / 5)).shoot_forward().delay(0.4),
		]),

		# 84.0 s — drone swarm wedge
		b.wave(84.0, [
			b.drone().formation(b.wedge_formation(5, 40, 14)).at(0, -400).move(b.straight(190)),
		]),

		# 88.0 s — dual ram closers from sides (+ middle ram)
		b.wave(88.0, [
			b.ram().at(-270, -400).move(b.straight(348, PI / 8)),
			b.ram().at( 270, -400).move(b.straight(348, -PI / 8)).delay(0.4),
			b.ram().at(   0, -400).move(b.straight(330)).delay(0.8),
		]),

		# 92.0 s — sniper crossfire from off-screen sides at speed enough to clear screen
		b.wave(92.0, [
			b.sniper().at(-500, 50).move(b.straight(180, PI / 2)).shoot_at_player(),
			b.sniper().at( 500, 50).move(b.straight(180, -PI / 2)).shoot_at_player(),
		]),

		# 95.0 s — 4 drones, sine weave from right (extended)
		b.wave(95.0, [
			b.drone().at( 95, -400).move(b.sine(150, -48)),
			b.drone().at( 36, -400).move(b.sine(150, -48)).delay(0.3),
			b.drone().at(-24, -400).move(b.sine(150, -48)).delay(0.6),
			b.drone().at(-84, -400).move(b.sine(150, -48)).delay(0.9),
			b.drone().at(-150, -400).move(b.sine(150, -48)).delay(1.1),
			b.drone().at( 150, -400).move(b.sine(150, -48)).delay(1.1),
		]),

		# 98.0 s — second bomber pressure
		b.wave(98.0, [
			b.bomber().at(0, -400).move(b.straight(80)).shoot_at_player(),
			b.fighter().at(-180, -400).move(b.straight(180, PI / 14)).shoot_forward().delay(0.4),
			b.fighter().at( 180, -400).move(b.straight(180, -PI / 14)).shoot_forward().delay(0.4),
		]),

		# 102.0 s — final fighter wedge into the clouds (+ ram sandwich)
		b.wave(102.0, [
			b.fighter().formation(b.wedge_formation(5, 36, 14)).at(0, -400).move(b.straight(162)).shoot_forward(),
			b.ram().at(-260, -400).move(b.straight(330, PI / 10)).delay(0.3),
			b.ram().at( 260, -400).move(b.straight(330, -PI / 10)).delay(0.3),
		]),

		# 106.0 s — closing drone swarm before clouds
		b.wave(106.0, [
			b.drone().at(-220, -400).move(b.sine(210, 60, 2.0)),
			b.drone().at(-110, -400).move(b.sine(210, 60, 2.0)).delay(0.15),
			b.drone().at(   0, -400).move(b.sine(210, 60, 2.0)).delay(0.3),
			b.drone().at( 110, -400).move(b.sine(210, -60, 2.0)).delay(0.45),
			b.drone().at( 220, -400).move(b.sine(210, -60, 2.0)).delay(0.6),
		]),
	]
	s.waves.assign(raw_waves)
	return s


func _build_section_3() -> LevelSection:
	var s := LevelSection.new()
	s.section_name           = &"cloud_descent"
	s.background_phase       = preload("res://assault/scenes/levels/edelia/1/phases/phase_cloud_descent.tres")
	s.transition_in_duration = 2.0
	s.end_condition          = LevelSection.EndCondition.ENEMIES_CLEARED
	s.duration               = 0.0

	var b := WaveBuilder.new()
	var L: ArcMovement.ArcDirection = WaveBuilder.LEFT
	var R: ArcMovement.ArcDirection = WaveBuilder.RIGHT

	var raw_waves: Array = [
		# 0.0 s — 5-ship ally escort arrowhead arriving from below
		# Front pair at y=400 (closer to camera), back trio at y=500 (further).
		b.wave(0.0, [
			b.ally().at(  0, 500).move(b.straight(185, PI)),
			b.ally().at(-50, 400).move(b.straight(160, PI - 0.18)).delay(0.2),
			b.ally().at( 50, 400).move(b.straight(160, PI + 0.18)).delay(0.2),
			b.ally().at(-100, 500).move(b.straight(145, PI - 0.32)).delay(0.4),
			b.ally().at( 100, 500).move(b.straight(145, PI + 0.32)).delay(0.4),
		]),

		# 2.0 s — drone screen rising with the allies
		b.wave(2.0, [
			b.drone().at(-130, -400).move(b.sine(170, 35, 3.0)),
			b.drone().at( 130, -400).move(b.sine(170, -35, 3.0)).delay(0.3),
		]),

		# 5.0 s — 3 fighters sweep left-to-right (+ drone chasers)
		b.wave(5.0, [
			b.fighter().at(-500,  20).move(b.straight(265, PI / 2)).free_after(4.5).shoot_at_player(),
			b.fighter().at(-500,  60).move(b.straight(265, PI / 2)).delay(0.3).free_after(4.5).shoot_at_player(),
			b.fighter().at(-500, 100).move(b.straight(265, PI / 2)).delay(0.6).free_after(4.5).shoot_at_player(),
			b.drone().at(-500, 150).move(b.straight(220, PI / 2)).free_after(5.0).delay(0.9),
		]),

		# 9.0 s — drone trio diving from top
		b.wave(9.0, [
			b.drone().formation(b.wedge_formation(3, 40, 16)).at(0, -400).move(b.straight(195)),
		]),

		# 11.0 s — sniper from below-left as ambush
		b.wave(11.0, [
			b.sniper().at(-260, 400).move(b.straight(100, -PI / 2 - PI / 12)).shoot_at_player().free_after(5.5),
		]),

		# 14.0 s — 3 fighters sweep right-to-left (+ drone chasers)
		b.wave(14.0, [
			b.fighter().at(500,  20).move(b.straight(265, -PI / 2)).free_after(4.5).shoot_at_player(),
			b.fighter().at(500,  60).move(b.straight(265, -PI / 2)).delay(0.3).free_after(4.5).shoot_at_player(),
			b.fighter().at(500, 100).move(b.straight(265, -PI / 2)).delay(0.6).free_after(4.5).shoot_at_player(),
			b.drone().at(500, 150).move(b.straight(220, -PI / 2)).free_after(5.0).delay(0.9),
		]),

		# 18.0 s — drone cluster sine from top
		b.wave(18.0, [
			b.drone().formation(b.cluster_formation(4, 38)).at(0, -400).move(b.sine(180, 45, 2.5)),
		]),

		# 22.0 s — 3 drones rising from behind (extended)
		b.wave(22.0, [
			b.drone().at(-150, 400).move(b.straight(185, PI)),
			b.drone().at( -75, 400).move(b.straight(185, PI)).delay(0.2),
			b.drone().at(   0, 400).move(b.straight(185, PI)).delay(0.4),
			b.drone().at(  75, 400).move(b.straight(185, PI)).delay(0.6),
			b.drone().at( 150, 400).move(b.straight(185, PI)).delay(0.8),
		]),

		# 26.0 s — fighter pair arc from above
		b.wave(26.0, [
			b.fighter().at(-260, -400).move(b.arc(R, 160, 4.0)).shoot_at_player().free_after(5.0),
			b.fighter().at( 260, -400).move(b.arc(L, 160, 4.0)).shoot_at_player().free_after(5.0).delay(0.3),
		]),

		# 28.0 s — ram from below corner (surprise)
		b.wave(28.0, [
			b.ram().at(-180, 400).move(b.straight(290, PI - 0.2)),
			b.ram().at( 180, 400).move(b.straight(290, PI + 0.2)).delay(0.4),
		]),

		# 32.0 s — 2 snipers from sides + 2 from top (+ drone screen)
		b.wave(32.0, [
			b.sniper().at(-500,  50).move(b.straight(95, PI / 2)).free_after(4.0).shoot_at_player(),
			b.sniper().at( 500,  50).move(b.straight(95, -PI / 2)).free_after(4.0).shoot_at_player(),
			b.sniper().at(-120, -400).move(b.straight(88, PI / 6)).shoot_at_player(),
			b.sniper().at( 120, -400).move(b.straight(88, -PI / 6)).shoot_at_player(),
			b.drone().at(   0, -400).move(b.sine(180, 50)).delay(0.5),
		]),

		# 36.0 s — drone wedge straight down center
		b.wave(36.0, [
			b.drone().formation(b.wedge_formation(4, 44, 16)).at(0, -400).move(b.straight(195)),
		]),

		# 38.0 s — fighter pair from off-screen sides + ram support
		b.wave(38.0, [
			b.fighter().at(-500, 0).move(b.straight(225, PI / 2)).shoot_at_player().free_after(5.0),
			b.fighter().at( 500, 0).move(b.straight(225, -PI / 2)).shoot_at_player().free_after(5.0).delay(0.3),
			b.ram().at(0, -400).move(b.straight(320)).delay(0.6),
		]),

		# 42.0 s — 4 fighters from both flanks (+ 2 extras)
		b.wave(42.0, [
			b.fighter().at(-500,   0).move(b.straight(240, PI / 2)).free_after(4.0).shoot_at_player(),
			b.fighter().at(-500,  60).move(b.straight(240, PI / 2)).delay(0.4).free_after(4.0).shoot_at_player(),
			b.fighter().at( 500,   0).move(b.straight(240, -PI / 2)).free_after(4.0).shoot_at_player(),
			b.fighter().at( 500,  60).move(b.straight(240, -PI / 2)).delay(0.4).free_after(4.0).shoot_at_player(),
			b.fighter().at(-500, 120).move(b.straight(240, PI / 2)).delay(0.8).free_after(4.0).shoot_at_player(),
			b.fighter().at( 500, 120).move(b.straight(240, -PI / 2)).delay(0.8).free_after(4.0).shoot_at_player(),
		]),

		# 46.0 s — drone burst from below
		b.wave(46.0, [
			b.drone().at(-100, 400).move(b.straight(220, PI)),
			b.drone().at(   0, 400).move(b.straight(220, PI)).delay(0.2),
			b.drone().at( 100, 400).move(b.straight(220, PI)).delay(0.4),
		]),

		# 50.0 s — gunship + 3 covering fighters (+ ram chaser)
		b.wave(50.0, [
			b.gunship().at(  0, -400).move(b.straight(42)),
			b.fighter().at(-65, -400).move(b.arc(L, 145, 4.5)).delay(0.8).free_after(5.0),
			b.fighter().at(  0, -400).move(b.straight(95)).delay(0.8),
			b.fighter().at( 65, -400).move(b.arc(R, 145, 4.5)).delay(0.8).free_after(5.0),
			b.ram().at(-220, -400).move(b.straight(330, PI / 12)).delay(1.5),
			b.ram().at( 220, -400).move(b.straight(330, -PI / 12)).delay(1.5),
		]),

		# 53.0 s — sniper crossfire from sides during gunship fight
		b.wave(53.0, [
			b.sniper().at(-500,  20).move(b.straight(95, PI / 2)).free_after(5.0).shoot_at_player(),
			b.sniper().at( 500,  20).move(b.straight(95, -PI / 2)).free_after(5.0).shoot_at_player(),
		]),

		# 56.0 s — drones rising from behind (extended)
		b.wave(56.0, [
			b.drone().at(-130, 400).move(b.straight(200, PI)),
			b.drone().at( -65, 400).move(b.straight(200, PI)).delay(0.2),
			b.drone().at(   0, 400).move(b.straight(200, PI)).delay(0.4),
			b.drone().at(  65, 400).move(b.straight(200, PI)).delay(0.6),
			b.drone().at( 130, 400).move(b.straight(200, PI)).delay(0.8),
		]),

		# 59.0 s — fighter wedge support
		b.wave(59.0, [
			b.fighter().formation(b.wedge_formation(3, 40, 14)).at(0, -400).move(b.straight(165)).shoot_forward(),
		]),

		# 62.0 s — second gunship wave with snipers (+ drone screen)
		b.wave(62.0, [
			b.gunship().at(-100, -400).move(b.straight(36)),
			b.gunship().at( 100, -400).move(b.straight(36)).delay(0.8),
			b.sniper().at(-225, -400).move(b.straight(82, PI / 10)).shoot_at_player().delay(1.2),
			b.sniper().at( 225, -400).move(b.straight(82, -PI / 10)).shoot_at_player().delay(1.2),
			b.drone().at(0, -400).move(b.sine(180, 50)).delay(0.5),
			b.drone().at(-150, -400).move(b.sine(180, -45)).delay(0.7),
			b.drone().at( 150, -400).move(b.sine(180, 45)).delay(0.7),
		]),

		# 66.0 s — fighter arc finisher
		b.wave(66.0, [
			b.fighter().at(-500,  40).move(b.straight(255, PI / 2)).free_after(4.5).shoot_at_player(),
			b.fighter().at( 500,  40).move(b.straight(255, -PI / 2)).free_after(4.5).shoot_at_player(),
		]),

		# 68.0 s — drones from below
		b.wave(68.0, [
			b.drone().at(-100, 400).move(b.straight(210, PI)),
			b.drone().at( 100, 400).move(b.straight(210, PI)).delay(0.3),
		]),

		# 72.0 s — final fighter assault from all directions (extended)
		b.wave(72.0, [
			b.fighter().at(-500,  40).move(b.straight(265, PI / 2)).free_after(4.5).shoot_at_player(),
			b.fighter().at( 500,  40).move(b.straight(265, -PI / 2)).free_after(4.5).shoot_at_player(),
			b.fighter().formation(b.v_formation(3)).at(0, -400).move(b.straight(150)).delay(0.5).shoot_forward(),
			b.fighter().at(-500, 100).move(b.straight(265, PI / 2)).free_after(4.5).shoot_at_player().delay(0.8),
			b.fighter().at( 500, 100).move(b.straight(265, -PI / 2)).free_after(4.5).shoot_at_player().delay(0.8),
			b.ram().at(0, 400).move(b.straight(300, PI)).delay(1.2),
		]),

		# 76.0 s — drone swarm closer
		b.wave(76.0, [
			b.drone().at(-180, -400).move(b.sine(200, 55, 2.5)),
			b.drone().at( -90, -400).move(b.sine(200, 55, 2.5)).delay(0.2),
			b.drone().at(   0, -400).move(b.sine(200, 55, 2.5)).delay(0.4),
			b.drone().at(  90, -400).move(b.sine(200, -55, 2.5)).delay(0.6),
			b.drone().at( 180, -400).move(b.sine(200, -55, 2.5)).delay(0.8),
		]),
	]
	s.waves.assign(raw_waves)
	return s


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_level_complete() -> void:
	print("[Level1Director] Level complete — showing debrief dialog")
	if score_tracker:
		score_tracker.stop_tracking()

	DialogPlayer.play(preload("res://dialog/scripts/level1_debrief.tres"))
	await DialogPlayer.dialog_finished
	if not is_instance_valid(self):
		return

	# ── Score debrief ────────────────────────────────────────────────────────
	var final_score: int = 0
	var breakdown: Dictionary = {}
	if score_tracker:
		final_score = score_tracker.get_total_score()
		breakdown = score_tracker.get_breakdown()

	var mission_cfg: MissionConfigResource = load(_MISSION_CONFIG_PATH) as MissionConfigResource
	var stars_earned: int = mission_cfg.stars_for_score(final_score) if mission_cfg else 1

	var debrief: LevelDebriefScreen = _DEBRIEF_SCENE.instantiate() as LevelDebriefScreen
	get_tree().root.add_child(debrief)
	debrief.show_debrief(final_score, breakdown, stars_earned)
	await debrief.dismissed
	if not is_inside_tree():
		return

	# ── Persist & exit ───────────────────────────────────────────────────────
	LevelExitCutscene.go_to_hub = MissionState.is_complete(_MISSION_NUMBER)
	MissionState.record_score(_MISSION_NUMBER, final_score)
	MissionState.complete(_MISSION_NUMBER, stars_earned)
	print("[Level1Director] Saved score=%d stars=%d (mission %d)" % [final_score, stars_earned, _MISSION_NUMBER])

	var hud: Node = get_tree().root.get_node_or_null("HUD")
	if hud:
		hud.queue_free()
	get_tree().change_scene_to_file("res://cutscenes/level_exit/level_exit_cutscene.tscn")
