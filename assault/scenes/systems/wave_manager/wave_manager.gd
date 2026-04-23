class_name WaveManager
extends Node

signal wave_triggered(wave_index: int)
signal waves_complete

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
#   "ship":                     Dictionary        — must contain "scene": PackedScene
#   "offset":                   Vector2           — camera-relative position offset
#   "delay":                    float             — seconds after wave trigger before this spawn
#   "on_spawned":               Callable          — optional, receives the instantiated node
#   "movement":                 MovementResource  — optional, attaches EnemyPathMover
#   "exit_mode":                EnemyPathMover.ExitMode  — optional, defaults to FREE_ON_SCREEN_EXIT
#   "look_in_moving_direction": bool              — optional, defaults to true
# }
#
# Ships self-configure from their own ShipConfig resource on _ready().
# WaveManager does not apply stats, health, or shooting settings.

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
			if _next_wave_index >= _waves.size():
				waves_complete.emit()
				set_process(false)
		else:
			break

func register_wave(trigger_time: float, spawns: Array) -> void:
	_waves.append({"trigger": trigger_time, "spawns": spawns})

## Loads all waves from a LevelResource. Call this from a level node's _ready()
## as a replacement for manual register_wave() calls.
func load_level(level: LevelResource) -> void:
	for wave: WaveResource in level.waves:
		var spawns: Array = []
		for entry: SpawnEntryResource in wave.entries:
			spawns.append(_entry_to_dict(entry))
		register_wave(wave.trigger_time, spawns)
	print("[WaveManager] Loaded '%s' — %d waves" % [level.level_name, level.waves.size()])

## Converts a SpawnEntryResource to the Dictionary format _spawn_ship() understands.
func _entry_to_dict(entry: SpawnEntryResource) -> Dictionary:
	var d: Dictionary = {
		"ship": {"scene": entry.ship_scene},
		"offset": entry.base_offset,
		"delay": entry.spawn_delay,
		"movement": entry.movement,
		"exit_mode": entry.exit_mode,
		"look_in_moving_direction": entry.look_in_moving_direction,
	}
	if entry.formation:
		d["formation"] = entry.formation
	if not entry.initial_props.is_empty():
		# Convert initial_props dict to on_spawned Callable
		var props: Dictionary = entry.initial_props.duplicate()
		d["on_spawned"] = func(e: Node) -> void:
			for key: String in props:
				e.set(key, props[key])
	return d

func _trigger_wave(wave: Dictionary, index: int) -> void:
	print("[Wave %d] TRIGGERED at %.1fs — %d spawns" % [index, _time_elapsed, wave.spawns.size()])
	wave_triggered.emit(index)
	for spawn in wave.spawns:
		for entry in _expand_formation(spawn):
			_spawn_with_delay(entry)

## Expands a spawn dict that has a "formation" key into one dict per slot.
## Slots add their offset to the entry's base offset and their delay to the base delay.
## If no formation is present, returns [spawn] unchanged.
func _expand_formation(spawn: Dictionary) -> Array:
	if not spawn.has("formation"):
		return [spawn]
	var formation: FormationResource = spawn["formation"] as FormationResource
	if not formation:
		return [spawn]
	var slots: Array = formation.compute_slots()
	# Direct typed assignment — 'as Vector2' is invalid on built-in value types in GDScript 4.
	var base_offset: Vector2 = spawn.get("offset", Vector2.ZERO)
	var base_delay: float = spawn.get("delay", 0.0)
	var expanded: Array = []
	for slot: FormationResource.FormationSlot in slots:
		# Shallow duplicate is intentional: MovementResource is pure data with no mutable runtime
		# state — all expanded slots sharing the same resource reference is safe.
		var entry: Dictionary = spawn.duplicate()
		entry["offset"] = base_offset + slot.offset
		entry["delay"] = base_delay + slot.delay
		entry.erase("formation")
		expanded.append(entry)
	return expanded

func _spawn_with_delay(spawn: Dictionary) -> void:
	var delay: float = spawn.get("delay", 0.0)
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	_spawn_ship(spawn)

# ── Spawning ──────────────────────────────────────────────────────────────────

func _spawn_ship(spawn: Dictionary) -> void:
	var cam := get_viewport().get_camera_2d()
	if not cam:
		return

	# Resolve scene from ship dict
	var ship_dict: Dictionary = spawn.get("ship", {})
	var scene: PackedScene = ship_dict.get("scene") as PackedScene
	if not scene:
		return

	# Position: camera-relative offset. Use direct typed assignment — 'as Vector2' is
	# invalid on built-in value types in GDScript 4 and would silently return null.
	var spawn_pos: Vector2 = cam.global_position + spawn.get("offset", Vector2.ZERO)

	var entity: Node = scene.instantiate()
	entity.global_position = spawn_pos
	enemy_container.add_child(entity)
	print("[Spawn] %s at (%.0f, %.0f)" % [scene.resource_path.get_file(), spawn_pos.x, spawn_pos.y])

	if spawn.has("on_spawned"):
		spawn.on_spawned.call(entity)

	# Attach movement controller if a MovementResource is provided.
	if spawn.has("movement"):
		var mover := EnemyPathMover.new()
		mover.movement = spawn["movement"] as MovementResource
		if spawn.has("exit_mode"):
			mover.exit_mode = spawn["exit_mode"]  # enum (int) — direct assignment, no cast needed
		if spawn.has("look_in_moving_direction"):
			mover.look_in_moving_direction = spawn["look_in_moving_direction"]  # bool — direct assignment
		entity.add_child(mover)
