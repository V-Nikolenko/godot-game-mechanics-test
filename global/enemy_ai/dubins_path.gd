## The shortest path between two poses for a vehicle with a minimum turn radius
## (docs/plans/cmulwkar000btqj2x1e58sfd4/3-plan.md §3; Dubins 1957, LaValle *Planning Algorithms* §15.3.1).
##
## A Dubins path is at most three pieces, each a full-rate arc of radius `r` or a straight line:
## the four CSC shapes (RSR, LSL, RSL, LSR) and the two CCC shapes (RLR, LRL). An attack-run brain
## plans one to arrive at a pass's start point already pointing along the run, then tracks its
## samples with `Steering.turn_toward` — this file only does the geometry. Pure maths: no node, no
## motion writes (it sits in `test_enemy_mover_single_writer.gd`'s sweep).
##
## Frame: Godot's y-down world. A turn's `sign` is +1 when the heading angle increases (clockwise on
## screen, "R"), −1 when it decreases ("L").
class_name DubinsPath
extends RefCounted

const EPS := 0.0001

## "RSR", "LSL", "RSL", "LSR", "RLR", "LRL" or "R"/"L" (a single arc).
var kind: String = ""
## Total length, px.
var length: float = INF
## Each entry is either
##   {"type": "arc", "center": Vector2, "sign": int, "angle": float (rad, ≥ 0), "start": Vector2,
##    "start_heading": float}
## or {"type": "line", "from": Vector2, "to": Vector2}.
var segments: Array[Dictionary] = []
var radius: float = 0.0

var _end_heading: float = 0.0


## Every geometrically valid Dubins path from pose (`p0`, `h0`) to pose (`p1`, `h1`) with turn radius
## `r`, shortest first. Headings are angles in radians.
static func candidates(p0: Vector2, h0: float, p1: Vector2, h1: float, r: float) -> Array[DubinsPath]:
	var out: Array[DubinsPath] = []
	if r <= 0.0:
		return out
	for s0 in [1, -1]:
		for s1 in [1, -1]:
			var path := _csc(p0, h0, p1, h1, r, s0, s1)
			if path != null:
				out.append(path)
	for s in [1, -1]:
		for side in [1.0, -1.0]:
			var path := _ccc(p0, h0, p1, h1, r, s, side)
			if path != null:
				out.append(path)
	out.sort_custom(func(a: DubinsPath, b: DubinsPath) -> bool: return a.length < b.length)
	return out


## The angle of the first arc, or 0 when the path starts with a straight.
func first_arc_angle() -> float:
	if segments.is_empty() or segments[0].type != "arc":
		return 0.0
	return segments[0].angle


## The heading at the end of the path, computed analytically (a sampled last chord is off by
## `step / 2r`).
func end_heading() -> float:
	return _end_heading


## Points along the path, `step` px apart (the last spacing may be shorter), start and end included.
func sample(step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for seg in segments:
		var n: int
		if seg.type == "line":
			n = maxi(1, int(ceil(seg.from.distance_to(seg.to) / step)))
			for i in n + 1:
				if i == 0 and not pts.is_empty():
					continue
				pts.append(seg.from.lerp(seg.to, float(i) / n))
		else:
			n = maxi(1, int(ceil(seg.angle * radius / step)))
			var a0: float = (seg.start - seg.center).angle()
			for i in n + 1:
				if i == 0 and not pts.is_empty():
					continue
				pts.append(seg.center + Vector2.from_angle(a0 + seg.sign * seg.angle * float(i) / n) * radius)
	return pts


## The number of `step`-spaced samples `sample(step)` spends on the first arc (0 with no first arc).
func first_arc_samples(step: float) -> int:
	var a := first_arc_angle()
	if a <= 0.0:
		return 0
	return maxi(1, int(ceil(a * radius / step)))


# ── Construction ─────────────────────────────────────────────────────────────────────────────────

static func _center(p: Vector2, heading: float, turn: int, r: float) -> Vector2:
	return p + Vector2.from_angle(heading + turn * PI / 2.0) * r


## The heading at point `q` on the circle round `c`, travelling with `sign`.
static func _heading_on(q: Vector2, c: Vector2, turn: int) -> float:
	return (q - c).angle() - turn * PI / 2.0 - PI


static func _wrap(a: float) -> float:
	var w := fposmod(a, TAU)
	# A full turn that is really "no turn" (float noise just below 2π) counts as none.
	return 0.0 if w > TAU - EPS else w


static func _arc(c: Vector2, turn: int, start: Vector2, start_heading: float, angle: float) -> Dictionary:
	return {"type": "arc", "center": c, "sign": turn, "angle": angle, "start": start, "start_heading": start_heading}


static func _letter(turn: int) -> String:
	return "R" if turn > 0 else "L"


static func _csc(p0: Vector2, h0: float, p1: Vector2, h1: float, r: float, s0: int, s1: int) -> DubinsPath:
	var c0 := _center(p0, h0, s0, r)
	var c1 := _center(p1, h1, s1, r)
	var w := c1 - c0
	var d := w.length()
	var path := DubinsPath.new()
	path.radius = r
	path._end_heading = h1
	if s0 == s1 and d < EPS:
		# Start and goal share a circle: a single arc.
		var a := _wrap(s0 * (h1 - h0))
		path.kind = _letter(s0)
		path.segments = [_arc(c0, s0, p0, h0, a)]
		path.length = r * a
		return path
	var phi: float
	var straight: float
	if s0 == s1:
		phi = w.angle()
		straight = d
	else:
		if d < 2.0 * r:
			return null
		straight = sqrt(d * d - 4.0 * r * r)
		phi = w.angle() + s0 * atan2(2.0 * r, straight)
	var t0 := c0 - Vector2.from_angle(phi + s0 * PI / 2.0) * r
	var t1 := c1 - Vector2.from_angle(phi + s1 * PI / 2.0) * r
	var a0 := _wrap(s0 * (phi - h0))
	var a1 := _wrap(s1 * (h1 - phi))
	path.kind = "%sS%s" % [_letter(s0), _letter(s1)]
	path.segments = [_arc(c0, s0, p0, h0, a0), {"type": "line", "from": t0, "to": t1}, _arc(c1, s1, t1, phi, a1)]
	path.length = r * (a0 + a1) + straight
	return path


static func _ccc(p0: Vector2, h0: float, p1: Vector2, h1: float, r: float, s: int, side: float) -> DubinsPath:
	var c0 := _center(p0, h0, s, r)
	var c1 := _center(p1, h1, s, r)
	var w := c1 - c0
	var d := w.length()
	if d < EPS or d > 4.0 * r:
		return null
	var cm := c0 + Vector2.from_angle(w.angle() + side * acos(clampf(d / (4.0 * r), -1.0, 1.0))) * (2.0 * r)
	var t0 := (c0 + cm) * 0.5
	var t1 := (cm + c1) * 0.5
	var ht0 := _heading_on(t0, c0, s)
	var ht1 := _heading_on(t1, cm, -s)
	var a0 := _wrap(s * (ht0 - h0))
	var am := _wrap(-s * (ht1 - ht0))
	var a1 := _wrap(s * (h1 - ht1))
	var path := DubinsPath.new()
	path.radius = r
	path._end_heading = h1
	path.kind = "%s%s%s" % [_letter(s), _letter(-s), _letter(s)]
	path.segments = [_arc(c0, s, p0, h0, a0), _arc(cm, -s, t0, ht0, am), _arc(c1, s, t1, ht1, a1)]
	path.length = r * (a0 + am + a1)
	return path
