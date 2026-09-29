## The Fighter's shell (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.4, §2.2, §2.8; task
## t8a-fighter-shell). INTENT tests: scene wiring, pool sizing for both the AI and the rail cadences,
## the rail fallback read from config fields, `aim_mode` being rail-only, and the Assault exit.
## The attack run itself (pass geometry, weapon selection) is t8b and extends this file.
##
## Harness rules (same as test_razor_drone.gd): the harness is built inside the body, fighters are
## hand-ticked with `_tick()`, and the shipped config is read from the preloaded `.tres` and never
## written (a case that needs other values writes the fighter's PRIVATE `config`).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
## Shared, read-only: never written (CLAUDE.md config rule).
const CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")

const DT := 1.0 / 60.0
const MID := Vector2(640.0, 360.0)

const P := FighterBrain.Phase


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID
	return h


func _spawn(h: RefCounted, pos: Vector2, aim_mode: String = "", configure: Callable = Callable()) -> Fighter:
	var fighter := SCENE.instantiate() as Fighter
	fighter.global_position = pos
	fighter.aim_mode = aim_mode
	if configure.is_valid():
		configure.call(fighter.config)
	h.root.add_child(fighter)
	fighter.set_physics_process(false)
	return fighter


func _brain(f: Fighter) -> FighterBrain:
	return f.get_node("Brain") as FighterBrain


func _tick(f: BaseEnemy) -> void:
	var before := f.global_position
	f._physics_process(DT)
	f.global_position = before + f.velocity * DT


func _lifetime(round_scene: PackedScene, speed: float) -> float:
	var bullet := round_scene.instantiate() as EnemyBullet
	var life := (bullet.get_node("ProjectileLifetime") as ProjectileLifetime).max_distance / speed
	bullet.free()
	return life


func _bullets_under(root: Node) -> int:
	var n := 0
	for c in root.get_children():
		if c is EnemyBullet and (c as EnemyBullet).visible:
			n += 1
	return n


# ── Scene ────────────────────────────────────────────────────────────────────────────────────────

func test_the_scene_has_the_ai_stack_and_no_state_machine() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	assert_not_null(f.get_node_or_null("Brain") as FighterBrain)
	assert_not_null(f.get_node_or_null("EnemyMover") as EnemyMover)
	assert_not_null(f.get_node_or_null("StateLight") as StateLight)
	assert_null(f.get_node_or_null("AIStateMachine"), "the AIStateMachine is deleted")
	assert_false(DirAccess.dir_exists_absolute("res://assault/scenes/enemies/fighter/states"),
		"states/ is deleted")
	assert_eq((f.get_node("EnemyMover") as EnemyMover).constraint_mode, EnemyMover.ConstraintMode.AUTO)


func test_both_attack_controllers_are_brain_driven_and_disabled() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	for n in ["AimedAttack", "ForwardAttack"]:
		var a := f.get_node(n) as AttackController
		assert_true(a.driven_by_brain, "%s is driven by the brain" % n)
		assert_false(a.enabled, "%s starts disabled" % n)
	assert_eq((f.get_node("AimedAttack") as AttackController).bullet_pool, f.get_node("AimedPool"))
	assert_eq((f.get_node("ForwardAttack") as AttackController).bullet_pool, f.get_node("ForwardPool"))
	assert_same(_brain(f).attack, f.get_node("AimedAttack"))
	assert_same(_brain(f).forward_attack, f.get_node("ForwardAttack"))


## `BulletPool` resolves its container as `get_parent().get_parent()`: a pool under an
## `AttackController` would put live bullets under the ship, and they would move with it.
func test_every_bullet_pool_is_a_direct_child_of_the_root() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var pools := f.find_children("*", "BulletPool", true, false)
	assert_eq(pools.size(), 2)
	for p in pools:
		assert_eq(p.get_parent(), f, "%s is a direct child of the root" % p.name)


func test_the_pools_hold_the_pulse_and_scatter_rounds() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	assert_same((f.get_node("AimedPool") as BulletPool).bullet_scene, EnemyRounds.PULSE)
	assert_same((f.get_node("ForwardPool") as BulletPool).bullet_scene, EnemyRounds.SCATTER)


# ── Config ───────────────────────────────────────────────────────────────────────────────────────

## The mover follows the curve only if the sideways acceleration `turn_rate × max_speed` fits.
func test_config_pins_the_turn_against_the_acceleration() -> void:
	assert_true(CONFIG.turn_rate * CONFIG.max_speed <= CONFIG.acceleration,
		"turn_rate × max_speed ≤ acceleration")


func test_the_config_reaches_the_mover_and_the_hull() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(600, 0))
	var m := f.get_node("EnemyMover") as EnemyMover
	assert_eq(m.max_speed, CONFIG.max_speed)
	assert_eq(m.acceleration, CONFIG.acceleration)
	assert_eq(m.max_turn_rate, CONFIG.turn_rate)
	assert_eq(f.health.max_health, CONFIG.max_health)
	assert_eq(f.contact_hit_box.damage, CONFIG.collision_damage)
	assert_same(_brain(f).config, f.config)


func test_the_rail_fields_are_the_legacy_weapon() -> void:
	assert_eq(CONFIG.rail_aimed_speed, 250.0)
	assert_eq(CONFIG.rail_forward_speed, 420.0)
	assert_eq(CONFIG.rail_forward_interval, 0.3)
	assert_eq(CONFIG.fire_interval, 0.8)


# ── Pools (plan §2.2, review N4) ─────────────────────────────────────────────────────────────────

func test_the_aimed_pool_covers_the_ai_and_both_rail_cadences() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var size := (f.get_node("AimedPool") as BulletPool).pool_size
	var ai := EnemyRounds.pool_size_for(CONFIG.aimed_max,
		_lifetime(EnemyRounds.PULSE, CONFIG.aimed_speed), CONFIG.min_burst_period)
	var rail_forward := EnemyRounds.pool_size_for(1,
		_lifetime(EnemyRounds.PULSE, CONFIG.rail_forward_speed), CONFIG.rail_forward_interval)
	var rail_aimed := EnemyRounds.pool_size_for(1,
		_lifetime(EnemyRounds.PULSE, CONFIG.rail_aimed_speed), CONFIG.fire_interval)
	assert_gte(size, ai, "AI burst cadence")
	assert_gte(size, rail_forward, "rail FORWARD cadence (the station's shoot_forward fighters)")
	assert_gte(size, rail_aimed, "rail aimed cadence")


func test_the_forward_pool_covers_the_ai_forward_burst() -> void:
	var f := SCENE.instantiate() as Fighter
	add_child_autofree(f)
	var size := (f.get_node("ForwardPool") as BulletPool).pool_size
	var need := EnemyRounds.pool_size_for(CONFIG.forward_max,
		_lifetime(EnemyRounds.SCATTER, CONFIG.forward_speed), CONFIG.min_burst_period)
	assert_gte(size, need)


func test_a_pool_one_short_of_the_need_would_fail_the_check() -> void:
	# Boundary: the sizing rule is a real inequality, not a tautology.
	var need := EnemyRounds.pool_size_for(CONFIG.aimed_max,
		_lifetime(EnemyRounds.PULSE, CONFIG.aimed_speed), CONFIG.min_burst_period)
	assert_false(need - 1 >= need)
	assert_eq(need, 20, "5 rounds × ceil(4.67 s / 1.2 s)")


# ── Rail fallback (plan §2.8) ────────────────────────────────────────────────────────────────────

func test_suspend_installs_the_aimed_rail_pattern_from_config() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400))
	f.suspend_ai()
	var a := f.get_node("AimedAttack") as AttackController
	var p := a.pattern as AimedAttackPattern
	assert_false(a.driven_by_brain)
	assert_true(a.enabled)
	assert_eq(p.fire_interval, CONFIG.fire_interval)
	assert_eq(p.bullet_speed, CONFIG.rail_aimed_speed)
	assert_eq(p.bullet_damage, CONFIG.bullet_damage)
	assert_true(p.aim_at_player)
	assert_false((f.get_node("ForwardAttack") as AttackController).enabled)


func test_suspend_installs_the_forward_rail_pattern_from_config() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	var p := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	assert_eq(p.fire_interval, CONFIG.rail_forward_interval)
	assert_eq(p.bullet_speed, CONFIG.rail_forward_speed)
	assert_eq(p.bullet_damage, CONFIG.bullet_damage)
	assert_false(p.aim_at_player)


func test_the_config_default_aim_mode_is_used_when_no_spawn_prop_is_set() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "", func(c: FighterConfig) -> void: c.aim_mode = "FORWARD")
	f.suspend_ai()
	var p := (f.get_node("AimedAttack") as AttackController).pattern as AimedAttackPattern
	assert_eq(p.bullet_speed, CONFIG.rail_forward_speed, "the config's FORWARD applies")


## Rail fire is real: the self-timed controller puts Pulse rounds in the world at the rail cadence.
func test_a_rail_forward_fighter_fires_at_the_rail_interval() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	var a := f.get_node("AimedAttack") as AttackController
	for _i in 3:
		a.tick(CONFIG.rail_forward_interval + 0.001)
	assert_eq(_bullets_under(h.root), 3, "one Pulse round per rail_forward_interval")


func test_a_rail_fighter_is_silent_on_the_forward_controller() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(0, -400), "FORWARD")
	f.suspend_ai()
	(f.get_node("ForwardAttack") as AttackController).tick(5.0)
	assert_eq(_bullets_under(h.root), 0)


# ── aim_mode is rail-only ────────────────────────────────────────────────────────────────────────

func test_aim_mode_on_an_ai_fighter_changes_nothing() -> void:
	var h := _harness("open_space")
	var a := _spawn(h, MID + Vector2(700, -100), "")
	var b := _spawn(h, MID + Vector2(700, -100), "FORWARD")
	for _i in 60:
		_tick(a)
		_tick(b)
	assert_eq(b.velocity, a.velocity, "same motion")
	assert_eq(b.global_position, a.global_position)
	assert_eq(_brain(b).phase, _brain(a).phase)
	for n in ["AimedAttack", "ForwardAttack"]:
		assert_eq((b.get_node(n) as AttackController).enabled, (a.get_node(n) as AttackController).enabled)
		assert_true((b.get_node(n) as AttackController).driven_by_brain)
	assert_eq(_bullets_under(h.root), 0, "no AI firing yet (t8b)")


# ── APPROACH ─────────────────────────────────────────────────────────────────────────────────────

func test_approach_closes_on_the_player_and_holds_at_the_standoff() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	var brain := _brain(f)
	for _i in 600:
		_tick(f)
	assert_eq(brain.phase, P.APPROACH)
	# It brakes at the standoff, so it overshoots by roughly v² / 2·braking (~65 px).
	assert_almost_eq(f.global_position.distance_to(MID), CONFIG.standoff_radius, 100.0)


func test_phase_changed_carries_the_phase_entered() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(900, 0))
	watch_signals(_brain(f))
	_brain(f).enter_phase(P.TURN)
	assert_signal_emitted_with_parameters(_brain(f), "phase_changed", [P.TURN])


# ── Assault DISENGAGE ────────────────────────────────────────────────────────────────────────────

func test_the_assault_budget_expiry_enters_disengage() -> void:
	var h := _harness("assault")
	var f := _spawn(h, MID + Vector2(200, 0), "", func(c: FighterConfig) -> void: c.engage_seconds = 0.5)
	var brain := _brain(f)
	for _i in 20:
		_tick(f)
	assert_ne(brain.phase, P.DISENGAGE, "0.33 s in: still fighting")
	for _i in 20:
		_tick(f)
	assert_eq(brain.phase, P.DISENGAGE)


func test_assault_disengage_frees_the_fighter_outside_the_world_rect() -> void:
	var h := _harness("assault")
	var f := _spawn(h, MID + Vector2(200, 0))
	var brain := _brain(f)
	brain.enter_phase(P.DISENGAGE)
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var freed := false
	for _i in 1500:
		_tick(f)
		if f.is_queued_for_deletion():
			freed = true
			break
	assert_true(freed, "the fighter leaves and frees itself")
	assert_false(rect.has_point(f.global_position), "and it was outside the world rect when freed")


func test_open_space_never_disengages() -> void:
	var h := _harness("open_space")
	var f := _spawn(h, MID + Vector2(700, 0), "", func(c: FighterConfig) -> void: c.engage_seconds = 0.1)
	for _i in 120:
		_tick(f)
	assert_ne(_brain(f).phase, P.DISENGAGE)
	assert_false(f.is_queued_for_deletion())
