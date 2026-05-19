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
