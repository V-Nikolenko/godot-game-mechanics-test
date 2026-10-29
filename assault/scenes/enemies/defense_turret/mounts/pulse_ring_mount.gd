## PulseRingMount - the PULSE_RING variant of `TurretMount` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.8; Phase 8 t8).
##
## A short-range emitter: idle until the player is within `trigger_range` of the mount, then one `EnergyRing` (`energy_ring.tscn`: TELEGRAPH 0.8 s,
## the band expanding to `max_radius` 280, FADE) centred on the mount, then `cooldown_seconds`. The cooldown counts from the end of the expansion.
## It forces the player to keep moving round the turret: stay outside `max_radius`, or slip through a gap.
##
## **No aim.** The mount does not turn to track (`_tracks()` is false) and ignores `fire_cone_deg`; it keeps the idle scan while nothing is
## perceived. Like every non-rocket mount it holds fire without line of sight.
##
## The ring is a **mount child** (centred on the mount, not its muzzle), set up with the host and the owner group (a turret group never burns its own
## members) and **owner-ticked from `_pre_tick`**, the `BeamTurretMount` rule: the mount sees the ring's phase of this very tick. Its gap bearing is a
## draw from the mount's `rng`. Killing the turret frees the ring. `power_down()` cancels a telegraph and fades an expanding band; the ring keeps
## ticking while UNPOWERED so the fade finishes.
##
## Tuning is this scene's exports plus `energy_ring.tscn`'s (`ring_scene`).
class_name PulseRingMount
extends TurretMount

const HEAD_RADIUS := 13.0
const HEAD_COLOR := Color(0.36, 0.4, 0.46, 1.0)
const EMITTER_COLOR := Color(1.0, 0.85, 0.3, 1.0)

## The ring starts only with the player this close to the mount's pivot, px.
@export var trigger_range: float = 300.0
@export var ring_scene: PackedScene

var _ring: EnergyRing


func _ready() -> void:
	if ring_scene != null:
		_ring = ring_scene.instantiate() as EnergyRing
		_ring.name = "Ring"
		add_child(_ring)
	queue_redraw()


func setup(host: Node2D, pools: Dictionary, owner_group: StringName) -> void:
	super.setup(host, pools, owner_group)
	_ring.setup(host, owner_group)


## The coverage reach is the trigger distance (the ring reaches farther, but only fires with the player this close).
func reach() -> float:
	return trigger_range


## The mount's ring (a child), for hosts and rows that watch its phase and hits.
func ring() -> EnergyRing:
	return _ring


# --- hooks -------------------------------------------------------------------------------------------------------------------------------------

func _pre_tick(delta: float) -> void:
	_ring.tick(delta)


## The ring needs no aim.
func _tracks(_in_phase: int, _clock: float) -> bool:
	return false


func _wants_telegraph(target: TargetInfo, can_fire: bool) -> bool:
	return can_fire and target.position.distance_to(global_position) <= trigger_range


func _telegraph_seconds() -> float:
	return _ring.telegraph_seconds


## The ring's own phase decides, so one clock rules (it has already advanced this tick).
func _telegraph_done() -> bool:
	return _ring.phase() != EnergyRing.Phase.TELEGRAPH


func _on_telegraph_start() -> void:
	_ring.start(rng.randf_range(0.0, 360.0))


## FIRE lasts while the band expands; the cooldown starts when it ends. A dropped `can_fire` does not cut a ring already out.
func _fire_tick(_delta: float, _can_fire: bool) -> bool:
	return _ring.phase() != EnergyRing.Phase.TELEGRAPH and _ring.phase() != EnergyRing.Phase.EXPANDING


func _stop_weapon() -> void:
	_ring.cancel()


## Placeholder art (the art task replaces it): a head disc with an emitter ring.
func _draw() -> void:
	draw_circle(Vector2.ZERO, HEAD_RADIUS, HEAD_COLOR)
	draw_arc(Vector2.ZERO, HEAD_RADIUS * 0.6, 0.0, TAU, 20, EMITTER_COLOR, 3.0)
