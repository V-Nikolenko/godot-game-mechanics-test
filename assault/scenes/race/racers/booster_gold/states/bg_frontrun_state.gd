## BgFrontrunState — active while Booster Gold is in 1st. Defend the lead: GRAB_PANEL preempts
## almost everything (panels keep top speed maxed = lead held). Soft-block the player by drifting
## onto the panel it wants. JUKE if tailed. Does NOT spend the dash here. → RECLAIM if passed.
class_name BgFrontrunState
extends State

var host: RaceShip

@export var panel_reach: float = 900.0
@export var tail_gap: float = 220.0       ## track_y within which a chaser counts as "tailing"
@export var tail_lane: float = 160.0

func process_physics(_delta: float) -> void:
	if host.sensors.incoming_threat() != null:
		host.brain.transition_to(&"BgEvade"); return
	var dir := host._director()
	if dir and not dir.is_in_front(host.participant):
		host.brain.transition_to(&"BgReclaim"); return

	var panel := host.sensors.nearest_panel_ahead(panel_reach)
	if panel != null:
		host.brain.get_state(&"BgGrabPanel").set("return_to", &"BgFrontrun")
		host.brain.transition_to(&"BgGrabPanel"); return

	# Someone sitting on my tail? Juke to deny the slipstream.
	var chaser := host.sensors.ship_behind(tail_gap, tail_lane)
	if chaser != null:
		host.brain.transition_to(&"BgJuke"); return

	host.set_forward_floor()
	host.steer_toward(host.global_position.x)   ## hold a clean line
