## The wreck scene for a dying ship's size (plan §2.8). Static; t11 calls it from the death hook, t12 adds the
## explosive variants (`explosive == true` returns null until then).
class_name WreckScenes
extends RefCounted

enum Size { SMALL, MEDIUM, LARGE }

const _INERT: Array[PackedScene] = [
	preload("res://assault/scenes/hazards/wreck/wreck_small.tscn"),
	preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn"),
	preload("res://assault/scenes/hazards/wreck/wreck_large.tscn"),
]


## The scene for [param size] (a `Size`), or null for an unknown size or an explosive wreck (t12).
static func scene_for(size: int, explosive: bool) -> PackedScene:
	if explosive or size < 0 or size >= _INERT.size():
		return null
	return _INERT[size]
