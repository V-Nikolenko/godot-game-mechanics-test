## INTENT tests for Phase 9 plan §2.5 (docs/plans/cmug23onr001pm52w9swwophy/3-plan.md; task plan
## docs/plans/cmw5k4yjr00a2qs2xu2iw7gvd/3-plan.md): the seeking-ordnance retarget contract and the hijacked homing rocket.
##
## A player homing rocket joins `SeekingOrdnance.GROUP` and answers `can_be_retargeted()` / `retarget()` /
## `is_retargeted()` / `jam_guidance()`. A claimed ("hijacked") rocket turns at `hijack_turn_rate` toward the player,
## eases to `hijack_speed`, hurts the player only by a `ContactBlast` once armed, keeps full damage on enemies, is shot
## down by one player bullet, and fizzles at the end of its window or when its source is freed. No Hacker exists yet:
## a fixture `_Claimer` node stands in for it (`SeekingOrdnance.eligible()` then `retarget(player, -1.0, self)`).
##
## Two kinds of row, the `test_enemy_rockets.gd` shape:
##   - HAND-TICKED (eligibility, turn, speed, arming, fizzle, source death, lifetime, tether, jammed, dodge, EventBus):
##     the rocket's and its `ProjectileLifetime`'s physics are off and `_tick()` calls the rocket's then the lifetime's
##     `_physics_process(DT)` (tree order), in both harnesses (`enemy_ai_harness.gd`, label-parameterised). A
##     `ContactBlast` attaches deferred, so a row that counts blasts awaits one idle frame after its loop.
##   - REAL PHYSICS on the 8x clock (blast on both real player scenes, lure, shoot-down, the self-hit and crossing guards):
##     only where a real overlap is the point. `_seconds()` / `_frames()` count game time at the unscaled tick rate.
##     The crossing row is the real-physics falsifier of both guards: a claimed rocket's HurtBox turns monitorable while
##     already overlapping its own HitBox and its salvo-mates', and Godot forms no pair for that, so the salvo row also
##     hands the HitBox callbacks the HurtBox directly.
##
## Rocket numbers are read from `homing_missile.tscn`'s exports, never typed, except in the one row that pins them.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const WARHEAD_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/warhead/warhead_missile.tscn")
const FIXTURE_ENEMY: PackedScene = preload("res://tests/helpers/fixture_enemy.tscn")
const BULLET_SCENE: PackedScene = preload("res://assault/scenes/projectiles/bullets/bullet.tscn")
const SHIP_SCENE: PackedScene = preload("res://open_space/scenes/entities/player/player_ship.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")

const MODES: Array = ["open_space", "assault"]
const DT := 1.0 / 60.0
const START := Vector2(640, 360)
const AMBER := Color(1.0, 0.7, 0.3)
const FIXTURE_HP := 1000

const _SPEEDUP := 8
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false

var _sandbox := SaveSandbox.new()
var _blasts: Array[Vector2] = []


## Stands in for the Hacker's dart: claims up to [param cap] eligible rockets within [param reach] for [param target].
class _Claimer extends Node2D:
	func claim(target: Node2D, reach: float, cap: int = 3) -> Array[Node2D]:
		var got: Array[Node2D] = []
		for rocket in SeekingOrdnance.eligible(get_tree(), global_position, reach):
			if got.size() >= cap:
				break
			if rocket.call(&"retarget", target, -1.0, self):
				got.append(rocket)
		return got


func before_all() -> void:
	_sandbox.capture()


func after_all() -> void:
	_sandbox.restore()


func before_each() -> void:
	_blasts = []


func after_each() -> void:
	_restore_clock()
	Input.action_release(&"shoot")


# --- Helpers ----------------------------------------------------------------------------------------------------------


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


## Waits [param s] game seconds of physics (frames counted at the unscaled tick rate).
func _seconds(s: float) -> void:
	await _frames(maxi(1, roundi(s * (_saved_ticks if _clock_scaled else Engine.physics_ticks_per_second))))


## Waits [param n] physics ticks (each one 1/60 s of game time, on the 8x clock too).
func _frames(n: int) -> void:
	await wait_physics_frames(n)


func _harness(mode: String) -> RefCounted:
	var h: RefCounted = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_watch_blasts(h.root)
	return h


func _watch_blasts(parent: Node) -> void:
	parent.child_entered_tree.connect(func(node: Node) -> void:
		if node is ContactBlast:
			_blasts.append((node as ContactBlast).global_position))


## A rocket in [param parent] at [param at] flying along [param dir], with its own and its lifetime's physics off.
func _hand_rocket(parent: Node, at: Vector2, dir: Vector2, target: Node = null) -> homing_missile:
	var r := _live_rocket(parent, at, dir, target)
	r.set_physics_process(false)
	_lifetime(r).set_physics_process(false)
	return r


## A rocket in [param parent] flying on real physics.
func _live_rocket(parent: Node, at: Vector2, dir: Vector2, target: Node = null) -> homing_missile:
	var r: homing_missile = HOMING_SCENE.instantiate()
	r.locked_target = target
	parent.add_child(r)
	r.global_position = at
	r.rotation = dir.angle() + PI / 2.0
	return r


func _lifetime(r: Node) -> ProjectileLifetime:
	return r.get_node("ProjectileLifetime") as ProjectileLifetime


func _tick(r: homing_missile) -> void:
	r._physics_process(DT)
	_lifetime(r)._physics_process(DT)


func _heading(r: Node2D) -> Vector2:
	return Vector2.UP.rotated(r.rotation)


func _claimer(parent: Node, at: Vector2) -> _Claimer:
	var c := _Claimer.new()
	parent.add_child(c)
	c.global_position = at
	return c


## Counts `retargeted`, `retarget_ended` and `expired` on [param r].
func _log(r: homing_missile) -> Dictionary:
	var log := {"retargeted": [], "ended": 0, "expired": 0}
	r.retargeted.connect(func(source: Node) -> void: (log["retargeted"] as Array).append(source))
	r.retarget_ended.connect(func() -> void: log["ended"] = int(log["ended"]) + 1)
	r.expired.connect(func() -> void: log["expired"] = int(log["expired"]) + 1)
	return log


## A lit jammer field (the Phase 9 §2.2 fixture), built from props before it enters the tree.
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


func _static_target(parent: Node, at: Vector2) -> Node2D:
	var t := Node2D.new()
	parent.add_child(t)
	t.global_position = at
	return t


func _circle(radius: float) -> CollisionShape2D:
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	return shape


## A real player (no shield) in place of the harness's fake one, own physics and process off.
func _real_player(h: RefCounted, mode: String, at: Vector2 = START) -> PlayerBase:
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


## Launches a real salvo through the player's `RocketState` (type 0 warhead, 1 homing) and returns the new rockets.
func _salvo(p: PlayerBase, type: int) -> Array[Node2D]:
	var rs := _rocket_state(p)
	var before := rs.get_children()
	rs._type = type
	rs._launch()
	var fresh: Array[Node2D] = []
	for child in rs.get_children():
		if not before.has(child) and child is Node2D:
			fresh.append(child as Node2D)
	return fresh


## Untyped on purpose: a freed rocket must read as "not alive", not raise a type error.
func _alive(n: Variant) -> bool:
	return is_instance_valid(n) and not (n as Node).is_queued_for_deletion()


# --- The contract -----------------------------------------------------------------------------------------------------


func test_the_scene_carries_the_hijack_tuning_and_a_closed_shoot_down_hurtbox() -> void:
	var r: homing_missile = HOMING_SCENE.instantiate()
	add_child_autofree(r)
	assert_eq(r.speed, 500.0)
	assert_eq(r.hijack_speed, 380.0)
	assert_eq(r.hijack_turn_rate, 1.6)
	assert_eq(r.hijack_seconds, 2.5)
	assert_eq(r.hijack_ease_seconds, 0.5)
	assert_eq(r.hijack_blast_damage, 18)
	assert_eq(r.hijack_blast_radius, 40.0)
	assert_eq(r.hijack_blast_frames, 3)
	assert_eq(r.hijack_trigger_radius, 30.0)
	assert_eq(r.hijack_arm_seconds, 0.25)
	assert_eq(r.hijack_arm_clearance, 60.0)
	assert_eq(r.tether_seconds, 0.3)
	var hit := r.get_node("HitBox") as HitBox
	assert_eq(hit.collision_layer, CollisionLayers.PLAYER_ROCKETS, "HitBox layer 32 unchanged")
	assert_eq(hit.collision_mask, 513, "HitBox mask 513 unchanged")
	assert_eq(hit.damage, 100, "full damage on enemies")
	var hurt := r.get_node("HurtBox") as HurtBox
	assert_not_null(hurt, "a shoot-down HurtBox")
	assert_eq(hurt.collision_layer, CollisionLayers.ENEMY_HURTBOX, "layer 512")
	assert_eq(hurt.collision_mask, CollisionLayers.PLAYER_HITBOX, "mask 64: only primary fire shoots it down")
	assert_false(hurt.monitoring, "closed until hijacked")
	assert_false(hurt.monitorable, "closed until hijacked")
	for sig in [&"retargeted", &"retarget_ended", &"expired"]:
		assert_true(r.has_signal(sig), "declares %s" % sig)
	var args: Array = []
	for s in r.get_signal_list():
		if s["name"] == "retargeted":
			args = s["args"]
	assert_eq(args.size(), 1, "retargeted(source: Node)")


func test_group_eligibility_order_and_refusals(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var at := START
	var near := _hand_rocket(h.root, at + Vector2(50, 0), Vector2.UP)
	var mid := _hand_rocket(h.root, at + Vector2(0, -100), Vector2.UP)
	var edge := _hand_rocket(h.root, at + Vector2(-300, 0), Vector2.UP)
	var beyond := _hand_rocket(h.root, at + Vector2(0, 301), Vector2.UP)
	var tie_a := _hand_rocket(h.root, at + Vector2(0, 200), Vector2.UP)
	var tie_b := _hand_rocket(h.root, at + Vector2(0, -200), Vector2.UP)
	var warhead: Node2D = WARHEAD_SCENE.instantiate()
	h.root.add_child(warhead)
	warhead.global_position = at + Vector2(10, 0)
	warhead.set_physics_process(false)
	assert_true(near.is_in_group(SeekingOrdnance.GROUP), "%s: a homing rocket is in the group" % mode)
	assert_false(warhead.is_in_group(SeekingOrdnance.GROUP), "%s: a warhead never is" % mode)
	assert_false(warhead.has_method(&"retarget"), "%s: and has no retarget()" % mode)

	var ties: Array[Node2D] = [tie_a, tie_b]
	ties.sort_custom(func(a: Node2D, b: Node2D) -> bool: return a.get_instance_id() < b.get_instance_id())
	var expected: Array[Node2D] = [near, mid, ties[0], ties[1], edge]
	assert_eq(SeekingOrdnance.eligible(get_tree(), at, 300.0), expected,
			"%s: sorted by distance, ties by instance id, one exactly at reach kept, one past it dropped" % mode)
	assert_false(SeekingOrdnance.eligible(get_tree(), at, 300.0).has(beyond))

	# A hijacked rocket drops out and refuses a second claim.
	var c := _claimer(h.root, at + Vector2(0, -600))
	var hijacks: Array = []
	var on_bus := func(rocket: Node2D, source: Node) -> void: hijacks.append([rocket, source])
	EventBus.player_ordnance_hijacked.connect(on_bus)
	var log := _log(mid)
	assert_true(mid.retarget(h.player, -1.0, c), "%s: a first claim succeeds" % mode)
	assert_false(SeekingOrdnance.eligible(get_tree(), at, 300.0).has(mid), "%s: a hijacked rocket is not eligible" % mode)
	assert_false(mid.can_be_retargeted())
	assert_false(mid.retarget(h.player, -1.0, c), "%s: and refuses a second claim" % mode)
	assert_eq((log["retargeted"] as Array).size(), 1, "%s: retargeted once" % mode)
	assert_eq(hijacks.size(), 1, "%s: one EventBus emit for one claim" % mode)

	# A null target is refused, with nothing changed.
	var log_near := _log(near)
	assert_false(near.retarget(null, -1.0, c), "%s: a null target is refused" % mode)
	assert_false(near.is_retargeted())
	assert_eq((log_near["retargeted"] as Array).size(), 0, "%s: no retargeted on a refusal" % mode)
	assert_eq(hijacks.size(), 1, "%s: no EventBus emit on a refusal" % mode)
	var before := near.global_position
	_tick(near)
	assert_almost_eq(near.global_position, before + Vector2.UP * near.speed * DT, Vector2.ONE * 1e-3,
			"%s: a refused rocket flies on as before" % mode)

	# Inside a lit jammer field: not eligible, refused.
	_jammer(h.root, edge.global_position, 40.0)
	assert_false(edge.can_be_retargeted(), "%s: not retargetable inside a lit field" % mode)
	assert_false(SeekingOrdnance.eligible(get_tree(), at, 300.0).has(edge), "%s: dropped from eligible()" % mode)
	assert_false(edge.retarget(h.player, -1.0, c), "%s: refused inside a lit field" % mode)
	assert_true(near.can_be_retargeted(), "%s: control: a rocket outside the field still can be" % mode)
	assert_eq(hijacks.size(), 1)
	EventBus.player_ordnance_hijacked.disconnect(on_bus)


func test_the_claimer_takes_at_most_its_cap_nearest_first(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var rockets: Array[homing_missile] = []
	for i in 4:
		rockets.append(_hand_rocket(h.root, START + Vector2(40.0 * (i + 1), 0), Vector2.UP))
	var c := _claimer(h.root, START)
	var got := c.claim(h.player, 500.0, 3)
	assert_eq(got, [rockets[0], rockets[1], rockets[2]] as Array[Node2D], "%s: the three nearest" % mode)
	assert_false(rockets[3].is_retargeted(), "%s: the fourth is left alone" % mode)


# --- Hijacked flight (hand-ticked, both harnesses) ---------------------------------------------------------------------


func test_a_claimed_rocket_turns_no_faster_than_hijack_turn_rate_and_comes_round(
		mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	# Flying directly away from the player, 800 px out: it has to come all the way round.
	h.player.global_position = Vector2(640, 900)
	var r := _hand_rocket(h.root, Vector2(640, 100), Vector2.UP)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(640, -200))))
	var bound := r.hijack_turn_rate * DT + 1e-4
	var worst := 0.0
	var total := 0.0
	var pointed_tick := -1
	var prev := _heading(r)
	for t in range(1, 151):
		if not _alive(r):
			break
		_tick(r)
		var now := _heading(r)
		var step := absf(prev.angle_to(now))
		worst = maxf(worst, step)
		total += step
		prev = now
		if pointed_tick < 0 and _alive(r) \
				and absf(now.angle_to(h.player.global_position - r.global_position)) <= 0.05:
			pointed_tick = t
	assert_lte(worst, bound, "%s: per-tick turn %.5f <= hijack_turn_rate * DT + 1e-4" % [mode, worst])
	assert_gt(total, 2.0, "%s: control: it really turned (%.2f rad)" % [mode, total])
	assert_between(pointed_tick, 1, 150, "%s: it points at the player within 2.5 s (tick %d)" % [mode, pointed_tick])


func test_speed_eases_from_500_to_hijack_speed_over_half_a_second_then_holds(
		mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, -600)  # dead ahead, out of reach: no turn
	var r := _hand_rocket(h.root, Vector2(640, 1000), Vector2.UP)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(0, 0))))
	var speeds: Array[float] = []
	var prev := r.global_position
	for t in 60:
		_tick(r)
		speeds.append(prev.distance_to(r.global_position) / DT)
		prev = r.global_position
	assert_almost_eq(speeds[0], r.speed + (r.hijack_speed - r.speed) * (1.0 / 30.0), 1e-2,
			"%s: tick 1 already easing from 500" % mode)
	# Positions are single-precision, so a speed read back from one tick's displacement is good to ~1e-2 px/s.
	for t in range(1, 30):
		assert_lte(speeds[t], speeds[t - 1] + 1e-2, "%s: monotone ease (tick %d)" % [mode, t + 1])
	for t in range(29, 60):
		assert_almost_eq(speeds[t], r.hijack_speed, 1e-2, "%s: %.0f px/s from tick 30 (tick %d)" % [mode, r.hijack_speed, t + 1])


## Arming is two rules, each with its own falsifier (task-plan review R1). The time rule: claimed 70 px from a
## stationary target, nose on it, so the clearance latches on the claim and the rocket is inside the trigger radius
## from about tick 5 (a clearance-only build blasts there); with the time rule it is ~47 px past the target by tick 15,
## so nothing happens on ticks 1..15.
func test_arming_waits_out_the_delay_even_when_already_clear(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var target := _static_target(h.root, START)
	var r := _hand_rocket(h.root, START + Vector2(0, -70), Vector2.DOWN)
	assert_true(r.retarget(target, -1.0, _claimer(h.root, START + Vector2(0, -600))))
	var inside_early := false
	for t in range(1, 16):
		_tick(r)
		assert_true(_alive(r), "%s: no blast on tick %d" % [mode, t])
		if not _alive(r):
			break
		if t < 15 and r.global_position.distance_to(target.global_position) <= r.hijack_trigger_radius:
			inside_early = true
	assert_true(inside_early, "%s: falsifier: it was inside the trigger radius before 0.25 s" % mode)
	if _alive(r):
		assert_gt(r.global_position.distance_to(target.global_position), r.hijack_trigger_radius,
				"%s: past the target by tick 15" % mode)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


## The clearance rule: claimed 20 px out, the player chasing its own just-claimed rocket (moved each tick to 20 px
## behind it, so the rocket is ~27 px from it after every move). Past 0.25 s a time-only build blasts on tick 15; with
## the clearance rule nothing happens through tick 30.
func test_arming_needs_the_rocket_to_have_been_clear(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var player: Node2D = h.player
	player.global_position = START
	var r := _hand_rocket(h.root, START + Vector2(0, -20), Vector2.UP)
	assert_true(r.retarget(player, -1.0, _claimer(h.root, START + Vector2(0, -600))))
	var inside_armed := false
	for t in range(1, 31):
		_tick(r)
		assert_true(_alive(r), "%s: no blast on tick %d" % [mode, t])
		if not _alive(r):
			break
		if t >= 15 and r.global_position.distance_to(player.global_position) <= r.hijack_trigger_radius:
			inside_armed = true
		player.global_position = r.global_position - _heading(r) * 20.0
	assert_true(inside_armed, "%s: falsifier: inside the trigger radius after 0.25 s" % mode)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


## Claimed on the ship itself: nothing in its first 0.25 s.
func test_a_rocket_claimed_on_the_ship_never_blasts_in_its_first_quarter_second(
		mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = START
	var r := _hand_rocket(h.root, START, Vector2.UP)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, START + Vector2(0, -600))))
	for t in range(1, 16):
		_tick(r)
		assert_true(_alive(r), "%s: claimed on the ship, still flying at tick %d" % [mode, t])
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


func test_an_unblasted_hijack_fizzles_at_the_end_of_its_window(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, 1460)  # 1100 px behind: out of reach in 2.5 s
	var r := _hand_rocket(h.root, START, Vector2.UP)
	var log := _log(r)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(640, 0))))
	assert_true(r.is_retargeted())
	var ticks := 0
	while _alive(r) and ticks < 300:
		_tick(r)
		ticks += 1
	assert_almost_eq(float(ticks), r.hijack_seconds / DT, 1.0, "%s: fizzled at 2.5 s (tick %d)" % [mode, ticks])
	assert_eq(log["ended"], 1, "%s: retarget_ended once" % mode)
	assert_eq(log["expired"], 1, "%s: expired once" % mode)
	assert_false(r.is_retargeted(), "%s: no longer retargeted once done" % mode)
	for i in 5:
		_tick(r)
	assert_eq(log["ended"], 1, "%s: still once" % mode)
	assert_eq(log["expired"], 1)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: a fizzle never blasts" % mode)


## `retarget()`'s window: a claimer's `seconds >= 0` is the window (1.0 s -> tick 60; 0.0 -> its first tick), a negative
## one uses the rocket's own `hijack_seconds`, and a claim with no source lasts its whole window (review R3, M3).
func test_the_window_comes_from_the_claimer_or_the_rocket(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, 1460)  # 1100 px behind: out of reach
	for row: Array in [[1.0, true, 60], [0.0, true, 1], [-1.0, false, 150]]:
		var r := _hand_rocket(h.root, START, Vector2.UP)
		var log := _log(r)
		var src: Node = _claimer(h.root, Vector2(640, 0)) if row[1] else null
		assert_true(r.retarget(h.player, row[0], src))
		var ticks := 0
		while _alive(r) and ticks < 300:
			_tick(r)
			ticks += 1
		var label := "%s: seconds %.1f, source %s" % [mode, row[0], row[1]]
		if row[2] == 1:
			assert_eq(ticks, 1, "%s: fizzles on its first tick" % label)
		else:
			assert_almost_eq(float(ticks), float(row[2]), 1.0, "%s: fizzles on tick %d (got %d)" % [label, row[2], ticks])
		assert_eq(log["ended"], 1, "%s: retarget_ended once" % label)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


## The target freed mid-hijack (it is the player, which can go): no error, straight flight from the next tick, the
## fizzle at the end of the window, no blast (review M2).
func test_a_freed_target_leaves_the_rocket_flying_straight_to_a_fizzle(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var target := _static_target(h.root, START + Vector2(400, 300))
	var r := _hand_rocket(h.root, START + Vector2(0, 640), Vector2.UP)
	var log := _log(r)
	assert_true(r.retarget(target, -1.0, _claimer(h.root, START)))
	for i in 20:
		_tick(r)
	target.free()
	var ticks := 20
	var h0 := Vector2.ZERO
	while _alive(r) and ticks < 300:
		_tick(r)
		ticks += 1
		if not _alive(r):
			break
		if ticks == 21:
			h0 = _heading(r)
		else:
			assert_lt(absf(h0.angle_to(_heading(r))), 1e-6, "%s: straight from tick 21 (tick %d)" % [mode, ticks])
	assert_almost_eq(float(ticks), r.hijack_seconds / DT, 1.0, "%s: fizzled at the end of the window (tick %d)" % [mode, ticks])
	assert_eq(log["ended"], 1, "%s: retarget_ended once" % mode)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


func test_freeing_the_source_fizzles_the_rocket_on_the_next_tick(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, 1460)
	var r := _hand_rocket(h.root, START, Vector2.UP)
	var log := _log(r)
	var c := _claimer(h.root, Vector2(640, 0))
	assert_true(r.retarget(h.player, -1.0, c))
	for i in 10:
		_tick(r)
	assert_true(_alive(r), "%s: precondition: still flying" % mode)
	c.free()
	_tick(r)
	assert_false(_alive(r), "%s: fizzled on the next tick" % mode)
	assert_eq(log["ended"], 1, "%s: retarget_ended once" % mode)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


func test_a_lifetime_expiry_ends_a_live_hijack(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var target := _static_target(h.root, START + Vector2(0, -300))
	h.player.global_position = target.global_position + Vector2(0, 750)
	var r := _hand_rocket(h.root, START, Vector2.UP, target)
	var log := _log(r)
	for i in 300:
		_tick(r)
	assert_true(_alive(r), "%s: precondition: hovering at 5.0 s" % mode)
	assert_gte(r.global_position.distance_to(h.player.global_position), 700.0, "%s: the player is >= 700 px away" % mode)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, target.global_position + Vector2(0, -200))))
	var ticks := 300
	while _alive(r) and ticks < 600:
		_tick(r)
		ticks += 1
		if h.is_assault:
			assert_true(EnemyWorld.projectile_world_rect(get_tree()).has_point(r.global_position),
					"%s: inside the projectile rect (tick %d)" % [mode, ticks])
	assert_almost_eq(float(ticks), 6.0 / DT, 1.5, "%s: max_time ends the hijack at 6.0 s (tick %d)" % [mode, ticks])
	assert_eq(log["ended"], 1, "%s: retarget_ended once" % mode)
	assert_eq(log["expired"], 1, "%s: expired once" % mode)
	assert_true(r.is_queued_for_deletion(), "%s: freed" % mode)
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)

	# Control: an unhijacked hover to 6.0 s ends with no retarget_ended.
	var r2 := _hand_rocket(h.root, START, Vector2.UP, target)
	var log2 := _log(r2)
	var t2 := 0
	while _alive(r2) and t2 < 600:
		_tick(r2)
		t2 += 1
	assert_almost_eq(float(t2), 6.0 / DT, 1.5, "%s: control expired at 6.0 s" % mode)
	assert_eq(log2["expired"], 1)
	assert_eq(log2["ended"], 0, "%s: control: no retarget_ended" % mode)


func test_the_tether_shows_for_tether_seconds_then_hides(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = Vector2(640, 1460)
	var r := _hand_rocket(h.root, START, Vector2.UP)
	assert_false(r.is_tether_visible(), "%s: no tether before a claim" % mode)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(640, 0))))
	assert_true(r.is_tether_visible(), "%s: shown on the claim" % mode)
	var expected_ticks := roundi(r.tether_seconds / DT)
	for t in range(1, expected_ticks + 3):
		_tick(r)
		assert_eq(r.is_tether_visible(), t < expected_ticks,
				"%s: tether visible on tick %d is %s" % [mode, t, t < expected_ticks])

	# Freeing the claimer mid-tether hides it at once; the rocket fizzles on the next tick, with no error.
	var r2 := _hand_rocket(h.root, START + Vector2(200, 0), Vector2.UP)
	var c := _claimer(h.root, Vector2(840, 0))
	assert_true(r2.retarget(h.player, -1.0, c))
	for i in 5:
		_tick(r2)
	assert_true(r2.is_tether_visible(), "%s: precondition: tether still up at tick 5" % mode)
	c.free()
	assert_false(r2.is_tether_visible(), "%s: hidden once the source is gone" % mode)
	_tick(r2)
	assert_false(_alive(r2), "%s: and the rocket fizzled" % mode)
	await get_tree().process_frame


func test_seekers_fly_straight_inside_a_lit_jammer(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = START + Vector2(400, 300)  # off the rockets' axes: steering would turn them
	var target := _static_target(h.root, START + Vector2(-400, -300))
	var c := _claimer(h.root, START + Vector2(0, -100))

	# Control first, with no field anywhere: both steer.
	var hijacked2 := _hand_rocket(h.root, START, Vector2.UP)
	assert_true(hijacked2.retarget(h.player, -1.0, c))
	var seeker2 := _hand_rocket(h.root, START + Vector2(60, 0), Vector2.UP, target)
	var h1 := _heading(hijacked2)
	var s1 := _heading(seeker2)
	for i in 30:
		_tick(hijacked2)
		_tick(seeker2)
	assert_gt(absf(h1.angle_to(_heading(hijacked2))), 0.1, "%s: control: the hijacked rocket turns outside" % mode)
	assert_gt(absf(s1.angle_to(_heading(seeker2))), 0.1, "%s: control: the seeker turns outside" % mode)
	hijacked2.free()
	seeker2.free()

	# The same pair, claimed before the field lights (a claim inside one is refused), then 30 ticks inside it.
	var hijacked := _hand_rocket(h.root, START, Vector2.UP)
	assert_true(hijacked.retarget(h.player, -1.0, c))
	var seeker := _hand_rocket(h.root, START + Vector2(60, 0), Vector2.UP, target)
	_jammer(h.root, START, 400.0)
	var h0 := _heading(hijacked)
	var s0 := _heading(seeker)
	for i in 30:
		_tick(hijacked)
		_tick(seeker)
		assert_true(Hazards.jammer_at(hijacked.global_position) != null, "%s: precondition: inside (tick %d)" % [mode, i + 1])
	assert_lt(absf(h0.angle_to(_heading(hijacked))), 1e-6, "%s: a hijacked rocket flies straight inside a lit field" % mode)
	assert_lt(absf(s0.angle_to(_heading(seeker))), 1e-6, "%s: so does a rocket with a locked target" % mode)
	assert_true(hijacked.is_retargeted(), "%s: still hijacked" % mode)
	assert_eq(seeker.locked_target, target, "%s: the seeker keeps its lock (it is jammed, not cleared)" % mode)


func test_jam_guidance_drops_the_lock_and_straightens_a_hijack(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	h.player.global_position = START + Vector2(400, 300)
	var target := _static_target(h.root, START + Vector2(-400, -300))
	var seeker := _hand_rocket(h.root, START, Vector2.UP, target)
	seeker.jam_guidance(null)
	assert_null(seeker.locked_target, "%s: the lock is dropped" % mode)
	var s0 := _heading(seeker)
	for i in 30:
		_tick(seeker)
	assert_lt(absf(s0.angle_to(_heading(seeker))), 1e-6, "%s: it flies forward" % mode)

	# A hijacked rocket jammed on tick 10 keeps its hijack but flies straight to the end of its window; a control
	# claimed beside it, never jammed, keeps turning (it is freed after 30 more ticks, before it could reach the player).
	var c := _claimer(h.root, START + Vector2(0, -400))
	var r := _hand_rocket(h.root, START + Vector2(0, 640), Vector2.UP)  # 2.5 s of straight flight stays in the rect
	var ctl := _hand_rocket(h.root, START + Vector2(60, 640), Vector2.UP)
	var log := _log(r)
	assert_true(r.retarget(h.player, -1.0, c))
	assert_true(ctl.retarget(h.player, -1.0, c))
	for i in 10:
		_tick(r)
		_tick(ctl)
	r.jam_guidance(c)
	assert_true(r.is_retargeted(), "%s: still hijacked after jam_guidance()" % mode)
	var h0 := _heading(r)
	var c0 := _heading(ctl)
	var ticks := 10
	while _alive(r) and ticks < 300:
		_tick(r)
		ticks += 1
		if ticks <= 40:
			_tick(ctl)
		if _alive(r):
			assert_true(r.is_retargeted(), "%s: hijacked until its window ends (tick %d)" % [mode, ticks])
			assert_lt(absf(h0.angle_to(_heading(r))), 1e-6, "%s: flies straight (tick %d)" % [mode, ticks])
	assert_almost_eq(float(ticks), r.hijack_seconds / DT, 1.0, "%s: and still fizzles at the end of its window" % mode)
	assert_eq(log["ended"], 1, "%s: retarget_ended once" % mode)
	assert_gt(absf(c0.angle_to(_heading(ctl))), 0.1, "%s: control: an unjammed hijack keeps turning" % mode)
	ctl.free()
	await get_tree().process_frame
	assert_eq(_blasts.size(), 0, "%s: no blast" % mode)


## Open Space: a ship cruising at 420 px/s across a rocket claimed 400 px away nose-on, turning 90 degrees at 0.6 s
## (either way), is never blasted. Assault: the fighter strafing at 360 px/s under a rocket claimed 500 px above it,
## nose-on, reversing at 0.6 s, is never blasted. Control (both): a stationary ship is. The geometry was fixed by a
## pre-run of the flight model (closest approach 64 / 219 px and 90 px against the 30 px trigger).
func test_a_fair_dodge_escapes_and_a_stationary_ship_is_blasted(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var player: CharacterBody2D = h.player
	var runs: Array = []
	if mode == "open_space":
		for turn_to in [Vector2.DOWN, Vector2.UP]:
			runs.append({"name": "turn %s" % turn_to, "rocket": Vector2(640, 0), "player": Vector2(640, 400),
					"vel": func(t: float) -> Vector2: return Vector2(420, 0) if t < 0.6 else turn_to * 420.0})
	else:
		runs.append({"name": "strafe and reverse", "rocket": Vector2(640, 100), "player": Vector2(640, 600),
				"vel": func(t: float) -> Vector2: return Vector2(360, 0) if t < 0.6 else Vector2(-360, 0)})
	var still_at: Vector2 = runs[0]["player"]
	runs.append({"name": "stationary", "rocket": runs[0]["rocket"], "player": still_at,
			"vel": func(_t: float) -> Vector2: return Vector2.ZERO})
	for run in runs:
		_blasts.clear()
		player.global_position = run["player"]
		var r := _hand_rocket(h.root, run["rocket"], Vector2.DOWN)
		var trigger := r.hijack_trigger_radius
		assert_true(r.retarget(player, -1.0, _claimer(h.root, (run["rocket"] as Vector2) + Vector2(0, -300))))
		var closest := INF
		var t := 0.0
		var ticks := 0
		while _alive(r) and ticks < 300:
			_tick(r)
			ticks += 1
			t += DT
			if _alive(r):
				closest = minf(closest, r.global_position.distance_to(player.global_position))
			player.global_position += (run["vel"] as Callable).call(t) * DT
		await get_tree().process_frame
		if run["name"] == "stationary":
			assert_eq(_blasts.size(), 1, "%s %s: control: a stationary ship is blasted" % [mode, run["name"]])
			assert_lt(ticks, 150, "%s: control: before the window ends" % mode)
		else:
			assert_eq(_blasts.size(), 0, "%s %s: never blasted (closest %.1f px)" % [mode, run["name"], closest])
			assert_gt(closest, trigger, "%s %s: closest %.1f px" % [mode, run["name"], closest])


func test_the_eventbus_hears_each_successful_claim_once(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var got: Array = []
	var on_bus := func(rocket: Node2D, source: Node) -> void: got.append([rocket, source])
	EventBus.player_ordnance_hijacked.connect(on_bus)
	var a := _hand_rocket(h.root, START, Vector2.UP)
	var b := _hand_rocket(h.root, START + Vector2(30, 0), Vector2.UP)
	var c := _claimer(h.root, Vector2(640, 0))
	assert_true(a.retarget(h.player, -1.0, c))
	assert_false(a.retarget(h.player, -1.0, c), "a refused re-claim")
	assert_false(b.retarget(null, -1.0, c), "a refused null target")
	assert_true(b.retarget(h.player, -1.0, null), "a claim with no source")
	EventBus.player_ordnance_hijacked.disconnect(on_bus)
	assert_eq(got, [[a, c], [b, null]], "%s: once per successful claim, with the rocket and the source" % mode)


func test_the_tell_is_amber_and_the_hurtbox_opens_only_while_hijacked(mode: String = use_parameters(MODES)) -> void:
	var h := _harness(mode)
	var r := _hand_rocket(h.root, START, Vector2.UP)
	var sprite := r.get_node("AnimatedSprite2D") as AnimatedSprite2D
	var hurt := r.get_node("HurtBox") as HurtBox
	await get_tree().process_frame
	assert_eq(sprite.self_modulate, Color.WHITE, "%s: white before" % mode)
	assert_false(hurt.monitoring or hurt.monitorable, "%s: HurtBox closed before" % mode)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(640, 0))))
	await get_tree().process_frame
	assert_eq(sprite.self_modulate, AMBER, "%s: amber while hijacked" % mode)
	assert_true(hurt.monitoring and hurt.monitorable, "%s: HurtBox open while hijacked" % mode)
	var trail: RocketTrail = null
	for child in r.get_children():
		if child is RocketTrail:
			trail = child
	assert_not_null(trail, "%s: the rocket keeps its trail" % mode)
	if trail != null:
		assert_eq(trail.birth_color(), AMBER, "%s: the trail turns amber" % mode)


# --- Real physics ------------------------------------------------------------------------------------------------------


func test_the_real_player_takes_only_the_blast(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h := _harness(mode)
	var p := _real_player(h, mode)
	var hurt := p.get_node("HurtBox") as HurtBox
	var received: Array[int] = []
	hurt.received_damage.connect(func(damage: int) -> void: received.append(damage))
	var hp0 := p.health_component.current_health
	var c := _claimer(h.root, START + Vector2(0, -500))
	await _frames(2)

	var r := _live_rocket(h.root, START + Vector2(0, -300), Vector2.DOWN)
	var blast := r.hijack_blast_damage
	assert_true(r.retarget(p, -1.0, c))
	await _seconds(1.0)
	assert_false(is_instance_valid(r), "%s: the rocket ended on the player" % mode)
	assert_eq(_blasts.size(), 1, "%s: one ContactBlast" % mode)
	assert_eq(received, [blast] as Array[int], "%s: exactly hijack_blast_damage once, never 100" % mode)
	assert_eq(p.health_component.current_health, hp0 - blast, "%s: HP drops by 18" % mode)

	# With one shield charge the charge is spent instead.
	p.shield_component.add_temporary()
	var hp1 := p.health_component.current_health
	var r2 := _live_rocket(h.root, START + Vector2(0, -300), Vector2.DOWN)
	assert_true(r2.retarget(p, -1.0, c))
	await _seconds(1.0)
	assert_eq(_blasts.size(), 2, "%s: the second rocket blasted" % mode)
	assert_eq(received, [blast, blast] as Array[int], "%s: the shielded hit is the blast alone" % mode)
	assert_eq(p.shield_component.temporary_count, 0, "%s: one charge spent" % mode)
	assert_eq(p.health_component.current_health, hp1, "%s: the charge absorbed it" % mode)


func test_a_lured_rocket_hits_an_enemy_for_full_damage_and_ends() -> void:
	_scale_clock()
	var h := _harness("open_space")
	h.player.global_position = Vector2(640, 800)
	var e: BaseEnemy = FIXTURE_ENEMY.instantiate()
	var health := e.get_node("Health") as Health
	health.max_health = FIXTURE_HP
	health.current_health = FIXTURE_HP
	e.get_node("HurtBox").add_child(_circle(14.0))
	e.add_to_group(&"enemies")
	h.root.add_child(e)
	e.global_position = Vector2(640, 400)
	var r := _live_rocket(h.root, Vector2(640, 100), Vector2.DOWN)
	var log := _log(r)
	assert_true(r.retarget(h.player, -1.0, _claimer(h.root, Vector2(640, 0))))
	await _seconds(1.0)
	assert_eq(health.current_health, FIXTURE_HP - 100, "the enemy took the rocket's full 100")
	assert_false(is_instance_valid(r), "the rocket ended on the enemy")
	assert_eq(log["ended"], 1, "retarget_ended once")
	assert_eq(_blasts.size(), 0, "no ContactBlast: the player takes nothing")


func test_one_bullet_shoots_a_hijacked_rocket_down_and_passes_an_unhijacked_one() -> void:
	_scale_clock()
	var h := _harness("open_space")
	h.player.global_position = Vector2(2000, 2000)
	var far := _static_target(h.root, Vector2(1600, 300))
	var r := _live_rocket(h.root, Vector2(300, 300), Vector2.RIGHT)
	var log := _log(r)
	assert_true(r.retarget(far, -1.0, _claimer(h.root, Vector2(200, 300))))
	var bullet: Bullet = BULLET_SCENE.instantiate()
	h.root.add_child(bullet)
	bullet.global_position = Vector2(700, 300)
	bullet.rotation = -PI / 2.0  # forward = LEFT
	bullet.expired.connect(bullet.queue_free)

	# The same line through an unhijacked rocket: nothing.
	var r2 := _live_rocket(h.root, Vector2(300, 600), Vector2.RIGHT)
	var bullet2: Bullet = BULLET_SCENE.instantiate()
	h.root.add_child(bullet2)
	bullet2.global_position = Vector2(700, 600)
	bullet2.rotation = -PI / 2.0
	bullet2.expired.connect(bullet2.queue_free)

	await _seconds(0.5)
	assert_false(is_instance_valid(r), "the hijacked rocket was shot down")
	assert_eq(log["ended"], 1, "retarget_ended once")
	assert_false(is_instance_valid(bullet), "the bullet was consumed")
	assert_eq(_blasts.size(), 0, "a shoot-down never blasts")
	assert_true(_alive(r2), "control: the unhijacked rocket flew on")
	assert_true(_alive(bullet2), "control: and so did the bullet")
	if _alive(r2) and _alive(bullet2):
		assert_gt(r2.global_position.x, bullet2.global_position.x, "control: they crossed")


func test_a_claimed_rocket_never_hits_itself_or_its_salvo(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h := _harness(mode)
	var p := _real_player(h, mode)
	await _frames(2)
	var salvo := _salvo(p, 1)
	assert_eq(salvo.size(), 3, "%s: a real 3-rocket homing salvo" % mode)
	var claimed := salvo[1] as homing_missile
	assert_true(claimed.retarget(p, -1.0, _claimer(h.root, START + Vector2(0, -500))))
	var hurt := claimed.get_node("HurtBox") as HurtBox
	var waited := 0
	for mark in [2, 10, 30]:
		await _frames(mark - waited)
		waited = mark
		for i in salvo.size():
			assert_true(_alive(salvo[i]), "%s: rocket %d alive %d ticks after the claim" % [mode, i, mark])
		if _alive(claimed):
			assert_true(hurt.monitorable, "%s: the claimed HurtBox is monitorable at tick %d" % [mode, mark])
	# Godot 4.6 forms no pair for two areas that already overlap when one of them turns monitorable (measured: with the
	# guard removed, nothing above fires, even after 140 ticks), so the rows above cannot fail on their own. The guard is
	# pinned by handing each salvo rocket's HitBox callback the claimed HurtBox directly: its own, and its mates'.
	for i in salvo.size():
		if _alive(salvo[i]):
			(salvo[i] as homing_missile)._on_hit_box_area_entered(hurt)
	for i in salvo.size():
		assert_true(_alive(salvo[i]), "%s: rocket %d ignores the claimed HurtBox (the self-hit guard)" % [mode, i])
	# And a warhead's HitBox ignores it too (the warhead guard), the same way.
	var warheads := _salvo(p, 0)
	for w in warheads:
		(w as WarheadMissile)._on_hit_box_area_entered(hurt)
		assert_true(_alive(w), "%s: a warhead ignores the claimed HurtBox" % mode)


func test_player_rockets_cross_a_hijacked_rocket_unharmed(mode: String = use_parameters(MODES)) -> void:
	_scale_clock()
	var h := _harness(mode)
	var at := Vector2(640, 600)  # low, so the warheads stay on screen until the last check
	var p := _real_player(h, mode, at)
	await _frames(2)
	var hijacked := _live_rocket(h.root, at + Vector2(0, -420), Vector2.DOWN)
	assert_true(hijacked.retarget(p, -1.0, _claimer(h.root, at + Vector2(0, -600))))
	var mates: Array[Node2D] = []
	mates.append_array(_salvo(p, 1))
	mates.append_array(_salvo(p, 0))
	assert_eq(mates.size(), 6, "%s: a homing and a warhead salvo" % mode)
	var crossed_at := -1
	for f in 60:
		await _frames(1)
		if not _alive(hijacked):
			break
		var bottom := -INF
		for m in mates:
			if _alive(m):
				bottom = maxf(bottom, m.global_position.y)
		if hijacked.global_position.y > bottom:
			crossed_at = f + 1
			break
	assert_gt(crossed_at, 0, "%s: the hijacked rocket flew through both salvos" % mode)
	await _frames(10)
	assert_true(_alive(hijacked), "%s: the hijacked rocket is alive 10 ticks after the crossing" % mode)
	if _alive(hijacked):
		assert_true((hijacked.get_node("HurtBox") as HurtBox).monitorable, "%s: its HurtBox stayed open" % mode)
	for i in mates.size():
		assert_true(_alive(mates[i]), "%s: salvo rocket %d alive after the crossing" % [mode, i])


# --- Primary fire --------------------------------------------------------------------------------------------------------


## Two real ships in lockstep, idle context (the `test_player_ability_lock.gd` shape): ship B has a hijacked rocket in
## flight, claimed on B, hand-ticked with the ships; A has none. Their primary-fire logs must be identical.
func test_primary_fire_is_identical_during_a_hijack(mode: String = use_parameters(MODES)) -> void:
	await get_tree().process_frame
	for id: StringName in UpgradeState.ALL_IDS:
		var boxes: Array[Node2D] = []
		var ships: Array[PlayerBase] = []
		for i in 2:
			var box := Node2D.new()
			add_child_autofree(box)
			var p := (SHIP_SCENE if mode == "open_space" else FIGHTER_SCENE).instantiate() as PlayerBase
			box.add_child(p)
			p.set_physics_process(false)
			p.global_position = START + Vector2(1200.0 * i, 0)
			p.rotation = 0.0
			p.velocity = Vector2.ZERO
			boxes.append(box)
			ships.append(p)
		var b := ships[1]
		var r := _hand_rocket(boxes[1], b.global_position + Vector2(0, 900), Vector2.DOWN)
		assert_true(r.retarget(b, -1.0, _claimer(boxes[1], b.global_position + Vector2(0, 1100))))
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
			var dummy := Node2D.new()
			var hb := HurtBox.new()
			hb.name = "HurtBox"
			hb.received_damage.connect(func(d: int) -> void: rec.append(["hit", clock[0], d]))
			dummy.add_child(hb)
			dummy.add_to_group(&"enemies")
			boxes[i].add_child(dummy)
			dummy.global_position = ws.weapon_muzzles[0].global_position + Vector2(0, -300)
		var in_flight := true
		for t in 120:
			clock[0] = t
			if t == 0:
				Input.action_press("shoot")
			elif t == 60:
				Input.action_release("shoot")
			if _alive(r):
				r._physics_process(DT)
			in_flight = in_flight and _alive(r) and r.is_retargeted()
			for i in 2:
				seed(t)
				(states[i] as WeaponState)._physics_process(DT)
		Input.action_release("shoot")
		assert_true(in_flight, "%s %s: the hijacked rocket was in flight for all 120 ticks" % [mode, id])
		assert_gt((logs[0] as Array).size(), 0, "%s %s: non-vacuous: the weapon fired or hit" % [mode, id])
		assert_eq(logs[1], logs[0], "%s %s: shots, cadence and damage are identical during a hijack" % [mode, id])
		for box in boxes:
			box.get_parent().remove_child(box)
			box.free()
