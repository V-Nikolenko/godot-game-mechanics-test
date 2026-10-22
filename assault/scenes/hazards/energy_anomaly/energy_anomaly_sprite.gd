## The Energy Anomaly's presentation, on its sprite only. Reads the parent `HazardField`'s cycle
## (`phase_changed` / `phase_progress()`) and writes nothing but this node's own look: the dim frames and a
## low glow while QUIET, rings that brighten through TELEGRAPH, the lit frames spinning while ACTIVE.
## Violet / magenta only (cyan means shield). Read-only toward ships and the field.
class_name EnergyAnomalySprite
extends AnimatedSprite2D

const QUIET_BRIGHTNESS := 0.45
const TELEGRAPH_FLOOR := 0.55
const SPIN_SPEED := 1.6
const RING_COLOR := Color(0.78, 0.35, 0.95, 0.22)
const RING_WIDTH := 2.0
const RING_POINTS := 96

var _field: HazardField
var _brightness: float = QUIET_BRIGHTNESS


func _ready() -> void:
	_field = get_parent() as HazardField
	if _field == null:
		return
	_field.phase_changed.connect(_on_phase_changed)
	_apply_phase(_field.phase())
	_brightness = _target_brightness()
	modulate = Color(1.0, 1.0, 1.0, _brightness)


func _process(delta: float) -> void:
	if _field == null:
		return
	_brightness = _target_brightness()
	modulate.a = _brightness
	if _field.phase() == HazardField.Phase.ACTIVE:
		rotation += SPIN_SPEED * delta


## 0..1: QUIET dim, TELEGRAPH climbing from `TELEGRAPH_FLOOR` to 1.0, ACTIVE full.
func brightness() -> float:
	return _brightness


func _target_brightness() -> float:
	match _field.phase():
		HazardField.Phase.TELEGRAPH:
			return lerpf(TELEGRAPH_FLOOR, 1.0, _field.phase_progress())
		HazardField.Phase.ACTIVE:
			return 1.0
	return QUIET_BRIGHTNESS


func _on_phase_changed(phase: int) -> void:
	_apply_phase(phase)


func _apply_phase(phase: int) -> void:
	animation = &"lit" if phase == HazardField.Phase.ACTIVE else &"dim"
	if not is_playing():
		play(animation)


func _draw() -> void:
	var field := get_parent() as HazardField
	if field != null:
		draw_arc(Vector2.ZERO, field.radius, 0.0, TAU, RING_POINTS, RING_COLOR, RING_WIDTH, true)
