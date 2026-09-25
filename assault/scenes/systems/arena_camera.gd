## assault/scenes/systems/arena_camera.gd
## Camera2D follow script for the 1480 × 1480 assault-mission play area.
##
## Follow strategy — Camera2D.offset, NOT global_position:
##   global_position stays permanently at the level origin (640, 360).
##   All player-follow panning is done through Camera2D.offset.
##   This keeps cam.global_position stable so:
##     • EnemyPathMover's cam-scroll delta (cam.global_position.y - initial)
##       is always 0 — enemies are never displaced by player panning.
##   Spawn positions (WaveManager, StationReinforcements, Level1Director's bonus drones) resolve
##   against cam.global_position + cam.offset — the camera's CURRENT view, not its resting
##   position — so a delayed spawn lands relative to wherever the player has panned to by the time
##   it fires, not the screen centre. (Prior to this, spawns resolved against global_position
##   alone, which a panned player could see land on screen — docs/plans/
##   a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr/.)
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
##   Horizontal ± 100 px  →  world x reachable: [-100, 1380]
##   Vertical  ± 380 px  →  world y reachable: [-380, 1100]
##
## Suspends offset tracking while camera zoom ≠ (1, 1) so the pause-menu zoom
## animation has exclusive control and the two systems never conflict.
class_name ArenaCamera
extends Camera2D

## Scale factor applied to all spawn offsets and EnemyPathMover movements.
## Keeps level_director spawn numbers in 640×360 "design units" that auto-scale.
const WORLD_SCALE : float = 2.0
const SCREEN_W : float = 1280.0
const SCREEN_H : float = 720.0
const H_LIMIT  : float = 100.0   ## Max horizontal offset (= horizontal buffer width).
const V_LIMIT  : float = 380.0   ## Max vertical offset   (= vertical buffer depth).

## Any ArenaCamera in the tree joins this group, which is how the mode-neutral enemy AI code in
## global/ (see global/enemy_ai/enemy_world.gd) tells an Assault arena apart from Open Space
## without ever naming this Assault-only class. Open Space has no node in this group.
const ARENA_GROUP : StringName = &"assault_arena"

## Margin added to the corridor's visible rect for a projectile's world bounds — reproduces
## today's EnemyBullet arena bounds exactly (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.9).
const _PROJECTILE_MARGIN : float = 64.0
## Margin added to the viewport half-size for the Drone Interceptor's legacy off-screen cull
## (drone_interceptor.gd's _check_off_screen, ported to a provider method in §2.5a/§2.11).
const _CULL_MARGIN : float = 80.0

## Lerp weight per second.  Higher = snappier follow; 1.0 per frame is the cap.
@export var follow_speed : float = 12.0
## Deadzone — half-extents of a rectangle around the framing point where small
## player movements do NOT move the camera.  Reduces wobble from minor
## adjustments.  Hollow Knight / Mario-style camera box.
@export var deadzone_half_size : Vector2 = Vector2(40.0, 30.0)

## The follow state, tracked separately from the final camera offset so that
## per-frame shake noise never pollutes the lerp baseline.  Final offset =
## _follow_offset + CameraShake.get_offset().
var _follow_offset : Vector2 = Vector2.ZERO
## Cached CanvasLayer children of Level1Background — all anchored to world
## space (factor 1.0) so the background reveals new texture as the camera pans.
var _bg_layers : Array[CanvasLayer] = []


func _ready() -> void:
	## Joined unconditionally, before the early return below — an ArenaCamera with no
	## Level1Background sibling (e.g. a bare instance in a test) is still a provider.
	add_to_group(ARENA_GROUP)

	var bg := get_parent().get_node_or_null("Level1Background")
	if bg == null:
		return
	for child in bg.get_children():
		if child is CanvasLayer:
			_bg_layers.append(child as CanvasLayer)


## The Assault corridor's projectile world bounds — the visible rect (see the class doc) grown by
## 64 px on every side. Equals today's EnemyBullet arena bounds exactly: x -164…1444, y -444…1164.
func projectile_world_rect() -> Rect2:
	return _visible_rect().grow(_PROJECTILE_MARGIN)


## The Drone Interceptor's legacy off-screen cull rect: this camera's global_position, ± half the
## viewport, ± 80 px (drone_interceptor.gd's _check_off_screen, before the §2.11 port).
func enemy_cull_rect() -> Rect2:
	var half : Vector2 = get_viewport().get_visible_rect().size * 0.5 + Vector2.ONE * _CULL_MARGIN
	return Rect2(global_position - half, half * 2.0)


## The corridor's visible rect: the pinned screen centre, ± half the viewport, ± the offset
## limits. A 1480×1480 world-space square (H_LIMIT + V_LIMIT both add to 740 past the half
## viewport on their axis) — see the class doc's "Offset limits".
func _visible_rect() -> Rect2:
	var pinned_centre := Vector2(SCREEN_W, SCREEN_H) * 0.5
	var half := Vector2(SCREEN_W * 0.5 + H_LIMIT, SCREEN_H * 0.5 + V_LIMIT)
	return Rect2(pinned_centre - half, half * 2.0)


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
