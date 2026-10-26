## EnemyMineScenes - the mine family's scenes and pool sizing (the `EnemyRocketScenes` shape).
## See docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.1.
class_name EnemyMineScenes
extends RefCounted

## The Bomber's mine IS the PROXIMITY variant: the same path, so the same cached `PackedScene` as
## `EnemyOrdnanceScenes.MINE`.
const PROXIMITY: PackedScene = preload("res://assault/scenes/projectiles/enemy_ordnance/mine.tscn")


## The scene for [param variant], or null while that variant's scene is not built yet (so a caller can sweep
## "every built variant").
static func scene_for(variant: EnemyMine.Variant) -> PackedScene:
	match variant:
		EnemyMine.Variant.PROXIMITY:
			return PROXIMITY
	return null


## Pooled mines a layer needs for [param variant], duck-typed on `cfg.max_live_mines` and the flat weights
## `w_<variant>` (missing = 0): PROXIMITY `max_live_mines + 2`; any other variant with weight > 0
## `ceil(max_live_mines * w / sum of weights) + 2`; weight 0 -> 0 (the pool is not built).
static func pool_size_for(variant: EnemyMine.Variant, cfg) -> int:
	var cap := int(cfg.max_live_mines)
	if variant == EnemyMine.Variant.PROXIMITY:
		return cap + 2
	var w := _weight(cfg, variant)
	if w <= 0.0:
		return 0
	var total := 0.0
	for v: int in EnemyMine.Variant.values():
		total += _weight(cfg, v)
	return int(ceil(cap * w / total)) + 2


## `property` as [param variant]'s scene authors it on the node at [param node_path] (the root by default; e.g.
## `^"ProjectileLifetime"` for the backstop), read through `PackedScene.get_state()` without instantiating the
## scene; [param fallback] (pass the script default) when the scene leaves it unset or the variant has no scene.
static func export_of(variant: EnemyMine.Variant, property: StringName, fallback: Variant,
		node_path: NodePath = ^".") -> Variant:
	var scene := scene_for(variant)
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


static func _weight(cfg, variant: int) -> float:
	var key := "w_" + String(EnemyMine.Variant.keys()[variant]).to_lower()
	if not (key in cfg):
		return 0.0
	return float(cfg.get(key))
