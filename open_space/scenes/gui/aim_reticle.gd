## AimReticle — the ring drawn on the hull that shows what the aim is actually doing.
##
## AimCursor is the precise aim POINT (a hardware cursor, one frame faster than anything
## drawn); this is the STATE around it — the dead zone, the gap between where the nose is
## going and where it currently points, and whether an assist is overriding the player's own
## input. Finding 6 (`2-research.md`) is explicit that assists must be VISIBLE, because
## invisible auto-aim "created problematic gaps between input and display".
##
## top_level, drawn with _draw() primitives in the BoostBar / OverheatBar idiom: it stores
## what it draws as members (set then queue_redraw()), because a _draw()-only node exposes
## nothing a headless test can assert on.
##
## FED, never reading: the ship's player_ship.gd::_handle_rotation is the one place the
## mouse is read project-wide, and it calls set_aim() with what ShipTurnController already
## computed. This node touches no Input.
##
## `top_level` reinterprets local coordinates as global, so the ship must reassign
## `global_position` every physics frame (same as BoostBar/OverheatBar) — otherwise the ring
## sits at world origin instead of on the hull.
class_name AimReticle
extends Node2D

enum AimState { NORMAL, SNAP, DISABLED }

const _RADIUS_FALLBACK: float = 0.0
const _ARC_POINTS: int = 48
const _TICK_WIDTH: float = 2.0
const _TICK_INNER: float = 0.72  ## fraction of the ring radius the tick starts at
const _TICK_OUTER: float = 1.28  ## fraction of the ring radius the tick ends at

const _COLOR_NORMAL: Color   = Color(0.35, 0.9, 1.0, 0.85)   ## matches AimCursor's cyan
const _COLOR_SNAP: Color     = Color(1.0, 0.85, 0.2, 0.9)    ## an assist is overriding aim
const _COLOR_DISABLED: Color = Color(0.6, 0.6, 0.6, 0.45)    ## steering frozen (focus lost)

var _ring_radius: float = _RADIUS_FALLBACK
var _target_angle: float = 0.0
var _hull_angle: float = 0.0
var _state: AimState = AimState.NORMAL

## True unless the &"keys" scheme (no cursor aiming to call out) hides the ring outright.
var _scheme_visible: bool = true


func _ready() -> void:
	top_level = true


## The ship's own physics may be off (the mission-menu freeze) while this node's _process
## keeps running — set_physics_process(false) on the parent does not stop a child's own
## processing. Polling here, rather than trusting the ship to hide us, is what keeps the
## ring from being left mid-swing behind the menu (plan review R2-N6).
func _process(_delta: float) -> void:
	_refresh_visibility()


func _refresh_visibility() -> void:
	var parent := get_parent()
	var physics_on: bool = parent == null or parent.is_physics_processing()
	visible = _scheme_visible and physics_on


## Stores what _draw() needs. ring_radius is read from ShipTurnController.mouse_dead_zone_px
## by the caller — never duplicated as a constant here.
func set_aim(ring_radius: float, target_angle: float, hull_angle: float,
		snap_held: bool, steering_enabled: bool) -> void:
	_ring_radius = ring_radius
	_target_angle = target_angle
	_hull_angle = hull_angle
	_state = AimState.DISABLED if not steering_enabled \
			else (AimState.SNAP if snap_held else AimState.NORMAL)
	queue_redraw()


## Hides the ring under the &"keys" scheme, where there is no cursor aiming to call out.
## Applied immediately (not left to wait for the next _process()) so a ship that never gets
## an idle frame in a test still reports the right visibility right after _ready().
func set_scheme_visible(scheme_visible: bool) -> void:
	_scheme_visible = scheme_visible
	_refresh_visibility()


## Testable seam onto the colour _draw() would use, without instantiating a canvas.
func ring_color() -> Color:
	match _state:
		AimState.SNAP:
			return _COLOR_SNAP
		AimState.DISABLED:
			return _COLOR_DISABLED
		_:
			return _COLOR_NORMAL


func _draw() -> void:
	if _ring_radius <= 0.0:
		return
	var color: Color = ring_color()
	draw_arc(Vector2.ZERO, _ring_radius, 0.0, TAU, _ARC_POINTS, color, 1.5)
	## The hull tick: where the nose actually points right now.
	_draw_tick(_hull_angle, color)
	## The target tick: where the nose is chasing. The gap between the two ticks is the
	## inertial lag ShipTurnController deliberately builds, made visible.
	_draw_tick(_target_angle, color.lightened(0.35))


func _draw_tick(angle: float, color: Color) -> void:
	## Vector2.UP is "forward" in this project's convention (ship_turn_controller.gd), so an
	## angle of 0 draws straight up, matching the hull's own facing at rotation == 0.
	var dir: Vector2 = Vector2.UP.rotated(angle)
	draw_line(dir * _ring_radius * _TICK_INNER, dir * _ring_radius * _TICK_OUTER,
			color, _TICK_WIDTH)
