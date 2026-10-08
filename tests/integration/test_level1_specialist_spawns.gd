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
## data. t21 removes deep_space and planet_approach and t22 removes cloud_descent (once a section has no rail left
## there is nothing to recompute the constant FROM; its count gate divides by it instead).
const _RAIL_SECTIONS: Array[StringName] = [&"deep_space", &"planet_approach", &"cloud_descent"]


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
	# Never vacuous: every frozen constant must be live-checked here until its section is migrated.
	for key: StringName in _LEGACY_PEAK_SPECIALISTS:
		assert_true(_RAIL_SECTIONS.has(key), "frozen constant for %s is not live-checked" % key)


## Boundary: the live computation can reject. Extra rams dropped on a rail section's first specialist moment raise
## that section's peak, so it no longer equals the frozen constant.
func test_extra_rams_at_the_peak_break_the_frozen_constant() -> void:
	var cam := ArenaCamera.new()
	add_child_autofree(cam)
	var checked := false
	for section: LevelSection in _build_sections():
		if section.section_name != &"planet_approach":
			continue
		checked = true
		var before := _live_peak(section, cam)
		assert_eq(before, int(_LEGACY_PEAK_SPECIALISTS[&"planet_approach"]))
		var trigger := 0.0
		for row: Dictionary in EXPECTED:
			if row["section"] == &"planet_approach":
				trigger = row["trigger"]
				break
		var b := WaveBuilder.new()
		var extra: Array = []
		for i in before + 1:
			extra.append(b.ram().at(0, -400).move(b.straight(300)))
		section.waves.append(b.wave(trigger, extra))
		assert_gt(_live_peak(section, cam), before, "an added ram wave must raise the live peak")
	assert_true(checked, "sanity: level 1 has planet_approach")


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
