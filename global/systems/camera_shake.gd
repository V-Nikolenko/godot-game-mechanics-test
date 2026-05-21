## CameraShake — global screen-shake autoload.
##
## Trauma model (Squirrel Eiserloh, GDC "Math for Game Programmers: Juicing
## Your Cameras With Math"):
##   • Any system calls add(amount) to inject trauma in [0, 1].
##   • Trauma decays linearly each frame.
##   • The visible shake is (trauma^2) * max_offset — quadratic so small
##     trauma is barely visible while large trauma reads as "screen-rattle".
##
## Usage from any system:
##   CameraShake.add(0.4)           ## light hit
##   CameraShake.add(0.7)           ## explosion
##   CameraShake.add(1.0)           ## boss death / big impact
##
## Usage from a Camera2D:
##   offset += CameraShake.get_offset()
##
## Registered as an autoload in project.godot.
extends Node

## Maximum shake offset in pixels when trauma == 1.
const _MAX_OFFSET : float = 8.0
## Trauma units lost per second.  Default = 1.5 → full trauma decays in ~0.67 s.
const _DECAY     : float = 1.5

var _trauma : float = 0.0


## Inject trauma.  Saturates at 1.0 — stacking multiple shakes never exceeds
## the visual cap, so spam-clicking a hit button can't blow out the screen.
func add(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


func _process(delta: float) -> void:
	if _trauma > 0.0:
		_trauma = maxf(_trauma - _DECAY * delta, 0.0)


## Returns the current shake offset.  Callers add this on top of their camera's
## final offset every frame.  Quadratic curve makes light shake almost invisible
## while keeping room for dramatic kicks.
func get_offset() -> Vector2:
	if _trauma <= 0.0:
		return Vector2.ZERO
	var t : float = _trauma * _trauma
	return Vector2(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0)
	) * _MAX_OFFSET * t
