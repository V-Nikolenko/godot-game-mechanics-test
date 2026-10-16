# open_space/scenes/levels/sector_hub.gd
extends Node2D

## Open Space hub. Spawns an idle Swarm Drone squad, a Razor Drone, a fighter pair, a Gatling pair and a Sniper, a Bomber, a Ram Corvette, a Missile Corvette and a Support Ship, each
## patrolling its own anchor point, and assigns the planet config.
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
const FIGHTER: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const GATLING_INTERCEPTOR: PackedScene = preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn")

const SNIPER: PackedScene = preload("res://assault/scenes/enemies/sniper/sniper.tscn")
const BOMBER: PackedScene = preload("res://assault/scenes/enemies/bomber/bomber.tscn")
const RAM_CORVETTE: PackedScene = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette.tscn")
const MISSILE_CORVETTE: PackedScene = preload("res://assault/scenes/enemies/missile_corvette/missile_corvette.tscn")
const SUPPORT_SHIP: PackedScene = preload("res://assault/scenes/enemies/support_ship/support_ship.tscn")

## Fighters and Gatlings patrol in pairs, a squad of two each (epic plan §2.10).
const SHOOTER_SQUAD_SIZE := 2

## 0 = every drone's rng seed randomizes; any other value seeds a local RandomNumberGenerator that
## in turn seeds each drone's own brain, so the whole patrol is reproducible.
@export var patrol_seed: int = 0
@export var squad_size: int = 4
@export var patrol_ring_radius: float = 1300.0
@export var swarm_anchor_bearing_deg: float = 90.0
@export var razor_anchor_bearing_deg: float = 270.0

## The fighter pair and the Gatling pair patrol a separate, wider ring (epic plan §2.10): their
## `perceive_radius` (540 / 560) is wider than a drone's, so the 1300 ring leaves too little room.
@export var shooter_ring_radius: float = 1500.0
@export var fighter_anchor_bearing_deg: float = 180.0
@export var gatling_anchor_bearing_deg: float = 0.0

## The Sniper, Bomber and Ram Corvette (epic plan §2.10, phase 4) patrol a third, widest ring: their
## `perceive_radius` is 600-700 px. 315 deg stays free - it is the diagonal closest to the pickup bench.
@export var specialist_ring_radius: float = 1700.0
@export var sniper_anchor_bearing_deg: float = 135.0
@export var bomber_anchor_bearing_deg: float = 45.0
@export var ram_anchor_bearing_deg: float = 225.0

## The Missile Corvette (epic plan §2.17, phase 5) takes the free 315 deg diagonal on a fourth ring: its `perceive_radius`
## is 720 px, and at 1900 the nearest interactable (the ship-boost pickup, 1287 px away) clears its idle ring plus that
## by +417 px. The Support Ship has no anchor of its own: it shares the Ram Corvette's, so the two engage together and
## the support wards the Ram (the Support + Ram combination, §37).
@export var missile_corvette_ring_radius: float = 1900.0
@export var missile_corvette_anchor_bearing_deg: float = 315.0

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
	_spawn_fighter_squad(_shooter_anchor(fighter_anchor_bearing_deg), rng)
	_spawn_gatling_squad(_shooter_anchor(gatling_anchor_bearing_deg), rng)
	# Appended after every existing draw, so the groups above keep their seeds.
	_spawn_sniper(_specialist_anchor(sniper_anchor_bearing_deg), rng)
	_spawn_bomber(_specialist_anchor(bomber_anchor_bearing_deg), rng)
	_spawn_ram_corvette(_specialist_anchor(ram_anchor_bearing_deg), rng)
	# Phase 5, draws 13 and 14: appended after the twelve above, so every existing seed is unchanged.
	_spawn_missile_corvette(_missile_corvette_anchor(), rng)
	_spawn_support_ship(_specialist_anchor(ram_anchor_bearing_deg), rng)

func _anchor(bearing_deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(bearing_deg)) * patrol_ring_radius

func _shooter_anchor(bearing_deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(bearing_deg)) * shooter_ring_radius

func _specialist_anchor(bearing_deg: float) -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(bearing_deg)) * specialist_ring_radius

func _missile_corvette_anchor() -> Vector2:
	return Vector2.RIGHT.rotated(deg_to_rad(missile_corvette_anchor_bearing_deg)) * missile_corvette_ring_radius

func _spawn_missile_corvette(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var corvette := MISSILE_CORVETTE.instantiate() as MissileCorvette
	corvette.global_position = anchor
	var brain := corvette.get_node("Brain") as MissileCorvetteBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(corvette)

## Shares the Ram Corvette's anchor and its idle/perceive radii, so the Ram's clearance holds for it.
func _spawn_support_ship(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var support := SUPPORT_SHIP.instantiate() as SupportShip
	support.global_position = anchor
	var brain := support.get_node("Brain") as SupportShipBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(support)

## A lone specialist: `patrol_anchor` and the seed are set before `add_child()`, so the brain's `_start()`
## builds its hub idle around that anchor.
func _spawn_sniper(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var sniper := SNIPER.instantiate() as Sniper
	sniper.global_position = anchor
	var brain := sniper.get_node("Brain") as SniperBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(sniper)

func _spawn_bomber(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var bomber := BOMBER.instantiate() as Bomber
	bomber.global_position = anchor
	var brain := bomber.get_node("Brain") as BomberBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(bomber)

func _spawn_ram_corvette(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var ram := RAM_CORVETTE.instantiate() as RamCorvette
	ram.global_position = anchor
	var brain := ram.get_node("Brain") as RamCorvetteBrain
	brain.rng_seed = _next_seed(rng)
	brain.patrol_anchor = anchor
	enemy_container.add_child(ram)

## A fighter pair: one shared `SquadController` and `patrol_anchor`, both set before `add_child()`
## (`Fighter._ready()` joins the squad itself). Drawn from `rng` after the drones, so adding the
## shooters leaves the drones' seeds unchanged.
func _spawn_fighter_squad(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var squad := SquadController.new()
	for i: int in SHOOTER_SQUAD_SIZE:
		var fighter := FIGHTER.instantiate() as Fighter
		fighter.global_position = anchor
		var brain := fighter.get_node("Brain") as FighterBrain
		brain.rng_seed = _next_seed(rng)
		brain.patrol_anchor = anchor
		fighter.squad = squad
		enemy_container.add_child(fighter)

## A Gatling pair, wired like the fighter pair; a squad of two converges its streams.
func _spawn_gatling_squad(anchor: Vector2, rng: RandomNumberGenerator) -> void:
	var squad := SquadController.new()
	for i: int in SHOOTER_SQUAD_SIZE:
		var gatling := GATLING_INTERCEPTOR.instantiate() as GatlingInterceptor
		gatling.global_position = anchor
		var brain := gatling.get_node("Brain") as GatlingInterceptorBrain
		brain.rng_seed = _next_seed(rng)
		brain.patrol_anchor = anchor
		gatling.squad = squad
		enemy_container.add_child(gatling)

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
