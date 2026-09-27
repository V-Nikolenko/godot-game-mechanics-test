## INTENT test: an EXPLOSIVE enemy's blast really damages the player (epic review B1,
## docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.3; task docs/plans/cmuj4y8qx006cp52x77tfozc2).
##
## The rev-1 design put the blast under the dying drone: freed in the frame it was enabled, sitting
## at the canvas origin, and never stepped. Every flag- or signal-level assertion was green on that
## design while the player took no damage, so this file asserts the only observable that matters:
## the player's **health** drops, through real physics.
##
## Player side: a real `HurtBox` (layer 128, mask 1281 — `player_fighter.tscn`) driving a real
## `Health.decrease` (`PlayerBase._apply_damage` with no shield, temp HP or i-frames running).
## Enemy side: an EXPLOSIVE fixture whose contact box does NOT reach the player, so any damage can
## only have come from the blast. Everything sits off-origin, so a blast wrongly left at (0, 0) — the
## B1 bug — deals nothing and fails the first case.
extends GutTest

const Fixture := preload("res://tests/helpers/contact_fixture.gd")

const CONTAINER_OFFSET := Vector2(120, 80)
const PLAYER_POS := Vector2(300, 200)
const BLAST_RADIUS := 60.0
const BLAST_DAMAGE := 25
## 40 px: contact box r 10 + player r 12 = 22 < 40 (no contact), blast r 60 + 12 = 72 > 40 (hit).
const NEAR := Vector2(40, 0)
## 120 px: beyond blast r 60 + player r 12.
const FAR := Vector2(120, 0)


func _container() -> Node2D:
	var c := Node2D.new()
	c.position = CONTAINER_OFFSET
	add_child_autofree(c)
	return c


func _player(container: Node2D) -> Health:
	var player := Fixture.build_player(PLAYER_POS)
	container.add_child(player)
	return player.get_node("Health") as Health


func _enemy(container: Node2D, offset: Vector2) -> BaseEnemy:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, BLAST_RADIUS, BLAST_DAMAGE)
	var enemy := Fixture.build_enemy(p, PLAYER_POS + offset)
	container.add_child(enemy)
	return enemy


func _kill_after_settle(enemy: BaseEnemy, armed: bool) -> void:
	# Let the resting (disarmed) state and both areas settle in the physics server first.
	await wait_physics_frames(3)
	if armed:
		enemy.contact_profile.set_armed(true)
		await wait_physics_frames(2)
	enemy.health.set_health(0)
	await wait_physics_frames(5)


func test_an_armed_drone_killed_within_blast_radius_hurts_the_player_by_blast_damage() -> void:
	var container := _container()
	var health := _player(container)
	var enemy := _enemy(container, NEAR)
	await _kill_after_settle(enemy, true)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH - BLAST_DAMAGE,
		"the blast (not the contact box, which never reaches) deals exactly blast_damage")
	for child in container.get_children():
		assert_false(child is ContactBlast and not child.is_queued_for_deletion(),
			"the blast is gone after its frames")


func test_an_unarmed_drone_killed_within_blast_radius_deals_nothing() -> void:
	var container := _container()
	var health := _player(container)
	var enemy := _enemy(container, NEAR)
	await _kill_after_settle(enemy, false)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "dying unarmed never detonates")


func test_an_armed_drone_killed_outside_blast_radius_deals_nothing() -> void:
	var container := _container()
	var health := _player(container)
	var enemy := _enemy(container, FAR)
	await _kill_after_settle(enemy, true)
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH, "out of reach")


## The detonation runs inside the contact box's own `area_entered` callback, which the physics
## server emits while flushing queries. A direct `add_child` of an Area2D there logs "Can't change
## this state while flushing queries", and GUT 9.7.1 fails a test on an unexpected engine error — so
## this case fails if the blast is ever parented synchronously.
func test_detonating_from_inside_a_real_area_entered_callback_raises_no_error() -> void:
	var container := _container()
	var health := _player(container)
	# Start out of contact, arm, then let the contact box overlap the player for real.
	var enemy := _enemy(container, FAR)
	await wait_physics_frames(2)
	enemy.contact_profile.set_armed(true)
	var detonations: Array[Vector2] = []
	enemy.contact_profile.detonated.connect(func(at: Vector2) -> void: detonations.append(at))
	await wait_physics_frames(2)
	enemy.global_position = health.get_parent().global_position + Vector2(5, 0)
	await wait_physics_frames(5)
	assert_eq(detonations.size(), 1, "the real contact detonated the drone")
	assert_eq(get_errors().size(), 0, "no engine error from detonating inside the physics callback")
	# The contact box itself deals CONTACT_DAMAGE; the blast lands inside the player's i-frame-free
	# fixture too, so both hit.
	assert_eq(health.current_health, Fixture.PLAYER_MAX_HEALTH - Fixture.CONTACT_DAMAGE - BLAST_DAMAGE,
		"contact box and blast both land")


func test_the_blast_survives_its_owners_free() -> void:
	var container := _container()
	_player(container)
	var enemy := _enemy(container, NEAR)
	await wait_physics_frames(1)
	enemy.contact_profile.set_armed(true)
	enemy.health.set_health(0)  # BaseEnemy queue_free()s here
	await wait_physics_frames(1)
	assert_false(is_instance_valid(enemy), "the owner is freed")
	var blasts := container.get_children().filter(func(c: Node) -> bool: return c is ContactBlast)
	assert_eq(blasts.size(), 1, "the blast is still in the container")
