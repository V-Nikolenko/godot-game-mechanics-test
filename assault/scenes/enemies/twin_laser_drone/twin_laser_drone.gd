## TwinLaserDrone - one end of a twin-laser pair (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12; Phase 8 t12). Behaviour: `ENEMY.md` beside
## this file.
##
## A small `BaseEnemy` driven by a `TwinLaserDroneBrain` and an `EnemyMover` through `BaseEnemy`'s shared tick, so this script defines no
## `_physics_process` and writes no motion. One `CircleShape2D` r 13 is shared by the body (layer 1, so it stops on a wreck), the `HurtBox` and the
## `ContactHitBox` (COLLISION, `collision_damage` from the `.tres`). The `StateLight` is the lens at the nose.
##
## Two drones are bound into a `TwinLaserPair` (the rig, a RefCounted both brains hold) by a `TwinLaserPairSpawn`; the pair's `EnemyBeam` is a child
## of drone A. `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and joins group `enemies`.
##
## Spawn a pair with b.twin_laser_pair().at(x, y).
class_name TwinLaserDrone
extends BaseEnemy

## Placeholder art (the art task replaces it): a dark disc with a rim and the lens dot at the nose.
const HULL_COLOR := Color(0.16, 0.17, 0.22, 1.0)
const RIM_COLOR := Color(0.55, 0.3, 0.32, 1.0)
const LENS_COLOR := Color(1.0, 0.35, 0.3, 1.0)
const LENS_RADIUS := 3.5

@export var config: TwinLaserDroneConfig = load("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")

@onready var _drone_brain: TwinLaserDroneBrain = $Brain
@onready var _drone_mover: EnemyMover = $EnemyMover


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	queue_redraw()


func _apply_config(cfg: TwinLaserDroneConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_drone_mover.max_speed = cfg.max_speed
	_drone_mover.acceleration = cfg.acceleration
	_drone_brain.config = cfg


func brain() -> TwinLaserDroneBrain:
	return _drone_brain


## The rig this drone belongs to, or null (a lone drone).
func pair() -> TwinLaserPair:
	return _drone_brain.pair if _drone_brain != null else null


func state_light() -> StateLight:
	return get_node_or_null("StateLight") as StateLight


## The body circle's radius (the scene's shared `CircleShape2D`).
func body_radius() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle := cs.shape as CircleShape2D if cs != null else null
	return circle.radius if circle != null else 0.0


func _draw() -> void:
	var r := body_radius()
	draw_circle(Vector2.ZERO, r, HULL_COLOR)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, RIM_COLOR, 2.0)
	draw_circle(Vector2(0.0, r * 0.45), LENS_RADIUS, LENS_COLOR)
