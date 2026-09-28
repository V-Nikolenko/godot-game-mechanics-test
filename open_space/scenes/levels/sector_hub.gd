# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns an idle Swarm Drone squad and a Razor Drone patrolling their own anchor
## points, and assigns the planet config.
## To change this planet's missions, background, or sprite — edit edelia.tres.
## To use a different config, change the path in _configure_planet().
##
## docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.11: `swarm_anchor_bearing_deg` (90°, below the
## hub) and `razor_anchor_bearing_deg` (270°, above it) sit in the planet-free arcs on the
## `patrol_ring_radius` ring — every mission trigger, pickup and the player's spawn clear each
## group's own idle ring plus its `perceive_radius`, pinned in
## `tests/integration/test_sector_hub_patrol.gd`. `patrol_ring_radius` is 1300, not the plan's
## 1000 — at 1000 the nearest weapon-unlocker pickup is only 285 px clear of the Razor's idle ring,
## short of its 450 px perceive_radius; see docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md, Phase
## 2. Replaces the hub's old ambient drone spawn (Enemy rework phase 2).

const SWARM_DRONE: PackedScene = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn")
const RAZOR_DRONE: PackedScene = preload("res://assault/scenes/enemies/razor_drone/razor_drone.tscn")

## 0 = every drone's rng seed randomizes; any other value seeds a local RandomNumberGenerator that
## in turn seeds each drone's own brain, so the whole patrol is reproducible.
@export var patrol_seed: int = 0
@export var squad_size: int = 4
@export var patrol_ring_radius: float = 1300.0
@export var swarm_anchor_bearing_deg: float = 90.0
@export var razor_anchor_bearing_deg: float = 270.0

@onready var enemy_container: Node2D = $EnemyContainer

func _ready() -> void:
	_spawn_patrol()

func _spawn_patrol() -> void:
	var rng := RandomNumberGenerator.new()
	if patrol_seed != 0:
		rng.seed = patrol_seed
	else:
		rng.randomize()
	_spawn_swarm_squad(_anchor(swarm_anchor_bearing_deg), rng)
	_spawn_razor(_anchor(razor_anchor_bearing_deg), rng)

func _anchor(bearing_deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(bearing_deg)) * patrol_ring_radius

## One squad, one shared `SquadController` and `patrol_anchor` — `SwarmDrone._ready()` calls
## `squad.join(self)` itself once `squad` is set, so it must be assigned before `add_child()`.
func _spawn_swarm_squad(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var squad := SquadController.new()
	for i: int in squad_size:
		var drone := SWARM_DRONE.instantiate() as SwarmDrone
		drone.global_position = anchor
		var brain := drone.get_node("Brain") as SwarmDroneBrain
		brain.rng_seed = _next_seed(rng)
		brain.patrol_anchor = anchor
		drone.squad = squad
		enemy_container.add_child(drone)

func _spawn_razor(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var drone := RAZOR_DRONE.instantiate() as RazorDrone
	drone.global_position = anchor
	var brain := drone.get_node("Brain") as RazorDroneBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(drone)

## A nonzero rng_seed: 0 means "randomize" to `EnemyBrain._ready()`, which would silently un-seed
## the one draw in 2^32 that lands on it.
func _next_seed(rng: RandomNumberGenerator) -> int:
	var s := rng.randi()
	return s if s != 0 else 1
