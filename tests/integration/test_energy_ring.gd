## INTENT tests for the Pulse Ring weapon: `EnergyRing` (assault/scenes/projectiles/enemy_beams/energy_ring.tscn)
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.5 and the two Pulse Ring rows of §2.3; task t3).
##
## Every behaviour row is hand-ticked at `DT` (the ring is owner-driven: `setup()`, `start()`, `tick(delta)`, `cancel()`) and runs in both
## harnesses. The static rows read the scene only. Every weapon number comes off the scene through `EnemyBeamScenes.ring_export` (fallback:
## the script default), every player number off an instance of `player_fighter.tscn` / `player_ship.tscn` - never typed here. `R` (reaction
## time) is a rule constant of §2.3.
##
## The ring's reach: the band's OUTER edge never passes `max_radius`, so a target is hittable up to `max_radius + R_t` from the centre
## (`R_t` = `EnergyHitScan.bounding_radius`) and not beyond (task decision, DECISIONS.md "Phase 8, built in t3").
##
## Victims are `fixture_enemy.tscn` with a 14 px `CircleShape2D` added to its `HurtBox` and group `enemies` joined at runtime, real
## asteroids, allies and player scenes. Gaps are made deterministic in the hit rows with `gap_spin_deg = 0` and a `start(gap_start_deg)`.
extends GutTest

const HARNESS := preload("res://tests/helpers/enemy_ai_harness.gd")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const ALLY_SCENE: PackedScene = preload("res://assault/scenes/allies/ally_fighter/ally_fighter.tscn")
const ASTEROID_SCENE: PackedScene = preload("res://assault/scenes/hazards/big_asteroid/big_asteroid.tscn")
const DUMB_ROCKET: PackedScene = preload("res://assault/scenes/projectiles/enemy_rockets/dumb_rocket.tscn")
const RING_SCRIPT: GDScript = preload("res://assault/scenes/projectiles/enemy_beams/energy_ring.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const FIXTURE_RADIUS := 14.0
const FIXTURE_HP := 1000
## Reaction time (§2.3): a rule constant, not tuning.
const R := 0.25
const CENTRE := Vector2(400.0, 300.0)
const OWNER_GROUP := &"ring_test_owner_group"

var _sandbox := SaveSandbox.new()


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


# ---------------------------------------------------------------------------------------------
# Builders and readers
# ---------------------------------------------------------------------------------------------

func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


func _default(property: StringName) -> Variant:
	return RING_SCRIPT.get_property_default_value(property)


func _export(property: StringName) -> Variant:
	return EnemyBeamScenes.ring_export(property, _default(property))


func _export_of_scene(scene: PackedScene, property: StringName) -> Variant:
	return EnemyBeamScenes.export_of_scene(scene, property, _default(property))


## Ticks a phase of [param seconds] lasts on the ring's clock (it ends on the tick whose summed delta reaches it).
func _ticks(seconds: float) -> int:
	return ceili(seconds / DT - 1e-3)


## The ring scene with [param changes] applied, re-packed: a synthetic copy for a boundary case.
func _synthetic(changes: Dictionary) -> PackedScene:
	var inst: Node = EnemyBeamScenes.ring_scene().instantiate()
	for key: StringName in changes:
		inst.set(key, changes[key])
	inst.scene_file_path = ""
	var scene := PackedScene.new()
	assert_eq(scene.pack(inst), OK, "the synthetic copy packs")
	inst.free()
	return scene


## A ring in the harness at [param at]; owner set from [param host] / [param group]; gaps held still unless [param spin] is true.
func _ring(h, host: Node2D = null, group: StringName = &"", at: Vector2 = CENTRE, spin: bool = false) -> EnergyRing:
	var r := EnemyBeamScenes.ring_scene().instantiate() as EnergyRing
	h.root.add_child(r)
	r.global_position = at
	if not spin:
		r.gap_spin_deg = 0.0
	r.setup(host, group)
	return r


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


## `fixture_enemy.tscn` made a ring victim: a 14 px circle on its `HurtBox` and group `enemies`.
func _victim(h, at: Vector2, hp: int = FIXTURE_HP) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(FIXTURE_RADIUS))
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = hp
	health.current_health = hp
	h.root.add_child(e)
	e.global_position = at
	return e


## A victim [param distance] px from the ring centre on [param bearing_deg].
func _victim_at(h, distance: float, bearing_deg: float, centre: Vector2 = CENTRE) -> BaseEnemy:
	return _victim(h, centre + Vector2.from_angle(deg_to_rad(bearing_deg)) * distance)


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


## Every `target_hit` as `[target, damage]`.
func _hits(r: EnergyRing) -> Array:
	var record: Array = []
	r.target_hit.connect(func(target: Node2D, damage: int) -> void: record.append([target, damage]))
	return record


func _hits_on(record: Array, target: Node) -> int:
	var n := 0
	for entry: Array in record:
		if entry[0] == target:
			n += 1
	return n


func _tick(r: EnergyRing, n: int) -> void:
	for i in n:
		r.tick(DT)


## Ticks [param r] until it is OFF (bounded), so a whole ring has passed.
func _run_out(r: EnergyRing) -> void:
	var cap := _ticks(float(_export(&"telegraph_seconds")) + float(_export(&"max_radius")) / float(_export(&"ring_speed"))
			+ float(_export(&"fade_seconds"))) + 10
	var n := 0
	while r.phase() != EnergyRing.Phase.OFF and n < cap:
		r.tick(DT)
		n += 1
	assert_eq(r.phase(), EnergyRing.Phase.OFF, "the ring ran out within its budget")


## The real player of [param mode] in place of the harness's stand-in, shield zeroed, health raised to [param hp].
func _real_player(h, mode: String, at: Vector2, hp: int) -> PlayerBase:
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var player: PlayerBase = (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate()
	h.root.add_child(player)
	player.global_position = at
	player.set_physics_process(false)
	player.set_process(false)
	player.shield_component.set_all_zero()
	player.health_component.max_health = hp
	player.health_component.current_health = hp
	return player


## `r_p`: the larger of the two player hurtboxes' circumscribed radius about the body origin (local transforms).
func _player_r_p() -> float:
	var r_p := 0.0
	for scene: PackedScene in [FIGHTER_SCENE, SHIP_SCENE]:
		var p := scene.instantiate() as PlayerBase
		var hurt := p.get_node("HurtBox") as Node2D
		for child in hurt.get_children():
			var cs := child as CollisionShape2D
			if cs == null or cs.disabled or cs.shape == null:
				continue
			var xf := hurt.transform * cs.transform
			var rect := cs.shape.get_rect()
			var far := 0.0
			for corner: Vector2 in [rect.position, rect.position + Vector2(rect.size.x, 0.0), rect.position + Vector2(0.0, rect.size.y), rect.end]:
				far = maxf(far, corner.length())
			var s := maxf(absf(xf.get_scale().x), absf(xf.get_scale().y))
			r_p = maxf(r_p, xf.origin.length() + far * s)
		p.free()
	return r_p


# ---------------------------------------------------------------------------------------------
# §2.5 timeline
# ---------------------------------------------------------------------------------------------

func test_timeline_phases_and_lethality(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var v := _victim_at(h, 10.0, 90.0)
	var phases: Array = []
	r.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var hits := _hits(r)
	var n_tel := _ticks(float(_export(&"telegraph_seconds")))
	assert_eq(r.phase(), EnergyRing.Phase.OFF, "%s: a fresh ring is OFF" % mode)
	assert_false(r.is_lethal(), "%s: OFF is not lethal" % mode)

	r.start(0.0)
	assert_eq(r.phase(), EnergyRing.Phase.TELEGRAPH, "%s: start() -> TELEGRAPH" % mode)
	_tick(r, n_tel - 1)
	assert_eq(r.phase(), EnergyRing.Phase.TELEGRAPH, "%s: still TELEGRAPH one tick before its end" % mode)
	assert_false(r.is_lethal(), "%s: TELEGRAPH is not lethal" % mode)
	assert_eq(r.radius(), 0.0, "%s: the band has not started to grow" % mode)
	assert_eq(hits.size(), 0, "%s: nothing is hit at TELEGRAPH end - 1 tick, though the fixture sits inside the band's reach" % mode)
	_tick(r, 1)
	assert_eq(r.phase(), EnergyRing.Phase.EXPANDING, "%s: EXPANDING on the tick the telegraph ends" % mode)
	assert_true(r.is_lethal(), "%s: EXPANDING is lethal" % mode)
	assert_eq(_hits_on(hits, v), 1, "%s: the fixture inside the first band is hit on the first EXPANDING tick" % mode)

	_tick(r, 6)
	var speed := float(_export(&"ring_speed"))
	assert_almost_eq(r.radius(), speed * 6.0 * DT, 0.5, "%s: the band grows at ring_speed" % mode)
	_run_out(r)
	assert_eq(phases, [EnergyRing.Phase.TELEGRAPH, EnergyRing.Phase.EXPANDING, EnergyRing.Phase.FADE, EnergyRing.Phase.OFF],
			"%s: phase_changed once per change, in order" % mode)
	for p: Variant in phases:
		assert_eq(typeof(p), TYPE_INT, "%s: phase_changed carries one int" % mode)
	assert_false(r.is_lethal(), "%s: OFF again, not lethal" % mode)


func test_ring_expands_to_max_radius_in_the_planned_time(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var max_radius := float(_export(&"max_radius"))
	var speed := float(_export(&"ring_speed"))
	r.start(0.0)
	var lethal_ticks := 0
	var fade_started := false
	var peak := 0.0
	var guard := 0
	while r.phase() != EnergyRing.Phase.OFF and guard < 400:
		r.tick(DT)
		guard += 1
		if r.is_lethal():
			lethal_ticks += 1
		peak = maxf(peak, r.radius())
		if r.phase() == EnergyRing.Phase.FADE:
			fade_started = true
	assert_true(fade_started, "%s: the ring reaches FADE" % mode)
	# The band's outer edge is capped at max_radius, so the band's centre radius tops out half a band short of it.
	assert_almost_eq(peak, max_radius - float(_export(&"band")) * 0.5, 0.01, "%s: the band's centre stops half a band inside max_radius" % mode)
	assert_almost_eq(float(lethal_ticks) * DT, max_radius / speed, 2.0 * DT, "%s: lethal for about max_radius / ring_speed (0.78 s)" % mode)


# ---------------------------------------------------------------------------------------------
# §2.5 hits
# ---------------------------------------------------------------------------------------------

func test_hits_a_fixture_once_when_the_band_passes(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	r.start(0.0)
	var v := _victim_at(h, 150.0, 90.0)
	var hits := _hits(r)
	var damage := int(_export(&"damage"))
	_tick(r, _ticks(float(_export(&"telegraph_seconds"))))
	assert_eq(hits.size(), 0, "%s: the band is still far from 150 px" % mode)
	_run_out(r)
	assert_eq(_hits_on(hits, v), 1, "%s: hit exactly once as the band passed (and while it lingered over the fixture)" % mode)
	assert_eq(_hp(v), FIXTURE_HP - damage, "%s: for damage" % mode)
	assert_eq(hits[0][1], damage, "%s: target_hit carries the damage" % mode)

	# Control: a new ring is a new hit.
	r.start(0.0)
	_run_out(r)
	assert_eq(_hits_on(hits, v), 2, "%s: a second ring hits the same fixture again (the once-per-ring table is cleared)" % mode)


func test_a_fixture_just_in_reach_is_hit_and_just_beyond_is_not(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	r.start(0.0)
	var max_radius := float(_export(&"max_radius"))
	var inside := _victim_at(h, max_radius, 90.0)
	var outside := _victim_at(h, max_radius, 270.0)
	# R_t is read off the fixture (its hurtbox sits off the node origin), then both are moved to the bounds.
	var r_t := EnergyHitScan.bounding_radius(outside)
	assert_gt(r_t, 0.0, "precondition: the fixture has a hurtbox radius")
	inside.global_position = CENTRE + Vector2.DOWN * (max_radius + r_t - 1.0)
	outside.global_position = CENTRE + Vector2.UP * (max_radius + r_t + 1.0)
	var hits := _hits(r)
	_run_out(r)
	assert_eq(_hits_on(hits, inside), 1, "%s: a fixture whose hurtbox just meets max_radius is hit" % mode)
	assert_eq(_hits_on(hits, outside), 0, "%s: a fixture at max_radius + R_t + 1 is never hit" % mode)
	assert_eq(_hp(outside), FIXTURE_HP, "%s: and loses nothing" % mode)


func test_gaps_pass_and_the_same_fixture_outside_one_is_hit(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var gap_deg := float(_export(&"gap_deg"))
	assert_eq(int(_export(&"gap_count")), 2, "precondition: two gaps")
	r.start(0.0)
	# Gap centres at 0 and 180 degrees, held still.
	var in_gap_a := _victim_at(h, 150.0, 0.0)
	var in_gap_b := _victim_at(h, 150.0, 180.0)
	var gap_edge := _victim_at(h, 150.0, gap_deg * 0.5 - 3.0)
	var outside := _victim_at(h, 150.0, 30.0)
	assert_gt(30.0, gap_deg * 0.5, "precondition: 30 degrees from a gap's centre is outside a 45 degree gap")
	var hits := _hits(r)
	_run_out(r)
	assert_eq(_hits_on(hits, in_gap_a), 0, "%s: a fixture in the first gap's bearing is not hit" % mode)
	assert_eq(_hits_on(hits, in_gap_b), 0, "%s: nor one in the second gap" % mode)
	assert_eq(_hits_on(hits, gap_edge), 0, "%s: nor one just inside the gap's edge" % mode)
	assert_eq(_hits_on(hits, outside), 1, "%s: the same distance 30 degrees from the gap is hit" % mode)
	assert_eq(_hp(in_gap_a), FIXTURE_HP, "%s: the gap passes with no damage" % mode)


func test_gaps_rotate_at_gap_spin(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h, null, &"", CENTRE, true)
	var spin := float(_export(&"gap_spin_deg"))
	assert_gt(spin, 0.0, "precondition: the shipped ring spins its gaps")
	r.start(10.0)
	var t0 := r.gap_center_deg(0)
	var t0b := r.gap_center_deg(1)
	assert_almost_eq(t0, 10.0, 0.001, "%s: the first gap starts at the bearing start() was given" % mode)
	assert_almost_eq(wrapf(t0b - t0, 0.0, 360.0), 360.0 / float(_export(&"gap_count")), 0.001, "%s: gaps are spread evenly" % mode)
	_tick(r, _ticks(0.5))
	assert_almost_eq(r.gap_center_deg(0) - t0, spin * 0.5, 0.6, "%s: 0.5 s later the gap has turned gap_spin_deg * 0.5" % mode)

	# A fixture on the gap's bearing at the moment the band passes is spared, even though the gap is turning.
	var h2 = _world(mode)
	var r2 := _ring(h2, null, &"", CENTRE, true)
	r2.start(0.0)
	_tick(r2, _ticks(float(_export(&"telegraph_seconds"))) + 1)
	var in_gap_now := _victim_at(h2, 150.0, r2.gap_center_deg(0))
	var hits := _hits(r2)
	_run_out(r2)
	assert_eq(_hits_on(hits, in_gap_now), 0, "%s: a fixture on a spinning gap's bearing when the band passes is spared" % mode)


func test_swept_interval_hits_a_fixture_the_band_crossed_between_ticks(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var band := float(_export(&"band"))
	var speed := float(_export(&"ring_speed"))
	r.start(0.0)
	var d := 190.0
	var v := _victim_at(h, d, 90.0)
	var r_t := EnergyHitScan.bounding_radius(v)
	var hits := _hits(r)
	r.tick(float(_export(&"telegraph_seconds")) + 0.375)
	var before := r.radius()
	assert_lt(before + band * 0.5 + r_t, d, "precondition: the band has not reached the fixture yet")
	assert_eq(hits.size(), 0, "%s: not hit yet" % mode)
	var step := 0.25
	r.tick(step)
	var after := r.radius()
	assert_almost_eq(after - before, speed * step, 0.01, "precondition: the band moved a whole step")
	assert_gt(after - band * 0.5 - r_t, d, "precondition: the band is already past the fixture at the tick's end (a point-in-time test would miss it)")
	assert_eq(_hits_on(hits, v), 1, "%s: the swept interval hit it" % mode)


func test_owner_set_is_exempt(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var host := _victim_at(h, 0.0, 0.0)
	var member := _victim_at(h, 150.0, 90.0)
	member.add_to_group(OWNER_GROUP)
	var control := _victim_at(h, 150.0, 270.0)
	var r := _ring(h, host, OWNER_GROUP)
	var hits := _hits(r)
	r.start(0.0)
	_run_out(r)
	assert_eq(_hits_on(hits, host), 0, "%s: the host (inside the ring's first band) is never hit" % mode)
	assert_eq(_hp(host), FIXTURE_HP)
	assert_eq(_hits_on(hits, member), 0, "%s: a member of the owner group is never hit" % mode)
	assert_eq(_hp(member), FIXTURE_HP)
	assert_eq(_hits_on(hits, control), 1, "%s: control: the same fixture outside the group is hit" % mode)


func test_victims(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var damage := int(_export(&"damage"))
	var r := _ring(h)
	var enemy := _victim_at(h, 100.0, 90.0)
	var asteroid: Node2D = ASTEROID_SCENE.instantiate()
	h.root.add_child(asteroid)
	asteroid.global_position = CENTRE + Vector2.from_angle(deg_to_rad(270.0)) * 150.0
	asteroid.set_physics_process(false)
	var player := _real_player(h, mode, CENTRE + Vector2.from_angle(deg_to_rad(45.0)) * 220.0, 10 * damage)
	var ally: Node2D = null
	if mode == "assault":
		ally = ALLY_SCENE.instantiate()
		h.root.add_child(ally)
		ally.global_position = CENTRE + Vector2.from_angle(deg_to_rad(135.0)) * 200.0
		ally.set_physics_process(false)
	var asteroid_hp := _hp(asteroid)
	var ally_hp := _hp(ally) if ally != null else 0
	var hits := _hits(r)
	r.start(0.0)
	_run_out(r)
	assert_eq(_hits_on(hits, enemy), 1, "%s: a fixture enemy is hit" % mode)
	assert_eq(_hp(enemy), FIXTURE_HP - damage, "%s: for damage" % mode)
	assert_eq(_hits_on(hits, asteroid), 1, "%s: an asteroid is hit" % mode)
	assert_eq(_hp(asteroid), asteroid_hp - damage, "%s: for damage" % mode)
	assert_eq(_hits_on(hits, player), 1, "%s: the real player is hit once" % mode)
	assert_eq(player.health_component.current_health, 10 * damage - damage, "%s: the player loses damage" % mode)
	if ally != null:
		assert_eq(_hits_on(hits, ally), 1, "%s: the real ally fighter is hit" % mode)
		assert_eq(_hp(ally), ally_hp - damage, "%s: for damage" % mode)
	assert_eq(hits.size(), 3 + (1 if ally != null else 0), "%s: one target_hit per delivered hit, nothing else hit" % mode)


func test_ordnance_is_never_hit(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var mine := EnemyMineScenes.scene_for(EnemyMine.Variant.PROXIMITY).instantiate() as EnemyMine
	h.root.add_child(mine)
	mine.global_position = CENTRE + Vector2(0.0, 150.0)
	mine.expired.connect(mine.queue_free)
	mine.launch(Vector2.ZERO, 0.0, mine.global_position)
	var rocket := DUMB_ROCKET.instantiate() as EnemyRocket
	h.root.add_child(rocket)
	rocket.global_position = CENTRE + Vector2(0.0, -150.0)
	rocket.expired.connect(rocket.queue_free)
	rocket.reset()
	rocket.launch(Vector2.DOWN, CENTRE + Vector2(0.0, 600.0), null)
	var received: Array[int] = [0]
	for node: Node in [mine, rocket]:
		(node.get_node("HurtBox") as HurtBox).received_damage.connect(func(_d: int) -> void: received[0] += 1)
	var r := _ring(h)
	var hits := _hits(r)
	r.start(0.0)
	_run_out(r)
	assert_eq(hits.size(), 0, "%s: nothing crossed but ordnance" % mode)
	assert_eq(received[0], 0, "%s: neither the mine's nor the rocket's hurtbox took anything" % mode)


func test_cancel_stops_the_ring(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var near := _victim_at(h, 60.0, 90.0)
	var far := _victim_at(h, 240.0, 270.0)
	var phases: Array = []
	r.phase_changed.connect(func(p: int) -> void: phases.append(p))
	var hits := _hits(r)

	r.start(0.0)
	_tick(r, 5)
	r.cancel()
	assert_eq(r.phase(), EnergyRing.Phase.OFF, "%s: cancel() in TELEGRAPH -> OFF at once" % mode)
	_tick(r, 120)
	assert_eq(hits.size(), 0, "%s: a cancelled telegraph never hits" % mode)
	assert_eq(phases, [EnergyRing.Phase.TELEGRAPH, EnergyRing.Phase.OFF], "%s: TELEGRAPH -> OFF" % mode)

	phases.clear()
	r.start(0.0)
	_tick(r, _ticks(float(_export(&"telegraph_seconds"))) + 12)
	assert_eq(_hits_on(hits, near), 1, "precondition: the band has passed the near fixture")
	assert_eq(_hits_on(hits, far), 0, "precondition: and not reached the far one")
	r.cancel()
	assert_eq(r.phase(), EnergyRing.Phase.FADE, "%s: cancel() while EXPANDING -> FADE" % mode)
	assert_false(r.is_lethal(), "%s: FADE is not lethal" % mode)
	_run_out(r)
	assert_eq(_hits_on(hits, far), 0, "%s: the cancelled ring never reaches the far fixture" % mode)
	assert_eq(_hits_on(hits, near), 1, "%s: nor does it hit the near one again" % mode)
	r.cancel()
	assert_eq(r.phase(), EnergyRing.Phase.OFF, "%s: cancel() in OFF changes nothing" % mode)
	assert_eq(phases, [EnergyRing.Phase.TELEGRAPH, EnergyRing.Phase.EXPANDING, EnergyRing.Phase.FADE, EnergyRing.Phase.OFF],
			"%s: TELEGRAPH, EXPANDING, FADE, OFF" % mode)


func test_centre_is_fixed_at_start(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var r := _ring(h)
	var shift := Vector2(0.0, 500.0)
	var at_start := _victim_at(h, 150.0, 90.0)
	var at_moved := _victim_at(h, 150.0, 90.0, CENTRE + shift)
	var hits := _hits(r)
	r.start(0.0)
	r.global_position += shift
	r.start(0.0)
	_run_out(r)
	assert_eq(_hits_on(hits, at_start), 1, "%s: the ring stays where start() was called (a start() while running is ignored)" % mode)
	assert_eq(_hits_on(hits, at_moved), 0, "%s: it did not follow its node" % mode)


# ---------------------------------------------------------------------------------------------
# Static: the scene, the clock rule
# ---------------------------------------------------------------------------------------------

func test_scene_exports_and_no_clock_of_its_own() -> void:
	assert_not_null(EnemyBeamScenes.ring_scene(), "the ring scene is registered")
	var r := EnemyBeamScenes.ring_scene().instantiate() as EnergyRing
	add_child_autofree(r)
	for property: StringName in [&"telegraph_seconds", &"fade_seconds", &"ring_speed", &"max_radius", &"band", &"gap_count", &"gap_deg",
			&"gap_spin_deg", &"damage", &"telegraph_width"]:
		assert_eq(r.get(property), _export(property), "%s on the instance is the scene's" % property)
	assert_gte(float(_export(&"telegraph_width")), 3.0, "the faint warning circle is at least 3 px wide")
	assert_gt(float(_export(&"ring_speed")), 0.0)
	assert_gt(float(_export(&"max_radius")), float(_export(&"band")), "the ring has room for its band")
	assert_false(r.is_physics_processing(), "the ring has no clock of its own: the owner ticks it")
	assert_false(r.is_processing())
	assert_eq(r.find_children("*", "Timer", true, false).size(), 0, "no Timer node")
	assert_eq(r.phase(), EnergyRing.Phase.OFF)


# ---------------------------------------------------------------------------------------------
# §2.3 fairness rows (Pulse Ring), with boundaries
# ---------------------------------------------------------------------------------------------

## The gap arc at half the ring's reach must let the player's hurtbox through three times over.
func _gap_is_wide_enough(scene: PackedScene, r_p: float) -> bool:
	var arc := deg_to_rad(float(_export_of_scene(scene, &"gap_deg"))) * float(_export_of_scene(scene, &"max_radius")) * 0.5
	return arc >= 3.0 * r_p


func _telegraph_is_reactable(scene: PackedScene) -> bool:
	return float(_export_of_scene(scene, &"telegraph_seconds")) >= R


func test_fairness_gap_arc_at_half_reach_is_three_player_radii() -> void:
	var r_p := _player_r_p()
	assert_gt(r_p, 0.0, "precondition: the player hurtbox has a radius")
	assert_true(_gap_is_wide_enough(EnemyBeamScenes.ring_scene(), r_p), "the shipped ring's gap arc at max_radius / 2 is >= 3 * r_p")
	assert_false(_gap_is_wide_enough(_synthetic({&"gap_deg": 15.0}), r_p), "boundary: a 15 degree gap fails the row")
	assert_false(_gap_is_wide_enough(_synthetic({&"max_radius": 80.0}), r_p), "boundary: a ring too small for its gap's arc fails the row")
	# The narrowest gap that passes is the bound itself: a step either side.
	var bound_deg := rad_to_deg(3.0 * r_p / (float(_export(&"max_radius")) * 0.5))
	assert_true(_gap_is_wide_enough(_synthetic({&"gap_deg": bound_deg + 0.5}), r_p), "boundary: just over the bound passes")
	assert_false(_gap_is_wide_enough(_synthetic({&"gap_deg": bound_deg - 0.5}), r_p), "boundary: just under the bound fails")


func test_fairness_telegraph_is_at_least_the_reaction_time() -> void:
	assert_true(_telegraph_is_reactable(EnemyBeamScenes.ring_scene()), "the shipped ring warns for at least R")
	assert_false(_telegraph_is_reactable(_synthetic({&"telegraph_seconds": R - 0.05})), "boundary: a warning shorter than R fails the row")
	assert_true(_telegraph_is_reactable(_synthetic({&"telegraph_seconds": R})), "boundary: exactly R passes")
