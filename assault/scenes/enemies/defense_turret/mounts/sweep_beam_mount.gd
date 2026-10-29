## SweepBeamMount - the SWEEP_BEAM variant of `TurretMount` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.8; Phase 8 t7).
##
## Fires `sweep_beam.tscn`. The mount aims not at the player but at the sweep's **start bearing**, `aim - s * sweep_arc_deg / 2`, where `aim` is
## the lead bearing (`BeamTurretMount`) and `s` is the sign of the player's angular velocity about the mount (still player: a side drawn from
## the mount's rng once per shot). TELEGRAPH shows the line there, frozen; ACTIVE then turns the mount by `s * sweep_rate` rad/s - the weapon's
## own rate, read from the beam scene, with **no turn-rate cap** - so the beam sweeps toward and through the player's lane.
class_name SweepBeamMount
extends BeamTurretMount

## Below this angular speed about the mount (rad/s) the player counts as still and the side is drawn.
const STILL_ANGULAR_SPEED := 0.05

## The side the shot in progress sweeps toward: +1 turns clockwise (increasing angle), -1 the other way.
var _side: float = 1.0
## The side the aim last saw; it becomes `_side` when the telegraph starts.
var _wanted_side: float = 1.0
var _still_side: float = 1.0


func setup(host: Node2D, pools: Dictionary, owner_group: StringName) -> void:
	super.setup(host, pools, owner_group)
	_draw_still_side()


## The current shot's sweep side (rows read it).
func side() -> float:
	return _side


func _pre_tick(delta: float) -> void:
	if _beam.phase() == EnemyBeam.Phase.ACTIVE:
		rotation += _side * _beam.sweep_rate * delta
	super._pre_tick(delta)


func _on_telegraph_start() -> void:
	_side = _wanted_side
	_draw_still_side()
	super._on_telegraph_start()


func _aim_point_for(target: TargetInfo) -> Vector2:
	if _is_frozen():
		return _aim_point
	var to_lead := _lead_point(target) - global_position
	_wanted_side = _side_for(target)
	return global_position + to_lead.rotated(-_wanted_side * deg_to_rad(_beam.sweep_arc_deg) * 0.5)


func _side_for(target: TargetInfo) -> float:
	var r := target.position - global_position
	var omega := r.cross(target.velocity) / maxf(r.length_squared(), 1.0)
	if absf(omega) < STILL_ANGULAR_SPEED:
		return _still_side
	return signf(omega)


func _draw_still_side() -> void:
	_still_side = 1.0 if rng.randf() < 0.5 else -1.0
