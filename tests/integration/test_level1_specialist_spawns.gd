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
## data. t21 removed deep_space and planet_approach and t22 removed cloud_descent (see `MIGRATED_SECTIONS` below: their
## count gate divides by the frozen constant instead; once a section has no rail left there is nothing to recompute the
## constant FROM), so this is empty — the Ph3 t17 shape. The check re-arms by itself if a section is ever put back on
## rails. Until then `_rail_lifetime()`'s sampling branch is exercised by nothing (t22 review N7); it stays for that day.
const _RAIL_SECTIONS: Array[StringName] = []


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


# ── t21 / t22: all three sections off rails (docs/plans/cmuyk2qqm009hoa2xyvw88ama/3-plan.md; t22: cloud_descent,
# docs/plans/cmuyk2qqp009loa2xb1k3py8o/3-plan.md) ────────────────────────────────────────────────────────────────────
#
# All 50 specialist lines (35 in t21, cloud_descent's 15 in t22) lost `.move()`, `.free_after()` and
# `.shoot_at_player()`; trigger, offset and delay are the pin above, unchanged. Each ship now lives `engage + deferral + exit` from its spawn moment, every term read
# from the shipped config or MEASURED on the real scene (`specialist_exit_probe.gd`) — never a straight-line exit for
# the sniper or the bomber, whose DISENGAGE curves (epic §2.9.2, the Ph3 open item):
#   sniper  engage_seconds + aim_seconds + lock_seconds        + measured exit
#   bomber  engage_seconds + run_length / run_speed + RUN_STALL_SLACK + measured exit
#   ram     engage_seconds + wind_up_seconds + charge_max_time  + max(world diagonal / exit_speed, measured exit)
# Each deferral also gets `_TICK_SLACK` (two 1/60 s ticks): the brains' AIM/LOCK and stall checks have no time
# epsilon, so the real deferral can run a tick or two over (t21 review N3). A spawn's moment is its wave's EFFECTIVE
# trigger (the running max in list order — `WaveManager` triggers strictly in order) plus its delay.
#
# The exits here are t21's VIEW-grid measurements. For the ram they under-report by about 1.7 s per life: a ram can
# begin DISENGAGE anywhere in the 1480 x 1480 corridor, and `test_engagement_deadline.gd` measures its cloud_descent
# rows over `SpecialistExitProbe.corridor_starts()` for that reason (t22 review B1 / N1). Kept here as t21 built it
# (a follow-up in DECISIONS); every section's peak has slack against it.

const SpecialistExitProbe := preload("res://tests/helpers/specialist_exit_probe.gd")

## The sections t21 (deep_space, planet_approach) and t22 (cloud_descent) took off rails: all 50 specialist rows.
const MIGRATED_SECTIONS: Array[StringName] = [&"deep_space", &"planet_approach", &"cloud_descent"]

## Epic §2.9.2: peak alive specialists at most this many times the FROZEN `_LEGACY_PEAK_SPECIALISTS`.
const _COUNT_RATIO := 2.5
const _TICK_SLACK := 2.0 / 60.0
const _PROBE_CAP := 20.0

const _SNIPER_CONFIG: SniperConfig = preload("res://assault/scenes/enemies/sniper/sniper_config.tres")
const _BOMBER_CONFIG: BomberConfig = preload("res://assault/scenes/enemies/bomber/bomber_config.tres")
const _RAM_CONFIG: RamCorvetteConfig = preload("res://assault/scenes/enemies/ram_corvette/ram_corvette_config.tres")


## Every specialist line of `names` that still carries a rail, as "section @ trigger s, offset" strings.
func _rail_rows(sections: Array[LevelSection], names: Array[StringName],
		kinds: Dictionary = _KIND_NAMES) -> Array[String]:
	var out: Array[String] = []
	for section: LevelSection in sections:
		if not names.has(section.section_name):
			continue
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not kinds.has(path):
					continue
				if entry.movement != null or entry.exit_mode == EnemyPathMover.ExitMode.FREE_ON_DURATION \
						or entry.initial_props.has("aim_mode"):
					out.append("%s %s @ %.1f s, offset %s" % [section.section_name, kinds[path],
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
	assert_eq(_count_lines(sections, MIGRATED_SECTIONS), 50, "sanity: 11 deep_space + 24 planet_approach + 15 cloud_descent lines")
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
	out.merge(_ph5_lives())
	out.merge(_ph7_lives())
	for path: String in out:
		var k: Dictionary = out[path]
		k["life"] = float(k["engage"]) + float(k["deferral"]) + float(k["exit"])
	return out


## One `{ "start", "end", "kind" }` per specialist the section spawns, from its EFFECTIVE trigger (header). The Phase 8
## ships (turret-group members, twin drones, the tender and its drones) are appended by `_ph8_intervals()`, so every
## peak, boundary and spill-over row below counts them.
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
			out.append({"start": t, "end": t + float(lives[path]["life"]), "kind": _name_of(path)})
	out.append_array(_ph8_intervals(section))
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
		gut.p("%s life %.2f s = engage %.2f + deferral %.2f + exit %.2f (%s)" % [_name_of(path), k["life"],
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
			"%s: peak alive specialists (sniper/ram/bomber/corvette/support) over %.1fx legacy" % [section.section_name, _COUNT_RATIO])
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


# ── Phase 5 t17: the Missile Corvette and the Support Ship join level 1 (epic plan
# docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.18; task plan docs/plans/cmv9szqmi002zqs2x3cd8f942/3-plan.md) ──────
#
# Five new lines, each inside an existing wave of a DURATION section, AI-driven with no rail: a corvette 1.0 s after
# deep_space's 11.0 s wave, a support with deep_space's 26.0 s ram pair (60 design units = 120 px behind the ram at
# (-255, -400)), a support with planet_approach's 28.0 s ram triple, and corvettes 1.0 s after planet_approach's 39.0 s
# and 84.0 s waves. They are pinned in `EXPECTED_PH5`, separately from the frozen 50-row `EXPECTED` above.
#
# Both kinds COUNT AS SPECIALISTS in the 2.5x gate (`_ai_lives()` merges them in); the frozen
# `_LEGACY_PEAK_SPECIALISTS` is unchanged. Their lives, every term read from the shipped config or measured:
#   corvette  engage_seconds + attack_window() (salvo_telegraph + 2 x salvo_gap) + _TICK_SLACK + measured exit
#   support   engage_seconds + measured exit (its budget never defers: DISENGAGE begins on expiry, escort or not)
# Both exits are measured over `SpecialistExitProbe.corridor_starts()` — the whole corridor, never the view grid, which
# under-reports a ship that can begin DISENGAGE anywhere in it (the Ph4 ram lesson) — once per file run, in
# `before_all()`.

const _MISSILE_CORVETTE := WaveBuilder.MISSILE_CORVETTE
const _SUPPORT_SHIP := WaveBuilder.SUPPORT_SHIP
const _PH5_KIND_NAMES := {_MISSILE_CORVETTE: "MISSILE_CORVETTE", _SUPPORT_SHIP: "SUPPORT_SHIP"}

const _CORVETTE_CONFIG: MissileCorvetteConfig = preload("res://assault/scenes/enemies/missile_corvette/missile_corvette_config.tres")
const _SUPPORT_CONFIG: SupportShipConfig = preload("res://assault/scenes/enemies/support_ship/support_ship_config.tres")

## Every corvette / support entry in `_build_sections()`, in encounter order, in `EXPECTED`'s shape (`trigger` is the
## wave's own `trigger_time`).
const EXPECTED_PH5: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "MISSILE_CORVETTE", "trigger": 11.00, "offset": Vector2(0.0, -400.0), "delay": 1.00},
	{"section": &"deep_space", "kind": "SUPPORT_SHIP", "trigger": 26.00, "offset": Vector2(-255.0, -460.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "SUPPORT_SHIP", "trigger": 28.00, "offset": Vector2(0.0, -460.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "MISSILE_CORVETTE", "trigger": 39.00, "offset": Vector2(0.0, -400.0), "delay": 1.00},
	{"section": &"planet_approach", "kind": "MISSILE_CORVETTE", "trigger": 84.00, "offset": Vector2(0.0, -400.0), "delay": 1.00},
]

## `{ path: probe result }` for the corvette and the support over `corridor_starts()`, filled once in `before_all()`.
var _ph5_exits: Dictionary = {}


func before_all() -> void:
	var cam := ArenaCamera.new()  # not add_child_autofree: before_all() runs outside any test
	add_child(cam)
	var world := cam.projectile_world_rect()
	cam.free()
	var corridor := SpecialistExitProbe.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), world)
	var corvette_speeds: Array[float] = [_CORVETTE_CONFIG.max_speed, 10.0]
	var support_speeds: Array[float] = [_SUPPORT_CONFIG.max_speed, 10.0]
	_ph5_exits = {
		_MISSILE_CORVETTE: SpecialistExitProbe.worst_disengage(self, load(_MISSILE_CORVETTE),
			MissileCorvetteBrain.Phase.DISENGAGE, corvette_speeds, _PROBE_CAP, corridor, _empty_pools),
		_SUPPORT_SHIP: SpecialistExitProbe.worst_disengage(self, load(_SUPPORT_SHIP), SupportShipBrain.Phase.DISENGAGE,
			support_speeds, _PROBE_CAP, corridor),
	}
	var layer_speeds: Array[float] = [_LAYER_CONFIG.exit_speed, 10.0]
	_ph7_exit = SpecialistExitProbe.worst_disengage(self, load(_MINE_LAYER), MineLayerBrain.Phase.DISENGAGE,
		layer_speeds, _PROBE_CAP, corridor, _layer_probe_prepare)


## A corvette never fires in DISENGAGE, so its probe instances skip prewarming 16 rockets each (2166 runs).
func _empty_pools(ship: Node) -> void:
	for child in ship.get_children():
		if child is BulletPool:
			(child as BulletPool).pool_size = 0


## The layer's probe instances skip prewarming every pool (as the corvette's do) and switch the tail drop off (`tail_range` 0
## on the private config copy). The probe reuses one world for 2166 runs and a mine outlives its layer, so a tail mine left by
## one run would sit in the way of every later one and the figure would measure that litter, not the exit; a mine dropped
## behind an exiting layer is outside its avoidance cone and never changes its exit (checked by hand: 3 s with and without).
##
## The probe world's player stub also leaves group `player` (rule 3, tests/README.md -> Gate time): DISENGAGE reads the player
## in exactly two places, the tail drop (off above) and the v-bar update (read only by the planner, which a layer in
## DISENGAGE never runs again), so with no target the per-tick `TargetInfo.player()` finds nobody and the prediction and tail
## checks return at their first line, and the exit is bit-identical (7.53 s over 2166 runs, 0 capped, before and after).
## The stub belongs to the probe's own world, which `worst_disengage()` frees before it returns.
func _layer_probe_prepare(ship: Node) -> void:
	_empty_pools(ship)
	(ship as MineLayer).config.tail_range = 0.0
	for player in get_tree().get_nodes_in_group(&"player"):
		player.remove_from_group(&"player")


func _name_of(path: String) -> String:
	if _KIND_NAMES.has(path):
		return _KIND_NAMES[path]
	return _PH5_KIND_NAMES[path] if _PH5_KIND_NAMES.has(path) else _PH7_KIND_NAMES[path]


func _ph5_lives() -> Dictionary:
	var c := _CORVETTE_CONFIG
	var deferral := c.salvo_telegraph + float(maxi(c.salvo_count, c.warhead_salvo_count) - 1) * c.salvo_gap
	return {
		_MISSILE_CORVETTE: {"engage": c.engage_seconds, "deferral": deferral + _TICK_SLACK,
			"exit": float(_ph5_exits[_MISSILE_CORVETTE]["seconds"]), "note": "measured corridor exit"},
		_SUPPORT_SHIP: {"engage": _SUPPORT_CONFIG.engage_seconds, "deferral": 0.0,
			"exit": float(_ph5_exits[_SUPPORT_SHIP]["seconds"]), "note": "measured corridor exit"},
	}


func _actual_ph5_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _PH5_KIND_NAMES.has(path):
					continue
				assert_null(entry.formation, "no Phase 5 line uses a formation; the pin has no formation column")
				out.append({"section": section.section_name, "kind": _PH5_KIND_NAMES[path],
					"trigger": wave.trigger_time, "offset": entry.base_offset, "delay": entry.spawn_delay})
	return out


func _section(sections: Array[LevelSection], section_name: StringName) -> LevelSection:
	for s: LevelSection in sections:
		if s.section_name == section_name:
			return s
	return null


func test_pinned_phase5_spawns_match_todays_data() -> void:
	var actual := _actual_ph5_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED_PH5.size(), "the number of corvette / support entries changed")
	assert_eq(actual, EXPECTED_PH5, "a corvette / support spawn's section, trigger, offset or delay changed")


## 5 rows: 2 in deep_space and 3 in planet_approach, 3 corvettes and 2 supports, none in an ENEMIES_CLEARED section
## (`test_engagement_deadline.gd` says why).
func test_the_phase5_pin_itself_is_internally_consistent() -> void:
	var by_kind: Dictionary = {}
	var by_section: Dictionary = {}
	for row: Dictionary in EXPECTED_PH5:
		by_kind[row["kind"]] = int(by_kind.get(row["kind"], 0)) + 1
		by_section[row["section"]] = int(by_section.get(row["section"], 0)) + 1
	assert_eq(EXPECTED_PH5.size(), 5)
	assert_eq(int(by_kind.get("MISSILE_CORVETTE", 0)), 3, "corvette row count changed")
	assert_eq(int(by_kind.get("SUPPORT_SHIP", 0)), 2, "support row count changed")
	assert_eq(int(by_section.get(&"deep_space", 0)), 2, "deep_space Phase 5 row count changed")
	assert_eq(int(by_section.get(&"planet_approach", 0)), 3, "planet_approach Phase 5 row count changed")
	assert_eq(by_section.size(), 2, "corvettes and supports spawn only in deep_space and planet_approach")


## Each support rides with the ram it was placed for: a ram line in the same wave, 60 design units above it.
func test_each_level1_support_spawns_with_a_ram_of_its_wave() -> void:
	var checked := 0
	for section: LevelSection in _build_sections():
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene == null or entry.ship_scene.resource_path != _SUPPORT_SHIP:
					continue
				checked += 1
				var escorted := false
				for other: SpawnEntryResource in wave.entries:
					if other.ship_scene and other.ship_scene.resource_path == _RAM \
							and other.base_offset + Vector2(0.0, -60.0) == entry.base_offset \
							and is_equal_approx(other.spawn_delay, entry.spawn_delay):
						escorted = true
				assert_true(escorted, "%s @ %.1f s: the support spawns with a ram, 60 units behind it" % [
					section.section_name, wave.trigger_time])
	assert_eq(checked, 2, "sanity: both supports were checked")


## Boundary: a Phase 5 line's delay changed in memory must not match the pin (fresh sections; nothing shared mutated).
func test_a_phase5_lines_delay_changed_fails_the_pin() -> void:
	for path: String in [_MISSILE_CORVETTE, _SUPPORT_SHIP]:
		var sections := _build_sections()
		var mutated := false
		for section: LevelSection in sections:
			for wave: WaveResource in section.waves:
				for entry: SpawnEntryResource in wave.entries:
					if not mutated and entry.ship_scene and entry.ship_scene.resource_path == path:
						entry.spawn_delay += 1.0
						mutated = true
		assert_true(mutated, "sanity: level 1 has a %s line to mutate" % _name_of(path))
		assert_ne(_actual_ph5_spawns(sections), EXPECTED_PH5, "a %s line with a changed delay must not match the pin"
			% _name_of(path))


## The migrated sections now hold 50 legacy + 5 Phase 5 = 55 specialist lines, and no Phase 5 line has a rail
## (`.move()`, `.free_after()` or `.shoot_*()`); the legacy count above is unchanged.
func test_phase5_lines_have_no_rail() -> void:
	var sections := _build_sections()
	var ph5 := 0
	for row: Dictionary in _actual_ph5_spawns(sections):
		if MIGRATED_SECTIONS.has(row["section"]):
			ph5 += 1
	assert_eq(_count_lines(sections, MIGRATED_SECTIONS) + ph5, 55, "50 legacy + 5 Phase 5 specialist lines")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH5_KIND_NAMES), [] as Array[String],
		"these corvette / support lines have .move(), .free_after() or shoot_*()")


## Boundary: a corvette line given `.move()` is reported by the same check, and only that line.
func test_a_phase5_line_given_move_fails_the_no_rail_check() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _MISSILE_CORVETTE:
					entry.movement = StraightMovement.new()
					mutated = true
	assert_true(mutated, "sanity: level 1 has a corvette line to mutate")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH5_KIND_NAMES).size(), 1,
		"a corvette line with .move() must be reported")


## Sanity boundary on the corridor probes: every start x speed ran, none capped, and the slowest exit is at least the
## straight distance from the world rect's centre to its nearest edge at `exit_speed`.
func test_phase5_measured_exits_are_real() -> void:
	var rect := _world_rect()
	var floor_distance := minf(rect.size.x, rect.size.y) / 2.0
	var corridor := SpecialistExitProbe.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), rect)
	var exit_speeds := {_MISSILE_CORVETTE: _CORVETTE_CONFIG.exit_speed, _SUPPORT_SHIP: _SUPPORT_CONFIG.exit_speed}
	assert_eq(_ph5_exits.size(), 2, "sanity: both kinds were probed")
	for path: String in _ph5_exits:
		var e: Dictionary = _ph5_exits[path]
		gut.p("%s: slowest corridor DISENGAGE %.2f s over %d runs (%s)" % [_name_of(path), e["seconds"], e["runs"],
			e["start"]])
		assert_eq(int(e["runs"]), corridor.size() * 2, "%s: every corridor start x speed ran" % _name_of(path))
		assert_eq(int(e["capped"]), 0, "%s: a probe run never left the world" % _name_of(path))
		assert_gte(float(e["seconds"]), floor_distance / float(exit_speeds[path]),
			"%s: the slowest exit is at least the centre's straight run to its edge" % _name_of(path))


## Boundary (acceptance criterion): one extra corvette at planet_approach's peak moment fails the count gate. The peak
## is MEASURED (`_peak()["at"]`, the ram-triple boundary's shape): the task text's 65.7 s predates the t22 ram levers,
## and today the peak is 7 at 98.0 s (bomber, two snipers, the 88 s ram triple and the 85 s corvette). Asserting the
## count is 7 keeps this from going vacuous: 7 + 1 = 8 > 7.5.
func test_an_extra_corvette_at_the_peak_fails_the_count_gate() -> void:
	var lives := _ai_lives()
	var section := _section(_build_sections(), &"planet_approach")
	assert_not_null(section, "sanity: level 1 has planet_approach")
	if section == null:
		return
	var limit := _COUNT_RATIO * int(_LEGACY_PEAK_SPECIALISTS[&"planet_approach"])
	var before := _peak(_ai_intervals(section, lives))
	assert_eq(int(before["count"]), 7, "sanity: planet_approach peaks at 7 alive, one under its 7.5 limit")
	var at: float = before["at"]
	var index := section.waves.size()
	for i in section.waves.size():
		if section.waves[i].trigger_time > at:
			index = i
			break
	var b := WaveBuilder.new()
	section.waves.insert(index, b.wave(at, [b.missile_corvette().at(0, -400)]))
	var effective := -INF
	for i in index + 1:
		effective = maxf(effective, section.waves[i].trigger_time)
	assert_almost_eq(effective, at, 0.0001, "sanity: the inserted wave sits in list order")
	var after := _peak(_ai_intervals(section, lives))
	gut.p("planet_approach + corvette at %.2f s: peak %d -> %d (limit %.1f)" % [at, before["count"], after["count"], limit])
	assert_eq(int(after["count"]), int(before["count"]) + 1, "the corvette adds exactly one ship at the peak")
	assert_gt(float(after["count"]), limit, "the count gate must reject this")


# ── Phase 7 t15: the Mine Layer joins level 1 (epic plan docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md §2.16) ─────────
#
# Two lines, each inside an existing wave of a DURATION section, AI-driven with no rail: deep_space's 16.0 s wave
# (entering from the left) and planet_approach's 47.0 s wave (from the right). They are pinned in `EXPECTED_PH7`,
# separately from the frozen 50-row `EXPECTED` and from `EXPECTED_PH5`.
#
# The layer COUNTS AS A SPECIALIST in the 2.5x gate (`_ai_lives()` merges it in); the frozen `_LEGACY_PEAK_SPECIALISTS`
# is unchanged. Its life, every term read from the shipped config or measured:
#   engage_seconds + LAY's stall guard (the longest pass: ZIGZAG) + _TICK_SLACK + measured exit
# The exit is `SpecialistExitProbe.worst_disengage()` over `corridor_starts()` at [exit_speed, 10], with no planned
# pass: the layer leaves along its current heading, and entering DISENGAGE releases the corridor constraint (as the
# Bomber's does), so the probe measures the real exit and not the `AssaultCorridorConstraint`'s hard band. The life
# also covers the run-in, which sits inside the engagement budget (APPROACH). Its mines outlive it by
# `assault_mine_life` (the spill-over rows below add that term, as a corvette's rocket life).

const _MINE_LAYER := WaveBuilder.MINE_LAYER
const _PH7_KIND_NAMES := {_MINE_LAYER: "MINE_LAYER"}
const _LAYER_CONFIG: MineLayerConfig = preload("res://assault/scenes/enemies/mine_layer/mine_layer_config.tres")

const EXPECTED_PH7: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "MINE_LAYER", "trigger": 16.00, "offset": Vector2(-400.0, -160.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "MINE_LAYER", "trigger": 47.00, "offset": Vector2(400.0, -160.0), "delay": 0.00},
]

## The layer's corridor-start DISENGAGE probe, filled once in `before_all()`.
var _ph7_exit: Dictionary = {}


## The longest LAY can run: `MineLayerBrain`'s stall guard on the ZIGZAG path (S -> mine 0 -> ... -> mine 5 -> E), read
## from the shipped config. The ARC path is shorter.
func _lay_stall_guard() -> float:
	var c := _LAYER_CONFIG
	var lead := c.pass_length * 0.5 - float(c.mines_per_pass - 1) * 0.5 * c.mine_step
	var chord := Vector2(c.mine_step, 2.0 * c.zigzag_amplitude).length()
	var path := 2.0 * Vector2(lead, c.zigzag_amplitude).length() + float(c.mines_per_pass - 1) * chord
	return path * MineLayerBrain.STALL_FACTOR / c.lay_speed + MineLayerBrain.STALL_SLACK


func _ph7_lives() -> Dictionary:
	return {
		_MINE_LAYER: {"engage": _LAYER_CONFIG.engage_seconds, "deferral": _lay_stall_guard() + _TICK_SLACK,
			"exit": float(_ph7_exit["seconds"]), "note": "measured corridor exit, no planned pass"},
	}


func _actual_ph7_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _PH7_KIND_NAMES.has(path):
					continue
				assert_null(entry.formation, "no Phase 7 line uses a formation; the pin has no formation column")
				out.append({"section": section.section_name, "kind": _PH7_KIND_NAMES[path],
					"trigger": wave.trigger_time, "offset": entry.base_offset, "delay": entry.spawn_delay})
	return out


func test_pinned_phase7_spawns_match_todays_data() -> void:
	var actual := _actual_ph7_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED_PH7.size(), "the number of Mine Layer entries changed")
	assert_eq(actual, EXPECTED_PH7, "a Mine Layer spawn's section, trigger, offset or delay changed")


## 2 rows, one in deep_space (from the left) and one in planet_approach (from the right), none in an ENEMIES_CLEARED
## section (`test_engagement_deadline.gd` says why), and each shares its wave with other traffic (no new wave).
func test_the_phase7_pin_itself_is_internally_consistent() -> void:
	var by_section: Dictionary = {}
	for row: Dictionary in EXPECTED_PH7:
		by_section[row["section"]] = int(by_section.get(row["section"], 0)) + 1
		assert_eq(row["kind"], "MINE_LAYER")
	assert_eq(EXPECTED_PH7.size(), 2)
	assert_eq(int(by_section.get(&"deep_space", 0)), 1, "deep_space Phase 7 row count changed")
	assert_eq(int(by_section.get(&"planet_approach", 0)), 1, "planet_approach Phase 7 row count changed")
	assert_eq(by_section.size(), 2, "Mine Layers spawn only in deep_space and planet_approach")
	assert_lt((EXPECTED_PH7[0]["offset"] as Vector2).x, 0.0, "deep_space's layer enters from the left")
	assert_gt((EXPECTED_PH7[1]["offset"] as Vector2).x, 0.0, "planet_approach's layer enters from the right")


## Each layer rides inside an existing wave (another ship in the same wave), so no wave's effective trigger moved.
func test_each_level1_mine_layer_shares_an_existing_wave() -> void:
	var checked := 0
	for section: LevelSection in _build_sections():
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene == null or entry.ship_scene.resource_path != _MINE_LAYER:
					continue
				checked += 1
				assert_gt(wave.entries.size(), 1, "%s @ %.1f s: the layer joins a wave that already existed" % [
					section.section_name, wave.trigger_time])
	assert_eq(checked, 2, "sanity: both layers were checked")


## Boundary: a Phase 7 line's delay changed in memory must not match the pin (fresh sections; nothing shared mutated).
func test_a_phase7_lines_delay_changed_fails_the_pin() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _MINE_LAYER:
					entry.spawn_delay += 1.0
					mutated = true
	assert_true(mutated, "sanity: level 1 has a Mine Layer line to mutate")
	assert_ne(_actual_ph7_spawns(sections), EXPECTED_PH7, "a Mine Layer line with a changed delay must not match the pin")


## The layer lines have no rail (`.move()`, `.free_after()` or `.shoot_*()`); 50 + 5 + 2 specialist lines in all.
func test_phase7_lines_have_no_rail() -> void:
	var sections := _build_sections()
	var ph7 := 0
	for row: Dictionary in _actual_ph7_spawns(sections):
		if MIGRATED_SECTIONS.has(row["section"]):
			ph7 += 1
	assert_eq(ph7, 2, "both Mine Layer lines are in a migrated section")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH7_KIND_NAMES), [] as Array[String],
		"these Mine Layer lines have .move(), .free_after() or shoot_*()")


## Boundary: a layer line given `.move()` is reported by the same check, and only that line.
func test_a_phase7_line_given_move_fails_the_no_rail_check() -> void:
	var sections := _build_sections()
	var mutated := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if not mutated and entry.ship_scene and entry.ship_scene.resource_path == _MINE_LAYER:
					entry.movement = StraightMovement.new()
					mutated = true
	assert_true(mutated, "sanity: level 1 has a Mine Layer line to mutate")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH7_KIND_NAMES).size(), 1,
		"a Mine Layer line with .move() must be reported")


## LAY's stall guard is the plan's 5.67 s (ZIGZAG), so the life below defers by the worst case, not a typed number.
func test_the_lay_deferral_is_the_zigzag_stall_guard() -> void:
	assert_almost_eq(_lay_stall_guard(), 5.67, 0.02, "732 px * 1.2 / 170 + 0.5")


## Sanity boundary on the corridor probe (the Phase 5 shape), plus the row the plan names: the probed layer is released
## from the corridor in DISENGAGE, so the figure is the real exit and not the constraint's cap.
func test_phase7_measured_exit_is_real_and_the_corridor_is_released() -> void:
	var rect := _world_rect()
	var floor_distance := minf(rect.size.x, rect.size.y) / 2.0
	var corridor := SpecialistExitProbe.corridor_starts(AssaultCorridorConstraint.new().inner_rect(), rect)
	var e: Dictionary = _ph7_exit
	gut.p("MINE_LAYER: slowest corridor DISENGAGE %.2f s over %d runs (%s)" % [e["seconds"], e["runs"], e["start"]])
	assert_eq(int(e["runs"]), corridor.size() * 2, "every corridor start x speed ran")
	assert_eq(int(e["capped"]), 0, "a probe run never left the world")
	assert_gte(float(e["seconds"]), floor_distance / _LAYER_CONFIG.exit_speed,
		"the slowest exit is at least the centre's straight run to its edge")
	var h: RefCounted = SpecialistExitProbe.HARNESS.assault()
	add_child_autofree(h.root)
	var layer := (load(_MINE_LAYER) as PackedScene).instantiate() as MineLayer
	layer.global_position = SpecialistExitProbe.MID_VIEW
	h.root.add_child(layer)
	layer.set_physics_process(false)
	(layer.get_node("Brain") as MineLayerBrain).enter_phase(MineLayerBrain.Phase.DISENGAGE)
	var mover := layer.get_node("EnemyMover") as EnemyMover
	assert_true(mover.constraint_released(), "DISENGAGE releases the corridor, as the probe's layer does")
	assert_eq(mover.max_speed, _LAYER_CONFIG.exit_speed, "and exits at exit_speed")


## Boundary (acceptance criterion): an extra Mine Layer at planet_approach's measured peak fails the count gate.
## The gate counts the layer: planet_approach's own layer (47 s) does not move the peak (7 at 98.0 s), and a second one
## at that moment takes it to 8 > 7.5; deep_space stays under its 12.5.
func test_an_extra_mine_layer_at_the_peak_fails_the_count_gate() -> void:
	var lives := _ai_lives()
	var section := _section(_build_sections(), &"planet_approach")
	assert_not_null(section, "sanity: level 1 has planet_approach")
	if section == null:
		return
	var limit := _COUNT_RATIO * int(_LEGACY_PEAK_SPECIALISTS[&"planet_approach"])
	var before := _peak(_ai_intervals(section, lives))
	assert_eq(int(before["count"]), 7, "sanity: planet_approach peaks at 7 alive, one under its 7.5 limit")
	var at: float = before["at"]
	var index := section.waves.size()
	for i in section.waves.size():
		if section.waves[i].trigger_time > at:
			index = i
			break
	var b := WaveBuilder.new()
	section.waves.insert(index, b.wave(at, [b.mine_layer().at(400, -160)]))
	var effective := -INF
	for i in index + 1:
		effective = maxf(effective, section.waves[i].trigger_time)
	assert_almost_eq(effective, at, 0.0001, "sanity: the inserted wave sits in list order")
	var after := _peak(_ai_intervals(section, lives))
	gut.p("planet_approach + mine layer at %.2f s: peak %d -> %d (limit %.1f)" % [at, before["count"], after["count"], limit])
	assert_eq(int(after["count"]), int(before["count"]) + 1, "the layer adds exactly one ship at the peak")
	assert_gt(float(after["count"]), limit, "the count gate must reject this")


# ── Phase 8 t19: a turret group, a twin pair and a Laser Tender join level 1 (epic plan
# docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md §2.18; task plan docs/plans/cmvqw0voi019bqs2x3j5zd2o8/3-plan.md) ──────
#
# Three lines, each inside an existing wave of a DURATION section, with no rail: `b.turret_group(TURRET_GROUP_ASSAULT_PAIR)
# .at(64, -220)` in deep_space's 3.0 s wave (effective 3.5 s, the wave-order quirk), `b.twin_laser_pair().at(-250, -220)` in
# deep_space's 29.0 s wave and `b.laser_tender().at(-300, -200)` in planet_approach's 2.0 s wave. Pinned in `EXPECTED_PH8`.
# The group's x is the plan's (-64) mirrored about the 640 column: at -64 the level-start `LaserWallWave` (x 0-672, lethal
# while the group spawns) killed every member in `scripts/measure-level1-columns.sh`; the column row now reads that wall too.
#
# Each line expands to several ships, so `_ai_lives()` (keyed per scene) does not hold them: `_ph8_intervals()` appends one
# interval per SHIP to `_ai_intervals()`, and the frozen 2.5x gate, every peak boundary and the spill-over rows count them.
# Every term is read from a scene, a config, code or the memoised Ph8 probes (`ph8_exit_keys.gd`, never a hand-built call):
#   turret-group member  _TICK_SLACK (the deferred spawn) + (world.end.y - y_spawn) / config.assault_drift_speed, where
#                        y_spawn = world centre y - ArenaCamera.V_LIMIT - CameraShake._MAX_OFFSET + design y * WORLD_SCALE
#                        + slot y: the view at its highest, shake included, so the longest drift any run can see
#   twin drone (x2)      engage_seconds + twin telegraph_seconds + max_advance + _TICK_SLACK + drone_exit_bound(), where
#                        max_advance = (max(standoff, tender assault_wall_lead) + overshoot) / advance_speed (plan §2.12)
#   tender               engage_seconds + launch_telegraph + _TICK_SLACK + tender_exit() (a LAUNCH shown at expiry finishes)
#   tender drone (x2)    from the tender's spawn (the earliest launch) to the latest launch (spawn + engage_seconds +
#                        launch_telegraph + _TICK_SLACK) plus a drone life (a launched drone's budget counts from its launch)
# No Ph8 ship leaves ordnance behind: the group's mounts' pools are `persist == false` (checked in the spill-over section),
# the Pulse Ring is a mount child and the twin beam a child of drone A, so `_ordnance_tail()` is 0 for every Ph8 kind.

const PH8_EXITS := preload("res://tests/helpers/ph8_exit_keys.gd")
const _CAMERA_SHAKE := preload("res://global/systems/camera_shake.gd")
const _TURRET_GROUP_DIR := "res://assault/scenes/structures/turret_group/"
const _TWIN_PAIR := WaveBuilder.TWIN_LASER_PAIR
const _LASER_TENDER := WaveBuilder.LASER_TENDER
const _PH8_KIND_NAMES := {WaveBuilder.TURRET_GROUP_ASSAULT_PAIR: "TURRET_GROUP_ASSAULT_PAIR", _TWIN_PAIR: "TWIN_LASER_PAIR",
	_LASER_TENDER: "LASER_TENDER", WaveBuilder.LASER_FENCE: "LASER_FENCE"}
## The `kind` of each Ph8 interval `_ph8_intervals()` builds.
const _PH8_INTERVAL_KINDS: Array[String] = ["TURRET_MEMBER", "TWIN_DRONE", "LASER_TENDER", "TENDER_DRONE"]
const _DRONE_CONFIG: TwinLaserDroneConfig = preload("res://assault/scenes/enemies/twin_laser_drone/twin_laser_drone_config.tres")
const _TENDER_CONFIG: LaserTenderConfig = preload("res://assault/scenes/enemies/laser_tender/laser_tender_config.tres")

const EXPECTED_PH8: Array[Dictionary] = [
	{"section": &"deep_space", "kind": "TURRET_GROUP_ASSAULT_PAIR", "trigger": 3.00, "offset": Vector2(64.0, -220.0), "delay": 0.00},
	{"section": &"deep_space", "kind": "TWIN_LASER_PAIR", "trigger": 29.00, "offset": Vector2(-250.0, -220.0), "delay": 0.00},
	{"section": &"planet_approach", "kind": "LASER_TENDER", "trigger": 2.00, "offset": Vector2(-300.0, -200.0), "delay": 0.00},
]

## `_ph8_lives()`'s figures and `_group_members()`'s per-preset rows, built once per file run (the probes are memo hits
## once `test_laser_tender.gd` has run; alone, this file pays for them once).
var _ph8_cache: Dictionary = {}
var _group_cache: Dictionary = {}


## `{ "telegraph", "max_advance", "drone_exit", "tender_exit", "drone", "launch_latest", "tender", "world" }`.
func _ph8_lives() -> Dictionary:
	if not _ph8_cache.is_empty():
		return _ph8_cache
	var d := _DRONE_CONFIG
	var t := _TENDER_CONFIG
	var telegraph := float(EnemyBeamScenes.export_of(EnemyBeam.Kind.TWIN, &"telegraph_seconds", 0.0))
	var max_advance := (maxf(d.standoff, t.assault_wall_lead) + d.overshoot) / d.advance_speed
	var drone_exit: float = PH8_EXITS.drone_exit_bound(self)
	var tender_exit := float(PH8_EXITS.tender_exit(self)["seconds"])
	var launch_latest := t.engage_seconds + t.launch_telegraph + _TICK_SLACK
	_ph8_cache = {
		"telegraph": telegraph, "max_advance": max_advance, "drone_exit": drone_exit, "tender_exit": tender_exit,
		"drone": d.engage_seconds + telegraph + max_advance + _TICK_SLACK + drone_exit,
		"launch_latest": launch_latest, "tender": launch_latest + tender_exit, "world": _world_rect(),
	}
	return _ph8_cache


## One `{ "name", "slot", "radius", "speed", "variants" }` per member slot of the preset at `path`, read from the off-tree
## preset and member scenes: the slot's local position, the member body circle's radius (scale applied), its config's
## `assault_drift_speed`, and the variant of each of its turret mounts (the slot override on the first, as
## `TurretGroup.mount_reaches()` reads them).
func _group_members(path: String) -> Array:
	if _group_cache.has(path):
		return _group_cache[path]
	var out: Array = []
	var preset := (load(path) as PackedScene).instantiate()
	for child in preset.get_children():
		var slot := child as TurretGroupSlot
		if slot == null or slot.member_scene == null:
			continue
		var member := slot.member_scene.instantiate()
		var body := member.get_node("CollisionShape2D") as CollisionShape2D
		var radius := (body.shape as CircleShape2D).radius * maxf(absf(body.scale.x), absf(body.scale.y))
		var variants: Array[int] = []
		var mount_slots := member.get_node_or_null("MountSlots")
		if mount_slots != null:
			for marker in mount_slots.get_children():
				if marker is TurretMountSlot:
					var first := variants.is_empty()
					variants.append(slot.variant if first and slot.variant >= 0 else int((marker as TurretMountSlot).variant))
		out.append({"name": String(slot.name), "slot": slot.position, "radius": radius,
			"speed": float(member.get(&"config").assault_drift_speed), "variants": variants})
		member.free()
	preset.free()
	_group_cache[path] = out
	return out


## A turret-group member's worst-case Assault life from its line's spawn moment (see the section header).
func _member_life(design_y: float, member: Dictionary) -> float:
	var world: Rect2 = _ph8_lives()["world"]
	var highest_view_centre: float = world.get_center().y - ArenaCamera.V_LIMIT - _CAMERA_SHAKE._MAX_OFFSET
	var y_spawn: float = highest_view_centre + design_y * ArenaCamera.WORLD_SCALE + (member["slot"] as Vector2).y
	return _TICK_SLACK + (world.end.y - y_spawn) / float(member["speed"])


func _is_turret_group(path: String) -> bool:
	return path.begins_with(_TURRET_GROUP_DIR)


## One `{ "start", "end", "kind" }` per ship the section's Ph8 lines spawn (see the section header).
func _ph8_intervals(section: LevelSection) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var effective := -INF
	for wave: WaveResource in section.waves:
		effective = maxf(effective, wave.trigger_time)
		for entry: SpawnEntryResource in wave.entries:
			var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
			var t: float = effective + entry.spawn_delay
			if _is_turret_group(path):
				for m: Dictionary in _group_members(path):
					out.append({"start": t, "end": t + _member_life(entry.base_offset.y, m), "kind": "TURRET_MEMBER"})
			elif path == _TWIN_PAIR:
				var lives := _ph8_lives()
				for i in 2:
					out.append({"start": t, "end": t + float(lives["drone"]), "kind": "TWIN_DRONE"})
			elif path == _LASER_TENDER:
				var lives := _ph8_lives()
				out.append({"start": t, "end": t + float(lives["tender"]), "kind": "LASER_TENDER"})
				for i in 2:
					out.append({"start": t, "end": t + float(lives["launch_latest"]) + float(lives["drone"]),
						"kind": "TENDER_DRONE"})
	return out


func _actual_ph8_spawns(sections: Array[LevelSection]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _PH8_KIND_NAMES.has(path) and not _is_turret_group(path):
					continue
				assert_null(entry.formation, "no Phase 8 line uses a formation; the pin has no formation column")
				out.append({"section": section.section_name, "kind": _PH8_KIND_NAMES.get(path, path.get_file()),
					"trigger": wave.trigger_time, "offset": entry.base_offset, "delay": entry.spawn_delay})
	return out


func test_pinned_phase8_spawns_match_todays_data() -> void:
	var actual := _actual_ph8_spawns(_build_sections())
	assert_eq(actual.size(), EXPECTED_PH8.size(), "the number of turret group / twin pair / tender / fence entries changed")
	assert_eq(actual, EXPECTED_PH8, "a Phase 8 spawn's section, trigger, offset or delay changed")


## 3 rows: the group and the pair in deep_space, the tender in planet_approach, none in an ENEMIES_CLEARED section
## (`test_engagement_deadline.gd` says why), and each shares its wave with other traffic (no new wave, no moved trigger).
func test_the_phase8_pin_itself_is_internally_consistent() -> void:
	var by_section: Dictionary = {}
	var by_kind: Dictionary = {}
	for row: Dictionary in EXPECTED_PH8:
		by_section[row["section"]] = int(by_section.get(row["section"], 0)) + 1
		by_kind[row["kind"]] = int(by_kind.get(row["kind"], 0)) + 1
	assert_eq(EXPECTED_PH8.size(), 3)
	assert_eq(int(by_section.get(&"deep_space", 0)), 2, "deep_space Phase 8 row count changed")
	assert_eq(int(by_section.get(&"planet_approach", 0)), 1, "planet_approach Phase 8 row count changed")
	assert_eq(by_section.size(), 2, "Phase 8 lines spawn only in deep_space and planet_approach")
	for kind: String in ["TURRET_GROUP_ASSAULT_PAIR", "TWIN_LASER_PAIR", "LASER_TENDER"]:
		assert_eq(int(by_kind.get(kind, 0)), 1, "one %s line" % kind)
	var checked := 0
	for section: LevelSection in _build_sections():
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _PH8_KIND_NAMES.has(path) and not _is_turret_group(path):
					continue
				checked += 1
				assert_eq(section.end_condition, LevelSection.EndCondition.DURATION, "%s is a DURATION section"
					% section.section_name)
				assert_gt(wave.entries.size(), 1, "%s @ %.1f s: the Phase 8 line joins a wave that already existed" % [
					section.section_name, wave.trigger_time])
	assert_eq(checked, 3, "sanity: all three Phase 8 lines were checked")


## Boundary: a Phase 8 line's delay changed in memory must not match the pin (fresh sections; nothing shared mutated).
func test_a_phase8_lines_delay_changed_fails_the_pin() -> void:
	for path: String in [WaveBuilder.TURRET_GROUP_ASSAULT_PAIR, _TWIN_PAIR, _LASER_TENDER]:
		var sections := _build_sections()
		var mutated := false
		for section: LevelSection in sections:
			for wave: WaveResource in section.waves:
				for entry: SpawnEntryResource in wave.entries:
					if not mutated and entry.ship_scene and entry.ship_scene.resource_path == path:
						entry.spawn_delay += 1.0
						mutated = true
		assert_true(mutated, "sanity: level 1 has a %s line to mutate" % _PH8_KIND_NAMES[path])
		assert_ne(_actual_ph8_spawns(sections), EXPECTED_PH8, "a %s line with a changed delay must not match the pin"
			% _PH8_KIND_NAMES[path])


## No Phase 8 line has a rail (`.move()`, `.free_after()` or `.shoot_*()`).
func test_phase8_lines_have_no_rail() -> void:
	var sections := _build_sections()
	assert_eq(_actual_ph8_spawns(sections).size(), 3, "sanity: three Phase 8 lines")
	assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH8_KIND_NAMES), [] as Array[String],
		"these Phase 8 lines have .move(), .free_after() or shoot_*()")


## Boundary: each Phase 8 line given `.move()` is reported by the same check, and only that line.
func test_a_phase8_line_given_move_fails_the_no_rail_check() -> void:
	for path: String in [WaveBuilder.TURRET_GROUP_ASSAULT_PAIR, _TWIN_PAIR, _LASER_TENDER]:
		var sections := _build_sections()
		var mutated := false
		for section: LevelSection in sections:
			for wave: WaveResource in section.waves:
				for entry: SpawnEntryResource in wave.entries:
					if not mutated and entry.ship_scene and entry.ship_scene.resource_path == path:
						entry.movement = StraightMovement.new()
						mutated = true
		assert_true(mutated, "sanity: level 1 has a %s line to mutate" % _PH8_KIND_NAMES[path])
		assert_eq(_rail_rows(sections, MIGRATED_SECTIONS, _PH8_KIND_NAMES).size(), 1,
			"a %s line with .move() must be reported" % _PH8_KIND_NAMES[path])


## The four Ph8 lives, printed, with the plan's figures as sanity (each term is read, never typed: these only catch a
## silently changed config or a probe that measured nothing). Members: the ring turret (slot y -60) drifts longest.
func test_phase8_lives_are_the_plans_figures() -> void:
	var lives := _ph8_lives()
	gut.p("Ph8 lives: drone %.2f s (engage %.2f + telegraph %.2f + max_advance %.2f + slack + exit bound %.2f); tender %.2f s (latest launch %.2f + exit %.2f); tender drone up to %.2f s after the tender's spawn"
		% [lives["drone"], _DRONE_CONFIG.engage_seconds, lives["telegraph"], lives["max_advance"], lives["drone_exit"],
		lives["tender"], lives["launch_latest"], lives["tender_exit"], float(lives["launch_latest"]) + float(lives["drone"])])
	assert_almost_eq(float(lives["max_advance"]), 1.92, 0.01, "(max(260, 180) + 200) / 240")
	assert_gt(float(lives["drone_exit"]), 0.0, "sanity: the drone exit bound was measured")
	assert_gt(float(lives["tender_exit"]), 0.0, "sanity: the tender exit was measured")
	assert_gt(float(lives["telegraph"]), 0.0, "sanity: the twin beam's telegraph was read from twin_beam.tscn")
	var members := _group_members(WaveBuilder.TURRET_GROUP_ASSAULT_PAIR)
	assert_eq(members.size(), 3, "sanity: assault_pair has three members")
	for m: Dictionary in members:
		gut.p("assault_pair %s (slot %s, r %.0f): drift life %.2f s from a -220 design-y spawn" % [m["name"], m["slot"],
			m["radius"], _member_life(-220.0, m)])
		assert_gt(float(m["speed"]), 0.0, "%s drifts" % m["name"])
		assert_lte(_member_life(-220.0, m), 28.2 + _TICK_SLACK + 0.01, "%s: the plan's <= 28.2 s drift life" % m["name"])


func _curve_text(intervals: Array[Dictionary]) -> String:
	var times: Array[float] = []
	for a: Dictionary in intervals:
		for key: String in ["start", "end"]:
			if not times.has(float(a[key])):
				times.append(float(a[key]))
	times.sort()
	var parts: PackedStringArray = []
	var last := -1
	for t in times:
		var alive := 0
		var ph8 := 0
		for a: Dictionary in intervals:
			if float(a["start"]) <= t and t < float(a["end"]):
				alive += 1
				if _PH8_INTERVAL_KINDS.has(a["kind"]):
					ph8 += 1
		if alive != last:
			parts.append("%.2f:%d%s" % [t, alive, " (ph8 %d)" % ph8 if ph8 > 0 else ""])
			last = alive
	return ", ".join(parts)


## The alive curves (the acceptance criteria's "curves printed"): every change of the alive count in each migrated
## section, Ph8 ships marked; the Ph8 intervals exist (3 members + 2 drones in deep_space, the tender + 2 drones in
## planet_approach) and the peak stays within the frozen 2.5x (the gate above, restated where the curve is printed).
func test_ph8_alive_curves_are_printed() -> void:
	var lives := _ai_lives()
	var expected_ph8 := {&"deep_space": 5, &"planet_approach": 3, &"cloud_descent": 0}
	for section: LevelSection in _build_sections():
		if not MIGRATED_SECTIONS.has(section.section_name):
			continue
		var intervals := _ai_intervals(section, lives)
		var ph8 := intervals.filter(func(a: Dictionary) -> bool: return _PH8_INTERVAL_KINDS.has(a["kind"]))
		var peak := _peak(intervals)
		var limit := _COUNT_RATIO * int(_LEGACY_PEAK_SPECIALISTS[section.section_name])
		gut.p("%s alive curve (peak %d at %.2f s, limit %.1f): %s" % [section.section_name, peak["count"], peak["at"], limit,
			_curve_text(intervals)])
		assert_eq(ph8.size(), int(expected_ph8[section.section_name]), "%s: Phase 8 ships counted" % section.section_name)
		assert_lte(float(peak["count"]), limit, "%s: peak alive within %.1fx legacy" % [section.section_name, _COUNT_RATIO])


const _LEVEL_SCENE := "res://assault/scenes/levels/edelia/1/level_1.tscn"


## Level 1's static `LaserWallWave` as one schedule row for the FIRST section (it is placed in `level_1.tscn`, not in
## `laser_column_schedule()`, and lights at level start: lethal from its warning's end for its `active_duration`, all
## inside deep_space while a member drifts): `{ "time": 0.0, "columns": [world x of each ray], "source": "wall" }`, read
## from the level scene's state (never instantiated) and the wall scene's rays. Cached.
func _wall_wave_row() -> Dictionary:
	if _group_cache.has(&"wall"):
		return _group_cache[&"wall"]
	var state := (load(_LEVEL_SCENE) as PackedScene).get_state()
	var origin := Vector2.INF
	var wall_scene: PackedScene = null
	for i in state.get_node_count():
		if state.get_node_name(i) != &"LaserWallWave":
			continue
		wall_scene = state.get_node_instance(i)
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"position":
				origin = state.get_node_property_value(i, p)
	assert_not_null(wall_scene, "sanity: level_1.tscn places a LaserWallWave")
	assert_true(origin.is_finite(), "sanity: the LaserWallWave has a position")
	var columns: Array[int] = []
	if wall_scene != null and origin.is_finite():
		var wall := wall_scene.instantiate()
		for ray in wall.get_children():
			if ray is LaserRay:
				assert_almost_eq((ray as Node2D).rotation, 0.0, 0.0001, "sanity: a vertical wall ray")
				columns.append(roundi(origin.x + (ray as Node2D).position.x))
		wall.free()
	var row := {"time": 0.0, "columns": columns, "source": "wall"}
	_group_cache[&"wall"] = row
	return row


## Every static member of every turret-group line against every column of `Level1Director.laser_column_schedule()` in
## its section that starts before the member is gone (no end filter: the beam turns lethal only after its charge-up, so
## any column lit before the member leaves may still be lit while it lives). A member is at world x `world centre x +
## design x * WORLD_SCALE + slot x` (world-anchored, `TurretGroup._ready()`), and survives only at `|x - column| >=
## LaserRay._BEAM_WIDTH / 2 + body radius`. The first section also gets `_wall_wave_row()` (the level-start wall).
## Returns `{ "checked", "conflicts" }`.
func _column_conflicts(sections: Array[LevelSection]) -> Dictionary:
	var schedule: Dictionary = load(_DIRECTOR_SCRIPT).laser_column_schedule()
	var world: Rect2 = _ph8_lives()["world"]
	var half := LaserRay._BEAM_WIDTH * 0.5
	var checked := 0
	var conflicts: Array[String] = []
	for section: LevelSection in sections:
		var rows: Array = (schedule.get(section.section_name, []) as Array).duplicate()
		if section == sections[0]:
			rows.append(_wall_wave_row())
		var effective := -INF
		for wave: WaveResource in section.waves:
			effective = maxf(effective, wave.trigger_time)
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _is_turret_group(path):
					continue
				var t: float = effective + entry.spawn_delay
				for m: Dictionary in _group_members(path):
					var x: float = world.get_center().x + entry.base_offset.x * ArenaCamera.WORLD_SCALE + (m["slot"] as Vector2).x
					var end := t + _member_life(entry.base_offset.y, m)
					var need: float = half + float(m["radius"])
					for row: Dictionary in rows:
						if float(row["time"]) >= end:
							continue
						for col in row["columns"]:
							checked += 1
							if absf(x - float(col)) < need:
								conflicts.append("%s %s at x %.0f (alive %.2f-%.2f s) vs the %.1f s %s at %d: %.0f < %.0f px" % [
									section.section_name, m["name"], x, t, end, row["time"], row.get("source", "column"), col,
									absf(x - float(col)), need])
	return {"checked": checked, "conflicts": conflicts}


func test_ph8_static_members_clear_every_lit_column() -> void:
	var sections := _build_sections()
	for section: LevelSection in sections:
		assert_false(_section_has_path(section, WaveBuilder.LASER_FENCE),
			"%s places a laser fence; this row covers group members only" % section.section_name)
	var result := _column_conflicts(sections)
	gut.p("column clearance: %d member x column pairs checked" % result["checked"])
	var wall_rays: int = (_wall_wave_row()["columns"] as Array).size()
	assert_eq(wall_rays, 12, "sanity: the LaserWallWave has twelve rays")
	assert_eq(int(result["checked"]), 3 * (8 + wall_rays),
		"sanity: three members x (deep_space's eight columns + the wall's rays), all lit before they leave")
	assert_eq(result["conflicts"], [] as Array[String], "these static members sit in a lit laser column")


## Boundary (t19's own finding): the epic plan's `.at(-64, -220)` clears every scheduled column but puts all three members
## inside the level-start LaserWallWave (x 0-672), where `scripts/measure-level1-columns.sh` saw both turrets die.
func test_the_plans_minus_64_placement_fails_on_the_wall_wave() -> void:
	var sections := _build_sections()
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene and entry.ship_scene.resource_path == WaveBuilder.TURRET_GROUP_ASSAULT_PAIR:
					entry.base_offset = Vector2(-64.0, -220.0)
	var result := _column_conflicts(sections)
	gut.p("plan placement (-64, -220): %s" % [result["conflicts"]])
	var wall_hits := (result["conflicts"] as Array).filter(func(c: String) -> bool: return c.contains(" wall at "))
	var column_hits := (result["conflicts"] as Array).filter(func(c: String) -> bool: return c.contains(" column at "))
	assert_eq(column_hits.size(), 0, "the plan's placement does clear every scheduled column")
	for member: String in ["BurstTurret", "RingTurret", "PowerSource"]:
		assert_true(wall_hits.any(func(c: String) -> bool: return c.contains(member)), "%s is inside the wall wave" % member)


## Boundary (acceptance criterion): revision 1's `.at(0, -220)` puts the power source on deep_space's 640 column.
func test_revision_1_group_placement_fails_the_column_row() -> void:
	var sections := _build_sections()
	var moved := false
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				if entry.ship_scene and entry.ship_scene.resource_path == WaveBuilder.TURRET_GROUP_ASSAULT_PAIR:
					entry.base_offset = Vector2(0.0, -220.0)
					moved = true
	assert_true(moved, "sanity: level 1 has a turret-group line to move")
	var result := _column_conflicts(sections)
	gut.p("revision 1 placement: %s" % [result["conflicts"]])
	assert_gt((result["conflicts"] as Array).size(), 0, "the revision-1 placement must fail the column row")
	var hits_power_source := false
	for c: String in result["conflicts"]:
		if c.contains("PowerSource") and c.contains("column at 640"):
			hits_power_source = true
	assert_true(hits_power_source, "the power source on the 640 column is the conflict")


func _section_has_path(section: LevelSection, path: String) -> bool:
	for wave: WaveResource in section.waves:
		for entry: SpawnEntryResource in wave.entries:
			if entry.ship_scene and entry.ship_scene.resource_path == path:
				return true
	return false


# ── Spill-over (§2.18) ────────────────────────────────────────────────────────────────────────────────────────────
#
# `LevelDirector` loads a section's waves the moment the section starts (`transition_in_duration` is the background's
# fade only), and an ENEMIES_CLEARED section waits for the enemy container to empty after its last wave triggers. So a
# specialist from a DURATION section must be gone — and, for a corvette, its last rocket too (rockets sit in the
# container) — before the next ENEMIES_CLEARED section's last effective trigger, counted from the DURATION section's
# start through every section in between. planet_approach -> cloud_descent is the acceptance row; deep_space ->
# station_assault (through asteroid_belt) is checked by the same predicate. Scope: the specialists, the two new kinds
# included; drones, fighters and Gatlings are bounded by their own level-1 gates and this task does not move them.

## The longest any corvette rocket (or a Cluster's submunitions) can stay in the container, read from the rocket scenes.
func _rocket_max_life() -> float:
	var life := 0.0
	for kind: EnemyRocket.Kind in [EnemyRocket.Kind.DUMB, EnemyRocket.Kind.PURSUIT, EnemyRocket.Kind.CLUSTER,
			EnemyRocket.Kind.WARHEAD]:
		life = maxf(life, EnemyRocketScenes.max_time_of(kind))
	var split := float(EnemyRocketScenes.export_of(EnemyRocket.Kind.CLUSTER, &"split_time", 0.0))
	return maxf(life, split + EnemyRocketScenes.max_time_of(EnemyRocket.Kind.SUBMUNITION))


## Seconds from the start of `sections[index]` to the last effective wave trigger of the next ENEMIES_CLEARED section
## (`INF` if none follows).
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


## How long a kind's ordnance outlives it in the container: a corvette's rockets, a Mine Layer's mines (their Assault
## `assault_mine_life`, counted as a rocket life is). Nothing else persists.
func _ordnance_tail(kind: String, rocket_life: float) -> float:
	if kind == "MISSILE_CORVETTE":
		return rocket_life
	return _LAYER_CONFIG.assault_mine_life if kind == "MINE_LAYER" else 0.0


## The intervals (plus a corvette's rocket life, a layer's mine life) still alive at `deadline`, as readable strings.
func _spills(intervals: Array[Dictionary], deadline: float, rocket_life: float) -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in intervals:
		var end: float = float(a["end"]) + _ordnance_tail(a["kind"], rocket_life)
		if end >= deadline:
			out.append("%s spawned %.2f s, gone %.2f s >= %.2f s" % [a["kind"], a["start"], end, deadline])
	return out


func test_no_specialist_outlives_the_next_enemies_cleared_sections_last_trigger() -> void:
	var lives := _ai_lives()
	var rocket_life := _rocket_max_life()
	var sections := _build_sections()
	var checked := 0
	for i in sections.size():
		var section := sections[i]
		if not [&"deep_space", &"planet_approach"].has(section.section_name):
			continue
		checked += 1
		assert_eq(section.end_condition, LevelSection.EndCondition.DURATION, "sanity: %s is a DURATION section"
			% section.section_name)
		var deadline := _next_cleared_deadline(sections, i)
		var intervals := _ai_intervals(section, lives)
		var latest := 0.0
		for a: Dictionary in intervals:
			latest = maxf(latest, float(a["end"]) + _ordnance_tail(a["kind"], rocket_life))
		gut.p("%s: last specialist (or rocket) gone %.2f s after the section starts; next ENEMIES_CLEARED last trigger at %.2f s"
			% [section.section_name, latest, deadline])
		assert_lt(deadline, INF, "sanity: an ENEMIES_CLEARED section follows %s" % section.section_name)
		assert_eq(_spills(intervals, deadline, rocket_life), [] as Array[String],
			"%s: these are still alive when the next ENEMIES_CLEARED section's last wave triggers" % section.section_name)
	assert_eq(checked, 2, "sanity: deep_space and planet_approach were checked")


## Boundary: a synthetic corvette whose own life ends just before planet_approach's deadline is still flagged once its
## rocket life is added, and one ending well before is not — the predicate counts the rocket term.
func test_a_corvette_whose_rockets_cross_the_deadline_is_flagged() -> void:
	var lives := _ai_lives()
	var rocket_life := _rocket_max_life()
	var sections := _build_sections()
	var index := sections.find(_section(sections, &"planet_approach"))
	var deadline := _next_cleared_deadline(sections, index)
	assert_almost_eq(deadline, 186.0, 0.001, "sanity: planet_approach's 110 s + cloud_descent's 76 s last trigger")
	var life: float = lives[_MISSILE_CORVETTE]["life"]
	var late: Array[Dictionary] = [{"start": deadline - life - 1.0, "end": deadline - 1.0, "kind": "MISSILE_CORVETTE"}]
	var early: Array[Dictionary] = [{"start": 0.0, "end": deadline - rocket_life - 1.0, "kind": "MISSILE_CORVETTE"}]
	assert_eq(_spills(late, deadline, rocket_life).size(), 1, "a corvette whose rockets outlive the deadline is flagged")
	assert_eq(_spills(early, deadline, rocket_life).size(), 0, "one whose rockets are gone in time is not")


## Boundary: a synthetic Mine Layer that has itself left by 1 s before the deadline is still flagged once its mines'
## `assault_mine_life` is added, and one whose mines are gone in time is not — the predicate counts the mine term.
func test_a_mine_layer_whose_mines_cross_the_deadline_is_flagged() -> void:
	var rocket_life := _rocket_max_life()
	var sections := _build_sections()
	var index := sections.find(_section(sections, &"planet_approach"))
	var deadline := _next_cleared_deadline(sections, index)
	var mine_life := _LAYER_CONFIG.assault_mine_life
	assert_gt(mine_life, 1.0, "sanity: the shipped Assault mine life is real")
	var late: Array[Dictionary] = [{"start": 0.0, "end": deadline - 1.0, "kind": "MINE_LAYER"}]
	var early: Array[Dictionary] = [{"start": 0.0, "end": deadline - mine_life - 1.0, "kind": "MINE_LAYER"}]
	assert_eq(_spills(late, deadline, rocket_life).size(), 1, "a layer whose mines outlive the deadline is flagged")
	assert_eq(_spills(early, deadline, rocket_life).size(), 0, "one whose mines are gone in time is not")


## The pools of the turret mounts `variants` build (`TurretMount.pool_specs()`, read off-tree from each variant's mount
## scene) whose ordnance outlives its owner, as "variant: pool" strings.
func _persisting_pools(variants: Array[int]) -> Array[String]:
	var out: Array[String] = []
	for v in variants:
		var scene := TurretMountScenes.scene_for(v)
		if scene == null:
			continue
		var mount := scene.instantiate() as TurretMount
		for spec: Dictionary in mount.pool_specs():
			if bool(spec.get("persist", false)):
				out.append("%s: %s" % [TurretMount.Variant.keys()[v], spec.get("name", "?")])
		mount.free()
	return out


## Phase 8 t19: no Ph8 ship leaves ordnance in the container (every mount of every placed group has `persist == false`
## pools; the ring is a mount child, the twin beam a child of drone A), so the predicate above needs no Ph8 tail term; and
## the Ph8 ships' own latest ends, printed, clear the next ENEMIES_CLEARED section's last trigger.
func test_ph8_ships_leave_no_ordnance_and_clear_the_next_cleared_section() -> void:
	var sections := _build_sections()
	var groups := 0
	for section: LevelSection in sections:
		for wave: WaveResource in section.waves:
			for entry: SpawnEntryResource in wave.entries:
				var path: String = entry.ship_scene.resource_path if entry.ship_scene else ""
				if not _is_turret_group(path):
					continue
				groups += 1
				for m: Dictionary in _group_members(path):
					assert_gt((m["variants"] as Array).size() + (1 if m["name"] == "PowerSource" else 0), 0,
						"sanity: %s has a mount (or is the power source)" % m["name"])
					assert_eq(_persisting_pools(m["variants"]), [] as Array[String],
						"%s's mounts leave ordnance behind" % m["name"])
	assert_eq(groups, 1, "sanity: level 1 places one turret group")
	var checked := 0
	for i in sections.size():
		var section := sections[i]
		if not [&"deep_space", &"planet_approach"].has(section.section_name):
			continue
		checked += 1
		var deadline := _next_cleared_deadline(sections, i)
		var latest := 0.0
		for a: Dictionary in _ph8_intervals(section):
			latest = maxf(latest, float(a["end"]))
			assert_eq(_ordnance_tail(a["kind"], 0.0), 0.0, "%s carries no ordnance tail" % a["kind"])
		gut.p("%s: last Phase 8 ship gone %.2f s after the section starts; next ENEMIES_CLEARED last trigger at %.2f s"
			% [section.section_name, latest, deadline])
		assert_gt(latest, 0.0, "sanity: %s has Phase 8 ships" % section.section_name)
		assert_lt(latest, deadline, "%s: a Phase 8 ship outlives the next ENEMIES_CLEARED section's last trigger"
			% section.section_name)
	assert_eq(checked, 2, "sanity: deep_space and planet_approach were checked")


## Boundary for the persist check: a ROCKET_BATTERY mount's rocket pools do persist (`persist_after_owner_death`), so a
## group carrying one would need a rocket tail here, and the check above would say so.
func test_a_rocket_battery_mounts_pools_persist() -> void:
	var variants: Array[int] = [TurretMount.Variant.ROCKET_BATTERY]
	var persisting := _persisting_pools(variants)
	gut.p("ROCKET_BATTERY persisting pools: %s" % [persisting])
	assert_gt(persisting.size(), 0, "a rocket battery's pools persist after its turret dies")
