# global/autoloads/log_state.gd
extends Node

## Persistent store for lore-log entries.
## Access anywhere: LogState.collect_next()
##                  LogState.is_collected(&"some_id")
##                  LogState.total_count()
##
## The catalogue is a directory of `LogEntryResource` `.tres` files — `total_count()` is
## derived from what's on disk, never a hand-maintained number. A lore-log pickup is
## anonymous: it does not name an entry, it just calls `collect_next()`, which grants the
## lowest-`sequence` entry not yet collected. This keeps the story reading in order no
## matter where in the game world the player found the collectible.
##
## Information logs (one-time, non-persisted, don't count toward completion) never touch
## this store at all.

signal log_collected(id: StringName)

const SAVE_PATH := "user://log_state.cfg"
const SECTION := "logs"
const DEFAULT_CATALOGUE_DIR := "res://global/resources/logs/entries"

## Overridable so tests can point this at a fixture directory without touching the
## production catalogue. Production code never changes this.
var catalogue_dir: String = DEFAULT_CATALOGUE_DIR

## Sorted by `sequence`, ties broken by `id`.
var _catalogue: Array[LogEntryResource] = []
## StringName -> LogEntryResource
var _by_id: Dictionary = {}
## StringName -> true
var _collected: Dictionary = {}


func _ready() -> void:
	_load_catalogue()
	_load()


## Total number of catalogue entries on disk. Adding a `.tres` to `catalogue_dir` is the
## entire bookkeeping a new log requires — there is no count to update anywhere else.
func total_count() -> int:
	return _catalogue.size()


func collected_count() -> int:
	return _collected.size()


func is_collected(id: StringName) -> bool:
	return _collected.get(id, false)


## Catalogue-order ids collected so far.
func collected_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in _catalogue:
		if _collected.get(entry.id, false):
			out.append(entry.id)
	return out


## Catalogue-order ids for every entry, collected or not — the Lore Logs reader walks this to
## render the whole catalogue, including rows it has to show as still locked.
func all_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry in _catalogue:
		out.append(entry.id)
	return out


func get_entry(id: StringName) -> LogEntryResource:
	return _by_id.get(id, null)


## Collects the next still-locked entry in catalogue order and returns its id. Returns
## &"" and changes nothing if every entry is already collected (or the catalogue is
## empty) — an anonymous pickup firing this after 100% completion is a no-op, not an error.
func collect_next() -> StringName:
	for entry in _catalogue:
		if not _collected.get(entry.id, false):
			_collected[entry.id] = true
			_save()
			log_collected.emit(entry.id)
			return entry.id
	return &""


func _load_catalogue() -> void:
	_catalogue.clear()
	_by_id.clear()
	var dir := DirAccess.open(catalogue_dir)
	if dir == null:
		return  # no catalogue yet — total_count() is legitimately 0
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var entry := load(catalogue_dir.path_join(file)) as LogEntryResource
		if entry == null:
			push_warning("LogState: %s did not load as a LogEntryResource, skipping" % file)
			continue
		if entry.id == &"":
			push_warning("LogState: %s has no id set, skipping" % file)
			continue
		if _by_id.has(entry.id):
			## Two catalogue files claiming one id would double-count total_count() and
			## collapse two entries onto one _collected flag, permanently blocking 100%
			## completion. Keep the first one seen, drop the rest, and warn loudly — this
			## is a content-authoring mistake, not a runtime condition to tolerate quietly.
			push_warning("LogState: duplicate log id '%s' in %s, ignoring" % [entry.id, file])
			continue
		_catalogue.append(entry)
		_by_id[entry.id] = entry
	_catalogue.sort_custom(func(a: LogEntryResource, b: LogEntryResource) -> bool:
		if a.sequence != b.sequence:
			return a.sequence < b.sequence
		return String(a.id) < String(b.id))


func _save() -> void:
	var cfg := ConfigFile.new()
	for id: StringName in _collected:
		cfg.set_value(SECTION, String(id), true)
	var err := cfg.save(SAVE_PATH)
	if err != OK:
		push_error("LogState: failed to save '%s' (error %d)" % [SAVE_PATH, err])


func _load() -> void:
	_collected.clear()
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	if not cfg.has_section(SECTION):
		return
	for key: String in cfg.get_section_keys(SECTION):
		var id := StringName(key)
		if not _by_id.has(id):
			push_warning("LogState: unknown log id '%s' in save file, ignoring" % key)
			continue
		_collected[id] = true
