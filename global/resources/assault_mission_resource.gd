## global/resources/assault_mission_resource.gd
class_name AssaultMissionResource
extends MissionConfigResource

## Assault mission — side-scrolling shoot-em-up with full scoring system.

## Score required to earn 2 stars on this mission. 0 disables the 2★ threshold.
@export var star_2_score: int = 0
## Score required to earn 3 stars on this mission. 0 disables the 3★ threshold.
@export var star_3_score: int = 0

## Returns the star count earned for a given final score.
## 1 = completed at all; 2 / 3 require crossing the configured thresholds.
func stars_for_score(score: int) -> int:
	if star_3_score > 0 and score >= star_3_score:
		return 3
	if star_2_score > 0 and score >= star_2_score:
		return 2
	return 1
