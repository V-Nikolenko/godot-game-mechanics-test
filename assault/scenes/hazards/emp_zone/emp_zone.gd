## EmpZone: a placed, neutral area that arms with a shrinking ring and then pulses an EMP every few seconds on everyone
## inside it, player and enemies alike (Phase 9 plan §2.13).
##
## Composition, like the jammer: the root is a plain `Node2D` and its child `Field` is a `HazardField` (kind `emp_zone`, the
## cycle and the avoid weight live in the scene). The field registers itself, so enemies steer round it while it is
## telegraphing or lit; this script only listens to `Field.phase_changed` and, on each change TO ACTIVE, makes the one
## `EmpPulse.emit(..., TARGET_ALL)`: the player's ability lock + boost refusal, every enemy that answers EMP, and every
## seeking rocket. Scene-placed only; never in an Assault level in Phase 9.
class_name EmpZone
extends Node2D

## Seconds each pulse disrupts what it reaches.
@export var emp_seconds: float = 2.0

var _field: HazardField


func _ready() -> void:
	_field = get_node("Field") as HazardField
	_field.phase_changed.connect(_on_phase_changed)


## The child field (the avoidance footprint and the cycle clock).
func field() -> HazardField:
	return _field if _field != null else get_node("Field") as HazardField


## World radius of the pulse: the field's own.
func radius() -> float:
	return field().radius


func _on_phase_changed(phase: int) -> void:
	if phase != HazardField.Phase.ACTIVE or not is_inside_tree():
		return
	EmpPulse.emit(get_tree(), global_position, field().radius, emp_seconds, self, EmpPulse.TARGET_ALL)
