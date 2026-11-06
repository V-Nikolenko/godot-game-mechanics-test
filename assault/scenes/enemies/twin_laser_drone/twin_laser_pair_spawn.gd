## TwinLaserPairSpawn - spawns a bound pair of Twin-Laser Drones (docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.12; Phase 8 t12). A wave
## (`WaveBuilder.twin_laser_pair()`) or a hub scene places it; it is not an enemy.
##
## On `_ready()` it defers `spawn_pair()` (public and idempotent, so a hand-ticked test calls it directly; the `TurretGroup.spawn_members()`
## precedent): two drones from `drone_scene`, added as siblings in its own parent (A first, so A leads on real physics) at -/+ `rig_length / 2` along
## its local X, their brains seeded `rng_seed` / `rng_seed + 1` (when non-zero), bound with `TwinLaserPair.bind()` and announced with
## `EventBus.enemy_spawned_orphan`. Then it frees itself. Never in `enemies`, never scored. Both brains get its own position as their `patrol_anchor`
## (t14): a hub layout places the spawner at the pair's patrol point.
class_name TwinLaserPairSpawn
extends Node2D

## 0 = each drone's brain randomizes its own rng; otherwise drone A gets this seed and drone B this + 1.
@export var rng_seed: int = 0
@export var drone_scene: PackedScene = load("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone.tscn")

## Read by `ScoreTracker` for a wave spawn: the spawner is never in a wave tally and never an escape.
var counts_toward_wave_clear: bool = false
var counts_as_escape: bool = false
var score_value: int = 0

var _pair: TwinLaserPair
var _spawned: bool = false


func _ready() -> void:
	spawn_pair.call_deferred()


## Spawns and binds the pair (once), then queues this node for deletion. Returns the rig (null when nothing could be spawned).
func spawn_pair() -> TwinLaserPair:
	if _spawned or not is_inside_tree() or is_queued_for_deletion() or drone_scene == null:
		return _pair
	var parent := get_parent()
	if parent == null:
		return null
	_spawned = true
	var a := drone_scene.instantiate() as Node2D
	var b := drone_scene.instantiate() as Node2D
	var cfg: Variant = a.get(&"config")
	var half: float = (cfg.rig_length if cfg is TwinLaserDroneConfig else 0.0) * 0.5
	var along := global_transform.x.normalized()
	var drones: Array[Node2D] = [a, b]
	for i in drones.size():
		var drone := drones[i]
		var at := global_position + along * half * (-1.0 if i == 0 else 1.0)
		drone.position = (parent as Node2D).to_local(at) if parent is Node2D else at
		var brain := drone.get_node_or_null("Brain") as EnemyBrain
		if brain != null and rng_seed != 0:
			brain.rng_seed = rng_seed + i
		if brain != null:
			brain.set(&"patrol_anchor", global_position)  # t14: the pair shares one hub anchor, the spawner's position (the pair's midpoint)
		parent.add_child(drone)
	_pair = TwinLaserPair.bind(a, b)
	for drone in drones:
		EventBus.enemy_spawned_orphan.emit(drone)
	queue_free()
	return _pair


## The rig this spawner bound (null before `spawn_pair()`).
func pair() -> TwinLaserPair:
	return _pair
