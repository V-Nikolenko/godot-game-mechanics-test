## PlayerRaceController — attached to the shared player ship at race start. The player keeps its
## normal shmup movement; this node (a) clamps the player's screen-Y to a band around the world
## anchor, (b) derives the player's track_y from its screen-Y each frame (high = nose ahead),
## (c) routes dash-panel crossings and damage into the top-speed economy.
class_name PlayerRaceController
extends Node

## Vertical band (px) the player may roam above/below RaceWorld.base_screen_y.
@export var band_ahead: float = 280.0    ## how far ABOVE the anchor (smaller y) the player may fly
@export var band_behind: float = 160.0   ## how far BELOW the anchor the player may drop
## Forward throttle while holding race_brake (1.0 = full speed). Lets the player slow to
## time a laser; the world scrolls slower and the player drops back in standings.
@export var brake_throttle: float = 0.3

var _ship: Node2D = null
var _participant: RaceParticipant = null
var _world: RaceWorld = null
var _last_health: int = -1
var _zoom_tween: Tween = null

func setup(ship: Node2D, participant: RaceParticipant, health: Health) -> void:
	_ship = ship
	_participant = participant
	_world = get_tree().get_first_node_in_group("race_world") as RaceWorld
	if health:
		_last_health = health.current_health
		health.amount_changed.connect(_on_health_changed)
	if _participant:
		_participant.panel_boosted.connect(_on_panel_boosted)

func _physics_process(_delta: float) -> void:
	if _ship == null or _participant == null or _world == null:
		return
	# Clamp the player's vertical roam to the band (input drives the actual movement).
	# track_y now self-advances in RaceParticipant at the player's top speed —
	# no screen-Y → track_y mapping needed.
	var top := _world.base_screen_y - band_ahead
	var bottom := _world.base_screen_y + band_behind
	_ship.global_position.y = clampf(_ship.global_position.y, top, bottom)

	## Throttle: holding race_brake slows the player's forward advance (RaceParticipant
	## applies cruise_factor to the player as of Phase 2). Release = full speed.
	_participant.set_cruise_factor(brake_throttle if Input.is_action_pressed("race_brake") else 1.0)

func _on_panel_boosted() -> void:
	_punch_camera()
	if _ship and _ship.has_method("set_thruster_state"):
		_ship.set_thruster_state(ThrusterEffect.State.BOOST_PANEL)
		await get_tree().create_timer(_participant.grace_after_panel).timeout
		if is_instance_valid(_ship) and _ship.has_method("clear_thruster_override"):
			_ship.clear_thruster_override()

## Quick zoom-out kick on a dash-panel boost, then settle back to 1.0. ArenaCamera only
## defers its offset tracking while zoom ≠ (1,1), so restoring to ONE hands control back.
func _punch_camera() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return
	if _zoom_tween and _zoom_tween.is_valid():
		_zoom_tween.kill()
	cam.zoom = Vector2(0.94, 0.94)
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(cam, "zoom", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _on_health_changed(current: int) -> void:
	if _last_health >= 0 and current < _last_health:
		_participant.lose_top_speed_on_hit()
	_last_health = current
