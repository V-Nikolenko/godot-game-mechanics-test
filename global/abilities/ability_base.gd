# global/abilities/ability_base.gd
class_name AbilityBase
extends Node

## Override in subclass. Called when the player presses use_ability.
## `ctx` provides access to actor, health, shield, overheat, etc.
## Returns true if the ability was successfully activated (starts cooldown).
func activate(ctx: AbilityController) -> bool:
	return false

## Override if the ability needs per-frame logic while active.
## Called by AbilityController._physics_process while this ability is the selected one.
func tick(_ctx: AbilityController, _delta: float) -> void:
	pass

## Called when this ability is deselected or the level ends.
## Clean up any active effects.
func deactivate(_ctx: AbilityController) -> void:
	pass

## Human-readable name for HUD display.
func get_display_name() -> String:
	return "Ability"

## Icon texture for HUD. Return null to show a placeholder.
func get_icon() -> Texture2D:
	return null

## Cooldown duration in seconds.
func get_cooldown() -> float:
	return 5.0
