## RaceWorld — scrolls the Track Node2D (group "race_track") downward at the player's current
## top speed, so track objects (panels, obstacles, finish line) move naturally without any
## per-object projection. Also maps AI racers' track_y to screen Y (relative to the player's
## anchor) and drives the parallax background. Add this node to group "race_world".
##
## Track layout convention (build your level with this in mind):
##   • Track local Y = 0 → player starting position on screen (base_screen_y).
##   • Objects at Track local Y = -N are encountered when the player's track_y reaches N.
##   • Place panels/obstacles/finish line at NEGATIVE local Y; more negative = further ahead.
##   • Example: a panel you want at race distance 3 000 → position.y = -3 000 in Track space.
class_name RaceWorld
extends Node

## Screen-Y the player rests around and that racers converge toward when level in the race.
@export var base_screen_y: float = 520.0
## Background scroll multiplier at player's min / max top speed.
@export var bg_scroll_min: float = 3.0
@export var bg_scroll_max: float = 11.0

var _director: RaceDirector = null
var _background: BackgroundController = null
var _track: Node2D = null

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_background = get_tree().get_first_node_in_group("background") as BackgroundController
	_track = get_tree().get_first_node_in_group("race_track") as Node2D
	if _track:
		## Initialise so Track local Y = 0 maps to base_screen_y on screen.
		## From this point, _track.position.y = base_screen_y + player.track_y each frame.
		_track.position.y = base_screen_y

## Screen Y for a racer, derived from the SAME scrolling Track the furniture uses, so a rival at
## track_y = R lines up exactly with furniture authored at Track-local Y = -R. (Furniture at
## local -R sits at world Y = _track.position.y - R; this puts the rival at the same place.)
func get_screen_y(p: RaceParticipant) -> float:
	if _track == null:
		return base_screen_y
	return _track.position.y - p.track_y

func _physics_process(_delta: float) -> void:
	var player := _director.get_player() if _director else null
	if player == null:
		return
	## Maintain the invariant: _track.position.y = base_screen_y + player.track_y.
	## RaceParticipant owns all track_y advancement (base speed + panel lunge + decay).
	## Mirroring it here means lunges and speed changes are immediately visible — no drift.
	if _track:
		_track.position.y = base_screen_y + player.track_y
	if _background:
		## Spike to max scroll during a panel lunge; otherwise follow the top-speed ramp.
		var fraction := maxf(player.top_speed_fraction(), player.lunge_fraction())
		_background.set_throttle_scroll(lerpf(bg_scroll_min, bg_scroll_max, fraction))
