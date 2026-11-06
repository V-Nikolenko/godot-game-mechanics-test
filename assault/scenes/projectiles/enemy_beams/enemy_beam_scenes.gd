## EnemyBeamScenes - the energy-weapon family's scenes and their exports (the `EnemyMineScenes` shape)
## (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.1; task t2). Weapon tuning lives in these scene exports, so gates read numbers
## through `export_of()` and never type them.
class_name EnemyBeamScenes
extends RefCounted

const BEAM: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/beam.tscn")
const SWEEP: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/sweep_beam.tscn")
const LANCE: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/lance.tscn")
## The endpoint beam (`set_endpoints()` every tick): the twin pair's and the laser fence's.
const TWIN: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/twin_beam.tscn")
## The Pulse Ring (`EnergyRing`; not an `EnemyBeam.Kind`: that enum is append-only and the ring is its own class).
const RING: PackedScene = preload("res://assault/scenes/projectiles/enemy_beams/energy_ring.tscn")


## The scene for [param kind], or null with no error for a kind that has no scene, so a
## caller can sweep "every built kind".
static func scene_for(kind: EnemyBeam.Kind) -> PackedScene:
	match kind:
		EnemyBeam.Kind.BEAM:
			return BEAM
		EnemyBeam.Kind.SWEEP:
			return SWEEP
		EnemyBeam.Kind.LANCE:
			return LANCE
		EnemyBeam.Kind.TWIN:
			return TWIN
	return null


## The Pulse Ring's scene.
static func ring_scene() -> PackedScene:
	return RING


## `export_of` for the Pulse Ring's scene.
static func ring_export(property: StringName, fallback: Variant, node_path: NodePath = ^".") -> Variant:
	return export_of_scene(RING, property, fallback, node_path)


## `property` as [param kind]'s scene authors it on the node at [param node_path] (the root by default), read through
## `PackedScene.get_state()` without instantiating the scene; [param fallback] (pass the script default) when the scene leaves it unset
## or the kind has no scene.
static func export_of(kind: EnemyBeam.Kind, property: StringName, fallback: Variant, node_path: NodePath = ^".") -> Variant:
	return export_of_scene(scene_for(kind), property, fallback, node_path)


## `export_of` for any beam scene, so a gate's boundary case can run the same predicate on a synthetic copy.
static func export_of_scene(scene: PackedScene, property: StringName, fallback: Variant, node_path: NodePath = ^".") -> Variant:
	if scene == null:
		return fallback
	# `SceneState` spells a child's path `./Child`.
	var want := String(node_path)
	if want != "." and not want.begins_with("./"):
		want = "./" + want
	var state := scene.get_state()
	for n in state.get_node_count():
		if String(state.get_node_path(n)) != want:
			continue
		for i in state.get_node_property_count(n):
			if state.get_node_property_name(n, i) == property:
				return state.get_node_property_value(n, i)
		return fallback
	return fallback
