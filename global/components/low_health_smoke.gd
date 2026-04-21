## LowHealthSmoke — continuous smoke/wisps that stream upward when HP is low.
## Add as a child Node of any entity (enemy, ally, player, boss).
## Call setup(health_node) after add_child() to connect it to the Health component.
##
## The smoke activates automatically when HP falls to or below `threshold` of
## max HP, and deactivates automatically when HP rises back above it or reaches 0.
class_name LowHealthSmoke
extends Node2D

@export_group("Behaviour")
## Fraction of max HP at which smoke starts (0.3 = 30 %).
@export_range(0.0, 1.0, 0.01) var threshold: float = 0.3

@export_group("Particles")
@export var amount: int = 10
@export var color: Color = Color(0.55, 0.55, 0.55, 0.85)
@export var min_velocity: float = 15.0
@export var max_velocity: float = 45.0
## Radius of the sphere from which smoke wisps originate (spread across the sprite).
@export var emission_radius: float = 5.0

var _particles: CPUParticles2D
var _health: Health

func _ready() -> void:
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = false
	_particles.explosiveness = 0.0
	_particles.amount = amount
	_particles.lifetime = 0.7
	_particles.direction = Vector2(0.0, -1.0)
	_particles.spread = 40.0
	_particles.initial_velocity_min = min_velocity
	_particles.initial_velocity_max = max_velocity
	_particles.scale_amount_min = 1.0
	_particles.scale_amount_max = 2.5
	_particles.color = color
	_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_particles.emission_sphere_radius = emission_radius
	add_child(_particles)

## Connect to a Health component so the smoke reacts to HP changes automatically.
## Call this after the component has been added to the scene tree.
func setup(health: Health) -> void:
	_health = health
	_health.amount_changed.connect(_on_health_changed)

## Immediately stop the smoke (e.g. called just before a death explosion).
func deactivate() -> void:
	_particles.emitting = false

func _on_health_changed(current: int) -> void:
	if not _health:
		return
	var pct := float(current) / float(_health.max_health)
	_particles.emitting = pct <= threshold and current > 0
