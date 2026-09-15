## Integrity test that every scene, resource and script in the project actually loads, and that
## loading the whole tree produces no engine errors.
##
## `/agent/verify.sh` step 1 (`godot --headless --import`) and step 2 (`--quit`, which boots the
## autoloads and the main scene) between them touch only a fraction of the tree. Import resolves
## *importable* assets — textures, fonts, audio — and never loads a `.tscn`/`.tres` at all; the
## boot loads only what `res://boot/…` pulls in transitively. Everything reachable solely from the
## assault levels, the race sub-mode, the open-space hub or infiltration is never loaded by the
## gate, so a scene broken by a rename sits there green until a player opens it.
##
## The case that motivated this file: three `ext_resource, invalid UID` warnings were live in the
## tree and `--import` surfaced exactly **one** of them. The other two only appeared once every
## scene had actually been loaded. Its first run then found two more of the same shape, neither of
## which any other check could see — `race_level_1.tscn` declaring 212 atlas tiles its 256×256
## texture cannot hold, and `TestIsometricScene.tscn` pointing its backdrop at a stale
## `res://.godot/imported/…ctex` hash so the sprite silently rendered nothing.
##
## Like `test_resource_uid_integrity.gd` and `test_suite_integrity.gd`, this is NOT a
## characterization test — it asserts a property that must hold, so a failure here is a regression
## to fix rather than a quirk to document.
##
## It and `test_resource_uid_integrity.gd` are complementary; neither subsumes the other:
##
##   * `test_resource_uid_integrity.gd` reads **files on disk** and never asks the engine, because
##     a warm `.godot/uid_cache.bin` keeps stale UIDs alive as working aliases. It catches drift
##     that still loads perfectly well today.
##   * this file asks the **engine** to load everything, because a reference that no longer
##     resolves by path either, a resource the engine rejects, or a script that does not compile
##     are all invisible to a text scan of the files.
##
## Five things to know before extending it:
##
##   * **A `.tscn` whose attached script fails to compile still loads to a non-null
##     `PackedScene`,** and `can_instantiate()` on it still returns `true` — the engine reports the
##     compile failure on stderr and hands back a usable scene with a broken script. That is why
##     the scripts are walked and compiled separately below rather than being taken on trust from
##     the scenes referencing them.
##   * **A `.gd` with a parse error still `load()`s to a non-null `GDScript`.** The giveaway is
##     `can_instantiate() == false`, exactly as documented in `test_suite_integrity.gd`.
##   * **Scripts must be compiled with the autoloads registered.** Half of this project's scripts
##     name `MissionState` / `EventBus` / `SessionState` / `ShipModuleState` / `DialogPlayer` /
##     `CameraShake` / `ShipProgressionState` at parse time, and a run with no autoloads fails all
##     of them with `Identifier not found`. That is why `/agent/verify.sh` cannot use
##     `--check-only --script` per file, and why this check lives in the GUT suite, which runs
##     inside a booted project where the autoloads exist.
##   * **The whole tree is loaded exactly once, in `_load_everything()`, and kept.** Godot's
##     resource cache holds no strong reference, so dropping the results would make every test
##     below re-read from disk and re-emit the same errors. The load pass is lazy and idempotent
##     so it does not matter which test runs first, or whether only one of them is run.
##   * **Engine errors are marked `handled` by the load pass itself.** GUT fails any test during
##     which the engine logged an error, with a bare `Unexpected Errors:` and no indication of
##     which of the 130 resources caused it. Taking ownership of them lets
##     `test_loading_the_project_logs_no_engine_errors` name the file instead — and engine
##     *warnings* reach the same tracker, which is what makes `ext_resource, invalid UID` (a
##     warning, not an error) fail this suite rather than scroll past in the log.
##
## `addons/` is not walked: vendored third-party code is not ours to police, and `addons/gut`'s
## own editor scenes are `@tool` scripts with no business being compiled by the game's gate.
extends GutTest

const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]

## Vacuity floors. The tree holds ~130 `.tscn`/`.tres` and ~280 `.gd` outside `addons/` today;
## these are deliberately slack and exist only so a broken walk fails loudly instead of turning
## every test below into an assertion about an empty array.
const MIN_RESOURCE_FILES := 100
const MIN_SCRIPT_FILES := 200

var _resource_files: Array[String] = []
var _script_files: Array[String] = []

## Populated by `_load_everything()`. Kept so the resources stay alive for the whole script.
var _loaded: Dictionary = {}
## path -> Array[String] of the engine errors logged while that path was loading.
var _errors_by_path: Dictionary = {}
var _load_pass_done := false


func before_all() -> void:
	_resource_files = _collect_files("res://", [".tscn", ".tres"])
	_resource_files.sort()
	_script_files = _collect_files("res://", [".gd"])
	_script_files.sort()


func after_all() -> void:
	# Drop the last strong references so the ~130 scenes and their textures do not outlive the
	# script; Godot's resource cache is non-owning and releases them once this dictionary does.
	_loaded.clear()


## Recursive walk of the project tree returning every file whose name ends with one of
## `extensions`.
func _collect_files(dir_path: String, extensions: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not (entry.begins_with(".") or SKIPPED_DIRS.has(entry)):
				found.append_array(_collect_files(full, extensions))
		else:
			for extension: String in extensions:
				if entry.ends_with(extension):
					found.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Load every collected file once, attributing any engine error to the file being loaded at the
## time, and claim those errors so GUT does not fail the test with an anonymous `Unexpected
## Errors:` instead. Idempotent: only the first caller pays for it.
func _load_everything() -> void:
	if _load_pass_done:
		return
	_load_pass_done = true
	var consumed := 0
	for path: String in _resource_files + _script_files:
		_loaded[path] = ResourceLoader.load(path)
		var errors: Array = get_errors()
		if errors.size() == consumed:
			continue
		var logged: Array[String] = []
		for i in range(consumed, errors.size()):
			var error: GutTrackedError = errors[i]
			# Ours to report now; see the header note on GUT's anonymous failure.
			error.handled = true
			logged.append("%s->%s: %s %s"
				% [error.file, error.function, error.code, error.rationale])
		consumed = errors.size()
		_errors_by_path[path] = logged


## One line per offending file, with its first error and how many followed it.
func _format_error_report() -> Array[String]:
	var lines: Array[String] = []
	for path: String in _errors_by_path:
		var logged: Array[String] = _errors_by_path[path]
		var extra := "" if logged.size() == 1 else " (+%d more)" % (logged.size() - 1)
		lines.append("%s -> %s%s" % [path, logged[0], extra])
	return lines


func test_the_walk_actually_found_the_projects_files() -> void:
	# Without this every test below would pass trivially if the walk ever broke.
	assert_gt(_resource_files.size(), MIN_RESOURCE_FILES,
		"expected well over %d .tscn/.tres files outside addons/, found %d"
		% [MIN_RESOURCE_FILES, _resource_files.size()])
	assert_gt(_script_files.size(), MIN_SCRIPT_FILES,
		"expected well over %d .gd files outside addons/, found %d"
		% [MIN_SCRIPT_FILES, _script_files.size()])
	assert_has(_resource_files, "res://boot/boot.tscn",
		"the walk should find the project's main scene")


func test_every_scene_and_resource_loads() -> void:
	# The check the gate's import step cannot make: `--import` never loads a .tscn/.tres, so a
	# scene pointing at a file that has been moved or deleted stays invisible until it is opened.
	_load_everything()
	var failed: Array[String] = []
	for path: String in _resource_files:
		if _loaded[path] == null:
			failed.append("%s -> load() returned null (see the ERROR lines above)" % path)
	assert_eq(failed, [] as Array[String],
		"scenes/resources that do not load:\n  " + "\n  ".join(failed))


func test_every_scene_can_be_instantiated() -> void:
	# A PackedScene can load and still be unusable — a missing base scene in an inherited scene,
	# or a node whose type no longer exists, both survive load() and fail here.
	_load_everything()
	var broken: Array[String] = []
	for path: String in _resource_files:
		if not path.ends_with(".tscn"):
			continue
		var scene := _loaded[path] as PackedScene
		if scene == null:
			continue  # already reported by test_every_scene_and_resource_loads
		if not scene.can_instantiate():
			broken.append("%s -> PackedScene.can_instantiate() == false" % path)
	assert_eq(broken, [] as Array[String],
		"scenes that load but cannot be instantiated:\n  " + "\n  ".join(broken))


func test_every_script_compiles() -> void:
	# The gate boots only `res://boot/…` and its transitive dependencies, so a compile error in a
	# script reachable only from an assault level, the race sub-mode, the open-space hub or
	# infiltration never surfaces there. A broken script loads non-null; can_instantiate() is the
	# real signal.
	_load_everything()
	var broken: Array[String] = []
	for path: String in _script_files:
		var script := _loaded[path] as GDScript
		if script == null:
			broken.append("%s -> did not load as a GDScript at all" % path)
		elif not script.can_instantiate():
			broken.append("%s -> compiled with errors (see the Parse Error lines above)" % path)
	assert_eq(broken, [] as Array[String],
		"scripts that do not compile:\n  " + "\n  ".join(broken))


func test_loading_the_project_logs_no_engine_errors() -> void:
	# The strongest of the four, and the reason the load pass claims the errors itself: a resource
	# can load, instantiate and compile while the engine complains the whole way. Warnings reach
	# the same tracker, so `ext_resource, invalid UID` — the warning that motivated this file —
	# lands here rather than scrolling past in the gate log.
	_load_everything()
	assert_eq(_format_error_report(), [] as Array[String],
		"the engine logged errors while loading the project:\n  "
		+ "\n  ".join(_format_error_report()))
