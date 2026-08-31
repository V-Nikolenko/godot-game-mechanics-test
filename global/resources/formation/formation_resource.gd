## FormationResource — abstract base for all formation patterns.
##
## compute_slots() returns one FormationSlot per ship. WaveManager calls this
## and spawns one ship per slot, adding slot.offset to the spawn entry's
## base_offset and adding slot.delay to the entry's base delay.
class_name FormationResource
extends Resource

## A single ship position within a formation.
class FormationSlot:
	var offset: Vector2   ## Screen-space displacement from the formation anchor.
	var delay: float      ## Additional spawn delay for this slot (seconds).

	func _init(o: Vector2, d: float = 0.0) -> void:
		offset = o
		delay = d

## Returns one FormationSlot per ship. Override in each subtype.
func compute_slots() -> Array:  ## Array[FormationSlot]
	return []
