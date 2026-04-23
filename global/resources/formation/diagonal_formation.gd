## DiagonalFormation — ships placed diagonally, each offset by (step_x, step_y)
## from the previous. The anchor is the center ship.
##
## count=5, step_x=40, step_y=14 reproduces Wave 2 and Wave 4's diagonal lines.
class_name DiagonalFormation
extends FormationResource

@export var count: int = 5
@export var step_x: float = 40.0    ## X offset per rank relative to center.
@export var step_y: float = 14.0    ## Y offset per rank relative to center.
@export var stagger_delay: float = 0.15

func compute_slots() -> Array:
	var slots: Array = []
	var mid: int = count / 2
	for i: int in count:
		var rank: int = i - mid
		var offset: Vector2 = Vector2(step_x * rank, step_y * rank)
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
