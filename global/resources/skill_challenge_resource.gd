## SkillChallengeResource — designer-placed bonus moment within a level section.
##
## Lives in a LevelSection.skill_challenges array (separate from waves). When
## its trigger_time elapses, Level1Director spawns a SkillChallengeRunner that
## stands up the hazard pattern, displays the prompt, and emits the result via
## EventBus.skill_challenge_completed.
class_name SkillChallengeResource
extends Resource

## Section-relative seconds before the challenge starts.
@export var trigger_time: float = 0.0

## Display name (shown in the on-screen "DANGER ZONE" prompt).
@export var challenge_name: String = "DANGER ZONE"

## How long the challenge runs from spawn to result.
@export_range(1.0, 30.0, 0.1) var duration: float = 4.0

## Hazard pattern instantiated for the duration. Optional — leave null for
## challenges whose hazards are baked into the level waves themselves.
@export var hazard_pattern: PackedScene = null

## Score awarded when the player reaches the end of the window damage-free.
@export var clean_bonus: int = 500
## Score awarded when the player reaches the end but took damage at least once.
@export var partial_bonus: int = 150
