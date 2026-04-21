extends Node

# GDD Phase 1 — Wave-based aerial combat
# Waves are now triggered by elapsed TIME (seconds) rather than scroll distance.
# Scroll can be re-added later; just reconnect ScrollController and swap the
# trigger units back to pixels — no other logic changes needed.

@export var wave_manager: WaveManager

# ── Ship Configurations ──────────────────────────────────────────────────────
# Each constant fully describes a ship: scene, stats, and shooting behaviour.
# Waves reference these by name and only specify position, path, and delay.
#
# "shooting" sub-dict (empty = no weapons):
#   fire_interval — seconds between shots
#   weapon_damage — bullet HitBox damage
#   aim_mode      — EnemyPathMover.AimMode (enemies only)
#
# Pool sizes (second arg to preload_pool) reflect the maximum number of that
# ship type that can be alive simultaneously across all waves.

const FIGHTER: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn"),
	"health":           60,
	"collision_damage": 20,
	"shooting": {
		"fire_interval": 0.8,
		"weapon_damage": 8,
		"aim_mode":      EnemyPathMover.AimMode.FORWARD,
	},
}

const DRONE: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/kamikaze_drone/kamikaze_drone.tscn"),
	"health":           30,
	"collision_damage": 30,
	"shooting":         {},   # pure ram — no weapons
}

const RAM_SHIP: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/ram_ship/ram_ship.tscn"),
	"health":           -1,
	"collision_damage": 50,
	"shooting":         {},
}

const SNIPER: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/sniper_skimmer/sniper_skimmer.tscn"),
	"health":           80,
	"collision_damage": 25,
	"shooting": {
		"fire_interval": 0.9,
		"weapon_damage": 15,
		"aim_mode":      EnemyPathMover.AimMode.PLAYER,
	},
}

const GUNSHIP: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/gunship/gunship.tscn"),
	"health":           200,
	"collision_damage": 30,
	"shooting": {
		"fire_interval": 0.6,
		"weapon_damage": 10,
		"aim_mode":      EnemyPathMover.AimMode.PLAYER,
	},
}

const BOMBER: Dictionary = {
	"scene":            preload("res://assault/scenes/enemies/bomber/bomber.tscn"),
	"health":           150,
	"collision_damage": 35,
	"shooting": {
		"fire_interval": 1.2,
		"weapon_damage": 12,
		"aim_mode":      EnemyPathMover.AimMode.PLAYER,
	},
}

const ALLY: Dictionary = {
	"scene":            preload("res://assault/scenes/allies/ally_fighter/ally_fighter.tscn"),
	"health":           10,
	"collision_damage": 25,
	"shooting": {
		"fire_interval": 0.75,
		"weapon_damage": 20,
	},
}


func _ready() -> void:
	print("[LEVEL] Level 1 started — time-based waves enabled")
	var existing := get_tree().root.get_node_or_null("HUD")
	if existing:
		existing.queue_free()
	get_tree().root.call_deferred("add_child", preload("res://assault/scenes/gui/hud.tscn").instantiate())

	_register_waves()


func _register_waves() -> void:


	# ── Wave 1 ── Formation: V of 5 fighters, straight down ─────────────────
	wave_manager.register_wave(2.0, [
		{"ship": FIGHTER, "offset": Vector2(  0,  0), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 90}},
		{"ship": FIGHTER, "offset": Vector2(-40, -12), "delay": 0.10, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 90}},
		{"ship": FIGHTER, "offset": Vector2( 40, -12), "delay": 0.10, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 90}},
		{"ship": FIGHTER, "offset": Vector2(-80, -24), "delay": 0.20, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 90}},
		{"ship": FIGHTER, "offset": Vector2( 80, -24), "delay": 0.20, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 90}},
	])
	
	# ── Ally Wave A ── 2 wingmen rise at mission start ───────────────────────
	wave_manager.register_wave(3.0, [
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(45, 0), "delay": 0.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 150, "angle": PI, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( -35, 0), "delay": 0.3,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 200, "angle": PI, "shoot": false, "rotate": false}},
	])

	# ── Wave 2 ── Formation: diagonal line, from top-right to down-left ────────────────────────
	wave_manager.register_wave(6.0, [
		{"ship": FIGHTER, "offset": Vector2( 100,  -56), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": -PI/3.6}},
		{"ship": FIGHTER, "offset": Vector2( 140, -42), "delay": 0.1, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": -PI/3.6}},
		{"ship": FIGHTER, "offset": Vector2( 180, -28), "delay": 0.2, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": -PI/3.6}},
		{"ship": FIGHTER, "offset": Vector2( 220, -14), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": -PI/3.6}},
		{"ship": FIGHTER, "offset": Vector2( 260, 0), "delay": 0.4, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": -PI/3.6}},
	])
	
		# ── Ally Wave A ── 2 wingmen rise at mission start ───────────────────────
	wave_manager.register_wave(7.0, [
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-180, 0), "delay": 0.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 130, "angle": PI, "shoot": false, "rotate": false}},
	])

	# ── Wave 2 ── Kamikaze surprise cluster, sine weave ─────────────────────
	wave_manager.register_wave(22.0, [
		{"ship": DRONE, "offset": Vector2(-50,  0), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.SINE, "speed": 140, "amplitude": 45}},
		{"ship": DRONE, "offset": Vector2(  0,  0), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.SINE, "speed": 140, "amplitude": 45}},
		{"ship": DRONE, "offset": Vector2( 50,  0), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.SINE, "speed": 140, "amplitude": 45}},
		{"ship": DRONE, "offset": Vector2( 25, 15), "delay": 0.2,  "path": {"type": EnemyPathMover.PathType.SINE, "speed": 140, "amplitude": 45}},
	])

	# ── Wave 3 ── Suppression: Gunship holds back, 4 fighters U-arc ─────────
	wave_manager.register_wave(38.0, [
		{"ship": GUNSHIP, "offset": Vector2(  0,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 50}},
		{"ship": FIGHTER, "offset": Vector2(-60, 20), "delay": 0.4, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 130, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(-20, 20), "delay": 0.4, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 130, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2( 20, 20), "delay": 0.4, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 130, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2( 60, 20), "delay": 0.4, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 130, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
	])

	# ── Wave 4 ── Formation: diagonal line, down-left ────────────────────────
	wave_manager.register_wave(55.0, [
		{"ship": FIGHTER, "offset": Vector2(-80,  0), "delay": 0.0,  "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
		{"ship": FIGHTER, "offset": Vector2(-40, 14), "delay": 0.15, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
		{"ship": FIGHTER, "offset": Vector2(  0, 28), "delay": 0.30, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
		{"ship": FIGHTER, "offset": Vector2( 40, 42), "delay": 0.45, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
		{"ship": FIGHTER, "offset": Vector2( 80, 56), "delay": 0.60, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
	])

	# ── Wave 4b ── Ram ship introduction ─────────────────────────────────────
	wave_manager.register_wave(68.0, [
		{"ship": RAM_SHIP, "offset": Vector2(  0,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 100}},
		{"ship": FIGHTER,  "offset": Vector2(-50, 10), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle":  PI/4}},
		{"ship": FIGHTER,  "offset": Vector2( 50, 10), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
	])

	# ── Ally Wave B ── 3 wingmen before the sniper pass ─────────────────────
	wave_manager.register_wave(76.0, [
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-50, 0), "delay": 0.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 120, "angle": PI - 0.25, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(  0, 0), "delay": 0.2,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 140, "angle": PI, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( 50, 0), "delay": 0.4,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 120, "angle": PI + 0.25, "shoot": false, "rotate": false}},
	])

	# ── Wave 5 ── Sniper pass: 2 skimmers + 3 fighters ──────────────────────
	wave_manager.register_wave(85.0, [
		{
			"ship": SNIPER,
			"spawn_edge": "left",
			"offset": Vector2(0, -20),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as SniperSkimmer).direction = 1.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 130, "angle": PI/2},
		},
		{
			"ship": SNIPER,
			"spawn_edge": "right",
			"offset": Vector2(0, 20),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as SniperSkimmer).direction = -1.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 130, "angle": -PI/2},
		},
		{"ship": FIGHTER, "offset": Vector2(-40, 0), "delay": 0.6, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 100, "angle":  PI/4}},
		{"ship": FIGHTER, "offset": Vector2(  0, 0), "delay": 0.6, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 100}},
		{"ship": FIGHTER, "offset": Vector2( 40, 0), "delay": 0.6, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 100, "angle": -PI/4}},
	])

	# ── Wave 6 ── Bomber crossing + covering fighters U-arcs ─────────────────
	wave_manager.register_wave(103.0, [
		{
			"ship": BOMBER,
			"spawn_edge": "left",
			"offset": Vector2(0, -10),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = 1.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 80, "angle": PI/2},
		},
		{"ship": FIGHTER, "offset": Vector2(-50,  0), "delay": 0.5, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 120, "duration": 3.8, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(  0,  0), "delay": 0.5, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 95}},
		{"ship": FIGHTER, "offset": Vector2( 50,  0), "delay": 0.5, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 120, "duration": 3.8, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
	])

	# ── Wave 7 ── Pincer: U_L/U_R arcs from flanks + SINE drones ───────────
	wave_manager.register_wave(120.0, [
		{"ship": FIGHTER, "offset": Vector2(-120,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 140, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2( -80, 12), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 110, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2( -40, 24), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude":  80, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2( 120,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 140, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(  80, 12), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 110, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(  40, 24), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude":  80, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": DRONE,   "offset": Vector2( -30,  0), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.SINE, "speed": 150, "amplitude": 50}},
		{"ship": DRONE,   "offset": Vector2(   0,  0), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.SINE, "speed": 150, "amplitude": 50}},
		{"ship": DRONE,   "offset": Vector2(  30,  0), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.SINE, "speed": 150, "amplitude": 50}},
	])

	# ── Ally Wave C ── 4 wingmen for heavy suppression ───────────────────────
	wave_manager.register_wave(136.0, [
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-60, 0), "delay": 0.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 150, "angle": PI - 0.2, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-20, 0), "delay": 0.15,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": PI - 0.05, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( 20, 0), "delay": 0.30,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": PI + 0.05, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( 60, 0), "delay": 0.45,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 150, "angle": PI + 0.2, "shoot": false, "rotate": false}},
	])

	# ── Wave 8 ── Suppression: 2 gunships + 2 ram ships + converging fighters
	wave_manager.register_wave(148.0, [
		{"ship": GUNSHIP,  "offset": Vector2(-55,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 50}},
		{"ship": GUNSHIP,  "offset": Vector2( 55,  0), "delay": 0.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 50}},
		{"ship": RAM_SHIP, "offset": Vector2(-30, 10), "delay": 0.6, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110}},
		{"ship": RAM_SHIP, "offset": Vector2( 30, 10), "delay": 0.6, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110}},
		{"ship": FIGHTER,  "offset": Vector2(-80, 20), "delay": 1.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle":  PI/4}},
		{"ship": FIGHTER,  "offset": Vector2(  0, 20), "delay": 1.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 100}},
		{"ship": FIGHTER,  "offset": Vector2( 80, 20), "delay": 1.0, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 110, "angle": -PI/4}},
	])

	# ── Wave 9 ── Asymmetric pincer: bombers crossing + U fighters + SINE drones
	wave_manager.register_wave(166.0, [
		{
			"ship": BOMBER,
			"spawn_edge": "left",
			"offset": Vector2(0, -15),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = 1.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 80, "angle": PI/2},
		},
		{
			"ship": BOMBER,
			"spawn_edge": "right",
			"offset": Vector2(0, 15),
			"delay": 0.0,
			"on_spawned": func(e: Node) -> void: (e as Bomber).direction = -1.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 80, "angle": -PI/2},
		},
		{"ship": FIGHTER, "offset": Vector2(-40, 0), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.U_L,  "amplitude": 110, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(  0, 0), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 95}},
		{"ship": FIGHTER, "offset": Vector2( 40, 0), "delay": 0.3, "path": {"type": EnemyPathMover.PathType.U_R,  "amplitude": 110, "duration": 3.5, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": DRONE,   "offset": Vector2(-20, 0), "delay": 0.9, "path": {"type": EnemyPathMover.PathType.SINE, "speed": 150, "amplitude": 55}},
		{"ship": DRONE,   "offset": Vector2( 20, 0), "delay": 0.9, "path": {"type": EnemyPathMover.PathType.SINE, "speed": 150, "amplitude": 55}},
	])

	# ── Ally Wave D ── 5 wingmen arrowhead for the elite encounter ───────────
	wave_manager.register_wave(180.0, [
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(  0, 0), "delay": 0.0,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 160, "angle": PI, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-40, 0), "delay": 0.2,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 140, "angle": PI - 0.18, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( 40, 0), "delay": 0.2,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 140, "angle": PI + 0.18, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2(-80, 0), "delay": 0.4,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 125, "angle": PI - 0.32, "shoot": false, "rotate": false}},
		{"ship": ALLY, "spawn_edge": "bottom", "offset": Vector2( 80, 0), "delay": 0.4,
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 125, "angle": PI + 0.32, "shoot": false, "rotate": false}},
	])

	# ── Wave 10 ── Elite Encounter ───────────────────────────────────────────
	wave_manager.register_wave(190.0, [
		{
			"ship": GUNSHIP,
			"offset": Vector2(0, 0),
			"delay": 0.0,
			"health": 500,  # Spawn override: set health directly (replaces on_spawned callback)
			"path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 35, "fire_interval": 0.4},
		},
		{"ship": FIGHTER, "offset": Vector2(-50, 22), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.U_L, "amplitude": 120, "duration": 4.0, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
		{"ship": FIGHTER, "offset": Vector2(  0, 22), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.STRAIGHT, "speed": 80}},
		{"ship": FIGHTER, "offset": Vector2( 50, 22), "delay": 0.8, "path": {"type": EnemyPathMover.PathType.U_R, "amplitude": 120, "duration": 4.0, "exit_mode": EnemyPathMover.ExitMode.FREE_ON_DURATION}},
	])


func _setup_elite(enemy: Node) -> void:
	var hp := enemy.get_node("Health") as Health
	hp.max_health = 500
	hp.current_health = 500
