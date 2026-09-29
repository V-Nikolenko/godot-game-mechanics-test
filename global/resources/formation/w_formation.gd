## WFormation — W shape: centre and outer pair forward, the two in between trail.
##
## count=5, spread=60, depth=40 produces:
##   slot 0: (-120,   0) — outer left, delay 0.2
##   slot 1: ( -60, -40) — trails, delay 0.1
##   slot 2: (   0,   0) — centre (first), delay 0
##   slot 3: (  60, -40) — trails, delay 0.1
##   slot 4: ( 120,   0) — outer right, delay 0.2
class_name WFormation
extends FormationResource

@export var count: int = 5
@export var spread: float = 60.0        ## Lateral pixels between adjacent slots.
@export var depth: float = 40.0         ## Backward offset for the trailing (odd-index) slots.
@export var stagger_delay: float = 0.1  ## Seconds per step outward from the centre.

func compute_slots() -> Array:
	var slots: Array = []
	var center: float = (count - 1) / 2.0
	for i in count:
		var x: float = (i - center) * spread
		var y: float = -depth if i % 2 == 1 else 0.0
		var delay: float = stagger_delay * floor(absf(i - center))
		slots.append(FormationResource.FormationSlot.new(Vector2(x, y), delay))
	return slots
