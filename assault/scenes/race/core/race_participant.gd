## RaceParticipant — on EVERY race ship (player + AI). Owns the ship's position along the track
## (track_y) and the TOP-SPEED ECONOMY (panels raise it; damage/idleness bleed it off). AI ships
## self-advance track_y from current_speed; the player's track_y is set externally by the
## PlayerRaceController (its screen-Y trims it). Registers with the RaceDirector on ready.
class_name RaceParticipant
extends Node

signal finished_race(participant: RaceParticipant)
signal top_speed_changed(value: float, maximum: float)
signal panel_boosted

@export var is_player: bool = false

@export_group("Top-speed economy")
@export var base_top_speed: float = 220.0   ## floor; decay never drops below this
@export var max_top_speed: float = 600.0    ## hard cap
@export var panel_gain: float = 70.0        ## top speed added per dash panel
@export var decay_per_sec: float = 22.0     ## bled off when not recently boosted
@export var loss_per_hit: float = 90.0      ## top speed lost on taking a hit
@export var grace_after_panel: float = 1.5  ## seconds of no-decay right after a panel
@export var panel_lunge: float = 650.0      ## instant forward leap on a panel (track_y units)

## AI ease-off: brains scale forward speed in [0..1] (1 = floor it). Player ignores this.
var cruise_factor: float = 1.0

var track_y: float = 0.0
var top_speed: float = 0.0
var current_speed: float = 0.0
var finished: bool = false

var _director: RaceDirector = null
var _grace: float = 0.0
var _lunge_remaining: float = 0.0

func _ready() -> void:
	top_speed = base_top_speed
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	if _director:
		_director.register(self)
	else:
		push_warning("[RaceParticipant] No RaceDirector in group 'race_director'.")
	top_speed_changed.emit(top_speed, max_top_speed)

## The owning ship node (RaceShip for AI; the player ship for the player).
func ship() -> Node2D:
	return get_parent() as Node2D

func global_x() -> float:
	var s := ship()
	return s.global_position.x if s else 0.0

func set_cruise_factor(f: float) -> void:
	cruise_factor = clampf(f, 0.0, 1.0)

## Add a forward lunge without the panel's speed/grace bonuses — used by racer AI states.
func add_lunge(amount: float) -> void:
	_lunge_remaining += amount

## Crossing a dash panel: raise top speed, grant the no-decay grace, lunge forward, flag visuals.
func cross_panel() -> void:
	top_speed = minf(max_top_speed, top_speed + panel_gain)
	_grace = grace_after_panel
	_lunge_remaining += panel_lunge
	top_speed_changed.emit(top_speed, max_top_speed)
	panel_boosted.emit()

## Taking a hit costs top speed (in addition to HP/shield handled by DamageReaction).
func lose_top_speed_on_hit() -> void:
	top_speed = maxf(base_top_speed, top_speed - loss_per_hit)
	top_speed_changed.emit(top_speed, max_top_speed)

func top_speed_fraction() -> float:
	return inverse_lerp(base_top_speed, max_top_speed, top_speed)

## 1.0 right after a panel hit, decays to 0 as the lunge is consumed (~0.25 s).
## Used by RaceWorld to spike background scroll during the burst.
func lunge_fraction() -> float:
	return clampf(_lunge_remaining / panel_lunge, 0.0, 1.0)

func _physics_process(delta: float) -> void:
	if finished or _director == null:
		return
	# Economy: decay toward base once the post-panel grace expires.
	if _grace > 0.0:
		_grace -= delta
	else:
		var decayed := maxf(base_top_speed, top_speed - decay_per_sec * delta)
		if decayed != top_speed:
			top_speed = decayed
			top_speed_changed.emit(top_speed, max_top_speed)

	current_speed = top_speed * (cruise_factor if not is_player else 1.0)

	# All ships (player and AI) self-advance track_y.
	# The Track node scrolls in RaceWorld at the same speed so the world looks right.
	track_y += current_speed * delta
	if _lunge_remaining > 0.0:
		var step := minf(_lunge_remaining, 2600.0 * delta)
		track_y += step
		_lunge_remaining -= step
	if track_y >= _director.track_length:
		track_y = _director.track_length
		finished = true
		_director.notify_finished(self)
		finished_race.emit(self)

func _exit_tree() -> void:
	if _director:
		_director.unregister(self)
