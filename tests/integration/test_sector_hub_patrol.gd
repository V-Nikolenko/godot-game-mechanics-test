## INTENT tests for SectorHub's ambient patrol (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md
## §2.11; task cmuj4y8s70084p52x8g2hl0tm). Replaces the retired hub-drone characterization test and
## the ambient-spawn pin `test_level1_drone_spawns.gd` used to carry — the old grey hub drone is
## gone, so there is nothing left to characterize; `_spawn_patrol()` is new code and this file
## asserts intent.
##
## Two techniques, for two different things:
## - The **clearance** cases read `sector_hub.tscn` the way every other hub test does —
##   instantiated, never added to the tree (`test_hub_log_placement.gd`'s established pattern) —
##   since they only need real node positions, not `_ready()`'s side effects.
## - The **spawn-behaviour** cases (composition, shared anchors, reproducibility, frame-0
##   perception, the pulse's container) need `_spawn_patrol()` to actually run, so they build a
##   MINIMAL harness instead of the whole scene: a bare `Node2D` running the real `sector_hub.gd`
##   script plus an `EnemyContainer` child, under `enemy_ai_harness.gd`'s `open_space()` root (a
##   fake player in group "player", no `ArenaCamera` — matching the real hub, which has neither a
##   corridor nor an `ArenaCamera`). Loading the full scene (player ship, HUD, three mission
##   triggers) would cost more without proving more; the clearance cases already cover the real
##   node positions those pieces would add.
extends GutTest

const HUB_SCENE: PackedScene = preload("res://open_space/scenes/levels/sector_hub.tscn")
const HUB_SCRIPT := "res://open_space/scenes/levels/sector_hub.gd"
const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")

const SWARM_CONFIG: SwarmDroneConfig = preload(
		"res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres")
const RAZOR_CONFIG: RazorDroneConfig = preload(
		"res://assault/scenes/enemies/razor_drone/razor_drone_config.tres")

const DT := 1.0 / 60.0
const PATROL_SEED := 20260928

var _player_spawn: Vector2 = Vector2.ZERO


func before_all() -> void:
	var hub := HUB_SCENE.instantiate()
	_player_spawn = (hub.get_node("PlayerShip") as Node2D).position
	hub.free()


# ── Geometry: §2.11's clearance table, computed from the real scene ────────────────────────────

## Every direct child of `hub` a patrol must stay clear of: every mission trigger (planet or
## station), every pickup, and the player's own spawn point.
func _interactable_points(hub: Node) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for child: Node in hub.get_children():
		if child is MissionTrigger or child is PickupBase:
			points.append((child as Node2D).position)
	var player := hub.get_node_or_null("PlayerShip") as Node2D
	if player != null:
		points.append(player.position)
	return points


func _assert_group_clears(anchor: Vector2, worst_idle_offset: float, perceive_radius: float,
		points: Array[Vector2], label: String) -> void:
	for p: Vector2 in points:
		var dist := p.distance_to(anchor)
		var clearance := dist - worst_idle_offset
		assert_gt(clearance, perceive_radius,
				"%s anchor %s must clear %s by more than perceive_radius (dist %.1f, clearance %.1f, need > %.1f)"
				% [label, anchor, p, dist, clearance, perceive_radius])


func test_the_walk_actually_found_interactables_and_the_player_spawn() -> void:
	# Without this, the clearance cases below would pass vacuously if the walk ever broke.
	var hub := HUB_SCENE.instantiate()
	var points := _interactable_points(hub)
	assert_gt(points.size(), 15,
			"expected sector_hub.tscn to place several planets/pickups plus the player spawn")
	hub.free()


func test_swarm_anchor_clears_every_planet_pickup_and_the_player_spawn() -> void:
	var hub := HUB_SCENE.instantiate()
	var anchor := Vector2.RIGHT.rotated(deg_to_rad(float(hub.swarm_anchor_bearing_deg))) \
			* float(hub.patrol_ring_radius)
	var worst_idle_offset := SWARM_CONFIG.idle_radius + SWARM_CONFIG.separation_radius
	_assert_group_clears(anchor, worst_idle_offset, SWARM_CONFIG.perceive_radius,
			_interactable_points(hub), "Swarm")
	hub.free()


func test_razor_anchor_clears_every_planet_pickup_and_the_player_spawn() -> void:
	var hub := HUB_SCENE.instantiate()
	var anchor := Vector2.RIGHT.rotated(deg_to_rad(float(hub.razor_anchor_bearing_deg))) \
			* float(hub.patrol_ring_radius)
	var worst_idle_offset := RAZOR_CONFIG.idle_radius + RAZOR_CONFIG.idle_radius_jitter
	_assert_group_clears(anchor, worst_idle_offset, RAZOR_CONFIG.perceive_radius,
			_interactable_points(hub), "Razor")
	hub.free()


# ── No reference to the retired ambient hub drone remains anywhere in the project ──────────────

const _SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import", ".claude"]
## Built by concatenation, never as a contiguous literal — this file is itself scanned by the sweep
## below, and writing the retired class/file name out in full here would trip it on itself.
const _PATROL_TERMS := ["Patrol" + "Drone", "patrol" + "_drone"]


func _collect_files(dir_path: String, extensions: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not (entry.begins_with(".") or _SKIPPED_DIRS.has(entry)):
				found.append_array(_collect_files(full, extensions))
		else:
			for ext: String in extensions:
				if entry.ends_with("." + ext):
					found.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## N12: scoped to `.gd`/`.tscn`/`.tres` — `docs/**/*.md` legitimately names the retired enemy.
func test_no_reference_to_the_retired_ambient_drone_remains_in_gd_tscn_or_tres() -> void:
	var files := _collect_files("res://", ["gd", "tscn", "tres"])
	assert_gt(files.size(), 100, "sanity: the sweep found real project files")
	var offenders: Array[String] = []
	for file_path: String in files:
		var text := FileAccess.get_file_as_string(file_path)
		for term: String in _PATROL_TERMS:
			if text.contains(term):
				offenders.append("%s (%s)" % [file_path, term])
				break
	assert_true(offenders.is_empty(),
			"a reference to the retired ambient hub drone's class/file name remains in: %s"
			% ", ".join(offenders))


# ── Spawn behaviour: a minimal harness runs the real sector_hub.gd script ──────────────────────

## A bare `Node2D` running the real `sector_hub.gd` script, with an `EnemyContainer` child (the
## only structural piece `_spawn_patrol()` needs), under an `enemy_ai_harness.gd` `open_space()`
## root — a fake player in group "player", no `ArenaCamera`. `patrol_seed` (and optionally
## `squad_size`) are set before the node enters the tree, since `_ready()` is what spawns the
## patrol. Every spawned drone's automatic physics is switched off immediately so callers can
## hand-tick it (tests/README.md: "keep _physics_process out of the tree and call it by hand").
func _spawn_hub(patrol_seed: int, squad_size: int = -1, player_pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var h: RefCounted = HARNESS.open_space()
	h.player.global_position = player_pos
	var hub := Node2D.new()
	hub.set_script(load(HUB_SCRIPT))
	var container := Node2D.new()
	container.name = "EnemyContainer"
	hub.add_child(container)
	hub.set("patrol_seed", patrol_seed)
	if squad_size >= 0:
		hub.set("squad_size", squad_size)
	h.root.add_child(hub)
	add_child_autofree(h.root)
	for c: Node in container.get_children():
		c.set_physics_process(false)
	return {"h": h, "hub": hub, "container": container}


func _tick(drone: BaseEnemy, dt: float = DT) -> void:
	var before := drone.global_position
	drone._physics_process(dt)
	drone.global_position = before + drone.velocity * dt


func _tick_all(drones: Array, dt: float = DT) -> void:
	for d in drones:
		if is_instance_valid(d):
			_tick(d, dt)


func _swarm_and_razor(container: Node2D) -> Dictionary:
	var swarms: Array[SwarmDrone] = []
	var razor: RazorDrone = null
	for c: Node in container.get_children():
		if c is SwarmDrone:
			swarms.append(c)
		elif c is RazorDrone:
			razor = c
	return {"swarms": swarms, "razor": razor}


func test_spawns_one_swarm_squad_and_one_razor_drone() -> void:
	var built := _spawn_hub(PATROL_SEED)
	var container: Node2D = built.container
	var found := _swarm_and_razor(container)
	var swarms: Array = found.swarms
	assert_eq(swarms.size(), 4, "the default squad_size Swarm Drones spawned")
	assert_not_null(found.razor, "exactly one Razor Drone spawned")
	assert_eq(container.get_child_count(), swarms.size() + 1,
			"nothing else spawned into EnemyContainer")

	var squad: SquadController = (swarms[0] as SwarmDrone).squad if not swarms.is_empty() else null
	assert_not_null(squad, "the Swarm squad shares a SquadController")
	for d: SwarmDrone in swarms:
		assert_eq(d.squad, squad, "every Swarm member shares the same SquadController")
	if squad != null:
		assert_eq(squad.member_count(), swarms.size(), "every spawned member joined the board")


func test_squad_size_is_configurable() -> void:
	var built := _spawn_hub(PATROL_SEED, 2)
	var found := _swarm_and_razor(built.container)
	assert_eq((found.swarms as Array).size(), 2, "squad_size drives the spawned count")


func test_every_member_carries_its_groups_shared_patrol_anchor() -> void:
	var built := _spawn_hub(PATROL_SEED)
	var hub: Node2D = built.hub
	var swarm_anchor := Vector2.RIGHT.rotated(deg_to_rad(float(hub.swarm_anchor_bearing_deg))) \
			* float(hub.patrol_ring_radius)
	var razor_anchor := Vector2.RIGHT.rotated(deg_to_rad(float(hub.razor_anchor_bearing_deg))) \
			* float(hub.patrol_ring_radius)
	var found := _swarm_and_razor(built.container)
	for d: SwarmDrone in found.swarms:
		assert_eq((d.get_node("Brain") as SwarmDroneBrain).patrol_anchor, swarm_anchor,
				"every Swarm member shares the squad's patrol_anchor")
	var razor: RazorDrone = found.razor
	assert_not_null(razor, "sanity: a Razor Drone spawned")
	if razor != null:
		assert_eq((razor.get_node("Brain") as RazorDroneBrain).patrol_anchor, razor_anchor,
				"the Razor patrols its own anchor")


func _brain_seeds(container: Node2D) -> Array[int]:
	var seeds: Array[int] = []
	for c: Node in container.get_children():
		seeds.append(int((c.get_node("Brain") as EnemyBrain).rng_seed))
	return seeds


func test_a_fixed_patrol_seed_reproduces_the_same_brain_seeds() -> void:
	var a := _spawn_hub(PATROL_SEED)
	var b := _spawn_hub(PATROL_SEED)
	assert_eq(_brain_seeds(a.container), _brain_seeds(b.container),
			"a fixed patrol_seed must derive identical per-drone rng seeds every run")


func test_nobody_perceives_the_player_at_frame_0() -> void:
	var built := _spawn_hub(PATROL_SEED, -1, _player_spawn)
	var found := _swarm_and_razor(built.container)
	var swarms: Array = found.swarms
	var all_drones: Array = []
	all_drones.append_array(swarms)
	if found.razor != null:
		all_drones.append(found.razor)
	assert_gt(all_drones.size(), 1, "sanity: something spawned")
	_tick_all(all_drones)
	for d: SwarmDrone in swarms:
		assert_eq((d.get_node("Brain") as SwarmDroneBrain).phase, SwarmDroneBrain.Phase.IDLE,
				"a Swarm member must not notice the player on its first tick")
	var razor: RazorDrone = found.razor
	if razor != null:
		assert_eq((razor.get_node("Brain") as RazorDroneBrain).phase,
				RazorDroneBrain.Phase.IDLE_ORBIT,
				"the Razor must not notice the player on its first tick")


## D4: `BulletPool._container = get_parent().get_parent()` — a Razor spawned as a direct child of
## `EnemyContainer` (as `_spawn_patrol()` does) must therefore land its pulse there too.
## `start_engaged = true` and a forced DASH bypass the hub idle on purpose: this case is only about
## the container wiring, not about idle-to-combat behaviour (already covered above).
func test_a_razor_pulse_bullets_parent_is_the_enemy_container() -> void:
	var built := _spawn_hub(PATROL_SEED, -1, _player_spawn)
	var razor: RazorDrone = _swarm_and_razor(built.container).razor
	assert_not_null(razor, "sanity: a Razor Drone spawned")
	if razor == null:
		return
	var brain := razor.get_node("Brain") as RazorDroneBrain
	brain.start_engaged = true
	brain.enter_phase(RazorDroneBrain.Phase.DASH)
	# Stop the instant the miss fires its pulse (OVERSHOOT's entry), rather than looking for the
	# brain to still be reading OVERSHOOT afterwards — DASH -> OVERSHOOT -> RETURN -> ORBIT can all
	# land within one _tick_phase() cascade (up to 4 transitions per tick), so a loop that waits for
	# `phase == OVERSHOOT` can step right over it.
	var guard := 0
	while brain.pulses_fired == 0 and guard < 200:
		_tick(razor)
		guard += 1
	assert_eq(brain.pulses_fired, 1, "sanity: a miss fires exactly one pulse")
	var container: Node2D = built.container
	var bullets: Array[Node] = container.get_children().filter(func(c: Node) -> bool: return c is EnemyBullet)
	assert_eq(bullets.size(), 1, "the pulse's parent is EnemyContainer (D4 grandparent rule)")
