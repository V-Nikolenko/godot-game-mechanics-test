## The code-drawn look of an `EmpZone`, a child of its `Field` (Phase 9 plan §2.13). QUIET: a dim 1 px ring at the full
## radius. TELEGRAPH: a brighter ring contracting from `radius` to `ARMED_SCALE * radius` over the arm time (the counterplay:
## leave before it closes). ACTIVE: the dim ring plus an expanding `EmpRing` spawned on the edge. Reads the field's
## `phase()` / `phase_progress()`; it has no effect of its own.
class_name EmpZoneArt
extends Node2D

const ARMED_SCALE := 0.6
const QUIET_COLOR := Color(0.65, 0.88, 1.0, 0.22)
const ARM_COLOR := Color(0.75, 0.92, 1.0)
const RING_POINTS := 64

var _field: HazardField


func _ready() -> void:
	_field = get_parent() as HazardField
	z_index = 4
	if _field != null:
		_field.phase_changed.connect(_on_phase_changed)


func _process(_delta: float) -> void:
	queue_redraw()


## The radius of the contracting arming ring for a TELEGRAPH [param progress] (0..1).
static func arming_radius(radius: float, progress: float) -> float:
	return radius * lerpf(1.0, ARMED_SCALE, clampf(progress, 0.0, 1.0))


func _on_phase_changed(phase: int) -> void:
	if phase == HazardField.Phase.ACTIVE and is_inside_tree():
		EmpRing.spawn(self, global_position, _field.radius)


func _draw() -> void:
	if _field == null:
		return
	draw_arc(Vector2.ZERO, _field.radius, 0.0, TAU, RING_POINTS, QUIET_COLOR, 1.0, true)
	if _field.phase() == HazardField.Phase.TELEGRAPH:
		var p := _field.phase_progress()
		var color := ARM_COLOR
		color.a = lerpf(0.35, 0.95, p)
		draw_arc(Vector2.ZERO, arming_radius(_field.radius, p), 0.0, TAU, RING_POINTS, color, 2.0, true)
