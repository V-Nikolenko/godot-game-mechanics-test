## Every spawn site that turns a design-space offset into a world position used to add it to
## `cam.global_position` only. `ArenaCamera` pins `global_position` at the level origin (640, 360)
## forever and does all player-follow panning through `Camera2D.offset`
## (`arena_camera.gd:5-12, 89-90`), so a spawn meant to land off the visible edge could actually
## land ON screen once the player panned. Found and deliberately deferred while building station
## reinforcements (EPIC sub-item 4b) rather than special-cased for one node — see
## `docs/plans/a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr/`.
##
## NOT characterization: this pins the FIXED behaviour (spawn position includes `cam.offset`),
## which nothing exercised before this fix — no test anywhere built a `Camera2D` for `WaveManager`,
## `StationReinforcements` or `Level1Director`'s bonus-drone spawner (see `1-context.md`).
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const BONUS_DRONE_SCENE: PackedScene = preload("res://assault/scenes/enemies/bonus_drone/bonus_drone.tscn")

## ArenaCamera.V_LIMIT — the max vertical pan a player can reach. Chosen over an arbitrary value so
## the case is the actual worst case the game allows, not a smaller number that happens to work.
const _PAN_OFFSET: Vector2 = Vector2(0.0, 380.0)


## A bare `PackedScene` wrapping an empty `Node2D`, so `WaveManager._spawn_ship()` has something to
## `instantiate()` without pulling in a real enemy scene's config/AI dependencies.
func _blank_ship_scene() -> PackedScene:
	var root := Node2D.new()
	var packed := PackedScene.new()
	packed.pack(root)
	root.free()
	return packed


# ── 1. WaveManager ────────────────────────────────────────────────────────────

func test_wave_manager_spawn_includes_camera_pan() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = Vector2(640.0, 360.0)
	cam.offset = _PAN_OFFSET
	cam.make_current()

	var wm := WaveManager.new()
	wm.enemy_container = container
	add_child_autofree(wm)

	wm.register_wave(0.0, [{"ship": {"scene": _blank_ship_scene()}, "offset": Vector2(0.0, 150.0)}])
	wm._process(0.0)

	assert_eq(container.get_child_count(), 1, "the spawn must land in the enemy container")
	var expected: Vector2 = Vector2(640.0, 360.0) + _PAN_OFFSET + Vector2(0.0, 150.0) * ArenaCamera.WORLD_SCALE
	assert_eq((container.get_child(0) as Node2D).global_position, expected,
		"spawn position must include the camera's current pan, not just its resting position")


## Boundary: at rest (offset == ZERO) the formula must collapse to today's unchanged behaviour.
func test_wave_manager_spawn_unchanged_when_camera_is_at_rest() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = Vector2(640.0, 360.0)
	cam.make_current()

	var wm := WaveManager.new()
	wm.enemy_container = container
	add_child_autofree(wm)

	wm.register_wave(0.0, [{"ship": {"scene": _blank_ship_scene()}, "offset": Vector2(0.0, 150.0)}])
	wm._process(0.0)

	assert_eq((container.get_child(0) as Node2D).global_position, Vector2(640.0, 660.0),
		"at rest, the fix must not change the pre-existing spawn position")


# ── 2. StationReinforcements ──────────────────────────────────────────────────

func test_station_reinforcements_spawn_includes_camera_pan() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = Vector2(640.0, 360.0)
	cam.offset = _PAN_OFFSET
	cam.make_current()

	var station := STATION_SCENE.instantiate() as SpaceStation
	container.add_child(station)
	station.global_position = Vector2(640.0, 180.0)
	var reinf := station.get_node("Reinforcements") as StationReinforcements
	reinf._timer.stop()

	## Squad 0 (LEFT) is (-440, 20) and (-440, 80) design units — ENEMY.md's squad table.
	## Averaging the two spawned ships makes the assertion independent of spawn order.
	reinf.spawn_next_squad()

	var ships: Array[BaseEnemy] = []
	for child in container.get_children():
		if child != station and child is BaseEnemy:
			ships.append(child as BaseEnemy)
	assert_eq(ships.size(), 2, "squad 0 (LEFT) is two ships")

	var mean_pos: Vector2 = (ships[0].global_position + ships[1].global_position) * 0.5
	var expected_origin: Vector2 = Vector2(640.0, 360.0) + _PAN_OFFSET
	var expected_mean_design_offset: Vector2 = (Vector2(-440.0, 20.0) + Vector2(-440.0, 80.0)) * 0.5
	var expected_mean: Vector2 = expected_origin + expected_mean_design_offset * ArenaCamera.WORLD_SCALE
	assert_eq(mean_pos, expected_mean,
		"reinforcement spawn position must include the camera's current pan")


## Boundary: with no camera in the tree at all, `_spawn_origin()` must still take its fixed
## fallback unchanged — every existing reinforcements test relies on this path.
func test_station_reinforcements_spawn_origin_fallback_is_unchanged_with_no_camera() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var station := STATION_SCENE.instantiate() as SpaceStation
	container.add_child(station)
	station.global_position = Vector2(640.0, 180.0)
	var reinf := station.get_node("Reinforcements") as StationReinforcements

	assert_eq(reinf._spawn_origin(), Vector2(640.0, 360.0),
		"the no-camera fallback must be unaffected by this fix")


# ── 3. Level1Director's bonus-drone spawner ──────────────────────────────────

## `Level1Director._ready()` builds every Level 1 section, wires `director.start()` and
## deferred-adds a HUD scene to `get_tree().root` — none of it relevant to this one method's
## arithmetic, and reproducing it is exactly what leaves a test full of orphaned nodes. Instead:
## attach a plain `Node` to the tree first (so `NOTIFICATION_READY` fires on a script-less node,
## a no-op), THEN `set_script()` the director script onto it. Verified for this fix (see the plan's
## Risks section): a script attached after a node has already entered the tree does not have its
## `_ready()` invoked — the engine's ready notification already fired — while `get_viewport()`
## already works, because the node is genuinely inside the tree.
func test_bonus_drone_spawn_includes_camera_pan() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = Vector2(640.0, 360.0)
	cam.offset = _PAN_OFFSET
	cam.make_current()

	var wm := WaveManager.new()
	wm.enemy_container = container
	add_child_autofree(wm)

	var director_node := Node.new()
	add_child_autofree(director_node)
	director_node.set_script(DIRECTOR_SCRIPT)
	director_node.set("wave_manager", wm)

	director_node.call("_spawn_bonus_drone_left_to_right")

	assert_eq(container.get_child_count(), 1, "the bonus drone must land in the enemy container")
	## _spawn_bonus_drone_left_to_right() passes camera_offset = Vector2(-680, 60) — raw world px,
	## NOT design-scaled (level_1_director.gd:104-105), unlike the other two spawn sites.
	var expected: Vector2 = Vector2(640.0, 360.0) + _PAN_OFFSET + Vector2(-680.0, 60.0)
	assert_eq((container.get_child(0) as Node2D).global_position, expected,
		"bonus drone spawn position must include the camera's current pan")
