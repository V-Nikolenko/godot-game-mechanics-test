## Level 1's Carrier as numbers (Phase 10 t12; epic plan docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.13, task plan
## docs/plans/cmwafsrbl00b3qs2y1xuez7c5/3-plan.md §2). Shared by `test_level1_heavy_spawns.gd` (column overlap, spill-over, the lit replay's
## attack row) and `test_level1_drone_spawns.gd` (the carrier's swarm drones in the C3 gate), so each number exists once.
##
## A Carrier has no budget and no exit: in Assault it crosses straight down at the constant `assault_cross_speed` and frees itself once its top
## edge is below the projectile world rect (`carrier.gd::_physics_process`). So its life is fixed by where it spawns: the worst case is the
## highest view, camera shake included (`test_level1_specialist_spawns.gd::_static_life()`'s rule). Its x is world-anchored (`.at(x, y)` lands at
## world x 640 + 2x) and sways at most `assault_sway_leash` either side of that; every part's hurtbox stays within `module_x_extent` of the
## hull centre, so the parts sweep world x ± (leash + extent).
##
## No `class_name`: test-only. `preload` it.
extends RefCounted

const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")
const CARRIER := WaveBuilder.CARRIER
const SHIPPED: CarrierConfig = preload("res://assault/scenes/enemies/carrier/carrier_config.tres")  # read only
const _CAMERA_SHAKE := preload("res://global/systems/camera_shake.gd")
## A ship freed on a physics tick is seen gone up to two ticks later (the specialist gate's slack).
const TICK_SLACK := 2.0 / 60.0

static var _body: Vector2 = Vector2.ZERO
static var _hurt_half_width: float = -1.0
static var _rocket_life: float = -1.0


## One `{ "spawn", "trigger", "offset", "delay" }` per Carrier entry of `section`, in list order: `trigger` the wave's EFFECTIVE trigger (the
## running max in list order, the one `WaveManager` uses), `spawn` = trigger + delay. For sections a test has mutated; the shipped lines are
## read through `level1_slice_replay.gd::placed(CARRIER)`.
static func lines(section: LevelSection) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var effective := -INF
	for w in section.waves:
		var wave: WaveResource = w
		effective = maxf(effective, wave.trigger_time)
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene == null or entry.ship_scene.resource_path != CARRIER:
				continue
			out.append({"spawn": effective + entry.spawn_delay, "trigger": effective, "offset": entry.base_offset, "delay": entry.spawn_delay})
	return out


## The Assault projectile world rect (pure constants of `ArenaCamera`).
static func world_rect() -> Rect2:
	var cam := ArenaCamera.new()
	var rect := cam.projectile_world_rect()
	cam.free()
	return rect


## The hull's body size (px), read from `carrier.tscn`. Cached.
static func body_size() -> Vector2:
	if _body == Vector2.ZERO:
		var c := (load(CARRIER) as PackedScene).instantiate() as Carrier
		_body = c.body_size()
		var shape := (c.get_node(^"HurtBox/CollisionShape2D") as CollisionShape2D)
		_hurt_half_width = (shape.shape as RectangleShape2D).size.x * absf(shape.scale.x) * 0.5
		c.free()
	return _body


static func body_half_height() -> float:
	return body_size().y * 0.5


## Half the width of the root `HurtBox` (px): what the lit replay measures a laser gap from.
static func hurt_half_width() -> float:
	body_size()
	return _hurt_half_width


## A wave spawn's world x (the carrier is world-anchored).
static func world_x(design_x: float) -> float:
	return world_rect().get_center().x + design_x * ArenaCamera.WORLD_SCALE


## The worst-case Assault life (s) of a carrier spawned at design y `design_y`: from the highest view (shake included) at
## `cfg.assault_cross_speed` until its top edge passes the world rect's bottom.
static func worst_life(design_y: float, cfg: CarrierConfig = SHIPPED) -> float:
	var world := world_rect()
	var y_spawn := world.get_center().y - ArenaCamera.V_LIMIT - _CAMERA_SHAKE._MAX_OFFSET + design_y * ArenaCamera.WORLD_SCALE
	return TICK_SLACK + (world.end.y + body_half_height() - y_spawn) / cfg.assault_cross_speed


## How far either side of its world x a carrier's parts can reach (px): the sway leash plus the parts' x extent.
static func swept_half_width(cfg: CarrierConfig = SHIPPED) -> float:
	return cfg.assault_sway_leash + cfg.module_x_extent


## The longest a missile-bank rocket lives (s): max `max_time` over the `HullMounts/Dorsal` slot's mount `pool_specs()` scenes (rockets persist
## past the carrier). Cached.
static func rocket_max_life() -> float:
	if _rocket_life >= 0.0:
		return _rocket_life
	var c := (load(CARRIER) as PackedScene).instantiate()
	var variant: int = (c.get_node(^"HullMounts/Dorsal") as TurretMountSlot).variant
	c.free()
	var mount := TurretMountScenes.scene_for(variant).instantiate()
	_rocket_life = 0.0
	for spec: Dictionary in mount.pool_specs():
		var rocket := (spec["scene"] as PackedScene).instantiate()
		_rocket_life = maxf(_rocket_life, float(rocket.get(&"max_time")))
		rocket.free()
	mount.free()
	return _rocket_life


## Per hangar of an UNDAMAGED carrier spawned at `spawn` (section s), port first: `{ "id", "earliest", "latest", "count" }`. The schedule clock
## starts when the hull centre enters the view, so `earliest` (the view entered at once) is a lower bound; a hangar launches only while the
## carrier lives, so `latest` is its worst life. Only for a run with no PANIC: an emergency deployment launches at any moment.
static func launch_windows(spawn: float, design_y: float, cfg: CarrierConfig = SHIPPED) -> Array[Dictionary]:
	var latest := spawn + worst_life(design_y, cfg)
	var port := spawn + cfg.first_launch_delay + cfg.door_open_seconds
	return [
		{"id": CarrierHangars.PORT, "earliest": port, "latest": latest, "count": cfg.assault_launch_count},
		{"id": CarrierHangars.STARBOARD, "earliest": port + cfg.starboard_launch_delay, "latest": latest, "count": cfg.assault_launch_count},
	]


## The C3 intervals of every Carrier's Assault swarm drones in `section` (`DroneConcurrency.squad_intervals()`'s shape): one squad per carrier
## (both hangars share one `SquadController`), port pair first, the first `ATTACKERS_PER_SQUAD` attack-capable. Each interval is
## `[carrier spawn, carrier spawn + worst life + the drone's lifetime]`: PANIC's `emergency_deploy()` launches every unlaunched hangar at once,
## with no schedule and no view check, so a drone can come out at any moment of the carrier's life (review round 1, finding 1).
static func drone_intervals(section: LevelSection, lifetimes: Dictionary, cfg: CarrierConfig = SHIPPED) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := 0
	for line in lines(section):
		var spawn: float = line["spawn"]
		var life := worst_life((line["offset"] as Vector2).y, cfg)
		var key := "carrier:%d" % n
		n += 1
		for i in 2 * cfg.assault_launch_count:
			var capable := i < DroneConcurrency.ATTACKERS_PER_SQUAD
			var drone: float = lifetimes["swarm_attacker"] if capable else lifetimes["swarm_rear"]
			out.append({"start": spawn, "end": spawn + life + drone, "capable": capable, "squad": key})
	return out
