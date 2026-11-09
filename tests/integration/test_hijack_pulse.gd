## INTENT tests for the Hijack Pulse (Phase 9 plan §2.11, docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yk700amqs2xuk3t1oge/3-plan.md, rows numbered as there). The Hacker Frigate charges (TELEGRAPH: any damage cancels it), then
## pulses (PULSE): every tick a `HijackPulse` dart from its hull centre at each eligible player homing rocket within `hijack_range`, in sight,
## up to `max_claims_per_pulse` a pulse; a dart that reaches its rocket hands it to the player (`retarget(player, -1.0, hacker)`) and expires.
##
## Two kinds of row, both harnesses unless a row says otherwise:
##   - HAND-TICKED at 1/60 (`_tick`): the Hacker (`_physics_process`, then its position integrated from its velocity, or restored when the
##     row freezes it for exact geometry), then the rockets (each, then its lifetime), then the brain's live darts (each, then its lifetime).
##     Every pooled dart's and rocket's own physics is off. No hand row yields before its last tick (the pool's recycle is deferred, so each
##     fires at most 4 darts), except the source-death row, which awaits only after everything it ticks is off. Off the physics step no ray
##     is cast: the line of sight counts as clear (the `LaserTenderBrain` precedent).
##   - REAL PHYSICS on the 8x clock, only for the line of sight, a real bullet's cancel and real blast damage. The Hacker is parked
##     (`max_speed` 0.001: `EnemyMover.step` caps every request to it, the nose still turns). Each run ends on its own condition.
## Line of sight is the Ph6 rule: only asteroids and wrecks block it, never an enemy body. The rows use a real `wreck_medium.tscn` (deviation
## D3: `fixture_wreck.gd` has no body, so a ray can never meet it).
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate.tscn")
const SHIPPED: HackerFrigateConfig = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres")  # read only
const DART_SCENE: PackedScene = preload("res://assault/scenes/projectiles/hijack_pulse/hijack_pulse.tscn")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const WRECK_MEDIUM: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
const Phase := HackerFrigateBrain.Phase

const DT := 1.0 / 60.0
const MODES := ["open_space", "assault"]
const ASSAULT_PLAYER := Vector2(640.0, 620.0)
## A parked Hacker: every mover request is capped to this (px/s).
const PARKED := 0.001
## TELEGRAPH at the shipped 0.9 s is 54 ticks.
const TELEGRAPH_TICKS := 54
## PULSE at the shipped 1.6 s is 96 ticks.
const PULSE_TICKS := 96

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false

var _sandbox := SaveSandbox.new()
var _roots: Array[Node] = []
var _blasts: Array[Vector2] = []


## A per-physics-tick observer for the real-physics rows: counts ticks and runs `on_tick` (added last, so it sees the tick's result).
class _Ticker extends Node:
	var ticks: int = 0
	var on_tick: Callable

	func _physics_process(_delta: float) -> void:
		ticks += 1
		if on_tick.is_valid():
			on_tick.call(ticks)


## A claimer that is not the Hacker (the "claimed first" case).
class _Claimer extends Node2D:
	pass


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func before_each() -> void:
	_blasts = []
	get_tree().node_added.connect(_on_node_added)


func after_each() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	_restore_clock()
	_roots.clear()
	Input.action_release(&"shoot")


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
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


## Waits [param n] physics ticks (each 1/60 s of game time, on the 8x clock too).
func _frames(n: int) -> void:
	await wait_physics_frames(n)


## A fresh harness world; any earlier world of this test is taken out of the tree first (its player would still be `players[0]`).
func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = ASSAULT_PLAYER if h.is_assault else Vector2.ZERO
	return h


## Every `ContactBlast` that enters the tree, wherever its rocket's parent is (a salvo's is the player's `RocketState`). A blast attaches
## deferred, so a hand row counts them after one idle frame.
func _on_node_added(node: Node) -> void:
	if node is ContactBlast:
		_blasts.append((node as ContactBlast).global_position)


## The Hacker at [param pos], engaged, `engage_seconds` 1000 unless [param props] says otherwise. Hand rows (`hand`) switch off its own
## physics and every pooled dart's (and the dart's lifetime's).
func _spawn(h, pos: Vector2, props: Dictionary = {}, seed: int = 1, hand: bool = true) -> HackerFrigate:
	return _spawn_into(h.root, pos, props, seed, hand)


func _spawn_into(parent: Node, pos: Vector2, props: Dictionary = {}, seed: int = 1, hand: bool = true) -> HackerFrigate:
	var hacker := SCENE.instantiate() as HackerFrigate
	var brain := hacker.get_node("Brain") as HackerFrigateBrain
	brain.start_engaged = true
	brain.rng_seed = seed
	hacker.config.engage_seconds = 1000.0
	for key in props:
		hacker.config.set(key, props[key])
	hacker.global_position = pos
	parent.add_child(hacker)
	if hand:
		hacker.set_physics_process(false)
		for dart in hacker.dart_pool().get_children():
			dart.set_physics_process(false)
			_lifetime(dart).set_physics_process(false)
	return hacker


func _brain(hacker: HackerFrigate) -> HackerFrigateBrain:
	return hacker.get_node("Brain") as HackerFrigateBrain


func _lifetime(n: Node) -> ProjectileLifetime:
	return n.get_node("ProjectileLifetime") as ProjectileLifetime


## Untyped on purpose: a freed node reads as "not alive", not a type error.
func _alive(n: Variant) -> bool:
	return is_instance_valid(n) and not (n as Node).is_queued_for_deletion()


## One hand tick in the plan's order: the Hacker (frozen: its position restored), the rockets (each, then its lifetime), then its live darts.
func _tick(hacker: HackerFrigate, rockets: Array = [], frozen: bool = false) -> void:
	if _alive(hacker):
		var before := hacker.global_position
		hacker._physics_process(DT)
		hacker.global_position = before if frozen else before + hacker.velocity * DT
	for r in rockets:
		if _alive(r):
			(r as Node)._physics_process(DT)
			var lt: Node = (r as Node).get_node_or_null("ProjectileLifetime") if _alive(r) else null
			if lt != null:
				(lt as ProjectileLifetime)._physics_process(DT)
	if _alive(hacker):
		for dart in _brain(hacker).live_darts():
			dart._physics_process(DT)
			_lifetime(dart)._physics_process(DT)


## A homing rocket in [param parent] at [param at] flying along [param dir] (toward [param target] if given), its own and its lifetime's
## physics off.
func _hand_rocket(parent: Node, at: Vector2, dir: Vector2, target: Node = null) -> homing_missile:
	var r := _live_rocket(parent, at, dir, target)
	r.set_physics_process(false)
	_lifetime(r).set_physics_process(false)
	return r


func _live_rocket(parent: Node, at: Vector2, dir: Vector2, target: Node = null) -> homing_missile:
	var r: homing_missile = HOMING_SCENE.instantiate()
	r.locked_target = target
	parent.add_child(r)
	r.global_position = at
	r.rotation = dir.angle() + PI / 2.0
	return r


## Counts `retargeted` (its sources), `retarget_ended` and `expired` on [param r].
func _log(r: homing_missile) -> Dictionary:
	var log := {"retargeted": [], "ended": 0, "expired": 0}
	r.retargeted.connect(func(source: Node) -> void: (log["retargeted"] as Array).append(source))
	r.retarget_ended.connect(func() -> void: log["ended"] = int(log["ended"]) + 1)
	r.expired.connect(func() -> void: log["expired"] = int(log["expired"]) + 1)
	return log


func _heading(r: Node2D) -> Vector2:
	return Vector2.UP.rotated(r.rotation)


func _static_target(parent: Node, at: Vector2) -> Node2D:
	var t := Node2D.new()
	parent.add_child(t)
	t.global_position = at
	return t


## A lit jammer field (the Phase 9 §2.2 fixture of `test_seeking_ordnance.gd`).
func _jammer(parent: Node, at: Vector2, radius: float) -> HazardField:
	var f := HazardField.new()
	f.kind = &"jammer"
	f.radius = radius
	f.avoid_weight = 0.0
	f.disables_abilities = true
	f.stabilise_seconds = 0.75
	f.position = at
	parent.add_child(f)
	return f


## A real medium wreck (r 25), held still: its drift and lifetime clock are off. Off AFTER `add_child`: READY switches a script's
## `_physics_process` back on, and the Assault wreck drifts down 60 px/s in it.
func _wreck(h, pos: Vector2) -> Node2D:
	var wreck := WRECK_MEDIUM.instantiate() as Node2D
	h.root.add_child(wreck)
	wreck.set_physics_process(false)
	_lifetime(wreck).set_physics_process(false)
	wreck.global_position = pos
	return wreck


## A real player (no shield) in place of the harness's stub, its own physics and process off; the test moves it.
func _real_player(h, mode: String, at: Vector2) -> PlayerBase:
	h.player.remove_from_group(&"player")
	h.player.queue_free()
	var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
	h.root.add_child(p)
	p.global_position = at
	p.rotation = 0.0
	p.set_physics_process(false)
	p.set_process(false)
	p.shield_component.set_all_zero()
	return p


func _rocket_state(p: PlayerBase) -> RocketState:
	return p.get_node("AttackStateMachine/WarheadMissileShootingState") as RocketState


## A real salvo through the player's `RocketState` (type 0 warhead, 1 homing); the new rockets, their own physics off.
func _salvo(p: PlayerBase, type: int) -> Array[Node2D]:
	var rs := _rocket_state(p)
	var before := rs.get_children()
	rs._type = type
	rs._launch()
	var fresh: Array[Node2D] = []
	for child in rs.get_children():
		if not before.has(child) and child is Node2D:
			var n := child as Node2D
			n.set_physics_process(false)
			var lt := n.get_node_or_null("ProjectileLifetime")
			if lt != null:
				lt.set_physics_process(false)
			fresh.append(n)
	return fresh


## The hull's spot for a row: Open Space 720 px straight above the player at (0, 0), Assault 520 px above it at (640, 620).
func _above(h) -> Vector2:
	return h.player.global_position + Vector2(0.0, -(SHIPPED.assault_preferred_range if h.is_assault else SHIPPED.preferred_range))


# ── 1. Structure ─────────────────────────────────────────────────────────────────────────────────

func test_the_dart_is_a_node2d_with_no_collision_and_the_planned_numbers() -> void:
	var dart := DART_SCENE.instantiate()
	add_child_autofree(dart)
	assert_true(dart is HijackPulse and dart is Node2D, "a Node2D HijackPulse")
	assert_eq(dart.find_children("*", "CollisionObject2D", true, false).size(), 0, "no Area2D / body anywhere")
	assert_eq(dart.find_children("*", "CollisionShape2D", true, false).size(), 0, "no shape anywhere")
	assert_eq(dart.find_children("*", "CollisionPolygon2D", true, false).size(), 0, "no polygon anywhere")
	assert_eq((dart as HijackPulse).speed, 900.0)
	assert_eq((dart as HijackPulse).claim_radius, 16.0)
	var lt := _lifetime(dart)
	assert_eq([lt.max_time, lt.max_distance, lt.use_world_rect], [1.6, 1400.0, true])
	var args := -1
	for s in dart.get_signal_list():
		if s["name"] == "expired":
			args = (s["args"] as Array).size()
	assert_eq(args, 0, "expired is declared with no arguments")


func test_the_hacker_pools_four_darts_that_die_with_it() -> void:
	var h = _world("open_space")
	var hacker := _spawn(h, _above(h))
	var pool := hacker.dart_pool()
	assert_not_null(pool, "a DartPool")
	assert_eq(pool.get_parent(), hacker, "a root child")
	assert_eq(pool.pool_size, 4)
	assert_false(pool.persist_after_owner_death, "darts are cancelled with their Hacker")
	assert_eq(pool.bullet_scene.resource_path, DART_SCENE.resource_path)


func test_the_shipped_pulse_numbers() -> void:
	var c := SHIPPED
	assert_eq([c.pulse_trigger_range, c.hijack_range, c.max_claims_per_pulse, c.pulse_telegraph, c.pulse_seconds], [870.0, 650.0, 3, 0.9, 1.6])
	assert_eq([c.pulse_period_min, c.pulse_period_max, c.first_pulse_delay, c.assault_pulses_per_life, c.pulse_lock_seconds],
			[6.0, 8.0, 2.0, 1, 0.0])
	assert_eq(c.pulse_trigger_range, c.preferred_range + c.range_drift + 60.0, "the whole held band is inside the trigger range")
	var second := c.first_pulse_delay + c.pulse_telegraph + c.pulse_seconds + c.pulse_period_min
	assert_almost_eq(second, 10.5, 1e-4)
	assert_gt(second, c.engage_seconds, "the earliest second Assault TELEGRAPH is past the budget: why the cap is 1")


# ── 2. Launch from the hull centre, claim on arrival ─────────────────────────────────────────────

func test_a_dart_leaves_the_hull_centre_and_claims_on_the_tick_it_arrives(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var r := _hand_rocket(h.root, hacker.global_position + Vector2(0.0, 300.0), Vector2.DOWN)
	var log := _log(r)
	brain.enter_phase(Phase.PULSE)
	_tick(hacker, [], true)
	var darts := brain.live_darts()
	assert_eq(darts.size(), 1, "%s: one dart on the first PULSE tick" % mode)
	if darts.is_empty():
		return
	var dart: HijackPulse = darts[0]
	# The dart ticked once already (15 px): its lifetime origin is where it left.
	assert_eq(_lifetime(dart)._origin, hacker.global_position, "%s: launched from the hull centre (the dish is 14 px off it)" % mode)
	assert_ne(hacker.dish().global_position, hacker.global_position, "%s: precondition: the dish is not the hull centre" % mode)
	var expired := []
	dart.expired.connect(func() -> void: expired.append(true))
	var claim_tick := -1
	var expire_tick := -1
	for i in range(2, 40):
		_tick(hacker, [], true)
		if claim_tick < 0 and (log["retargeted"] as Array).size() > 0:
			claim_tick = i
		if expire_tick < 0 and expired.size() > 0:
			expire_tick = i
	assert_eq(log["retargeted"], [hacker], "%s: claimed once, the Hacker the source" % mode)
	assert_eq(expired.size(), 1, "%s: the dart expired once" % mode)
	assert_eq(claim_tick, expire_tick, "%s: on the claim tick (%d / %d)" % [mode, claim_tick, expire_tick])
	assert_eq(claim_tick, 19, "%s: 300 px at 15 px a tick, within 16 px on tick 19" % mode)
	assert_true(r.is_retargeted(), "%s: hijacked" % mode)
	assert_true(r.is_tether_visible(), "%s: the rocket draws the tether, not the dart" % mode)
	assert_false(dart.is_flying())
	assert_eq(brain.darts_fired, 1)


# ── 3. A refused or vanished target ends a dart with no claim ────────────────────────────────────

func _refusal_run(mode: String, case: String) -> Dictionary:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var at: Vector2 = hacker.global_position + Vector2(0.0, 400.0)
	var r := _hand_rocket(h.root, at, Vector2.DOWN)
	var log := _log(r)
	brain.enter_phase(Phase.PULSE)
	_tick(hacker, [], true)
	var dart: HijackPulse = brain.live_darts()[0]
	var expired := []
	dart.expired.connect(func() -> void: expired.append(true))
	for _i in 5:
		_tick(hacker, [], true)
	var claimer: _Claimer = null
	match case:
		"freed":
			r.free()
		"claimed_first":
			claimer = _Claimer.new()
			h.root.add_child(claimer)
			assert_true(r.retarget(h.player, -1.0, claimer), "%s: precondition: the fixture claimer took it" % mode)
		"jammed":
			_jammer(h.root, at, 120.0)
	var ended_on := -1
	for i in 40:
		_tick(hacker, [], true)
		if ended_on < 0 and expired.size() > 0:
			ended_on = i + 1
	return {"expired": expired.size(), "ended_on": ended_on, "log": log, "claimer": claimer, "darts": brain.darts_fired,
		"rocket": r if case != "freed" else null}


func test_a_freed_claimed_or_jammed_rocket_ends_its_dart_unclaimed(mode: String = use_parameters(MODES)) -> void:
	var freed := _refusal_run(mode, "freed")
	assert_eq(freed["expired"], 1, "%s freed: the dart expired once" % mode)
	assert_eq(freed["ended_on"], 1, "%s freed: on its next tick" % mode)
	assert_eq(freed["darts"], 1, "%s freed: no second dart" % mode)
	var first := _refusal_run(mode, "claimed_first")
	assert_eq(first["expired"], 1, "%s claimed first: the dart expired" % mode)
	assert_eq(first["ended_on"], 1, "%s claimed first: on its next tick" % mode)
	assert_eq((first["log"] as Dictionary)["retargeted"], [first["claimer"]], "%s claimed first: one claim, the fixture's" % mode)
	var jammed := _refusal_run(mode, "jammed")
	assert_eq(jammed["expired"], 1, "%s jammed: the dart expired" % mode)
	assert_eq(jammed["ended_on"], 1, "%s jammed: on its next tick" % mode)
	assert_eq((jammed["log"] as Dictionary)["retargeted"], [], "%s jammed: never claimed" % mode)
	assert_eq(jammed["darts"], 1, "%s jammed: no second dart at a jammed rocket" % mode)
	var control := _refusal_run(mode, "control")
	assert_eq((control["log"] as Dictionary)["retargeted"].size(), 1, "%s control: the untouched rocket is claimed" % mode)
	assert_eq(control["expired"], 1)


# ── 5. A receding rocket outruns the dart (the documented limit) ─────────────────────────────────

func _recede(mode: String, dir: float) -> Dictionary:
	var h = _world(mode)
	var hacker := _spawn(h, Vector2(0.0, 300.0))
	var brain := _brain(hacker)
	var r := _hand_rocket(h.root, Vector2(650.0, 300.0), Vector2.RIGHT * dir)
	var log := _log(r)
	brain.enter_phase(Phase.PULSE)
	_tick(hacker, [r], true)  # the Hacker's pass sees the rocket at exactly 650.0, then it moves
	var out := {"darts": 0, "min_gap": INF, "expire_tick": -1, "clock": -1.0, "gap_at_expiry": -1.0, "dart_origin": Vector2.INF, "log": log}
	var darts := brain.live_darts()
	if darts.is_empty():
		return out
	var dart: HijackPulse = darts[0]
	out["dart_origin"] = _lifetime(dart)._origin
	var expired := []
	dart.expired.connect(func() -> void:
		expired.append(true)
		if _alive(r):
			out["gap_at_expiry"] = r.global_position.distance_to(dart.global_position)
		out["clock"] = _lifetime(dart)._clock)
	var tick := 1
	while tick < PULSE_TICKS + 2:
		if expired.is_empty() and _alive(r):
			out["min_gap"] = minf(float(out["min_gap"]), r.global_position.distance_to(dart.global_position))
		if not expired.is_empty() and int(out["expire_tick"]) < 0:
			out["expire_tick"] = tick
		tick += 1
		_tick(hacker, [r], true)
	if not expired.is_empty() and int(out["expire_tick"]) < 0:
		out["expire_tick"] = tick
	out["darts"] = brain.darts_fired
	return out


func test_a_rocket_receding_at_500_px_s_from_650_px_is_never_claimed(mode: String = use_parameters(MODES)) -> void:
	var run := _recede(mode, 1.0)
	gut.p("%s receding: dart expired on tick %d, clock %.4f s, gap %.2f px (min %.2f)" % [mode, run["expire_tick"], run["clock"],
			run["gap_at_expiry"], run["min_gap"]])
	assert_eq(run["dart_origin"], Vector2(0.0, 300.0), "%s: the dart's lifetime measures from the hull centre" % mode)
	assert_eq((run["log"] as Dictionary)["retargeted"], [], "%s: never claimed" % mode)
	assert_gt(float(run["min_gap"]), 16.0, "%s: the gap stays above claim_radius" % mode)
	assert_eq(int(run["expire_tick"]), 94, "%s: the 1400 px rule on tick 94" % mode)
	assert_lt(float(run["clock"]), 1.6, "%s: before max_time" % mode)
	assert_gte(float(run["gap_at_expiry"]), 20.0, "%s: 23.3 px short at expiry" % mode)
	assert_eq(run["darts"], 1, "%s: one dart, no second" % mode)
	var control := _recede(mode, -1.0)
	assert_eq(((control["log"] as Dictionary)["retargeted"] as Array).size(), 1, "%s control: a rocket closing on the hull is claimed" % mode)


# ── 7. The cap ───────────────────────────────────────────────────────────────────────────────────

func _cap_run(mode: String, cap: int) -> Dictionary:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h), {"max_claims_per_pulse": cap})
	var brain := _brain(hacker)
	var logs: Array = []
	for k in 6:
		var r := _hand_rocket(h.root, hacker.global_position + Vector2(0.0, 300.0 + 50.0 * k), Vector2.DOWN)
		logs.append(_log(r))
	brain.enter_phase(Phase.PULSE)
	for _i in PULSE_TICKS + 4:
		_tick(hacker, [], true)
	var claimed: Array[int] = []
	for k in 6:
		if not ((logs[k] as Dictionary)["retargeted"] as Array).is_empty():
			claimed.append(300 + 50 * k)
	return {"darts": brain.darts_fired, "claimed": claimed, "pulses": brain.pulses_fired}


func test_six_rockets_in_reach_give_exactly_three_darts_at_the_nearest(mode: String = use_parameters(MODES)) -> void:
	var run := _cap_run(mode, 3)
	assert_eq(run["darts"], 3, "%s: three darts" % mode)
	assert_eq(run["claimed"], [300, 350, 400] as Array[int], "%s: the three nearest claimed" % mode)
	var control := _cap_run(mode, 4)
	assert_eq(control["darts"], 4, "%s control: cap 4 gives four darts" % mode)
	assert_eq(control["claimed"], [300, 350, 400, 450] as Array[int], "%s control: and four claims" % mode)


# ── 9. The two ranges ────────────────────────────────────────────────────────────────────────────

func _trigger_run(mode: String, distance: float) -> int:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h), {"first_pulse_delay": 0.0})
	var brain := _brain(hacker)
	for i in 60:
		h.player.global_position = hacker.global_position + Vector2(0.0, distance)
		_tick(hacker, [], true)
		if brain.phase == Phase.TELEGRAPH:
			return i + 1
	return -1


func test_telegraph_needs_the_player_within_870_px(mode: String = use_parameters(MODES)) -> void:
	assert_eq(_trigger_run(mode, 869.0), 1, "%s: 869 px: TELEGRAPH on the first tick" % mode)
	assert_eq(_trigger_run(mode, 871.0), -1, "%s: 871 px: none in 60 ticks with the cooldown at 0" % mode)


func test_a_rocket_at_649_px_is_darted_and_one_at_651_px_is_not(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var a := _hand_rocket(h.root, hacker.global_position + Vector2(649.0, 0.0), Vector2.DOWN)
	var b := _hand_rocket(h.root, hacker.global_position + Vector2(-651.0, 0.0), Vector2.DOWN)
	var log_a := _log(a)
	var log_b := _log(b)
	brain.enter_phase(Phase.PULSE)
	var targets: Array = []
	for _i in PULSE_TICKS:
		_tick(hacker, [], true)
		for dart in brain.live_darts():
			if not targets.has(dart.rocket()):
				targets.append(dart.rocket())
	assert_eq((log_a["retargeted"] as Array).size(), 1, "%s: 649 px claimed" % mode)
	assert_false(targets.has(b), "%s: 651 px never darted" % mode)
	assert_eq(log_b["retargeted"], [], "%s: 651 px never claimed" % mode)
	assert_eq(brain.darts_fired, 1, "%s: one dart in the whole window" % mode)


# ── 12. A rocket inside a jammer is never darted ─────────────────────────────────────────────────

func _jammer_run(mode: String, field_offset: Vector2) -> Dictionary:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var at := hacker.global_position + Vector2(0.0, 300.0)
	var r := _hand_rocket(h.root, at, Vector2.DOWN)
	var log := _log(r)
	_jammer(h.root, at + field_offset, 120.0)
	brain.enter_phase(Phase.PULSE)
	var was_pulse := true
	for _i in PULSE_TICKS:
		was_pulse = was_pulse and brain.phase == Phase.PULSE
		_tick(hacker, [], true)
	return {"darts": brain.darts_fired, "claims": (log["retargeted"] as Array).size(), "pulse": was_pulse}


func test_a_rocket_inside_a_lit_jammer_gets_no_dart(mode: String = use_parameters(MODES)) -> void:
	var inside := _jammer_run(mode, Vector2.ZERO)
	assert_true(inside["pulse"], "%s: the Hacker still pulses" % mode)
	assert_eq(inside["darts"], 0, "%s: no dart at a jammed rocket" % mode)
	assert_eq(inside["claims"], 0)
	var control := _jammer_run(mode, Vector2(2000.0, 0.0))
	assert_eq(control["darts"], 1, "%s control: the field 2000 px away, one dart" % mode)
	assert_eq(control["claims"], 1, "%s control: and a claim" % mode)


# ── 15. Killing the Hacker cancels its darts and fizzles its rockets ─────────────────────────────

func test_killing_the_hacker_mid_pulse_frees_its_darts_and_fizzles_its_rockets(mode: String = use_parameters(MODES)) -> void:
	for kill in [true, false]:
		var h = _world(mode)
		var hacker := _spawn(h, _above(h))
		var brain := _brain(hacker)
		var rockets: Array = []
		var logs: Array = []
		for d in [150.0, 300.0, 600.0]:
			var r := _hand_rocket(h.root, hacker.global_position + Vector2(0.0, d), Vector2.DOWN)
			rockets.append(r)
			logs.append(_log(r))
		brain.enter_phase(Phase.PULSE)
		for _i in 20:
			_tick(hacker, [], true)
		assert_eq((logs[0]["retargeted"] as Array).size(), 1, "%s: the 150 px rocket claimed by tick 20" % mode)
		assert_eq((logs[1]["retargeted"] as Array).size(), 1, "%s: the 300 px rocket claimed by tick 20" % mode)
		var flying := brain.live_darts()
		assert_eq(flying.size(), 1, "%s: the 600 px dart still flying" % mode)
		if not kill:
			for _i in 40:
				_tick(hacker, [], true)
			assert_eq((logs[2]["retargeted"] as Array).size(), 1, "%s control: without the kill the 600 px rocket is claimed" % mode)
			continue
		var all_darts: Array = hacker.dart_pool().get_children()
		for dart in flying:
			all_darts.append(dart)
		for node in h.root.get_children():
			if node is HijackPulse and not all_darts.has(node):
				all_darts.append(node)
		hacker.health.decrease(9999)
		await get_tree().process_frame
		await get_tree().process_frame
		assert_false(is_instance_valid(hacker), "%s: the Hacker is gone" % mode)
		for dart in all_darts:
			assert_false(is_instance_valid(dart), "%s: every dart went with it" % mode)
		assert_eq(logs[2]["retargeted"], [], "%s: the 600 px rocket was never claimed" % mode)
		var blasts_before := _blasts.size()
		for k in 2:
			(rockets[k] as homing_missile)._physics_process(DT)
			assert_eq(logs[k]["ended"], 1, "%s: claimed rocket %d fizzled on its next tick" % [mode, k])
		await get_tree().process_frame
		assert_eq(_blasts.size(), blasts_before, "%s: no ContactBlast" % mode)


# ── 16 / 21. The tell, and holding fire ──────────────────────────────────────────────────────────

func test_the_tell_runs_on_the_light_and_the_dish_and_holding_fire_gives_no_dart(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var light := hacker.state_light()
	for _i in 30:
		_tick(hacker, [], true)
	assert_eq(brain.phase, Phase.HOLD_ARC, "%s: precondition" % mode)
	assert_eq(light.get_state(), StateLight.State.OFF, "%s HOLD_ARC: light off" % mode)
	assert_eq(hacker.dish_open(), 0.0, "%s HOLD_ARC: dish folded" % mode)
	assert_eq(hacker.dish().scale, Vector2.ONE * HackerFrigate.DISH_FOLDED_SCALE, "%s HOLD_ARC: the part is folded" % mode)
	assert_eq(hacker.tell_kind(), &"", "%s HOLD_ARC: no tell" % mode)
	assert_eq(hacker.ripple_count(), 0)
	# TELEGRAPH at 2.0 s (tick 120).
	while brain.phase != Phase.TELEGRAPH:
		_tick(hacker, [], true)
	var last_open := -1.0
	var last_r := INF
	var monotonic := true
	var last_charge := 0.0
	while brain.phase == Phase.TELEGRAPH:
		assert_eq(light.get_state(), StateLight.State.CHARGING, "%s TELEGRAPH: yellow" % mode)
		monotonic = monotonic and hacker.dish_open() >= last_open and hacker.charge_ring_radius() <= last_r
		last_open = hacker.dish_open()
		last_r = hacker.charge_ring_radius()
		last_charge = last_r
		_tick(hacker, [], true)
	assert_true(monotonic, "%s TELEGRAPH: the dish opens and the ring closes monotonically" % mode)
	assert_almost_eq(last_charge, 40.0 + 20.0 / TELEGRAPH_TICKS, 0.5, "%s TELEGRAPH: the ring closed from 60 to about 40" % mode)
	assert_eq(brain.phase, Phase.PULSE)
	var ripples := {}
	var pulse_tick := 0
	while brain.phase == Phase.PULSE:
		assert_eq(light.get_state(), StateLight.State.COMMIT, "%s PULSE: white" % mode)
		assert_eq(hacker.dish_open(), 1.0, "%s PULSE: dish open" % mode)
		assert_eq(hacker.tell_kind(), &"pulse")
		ripples[pulse_tick] = hacker.ripple_count()
		pulse_tick += 1
		_tick(hacker, [], true)
	assert_eq([ripples.get(0), ripples.get(25), ripples.get(73)], [1, 2, 4], "%s PULSE: ripples at 0.0 / 0.41 / 1.21 s" % mode)
	assert_eq(pulse_tick, PULSE_TICKS, "%s: a 96-tick window" % mode)
	assert_eq(brain.phase, Phase.HOLD_ARC)
	assert_eq(light.get_state(), StateLight.State.OFF, "%s after: light off" % mode)
	assert_eq(hacker.dish_open(), 0.0, "%s after: dish folded" % mode)
	assert_eq(hacker.tell_kind(), &"", "%s after: no tell" % mode)
	assert_eq(hacker.ripple_count(), 0)
	# Holding fire: nothing to claim.
	assert_eq(brain.pulses_fired, 1, "%s: one pulse" % mode)
	assert_eq(brain.darts_fired, 0, "%s: no rocket in flight, no dart" % mode)
	assert_eq(brain.live_darts().size(), 0)
	assert_between(brain.pulse_cooldown, SHIPPED.pulse_period_min - DT, SHIPPED.pulse_period_max, "%s: a fresh cooldown" % mode)


# ── 4. Rockets in flight when PULSE starts ───────────────────────────────────────────────────────

## Three rockets cross the Hacker's front 0.3 s before PULSE (from 300 px left of the hull, level with it and 30 / 60 px beyond it, flying +x
## at static targets 900 px on); with the Hacker on the shipped cycle (`first_pulse_delay` 0.5: TELEGRAPH tick 30, PULSE tick 84). Returns
## per rocket: claim tick, the largest per-tick heading change after it, the smallest heading error to the player, the closest approach.
## Pre-run change (DECISIONS.md, Phase 9 t9): the task plan's start, 250 / 280 / 310 px nearer the player, put the Assault claims 250-310 px
## from the player, inside two hijacked turn radii (380 / 1.6 = 238 px), and those rockets circled it (heading error never under 55°).
func _in_flight(mode: String, with_hacker: bool) -> Dictionary:
	var blasts0 := _blasts.size()
	var h = _world(mode)
	var props := {"first_pulse_delay": 0.5, "range_drift": 0.0, "nose_cone_deg": 0.0, "route_cone_deg": 0.0}
	var hacker: HackerFrigate = _spawn(h, _above(h), props) if with_hacker else null
	if hacker != null:
		_brain(hacker).force_orbit_direction(1)
	for _i in 66:
		_tick(hacker)
	var hull: Vector2 = hacker.global_position if hacker != null else _above(h)
	var rockets: Array = []
	var stats: Array = []
	for k in 3:
		var start := hull + Vector2(-300.0, -30.0 * k)
		var r := _hand_rocket(h.root, start, Vector2.RIGHT, _static_target(h.root, start + Vector2(900.0, 0.0)))
		rockets.append(r)
		stats.append({"log": _log(r), "claim": -1, "max_turn": 0.0, "min_err": INF, "closest": INF, "prev": Vector2.ZERO})
	var player: Node2D = h.player
	for i in range(67, 67 + 300):
		_tick(hacker, rockets)
		for k in 3:
			var s: Dictionary = stats[k]
			var r: Variant = rockets[k]
			if not _alive(r):
				continue
			var rk := r as homing_missile
			if int(s["claim"]) < 0 and (s["log"]["retargeted"] as Array).size() > 0:
				s["claim"] = i
				s["prev"] = _heading(rk)
				continue
			if int(s["claim"]) >= 0:
				s["max_turn"] = maxf(float(s["max_turn"]), absf((s["prev"] as Vector2).angle_to(_heading(rk))))
				s["prev"] = _heading(rk)
				s["min_err"] = minf(float(s["min_err"]), absf(_heading(rk).angle_to(player.global_position - rk.global_position)))
				s["closest"] = minf(float(s["closest"]), rk.global_position.distance_to(player.global_position))
		if not (_alive(rockets[0]) or _alive(rockets[1]) or _alive(rockets[2])):
			break
	await get_tree().process_frame
	return {"stats": stats, "pulse_tick": 84, "blasts": _blasts.size() - blasts0, "darts": _brain(hacker).darts_fired if hacker != null else 0}


func test_rockets_in_flight_are_claimed_and_turn_on_the_player(mode: String = use_parameters(MODES)) -> void:
	var run: Dictionary = await _in_flight(mode, true)
	var turn := 1.6 * DT + 1e-4
	for k in 3:
		var s: Dictionary = run["stats"][k]
		gut.p("%s in flight rocket %d: claimed tick %d (PULSE tick 84), max turn %.5f rad/tick, min heading error %.2f deg, closest %.1f px"
				% [mode, k, s["claim"], s["max_turn"], rad_to_deg(float(s["min_err"])), s["closest"]])
		assert_eq(s["log"]["retargeted"].size(), 1, "%s rocket %d: claimed by a dart" % [mode, k])
		assert_gte(int(s["claim"]), int(run["pulse_tick"]), "%s rocket %d: during PULSE" % [mode, k])
		assert_lte(float(s["max_turn"]), turn, "%s rocket %d: turn-limited" % [mode, k])
		assert_lt(float(s["min_err"]), deg_to_rad(10.0), "%s rocket %d: comes round to within 10 degrees of the player" % [mode, k])
	gut.p("%s in flight: %d darts, %d blasts" % [mode, run["darts"], run["blasts"]])
	var control: Dictionary = await _in_flight(mode, false)
	for k in 3:
		assert_eq(control["stats"][k]["log"]["retargeted"], [], "%s control: no Hacker, rocket %d never retargeted" % [mode, k])


# ── 6. Newly launched rockets, and the measured limit ────────────────────────────────────────────

## A real ship (still) under a Hacker on the shipped cycle (`first_pulse_delay` 0: TELEGRAPH tick 1, PULSE tick 55) fires a real homing salvo
## 0.5 s into PULSE (tick 85); the rockets lock on the Hacker (the only enemy). `variant`: "still"; "placed" (review R1: on the first claim the
## player is re-placed 300 px ahead along that rocket's heading); "late" (a second salvo 0.2 s after PULSE ends).
func _newly(mode: String, variant: String) -> Dictionary:
	var blasts0 := _blasts.size()
	var h = _world(mode)
	var at: Vector2 = h.player.global_position
	var p := _real_player(h, mode, at)
	var hacker := _spawn(h, _above(h), {"first_pulse_delay": 0.0})
	var brain := _brain(hacker)
	var rockets: Array = []
	var claims := [0]
	var closest := [INF, INF, INF]
	var pulse_end := -1
	var late: Array = []
	var darts_at_late := -1
	for i in range(1, 60 * 6):
		if i == 85:
			for r in _salvo(p, 1):
				rockets.append(r)
				(r as homing_missile).retargeted.connect(func(_s: Node) -> void:
					claims[0] += 1
					if variant == "placed" and claims[0] == 1:
						p.global_position = (r as Node2D).global_position + _heading(r as Node2D) * 300.0)
		if variant == "late" and pulse_end > 0 and i == pulse_end + 12:
			late = _salvo(p, 1)
			rockets.append_array(late)
			darts_at_late = brain.darts_fired
		_tick(hacker, rockets)
		if pulse_end < 0 and brain.pulses_fired == 1 and brain.phase != Phase.PULSE:
			pulse_end = i
		for k in mini(rockets.size(), 3):
			if _alive(rockets[k]) and (rockets[k] as homing_missile).is_retargeted():
				closest[k] = minf(closest[k], (rockets[k] as Node2D).global_position.distance_to(p.global_position))
		if i > 85 and pulse_end > 0 and i > pulse_end + 20 and rockets.all(func(r: Variant) -> bool: return not _alive(r)):
			break
	await get_tree().process_frame
	return {"darts": brain.darts_fired, "claims": claims[0], "blasts": _blasts.size() - blasts0, "closest": closest, "pulse_end": pulse_end,
		"darts_at_late": darts_at_late, "late": late.size()}


func test_a_salvo_launched_during_pulse_is_claimed_and_a_still_player_is_not_blasted(mode: String = use_parameters(MODES)) -> void:
	var r: homing_missile = HOMING_SCENE.instantiate()
	var trigger := r.hijack_trigger_radius
	r.free()
	var run: Dictionary = await _newly(mode, "still")
	gut.p("%s newly launched, still player: %d darts, %d claims, %d blasts, closest %s px" % [mode, run["darts"], run["claims"], run["blasts"],
			run["closest"]])
	assert_eq(run["darts"], 3, "%s: three darts" % mode)
	assert_eq(run["claims"], 3, "%s: newly launched rockets are claimed" % mode)
	# The measured limit (review B1): a salvo fired at the Hacker is claimed heading away and fizzles short of a still player.
	assert_eq(run["blasts"], 0, "%s: no ContactBlast" % mode)
	for k in 3:
		assert_gt(float(run["closest"][k]), trigger, "%s rocket %d: never within the trigger radius" % [mode, k])
	var placed: Dictionary = await _newly(mode, "placed")
	gut.p("%s newly launched, player placed ahead: %d claims, %d blasts" % [mode, placed["claims"], placed["blasts"]])
	assert_gte(placed["blasts"], 1, "%s control A: a player 300 px ahead of a claimed rocket is blasted" % mode)
	var late: Dictionary = await _newly(mode, "late")
	assert_eq(late["late"], 3, "%s control B: a second salvo was launched after the window" % mode)
	assert_eq(late["darts"], 3, "%s control B: and got no dart" % mode)
	assert_eq(late["darts_at_late"], 3)


# ── 8. No darts outside PULSE ────────────────────────────────────────────────────────────────────

func test_no_dart_flies_in_hold_arc_break_off_or_telegraph(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h))
	var brain := _brain(hacker)
	var home: Vector2 = hacker.global_position + Vector2(0.0, 600.0)  # beyond the 540 px break-off exit, inside the 870 px trigger
	_hand_rocket(h.root, hacker.global_position + Vector2(0.0, 300.0), Vector2.DOWN)
	_hand_rocket(h.root, hacker.global_position + Vector2(200.0, 0.0), Vector2.DOWN)
	var seen := {}
	var leak := false
	var first_pulse_darts := -1
	for i in 260:
		if i >= 60 and i < 90:
			h.player.global_position = hacker.global_position + Vector2(0.0, 400.0)  # inside min_range: BREAK_OFF
		else:
			h.player.global_position = home
		_tick(hacker, [], true)
		seen[brain.phase] = true
		if brain.phase != Phase.PULSE:
			leak = leak or brain.darts_fired > 0 or brain.live_darts().size() > 0
		elif first_pulse_darts < 0:
			first_pulse_darts = brain.darts_fired
	assert_true(seen.has(Phase.HOLD_ARC) and seen.has(Phase.BREAK_OFF) and seen.has(Phase.TELEGRAPH) and seen.has(Phase.PULSE),
			"%s: precondition: every phase was visited (%s)" % [mode, seen.keys()])
	assert_false(leak, "%s: no dart in HOLD_ARC (cooldown running), BREAK_OFF or TELEGRAPH" % mode)
	assert_eq(first_pulse_darts, 2, "%s: both darts on PULSE's first tick" % mode)


# ── 10. Cadence (Open Space) ─────────────────────────────────────────────────────────────────────

func _cadence(props: Dictionary) -> Dictionary:
	var h = _world("open_space")
	var all := {"range_drift": 0.0}
	all.merge(props, true)
	var hacker := _spawn(h, _above(h), all)
	var brain := _brain(hacker)
	var telegraph_ticks: Array[int] = []
	var pulse_ends: Array[int] = []
	var prev := brain.phase
	for i in range(1, int(20.0 / DT) + 1):
		_tick(hacker)
		if brain.phase == Phase.TELEGRAPH and prev != Phase.TELEGRAPH:
			telegraph_ticks.append(i)
		if prev == Phase.PULSE and brain.phase != Phase.PULSE:
			pulse_ends.append(i)
		prev = brain.phase
	return {"telegraphs": telegraph_ticks, "pulse_ends": pulse_ends, "pulses": brain.pulses_fired}


func test_open_space_pulses_every_6_to_8_s_at_its_held_range() -> void:
	var run := _cadence({})
	var tg: Array[int] = run["telegraphs"]
	var ends: Array[int] = run["pulse_ends"]
	gut.p("cadence: TELEGRAPH ticks %s, PULSE ends %s" % [tg, ends])
	assert_gte(int(run["pulses"]), 2, "at least two pulses in 20 s")
	assert_eq(tg[0], 120, "the first TELEGRAPH on tick 120 (2.0 s)")
	assert_lte(tg[1] * DT, 12.5 + 1e-6, "the second by 12.5 s")
	for k in mini(ends.size(), tg.size() - 1):
		var gap := (tg[k + 1] - ends[k]) * DT
		assert_between(gap, SHIPPED.pulse_period_min - 1e-6, SHIPPED.pulse_period_max + 1e-6, "interval %d: %.3f s" % [k, gap])
	var control := _cadence({"pulse_trigger_range": 650.0})
	assert_eq((control["telegraphs"] as Array).size(), 0, "control: a 650 px trigger range never pulses at the 720 px held range")


# ── 11. The Disruptor hook ───────────────────────────────────────────────────────────────────────

## A frozen Hacker at its held range over a real ship, `first_pulse_delay` 0; [param end_at] re-places the player that far from the hull
## for the PULSE-end tick (0 = stay). Returns the lock reading through the pulse and on the end tick, and the player.
func _hook_run(mode: String, lock_seconds: float, end_at: float = 0.0) -> Dictionary:
	var h = _world(mode)
	var p := _real_player(h, mode, h.player.global_position)
	var hacker := _spawn(h, _above(h), {"first_pulse_delay": 0.0, "pulse_lock_seconds": lock_seconds})
	var brain := _brain(hacker)
	var early := false
	var on_end := false
	var ended := false
	for i in 200:
		if brain.phase == Phase.PULSE and brain._phase_time >= SHIPPED.pulse_seconds - DT - 1e-6 and end_at > 0.0:
			p.global_position = hacker.global_position + Vector2(0.0, end_at)
		var before := brain.phase
		_tick(hacker, [], true)
		if before == Phase.PULSE and brain.phase == Phase.HOLD_ARC:
			on_end = p.abilities_locked()
			ended = true
			break
		early = early or p.abilities_locked()
	return {"early": early, "on_end": on_end, "ended": ended, "p": p}


func test_the_pulse_end_hook_locks_for_pulse_lock_seconds_and_the_base_hacker_never_locks(
		mode: String = use_parameters(MODES)) -> void:
	var run := _hook_run(mode, 1.0)
	assert_true(run["ended"], "%s: precondition: the pulse ended" % mode)
	assert_false(run["early"], "%s: no lock through TELEGRAPH and PULSE" % mode)
	assert_true(run["on_end"], "%s: locked on the PULSE -> HOLD_ARC tick" % mode)
	var p: PlayerBase = run["p"]
	for _i in 59:
		p._step_disruption(DT)
	assert_true(p.abilities_locked(), "%s: still locked after 59 ticks" % mode)
	p._step_disruption(DT)
	assert_false(p.abilities_locked(), "%s: free after 60 ticks (1.0 s)" % mode)
	var base := _hook_run(mode, SHIPPED.pulse_lock_seconds)
	assert_true(base["ended"])
	assert_false(base["early"] or base["on_end"], "%s control: the shipped 0.0 never locks" % mode)
	var far := _hook_run(mode, 1.0, 871.0)
	assert_true(far["ended"])
	assert_false(far["on_end"], "%s control: a player 871 px away at the PULSE end is not locked" % mode)


# ── 17. Warheads are never darted ────────────────────────────────────────────────────────────────

func test_a_warhead_salvo_is_never_darted_and_a_homing_salvo_is(mode: String = use_parameters(MODES)) -> void:
	for type in [0, 1]:
		var h = _world(mode)
		var p := _real_player(h, mode, h.player.global_position)
		var hacker := _spawn(h, p.global_position + Vector2(0.0, -500.0))
		var brain := _brain(hacker)
		brain.enter_phase(Phase.PULSE)
		var salvo := _salvo(p, type)
		assert_eq(salvo.size(), 3, "%s: a real 3-rocket salvo (type %d)" % [mode, type])
		var rot: Array = []
		var pos: Array = []
		for w in salvo:
			rot.append(w.rotation)
			pos.append(w.global_position)
		var steady := true
		for _i in PULSE_TICKS:
			_tick(hacker, salvo, true)
			if type != 0:
				continue
			for k in salvo.size():
				var w := salvo[k] as WarheadMissile
				steady = steady and w.rotation == rot[k] \
						and absf(w.global_position.distance_to(pos[k]) - w.speed * DT) < 1e-3
				pos[k] = w.global_position
		if type == 0:
			assert_eq(brain.darts_fired, 0, "%s: no dart at a warhead" % mode)
			assert_true(steady, "%s: each warhead flies straight at its own speed" % mode)
		else:
			assert_eq(brain.darts_fired, 3, "%s control: the homing salvo from the same point is darted" % mode)


# ── 18. Primary fire is bit-identical ────────────────────────────────────────────────────────────

## Two real ships in lockstep (the `test_seeking_ordnance.gd` shape): ship B under a Hacker running TELEGRAPH + PULSE (`first_pulse_delay`
## 0: PULSE on tick 55) with a homing salvo launched on tick 50 and claimed in PULSE; ship A, out of group `player`, launches the same salvo
## unclaimed. 150 ticks of `WeaponState`, `shoot` held for the first 60: identical shot logs.
func test_primary_fire_is_identical_while_a_hacker_hijacks(mode: String = use_parameters(MODES)) -> void:
	await get_tree().process_frame
	var start := Vector2(640.0, 360.0)
	for id: StringName in UpgradeState.ALL_IDS:
		var boxes: Array[Node2D] = []
		var ships: Array[PlayerBase] = []
		for i in 2:
			var box := Node2D.new()
			add_child_autofree(box)
			var ship := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
			box.add_child(ship)
			ship.set_physics_process(false)
			ship.global_position = start + Vector2(1600.0 * i, 0.0)
			ship.rotation = 0.0
			ship.velocity = Vector2.ZERO
			boxes.append(box)
			ships.append(ship)
		ships[0].remove_from_group(&"player")
		var hacker := _spawn_into(boxes[1], ships[1].global_position + Vector2(0.0, -600.0), {"first_pulse_delay": 0.0})
		var clock: Array = [0]
		var logs: Array = [[], []]
		var states: Array = []
		for i in 2:
			var ws := ships[i].get_node("AttackStateMachine/WeaponState") as WeaponState
			ws._active_id = id
			states.append(ws)
			var rec: Array = logs[i]
			ws.child_entered_tree.connect(func(n: Node) -> void:
				var bullet := n as Bullet
				if bullet != null:
					rec.append(["shot", clock[0], bullet.damage, bullet.rotation]))
			# The mining laser fires no bullet: a dummy enemy hurtbox in its path logs its hits (the t4 row's).
			var dummy := Node2D.new()
			var hb := HurtBox.new()
			hb.name = "HurtBox"
			hb.received_damage.connect(func(d: int) -> void: rec.append(["hit", clock[0], d]))
			dummy.add_child(hb)
			dummy.add_to_group(&"enemies")
			boxes[i].add_child(dummy)
			dummy.global_position = ws.weapon_muzzles[0].global_position + Vector2(0, -300)
		var salvos: Array = [[], []]
		var claims := [0]
		for t in 150:
			clock[0] = t
			if t == 0:
				Input.action_press("shoot")
			elif t == 60:
				Input.action_release("shoot")
			if t == 50:
				for i in 2:
					salvos[i] = _salvo(ships[i], 1)
				for r in salvos[1]:
					(r as homing_missile).retargeted.connect(func(_s: Node) -> void: claims[0] += 1)
			_tick(hacker, salvos[1])
			for r in salvos[0]:
				if _alive(r):
					(r as Node)._physics_process(DT)
			for i in 2:
				seed(t)
				(states[i] as WeaponState)._physics_process(DT)
		Input.action_release("shoot")
		assert_eq(_brain(hacker).pulses_fired, 1, "%s %s: B's Hacker pulsed once" % [mode, id])
		assert_eq(claims[0], 3, "%s %s: and its darts claimed B's salvo" % [mode, id])
		assert_gt((logs[0] as Array).size(), 0, "%s %s: non-vacuous: the weapon fired" % [mode, id])
		assert_eq(logs[1], logs[0], "%s %s: shots, cadence and damage identical under a pulse" % [mode, id])
		for box in boxes:
			box.get_parent().remove_child(box)
			box.free()


# ── 19. Assault: one pulse per life ──────────────────────────────────────────────────────────────

## Ticks the Hacker for [param seconds]; PULSE entries, the TELEGRAPH -> / PULSE -> transition ticks, the DISENGAGE tick.
func _life_run(h, hacker: HackerFrigate, seconds: float, frozen: bool = false, on_tick: Callable = Callable()) -> Dictionary:
	var brain := _brain(hacker)
	var out := {"disengage": -1, "pulse_in": [], "pulse_out": [], "telegraph_out": []}
	var prev := brain.phase
	for i in range(1, int(round(seconds / DT)) + 1):
		if not _alive(hacker):
			break
		_tick(hacker, [], frozen)
		if not _alive(hacker):
			break
		if brain.phase == Phase.PULSE and prev != Phase.PULSE:
			(out["pulse_in"] as Array).append(i)
		if prev == Phase.PULSE and brain.phase != Phase.PULSE:
			(out["pulse_out"] as Array).append([i, brain.phase])
		if prev == Phase.TELEGRAPH and brain.phase != Phase.TELEGRAPH and brain.phase != Phase.PULSE:
			(out["telegraph_out"] as Array).append([i, brain.phase])
		if int(out["disengage"]) < 0 and brain.phase == Phase.DISENGAGE:
			out["disengage"] = i
		if on_tick.is_valid():
			on_tick.call(i)
		prev = brain.phase
	out["pulses"] = brain.pulses_fired
	return out


func test_an_assault_life_pulses_once_then_disengages_on_its_expiry_tick() -> void:
	var h = _world("assault")
	var hacker := _spawn(h, _above(h), {"engage_seconds": SHIPPED.engage_seconds})
	var run := _life_run(h, hacker, 10.0)
	assert_eq(run["pulses"], 1, "one pulse in a 9 s life")
	assert_between(int(run["disengage"]), int(round(9.0 / DT)) - 2, int(round(9.0 / DT)), "DISENGAGE on the expiry tick")


func test_the_per_life_cap_is_what_stops_a_second_assault_pulse() -> void:
	var fast := {"engage_seconds": 30.0, "first_pulse_delay": 0.5, "pulse_period_min": 1.0, "pulse_period_max": 1.0, "range_drift": 0.0}
	var a = _world("assault")
	var assault := _life_run(a, _spawn(a, _above(a), fast), 20.0)
	assert_eq(assault["pulses"], 1, "Assault: exactly one pulse in 20 s")
	var o = _world("open_space")
	var open := _life_run(o, _spawn(o, _above(o), fast), 20.0)
	assert_gte(int(open["pulses"]), 3, "control: Open Space pulses again and again on the same timings (%d)" % open["pulses"])
	var capped := fast.duplicate()
	capped["assault_pulses_per_life"] = 2
	var a2 = _world("assault")
	var two := _life_run(a2, _spawn(a2, _above(a2), capped), 20.0)
	assert_eq(two["pulses"], 2, "boundary: a cap of 2 gives exactly two")


func test_a_budget_expiring_in_pulse_lets_the_window_finish_and_still_locks() -> void:
	var h = _world("assault")
	var p := _real_player(h, "assault", h.player.global_position)
	var hacker := _spawn(h, _above(h), {"engage_seconds": 2.0, "first_pulse_delay": 0.5, "pulse_lock_seconds": 1.0})
	var locked := [false]
	var brain := _brain(hacker)
	var run := _life_run(h, hacker, 4.0, true, func(_i: int) -> void:
		if brain.phase == Phase.DISENGAGE and not locked[0]:
			locked[0] = p.abilities_locked())
	assert_eq(run["pulse_in"], [84], "PULSE at 1.4 s")
	assert_eq(run["pulse_out"], [[84 + PULSE_TICKS, Phase.DISENGAGE]], "the full 96-tick window, then DISENGAGE on its end tick")
	assert_eq(run["disengage"], 84 + PULSE_TICKS)
	assert_true(locked[0], "the lock hook still fired on the end tick")


func test_a_budget_expiring_in_telegraph_cancels_it() -> void:
	var h = _world("assault")
	var hacker := _spawn(h, _above(h), {"engage_seconds": 1.0, "first_pulse_delay": 0.5})
	var run := _life_run(h, hacker, 2.5, true)
	assert_eq(run["pulses"], 0, "no PULSE")
	assert_eq((run["telegraph_out"] as Array).size(), 1)
	if not (run["telegraph_out"] as Array).is_empty():
		assert_between(int(run["telegraph_out"][0][0]), 59, 61, "cancelled on the expiry tick (1.0 s)")
		assert_eq(run["telegraph_out"][0][1], Phase.DISENGAGE, "straight to DISENGAGE")
	assert_eq(_brain(hacker).telegraph_cancels, 1)


# ── 20. EMP (deviation D2) ───────────────────────────────────────────────────────────────────────

func test_an_emp_cancels_a_telegraph_and_ends_a_pulse_without_the_lock(mode: String = use_parameters(MODES)) -> void:
	for at in [Phase.TELEGRAPH, Phase.PULSE, -1]:
		var h = _world(mode)
		var p := _real_player(h, mode, h.player.global_position)
		var hacker := _spawn(h, _above(h), {"first_pulse_delay": 0.0, "pulse_lock_seconds": 1.0})
		var brain := _brain(hacker)
		var stop_tick := 10 if at == Phase.TELEGRAPH else 70  # TELEGRAPH ticks 1-54, PULSE from tick 55
		for _i in stop_tick:
			_tick(hacker, [], true)
		if at == -1:
			for _i in 60:
				_tick(hacker, [], true)
			assert_eq(brain.pulses_fired, 1, "%s control: with no EMP the TELEGRAPH reached PULSE" % mode)
			continue
		assert_eq(brain.phase, at, "%s: precondition" % mode)
		hacker.apply_emp(2.0, null)
		assert_eq(brain.phase, Phase.HOLD_ARC, "%s: an EMP ends %s at once" % [mode, Phase.keys()[at]])
		assert_eq(hacker.state_light().get_state(), StateLight.State.OFF, "%s: light off" % mode)
		assert_eq(hacker.dish_open(), 0.0, "%s: dish folded" % mode)
		if at == Phase.TELEGRAPH:
			assert_eq(brain.telegraph_cancels, 1, "%s: counted as a cancel" % mode)
		assert_false(p.abilities_locked(), "%s: no lock" % mode)
		for _i in 130:
			_tick(hacker, [], true)
		assert_false(hacker.is_emp_disrupted(), "%s: the window is over" % mode)
		assert_eq(brain.phase, Phase.HOLD_ARC, "%s: back in HOLD_ARC" % mode)
		assert_false(p.abilities_locked(), "%s: still no lock" % mode)
		assert_between(brain.pulse_cooldown, SHIPPED.pulse_period_min - 0.2, SHIPPED.pulse_period_max,
				"%s: with a fresh cooldown (%.2f s, counting again from the window's end)" % [mode, brain.pulse_cooldown])


# ── 22. Fairness (deviation D4: the geometry is the task plan's, fixed by review B3) ──────────────

## The fairness point P: Open Space (0, 0), Assault (640, 560).
func _fair_p(mode: String) -> Vector2:
	return Vector2.ZERO if mode == "open_space" else Vector2(640.0, 560.0)


## Hand-ticked: a real player at P; a frozen Hacker at P + (300, -450) in PULSE from tick 0; three homing rockets from P + (-7 / 0 / 7, -450)
## flying +y at a static point P + (0, 400). With [param moving] the player cruises +x from tick 0 (Open Space 420 px/s, then +y after
## 0.6 s; Assault 360 px/s, then -y after 0.6 s). Per rocket: the claim tick, the end tick and the closest approach after its claim.
func _fair(mode: String, moving: bool) -> Dictionary:
	var blasts0 := _blasts.size()
	var h = _world(mode)
	var at := _fair_p(mode)
	var p := _real_player(h, mode, at)
	var hacker := _spawn(h, at + Vector2(300.0, -450.0))
	_brain(hacker).enter_phase(Phase.PULSE)
	var goal := _static_target(h.root, at + Vector2(0.0, 400.0))
	var rockets: Array = []
	var stats: Array = []
	for dx in [-7.0, 0.0, 7.0]:
		var r := _hand_rocket(h.root, at + Vector2(dx, -450.0), Vector2.DOWN, goal)
		rockets.append(r)
		var s := {"claim": -1, "end": -1, "closest": INF}
		stats.append(s)
	var tick := [0]
	for k in 3:
		var s: Dictionary = stats[k]
		(rockets[k] as homing_missile).retargeted.connect(func(_src: Node) -> void: s["claim"] = tick[0])
		(rockets[k] as homing_missile).retarget_ended.connect(func() -> void: s["end"] = tick[0])
	var speed := 420.0 if mode == "open_space" else 360.0
	var turned := Vector2.DOWN if mode == "open_space" else Vector2.UP
	for i in range(1, 300):
		tick[0] = i
		_tick(hacker, rockets, true)
		if moving:
			p.global_position += (Vector2.RIGHT if i * DT < 0.6 else turned) * speed * DT
		for k in 3:
			if _alive(rockets[k]) and (rockets[k] as homing_missile).is_retargeted():
				stats[k]["closest"] = minf(float(stats[k]["closest"]), (rockets[k] as Node2D).global_position.distance_to(p.global_position))
		if not (_alive(rockets[0]) or _alive(rockets[1]) or _alive(rockets[2])):
			break
	await get_tree().process_frame
	return {"stats": stats, "blasts": _blasts.size() - blasts0}


func test_a_player_who_moves_off_the_line_is_never_blasted_and_a_still_one_is(mode: String = use_parameters(MODES)) -> void:
	var still: Dictionary = await _fair(mode, false)
	var first_blast := 1 << 30
	var last_claim := -1
	for s in still["stats"]:
		first_blast = mini(first_blast, int(s["end"]))
		last_claim = maxi(last_claim, int(s["claim"]))
	gut.p("%s fairness, still: claims %s, ends %s, %d blasts" % [mode, still["stats"].map(func(s: Dictionary) -> int: return s["claim"]),
			still["stats"].map(func(s: Dictionary) -> int: return s["end"]), still["blasts"]])
	assert_gte(int(still["blasts"]), 1, "%s control: a still player is blasted" % mode)
	assert_gte(last_claim, 1, "%s precondition: all claimed" % mode)
	assert_lte((last_claim + 18) * DT, first_blast * DT + 1e-6, "%s precondition: every claim at least 0.3 s before the first blast" % mode)
	var moving: Dictionary = await _fair(mode, true)
	for k in 3:
		var s: Dictionary = moving["stats"][k]
		gut.p("%s fairness, moving: rocket %d claimed tick %d, closest %.1f px" % [mode, k, s["claim"], s["closest"]])
		assert_gte(int(s["claim"]), 1, "%s rocket %d: claimed" % [mode, k])
		assert_gt(float(s["closest"]), 30.0, "%s rocket %d: never within the trigger radius" % [mode, k])
	assert_eq(moving["blasts"], 0, "%s: a player who cruised off the line and turned is never blasted" % mode)


# ── 23. The arc goes on through TELEGRAPH and PULSE (review B2) ──────────────────────────────────

const ARC_PROPS := {"nose_cone_deg": 0.0, "route_cone_deg": 0.0, "range_drift": 0.0, "reversal_min": 30.0, "reversal_max": 30.0}


## The shipped cycle on the forced cw arc (0.18 rad/s): the bearing rate round the still player over 1.0-2.0 s (HOLD_ARC) and over the
## whole TELEGRAPH + PULSE (2.0-4.5 s), the worst nose error in the window, and whether the Assault view clamp ever bound.
func _arc_window(mode: String, extra: Dictionary = {}) -> Dictionary:
	var h = _world(mode)
	var props := ARC_PROPS.duplicate()
	props.merge(extra, true)
	var hacker := _spawn(h, _above(h), props)
	var brain := _brain(hacker)
	brain.force_orbit_direction(1)
	var player: Node2D = h.player
	var bearing := 0.0
	var at := {}
	var tg := -1
	var end := -1
	var nose := 0.0
	var clamp := false
	var prev := brain.phase
	for i in range(1, 300):
		var before := (hacker.global_position - player.global_position).angle()
		_tick(hacker)
		bearing += wrapf((hacker.global_position - player.global_position).angle() - before, -PI, PI)
		at[i] = bearing
		if tg < 0 and brain.phase == Phase.TELEGRAPH:
			tg = i
		if tg > 0 and end < 0 and prev == Phase.PULSE and brain.phase != Phase.PULSE:
			end = i
		if tg > 0 and end < 0:
			var facing := Vector2.RIGHT.rotated(hacker.rotation + hacker.sprite_forward_angle)
			nose = maxf(nose, absf(facing.angle_to(player.global_position - hacker.global_position)))
		clamp = clamp or brain.view_clamp_bound
		prev = brain.phase
	var hold := (float(at[120]) - float(at[60])) / 1.0
	var window := (float(at[end]) - float(at[tg])) / ((end - tg) * DT) if tg > 0 and end > 0 else 0.0
	return {"tg": tg, "end": end, "hold": hold, "window": window, "nose": nose, "clamp": clamp}


func test_the_hacker_keeps_its_arc_and_its_nose_through_the_pulse(mode: String = use_parameters(MODES)) -> void:
	var run := _arc_window(mode)
	gut.p("%s arc: TELEGRAPH tick %d, PULSE end tick %d, rate %.4f (HOLD_ARC) / %.4f (window) rad/s, nose worst %.2f deg" % [mode, run["tg"],
			run["end"], run["hold"], run["window"], rad_to_deg(float(run["nose"]))])
	assert_eq([run["tg"], run["end"]], [120, 120 + TELEGRAPH_TICKS + PULSE_TICKS], "%s: the window is 2.0-4.5 s" % mode)
	assert_almost_eq(float(run["window"]), float(run["hold"]), 0.02, "%s: the window's rate is the arc's" % mode)
	assert_almost_eq(float(run["hold"]), SHIPPED.orbit_speed_cw, 0.02, "%s: HOLD_ARC at the cw 0.18 rad/s" % mode)
	assert_almost_eq(float(run["window"]), SHIPPED.orbit_speed_cw, 0.02, "%s: and the window too (review R2)" % mode)
	assert_lt(float(run["nose"]), deg_to_rad(5.0), "%s: the nose stays on the player" % mode)
	if mode == "assault":
		assert_false(run["clamp"], "assault: the view clamp never binds")
	var parked := _arc_window(mode, {"max_speed": PARKED})
	assert_lt(absf(float(parked["window"]) - SHIPPED.orbit_speed_cw), 0.02 + 1.0, "sanity")
	assert_gt(absf(float(parked["window"]) - SHIPPED.orbit_speed_cw), 0.02, "%s control: a parked hull fails the rate" % mode)


## t8's cone-row snap on the TELEGRAPH entry tick, the 0.18 rad/s far-way case (review R3: axis = bearing + s * 10 degrees); the exit
## through the near edge, measured against the full ± 30 degree cone by the test.
func _cone_in_window(cone_deg: float) -> Dictionary:
	var h = _world("open_space")
	var hacker := _spawn(h, _above(h), ARC_PROPS)
	var brain := _brain(hacker)
	brain.force_orbit_direction(1)
	var player: CharacterBody2D = h.player
	var guard := 0
	while brain.phase != Phase.TELEGRAPH and guard < 300:
		_tick(hacker)
		guard += 1
	var b := (hacker.global_position - player.global_position).angle()
	var s := signf((hacker.global_position - player.global_position).normalized().cross(hacker.velocity - player.velocity))
	var axis := b + s * deg_to_rad(10.0)
	player.rotation = axis + PI / 2.0
	hacker.config.nose_cone_deg = cone_deg
	var out := {"exit": -1.0, "near": false, "inside_at_bound": false, "pulse_end": -1.0, "sign": s}
	var prev := brain.phase
	for i in range(1, 200):
		_tick(hacker)
		var a := wrapf((hacker.global_position - player.global_position).angle() - axis, -PI, PI)
		if i == int(round(2.2 / DT)):
			out["inside_at_bound"] = absf(a) < deg_to_rad(30.0)
		if float(out["exit"]) < 0.0 and absf(a) >= deg_to_rad(30.0):
			out["exit"] = i * DT
			out["near"] = signf(a) == -s
		if float(out["pulse_end"]) < 0.0 and prev == Phase.PULSE and brain.phase != Phase.PULSE:
			out["pulse_end"] = i * DT
		prev = brain.phase
	return out


func test_it_slides_out_of_the_nose_during_the_pulse() -> void:
	var run := _cone_in_window(30.0)
	gut.p("cone in the window: exit %.3f s (near %s), PULSE ends %.3f s after the snap" % [run["exit"], run["near"], run["pulse_end"]])
	assert_eq(float(run["sign"]), 1.0, "precondition: moving the cw way")
	assert_between(float(run["exit"]), 0.0, 2.2 + 1e-6, "out of the 30 degree cone within 2.2 s")
	assert_true(run["near"], "through the near edge")
	assert_lt(float(run["exit"]), float(run["pulse_end"]), "before PULSE ends")
	var control := _cone_in_window(0.0)
	assert_true(control["inside_at_bound"], "control: cone 0 is still inside at 2.2 s")


## The player is re-placed 400 px from the hull (inside `min_range`) for every tick from [param from_tick] on.
func _committed(mode: String, from_tick: int) -> Dictionary:
	var h = _world(mode)
	var hacker := _spawn(h, _above(h), ARC_PROPS)
	var brain := _brain(hacker)
	brain.force_orbit_direction(1)
	var dir: Vector2 = (h.player.global_position - hacker.global_position).normalized()
	var out := {"break_in_attack": false, "pulse_end": -1, "break_at": -1, "phase_at_start": -1}
	var prev := brain.phase
	for i in range(1, 400):
		if i >= from_tick:
			if i == from_tick:
				out["phase_at_start"] = brain.phase
			h.player.global_position = hacker.global_position + dir * 400.0
		_tick(hacker)
		if int(out["pulse_end"]) < 0 and prev == Phase.PULSE and brain.phase != Phase.PULSE:
			out["pulse_end"] = i
		if int(out["break_at"]) < 0 and brain.phase == Phase.BREAK_OFF:
			out["break_at"] = i
			break
		prev = brain.phase
	return out


func test_no_break_off_until_the_pulse_ends_then_on_the_next_tick(mode: String = use_parameters(MODES)) -> void:
	var run := _committed(mode, 121)
	assert_eq(run["phase_at_start"], Phase.TELEGRAPH, "%s: precondition: re-placed from TELEGRAPH entry on" % mode)
	assert_eq(run["pulse_end"], 120 + TELEGRAPH_TICKS + PULSE_TICKS, "%s: TELEGRAPH and PULSE ran through" % mode)
	assert_eq(run["break_at"], int(run["pulse_end"]) + 1, "%s: BREAK_OFF on the first HOLD_ARC tick after the PULSE end" % mode)
	var control := _committed(mode, 60)
	assert_eq(control["phase_at_start"], Phase.HOLD_ARC, "%s control: precondition" % mode)
	assert_eq(control["break_at"], 60, "%s control: from HOLD_ARC it breaks off on its first tick" % mode)


# ── 14. Line of sight (real physics, 8x; deviation D3: a real wreck) ─────────────────────────────

## Waits physics ticks until [param cond] holds (checked before each), at most [param cap]; whether it held.
func _wait_until(cond: Callable, cap: int) -> bool:
	for _i in cap:
		if cond.call():
			return true
		await _frames(1)
	return cond.call()


## (a) A fixture enemy's body midway between hull and player is no cover: TELEGRAPH, then PULSE 54 ticks later with no hit (the no-hit
## control of (c)). (b) In the same run, of two rockets held 400 px from the hull, the one behind a wreck gets no dart.
func test_an_enemy_body_never_blocks_the_pulse_and_a_wreck_covers_a_rocket(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var hull := _above(h)
	var player_at: Vector2 = h.player.global_position
	var fixture := FIXTURE_ENEMY.instantiate() as Node2D
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0
	shape.shape = circle
	fixture.add_child(shape)
	h.root.add_child(fixture)
	fixture.set_physics_process(false)
	fixture.global_position = (hull + player_at) / 2.0
	var clear_r := _hand_rocket(h.root, hull + Vector2(400.0, 0.0), Vector2.DOWN)
	var covered_r := _hand_rocket(h.root, hull + Vector2(-400.0, 0.0), Vector2.DOWN)
	_wreck(h, hull + Vector2(-150.0, 0.0))
	await _frames(2)
	var hacker := _spawn(h, hull, {"max_speed": PARKED, "first_pulse_delay": 0.1}, 1, false)
	var brain := _brain(hacker)
	var ticker := _Ticker.new()
	var probe := {}
	var events: Array = []
	var claim := [-1]
	var covered_claims := [0]
	brain.phase_changed.connect(func(p: int) -> void: events.append([ticker.ticks, p]))
	clear_r.retargeted.connect(func(_s: Node) -> void: claim[0] = ticker.ticks)
	covered_r.retargeted.connect(func(_s: Node) -> void: covered_claims[0] += 1)
	ticker.on_tick = func(t: int) -> void:
		if t == 1:
			var q := PhysicsRayQueryParameters2D.create(hacker.global_position, player_at, LineOfSight.BLOCK_MASK)
			q.collide_with_areas = false
			q.exclude = [hacker.get_rid()]
			probe.merge(hacker.get_world_2d().direct_space_state.intersect_ray(q))
	h.root.add_child(ticker)
	var done := await _wait_until(func() -> bool: return claim[0] >= 0 and ticker.ticks >= claim[0] + 10, 240)
	assert_true(done, "%s: the clear rocket was claimed" % mode)
	assert_eq(probe.get("collider"), fixture, "%s: precondition: the ray from the hull meets the fixture's body first" % mode)
	var tg := -1
	var pulse := -1
	for e in events:
		if tg < 0 and e[1] == Phase.TELEGRAPH:
			tg = e[0]
		if pulse < 0 and e[1] == Phase.PULSE:
			pulse = e[0]
	assert_gte(tg, 0, "%s: an enemy body does not block the pulse: TELEGRAPH" % mode)
	assert_eq(pulse - tg, TELEGRAPH_TICKS, "%s: and PULSE 54 ticks later, with no hit" % mode)
	assert_eq(brain.darts_fired, 1, "%s: one dart, at the clear rocket" % mode)
	assert_eq(covered_claims[0], 0, "%s: the rocket behind the wreck gets none" % mode)
	assert_eq(brain.telegraph_cancels, 0)


## (c) A wreck midway hides the player: no TELEGRAPH for 1.0 s; freed, TELEGRAPH within 3 ticks; then one real player bullet cancels it.
func test_a_wreck_between_holds_the_charge_and_a_bullet_cancels_it(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var hull := _above(h)
	var wreck := _wreck(h, (hull + h.player.global_position) / 2.0)
	await _frames(2)
	var hacker := _spawn(h, hull, {"max_speed": PARKED, "first_pulse_delay": 0.1}, 1, false)
	var brain := _brain(hacker)
	var ticker := _Ticker.new()
	h.root.add_child(ticker)
	var events: Array = []
	brain.phase_changed.connect(func(p: int) -> void: events.append([ticker.ticks, p]))
	var hits: Array = []
	hacker.health.amount_changed.connect(func(_hp: int) -> void: hits.append(ticker.ticks))
	await _frames(60)
	assert_eq(brain.telegraphs, 0, "%s: no TELEGRAPH for 1.0 s with a wreck between" % mode)
	var freed_at := ticker.ticks
	wreck.queue_free()
	await _wait_until(func() -> bool: return brain.telegraphs > 0, 8)
	var tg := -1
	for e in events:
		if e[1] == Phase.TELEGRAPH:
			tg = e[0]
	assert_between(tg - freed_at, 0, 3, "%s: TELEGRAPH within 3 ticks of the wreck going (%d)" % [mode, tg - freed_at])
	var bullet: Bullet = BULLET_SCENE.instantiate()
	h.root.add_child(bullet)
	bullet.global_position = hull + Vector2(0.0, 70.0)
	bullet.rotation = 0.0  # forward = UP, at the hull
	bullet.expired.connect(bullet.queue_free)
	await _wait_until(func() -> bool: return not hits.is_empty(), 20)
	assert_false(hits.is_empty(), "%s: the bullet hit" % mode)
	if hits.is_empty():
		return
	var hit: int = hits[0]
	await _wait_until(func() -> bool: return ticker.ticks >= hit + 2, 4)
	assert_eq(brain.phase, Phase.HOLD_ARC, "%s: the charge is cancelled" % mode)
	assert_eq(brain.telegraph_cancels, 1, "%s: one cancel" % mode)
	await _wait_until(func() -> bool: return ticker.ticks >= tg + TELEGRAPH_TICKS + 3, 80)
	var pulses := events.filter(func(e: Array) -> bool: return e[1] == Phase.PULSE)
	assert_eq(pulses, [], "%s: no PULSE when it would have come" % mode)
	assert_gte(brain.pulse_cooldown, SHIPPED.pulse_period_min - (ticker.ticks - hit) * DT - DT, "%s: a fresh cooldown" % mode)


# ── 22b. Fairness on real physics: the still player's damage ─────────────────────────────────────

func test_a_still_player_loses_one_18_point_blast_on_real_physics(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h = _world(mode)
	var at := _fair_p(mode)
	var p := _real_player(h, mode, at)
	var hurt := p.get_node("HurtBox") as HurtBox
	var received: Array[int] = []
	hurt.received_damage.connect(func(d: int) -> void: received.append(d))
	var hp0 := p.health_component.current_health
	var goal := _static_target(h.root, at + Vector2(0.0, 400.0))
	await _frames(2)
	var blasts0 := _blasts.size()
	var hacker := _spawn(h, at + Vector2(300.0, -450.0), {"max_speed": PARKED, "pulse_telegraph": 0.05, "first_pulse_delay": 0.0}, 1, false)
	var brain := _brain(hacker)
	var ticker := _Ticker.new()
	h.root.add_child(ticker)
	var rockets: Array = []
	var ends: Array = []
	brain.phase_changed.connect(func(ph: int) -> void:
		if ph != Phase.PULSE or not rockets.is_empty():
			return
		for dx in [-7.0, 0.0, 7.0]:
			var r := _live_rocket(h.root, at + Vector2(dx, -450.0), Vector2.DOWN, goal)
			r.retarget_ended.connect(func() -> void: ends.append(ticker.ticks))
			rockets.append(r))
	var gone := await _wait_until(func() -> bool:
		return rockets.size() == 3 and rockets.all(func(r: Variant) -> bool: return not _alive(r)), 240)
	await _frames(4)
	gut.p("%s real blast: ends at ticks %s, %d blasts, received %s, HP %d -> %d" % [mode, ends, _blasts.size() - blasts0, received, hp0,
			p.health_component.current_health])
	assert_true(gone, "%s: all three rockets ended" % mode)
	assert_eq(_blasts.size() - blasts0, 3, "%s: all three blasted on the still player" % mode)
	assert_eq(ends.size(), 3)
	if ends.size() == 3:
		assert_lte(int(ends.max()) - int(ends.min()), 3, "%s: within 3 ticks of each other, so the i-frames decide" % mode)
	assert_gt(received.size(), 0, "%s: the player was hit" % mode)
	for d in received:
		assert_eq(d, 18, "%s: only hijack_blast_damage, never 100" % mode)
	assert_eq(hp0 - p.health_component.current_health, 18, "%s: one blast's 18 HP (pinned), well under 3 x 18" % mode)
