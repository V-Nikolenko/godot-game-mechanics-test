## open_space/scenes/entities/interactables/mission_config_resource.gd
class_name MissionConfigResource
extends Resource

## Per-mission configuration injected into Planet at runtime.

@export var display_name: String = ""
## Full res:// path to the target scene, e.g. "res://assault/scenes/levels/level_1.tscn"
@export var scene_path: String = ""
## Unique string key used to read/write progress in MissionState.
@export var mission_id: String = ""
## If non-empty, this mission is locked until the named mission_id is complete.
@export var required_mission: String = ""
