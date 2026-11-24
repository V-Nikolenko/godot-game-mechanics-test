## The Space Fortress's reinforcements (plan §2.8; Phase 11 t8): the hangar's drones, the sector defenders a lost battery calls from its generator, the
## `critical` surge and the scuttle on death, all through `BossReinforcements` (§2.2) and the three scene-authored bays. Intent tests, every row in both
## harnesses (IDEAS §40). Hand-driven: the fortress's own physics is off and the test ticks `reinforcements()` itself (`active` true, the brain's
## `is_engaged()` answer); only rows 5 and 6 let the escorts' own AI run, on real physics at the 8x clock (tests/README.md -> Gate time rule 1).
##
## Row 7 (the §25 `reinforcements` key, on its pinned path and with the hangar dead) lives in `test_space_fortress.gd`, beside the other five keys.
extends GutTest

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const SCENE: PackedScene = preload("res://assault/scenes/enemies/space_fortress/space_fortress.tscn")
const SHIPPED: SpaceFortressConfig = preload("res://assault/scenes/enemies/space_fortress/space_fortress_config.tres")  # read only
const DEFAULT_GUN: WeaponModeResource = preload("res://assault/scenes/player/weapons/modes/default.tres")
const SWARM_PATH := "res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn"
const FIGHTER_PATH := "res://assault/scenes/enemies/fighter/fighter.tscn"
const GATLING_PATH := "res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor.tscn"

const MODES := ["open_space", "assault"]
const DT := 1.0 / 60.0
const SPAWN := Vector2(640.0, 360.0)
const HANGAR := &"hangar"
const NORTH_BAY := &"north_defenders"
const SOUTH_BAY := &"south_defenders"
const NORTH_LOSSES := [&"battery_artillery", &"battery_missiles", &"hangar"]
const SOUTH_LOSSES := [&"battery_spread", &"battery_pulse", &"battery_sweep"]
## A cap nothing reaches, for the rows that are not about the cap.
const BIG_CAP := {"escort_cap_open_space": 40, "escort_cap_assault": 40}
## Seconds from launch to the first round in the escort container (Assault). The gatling pair fires inside the plan's 3 s (measured 2.85 s); a fighter pair
## flies its own lead-in and waits for its attack slot before the first burst (measured 3.9-4.5 s from every launch geometry tried), so its bound is 5 s.
const GATLING_FIRST_FIRE := 3.0
const FIGHTER_FIRST_FIRE := 5.0
const _SPEEDUP := 8

var _roots: Array[Node] = []
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func after_each() -> void:
	_restore_clock()
	_roots.clear()


func _scale_clock() -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ── Helpers ──────────────────────────────────────────────────────────────────────────────────────

func _world(mode: String):
	for old in _roots:
		if is_instance_valid(old) and old.is_inside_tree():
			old.get_parent().remove_child(old)
	var h = HARNESS.open_space() if mode == "open_space" else HARNESS.assault()
	add_child_autofree(h.root)
	_roots.append(h.root)
	h.player.global_position = Vector2(640.0, 560.0) if mode == "assault" else Vector2(640.0, 1000.0)
	return h


## A fortress with its physics off. [param props] are written on its private config copy before it enters the tree.
func _spawn(h, props: Dictionary = {}, parent: Node = null) -> SpaceFortress:
	var f := SCENE.instantiate() as SpaceFortress
	for key in props:
		f.config.set(key, props[key])
	f.global_position = SPAWN
	(parent if parent != null else h.root).add_child(f)
	f.set_physics_process(false)
	return f


func _bays(f: SpaceFortress) -> BossReinforcements:
	return f.reinforcements()


## Hand-ticks the bays [param seconds] with `active` true.
func _run(f: SpaceFortress, seconds: float) -> void:
	for i in roundi(seconds / DT):
		_bays(f).tick(DT, true)


func _settle() -> void:
	await get_tree().physics_frame
	await get_tree().process_frame


func _lose(f: SpaceFortress, ids: Array) -> void:
	for id in ids:
		f.part(id).destroy()
	await _settle()


## Enters `shields_exposed` by two batteries of one side ([param ids]); returns once the deferred unlocks ran.
func _to_shields_exposed(f: SpaceFortress) -> void:
	await _lose(f, [&"battery_spread", &"battery_pulse"])
	assert_eq(f.phase_driver().current_id(), &"shields_exposed", "sanity: two batteries lost")


func _scene_paths(escorts: Array) -> Array:
	return escorts.map(func(e: Node) -> String: return e.scene_file_path)


func _bay_node(f: SpaceFortress, part_name: String) -> ReinforcementBay:
	return f.get_node("Modules/%s/Bay" % part_name) as ReinforcementBay


## A hit through the hurtbox's real entry (`area_entered`): the sector bubble is asked first, exactly as for a bullet.
func _hit(f: SpaceFortress, id: StringName, damage: int) -> void:
	var hb := HitBox.new()
	hb.damage = damage
	f.add_child(hb)
	hb.global_position = f.part(id).global_position
	f.part(id).hurt_box._on_area_entered(hb)
	hb.free()


# ══ 1. Nothing launches without a loss; the first loss calls its sector ═════════════════════════

func test_nothing_launches_in_batteries_until_a_battery_dies(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	_run(f, 20.0)
	assert_eq(_bays(f).live_count(), 0, "%s: a quiet fortress launches nothing in 20 s" % mode)
	assert_eq([_bays(f).launches(HANGAR), _bays(f).launches(NORTH_BAY), _bays(f).launches(SOUTH_BAY)], [0, 0, 0], "%s: no bay launched" % mode)

	await _lose(f, [&"battery_artillery"])
	_run(f, 0.9)
	assert_eq(_bays(f).launches(NORTH_BAY), 0, "%s: the doors take door_seconds (1.0): nothing at 0.9 s" % mode)
	assert_true(_bays(f).door_open(NORTH_BAY), "%s: the north doors are opening" % mode)
	_run(f, 0.2)
	assert_eq(_bays(f).launches(NORTH_BAY), 1, "%s: the first loss launches its sector's pair" % mode)
	assert_eq(_scene_paths(_bays(f).escorts()), [FIGHTER_PATH, FIGHTER_PATH], "%s: fighters from the north" % mode)

	await _lose(f, [&"battery_spread"])
	_run(f, 1.1)
	assert_eq(_bays(f).launches(SOUTH_BAY), 1, "%s: a south loss launches the south pair" % mode)
	var paths := _scene_paths(_bays(f).escorts())
	paths.sort()
	assert_eq(paths, [FIGHTER_PATH, FIGHTER_PATH, GATLING_PATH, GATLING_PATH], "%s: gatlings from the south" % mode)
	assert_eq(_bays(f).launches(HANGAR), 0, "%s: the hangar bay waits for its own phase (it activates, it does not launch, on entering it)" % mode)
	# The hangar is watched by the north bay (its loss calls the north defenders), not the south one.
	await _lose(f, [HANGAR])
	assert_eq([_bays(f).pending(NORTH_BAY), _bays(f).pending(SOUTH_BAY)], [1, 0], "%s: the hangar's loss queues one north launch" % mode)


# ══ 2. The hangar ═══════════════════════════════════════════════════════════════════════════════

func test_the_hangar_launches_after_shields_exposed_then_every_period(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, BIG_CAP)
	var assault: bool = h.is_assault
	var count := 2 if assault else 3
	var period := 14.0 if assault else 12.0
	var bay := _bay_node(f, "Hangar")
	assert_eq([bay.count_for(assault), bay.period_for(assault)], [count, period], "%s: the scene's count and period for this mode" % mode)
	assert_eq([bay.first_delay, bay.door_seconds, bay.open_hold_seconds, bay.opens_part], [2.0, 0.8, 2.0, true], "%s: the authored door cycle" % mode)

	_run(f, 30.0)
	assert_eq(_bays(f).launches(HANGAR), 0, "%s: the hangar bay is idle through `batteries`" % mode)
	await _to_shields_exposed(f)
	var hangar := f.part(HANGAR)
	var vulnerable_ticks := 0
	var light := hangar.get_node("Light") as StateLight
	var light_before := light.get_state()
	var first_close := -1.0
	var charging_when_opened := false
	var light_when_closed := -1
	var t := 0.0
	var first_open := -1.0
	var launches_seen: Array[float] = []
	while t < 2.0 * period + 5.0:
		var before := _bays(f).launches(HANGAR)
		_bays(f).tick(DT, true)
		t += DT
		if _bays(f).launches(HANGAR) > before:
			launches_seen.append(t)
		if hangar.is_vulnerable():
			vulnerable_ticks += 1
			if first_open < 0.0:
				charging_when_opened = light.get_state() == StateLight.State.CHARGING
				first_open = t
		elif first_open >= 0.0 and first_close < 0.0:
			first_close = t
			light_when_closed = light.get_state()
	assert_almost_eq(launches_seen[0], 2.0 + 0.8, 0.05, "%s: the first launch at first_delay + door_seconds after the phase" % mode)
	assert_almost_eq(launches_seen[1] - launches_seen[0], period, 0.05, "%s: then every period" % mode)
	assert_almost_eq(first_open, 2.0, 0.05, "%s: the doors began opening at first_delay" % mode)
	assert_eq(_bays(f).launches(HANGAR), 3, "%s: three launches in 2 periods + 5 s" % mode)
	var swarms := _bays(f).escorts().filter(func(e: Node) -> bool: return e.scene_file_path == SWARM_PATH)
	assert_eq(swarms.size(), 3 * count, "%s: %d drones per launch" % [mode, count])
	assert_almost_eq(float(vulnerable_ticks) * DT, 3.0 * 2.8, 0.15, "%s: hittable exactly 2.8 s per launch" % mode)
	assert_false(hangar.is_vulnerable(), "%s: locked again after the doors closed" % mode)
	assert_true(charging_when_opened, "%s: the telegraph light shows while the doors open" % mode)
	assert_almost_eq(first_close - first_open, 2.8, 0.05, "%s: hittable for door_seconds + open_hold_seconds, then locked" % mode)
	assert_eq(light_when_closed, light_before, "%s: the light is back to what it showed" % mode)


## One open window of focused default fire kills the hangar through the sector bubble with its generator alive (§26 needs it reachable).
func test_one_open_window_of_default_fire_kills_the_hangar_behind_its_bubble(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, BIG_CAP)
	await _to_shields_exposed(f)
	var hangar := f.part(HANGAR)
	assert_false(f.part(&"shield_north").is_destroyed(), "%s: the generator is alive" % mode)
	var shield := f.north_sector().shield_of(HANGAR)
	assert_not_null(shield, "%s: the hangar sits behind the north bubble" % mode)
	# A locked hangar takes no hit through the bubble either (the bubble never absorbs for an armoured host).
	_hit(f, HANGAR, DEFAULT_GUN.damage)
	assert_eq(hangar.health.current_health, SHIPPED.hangar_health, "%s: a locked hangar takes nothing" % mode)
	assert_eq(shield.points(), SHIPPED.sector_shield_capacity, "%s: and the bubble absorbs nothing for it" % mode)

	var interval := DEFAULT_GUN.fire_interval
	var hits := 0
	var next_hit := 0.0
	var t := 0.0
	var killed_at := -1.0
	var opened_at := -1.0
	while t < 5.0 and killed_at < 0.0:
		_bays(f).tick(DT, true)
		t += DT
		if hangar.is_vulnerable():
			if opened_at < 0.0:
				opened_at = t
				next_hit = t
			if t >= next_hit:
				_hit(f, HANGAR, DEFAULT_GUN.damage)
				hits += 1
				next_hit += interval
		if hangar.is_destroyed():
			killed_at = t
	assert_gt(killed_at, 0.0, "%s: the hangar died" % mode)
	assert_lte(killed_at - opened_at, 2.8, "%s: inside one open window (opened %.2f, killed %.2f, %d hits)" % [mode, opened_at, killed_at, hits])
	assert_gte(hits * DEFAULT_GUN.damage, SHIPPED.sector_shield_capacity + SHIPPED.hangar_health, "%s: the bubble then the hull took the damage" % mode)
	assert_true(_bays(f).is_dead(HANGAR), "%s: its bay is dead" % mode)
	_run(f, 30.0)
	assert_eq(_bays(f).launches(HANGAR), 1 if opened_at + 0.8 <= killed_at else 0, "%s: no launch after the hangar died" % mode)


## The feasibility inequality (config, scene and player-scene numbers): one open window outguns the bubble and the hull; with `open_hold_seconds` 0 it
## does not, which is the trap the held-open window exists to avoid.
func test_the_hangar_window_outguns_bubble_plus_hull_and_a_zero_hold_would_not() -> void:
	var f := SCENE.instantiate() as SpaceFortress
	autofree(f)
	var bay := f.get_node("Modules/Hangar/Bay") as ReinforcementBay
	var dps := float(DEFAULT_GUN.damage) / DEFAULT_GUN.fire_interval
	var needed := float(SHIPPED.sector_shield_capacity + SHIPPED.hangar_health)
	assert_gte((bay.door_seconds + bay.open_hold_seconds) * dps, needed, "2.8 s x %.0f/s >= %.0f" % [dps, needed])
	assert_lt(bay.door_seconds * dps, needed, "boundary: with open_hold_seconds 0 the window (door_seconds only) fails the same inequality")
	assert_eq(bay.open_hold_seconds, 2.0)
	assert_eq(f.get_node("Modules/ShieldNorth/Bay").watch_ids, NORTH_LOSSES as Array[StringName], "north watch list")
	assert_eq(f.get_node("Modules/ShieldSouth/Bay").watch_ids, SOUTH_LOSSES as Array[StringName], "south watch list")


func test_a_destroyed_hangar_never_launches_again_and_a_live_one_surges(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, BIG_CAP)
	await _to_shields_exposed(f)
	_run(f, 3.0)
	assert_eq(_bays(f).launches(HANGAR), 1, "%s: precondition: one launch" % mode)
	f.part(HANGAR).destroy()
	assert_true(_bays(f).is_dead(HANGAR), "%s: dead" % mode)
	_run(f, 40.0)
	assert_eq(_bays(f).launches(HANGAR), 1, "%s: destroyed -> no further launch" % mode)

	# The surge, with a live hangar (a second world) and without.
	var live := _spawn(h, BIG_CAP)
	live.name = "LiveFortress"
	live.global_position = SPAWN + Vector2(0.0, 900.0)
	await _lose(live, [&"battery_spread", &"battery_pulse"])
	await _lose(live, [&"shield_north", &"shield_south"])
	live.part(&"core").set_vulnerable(true)
	live.part(&"core").hurt_box.received_damage.emit(SHIPPED.core_health - roundi(SHIPPED.critical_core_ratio * SHIPPED.core_health))
	await _settle()
	assert_eq(live.phase_driver().current_id(), &"critical")
	var swarm_before := _bays(live).escorts().filter(func(e: Node) -> bool: return e.scene_file_path == SWARM_PATH).size()
	assert_eq(_bays(live).pending(HANGAR), 1, "%s: the surge is queued (the doors then take their cycle)" % mode)
	_run(live, 1.0)
	var swarm_after := _bays(live).escorts().filter(func(e: Node) -> bool: return e.scene_file_path == SWARM_PATH).size()
	assert_eq(swarm_after - swarm_before, SHIPPED.hangar_surge_count, "%s: the surge puts out %d drones" % [mode, SHIPPED.hangar_surge_count])
	assert_eq(SHIPPED.hangar_surge_count, 4, "the plan's number")


# ══ 3. A destroyed generator ends its bay ═══════════════════════════════════════════════════════

func test_a_destroyed_generator_stops_its_half_calling_defenders(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, BIG_CAP)
	await _lose(f, [&"shield_south"])
	assert_true(_bays(f).is_dead(SOUTH_BAY), "%s: the south bay died with its generator" % mode)
	await _lose(f, [&"battery_spread"])
	_run(f, 5.0)
	assert_eq(_bays(f).launches(SOUTH_BAY), 0, "%s: a later south battery loss launches nothing" % mode)
	assert_eq(_scene_paths(_bays(f).escorts()), [], "%s: and nothing else is out" % mode)
	# Control: the north bay still answers its own half.
	await _lose(f, [&"battery_missiles"])
	_run(f, 1.2)
	assert_eq(_bays(f).launches(NORTH_BAY), 1, "%s: the north half still calls its pair" % mode)

	# A launch whose doors are opening when the generator dies never comes out.
	await _lose(f, [&"battery_artillery"])
	_run(f, 0.5)
	assert_true(_bays(f).door_open(NORTH_BAY), "%s: precondition: the north doors are opening" % mode)
	await _lose(f, [&"shield_north"])
	_run(f, 3.0)
	assert_eq(_bays(f).launches(NORTH_BAY), 1, "%s: the opening launch was cancelled by the generator's death" % mode)


# ══ 4. Caps ═════════════════════════════════════════════════════════════════════════════════════

func test_the_escort_caps_and_skipped_launches(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h)
	var cap := SHIPPED.escort_cap_assault if h.is_assault else SHIPPED.escort_cap_open_space
	assert_eq(cap, 4 if h.is_assault else 6, "%s: the plan's caps" % mode)
	await _lose(f, NORTH_LOSSES)
	await _lose(f, SOUTH_LOSSES)
	var peak := 0
	for i in roundi(15.0 / DT):
		_bays(f).tick(DT, true)
		peak = maxi(peak, _bays(f).live_count())
	assert_eq(peak, cap, "%s: never more than %d alive, and the cap is reached" % [mode, cap])
	var launched := _bays(f).launches(NORTH_BAY) + _bays(f).launches(SOUTH_BAY)
	var skipped := _bays(f).skipped(NORTH_BAY) + _bays(f).skipped(SOUTH_BAY)
	assert_eq(launched * 2, cap, "%s: the pairs that fit" % mode)
	assert_eq(launched + skipped, 6, "%s: six launches were called; those without room are counted, not lost silently" % mode)
	assert_gt(skipped, 0, "%s: some were skipped" % mode)


# ══ 5. Where escorts live, the section, death and fire ══════════════════════════════════════════

func test_escorts_land_in_the_fortress_escort_container(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var enemy_container := Node2D.new()
	enemy_container.name = "EnemyContainer"
	h.root.add_child(enemy_container)
	var f := _spawn(h, {}, enemy_container)
	assert_null(EscortContainer.of(f), "%s: no container before the first launch" % mode)
	await _lose(f, [&"battery_artillery"])
	_run(f, 1.2)
	var box := EscortContainer.of(f)
	assert_not_null(box, "%s: created at the first launch" % mode)
	assert_eq(String(box.name), "SpaceFortressEscorts", "%s: named after the node" % mode)
	assert_eq(box.get_parent(), enemy_container, "%s: a sibling of the fortress" % mode)
	assert_eq(_bays(f).live_count(), 2)
	for escort in _bays(f).escorts():
		assert_eq(escort.get_parent(), box, "%s: an escort lives in the escort container" % mode)
		assert_true(escort.is_in_group(f.owner_group()), "%s: in the fortress's owner group" % mode)
	for child in enemy_container.get_children():
		assert_false(child is BaseEnemy and child != f, "%s: no escort is a direct child of the enemy container" % mode)


func test_enemies_cleared_waits_only_for_the_fortress() -> void:
	var mode := "assault"  # ENEMIES_CLEARED is the Assault director's end condition; the Open Space hub has no section to wait on
	_scale_clock()
	var h = _world(mode)
	var container := Node2D.new()
	h.root.add_child(container)
	var wave_manager := WaveManager.new()
	wave_manager.enemy_container = container
	add_child_autofree(wave_manager)
	var director := LevelDirector.new()
	director.wave_manager = wave_manager
	add_child_autofree(director)
	var started: Array = []
	director.section_started.connect(func(index: int, _n: StringName) -> void: started.append(index))
	var gated := LevelSection.new()
	gated.section_name = &"gated"
	gated.end_condition = LevelSection.EndCondition.ENEMIES_CLEARED
	gated.enemies_cleared_timeout = 60.0
	director.add_section(gated)
	var after := LevelSection.new()
	after.section_name = &"after"
	after.end_condition = LevelSection.EndCondition.DURATION
	after.duration = 999.0
	director.add_section(after)

	var f := _spawn(h, BIG_CAP, container)
	await _lose(f, [&"battery_artillery", &"battery_spread"])
	_run(f, 1.2)
	var box := EscortContainer.of(f)
	assert_eq(_bays(f).live_count(), 4, "%s: precondition: the fortress and four escorts" % mode)
	for child in container.get_children():
		if child is BaseEnemy:
			assert_eq(child, f, "%s: the only enemy the section counts is the fortress" % mode)
	# Park the escorts: this row is about the section's count, not their AI.
	for escort in _bays(f).escorts():
		escort.set_physics_process(false)
	director.start()
	wave_manager.waves_complete.emit()
	await wait_physics_frames(4)
	assert_eq(started.size(), 1, "%s: the section waits while the fortress lives" % mode)

	f.queue_free()
	await wait_until(func() -> bool: return started.size() == 2, 3.0)
	assert_eq(started.size(), 2, "%s: the fortress's end ends the wait" % mode)
	assert_false(is_instance_valid(box), "%s: the escort container went with it" % mode)


func test_the_fortress_scuttles_its_escorts_when_its_death_starts(mode: String = use_parameters(MODES)) -> void:
	var h = _world(mode)
	var f := _spawn(h, BIG_CAP)
	f.death_duration = 0.05
	await _lose(f, [&"battery_artillery", &"battery_spread"])
	_run(f, 1.2)
	var escorts := _bays(f).escorts()
	assert_eq(escorts.size(), 4, "%s: precondition" % mode)
	for escort in escorts:
		escort.set_physics_process(false)
	var box := EscortContainer.of(f)
	var died: Array[int] = [0]
	for escort in escorts:
		(escort as BaseEnemy).died.connect(func() -> void: died[0] += 1)
	var started: Array[int] = [0]
	f.death_started.connect(func() -> void: started[0] += 1)
	var tracker := ScoreTracker.new()
	add_child_autofree(tracker)
	tracker.start_tracking()
	tracker.set_process(false)

	f.part(&"core").destroy()
	assert_eq(started[0], 1, "%s: the death started" % mode)
	assert_eq(died[0], 4, "%s: every escort's `died` fired in that call (scuttled)" % mode)
	assert_eq(tracker.get_total_score(), 0, "%s: a scuttled escort pays nothing" % mode)
	assert_true(is_instance_valid(box), "%s: the container lives through the death sequence" % mode)
	var fortress_ref: WeakRef = weakref(f)
	await wait_until(func() -> bool: return fortress_ref.get_ref() == null, 3.0)
	await _settle()
	assert_false(is_instance_valid(f), "%s: the fortress is gone" % mode)
	assert_false(is_instance_valid(box), "%s: and the escort container with it" % mode)


## The station's rail-fire gate, re-expressed for AI escorts: a fighter pair and a gatling pair launched in Assault each put a round into the escort
## container soon after launch (the bounds above). Two fortresses share one world, each where it holds (y 180) presenting the lost battery's side to the
## player, as the facing rule would; their own AI stays off and the escorts run on real physics at 8x.
func test_assault_escorts_fire_soon_after_launch() -> void:
	_scale_clock()
	var h = _world("assault")
	var rows := [
		["FighterFortress", 400.0, PI, &"battery_artillery", FIGHTER_PATH, FIGHTER_FIRST_FIRE],
		["GatlingFortress", 880.0, 0.0, &"battery_spread", GATLING_PATH, GATLING_FIRST_FIRE],
	]
	var fortresses: Array[SpaceFortress] = []
	for row in rows:
		var f := _spawn(h, BIG_CAP)
		f.name = row[0]
		f.global_position = Vector2(row[1], SHIPPED.assault_hold_y)
		f.rotation = row[2]
		await _lose(f, [row[3]])
		var waited := 0.0
		while _bays(f).live_count() == 0 and waited < 3.0:
			_bays(f).tick(DT, true)
			waited += DT
		assert_eq(_scene_paths(_bays(f).escorts()), [row[4], row[4]], "precondition: %s's pair is out" % row[0])
		fortresses.append(f)
	var first := [-1.0, -1.0]
	var elapsed := 0.0
	while elapsed < 8.0 and (first[0] < 0.0 or first[1] < 0.0):
		await get_tree().physics_frame
		elapsed += 1.0 / Engine.physics_ticks_per_second * Engine.time_scale
		for i in 2:
			if first[i] >= 0.0:
				continue
			# A round in flight is reparented from its pool to the escort container; the shooter is the pool's owner.
			for child in EscortContainer.of(fortresses[i]).get_children():
				if child is EnemyBullet:
					for escort in _bays(fortresses[i]).escorts():
						if _owned_by(child, escort):
							first[i] = elapsed
	for i in 2:
		assert_between(first[i], 0.0, rows[i][5], "the %s pair put a round in the escort container within %.1f s of launch" % [String(rows[i][4]).get_file(), rows[i][5]])


## True when [param bullet] came out of one of [param escort]'s own pools (its recycle callable is connected from that pool).
func _owned_by(bullet: Node, escort: Node) -> bool:
	for pool in escort.find_children("*", "BulletPool", true, false):
		if (pool as BulletPool)._active.has(bullet):
			return true
	return false


# ══ 6. Launches ignore the camera pan ═══════════════════════════════════════════════════════════

func test_bay_launches_ignore_the_camera_pan() -> void:
	var h = _world("assault")
	var cam := h.root.get_node("ArenaCamera") as Camera2D
	var f := _spawn(h, BIG_CAP)
	await _lose(f, [&"battery_artillery"])
	cam.offset = Vector2(0.0, 380.0)
	_run(f, 1.2)
	var mouth: Vector2 = _bay_node(f, "ShieldNorth").mouth_position()
	assert_eq(_bays(f).live_count(), 2, "precondition: a pair is out")
	var centre := Vector2.ZERO
	for escort in _bays(f).escorts():
		centre += (escort as Node2D).global_position
		assert_lt((escort as Node2D).global_position.distance_to(mouth), 40.0, "an escort is born at the world-space mouth, panned camera or not")
	centre /= 2.0
	assert_almost_eq(centre.x, mouth.x, 0.01, "the pair is centred on the mouth")
	assert_almost_eq(centre.y, mouth.y, 0.01)
	assert_almost_eq(mouth.y, SPAWN.y - 190.0, 0.01, "the mouth lies just outside the hull on the north side")
