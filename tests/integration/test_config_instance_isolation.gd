## Invariant test: every entity instance owns its `*_config.tres`, nobody shares one.
##
## NOT characterization. Today's behaviour is the bug this file exists to end: ten entity scripts
## declare `@export var config: XConfig = load("res://.../x_config.tres")`, `ResourceLoader` caches
## by path, and so every entity of a type in the process — and every `preload()` in this suite —
## holds the SAME object. Writing one enemy's `config.max_health` rewrote the shipped balance data
## for every other live enemy of that type and for every later test in the run.
##
## Plan: `docs/plans/every-enemy-that-does-export-var-config-load-shares-one-conf/3-plan.md`.
##
## ── What the fix is, so a failure here is readable ───────────────────────────────────────────
##
## `ShipConfig.privatise(node)` (`global/resources/ship_config.gd`) swaps a node's `config` for a
## `duplicate()` of it, and is called from BOTH `_init()` and `_enter_tree()` on `BaseEnemy`
## (`base_enemy.gd`) and `AllyFighter` (`ally_fighter.gd`). Both hooks are needed and they close
## different windows:
##
## - `_init()` runs at construction, so `entity.config` is private before `instantiate()` even
##   returns. Without it every write between `instantiate()` and `add_child()` still lands on the
##   shared resource — and that is exactly where `wave_manager.gd:177-181` applies `initial_props`,
##   deliberately and with a comment saying so. Test 4's second half is that window.
## - `_enter_tree()` catches a `config` that a `.tscn` override or `initial_props` substituted in
##   AFTER the constructor, and it still runs before any child's `_ready()` — which matters because
##   all four space-station children read `_station.config` in their own `_ready()`. Test 6.
##
## They compose because `duplicate()` blanks `resource_path`, so a blank path IS the marker of an
## already-private copy and the second call is a no-op. Test 5 pins that.
##
## ── Two windows this does NOT close ──────────────────────────────────────────────────────────
##
## Recorded rather than fixed, because neither is reachable in non-addon code today (`grep` finds
## no `Node.duplicate()` and no `entity.config = ` assignment outside `addons/`):
##
## 1. `Node.duplicate()` on a live entity yields two nodes sharing ONE private copy. The
##    idempotence guard cannot tell "private to me" from "private to someone else" — both have a
##    blank `resource_path`.
## 2. Assigning `entity.config = load(...)` after the entity is already in the tree fires neither
##    hook, so that entity is back on the shared object.
##
## ── Harness notes ────────────────────────────────────────────────────────────────────────────
##
## 1. **Every entity is parented to a throwaway container `Node2D`, never to the test directly.**
##    `ExplosionEffect` parents its particles to `actor.get_parent()` and `bullet_pool.gd:47`
##    resolves `get_parent().get_parent()`. Same rule as `test_enemy_contact_damage.gd` note 1.
## 2. **`_ready()` must actually run**, so entities are added to the tree, not just instantiated —
##    except where a test is deliberately probing the not-yet-in-tree window.
## 3. **The roster is a `DirAccess` sweep, not a hand-written list** (precedent:
##    `test_enemy_hurtbox_geometry.gd:317-334`), so an enemy added later cannot escape it. That is
##    the whole point: the guarantee has to survive the next entity somebody writes.
extends GutTest

## Top-level directories only — `assault/scenes/enemies/` also holds loose scripts and its
## subdirectories hold non-entity scenes (`bomber/bomb.tscn`, `light_assault_ship/states/`).
const _ENTITY_DIRS: Array[String] = [
	"res://assault/scenes/enemies",
	"res://assault/scenes/allies",
]

## Ten entity directories carry a `*config*.tres` today (`sniper_enemy` has none). A sweep that
## finds fewer has broken, and a broken sweep passes every assertion below vacuously.
const _MIN_ENTITIES_WITH_CONFIG: int = 10

const GUNSHIP_SCENE: PackedScene = preload("res://assault/scenes/enemies/gunship/gunship.tscn")
const GUNSHIP_CONFIG_PATH := "res://assault/scenes/enemies/gunship/gunship_config.tres"
const STATION_SCENE: PackedScene = preload("res://assault/scenes/enemies/space_station/space_station.tscn")


## Records what a CHILD saw in its own `_ready()`. Deliberately not named `Test*`: GUT treats an
## inner class whose name starts with "Test" as a nested test collection and would try to run it.
class ConfigProbe:
	extends Node
	var seen: Resource = null

	func _ready() -> void:
		var cfg: Variant = get_parent().get("config")
		seen = cfg as Resource


# ── Sweep ────────────────────────────────────────────────────────────────────

## `{name, scene, config}` per entity directory that has both `<dir>/<dir>.tscn` and exactly one
## `*config*.tres`. Directories with no config (`sniper_enemy`) are skipped — they have nothing to
## share. A directory with TWO configs is a failure, not a coin toss: the sweep would otherwise
## silently pick one and check the wrong resource forever.
func _sweep() -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for root in _ENTITY_DIRS:
		var dir := DirAccess.open(root)
		assert_not_null(dir, "cannot open %s" % root)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var scene_path := "%s/%s/%s.tscn" % [root, sub, sub]
			if not ResourceLoader.exists(scene_path):
				continue
			var configs: Array[String] = []
			var entity_dir := DirAccess.open("%s/%s" % [root, sub])
			if entity_dir == null:
				continue
			for file in entity_dir.get_files():
				if file.ends_with(".tres") and file.contains("config"):
					configs.append("%s/%s/%s" % [root, sub, file])
			if configs.is_empty():
				continue
			assert_eq(
				configs.size(), 1,
				(
					"%s/%s holds %d files matching *config*.tres, so this sweep cannot tell which "
					+ "one the entity uses. Give the entity exactly one, or teach the sweep."
				) % [root, sub, configs.size()]
			)
			found.append({"name": sub, "scene": scene_path, "config": configs[0]})
	return found


## A throwaway container per call — harness note 1.
func _spawn(scene_path: String) -> Node:
	var container := Node2D.new()
	add_child_autofree(container)
	var scene := load(scene_path) as PackedScene
	assert_not_null(scene, "%s failed to load" % scene_path)
	var entity := scene.instantiate()
	container.add_child(entity)
	return entity


## Script-declared properties only. `get_property_list()` on the instance would also hand back
## `script`, `resource_path` and `resource_local_to_scene`, none of which is balance data — and
## `script` is a `TYPE_OBJECT` that would make the flatness test below fail on every config.
func _config_fields(cfg: Resource) -> Array[Dictionary]:
	var fields: Array[Dictionary] = []
	for prop in cfg.get_script().get_script_property_list():
		if prop["usage"] & PROPERTY_USAGE_STORAGE:
			fields.append(prop)
	return fields


# ── 1. The invariant ─────────────────────────────────────────────────────────

func test_two_instances_never_share_a_config() -> void:
	var checked := 0
	for entry in _sweep():
		var shipped := load(entry["config"]) as ShipConfig
		var a := _spawn(entry["scene"])
		var b := _spawn(entry["scene"])
		var cfg_a: Variant = a.get("config")
		var cfg_b: Variant = b.get("config")
		if not (cfg_a is ShipConfig):
			continue
		checked += 1
		assert_ne(
			cfg_a, cfg_b,
			(
				"%s: two instances share ONE config object, so writing to either rewrites the "
				+ "other's balance data. `ShipConfig.privatise()` should have run from _init()."
			) % entry["name"]
		)
		assert_ne(
			cfg_a, shipped,
			(
				"%s: the instance holds the ResourceLoader-cached `%s` itself, so a write reaches "
				+ "every entity in the process AND every preload() in this suite."
			) % [entry["name"], entry["config"]]
		)
		assert_true(
			(cfg_a as Resource).resource_path.is_empty(),
			(
				"%s: a private copy has a blank resource_path (duplicate() blanks it). A non-blank "
				+ "one means this config is still cached and shared."
			) % entry["name"]
		)
	assert_gte(
		checked, _MIN_ENTITIES_WITH_CONFIG,
		(
			"the entity sweep found only %d config-carrying entities; %d exist. Every assertion "
			+ "in this file is vacuous when the sweep breaks."
		) % [checked, _MIN_ENTITIES_WITH_CONFIG]
	)


# ── 2. No balance drift ──────────────────────────────────────────────────────

func test_the_copy_carries_every_shipped_value() -> void:
	for entry in _sweep():
		var shipped := load(entry["config"]) as ShipConfig
		var entity := _spawn(entry["scene"])
		var cfg: Variant = entity.get("config")
		if not (cfg is ShipConfig):
			continue
		var live := cfg as ShipConfig
		var fields := _config_fields(shipped)
		assert_gt(fields.size(), 0, "%s: config exposes no stored fields" % entry["name"])
		for prop in fields:
			assert_eq(
				live.get(prop["name"]), shipped.get(prop["name"]),
				(
					"%s: the per-instance copy's `%s` does not match the shipped %s. The copy must "
					+ "be value-identical — the .tres stays the single source of truth."
				) % [entry["name"], prop["name"], entry["config"].get_file()]
			)


# ── 3. The assumption the shallow copy rests on ──────────────────────────────

## `duplicate()` is SHALLOW, and even `duplicate(true)` never duplicates a Resource held inside an
## Array or Dictionary. So the moment a config gains a nested resource, test 1's isolation becomes
## a lie for that field while still passing. This is the early warning.
func test_configs_are_flat_so_a_shallow_copy_is_complete() -> void:
	var checked := 0
	for entry in _sweep():
		var shipped := load(entry["config"]) as ShipConfig
		checked += 1
		for prop in _config_fields(shipped):
			var type: int = prop["type"]
			assert_false(
				type == TYPE_OBJECT or type == TYPE_ARRAY or type == TYPE_DICTIONARY,
				(
					"%s.%s is a nested Object/Array/Dictionary. `ShipConfig.privatise()` uses a "
					+ "shallow duplicate(), which would leave that field SHARED between every "
					+ "instance while this file's other tests still pass. Give %s a deep copy "
					+ "before adding this field."
				) % [entry["config"].get_file(), prop["name"], entry["config"].get_file()]
			)
	assert_gte(checked, _MIN_ENTITIES_WITH_CONFIG, "the sweep found only %d configs" % checked)


# ── 4. The defect, stated directly ───────────────────────────────────────────

func test_writing_to_one_entitys_config_cannot_reach_another() -> void:
	var shipped_health: int = (load(GUNSHIP_CONFIG_PATH) as ShipConfig).max_health

	var a := _spawn(GUNSHIP_SCENE.resource_path)
	var b := _spawn(GUNSHIP_SCENE.resource_path)
	(a.get("config") as ShipConfig).max_health = 1

	assert_eq(
		(b.get("config") as ShipConfig).max_health, shipped_health,
		"writing one gunship's config.max_health changed a DIFFERENT live gunship's"
	)
	assert_eq(
		(load(GUNSHIP_CONFIG_PATH) as ShipConfig).max_health, shipped_health,
		"writing one gunship's config.max_health rewrote the shipped gunship_config.tres in memory"
	)
	var c := _spawn(GUNSHIP_SCENE.resource_path)
	assert_eq(
		(c.get("config") as ShipConfig).max_health, shipped_health,
		"a gunship spawned AFTER the write inherited the poisoned value"
	)

	## The window `_init()` exists for: `wave_manager.gd:177-181` applies spawn overrides to a
	## freshly instantiated entity BEFORE add_child, so a difficulty scaler written the idiomatic
	## way runs entirely out of the tree. On an `_enter_tree()`-only fix this half fails.
	var loose := GUNSHIP_SCENE.instantiate()
	autofree(loose)
	(loose.get("config") as ShipConfig).max_health = 7
	assert_eq(
		(load(GUNSHIP_CONFIG_PATH) as ShipConfig).max_health, shipped_health,
		(
			"a write to an entity that is instantiated but NOT YET in the tree reached the shipped "
			+ "resource. That is the window WaveManager's initial_props idiom runs in."
		)
	)


# ── 5. Boundary — the idempotence guard ──────────────────────────────────────

## Without the `resource_path.is_empty()` check in `privatise()`, the second `_enter_tree()` copies
## the copy and every per-instance change made before the re-parent is silently discarded.
func test_reentering_the_tree_keeps_the_same_private_copy() -> void:
	var entity := _spawn(GUNSHIP_SCENE.resource_path)
	var before: Variant = entity.get("config")
	assert_true(
		(before as Resource).resource_path.is_empty(),
		"the entity's config is not a private copy to begin with"
	)
	(before as ShipConfig).max_health = 4321

	var parent := entity.get_parent()
	parent.remove_child(entity)
	parent.add_child(entity)

	assert_eq(
		entity.get("config"), before,
		"re-parenting replaced the private config with a fresh copy — privatise() is not idempotent"
	)
	assert_eq(
		(entity.get("config") as ShipConfig).max_health, 4321,
		"re-parenting discarded a per-instance config value"
	)


# ── 6. Boundary — the ordering the design rests on ───────────────────────────

## The space station's four child nodes read `_station.config` in THEIR `_ready()`, which runs
## before the station's. So the copy must already exist by then, which is why it is installed in
## `_init()`/`_enter_tree()` and not in `_ready()`.
##
## This has to be an IDENTITY check taken from inside a child. Comparing the child's copied VALUES
## is green even on a `_ready()`-time design, because the children copy identical numbers off the
## shared original — that is exactly why the first draft of this test was rejected in review.
func test_station_children_see_the_private_copy_in_their_ready() -> void:
	var seen: Array[Resource] = []
	var stations: Array[Node] = []
	for i in 2:
		var container := Node2D.new()
		add_child_autofree(container)
		var station := STATION_SCENE.instantiate()
		var probe := ConfigProbe.new()
		station.add_child(probe)
		container.add_child(station)
		stations.append(station)
		assert_not_null(probe.seen, "the probe's _ready() did not run")
		seen.append(probe.seen)
		assert_eq(
			probe.seen, station.get("config"),
			(
				"a child's _ready() saw a DIFFERENT config object than the one the station ends up "
				+ "holding. The copy must be installed before any child is ready — _init()/"
				+ "_enter_tree(), never _ready()."
			)
		)
		assert_true(
			probe.seen.resource_path.is_empty(),
			"a child's _ready() saw the shared, ResourceLoader-cached config, not a private copy"
		)
	assert_ne(
		seen[0], seen[1],
		"two stations' children saw the SAME config object, so the stations share their stats"
	)
