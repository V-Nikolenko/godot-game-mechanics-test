## LevelSection — one timed segment of a level.
## Bundles section-relative waves with a background target state and an exit condition.
class_name LevelSection
extends Resource

enum EndCondition {
	DURATION,        ## Advance after [duration] seconds.
	WAVES_COMPLETE,  ## Advance after all waves have triggered.
	ENEMIES_CLEARED, ## Advance after waves complete AND enemy_container is empty.
}

@export var section_name: StringName = &""

## Background target state for this section.
@export var background_phase: BackgroundPhase

## How long (seconds) to tween from the previous phase to this one.
## Pass this to background.transition_to(phase, transition_in_duration).
@export var transition_in_duration: float = 2.0

## Waves to load at section start.  trigger_time is SECTION-RELATIVE.
@export var waves: Array[WaveResource] = []

@export var end_condition: EndCondition = EndCondition.DURATION

## Seconds before advancing (only when end_condition == DURATION).
@export var duration: float = 30.0

## Safety net for ENEMIES_CLEARED: seconds to wait for [enemy_container] to empty before
## giving up, freeing whatever is left and advancing anyway.
##
## The default is the hardcoded constant this replaced, sized for "wait for the last stragglers
## to fly off screen". Boss sections need far longer — the fight itself is the section, and a
## player who is losing must still be allowed to keep trying. Ignored by the other end conditions.
@export var enemies_cleared_timeout: float = 10.0
