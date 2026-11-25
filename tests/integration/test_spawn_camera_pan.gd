## Every spawn site that turns a design-space offset into a world position used to add it to
## `cam.global_position` only. `ArenaCamera` pins `global_position` at the level origin (640, 360)
## forever and does all player-follow panning through `Camera2D.offset`
## (`arena_camera.gd:5-12, 89-90`), so a spawn meant to land off the visible edge could actually
## land ON screen once the player panned. Found and deliberately deferred while building the (since retired) space
## station's reinforcements rather than special-cased for one node — see
## `docs/plans/a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr/`.
##
## NOT characterization: this pins the FIXED behaviour (spawn position includes `cam.offset`),
## which nothing exercised before this fix — no test anywhere built a `Camera2D` for `WaveManager`
## or `Level1Director`'s bonus-drone spawner (see `1-context.md`). Boss escorts spawn at their bay's mouth, not at a camera
## offset: `test_fortress_reinforcements.gd::test_bay_launches_ignore_the_camera_pan` covers them.
extends GutTest

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


# ── 2. Level1Director's bonus-drone spawner ──────────────────────────────────

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
