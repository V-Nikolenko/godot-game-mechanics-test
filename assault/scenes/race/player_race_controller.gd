## PlayerRaceController — attached to the shared player ship at race start. The player keeps its
## normal shmup movement; this node (a) clamps the player's screen-Y to a band around the world
## anchor, (b) derives the player's track_y from its screen-Y each frame (high = nose ahead),
## (c) routes dash-panel crossings and damage into the top-speed economy.
class_name PlayerRaceController
extends Node

## Vertical band (px) the player may roam above/below RaceWorld.base_screen_y.
@export var band_ahead: float = 280.0    ## how far ABOVE the anchor (smaller y) the player may fly
@export var band_behind: float = 160.0   ## how far BELOW the anchor the player may drop

var _ship: Node2D = null
var _participant: RaceParticipant = null
var _world: RaceWorld = null
var _last_health: int = -1

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

func _on_panel_boosted() -> void:
	if _ship and _ship.has_method("set_thruster_state"):
		_ship.set_thruster_state(ThrusterEffect.State.BOOST_PANEL)
		await get_tree().create_timer(_participant.grace_after_panel).timeout
		if is_instance_valid(_ship) and _ship.has_method("clear_thruster_override"):
			_ship.clear_thruster_override()

func _on_health_changed(current: int) -> void:
	if _last_health >= 0 and current < _last_health:
		_participant.lose_top_speed_on_hit()
	_last_health = current
