# open_space/scenes/entities/player/open_space_camera_rig.gd
## Owns the speed-zoom + camera-lead computation behind the ship's `speed_feel` camera
## effect. A pure `step()`/`get_offset()`/`get_zoom()`, resolved by TYPE from
## `player_ship.gd::_ready()` exactly like `_turn` and `_boost_meter`.
##
## Lives beside the ship rather than inline in `_update_camera_feel()` because the camera
## itself does not: `Camera2D` is a child of `PlayerShip` in `sector_hub.tscn`, not in
## `player_ship.tscn`, so every headless test that instantiates the ship scene alone takes
## `_update_camera_feel()`'s early return and never reaches the formula. A node with a pure
## step is drivable and assertable without a camera at all — the same shape that made
## `ShipTurnController` testable.
##
## Fixes the epic's headline bug: the old formula took its magnitude from `velocity` but
## its direction from the hull's FACING (`Vector2.UP.rotated(rotation)`), so turning the
## nose away from the ship's momentum swung the lead the WRONG way — opposite to travel.
## Direction here comes from `velocity`, never from `rotation`.
class_name OpenSpaceCameraRig
extends Node

## Seconds of travel to lead the camera by. raw = velocity * lookahead_time.
@export var lookahead_time: float = 0.30
## Hard cap on the lead distance, in px.
@export var lead_max_px: float = 90.0
## Raw lead under this many px reads as zero. SUBTRACTED, not clipped, so the applied lead
## grows continuously from the edge of the dead zone instead of popping from 0 to the
## dead-zone radius the instant the ship crosses it.
@export var lead_dead_zone_px: float = 32.0
## Half-life (seconds) of the exponential smoothing on the lead vector. Separate from
## CameraDirector.blend_speed, which handles hand-off between effects, not this smoothing.
@export var lead_half_life: float = 0.20
## Zoom level at/above zoom_speed_threshold.
@export var zoom_min: float = 0.85
## Speed (px/s) at which the zoom reaches zoom_min.
@export var zoom_speed_threshold: float = 400.0
## Extra pull-back applied to the zoom target while boosting (FLY-2).
@export var boost_zoom_bonus: float = 0.06

## The smoothed, applied lead. What get_offset() returns (scaled by _motion_scale).
var _lead: Vector2 = Vector2.ZERO
## Accessibility scale from SettingsState.camera_motion (CAM-2): 1.0 / 0.5 / 0.0.
var _motion_scale: float = 1.0
var _boosting: bool = false


## Advances the smoothed lead toward the raw lead computed from velocity. Direction is
## velocity.normalized() — never rotation — which is the bug fix this rig exists for.
func step(velocity: Vector2, delta: float) -> void:
	var raw: Vector2 = velocity * lookahead_time
	var mag: float = raw.length()
	if mag <= lead_dead_zone_px:
		raw = Vector2.ZERO
	else:
		raw = raw.normalized() * minf(mag - lead_dead_zone_px, lead_max_px)
	var k: float = 1.0 - exp(-log(2.0) / maxf(lead_half_life, 0.0001) * delta)
	_lead = _lead.lerp(raw, k)


## The camera-lead offset to push into CameraDirector.set_effect().
func get_offset() -> Vector2:
	return _lead * _motion_scale


## The zoom target to push into CameraDirector.set_effect().
func get_zoom(velocity: Vector2) -> Vector2:
	var t: float = clampf(velocity.length() / zoom_speed_threshold, 0.0, 1.0)
	var target: float = zoom_min - (boost_zoom_bonus if _boosting else 0.0)
	return Vector2.ONE * lerpf(1.0, lerpf(1.0, target, t), _motion_scale)


func set_motion_scale(scale: float) -> void:
	_motion_scale = scale


## PUBLIC, and load-bearing for FLY-2: this rig owns the accessibility scale, but
## CameraShake.add() is called from the ship, outside the rig. Without a reader here,
## camera_motion = off would still shake the screen on every boost. Every automatic-motion
## channel in the epic routes its amplitude through this one number.
func get_motion_scale() -> float:
	return _motion_scale


func set_boosting(boosting: bool) -> void:
	_boosting = boosting
