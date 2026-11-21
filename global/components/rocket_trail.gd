## RocketTrail — continuous fire trail for rockets/missiles.
## Add as a child Node of any rocket scene (homing_missile, warhead_missile, etc.).
## Particles emit in local-down direction with local_coords=false so they stay
## in world space as the rocket moves, forming a visible trail behind it.
## Configure via @export properties before add_child() so _ready() reads them.
## `set_colors()` recolours it at any time (a hijacked homing rocket's amber tell, Phase 9 §2.5).
class_name RocketTrail
extends Node2D

@export_group("Particles")
@export var amount: int = 18
@export var lifetime: float = 0.14
## Offset along local +Y (behind the rocket nose).
@export var offset_behind: float = 8.0

var _particles: CPUParticles2D
var _birth: Color = Color(1.0, 0.95, 0.3, 1.0)
var _death: Color = Color(1.0, 0.25, 0.0, 0.0)

func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.position = Vector2(0.0, offset_behind)

	_particles.emitting = true
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.amount = amount
	_particles.lifetime = lifetime

	# local_coords = false: particles are emitted into world space and stay put
	# as the rocket moves forward, creating a persistent trail.
	_particles.local_coords = false

	# Local +Y = "behind" for a rocket whose nose points in local -Y (UP).
	_particles.direction = Vector2(0.0, 1.0)
	_particles.spread = 8.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 15.0
	_particles.initial_velocity_max = 40.0
	_particles.scale_amount_min = 2.5
	_particles.scale_amount_max = 5.0

	# Gradient: bright yellow at birth → transparent orange at death (unless set_colors() said otherwise).
	_particles.color_ramp = _ramp()

	add_child(_particles)


## Recolours the trail: [param birth] at emission, fading to [param death]. Before `_ready()` the colours are kept for it.
func set_colors(birth: Color, death: Color) -> void:
	_birth = birth
	_death = death
	if _particles != null:
		_particles.color_ramp = _ramp()


## The colour a particle is born with, read from the live ramp once the particles exist.
func birth_color() -> Color:
	if _particles != null and _particles.color_ramp != null:
		return _particles.color_ramp.get_color(0)
	return _birth


func _ramp() -> Gradient:
	var grad := Gradient.new()
	grad.set_color(0, _birth)
	grad.set_color(1, _death)
	return grad
