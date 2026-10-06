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
const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")

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
		+ DroneConcurrency.worst_exit_after_speed(c.dash_speed, c.exit_speed, c.acceleration, c.braking,
			exit_distance) + MARGIN


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


# ── Ph3 t17: fighters (docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md §2.9.3, task plan
# docs/plans/cmulwkarp00ctqj2x6ih09c0k/3-plan.md §4) ─────────────────────────────────────────────
#
# Per ENTRY, in the relative form: the ENEMIES_CLEARED clock starts on the tick the section's last wave
# TRIGGERS (`waves_complete`), so a fighter entering at `entry_time` must be gone by
#
#   (entry_time - last_wave_trigger) + engage_seconds + deferral + worst_exit + MARGIN  <  timeout
#
# `entry_time` uses each wave's EFFECTIVE trigger — the running maximum over the list, since
# `WaveManager` triggers strictly in list order. `deferral` = burst_telegraph + max(aimed_max *
# aimed_gap, forward_max * forward_gap): `FighterBrain` defers budget expiry only to the end of a
# running burst. No bullet term: rounds die with their ship (`BulletPool._exit_tree()`).
#
# `worst_exit` is NOT the Razor's straight-line term (task review B1, 4-review.md): `_tick_disengage`
# turns the fighter's VELOCITY toward its exit point at ω = min(turn_rate, acceleration / exit_speed)
# while asking for `exit_speed`, so a fighter flying away from its exit swings round on a curve. The
# term below bounds that: a half turn (π/ω), then a straight run that covers `exit_distance` plus the
# turn's overshoot (at most a diameter, 2·exit_speed/ω — the run to the exit point is never longer
# than that while exit_distance ≥ the turn radius / 2). `test_the_fighter_exit_term_bounds_a_real_fighters_disengage`
# gates it on the real `fighter.tscn`.

const FIGHTER_CONFIG: FighterConfig = preload("res://assault/scenes/enemies/fighter/fighter_config.tres")
const GATLING_CONFIG: GatlingInterceptorConfig = \
	preload("res://assault/scenes/enemies/gatling_interceptor/gatling_interceptor_config.tres")
const FIGHTER_SCENE: PackedScene = preload("res://assault/scenes/enemies/fighter/fighter.tscn")
const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DT := 1.0 / 60.0


func _fighter_deferral() -> float:
	var f := FIGHTER_CONFIG
	return f.burst_telegraph + maxf(f.aimed_max * f.aimed_gap, f.forward_max * f.forward_gap)


## The curved DISENGAGE bound (header). 5.37 s with today's config and the 804 px exit distance.
func _fighter_exit_bound(exit_distance: float) -> float:
	var f := FIGHTER_CONFIG
	var omega := minf(f.turn_rate, f.acceleration / f.exit_speed)
	return PI / omega + (exit_distance + 2.0 * f.exit_speed / omega) / f.exit_speed


## Everything after entry: budget, worst burst deferral, worst exit, margin.
func _fighter_tail(exit_distance: float) -> float:
	return FIGHTER_CONFIG.engage_seconds + _fighter_deferral() + _fighter_exit_bound(exit_distance) + MARGIN


func _gatling_deferral() -> float:
	var g := GATLING_CONFIG
	return g.spin_up_seconds + g.sync_wait_max + g.stream_rounds_max * g.stream_interval


## Razor-shaped, as the task specifies. Only ever used by a row that must FAIL, so an exit that is
## really longer (the Gatling's DISENGAGE curves too) can only make that row fail harder.
func _gatling_tail(exit_distance: float) -> float:
	var g := GATLING_CONFIG
	return g.engage_seconds + _gatling_deferral() \
		+ DroneConcurrency.worst_exit_after_speed(g.max_speed, g.exit_speed, g.acceleration, g.braking,
			exit_distance) + MARGIN


## THE per-entry check: one `{ "trigger", "delay", "rel", "computed", "over" }` per ship of `scene_path`
## the section spawns, formation slots expanded. `trigger` is the wave's effective trigger (running max
## in list order); `rel` = entry time - the section's last effective trigger; `computed` = rel + tail;
## `over` = computed >= the section's timeout. Every fighter and Gatling row below goes through this.
func _deadline_rows(section: LevelSection, scene_path: String, tail: float) -> Array[Dictionary]:
	var effective: Array[float] = []
	var running := -INF
	for w in section.waves:
		running = maxf(running, (w as WaveResource).trigger_time)
		effective.append(running)
	var last_trigger := running
	var rows: Array[Dictionary] = []
	for i in section.waves.size():
		var wave: WaveResource = section.waves[i]
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene == null or entry.ship_scene.resource_path != scene_path:
				continue
			var delays: Array[float] = []
			if entry.formation != null:
				for s in entry.formation.compute_slots():
					delays.append(entry.spawn_delay + (s as FormationResource.FormationSlot).delay)
			else:
				delays.append(entry.spawn_delay)
			for d in delays:
				var rel := effective[i] + d - last_trigger
				rows.append({"trigger": effective[i], "delay": d, "rel": rel, "computed": rel + tail,
					"over": rel + tail >= section.enemies_cleared_timeout})
	return rows


func _over(rows: Array[Dictionary]) -> Array[Dictionary]:
	return rows.filter(func(r: Dictionary) -> bool: return r["over"])


## A freshly built cloud_descent: each call builds new resources, so a test may add to it freely.
func _cloud_descent() -> LevelSection:
	for s in _sections():
		var section: LevelSection = s
		if section.section_name == &"cloud_descent":
			return section
	return null


## A copy of the section's last wave with one extra `scene` entry at `delay` (the original wave's
## entries array is replaced, not mutated in place).
func _add_to_last_wave(section: LevelSection, scene: PackedScene, delay: float) -> void:
	var last := _last_wave(section)
	var entries: Array[SpawnEntryResource] = []
	entries.assign(last.entries)
	var extra := SpawnEntryResource.new()
	extra.ship_scene = scene
	extra.spawn_delay = delay
	entries.append(extra)
	last.entries = entries


func test_every_enemies_cleared_fighter_entry_clears_the_timeout() -> void:
	var tail := _fighter_tail(_exit_distance())
	var checked := 0
	for s in _sections():
		var section: LevelSection = s
		if section.end_condition != LevelSection.EndCondition.ENEMIES_CLEARED:
			continue
		var timeout := section.enemies_cleared_timeout
		var rows := _deadline_rows(section, WaveBuilder.FIGHTER, tail)
		if section.section_name == &"cloud_descent":
			assert_eq(rows.size(), 31, "sanity: cloud_descent's 27 fighter lines spawn 31 ships (25 + wedge 3 + V 3)")
		checked += rows.size()
		for row in _over(rows):
			fail_test("%s: fighter entering at %.1f s + %.2f s needs %.2f s of the %.1f s timeout"
				% [section.section_name, row["trigger"], row["delay"], row["computed"], timeout])
		var worst: Dictionary = {}
		for row in rows:
			if worst.is_empty() or float(row["computed"]) > float(worst["computed"]):
				worst = row
		if not worst.is_empty():
			gut.p("%s: worst fighter entry %.1f s + %.2f s (%.2f s from the last trigger) computes %.2f s "
				% [section.section_name, worst["trigger"], worst["delay"], worst["rel"], worst["computed"]]
				+ "(tail %.2f = engage %.1f + deferral %.2f + curved exit %.2f + margin %.1f): margin %.2f s of %.1f s"
				% [tail, FIGHTER_CONFIG.engage_seconds, _fighter_deferral(), _fighter_exit_bound(_exit_distance()),
					MARGIN, timeout - float(worst["computed"]), timeout])
	assert_gt(checked, 0, "sanity: at least one fighter entry of an ENEMIES_CLEARED section was checked")


## Boundary, literal (from the task): a fighter added to cloud_descent's 76.0 s wave at that wave's own
## latest delay, 0.8 s, is flagged by the same check — it computes 0.8 + tail (13.47 s with the curved
## exit; the task's straight-line figure was 10.94) against the 10 s timeout. Derived from today's
## `engage_seconds` 6.0: if a pre-approved lever ever shortens it below about 2.7 s, re-derive this row;
## the config-derived row below keeps proving the check rejects either way.
func test_a_fighter_in_the_last_wave_at_delay_0_8_misses_the_timeout() -> void:
	var section := _cloud_descent()
	assert_not_null(section, "sanity: cloud_descent exists")
	if section == null:
		return
	var last := _last_wave(section)
	assert_almost_eq(last.trigger_time, 76.0, 0.001, "sanity: cloud_descent's last wave triggers at 76.0 s")
	assert_almost_eq(_max_delay(last), 0.8, 0.001, "sanity: its latest delay is 0.8 s")
	for e in last.entries:
		var entry: SpawnEntryResource = e
		assert_false(entry.ship_scene != null and entry.ship_scene.resource_path == WaveBuilder.FIGHTER,
			"the shipped 76.0 s wave contains no fighter")

	var tail := _fighter_tail(_exit_distance())
	assert_eq(_over(_deadline_rows(section, WaveBuilder.FIGHTER, tail)).size(), 0, "control: the shipped section passes")
	_add_to_last_wave(section, FIGHTER_SCENE, 0.8)
	var over := _over(_deadline_rows(section, WaveBuilder.FIGHTER, tail))
	assert_eq(over.size(), 1, "the added delay-0.8 fighter (and only it) must be flagged")
	if over.size() == 1:
		var computed: float = over[0]["computed"]
		assert_almost_eq(float(over[0]["rel"]), 0.8, 0.001, "it enters 0.8 s after the last trigger")
		assert_gte(computed, 10.9, "the task's figure: a delay-0.8 fighter there computes >= 10.9 s")
		assert_gt(computed, section.enemies_cleared_timeout, "%.2f s must exceed the %.1f s timeout"
			% [computed, section.enemies_cleared_timeout])


## Boundary, config-derived (epic review N5 — survives a lever on `engage_seconds`): a one-fighter wave
## inserted just before cloud_descent's last wave, triggering 0.25 s past the latest time the formula
## allows (last trigger + timeout − tail), is flagged by the same check; the same wave 0.5 s earlier is not.
## Today that is 73.58 s vs 73.08 s. The shipped section, run through the check unchanged, is the control.
func test_a_fighter_just_past_the_config_derived_limit_misses_the_timeout() -> void:
	var tail := _fighter_tail(_exit_distance())
	var shipped := _cloud_descent()
	assert_not_null(shipped, "sanity: cloud_descent exists")
	if shipped == null:
		return
	assert_eq(_over(_deadline_rows(shipped, WaveBuilder.FIGHTER, tail)).size(), 0, "control: the shipped section passes")
	var limit := _last_wave(shipped).trigger_time + shipped.enemies_cleared_timeout - tail

	var late := _with_fighter_wave_before_last(limit + 0.25)
	var over := _over(_deadline_rows(late, WaveBuilder.FIGHTER, tail))
	assert_eq(over.size(), 1, "the fighter wave at %.2f s (and only it) must be flagged" % (limit + 0.25))
	if over.size() == 1:
		assert_gt(float(over[0]["computed"]), late.enemies_cleared_timeout, "%.2f s must exceed the %.1f s timeout"
			% [float(over[0]["computed"]), late.enemies_cleared_timeout])

	var early := _with_fighter_wave_before_last(limit - 0.25)
	assert_eq(_over(_deadline_rows(early, WaveBuilder.FIGHTER, tail)).size(), 0,
		"control: the same wave at %.2f s, inside the limit, passes" % (limit - 0.25))


## A freshly built cloud_descent with a one-fighter wave at `trigger` inserted just before its last wave.
## Asserts the insert keeps list order monotonic, so `trigger` is also the wave's effective trigger.
func _with_fighter_wave_before_last(trigger: float) -> LevelSection:
	var section := _cloud_descent()
	var last_index := section.waves.size() - 1
	assert_eq(section.waves[last_index], _last_wave(section), "sanity: the last-listed wave triggers last")
	assert_between(trigger, (section.waves[last_index - 1] as WaveResource).trigger_time,
		(section.waves[last_index] as WaveResource).trigger_time, "sanity: the inserted wave sits in list order")
	var entry := SpawnEntryResource.new()
	entry.ship_scene = FIGHTER_SCENE
	var wave := WaveResource.new()
	wave.trigger_time = trigger
	var entries: Array[SpawnEntryResource] = [entry]
	wave.entries = entries
	var waves: Array[WaveResource] = []
	waves.assign(section.waves)
	waves.insert(last_index, wave)
	section.waves = waves
	return section


## Boundary: a Gatling added at delay 0 to cloud_descent's last wave is flagged — its deferral
## (spin_up + sync_wait_max + 12 x 0.09 = 2.08 s) and 7.0 s budget put it at about 12.5 s against 10 s.
## station_assault, the other ENEMIES_CLEARED section, has a 180 s net sized for the boss fight; the
## same entry there is reported, not asserted.
func test_a_gatling_in_an_enemies_cleared_last_wave_misses_the_timeout() -> void:
	assert_almost_eq(_gatling_deferral(), 2.08, 0.001, "sanity: the task's 0.25 + 0.75 + 12 x 0.09")
	var tail := _gatling_tail(_exit_distance())
	for s in _sections():
		var section: LevelSection = s
		if section.end_condition != LevelSection.EndCondition.ENEMIES_CLEARED:
			continue
		_add_to_last_wave(section, load(WaveBuilder.GATLING_INTERCEPTOR) as PackedScene, 0.0)
		var rows := _deadline_rows(section, WaveBuilder.GATLING_INTERCEPTOR, tail)
		assert_eq(rows.size(), 1, "%s: sanity: exactly the added Gatling" % section.section_name)
		if rows.size() != 1:
			continue
		var computed: float = rows[0]["computed"]
		if section.section_name == &"cloud_descent":
			assert_true(rows[0]["over"], "cloud_descent: the delay-0 Gatling must be flagged")
			assert_gt(computed, section.enemies_cleared_timeout, "cloud_descent: %.2f s must exceed %.1f s"
				% [computed, section.enemies_cleared_timeout])
		else:
			gut.p("%s: a delay-0 Gatling computes %.2f s against its %.1f s net"
				% [section.section_name, computed, section.enemies_cleared_timeout])


func test_no_enemies_cleared_section_spawns_a_gatling() -> void:
	var checked := 0
	for s in _sections():
		var section: LevelSection = s
		if section.end_condition != LevelSection.EndCondition.ENEMIES_CLEARED:
			continue
		checked += 1
		assert_false(_section_has_scene(section, WaveBuilder.GATLING_INTERCEPTOR),
			"%s spawns a Gatling Interceptor in its waves" % section.section_name)
	assert_gt(checked, 0, "sanity: level 1 has ENEMIES_CLEARED sections")


## The exit term is a claim about `FighterBrain._tick_disengage`, so it is gated on the real scene: a
## fighter in the Assault harness (camera at MID, the live 1608 x 1608 world rect), hand-ticked like
## `test_fighter.gd`, put into DISENGAGE from a grid over the visible view x 8 headings x two start speeds —
## `max_speed`, and just above the standing-start threshold (`FighterBrain.STANDING_START_FRACTION` x
## `max_speed` + 1), where the turn-round is slowest (task review round 2 B3) — plus the two named starts (the rect's centre heading directly away from its tie-broken left
## exit; 200 px below centre heading away from its bottom exit). Every one must be freed within the
## bound. Boundary: the slowest also takes longer than the Razor-shaped straight-line term the task
## first specified, which is why that term is not used (task review B1).
func test_the_fighter_exit_term_bounds_a_real_fighters_disengage() -> void:
	var h: RefCounted = HARNESS.assault()
	add_child_autofree(h.root)
	h.player.global_position = MID_VIEW + Vector2(0.0, 300.0)
	var exit_distance := _exit_distance()
	var bound := _fighter_exit_bound(exit_distance)
	var starts: Array = [[Vector2.ZERO, Vector2.RIGHT], [Vector2(0.0, 200.0), Vector2.UP]]
	for x in [-560.0, -280.0, 0.0, 280.0, 560.0]:
		for y in [-320.0, -160.0, 0.0, 160.0, 320.0]:
			for k in 8:
				starts.append([Vector2(x, y), Vector2.RIGHT.rotated(k * PI / 4.0)])
	var speeds: Array[float] = [FIGHTER_CONFIG.max_speed,
		FighterBrain.STANDING_START_FRACTION * FIGHTER_CONFIG.max_speed + 1.0]
	var slowest := 0.0
	var slowest_start := ""
	for start in starts:
		for speed in speeds:
			var t := _disengage_seconds(h, MID_VIEW + start[0], start[1] * speed, bound + 5.0)
			assert_lte(t, bound, "a fighter at %s heading %s at %.0f px/s took %.2f s to leave (bound %.2f s)"
				% [start[0], start[1], speed, t, bound])
			if t > slowest:
				slowest = t
				slowest_start = "%s heading %s at %.0f px/s" % [start[0], start[1], speed]
	var f := FIGHTER_CONFIG
	var straight := DroneConcurrency.worst_exit_after_speed(f.max_speed, f.exit_speed, f.acceleration, f.braking,
		exit_distance)
	gut.p("fighter DISENGAGE over %d starts: slowest %.2f s (%s); bound %.2f s, straight-line term %.2f s"
		% [starts.size() * speeds.size(), slowest, slowest_start, bound, straight])
	assert_gt(slowest, straight, "the straight-line term is not a bound on the curved exit")


const MID_VIEW := Vector2(640.0, 360.0)


## Seconds from `enter_phase(DISENGAGE)` until the fighter queues itself for deletion (or `cap`).
func _disengage_seconds(h: RefCounted, pos: Vector2, velocity: Vector2, cap: float) -> float:
	var fighter := FIGHTER_SCENE.instantiate() as Fighter
	fighter.global_position = pos
	var brain := fighter.get_node("Brain") as FighterBrain
	brain.rng_seed = 1
	brain.start_engaged = true
	h.root.add_child(fighter)
	fighter.set_physics_process(false)
	fighter.velocity = velocity
	brain.enter_phase(FighterBrain.Phase.DISENGAGE)
	var t := 0.0
	while t < cap and not fighter.is_queued_for_deletion():
		var before := fighter.global_position
		fighter._physics_process(DT)
		fighter.global_position = before + fighter.velocity * DT
		t += DT
	fighter.free()
	return t
