## The wreck scene for a dying ship's size (plan §2.8, §2.10). Static; `BaseEnemy._maybe_leave_wreck()` calls it from the
## death hook.
class_name WreckScenes
extends RefCounted

enum Size { SMALL, MEDIUM, LARGE }

const _INERT: Array[PackedScene] = [
	preload("res://assault/scenes/hazards/wreck/wreck_small.tscn"),
	preload("res://assault/scenes/hazards/wreck/wreck_medium.tscn"),
	preload("res://assault/scenes/hazards/wreck/wreck_large.tscn"),
]
## One explosive wreck for every size.
const _EXPLOSIVE: PackedScene = preload("res://assault/scenes/hazards/wreck/wreck_explosive.tscn")


## The scene for [param size] (a `Size`), or null for an unknown size. [param explosive] returns the explosive wreck.
static func scene_for(size: int, explosive: bool) -> PackedScene:
	if size < 0 or size >= _INERT.size():
		return null
	return _EXPLOSIVE if explosive else _INERT[size]
