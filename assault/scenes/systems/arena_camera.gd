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
## Background anchoring:
##   Each background CanvasLayer is screen-fixed by default — its content
##   doesn't move when the camera pans.  That makes the 740×740 background
##   look "cropped" because you only ever see the same 640×360 portion of
##   the texture, no matter where the player flies.
##
##   To anchor every layer to world-space (so panning the camera reveals
##   new parts of its texture), we set cl.offset = -camera.offset.  This
##   shifts the canvas opposite to the camera pan, exactly cancelling the
##   apparent motion so the texture appears stuck to the world.
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
## Deadzone — half-extents of a rectangle around the framing point where small
## player movements do NOT move the camera.  Reduces wobble from minor
## adjustments.  Hollow Knight / Mario-style camera box.
@export var deadzone_half_size : Vector2 = Vector2(20.0, 15.0)

## The follow state, tracked separately from the final camera offset so that
## per-frame shake noise never pollutes the lerp baseline.  Final offset =
## _follow_offset + CameraShake.get_offset().
var _follow_offset : Vector2 = Vector2.ZERO
## Cached CanvasLayer children of Level1Background — all anchored to world
## space (factor 1.0) so the background reveals new texture as the camera pans.
var _bg_layers : Array[CanvasLayer] = []


func _ready() -> void:
	var bg := get_parent().get_node_or_null("Level1Background")
	if bg == null:
		return
	for child in bg.get_children():
		if child is CanvasLayer:
			_bg_layers.append(child as CanvasLayer)


func _physics_process(delta: float) -> void:
	## Defer to the pause-menu while it is animating the camera zoom.
	if not zoom.is_equal_approx(Vector2.ONE):
		return

	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return
	var p : Vector2 = (players[0] as Node2D).global_position

	## Player displacement from the fixed screen centre, with deadzone subtracted.
	## Inside the deadzone box, target stays at current offset → camera holds.
	var dx := p.x - SCREEN_W * 0.5
	var dy := p.y - SCREEN_H * 0.5
	dx = _apply_deadzone(dx, deadzone_half_size.x)
	dy = _apply_deadzone(dy, deadzone_half_size.y)

	## Clamp so the viewport never reveals world outside the 740 × 740 area.
	var target : Vector2 = Vector2(
		clamp(dx, -H_LIMIT, H_LIMIT),
		clamp(dy, -V_LIMIT, V_LIMIT)
	)

	_follow_offset = _follow_offset.lerp(target, minf(follow_speed * delta, 1.0))
	offset = _follow_offset + CameraShake.get_offset()

	## Anchor every background CanvasLayer to world space.  Shake is excluded
	## so the background doesn't jitter when the screen shakes.
	for cl in _bg_layers:
		cl.offset = -_follow_offset


## Deadzone helper: returns 0 if |value| < half_size, otherwise the value
## reduced by the deadzone half-size (so target = 0 exactly at the edge).
static func _apply_deadzone(value: float, half_size: float) -> float:
	if absf(value) <= half_size:
		return 0.0
	return value - signf(value) * half_size
