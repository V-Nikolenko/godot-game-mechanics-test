## INTENT tests for `LineOfSight` (global/enemy_ai/line_of_sight.gd) - new code, so these assert
## docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.2.2, not today's behaviour.
##
## Every case awaits one physics frame after placing bodies: a body added this frame is not in the
## physics server's broadphase until the next step, so a ray cast straight away would miss it.
extends GutTest

const FROM := Vector2.ZERO
const TO := Vector2(400.0, 0.0)


## A body that opts in through the duck-typed query rather than the `asteroids` group.
class Wreck extends StaticBody2D:
	var blocks := true

	func blocks_line_of_sight() -> bool:
		return blocks


func _body(node: PhysicsBody2D, at: Vector2, layer: int = CollisionLayers.ENVIRONMENT) -> PhysicsBody2D:
	node.collision_layer = layer
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	node.add_child(shape)
	add_child_autofree(node)
	node.global_position = at
	return node


func _rock(at: Vector2) -> StaticBody2D:
	var rock := _body(StaticBody2D.new(), at) as StaticBody2D
	rock.add_to_group("asteroids")
	return rock


func _clear(exclude: Array[RID] = []) -> bool:
	await get_tree().physics_frame
	return LineOfSight.clear(get_tree().root.world_2d.direct_space_state, FROM, TO, exclude)


func test_open_space_is_clear() -> void:
	assert_true(await _clear())


func test_an_asteroid_on_the_segment_blocks() -> void:
	_rock(Vector2(200.0, 0.0))
	assert_false(await _clear())


func test_removing_the_asteroid_clears_the_line() -> void:
	var rock := _rock(Vector2(200.0, 0.0))
	assert_false(await _clear())
	rock.free()
	assert_true(await _clear())


func test_a_plain_character_body_does_not_block() -> void:
	# A fighter stand-in on the beam's block layer: opt-in blocking means it is skipped.
	_body(CharacterBody2D.new(), Vector2(200.0, 0.0), CollisionLayers.ENVIRONMENT)
	assert_true(await _clear())


func test_a_body_answering_blocks_line_of_sight_blocks() -> void:
	_body(Wreck.new(), Vector2(200.0, 0.0))
	assert_false(await _clear())


func test_a_body_answering_false_does_not_block() -> void:
	var wreck := _body(Wreck.new(), Vector2(200.0, 0.0)) as Wreck
	wreck.blocks = false
	assert_true(await _clear())


func test_a_blocker_behind_the_target_is_clear() -> void:
	_rock(Vector2(600.0, 0.0))
	assert_true(await _clear())


func test_an_excluded_rid_is_clear() -> void:
	var rock := _rock(Vector2(200.0, 0.0))
	assert_true(await _clear([rock.get_rid()] as Array[RID]))


func test_a_blocker_behind_a_non_blocking_body_is_still_found() -> void:
	# The recast: the ray hits the fighter first, excludes it, and carries on to the rock.
	_body(CharacterBody2D.new(), Vector2(100.0, 0.0))
	_rock(Vector2(250.0, 0.0))
	assert_false(await _clear())


func test_a_body_on_an_unmasked_layer_does_not_block() -> void:
	var rock := _rock(Vector2(200.0, 0.0))
	rock.collision_layer = CollisionLayers.PLAYER_HURTBOX
	assert_true(await _clear())


func test_hazard_contact_layer_blocks() -> void:
	var rock := _rock(Vector2(200.0, 0.0))
	rock.collision_layer = CollisionLayers.HAZARD_CONTACT
	assert_false(await _clear())


func test_an_area_never_blocks() -> void:
	var area := Area2D.new()
	area.collision_layer = CollisionLayers.ENVIRONMENT
	var shape := CollisionShape2D.new()
	shape.shape = CircleShape2D.new()
	area.add_child(shape)
	area.add_to_group("asteroids")
	add_child_autofree(area)
	area.global_position = Vector2(200.0, 0.0)
	assert_true(await _clear())


func test_five_stacked_non_blocking_bodies_terminate_and_return_clear() -> void:
	for i in 5:
		_body(CharacterBody2D.new(), Vector2(100.0 + i * 20.0, 0.0))
	assert_true(await _clear(), "the recast cap is reached and the line counts as clear")
