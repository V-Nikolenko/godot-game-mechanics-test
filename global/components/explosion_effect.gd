## ExplosionEffect — large one-shot particle burst spawned when an entity dies.
## Add as a child Node of any entity (enemy, ally, player, boss).
## Call explode() just before the entity calls queue_free().
##
## Particles are spawned directly into a container (the actor's parent by default, or an
## explicit one) so they survive after the entity is freed.
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
## when one is given, inside [param container] (or the actor's parent when omitted).
##
## [param at] (a Vector2, or null/omitted) exists for entities whose death is a CHAIN of
## blasts across a large hull rather than one burst at the centre — StationDeathSequence.
## Omitting it preserves the historic behaviour exactly, so every existing caller is
## unaffected. [param at] moves the blast; it never re-homes it.
##
## [param container] lets a caller whose actor's parent is not a safe home (an entity that
## is itself freed with a larger wreck, for instance) say so explicitly. A null, freed, or
## detached container falls back to the actor's parent.
##
## The actor is resolved by walking up from this node's parent to the nearest Node2D
## ancestor, not by a fixed hop count, so an ExplosionEffect may sit under an intermediate
## non-Node2D node (DamageReaction) without losing its position.
func explode(at: Variant = null, container: Node = null) -> void:
	var actor := _nearest_node2d()
	if not actor:
		## Not get_path(): this can legitimately fire before the effect has ever entered a
		## tree, and get_path() on a node outside the tree pushes its own engine error.
		push_warning("%s: no Node2D ancestor found; explosion suppressed" % self)
		return

	var target := container
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		target = actor.get_parent()
	if not target:
		return

	var p := CPUParticles2D.new()
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

	## Parent BEFORE setting global_position: a parentless Node2D has no parent CanvasItem,
	## so global_position on an out-of-tree node is just position, and target.add_child()
	## would then re-apply the container's transform on top of an already-world coordinate.
	target.add_child(p)
	## Direct typed assignment — `at as Vector2` is invalid on built-in value types in
	## GDScript 4 and would silently return null, i.e. a blast at the origin with no error.
	## Same trap wave_manager.gd:137 and :170-171 document.
	if at is Vector2:
		var pos: Vector2 = at
		p.global_position = pos
	else:
		p.global_position = actor.global_position
	p.finished.connect(p.queue_free)


## Walks up from this node's parent to the nearest Node2D ancestor. Needed because an
## ExplosionEffect can sit one hop deeper than its actor, under a non-Node2D behaviour node
## (DamageReaction extends Node) — a fixed single-hop cast would silently find nothing there.
func _nearest_node2d() -> Node2D:
	var n := get_parent()
	while n != null:
		if n is Node2D:
			return n
		n = n.get_parent()
	return null
