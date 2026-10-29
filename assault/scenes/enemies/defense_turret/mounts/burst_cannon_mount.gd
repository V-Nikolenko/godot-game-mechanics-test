## BurstCannonMount - the BURST_CANNON variant of `TurretMount` (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.7; Phase 8 t6).
##
## TELEGRAPH is a `charge_seconds` charge (the host's light goes CHARGING; no line is drawn), then a burst of `burst_count` Pulse rounds
## `burst_gap` apart from a `BurstClock`, the first on the tick the charge ends. A due round leaves only while `aim_error()` is inside half the
## `fire_cone_deg`; one that falls outside is held (dropped, counted in `shots_held`), so no round ever leaves wide. The mount keeps tracking
## through the charge and the burst. Losing `can_fire` stops the burst; rounds already in flight belong to the pool.
##
## Rounds come from one `BulletPool` the host builds from `pool_specs()` as its own root child, so they land in the host's container. Its size
## is `EnemyRounds.pool_size_for()` over the shortest burst period (charge + burst + cooldown) and the round's own `max_time`.
##
## Tuning is this scene's exports (`burst_cannon_mount.tscn`); gates read them through `TurretMountScenes.export_of()`.
class_name BurstCannonMount
extends TurretMount

## The pool's key in `setup()`'s `pools` and the base of its node name.
const POOL_NAME := &"PulsePool"
## Fallback for a round scene that does not author its `ProjectileLifetime.max_time` (the `enemy_bullet.tscn` default).
const DEFAULT_ROUND_MAX_TIME := 18.0
const HEAD_RADIUS := 13.0
const BARREL_WIDTH := 6.0
const HEAD_COLOR := Color(0.36, 0.4, 0.46, 1.0)
const BARREL_COLOR := Color(0.62, 0.66, 0.72, 1.0)

## TELEGRAPH: the charge before the burst, s.
@export var charge_seconds: float = 0.4
@export var burst_count: int = 4
## Seconds between rounds of one burst.
@export var burst_gap: float = 0.12
## The speed rounds leave at, px/s (the Pulse round's own 300).
@export var round_speed: float = 300.0
@export var round_scene: PackedScene = EnemyRounds.PULSE

## Due rounds not fired because the aim was outside the cone.
var shots_held: int = 0
## Due rounds not fired because the pool was exhausted.
var shots_refused: int = 0

var _burst := BurstClock.new()
var _bursting: bool = false


func pool_specs() -> Array[Dictionary]:
	var max_time := float(EnemyBeamScenes.export_of_scene(round_scene, &"max_time", DEFAULT_ROUND_MAX_TIME, ^"ProjectileLifetime"))
	var period := charge_seconds + (burst_count - 1) * burst_gap + cooldown_seconds
	var specs: Array[Dictionary] = [{
		"name": POOL_NAME,
		"scene": round_scene,
		"size": EnemyRounds.pool_size_for(burst_count, max_time, period),
		"persist": false,
	}]
	return specs


func _ready() -> void:
	queue_redraw()


func _shot_speed() -> float:
	return round_speed


func _telegraph_seconds() -> float:
	return charge_seconds


func _fire_tick(delta: float, can_fire: bool) -> bool:
	if not can_fire:
		_stop_weapon()
		return true
	if not _bursting:
		_burst.start(burst_count, burst_gap)
		_bursting = true
	for _i in _burst.advance(delta):
		_shoot()
	if _burst.is_running():
		return false
	_bursting = false
	return true


func _stop_weapon() -> void:
	_burst.stop()
	_bursting = false


func _shoot() -> void:
	if aim_error() > deg_to_rad(fire_cone_deg) * 0.5:
		shots_held += 1
		return
	var pool := _pools.get(POOL_NAME) as BulletPool
	var projectile: EnemyBullet = pool.acquire(muzzle_position()) as EnemyBullet if pool != null else null
	if projectile == null:
		shots_refused += 1
		return
	projectile.speed = round_speed
	projectile.set_direction(Vector2.RIGHT.rotated(global_rotation))
	round_fired.emit(projectile)


## Placeholder art (the art task replaces it): a head disc and a barrel along +X to the muzzle.
func _draw() -> void:
	var tip := _muzzle.position.x if _muzzle != null else HEAD_RADIUS * 2.0
	draw_rect(Rect2(0.0, -BARREL_WIDTH * 0.5, tip, BARREL_WIDTH), BARREL_COLOR)
	draw_circle(Vector2.ZERO, HEAD_RADIUS, HEAD_COLOR)
