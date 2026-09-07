## Integration test for player-bullet lifetime and the pass-through rule.
##
## NOT purely characterization. Tests 1, 4 and 5 pin behaviour that already ships; tests 2 and 3
## assert *new* intent and are red before the change. Plan:
## `docs/plans/two-consecutive-reviews-asserted-that-a-player-bullet-dies-o/3-plan.md`.
##
## Two rules are under test, and they pull in opposite directions, which is why they live in one
## file:
##
##   1. **A player bullet is NOT consumed by a hurtbox it overlaps.** This is not new — it is what
##      ships today, by accident of three unrelated settings (`bullet.gd:84` emits `expired`
##      without freeing, the `queue_free()` at `:49` is gated on `range_px > 0.0`, and
##      `weapons/modes/default.tres` sets `range_px = 0.0`). The whole space-station mini-boss
##      rests on it: shots aimed at a turret have to survive crossing the armoured core, or the
##      turrets — and therefore the boss — become unkillable. See
##      `assault/scenes/enemies/space_station/ENEMY.md` -> "Core hurtbox: why it spans the whole
##      hull" and `test_space_station.gd`'s two real-physics bullet tests. Test 1 restates that
##      premise at the bullet level so the next person to touch projectile lifetime finds a red
##      test instead of an unwinnable boss.
##
##   2. **An unpooled projectile owns its own lifetime and frees itself when it leaves the
##      screen.** This IS new. Player bullets were the only projectiles in the game with no owner:
##      all four spawn sites did a plain `state.add_child(bullet)` and nothing in the repo listened
##      to their `expired`, so every shot ever fired stayed in the level for the whole mission.
##
## The tension between them is the reason the fix is `screen_exited -> queue_free` and NOT
## `expired -> queue_free`: `expired` also fires on an ordinary hurtbox hit, so wiring it would
## silently break rule 1.
##
## Lives in `integration/` rather than `unit/` because it loads real scenes and steps physics
## (`tests/README.md`: `unit/` is "no scene loading").
extends GutTest

const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SNIPER_BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/sniper_bullet.tscn")

## The bullet's HitBox sits on layer 64 with mask 513 (`bullet.tscn:44-45`).
const _HITBOX_LAYER: int = 64
## A layer inside that mask, so the HitBox can see our stand-in target.
const _TARGET_LAYER: int = 1


## `state` must carry a SCRIPT, not be a bare `Node`. Every behaviour resolves its actor with
## `state.get("actor")`, and `set("actor", x)` on a scriptless node is a silent no-op — so a
## `Node.new()` state makes `get("actor")` return null, every `fire()` early-returns, and test 3
## passes having spawned nothing at all.
class StubState extends Node:
	var actor: Node2D = null


## `actor.velocity` is read DIRECTLY (not through `get()`) by four behaviours
## (`straight_behavior.gd:19`, `long_range_behavior.gd:14`, `spread_behavior.gd:18`,
## `sniper_behavior.gd:84`), so a plain `Node2D` raises "Invalid access to property" and reds the
## test on setup rather than on behaviour. `pierce_module_active` IS read via `get()`, so it is
## safe either way — declared here anyway so the stub matches the real actor's surface.
class StubActor extends Node2D:
	var velocity: Vector2 = Vector2.ZERO
	var pierce_module_active: bool = false


var _container: Node2D
var _state: StubState
var _actor: StubActor
var _muzzle: Marker2D


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_actor = StubActor.new()
	_container.add_child(_actor)
	_actor.global_position = Vector2(400.0, 300.0)
	_muzzle = Marker2D.new()
	_actor.add_child(_muzzle)
	_state = StubState.new()
	_state.actor = _actor
	_container.add_child(_state)


func _mode(scene: PackedScene) -> WeaponModeResource:
	var mode := WeaponModeResource.new()
	mode.projectile_scene = scene
	mode.range_px = 0.0
	mode.damage = 50
	return mode


## Bullets the behaviours spawned, in spawn order.
func _spawned_bullets() -> Array[Bullet]:
	var out: Array[Bullet] = []
	for child in _state.get_children():
		if child is Bullet:
			out.append(child as Bullet)
	return out


func _notifier_of(bullet: Bullet) -> VisibleOnScreenNotifier2D:
	return bullet.get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D


# ---------------------------------------------------------------------------------------------
# 1. The pass-through premise — the rule the space station depends on.
# ---------------------------------------------------------------------------------------------

## A bullet overlapping a real HurtBox deals its damage and KEEPS FLYING, at full damage.
##
## The layers are not decoration: `hurtbox_component.gd:12` fires off the HurtBox's *own*
## `area_entered`, so a default `HurtBox.new()` (layer 1 / mask 1) never sees the bullet's HitBox
## on layer 64 and this test would pass without any collision ever happening.
func test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	_container.add_child(bullet)
	bullet.global_position = Vector2(400.0, 300.0)

	var hurtbox := HurtBox.new()
	hurtbox.collision_layer = _TARGET_LAYER
	hurtbox.collision_mask = _HITBOX_LAYER
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	hurtbox.add_child(shape)
	_container.add_child(hurtbox)
	hurtbox.global_position = Vector2(400.0, 300.0)
	watch_signals(hurtbox)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# NOTE: this assert's 4th parameter is an emission *index*, not a message — passing a string
	# there makes GUT compare a String to an int and the failure looks unrelated to the test.
	assert_signal_emitted_with_parameters(hurtbox, "received_damage", [50])
	assert_true(is_instance_valid(bullet) and bullet.is_inside_tree(),
			"a player bullet must NOT be consumed by a hurtbox it overlaps — the station boss "
			+ "becomes unkillable if it is (see this file's header)")
	assert_false(bullet.is_queued_for_deletion(), "the bullet must not have been queued for free")
	var hb := bullet.get_node("HitBox") as HitBox
	assert_eq(hb.damage, 50, "damage must not decay on a non-pierce hit")


# ---------------------------------------------------------------------------------------------
# 2 + 3. The new rule — an unpooled player bullet owns its own lifetime.
# ---------------------------------------------------------------------------------------------

## `VisibleOnScreenNotifier2D` is driven by the renderer and needs a draw pass, which a headless
## gate has no business reproducing. Every test below emits `screen_exited` by hand: the unit
## under test is OUR wiring, not Godot's culling.
func test_a_launched_bullet_frees_itself_when_it_leaves_the_screen() -> void:
	StraightBehavior.new().fire(_state, _mode(BULLET_SCENE), _muzzle)

	var bullets := _spawned_bullets()
	assert_eq(bullets.size(), 1, "StraightBehavior should have spawned exactly one bullet")
	var bullet := bullets[0]

	_notifier_of(bullet).screen_exited.emit()
	assert_true(bullet.is_queued_for_deletion(),
			"a launched bullet must free itself once it leaves the screen")

	await get_tree().process_frame
	assert_false(is_instance_valid(bullet), "the bullet should be gone after a frame")


## The invariant form: enumerate the behaviours from the class list rather than a hand-written
## list, so a SIXTH behaviour is covered on the day it is added rather than silently skipped.
##
## Two branches, each covering a distinct failure mode:
##   (a) `SniperBehavior.fire()` is a deliberate no-op (`sniper_behavior.gd:29-30`) — it spawns
##       through `start_charge` / `fire_from_charge`, so calling `fire()` would prove nothing.
##   (b) `BeamBehavior` spawns a `PiercingBeam`, not a `Bullet` (`beam_behavior.gd:40-42`), and
##       already owns its own frees (`:46`, `:141`) — asserted rather than skipped, so a new
##       behaviour cannot hide behind the same branch.
## An unrecognised behaviour class FAILS rather than passing over.
func test_every_weapon_behavior_hands_off_its_projectile_s_lifetime() -> void:
	var behaviors := _weapon_behavior_class_list()
	assert_gt(behaviors.size(), 0, "the class list should name at least one WeaponBehavior")

	for entry: Dictionary in behaviors:
		var class_id: String = entry["class"]
		var script: Script = load(entry["path"]) as Script
		assert_not_null(script, "%s should load from %s" % [class_id, entry["path"]])
		var behavior: WeaponBehavior = script.new()

		if class_id == "BeamBehavior":
			await _assert_beam_owns_its_own_projectiles(behavior)
			continue
		if class_id in ["StraightBehavior", "LongRangeBehavior", "SpreadBehavior"]:
			behavior.fire(_state, _mode(BULLET_SCENE), _muzzle)
		elif class_id == "SniperBehavior":
			var mode := _mode(SNIPER_BULLET_SCENE)
			behavior.start_charge(_state, mode, _muzzle)
			behavior.fire_from_charge(_state, mode)
		else:
			fail_test("Unrecognised WeaponBehavior '%s' (%s). Add a branch here: either it spawns "
					% [class_id, entry["path"]]
					+ "Bullets through fire(), or it owns its projectiles' lifetimes itself.")
			continue

		var bullets := _spawned_bullets()
		# Without this the connection loop below is vacuous and green — which is the DEFAULT
		# outcome of the obvious harness, not a hypothetical.
		assert_gt(bullets.size(), 0, "%s should have spawned at least one Bullet" % class_id)
		for bullet: Bullet in bullets:
			var notifier := _notifier_of(bullet)
			assert_not_null(notifier, "%s's bullet should carry a notifier" % class_id)
			assert_true(notifier.screen_exited.is_connected(bullet.queue_free),
					"%s must hand off its bullet's lifetime — every unpooled player projectile "
							% class_id
							+ "frees itself when it leaves the screen, or it leaks for the whole "
							+ "mission")
			bullet.free()


## `BeamBehavior` never spawns a `Bullet`; it spawns and frees its own `PiercingBeam`s.
func _assert_beam_owns_its_own_projectiles(behavior: WeaponBehavior) -> void:
	behavior.fire(_state, _mode(BULLET_SCENE), _muzzle)
	assert_eq(_spawned_bullets().size(), 0, "BeamBehavior.fire() is a no-op and spawns no Bullet")

	var muzzles: Array[Marker2D] = [_muzzle]
	behavior.tick(_state, _mode(BULLET_SCENE), muzzles, 0.016)
	assert_eq(_spawned_bullets().size(), 0, "BeamBehavior.tick() spawns a PiercingBeam, no Bullet")
	assert_eq(_piercing_beams().size(), 1, "BeamBehavior.tick() should have spawned one beam")

	behavior.release(_state)
	await get_tree().process_frame
	assert_eq(_piercing_beams().size(), 0, "BeamBehavior frees its own beams on release()")


func _piercing_beams() -> Array[Node]:
	var out: Array[Node] = []
	for child in _state.get_children():
		if child is PiercingBeam and not child.is_queued_for_deletion():
			out.append(child)
	return out


## Every class in the project whose declared base is `WeaponBehavior`. Reading the class list
## rather than naming the five we know about is the whole point: a hand-written list cannot see a
## class that does not exist yet.
func _weapon_behavior_class_list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in ProjectSettings.get_global_class_list():
		if entry.get("base", "") == "WeaponBehavior":
			out.append(entry)
	return out


# ---------------------------------------------------------------------------------------------
# 4. Boundary: the fix must not reach pooled bullets.
# ---------------------------------------------------------------------------------------------

## The obvious "simplification" of this change — putting the `queue_free()` inside
## `bullet.gd::_on_visible_on_screen_notifier_2d_screen_exited()` — quietly destroys
## `AllyFighter`'s pool, which recycles this same `bullet.tscn` (`ally_fighter.gd:11,22`).
##
## This is GREEN today, and that is the point: it guards the constraint, not the change.
##
## It deliberately does NOT assert `_idle.size()`. On the broken build `_recycle()` runs before
## the delete queue flushes, so the freed bullets DO get appended back to `_idle` and the size
## still reads 2 — a size assertion is green on exactly the build this test exists to catch. What
## actually breaks is `acquire()`: it errors at `bullet_pool.gd:67` and returns null.
##
## Parented pool -> ship -> container because `bullet_pool.gd:47` resolves its container as
## `get_parent().get_parent()` (harness copied from `test_radial_attack_pattern.gd:20-35`).
func test_a_pooled_bullet_survives_leaving_the_screen() -> void:
	var ship := Node2D.new()
	_container.add_child(ship)
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	pool.bullet_scene = BULLET_SCENE
	pool.pool_size = 2
	ship.add_child(pool)

	var first: Bullet = pool.acquire(Vector2(100.0, 100.0)) as Bullet
	var second: Bullet = pool.acquire(Vector2(120.0, 100.0)) as Bullet
	assert_not_null(first, "the pool should hand out its first bullet")
	assert_not_null(second, "the pool should hand out its second bullet")

	_notifier_of(first).screen_exited.emit()
	_notifier_of(second).screen_exited.emit()
	await get_tree().process_frame
	await get_tree().process_frame

	var reacquired: Bullet = pool.acquire(Vector2(140.0, 100.0)) as Bullet
	assert_not_null(reacquired,
			"a POOLED bullet must survive leaving the screen — the pool owns its lifetime. "
			+ "If this is null the free was moved into bullet.gd and AllyFighter's pool is drained "
			+ "(docs/BULLET_POOL.md: 'the pool is smart, bullets are dumb').")
	assert_true(is_instance_valid(reacquired), "the reacquired bullet must not be a freed instance")


# ---------------------------------------------------------------------------------------------
# 5. Characterization: what PierceModule does today.
# ---------------------------------------------------------------------------------------------

## PIN, NOT ENDORSEMENT. `PierceModule` ("Penetrating Rounds") is strictly a DOWNGRADE today,
## because the base gun already pierces without limit: equipping it only shrinks hits 2-4 from 50
## to 28/15/8, and once `pierces_remaining` reaches 0 the bullet flies on at 8 anyway.
##
## Whether the default gun should instead stop on its first damaging hit is a coupled, whole-game
## balance decision — it requires `SpaceStation`'s armoured core to stop absorbing shots aimed at
## its turrets (test 1) — so it is filed as its own backlog task rather than folded in here.
## Changing pierce behaviour should fail this test; that is the signal the change was deliberate.
func test_pierce_module_today_only_reduces_damage() -> void:
	var bullet := BULLET_SCENE.instantiate() as Bullet
	_container.add_child(bullet)
	bullet.pierces_remaining = Bullet.MAX_PIERCE
	var hb := bullet.get_node("HitBox") as HitBox

	var target := Area2D.new()
	_container.add_child(target)

	var seen: Array[int] = []
	for i in 4:
		seen.append(hb.damage)
		bullet._on_hit_box_area_entered(target)
		# `_apply_pierce` is deferred so the HurtBox reads the un-reduced value first.
		await get_tree().process_frame

	assert_eq(seen, [50, 28, 15, 8] as Array[int],
			"pierce damage decays by PIERCE_DAMAGE_FACTOR (0.55), rounded half away from zero")
	assert_eq(bullet.pierces_remaining, 0, "three pierces spent over the first three hits")
	assert_true(is_instance_valid(bullet) and not bullet.is_queued_for_deletion(),
			"the bullet is STILL ALIVE after exhausting its pierces — it flies on at reduced "
			+ "damage, which is why PierceModule reads as a limiter rather than an upgrade")


## The one free path a sniper bullet has today (`bullet.gd:71-76`): an `unlimited_pierce` bullet
## passes through every regular enemy, but an asteroid or ram-ship stops it dead for zero damage.
## `sniper_shot.tres:12` sets `range_px = 0.0`, so this is its ONLY self-destruct short of leaving
## the screen.
func test_an_unlimited_pierce_bullet_is_stopped_by_an_asteroid_for_zero_damage() -> void:
	var bullet := SNIPER_BULLET_SCENE.instantiate() as Bullet
	_container.add_child(bullet)
	bullet.unlimited_pierce = true
	var hb := bullet.get_node("HitBox") as HitBox

	var asteroid := Node2D.new()
	asteroid.add_to_group("asteroids")
	_container.add_child(asteroid)
	var area := Area2D.new()
	asteroid.add_child(area)

	bullet._on_hit_box_area_entered(area)

	assert_eq(hb.damage, 0, "the HitBox is zeroed first so a HurtBox firing after us reads 0")
	assert_true(bullet.is_queued_for_deletion(), "an asteroid stops an unlimited-pierce bullet")
