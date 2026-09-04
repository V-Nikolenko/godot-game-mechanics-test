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
## Four properties are checked, all from files alone: a reference's UID agrees with its target's,
## a reference's UID exists *somewhere* in the tree, no two files claim the same UID, and the
## UID-only references in `project.godot` / `export_presets.cfg` — which have no path to fall back
## to — resolve.
##
## **Declared UIDs are read from disk, never from `ResourceUID` / `ResourceLoader`.** Those consult
## `.godot/uid_cache.bin`, which is gitignored and which also keeps *stale* UIDs registered as
## working aliases once a warm project has loaded them. Asking the engine therefore gives an
## answer that depends on cache warmth: five of the mismatches below report as perfectly fine on a
## warm cache and fail on a fresh clone. The files on disk are the only source of truth that
## travels with the repository — and note that `/agent/verify.sh` itself always runs warm, so its
## import and boot steps cannot be relied on to surface any of this.
##
## `addons/` is excluded deliberately when *scanning references*: vendored third-party code is not
## ours to police. It is still indexed for *declarations*, because our scenes legitimately point at
## resources vendored under `addons/` and a UID there is a perfectly valid target.
extends GutTest

const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]
## The declaration index walks everything our own scenes may point at, `addons/` included.
const SKIPPED_DIRS_FOR_DECLARATIONS: Array[String] = [".godot", ".git", ".import"]

## Config files that name a resource by UID **and nothing else** — there is no `res://` fallback
## line beside them, so a stale UID here is not a degraded reference, it is a hard failure on a
## cold cache. `run/main_scene` is the one that stops the game booting at all.
const UID_ONLY_CONFIG_FILES: Array[String] = ["res://project.godot", "res://export_presets.cfg"]

## Floors for the two mass-strip canaries at the bottom of this file; see the comment there.
const MIN_REFERENCES_WITH_A_UID := 250
const MIN_FILES_DECLARING_A_UID := 75
## Vacuity floor for the declaration index; the whole tree declares ~750 UIDs today.
const MIN_UIDS_IN_DECLARATION_INDEX := 300

## Every ext_resource reference found, as {file, line, path, ref_uid}.
var _references: Array[Dictionary] = []
## Files actually scanned — guards against a silently empty walk making every test vacuous.
var _scanned_files: int = 0
## Of those, how many declare a `uid://…` of their own in their header line.
var _files_declaring_a_uid: int = 0
## `uid://…` → every file on disk declaring it. Built over the whole tree, `addons/` included.
## More than one owner for a UID is a collision, and which one wins depends on scan order.
var _declared_by_uid: Dictionary = {}

var _uid_re: RegEx
var _path_re: RegEx
## A bare quoted UID, with no `uid=` key in front of it — how `project.godot` and
## `export_presets.cfg` write theirs (`run/main_scene="uid://bj5rbqgudkfsg"`).
var _quoted_uid_re: RegEx


func before_all() -> void:
	_uid_re = RegEx.create_from_string('uid="(uid://[^"]+)"')
	_path_re = RegEx.create_from_string('path="(res://[^"]+)"')
	_quoted_uid_re = RegEx.create_from_string('"(uid://[^"]+)"')

	_build_declaration_index()

	for file_path: String in _collect_resource_files("res://"):
		_scanned_files += 1
		if not _declared_uid_for(file_path).is_empty():
			_files_declaring_a_uid += 1
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


## Index every UID the tree declares, mapped back to the file(s) declaring it.
##
## This is the piece that lets a UID be checked for existing *at all*, rather than only against
## the one file a reference happens to name. `.godot/uid_cache.bin` answers that question too —
## and answers it wrongly, keeping a dead UID alive as an alias for as long as the cache stays
## warm — so the index is built from files, exactly like everything else in here.
func _build_declaration_index() -> void:
	for asset_path: String in _collect_all_files("res://", SKIPPED_DIRS_FOR_DECLARATIONS):
		# Sidecars declare on behalf of the asset beside them, and that asset is visited too.
		if asset_path.ends_with(".uid") or asset_path.ends_with(".import"):
			continue
		var uid := _declared_uid_for(asset_path)
		if uid.is_empty():
			continue
		if not _declared_by_uid.has(uid):
			_declared_by_uid[uid] = [] as Array[String]
		(_declared_by_uid[uid] as Array[String]).append(asset_path)


## Recursive walk returning every file under `dir_path`, whatever its extension.
func _collect_all_files(dir_path: String, skipped_dirs: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not (entry.begins_with(".") or skipped_dirs.has(entry)):
				found.append_array(_collect_all_files(full, skipped_dirs))
		else:
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


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


func test_the_declaration_index_actually_found_the_projects_uids() -> void:
	# Without this the three tests below pass trivially if the whole-tree walk ever breaks.
	assert_gte(_declared_by_uid.size(), MIN_UIDS_IN_DECLARATION_INDEX,
		("the UID declaration index holds only %d entries — the whole-tree walk has broken, and "
		+ "every check built on it is now vacuous") % _declared_by_uid.size())


## The dangling-UID check the pairwise test above cannot make.
##
## `test_every_ext_resource_uid_matches_the_uid_its_target_declares` compares a reference against
## *one* file: the one its `path=` names. When that file declares no UID of its own it `continue`s,
## because there is nothing to disagree with — so a reference carrying a UID that exists nowhere in
## the project slips through it untouched. Godot on a cold cache does not slip: it prints
## `ext_resource, invalid UID` and falls back to the path.
##
## A warm `.godot/uid_cache.bin` hides that, which is the whole reason this check reads the tree
## instead of asking `ResourceUID.has_id()`: the cache keeps a UID resolving long after the file
## that justified it stopped saying so, `--import` warns about nothing, and `.godot/` is gitignored
## — so CI and fresh clones see a breakage the developer's machine does not.
##
## Note the limit of *this* check, which the two tests at the bottom of the file exist to cover:
## "declared by no file" is decided on UID **text**. A reference can spell a UID differently from
## the file declaring it and still mean the identical 64-bit id, and this test calls that dangling
## when it is not. Five `.tres` files under `open_space/scenes/mission_data/planets/` were exactly
## that case — they referenced `uid://bi366j2tsyby` while the sidecar declared
## `uid://d5wyr8hce0t2q`, two spellings of id 88460944458999674 — and the two were reconciled by
## canonicalising both to `uid://bi366j2tsyby`, not by treating either as dead.
func test_every_ext_resource_uid_resolves_to_a_resource_on_disk() -> void:
	var dangling: Array[String] = []
	for ref: Dictionary in _references:
		var ref_uid: String = ref["ref_uid"]
		if ref_uid.is_empty():
			continue  # No UID written; Godot falls back to the path, which is checked above.
		if not _declared_by_uid.has(ref_uid):
			dangling.append("%s:%d\n      path = %s\n      ref  = %s (declared by no file)" % [
				ref["file"], ref["line"], ref["path"], ref_uid,
			])
	assert_eq(dangling, [] as Array[String],
		("ext_resource UIDs that no file in the project declares — these load only while a warm "
		+ ".godot/uid_cache.bin keeps them aliased:\n    ") + "\n    ".join(dangling))


## Two files must never claim the same UID.
##
## Nothing on disk resolves the tie; whichever the engine scanned last wins, so a reference to the
## shared UID silently loads the wrong resource, and *which* wrong resource can differ between a
## fresh clone and a warm one. Copying a `.tscn` or a `.gd.uid` sidecar by hand is the usual way in.
##
## Collisions entirely inside `addons/` are left alone, per this file's rule about vendored code.
func test_no_two_resources_declare_the_same_uid() -> void:
	var collisions: Array[String] = []
	for uid: String in _declared_by_uid:
		var owners: Array[String] = _declared_by_uid[uid]
		if owners.size() < 2:
			continue
		if owners.all(func(p: String) -> bool: return p.begins_with("res://addons/")):
			continue
		collisions.append("%s declared by:\n      %s" % [uid, "\n      ".join(owners)])
	assert_eq(collisions, [] as Array[String],
		"UIDs claimed by more than one file:\n    " + "\n    ".join(collisions))


## `project.godot` and `export_presets.cfg` reference resources by UID with **no path fallback**.
##
## `run/main_scene="uid://bj5rbqgudkfsg"` is the sharpest case: there is no `res://` beside it to
## degrade to, so a stale UID there is not a warning, it is a project that does not boot. Step 2 of
## `/agent/verify.sh` boots the game headless and would catch it — but only on a cold cache, and
## the gate always runs warm. This check does not care either way.
func test_uid_only_config_references_resolve() -> void:
	var checked := 0
	var dangling: Array[String] = []
	for config_path: String in UID_ONLY_CONFIG_FILES:
		if not FileAccess.file_exists(config_path):
			continue  # export_presets.cfg is optional; project.godot is covered by the floor below.
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(config_path).split("\n"):
			line_number += 1
			for match_result: RegExMatch in _quoted_uid_re.search_all(line):
				var uid := match_result.get_string(1)
				checked += 1
				if not _declared_by_uid.has(uid):
					dangling.append("%s:%d -> %s (declared by no file)" % [
						config_path, line_number, uid,
					])
	assert_gt(checked, 0,
		("found no uid:// reference in %s — project.godot has always carried run/main_scene as a "
		+ "UID, so this check has gone blind") % ", ".join(UID_ONLY_CONFIG_FILES))
	assert_eq(dangling, [] as Array[String],
		"UID-only config references that resolve to nothing:\n    " + "\n    ".join(dangling))


## A canary against a *mass strip* of UIDs, which none of the tests above can see.
##
## The two checks above are both pairwise, and both `continue` when a UID is absent: a reference
## with no `uid=` falls through to its path, and a target that declares none has nothing to
## disagree with. So a change that deletes every UID in the project passes them **perfectly**,
## having destroyed the exact thing they exist to protect.
##
## That is not hypothetical. The Godot MCP `update_project_uids` tool resaves scenes through
## `load()` + `ResourceSaver.save()`, and a scene resaved that way headlessly comes back with no
## `uid=` on its header and none on any `[ext_resource]` line. Pointed at `res://` by hand on a
## scratch clone it rewrote 111 of the 155 `.tscn`/`.tres` files in the tree that way (it also
## deletes every comment in them). As the MCP actually calls it the tool is a harmless no-op —
## see `tests/README.md` → *"Never run the Godot MCP `update_project_uids` tool"*.
##
## These floors are canaries, not budgets. They sit well under today's counts (332 of 485
## references, 98 of 130 files, on 2026-09-04), so ordinary hand-authoring drift — this project has
## plenty of legitimately UID-less references — never trips them, while a wholesale strip takes
## both to zero. Raise them if they ever start to look tight; never lower one to make a red run
## green.
func test_the_project_has_not_had_its_reference_uids_stripped() -> void:
	var with_uid := 0
	for ref: Dictionary in _references:
		if not (ref["ref_uid"] as String).is_empty():
			with_uid += 1
	assert_gte(with_uid, MIN_REFERENCES_WITH_A_UID,
		("only %d of %d ext_resource references still carry a uid:// — a mass UID strip looks "
		+ "exactly like this, and every other test in this file stays green through it. "
		+ "See tests/README.md on update_project_uids.") % [with_uid, _references.size()])


func test_the_project_has_not_had_its_declared_uids_stripped() -> void:
	assert_gte(_files_declaring_a_uid, MIN_FILES_DECLARING_A_UID,
		("only %d of %d .tscn/.tres files still declare a uid:// in their header — a mass UID "
		+ "strip looks exactly like this. See tests/README.md on update_project_uids.")
		% [_files_declaring_a_uid, _scanned_files])


## Every UID we write must be one the editor could have *minted*.
##
## `uid://…` is not an opaque label — it is base-34 text for a 64-bit integer, and the integer is
## the only thing Godot stores or matches on. `ResourceUID.text_to_id()` decodes it with a digit
## alphabet of `a`–`y` then `0`–`8`, which is 25 + 9 = 34 symbols. Two consequences follow, and
## both are invisible to every text-comparing check above:
##
##   * **`z` and `9` are not in the alphabet.** `z` decodes to the same digit as `0` and `9` to the
##     same digit as `8` *with a carry*, so `uid://az` and `uid://a0` are the same UID spelled two
##     ways. `cutscenes/base/dialog_presenter.tscn` carried `uid://b8h6n2q5m4y9j`, which is really
##     `uid://b8h6n2q5m40aj`.
##   * **Long text silently wraps.** Anything past ~13 characters overflows 64 bits and is masked,
##     so `uid://braceasteroid01` is really `uid://ctmejjlwnwajg`. `uid://a1b2c3d4e5f6g` loses its
##     leading `a` (digit zero) and is really `uid://1b2c3d4e5f6g`.
##
## So a hand-typed UID can be an *alias* for a UID some other resource legitimately owns, and
## nothing on disk shows it: the two strings differ, `test_no_two_resources_declare_the_same_uid`
## compares strings, and the collision only appears once the engine has decoded both to the same
## integer — at which point one of the two resources loads in place of the other. Round-tripping
## the text through the integer is the only way to see it coming.
##
## `text_to_id()` / `id_to_text()` are pure encoding functions — unlike `ResourceUID.has_id()` and
## `ResourceLoader.get_resource_uid()` they never consult `.godot/uid_cache.bin`, so using them
## here does not break this file's read-from-disk rule.
##
## Malformed text falls out of the same check for free: `text_to_id()` returns `-1` for a
## character outside the alphabet, and `id_to_text(-1)` is `uid://<invalid>`.
func test_every_uid_the_project_writes_is_canonical() -> void:
	var aliases: Array[String] = []
	for uid: String in _uids_we_author():
		var canonical := ResourceUID.id_to_text(ResourceUID.text_to_id(uid))
		if canonical == uid:
			continue
		aliases.append("%s\n      really  = %s\n      written in %s" % [
			uid, canonical, ", ".join(_uids_we_author()[uid]),
		])
	assert_eq(aliases, [] as Array[String],
		("uid:// text the editor would never mint — each is an alias that decodes to a different "
		+ "UID than it spells:\n    ") + "\n    ".join(aliases))


## The collision check `test_no_two_resources_declare_the_same_uid` cannot make.
##
## That test compares UID *text*. This one decodes first, so two resources spelling the same
## 64-bit id differently — the exact wreckage the canonicality test above is designed to prevent
## reaching this point — still shows up as what it is: two files claiming one UID, with load order
## deciding which one a reference actually gets.
##
## Kept separate from the canonicality test on purpose. A non-canonical UID that collides with
## nothing is untidy; one that collides silently swaps a resource at load time. They are different
## severities and deserve different failure messages.
func test_no_two_resources_decode_to_the_same_uid() -> void:
	var owners_by_id: Dictionary = {}
	for uid: String in _declared_by_uid:
		var id := ResourceUID.text_to_id(uid)
		if not owners_by_id.has(id):
			owners_by_id[id] = {} as Dictionary
		for owner: String in _declared_by_uid[uid] as Array[String]:
			(owners_by_id[id] as Dictionary)[owner] = uid

	var collisions: Array[String] = []
	for id: int in owners_by_id:
		var owners: Dictionary = owners_by_id[id]
		if owners.size() < 2:
			continue
		if owners.keys().all(func(p: String) -> bool: return p.begins_with("res://addons/")):
			continue  # Vendored code is not ours to police; see this file's header.
		var lines: Array[String] = []
		for owner: String in owners:
			lines.append("%s (as %s)" % [owner, owners[owner]])
		collisions.append("%s decoded from %d spellings by:\n      %s" % [
			ResourceUID.id_to_text(id), owners.size(), "\n      ".join(lines),
		])
	assert_eq(collisions, [] as Array[String],
		("UIDs that decode to one id despite being written differently — whichever file the engine "
		+ "scans last wins:\n    ") + "\n    ".join(collisions))


## Every `uid://` string this project authors, mapped to where it is written.
##
## Declarations *and* references, because the two drift independently: a reference can carry an
## alias while its target's header is canonical, and `test_every_ext_resource_uid_matches_the_uid_
## its_target_declares` compares them as text and sees nothing wrong.
##
## `addons/` declarations are excluded — vendored code is not ours to fix — but our references
## *into* `addons/` are included, because we are the ones who wrote them.
func _uids_we_author() -> Dictionary:
	var written_in: Dictionary = {}
	for uid: String in _declared_by_uid:
		for owner: String in _declared_by_uid[uid] as Array[String]:
			if owner.begins_with("res://addons/"):
				continue
			if not written_in.has(uid):
				written_in[uid] = [] as Array[String]
			(written_in[uid] as Array[String]).append(owner)
	for ref: Dictionary in _references:
		var ref_uid: String = ref["ref_uid"]
		if ref_uid.is_empty():
			continue
		if not written_in.has(ref_uid):
			written_in[ref_uid] = [] as Array[String]
		var origin := "%s:%d" % [ref["file"], ref["line"]]
		if not (written_in[ref_uid] as Array[String]).has(origin):
			(written_in[ref_uid] as Array[String]).append(origin)
	return written_in
