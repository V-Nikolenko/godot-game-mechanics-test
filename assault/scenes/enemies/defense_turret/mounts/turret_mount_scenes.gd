## TurretMountScenes - one scene per `TurretMount.Variant` and their authored exports (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7;
## the `EnemyBeamScenes` shape). Weapon tuning lives in these scenes, so gates read it through `export_of()` and never type a number.
class_name TurretMountScenes
extends RefCounted

const BURST_CANNON: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/burst_cannon_mount.tscn")


## The mount scene for [param variant], or null with no error while that variant is not built yet (the other variants arrive in later tasks),
## so a caller can sweep "every built variant".
static func scene_for(variant: int) -> PackedScene:
	match variant:
		TurretMount.Variant.BURST_CANNON:
			return BURST_CANNON
	return null


## `property` as [param variant]'s mount scene authors it on the node at [param node_path] (the root by default), read without instantiating the
## scene; [param fallback] (pass the script default) when the scene leaves it unset or the variant has no scene.
static func export_of(variant: int, property: StringName, fallback: Variant, node_path: NodePath = ^".") -> Variant:
	return EnemyBeamScenes.export_of_scene(scene_for(variant), property, fallback, node_path)
