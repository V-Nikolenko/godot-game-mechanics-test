## Sensors — stateless perception for a racer brain. Reads the RaceDirector standings and small
## group scans. No strategy lives here; brains call these and decide. Attach as a child of the
## RaceShip; it self-resolves its host on setup().
class_name Sensors
extends Node

## Detects player bullets (64) and AI/enemy bullets (256). Self-dodge is avoided by the
## Y-position filter in incoming_threat(): a racer's own just-fired bullet starts above the
## muzzle and immediately travels upward — it is never below the ship and is never returned.
@export var bullet_mask: int = 64 | 256
@export var threat_radius: float = 95.0

## Lateral tolerance (px) for "a hazard is in the same lane as this panel" (trap check).
const _TRAP_LANE_TOL: float = 150.0

var _host: RaceShip = null
var _part: RaceParticipant = null
var _director: RaceDirector = null
var _threat_area: Area2D = null

func setup(host: RaceShip) -> void:
	_host = host
	_part = host.participant
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_threat_area = Area2D.new()
	_threat_area.collision_layer = 0
	_threat_area.collision_mask = bullet_mask
	_threat_area.monitoring = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = threat_radius
	shape.shape = circle
	_threat_area.add_child(shape)
	host.add_child(_threat_area)

func _pos() -> Vector2:
	return _host.global_position

## Nearest participant ahead of me on the track, within max_gap track_y and lane_tol px in X.
func ship_ahead(max_gap: float, lane_tol: float) -> RaceParticipant:
	return _nearest_ship(true, max_gap, lane_tol)

func ship_behind(max_gap: float, lane_tol: float) -> RaceParticipant:
	return _nearest_ship(false, max_gap, lane_tol)

func _nearest_ship(ahead: bool, max_gap: float, lane_tol: float) -> RaceParticipant:
	var best: RaceParticipant = null
	var best_gap := max_gap
	for p in _all_participants():
		if p == _part:
			continue
		var gap := p.track_y - _part.track_y     ## >0 = ahead
		if (ahead and gap <= 0.0) or (not ahead and gap >= 0.0):
			continue
		var ag := absf(gap)
		if ag > max_gap or absf(p.global_x() - _pos().x) > lane_tol:
			continue
		if ag < best_gap:
			best_gap = ag
			best = p
	return best

func _all_participants() -> Array[RaceParticipant]:
	var out: Array[RaceParticipant] = []
	for n in get_tree().get_nodes_in_group("racers"):
		var s := n as RaceShip
		if s and is_instance_valid(s):
			out.append(s.participant)
	if _director and _director.get_player():
		out.append(_director.get_player())
	return out

## True if crossing this dash panel would lunge the ship (+panel_lunge track_y) into a
## non-laser lethal hazard (wall/asteroid) sitting just ahead in the panel's lane. Such a
## panel is rocket-or-die for the player; AI refuse it (nearest_panel_ahead skips it).
## Lasers are excluded — they pulse, and the laser timing reflex handles them separately.
func panel_is_trapped(panel: Node2D) -> bool:
	if panel == null:
		return false
	var lunge: float = _part.panel_lunge if _part else 650.0
	var px := panel.global_position.x
	var py := panel.global_position.y
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h) or h is LaserRay:
			continue
		if not h.has_method("danger_rect"):
			continue
		var c: Vector2 = h.danger_rect().get_center()
		var ahead := py - c.y                  ## >0 = hazard ahead (above the panel)
		if ahead <= 0.0 or ahead > lunge:
			continue
		if absf(c.x - px) < _TRAP_LANE_TOL:
			return true
	return false

## Nearest dash panel ahead on screen (smaller y), within max_gap px of vertical reach.
## Trapped panels (a wall just ahead in-lane) are skipped — no racer dives into a trap.
func nearest_panel_ahead(max_gap: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_gap
	for n in get_tree().get_nodes_in_group("dash_panels"):
		var p := n as Node2D
		if p == null:
			continue
		if panel_is_trapped(p):
			continue
		var dy := _pos().y - p.global_position.y   ## >0 = ahead (above me)
		if dy < -80.0 or dy > max_gap:
			continue
		var d := absf(p.global_position.x - _pos().x) + maxf(0.0, dy)
		if d < best_d:
			best_d = d
			best = p
	return best

## Returns the first bullet that is BEHIND this ship (higher screen Y = further back in race
## space). A bullet is only a threat if it is below us on screen and therefore flying toward us.
## Forward-only bullets fired by self or by ships ahead are already past — their Y is lower
## (above us) and they are filtered out. Requires all AI bullets to fly Vector2.UP (Step 2).
func incoming_threat() -> Node2D:
	if _threat_area == null:
		return null
	for area in _threat_area.get_overlapping_areas():
		if area.global_position.y > _host.global_position.y:
			return area
	return null

## Nearest hazard (asteroids/mines) ahead within lookahead px, for opt-in avoidance.
func hazard_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_d := lookahead
	for grp in ["asteroids", "mines"]:
		for n in get_tree().get_nodes_in_group(grp):
			var h := n as Node2D
			if h == null:
				continue
			var dy := _pos().y - h.global_position.y
			if dy <= 0.0 or dy > lookahead:
				continue
			if dy < best_d:
				best_d = dy
				best = h
	return best

## Nearest currently-lethal track hazard (group "race_hazards") ahead within lookahead px
## whose lethal rect overlaps my current X. Used by the RaceShip avoidance reflex.
func race_hazard_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_dy := lookahead
	var x := _pos().x
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if not h.has_method("is_lethal_now") or not h.is_lethal_now():
			continue
		if not h.has_method("danger_rect"):
			continue
		var rect: Rect2 = h.danger_rect()
		var dy := _pos().y - rect.get_center().y   ## >0 = ahead (above me on screen)
		if dy <= 0.0 or dy > lookahead:
			continue
		## Only care if it blocks my current X lane.
		if x < rect.position.x or x > rect.position.x + rect.size.x:
			continue
		if dy < best_dy:
			best_dy = dy
			best = h
	return best

## Nearest X within the lane [lane_min, lane_max] that clears every lethal hazard rect
## within lookahead px ahead. Steps outward from current X to the closest free side.
func safe_x(current_x: float, lookahead: float, lane_min: float = 128.0, lane_max: float = 1152.0) -> float:
	var blocks: Array[Vector2] = []   ## each = (min_x, max_x)
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var h := n as Node2D
		if h == null or not is_instance_valid(h):
			continue
		if not h.has_method("is_lethal_now") or not h.is_lethal_now():
			continue
		if not h.has_method("danger_rect"):
			continue
		var rect: Rect2 = h.danger_rect()
		var dy := _pos().y - rect.get_center().y
		if dy <= 0.0 or dy > lookahead:
			continue
		blocks.append(Vector2(rect.position.x, rect.position.x + rect.size.x))
	if blocks.is_empty():
		return current_x
	if _x_is_clear(current_x, blocks):
		return current_x
	## Search outward in 16 px steps for the nearest clear X inside the lane.
	for step in range(16, 1100, 16):
		var left := current_x - step
		if left >= lane_min and _x_is_clear(left, blocks):
			return left
		var right := current_x + step
		if right <= lane_max and _x_is_clear(right, blocks):
			return right
	return current_x   ## boxed in — no clear X (attrition: HazardSystem will kill us)

func _x_is_clear(x: float, blocks: Array[Vector2]) -> bool:
	for b in blocks:
		if x >= b.x and x <= b.y:
			return false
	return true

## Nearest full-width (horizontal) LaserRay ahead within lookahead px — a timing gate the
## ship cannot dodge laterally. Returns null if none (vertical lasers are dodged via safe_x).
func blocking_laser_ahead(lookahead: float) -> Node2D:
	var best: Node2D = null
	var best_dy := lookahead
	for n in get_tree().get_nodes_in_group("race_hazards"):
		var l := n as LaserRay
		if l == null or not is_instance_valid(l) or not l.is_full_width():
			continue
		var dy := _pos().y - l.global_position.y   ## >0 = ahead (above me)
		if dy <= 0.0 or dy > lookahead:
			continue
		if dy < best_dy:
			best_dy = dy
			best = l
	return best

## Whether to brake before a horizontal laser: hold unless the beam is fully dark (the only
## safe window to cross). Coarse but robust — the racer waits out warn/charge/active/dissolve
## and advances during the OFF gap.
func laser_should_brake(laser: LaserRay) -> bool:
	return not laser.is_safe_to_cross()

func gap_to(p: RaceParticipant) -> float:
	return p.track_y - _part.track_y if p else 0.0

func player() -> RaceParticipant:
	return _director.get_player() if _director else null
