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

## Spawn the explosion at the parent entity's current world position, or at [param at]
## when one is given.
##
## [param at] (a Vector2, or null/omitted) exists for entities whose death is a CHAIN of
## blasts across a large hull rather than one burst at the centre — StationDeathSequence.
## Omitting it preserves the historic behaviour exactly, so every existing caller is
## unaffected.
##
## NOTE the particles are still parented to `actor.get_parent()` regardless of [param at]:
## `at` moves the blast, it does not re-home it. An ExplosionEffect must therefore be a
## child of the ENTITY (as base_enemy.gd:32-33 does), not of one of the entity's own
## behaviour nodes — one hop too deep and the particles land inside the entity, where they
## are freed with it and inherit its rotation.
func explode(at: Variant = null) -> void:
	var actor := get_parent() as Node2D
	if not actor:
		return
	var container := actor.get_parent()
	if not container:
		return

	var p := CPUParticles2D.new()
	## Direct typed assignment — `at as Vector2` is invalid on built-in value types in
	## GDScript 4 and would silently return null, i.e. a blast at the origin with no error.
	## Same trap wave_manager.gd:137 and :170-171 document.
	if at is Vector2:
		var pos: Vector2 = at
		p.global_position = pos
	else:
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
