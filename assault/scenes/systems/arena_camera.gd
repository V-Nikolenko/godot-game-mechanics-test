## assault/scenes/systems/arena_camera.gd
## Camera2D follow script for the 740 × 740 assault-mission play area.
##
## Horizontal (50 px buffer on each side):
##   Camera stays fixed at x = 320 while the player is within the normal 640 px
##   screen width.  When the player enters the left or right 50 px buffer zone
##   the camera smoothly follows to keep the player in frame.
##
## Vertical (190 px buffer on each side):
##   Camera stays at y = 180 while the player is within the normal 360 px height.
##   Beyond the screen edges:
##     • Inner 140 px — fast 1:1 follow (feels like free movement with camera).
##     • Outer 50 px  — slow eased follow (soft cushion approaching the hard limit).
##
## World bounds:  x [-50, 690]  /  y [-190, 550]   (740 × 740 play area)
## Camera range:  x [270, 370]  /  y [-10, 370]
##
## Background parallax:
##   Level1Background's visuals all live inside CanvasLayer children.
##   CanvasLayers are screen-fixed by default — they completely ignore the
##   Camera2D position.  To make the background appear to occupy a fixed world
##   position (and therefore scroll as the camera pans), we set each layer's
##   offset to -(camera_position − home_position) every frame.  When the camera
##   moves right by N px the offset shifts left by N px, exactly cancelling the
##   screen-fixedness and making the background feel world-anchored.
##
## Suspends position tracking while camera zoom ≠ (1, 1) so the pause-menu zoom
## animation has exclusive control and the two systems never conflict.
extends Camera2D

const SCREEN_W : float = 640.0
const SCREEN_H : float = 360.0
const H_BUFFER : float = 50.0    ## Horizontal extension on each side.
const V_INNER  : float = 140.0   ## Vertical fast-follow zone depth.
const V_OUTER  : float = 50.0    ## Vertical soft-cushion zone depth.  V_INNER + V_OUTER = 190.

## Follow speeds expressed as lerp weight per second (clamped to 1.0 per frame).
@export var h_follow_speed : float = 8.0    ## Smooth pan into the horizontal buffers.
@export var v_fast_speed   : float = 30.0   ## Inner vertical zone — snappy, 1:1 feel.
@export var v_slow_speed   : float = 4.0    ## Outer vertical zone — soft easing near boundary.
@export var return_speed   : float = 12.0   ## Return to neutral when player is back inside screen.

## Camera home position (set in _ready from tscn-defined position).
var _home          : Vector2
## All CanvasLayer children of Level1Background, cached for offset updates.
var _canvas_layers : Array[CanvasLayer] = []


func _ready() -> void:
	_home = global_position   ## Should be (320, 180) as set in level_1.tscn.
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
	var px : float = (players[0] as Node2D).global_position.x
	var py : float = (players[0] as Node2D).global_position.y

	# ── Horizontal ─────────────────────────────────────────────────────────────
	# Dead zone: player x in [0, 640] → camera stays at x = 320.
	# Buffer zones: player x in [-50, 0] or [640, 690] → camera follows.
	var tx : float = SCREEN_W * 0.5
	if px < 0.0:
		tx = SCREEN_W * 0.5 + px           ## px is negative → shifts camera left.
	elif px > SCREEN_W:
		tx = SCREEN_W * 0.5 + px - SCREEN_W ## px > 640 → shifts camera right.
	tx = clamp(tx, SCREEN_W * 0.5 - H_BUFFER, SCREEN_W * 0.5 + H_BUFFER)
	## = clamp(tx, 270, 370)

	# ── Vertical ───────────────────────────────────────────────────────────────
	# Dead zone: player y in [0, 360] → camera stays at y = 180.
	# Outside: fast follow for first V_INNER px, slow ease for last V_OUTER px.
	var ty      : float = SCREEN_H * 0.5
	var v_excess: float = 0.0
	if py < 0.0:
		v_excess = -py
		ty = SCREEN_H * 0.5 + py            ## py negative → shift camera up.
	elif py > SCREEN_H:
		v_excess = py - SCREEN_H
		ty = SCREEN_H * 0.5 + py - SCREEN_H ## shift camera down.
	ty = clamp(ty, SCREEN_H * 0.5 - (V_INNER + V_OUTER),
	               SCREEN_H * 0.5 + (V_INNER + V_OUTER))
	## = clamp(ty, -10, 370)

	# ── Lerp speeds ─────────────────────────────────────────────────────────────
	var h_spd : float = h_follow_speed if (px < 0.0 or px > SCREEN_W) else return_speed

	var v_spd : float
	if v_excess == 0.0:
		v_spd = return_speed
	elif v_excess <= V_INNER:
		v_spd = v_fast_speed
	else:
		v_spd = v_slow_speed

	global_position.x = lerpf(global_position.x, tx, minf(h_spd * delta, 1.0))
	global_position.y = lerpf(global_position.y, ty, minf(v_spd * delta, 1.0))

	# ── Shift CanvasLayer backgrounds to simulate world-fixed position ──────────
	# CanvasLayers ignore Camera2D entirely.  Setting offset = -(cam − home)
	# makes each layer appear to sit at a fixed world position, so the
	# background visibly scrolls as the camera pans into the buffer zones.
	var cam_delta := global_position - _home
	for cl in _canvas_layers:
		cl.offset = -cam_delta
