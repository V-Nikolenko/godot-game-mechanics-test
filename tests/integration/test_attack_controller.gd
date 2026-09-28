## Integration tests for AttackController's brain-driven extensions — enabled (hold fire),
## driven_by_brain (tick()), fire_now() — and the accuracy hook on AimedAttackPattern /
## GatlingAttackPattern (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.7, task t8).
##
## The "default path unchanged" cases are the pin: they exercise AttackController and the two
## patterns exactly as light_assault_ship.gd, interceptor.gd and ally_fighter.gd configure them
## (default enabled/driven_by_brain, aim_at_player as before, the new accuracy at its 0.0
## default). Because all three ships only ever add a plain AttackController and one of these
## patterns — ally_fighter's ForwardAttackPattern is untouched by this task — pinning the
## component with defaults pins every current consumer without re-instantiating each scene.
## Everything else here is new code and asserts intent, not characterization.
##
## _process()/tick() are called by hand (tests/README.md:455) rather than through simulate(),
## so timing assertions are exact rather than approximate.
extends GutTest

const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/enemy_bullet/enemy_bullet.tscn")

var _container: Node2D
var _ship: Node2D
var _pool: BulletPool


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_ship = Node2D.new()
	_container.add_child(_ship)
	_ship.global_position = Vector2(400.0, 300.0)
	_pool = _make_pool(32)


func _make_pool(size: int) -> BulletPool:
	var pool := BulletPool.new()
	pool.name = "BulletPool"
	pool.bullet_scene = BULLET_SCENE
	pool.pool_size = size
	_ship.add_child(pool)
	return pool


func _fired() -> Array:
	var out: Array = []
	for child in _container.get_children():
		if child is EnemyBullet:
			out.append(child)
	return out


func _make_controller(pattern: AttackPatternResource) -> AttackController:
	var controller := AttackController.new()
	controller.pattern = pattern
	controller.bullet_pool = _pool
	_ship.add_child(controller)
	return controller


## aim_at_player = false isolates cadence from aiming; direction has its own cases below.
func _aimed_pattern(interval: float = 0.5) -> AimedAttackPattern:
	var p := AimedAttackPattern.new()
	p.fire_interval = interval
	p.aim_at_player = false
	return p


# ── Default path: unchanged cadence and direction ──────────────────────────────

func test_default_configured_controller_fires_on_every_interval_wrap() -> void:
	var controller := _make_controller(_aimed_pattern(0.5))
	controller._process(0.3)
	assert_eq(_fired().size(), 0, "no shot before the interval elapses")
	controller._process(0.3)
	assert_eq(_fired().size(), 1, "one shot once the interval wraps (0.6 >= 0.5)")
	controller._process(0.5)
	assert_eq(_fired().size(), 2, "cadence continues unchanged on the next interval")


func test_aimed_pattern_accuracy_zero_matches_todays_direct_aim() -> void:
	var player := Node2D.new()
	_container.add_child(player)
	player.add_to_group("player")
	player.global_position = _ship.global_position + Vector2(120.0, -160.0)

	var p := AimedAttackPattern.new()
	p.aim_at_player = true
	p.accuracy = 0.0
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = (player.global_position - _ship.global_position).normalized()
	assert_almost_eq((bullets[0] as EnemyBullet)._direction.angle(), expected.angle(), 0.001,
			"accuracy 0 must reproduce today's direct-aim-at-player direction")


func test_gatling_pattern_accuracy_zero_matches_todays_direct_aim() -> void:
	var player := Node2D.new()
	_container.add_child(player)
	player.add_to_group("player")
	player.global_position = _ship.global_position + Vector2(-90.0, 200.0)

	var p := GatlingAttackPattern.new()
	p.aim_at_player = true
	p.accuracy = 0.0
	p.spread_angle = 0.0  ## isolate direction from the random scatter
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected: Vector2 = (player.global_position - _ship.global_position).normalized()
	assert_almost_eq((bullets[0] as EnemyBullet)._direction.angle(), expected.angle(), 0.001,
			"accuracy 0 must reproduce today's direct-aim-at-player direction")


## BOUNDARY, matches both patterns' shipped no-player fallback (aimed_attack_pattern.gd,
## gatling_attack_pattern.gd) — now routed through TargetInfo.NO_TARGET_AIM.
func test_aimed_pattern_falls_back_to_down_with_no_player() -> void:
	var p := AimedAttackPattern.new()
	p.aim_at_player = true
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	assert_almost_eq((bullets[0] as EnemyBullet)._direction.angle(), Vector2.DOWN.angle(), 0.001)


# ── accuracy against a moving target: the intercept direction ──────────────────

func test_accuracy_one_against_a_moving_target_aims_at_the_intercept_point() -> void:
	var player := CharacterBody2D.new()
	_container.add_child(player)
	player.add_to_group("player")
	player.global_position = _ship.global_position + Vector2(300.0, 0.0)
	player.velocity = Vector2(0.0, -120.0)

	var p := AimedAttackPattern.new()
	p.aim_at_player = true
	p.accuracy = 1.0
	p.bullet_speed = 250.0
	p.fire(_ship, _pool)

	var bullets := _fired()
	assert_eq(bullets.size(), 1)
	var expected := TargetInfo.player(_ship.get_tree()).intercept(_ship.global_position, p.bullet_speed)
	assert_true(expected.ok, "the test's own target must have a solvable intercept")
	var expected_dir: Vector2 = (expected.point - _ship.global_position).normalized()
	assert_almost_eq((bullets[0] as EnemyBullet)._direction.angle(), expected_dir.angle(), 0.001,
			"accuracy 1 must aim at the lead point, not the player's current position")
	## The defining difference from accuracy 0: direct aim and the lead point are not the same
	## direction here, so a build that ignores accuracy would fail the assertion above.
	var direct_dir: Vector2 = (player.global_position - _ship.global_position).normalized()
	assert_gt(absf(expected_dir.angle_to(direct_dir)), 0.01,
			"the moving target must make direct aim and intercept aim actually differ")


# ── enabled: hold fire keeps the timer phase ────────────────────────────────────

func test_disabled_withholds_the_shot_but_keeps_the_timer_phase() -> void:
	var controller := _make_controller(_aimed_pattern(0.5))
	controller.enabled = false
	controller._process(0.5)
	assert_eq(_fired().size(), 0, "no shot while disabled")

	## Re-enabling partway through the NEXT interval must not fire early: the wrap already
	## consumed while disabled, so this frame is on interval 2's clock, not interval 1's.
	controller.enabled = true
	controller._process(0.2)
	assert_eq(_fired().size(), 0, "the interval that wrapped while disabled owes no shot back")
	controller._process(0.3)
	assert_eq(_fired().size(), 1, "fires once the (unaffected) timer phase wraps again")


# ── driven_by_brain: _process becomes inert, tick fires ─────────────────────────

func test_driven_by_brain_makes_process_inert() -> void:
	var controller := _make_controller(_aimed_pattern(0.5))
	controller.driven_by_brain = true
	controller._process(10.0)
	assert_eq(_fired().size(), 0, "_process must not advance the timer once brain-driven")


func test_driven_by_brain_fires_through_tick() -> void:
	var controller := _make_controller(_aimed_pattern(0.5))
	controller.driven_by_brain = true
	controller.tick(0.5)
	assert_eq(_fired().size(), 1, "tick() drives the same timer _process used to own")


# ── fire_now: fires immediately, ignoring the timer ─────────────────────────────

func test_fire_now_fires_immediately_regardless_of_timer_phase() -> void:
	var controller := _make_controller(_aimed_pattern(10.0))
	controller.fire_now()
	assert_eq(_fired().size(), 1, "fire_now fires without waiting for the interval")
	controller._process(0.016)
	assert_eq(_fired().size(), 1, "fire_now must not perturb the timer for the next scheduled shot")
