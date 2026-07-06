## SpeedStreaks — a screen overlay that draws vertical streaks scrolling downward, with
## speed and opacity scaled by the player's top-speed fraction. Subtle/near-invisible at
## base speed, vivid near max. Attach to the Draw (Node2D) child of a CanvasLayer.
extends Node2D

@export var streak_count: int = 28
@export var color: Color = Color(0.7, 0.85, 1.0)
@export var max_alpha: float = 0.45        ## opacity at full speed (0 at base)
@export var streak_len_min: float = 20.0
@export var streak_len_max: float = 90.0
@export var slow_speed: float = 220.0      ## scroll px/s at base top speed
@export var fast_speed: float = 1500.0     ## scroll px/s at max top speed
@export var lane_min: float = 150.0
@export var lane_max: float = 1130.0
@export var screen_height: float = 720.0

var _ys: PackedFloat32Array = PackedFloat32Array()
var _xs: PackedFloat32Array = PackedFloat32Array()
var _len: PackedFloat32Array = PackedFloat32Array()
var _director: RaceDirector = null
var _frac: float = 0.0

func _ready() -> void:
	_director = get_tree().get_first_node_in_group("race_director") as RaceDirector
	_ys.resize(streak_count)
	_xs.resize(streak_count)
	_len.resize(streak_count)
	for i in streak_count:
		_xs[i] = randf_range(lane_min, lane_max)
		_ys[i] = randf() * screen_height
		_len[i] = randf_range(streak_len_min, streak_len_max)

func _process(delta: float) -> void:
	var p := _director.get_player() if _director else null
	_frac = clampf(p.top_speed_fraction(), 0.0, 1.0) if p else 0.0
	var spd := lerpf(slow_speed, fast_speed, _frac)
	for i in streak_count:
		_ys[i] += spd * delta
		if _ys[i] > screen_height + _len[i]:
			_ys[i] = -_len[i]
			_xs[i] = randf_range(lane_min, lane_max)
	queue_redraw()

func _draw() -> void:
	var a := max_alpha * _frac
	if a <= 0.01:
		return
	var c := Color(color.r, color.g, color.b, a)
	for i in streak_count:
		draw_line(Vector2(_xs[i], _ys[i]), Vector2(_xs[i], _ys[i] + _len[i]), c, 2.0)
