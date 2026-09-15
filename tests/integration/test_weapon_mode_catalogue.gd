## Invariant test: every `.tres` in `assault/scenes/player/weapons/modes/` is reachable.
##
## `WeaponState._load_modes()` walks `UpgradeState.ALL_IDS` and loads `<id>.tres` — it never
## looks at what's actually on disk in `weapons/modes/`. A `.tres` whose filename has no matching
## entry in `ALL_IDS` is therefore never loaded: it cannot be selected, cycled to, or shown in the
## player menu, and nothing fails or warns. `long_range.tres` sat in this state until removed
## (`docs/plans/.../code-health-backlog`); this sweep is a directory listing rather than a
## hand-written roster so a future orphan is caught the day it lands instead of the next audit.
extends GutTest

const MODES_DIR := "res://assault/scenes/player/weapons/modes"
const UpgradeStateScript := preload("res://global/autoloads/upgrade_state.gd")


func test_every_weapon_mode_tres_has_a_matching_all_ids_entry() -> void:
	var dir := DirAccess.open(MODES_DIR)
	assert_not_null(dir, "cannot open %s" % MODES_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		if not file.ends_with(".tres"):
			continue
		var id := StringName(file.trim_suffix(".tres"))
		assert_true(id in UpgradeStateScript.ALL_IDS,
			"%s has no matching id in UpgradeState.ALL_IDS, so it can never be loaded" % file)


func test_every_all_ids_entry_has_a_matching_tres_on_disk() -> void:
	for id: StringName in UpgradeStateScript.ALL_IDS:
		var path := "%s/%s.tres" % [MODES_DIR, id]
		assert_true(ResourceLoader.exists(path), "ALL_IDS names '%s' but %s does not exist" % [id, path])
