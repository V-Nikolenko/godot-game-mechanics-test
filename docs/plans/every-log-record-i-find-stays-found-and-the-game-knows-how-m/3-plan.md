# Log record persistence store (LogEntryResource + LogState)

## Problem

The epic wants discoverable lore/info logs across all three modes. Nothing else in the epic —
the pickup, the "read it" popup, the ESC-menu Lore Logs list, placement in assault/infiltration —
can be built until "what is a log" and "where is it saved" exist. Today there is no log data type
and no persistent store, so a player's found logs vanish on relaunch and there is no way to answer
"how many logs are there" without a human counting them by hand.

This task builds only the data model and the persistence/query autoload — **not** the pickup
scene, not the reading UI, not the ESC menu. Those are separate tasks in this epic and consume
the API built here.

## Design

### `LogEntryResource` (new `Resource` subtype)

`global/resources/logs/log_entry_resource.gd`:

```gdscript
class_name LogEntryResource
extends Resource

## Stable id. Matches the catalogue `.tres` filename by convention but is read from this
## field, not the filename — LogState never parses a path for meaning.
@export var id: StringName = &""
## Shown as the entry title wherever a log is listed (menu, popup).
@export var title: String = ""
@export_multiline var body: String = ""
## Position in the reading order. Lore logs unlock in ascending `sequence` order regardless
## of collection order in the world — see LogState.collect_next().
@export var sequence: int = 0
```

Flat `Resource`, no nested sub-resources — same shallow shape as every other config `.tres` in
the project, so no `privatise()`-style copy is ever needed (these are read-only catalogue data,
never mutated per-instance).

One `.tres` per entry, matching `mission_config_resource.gd`'s per-mission pattern. Production
catalogue lives at `global/resources/logs/entries/`. This task does not author narrative content —
authoring real entries is for whichever later task actually writes lore — so this directory may
ship with zero or a couple of files; `LogState` must not assume anything is at that path.

### Design fork: anonymous vs. named pickups

**Chosen: anonymous.** A lore-log collectible carries no id; collecting one always grants the
next still-locked `LogEntryResource` in ascending `sequence` order. Rejected alternative: each
collectible names its target entry, so the menu could show a specific gap. Anonymous wins because:

1. It is the cheapest reading of "place the collectible on the map and everything else happens
   automatically" — a level designer drops one generic pickup scene with zero per-instance
   configuration.
2. It keeps reading order a property of the catalogue (`sequence` on the `.tres` files) rather
   than of *where a level designer happened to place things* across three separate modules. The
   later "place logs in assault and infiltration" task does not have to reason about which id is
   "next" in a specific mission — it just places the same anonymous pickup scene.
3. The story always reads in sequence no matter which corner of the map is explored first, which
   matches "unlocked in a specific order" from the source idea more directly than a
   possibly-gappy named list.

This task builds the store `collect_next()` needs; the pickup scene that calls it is a later task.

### `LogState` (new autoload)

`global/autoloads/log_state.gd`, registered in `project.godot` `[autoload]` as `LogState=`.

```gdscript
extends Node

signal log_collected(id: StringName)

const SAVE_PATH := "user://log_state.cfg"
const SECTION := "logs"
const DEFAULT_CATALOGUE_DIR := "res://global/resources/logs/entries"

## Overridable so tests can point this at a fixture directory without touching the
## production catalogue. Production code never changes this.
var catalogue_dir: String = DEFAULT_CATALOGUE_DIR

var _catalogue: Array[LogEntryResource] = []   # sorted by sequence, ties broken by id
var _by_id: Dictionary = {}                     # StringName -> LogEntryResource
var _collected: Dictionary = {}                 # StringName -> true

func _ready() -> void:
    _load_catalogue()
    _load()

## Total number of catalogue entries on disk. Derived every time the catalogue is loaded —
## there is no hand-maintained count anywhere. Adding a `.tres` to `catalogue_dir` is the
## entire bookkeeping a new log requires.
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

func get_entry(id: StringName) -> LogEntryResource:
    return _by_id.get(id, null)

## Collects the next still-locked entry in catalogue order and returns its id. Returns
## &"" and changes nothing if every entry is already collected (or the catalogue is
## empty) — an anonymous pickup that fires this after 100% completion must be a no-op,
## not an error.
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
```

Notes:
- `_load_catalogue()` must run before `_load()` so validate-on-load has something to validate
  against — mirrors `ShipModuleState`'s "known ids first, then load" ordering.
- `catalogue_dir` is a plain instance var, not a constant, purely so `test_log_state.gd` can
  construct a tree-less `LogState.new()`, point it at a fixture directory, and call
  `_load_catalogue()` / `_load()` directly — the same "construct, don't add to tree" idiom
  `test_upgrade_state.gd` already uses. Production code never touches it.
- No `unlock()`-by-id API is exposed. `collect_next()` is the only mutator, which is what makes
  the pickup anonymous — there is no id for it to pass in even if it wanted to.

### Wiring

- `project.godot`: add `LogState="*res://global/autoloads/log_state.gd"` to `[autoload]`.
- `tests/helpers/save_sandbox.gd`: add `"user://log_state.cfg"` to `PATHS`.

## Build sequence

1. `global/resources/logs/log_entry_resource.gd` — the `Resource` subtype. No test file of its
   own (it is pure data, like `MissionConfigResource`); covered indirectly by `test_log_state.gd`
   and by `test_project_load_integrity.gd`'s project-wide load sweep. Leave the script's own
   `ext_resource` UID unset on every `.tres` that references it — never hand-type or copy a
   `uid://` from a sibling file (`CLAUDE.md`, `tests/README.md`); a path-only reference is legal
   and `test_resource_uid_integrity.gd` / `test_project_load_integrity.gd` will catch it if this
   is missed anyway, but there's no reason to create the risk across the several new `.tres`
   files this task adds.
2. Fixture catalogue for tests: `tests/unit/fixtures/log_entries/{entry_a,entry_b,entry_c}.tres`
   — three minimal real `LogEntryResource` instances with distinct `sequence` values (e.g. 2, 0,
   1, filenames deliberately not in sequence order, to prove sort-by-sequence rather than
   sort-by-filename). These are real resources so `test_project_load_integrity.gd` validates them
   for free.
3. `global/autoloads/log_state.gd` — the autoload, per the Design section above.
4. Register `LogState` in `project.godot`.
5. Add `"user://log_state.cfg"` to `tests/helpers/save_sandbox.gd`'s `PATHS`.
6. `tests/unit/test_log_state.gd` — see Test plan.
7. `bash /agent/verify.sh`.

Each step is independently small; 1–2 and 3–5 can land together since the autoload is untestable
without its fixture catalogue.

## Test plan

`tests/unit/test_log_state.gd`, `extends GutTest`, using `SaveSandbox` exactly like
`test_upgrade_state.gd` (`before_all(): _sandbox.capture()`, `after_all(): _sandbox.restore()`,
`_sandbox.clear_all()` at the top of any test that exercises `_load()`).

Helper: `_fresh() -> LogState` constructs `LogStateScript.new()` (tree-less, `_ready()` never
fires), sets `catalogue_dir = "res://tests/unit/fixtures/log_entries"`, and calls
`_load_catalogue()` manually. Tests that need persistence additionally call `_load()`.

- `test_total_count_is_derived_from_the_catalogue_directory` — `_fresh()` catalogue of 3 fixture
  files → `total_count() == 3`. (The behavioral proof that the total is not hand-typed: it comes
  from however many `.tres` files happen to be in the directory.)
- `test_catalogue_sorts_by_sequence_not_filename` — fixture files' `sequence` values are
  deliberately out of filename order; `collect_next()` called three times returns ids in
  `sequence` order, not filename/directory-listing order.
- `test_collect_next_collects_in_order_and_reports_it` — first `collect_next()` call returns the
  lowest-`sequence` id, marks it `is_collected() == true`, leaves the others `false`, and emits
  `log_collected` with that id exactly once.
- `test_collect_next_is_idempotent_once_everything_is_collected` (boundary) — call
  `collect_next()` `total_count()` times, then once more: the extra call returns `&""`, does not
  emit `log_collected` again, and `collected_count()` stays at `total_count()`. This is the
  "already collected" case from the task's done-when list, read as "the whole catalogue is
  already collected" rather than "collecting the same named id twice" — consistent with there
  being no id-based collect API to call twice.
- `test_collected_state_survives_a_save_load_round_trip` — `_sandbox.clear_all()`, collect two
  entries with a `writer` instance, `writer.free()`, construct a fresh `reader` instance pointed
  at the same fixture catalogue, call `_load()`, assert both are `is_collected()` and the third
  is not.
- `test_load_drops_unknown_ids_left_in_the_save_file` — `_sandbox.clear_all()`, hand-write a
  `ConfigFile` at `LogStateScript.SAVE_PATH` with one real fixture id and one id that matches no
  catalogue entry, construct a fresh instance, `_load_catalogue()` then `_load()`: the real id is
  collected, the unknown one is silently dropped (not present in `collected_ids()`,
  `collected_count() == 1`).
- `test_get_entry_returns_the_matching_resource` — `get_entry()` on a known fixture id returns a
  `LogEntryResource` whose `title`/`body` match the fixture; unknown id returns `null`.
- `test_duplicate_catalogue_id_is_dropped_not_double_counted` (boundary) — a fourth fixture
  directory (or a fixture pair sharing one `id`) where two `.tres` files declare the same `id`:
  `total_count()` still counts the id once, and `collect_next()` never gets stuck double-counting
  it against `total_count()`.

## Risks

- **Empty production catalogue**: `global/resources/logs/entries/` ships with no files this task
  (no lore content authored yet), so `LogState.total_count()` is legitimately 0 in the running
  game until a later task adds `.tres` entries. This is correct, not a bug — the derivation is
  what's being tested, not any particular count. Flagged in `1-context.md` and here so a future
  reader does not mistake it for an oversight.
- **`DirAccess.open()` on a path with zero shipped files**: Godot does not track empty
  directories in git, so `global/resources/logs/entries/` will not exist on disk until its first
  `.tres` lands. `_load_catalogue()` treats a `null` `DirAccess` as an empty catalogue (already
  handled above), so this is not a crash risk, just the reason the directory doesn't appear in
  step 1 of the build sequence.

## Out of scope

- The pickup scene/collectible that calls `collect_next()` in the world (next task in the epic).
- Any "you found a log" UI/popup.
- The ESC menu Lore Logs section.
- Information logs (the re-readable, non-persisted, non-completion type) — the task body and this
  plan are about the **lore log** persistence store only; information logs never touch `LogState`
  at all per the source idea ("not stored"), so they need no store-side work here.
- Authoring real narrative content for the production catalogue.
