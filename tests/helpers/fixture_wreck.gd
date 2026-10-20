## A duck-typed wreck for avoidance and cover tests (the real `Wreck` is a later Phase 6 task): a plain
## `Node2D` that answers `hazard_info()` with a line-of-sight-blocking, claimable `HazardInfo` and joins the
## `Hazards` registry while in the tree. No body, no collision: it exercises the avoidance stage only.
##
## No `class_name`: test-only. Preload it:
##     const FIXTURE_WRECK := preload("res://tests/helpers/fixture_wreck.gd")
extends Node2D

var info := HazardInfo.new()


func _init() -> void:
	info.kind = &"wreck"
	info.avoid_weight = 0.6
	info.line_of_sight_blocker = true
	info.source = self


func hazard_info() -> HazardInfo:
	info.position = global_position
	return info


func _enter_tree() -> void:
	Hazards.register(self)


func _exit_tree() -> void:
	Hazards.unregister(self)
