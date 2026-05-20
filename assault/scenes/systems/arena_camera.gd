## assault/scenes/systems/arena_camera.gd
## Camera2D follow script for the 740 × 740 assault-mission play area.
##
## Design: Camera2D.global_position NEVER changes (stays at the level origin,
## (320, 180)).  Player following is done entirely through Camera2D.offset.
## This keeps cam.global_position stable so that:
##   • EnemyPathMover's cam-scroll compensation (cam.global_position.y -
##     _initial_cam_y) always evaluates to 0 — enemies are never displaced.
##   • WaveManager spawn positions (cam.global_position + entry_offset) always
##     resolve from the fixed screen centre — no positional drift on delayed
##     spawns.
##   • Background CanvasLayers remain screen-fixed by default — no extra code
##     needed and camera movement does not disturb them.
##
## Offset limits (equal to the buffer distances from screen centre):
##   Horizontal ± 50 px  →  world x reachable: [-50, 690]
##   Vertical  ±190 px  →  world y reachable: [-190, 550]
##
## The offset is lerped toward the player position every physics frame,
## giving an immediate, smooth follow that starts as soon as the player
## moves away from the screen centre.
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
		clamp(p.x - SCREEN_W * 0.5, -H_LIMIT, H_LIMIT),
		clamp(p.y - SCREEN_H * 0.5, -V_LIMIT, V_LIMIT)
	)

	offset = offset.lerp(target, minf(follow_speed * delta, 1.0))
