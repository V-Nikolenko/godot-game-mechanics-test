## HitEffect — one-shot particle burst played each time an entity takes damage.
## Add as a child Node of any entity (enemy, ally, player, boss).
## Call burst() from the entity's damage handler.
##
## Configure via @export properties before add_child() so _ready() reads them.
class_name HitEffect
extends Node2D

@export_group("Particles")
@export var amount: int = 10
@export var lifetime: float = 0.25
@export var color: Color = Color(1.0, 0.35, 0.1)
@export var min_velocity: float = 40.0
@export var max_velocity: float = 100.0
@export var min_scale: float = 1.5
@export var max_scale: float = 3.0

var _particles: CPUParticles2D

func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.amount = amount
	_particles.lifetime = lifetime
	_particles.direction = Vector2(0.0, -1.0)
	_particles.spread = 180.0
	_particles.initial_velocity_min = min_velocity
	_particles.initial_velocity_max = max_velocity
	_particles.scale_amount_min = min_scale
	_particles.scale_amount_max = max_scale
	_particles.color = color
	add_child(_particles)

## Trigger a burst at the parent entity's current position.
func burst() -> void:
	_particles.restart()
