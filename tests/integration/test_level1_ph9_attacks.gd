## Phase 9 t14: both Phase 9 spawns level 1 places do their job inside their Assault life (epic plan
## docs/plans/cmug23onr001pm52w9swwophy/3-plan.md §2.17; task plan docs/plans/cmw5k4ykj00b6qs2xt4pm0wjg/3-plan.md).
##
## Each placed line replays only a slice of planet_approach through a real `WaveManager`, among the real traffic of its moment
## (`tests/helpers/level1_slice_replay.gd`, the `test_level1_ph8_attacks.gd` shape; no director, so no laser columns), at the 16x
## clock, and stops as soon as its claim is decided:
##   Hacker   the 42.0 s Hacker, against a player stub that launches one live homing rocket every 0.4 game s, locked on the nearest
##            live non-Hacker enemy whose bearing from the stub is more than 30 degrees off the Hacker's (none: unlocked, on a fixed
##            heading 60 degrees off the Hacker's bearing), so the designed counter (a hit in TELEGRAPH cancels the pulse) is not what
##            the replay measures. It reaches PULSE exactly once, with budget left, with rockets in flight; the row stops when that
##            PULSE ends.
##   jammer   the 62.0 s local jammer drifting at world x 480: a real `player_fighter.tscn` parked at the stub's position (physics and
##            process off, out of group `player`, no collision, so traffic neither targets nor hurts it) is locked by its field, and a
##            second one at the same y and x 1240 (outside the r 240 field for the jammer's whole life) never is. Both are stepped
##            through `_step_disruption()` on every physics tick. The row stops on the near ship's lock.
## Boundary: the same Hacker with a 1.0 s private budget (< `first_pulse_delay` 2.0) never telegraphs and disengages.
extends GutTest

const Slice := preload("res://tests/helpers/level1_slice_replay.gd")
const HACKER_CONFIG: HackerFrigateConfig = preload("res://assault/scenes/enemies/hacker_frigate/hacker_frigate_config.tres")
const JAMMER_CONFIG: JammingStructureConfig = preload("res://assault/scenes/enemies/jamming_structure/jamming_structure_config.tres")
const HOMING_SCENE: PackedScene = preload("res://assault/scenes/projectiles/missiles/homing/homing_missile.tscn")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/player/player_fighter.tscn")
const _SPEEDUP := 16
## A rocket every this many game seconds from the stub.
const ROCKET_PERIOD := 0.4
## A rocket's target must sit more than this far off the Hacker's bearing from the stub; the unlocked fallback flies this far off.
const OFF_BEARING := deg_to_rad(30.0)
const FALLBACK_OFF := deg_to_rad(60.0)
## The control fighter's world x: outside the jammer's field (x 480 +- 240) for its whole life.
const FAR_X := 1240.0

var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()


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


func _only_row(scene_path: String, label: String) -> Dictionary:
	var rows := Slice.placed(scene_path)
	assert_eq(rows.size(), 1, "sanity: level 1 places one %s line" % label)
	return rows[0] if rows.size() == 1 else {}


func _stub() -> Node2D:
	return get_tree().get_first_node_in_group(&"player") as Node2D


# ── Hacker ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## The nearest live non-Hacker enemy more than `OFF_BEARING` off the Hacker's bearing from `from`, or null.
func _rocket_target(hacker: Node2D, from: Vector2) -> Node2D:
	var hacker_bearing := (hacker.global_position - from).angle()
	var best: Node2D = null
	var best_d := INF
	for node in get_tree().get_nodes_in_group(&"enemies"):
		var e := node as BaseEnemy
		if e == null or e == hacker or not e.is_inside_tree() or e is HackerFrigate:
			continue
		if absf(angle_difference(hacker_bearing, (e.global_position - from).angle())) <= OFF_BEARING:
			continue
		var d := from.distance_to(e.global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


## One live homing rocket from the stub, in its parent (freed with the world), its `retargeted` counted into `seen`.
func _launch_rocket(stub: Node2D, hacker: Node2D, seen: Dictionary) -> void:
	var r: homing_missile = HOMING_SCENE.instantiate()
	var target := _rocket_target(hacker, stub.global_position)
	var dir: Vector2
	if target != null:
		r.locked_target = target
		dir = (target.global_position - stub.global_position).normalized()
	else:
		var to_hacker := (hacker.global_position - stub.global_position).normalized()
		var side := signf(to_hacker.angle_to(Vector2.UP))
		dir = to_hacker.rotated((side if side != 0.0 else 1.0) * FALLBACK_OFF)
	stub.get_parent().add_child(r)
	r.global_position = stub.global_position
	r.rotation = dir.angle() + PI / 2.0
	seen["rockets"] = int(seen["rockets"]) + 1
	r.retargeted.connect(func(_source: Node) -> void: seen["claims"] = int(seen["claims"]) + 1)


## Replays the 42.0 s Hacker's slice; `{ "targets", "stopped", "telegraphs", "pulses", "pulse_left", "in_flight", "claims",
## "rockets", "pulse_ended", "disengaged" }`. Stops when its first PULSE has ended, it has disengaged without one (the boundary) or
## it has left.
func _hacker_slice(row: Dictionary, tweak: Callable = Callable()) -> Dictionary:
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	var to: float = float(row["rel"]) + HACKER_CONFIG.engage_seconds + Slice.POST_ROLL
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, to)
	var seen := {"telegraphs": 0, "pulses": 0, "pulse_left": [], "in_flight": [], "claims": 0, "rockets": 0,
		"pulse_ended": false, "disengaged": false}
	var hook := func(ship: Node) -> void:
		if tweak.is_valid():
			tweak.call(ship)
		var brain := ship.get_node("Brain") as HackerFrigateBrain
		var last := [-1]
		brain.phase_changed.connect(func(p: int) -> void:
			if p == HackerFrigateBrain.Phase.TELEGRAPH:
				seen["telegraphs"] = int(seen["telegraphs"]) + 1
			elif p == HackerFrigateBrain.Phase.PULSE:
				seen["pulses"] = int(seen["pulses"]) + 1
				(seen["pulse_left"] as Array).append(brain.budget.remaining() if brain.budget != null else -1.0)
				var flying := get_tree().get_nodes_in_group(SeekingOrdnance.GROUP).filter(func(n: Node) -> bool:
					return n.has_method("can_be_retargeted") and n.can_be_retargeted())
				(seen["in_flight"] as Array).append(flying.size())
			elif p == HackerFrigateBrain.Phase.DISENGAGE:
				seen["disengaged"] = true
			if last[0] == HackerFrigateBrain.Phase.PULSE and p != HackerFrigateBrain.Phase.PULSE:
				seen["pulse_ended"] = true
			last[0] = p)
	var next_rocket := [0.0]
	var observe := func(ship: BaseEnemy, t: float) -> bool:
		if ship == null or bool(seen["pulse_ended"]):
			return true
		if bool(seen["disengaged"]) and int(seen["pulses"]) == 0:
			return true
		var stub := _stub()
		if stub != null and t >= next_rocket[0]:
			next_rocket[0] = t + ROCKET_PERIOD
			_launch_rocket(stub, ship, seen)
		return false
	var out: Dictionary = await Slice.new().run(self, waves, to - from, WaveBuilder.HACKER_FRIGATE, observe, hook)
	seen["targets"] = out["targets"]
	seen["stopped"] = out["stopped"]
	return seen


func test_the_level1_hacker_reaches_pulse_inside_its_budget() -> void:
	var row := _only_row(WaveBuilder.HACKER_FRIGATE, "Hacker Frigate")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _hacker_slice(row)
	gut.p("planet_approach Hacker at %.1f s: %d rockets launched, telegraphs %d, pulses %d, budget left at PULSE %s, rockets in flight at PULSE %s, claims %d"
		% [row["rel"], seen["rockets"], seen["telegraphs"], seen["pulses"], seen["pulse_left"], seen["in_flight"], seen["claims"]])
	assert_eq(int(seen["targets"]), 1, "one Hacker in its slice")
	assert_eq(int(seen["pulses"]), 1, "reaches PULSE exactly once")
	for left: float in seen["pulse_left"]:
		assert_gt(left, 0.0, "PULSE starts with budget left")
	for flying: int in seen["in_flight"]:
		assert_gt(flying, 0, "homing rockets are in flight when PULSE starts")
	# 2 claims in each of 5 runs while building (t14), so asserted: the pulse takes at least one of the stub's rockets.
	assert_gte(int(seen["claims"]), 1, "the PULSE claims at least one of the player's rockets")
	assert_true(bool(seen["pulse_ended"]), "the PULSE window ends")
	assert_true(bool(seen["stopped"]), "the slice ended on its claim, not its length")


## Boundary: the same Hacker with a 1.0 s private budget (< first_pulse_delay) disengages before it can telegraph.
func test_a_level1_hacker_with_a_1_s_budget_never_pulses() -> void:
	var row := _only_row(WaveBuilder.HACKER_FRIGATE, "Hacker Frigate")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _hacker_slice(row, func(ship: Node) -> void:
		(ship as HackerFrigate).config.engage_seconds = 1.0)
	gut.p("planet_approach Hacker, engage 1.0: telegraphs %d, pulses %d, disengaged %s" % [seen["telegraphs"], seen["pulses"],
		seen["disengaged"]])
	assert_eq(int(seen["targets"]), 1, "sanity: one Hacker")
	assert_true(bool(seen["disengaged"]), "sanity: its budget ran out inside the run")
	assert_eq(int(seen["telegraphs"]), 0, "no TELEGRAPH on a 1 s budget")
	assert_eq(int(seen["pulses"]), 0, "no PULSE on a 1 s budget")
	assert_eq(HACKER_CONFIG.engage_seconds, 9.0, "the shipped config is untouched")


# ── Jammer ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## A real fighter parked in `parent` at `at`: physics and process off, out of group `player`, no collision anywhere.
func _parked_fighter(parent: Node, at: Vector2) -> PlayerBase:
	var p := FIGHTER_SCENE.instantiate() as PlayerBase
	parent.add_child(p)
	p.set_physics_process(false)
	p.set_process(false)
	p.remove_from_group(&"player")
	p.collision_layer = 0
	p.collision_mask = 0
	p.global_position = at
	p.velocity = Vector2.ZERO
	for area in p.find_children("*", "Area2D", true, false):
		(area as Area2D).set_deferred("monitoring", false)
		(area as Area2D).set_deferred("monitorable", false)
	return p


func test_the_level1_jammer_locks_a_parked_player() -> void:
	var row := _only_row(WaveBuilder.JAMMER, "local jammer")
	if row.is_empty():
		return
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	# A cap, not the expected length (the jammer's worst drift life, `test_level1_specialist_spawns.gd`: world bottom 1164 minus its
	# highest spawn y -468, at the config's drift speed): the lock comes once the drifting field reaches the stub's row (~4.9 s in).
	var length: float = Slice.PRE_ROLL + (1164.0 + 468.0) / JAMMER_CONFIG.assault_drift_speed
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, from + length)
	var ships: Array = [null, null]  # near, far
	var seen := {"locked_at": -1.0, "far_locked": false, "field_is_the_jammers": false, "jammer_alive": false}
	var observe := func(jammer: BaseEnemy, t: float) -> bool:
		if ships[0] == null:
			var stub := _stub()
			if stub == null:
				return false
			ships[0] = _parked_fighter(stub.get_parent(), stub.global_position)
			ships[1] = _parked_fighter(stub.get_parent(), Vector2(FAR_X, stub.global_position.y))
		var near := ships[0] as PlayerBase
		var far := ships[1] as PlayerBase
		var dt := get_physics_process_delta_time()
		near._step_disruption(dt)
		far._step_disruption(dt)
		if far.abilities_locked():
			seen["far_locked"] = true
		if near.abilities_locked():
			seen["locked_at"] = t
			seen["jammer_alive"] = jammer != null
			var info := Hazards.jammer_at(near.global_position)
			seen["field_is_the_jammers"] = jammer != null and info != null \
				and info == (jammer as JammingStructure).field().hazard_info()
			return true
		return false
	_scale_clock()
	var out: Dictionary = await Slice.new().run(self, waves, length, WaveBuilder.JAMMER, observe)
	gut.p("planet_approach jammer at %.1f s: near ship locked at slice %.2f s (jammer spawned at %.1f), far ship locked %s"
		% [row["rel"], seen["locked_at"], Slice.PRE_ROLL, seen["far_locked"]])
	assert_eq(int(out["targets"]), 1, "one jammer in its slice")
	assert_gt(float(seen["locked_at"]), 0.0, "the parked ship is locked")
	assert_true(bool(seen["jammer_alive"]), "while the jammer lives")
	assert_true(bool(seen["field_is_the_jammers"]), "by the jammer's own field")
	assert_false(bool(seen["far_locked"]), "control: the ship outside the field never locks")
	assert_true(bool(out["stopped"]), "the slice ended on the lock, not its length")
