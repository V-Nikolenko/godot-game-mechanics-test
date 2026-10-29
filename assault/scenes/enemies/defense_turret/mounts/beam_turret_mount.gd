## BeamTurretMount - a `TurretMount` that fires one `EnemyBeam` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.8; Phase 8 t7): the base of the
## SWEEP_BEAM, LANCE and BEAM_CANNON variants. The lance and the beam cannon are this script on two scenes; the sweep adds its own aim and rotation
## (`SweepBeamMount`).
##
## The beam is a **mount child** at the muzzle, set up in `setup()` with the host and the mount's owner group (so a turret group never burns
## its own members), and is **owner-ticked from `_pre_tick`**: it advances *before* the phase step, so the mount sees the beam's phase of this very
## tick and the host's light changes with the line (CHARGING -> [COMMIT] -> ARMED) on the tick the beam does. Killing the turret frees it (a child).
##
## **The shown line is the line that fires.** The mount turns only while `_is_frozen()` is false: never in FIRE, and in TELEGRAPH only until the last
## `commit_seconds` (the lance's COMMIT; a beam with none locks at TELEGRAPH start, so the beam cannon's bearing is the one it had when the warning
## appeared). The aim point freezes with it. `power_down()` cancels the beam (a telegraph never lands; a lit beam fades), and the beam keeps
## ticking while UNPOWERED so the fade finishes.
##
## **Aim (R8.9):** a beam aims at `P + v * telegraph_seconds * lead_blend` - where the player will be when the beam can first hurt. It fires only
## with `aim_error()` inside half the `fire_cone_deg` and `can_fire`; without line of sight it holds fire (`fires_past_cover()` is false).
##
## Tuning is the mount scene's exports plus the beam scene's (`beam_scene`); gates read both through `TurretMountScenes.export_of()` /
## `EnemyBeamScenes.export_of()`.
class_name BeamTurretMount
extends TurretMount

const HEAD_RADIUS := 13.0
const BARREL_WIDTH := 6.0
const HEAD_COLOR := Color(0.36, 0.4, 0.46, 1.0)

## The weapon: an `EnemyBeam` scene (`beam.tscn`, `sweep_beam.tscn` or `lance.tscn`).
@export var beam_scene: PackedScene
## Placeholder art (the art task replaces it): the barrel's colour tells the variants apart.
@export var barrel_color: Color = Color(0.62, 0.66, 0.72, 1.0)

var _beam: EnemyBeam


func _ready() -> void:
	if beam_scene != null:
		_beam = beam_scene.instantiate() as EnemyBeam
		_beam.name = "Beam"
		_beam.position = _muzzle.position if _muzzle != null else Vector2.ZERO
		add_child(_beam)
	queue_redraw()


func setup(host: Node2D, pools: Dictionary, owner_group: StringName) -> void:
	super.setup(host, pools, owner_group)
	_beam.setup(host, owner_group)


## The mount's beam (a child), for hosts and rows that watch its phase and hits.
func beam() -> EnemyBeam:
	return _beam


func is_committed() -> bool:
	return _beam != null and _beam.is_committed()


# --- hooks -------------------------------------------------------------------------------------------------------------------------------------

func _pre_tick(delta: float) -> void:
	_beam.tick(delta)


func _aim_point_for(target: TargetInfo) -> Vector2:
	if _is_frozen():
		return _aim_point
	return _lead_point(target)


func _tracks(_in_phase: int, _clock: float) -> bool:
	return not _is_frozen()


func _telegraph_seconds() -> float:
	return _beam.telegraph_seconds


## The beam's own phase decides, so one clock rules (it has already advanced this tick).
func _telegraph_done() -> bool:
	return _beam.phase() != EnemyBeam.Phase.TELEGRAPH


func _on_telegraph_start() -> void:
	_beam.start()


## The shot is over once the beam leaves ACTIVE. A dropped `can_fire` does not cut a lit beam: a committed shot runs out (a perception loss
## does, through `scan()` -> `_stop_weapon()`).
func _fire_tick(_delta: float, _can_fire: bool) -> bool:
	return _beam.phase() != EnemyBeam.Phase.TELEGRAPH and _beam.phase() != EnemyBeam.Phase.ACTIVE


func _stop_weapon() -> void:
	_beam.cancel()


# --- internals ---------------------------------------------------------------------------------------------------------------------------------

## Where the target will be when the beam can first hurt, `lead_blend` of the way.
func _lead_point(target: TargetInfo) -> Vector2:
	return target.position + target.velocity * _beam.telegraph_seconds * lead_blend


## Seconds before the end of TELEGRAPH at which the aim locks: the last `commit_seconds` of a lance, the whole TELEGRAPH of a beam without one.
func _lock_seconds() -> float:
	return _beam.commit_seconds if _beam.commit_seconds > 0.0 else _beam.telegraph_seconds


func _is_frozen() -> bool:
	match _phase:
		Phase.FIRE:
			return true
		Phase.TELEGRAPH:
			return _beam.phase() != EnemyBeam.Phase.TELEGRAPH or _phase_clock + CLOCK_EPS >= _beam.telegraph_seconds - _lock_seconds()
	return false


## Placeholder art: a head disc and a barrel along +X to the muzzle.
func _draw() -> void:
	var tip := _muzzle.position.x if _muzzle != null else HEAD_RADIUS * 2.0
	draw_rect(Rect2(0.0, -BARREL_WIDTH * 0.5, tip, BARREL_WIDTH), barrel_color)
	draw_circle(Vector2.ZERO, HEAD_RADIUS, HEAD_COLOR)
