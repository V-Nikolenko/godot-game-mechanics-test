## LineFormation — ships in a straight horizontal or vertical line, centered.
class_name LineFormation
extends FormationResource

enum Axis { HORIZONTAL, VERTICAL }

@export var count: int = 5
@export var spacing: float = 40.0
@export var axis: Axis = Axis.HORIZONTAL
@export var stagger_delay: float = 0.1

func compute_slots() -> Array:
	var slots: Array = []
	var total_span: float = spacing * (count - 1)
	for i: int in count:
		var offset: Vector2
		if axis == Axis.HORIZONTAL:
			offset = Vector2(-total_span * 0.5 + spacing * i, 0.0)
		else:
			offset = Vector2(0.0, -total_span * 0.5 + spacing * i)
		slots.append(FormationResource.FormationSlot.new(offset, stagger_delay * i))
	return slots
