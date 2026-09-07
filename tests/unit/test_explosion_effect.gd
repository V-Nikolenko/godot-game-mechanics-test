## Unit tests for ExplosionEffect — the shared death-burst component. It resolves its OWN
## world position and its container node rather than being told either, so most of this file
## exercises that resolution rather than the particle look (untouched, see 3-plan.md's "Out of
## scope").
##
## Plan: `docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin/3-plan.md`.
## Every entity is parented under a container `Node2D` owned by `add_child_autofree`, per the
## `ExplosionEffect` rule in `tests/README.md` — a bare test-script parent leaves an unfreed
## `CPUParticles2D` behind for ~`lifetime` seconds.
extends GutTest


func _particles_in(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is CPUParticles2D:
			out.append(child)
	return out


## container(Node2D) -> actor(Node2D) -> fx(ExplosionEffect). The container carries the
## caller-supplied transform so tests can prove the fix works when it is not at identity.
func _build(container_position: Vector2 = Vector2.ZERO, container_rotation: float = 0.0) -> Dictionary:
	var container := Node2D.new()
	container.position = container_position
	container.rotation = container_rotation
	add_child_autofree(container)
	var actor := Node2D.new()
	container.add_child(actor)
	var fx := ExplosionEffect.new()
	actor.add_child(fx)
	return {"container": container, "actor": actor, "fx": fx}


func test_particles_are_not_children_of_the_effect() -> void:
	var b := _build()
	(b.fx as ExplosionEffect).explode()
	assert_eq(_particles_in(b.fx).size(), 0, "particles must not die with the actor's effect node")


func test_particles_land_in_the_actors_parent_by_default() -> void:
	var b := _build()
	(b.fx as ExplosionEffect).explode()
	assert_eq(_particles_in(b.container).size(), 1, "the container is the actor's parent by default")


func test_particles_spawn_at_the_actor_position() -> void:
	var b := _build()
	(b.actor as Node2D).global_position = Vector2(100, 40)
	(b.fx as ExplosionEffect).explode()
	var p := _particles_in(b.container)[0] as CPUParticles2D
	assert_eq(p.global_position, Vector2(100, 40))


## Fails before component change 0: the old code set global_position on the particle while it
## was still out of the tree, so a non-identity container's transform got applied on top of an
## already-world coordinate instead of never being applied at all.
func test_particles_land_at_the_actor_position_under_a_transformed_container() -> void:
	var b := _build(Vector2(300, 50), 0.7)
	(b.actor as Node2D).global_position = Vector2(700, 500)
	var expected: Vector2 = (b.actor as Node2D).global_position
	(b.fx as ExplosionEffect).explode()
	var p := _particles_in(b.container)[0] as CPUParticles2D
	assert_almost_eq(p.global_position, expected, Vector2(0.01, 0.01))


## Fails before component change 1: the DamageReaction shape (ExplosionEffect one hop deeper
## than its actor, under a plain Node behaviour node) made the old single-hop `get_parent() as
## Node2D` cast return null, silently suppressing the explosion.
func test_an_effect_under_a_non_node2d_parent_still_explodes() -> void:
	var container := Node2D.new()
	add_child_autofree(container)
	var ship := Node2D.new()
	container.add_child(ship)
	var behaviour := Node.new()
	ship.add_child(behaviour)
	var fx := ExplosionEffect.new()
	behaviour.add_child(fx)
	ship.global_position = Vector2(777, 222)

	fx.explode()

	var particles := _particles_in(container)
	assert_eq(particles.size(), 1, "the ship (nearest Node2D ancestor) is the actor")
	if particles.size() == 1:
		assert_eq((particles[0] as CPUParticles2D).global_position, Vector2(777, 222))


func test_an_explicit_container_overrides_the_default() -> void:
	var b := _build()
	var other := Node2D.new()
	add_child_autofree(other)
	(b.fx as ExplosionEffect).explode(null, other)
	assert_eq(_particles_in(other).size(), 1, "the explicit container is used instead of the default")
	assert_eq(_particles_in(b.container).size(), 0, "the default is not also used")


## An explicit container re-homes the blast; it does not move it. Uses a transformed explicit
## container so it also guards component change 0 on the explicit-container path.
func test_an_explicit_container_still_uses_the_actor_position() -> void:
	var b := _build()
	(b.actor as Node2D).global_position = Vector2(150, -60)
	var expected: Vector2 = (b.actor as Node2D).global_position
	var other := Node2D.new()
	other.position = Vector2(500, 20)
	other.rotation = 1.1
	add_child_autofree(other)

	(b.fx as ExplosionEffect).explode(null, other)

	var p := _particles_in(other)[0] as CPUParticles2D
	assert_almost_eq(p.global_position, expected, Vector2(0.01, 0.01))


## Pins the existing StationDeathSequence contract: `at` overrides where the blast lands, but
## never which node it lands in.
func test_the_at_argument_overrides_the_position_but_not_the_container() -> void:
	var b := _build()
	var other := Node2D.new()
	add_child_autofree(other)
	(b.fx as ExplosionEffect).explode(Vector2(999, 111), other)
	var p := _particles_in(other)[0] as CPUParticles2D
	assert_eq(p.global_position, Vector2(999, 111))


func test_a_null_or_detached_explicit_container_falls_back_to_the_default() -> void:
	var b := _build()
	var detached := Node2D.new()  ## never added to any tree
	(b.fx as ExplosionEffect).explode(null, detached)
	assert_eq(_particles_in(b.container).size(), 1, "falls back to the actor's parent")
	detached.free()


## Deliberately NOT added to the tree with add_child_autofree: the ancestor walk climbs past
## the test's own hierarchy if one exists, and the GUT test script itself sits under further
## Node2D ancestors (the runner scene) that would otherwise mask the missing-ancestor case this
## test exists to cover.
func test_an_effect_with_no_node2d_ancestor_warns_and_does_not_crash() -> void:
	var root := Node.new()
	var behaviour := Node.new()
	root.add_child(behaviour)
	var fx := ExplosionEffect.new()
	behaviour.add_child(fx)

	fx.explode()

	assert_push_warning("no Node2D ancestor", "the silent-suppression path must say why")
	assert_eq(_particles_in(root).size(), 0)
	assert_eq(_particles_in(behaviour).size(), 0)
	root.free()


## Guards research finding 3: `finished` only fires while `one_shot` is true, so a component
## that forgets to set it leaks every particle it ever spawns.
func test_the_particles_free_themselves_when_finished() -> void:
	var b := _build()
	var fx := b.fx as ExplosionEffect
	fx.lifetime = 0.05
	fx.explode()
	var p := _particles_in(b.container)[0] as CPUParticles2D
	await wait_seconds(0.3)
	assert_true(not is_instance_valid(p), "the particle frees itself once its burst finishes")
