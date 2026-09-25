## Characterization tests for `PatrolDrone` (`open_space/scenes/entities/enemies/patrol_drone.gd`),
## taken before the Phase 1 architecture rework touches the enemy roster
## (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §3 step 3, "t3-pin-drones"). PatrolDrone is
## Open Space's only enemy today and is characterised rather than fixed (plan P-16): Phase 2's
## Swarm Drone replaces it, and this file is what makes that replacement's diff visible.
##
## Two of the cases below pin a KNOWN BUG, not a design choice (plan P-16, task acceptance
## criteria): the HurtBox's `collision_mask == 64` only accepts the player's primary-bullet
## layer, so the player's rockets (layer 32) pass straight through it, and the body sits on
## `collision_layer == 256` (`enemy_hitbox`), not `enemy_hurtbox` (512) or any hazard layer. Both
## are pinned as today's behaviour so a future fix is a visible, deliberate diff, not a silent one.
##
## Damage is delivered through the scene's own wiring — `drone.hurt_box.received_damage.emit(n)`,
## which is what `patrol_drone.tscn`'s `[connection signal="received_damage" ... method=
## "_on_received_damage"]` actually routes — rather than calling `_on_received_damage()` directly,
## so a test here would fail if that connection were ever removed from the scene. Same technique
## `test_base_enemy.gd` uses for `BaseEnemy`'s roster.
##
## The drift cases assert on `velocity`, never on accumulated `global_position`: PatrolDrone moves
## through `move_and_slide()`, which reads `get_physics_process_delta_time()` internally instead of
## taking a delta argument, and that value is not reliably `1/60` when the method is invoked by
## hand outside a real physics substep (confirmed empirically while writing the sibling
## `test_drone_interceptor.gd` — see that file's harness note 1). `velocity` is assigned directly by
## script logic before `move_and_slide()` ever runs, so a single tick reads back exactly what
## `_direction * move_speed` computes, unaffected by that unreliable delta — matching the same
## precedent `test_open_space_boost_verb.gd` established for `OpenSpacePlayerShip`.
extends GutTest

const PATROL_DRONE_SCENE: PackedScene = \
		preload("res://open_space/scenes/entities/enemies/patrol_drone.tscn")

const DT := 1.0 / 60.0

## `patrol_drone.tscn:12-13`: pinned separately from the HurtBox's own `collision_layer` (512,
## the standard `enemy_hurtbox` bit) because the body and the HurtBox area are different nodes
## with independent layers.
const _BODY_LAYER := 256
## `patrol_drone.tscn:33`: the bug this file pins (see header) — only the player's primary
## bullet layer (64) is accepted; the rocket layer (32) is not part of the mask.
const _HURTBOX_MASK := 64


## A fresh `PatrolDrone`, added to the tree via `add_child_autofree` so `_ready()` runs and
## `HealthComponent`'s invincibility `Timer` is built inside a live tree (tests/README.md).
func _spawn(direction: Vector2 = Vector2.RIGHT, speed: float = 60.0) -> PatrolDrone:
	var drone := PATROL_DRONE_SCENE.instantiate() as PatrolDrone
	assert_not_null(drone, "sanity: patrol_drone.tscn's root is not a PatrolDrone")
	drone.initial_direction = direction
	drone.move_speed = speed
	add_child_autofree(drone)
	drone.set_physics_process(false)  # ticked by hand below, so elapsed time is exact
	return drone


# ── 1. Drift = initial_direction * move_speed ─────────────────────────────────

func test_drifts_at_initial_direction_times_move_speed() -> void:
	var drone := _spawn(Vector2(1.0, 0.0), 90.0)

	drone._physics_process(DT)

	assert_almost_eq(drone.velocity.x, 90.0, 0.01)
	assert_almost_eq(drone.velocity.y, 0.0, 0.01)


## A diagonal direction, so the drift is checked on both axes at once, not just the axis the
## first case happens to use.
func test_drifts_along_a_diagonal_direction() -> void:
	var dir := Vector2(1.0, 1.0).normalized()
	var drone := _spawn(dir, 120.0)

	drone._physics_process(DT)

	var expected: Vector2 = dir * 120.0
	assert_almost_eq(drone.velocity.x, expected.x, 0.01)
	assert_almost_eq(drone.velocity.y, expected.y, 0.01)


## BOUNDARY: a zero `initial_direction` must not leave the drone motionless or produce a NaN
## velocity — `_ready()` falls back to `Vector2.RIGHT`.
func test_zero_initial_direction_falls_back_to_right() -> void:
	var drone := _spawn(Vector2.ZERO, 60.0)

	drone._physics_process(DT)

	assert_almost_eq(drone.velocity.x, 60.0, 0.01, "must fall back to RIGHT, not stall")
	assert_almost_eq(drone.velocity.y, 0.0, 0.01)


# ── 2. Scene-wired damage → health, death, free ────────────────────────────────

func test_scene_wired_damage_decreases_health() -> void:
	var drone := _spawn()
	assert_eq(drone.health_component.current_health, 50, "sanity: patrol_drone.tscn's shipped max_health")

	drone.hurt_box.received_damage.emit(20)

	assert_eq(drone.health_component.current_health, 30, "the HurtBox->_on_received_damage wiring must still route into Health.decrease()")


func test_health_reaching_zero_emits_died_and_frees_the_drone() -> void:
	var drone := _spawn()
	watch_signals(drone)

	drone.hurt_box.received_damage.emit(drone.health_component.max_health)

	assert_signal_emit_count(drone, "died", 1, "died must fire exactly once")
	assert_true(drone.is_queued_for_deletion(), "a dead drone must be queued for deletion")


## BOUNDARY: non-lethal damage must not emit died or free the drone.
func test_non_lethal_damage_does_not_emit_died() -> void:
	var drone := _spawn()
	watch_signals(drone)

	drone.hurt_box.received_damage.emit(1)

	assert_signal_not_emitted(drone, "died", "a non-lethal hit must not emit died")
	assert_false(drone.is_queued_for_deletion())


# ── 3. Characterization of a bug: HurtBox mask and body layer ─────────────────

## The player's rockets are collision layer 32 (`homing_missile.gd` / `warhead_missile.gd`);
## PatrolDrone's HurtBox mask is 64 (the player's primary bullet only), so a rocket overlaps the
## area without ever triggering `received_damage`. Pinned as today's bug (plan P-16), not fixed.
func test_hurtbox_mask_only_accepts_the_player_bullet_layer_rockets_pass_through() -> void:
	var drone := _spawn()
	assert_eq(drone.hurt_box.collision_mask, _HURTBOX_MASK, "characterization of a bug: see file header")
	const PLAYER_ROCKET_LAYER := 32
	assert_eq(
		drone.hurt_box.collision_mask & PLAYER_ROCKET_LAYER, 0,
		"characterization of a bug: the player's rockets must currently pass through unnoticed"
	)


func test_body_sits_on_the_enemy_hitbox_layer() -> void:
	var drone := _spawn()
	assert_eq(drone.collision_layer, _BODY_LAYER, "characterization: patrol_drone.tscn's body layer")
