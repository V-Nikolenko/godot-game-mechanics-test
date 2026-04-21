## RocketTrail — continuous fire trail for rockets/missiles.
## Add as a child Node of any rocket scene (homing_missile, warhead_missile, etc.).
## Particles emit in local-down direction with local_coords=false so they stay
## in world space as the rocket moves, forming a visible trail behind it.
## Configure via @export properties before add_child() so _ready() reads them.
class_name RocketTrail
extends Node2D

@export_group("Particles")
@export var amount: int = 18
@export var lifetime: float = 0.28
## Offset along local +Y (behind the rocket nose).
@export var offset_behind: float = 8.0

var _particles: CPUParticles2D

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

	# Gradient: bright yellow at birth → transparent orange at death.
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.3, 1.0))
	grad.set_color(1, Color(1.0, 0.25, 0.0, 0.0))
	_particles.color_ramp = grad

	add_child(_particles)
