## Integrity test over every `[ext_resource]` reference in the project's scenes and resources.
##
## Godot 4 writes each reference twice: a `uid://…` and a `res://…` text path. The UID is
## authoritative — the text path is only a fallback, used with a warning when the UID resolves to
## nothing. So when the two disagree the project still loads and nothing looks broken, but the
## safety net is gone: move or rename the target and the reference dies for real.
##
## Hand-edited scenes drift into exactly this state, because a UID cannot be written by hand — it
## is minted by the editor. Every mismatch this test caught on its first run was an invented,
## dangling UID (`uid://level2wavesscript`, `uid://bospm3nuos001`, `uid://b7p4usem3nu02`) or a UID
## left behind after its target was reassigned a new one.
##
## Unlike the rest of `tests/`, this is NOT a characterization test. It asserts a property that
## must hold, so a new mismatch is a regression rather than a documented quirk.
##
## **Declared UIDs are read from disk, never from `ResourceUID` / `ResourceLoader`.** Those consult
## `.godot/uid_cache.bin`, which is gitignored and which also keeps *stale* UIDs registered as
## working aliases once a warm project has loaded them. Asking the engine therefore gives an
## answer that depends on cache warmth: five of the mismatches below report as perfectly fine on a
## warm cache and fail on a fresh clone. The files on disk are the only source of truth that
## travels with the repository.
##
## `addons/` is excluded deliberately: vendored third-party code is not ours to police.
extends GutTest

const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]

## Every ext_resource reference found, as {file, line, path, ref_uid}.
var _references: Array[Dictionary] = []
## Files actually scanned — guards against a silently empty walk making every test vacuous.
var _scanned_files: int = 0

var _uid_re: RegEx
var _path_re: RegEx


func before_all() -> void:
	_uid_re = RegEx.create_from_string('uid="(uid://[^"]+)"')
	_path_re = RegEx.create_from_string('path="(res://[^"]+)"')

	for file_path: String in _collect_resource_files("res://"):
		_scanned_files += 1
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
			line_number += 1
			if not line.begins_with("[ext_resource"):
				continue
			var path_match := _path_re.search(line)
			if path_match == null:
				continue
			var uid_match := _uid_re.search(line)
			_references.append({
				"file": file_path,
				"line": line_number,
				"path": path_match.get_string(1),
				# A reference may legitimately carry no UID at all; only the pairing is checked.
				"ref_uid": "" if uid_match == null else uid_match.get_string(1),
			})


## Recursive walk of the project tree returning every `.tscn` / `.tres`.
func _collect_resource_files(dir_path: String) -> Array[String]:
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
				found.append_array(_collect_resource_files(full))
		elif entry.ends_with(".tscn") or entry.ends_with(".tres"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## The UID a resource declares *on disk*, or "" if it declares none.
##
## Three storage formats, one per kind of resource:
##   `.tscn` / `.tres` — in the `[gd_scene]` / `[gd_resource]` header line.
##   `.gd`             — in a sibling `<script>.gd.uid` file holding just the UID.
##   everything else   — in the sibling `<asset>.import` file generated on import.
func _declared_uid_for(path: String) -> String:
	if path.ends_with(".tscn") or path.ends_with(".tres"):
		var header := FileAccess.get_file_as_string(path).split("\n")[0]
		var m := _uid_re.search(header)
		return "" if m == null else m.get_string(1)

	var sidecar := path + (".uid" if path.ends_with(".gd") else ".import")
	if not FileAccess.file_exists(sidecar):
		return ""
	var text := FileAccess.get_file_as_string(sidecar).strip_edges()
	if sidecar.ends_with(".uid"):
		return text
	# `.import` files carry several key=value lines; the UID is the one on its own line.
	for line: String in text.split("\n"):
		if line.begins_with("uid="):
			var m := _uid_re.search(line)
			if m != null:
				return m.get_string(1)
	return ""


func test_the_walk_actually_found_the_projects_scenes() -> void:
	# Without this the tests below would pass trivially if the walk ever broke.
	assert_gt(_scanned_files, 100,
		"expected the project to contain well over 100 .tscn/.tres files outside addons/")
	assert_gt(_references.size(), 100, "expected well over 100 ext_resource references")


func test_every_ext_resource_path_points_at_a_file_that_exists() -> void:
	var broken: Array[String] = []
	for ref: Dictionary in _references:
		if not FileAccess.file_exists(ref["path"]):
			broken.append("%s:%d -> %s" % [ref["file"], ref["line"], ref["path"]])
	assert_eq(broken, [] as Array[String],
		"ext_resource paths that resolve to nothing:\n  " + "\n  ".join(broken))


func test_every_ext_resource_uid_matches_the_uid_its_target_declares() -> void:
	var mismatched: Array[String] = []
	for ref: Dictionary in _references:
		var ref_uid: String = ref["ref_uid"]
		if ref_uid.is_empty():
			continue  # No UID written; Godot falls back to the path, which is checked above.
		var declared_uid := _declared_uid_for(ref["path"])
		if declared_uid.is_empty():
			continue  # Target declares no UID of its own, so there is nothing to disagree with.
		if declared_uid != ref_uid:
			mismatched.append("%s:%d\n      path = %s\n      ref  = %s\n      real = %s" % [
				ref["file"], ref["line"], ref["path"], ref_uid, declared_uid,
			])
	assert_eq(mismatched, [] as Array[String],
		"ext_resource UIDs disagreeing with their target's declared UID:\n    "
		+ "\n    ".join(mismatched))
