## INTENT tests for `ContactProfile` and `ContactBlast` (`global/components/contact_profile.gd`,
## `global/components/contact_blast.gd`), the per-enemy rule for what touching an enemy does:
## NONE, COLLISION (always, every legacy enemy), RAMMING (only while armed), EXPLOSIVE (only while
## armed, then a blast that outlives the drone). Design: docs/plans/cmufs7ek60001nm2x6d0bt2et/
## 3-plan.md §2.3; task plan docs/plans/cmuj4y8qx006cp52x77tfozc2/3-plan.md.
##
## The fixture (`tests/helpers/contact_fixture.gd`) is a `BaseEnemy` with a code-built
## `ContactHitBox`, always parented to an OFFSET container `Node2D` so a blast placed in local
## instead of global coordinates — or left at the origin — fails the position case.
##
## Frame counting: the blast counts ITS OWN physics frames from the moment it enters the tree, so
## the lifetime case records `Engine.get_physics_frames()` on `tree_entered` and counts from there.
## GUT's awaiter can resume a frame late, which is why the counts come from the engine, never from
## the number passed to `wait_physics_frames()`.
extends GutTest

const Fixture := preload("res://tests/helpers/contact_fixture.gd")

const CONTAINER_OFFSET := Vector2(37, -21)
const ENEMY_POS := Vector2(250, 180)


func _container() -> Node2D:
	var c := Node2D.new()
	c.position = CONTAINER_OFFSET
	add_child_autofree(c)
	return c


func _spawn(p: ContactProfile, container: Node2D = null, pos: Vector2 = ENEMY_POS) -> BaseEnemy:
	var c := container if container != null else _container()
	var enemy := Fixture.build_enemy(p, pos)
	c.add_child(enemy)
	return enemy


func _blasts(container: Node) -> Array[ContactBlast]:
	var out: Array[ContactBlast] = []
	for child in container.get_children():
		if child is ContactBlast:
			out.append(child)
	return out


func _dummy_area() -> Area2D:
	var a := Area2D.new()
	autofree(a)
	return a


# ── Mode matrix ────────────────────────────────────────────────────────────────

func test_resting_hitbox_state_per_mode() -> void:
	var expected := {
		ContactProfile.Mode.NONE: false,
		ContactProfile.Mode.COLLISION: true,
		ContactProfile.Mode.RAMMING: false,
		ContactProfile.Mode.EXPLOSIVE: false,
	}
	var enemies := {}
	for mode: int in expected:
		enemies[mode] = _spawn(Fixture.profile(mode))
	await wait_physics_frames(2)
	for mode: int in expected:
		var enemy: BaseEnemy = enemies[mode]
		var on: bool = expected[mode]
		assert_eq(enemy.contact_hit_box.monitorable, on, "mode %d: monitorable at rest" % mode)
		assert_eq(enemy.contact_hit_box.monitoring, on, "mode %d: monitoring at rest" % mode)
		assert_false(enemy.contact_profile.is_armed(), "mode %d: never armed at rest" % mode)


func test_ramming_arms_and_disarms_through_deferred_toggles() -> void:
	var enemy := _spawn(Fixture.profile(ContactProfile.Mode.RAMMING))
	await wait_physics_frames(1)
	enemy.contact_profile.set_armed(true)
	assert_true(enemy.contact_profile.is_armed())
	assert_false(enemy.contact_hit_box.monitorable, "deferred: not applied inside the same call")
	await wait_physics_frames(1)
	assert_true(enemy.contact_hit_box.monitorable, "armed: monitorable")
	assert_true(enemy.contact_hit_box.monitoring, "armed: monitoring")

	enemy.contact_profile.set_armed(false)
	await wait_physics_frames(1)
	assert_false(enemy.contact_profile.is_armed())
	assert_false(enemy.contact_hit_box.monitorable, "disarmed: not monitorable")
	assert_false(enemy.contact_hit_box.monitoring, "disarmed: not monitoring")


## Boundary: arming only means something for RAMMING / EXPLOSIVE.
func test_set_armed_is_a_no_op_for_none_and_collision() -> void:
	var none := _spawn(Fixture.profile(ContactProfile.Mode.NONE))
	var collision := _spawn(Fixture.profile(ContactProfile.Mode.COLLISION))
	await wait_physics_frames(1)
	none.contact_profile.set_armed(true)
	collision.contact_profile.set_armed(true)
	await wait_physics_frames(1)
	assert_false(none.contact_profile.is_armed())
	assert_false(collision.contact_profile.is_armed())
	assert_false(none.contact_hit_box.monitorable, "NONE stays disabled")
	assert_false(none.contact_hit_box.monitoring, "NONE stays disabled")
	assert_true(collision.contact_hit_box.monitorable, "COLLISION untouched")

	collision.contact_profile.set_armed(false)
	await wait_physics_frames(1)
	assert_true(collision.contact_hit_box.monitorable, "disarming COLLISION does not switch it off")


# ── Contact ────────────────────────────────────────────────────────────────────

func test_armed_explosive_contact_reports_and_detonates_once() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var enemy := _spawn(p)
	p.set_armed(true)
	watch_signals(p)
	var area := _dummy_area()
	enemy.contact_hit_box.area_entered.emit(area)
	assert_signal_emit_count(p, "contact_made", 1)
	assert_signal_emitted_with_parameters(p, "contact_made", [area])
	assert_signal_emit_count(p, "detonated", 1)
	await wait_physics_frames(1)  # let the queued blast attach, so it is not an orphan at test end


func test_armed_ramming_contact_reports_without_detonating() -> void:
	var p := Fixture.profile(ContactProfile.Mode.RAMMING)
	var enemy := _spawn(p)
	var container := enemy.get_parent()
	p.set_armed(true)
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_emit_count(p, "contact_made", 1)
	assert_signal_not_emitted(p, "detonated")
	await wait_physics_frames(1)
	assert_eq(_blasts(container).size(), 0, "a rammer never spawns a blast")


func test_unarmed_ramming_and_explosive_contacts_are_ignored() -> void:
	for mode: int in [ContactProfile.Mode.RAMMING, ContactProfile.Mode.EXPLOSIVE]:
		var p := Fixture.profile(mode, 40.0, 25)
		var enemy := _spawn(p)
		watch_signals(p)
		enemy.contact_hit_box.area_entered.emit(_dummy_area())
		assert_signal_not_emitted(p, "contact_made", "mode %d unarmed" % mode)
		assert_signal_not_emitted(p, "detonated", "mode %d unarmed" % mode)


func test_collision_contact_always_reports() -> void:
	var enemy := _spawn(null)
	var p := enemy.contact_profile
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_emit_count(p, "contact_made", 1)
	assert_signal_not_emitted(p, "detonated")


func test_none_contact_is_ignored() -> void:
	var p := Fixture.profile(ContactProfile.Mode.NONE)
	var enemy := _spawn(p)
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_not_emitted(p, "contact_made")


# ── detonate() ─────────────────────────────────────────────────────────────────

func test_detonate_is_idempotent() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var enemy := _spawn(p)
	var container := enemy.get_parent()
	watch_signals(p)
	p.detonate()
	p.detonate()
	assert_signal_emit_count(p, "detonated", 1)
	assert_signal_emitted_with_parameters(p, "detonated", [enemy.global_position])
	await wait_physics_frames(1)
	assert_eq(_blasts(container).size(), 1, "one blast node")


func test_detonate_is_a_no_op_for_collision() -> void:
	var enemy := _spawn(null)
	var container := enemy.get_parent()
	watch_signals(enemy.contact_profile)
	enemy.contact_profile.detonate()
	assert_signal_not_emitted(enemy.contact_profile, "detonated")
	await wait_physics_frames(1)
	assert_eq(_blasts(container).size(), 0)


func test_detonate_outside_the_tree_warns_and_spawns_nothing() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var enemy := Fixture.build_enemy(p, ENEMY_POS)
	autofree(enemy)
	# Never entered the tree, so BaseEnemy._ready() never ran setup(): wire it by hand.
	p.setup(enemy, enemy.get_node("ContactHitBox") as HitBox, enemy.get_node("Health") as Health)
	watch_signals(p)
	p.detonate()
	assert_push_warning("ContactProfile")
	assert_signal_not_emitted(p, "detonated")


## Boundary: a blast must live at least 2 physics frames to be stepped and then reported.
func test_blast_frames_below_two_is_clamped_with_an_error() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	p.blast_frames = 1
	_spawn(p)
	assert_push_error("blast_frames")
	assert_eq(p.blast_frames, 2)


func test_the_blast_lands_in_the_owners_parent_at_its_position_and_outlives_it() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var enemy := _spawn(p)
	var container := enemy.get_parent()
	var owner_pos := enemy.global_position
	assert_ne(owner_pos, enemy.position, "sanity: the container offset makes global differ from local")
	p.detonate()
	enemy.queue_free()
	await wait_physics_frames(1)
	assert_false(is_instance_valid(enemy), "the owner is gone")
	var blasts := _blasts(container)
	assert_eq(blasts.size(), 1, "the blast is a child of the owner's parent")
	if blasts.is_empty():
		return
	var blast := blasts[0]
	assert_true(blast.is_inside_tree(), "the blast survives the owner's free")
	assert_eq(blast.global_position, owner_pos, "at the owner's global position")
	assert_eq(blast.collision_layer, CollisionLayers.ENEMY_HITBOX)
	assert_eq(blast.collision_mask, 0)
	assert_true(blast.monitorable)
	assert_eq(blast.damage, 25)
	assert_eq(blast.damage_type, HitBox.DamageType.CONTACT)
	var shape := blast.get_child(0) as CollisionShape2D
	assert_not_null(shape)
	if shape != null:
		assert_eq((shape.shape as CircleShape2D).radius, 40.0)


func test_the_blast_frees_itself_after_blast_frames_of_its_own() -> void:
	var blast := ContactBlast.spawn(_container(), Vector2(10, 10), 40.0, 25, 4)
	# Both ends recorded by the blast's own tree signals, never by when GUT's awaiter resumes (it can
	# resume a frame late). It enters in the message flush after physics frame N and must leave in
	# the end-of-frame deletion of frame N + 4: four physics ticks of its own, no more, no fewer.
	var frames := {"entered": -1, "exited": -1}
	blast.tree_entered.connect(func() -> void: frames["entered"] = Engine.get_physics_frames())
	blast.tree_exiting.connect(func() -> void: frames["exited"] = Engine.get_physics_frames())
	await wait_physics_frames(12)
	assert_gte(frames["entered"], 0, "the blast entered the tree")
	assert_false(is_instance_valid(blast), "the blast freed itself")
	assert_eq(frames["exited"] - frames["entered"], 4, "live for exactly blast_frames physics frames")


func test_armed_death_detonates_and_unarmed_death_does_not() -> void:
	var armed := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var armed_enemy := _spawn(armed)
	armed.set_armed(true)
	var unarmed := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var unarmed_container := _container()
	var unarmed_enemy := _spawn(unarmed, unarmed_container)
	watch_signals(armed)
	watch_signals(unarmed)
	armed_enemy.health.set_health(0)
	unarmed_enemy.health.set_health(0)
	assert_signal_emit_count(armed, "detonated", 1, "armed death detonates")
	assert_signal_not_emitted(unarmed, "detonated", "unarmed death never detonates")
	await wait_physics_frames(1)
	assert_eq(_blasts(unarmed_container).size(), 0, "no blast from an unarmed death")


## The Swarm's rule: its contact handler kills it, so contact and death both reach detonate()
## within one call stack. The flag is set before spawning, so the re-entry is a no-op.
func test_contact_then_death_in_one_call_detonates_once() -> void:
	var p := Fixture.profile(ContactProfile.Mode.EXPLOSIVE, 40.0, 25)
	var enemy := _spawn(p)
	var container := enemy.get_parent()
	p.set_armed(true)
	p.contact_made.connect(func(_a: Area2D) -> void: enemy.health.set_health(0))
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_emit_count(p, "detonated", 1)
	await wait_physics_frames(1)
	assert_eq(_blasts(container).size(), 1, "exactly one blast")


## Review round 1 B1: a deferred `container.add_child` whose container is freed first is dropped
## by the engine, and the orphan blast leaks. The blast defers on itself and frees itself instead.
func test_a_blast_whose_container_is_freed_before_the_flush_frees_itself() -> void:
	var container := Node2D.new()
	add_child(container)
	var blast := ContactBlast.spawn(container, Vector2.ZERO, 40.0, 25, 3)
	container.free()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(blast), "the orphaned blast freed itself")


# ── ARMOR (plan cmufs7ele0015nm2xvag3vrwc §2.6.3, X8 / X13) ───────────────────────

## Stands in for a player: a node with a recording `apply_knockback`, under which a real
## `HurtBox` hangs so `area.get_parent()` is the stub, exactly as for the real player.
class ShoveStub extends Node2D:
	var impulses: Array[Vector2] = []
	var hurt_box: HurtBox = HurtBox.new()

	func _init() -> void:
		add_child(hurt_box)

	func apply_knockback(impulse: Vector2) -> void:
		impulses.append(impulse)


## A target with a hurtbox but no `apply_knockback` at all.
class BareTarget extends Node2D:
	var hurt_box: HurtBox = HurtBox.new()

	func _init() -> void:
		add_child(hurt_box)


func _armor(shove_speed: float = 0.0) -> ContactProfile:
	var p := Fixture.profile(ContactProfile.Mode.ARMOR)
	p.shove_speed = shove_speed
	return p


func test_armor_is_appended_so_serialized_ints_do_not_shift() -> void:
	assert_eq(ContactProfile.Mode.NONE, 0)
	assert_eq(ContactProfile.Mode.COLLISION, 1)
	assert_eq(ContactProfile.Mode.RAMMING, 2)
	assert_eq(ContactProfile.Mode.EXPLOSIVE, 3)
	assert_eq(ContactProfile.Mode.ARMOR, 4)


func test_armor_starts_armed_with_the_hitbox_on() -> void:
	var enemy := _spawn(_armor())
	assert_true(enemy.contact_profile.is_armed(), "armed at setup()")
	await wait_physics_frames(2)
	assert_true(enemy.contact_hit_box.monitorable, "monitorable at rest")
	assert_true(enemy.contact_hit_box.monitoring, "monitoring at rest")


func test_armor_contact_reports_without_detonating_or_spawning_a_blast() -> void:
	var p := _armor()
	var enemy := _spawn(p)
	var container := enemy.get_parent()
	watch_signals(p)
	var area := _dummy_area()
	enemy.contact_hit_box.area_entered.emit(area)
	assert_signal_emit_count(p, "contact_made", 1)
	assert_signal_emitted_with_parameters(p, "contact_made", [area])
	assert_signal_not_emitted(p, "detonated")
	await wait_physics_frames(1)
	assert_eq(_blasts(container).size(), 0, "armour never spawns a blast")


func test_armor_set_armed_false_closes_the_hitbox_and_true_reopens_it() -> void:
	var p := _armor()
	var enemy := _spawn(p)
	await wait_physics_frames(1)
	p.set_armed(false)
	assert_false(p.is_armed())
	await wait_physics_frames(1)
	assert_false(enemy.contact_hit_box.monitorable, "closed: not monitorable")
	assert_false(enemy.contact_hit_box.monitoring, "closed: not monitoring")
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_not_emitted(p, "contact_made", "a closed armour reports nothing")
	p.set_armed(true)
	await wait_physics_frames(1)
	assert_true(enemy.contact_hit_box.monitorable, "reopened")


func test_armor_owner_death_never_detonates_armed_or_not() -> void:
	for armed: bool in [true, false]:
		var p := _armor()
		var container := _container()
		var enemy := _spawn(p, container)
		p.set_armed(armed)
		watch_signals(p)
		enemy.health.set_health(0)
		assert_signal_not_emitted(p, "detonated", "armed=%s" % armed)
		await wait_physics_frames(1)
		assert_eq(_blasts(container).size(), 0, "no blast, armed=%s" % armed)


func test_armor_contact_does_not_harm_its_owner() -> void:
	var p := _armor(260.0)
	var enemy := _spawn(p)
	var before: int = enemy.health.current_health
	var target := ShoveStub.new()
	add_child_autofree(target)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_eq(enemy.health.current_health, before, "touching never hurts the armoured owner")


func test_armor_shove_calls_apply_knockback_once_with_an_owner_to_target_impulse() -> void:
	var p := _armor(260.0)
	var enemy := _spawn(p)
	var target := ShoveStub.new()
	add_child_autofree(target)
	target.global_position = enemy.global_position + Vector2(30, 40)  # 50 px away, direction (0.6, 0.8)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_eq(target.impulses.size(), 1, "one call per armed touch")
	if target.impulses.is_empty():
		return
	assert_almost_eq(target.impulses[0].length(), 260.0, 0.01, "impulse is shove_speed long")
	assert_almost_eq(target.impulses[0].x, 156.0, 0.01, "points owner -> target (x)")
	assert_almost_eq(target.impulses[0].y, 208.0, 0.01, "points owner -> target (y)")


func test_armor_shove_with_zero_speed_calls_nothing() -> void:
	var enemy := _spawn(_armor(0.0))
	var target := ShoveStub.new()
	add_child_autofree(target)
	target.global_position = enemy.global_position + Vector2(30, 0)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_eq(target.impulses.size(), 0)


func test_armor_shove_onto_a_target_without_the_method_calls_nothing_and_errors_nothing() -> void:
	var p := _armor(260.0)
	var enemy := _spawn(p)
	var target := BareTarget.new()
	add_child_autofree(target)
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_signal_emit_count(p, "contact_made", 1, "the touch still reports")


func test_armor_shove_with_an_orphan_area_does_not_error() -> void:
	var p := _armor(260.0)
	var enemy := _spawn(p)
	watch_signals(p)
	enemy.contact_hit_box.area_entered.emit(_dummy_area())
	assert_signal_emit_count(p, "contact_made", 1)


func test_a_closed_armor_does_not_shove() -> void:
	var p := _armor(260.0)
	var enemy := _spawn(p)
	p.set_armed(false)
	var target := ShoveStub.new()
	add_child_autofree(target)
	target.global_position = enemy.global_position + Vector2(30, 0)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_eq(target.impulses.size(), 0)


## Only ARMOR shoves: a RAMMING profile with a (stray) shove_speed stays a plain contact.
func test_only_armor_shoves() -> void:
	var p := Fixture.profile(ContactProfile.Mode.RAMMING)
	p.shove_speed = 260.0
	var enemy := _spawn(p)
	p.set_armed(true)
	var target := ShoveStub.new()
	add_child_autofree(target)
	target.global_position = enemy.global_position + Vector2(30, 0)
	enemy.contact_hit_box.area_entered.emit(target.hurt_box)
	assert_eq(target.impulses.size(), 0)


# ── Rails ──────────────────────────────────────────────────────────────────────

func test_suspend_ai_arms_a_ramming_profile_and_leaves_collision_untouched() -> void:
	var ram := _spawn(Fixture.profile(ContactProfile.Mode.RAMMING))
	var legacy := _spawn(null)
	ram.suspend_ai()
	legacy.suspend_ai()
	assert_true(ram.contact_profile.is_armed(), "a rail arms a rammer")
	assert_false(legacy.contact_profile.is_armed(), "COLLISION has no armed state")
	await wait_physics_frames(1)
	assert_true(ram.contact_hit_box.monitorable)
	assert_true(legacy.contact_hit_box.monitorable, "legacy hitbox untouched")


# ── Engine pin (C5) ────────────────────────────────────────────────────────────

## Whether an area enabled WHILE already overlapping a hurtbox registers on the next step is engine
## behaviour, so it is pinned here, not assumed: disarmed for several frames → 0 hits; armed → the
## overlap is reported exactly once (not zero, not once per frame).
func test_arming_while_overlapping_a_player_hurtbox_registers_exactly_one_hit() -> void:
	var container := _container()
	var player := Fixture.build_player(ENEMY_POS)
	container.add_child(player)
	var hits: Array[int] = []
	(player.get_node("HurtBox") as HurtBox).received_damage.connect(func(d: int) -> void: hits.append(d))
	var enemy := _spawn(Fixture.profile(ContactProfile.Mode.RAMMING), container, ENEMY_POS + Vector2(5, 0))
	await wait_physics_frames(5)
	assert_eq(hits.size(), 0, "a disarmed rammer overlapping the player deals nothing")
	enemy.contact_profile.set_armed(true)
	await wait_physics_frames(5)
	assert_eq(hits, [Fixture.CONTACT_DAMAGE] as Array[int], "arming while overlapping: exactly one hit")
