## TurretMountScenes - one scene per `TurretMount.Variant` and their authored exports (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7;
## the `EnemyBeamScenes` shape). Weapon tuning lives in these scenes, so gates read it through `export_of()` and never type a number.
class_name TurretMountScenes
extends RefCounted

const BURST_CANNON: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/burst_cannon_mount.tscn")
const SWEEP_BEAM: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/sweep_beam_mount.tscn")
const LANCE: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/lance_mount.tscn")
const BEAM_CANNON: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/beam_cannon_mount.tscn")
const ROCKET_BATTERY: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/rocket_battery_mount.tscn")
const PULSE_RING: PackedScene = preload("res://assault/scenes/enemies/defense_turret/mounts/pulse_ring_mount.tscn")


## The mount scene for [param variant], or null with no error while that variant is not built yet (every variant is built as of t8),
## so a caller can sweep "every built variant".
static func scene_for(variant: int) -> PackedScene:
	match variant:
		TurretMount.Variant.BURST_CANNON:
			return BURST_CANNON
		TurretMount.Variant.SWEEP_BEAM:
			return SWEEP_BEAM
		TurretMount.Variant.LANCE:
			return LANCE
		TurretMount.Variant.BEAM_CANNON:
			return BEAM_CANNON
		TurretMount.Variant.ROCKET_BATTERY:
			return ROCKET_BATTERY
		TurretMount.Variant.PULSE_RING:
			return PULSE_RING
	return null


## `property` as [param variant]'s mount scene authors it on the node at [param node_path] (the root by default), read without instantiating the
## scene; [param fallback] (pass the script default) when the scene leaves it unset or the variant has no scene.
static func export_of(variant: int, property: StringName, fallback: Variant, node_path: NodePath = ^".") -> Variant:
	return EnemyBeamScenes.export_of_scene(scene_for(variant), property, fallback, node_path)
