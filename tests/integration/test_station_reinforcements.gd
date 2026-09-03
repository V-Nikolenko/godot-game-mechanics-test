## Integration test for StationReinforcements (EPIC sub-item 4b).
##
## NOT characterization: `StationReinforcements`, the `Reinforcements` node in
## `space_station.tscn` and the three `reinforcement_*` fields on `SpaceStationConfig` are all new
## code, so these assert intended behaviour. Plan and both review rounds:
## `docs/plans/station-reinforcements/`.
##
## ── Harness rules, inherited from `test_station_gunnery.gd` ──────────────────────────────────
##
## 1. **Never write to `station.config`.** `space_station.gd:36` `load()`s the `.tres` and
##    ResourceLoader caches, so every station in the process shares ONE object. Overrides go on the
##    REINFORCEMENTS NODE, which copies the config in `_ready()` and never reads it again.
## 2. **The station is parented to a container `Node2D`.** Reinforcements spawn as SIBLINGS of the
##    station into `_station.get_parent()`, which in the real level is
##    `WaveManager.enemy_container` — so the container is what a test counts.
## 3. **`LaserPhase.rotation_speed = 0`**, so nothing rotates under an absolute-position assertion.
## 4. **The reinforcement `Timer` is stopped in `before_each`**, so every squad in this file is
##    forced through `spawn_next_squad()`. Two cases (10 and 15) exercise the timer itself, and
##    case 10 has to `start()` it again first or its `is_stopped()` assertion would be vacuous.
##
## Nothing here awaits a wall clock. `reinforcement_first_delay` is 8 s in the shipped config and
## a test that waited it out would be forty times longer than anything else in the suite.
##
## ── Counting container children needs a filter ───────────────────────────────────────────────
##
## `ExplosionEffect` parents its CPUParticles2D to `actor.get_parent()`, and a reinforcement
## `interceptor` / `fighter` builds its own `BulletPool` whose bullets reparent into the same
## container (`bullet_pool.gd:47`). So `_reinforcements()` filters by type, exactly as
## `test_station_gunnery.gd:81-86` does for bullets.
extends GutTest

const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")
const STATION_CONFIG := preload("res://assault/scenes/enemies/space_station/space_station_config.tres")

## The player's primary bullet is `collision_layer = 64` (`bullet.tscn:44`). A HurtBox whose mask
## excludes that bit cannot be hit by it at all — the `ram_ship` defect review round 1 caught.
const PLAYER_BULLET_LAYER: int = 64

## Design-unit half-screen. `ArenaCamera` is 1280x720 world at WORLD_SCALE 2.0.
const DESIGN_HALF_W: float = 320.0
const DESIGN_HALF_H: float = 180.0

var _container: Node2D
var _station: SpaceStation
var _reinf: StationReinforcements


func before_each() -> void:
	_container = Node2D.new()
	add_child_autofree(_container)
	_station = STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(_station)
	_station.global_position = Vector2(640.0, 180.0)
	_reinf = _station.get_node("Reinforcements") as StationReinforcements
	(_station.get_node("LaserPhase") as StationLaserPhase).rotation_speed = 0.0
	## Stop the real cadence — every squad in this file is forced.
	_reinf._timer.stop()


## Every reinforcement is a BaseEnemy and a sibling of the station. Filtered rather than a raw
## get_children(): see the file header.
func _reinforcements() -> Array[BaseEnemy]:
	var out: Array[BaseEnemy] = []
	for child in _container.get_children():
		if child == _station:
			continue
		var e := child as BaseEnemy
		if e != null:
			out.append(e)
	return out


func _turrets() -> Array[StationTurret]:
	var out: Array[StationTurret] = []
	for child in _station.get_node("Turrets").get_children():
		var t := child as StationTurret
		if t != null:
			out.append(t)
	return out


func _kill_all_turrets() -> void:
	for t in _turrets():
		t.hurt_box.received_damage.emit(t.health.max_health)


## Every entry of every squad, flattened. The table is the thing most of these cases assert on.
func _all_entries() -> Array[SpawnEntryResource]:
	var out: Array[SpawnEntryResource] = []
	for squad: Array in _reinf.squads():
		for e: SpawnEntryResource in squad:
			out.append(e)
	return out


func _free_all_reinforcements() -> void:
	for e in _reinforcements():
		e.free()


# ── 1. Config ─────────────────────────────────────────────────────────────────

## Cannot pass vacuously: the node's own defaults are 20 / 30 / 2 against the config's 8 / 10 / 4,
## the same trick `station_gunnery.gd:64-73` uses.
func test_the_node_copies_its_three_fields_from_the_config() -> void:
	assert_almost_eq(_reinf.reinforcement_first_delay, STATION_CONFIG.reinforcement_first_delay, 0.001,
		"reinforcement_first_delay must be copied from SpaceStationConfig")
	assert_almost_eq(_reinf.reinforcement_interval, STATION_CONFIG.reinforcement_interval, 0.001,
		"reinforcement_interval must be copied from SpaceStationConfig")
	assert_eq(_reinf.reinforcement_max_alive, STATION_CONFIG.reinforcement_max_alive,
		"reinforcement_max_alive must be copied from SpaceStationConfig")


# ── 2-4. The squad geometry ───────────────────────────────────────────────────

## The backlog's done-condition: "reinforcement waves spawn from at least three screen edges".
## Four is what the table actually does.
func test_the_squads_cover_four_distinct_screen_edges() -> void:
	var left := false
	var right := false
	var below := false
	var above := false
	for e in _all_entries():
		if e.base_offset.x < -DESIGN_HALF_W:
			left = true
		if e.base_offset.x > DESIGN_HALF_W:
			right = true
		if e.base_offset.y > DESIGN_HALF_H:
			below = true
		if e.base_offset.y < -DESIGN_HALF_H:
			above = true
	assert_true(left, "a squad must enter from the left edge")
	assert_true(right, "a squad must enter from the right edge")
	assert_true(below, "a squad must enter from below")
	assert_true(above, "a squad must enter from above")


## Boundary: nothing may pop in inside the play area, on top of the player.
func test_every_entry_starts_outside_the_play_area() -> void:
	for e in _all_entries():
		var outside: bool = absf(e.base_offset.x) > DESIGN_HALF_W or absf(e.base_offset.y) > DESIGN_HALF_H
		assert_true(outside,
			"entry at %s is inside the 640x360 play area — it would pop in on screen" % e.base_offset)


## Boundary, research finding 5: the margin must exceed half the largest sprite plus the camera's
## horizontal pan. Half-extent is 37 (the interceptor's 64x74 sprite; `interceptor.tscn:58-60` has
## no scale on the Sprite2D). Horizontal budget 640 + H_LIMIT 100 + 37 = 777 world px; vertical
## 360 + 37 = 397, V_LIMIT deliberately excluded because every spawn in the game resolves against
## the camera's fixed centre. This is a live constraint on future edits: it fails at design +/-380.
func test_every_entry_clears_the_off_screen_spawn_margin() -> void:
	var h_margin: float = 640.0 + ArenaCamera.H_LIMIT + 37.0
	var v_margin: float = 360.0 + 37.0
	for e in _all_entries():
		var world: Vector2 = e.base_offset * ArenaCamera.WORLD_SCALE
		var clears: bool = absf(world.x) > h_margin or absf(world.y) > v_margin
		assert_true(clears,
			"entry at design %s = world %s clears neither the %d px horizontal nor the %d px vertical margin"
				% [e.base_offset, world, int(h_margin), int(v_margin)])


# ── 5. Deterministic cycling ──────────────────────────────────────────────────

## Fixed order, never randf() — the laser phase already established that random attack ordering
## cannot be balanced or tested. LEFT -> RIGHT -> BOTTOM -> TOP, then LEFT again.
func test_squads_cycle_left_right_bottom_top_and_then_repeat() -> void:
	var edges: Array[String] = []
	for i in 5:
		_free_all_reinforcements()
		_reinf.spawn_next_squad()
		var ships := _reinforcements()
		assert_eq(ships.size(), 2, "each squad is two ships")
		var centre: Vector2 = Vector2(640.0, 360.0)
		var mean: Vector2 = (ships[0].global_position + ships[1].global_position) * 0.5 - centre
		if mean.x < -600.0:
			edges.append("LEFT")
		elif mean.x > 600.0:
			edges.append("RIGHT")
		elif mean.y > 400.0:
			edges.append("BOTTOM")
		elif mean.y < -400.0:
			edges.append("TOP")
		else:
			edges.append("?")
	assert_eq(edges, ["LEFT", "RIGHT", "BOTTOM", "TOP", "LEFT"] as Array[String],
		"squads must cycle in a fixed order and wrap back to LEFT")


# ── 6-8. What a spawned ship looks like ───────────────────────────────────────

## The rotation trap. `station_laser_phase.gd:123` writes `_station.rotation`; anything parented
## under the station would be dragged around the arena with the hull. And `bullet_pool.gd:47`
## hardcodes `get_parent().get_parent()`, so a reinforcement's own pool depends on this too.
func test_ships_are_siblings_of_the_station_with_a_path_mover() -> void:
	_reinf.spawn_next_squad()
	var ships := _reinforcements()
	assert_eq(ships.size(), 2, "the first squad is two ships")
	for ship in ships:
		assert_eq(ship.get_parent(), _container,
			"a reinforcement must be a SIBLING of the station, not a child of it")
		var mover: EnemyPathMover = null
		for child in ship.get_children():
			if child is EnemyPathMover:
				mover = child as EnemyPathMover
		assert_not_null(mover, "every reinforcement needs an EnemyPathMover or it sits still")


## A sign flip in the 0-is-down angle convention is the exact bug class that shipped once already
## in the turret barrels. Every entry's movement must carry it toward the screen centre.
func test_every_entry_moves_into_the_screen() -> void:
	for squad: Array in _reinf.squads():
		for e: SpawnEntryResource in squad:
			assert_not_null(e.movement, "every entry needs a movement or the ship sits still")
			var toward_centre: Vector2 = -e.base_offset
			var step: Vector2 = e.movement.sample(1.0)
			assert_gt(step.dot(toward_centre), 0.0,
				"entry at %s moves away from the screen centre (step %s)" % [e.base_offset, step])


## The hard guarantee that no reinforcement can strand `ENEMIES_CLEARED`, which polls the
## container's child count (`level_director.gd:116`). FREE_ON_SCREEN_EXIT would not do: it only
## culls a ship that has been on screen at least once.
func test_every_spawned_mover_frees_on_a_fixed_duration() -> void:
	_reinf.spawn_next_squad()
	for ship in _reinforcements():
		for child in ship.get_children():
			var mover := child as EnemyPathMover
			if mover == null:
				continue
			assert_eq(mover.exit_mode, EnemyPathMover.ExitMode.FREE_ON_DURATION,
				"a reinforcement must have a hard lifetime, not a screen-exit cull")
			assert_gt(mover.exit_time, 0.0, "FREE_ON_DURATION with exit_time 0 falls back to the movement duration")


# ── 9. Score registration ─────────────────────────────────────────────────────

## Without this, killing a reinforcement awards nothing: ScoreTracker is the only thing that pays
## out `BaseEnemy.died`, and it only connects enemies it has been told about.
func test_each_spawned_ship_is_announced_as_an_orphan_spawn() -> void:
	var seen: Array[Node] = []
	var handler := func(enemy: Node) -> void: seen.append(enemy)
	EventBus.enemy_spawned_orphan.connect(handler)
	_reinf.spawn_next_squad()
	EventBus.enemy_spawned_orphan.disconnect(handler)

	var ships := _reinforcements()
	assert_eq(seen.size(), ships.size(), "every reinforcement must be announced exactly once")
	for ship in ships:
		assert_true(seen.has(ship), "%s was spawned but never announced" % ship.name)


# ── 10-11. The phase gate ─────────────────────────────────────────────────────

## Research finding 1: constant adds are how a boss gets overshadowed by its own minions. Phase 2
## is already beams every 6.5 s over rings every 2.0 s.
##
## The timer is restarted first on purpose. `before_each` already stopped it, so asserting
## `is_stopped()` without this would be vacuous — review round 2, finding N2.
func test_breaking_the_armour_stops_reinforcements() -> void:
	_reinf._timer.start(5.0)
	assert_false(_reinf._timer.is_stopped(), "precondition: the timer is running before armor_broken")

	_kill_all_turrets()
	assert_true(_reinf._timer.is_stopped(), "armor_broken must stop the reinforcement timer")

	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 0, "no squad may spawn once the armour is broken")


## Nothing this node drives may outlive the station — a live reinforcement holds
## `LevelSection.ENEMIES_CLEARED` open, and that section's timeout is 180 s.
##
## `died` is the BACKSTOP, and isolating it takes a disconnect. The station refuses all core damage
## while a turret lives (`space_station.gd:124-130`), so the only route to `died` runs through
## `armor_broken` — which already stops this node. Unhooking `armor_broken` first is what makes the
## case discriminate: without the `died` connection nothing would stop the spawner at all.
func test_the_stations_death_stops_reinforcements() -> void:
	_station.armor_broken.disconnect(_reinf._stop)

	_kill_all_turrets()
	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 2,
		"precondition: with armor_broken unhooked, the spawner is still running")
	_free_all_reinforcements()

	## The armour is gone, so the core now takes damage.
	_station.hurt_box.received_damage.emit(_station.health.max_health)
	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 0, "no squad may spawn once the station is dead")
	assert_true(_reinf._timer.is_stopped(), "the station's death must stop the reinforcement timer")


# ── 12. The population cap ────────────────────────────────────────────────────

## Boundary, at the SHIPPED value of 4. Squads are 2 ships, so an "already at the cap?" check
## would let the third squad through at 4 alive and peak at 6 — review round 1, finding S1.
## Squads are never half-spawned: half a squad reads as a bug, not as a cap.
func test_the_cap_skips_a_whole_squad_and_recovers_when_ships_are_freed() -> void:
	assert_eq(_reinf.reinforcement_max_alive, 4, "this case is written against the shipped cap")

	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 2, "first squad")
	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 4, "second squad reaches the cap exactly")
	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 4,
		"the third squad must be skipped WHOLE — 4 + 2 > 4, and half a squad is not a cap")

	_free_all_reinforcements()
	_reinf.spawn_next_squad()
	assert_eq(_reinforcements().size(), 2,
		"freed ships must be pruned from the live list, or the spawner jams permanently")


# ── 13-14. Wiring and roster rules ────────────────────────────────────────────

## `docs/enemy-roster.md:260,294` mark both as self-managed AI that must never get a mover —
## and `EnemyPathMover._ready()` silently disables the AI it depends on.
func test_no_squad_uses_a_self_managed_ai_enemy() -> void:
	for e in _all_entries():
		var path: String = e.ship_scene.resource_path
		assert_ne(path, WaveBuilder.GUNSHIP, "gunship is self-managed AI and must never get a mover")
		assert_ne(path, WaveBuilder.DRONE_INTERCEPTOR,
			"drone_interceptor is self-managed AI and must never get a mover")


## 4a lost time to an unwired export that left the gate green. The node has to be in the scene.
func test_the_scene_carries_a_reinforcements_node() -> void:
	var found: StationReinforcements = null
	for child in _station.get_children():
		if child is StationReinforcements:
			found = child as StationReinforcements
	assert_not_null(found, "space_station.tscn must carry a Reinforcements child")
	assert_eq(found.name, &"Reinforcements", "the node is named Reinforcements")


# ── 15. The cadence ───────────────────────────────────────────────────────────

## Read off the Timer, never awaited: the shipped first delay is 8 s. The one_shot + restart-only-
## in-_on_timer_timeout split is what lets cases 10-12 force squads without re-arming the timer.
func test_the_first_delay_and_then_the_repeat_interval() -> void:
	## before_each stopped it; re-instantiate to observe what _ready() actually left behind.
	var station := STATION_SCENE.instantiate() as SpaceStation
	_container.add_child(station)
	var reinf := station.get_node("Reinforcements") as StationReinforcements

	assert_true(reinf._timer.one_shot, "the timer must be one_shot and restarted explicitly")
	assert_almost_eq(reinf._timer.wait_time, reinf.reinforcement_first_delay, 0.001,
		"the first squad lands after reinforcement_first_delay, not on the boss's first frame")
	assert_false(reinf._timer.is_stopped(), "_ready() must arm the timer")

	reinf._on_timer_timeout()
	assert_almost_eq(reinf._timer.wait_time, reinf.reinforcement_interval, 0.001,
		"subsequent squads land on reinforcement_interval, not on the first delay forever")
	assert_false(reinf._timer.is_stopped(), "the cadence must keep going after the first squad")

	station.free()


## And the split itself: spawn_next_squad() must not touch the timer.
func test_spawning_a_squad_does_not_touch_the_timer() -> void:
	_reinf._timer.stop()
	_reinf.spawn_next_squad()
	assert_true(_reinf._timer.is_stopped(),
		"spawn_next_squad() must not re-arm the timer — cases 10-12 depend on that split")


# ── 16. Every squad ship is killable by the primary weapon ────────────────────

## The `ram_ship` class of defect, caught automatically the next time someone swaps a squad ship.
## The mask must be read IN THE TREE: `hurt_box` is `@onready` (`base_enemy.gd:7`) and the
## governing value is written in `_ready()` (`base_enemy.gd:25` sets 97|1024 = 1121; `ram_ship.gd:19`
## is the one subclass that narrows it to 33 afterwards).
##
## This iterates the squad table, so the ram case is discriminating but counterfactual today:
## 1121 & 64 == 64 passes for all three chosen ships, 33 & 64 == 0 would fail.
func test_every_squad_ship_can_be_hit_by_the_players_primary_weapon() -> void:
	var checked: Dictionary = {}
	for e in _all_entries():
		var path: String = e.ship_scene.resource_path
		if checked.has(path):
			continue
		checked[path] = true
		var ship := e.ship_scene.instantiate() as BaseEnemy
		assert_not_null(ship, "%s is not a BaseEnemy" % path)
		_container.add_child(ship)
		assert_ne(ship.hurt_box.collision_mask & PLAYER_BULLET_LAYER, 0,
			"%s ignores the player's bullet layer (64) — it cannot be shot down" % path.get_file())
		ship.free()
	assert_gt(checked.size(), 0, "the squad table must reference at least one ship scene")


# ── 17. The combo cost of an ignored squad ────────────────────────────────────

## The deliberate balance decision, pinned with a number rather than left as a comment.
##
## Registering reinforcements with ScoreTracker buys kill score AND inherits the game's universal
## escape penalty: `score_tracker.gd:211` multiplies the combo by `escape_combo_multiplier` (0.75)
## OUTSIDE the `if counts_in_wave:` block, so `wave_index == -1` does not exempt it. Two ships
## flying through therefore cost 0.75 twice. 4.0 -> 2.25, comfortably above the 1.0 floor at
## `score_tracker.gd:212-213`, so the assertion is exact.
##
## set_process(false) is mandatory: `score_tracker.gd:112-124` decays any combo above 1.0 straight
## back to 1.0 on the first processed frame when `_combo_decay_remaining` is 0, and
## `start_tracking()` turns `_process` on. Same remedy as
## `test_station_assault_section.gd:142-147`.
func test_a_squad_that_flies_through_costs_two_escape_combo_penalties() -> void:
	var tracker := ScoreTracker.new()
	add_child_autofree(tracker)
	tracker.start_tracking()
	tracker.set_process(false)
	tracker.set("_combo", 4.0)

	_reinf.spawn_next_squad()
	var ships := _reinforcements()
	assert_eq(ships.size(), 2, "precondition: the squad is two ships")
	for ship in ships:
		ship.queue_free()
	await wait_physics_frames(2)

	assert_almost_eq(float(tracker.get("_combo")), 2.25, 0.001,
		"two reinforcements flying through must cost 4.0 * 0.75 * 0.75 — the accepted balance cost")
