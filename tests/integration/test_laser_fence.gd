## Laser fences (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.11; Phase 8 t10): `LaserFence` (`assault/scenes/structures/laser_fence/`) and its
## `LaserEmitter` posts (`assault/scenes/enemies/laser_emitter/`). INTENT tests.
##
## Rows run in both harnesses (`tests/helpers/enemy_ai_harness.gd`) unless the name says `assault_` / `open_space_`. They are hand-ticked: a row turns off the
## physics tick of the fence and its `AssaultDrift`, then steps `fence.step(DT)` (and the drift's `step(DT)` where a row wants the carry). The rows with a
## wreck and with the linger run on real physics at the 8x clock (a cover ray and a particle lifetime need real frames). Numbers are read from the scenes
## (`EnemyBeamScenes`, the fence's own exports), never typed.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const FENCE: PackedScene = preload("res://assault/scenes/structures/laser_fence/laser_fence.tscn")
const POST: PackedScene = preload("res://assault/scenes/enemies/laser_emitter/laser_emitter.tscn")
const POST_CONFIG: LaserEmitterConfig = preload("res://assault/scenes/enemies/laser_emitter/laser_emitter_config.tres")  # read only
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const SHIELDED_SITE: PackedScene = preload("res://tests/helpers/shielded_site.tscn")
const WRECK_LARGE: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_large.tscn")
const BEAM_SCRIPT: Script = preload("res://assault/scenes/projectiles/enemy_beams/enemy_beam.gd")

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const AT := Vector2(640.0, 300.0)
const LETHAL := 10000
const FIXTURE_RADIUS := 14.0
const FIXTURE_HP := 100
const _SPEEDUP := 8

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_clock_scaled = true
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


func _world(mode: String):
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	return h


func _beam_export(property: StringName) -> Variant:
	return EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, property, BEAM_SCRIPT.get_property_default_value(property))


## A fence at [param at] in the harness. Hand-ticked (`real` false): its own physics tick and its drift's are off.
func _fence(h, props: Dictionary = {}, at: Vector2 = AT, real: bool = false) -> LaserFence:
	var f := FENCE.instantiate() as LaserFence
	for key: StringName in props:
		f.set(key, props[key])
	f.position = at
	h.root.add_child(f)
	if not real:
		f.set_physics_process(false)
		(f.get_node("AssaultDrift") as AssaultDrift).set_physics_process(false)
	return f


## One fence tick, then (when [param drift]) the drift's own.
func _step(f: LaserFence, n: int = 1, drift: bool = false) -> void:
	for i in n:
		if drift:
			(f.get_node("AssaultDrift") as AssaultDrift).step(DT)
		f.step(DT)


func _ticks(seconds: float) -> int:
	return ceili(seconds / DT - 1e-3)


func _circle(radius: float) -> CollisionShape2D:
	var cs := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	cs.shape = circle
	return cs


## `fixture_enemy.tscn` made a beam victim: a 14 px circle on its `HurtBox` and group `enemies`.
func _victim(h, at: Vector2, hp: int = FIXTURE_HP) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(FIXTURE_RADIUS))
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = hp
	health.current_health = hp
	h.root.add_child(e)
	e.global_position = at
	e.set_physics_process(false)
	return e


func _hp(node: Node) -> int:
	return (node.get_node("Health") as Health).current_health


func _kill(post: LaserEmitter) -> void:
	post.hurt_box.received_damage.emit(LETHAL)


## Steps until [param done] holds or [param max_steps] pass; true when it held.
func _run(f: LaserFence, max_steps: int, done: Callable) -> bool:
	for i in max_steps:
		_step(f)
		if done.call():
			return true
	return false


# ── Structure ───────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_fence_is_two_posts_and_a_twin_beam_with_fence_overrides(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	assert_true(f.post_a() is LaserEmitter and f.post_b() is LaserEmitter)
	assert_true(f.beam() is EnemyBeam)
	assert_eq(f.beam().kind, EnemyBeam.Kind.TWIN)
	assert_eq(f.beam().damage, 12, "%s: fence damage" % mode)
	assert_eq(f.beam().avoid_weight, 1.0, "%s: the fence's beam is a full-weight hazard" % mode)
	assert_true(f.beam().registers_hazard)
	assert_false(f.is_in_group(&"enemies"), "%s: the fence is not an enemy" % mode)
	assert_true(f.post_a().is_in_group(&"enemies") and f.post_b().is_in_group(&"enemies"), "%s: the posts are" % mode)
	assert_false(f.counts_toward_wave_clear)
	assert_false(f.counts_as_escape)
	assert_false(f.is_laser_blocking())
	assert_true(f.post_a().is_in_group(f.owner_group) and f.post_b().is_in_group(f.owner_group), "%s: both posts share the owner group" % mode)
	assert_true(String(f.owner_group).begins_with("laser_fence_"))


func test_a_post_is_a_static_destructible_enemy(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var post := POST.instantiate() as LaserEmitter
	h.root.add_child(post)
	assert_eq(post.health.max_health, POST_CONFIG.max_health)
	assert_eq(POST_CONFIG.max_health, 140)
	assert_eq(POST_CONFIG.score_value, 40)
	assert_eq(POST_CONFIG.collision_damage, 0)
	assert_false(POST_CONFIG.counts_as_escape, "a post drifting out of Assault never breaks the combo")
	assert_false(post.counts_as_escape)
	assert_true(post.is_fence_post())
	assert_false(post.is_laser_blocking())
	assert_false(post.is_ai_driven(), "no mover: it refuses tows")
	assert_null(post.get_node_or_null("EnemyMover"))
	assert_null(post.get_node_or_null("ContactHitBox"))
	assert_almost_eq((post.get_node("CollisionShape2D") as CollisionShape2D).shape.radius, LaserEmitter.BODY_RADIUS, 0.001)
	post.hurt_box.received_damage.emit(POST_CONFIG.max_health)
	assert_true(post.was_killed, "%s: a post dies to damage" % mode)


# ── Timeline ────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_static_fence_lights_after_its_telegraph_and_stays_lit_for_30_seconds(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	var tele: float = _beam_export(&"telegraph_seconds")
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: nothing before the first step" % mode)
	_step(f)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.TELEGRAPH, "%s: the warning starts at once" % mode)
	_step(f, _ticks(tele) - 2)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.TELEGRAPH, "%s: still warning a tick before the end" % mode)
	_step(f, 3)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.ACTIVE, "%s: lit after the telegraph" % mode)
	for second in 30:
		_step(f, 60)
		assert_eq(f.beam().phase(), EnemyBeam.Phase.ACTIVE, "%s: still lit %d s on" % [mode, second + 1])
	assert_true(f.is_lit())


func test_a_cycle_fence_flashes_off_telegraph_on(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h, {&"mode": LaserFence.Mode.CYCLE})
	assert_eq(f.off_seconds, 2.5)
	assert_eq(f.on_seconds, 3.0)
	var tele: float = _beam_export(&"telegraph_seconds")
	var log: Array = []
	f.beam().phase_changed.connect(func(p: int) -> void: log.append([p, snappedf(_t[0], DT)]))
	_t[0] = 0.0
	for i in _ticks(f.cycle_period() * 2.0 + 0.5):
		_t[0] += DT
		f.step(DT)
	var phases := log.map(func(e: Array) -> int: return e[0])
	var want := [EnemyBeam.Phase.TELEGRAPH, EnemyBeam.Phase.ACTIVE, EnemyBeam.Phase.FADE, EnemyBeam.Phase.OFF]
	assert_eq(phases.slice(0, 8), want + want, "%s: TELEGRAPH, ACTIVE, FADE, OFF, twice" % mode)
	assert_almost_eq(float(log[0][1]), f.off_seconds, DT * 1.5, "%s: dark for off_seconds" % mode)
	assert_almost_eq(float(log[1][1]) - float(log[0][1]), tele, DT * 1.5, "%s: warns for the telegraph" % mode)
	assert_almost_eq(float(log[2][1]) - float(log[1][1]), f.on_seconds, DT * 1.5, "%s: lit for on_seconds" % mode)
	assert_almost_eq(float(log[4][1]) - float(log[0][1]), f.cycle_period(), DT * 1.5, "%s: one period apart" % mode)


var _t: Array[float] = [0.0]


func test_phase_offset_starts_a_cycle_part_way_in(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var tele: float = _beam_export(&"telegraph_seconds")
	var a := _fence(h, {&"mode": LaserFence.Mode.CYCLE}, AT)
	var b := _fence(h, {&"mode": LaserFence.Mode.CYCLE}, AT + Vector2(0.0, 200.0))
	var c := _fence(h, {&"mode": LaserFence.Mode.CYCLE, &"phase_offset": 2.5 + tele + 0.5}, AT + Vector2(0.0, 400.0))
	var d := _fence(h, {&"mode": LaserFence.Mode.CYCLE, &"phase_offset": 2.5 + tele - 0.3}, AT + Vector2(0.0, 600.0))
	for f in [a, b, c, d]:
		_step(f)
	assert_eq(a.beam().phase(), EnemyBeam.Phase.OFF, "%s: no offset starts dark" % mode)
	assert_eq(c.beam().phase(), EnemyBeam.Phase.ACTIVE, "%s: offset into the lit part starts lit" % mode)
	assert_eq(d.beam().phase(), EnemyBeam.Phase.TELEGRAPH, "%s: offset into the warning starts warning" % mode)
	_step(d, _ticks(0.3) + 1)
	assert_eq(d.beam().phase(), EnemyBeam.Phase.ACTIVE, "%s: and lights when the rest of it has passed" % mode)
	# Alternating barriers: one lit while the other is dark.
	var e := _fence(h, {&"mode": LaserFence.Mode.CYCLE}, AT + Vector2(300.0, 0.0))
	var g := _fence(h, {&"mode": LaserFence.Mode.CYCLE, &"phase_offset": e.cycle_period() * 0.5}, AT + Vector2(300.0, 200.0))
	var lit_together := 0
	var one_lit := 0
	for i in _ticks(e.cycle_period() * 2.0):
		_step(e)
		_step(g)
		if e.beam().phase() == EnemyBeam.Phase.ACTIVE and g.beam().phase() == EnemyBeam.Phase.ACTIVE:
			lit_together += 1
		if e.beam().phase() == EnemyBeam.Phase.ACTIVE or g.beam().phase() == EnemyBeam.Phase.ACTIVE:
			one_lit += 1
	assert_gt(one_lit, 0, "%s: sanity, a barrier was lit" % mode)
	assert_lt(lit_together, one_lit, "%s: half a period apart they are not lit together the whole time" % mode)


# ── Damage ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_a_lit_fence_hurts_an_enemy_crossing_it_and_never_its_own_posts(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	var crosser := _victim(h, AT)
	var beside := _victim(h, AT + Vector2(0.0, 120.0))
	var hits: Array = []
	f.beam().target_hit.connect(func(target: Node2D, damage: int) -> void: hits.append([target, damage]))
	_step(f, _ticks(float(_beam_export(&"telegraph_seconds"))) - 1)
	assert_eq(_hp(crosser), FIXTURE_HP, "%s: a warning line hurts nobody" % mode)
	_step(f, 60)
	assert_lt(_hp(crosser), FIXTURE_HP, "%s: the lit fence hurt the crosser" % mode)
	assert_eq(hits[0][1], 12)
	assert_eq(_hp(beside), FIXTURE_HP, "%s: an enemy off the line is untouched" % mode)
	_step(f, 180)
	assert_eq(f.post_a().health.current_health, f.post_a().health.max_health, "%s: post A is never hurt by its own beam" % mode)
	assert_eq(f.post_b().health.current_health, f.post_b().health.max_health, "%s: nor post B" % mode)
	assert_false(hits.any(func(e: Array) -> bool: return e[0] == f.post_a() or e[0] == f.post_b()))


func test_a_fence_in_a_group_uses_the_groups_owner_set(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var group := TurretGroup.new()
	group.world_anchored_x = false
	var f := FENCE.instantiate() as LaserFence
	f.set_turret_group(group)
	assert_eq(f.owner_group, group.owner_group)
	assert_false(f.world_anchored_x, "a group member is already placed")
	f.position = AT
	h.root.add_child(f)
	f.set_physics_process(false)
	assert_true(f.post_a().is_in_group(group.owner_group), "%s: the posts join the group's set" % mode)
	group.free()


# ── Collapse ────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_killing_one_post_collapses_the_beam_within_one_tick_and_it_never_relights(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	var victim := _victim(h, AT)
	_step(f, 80)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.ACTIVE)
	var before := _hp(victim)
	_kill(f.post_a())
	assert_true(f.is_collapsed())
	assert_eq(f.beam().phase(), EnemyBeam.Phase.FADE, "%s: down in the same call" % mode)
	_step(f)
	assert_false(f.beam().is_lethal(), "%s: not lethal on the next tick" % mode)
	assert_null(f.beam().hazard_info(), "%s: and no longer a hazard" % mode)
	_step(f, 60 * 12)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: it never relights" % mode)
	assert_eq(_hp(victim), before, "%s: nothing hurt after the collapse" % mode)
	assert_true(is_instance_valid(f.post_b()), "%s: the survivor stays" % mode)
	f.post_b().hurt_box.received_damage.emit(10)
	assert_eq(f.post_b().health.current_health, f.post_b().health.max_health - 10, "%s: and stays a target" % mode)
	assert_eq(f.posts().size(), 1)


func test_a_cycle_fence_never_flashes_again_once_a_post_is_gone(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h, {&"mode": LaserFence.Mode.CYCLE})
	_step(f, _ticks(f.off_seconds) + 10)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.TELEGRAPH)
	_kill(f.post_b())
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: a warning that never hurt just goes dark" % mode)
	_step(f, _ticks(f.cycle_period() * 3.0))
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: three periods later it is still dark" % mode)


func test_a_post_that_leaves_the_tree_collapses_the_beam_too(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	_step(f, 80)
	f.post_a().free()
	assert_true(f.is_collapsed())
	assert_ne(f.beam().phase(), EnemyBeam.Phase.ACTIVE)
	_step(f, 60)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF)


# ── Hazard ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_the_hazard_is_registered_exactly_while_it_warns_or_burns_and_spans_the_posts(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var base := Hazards.count()
	var f := _fence(h)
	assert_eq(Hazards.count(), base, "%s: nothing before the first step" % mode)
	_step(f)
	assert_eq(Hazards.count(), base + 1, "%s: registered from TELEGRAPH" % mode)
	var info := f.beam().hazard_info()
	assert_not_null(info)
	assert_eq(info.kind, &"laser_wall")
	assert_almost_eq(info.position.distance_to(AT), 0.0, 0.01, "%s: at the midpoint between the posts" % mode)
	assert_almost_eq(info.segment_half.distance_to((f.post_b().global_position - f.post_a().global_position) * 0.5), 0.0, 0.01, "%s: the segment between the posts" % mode)
	assert_eq(info.avoid_weight, 1.0)
	assert_eq(info.exempt_group, f.owner_group, "%s: the fence's own pair ignores it" % mode)
	_step(f, 80)
	assert_eq(Hazards.count(), base + 1, "%s: and still while ACTIVE" % mode)
	_kill(f.post_a())
	assert_eq(Hazards.count(), base, "%s: gone with the collapse" % mode)
	var g := _fence(h, {&"mode": LaserFence.Mode.CYCLE}, AT + Vector2(0.0, 300.0))
	var base2 := Hazards.count()
	_step(g, _ticks(g.off_seconds) - 3)
	assert_eq(Hazards.count(), base2, "%s: a dark barrier is not a hazard" % mode)
	_step(g, 10)
	assert_eq(Hazards.count(), base2 + 1, "%s: a warning one is" % mode)
	_step(g, _ticks(g.cycle_period() - g.off_seconds) + 3)
	assert_eq(Hazards.count(), base2, "%s: and again not once it fades" % mode)
	g.free()
	assert_eq(Hazards.count(), base2)


func test_set_powered_false_drops_the_fence_for_good(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	_step(f, 80)
	assert_true(f.is_lit())
	var light := f.post_a().state_light()
	assert_eq(light.get_state(), StateLight.State.ARMED, "%s: a lit fence shows red posts" % mode)
	f.set_powered(false)
	assert_false(f.is_powered())
	assert_eq(f.beam().phase(), EnemyBeam.Phase.FADE, "%s: the beam is cancelled" % mode)
	_step(f, 60 * 10)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: and does not restart" % mode)
	assert_eq(light.get_state(), StateLight.State.OFF, "%s: the lights are out" % mode)
	f.set_powered(true)
	_step(f, 60 * 5)
	assert_eq(f.beam().phase(), EnemyBeam.Phase.OFF, "%s: a later set_powered(true) is ignored" % mode)
	assert_eq(f.posts().size(), 2, "%s: the posts are still there to destroy" % mode)


func test_a_group_going_dark_drops_a_member_fence(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var site := SHIELDED_SITE.instantiate() as TurretGroup
	site.position = AT + Vector2(0.0, -100.0)
	h.root.add_child(site)
	site.spawn_members()
	var fence: LaserFence = null
	var source: PowerSource = null
	for m in site.members():
		m.set_physics_process(false)
		if m is LaserFence:
			fence = m
		elif m is PowerSource:
			source = m
	assert_not_null(fence, "%s: the preset holds a fence" % mode)
	fence.set_physics_process(false)
	for i in 80:
		fence.step(DT)
	assert_true(fence.is_lit())
	source.hurt_box.received_damage.emit(LETHAL)
	assert_false(fence.is_powered(), "%s: the group's power coupling reaches the fence" % mode)
	assert_ne(fence.beam().phase(), EnemyBeam.Phase.ACTIVE)


# ── AI avoidance (R8.21) ────────────────────────────────────────────────────────────────────────────────────────────

## A fixture with a real `EnemyMover` flying straight up at 200 px/s with the given avoidance; hand-ticked.
func _flyer(h, avoidance: float) -> BaseEnemy:
	var e := FIXTURE_ENEMY.instantiate() as BaseEnemy
	e.get_node("HurtBox").add_child(_circle(FIXTURE_RADIUS))
	e.add_to_group(&"enemies")
	var health := e.get_node("Health") as Health
	health.max_health = FIXTURE_HP
	health.current_health = FIXTURE_HP
	var mover := e.get_node("EnemyMover") as EnemyMover
	mover.hazard_avoidance = avoidance
	mover.hazard_margin = 24.0
	e.position = AT + Vector2(0.0, 300.0)
	h.root.add_child(e)
	e.set_physics_process(false)
	(e.get_node("Brain")).desired_velocity = Vector2(0.0, -200.0)
	return e


## Flies [param e] at the lit STATIC fence for 5 s. Returns `{x_at_wall, y_end}`.
func _fly_at_fence(f: LaserFence, e: BaseEnemy) -> Dictionary:
	var x_at_wall := INF
	for i in 300:
		f.step(DT)
		var before := e.global_position
		e._physics_process(DT)
		# move_and_slide() outside a physics frame integrates over the frame's delta, not DT: put the body where DT would have taken it.
		e.global_position = before + e.velocity * DT
		if x_at_wall == INF and e.global_position.y <= AT.y:
			x_at_wall = e.global_position.x
	return {"x_at_wall": x_at_wall, "y_end": e.global_position.y}


func test_an_ai_enemy_with_avoidance_passes_round_an_end_and_is_never_hit(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	var e := _flyer(h, 1.0)
	var run := _fly_at_fence(f, e)
	assert_eq(_hp(e), FIXTURE_HP, "%s: never hit" % mode)
	assert_lt(float(run["y_end"]), AT.y - 40.0, "%s: it got past the fence" % mode)
	var half := (f.post_b().global_position.x - f.post_a().global_position.x) * 0.5
	assert_gt(absf(float(run["x_at_wall"]) - AT.x), half, "%s: and went round an end (x %.0f at the wall)" % [mode, float(run["x_at_wall"])])


func test_an_ai_enemy_with_no_avoidance_flies_into_the_beam(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _fence(h)
	var e := _flyer(h, 0.0)
	var run := _fly_at_fence(f, e)
	assert_lt(_hp(e), FIXTURE_HP, "%s: the control is hit" % mode)
	assert_almost_eq(float(run["x_at_wall"]), AT.x, 1.0, "%s: it flew straight" % mode)


# ── Assault ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_assault_drift_carries_both_posts_and_the_hazard_velocity_reads_it() -> void:
	var h = _world("assault")
	var f := _fence(h)
	var y0 := f.global_position.y
	var a0 := f.post_a().global_position
	_step(f, 60, true)
	assert_almost_eq(f.global_position.y - y0, 60.0, 0.5, "the fence drifts 60 px/s")
	assert_almost_eq(f.post_a().global_position.y - a0.y, 60.0, 0.5, "and carries its posts")
	assert_almost_eq(f.post_a().global_position.x, a0.x, 0.001)
	assert_almost_eq(f.beam().hazard_info().velocity.distance_to(Vector2(0.0, 60.0)), 0.0, 0.01, "the hazard leads the carried wall")
	assert_almost_eq(f.beam().hazard_info().position.y, f.global_position.y, 0.5, "the hazard follows the posts")


func test_open_space_the_fence_stays_where_it_was_put() -> void:
	var h = _world("open_space")
	var f := _fence(h)
	_step(f, 60, true)
	assert_eq(f.global_position, AT)
	assert_eq(f.beam().hazard_info().velocity, Vector2.ZERO)


func test_assault_a_fence_below_the_world_frees_itself() -> void:
	var h = _world("assault")
	var rect := EnemyWorld.projectile_world_rect(get_tree())
	var f := _fence(h, {}, Vector2(AT.x, rect.end.y + 5.0))
	_step(f, 2, true)
	assert_true(f.is_queued_for_deletion())


func test_assault_a_wave_spawned_fence_lands_at_world_x_640_plus_2_design_x_with_the_view_panned() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(100.0, 0.0)
	for anchored in [true, false]:
		var f := FENCE.instantiate() as LaserFence
		f.world_anchored_x = anchored
		f.global_position = cam.global_position + cam.offset + Vector2(-64.0, -220.0) * ArenaCamera.WORLD_SCALE  # WaveManager's formula
		var y := f.global_position.y
		h.root.add_child(f)
		f.set_physics_process(false)
		assert_almost_eq(f.global_position.x, 512.0 if anchored else 612.0, 0.001, "anchored %s: x" % anchored)
		assert_eq(f.global_position.y, y, "y stays camera-relative")
		assert_almost_eq(f.post_a().global_position.x, f.global_position.x - 150.0, 0.001)


func test_open_space_the_fence_x_is_untouched() -> void:
	var h = _world("open_space")
	var f := _fence(h, {}, Vector2(612.0, -80.0))
	assert_eq(f.global_position.x, 612.0)


func test_a_group_member_fence_skips_the_anchor() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(100.0, 0.0)
	var site := SHIELDED_SITE.instantiate() as TurretGroup
	site.world_anchored_x = false
	site.global_position = Vector2(612.0, 200.0)
	h.root.add_child(site)
	site.spawn_members()
	var fence: LaserFence = null
	for m in site.members():
		if m is LaserFence:
			fence = m
	assert_not_null(fence)
	assert_almost_eq(fence.global_position.x, 612.0, 0.001, "placed at its slot, not shifted by the pan")


func test_a_fence_hands_its_posts_to_the_score_tracker_as_orphans() -> void:
	var h = _world("open_space")
	var seen: Array = []
	var collect := func(e: Node) -> void: seen.append(e)
	EventBus.enemy_spawned_orphan.connect(collect)
	var f := _fence(h)
	EventBus.enemy_spawned_orphan.disconnect(collect)
	assert_eq(seen.size(), 2)
	assert_true(seen.has(f.post_a()) and seen.has(f.post_b()))
	assert_false(seen.has(f))


# ── Shield generator preset (plan §2.10.5) ──────────────────────────────────────────────────────────────────────────

func test_a_fence_in_a_generator_group_has_no_shield_on_either_post(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var site := SHIELDED_SITE.instantiate() as TurretGroup
	site.position = AT + Vector2(0.0, -100.0)
	h.root.add_child(site)
	site.spawn_members()
	var fence: LaserFence = null
	var gen: ShieldGenerator = null
	var others: Array = []
	for m in site.members():
		m.set_physics_process(false)
		if m is LaserFence:
			fence = m
		elif m is ShieldGenerator:
			gen = m
		else:
			others.append(m)
	assert_not_null(fence, "%s: the preset has its fence" % mode)
	assert_not_null(gen)
	for i in 5:
		gen._physics_process(DT)
	var shielded := 0
	for m in others:
		if (m as Node).get_children().any(func(c: Node) -> bool: return c is EnemyShield):
			shielded += 1
	assert_eq(shielded, others.size(), "%s: the generator's other members all carry a bubble" % mode)
	assert_eq(fence.find_children("*", "EnemyShield", true, false).size(), 0, "%s: no bubble anywhere under the fence" % mode)
	for post in [fence.post_a(), fence.post_b()]:
		assert_false(post.hurt_box.has_absorber(), "%s: no absorber on a post" % mode)
		assert_true(post.get_children().all(func(c: Node) -> bool: return not c is EnemyShield))


# ── Real physics at 8x ──────────────────────────────────────────────────────────────────────────────────────────────
# One scenario per harness shared by the cover row and the linger row (gate time: the lit wait is paid once).

func test_a_wreck_shadows_the_middle_and_the_last_posts_particles_get_time_to_finish(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var wreck := WRECK_LARGE.instantiate() as Wreck
	wreck.assault_drift = 0.0
	h.root.add_child(wreck)
	wreck.global_position = AT
	var base := Hazards.count()  # the wreck registers itself; the fence must add nothing once it is down
	var reach := wreck.body_radius() + 40.0
	var near_a := _victim(h, AT + Vector2(-reach, 0.0))
	var shadow := _victim(h, AT)
	var near_b := _victim(h, AT + Vector2(reach, 0.0))
	var f := _fence(h, {&"drift_speed": 0.0}, AT, true)
	var hit: Array = []
	f.beam().target_hit.connect(func(target: Node2D, _d: int) -> void: hit.append(target))
	await wait_physics_frames(3)
	await wait_physics_frames(_ticks(float(_beam_export(&"telegraph_seconds")) + float(_beam_export(&"ignite_grace"))) + 20)
	assert_true(f.beam().is_lethal(), "%s: the fence is lit" % mode)
	assert_true(hit.has(near_a), "%s: the part on post A's side hurts" % mode)
	assert_true(hit.has(near_b), "%s: and on post B's side" % mode)
	assert_false(hit.has(shadow), "%s: the shadow behind the wreck is safe" % mode)
	assert_eq(f.beam().hit_segments().size(), 2, "%s: two lethal parts" % mode)
	assert_not_null(f.beam().hazard_info(), "%s: the hazard still spans the whole fence" % mode)
	# The linger (review N8): the second post's explosion particles spawn under the fence and need it to stay.
	hit.clear()
	_kill(f.post_a())
	await wait_physics_frames(5)
	_kill(f.post_b())
	await wait_physics_frames(_ticks(0.15))
	assert_gt(f.find_children("*", "CPUParticles2D", false, false).size(), 0, "%s: the posts' explosion particles are under the fence" % mode)
	await wait_physics_frames(_ticks(0.45))
	assert_true(is_instance_valid(f) and not f.is_queued_for_deletion(), "%s: still here 0.6 s after the last post" % mode)
	assert_eq(Hazards.count(), base, "%s: no hazard registered" % mode)
	assert_eq(hit.size(), 0, "%s: no hit after the collapse" % mode)
	await wait_physics_frames(_ticks(0.5) + 6)
	assert_false(is_instance_valid(f), "%s: gone by 1.1 s" % mode)
	assert_eq(Hazards.count(), base)


# ── WaveBuilder through a real WaveManager ──────────────────────────────────────────────────────────────────────────

func test_assault_wave_builder_spawns_a_fence_at_world_x_through_a_real_wave_manager() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as ArenaCamera
	cam.set_physics_process(false)
	cam.offset = Vector2(-100.0, 0.0)
	var container := Node2D.new()
	h.root.add_child(container)
	var wm := WaveManager.new()
	wm.enemy_container = container
	h.root.add_child(wm)
	var b := WaveBuilder.new()
	var w := b.wave(0.0, [b.laser_fence().at(-64.0, -220.0).prop("mode", LaserFence.Mode.CYCLE)])
	assert_eq(w.entries[0].ship_scene.resource_path, WaveBuilder.LASER_FENCE)
	wm.load_section([w] as Array[WaveResource])
	for i in 4:
		await get_tree().process_frame
	var fences := container.get_children().filter(func(c: Node) -> bool: return c is LaserFence)
	assert_eq(fences.size(), 1, "one fence")
	var f: LaserFence = fences[0]
	assert_eq(f.mode, LaserFence.Mode.CYCLE, "the prop reached the fence before it entered the tree")
	assert_almost_eq(f.global_position.x, 512.0, 0.001, "the anchor holds on the real spawn path: 640 + 2 * design x")
	assert_false(f.is_in_group(&"enemies"))
