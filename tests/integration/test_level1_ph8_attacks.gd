## Phase 8 t19: every Phase 8 spawn level 1 places attacks inside its Assault budget (epic plan
## docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.18; task plan docs/plans/cmvqw0voi019bqs2x3j5zd2o8/3-plan.md §E).
##
## Each placed line replays only a slice of its own section through a real `WaveManager`, among the real traffic of its
## moment (`tests/helpers/level1_slice_replay.gd`; no director, so no laser columns), at the 16x clock (every row here
## is bound by the game clock), and stops as soon as its claim is decided:
##   turrets     deep_space's `assault_pair` group: each of its two turrets has a mount enter `TurretMount.Phase.FIRE`
##               while the turret's centre is inside `EnemyWorld.view_rect()` (read from the mount's `phase_changed`,
##               because a pulse ring enters and leaves FIRE in one tick). Member departure is analytic
##               (`test_level1_specialist_spawns.gd`), not replayed.
##   twin pair   deep_space's 29.0 s pair: each drone enters ADVANCE exactly once, its rig's TELEGRAPH starts with
##               budget left, the rig starts one advance, and both drones then DISENGAGE (one attack per life).
##   tender      planet_approach's 2.0 s tender: LAUNCH starts with budget left, it launches exactly once, and its
##               pair's rig reaches ADVANCE with the drone budget left at TELEGRAPH.
## Boundaries: the same pair with a 1.0 s private budget never advances; the same tender with a 0.5 s private budget
## never reaches LAUNCH and launches nothing. The private configs are each ship's own copy (`tweak` runs before `_ready()`).
extends GutTest

const Slice := preload("res://tests/helpers/level1_slice_replay.gd")
const TURRET_SCENE := "res://assault/scenes/enemies/defense_turret/defense_turret.tscn"
const DRONE_SCENE := "res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn"
const DRONE_CONFIG: TwinLaserDroneConfig = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")
const TENDER_CONFIG: LaserTenderConfig = preload("res://assault/scenes/enemies/laser_tender/laser_tender_config.tres")
const _SPEEDUP := 16
## The turret slice: long enough for the pulse-ring turret (it fires only with the player within its 300 px trigger range)
## to drift down to the stub at the view's lower centre; the row stops long before this once both have fired.
const TURRET_SLICE := 16.0

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


# ── Turrets ─────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_both_level1_turrets_fire_while_in_view() -> void:
	var row := _only_row(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR, "turret group")
	if row.is_empty():
		return
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, from + TURRET_SLICE)
	var turrets: Array[Node] = []
	var fired: Dictionary = {}  # turret instance id -> slice time of its first FIRE in view
	var clock := [0.0]
	var hook := func(ship: Node) -> void:
		turrets.append(ship)
		ship.ready.connect(func() -> void:
			for m: TurretMount in (ship as DefenseTurret).mounts():
				m.phase_changed.connect(func(p: int) -> void:
					if p != TurretMount.Phase.FIRE or fired.has(ship.get_instance_id()):
						return
					if EnemyWorld.view_rect(ship.get_tree()).has_point((ship as Node2D).global_position):
						fired[ship.get_instance_id()] = clock[0]), CONNECT_ONE_SHOT)
	var observe := func(_ship: BaseEnemy, t: float) -> bool:
		clock[0] = t
		return fired.size() >= 2
	_scale_clock()
	var out: Dictionary = await Slice.new().run(self, waves, TURRET_SLICE, TURRET_SCENE, observe, hook)
	gut.p("deep_space turret group at %.1f s: %d turrets, first FIRE in view at %s (slice s; spawn at %.1f)" % [row["rel"],
		out["targets"], fired.values(), Slice.PRE_ROLL])
	assert_eq(int(out["targets"]), 2, "the group spawns two turrets")
	assert_eq(fired.size(), 2, "both turrets fire while inside the view")


# ── Twin pair ───────────────────────────────────────────────────────────────────────────────────────────────────────

## Replays the 29.0 s pair's slice; `{ "targets", "advances" (per drone id), "telegraph_left", "rig_advances",
## "disengaged" (per drone id) }`. Stops when both drones have disengaged or left.
func _pair_slice(row: Dictionary, tweak: Callable = Callable()) -> Dictionary:
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	var to: float = float(row["rel"]) + DRONE_CONFIG.engage_seconds + Slice.POST_ROLL
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, to)
	var drones: Array[Node] = []
	var seen := {"advances": {}, "disengaged": {}, "telegraph_left": [], "rig_advances": 0}
	var hook := func(ship: Node) -> void:
		if tweak.is_valid():
			tweak.call(ship)
		drones.append(ship)
		var id := ship.get_instance_id()
		(seen["advances"] as Dictionary)[id] = 0
		var brain := ship.get_node("Brain") as TwinLaserDroneBrain
		brain.phase_changed.connect(func(p: int) -> void:
			if p == TwinLaserDroneBrain.Phase.TELEGRAPH:
				(seen["telegraph_left"] as Array).append(brain.budget.remaining())
			elif p == TwinLaserDroneBrain.Phase.ADVANCE:
				seen["advances"][id] = int(seen["advances"][id]) + 1
				if brain.pair != null:
					seen["rig_advances"] = maxi(int(seen["rig_advances"]), brain.pair.advances_started)
			elif p == TwinLaserDroneBrain.Phase.DISENGAGE:
				(seen["disengaged"] as Dictionary)[id] = true)
	var observe := func(_ship: BaseEnemy, _t: float) -> bool:
		if drones.size() < 2:
			return false
		for d in drones:
			if is_instance_valid(d) and d.is_inside_tree() and not (seen["disengaged"] as Dictionary).has(d.get_instance_id()):
				return false
		return true
	var out: Dictionary = await Slice.new().run(self, waves, to - from, DRONE_SCENE, observe, hook)
	seen["targets"] = out["targets"]
	seen["stopped"] = out["stopped"]
	return seen


func test_the_level1_twin_pair_advances_once_inside_its_budget() -> void:
	var row := _only_row(WaveBuilder.TWIN_LASER_PAIR, "twin pair")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _pair_slice(row)
	gut.p("deep_space twin pair at %.1f s: advances %s, budget left at TELEGRAPH %s, rig advances %d, disengaged %s" % [
		row["rel"], (seen["advances"] as Dictionary).values(), seen["telegraph_left"], seen["rig_advances"],
		(seen["disengaged"] as Dictionary).size()])
	assert_eq(int(seen["targets"]), 2, "the spawner makes two drones")
	assert_eq((seen["advances"] as Dictionary).values(), [1, 1], "each drone enters ADVANCE exactly once")
	assert_gt((seen["telegraph_left"] as Array).size(), 0, "the rig telegraphs")
	for left: float in seen["telegraph_left"]:
		assert_gt(left, 0.0, "TELEGRAPH starts with budget left")
	assert_eq(int(seen["rig_advances"]), 1, "the rig starts one advance")
	assert_eq((seen["disengaged"] as Dictionary).size(), 2, "both drones leave after their one attack")
	assert_true(bool(seen["stopped"]), "the slice ended on its claim, not its length")


## Boundary: the same pair with a 1.0 s private budget runs out while forming, so it never advances.
func test_a_level1_twin_pair_with_a_1_s_budget_never_advances() -> void:
	var row := _only_row(WaveBuilder.TWIN_LASER_PAIR, "twin pair")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _pair_slice(row, func(ship: Node) -> void:
		(ship as TwinLaserDrone).config.engage_seconds = 1.0)
	gut.p("deep_space twin pair, engage 1.0: advances %s, disengaged %d" % [(seen["advances"] as Dictionary).values(),
		(seen["disengaged"] as Dictionary).size()])
	assert_eq(int(seen["targets"]), 2, "sanity: two drones")
	assert_eq((seen["disengaged"] as Dictionary).size(), 2, "sanity: both budgets ran out inside the run")
	assert_eq((seen["advances"] as Dictionary).values(), [0, 0], "no ADVANCE on a 1 s budget")
	assert_eq(DRONE_CONFIG.engage_seconds, 8.0, "the shipped config is untouched")


# ── Laser Tender ────────────────────────────────────────────────────────────────────────────────────────────────────

## Replays the 2.0 s tender's slice; `{ "targets", "launch_left", "launches", "rig", "telegraph_left", "advanced",
## "disengaged" }`. Stops at its pair's first ADVANCE, or (no launch) once the tender has disengaged.
func _tender_slice(row: Dictionary, tweak: Callable = Callable()) -> Dictionary:
	var from: float = float(row["rel"]) - Slice.PRE_ROLL
	var to: float = float(row["rel"]) + TENDER_CONFIG.engage_seconds + TENDER_CONFIG.launch_telegraph \
		+ DRONE_CONFIG.engage_seconds + Slice.POST_ROLL
	var waves := Slice.slice_waves(Slice.section(row["section"]), from, to)
	var seen := {"launch_left": [], "launches": 0, "telegraph_left": [], "advanced": false, "disengaged": false}
	var rig: Array = [null]
	var hook := func(ship: Node) -> void:
		if tweak.is_valid():
			tweak.call(ship)
		var brain := ship.get_node("Brain") as LaserTenderBrain
		brain.phase_changed.connect(func(p: int) -> void:
			if p == LaserTenderBrain.Phase.LAUNCH:
				(seen["launch_left"] as Array).append(brain.budget.remaining())
			elif p == LaserTenderBrain.Phase.DISENGAGE:
				seen["disengaged"] = true)
		brain.launched.connect(func(pair: TwinLaserPair) -> void:
			seen["launches"] = int(seen["launches"]) + 1
			rig[0] = weakref(pair)
			# A weakref, never `pair` itself: the rig holds this connection, so capturing it would be a RefCounted cycle (a leak at exit).
			var weak: WeakRef = weakref(pair)
			pair.phase_changed.connect(func(p: int) -> void:
				var r := weak.get_ref() as TwinLaserPair
				if r == null:
					return
				if p == TwinLaserPair.Phase.TELEGRAPH and r.drone_a != null and is_instance_valid(r.drone_a):
					var b := r.drone_a.get_node("Brain") as TwinLaserDroneBrain
					(seen["telegraph_left"] as Array).append(b.budget.remaining() if b.budget != null else -1.0)
				elif p == TwinLaserPair.Phase.ADVANCE:
					seen["advanced"] = true))
	var observe := func(ship: BaseEnemy, _t: float) -> bool:
		if bool(seen["advanced"]):
			return true
		return rig[0] == null and (ship == null or bool(seen["disengaged"]))
	var out: Dictionary = await Slice.new().run(self, waves, to - from, WaveBuilder.LASER_TENDER, observe, hook)
	seen["targets"] = out["targets"]
	return seen


func test_the_level1_tender_launches_once_and_its_pair_advances_inside_budget() -> void:
	var row := _only_row(WaveBuilder.LASER_TENDER, "Laser Tender")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _tender_slice(row)
	gut.p("planet_approach tender at %.1f s: budget left at LAUNCH %s, launches %d, drone budget left at TELEGRAPH %s, advanced %s"
		% [row["rel"], seen["launch_left"], seen["launches"], seen["telegraph_left"], seen["advanced"]])
	assert_eq(int(seen["targets"]), 1, "one tender in its slice")
	assert_eq((seen["launch_left"] as Array).size(), 1, "reaches LAUNCH, once")
	for left: float in seen["launch_left"]:
		assert_gt(left, 0.0, "LAUNCH starts with budget left")
	assert_eq(int(seen["launches"]), 1, "launches exactly one pair")
	assert_gt((seen["telegraph_left"] as Array).size(), 0, "its pair telegraphs")
	for left: float in seen["telegraph_left"]:
		assert_gt(left, 0.0, "the launched pair's TELEGRAPH starts with drone budget left")
	assert_true(bool(seen["advanced"]), "its pair reaches ADVANCE")


## Boundary: the same tender with a 0.5 s private budget leaves before it can launch.
func test_a_level1_tender_with_a_half_second_budget_never_launches() -> void:
	var row := _only_row(WaveBuilder.LASER_TENDER, "Laser Tender")
	if row.is_empty():
		return
	_scale_clock()
	var seen := await _tender_slice(row, func(ship: Node) -> void:
		(ship as LaserTender).config.engage_seconds = 0.5)
	gut.p("planet_approach tender, engage 0.5: LAUNCH %s, launches %d, disengaged %s" % [seen["launch_left"], seen["launches"],
		seen["disengaged"]])
	assert_eq(int(seen["targets"]), 1, "sanity: one tender")
	assert_true(bool(seen["disengaged"]), "sanity: its budget ran out inside the run")
	assert_eq((seen["launch_left"] as Array).size(), 0, "no LAUNCH on a 0.5 s budget")
	assert_eq(int(seen["launches"]), 0, "nothing launched")
	assert_eq(TENDER_CONFIG.engage_seconds, 10.0, "the shipped config is untouched")
