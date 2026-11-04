## The Laser Tender (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.13; task plan docs/plans/cmvqw0vnz018nqs2xv56q6a0a/3-plan.md; Phase 8 t13):
## the "controller ship" of IDEAS §6.10. A slow carrier with two Twin-Laser Drones docked in visible cradles; it holds at range and launches them in
## a V toward two points either side of the player's predicted path (Attack B). Behaviour: `ENEMY.md` beside this file.
##
## A `LaserTenderBrain` decides and an `EnemyMover` moves it, through `BaseEnemy`'s shared tick, so this script defines no `_physics_process` and
## writes no motion (`test_twin_laser_drones.gd` sweeps it through any receiver: it places drones, it never moves them). One `CircleShape2D` r 40 is
## shared by the body, the `HurtBox` and the `ContactHitBox` (COLLISION). No gun. `CradleL` / `CradleR` (`Marker2D`) each hold a `DockedDrone`
## (a textureless placeholder the art task replaces) shown while that cradle holds a drone. The `StateLight` between them is the cradle light.
##
## `_ready()` copies the config onto every node that uses it (the `.tres` wins over the scene) and joins group `enemies`.
##
## Spawn with b.laser_tender().at(x, y).
class_name LaserTender
extends BaseEnemy

## Placeholder art (the art task replaces it): a dark disc with a rim and two cradle notches.
const HULL_COLOR := Color(0.18, 0.19, 0.24, 1.0)
const RIM_COLOR := Color(0.5, 0.36, 0.3, 1.0)
const NOTCH_COLOR := Color(0.08, 0.08, 0.1, 1.0)
const NOTCH_RADIUS := 13.0

@export var config: LaserTenderConfig = load("res://assault/scenes/enemies/laser_tender/laser_tender_config.tres")
## What `launch_pair()` instantiates. A Ph10 / Ph11 caller may swap it; the brain plans with this scene's own drone tuning.
@export var drone_scene: PackedScene = load("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn")

var _docked: int = 2
var _launches: int = 0
var _pair: TwinLaserPair
## Every drone this tender launched (any rig), pruned of freed nodes: the ones it may take back with `dock()`.
var _launched: Array[Node2D] = []

@onready var _tender_brain: LaserTenderBrain = $Brain
@onready var _tender_mover: EnemyMover = $EnemyMover
@onready var _cradle_l: Marker2D = $CradleL
@onready var _cradle_r: Marker2D = $CradleR


func _ready() -> void:
	super._ready()
	add_to_group("enemies")
	if config:
		_apply_config(config)
	_set_docked(2)
	queue_redraw()


func _apply_config(cfg: LaserTenderConfig) -> void:
	health.max_health = cfg.max_health
	health.current_health = cfg.max_health
	score_value = cfg.score_value
	if contact_hit_box:
		contact_hit_box.damage = cfg.collision_damage
	_tender_mover.max_speed = cfg.max_speed
	_tender_mover.acceleration = cfg.acceleration
	_tender_brain.config = cfg


func brain() -> LaserTenderBrain:
	return _tender_brain


func state_light() -> StateLight:
	return get_node_or_null("StateLight") as StateLight


## The body circle's radius (the scene's shared `CircleShape2D`).
func body_radius() -> float:
	var cs := get_node_or_null("CollisionShape2D") as CollisionShape2D
	var circle := cs.shape as CircleShape2D if cs != null else null
	return circle.radius if circle != null else 0.0


## [CradleL, CradleR].
func cradles() -> Array[Marker2D]:
	return [_cradle_l, _cradle_r]


## Drones in the cradles (0..2).
func docked_count() -> int:
	return _docked


## The last rig this tender launched, or null.
func pair() -> TwinLaserPair:
	return _pair


## True while the brain idles (IDLE, NOTICING or RETURNING; t14): a launched pair reads it (duck-typed, from the drone brain's side) and flies
## back to dock.
func recalls_drones() -> bool:
	return _tender_brain != null and LaserTenderBrain._is_idle_phase(_tender_brain.phase)


## How many pairs this tender has launched.
func launches() -> int:
	return _launches


## The live drones this tender launched (any rig).
func launched_drones() -> Array[Node2D]:
	_prune()
	return _launched.duplicate()


## Launches the docked pair toward [param points] (`points[0]` for the `CradleL` drone A, `points[1]` for the `CradleR` drone B: the caller orders
## them) and returns the new rig; null when there are fewer than two points, no parent or no drone scene. The Ph10 (Carrier hangars) / Ph11 (fortress
## bays) seam.
##
## The two drones are instantiated from `drone_scene` at the cradles, seeded from the tender brain's `rng`, given a mutual collision exception with
## the tender (they start inside its body and dock back into it), added as siblings in the tender's parent (A first, so A leads on real physics),
## bound with `TwinLaserPair.bind(a, b, self)` (the tender joins the pair's owner group, so its beam never hurts it), put in LAUNCHED and announced
## with `EventBus.enemy_spawned_orphan`. **Calling rule:** the drones are added synchronously, so call this on the physics step or from idle code,
## never from a physics callback (`area_entered` / `body_entered`), where a caller must `call_deferred` it.
func launch_pair(points: PackedVector2Array) -> TwinLaserPair:
	var parent := get_parent()
	if points.size() < 2 or parent == null or drone_scene == null:
		return null
	_leave_finished_rig()
	var a := drone_scene.instantiate() as Node2D
	var b := drone_scene.instantiate() as Node2D
	var drones: Array[Node2D] = [a, b]
	var markers: Array[Marker2D] = [_cradle_l, _cradle_r]
	var rng: RandomNumberGenerator = _tender_brain.rng if _tender_brain != null else null
	for i in drones.size():
		var drone := drones[i]
		var at := markers[i].global_position
		drone.position = (parent as Node2D).to_local(at) if parent is Node2D else at
		var drone_brain := drone.get_node_or_null("Brain") as EnemyBrain
		if drone_brain != null and rng != null:
			drone_brain.rng_seed = rng.randi_range(1, 0x7FFFFFFF)
		if drone is PhysicsBody2D:
			(drone as PhysicsBody2D).add_collision_exception_with(self)
			add_collision_exception_with(drone)
	for drone in drones:
		parent.add_child(drone)
	var rig := TwinLaserPair.bind(a, b, self)
	rig.launch(points[0], points[1], config.launch_speed, config.launch_max_seconds)
	_pair = rig
	_launches += 1
	_set_docked(0)
	for drone in drones:
		_launched.append(drone)
		EventBus.enemy_spawned_orphan.emit(drone)
	return rig


## Takes a returning drone back into a cradle: frees it (it docked, it did not die) and counts it as docked. The brain calls it for a SOLO drone this
## tender launched (`launched_drones()`).
func dock(drone: Node2D) -> void:
	if not is_instance_valid(drone) or drone.is_queued_for_deletion():
		return
	_launched.erase(drone)
	drone.queue_free()
	_set_docked(mini(_docked + 1, 2))


## The end of REARM: both cradles hold a drone again.
func rearm_cradles() -> void:
	_set_docked(2)


func _set_docked(n: int) -> void:
	_docked = clampi(n, 0, 2)
	var l := get_node_or_null("CradleL/DockedDrone") as CanvasItem
	var r := get_node_or_null("CradleR/DockedDrone") as CanvasItem
	if l != null:
		l.visible = _docked >= 1
	if r != null:
		r.visible = _docked >= 2


func _prune() -> void:
	for i in range(_launched.size() - 1, -1, -1):
		var d: Variant = _launched[i]
		if not is_instance_valid(d) or (d as Node).is_queued_for_deletion():
			_launched.remove_at(i)


## Before a new launch: once every drone of the previous rig is gone, the tender leaves that rig's owner group (a live drone of it may still hold a
## fading beam, so the group is kept until then; only the previous rig is checked, which is harmless).
func _leave_finished_rig() -> void:
	if _pair == null:
		return
	var gone := true
	for d: Variant in [_pair.drone_a, _pair.drone_b]:
		if is_instance_valid(d) and not (d as Node).is_queued_for_deletion():
			gone = false
	if gone and _pair.owner_group != &"" and is_in_group(_pair.owner_group):
		remove_from_group(_pair.owner_group)


func _draw() -> void:
	var r := body_radius()
	draw_circle(Vector2.ZERO, r, HULL_COLOR)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, RIM_COLOR, 2.0)
	for m: Marker2D in [_cradle_l, _cradle_r]:
		if m != null:
			draw_circle(m.position, NOTCH_RADIUS, NOTCH_COLOR)
