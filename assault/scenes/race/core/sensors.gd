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

## Nearest dash panel ahead on screen (smaller y), within max_gap px of vertical reach.
func nearest_panel_ahead(max_gap: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_gap
	for n in get_tree().get_nodes_in_group("dash_panels"):
		var p := n as Node2D
		if p == null:
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

func gap_to(p: RaceParticipant) -> float:
	return p.track_y - _part.track_y if p else 0.0

func player() -> RaceParticipant:
	return _director.get_player() if _director else null
