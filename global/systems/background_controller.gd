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

## Multiply all scrolling-layer speeds by [m] (1.0 = normal). Default is a
## deliberate silent no-op for controllers that have no scrolling layers;
## subclasses that scroll layers should override this.
## Used by dash panels to speed up the world while the player is boosting.
func set_scroll_multiplier(m: float) -> void:
	pass

## Multiply all scrolling-layer speeds by [m] based on the player's race throttle
## (player screen position). Combined multiplicatively with set_scroll_multiplier so
## a dash boost stacks on top of the current throttle-driven base speed. Default no-op.
func set_throttle_scroll(m: float) -> void:
	pass
