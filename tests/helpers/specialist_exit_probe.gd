## The measured Assault exit of a Phase 4 specialist (docs/plans/cmuyk2qqm009hoa2xyvw88ama/3-plan.md §2): the
## slowest DISENGAGE, from `enter_phase(DISENGAGE)` to `queue_free()`, over the Ph3 404-start grid, run on the REAL
## scene in a `HARNESS.assault()` world. This is `test_engagement_deadline.gd::_disengage_seconds()` generalised over
## the scene, so the count and deadline gates never use a straight-line exit for a ship whose DISENGAGE curves (the
## Ph3 open item: a straight-line term under-reported the fighter's exit by about 2.5 s).
##
## The grid: x in {-560, -280, 0, 280, 560} x y in {-320, -160, 0, 160, 320} around the view centre, 8 headings
## (k * 45 deg), plus two named starts (the centre heading right, away from its tie-broken left exit; 200 px below
## the centre heading up, away from its bottom exit), each at every speed the caller passes. Callers pass the
## fastest speed the ship can carry into DISENGAGE, 10 px/s and 2 px/s (just above the brains' `HEADING_MIN_SPEED`,
## so the heading is the velocity's): a start from rest is slowest for the sniper and the bomber (t21 review N3).
##
## No real-time physics: the ship's `_physics_process(DT)` is called by hand and its position integrated from its
## velocity (the Ph3 shape), so 404 runs cost well under a second per kind. Used by
## `test_level1_specialist_spawns.gd` (t21) and `test_engagement_deadline.gd` (t22).
##
## Two start sets. `starts()` (above, the default) covers the 1280 x 720 VIEW; t21's count gates use it. A ship that
## fights in the corridor can begin its DISENGAGE anywhere in `AssaultCorridorConstraint`'s 1480 x 1480 rect, and for
## the Ram Corvette the view grid under-reports: its curved exit turns at `acceleration / exit_speed`, and from a
## corner-tie start outside the view heading away from its tie-broken edge the turning circle keeps it inside for
## about 2 s longer (t22 review B1: 5.77 s vs 3.72 s at `exit_speed` 560). `corridor_starts()` is the second set,
## used by t22's cloud_descent ram rows (task plan docs/plans/cmuyk2qqp009loa2xb1k3py8o/3-plan.md §2).
extends RefCounted

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DT := 1.0 / 60.0
const MID_VIEW := Vector2(640.0, 360.0)


## The grid's starts as `[offset from the view centre, unit heading]` pairs.
static func starts() -> Array:
	var out: Array = [[Vector2.ZERO, Vector2.RIGHT], [Vector2(0.0, 200.0), Vector2.UP]]
	for x in [-560.0, -280.0, 0.0, 280.0, 560.0]:
		for y in [-320.0, -160.0, 0.0, 160.0, 320.0]:
			for k in 8:
				out.append([Vector2(x, y), Vector2.RIGHT.rotated(k * PI / 4.0)])
	return out


## The corridor grid's spacing (px) and how far inside the corridor's edge its outermost row sits (px). 80 / 20 gives
## offsets every 80 px over ±720 on the shipped 1480 x 1480 corridor (19 x 19 positions).
const CORRIDOR_STEP := 80.0
const CORRIDOR_INSET := 20.0
## Each corridor start's headings: straight away from its nearest world edge, and this far either side (deg).
const CORRIDOR_SPREAD_DEG: Array[float] = [-45.0, 0.0, 45.0]


## The second start set (header), as `[offset from the view centre, unit heading]` pairs: a square grid over
## `corridor` (the `AssaultCorridorConstraint.inner_rect()` an AI ship fights in), each position heading straight away
## from its nearest edge of `world` (the `projectile_world_rect()` it must leave), tie-broken left, right, top, bottom
## exactly as the brains' `_enter_disengage()` do, and +-45 deg from that. A heading away from the chosen edge is the
## start that needs the full turn; the grid includes the corner ties (|x| == |y|) where the turning circle hurts most.
static func corridor_starts(corridor: Rect2, world: Rect2) -> Array:
	var out: Array = []
	var centre := corridor.get_center()
	var n := int(floor((corridor.size.x * 0.5 - CORRIDOR_INSET) / CORRIDOR_STEP))
	var m := int(floor((corridor.size.y * 0.5 - CORRIDOR_INSET) / CORRIDOR_STEP))
	for i in range(-n, n + 1):
		for j in range(-m, m + 1):
			var pos := centre + Vector2(i, j) * CORRIDOR_STEP
			var to_left := pos.x - world.position.x
			var to_right := world.end.x - pos.x
			var to_top := pos.y - world.position.y
			var to_bottom := world.end.y - pos.y
			var nearest := minf(minf(to_left, to_right), minf(to_top, to_bottom))
			var away := Vector2.UP
			if nearest == to_left:
				away = Vector2.RIGHT
			elif nearest == to_right:
				away = Vector2.LEFT
			elif nearest == to_top:
				away = Vector2.DOWN
			for deg in CORRIDOR_SPREAD_DEG:
				out.append([pos - MID_VIEW, away.rotated(deg_to_rad(deg))])
	return out


## `{ "seconds": slowest exit, "start": where it started, "runs": how many runs, "capped": runs that hit `cap` }`.
## `start_set` is `starts()` when empty (t21's gates), or e.g. `corridor_starts()`.
## `host` is any node in the tree; the harness world is built under it and freed before this returns.
static func worst_disengage(host: Node, scene: PackedScene, disengage_phase: int, speeds: Array[float],
		cap: float, start_set: Array = [], prepare: Callable = Callable()) -> Dictionary:
	# Memoised for the whole GUT process (tests/README.md -> "Gate time", rule 2): two files measure the same
	# ship over the same grid at the same speeds, and the result is a pure function of exactly these inputs
	# (the run is hand-ticked, seeded, and reads no clock). Keyed by every input, `prepare` included, so a
	# different start set, speed list, cap or hook never reuses a figure; a copy is returned so a caller
	# cannot edit the cached one.
	var key := [scene.resource_path, disengage_phase, speeds, cap,
		(start_set if not start_set.is_empty() else starts()), prepare].duplicate(true)
	if _memo.has(key):
		return (_memo[key] as Dictionary).duplicate()
	var result := _measure_worst_disengage(host, scene, disengage_phase, speeds, cap, start_set, prepare)
	_memo[key] = result
	return result.duplicate()


## `worst_disengage()`'s results by input key. Static, so it lives as long as the script resource: one GUT process.
static var _memo: Dictionary = {}


static func _measure_worst_disengage(host: Node, scene: PackedScene, disengage_phase: int, speeds: Array[float],
		cap: float, start_set: Array, prepare: Callable) -> Dictionary:
	var h: RefCounted = HARNESS.assault()
	host.add_child(h.root)
	h.player.global_position = MID_VIEW + Vector2(0.0, 300.0)
	var slowest := 0.0
	var slowest_start := ""
	var runs := 0
	var capped := 0
	for start in (start_set if not start_set.is_empty() else starts()):
		for speed in speeds:
			var t := disengage_seconds(h.root, scene, disengage_phase, MID_VIEW + start[0], start[1] * speed, cap,
				prepare)
			runs += 1
			if t >= cap:
				capped += 1
			if t > slowest:
				slowest = t
				slowest_start = "%s heading %s at %.0f px/s" % [start[0], start[1], speed]
	h.root.free()
	return {"seconds": slowest, "start": slowest_start, "runs": runs, "capped": capped}


## Seconds from `enter_phase(disengage_phase)` until the ship queues itself for deletion (or `cap`).
static func disengage_seconds(root: Node, scene: PackedScene, disengage_phase: int, pos: Vector2,
		velocity: Vector2, cap: float, prepare: Callable = Callable()) -> float:
	var ship := scene.instantiate() as BaseEnemy
	ship.global_position = pos
	var brain := ship.get_node("Brain")
	brain.set(&"rng_seed", 1)
	if prepare.is_valid():
		prepare.call(ship)
	root.add_child(ship)
	ship.set_physics_process(false)
	ship.velocity = velocity
	brain.call(&"enter_phase", disengage_phase)
	var t := 0.0
	while t < cap and not ship.is_queued_for_deletion():
		var before := ship.global_position
		ship._physics_process(DT)
		ship.global_position = before + ship.velocity * DT
		t += DT
	ship.free()
	return t
