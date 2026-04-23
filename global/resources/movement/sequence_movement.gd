## SequenceMovement — chains multiple MovementResources end-to-end.
##
## Each step runs for its total_duration(). When a step finishes, the next
## begins. Position is accumulated so transitions are seamless.
##
## Example — approach, pause, strafe left:
##   var seq := SequenceMovement.new()
##   seq.steps = [straight_down_60, hold_1_5s, straight_left_150]
##
## Put infinite-duration steps (StraightMovement, SineMovement) LAST — they
## consume all remaining time. Any step with INF duration causes sample() to
## never advance past it, so subsequent steps are unreachable.
## total_duration() returns INF if ANY step is infinite (not just the last);
## otherwise returns the sum of all finite step durations.
class_name SequenceMovement
extends MovementResource

@export var steps: Array[MovementResource] = []

func sample(t: float) -> Vector2:
	if steps.is_empty():
		return Vector2.ZERO

	var accumulated_pos: Vector2 = Vector2.ZERO
	var time_remaining: float = t

	for i: int in steps.size():
		var step: MovementResource = steps[i]
		var step_dur: float = step.total_duration()

		if time_remaining < step_dur or i == steps.size() - 1:
			# We are inside this step. sample at local time and add accumulated offset.
			return accumulated_pos + step.sample(time_remaining)

		# This step has completed. Record its final position and advance time.
		accumulated_pos += step.sample(step_dur)
		time_remaining -= step_dur

	return accumulated_pos

func total_duration() -> float:
	var total: float = 0.0
	for step: MovementResource in steps:
		var d: float = step.total_duration()
		if d == INF:
			return INF
		total += d
	return total
