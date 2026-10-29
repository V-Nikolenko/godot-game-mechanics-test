## TurretMount - everything that aims and fires on a turret: the Ph10 / Ph11 seam (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7;
## task plan docs/plans/cmvqw0vnb017rqs2xsyursu5d/3-plan.md).
##
## A mount is a `Node2D` its host places at a `TurretMountSlot`. It owns the aim, the muzzle, the weapon and its telegraph, and it **never reads
## its host's type**, so a ship module or a fortress (Ph10 / Ph11) can carry it unchanged. It writes **only its own `rotation`** (local to its
## parent, turn-rate limited); never the host's.
##
## The base class runs the cycle; a variant is a subclass with its own script and scene (`TurretMountScenes`) that overrides the hooks below.
## Weapon tuning lives in that scene's exports, never in a host config.
##
## THE CYCLE (`Phase`), driven by the host brain through `tick(delta, target, can_fire)` and `scan(delta)`:
## - SCAN: no target; a triangle sweep of `scan_arc_deg` about `rest_bearing_deg` at `scan_speed`.
## - TRACK: aim and turn; steps to TELEGRAPH once the cooldown is over, `_wants_telegraph()` passes and `telegraph_gate` (asked last) allows it.
## - TELEGRAPH: back to TRACK if `can_fire` drops; FIRE when `_telegraph_done()`, with the first `_fire_tick(0, …)` on that same tick.
## - FIRE: `_fire_tick(delta, can_fire)` until it reports done; COOLDOWN.
## - COOLDOWN: aim and turn; TRACK once `_cooldown_left` runs out.
## - UNPOWERED: `power_down()`; the mount eases to `rest_bearing_deg` (the droop) and never leaves it in this phase.
##
## Tick order, each `tick()` / `scan()`: `_pre_tick(delta)` (an owner-ticked beam advances before the phase step reads its phase), the cooldown
## counts down, the phase clock counts up, the phase step runs (aim and turn first), then `_weapon_tick(delta)` - once per call in EVERY phase,
## UNPOWERED included, so an owner-ticked beam or ring finishes its fade.
## The cooldown is its own clock: it counts in every phase, SCAN included, and is set by any exit from FIRE except `power_down()`, so a
## turret whose perception flickers never fires faster than its exports.
##
## HOOKS (subclass surface): `_pre_tick`, `_aim_point_for`, `_shot_speed`, `_tracks`, `_wants_telegraph`, `_telegraph_seconds`, `_telegraph_done`,
## `_on_telegraph_start`, `_fire_tick`, `_weapon_tick`, `_stop_weapon`, `pool_specs`, `fires_past_cover`, `is_committed`.
class_name TurretMount
extends Node2D

## Append-only.
enum Variant { BURST_CANNON, SWEEP_BEAM, ROCKET_BATTERY, PULSE_RING, LANCE, BEAM_CANNON }
## Append-only.
enum Phase { SCAN, TRACK, TELEGRAPH, FIRE, COOLDOWN, UNPOWERED }

## Floating-point slack for clock comparisons (24 ticks of 1/60 s must reach 0.4 s).
const CLOCK_EPS := 1e-6
## The droop tint of a powered-down mount's code-drawn head (placeholder until the art task).
const UNPOWERED_TINT := Color(0.45, 0.45, 0.5, 1.0)

signal phase_changed(phase: int)
## A projectile left the muzzle (rows read every launch through it).
signal round_fired(projectile: Node2D)

## Turn rate of the mount, rad/s. A host slot's `turn_rate_override` (>= 0) replaces it before `setup()`.
@export var turn_rate: float = 2.0
## The mount telegraphs only with its target within this distance of the muzzle, px. (§2.7 calls it `range`, which shadows the built-in.)
@export var fire_range: float = 700.0
## Share of the way from the target's position to its intercept point that the aim leads (R8.9's partial lead).
@export var lead_blend: float = 0.6
## Full width of the cone a round may leave in, degrees: a mount fires only with `aim_error()` <= half of it.
@export var fire_cone_deg: float = 8.0
## Width of the idle scan, degrees, centred on `rest_bearing_deg`.
@export var scan_arc_deg: float = 90.0
## Angular speed of the idle scan, rad/s.
@export var scan_speed: float = 0.4
## Seconds between the end of a FIRE and the next TELEGRAPH.
@export var cooldown_seconds: float = 2.2
## Scan centre and droop target, degrees, Godot convention (0 = +X, 90 = down), local to the mount's parent. The host copies its slot's here.
@export var rest_bearing_deg: float = 90.0

## The scan's start offset is drawn from this; the host assigns its brain's rng before `setup()`. Null = a randomised one of the mount's own.
var rng: RandomNumberGenerator
## Optional hold on TRACK -> TELEGRAPH (`call() -> bool`; the host binds whatever it needs, e.g. a group's stagger). Asked last, only when every
## other check has passed; a refusal keeps the mount in TRACK and it asks again next tick. Empty = always allowed.
var telegraph_gate: Callable = Callable()

var _host: Node2D
var _pools: Dictionary = {}
var _owner_group: StringName = &""
var _phase: int = Phase.SCAN
var _phase_clock: float = 0.0
var _cooldown_left: float = 0.0
var _aim_point: Vector2 = Vector2.ZERO
var _scan_offset: float = 0.0
var _scan_dir: float = 1.0

@onready var _muzzle: Node2D = get_node_or_null("Muzzle") as Node2D


## Binds the mount to its host. `pools` maps each `pool_specs()` name to the `BulletPool` the host built for it (root children of the host, so
## rounds land in the host's container). `owner_group` is the set every weapon of this mount exempts (the turret, its group, its mounts).
func setup(host: Node2D, pools: Dictionary, owner_group: StringName) -> void:
	_host = host
	_pools = pools
	_owner_group = owner_group
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var half := _scan_half()
	_scan_offset = rng.randf_range(-half, half)
	_scan_dir = 1.0 if rng.randf() < 0.5 else -1.0
	rotation = _rest() + _scan_offset
	_aim_point = global_position + Vector2.RIGHT.rotated(global_rotation)


## One tick with a target snapshot. `can_fire` is the host's say (line of sight, power); the mount adds range, cone, cooldown and its gate.
## With no target this is `scan(delta)`.
func tick(delta: float, target: TargetInfo, can_fire: bool) -> void:
	if target == null or not target.has_target:
		scan(delta)
		return
	_pre_tick(delta)
	_count_clocks(delta)
	match _phase:
		Phase.UNPOWERED:
			_droop(delta)
		Phase.SCAN:
			_enter(Phase.TRACK)
			_track_step(delta, target, can_fire)
		Phase.TRACK:
			_track_step(delta, target, can_fire)
		Phase.TELEGRAPH:
			_aim_and_turn(delta, target)
			if not can_fire:
				_stop_weapon()
				_enter(Phase.TRACK)
			elif _telegraph_done():
				_enter(Phase.FIRE)
				if _fire_tick(0.0, can_fire):
					_end_fire()
		Phase.FIRE:
			_aim_and_turn(delta, target)
			if _fire_tick(delta, can_fire):
				_end_fire()
		Phase.COOLDOWN:
			_aim_and_turn(delta, target)
			if _cooldown_left <= CLOCK_EPS:
				_enter(Phase.TRACK)
	_weapon_tick(delta)


## One idle tick: any live weapon stops (a FIRE cut here still starts the cooldown), the phase becomes SCAN and the mount follows its sweep.
## An unpowered mount only droops.
func scan(delta: float) -> void:
	_pre_tick(delta)
	_count_clocks(delta)
	if _phase == Phase.UNPOWERED:
		_droop(delta)
	else:
		if _phase != Phase.SCAN:
			var was_firing := _phase == Phase.FIRE
			_stop_weapon()
			if was_firing:
				_cooldown_left = cooldown_seconds
			_enter(Phase.SCAN)
		_scan_step(delta)
	_weapon_tick(delta)


## Unpowered for good in this phase: the weapon stops (a telegraph never lands), the cooldown clears and the mount droops to rest. Idempotent.
func power_down() -> void:
	if _phase == Phase.UNPOWERED:
		return
	_stop_weapon()
	_cooldown_left = 0.0
	modulate = UNPOWERED_TINT
	_enter(Phase.UNPOWERED)


## The pools this mount fires from: `{name, scene, size, persist}` each. The host builds them as its own root children.
func pool_specs() -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	return specs


func muzzle_position() -> Vector2:
	return _muzzle.global_position if _muzzle != null else global_position


## Unsigned angle (rad) between the mount's facing and the bearing from its pivot to `aim_point()`.
func aim_error() -> float:
	var to_aim := _aim_point - global_position
	if to_aim.length_squared() < 0.000001:
		return 0.0
	return absf(angle_difference(global_rotation, to_aim.angle()))


func aim_point() -> Vector2:
	return _aim_point


func phase() -> int:
	return _phase


func owner_group() -> StringName:
	return _owner_group


func cooldown_left() -> float:
	return maxf(_cooldown_left, 0.0)


## Curving ordnance fires past cover (the rocket battery, t8); every other variant holds fire without line of sight.
func fires_past_cover() -> bool:
	return false


## True while a committed shot cannot be dodged by waiting (the lance's COMMIT, t7): the host lights COMMIT.
func is_committed() -> bool:
	return false


# --- hooks -------------------------------------------------------------------------------------------------------------------------------------

## Before the cooldown and the phase clock count, once per `tick()` / `scan()`: a weapon that owns a clock the phase step reads (a beam) advances here.
func _pre_tick(_delta: float) -> void:
	pass


## Where to aim at `target`. Projectile variants: `lead_blend` of the way from the target to its intercept (the plain position when that fails).
func _aim_point_for(target: TargetInfo) -> Vector2:
	var hit: Dictionary = target.intercept(muzzle_position(), _shot_speed())
	return target.position.lerp(hit["point"] as Vector2, lead_blend)


## The speed a shot leaves at, px/s (0 = no projectile: the intercept falls back to the target's position).
func _shot_speed() -> float:
	return 0.0


## Whether the mount aims and turns in `phase` after `phase_clock` seconds of it.
func _tracks(_in_phase: int, _clock: float) -> bool:
	return true


## Whether TRACK may step to TELEGRAPH this tick (checked after this tick's turn; the cooldown and the gate are checked by the base).
func _wants_telegraph(target: TargetInfo, can_fire: bool) -> bool:
	return can_fire \
			and target.position.distance_to(muzzle_position()) <= fire_range \
			and aim_error() <= deg_to_rad(fire_cone_deg) * 0.5


func _telegraph_seconds() -> float:
	return 0.0


## Whether TELEGRAPH is over. A beam answers from its own phase, so one clock decides.
func _telegraph_done() -> bool:
	return _phase_clock + CLOCK_EPS >= _telegraph_seconds()


func _on_telegraph_start() -> void:
	pass


## One FIRE tick; true when the shot is done. Called with delta 0 on the tick TELEGRAPH ends.
func _fire_tick(_delta: float, _can_fire: bool) -> bool:
	return true


## The weapon's own clock: once per `tick()` / `scan()` in every phase.
func _weapon_tick(_delta: float) -> void:
	pass


## Stop whatever is live: no further shot; a telegraph never lands.
func _stop_weapon() -> void:
	pass


# --- internals ---------------------------------------------------------------------------------------------------------------------------------

func _track_step(delta: float, target: TargetInfo, can_fire: bool) -> void:
	_aim_and_turn(delta, target)
	if _cooldown_left > CLOCK_EPS or not _wants_telegraph(target, can_fire):
		return
	if telegraph_gate.is_valid() and telegraph_gate.call() != true:
		return
	_enter(Phase.TELEGRAPH)
	_on_telegraph_start()


func _aim_and_turn(delta: float, target: TargetInfo) -> void:
	_aim_point = _aim_point_for(target)
	if not _tracks(_phase, _phase_clock):
		return
	_turn_toward((_aim_point - global_position).angle() - _parent_rotation(), delta)


func _end_fire() -> void:
	_cooldown_left = cooldown_seconds
	_enter(Phase.COOLDOWN)


func _count_clocks(delta: float) -> void:
	_cooldown_left -= delta
	_phase_clock += delta


func _scan_step(delta: float) -> void:
	var half := _scan_half()
	_scan_offset += _scan_dir * scan_speed * delta
	if _scan_offset > half:
		_scan_offset = half - (_scan_offset - half)
		_scan_dir = -1.0
	elif _scan_offset < -half:
		_scan_offset = -half + (-half - _scan_offset)
		_scan_dir = 1.0
	_scan_offset = clampf(_scan_offset, -half, half)
	_turn_toward(_rest() + _scan_offset, delta)


func _droop(delta: float) -> void:
	_turn_toward(_rest(), delta)


## The one write: this node's own `rotation`, at most `turn_rate · delta` toward `desired` (local to the parent).
func _turn_toward(desired: float, delta: float) -> void:
	rotation = rotate_toward(rotation, desired, turn_rate * delta)


func _enter(new_phase: int) -> void:
	if _phase == new_phase:
		return
	_phase = new_phase
	_phase_clock = 0.0
	phase_changed.emit(new_phase)


func _rest() -> float:
	return deg_to_rad(rest_bearing_deg)


func _scan_half() -> float:
	return deg_to_rad(scan_arc_deg) * 0.5


func _parent_rotation() -> float:
	var parent := get_parent() as Node2D
	return parent.global_rotation if parent != null else 0.0
