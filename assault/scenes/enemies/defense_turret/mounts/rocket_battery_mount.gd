## RocketBatteryMount - the ROCKET_BATTERY variant of `TurretMount` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.8; Phase 8 t8).
##
## TELEGRAPH is the tube glow (`charge_seconds`; the host's light goes CHARGING and the muzzle lamp swells), then a salvo of `salvo_count` Phase 5
## `EnemyRocket`s `salvo_gap` apart from a `BurstClock`, the first on the tick the glow ends. Each rocket is PURSUIT with probability
## `pursuit_chance` (a draw from the mount's `rng`, the brain's), else DUMB. A rocket leaves along the barrel with the mount's predicted aim point
## (`launch(dir, aim_point, host)`): a DUMB one flies the barrel's line, a PURSUIT one steers on the aim point itself.
##
## **Fires past cover** (`fires_past_cover()` true): ordnance that curves round a wreck, the Missile Corvette's rule, so the brain never holds this
## mount for want of line of sight. Losing `can_fire` (power, perception) still stops the salvo.
##
## **Launcher contract.** The host answers the rocket's duck-typed questions: `launch_velocity()` (ZERO: a static host) and `rocket_clear_radius()`
## (its body radius + 4), so a rocket opens its impact box only once clear of the hull and never hits its own turret. The mount reads no host type.
##
## **Pools.** One `BulletPool` per kind, as the host's root children with `persist_after_owner_death`, so a rocket in flight outlives its turret
## and frees itself on `expired`. Sizes come from `EnemyRocketScenes.pool_size_for()` over a stand-in for the salvo (every rocket of a salvo may be of
## one kind, so each pool holds a whole salvo, times the salvos that can still be in flight).
##
## Tuning is this scene's exports (`rocket_battery_mount.tscn`) and the rocket scenes'; gates read them through `TurretMountScenes.export_of()` /
## `EnemyRocketScenes.export_of()`.
class_name RocketBatteryMount
extends TurretMount

const DUMB_POOL := &"DumbPool"
const PURSUIT_POOL := &"PursuitPool"
const HEAD_RADIUS := 13.0
const BARREL_WIDTH := 8.0
const HEAD_COLOR := Color(0.36, 0.4, 0.46, 1.0)
const BARREL_COLOR := Color(0.78, 0.5, 0.3, 1.0)
const GLOW_COLOR := Color(1.0, 0.45, 0.2, 0.85)

## TELEGRAPH: the tube glow before the salvo, s.
@export var charge_seconds: float = 0.5
@export var salvo_count: int = 2
## Seconds between rockets of one salvo.
@export var salvo_gap: float = 0.35
## Chance each rocket of a salvo is a PURSUIT rocket; DUMB otherwise.
@export_range(0.0, 1.0) var pursuit_chance: float = 1.0 / 3.0

## Rockets not launched because a pool was exhausted.
var rockets_refused: int = 0

var _salvo := BurstClock.new()
var _firing: bool = false


func pool_specs() -> Array[Dictionary]:
	var stand_in := {"salvo_count": salvo_count, "warhead_salvo_count": 0, "salvo_period_min": _period()}
	var specs: Array[Dictionary] = []
	for entry in [[DUMB_POOL, EnemyRocket.Kind.DUMB], [PURSUIT_POOL, EnemyRocket.Kind.PURSUIT]]:
		var kind: EnemyRocket.Kind = entry[1]
		specs.append({
			"name": entry[0],
			"scene": EnemyRocketScenes.scene_for(kind),
			"size": EnemyRocketScenes.pool_size_for(kind, stand_in),
			"persist": true,
		})
	return specs


func _ready() -> void:
	phase_changed.connect(func(_p: int) -> void: queue_redraw())
	queue_redraw()


func fires_past_cover() -> bool:
	return true


# --- hooks -------------------------------------------------------------------------------------------------------------------------------------

## The rocket's cruise speed, for the lead estimate (a rocket boosts first, so this is a slight over-lead; `lead_blend` damps it).
func _shot_speed() -> float:
	return float(EnemyRocketScenes.export_of(EnemyRocket.Kind.DUMB, &"cruise_speed", 520.0))


func _telegraph_seconds() -> float:
	return charge_seconds


func _fire_tick(delta: float, can_fire: bool) -> bool:
	if not can_fire:
		_stop_weapon()
		return true
	if not _firing:
		_salvo.start(salvo_count, salvo_gap)
		_firing = true
	for _i in _salvo.advance(delta):
		_launch_one()
	if _salvo.is_running():
		return false
	_firing = false
	return true


func _stop_weapon() -> void:
	_salvo.stop()
	_firing = false
	queue_redraw()


# --- internals ---------------------------------------------------------------------------------------------------------------------------------


## Shortest time between two salvos' first rockets: glow + the salvo + the cooldown.
func _period() -> float:
	return charge_seconds + (salvo_count - 1) * salvo_gap + cooldown_seconds


## The kind of the next rocket: one draw from `rng` (PURSUIT with probability `pursuit_chance`, else DUMB). Public so a row can read the distribution.
func pick_kind() -> EnemyRocket.Kind:
	return EnemyRocket.Kind.PURSUIT if rng.randf() < pursuit_chance else EnemyRocket.Kind.DUMB


func _launch_one() -> void:
	var pursuit := pick_kind() == EnemyRocket.Kind.PURSUIT
	var pool := _pools.get(PURSUIT_POOL if pursuit else DUMB_POOL) as BulletPool
	var rocket: EnemyRocket = pool.acquire(muzzle_position()) as EnemyRocket if pool != null else null
	if rocket == null:
		rockets_refused += 1
		return
	rocket.launch(Vector2.RIGHT.rotated(global_rotation), _aim_point, _host)
	round_fired.emit(rocket)


## Placeholder art (the art task replaces it): a head disc, a stubby barrel and a muzzle lamp that glows through TELEGRAPH.
func _draw() -> void:
	var tip := _muzzle.position.x if _muzzle != null else HEAD_RADIUS * 2.0
	draw_rect(Rect2(0.0, -BARREL_WIDTH * 0.5, tip, BARREL_WIDTH), BARREL_COLOR)
	draw_circle(Vector2.ZERO, HEAD_RADIUS, HEAD_COLOR)
	if _phase == Phase.TELEGRAPH:
		draw_circle(Vector2(tip, 0.0), 7.0, GLOW_COLOR)
