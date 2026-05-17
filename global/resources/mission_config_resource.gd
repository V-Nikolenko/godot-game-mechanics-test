## global/resources/mission_config_resource.gd
class_name MissionConfigResource
extends Resource

## Per-mission data. Create one .tres per mission, add to PlanetConfigResource.missions[].

## Displayed in the mission list and info panel.
@export var display_name: String = ""
## Full res:// path to the scene to load when this mission is launched.
@export var scene_path: String = ""
## If non-zero, this mission is locked until the mission with that number is completed.
@export var required_mission: int = 0
## Determines the icon shown in the list row. "assault" | "infiltration"
@export_enum("assault", "infiltration") var mission_type: String = "assault"
## Texture shown in the preview image panel when this row is selected in the menu.
@export var mission_image: Texture2D = null
## One- or two-sentence description shown in the info panel when this mission is selected.
@export_multiline var description: String = ""
## Global mission number shown in the list and on the planet map point (01, 02, 03...).
## Set this manually across all planets so numbers form one continuous sequence.
@export var mission_number: int = 0
## If true, a line is drawn from the previous mission's point to this one on the planet map.
## Disable for standalone missions that should not be visually connected to the one above.
@export var connect_line: bool = true
