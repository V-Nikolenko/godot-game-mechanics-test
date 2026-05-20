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

## Score required to earn 2 stars on this mission. 0 disables the 2★ threshold.
@export var star_2_score: int = 0
## Score required to earn 3 stars on this mission. 0 disables the 3★ threshold.
@export var star_3_score: int = 0

## If non-zero, this mission also requires the player to have at least
## [required_score] on mission [required_score_mission] to unlock.
## Composes with required_mission via AND — both conditions must pass.
@export var required_score_mission: int = 0
@export var required_score: int = 0

## Returns the star count earned for a given final score.
## 1 = completed at all; 2 / 3 require crossing the configured thresholds.
func stars_for_score(score: int) -> int:
	if star_3_score > 0 and score >= star_3_score:
		return 3
	if star_2_score > 0 and score >= star_2_score:
		return 2
	return 1
