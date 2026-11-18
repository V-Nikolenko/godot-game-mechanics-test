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
## "Fired" is counted, not timed: every spawn of a triggered wave must have arrived through `WaveManager.enemy_spawned`
## before the world is freed. A spawn timer runs on idle time and `t` sums physics time; at the 16x clock one idle frame
## is ~0.3 game s, so a physics-time margin alone sometimes freed the `WaveManager` with a delayed spawn still waiting,
## and the stranded timer kept that ship's scene alive to process exit (Phase 9 t1: the intermittent
## `test_level1_ph8_attacks.gd` "resources still in use at exit" leak that failed the gate with every test green).
##
## **Lit replays (Phase 10 t11, task plan docs/plans/cmwafsrbi00azqs2yuwzayuk3/3-plan.md §2).** `light_lasers` (default false: every caller that
## does not set it runs exactly the code path above) lights the real lasers of `lit_section` on the slice timeline: the director's own
## `_spawn_laser_columns()` (on a `set_script` spawner, so `COLUMN_WARN_SECONDS` / `COLUMN_ACTIVE_SECONDS` apply) fires each row of
## `Level1Director.laser_column_schedule()` when an IDLE-time clock reaches `row.time - lit_from` (`Level1Director._process` fires on idle time),
## and for deep_space the `LaserWallWave` that `level_1.tscn` places is added at the `load_section()` moment, as the level lights it at
## level start. A row (or the wall) that began before `lit_from` is relit only while it can still be lethal (`warm_start()`). Every
## `LaserRay` is tracked (its lethal window per physics tick, the largest idle delta around it), every death of a ship of `target_path`
## (hull `died`, each `Modules/*` `EnemyModule.destroyed`) is recorded with whether a LETHAL ray covered that node's hurtbox at that moment,
## and the smallest horizontal gap between each such ship's root hurtbox and a lit strip at its height. The CALLER caps
## `Engine.max_physics_steps_per_frame` for a lit run (the deep_space slice is CPU-bound at 16x: uncapped, its idle frames reach 2.13 game s
## and every laser edge reads seconds late).
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
## Run at least this long past the last spawn of a triggered wave (physics time; the arrival count below is the real
## condition).
const SPAWN_SETTLE := 0.1
## Give up this long past the last spawn of a triggered wave with spawns still missing, and report it (game seconds).
const SETTLE_CAP := 5.0
const LASER_SCENE: PackedScene = preload("res://assault/scenes/hazards/laser_ray/laser_ray.tscn")
const LEVEL_SCENE_PATH := "res://assault/scenes/levels/edelia/1/level_1.tscn"
## A ray relit at a slice start keeps at least this lethal span, else it is not relit (`warm_start()`).
const MIN_ACTIVE := 0.25

## Light `lit_section`'s real lasers on the slice timeline (header). Set on the instance before `run()`.
var light_lasers := false
## Whose column schedule (and, for deep_space, the level-start wall).
var lit_section: StringName = &""
## The slice's start in section time: slice time + `lit_from` = section time.
var lit_from := 0.0
## Lit runs: one `{ "ship", "what", "t", "covered", "source" }` per death of a ship of `target_path` (`ship` its spawn index, `what` "hull" or
## the part's `module_id`, `t` section time, `covered` a lethal ray's strip met that node's hurtbox, `source` "wall" / "column" / ""). Readable
## during the run (an `observe` may stop on it).
var deaths: Array[Dictionary] = []

var _target_path: String = ""
var _target: BaseEnemy = null
var _tweak: Callable = Callable()
var _pending: float = 0.0
var _waves: Array[WaveResource] = []
var _targets_spawned: int = 0
var _spawned: int = 0
## Spawns the triggered waves will make (formation slots expanded), and how many `WaveManager` has made so far.
var _scheduled: int = 0
var _arrived: int = 0
## Lit runs only (see `light_lasers`).
var _host: Node = null
var _slice_t: float = 0.0
var _rays: Array[Dictionary] = []
var _idle: Array[float] = []
var _lit_clock: float = 0.0
var _lit_pending: Array = []
var _lit_spawner: Node = null
var _lit_wall: Node = null
var _lit_row_time: float = 0.0
var _lit_targets: Array[Node] = []
var _clearance: Dictionary = {}
static var _timing: Dictionary = {}


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


## How many ships `waves` make through `WaveManager`: one per formation slot, one per plain entry, none for an entry
## with no scene (`_spawn_ship()` returns before spawning it).
static func spawn_count(waves: Array[WaveResource]) -> int:
	var n := 0
	for wave in waves:
		for e in wave.entries:
			var entry: SpawnEntryResource = e
			if entry.ship_scene == null:
				continue
			n += entry.formation.compute_slots().size() if entry.formation != null else 1
	return n


## `{ "init", "increase", "dissolve" }`: each `LaserRay` animation's length (s), read from `laser_ray.tscn`'s `SpriteFrames` (frame durations /
## speed). Cached.
static func ray_timing() -> Dictionary:
	if not _timing.is_empty():
		return _timing
	var ray := LASER_SCENE.instantiate()
	var frames: SpriteFrames = (ray.get_node(^"BeamSprite") as AnimatedSprite2D).sprite_frames
	for pair in [["init", &"laser_init"], ["increase", &"laser_increase"], ["dissolve", &"laser_dissolve"]]:
		var anim: StringName = pair[1]
		var total := 0.0
		for i in frames.get_frame_count(anim):
			total += frames.get_frame_duration(anim, i)
		_timing[pair[0]] = total / frames.get_animation_speed(anim)
	ray.free()
	return _timing


## A director column's whole lit window (s): warning, charge-up, lethal span and dissolve, at `_spawn_laser_columns()`'s defaults.
static func lit_seconds() -> float:
	var t := ray_timing()
	return DIRECTOR_SCRIPT.COLUMN_WARN_SECONDS + float(t["increase"]) + DIRECTOR_SCRIPT.COLUMN_ACTIVE_SECONDS + float(t["dissolve"])


## A director column turns lethal this long after its row fires (s).
static func column_lethal_offset() -> float:
	return DIRECTOR_SCRIPT.COLUMN_WARN_SECONDS + float(ray_timing()["increase"])


## How a ray that began `elapsed` s before the slice start is relit at it: `{}` = not lit, else `{ "warn", "active" }`. `warn` / `active` are
## the ray's own timings; its lethal span ends at `lethal_end = warn + increase + active`.
##   elapsed < warn (strict): still warning, so only the warning is shorter (exact);
##   else rest = lethal_end - elapsed - (init + increase) >= MIN_ACTIVE: warn 0, active rest (the relit ray replays init + increase first, so
##   it is lethal for a shorter span that ends on time). Never active <= 0, which a `LaserRay` reads as "never dissolve";
##   else (its lethal span is over or nearly over, dissolve included): not lit.
static func warm_start(elapsed: float, warn: float, active: float) -> Dictionary:
	if elapsed < warn:
		return {"warn": warn - elapsed, "active": active}
	var t := ray_timing()
	var rest := warn + float(t["increase"]) + active - elapsed - (float(t["init"]) + float(t["increase"]))
	if rest >= MIN_ACTIVE:
		return {"warn": 0.0, "active": rest}
	return {}


## `{ "scene", "position" }` of `level_1.tscn`'s `LaserWallWave`, read from the level scene's state (never instantiated).
static func wall_placement() -> Dictionary:
	var state := (load(LEVEL_SCENE_PATH) as PackedScene).get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) != &"LaserWallWave":
			continue
		var at := Vector2.ZERO
		for p in state.get_node_property_count(i):
			if state.get_node_property_name(i, p) == &"position":
				at = state.get_node_property_value(i, p)
		return {"scene": state.get_node_instance(i), "position": at}
	return {}


## The world AABB of a hurtbox's shapes (an empty `Rect2` for none).
static func hurt_aabb(hurt_box: Node) -> Rect2:
	var out := Rect2()
	var any := false
	if hurt_box == null or not is_instance_valid(hurt_box):
		return out
	for c in hurt_box.get_children():
		var cs := c as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		var r: Rect2 = cs.get_global_transform() * cs.shape.get_rect()
		out = r if not any else out.merge(r)
		any = true
	return out


## Replays `waves` for up to `length` game seconds (summed physics delta) in a fresh Assault world under `host`, and
## calls `observe.call(ship, t) -> bool` on every physics frame once the first ship of `target_path` has spawned
## (`ship` is null once it has left the tree; `t` is slice time). The replay STOPS on the first frame `observe`
## returns true, or at `length`. `tweak.call(ship)`, when valid, runs on each ship of `target_path` as it enters the
## tree: after `_enter_tree()`'s `ShipConfig.privatise()` and before any `_ready()`, so it may edit that ship's PRIVATE
## config (never the shared `.tres`). Before returning, the `WaveManager` is switched off and the world keeps
## stepping until every spawn of an already-triggered wave has arrived (an unfired `SceneTreeTimer` is a leak; past
## `SETTLE_CAP` it gives up with a `push_error`), then the world is freed. Returns `{ "targets": ships of `target_path`
## spawned, "spawned": all ships, "t": slice time at the stop, "stopped": whether `observe` returned true }`; a lit run (`light_lasers`) adds
## `"deaths"` (as `deaths`), `"lit"` (one `{ "source", "x", "row_time", "from", "to", "max_idle", "lit_warn", "lit_active" }` per ray: `from`
## / `to` its first / last lethal physics tick in section time, -1 if never lethal; `max_idle` the largest idle delta from its creation frame to
## the frame after its last lethal one, never below the load frame's), `"max_idle"` (the run's largest idle delta), `"lethal_at_stop"` (rays
## lethal on the stop tick) and `"clearance"` (`{ target index: { "lethal": px, "warning": px } }`: the smallest horizontal gap between its
## root hurtbox and a lethal strip, or a strip still warning, at its height; INF when it never shared one's height).
func run(host: Node, waves: Array[WaveResource], length: float, target_path: String, observe: Callable,
		tweak: Callable = Callable()) -> Dictionary:
	_target_path = target_path
	_tweak = tweak
	_target = null
	_targets_spawned = 0
	_spawned = 0
	_pending = 0.0
	_scheduled = 0
	_arrived = 0
	_waves = waves
	_host = host
	_slice_t = 0.0
	deaths = []
	_rays = []
	_idle = []
	_lit_targets = []
	_clearance = {}
	_lit_wall = null
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
	wm.enemy_spawned.connect(_on_wave_spawn)

	for i in 3:
		await host.get_tree().process_frame
	if light_lasers:
		_light_begin(harness.root)
	wm.load_section(waves)
	var t := 0.0
	var stopped := false
	while t < length and not stopped:
		await host.get_tree().physics_frame
		t += host.get_physics_process_delta_time()
		_slice_t = t
		if light_lasers:
			_light_tick(t)
		if _targets_spawned > 0:
			var ship: BaseEnemy = _target if is_instance_valid(_target) and _target.is_inside_tree() else null
			stopped = bool(observe.call(ship, t))
	var stop_t := t
	var lit_out := _light_end() if light_lasers else {}
	wm.set_process(false)
	while (t < _pending + SPAWN_SETTLE or _arrived < _scheduled) and t < _pending + SETTLE_CAP:
		await host.get_tree().physics_frame
		t += host.get_physics_process_delta_time()
	if _arrived < _scheduled:
		push_error("level1_slice_replay: %d of %d triggered spawns never arrived; freeing the WaveManager leaks their timers"
				% [_scheduled - _arrived, _scheduled])
	container.child_entered_tree.disconnect(_on_child_entered)
	harness.root.queue_free()
	await host.get_tree().process_frame
	# A caller's tweak may capture this instance (to read `slice_time()` or `deaths`): drop it, or the two reference each other and leak.
	_tweak = Callable()
	_waves = []
	var out := {"targets": _targets_spawned, "spawned": _spawned, "t": stop_t, "stopped": stopped}
	out.merge(lit_out)
	return out


## Slice time (summed physics delta) of the latest physics frame of the running replay.
func slice_time() -> float:
	return _slice_t


## The latest spawn moment of any triggered wave, so `run()` knows how long its spawn timers still need, and how many
## ships it still owes.
func _on_wave_triggered(wave_index: int) -> void:
	var one: Array[WaveResource] = [_waves[wave_index]]
	_pending = maxf(_pending, last_spawn(one))
	_scheduled += spawn_count(one)


## One ship out of a `WaveManager` spawn (immediate or after its delay timer).
func _on_wave_spawn(_enemy: Node, _wave_index: int) -> void:
	_arrived += 1


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
		if light_lasers:
			_watch_deaths(node)
		if _tweak.is_valid():
			_tweak.call(node)
		if _target == null:
			_target = node as BaseEnemy


# ── Lit runs (`light_lasers`) ────────────────────────────────────────────────────────────────────────────────────────

## At the `load_section()` moment (inside the same `process_frame` resume, so the wall and `WaveManager`'s clock start in the same idle
## frame): the spawner, the wall, every row due now or carried over the slice start, and the idle hook for the rest.
func _light_begin(root: Node) -> void:
	var tree := _host.get_tree()
	var load_delta := _host.get_process_delta_time()
	_idle = [load_delta]
	# `WaveManager._process` adds this frame's delta as well; a hook connected during this emission is first called next frame.
	_lit_clock = load_delta
	tree.node_added.connect(_on_lit_node_added)
	_lit_spawner = Node.new()
	root.add_child(_lit_spawner)
	# The director's real `_spawn_laser_columns()`; `set_script` on a node already in the tree runs no `_ready()`.
	_lit_spawner.set_script(DIRECTOR_SCRIPT)
	if lit_section == &"deep_space":
		var place := wall_placement()
		var wall := (place["scene"] as PackedScene).instantiate() as Node2D
		var lit := true
		for child in wall.get_children():
			var ray := child as LaserRay
			if ray == null:
				continue
			var relit := warm_start(lit_from, ray.warn_duration, ray.active_duration)
			if relit.is_empty():
				lit = false
				break
			# Before `add_child`: a wall ray starts in its `_ready()`.
			ray.warn_duration = relit["warn"]
			ray.active_duration = relit["active"]
		if lit:
			wall.position = place["position"]
			_lit_wall = wall
			_lit_row_time = 0.0
			root.add_child(wall)
		else:
			wall.free()
	_lit_pending = []
	for row: Dictionary in DIRECTOR_SCRIPT.laser_column_schedule().get(lit_section, []):
		var elapsed := lit_from - float(row["time"])
		if elapsed <= 0.0:
			_lit_pending.append(row)
			continue
		var relit := warm_start(elapsed, DIRECTOR_SCRIPT.COLUMN_WARN_SECONDS, DIRECTOR_SCRIPT.COLUMN_ACTIVE_SECONDS)
		if not relit.is_empty():
			_fire_row(row, relit)
	_fire_due_rows()
	tree.process_frame.connect(_on_lit_frame)


## Fires a row through the director's own method: at its defaults (the hoisted constants) unless relit.
func _fire_row(row: Dictionary, relit: Dictionary = {}) -> void:
	_lit_row_time = float(row["time"])
	if relit.is_empty():
		_lit_spawner._spawn_laser_columns(row["columns"])
	else:
		_lit_spawner._spawn_laser_columns(row["columns"], float(relit["warn"]), float(relit["active"]))


func _fire_due_rows() -> void:
	var i := 0
	while i < _lit_pending.size():
		var row: Dictionary = _lit_pending[i]
		if _lit_clock >= float(row["time"]) - lit_from:
			_fire_row(row)
			_lit_pending.remove_at(i)
		else:
			i += 1


## Every later idle frame: the clock, then the rows due (`Level1Director._process`'s semantics).
func _on_lit_frame() -> void:
	var d := _host.get_process_delta_time()
	_idle.append(d)
	_lit_clock += d
	_fire_due_rows()


func _on_lit_node_added(node: Node) -> void:
	var ray := node as LaserRay
	if ray == null:
		return
	var source := "wall" if _lit_wall != null and ray.get_parent() == _lit_wall else "column"
	_rays.append({"ray": ray, "source": source, "row_time": _lit_row_time, "x": NAN, "from": -1.0, "to": -1.0,
		"created": _idle.size() - 1, "last_lethal": -1, "lit_warn": ray.warn_duration, "lit_active": ray.active_duration})


## Each physics tick: every ray's lethal window, and each target's clearance from the strips at its height.
func _light_tick(t: float) -> void:
	var section_t := t + lit_from
	var frame := _idle.size() - 1
	for r: Dictionary in _rays:
		var ray: LaserRay = r["ray"] if is_instance_valid(r["ray"]) else null
		if ray == null:
			continue
		if is_nan(float(r["x"])):
			r["x"] = ray.global_position.x
		if ray.is_lethal_now():
			if float(r["from"]) < 0.0:
				r["from"] = section_t
			r["to"] = section_t
			r["last_lethal"] = frame
	for i in _lit_targets.size():
		var ship := _lit_targets[i]
		if not is_instance_valid(ship) or not ship.is_inside_tree():
			continue
		var box := hurt_aabb(ship.get_node_or_null(^"HurtBox"))
		var c: Dictionary = _clearance[i]
		for r: Dictionary in _rays:
			var ray: LaserRay = r["ray"] if is_instance_valid(r["ray"]) else null
			if ray == null:
				continue
			var strip := ray.danger_rect()
			if strip.position.y >= box.end.y or box.position.y >= strip.end.y:
				continue
			var gap := maxf(0.0, maxf(strip.position.x - box.end.x, box.position.x - strip.end.x))
			if ray.is_lethal_now():
				c["lethal"] = minf(float(c["lethal"]), gap)
			elif float(r["from"]) < 0.0:
				c["warning"] = minf(float(c["warning"]), gap)


## A ship of `target_path` entering the tree (before its `_ready()`): its hull's `died` and every part's `destroyed`.
func _watch_deaths(node: Node) -> void:
	var index := _lit_targets.size()
	_lit_targets.append(node)
	_clearance[index] = {"lethal": INF, "warning": INF}
	(node as BaseEnemy).died.connect(_on_lit_death.bind(index, "hull", node.get_node_or_null(^"HurtBox")))
	var modules := node.get_node_or_null(^"Modules")
	if modules == null:
		return
	for child in modules.get_children():
		var part := child as EnemyModule
		if part != null:
			part.destroyed.connect(func(p: EnemyModule) -> void:
				_on_lit_death(index, String(p.module_id), p.get_node_or_null(^"HurtBox")))


## Covered = a LETHAL ray's strip meets the dying node's hurtbox at this moment (a warning line never kills).
func _on_lit_death(index: int, what: String, hurt_box: Node) -> void:
	var box := hurt_aabb(hurt_box)
	var covered := false
	var source := ""
	for r: Dictionary in _rays:
		var ray: LaserRay = r["ray"] if is_instance_valid(r["ray"]) else null
		if ray != null and ray.is_lethal_now() and ray.danger_rect().intersects(box):
			covered = true
			source = r["source"]
			break
	deaths.append({"ship": index, "what": what, "t": _slice_t + lit_from, "covered": covered, "source": source})


## At the stop: drop the tree hooks (before the world is freed) and summarise.
func _light_end() -> Dictionary:
	var tree := _host.get_tree()
	if tree.process_frame.is_connected(_on_lit_frame):
		tree.process_frame.disconnect(_on_lit_frame)
	if tree.node_added.is_connected(_on_lit_node_added):
		tree.node_added.disconnect(_on_lit_node_added)
	var load_delta: float = _idle[0] if not _idle.is_empty() else 0.0
	var run_max := 0.0
	for d in _idle:
		run_max = maxf(run_max, d)
	var lit: Array[Dictionary] = []
	var lethal_now := 0
	for r: Dictionary in _rays:
		var last: int = int(r["last_lethal"]) + 1 if int(r["last_lethal"]) >= 0 else _idle.size() - 1
		var d := load_delta
		for k in range(int(r["created"]), mini(last, _idle.size() - 1) + 1):
			d = maxf(d, _idle[k])
		if is_instance_valid(r["ray"]) and (r["ray"] as LaserRay).is_lethal_now():
			lethal_now += 1
		lit.append({"source": r["source"], "x": r["x"], "row_time": r["row_time"], "from": r["from"], "to": r["to"], "max_idle": d,
			"lit_warn": r["lit_warn"], "lit_active": r["lit_active"]})
	return {"deaths": deaths.duplicate(), "lit": lit, "max_idle": run_max, "lethal_at_stop": lethal_now,
		"clearance": _clearance.duplicate(true)}
