## ExplosionEffect — large one-shot particle burst spawned when an entity dies.
## Add as a child Node of any entity (enemy, ally, player, boss).
## Call explode() just before the entity calls queue_free().
##
## Particles are spawned directly into the entity's parent container so they
## survive after the entity is freed.
##
## Configure via @export properties before add_child() so values are set in time.
class_name ExplosionEffect
extends Node2D

@export_group("Particles")
@export var amount: int = 22
@export var lifetime: float = 0.5
@export var color: Color = Color(1.0, 0.5, 0.1)
@export var min_velocity: float = 60.0
@export var max_velocity: float = 200.0
@export var min_scale: float = 2.0
@export var max_scale: float = 4.5

@export_group("Behaviour")
## When true the burst renders even while the scene tree is paused.
## Enable for the player death explosion so it shows on the game-over screen.
@export var always_process: bool = false

## Spawn the explosion at the parent entity's current world position.
func explode() -> void:
	var actor := get_parent() as Node2D
	if not actor:
		return
	var container := actor.get_parent()
	if not container:
		return

	var p := CPUParticles2D.new()
	p.global_position = actor.global_position
	if always_process:
		p.process_mode = Node.PROCESS_MODE_ALWAYS
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = amount
	p.lifetime = lifetime
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = min_velocity
	p.initial_velocity_max = max_velocity
	p.scale_amount_min = min_scale
	p.scale_amount_max = max_scale
	p.color = color
	container.add_child(p)
	p.finished.connect(p.queue_free)
