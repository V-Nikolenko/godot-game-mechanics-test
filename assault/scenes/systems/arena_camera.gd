## assault/scenes/systems/arena_camera.gd
## Camera2D follow script for the 740 × 740 assault-mission play area.
##
## Follow strategy — Camera2D.offset, NOT global_position:
##   global_position stays permanently at the level origin (320, 180).
##   All player-follow panning is done through Camera2D.offset.
##   This keeps cam.global_position stable so:
##     • EnemyPathMover's cam-scroll delta (cam.global_position.y - initial)
##       is always 0 — enemies are never displaced by player panning.
##     • WaveManager spawn positions (cam.global_position + entry_offset)
##       always resolve from the fixed screen centre — no drift on delayed spawns.
##
## Background pinning:
##   In Godot 4.3, Camera2D.offset is incorporated into the viewport canvas
##   transform in a way that visually shifts CanvasLayer content even when
##   follow_viewport_enabled = false.  To keep all background layers
##   screen-fixed, each CanvasLayer's own offset is set to -camera.offset
##   every frame, exactly cancelling any induced shift.
##
## Offset limits (equal to the buffer distances from screen centre):
##   Horizontal ± 50 px  →  world x reachable: [-50, 690]
##   Vertical  ±190 px  →  world y reachable: [-190, 550]
##
## Suspends offset tracking while camera zoom ≠ (1, 1) so the pause-menu zoom
## animation has exclusive control and the two systems never conflict.
extends Camera2D

const SCREEN_W : float = 640.0
const SCREEN_H : float = 360.0
const H_LIMIT  : float = 50.0    ## Max horizontal offset (= horizontal buffer width).
const V_LIMIT  : float = 190.0   ## Max vertical offset   (= vertical buffer depth).

## Lerp weight per second.  Higher = snappier follow; 1.0 per frame is the cap.
@export var follow_speed : float = 12.0
## Upward shift applied to the vertical target so the ship rests below the
## screen centre — gives more "look-ahead" space above the player.
## 0 = perfectly centred.  60 = ship sits ~⅔ down the screen (shmup default).
@export var v_bias : float = 60.0

## Background CanvasLayer children of Level1Background, cached for pinning.
var _canvas_layers : Array[CanvasLayer] = []


func _ready() -> void:
	var bg := get_parent().get_node_or_null("Level1Background")
	if bg:
		for child in bg.get_children():
			if child is CanvasLayer:
				_canvas_layers.append(child as CanvasLayer)


func _physics_process(delta: float) -> void:
	## Defer to the pause-menu while it is animating the camera zoom.
	if not zoom.is_equal_approx(Vector2.ONE):
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p : Vector2 = (players[0] as Node2D).global_position

	## Target offset = player displacement from the fixed screen centre.
	## Clamped so the viewport never reveals world outside the 740 × 740 area.
	var target : Vector2 = Vector2(
		clamp(p.x - SCREEN_W * 0.5,         -H_LIMIT, H_LIMIT),
		clamp(p.y - SCREEN_H * 0.5 - v_bias, -V_LIMIT, V_LIMIT)
	)

	offset = offset.lerp(target, minf(follow_speed * delta, 1.0)).round()

	## Pin every background CanvasLayer so it stays screen-fixed regardless of
	## any shift that Camera2D.offset induces on the canvas transform.
	for cl in _canvas_layers:
		cl.offset = -offset
