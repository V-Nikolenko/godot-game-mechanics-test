## BackgroundController — abstract base for level background renderers.
##
## Subclasses must override `transition_to()` to tween their visual state
## toward the values in a BackgroundPhase resource over the given duration.
##
## LevelDirector calls this on each section start. Sequencer code should
## reference this type rather than any concrete level-specific class.
class_name BackgroundController
extends Node

## Transition the background's visual state toward [phase] over [duration]
## seconds. A duration of 0 should snap instantly. A null phase is a no-op.
##
## Default implementation logs a warning and does nothing — subclasses MUST
## override.
func transition_to(phase: BackgroundPhase, duration: float) -> void:
	push_warning(
		"[BackgroundController] transition_to() not overridden on %s" %
		[get_script().resource_path if get_script() else "unknown"]
	)
