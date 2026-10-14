## Characterization: pins every Sniper (`WaveBuilder.SNIPER`, also reached through the `b.sniper_enemy()` alias),
## Ram (`WaveBuilder.RAM`) and Bomber (`WaveBuilder.BOMBER`) spawn in Level 1 — the state of the world BEFORE Enemy rework
## phase 4 touches any of it (docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md §2.9.1, task t1-pin).
##
## NOT an invariant — like `test_level1_fighter_spawns.gd`, every number here is a deliberate design choice this
## file freezes. A failure means "the specialist spawns changed", which is expected starting at the renames (t7, t8)
## and the migration (t21, t22). Those tasks update this file: they keep trigger, offset and delay (the pin) and
## retire the per-section "live equals constant" check below for the section they take off rails, while the frozen
## `_LEGACY_PEAK_SPECIALISTS` constants stay for their count gates to divide by.
##
## What is pinned: section, trigger time, base offset and spawn delay of all 50 rows (26 sniper, 22 ram, 2 bomber).
## Fire timing (`shoot_at_player()` / `aim_mode`) is deliberately NOT pinned (plan C14): the new AI decides
## when to fire. `.move()` and `.free_after()` are not pinned either; they are the rails t21/t22 delete, and
## `_rail_lifetime()` reads them only to freeze the legacy density.
##
## ── Why `_build_sections()`, not the level scene ─────────────────────────────────────────────
##
## `Level1Director._build_sections()` is callable on a bare, never-entered-tree instance, so this reads the wave
## data directly, in the same units and code path `WaveManager` consumes (same reasoning as
## `test_level1_fighter_spawns.gd`).
##
## ── The legacy peak is a frozen constant, not re-derived every run ───────────────────────────────
##
## `_LEGACY_PEAK_SPECIALISTS` is the most sniper / ram / bomber ships alive at once in each section, computed from
## the live rails: each entry's on-screen time is its OWN `free_after`, or its OWN `MovementResource` sampled from
## its OWN spawn offset until it leaves `ArenaCamera.enemy_cull_rect()` after having been inside it, capped at 20 s
## (exactly what `EnemyPathMover` does at runtime; `test_level1_fighter_spawns.gd::_rail_lifetime()` is the same
## arithmetic). The constants were filled in from the first computed run, not typed from the plan, and
## `test_legacy_peak_specialists_match_frozen_constants` asserts the live computation equals them for every
## section still in `_RAIL_SECTIONS`. Once t21/t22 delete a section's rails there is nothing left to recompute
## them FROM, so that section leaves `_RAIL_SECTIONS` and the constant is only divided by.
extends GutTest

const _DIRECTOR_SCRIPT := "res://assault/scenes/levels/edelia/1/level_1_director.gd"

const DroneConcurrency := preload("res://tests/helpers/level1_drone_concurrency.gd")

const _SNIPER := WaveBuilder.SNIPER
const _RAM := WaveBuilder.RAM
const _BOMBER := WaveBuilder.BOMBER

## The rail sampling cap and step. 20 s comfortably exceeds every real specialist rail's lifetime; 0.02 s keeps the
## cull-rect crossing reasonably precise without the sweep costing real time.
const _CULL_CAP: float = 20.0
const _CULL_STEP: float = 0.02

## Every sniper / ram / bomber entry in `_build_sections()`, in encounter order, as pinned from a computed run of
## `_actual_specialist_spawns()` below. Regenerate by walking `_build_sections()` the same way that function does —
## never hand-edit a single row without re-deriving the whole table. No specialist line uses a formation today.
const EXPECTED: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 0.50, "offset": Vector2(-120.0, -500.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 0.50, "offset": Vector2(120.0, -500.0), "delay": 0.50},
	{"section": &"deep_space", "kind": "RAM", "trigger": 7.50, "offset": Vector2(0.0, -400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 11.00, "offset": Vector2(-185.0, -400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 11.00, "offset": Vector2(185.0, -400.0), "delay": 0.30},
	{"section": &"deep_space", "kind": "RAM", "trigger": 15.50, "offset": Vector2(0.0, 400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 19.50, "offset": Vector2(220.0, 400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "RAM", "trigger": 26.00, "offset": Vector2(-255.0, -400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "RAM", "trigger": 26.00, "offset": Vector2(255.0, -400.0), "delay": 0.50},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 29.00, "offset": Vector2(-260.0, -400.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "SNIPER", "trigger": 29.00, "offset": Vector2(260.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 13.00, "offset": Vector2(0.0, -400.0), "delay": 0.60},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 16.00, "offset": Vector2(220.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 28.00, "offset": Vector2(0.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 28.00, "offset": Vector2(-220.0, -400.0), "delay": 0.40},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 28.00, "offset": Vector2(220.0, -400.0), "delay": 0.40},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 32.00, "offset": Vector2(-220.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 44.00, "offset": Vector2(-145.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 44.00, "offset": Vector2(145.0, -400.0), "delay": 0.20},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 55.00, "offset": Vector2(-200.0, 400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 55.00, "offset": Vector2(200.0, 400.0), "delay": 0.30},
	{"section": &"planet_approach", "kind": "BOMBER", "trigger": 58.00, "offset": Vector2(0.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 65.00, "offset": Vector2(-240.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 65.00, "offset": Vector2(240.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 65.00, "offset": Vector2(0.0, -400.0), "delay": 0.70},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 75.00, "offset": Vector2(-260.0, -400.0), "delay": 0.50},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 75.00, "offset": Vector2(260.0, -400.0), "delay": 0.50},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 88.00, "offset": Vector2(-270.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 88.00, "offset": Vector2(270.0, -400.0), "delay": 0.40},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 88.00, "offset": Vector2(0.0, -400.0), "delay": 0.80},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 92.00, "offset": Vector2(-500.0, 50.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SNIPER", "trigger": 92.00, "offset": Vector2(500.0, 50.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "BOMBER", "trigger": 98.00, "offset": Vector2(0.0, -400.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 102.00, "offset": Vector2(-260.0, -400.0), "delay": 0.30},
	{"section": &"planet_approach", "kind": "RAM", "trigger": 102.00, "offset": Vector2(260.0, -400.0), "delay": 0.30},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 11.00, "offset": Vector2(-260.0, 400.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 28.00, "offset": Vector2(-180.0, 400.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 28.00, "offset": Vector2(180.0, 400.0), "delay": 0.40},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 32.00, "offset": Vector2(-500.0, 50.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 32.00, "offset": Vector2(500.0, 50.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 32.00, "offset": Vector2(-120.0, -400.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 32.00, "offset": Vector2(120.0, -400.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 38.00, "offset": Vector2(0.0, -400.0), "delay": 0.60},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 50.00, "offset": Vector2(-220.0, -400.0), "delay": 1.50},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 50.00, "offset": Vector2(220.0, -400.0), "delay": 1.50},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 53.00, "offset": Vector2(-500.0, 20.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 53.00, "offset": Vector2(500.0, 20.0), "delay": 0.00},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 62.00, "offset": Vector2(-225.0, -400.0), "delay": 1.20},
	{"section": &"cloud_descent", "kind": "SNIPER", "trigger": 62.00, "offset": Vector2(225.0, -400.0), "delay": 1.20},
	{"section": &"cloud_descent", "kind": "RAM", "trigger": 72.00, "offset": Vector2(0.0, 400.0), "delay": 1.20},]

## Legacy per-section peaks of sniper + ram + bomber alive at once, from a computed run (see the file header).
const _LEGACY_PEAK_SPECIALISTS: Dictionary = {
	&"deep_space": 5,
	&"planet_approach": 3,
	&"cloud_descent": 4,
}

const _KIND_NAMES := {_SNIPER: "SNIPER", _RAM: "RAM", _BOMBER: "BOMBER"}


## Callable on a bare, never-entered-tree instance — see the file header.
func _build_sections() -> Array[LevelSection]:
	var script := load(_DIRECTOR_SCRIPT)
	var inst: Node = script.new()
	var sections: Array[LevelSection] = inst._build_sections()
	inst.free()
	return sections


## One row per sniper / ram / bomber entry, in the same shape as `EXPECTED`.
func _actual_specialist_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _KIND_NAMES.has(path):
					continue
				assert_null(entry.formation, "no specialist line uses a formation; the pin has no formation column")
				out.append({
					"section": section.section_name,
					"kind": _KIND_NAMES[path],
					"trigger": wave.trigger_time,
					"offset": entry.base_offset,
					"delay": entry.spawn_delay,
				})
	return out


# ── The pin ───────────────────────────────────────────────────────────────────

func test_pinned_specialist_spawns_match_todays_data() -> void:
	var actual := _actual_specialist_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED.size(),
		"the number of SNIPER/RAM/BOMBER entries in _build_sections() has changed")
	assert_eq(actual, EXPECTED, "a specialist spawn's section, trigger, offset or delay changed")


## 50 pinned rows (26 sniper incl. the `sniper_enemy()` alias, 22 ram, 2 bomber), split by kind and section, so a
## stale hand-edit of the roster text is caught independent of whether `_build_sections()` changed.
func test_the_pin_itself_is_internally_consistent() -> void:
	var by_kind: Dictionary = {}
	var by_section: Dictionary = {}
	for row: Dictionary in EXPECTED:
		by_kind[row["kind"]] = int(by_kind.get(row["kind"], 0)) + 1
		by_section[row["section"]] = int(by_section.get(row["section"], 0)) + 1
	assert_eq(EXPECTED.size(), 50)
	assert_eq(int(by_kind.get("SNIPER", 0)), 26, "sniper row count changed")
	assert_eq(int(by_kind.get("RAM", 0)), 22, "ram row count changed")
	assert_eq(int(by_kind.get("BOMBER", 0)), 2, "bomber row count changed")
	assert_eq(int(by_section.get(&"deep_space", 0)), 11, "deep_space row count changed")
	assert_eq(int(by_section.get(&"planet_approach", 0)), 24, "planet_approach row count changed")
	assert_eq(int(by_section.get(&"cloud_descent", 0)), 15, "cloud_descent row count changed")
	assert_eq(by_section.size(), 3, "specialists spawn only in deep_space, planet_approach and cloud_descent")


## The alias really is counted: `b.sniper_enemy()` and `b.sniper()` build the same scene, so the 26 sniper rows
## include the two `sniper_enemy()` lines of deep_space's 0.5 s wave.
func test_the_sniper_enemy_alias_lines_are_among_the_pinned_snipers() -> void:
	var first_wave := 0
	for row: Dictionary in EXPECTED:
		if row["section"] == &"deep_space" and row["kind"] == "SNIPER" and is_equal_approx(row["trigger"], 0.5):
			first_wave += 1
	assert_eq(first_wave, 2, "deep_space's 0.5 s sniper pair is built with b.sniper_enemy()")


## Boundary (acceptance criterion): a specialist line's delay changed in memory must not match the pin. Done on a
## fresh `_build_sections()` result, so nothing shared is mutated.
func test_a_specialist_lines_delay_changed_fails_the_pin() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _RAM:
					entry.spawn_delay += 1.0
					mutated = true
	assert_true(mutated, "sanity: level 1 has a ram line to mutate")
	assert_ne(_actual_specialist_spawns(sections), EXPECTED, "a ram line with a changed delay must not match the pin")


## Boundary (acceptance criterion): a missing row must not match the pin, whichever family it is from.
func test_a_missing_specialist_row_fails_the_pin() -> void:
	for path: String in [_SNIPER, _RAM, _BOMBER]:
		var sections := _build_sections()
		var removed := false
		for section: LevelSection in sections:
			for wave: WaveResource in section.waves:
				if removed:
					break
				for entry: SpawnEntryResource in wave.entries:
					if entry.ship_scene and entry.ship_scene.resource_path == path:
						wave.entries.erase(entry)
						removed = true
						break
		assert_true(removed, "sanity: level 1 has a %s line to remove" % _KIND_NAMES[path])
		var actual := _actual_specialist_spawns(sections)
		assert_eq(actual.size(), EXPECTED.size() - 1, "exactly one row went missing")
		assert_ne(actual, EXPECTED, "a level with a %s row missing must not match the pin" % _KIND_NAMES[path])


# ── Legacy peak concurrency (§2.9.1) ──────────────────────────────────────────────────────────────

## `FREE_ON_DURATION` -> `exit_time`. Otherwise sample `movement` from `offset` until it next leaves
## `enemy_cull_rect()` after having been inside it, capped at `_CULL_CAP` — the same has-been-on-screen gate
## `EnemyPathMover._check_off_screen()` applies. `cam` is bound in by the caller (`spawn_intervals()`'s
## `lifetime_fn` contract).
func _rail_lifetime(_path: String, offset: Vector2, movement: MovementResource, exit_mode: int,
		exit_time: float, cam: ArenaCamera) -> float:
	if exit_mode == EnemyPathMover.ExitMode.FREE_ON_DURATION:
		return exit_time
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
		else:
			if not inside:
				return t
		t += _CULL_STEP
	return _CULL_CAP


func _no_rate(_path: String, _offset: Vector2, _movement: MovementResource, _exit_mode: int,
		_exit_time: float, _aim_mode: String) -> float:
	return 0.0


func _live_peak(section: LevelSection, cam: ArenaCamera) -> int:
	var ship_paths: Array[String] = [_SNIPER, _RAM, _BOMBER]
	var intervals := DroneConcurrency.spawn_intervals(section, ship_paths,
		Callable(self, "_rail_lifetime").bind(cam), Callable(self, "_no_rate"))
	return DroneConcurrency.peak_interval_count(intervals)


## The sections whose specialists are still on rails, so their frozen constants can still be recomputed from live
## data. t21 removed deep_space and planet_approach (see `MIGRATED_SECTIONS` below: their count gate divides by the
## frozen constant instead) and t22 removes cloud_descent (once a section has no rail left there is nothing to
## recompute the constant FROM).
const _RAIL_SECTIONS: Array[StringName] = [&"cloud_descent"]


func test_legacy_peak_specialists_match_frozen_constants() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var checked := 0
	for section: LevelSection in _build_sections():
		if not _RAIL_SECTIONS.has(section.section_name):
			continue
		checked += 1
		var peak := _live_peak(section, cam)
		gut.p("%s: legacy peak specialists %d" % [section.section_name, peak])
		assert_eq(peak, int(_LEGACY_PEAK_SPECIALISTS[section.section_name]),
			"%s: legacy peak concurrent snipers/rams/bombers changed" % section.section_name)
	assert_eq(checked, _RAIL_SECTIONS.size(), "sanity: every section still on rails was checked")
	# Never vacuous: every frozen constant is live-checked here until its section is migrated, then gated below.
	for key: StringName in _LEGACY_PEAK_SPECIALISTS:
		assert_true(_RAIL_SECTIONS.has(key) or MIGRATED_SECTIONS.has(key),
			"frozen constant for %s is neither live-checked nor gated" % key)


## Boundary: the live computation can reject. Extra rams dropped on a rail section's first specialist moment raise
## that section's peak, so it no longer equals the frozen constant. On cloud_descent since t21: it is the one section
## still on rails (t22 retires it, and the count gate's boundary below takes over).
func test_extra_rams_at_the_peak_break_the_frozen_constant() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var checked := false
	for section: LevelSection in _build_sections():
		if section.section_name != &"cloud_descent":
			continue
		checked = true
		var before := _live_peak(section, cam)
		assert_eq(before, int(_LEGACY_PEAK_SPECIALISTS[&"cloud_descent"]))
		var trigger := 0.0
		for row: Dictionary in EXPECTED:
			if row["section"] == &"cloud_descent":
				trigger = row["trigger"]
				break
		var b := WaveBuilder.new()
		var extra: Array = []
		for i in before + 1:
			extra.append(b.ram().at(0, -400).move(b.straight(300)))
		section.waves.append(b.wave(trigger, extra))
		assert_gt(_live_peak(section, cam), before, "an added ram wave must raise the live peak")
	assert_true(checked, "sanity: level 1 has cloud_descent")


## Boundary for the shared helper: a section with no specialists computes a peak of 0.
func test_a_section_with_no_specialists_has_zero_peak() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var checked := 0
	for section: LevelSection in _build_sections():
		if _LEGACY_PEAK_SPECIALISTS.has(section.section_name):
			continue
		checked += 1
		assert_eq(_live_peak(section, cam), 0, "%s spawns no specialists" % section.section_name)
	assert_gt(checked, 0, "sanity: level 1 has a section without specialists")


# ── t21: deep_space and planet_approach off rails (docs/plans/cmuyk2qqm009hoa2xyvw88ama/3-plan.md) ────────────────
#
# Their 35 specialist lines lost `.move()`, `.free_after()` and `.shoot_at_player()`; trigger, offset and delay are
# the pin above, unchanged. Each ship now lives `engage + deferral + exit` from its spawn moment, every term read
# from the shipped config or MEASURED on the real scene (`specialist_exit_probe.gd`) — never a straight-line exit for
# the sniper or the bomber, whose DISENGAGE curves (epic §2.9.2, the Ph3 open item):
#   sniper  engage_seconds + aim_seconds + lock_seconds        + measured exit
#   bomber  engage_seconds + run_length / run_speed + RUN_STALL_SLACK + measured exit
#   ram     engage_seconds + wind_up_seconds + charge_max_time  + max(world diagonal / exit_speed, measured exit)
# Each deferral also gets `_TICK_SLACK` (two 1/60 s ticks): the brains' AIM/LOCK and stall checks have no time
# epsilon, so the real deferral can run a tick or two over (t21 review N3). A spawn's moment is its wave's EFFECTIVE
# trigger (the running max in list order — `WaveManager` triggers strictly in order) plus its delay.

const SpecialistExitProbe := preload("res://tests/helpers/specialist_exit_probe.gd")

## The sections t21 took off rails. t22 adds cloud_descent.
const MIGRATED_SECTIONS: Array[StringName] = [&"deep_space", &"planet_approach"]

## Epic §2.9.2: peak alive specialists at most this many times the FROZEN `_LEGACY_PEAK_SPECIALISTS`.
const _COUNT_RATIO := 2.5
const _TICK_SLACK := 2.0 / 60.0
const _PROBE_CAP := 20.0

const _SNIPER_CONFIG: SniperConfig = preload("res://assault/scenes/enemies/sniper/sniper_config.tres")
const _BOMBER_CONFIG: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")
const _RAM_CONFIG: RamCorvetteConfig = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres")


## Every specialist line of `names` that still carries a rail, as "section @ trigger s, offset" strings.
func _rail_rows(sections: Array[LevelSection], names: Array[StringName]) -> Array[String]:
	var out: Array[String] = []
	for section: LevelSection in sections:
		if not names.has(section.section_name):
			continue
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _KIND_NAMES.has(path):
					continue
				if entry.movement != null or entry.exit_mode == EnemyPathMover.ExitMode.FREE_ON_DURATION \
						or entry.initial_props.has("aim_mode"):
					out.append("%s %s @ %.1f s, offset %s" % [section.section_name, _KIND_NAMES[path],
						wave.trigger_time, entry.base_offset])
	return out


func _count_lines(sections: Array[LevelSection], names: Array[StringName]) -> int:
	var n := 0
	for row: Dictionary in _actual_specialist_spawns(sections):
		if names.has(row["section"]):
			n += 1
	return n


func test_migrated_sections_have_no_rail_left() -> void:
	var sections := _build_sections()
	assert_eq(_count_lines(sections, MIGRATED_SECTIONS), 35, "sanity: 11 deep_space + 24 planet_approach lines")
	var rails := _rail_rows(sections, MIGRATED_SECTIONS)
	assert_eq(rails, [] as Array[String], "these specialist lines still have .move(), .free_after() or shoot_*()")


## Boundary: a migrated ram line given `.move()` again is reported, and only that line.
func test_a_specialist_line_given_move_again_fails_the_no_rail_check() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		if section.section_name != &"deep_space":
			continue
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _RAM:
					entry.movement = StraightMovement.new()
					mutated = true
	assert_true(mutated, "sanity: deep_space has a ram line to mutate")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS).size(), 1, "a ram line with .move() put back must be reported")


# ── Measured lifetimes ──────────────────────────────────────────────────────────────────────────────────────────

## The probe runs once per file run (about 3 s for the three kinds), not once per test.
var _exits: Dictionary = {}

func _measured_exits() -> Dictionary:
	if not _exits.is_empty():
		return _exits
	var sniper_speeds: Array[float] = [_SNIPER_CONFIG.max_speed, 10.0, 2.0]
	var bomber_speeds: Array[float] = [_BOMBER_CONFIG.max_speed, 10.0, 2.0]
	var ram_speeds: Array[float] = [maxf(_RAM_CONFIG.charge_speed, _RAM_CONFIG.exposed_charge_speed), 10.0, 2.0]
	_exits = {
		_SNIPER: SpecialistExitProbe.worst_disengage(self, load(_SNIPER), SniperBrain.Phase.DISENGAGE,
			sniper_speeds, _PROBE_CAP),
		_BOMBER: SpecialistExitProbe.worst_disengage(self, load(_BOMBER), BomberBrain.Phase.DISENGAGE,
			bomber_speeds, _PROBE_CAP),
		_RAM: SpecialistExitProbe.worst_disengage(self, load(_RAM), RamCorvetteBrain.Phase.DISENGAGE,
			ram_speeds, _PROBE_CAP),
	}
	return _exits


func _world_rect() -> Rect2:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	return cam.projectile_world_rect()


## `{ path: { "life", "engage", "deferral", "exit", "note" } }`, every term from the shipped configs or the probe.
func _ai_lives() -> Dictionary:
	var exits := _measured_exits()
	var rect := _world_rect()
	var s := _SNIPER_CONFIG
	var b := _BOMBER_CONFIG
	var r := _RAM_CONFIG
	var ram_straight: float = rect.size.length() / r.exit_speed
	var ram_curved: float = exits[_RAM]["seconds"]
	var out := {
		_SNIPER: {"engage": s.engage_seconds, "deferral": s.aim_seconds + s.lock_seconds + _TICK_SLACK,
			"exit": float(exits[_SNIPER]["seconds"]), "note": "measured curved exit"},
		_BOMBER: {"engage": b.engage_seconds,
			"deferral": b.run_length / b.run_speed + BomberBrain.RUN_STALL_SLACK + _TICK_SLACK,
			"exit": float(exits[_BOMBER]["seconds"]), "note": "measured curved exit"},
		_RAM: {"engage": r.engage_seconds, "deferral": r.wind_up_seconds + r.charge_max_time + _TICK_SLACK,
			"exit": maxf(ram_straight, ram_curved),
			"note": "max(straight %.2f, measured curved %.2f)" % [ram_straight, ram_curved]},
	}
	for path: String in out:
		var k: Dictionary = out[path]
		k["life"] = float(k["engage"]) + float(k["deferral"]) + float(k["exit"])
	return out


## One `{ "start", "end", "kind" }` per specialist the section spawns, from its EFFECTIVE trigger (header).
func _ai_intervals(section: LevelSection, lives: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var effective := -INF
	for wave: WaveResource in section.waves:
		effective = maxf(effective, wave.trigger_time)
		for entry: SpawnEntryResource in wave.entries:
			var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
			if not lives.has(path):
				continue
			var t: float = effective + entry.spawn_delay
			out.append({"start": t, "end": t + float(lives[path]["life"]), "kind": _KIND_NAMES[path]})
	return out


## `{ "count", "at" }`: the most intervals alive at once and the first start time at which that is reached
## (`DroneConcurrency.peak_interval_count()`'s sampling-at-starts, plus the moment — t21 review N1).
func _peak(intervals: Array[Dictionary]) -> Dictionary:
	var best := {"count": 0, "at": 0.0}
	for a: Dictionary in intervals:
		var t: float = a["start"]
		var alive := 0
		for b: Dictionary in intervals:
			if b["start"] <= t and t < b["end"]:
				alive += 1
		if alive > int(best["count"]):
			best = {"count": alive, "at": t}
	return best


## Sanity boundary on the probe: every run left the world before the cap, and the slowest exit is at least the
## straight distance from the rect's centre to its nearest edge at `exit_speed` (a probe that measured nothing —
## a ship freed on its first tick — fails here).
func test_measured_exits_are_real() -> void:
	var exits := _measured_exits()
	var rect := _world_rect()
	var floor_distance := minf(rect.size.x, rect.size.y) / 2.0
	var exit_speeds := {_SNIPER: _SNIPER_CONFIG.exit_speed, _BOMBER: _BOMBER_CONFIG.exit_speed,
		_RAM: _RAM_CONFIG.exit_speed}
	for path: String in exits:
		var e: Dictionary = exits[path]
		gut.p("%s: slowest DISENGAGE %.2f s over %d runs (%s)" % [_KIND_NAMES[path], e["seconds"], e["runs"], e["start"]])
		assert_eq(int(e["runs"]), SpecialistExitProbe.starts().size() * 3, "%s: every start x speed ran" % _KIND_NAMES[path])
		assert_eq(int(e["capped"]), 0, "%s: a probe run never left the world" % _KIND_NAMES[path])
		assert_gte(float(e["seconds"]), floor_distance / float(exit_speeds[path]),
			"%s: the slowest exit is at least the centre's straight run to its edge" % _KIND_NAMES[path])


func test_migrated_sections_peak_alive_specialists_within_2_5x() -> void:
	var lives := _ai_lives()
	for path: String in lives:
		var k: Dictionary = lives[path]
		gut.p("%s life %.2f s = engage %.2f + deferral %.2f + exit %.2f (%s)" % [_KIND_NAMES[path], k["life"],
			k["engage"], k["deferral"], k["exit"], k["note"]])
	var checked := 0
	for section: LevelSection in _build_sections():
		if not MIGRATED_SECTIONS.has(section.section_name):
			continue
		checked += 1
		var legacy := int(_LEGACY_PEAK_SPECIALISTS[section.section_name])
		var peak := _peak(_ai_intervals(section, lives))
		gut.p("%s: peak alive specialists %d at %.2f s (limit %.1f = %.1f x frozen %d)" % [section.section_name,
			peak["count"], peak["at"], _COUNT_RATIO * legacy, _COUNT_RATIO, legacy])
		assert_lte(float(peak["count"]), _COUNT_RATIO * legacy,
			"%s: peak alive snipers/rams/bombers over %.1fx legacy" % [section.section_name, _COUNT_RATIO])
	assert_eq(checked, MIGRATED_SECTIONS.size(), "sanity: every migrated section was checked")


## Boundary: one extra ram triple at planet_approach's own peak moment fails the count gate. The wave is INSERTED in
## list order (asserted), so its effective trigger is its own and not the running max of a later wave (review N1).
func test_an_extra_ram_triple_at_the_peak_fails_the_count_gate() -> void:
	var lives := _ai_lives()
	var section: LevelSection = null
	for s: LevelSection in _build_sections():
		if s.section_name == &"planet_approach":
			section = s
	assert_not_null(section, "sanity: level 1 has planet_approach")
	if section == null:
		return
	var limit := _COUNT_RATIO * int(_LEGACY_PEAK_SPECIALISTS[&"planet_approach"])
	var before := _peak(_ai_intervals(section, lives))
	assert_gt(float(int(before["count"]) + 3), limit, "sanity: three more ships at the peak are enough to cross the limit")
	var at: float = before["at"]
	var index := section.waves.size()
	for i in section.waves.size():
		if section.waves[i].trigger_time > at:
			index = i
			break
	var b := WaveBuilder.new()
	section.waves.insert(index, b.wave(at, [b.ram().at(-200, -400), b.ram().at(0, -400), b.ram().at(200, -400)]))
	var effective := -INF
	for i in index + 1:
		effective = maxf(effective, section.waves[i].trigger_time)
	assert_almost_eq(effective, at, 0.0001, "sanity: the inserted wave sits in list order")
	var after := _peak(_ai_intervals(section, lives))
	gut.p("planet_approach + ram triple at %.2f s: peak %d -> %d (limit %.1f)" % [at, before["count"], after["count"], limit])
	assert_eq(int(after["count"]), int(before["count"]) + 3, "the triple adds exactly its three rams at the peak")
	assert_gt(float(after["count"]), limit, "the count gate must reject this")
