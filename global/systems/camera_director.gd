## CameraDirector — owns a Camera2D and arbitrates between multiple "effects"
## that all want to drive its zoom / offset.
##
## Why this exists:
##   Open-space has at least four systems that want to control the camera:
##     1. Speed-zoom + camera lead (player_ship.gd)
##     2. Planet dwell zoom-in (mission_select_hub.gd)
##     3. Pause-menu zoom (pause_menu.gd, via direct tween)
##     4. Screen shake (CameraShake autoload)
##   Without arbitration, each system fights the others through ad-hoc
##   "step aside" guards that don't scale and break easily.
##
## Model (Cinemachine-inspired, simplified):
##   Each system pushes a NAMED effect with a target zoom, target offset,
##   and a priority. Each frame the director picks the highest-priority
##   effect, smoothly blends the camera toward it, and adds shake on top.
##   Clearing an effect (when its driving system goes idle) drops priority
##   back to the next effect, and the director blends smoothly to it — no
##   pop on hand-off.
##
## Usage from a system:
##   director.set_effect(&"speed_zoom",   zoom=0.85, offset=(0,-100), priority=0)
##   director.set_effect(&"planet_dwell", zoom=1.20, offset=(40,0),   priority=10)
##   director.clear_effect(&"planet_dwell")   ## hub takes itself out
##
## Pause-menu integration:
##   Pause-menu still uses its own tween directly on the camera (it has
##   different needs — it animates global_position too, and runs while the
##   tree is paused). The director writes camera.zoom + camera.offset
##   every frame, so when the pause menu opens it sets process_mode = DISABLED
##   on this director, letting its tween run unmolested.

class_name CameraDirector
extends Node

## Default blend speed (lerp weight / second) for smoothing between effects.
## Higher = snappier hand-offs; lower = gentler.
@export var blend_speed : float = 6.0

## NodePath to the Camera2D this director controls. Defaults to a sibling.
@export var camera_path : NodePath = NodePath("..")

var _camera : Camera2D = null

## name(StringName) → { priority: int, zoom: Vector2, offset: Vector2 }
var _effects : Dictionary = {}

## The actually-applied (post-blend) state. Initialised from current camera.
var _applied_zoom   : Vector2 = Vector2.ONE
var _applied_offset : Vector2 = Vector2.ZERO


func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera2D
	if _camera != null:
		_applied_zoom   = _camera.zoom
		_applied_offset = _camera.offset


## Push or update an effect by name. Higher priority overrides lower.
## Use a stable name per system (e.g. &"speed_zoom") so subsequent calls
## update the same slot rather than stacking.
func set_effect(name: StringName, zoom: Vector2, offset: Vector2, priority: int = 0) -> void:
	_effects[name] = {
		"priority": priority,
		"zoom":     zoom,
		"offset":   offset,
	}


## Remove an effect — director blends down to the next-highest priority.
func clear_effect(name: StringName) -> void:
	_effects.erase(name)


func _process(delta: float) -> void:
	if _camera == null:
		return

	## External-write detection: if camera.zoom no longer matches our last
	## applied value, some other system is driving the camera directly
	## (e.g. pause-menu tween that animates zoom + global_position together
	## while the tree is paused). We resync from the camera's current state
	## and skip this frame, so the external animator has unmolested control.
	## When it finishes and stops writing, our applied state already matches
	## the camera so we resume seamlessly with no pop.
	if not _camera.zoom.is_equal_approx(_applied_zoom):
		_applied_zoom   = _camera.zoom
		_applied_offset = _camera.offset
		return

	## Find the active (highest-priority) effect, or fall back to defaults.
	var target_zoom   : Vector2 = Vector2.ONE
	var target_offset : Vector2 = Vector2.ZERO
	var max_priority  : int     = -1
	for eff: Dictionary in _effects.values():
		if eff.priority > max_priority:
			max_priority  = eff.priority
			target_zoom   = eff.zoom
			target_offset = eff.offset

	## Blend from currently-applied state toward the active target.
	## This is what removes the pop on hand-off between effects.
	var k : float = minf(blend_speed * delta, 1.0)
	_applied_zoom   = _applied_zoom.lerp(target_zoom, k)
	_applied_offset = _applied_offset.lerp(target_offset, k)

	## Shake is composed on top — it shouldn't smear into the blend.
	_camera.zoom   = _applied_zoom
	_camera.offset = (_applied_offset + CameraShake.get_offset()).round()
