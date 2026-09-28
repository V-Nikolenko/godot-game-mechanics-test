## The §2.6 deadline: an AI drone's Assault exit must clear the level before the section's own
## ENEMIES_CLEARED safety net gives up (docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6).
##
## For every drone/razor spawn in every ENEMIES_CLEARED section of level 1:
##
##   last_wave_max_delay + engage_seconds + exit_distance / exit_speed
##       + exit_speed / (2 * acceleration) + margin  <  enemies_cleared_timeout
##
## `last_wave_max_delay` is the largest `spawn_delay + slot.delay` in the SECTION'S LAST WAVE
## (`waves_complete` fires when that wave TRIGGERS, not when its spawns land — level_director.gd),
## so a drone/razor anywhere in an earlier wave is already less time-pressured than one spawned
## last. `exit_distance` is half the shorter side of the LIVE `projectile_world_rect()` — the
## worst-case straight-line distance from any point inside it to the nearest edge.
##
## The Swarm formula reads `swarm_drone_config.tres` (t8b); a section with a Razor Drone is also judged by
## the Razor formula, from `razor_drone_config.tres` (t10), which adds its dash deferral.
## The Swarm Drone never starts an attack its budget cannot finish (`SwarmDroneBrain.can_start_attack`),
## so the budget always expires outside a burst, at <= max_speed, and DISENGAGE begins exactly at
## `engage_seconds`: the formula below needs no burst term.
extends GutTest

const DIRECTOR_SCRIPT := preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

const SWARM_CONFIG: SwarmDroneConfig = preload("res://assault/scenes/enemies/swarm_drone/swarm_drone_config.tres")
const RAZOR_CONFIG: RazorDroneConfig = preload("res://assault/scenes/enemies/razor_drone/razor_drone_config.tres")
const RAZOR_SCENE := "res://assault/scenes/enemies/razor_drone/razor_drone.tscn"
const MARGIN := 0.5

const DRONE_OR_RAZOR_SCENES: Array[String] = [
	"res://assault/scenes/enemies/swarm_drone/swarm_drone.tscn",
	"res://assault/scenes/enemies/razor_drone/razor_drone.tscn",
]


## `Level1Director._build_sections()` touches only `LevelSection.new()`, `preload` and
## `WaveBuilder` (a `RefCounted`), so this is safe to call on a bare instance that never entered
## the tree (test_level_1_sequence.gd already relies on the same fact).
func _sections() -> Array:
	var d: Node = DIRECTOR_SCRIPT.new()
	autofree(d)
	return d._build_sections()


func _is_drone_or_razor(entry: SpawnEntryResource) -> bool:
	return entry.ship_scene != null and DRONE_OR_RAZOR_SCENES.has(entry.ship_scene.resource_path)


func _last_wave(section: LevelSection) -> WaveResource:
	var last: WaveResource = null
	for w in section.waves:
		var wave: WaveResource = w
		if last == null or wave.trigger_time > last.trigger_time:
			last = wave
	return last


## The largest `spawn_delay + slot.delay` across every ship the wave spawns, a formation's slots
## included (`FormationResource.compute_slots()`, wave_manager.gd: `base_delay + slot.delay`).
func _max_delay(wave: WaveResource) -> float:
	var max_delay := 0.0
	for e in wave.entries:
		var entry: SpawnEntryResource = e
		if entry.formation != null:
			for s in entry.formation.compute_slots():
				var slot: FormationResource.FormationSlot = s
				max_delay = maxf(max_delay, entry.spawn_delay + slot.delay)
		else:
			max_delay = maxf(max_delay, entry.spawn_delay)
	return max_delay


func _section_has_drone_or_razor(section: LevelSection) -> bool:
	for w in section.waves:
		var wave: WaveResource = w
		for e in wave.entries:
			if _is_drone_or_razor(e):
				return true
	return false


## The Swarm never starts an attack its budget cannot finish, so its exit
## begins exactly at `engage_seconds`, from at most `max_speed`.
func _swarm_deadline(last_wave_max_delay: float, exit_distance: float) -> float:
	return last_wave_max_delay + SWARM_CONFIG.engage_seconds + exit_distance / SWARM_CONFIG.exit_speed \
		+ SWARM_CONFIG.exit_speed / (2.0 * SWARM_CONFIG.acceleration) + MARGIN


## The Razor defers its expiry through a boost, so it can start its exit up to `max_dash_seconds` late
## and moving at `dash_speed` AWAY from its exit edge: it must shed that, turn through, and win back
## the ground it lost (task plan docs/plans/cmuj4y8rr007gp52xxs8dec5s, review round 2 A4). Conservative.
func _razor_deadline(last_wave_max_delay: float, exit_distance: float) -> float:
	var c := RAZOR_CONFIG
	return last_wave_max_delay + c.engage_seconds + c.max_dash_seconds \
		+ (c.dash_speed + c.exit_speed) / minf(c.acceleration, c.braking) \
		+ (exit_distance + c.dash_speed * c.dash_speed / (2.0 * c.braking)) / c.exit_speed + MARGIN


func _section_has_scene(section: LevelSection, scene_path: String) -> bool:
	for w in section.waves:
		var wave: WaveResource = w
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene != null and entry.ship_scene.resource_path == scene_path:
				return true
	return false


func _exit_distance() -> float:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := cam.projectile_world_rect()
	return minf(rect.size.x, rect.size.y) / 2.0


func test_every_enemies_cleared_sections_drone_exit_clears_the_timeout() -> void:
	var exit_distance := _exit_distance()
	var checked := 0
	for s in _sections():
		var section: LevelSection = s
		if section.end_condition != LevelSection.EndCondition.ENEMIES_CLEARED:
			continue
		if not _section_has_drone_or_razor(section):
			continue
		checked += 1

		var last_wave_max_delay := _max_delay(_last_wave(section))
		# Each kind is judged by its own config: a Razor here uses the Razor's (longer) formula.
		var deadline := _swarm_deadline(last_wave_max_delay, exit_distance)
		if _section_has_scene(section, RAZOR_SCENE):
			deadline = maxf(deadline, _razor_deadline(last_wave_max_delay, exit_distance))

		assert_lt(deadline, section.enemies_cleared_timeout,
			"section %s: %.2f s must clear its %.1f s timeout"
				% [section.section_name, deadline, section.enemies_cleared_timeout])

	assert_gt(checked, 0, "sanity: at least one ENEMIES_CLEARED section must actually have a drone")


## Boundary (task review B1): the guard really fires for a Razor. A Razor spawned in cloud_descent's
## last wave would need about 15.4 s against a 10 s timeout, so adding one there fails the case above.
## Without this, the Razor formula could silently regress to the Swarm's again.
func test_a_razor_in_an_enemies_cleared_section_would_miss_the_timeout() -> void:
	var exit_distance := _exit_distance()
	var found := false
	for s in _sections():
		var section: LevelSection = s
		if section.section_name != &"cloud_descent":
			continue
		found = true
		assert_eq(section.end_condition, LevelSection.EndCondition.ENEMIES_CLEARED, "sanity")
		var delay := _max_delay(_last_wave(section))
		var razor := _razor_deadline(delay, exit_distance)
		assert_gt(razor, section.enemies_cleared_timeout,
			"a Razor there (%.2f s) must fail the %.1f s timeout" % [razor, section.enemies_cleared_timeout])
		assert_lt(_swarm_deadline(delay, exit_distance), section.enemies_cleared_timeout,
			"control: the Swarm there passes")
		assert_false(_section_has_scene(section, RAZOR_SCENE), "sanity: no Razor spawns there today")
	assert_true(found, "sanity: cloud_descent exists")


## Sanity on the live rect this test depends on — 1608x1608, half the shorter side 804 px, so the
## formula above evaluates to about 9.58 s on today's data (cloud_descent's last wave has a 0.8 s
## max delay: docs/plans/cmufs7ek60001nm2x6d0bt2et/3-plan.md §2.6).
func test_projectile_world_rect_matches_the_plans_804_px_exit_distance() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var rect := cam.projectile_world_rect()
	assert_almost_eq(minf(rect.size.x, rect.size.y) / 2.0, 804.0, 0.01)
