## Characterization tests for `EnemyPathMover` (`assault/scenes/enemies/enemy_path_mover.gd`),
## taken before the Phase 1 architecture rework touches it
## (`docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md` §3 step 2, "t2-pin-path-mover"). Every
## path-driven Assault wave — `WaveManager`, `StationReinforcements`, the bonus-drone spawner —
## routes through this node, so these pins are what stops the brain/mover split (t10) from
## silently changing how a rail-driven ship moves, exits or gets its AI switched off.
##
## ── Harness notes ─────────────────────────────────────────────────────────────────────────────
##
## 1. `PathMoverActor` (`tests/helpers/path_mover_actor.gd`) is a bare `CharacterBody2D` —
##    `EnemyPathMover` only needs `get_parent() as CharacterBody2D` plus an optional child named
##    "AIStateMachine" — so these tests do not pull in `BaseEnemy`'s config/HurtBox/
##    AttackController machinery just to pin movement.
## 2. Every mover under test has its own `_physics_process` turned OFF right after it is added
##    (`mover.set_physics_process(false)`) and is ticked by calling `_physics_process(delta)`
##    directly, so elapsed time is exact and never depends on how many real engine frames this
##    test happened to run for — same technique as `unit/test_overheat_component.gd` and
##    `integration/test_spawn_camera_pan.gd` (`wm._process(0.0)`).
## 3. `StraightMovement` with `speed = 1.0, angle = 0.0` gives `sample(t) == Vector2(0.0, t)` —
##    an identity function of elapsed time — so a test can jump straight to an exact target
##    world-space offset in one `_physics_process(delta)` call instead of stepping through many
##    small frames. Used for the off-screen-cull boundary cases, where the exact offset matters.
## 4. The mover is added as a child only AFTER its host actor is already inside the tree, the same
##    order `wave_manager.gd:198` uses (`enemy_container.add_child(entity)` before
##    `entity.add_child(mover)`) — `_ready()` reads `get_parent()`, `get_viewport()` and the
##    "AIStateMachine" sibling, all of which need the real parent chain already in place.
extends GutTest

const PathMoverActor := preload("res://tests/helpers/path_mover_actor.gd")
const LIGHT_ASSAULT_SHIP_SCENE: PackedScene = \
		preload("res://assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn")

const _DT := 1.0 / 60.0


## A fresh `PathMoverActor` at `pos`, added to the tree via `add_child_autofree`.
func _spawn_actor(pos: Vector2 = Vector2.ZERO) -> CharacterBody2D:
	var actor: CharacterBody2D = PathMoverActor.new()
	actor.global_position = pos
	add_child_autofree(actor)
	return actor


## Attaches a mover to `actor`, disables its automatic ticking, and returns it.
func _attach_mover(actor: CharacterBody2D, movement: MovementResource) -> EnemyPathMover:
	var mover := EnemyPathMover.new()
	mover.movement = movement
	actor.add_child(mover)
	mover.set_physics_process(false)
	return mover


## A `Camera2D` at `pos`, added to the tree, made current, and freed with the test.
func _spawn_camera(pos: Vector2) -> Camera2D:
	var cam := Camera2D.new()
	add_child_autofree(cam)
	cam.global_position = pos
	cam.make_current()
	return cam


## A plain `Node` named "AIStateMachine" — matching the node name `EnemyPathMover._ready()`
## looks up by string, nothing more.
func _add_ai_state_machine(actor: Node) -> Node:
	var machine := Node.new()
	machine.name = "AIStateMachine"
	actor.add_child(machine)
	return machine


# ── 1. Position = spawn + sample(t) * WORLD_SCALE ─────────────────────────────

func test_position_follows_spawn_plus_sampled_movement_scaled_by_world_scale() -> void:
	var spawn := Vector2(100.0, 50.0)
	var actor := _spawn_actor(spawn)
	var movement := StraightMovement.new()
	movement.speed = 120.0
	movement.angle = PI / 2.0  # screen-right, per StraightMovement's own convention.
	var mover := _attach_mover(actor, movement)

	var elapsed := 0.0
	for _i in 10:
		mover._physics_process(_DT)
		elapsed += _DT

	var expected: Vector2 = spawn + movement.sample(elapsed) * ArenaCamera.WORLD_SCALE
	assert_almost_eq(actor.global_position.x, expected.x, 0.001)
	assert_almost_eq(actor.global_position.y, expected.y, 0.001)


# ── 2. Actor physics suspended, AIStateMachine disabled ───────────────────────

func test_actor_physics_processing_is_suspended_on_ready() -> void:
	var actor := _spawn_actor()
	# A freshly-added node with no `_physics_process` override defaults to NOT processing (Godot
	# only flips the flag on once a real physics frame has run), so physics is turned on
	# explicitly here to prove the mover's suspension, not merely observe an already-off default.
	actor.set_physics_process(true)
	assert_true(actor.is_physics_processing(), "sanity: explicitly turned on before the mover attaches")

	_attach_mover(actor, StraightMovement.new())
	assert_false(actor.is_physics_processing(), "EnemyPathMover must suspend the actor's own physics")


func test_ai_state_machine_child_is_disabled_on_ready() -> void:
	var actor := _spawn_actor()
	var state_machine := _add_ai_state_machine(actor)
	assert_eq(state_machine.process_mode, Node.PROCESS_MODE_INHERIT, "sanity: enabled before the mover attaches")
	_attach_mover(actor, StraightMovement.new())
	assert_eq(state_machine.process_mode, Node.PROCESS_MODE_DISABLED)


## Boundary: an actor with no "AIStateMachine" child (most path-driven ships that never carry
## their own AI) must not error on the lookup.
func test_actor_without_ai_state_machine_is_unaffected() -> void:
	var actor := _spawn_actor()
	_attach_mover(actor, StraightMovement.new())
	assert_null(actor.get_node_or_null("AIStateMachine"))


# ── 3. FREE_ON_DURATION: exit_time and total_duration() ───────────────────────

func test_free_on_duration_frees_at_the_explicit_exit_time() -> void:
	var actor := _spawn_actor()
	var movement := StraightMovement.new()  # duration == 0 -> total_duration() == INF
	var mover := _attach_mover(actor, movement)
	mover.exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
	mover.exit_time = 2.0

	mover._physics_process(1.5)
	assert_false(actor.is_queued_for_deletion(), "must not free before exit_time")

	# 1.5 + 0.5 == 2.0 exactly in binary floating point (both are exact powers-of-two fractions),
	# so this lands on the cutoff without float-rounding risk.
	mover._physics_process(0.5)  # elapsed == 2.0 exactly
	assert_true(actor.is_queued_for_deletion(), "must free once elapsed reaches exit_time")


func test_free_on_duration_falls_back_to_movement_total_duration_when_exit_time_is_zero() -> void:
	var actor := _spawn_actor()
	var movement := StraightMovement.new()
	movement.duration = 1.5
	var mover := _attach_mover(actor, movement)
	mover.exit_mode = EnemyPathMover.ExitMode.FREE_ON_DURATION
	mover.exit_time = 0.0  # 0 = use movement.total_duration()

	assert_eq(movement.total_duration(), 1.5, "sanity: the movement's own finite duration")
	mover._physics_process(1.0)
	assert_false(actor.is_queued_for_deletion(), "must not free before total_duration()")

	# 1.0 + 0.5 == 1.5 exactly in binary floating point, so this lands on the cutoff without
	# float-rounding risk.
	mover._physics_process(0.5)  # elapsed == 1.5 exactly
	assert_true(actor.is_queued_for_deletion(), "must free once elapsed reaches movement.total_duration()")


# ── 4. FREE_ON_SCREEN_EXIT: the 80 px margin ───────────────────────────────────

## Drives one actor through: enter the screen, sit exactly on the 80 px margin (not culled),
## then cross one unit past it (culled). A single continuous StraightMovement(speed=1, angle=0)
## makes sample(t) == Vector2(0, t), so `_physics_process(delta)` can jump straight to an exact
## target elapsed time without stepping through intermediate frames. Every delta below is a
## binary-exact fraction (0.5, 219.5, ...) so the additions that build up `_elapsed` cannot drift
## off the intended boundary through float rounding.
func test_off_screen_cull_boundary_at_exactly_80px_and_just_beyond() -> void:
	var cam_pos := Vector2(640.0, 360.0)
	_spawn_camera(cam_pos)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	assert_eq(vp, Vector2(1280.0, 720.0), "sanity: the project's fixed 1280x720 viewport")

	var actor := _spawn_actor(cam_pos)  # spawns dead centre: on screen from frame 1.
	var movement := StraightMovement.new()
	movement.speed = 1.0
	movement.angle = 0.0  # sample(t) == Vector2(0, t); WORLD_SCALE then doubles it.
	var mover := _attach_mover(actor, movement)

	# Frame 1: stay near centre (t=0.5 -> offset.y=1.0) so _has_been_on_screen latches true.
	mover._physics_process(0.5)
	assert_false(actor.is_queued_for_deletion(), "sanity: still on screen")

	# Jump to exactly the 80 px margin: offset.y == vp.y*0.5 + 80 == 440, so world y == 800,
	# matching the legacy cull rect's y -80..800 bound (WORLD_SCALE == 2, so t == 220 -> elapsed
	# so far is 0.5, so the next delta is 219.5).
	var margin_offset := vp.y * 0.5 + 80.0
	mover._physics_process(219.5)
	assert_eq(actor.global_position.y, cam_pos.y + margin_offset, "sanity: landed exactly on the margin")
	assert_false(actor.is_queued_for_deletion(), "exactly 80 px outside the viewport must NOT be culled")

	# One more world-space unit past the margin (t += 0.5 -> offset.y += 1.0).
	mover._physics_process(0.5)
	assert_eq(actor.global_position.y, cam_pos.y + margin_offset + 1.0, "sanity: one unit past the margin")
	assert_true(actor.is_queued_for_deletion(), "just beyond the 80 px margin must be culled")


## Boundary: an actor spawned off-screen that never enters the viewport is never culled, no
## matter how far it later drifts. `_check_off_screen` only starts culling AFTER
## `_has_been_on_screen` latches true, and that latch requires one frame inside the margin.
func test_actor_that_never_enters_the_screen_is_never_culled() -> void:
	var cam_pos := Vector2(640.0, 360.0)
	_spawn_camera(cam_pos)
	var vp: Vector2 = get_viewport().get_visible_rect().size

	# Spawn well beyond the margin already, and keep moving further away.
	var far_start := cam_pos + Vector2(0.0, vp.y * 0.5 + 500.0)
	var actor := _spawn_actor(far_start)
	var movement := StraightMovement.new()
	movement.speed = 50.0  # keeps drifting further away, still always off-screen.
	movement.angle = 0.0
	var mover := _attach_mover(actor, movement)

	for _i in 30:
		mover._physics_process(_DT)
	assert_false(actor.is_queued_for_deletion(), "an actor that never entered the screen must never be culled")


# ── 5. No-camera warning path ──────────────────────────────────────────────────

## No Camera2D anywhere in the tree: `get_camera_2d()` returns null. `_ready()` only
## `push_warning`s (which GUT does not treat as a failure — see tests/README.md), and
## `_check_off_screen` returns immediately whenever `cam` is null, so movement must keep working
## and the actor must never be culled however far it travels.
func test_no_camera_moves_without_error_and_is_never_culled() -> void:
	assert_null(get_viewport().get_camera_2d(), "sanity: no camera is current for this test")
	var spawn := Vector2(0.0, 0.0)
	var actor := _spawn_actor(spawn)
	var movement := StraightMovement.new()
	movement.speed = 500.0
	movement.angle = 0.0
	var mover := _attach_mover(actor, movement)

	var elapsed := 0.0
	for _i in 120:  # far more than enough to leave any plausible viewport far behind.
		mover._physics_process(_DT)
		elapsed += _DT

	var expected: Vector2 = spawn + movement.sample(elapsed) * ArenaCamera.WORLD_SCALE
	assert_almost_eq(actor.global_position.y, expected.y, 0.01, "movement must still be applied with no camera")
	assert_false(actor.is_queued_for_deletion(), "with no camera, off-screen culling must be skipped entirely")


# ── 6. Nose-down facing: atan2(-vel.x, vel.y) ──────────────────────────────────

func test_facing_matches_the_nose_down_convention() -> void:
	var actor := _spawn_actor()
	var movement := StraightMovement.new()
	movement.speed = 100.0
	movement.angle = PI / 4.0  # a diagonal, so both vel components are non-zero.
	var mover := _attach_mover(actor, movement)

	mover._physics_process(_DT)

	var vel: Vector2 = movement.sample(_DT) * ArenaCamera.WORLD_SCALE  # sample(0) == Vector2.ZERO
	var expected_rotation: float = atan2(-vel.x, vel.y)
	assert_almost_eq(actor.rotation, expected_rotation, 0.0001)


# ── 7. The real light_assault_ship.tscn (review F3) ────────────────────────────

## `LightAssaultShip`'s `AIStateMachine` states write `actor.velocity` and call
## `move_and_slide()` from `StateMachine._process` (`approach_state.gd:24-25`,
## `strafe_exit_state.gd:14-15`), which `set_physics_process(false)` does NOT stop — only the
## "AIStateMachine" name lookup does. This case must keep failing if that lookup is ever made
## conditional on a future `suspend_ai()` contract (t10 depends on this file staying green
## unchanged): attach a mover to the REAL scene and assert both effects independently.
func test_light_assault_ship_ai_state_machine_disabled_and_position_matches_path() -> void:
	var container := Node2D.new()
	add_child_autofree(container)

	var spawn := Vector2(300.0, 200.0)
	var entity := LIGHT_ASSAULT_SHIP_SCENE.instantiate() as CharacterBody2D
	assert_not_null(entity, "sanity: light_assault_ship.tscn's root must be a CharacterBody2D")
	entity.global_position = spawn
	container.add_child(entity)  # entity._ready() (incl. AIStateMachine.enter()) runs here.

	var state_machine := entity.get_node_or_null("AIStateMachine")
	assert_not_null(state_machine, "sanity: light_assault_ship.tscn must carry an AIStateMachine")
	assert_eq(state_machine.process_mode, Node.PROCESS_MODE_INHERIT, "sanity: enabled before the mover attaches")

	var movement := StraightMovement.new()
	movement.speed = 60.0
	movement.angle = 0.0
	var mover := EnemyPathMover.new()
	mover.movement = movement
	entity.add_child(mover)  # mirrors wave_manager.gd: mover attached AFTER the ship is ready.
	mover.set_physics_process(false)

	assert_eq(
		state_machine.process_mode, Node.PROCESS_MODE_DISABLED,
		"attaching a path mover must disable the ship's own AIStateMachine"
	)

	var elapsed := 0.0
	for _i in 20:
		mover._physics_process(_DT)
		elapsed += _DT

	var expected: Vector2 = spawn + movement.sample(elapsed) * ArenaCamera.WORLD_SCALE
	assert_almost_eq(entity.global_position.x, expected.x, 0.001)
	assert_almost_eq(entity.global_position.y, expected.y, 0.001)
