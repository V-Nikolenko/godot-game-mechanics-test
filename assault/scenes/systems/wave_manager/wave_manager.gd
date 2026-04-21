class_name WaveManager
extends Node

signal wave_triggered(wave_index: int)

@export var enemy_container: Node2D

# ── Wave registry ─────────────────────────────────────────────────────────────
# Each wave dict:
# {
#   "trigger": float,   — seconds after level start that fires this wave
#   "spawns": Array     — spawn descriptors
# }
#
# Each spawn dict:
# {
#   "ship":       Dictionary  — ship constant (scene + stats)
#   "offset":     Vector2     — position offset from screen edge centre
#   "delay":      float       — seconds after wave trigger before this spawn
#   "spawn_edge": String      — "top" | "bottom" | "left" | "right"  (default: "top")
#   "on_spawned": Callable    — optional, receives the instantiated node
#   "path":       Dictionary  — optional, attaches EnemyPathMover:
#     {
#       "type":      EnemyPathMover.PathType  (required)
#       "speed":     float
#       "angle":     float
#       "amplitude": float
#       "duration":  float
#       "exit_mode": EnemyPathMover.ExitMode
#       "shoot":     bool
#       "rotate":    bool   — false keeps actor's own rotation (use for allies)
#     }
# }

var _waves: Array[Dictionary] = []
var _next_wave_index: int = 0
var _time_elapsed: float = 0.0

# ── Time-based wave triggering ────────────────────────────────────────────────

func _process(delta: float) -> void:
	_time_elapsed += delta
	while _next_wave_index < _waves.size():
		var wave: Dictionary = _waves[_next_wave_index]
		if _time_elapsed >= wave.trigger:
			_trigger_wave(wave, _next_wave_index)
			_next_wave_index += 1
		else:
			break

func register_wave(trigger_time: float, spawns: Array) -> void:
	_waves.append({"trigger": trigger_time, "spawns": spawns})

func _trigger_wave(wave: Dictionary, index: int) -> void:
	print("[Wave %d] TRIGGERED at %.1fs — %d spawns" % [index, _time_elapsed, wave.spawns.size()])
	wave_triggered.emit(index)
	for spawn in wave.spawns:
		_spawn_with_delay(spawn)

func _spawn_with_delay(spawn: Dictionary) -> void:
	var delay: float = spawn.get("delay", 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_enemy(spawn)

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_enemy(spawn: Dictionary) -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	var ship_cfg: Dictionary = spawn.get("ship", {})
	var scene: PackedScene
	if not ship_cfg.is_empty() and ship_cfg.has("scene"):
		scene = ship_cfg["scene"] as PackedScene
	else:
		scene = spawn.get("scene") as PackedScene
	if not scene:
		return

	var offset: Vector2 = spawn.get("offset", Vector2.ZERO)
	var edge: String = spawn.get("spawn_edge", "top")
	var spawn_pos: Vector2

	match edge:
		"left":
			spawn_pos = Vector2(
				cam.global_position.x - viewport_size.x * 0.5,
				cam.global_position.y + offset.y
			)
		"right":
			spawn_pos = Vector2(
				cam.global_position.x + viewport_size.x * 0.5,
				cam.global_position.y + offset.y
			)
		"bottom":
			spawn_pos = Vector2(
				cam.global_position.x + offset.x,
				cam.global_position.y + viewport_size.y * 0.5 + offset.y
			)
		_: # "top"
			spawn_pos = Vector2(
				cam.global_position.x + offset.x,
				cam.global_position.y - viewport_size.y * 0.5 + offset.y
			)

	var enemy: Node = scene.instantiate()
	enemy.global_position = spawn_pos
	enemy_container.add_child(enemy)
	print("[Spawn] %s created at (%.0f, %.0f)" % [scene.resource_path.get_file(), spawn_pos.x, spawn_pos.y])

	if not ship_cfg.is_empty():
		_apply_ship_stats(enemy, ship_cfg)

	# Apply per-spawn overrides (health, collision_damage, shooting, etc.)
	_apply_spawn_overrides(enemy, spawn)

	if spawn.has("on_spawned"):
		spawn.on_spawned.call(enemy)

	if spawn.has("path"):
		var path_cfg: Dictionary = spawn["path"]
		var mover := EnemyPathMover.new()
		mover.path_type = path_cfg.get("type", EnemyPathMover.PathType.STRAIGHT)
		if path_cfg.has("speed"):
			mover.speed = path_cfg["speed"]
		if path_cfg.has("angle"):
			mover.path_angle = path_cfg["angle"]
		if path_cfg.has("amplitude"):
			mover.amplitude = path_cfg["amplitude"]
		if path_cfg.has("duration"):
			mover.duration = path_cfg["duration"]
		if path_cfg.has("exit_mode"):
			mover.exit_mode = path_cfg["exit_mode"]
		var ship_shooting: Dictionary = ship_cfg.get("shooting", {})
		if ship_shooting.is_empty():
			mover.shoot_while_on_path = false
		else:
			if ship_shooting.has("fire_interval"):
				mover.path_fire_interval = ship_shooting["fire_interval"]
			if ship_shooting.has("aim_mode"):
				mover.aim_mode = ship_shooting["aim_mode"]
			if ship_shooting.has("weapon_damage") and ship_shooting["weapon_damage"] > 0:
				mover.bullet_damage = ship_shooting["weapon_damage"]
		if path_cfg.has("fire_interval"):
			mover.path_fire_interval = path_cfg["fire_interval"]
		if path_cfg.has("aim_mode"):
			mover.aim_mode = path_cfg["aim_mode"]
		if path_cfg.has("shoot"):
			mover.shoot_while_on_path = path_cfg["shoot"]
		if path_cfg.has("rotate"):
			mover.rotate_actor = path_cfg["rotate"]
		enemy.add_child(mover)

## Applies health, collision damage, and shooting stats from a ship constant dict.
func _apply_ship_stats(enemy: Node, cfg: Dictionary) -> void:
	if cfg.has("health") and cfg["health"] > 0:
		var hp := enemy.get_node_or_null("Health") as Health
		if hp:
			hp.max_health = cfg["health"]
			hp.current_health = cfg["health"]
	if cfg.has("collision_damage"):
		for child in enemy.get_children():
			if child is HitBox:
				(child as HitBox).damage = cfg["collision_damage"]
				break
	var shooting: Dictionary = cfg.get("shooting", {})
	if not shooting.is_empty():
		if shooting.has("fire_interval") and enemy.get("fire_interval") != null:
			enemy.set("fire_interval", shooting["fire_interval"])
		if shooting.has("weapon_damage") and enemy.get("bullet_damage") != null:
			enemy.set("bullet_damage", shooting["weapon_damage"])
		if shooting.has("aim_mode") and enemy.get("aim_mode") != null:
			enemy.set("aim_mode", shooting["aim_mode"])

## Applies per-spawn stat overrides, taking precedence over ship constants.
## Supports: health, collision_damage, shooting (with nested aim_mode, fire_interval, weapon_damage).
func _apply_spawn_overrides(enemy: Node, spawn: Dictionary) -> void:
	var had_overrides: bool = false

	# Health override
	if spawn.has("health") and spawn["health"] > 0:
		var hp := enemy.get_node_or_null("Health") as Health
		if hp:
			hp.max_health = spawn["health"]
			hp.current_health = spawn["health"]
			had_overrides = true

	# Collision damage override
	if spawn.has("collision_damage"):
		for child in enemy.get_children():
			if child is HitBox:
				(child as HitBox).damage = spawn["collision_damage"]
				had_overrides = true
				break

	# Shooting overrides (aim_mode, fire_interval, weapon_damage)
	var shooting: Dictionary = spawn.get("shooting", {})
	if not shooting.is_empty():
		if shooting.has("fire_interval") and enemy.get("fire_interval") != null:
			enemy.set("fire_interval", shooting["fire_interval"])
			had_overrides = true
		if shooting.has("weapon_damage") and enemy.get("bullet_damage") != null:
			enemy.set("bullet_damage", shooting["weapon_damage"])
			had_overrides = true
		if shooting.has("aim_mode") and enemy.get("aim_mode") != null:
			enemy.set("aim_mode", shooting["aim_mode"])
			had_overrides = true

	if had_overrides:
		print("[Override] %s — spawn-level stats applied" % [enemy.name])
