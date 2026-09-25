## Unit tests for EnemyWorld, the static duck-typed lookup of the Assault-vs-Open-Space provider
## (global/enemy_ai/enemy_world.gd). ArenaCamera is the only shipped provider today; these tests
## exercise it directly rather than through a full level scene.
extends GutTest


func test_no_provider_means_no_arena_no_rect_no_cull_no_constraint() -> void:
	assert_null(EnemyWorld.arena(get_tree()))
	assert_false(EnemyWorld.has_projectile_world_rect(get_tree()))
	assert_eq(EnemyWorld.projectile_world_rect(get_tree()), Rect2())
	assert_false(EnemyWorld.has_cull_rect(get_tree()))
	assert_eq(EnemyWorld.cull_rect(get_tree()), Rect2())
	assert_false(EnemyWorld.has_movement_constraint(get_tree()))
	assert_null(EnemyWorld.movement_constraint(get_tree()))


func test_arena_camera_in_the_tree_is_the_provider() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	assert_eq(EnemyWorld.arena(get_tree()), cam)


func test_arena_camera_projectile_world_rect_matches_legacy_enemy_bullet_bounds() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	assert_eq(rect.position, Vector2(-164.0, -444.0))
	assert_eq(rect.end, Vector2(1444.0, 1164.0))


func test_arena_camera_cull_rect_is_camera_position_plus_or_minus_half_viewport_plus_or_minus_80() -> void:
	var cam := ArenaCamera.new()
	cam.global_position = Vector2(200.0, -50.0)
	add_child_autofree(cam)
	var vp : Vector2 = get_viewport().get_visible_rect().size
	assert_eq(vp, Vector2(1280.0, 720.0), "sanity: the project's fixed 1280x720 viewport")
	var rect := EnemyWorld.cull_rect(get_tree())
	assert_eq(rect.position, cam.global_position - vp * 0.5 - Vector2(80.0, 80.0))
	assert_eq(rect.end, cam.global_position + vp * 0.5 + Vector2(80.0, 80.0))


func test_arena_camera_has_no_movement_constraint_yet() -> void:
	## t4b state: ArenaCamera does not implement enemy_movement_constraint() yet (a later task
	## adds it), so the lookup must report "no constraint", not error.
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	assert_false(EnemyWorld.has_movement_constraint(get_tree()))
	assert_null(EnemyWorld.movement_constraint(get_tree()))


func test_plain_camera2d_is_not_a_provider() -> void:
	## Boundary: a bare Camera2D (the level_2.tscn shape) carries no ArenaCamera script and must
	## not be picked up as a provider.
	var cam := Camera2D.new()
	add_child_autofree(cam)
	assert_null(EnemyWorld.arena(get_tree()))
	assert_false(EnemyWorld.has_projectile_world_rect(get_tree()))
	assert_eq(EnemyWorld.projectile_world_rect(get_tree()), Rect2())
