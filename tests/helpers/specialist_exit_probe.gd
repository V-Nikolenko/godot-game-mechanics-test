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
## `test_level1_specialist_spawns.gd` (t21) and meant for t22's cloud_descent deadline rows.
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


## `{ "seconds": slowest exit, "start": where it started, "runs": how many runs, "capped": runs that hit `cap` }`.
## `host` is any node in the tree; the harness world is built under it and freed before this returns.
static func worst_disengage(host: Node, scene: PackedScene, disengage_phase: int, speeds: Array[float],
		cap: float) -> Dictionary:
	var h: RefCounted = HARNESS.assault()
	host.add_child(h.root)
	h.player.global_position = MID_VIEW + Vector2(0.0, 300.0)
	var slowest := 0.0
	var slowest_start := ""
	var runs := 0
	var capped := 0
	for start in starts():
		for speed in speeds:
			var t := disengage_seconds(h.root, scene, disengage_phase, MID_VIEW + start[0], start[1] * speed, cap)
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
		velocity: Vector2, cap: float) -> float:
	var ship := scene.instantiate() as BaseEnemy
	ship.global_position = pos
	var brain := ship.get_node("Brain")
	brain.set(&"rng_seed", 1)
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
