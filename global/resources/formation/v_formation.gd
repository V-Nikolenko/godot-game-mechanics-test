## VFormation — classic V (chevron) with one lead ship and symmetric wing pairs.
##
## count=5, spread=40, row_gap=12 produces:
##   slot 0: (  0,   0) — lead
##   slot 1: (-40,  12) — wing rank 1
##   slot 2: ( 40,  12)
##   slot 3: (-80,  24) — wing rank 2
##   slot 4: ( 80,  24)
class_name VFormation
extends FormationResource

@export var count: int = 5
@export var spread: float = 40.0        ## Lateral pixels between adjacent ships.
@export var row_gap: float = 12.0       ## Downward offset per rank.
@export var stagger_delay: float = 0.1  ## Seconds between each wing-pair spawn.

func compute_slots() -> Array:
	var slots: Array = []
	slots.append(FormationResource.FormationSlot.new(Vector2.ZERO, 0.0))
	var rank: int = 1
	var delay: float = stagger_delay
	while slots.size() < count:
		var x: float = spread * rank
		var y: float = row_gap * rank
		slots.append(FormationResource.FormationSlot.new(Vector2(-x, y), delay))
		if slots.size() < count:
			slots.append(FormationResource.FormationSlot.new(Vector2( x, y), delay))
		rank += 1
		delay += stagger_delay
	return slots
