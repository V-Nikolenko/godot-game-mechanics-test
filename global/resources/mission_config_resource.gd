## global/resources/mission_config_resource.gd
class_name MissionConfigResource
extends Resource

## Per-mission data. Create one .tres per mission, add to PlanetConfigResource.missions[].

## Displayed in the mission list and info panel.
@export var display_name: String = ""
## Full res:// path to the scene to load when this mission is launched.
@export var scene_path: String = ""
## Unique key used by MissionState to track completion.
@export var mission_id: String = ""
## If non-empty, this mission is locked until the named mission_id is completed.
@export var required_mission: String = ""
## Determines the icon shown in the list row. "assault" | "infiltration"
@export_enum("assault", "infiltration") var mission_type: String = "assault"
## Texture shown in the preview image panel when this row is selected in the menu.
@export var mission_image: Texture2D = null
## One- or two-sentence description shown in the info panel when this mission is selected.
@export_multiline var description: String = ""
## Global mission number shown in the list and on the planet map point (01, 02, 03...).
## Set this manually across all planets so numbers form one continuous sequence.
@export var mission_number: int = 0
