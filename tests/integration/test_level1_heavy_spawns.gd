## Level 1's four Heavy Gunships (Phase 10 t11; epic plan docs/plans/cmug23oo90029m52wae4clve0/3-plan.md §2.12, task plan
## docs/plans/cmwafsrbi00azqs2yuwzayuk3/3-plan.md §3). Intent, not characterization: the three Cloud Descent heavies left their rails in t11 (a rail
## suspends the brain, so before t11 they never fired) and the deep_space one moved to `.at(160, -500)` (the owner's option M, with the hull's body
## `collision_mask` 0), so every row here asserts what t11 is for.
##
## PURE DATA (no physics): the pin `EXPECTED_PH10_GUNSHIPS` (trigger, offset, delay; the effective trigger is the wave's own), no rail, the frozen
## `_LEGACY_PEAK_HEAVIES` recomputed from the pre-t11 rails every run (`_LEGACY_ROWS`, the old `WaveBuilder.straight(42 / 36)` rails as data), the
## heavy count gate (peak alive per section <= 1.0 x the frozen peak; a section without one holds none), the spill-over row (a DURATION
## section's heavy, its last rocket included, is gone before its own section ends and before the next ENEMIES_CLEARED section's last trigger) and
## which heavies meet lasers at all (only the deep_space one: every Cloud Descent column set is dark before the first Cloud Descent heavy).
## A heavy's life is `engage_seconds + attack_window() + measured exit`; the exit is `ph10_exit_keys.gd`'s memoised corridor probe, read in
## `before_all()` before any replay world exists (its `prepare_probe` strips group `player` from the whole tree).
##
## REPLAYS (`tests/helpers/level1_slice_replay.gd`, the 16x clock), each run once, lazily by the first test that needs it, and shared as data
## (tests/README.md -> Gate time rule 2):
##   deep_space lit     the section from 0.0 s with its real wall and columns (`light_lasers`), stopped once the heavy has left and the 6.0 s row's
##                      lethal end + 1.25 s has passed. One scenario is the heavy's laser check, its attack-in-budget row and its fire record.
##   kill boundary      deep_space from 2.5 s (the wall relit with a 0.5 s warning) plus one added heavy; the two heavies are held at x 640 (the
##                      wall's 644 ray) and x 1152 (the 6.0 s set's column) with avoidance off, so each must be reported dead under a lit ray.
##   carried over       deep_space from 11.0 s, no ships: the 6.0 s row relit mid-way (warn 0, active 1.8) must be lethal until its real end.
##   cloud_descent      50.0 - 1.0 s to 62.8 + engage + 2.0 s, lasers off (none is lit there), all three heavies.
## Every lit run caps `Engine.max_physics_steps_per_frame` at `LIT_MAX_STEPS` (the deep_space slice is CPU-bound at 16x; uncapped its idle
## frames reach 2.13 game s and every laser edge reads late: README rule 1).
extends GutTest

const REPLAY: GDScript = preload("res://tests/helpers/level1_slice_replay.gd")
const PH10_EXITS: GDScript = preload("res://tests/helpers/ph10_exit_keys.gd")
const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")
const DIRECTOR_SCRIPT: GDScript = preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")
const SHIPPED: HeavyGunshipConfig = preload("res://assault/scenes/enemies/heavy_gunship/heavy_gunship_config.tres")  # read only
const HEAVY := WaveBuilder.HEAVY_GUNSHIP
const Phase := HeavyGunshipBrain.Phase

const _SPEEDUP := 16
## A lit run's physics steps per idle frame (time scale and tick rate stay x 16, so a step is still 1/60 game s).
const LIT_MAX_STEPS := 16
const TICK := 1.0 / 60.0
## Half of the epic review's N4 shift (a wall lit 2.5 s late): a laser edge's late tolerance must stay under it.
const EDGE_GUARD := 1.25
## The rail sampling cap and step (`test_level1_specialist_spawns.gd`'s).
const _CULL_CAP := 20.0
const _CULL_STEP := 0.02
## The fire-density window (s): the fighter density gate's.
const FIRE_WINDOW := 2.0
## The kill-detection boundary's held x (world px): inside the wall's 644 ray, and on the 6.0 s set's 1152 column.
const HELD_X: Array[float] = [640.0, 1152.0]

## Every Heavy Gunship line of level 1, in encounter order: section, the wave's own trigger, offset, delay. The deep_space offset is lever 2
## (task plan §5a, option M; the legacy row was (0, -500)).
const EXPECTED_PH10_GUNSHIPS: Array[Dictionary] = [
	{"section": &"deep_space", "trigger": 3.5, "offset": Vector2(160.0, -500.0), "delay": 0.0},
	{"section": &"cloud_descent", "trigger": 50.0, "offset": Vector2(0.0, -400.0), "delay": 0.0},
	{"section": &"cloud_descent", "trigger": 62.0, "offset": Vector2(-100.0, -400.0), "delay": 0.0},
	{"section": &"cloud_descent", "trigger": 62.0, "offset": Vector2(100.0, -400.0), "delay": 0.8},
]

## The most gunships alive at once per section before t11, from a computed run of `_legacy_peaks()` over `_LEGACY_ROWS` (frozen; the
## recompute row keeps it honest). Divided by in the count gate.
const _LEGACY_PEAK_HEAVIES: Dictionary = {
	&"deep_space": 1,
	&"cloud_descent": 3,
}

var _exit: Dictionary = {}
var _window: float = -1.0
var _rocket_life: float = -1.0
var _deep: Dictionary = {}
var _boundary: Dictionary = {}
var _carried: Dictionary = {}
var _cloud: Dictionary = {}
var _saved_time_scale: float = 1.0
var _saved_ticks: int = 60
var _saved_max_steps: int = 8
var _clock_scaled: bool = false


func before_all() -> void:
	_exit = PH10_EXITS.heavy_gunship_exit(self)


func after_each() -> void:
	_restore_clock()


## The 16x clock; a lit run caps the steps per frame at `max_steps` instead of scaling them.
func _scale_clock(max_steps: int = -1) -> void:
	if _clock_scaled:
		return
	_saved_time_scale = Engine.time_scale
	_saved_ticks = Engine.physics_ticks_per_second
	_saved_max_steps = Engine.max_physics_steps_per_frame
	_clock_scaled = true
	Engine.physics_ticks_per_second = _saved_ticks * _SPEEDUP
	Engine.max_physics_steps_per_frame = max_steps if max_steps > 0 else _saved_max_steps * _SPEEDUP
	Engine.time_scale = _saved_time_scale * _SPEEDUP


func _restore_clock() -> void:
	if not _clock_scaled:
		return
	_clock_scaled = false
	Engine.time_scale = _saved_time_scale
	Engine.physics_ticks_per_second = _saved_ticks
	Engine.max_physics_steps_per_frame = _saved_max_steps


# ── Data ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

func _build_sections() -> Array[LevelSection]:
	var d: Node = DIRECTOR_SCRIPT.new()
	var sections: Array[LevelSection] = d._build_sections()
	d.free()
	return sections


func _section(sections: Array[LevelSection], section_name: StringName) -> LevelSection:
	for s in sections:
		if s.section_name == section_name:
			return s
	return null


## One `{ "section", "trigger", "effective", "offset", "delay", "entry" }` per heavy line, in encounter order (`trigger` the wave's own,
## `effective` the running max in list order, the trigger `WaveManager` really uses).
func _heavy_lines(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section in sections:
		var effective := -INF
		for wave: WaveResource in section.waves:
			effective = maxf(effective, wave.trigger_time)
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene == null or entry.ship_scene.resource_path != HEAVY:
					continue
				out.append({"section": section.section_name, "trigger": wave.trigger_time, "effective": effective,
					"offset": entry.base_offset, "delay": entry.spawn_delay, "entry": entry})
	return out


## The pin's shape of `_heavy_lines()`.
func _pin_rows(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in _heavy_lines(sections):
		out.append({"section": line["section"], "trigger": line["trigger"], "offset": line["offset"], "delay": line["delay"]})
	return out


## The four gunship rows as they shipped before t11 (the deep_space one AI since t4, at (0, -500); the Cloud Descent three on straight rails),
## as data: the legacy peak is recomputed from them every run.
func _legacy_rows() -> Array[Dictionary]:
	var b := WaveBuilder.new()
	return [
		{"section": &"deep_space", "trigger": 3.5, "offset": Vector2(0.0, -500.0), "delay": 0.0, "movement": null},
		{"section": &"cloud_descent", "trigger": 50.0, "offset": Vector2(0.0, -400.0), "delay": 0.0, "movement": b.straight(42)},
		{"section": &"cloud_descent", "trigger": 62.0, "offset": Vector2(-100.0, -400.0), "delay": 0.0, "movement": b.straight(36)},
		{"section": &"cloud_descent", "trigger": 62.0, "offset": Vector2(100.0, -400.0), "delay": 0.8, "movement": b.straight(36)},
	]


## A rail row lives until it leaves `enemy_cull_rect()` after having been inside it (the `EnemyPathMover` rule), capped at `_CULL_CAP`
## (`test_level1_specialist_spawns.gd::_rail_lifetime()`, copied: those helpers are another test's instance methods). Returns 0.0 for no rail;
## the caller treats a no-rail legacy gunship as never leaving (it held until killed).
func _rail_lifetime(offset: Vector2, movement: MovementResource, cam: ArenaCamera) -> float:
	if movement == null:
		return 0.0
	var rect := cam.enemy_cull_rect()
	var has_been_on_screen := false
	var t := 0.0
	while t <= _CULL_CAP:
		var world: Vector2 = (offset + movement.sample(t)) * ArenaCamera.WORLD_SCALE
		var inside := rect.has_point(world)
		if not has_been_on_screen:
			if inside:
				has_been_on_screen = true
		elif not inside:
			return t
		t += _CULL_STEP
	return _CULL_CAP


## `{ "count", "at" }`: the most intervals alive at once and the first start at which that is reached.
func _peak(intervals: Array[Dictionary]) -> Dictionary:
	var best := {"count": 0, "at": 0.0}
	for a in intervals:
		var t: float = a["start"]
		var alive := 0
		for b in intervals:
			if float(b["start"]) <= t and t < float(b["end"]):
				alive += 1
		if alive > int(best["count"]):
			best = {"count": alive, "at": t}
	return best


func _legacy_peaks() -> Dictionary:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var by_section: Dictionary = {}
	for row in _legacy_rows():
		var start: float = float(row["trigger"]) + float(row["delay"])
		var life := INF if row["movement"] == null else _rail_lifetime(row["offset"], row["movement"], cam)
		if not by_section.has(row["section"]):
			by_section[row["section"]] = [] as Array[Dictionary]
		(by_section[row["section"]] as Array[Dictionary]).append({"start": start, "end": start + life, "life": life})
	var out: Dictionary = {}
	for key in by_section:
		out[key] = {"peak": int(_peak(by_section[key])["count"]), "intervals": by_section[key]}
	return out


## The heavy cannon's window at full strength, from a live heavy's brain (`attack_window()`). Cached.
func _attack_window() -> float:
	if _window >= 0.0:
		return _window
	var h: RefCounted = HARNESS.assault()
	add_child(h.root)
	var g := (load(HEAVY) as PackedScene).instantiate() as HeavyGunship
	h.root.add_child(g)
	_window = (g.get_node(^"Brain") as HeavyGunshipBrain).attack_window()
	remove_child(h.root)
	h.root.free()
	return _window


## The longest a rear-missile rocket lives (s): max `max_time` over the Missiles mount's `pool_specs()` scenes, the mount found through the
## scene's own `Modules/Missiles/MountSlots/Slot0` variant. Cached.
func _rocket_max_life() -> float:
	if _rocket_life >= 0.0:
		return _rocket_life
	var g := (load(HEAVY) as PackedScene).instantiate()
	var variant: int = (g.get_node(^"Modules/Missiles/MountSlots/Slot0") as TurretMountSlot).variant
	g.free()
	var mount := TurretMountScenes.scene_for(variant).instantiate()
	_rocket_life = 0.0
	for spec: Dictionary in mount.pool_specs():
		var rocket := (spec["scene"] as PackedScene).instantiate()
		_rocket_life = maxf(_rocket_life, float(rocket.get(&"max_time")))
		rocket.free()
	mount.free()
	return _rocket_life


## `engage_seconds + attack_window() + measured exit`: a heavy's Assault life from its spawn.
func _heavy_life(engage: float = SHIPPED.engage_seconds) -> float:
	return engage + _attack_window() + float(_exit["seconds"])


func _heavy_intervals(section: LevelSection) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for line in _heavy_lines([section] as Array[LevelSection]):
		var start: float = float(line["effective"]) + float(line["delay"])
		out.append({"start": start, "end": start + _heavy_life()})
	return out


## A one-heavy wave at `trigger` inserted in list order (before the first wave that triggers later), so its effective trigger is its own.
func _insert_heavy_wave(section: LevelSection, trigger: float) -> void:
	var index := section.waves.size()
	for i in section.waves.size():
		if (section.waves[i] as WaveResource).trigger_time > trigger:
			index = i
			break
	var b := WaveBuilder.new()
	var waves: Array[WaveResource] = []
	waves.assign(section.waves)
	waves.insert(index, b.wave(trigger, [b.heavy_gunship().at(0, -400)]))
	section.waves = waves
	var effective := -INF
	for i in index + 1:
		effective = maxf(effective, (section.waves[i] as WaveResource).trigger_time)
	assert_almost_eq(effective, trigger, 0.0001, "sanity: the inserted wave sits in list order")


# ── The pin ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func test_pinned_heavy_gunship_spawns_match_the_director() -> void:
	var sections := _build_sections()
	assert_eq(_pin_rows(sections), EXPECTED_PH10_GUNSHIPS, "a Heavy Gunship line's section, trigger, offset or delay changed")
	for line in _heavy_lines(sections):
		assert_almost_eq(float(line["effective"]), float(line["trigger"]), 0.0001,
			"%s %.1f s: the wave's effective trigger is its own (no later-listed wave holds it back)" % [line["section"], line["trigger"]])
	var placed: Array[Dictionary] = REPLAY.placed(HEAVY)
	assert_eq(placed.size(), EXPECTED_PH10_GUNSHIPS.size(), "the replay helper reads the same four lines")
	for i in mini(placed.size(), EXPECTED_PH10_GUNSHIPS.size()):
		assert_almost_eq(float(placed[i]["trigger"]), float(EXPECTED_PH10_GUNSHIPS[i]["trigger"]), 0.0001)
		assert_eq(placed[i]["offset"], EXPECTED_PH10_GUNSHIPS[i]["offset"])


## The legacy rows and the pin are the same four arrivals: only the deep_space offset moved (lever 2), so they agree on section, trigger, delay.
func test_the_legacy_rows_are_the_pins_arrivals() -> void:
	var legacy := _legacy_rows()
	assert_eq(legacy.size(), EXPECTED_PH10_GUNSHIPS.size())
	for i in mini(legacy.size(), EXPECTED_PH10_GUNSHIPS.size()):
		var a: Dictionary = legacy[i]
		var p: Dictionary = EXPECTED_PH10_GUNSHIPS[i]
		assert_eq(a["section"], p["section"])
		assert_almost_eq(float(a["trigger"]), float(p["trigger"]), 0.0001)
		assert_almost_eq(float(a["delay"]), float(p["delay"]), 0.0001)
		if a["section"] == &"cloud_descent":
			assert_eq(a["offset"], p["offset"], "a Cloud Descent heavy arrives where its gunship did")


## Boundaries: a changed delay or offset fails the pin.
func test_a_heavy_lines_changed_delay_or_offset_fails_the_pin() -> void:
	var sections := _build_sections()
	var lines := _heavy_lines(sections)
	assert_eq(lines.size(), 4, "sanity: four heavy lines")
	if lines.size() != 4:
		return
	(lines[2]["entry"] as SpawnEntryResource).spawn_delay += 0.5
	assert_ne(_pin_rows(sections), EXPECTED_PH10_GUNSHIPS, "a heavy with a changed delay must not match the pin")
	sections = _build_sections()
	(_heavy_lines(sections)[0]["entry"] as SpawnEntryResource).base_offset = Vector2(0.0, -500.0)
	assert_ne(_pin_rows(sections), EXPECTED_PH10_GUNSHIPS, "the legacy deep_space offset must not match the pin")


# ── No rail ──────────────────────────────────────────────────────────────────────────────────────────────────────────

func _rail_violations(sections: Array[LevelSection]) -> Array[String]:
	var out: Array[String] = []
	for line in _heavy_lines(sections):
		var entry: SpawnEntryResource = line["entry"]
		if entry.movement != null:
			out.append("%s %.1f s has a rail" % [line["section"], line["trigger"]])
		if entry.exit_mode != EnemyPathMover.ExitMode.FREE_ON_SCREEN_EXIT or entry.exit_time != 0.0:
			out.append("%s %.1f s has an exit mode" % [line["section"], line["trigger"]])
		if entry.formation != null:
			out.append("%s %.1f s has a formation" % [line["section"], line["trigger"]])
	return out


func test_no_heavy_gunship_rides_a_rail() -> void:
	assert_eq(_rail_violations(_build_sections()), [] as Array[String], "a rail suspends the heavy's brain: it never fires")


## Boundary: the 50.0 s heavy's legacy `.move(b.straight(42))` put back fails it.
func test_a_heavy_given_its_rail_back_fails_the_no_rail_check() -> void:
	var sections := _build_sections()
	var lines := _heavy_lines(sections)
	assert_eq(lines.size(), 4, "sanity: four heavy lines")
	if lines.size() != 4:
		return
	(lines[1]["entry"] as SpawnEntryResource).movement = WaveBuilder.new().straight(42)
	assert_eq(_rail_violations(sections).size(), 1, "the railed 50.0 s heavy is flagged")


# ── The legacy peak, the count gate ──────────────────────────────────────────────────────────────────────────────────

func test_the_legacy_peak_heavies_recompute_to_the_frozen_values() -> void:
	var peaks := _legacy_peaks()
	assert_eq(peaks.size(), _LEGACY_PEAK_HEAVIES.size(), "the frozen constant covers every legacy section")
	for key in _LEGACY_PEAK_HEAVIES:
		assert_true(peaks.has(key), "%s had legacy gunships" % key)
		if not peaks.has(key):
			continue
		var lives: Array = (peaks[key]["intervals"] as Array).map(func(a: Dictionary) -> String: return "%.2f" % float(a["life"]))
		gut.p("%s: legacy peak %d (lives %s)" % [key, peaks[key]["peak"], lives])
		assert_eq(int(peaks[key]["peak"]), int(_LEGACY_PEAK_HEAVIES[key]), "%s: legacy peak gunships changed" % key)
	var rail := _legacy_peaks()[&"cloud_descent"]["intervals"][0] as Dictionary
	assert_between(float(rail["life"]), 12.8, _CULL_CAP - _CULL_STEP,
		"the 50.0 s rail outlived the 62.8 s spawn and left the cull rect before the cap")


func test_the_measured_heavy_exit_is_real() -> void:
	gut.p("heavy life %.2f s = engage %.1f + attack window %.2f + measured exit %.2f (worst from %s over %d runs, %d capped)" % [_heavy_life(),
		SHIPPED.engage_seconds, _attack_window(), _exit["seconds"], _exit["start"], _exit["runs"], _exit["capped"]])
	assert_eq(int(_exit["capped"]), 0, "no probe run hit the cap")
	assert_gt(float(_exit["seconds"]), 0.0)


func test_peak_alive_heavies_stay_within_the_legacy_peak() -> void:
	var checked := 0
	for section in _build_sections():
		var peak := _peak(_heavy_intervals(section))
		var limit := int(_LEGACY_PEAK_HEAVIES.get(section.section_name, 0))
		if int(peak["count"]) > 0 or limit > 0:
			gut.p("%s: peak alive heavies %d at %.2f s (frozen %d)" % [section.section_name, peak["count"], peak["at"], limit])
		assert_lte(int(peak["count"]), limit, "%s: more heavies alive at once than the legacy gunships" % section.section_name)
		checked += 1
	assert_eq(checked, 5, "sanity: every level-1 section was checked")


## Boundary: one extra heavy inserted (in list order) at each section's own peak moment fails the gate.
func test_one_extra_heavy_at_the_peak_fails_the_count_gate() -> void:
	for key in _LEGACY_PEAK_HEAVIES:
		var section := _section(_build_sections(), key)
		var before := _peak(_heavy_intervals(section))
		_insert_heavy_wave(section, float(before["at"]))
		var after := _peak(_heavy_intervals(section))
		gut.p("%s + one heavy at %.2f s: peak %d -> %d (frozen %d)" % [key, before["at"], before["count"], after["count"], _LEGACY_PEAK_HEAVIES[key]])
		assert_eq(int(after["count"]), int(before["count"]) + 1, "%s: the extra heavy is alive at the peak" % key)
		assert_gt(int(after["count"]), int(_LEGACY_PEAK_HEAVIES[key]), "%s: the count gate must reject it" % key)


## Boundary: planet_approach had no gunship, so a heavy there fails the gate.
func test_a_heavy_in_planet_approach_fails_the_count_gate() -> void:
	var section := _section(_build_sections(), &"planet_approach")
	assert_eq(_peak(_heavy_intervals(section))["count"], 0, "control: none today")
	_insert_heavy_wave(section, 40.0)
	assert_gt(int(_peak(_heavy_intervals(section))["count"]), int(_LEGACY_PEAK_HEAVIES.get(&"planet_approach", 0)),
		"a heavy where no gunship flew must be rejected")


# ── Spill-over ───────────────────────────────────────────────────────────────────────────────────────────────────────

## Seconds from the start of `sections[index]` to the last effective trigger of the next ENEMIES_CLEARED section (`INF` if none follows):
## `test_level1_specialist_spawns.gd`'s predicate.
func _next_cleared_deadline(sections: Array[LevelSection], index: int) -> float:
	var t := 0.0
	for i in range(index, sections.size()):
		var s := sections[i]
		if i > index and s.end_condition == LevelSection.EndCondition.ENEMIES_CLEARED:
			var last := -INF
			for w: WaveResource in s.waves:
				last = maxf(last, w.trigger_time)
			return t + maxf(last, 0.0)
		t += s.duration
	return INF


## Every DURATION section's heavy whose end (spawn + engage + max(window + exit, rocket life): the rockets launch inside the budget) is not
## before its own section's end and the next ENEMIES_CLEARED section's last trigger.
func _spills(sections: Array[LevelSection], engage: float) -> Array[String]:
	var out: Array[String] = []
	var tail := engage + maxf(_attack_window() + float(_exit["seconds"]), _rocket_max_life())
	for i in sections.size():
		var section := sections[i]
		if section.end_condition != LevelSection.EndCondition.DURATION:
			continue
		var deadline := minf(section.duration, _next_cleared_deadline(sections, i))
		for line in _heavy_lines([section] as Array[LevelSection]):
			var end: float = float(line["effective"]) + float(line["delay"]) + tail
			gut.p("%s heavy at %.1f s gone by %.2f s (limit %.2f s)" % [section.section_name, line["trigger"], end, deadline])
			if end >= deadline:
				out.append("%s heavy at %.1f s gone %.2f s >= %.2f s" % [section.section_name, line["trigger"], end, deadline])
	return out


func test_no_duration_section_heavy_outlives_its_section_or_the_next_clearing() -> void:
	var sections := _build_sections()
	var checked := 0
	for s in sections:
		if s.end_condition == LevelSection.EndCondition.DURATION:
			checked += _heavy_lines([s] as Array[LevelSection]).size()
	assert_eq(checked, 1, "sanity: one heavy sits in a DURATION section (deep_space)")
	assert_eq(_spills(sections, SHIPPED.engage_seconds), [] as Array[String])


## Boundary: with a 20 s budget the deep_space heavy is still alive when deep_space ends.
func test_a_20_s_budget_makes_the_deep_space_heavy_spill_over() -> void:
	var spills := _spills(_build_sections(), 20.0)
	assert_eq(spills.size(), 1, "the deep_space heavy is flagged")
	if spills.size() == 1:
		assert_true(spills[0].begins_with("deep_space"))


# ── Which heavies meet lasers ────────────────────────────────────────────────────────────────────────────────────────

## Each heavy alive while a laser of its section may be lit: the wall (deep_space, lit from 0.0 s for its rays' warning + charge-up + lethal
## span + dissolve) and every row of `laser_column_schedule()` (`lit_seconds()`).
func _laser_meetings(sections: Array[LevelSection]) -> Array[String]:
	var schedule: Dictionary = DIRECTOR_SCRIPT.laser_column_schedule()
	var timing: Dictionary = REPLAY.ray_timing()
	var wall := (REPLAY.wall_placement()["scene"] as PackedScene).instantiate()
	var wall_ray := wall.get_child(0) as LaserRay
	var wall_end: float = wall_ray.warn_duration + float(timing["increase"]) + wall_ray.active_duration + float(timing["dissolve"])
	wall.free()
	var out: Array[String] = []
	for section in sections:
		var windows: Array = []
		for row: Dictionary in schedule.get(section.section_name, []):
			windows.append([float(row["time"]), float(row["time"]) + REPLAY.lit_seconds()])
		if section == sections[0]:
			windows.append([0.0, wall_end])
		for line in _heavy_lines([section] as Array[LevelSection]):
			var start: float = float(line["effective"]) + float(line["delay"])
			for w: Array in windows:
				if start < float(w[1]) and start + _heavy_life() > float(w[0]):
					out.append("%s %.1f s" % [section.section_name, start])
					break
	return out


func test_only_the_deep_space_heavy_meets_a_lit_laser() -> void:
	assert_almost_eq(REPLAY.lit_seconds(), 8.4, 0.001, "sanity: 3.0 warning + 0.56 charge-up + 4.0 lethal + 0.84 dissolve")
	assert_eq(_laser_meetings(_build_sections()), ["deep_space 3.5 s"] as Array[String],
		"every Cloud Descent column set is dark before its first heavy, so only the deep_space heavy is replayed lit")


## Boundary: a Cloud Descent heavy moved to 34.0 s (its last column set) is flagged.
func test_a_heavy_at_cloud_descents_34_s_set_meets_a_laser() -> void:
	var sections := _build_sections()
	var cloud := _section(sections, &"cloud_descent")
	_insert_heavy_wave(cloud, 34.0)
	assert_true(_laser_meetings(sections).has("cloud_descent 34.0 s"))


# ── The warm-start rule (data) ───────────────────────────────────────────────────────────────────────────────────────

func test_the_warm_start_rule() -> void:
	var t: Dictionary = REPLAY.ray_timing()
	assert_almost_eq(float(t["init"]), 0.2, 0.0001, "sanity: laser_init 1 x 1.0 / 5")
	assert_almost_eq(float(t["increase"]), 0.56, 0.0001, "sanity: laser_increase 7 x 0.4 / 5")
	assert_almost_eq(float(t["dissolve"]), 0.84, 0.0001, "sanity: laser_dissolve 7 x 0.6 / 5")
	# Still warning: exact, only the warning is shorter.
	assert_eq(REPLAY.warm_start(2.5, 3.0, 4.0), {"warn": 0.5, "active": 4.0})
	assert_eq(REPLAY.warm_start(0.0, 3.0, 4.0), {"warn": 3.0, "active": 4.0}, "at the row's own start nothing changes")
	# Equality takes the middle branch: rest = 3.0 + 0.56 + 4.0 - 3.0 - 0.76 = 3.8.
	var at_warn: Dictionary = REPLAY.warm_start(3.0, 3.0, 4.0)
	assert_almost_eq(float(at_warn["warn"]), 0.0, 0.0001)
	assert_almost_eq(float(at_warn["active"]), 3.8, 0.0001)
	# The carried-over row of the real-ray test: 7.56 - 5.0 - 0.76 = 1.8.
	assert_almost_eq(float(REPLAY.warm_start(5.0, 3.0, 4.0)["active"]), 1.8, 0.0001)
	# rest < MIN_ACTIVE: not lit (7.56 - 6.6 - 0.76 = 0.2).
	assert_eq(REPLAY.warm_start(6.6, 3.0, 4.0), {})
	# Inside the dissolve (the 6.0 s row seen from 13.8 s): not lit.
	assert_eq(REPLAY.warm_start(13.8 - 6.0, 3.0, 4.0), {})
	# The wall at 7.0 / 11.0 s: not lit.
	assert_eq(REPLAY.warm_start(7.0, 3.0, 4.0), {})
	assert_eq(REPLAY.warm_start(11.0, 3.0, 4.0), {})
	var bad: Array[String] = []
	var elapsed := 0.0
	while elapsed <= REPLAY.lit_seconds():
		var r: Dictionary = REPLAY.warm_start(elapsed, 3.0, 4.0)
		if not r.is_empty() and (float(r["active"]) < REPLAY.MIN_ACTIVE or float(r["warn"]) < 0.0):
			bad.append("%.2f -> %s" % [elapsed, r])
		elapsed += 0.01
	assert_eq(bad, [] as Array[String], "no relit ray ever has active < MIN_ACTIVE or a negative warning")


# ── Replays ──────────────────────────────────────────────────────────────────────────────────────────────────────────

## A per-heavy record, filled by `_hook_heavy()`.
func _new_log() -> Dictionary:
	return {"spawn": -1.0, "first_fire": -1.0, "fire_left": -1.0, "fire_phase": -1, "disengage": -1.0, "broadside": -1.0, "in_view": false,
		"gone": -1.0, "killed": false, "rounds": [] as Array[float], "rockets": [] as Array[float], "last_pos": Vector2.ZERO, "last_phase": -1}


## Hooks one heavy as it enters the tree (before its `_ready()`): its brain's phases, its death and departure, and (once `build_mounts()` has
## run in `_ready()`) every mount's FIRE and rounds. `clock[0]` is section time, kept by the caller's `observe` (which runs only once a
## heavy has spawned, so the spawn moment is passed in).
func _hook_heavy(ship: Node, recs: Array, clock: Array, spawn_t: float) -> void:
	var rec := _new_log()
	rec["spawn"] = spawn_t
	recs.append(rec)
	var brain := ship.get_node(^"Brain") as HeavyGunshipBrain
	brain.phase_changed.connect(func(p: int) -> void:
		if p == Phase.DISENGAGE and float(rec["disengage"]) < 0.0:
			rec["disengage"] = clock[0]
		elif p == Phase.BROADSIDE and float(rec["broadside"]) < 0.0:
			rec["broadside"] = clock[0])
	(ship as BaseEnemy).died.connect(func() -> void: rec["killed"] = true)
	# Its own exit or death queues it; a ship freed with the replay world at the stop is not "gone".
	ship.tree_exiting.connect(func() -> void:
		if ship.is_queued_for_deletion():
			rec["gone"] = clock[0])
	ship.ready.connect(func() -> void:
		var hull := (ship as HeavyGunship).modular_hull()
		for id in [HeavyGunshipBrain.BATTERY_PORT, HeavyGunshipBrain.BATTERY_STARBOARD]:
			for mount in hull.mounts_of(id):
				mount.phase_changed.connect(func(p: int) -> void:
					if p == TurretMount.Phase.FIRE and float(rec["first_fire"]) < 0.0:
						rec["first_fire"] = clock[0]
						rec["fire_left"] = brain.budget.remaining()
						rec["fire_phase"] = brain.phase)
		for part in hull.modules():
			var rocket_part := part.module_id == HeavyGunshipBrain.MISSILES
			for mount in part.mounts():
				mount.round_fired.connect(func(_projectile: Node2D) -> void:
					(rec["rockets"] if rocket_part else rec["rounds"]).append(clock[0])), CONNECT_ONE_SHOT)


## Notes where a live heavy is (and whether it has been inside the view) each tick.
func _watch(ship: Node, rec: Dictionary) -> void:
	if ship == null or not is_instance_valid(ship) or not ship.is_inside_tree():
		return
	var pos := (ship as Node2D).global_position
	rec["last_pos"] = pos
	rec["last_phase"] = (ship.get_node(^"Brain") as HeavyGunshipBrain).phase
	if not rec["in_view"] and EnemyWorld.view_rect(ship.get_tree()).has_point(pos):
		rec["in_view"] = true


## The 6.0 s row's lethal end (section s): the deep_space run lasts past it + `EDGE_GUARD` + a tick, so both its edges are checked.
func _six_row_end() -> float:
	return 6.0 + REPLAY.column_lethal_offset() + DIRECTOR_SCRIPT.COLUMN_ACTIVE_SECONDS


## Deep_space from 0.0 s, lit: `{ "out", "rec", "stop" }` (`stop` in section time). Run once.
func _deep_space_run() -> Dictionary:
	if not _deep.is_empty():
		return _deep
	var section: LevelSection = REPLAY.section(&"deep_space")
	var waves: Array[WaveResource] = REPLAY.slice_waves(section, 0.0, section.duration)
	var replay = REPLAY.new()
	replay.light_lasers = true
	replay.lit_section = &"deep_space"
	replay.lit_from = 0.0
	var recs: Array = []
	var clock := [0.0]
	var stop_after := _six_row_end() + EDGE_GUARD + TICK
	var tweak := func(ship: Node) -> void:
		_hook_heavy(ship, recs, clock, replay.slice_time())
	var observe := func(ship: BaseEnemy, t: float) -> bool:
		clock[0] = t
		if not recs.is_empty():
			_watch(ship, recs[0])
		return ship == null and t >= stop_after
	_scale_clock(LIT_MAX_STEPS)
	var out: Dictionary = await replay.run(self, waves, section.duration, HEAVY, observe, tweak)
	_restore_clock()
	_deep = {"out": out, "rec": recs[0] if recs.size() == 1 else {}, "heavies": recs.size(), "stop": float(out["t"])}
	return _deep


## Deep_space from 2.5 s, lit, plus one added heavy at `.at(256, -500)` in the 3.5 s wave's slice copy; both heavies with private
## `hazard_avoidance` 0, held at `HELD_X` every tick. Stops when each has a covered death (cap: the 6.0 s row's lethal end + 0.5). Run once.
func _boundary_run() -> Dictionary:
	if not _boundary.is_empty():
		return _boundary
	var from := 2.5
	var section: LevelSection = REPLAY.section(&"deep_space")
	var waves: Array[WaveResource] = REPLAY.slice_waves(section, from, section.duration)
	var b := WaveBuilder.new()
	var extra: SpawnEntryResource = b.wave(0.0, [b.heavy_gunship().at(256, -500)]).entries[0]
	var host_wave: WaveResource = null
	for w in waves:
		for e in w.entries:
			if (e as SpawnEntryResource).ship_scene != null and (e as SpawnEntryResource).ship_scene.resource_path == HEAVY:
				host_wave = w
	assert_not_null(host_wave, "sanity: the slice holds the deep_space heavy's wave")
	if host_wave == null:
		return {}
	var entries: Array[SpawnEntryResource] = []
	entries.assign(host_wave.entries)
	entries.append(extra)
	host_wave.entries = entries
	var replay = REPLAY.new()
	replay.light_lasers = true
	replay.lit_section = &"deep_space"
	replay.lit_from = from
	var held: Array[Node] = []
	var tweak := func(ship: Node) -> void:
		(ship as BaseEnemy).config.hazard_avoidance = 0.0
		held.append(ship)
	var observe := func(_ship: BaseEnemy, _t: float) -> bool:
		for i in held.size():
			if is_instance_valid(held[i]) and held[i].is_inside_tree():
				(held[i] as Node2D).global_position.x = HELD_X[mini(i, HELD_X.size() - 1)]
		var dead := {}
		for d: Dictionary in replay.deaths:
			if d["covered"]:
				dead[d["ship"]] = true
		return dead.size() >= 2
	var length := _six_row_end() + 0.5 - from
	_scale_clock(LIT_MAX_STEPS)
	var out: Dictionary = await replay.run(self, waves, length, HEAVY, observe, tweak)
	_restore_clock()
	_boundary = {"out": out, "from": from, "stop": float(out["t"]) + from, "held": held.size()}
	return _boundary


## Deep_space from 11.0 s, rays only: the 6.0 s row is carried over the slice start (warn 0, active 1.8). Run once.
func _carried_run() -> Dictionary:
	if not _carried.is_empty():
		return _carried
	var from := 11.0
	var replay = REPLAY.new()
	replay.light_lasers = true
	replay.lit_section = &"deep_space"
	replay.lit_from = from
	var length := _six_row_end() - from + EDGE_GUARD + TICK
	_scale_clock(LIT_MAX_STEPS)
	var out: Dictionary = await replay.run(self, [] as Array[WaveResource], length, HEAVY, func(_s: BaseEnemy, _t: float) -> bool: return false)
	_restore_clock()
	_carried = {"out": out, "from": from, "stop": float(out["t"]) + from}
	return _carried


## Cloud Descent 49.0 s .. 62.8 + engage + 2.0 s, lasers off: all three heavies. Stops once all three have spawned and each has entered
## DISENGAGE or left. Run once.
func _cloud_run() -> Dictionary:
	if not _cloud.is_empty():
		return _cloud
	var rows: Array = REPLAY.placed(HEAVY).filter(func(r: Dictionary) -> bool: return r["section"] == &"cloud_descent")
	var first: float = float(rows[0]["rel"])
	var last: float = float(rows[rows.size() - 1]["rel"])
	var from := first - REPLAY.PRE_ROLL
	var to := last + SHIPPED.engage_seconds + REPLAY.POST_ROLL
	var waves: Array[WaveResource] = REPLAY.slice_waves(REPLAY.section(&"cloud_descent"), from, to)
	var recs: Array = []
	var clock := [from]
	var replay = REPLAY.new()
	var tweak := func(ship: Node) -> void:
		_hook_heavy(ship, recs, clock, replay.slice_time() + from)
	var observe := func(_ship: BaseEnemy, t: float) -> bool:
		clock[0] = t + from
		if recs.size() < rows.size():
			return false
		for rec: Dictionary in recs:
			if float(rec["disengage"]) < 0.0 and float(rec["gone"]) < 0.0:
				return false
		return true
	_scale_clock()
	var out: Dictionary = await replay.run(self, waves, to - from, HEAVY, observe, tweak)
	_restore_clock()
	_cloud = {"out": out, "recs": recs, "from": from}
	return _cloud


## One heavy's attack and departure, for the prints.
func _log_text(rec: Dictionary) -> String:
	return "spawn %.2f, BROADSIDE %.2f, first battery FIRE %.2f (%.2f s of budget left, phase %d), DISENGAGE %.2f, gone %.2f, killed %s" % [
		rec["spawn"], rec["broadside"], rec["first_fire"], rec["fire_left"], rec["fire_phase"], rec["disengage"], rec["gone"], rec["killed"]]


## The lit-run timing rows for one run: every ray edge reached before the stop, against the level's own times (header; task plan §3).
## Returns the checked edges as "<source> <row_time> onset|end" strings.
func _check_ray_edges(run: Dictionary, label: String) -> Array[String]:
	var out: Dictionary = run["out"]
	var timing: Dictionary = REPLAY.ray_timing()
	var checked: Array[String] = []
	var stop: float = run["stop"]
	var from: float = float(run.get("from", 0.0))
	for r: Dictionary in out["lit"]:
		var lit_at := maxf(float(r["row_time"]), from)
		var warn := float(r["lit_warn"])
		var expected := lit_at + (warn if warn > 0.0 else float(timing["init"])) + float(timing["increase"])
		var d := float(r["max_idle"])
		var key := "%s %.1f x %.0f" % [r["source"], r["row_time"], r["x"]]
		if expected + EDGE_GUARD >= stop:
			continue
		assert_lt(2.0 * d + 2.0 * TICK, EDGE_GUARD, "%s %s: the late tolerance (d %.3f) stays under the N4 guard" % [label, key, d])
		checked.append("%s %.1f onset" % [r["source"], r["row_time"]])
		assert_between(float(r["from"]), expected - 2.0 * d - TICK, expected + 2.0 * d + 2.0 * TICK,
			"%s %s: lethal from %.3f s, the level makes it lethal at %.3f s (d %.3f)" % [label, key, r["from"], expected, d])
		var active := float(r["lit_active"])
		if expected + active + EDGE_GUARD >= stop:
			continue
		checked.append("%s %.1f end" % [r["source"], r["row_time"]])
		var span := float(r["to"]) - float(r["from"])
		assert_between(span, active - d - 2.0 * TICK, active + d + TICK,
			"%s %s: lethal for %.3f s of its %.3f s (d %.3f)" % [label, key, span, active, d])
	return checked


func _assert_idle_capped(out: Dictionary, label: String) -> void:
	var cap := float(LIT_MAX_STEPS) / 60.0 + 2.0 * TICK
	gut.p("%s: largest idle frame %.3f s (cap %.3f s)" % [label, out["max_idle"], cap])
	assert_lte(float(out["max_idle"]), cap, "%s: the largest idle frame %.3f s stays within the step cap (%.3f s)" % [label, out["max_idle"], cap])


func test_no_heavy_part_or_hull_dies_under_a_lit_laser() -> void:
	var run := await _deep_space_run()
	var out: Dictionary = run["out"]
	var rec: Dictionary = run["rec"]
	assert_eq(int(run["heavies"]), 1, "the deep_space slice spawns its one heavy")
	if rec.is_empty():
		return
	var clearance: Dictionary = (out["clearance"] as Dictionary).get(0, {"lethal": INF, "warning": INF})
	gut.p("deep_space lit: %s; stop %.2f s; clearance lethal %.1f px, warning %.1f px; measured exit %.2f s, lit exit %.2f s after DISENGAGE" % [
		_log_text(rec), run["stop"], clearance["lethal"], clearance["warning"], _exit["seconds"],
		float(rec["gone"]) - float(rec["disengage"]) if float(rec["disengage"]) >= 0.0 else -1.0])
	if float(rec["gone"]) < 0.0:
		gut.p("the cap ended the run with the heavy alive: phase %d at %s, %.2f s" % [rec["last_phase"], rec["last_pos"], run["stop"]])
	assert_eq((out["deaths"] as Array).filter(func(d: Dictionary) -> bool: return d["covered"]), [],
		"no heavy part or hull died under a lit ray")
	assert_false(rec["killed"], "the heavy was not killed at all (a heavy killed early would have met fewer lasers)")
	assert_gt(float(rec["disengage"]), 0.0, "it entered DISENGAGE")
	assert_gte(float(rec["gone"]), float(rec["disengage"]), "and left after it")
	assert_true(rec["in_view"], "it came down into the view")
	var fought := (float(rec["broadside"]) >= 0.0 and float(rec["broadside"]) < float(rec["disengage"])) \
		or (float(rec["first_fire"]) >= 0.0 and float(rec["first_fire"]) < float(rec["disengage"]))
	assert_true(fought, "it reached BROADSIDE or fired a battery before DISENGAGE (it survived by fighting, not by staying away)")
	assert_gte(float(clearance["lethal"]), LaserRay._HAZARD_PAD, "its hull kept at least the laser's hazard pad from every lit strip at its height")


## Boundary (kill detection): a heavy held in the wall's 644 ray and one held on the 6.0 s set's 1152 column are both reported dead under a
## lit ray, each with its source.
func test_a_heavy_held_in_a_lit_ray_is_reported_dead() -> void:
	var run := await _boundary_run()
	if run.is_empty():
		return
	var deaths: Array = run["out"]["deaths"]
	gut.p("kill boundary from %.1f s: %d heavies, stop %.2f s, deaths %s" % [run["from"], run["held"], run["stop"], deaths])
	assert_eq(int(run["held"]), 2, "the slice spawned both held heavies")
	var wall := deaths.filter(func(d: Dictionary) -> bool: return d["ship"] == 0 and d["covered"] and d["source"] == "wall")
	var column := deaths.filter(func(d: Dictionary) -> bool:
		return d["ship"] == 1 and d["covered"] and d["source"] == "column" and float(d["t"]) >= 6.0)
	assert_gt(wall.size(), 0, "the heavy held at x 640 dies in the wall's lit ray")
	assert_gt(column.size(), 0, "the heavy held at x 1152 dies in a lit column of the 6.0 s set (the only one at x 1152 before 22.0 s)")


func test_the_replayed_lasers_are_lethal_when_the_level_makes_them() -> void:
	var deep := await _deep_space_run()
	_assert_idle_capped(deep["out"], "deep_space from 0")
	var checked := _check_ray_edges(deep, "deep_space from 0")
	for edge in ["wall 0.0 onset", "wall 0.0 end", "column 6.0 onset", "column 6.0 end"]:
		assert_true(checked.has(edge), "deep_space from 0 checked the %s edge" % edge)
	var boundary := await _boundary_run()
	if boundary.is_empty():
		return
	_assert_idle_capped(boundary["out"], "kill boundary")
	var walls: Array = (boundary["out"]["lit"] as Array).filter(func(r: Dictionary) -> bool: return r["source"] == "wall")
	assert_eq(walls.size(), 12, "the wall is relit from 2.5 s")
	for r: Dictionary in walls:
		assert_almost_eq(float(r["lit_warn"]), 0.5, 0.0001, "the wall's warning is shortened to 0.5 s (the exact warm start)")
	var b_checked := _check_ray_edges(boundary, "kill boundary")
	assert_true(b_checked.has("wall 0.0 onset"), "the boundary run checked the shifted wall's onset (3.56 s, never 6.06 s)")
	gut.p("checked edges: from 0 %d, boundary %d" % [checked.size(), b_checked.size()])


## The approximate warm-start branch on real rays: from 11.0 s the 6.0 s row is relit with warn 0 / active 1.8 and is lethal from about 11.76 s
## to its real lethal end, 13.56 s; the wall is not relit; nothing is lethal at the stop.
func test_a_column_carried_over_a_slice_start_is_relit_until_its_lethal_end() -> void:
	var run := await _carried_run()
	var out: Dictionary = run["out"]
	_assert_idle_capped(out, "carried over")
	var lit: Array = out["lit"]
	var six: Array = lit.filter(func(r: Dictionary) -> bool: return r["source"] == "column" and is_equal_approx(float(r["row_time"]), 6.0))
	assert_eq(six.size(), 3, "the 6.0 s row's three columns are relit")
	assert_eq(lit.filter(func(r: Dictionary) -> bool: return r["source"] == "wall").size(), 0, "the wall is not relit")
	for r: Dictionary in six:
		assert_almost_eq(float(r["lit_warn"]), 0.0, 0.0001)
		assert_almost_eq(float(r["lit_active"]), 1.8, 0.0001, "7.56 - 5.0 - 0.76")
		gut.p("carried 6.0 s column x %.0f: lethal %.3f-%.3f s (d %.3f)" % [r["x"], r["from"], r["to"], r["max_idle"]])
	var checked := _check_ray_edges(run, "carried over")
	assert_true(checked.has("column 6.0 onset") and checked.has("column 6.0 end"), "both edges of the relit row are checked")
	for r: Dictionary in six:
		assert_almost_eq(float(r["to"]), _six_row_end(), 2.0 * float(r["max_idle"]) + 2.0 * TICK, "it ends with the real row")
	assert_eq(int(out["lethal_at_stop"]), 0, "no ray is lethal at the stop")


func test_every_placed_heavy_fires_a_battery_inside_its_budget() -> void:
	var deep := await _deep_space_run()
	var cloud := await _cloud_run()
	var recs: Array = []
	if not (deep["rec"] as Dictionary).is_empty():
		recs.append(["deep_space", deep["rec"]])
	for rec in cloud["recs"]:
		recs.append(["cloud_descent", rec])
	assert_eq(recs.size(), EXPECTED_PH10_GUNSHIPS.size(), "every placed heavy was replayed")
	for pair in recs:
		var rec: Dictionary = pair[1]
		gut.p("%s heavy: %s" % [pair[0], _log_text(rec)])
		assert_gte(float(rec["first_fire"]), 0.0, "%s heavy spawned %.2f s fires a battery" % [pair[0], rec["spawn"]])
		assert_gt(float(rec["fire_left"]), 0.0, "%s heavy spawned %.2f s fires with budget left" % [pair[0], rec["spawn"]])
		assert_ne(int(rec["fire_phase"]), Phase.DISENGAGE, "%s heavy spawned %.2f s fires before DISENGAGE" % [pair[0], rec["spawn"]])


## Measured, ungated (§2.12): the heavies' gun rounds and rockets per section; the peak in any 2 s window. Recorded in DECISIONS.
func test_heavy_fire_density_is_measured() -> void:
	var deep := await _deep_space_run()
	var cloud := await _cloud_run()
	var sections := {"deep_space": [deep["rec"]] if not (deep["rec"] as Dictionary).is_empty() else [], "cloud_descent": cloud["recs"]}
	var total := 0
	for key in sections:
		var all_rounds: Array[float] = []
		var rockets := 0
		for rec: Dictionary in sections[key]:
			all_rounds.append_array(rec["rounds"])
			rockets += (rec["rockets"] as Array).size()
			var own: Array[float] = []
			own.assign(rec["rounds"])
			gut.p("%s heavy spawned %.2f s: %d gun rounds (peak %.0f in %.0f s), %d rockets" % [key, rec["spawn"], own.size(),
				DroneConcurrency.peak_window_rate(own, FIRE_WINDOW) * FIRE_WINDOW, FIRE_WINDOW, (rec["rockets"] as Array).size()])
		total += all_rounds.size()
		gut.p("%s heavies: %d gun rounds, %d rockets, peak %.0f gun rounds in any %.0f s window" % [key, all_rounds.size(), rockets,
			DroneConcurrency.peak_window_rate(all_rounds, FIRE_WINDOW) * FIRE_WINDOW, FIRE_WINDOW])
	assert_gt(total, 0, "rounds were counted")


## The helper's default path lights nothing; the lit deep_space run saw the wall's 12 rays and the 6.0 s row's three.
func test_a_replay_with_lasers_off_lights_nothing() -> void:
	var rays := [0]
	var counter := func(node: Node) -> void:
		if node is LaserRay:
			rays[0] += 1
	get_tree().node_added.connect(counter)
	_scale_clock()
	await REPLAY.new().run(self, [] as Array[WaveResource], 0.5, HEAVY, func(_s: BaseEnemy, _t: float) -> bool: return false)
	_restore_clock()
	get_tree().node_added.disconnect(counter)
	assert_eq(rays[0], 0, "light_lasers off adds no LaserRay")
	var lit: Array = (await _deep_space_run())["out"]["lit"]
	assert_eq(lit.filter(func(r: Dictionary) -> bool: return r["source"] == "wall").size(), 12, "the wall's twelve rays")
	assert_eq(lit.filter(func(r: Dictionary) -> bool: return r["source"] == "column" and is_equal_approx(float(r["row_time"]), 6.0)).size(), 3,
		"the 6.0 s row's three columns")
