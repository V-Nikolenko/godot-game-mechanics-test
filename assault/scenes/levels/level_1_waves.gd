extends Node

# GDD Phase 1 — Wave-based aerial combat
# Wave types implemented:
#   Formation Waves   — geometric fighter formations from top
#   Suppression Waves — Gunship(s) hold back, fighters push forward
#   Pincer Waves      — simultaneous left + right flanks
#   Elite Encounter   — scroll slows to 50%, high-HP Gunship + escort

@export var wave_manager: WaveManager
@export var scroll_controller: ScrollController

const NORMAL_SCROLL_SPEED := 25.0
const ELITE_SCROLL_SPEED  := 12.5   # 50 % — scroll slows during elite encounter

@onready var fighter_scene:  PackedScene = preload("res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn")
@onready var drone_scene:    PackedScene = preload("res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn")
@onready var skimmer_scene:  PackedScene = preload("res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn")
@onready var gunship_scene:  PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")
@onready var bomber_scene:   PackedScene = preload("res://assault/scenes/enemies/bomber/bomber.tscn")

func _ready() -> void:
	_register_waves()

func _register_waves() -> void:

	# ── Wave 1 ── Formation: V of 5 fighters ────────────────────────────────
	# Teaches basic formation reading. Lead ship first, wings stagger in.
	wave_manager.register_wave(100.0, [
		{"scene": fighter_scene, "offset": Vector2(  0,  0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-40, 12), "delay": 0.10},
		{"scene": fighter_scene, "offset": Vector2( 40, 12), "delay": 0.10},
		{"scene": fighter_scene, "offset": Vector2(-80, 24), "delay": 0.20},
		{"scene": fighter_scene, "offset": Vector2( 80, 24), "delay": 0.20},
	])

	# ── Wave 2 ── Kamikaze surprise cluster ──────────────────────────────────
	# 4 drones lock on the player the moment they spawn — forces repositioning.
	wave_manager.register_wave(280.0, [
		{"scene": drone_scene, "offset": Vector2(-50,  0), "delay": 0.0},
		{"scene": drone_scene, "offset": Vector2(  0,  0), "delay": 0.0},
		{"scene": drone_scene, "offset": Vector2( 50,  0), "delay": 0.0},
		{"scene": drone_scene, "offset": Vector2( 25, 15), "delay": 0.2},
	])

	# ── Wave 3 ── Suppression: Gunship holds back, 4 fighters push ──────────
	# Gunship fires from safe distance; lights create density pressure.
	wave_manager.register_wave(460.0, [
		{"scene": gunship_scene, "offset": Vector2(  0,  0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-60, 20), "delay": 0.4},
		{"scene": fighter_scene, "offset": Vector2(-20, 20), "delay": 0.4},
		{"scene": fighter_scene, "offset": Vector2( 20, 20), "delay": 0.4},
		{"scene": fighter_scene, "offset": Vector2( 60, 20), "delay": 0.4},
	])

	# ── Wave 4 ── Formation: diagonal line (right-heavy approach) ───────────
	# Diagonal angle forces the player to shift position laterally.
	wave_manager.register_wave(650.0, [
		{"scene": fighter_scene, "offset": Vector2(-80,  0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-40, 14), "delay": 0.15},
		{"scene": fighter_scene, "offset": Vector2(  0, 28), "delay": 0.30},
		{"scene": fighter_scene, "offset": Vector2( 40, 42), "delay": 0.45},
		{"scene": fighter_scene, "offset": Vector2( 80, 56), "delay": 0.60},
	])

	# ── Wave 5 ── Sniper pass: 2 skimmers cross simultaneously + 3 fighters ─
	# Skimmers lock aim mid-pass while fighters create bullet pressure below.
	wave_manager.register_wave(850.0, [
		{
			"scene": skimmer_scene,
			"spawn_edge": "left",
			"offset": Vector2(0, -20),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: e.direction = 1.0,
		},
		{
			"scene": skimmer_scene,
			"spawn_edge": "right",
			"offset": Vector2(0, 20),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: e.direction = -1.0,
		},
		{"scene": fighter_scene, "offset": Vector2(-40, 0), "delay": 0.6},
		{"scene": fighter_scene, "offset": Vector2(  0, 0), "delay": 0.6},
		{"scene": fighter_scene, "offset": Vector2( 40, 0), "delay": 0.6},
	])

	# ── Wave 6 ── Bomber pass + covering fighters ────────────────────────────
	# Slow bomber crosses screen dropping bombs while fighters keep pressure up.
	wave_manager.register_wave(1050.0, [
		{
			"scene": bomber_scene,
			"spawn_edge": "left",
			"offset": Vector2(0, -10),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: e.direction = 1.0,
		},
		{"scene": fighter_scene, "offset": Vector2(-50,  0), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2(  0,  0), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2( 50,  0), "delay": 0.5},
	])

	# ── Wave 7 ── Pincer: symmetric 3+3 flanks + kamikaze center surprise ───
	# Left and right flanks compress safe zone; drones force a final reposition.
	wave_manager.register_wave(1250.0, [
		{"scene": fighter_scene, "offset": Vector2(-120,  0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2( -80, 12), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2( -40, 24), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2( 120,  0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(  80, 12), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(  40, 24), "delay": 0.0},
		{"scene": drone_scene,   "offset": Vector2( -30,  0), "delay": 0.8},
		{"scene": drone_scene,   "offset": Vector2(   0,  0), "delay": 0.8},
		{"scene": drone_scene,   "offset": Vector2(  30,  0), "delay": 0.8},
	])

	# ── Wave 8 ── Suppression: 2 gunships + 5 fighters ──────────────────────
	# Dual gunships split horizontal coverage; fighters fill the gaps.
	wave_manager.register_wave(1480.0, [
		{"scene": gunship_scene, "offset": Vector2(-55, 0), "delay": 0.0},
		{"scene": gunship_scene, "offset": Vector2( 55, 0), "delay": 0.0},
		{"scene": fighter_scene, "offset": Vector2(-80, 20), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2(-30, 20), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2(  0, 20), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2( 30, 20), "delay": 0.5},
		{"scene": fighter_scene, "offset": Vector2( 80, 20), "delay": 0.5},
	])

	# ── Wave 9 ── Asymmetric pincer: bombers both flanks + fighter center ────
	# Two bombers create persistent bomb zones from opposite directions.
	wave_manager.register_wave(1700.0, [
		{
			"scene": bomber_scene,
			"spawn_edge": "left",
			"offset": Vector2(0, -15),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: e.direction = 1.0,
		},
		{
			"scene": bomber_scene,
			"spawn_edge": "right",
			"offset": Vector2(0, 15),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: e.direction = -1.0,
		},
		{"scene": fighter_scene, "offset": Vector2(-40, 0), "delay": 0.3},
		{"scene": fighter_scene, "offset": Vector2(  0, 0), "delay": 0.3},
		{"scene": fighter_scene, "offset": Vector2( 40, 0), "delay": 0.3},
		{"scene": drone_scene,   "offset": Vector2(-20, 0), "delay": 0.9},
		{"scene": drone_scene,   "offset": Vector2( 20, 0), "delay": 0.9},
	])

	# ── Wave 10 ── Elite Encounter ───────────────────────────────────────────
	# Scroll slows to 50 %. Elite Gunship (500 HP, fast fire) + 3 fighter escort.
	# Scroll resumes to normal the moment the elite dies.
	wave_manager.register_wave(2000.0, [
		{
			"scene": gunship_scene,
			"offset": Vector2(0, 0),
			"delay": 0.0,
			"on_spawned": _setup_elite,
		},
		{"scene": fighter_scene, "offset": Vector2(-50, 22), "delay": 0.8},
		{"scene": fighter_scene, "offset": Vector2(  0, 22), "delay": 0.8},
		{"scene": fighter_scene, "offset": Vector2( 50, 22), "delay": 0.8},
	], ELITE_SCROLL_SPEED)


func _setup_elite(enemy: Node) -> void:
	var hp: Health = enemy.get_node("Health")
	hp.max_health = 500
	hp.current_health = 500
	enemy.fire_interval = 0.45
	enemy.died.connect(func() -> void:
		if scroll_controller:
			scroll_controller.set_speed(NORMAL_SCROLL_SPEED)
	)
