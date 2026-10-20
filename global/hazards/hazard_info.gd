## One hazard's shared description: everything a ship, an enemy or a test needs to know about a pull,
## a slow or a danger without knowing what node makes it (docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md §2.1).
##
## Each hazard node owns ONE instance, updates it in place and returns it from `hazard_info()`. Callers
## treat the fields as read-only; the claim methods are the one mutable part.
##
## Field profile (softened 1/r, short reach, no hard edge): `falloff(r)` is 1 inside `core_radius`,
## `core_radius / r` out to 0.85 * `radius`, then a linear taper to 0 at `radius`, 0 beyond.
class_name HazardInfo
extends RefCounted

## Fraction of `radius` where the 1/r profile hands over to the linear taper.
const TAPER_START := 0.85

var position: Vector2 = Vector2.ZERO
## Outer edge of every effect: pull reach, slow area, avoidance footprint.
var radius: float = 0.0
## Radial acceleration at the core, px/s², toward the centre (0 = none).
var pull_force: float = 0.0
## Hull stress inside `damage_radius` (= stress_damage / stress_period; for the AI).
var damage_per_second: float = 0.0
## 0..1 slow inside `radius`.
var movement_penalty: float = 0.0
## Carried for Phase 9; no producer or consumer in Phase 6.
var disables_abilities: bool = false
## Mirrors the body's `blocks_line_of_sight()`.
var line_of_sight_blocker: bool = false
## &"gravity_well", &"anomaly", &"gravity_field", &"reactor_field", &"wreck" or &"debris".
var kind: StringName = &""
## Softening radius: the pull is constant inside it.
var core_radius: float = 0.0
## Hull-stress radius.
var damage_radius: float = 0.0
## Swirl acceleration at the core, px/s². The sign is the direction (+ = clockwise in screen space).
var tangential_force: float = 0.0
## 0..1, how bad entering is (well 1.0, reactor 1.0, anomaly 0.7 lit / 0 quiet, gravity field 0.6,
## wreck 0.6, debris 0.4).
var avoid_weight: float = 0.0
## Drifting hazards; avoidance leads them.
var velocity: Vector2 = Vector2.ZERO
## The hazard node.
var source: Node = null
## Instance id of the claimer, 0 = free. An id, not a reference: a freed claimer frees the claim.
var claimer_id: int = 0


## 0..1 strength of the field at distance [param r] from the centre.
func falloff(r: float) -> float:
	if r >= radius:
		return 0.0
	if r <= core_radius:
		return 1.0
	var taper_at := radius * TAPER_START
	if r <= taper_at:
		return core_radius / r
	var at_taper := minf(1.0, core_radius / taper_at)
	return at_taper * (radius - r) / (radius - taper_at)


## Acceleration (px/s²) the field applies at world point [param pos]: radial pull toward the centre plus
## the tangential swirl, both scaled by `falloff`. `Vector2.ZERO` at the exact centre (no direction).
func accel_at(pos: Vector2) -> Vector2:
	var offset := pos - position
	var r := offset.length()
	if r <= 0.0:
		return Vector2.ZERO
	var f := falloff(r)
	if f <= 0.0:
		return Vector2.ZERO
	var outward := offset / r
	# Screen space is y-down, so (-y, x) of the outward vector is the clockwise tangent.
	var clockwise := Vector2(-outward.y, outward.x)
	return (-outward * pull_force + clockwise * tangential_force) * f


## `movement_penalty` inside `radius`, 0 outside.
func penalty_at(pos: Vector2) -> float:
	return movement_penalty if pos.distance_to(position) <= radius else 0.0


## True when [param pos] is within `radius + margin` of the centre.
func contains(pos: Vector2, margin: float = 0.0) -> bool:
	return pos.distance_to(position) <= radius + margin


## Takes the claim. Succeeds when free, when [param node] already holds it, and when the holder was freed.
func try_claim(node: Node) -> bool:
	if node == null:
		return false
	var id := node.get_instance_id()
	if claimer_id == 0 or claimer_id == id or not is_instance_id_valid(claimer_id):
		claimer_id = id
		return true
	return false


## Releases the claim; a no-op unless [param node] holds it.
func release(node: Node) -> void:
	if node != null and claimer_id == node.get_instance_id():
		claimer_id = 0


func is_claimed_by(node: Node) -> bool:
	return node != null and claimer_id != 0 and claimer_id == node.get_instance_id()


## True while a live node holds the claim.
func is_claimed() -> bool:
	return claimer_id != 0 and is_instance_id_valid(claimer_id)
