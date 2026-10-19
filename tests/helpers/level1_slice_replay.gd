## A slice of a level-1 section replayed through a real `WaveManager` (Enemy rework phase 5, t17; epic plan
## docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md §2.18, task plan docs/plans/cmv9szqmi002zqs2x3cd8f942/3-plan.md).
##
## The attack-in-budget rows of the Missile Corvette and the Support Ship each replay only `rel - PRE_ROLL ..
## rel + engage_seconds + POST_ROLL` of the section their placed spawn lives in, never the whole section (§4.3: the
## t17 time allotment). Every wave whose EFFECTIVE trigger (the running max in list order — `WaveManager` triggers
## strictly in list order, the Ph3 wave-order quirk) falls in that window is kept, in list order, re-timed to the
## window's start, with ALL its entries: the support needs the real allies it arrives with, and the corvette fights
## among the real traffic of its moment. Ships spawned before the window are not in it — a stated simplification.
##
## The world is the shape `test_level1_specialist_exit.gd` uses: `HARNESS.assault()` (a real `ArenaCamera`, so the
## corridor, the view rect and the world rect are live), a stationary hurtbox-less player stub at the lower centre of
## the view (nothing can end early by hitting it), every brain seeded from its spawn index before its `_ready()`.
## The CALLER owns the 8x clock (scale it before `run()`, restore it in `after_each`); `run()` lets three idle frames
## pass before `load_section()` so a catch-up burst cannot land on wave 0, stops as soon as the caller's condition
## holds, and then steps on until every triggered spawn timer has fired (an unfired `SceneTreeTimer` is a leak).
##
## No `class_name`: test-only. `preload` it.
extends RefCounted

const HARNESS: GDScript = preload("res://tests/helpers/enemy_ai_harness.gd")
const DIRECTOR_SCRIPT: GDScript = preload("res://assault/scenes/levels/edelia/1/level_1_director.gd")

## The window opens this long before the placed spawn and closes this long after its budget (§2.18).
const PRE_ROLL := 1.0
const POST_ROLL := 2.0
## Where the stationary player stub sits, from the camera centre (the lower centre of the view, as the other replays).
const PLAYER_OFFSET := Vector2(0.0, 250.0)
## Non-zero: an `rng_seed` of 0 means "randomize".
const SEED_BASE := 5171
## Run this long past the last spawn of a triggered wave so its timer has certainly fired.
const SPAWN_SETTLE := 0.1

var _target_path: String = ""
var _target: BaseEnemy = null
var _tweak: Callable = Callable()
var _pending: float = 0.0
var _waves: Array[WaveResource] = []
var _targets_spawned: int = 0
var _spawned: int = 0


## A freshly built section (each call builds new resources; nothing shipped is shared or mutated).
static func section(section_name: StringName) -> LevelSection:
	var d: Node = DIRECTOR_SCRIPT.new()
	var out: LevelSection = null
	for s in d._build_sections():
		if (s as LevelSection).section_name == section_name:
			out = s
	d.free()
	return out


## One `{ "section", "trigger", "delay", "offset", "rel" }` per spawn of `scene_path` in level 1, in encounter order.
## `trigger` is the wave's effective trigger; `rel` = trigger + delay, the spawn moment in section time. No formations
## (the new lines use none; asserted by the pin).
static func placed(scene_path: String) -> Array[Dictionary]:
	var d: Node = DIRECTOR_SCRIPT.new()
	var out: Array[Dictionary] = []
	for s in d._build_sections():
		var sec: LevelSection = s
		var effective := -INF
		for w in sec.waves:
			var wave: WaveResource = w
			effective = maxf(effective, wave.trigger_time)
			for e in wave.entries:
				var entry: SpawnEntryResource = e
				if entry.ship_scene == null or entry.ship_scene.resource_path != scene_path:
					continue
				out.append({"section": sec.section_name, "trigger": effective, "delay": entry.spawn_delay,
					"offset": entry.base_offset, "rel": effective + entry.spawn_delay})
	d.free()
	return out


## The waves of `sec` whose effective trigger lies in [from, to), in list order, re-timed by −from. New
## `WaveResource`s; the entries are the section's own (read, never written).
static func slice_waves(sec: LevelSection, from: float, to: float) -> Array[WaveResource]:
	var out: Array[WaveResource] = []
	var effective := -INF
	for w in sec.waves:
		var wave: WaveResource = w
		effective = maxf(effective, wave.trigger_time)
		if effective < from or effective >= to:
			continue
		var copy := WaveResource.new()
		copy.trigger_time = effective - from
		var entries: Array[SpawnEntryResource] = []
		entries.assign(wave.entries)
		copy.entries = entries
		out.append(copy)
	return out


## The latest spawn moment in `waves` (trigger + delay + formation slot delay), in slice time.
static func last_spawn(waves: Array[WaveResource]) -> float:
	var latest := 0.0
	for wave in waves:
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			var delay := entry.spawn_delay
			if entry.formation != null:
				for slot in entry.formation.compute_slots():
					delay = maxf(delay, entry.spawn_delay + (slot as FormationResource.FormationSlot).delay)
			latest = maxf(latest, wave.trigger_time + delay)
	return latest


## Replays `waves` for up to `length` game seconds (summed physics delta) in a fresh Assault world under `host`, and
## calls `observe.call(ship, t) -> bool` on every physics frame once the first ship of `target_path` has spawned
## (`ship` is null once it has left the tree; `t` is slice time). The replay STOPS on the first frame `observe`
## returns true, or at `length`. `tweak.call(ship)`, when valid, runs on each ship of `target_path` as it enters the
## tree: after `_enter_tree()`'s `ShipConfig.privatise()` and before any `_ready()`, so it may edit that ship's PRIVATE
## config (never the shared `.tres`). Before returning, the `WaveManager` is switched off and the world keeps
## stepping until every spawn timer of an already-triggered wave has fired (an unfired `SceneTreeTimer` is a leak),
## then the world is freed. Returns `{ "targets": ships of `target_path` spawned, "spawned": all ships, "t": slice
## time at the stop, "stopped": whether `observe` returned true }`.
func run(host: Node, waves: Array[WaveResource], length: float, target_path: String, observe: Callable,
		tweak: Callable = Callable()) -> Dictionary:
	_target_path = target_path
	_tweak = tweak
	_target = null
	_targets_spawned = 0
	_spawned = 0
	_pending = 0.0
	_waves = waves
	var harness: RefCounted = HARNESS.assault()
	host.add_child(harness.root)
	var cam := harness.root.get_node("ArenaCamera") as Camera2D
	cam.make_current()
	harness.player.global_position = cam.global_position + PLAYER_OFFSET
	var container := Node2D.new()
	container.name = "EnemyContainer"
	harness.root.add_child(container)
	container.child_entered_tree.connect(_on_child_entered)
	var wm := WaveManager.new()
	wm.enemy_container = container
	harness.root.add_child(wm)
	wm.wave_triggered.connect(_on_wave_triggered)

	for i in 3:
		await host.get_tree().process_frame
	wm.load_section(waves)
	var t := 0.0
	var stopped := false
	while t < length and not stopped:
		await host.get_tree().physics_frame
		t += host.get_physics_process_delta_time()
		if _targets_spawned > 0:
			var ship: BaseEnemy = _target if is_instance_valid(_target) and _target.is_inside_tree() else null
			stopped = bool(observe.call(ship, t))
	var stop_t := t
	wm.set_process(false)
	while t < _pending + SPAWN_SETTLE:
		await host.get_tree().physics_frame
		t += host.get_physics_process_delta_time()
	container.child_entered_tree.disconnect(_on_child_entered)
	harness.root.queue_free()
	await host.get_tree().process_frame
	return {"targets": _targets_spawned, "spawned": _spawned, "t": stop_t, "stopped": stopped}


## The latest spawn moment of any triggered wave, so `run()` knows how long its spawn timers still need.
func _on_wave_triggered(wave_index: int) -> void:
	var one: Array[WaveResource] = [_waves[wave_index]]
	_pending = maxf(_pending, last_spawn(one))


## Seeds every ship's brain before its `_ready()` (`child_entered_tree` fires on `add_child`, after `_enter_tree()`
## and before the subtree is ready), applies the tweak to every ship of the target kind and remembers the first.
func _on_child_entered(node: Node) -> void:
	if not node is BaseEnemy:
		return
	var brain := node.get_node_or_null("Brain") as EnemyBrain
	if brain != null:
		brain.rng_seed = SEED_BASE + _spawned
	_spawned += 1
	if node.scene_file_path == _target_path:
		_targets_spawned += 1
		if _tweak.is_valid():
			_tweak.call(node)
		if _target == null:
			_target = node as BaseEnemy
