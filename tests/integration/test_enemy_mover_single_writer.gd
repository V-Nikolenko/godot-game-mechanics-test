## INVARIANT test (not characterization): when an enemy has an `EnemyMover`, that mover is the
## **single writer** of the enemy's `velocity` and `rotation` and the only caller of
## `move_and_slide()` (docs/plans/cmufklb100001p92xs1ey2fb1/3-plan.md §2.4, epic review F10/N2;
## task plan docs/plans/cmug33ldn00d3m52wfe1j6fct/3-plan.md). Same shape as
## `test_ship_rotation_single_writer.gd`, which gates the player ships' rotation.
##
## Two rosters, two matchers, because the two kinds of file write in different ways:
##
## - **A — AI scripts:** every `*_brain.gd` in the project, and every `global/enemy_ai/*.gd` except
##   `enemy_mover.gd` itself. These are `Node`s / `RefCounted`s that reach the body through a
##   receiver, so only writes *through a receiver* (`actor.`, `_actor.`, `body.`, `_body.`, `self.`)
##   are forbidden. That is what lets `target_info.gd`'s `info.velocity = …` — a snapshot, not a
##   body — through without an allowlist entry (epic review N2).
## - **B — mover-driven enemy roots:** the root script of every scene that contains an
##   `EnemyMover`, **and every ancestor script** of it (`base_enemy.gd`, from the fixture on day one).
##   These *are* the `CharacterBody2D`, so bare and `self.` writes are forbidden.
##
## Forbidden in both: assignments (`=`, `+=`, `-=`, `*=`, `/=`, not `==`) to `velocity` (including
## `velocity.x`/`.y`), `rotation`, `global_rotation`, `rotation_degrees`; calls to `set_velocity(`,
## `set_rotation(`, `look_at(`, `rotate(`; and any `move_and_slide(` / `move_and_collide(`.
## Comments and string contents are blanked before matching, so a doc comment or log message quoting
## a forbidden line is not a hit.
##
## The allowlist is empty and permanent. The sanctioned route for a brain is the mover's request API
## (`request_velocity`, the Steering wrappers, `boost`, `face_toward`, `halt`).
extends GutTest

const MOVER_SCRIPT := "res://global/enemy_ai/enemy_mover.gd"
const ENEMY_AI_DIR := "res://global/enemy_ai"
const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]

## Empty and permanent. A test below asserts it stays empty.
const ALLOWLIST: Array[String] = []

const _PROPS := "(velocity(\\.[xy])?|rotation|global_rotation|rotation_degrees)"
const _ASSIGN := "\\s*(\\+=|-=|\\*=|/=|=(?!=))"
const _CALLS := "(set_velocity|set_rotation|look_at|rotate)\\s*\\("
const _RECEIVER := "\\b(actor|_actor|body|_body|self)\\."
const _BARE := "(^|[^\\w.])(self\\.)?"

var _ai_patterns: Array[RegEx] = []
var _root_patterns: Array[RegEx] = []


func before_all() -> void:
	var move := RegEx.create_from_string("\\bmove_and_(slide|collide)\\s*\\(")
	_ai_patterns = [
		RegEx.create_from_string(_RECEIVER + _PROPS + _ASSIGN),
		RegEx.create_from_string(_RECEIVER + _CALLS),
		move,
	]
	_root_patterns = [
		RegEx.create_from_string(_BARE + _PROPS + _ASSIGN),
		RegEx.create_from_string(_BARE + _CALLS),
		move,
	]


# ── Matchers ───────────────────────────────────────────────────────────────────

## `line` reduced to code: any `#` comment removed and the contents of string literals blanked,
## so neither a doc comment nor a log message quoting a forbidden line counts as a write.
func _code_only(line: String) -> String:
	var out := ""
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				out += "  "
				i += 2
				continue
			if c == quote:
				quote = ""
				out += c
			else:
				out += " "
		elif c == "\"" or c == "'":
			quote = c
			out += c
		elif c == "#":
			return out
		else:
			out += c
		i += 1
	return out


## The offending lines of `source` under `patterns`, as "line N: text".
func _hits(source: String, patterns: Array[RegEx]) -> Array[String]:
	var found: Array[String] = []
	var lines := source.split("\n")
	for n in lines.size():
		var code := _code_only(lines[n])
		for re: RegEx in patterns:
			if re.search(code) != null:
				found.append("line %d: %s" % [n + 1, lines[n].strip_edges()])
				break
	return found


func _ai_hits(source: String) -> Array[String]:
	return _hits(source, _ai_patterns)


func _root_hits(source: String) -> Array[String]:
	return _hits(source, _root_patterns)


# ── Rosters ────────────────────────────────────────────────────────────────────

func _collect(dir_path: String, suffix: String) -> Array[String]:
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
				found.append_array(_collect(full, suffix))
		elif entry.ends_with(suffix):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


## Roster A: every *_brain.gd, plus global/enemy_ai/*.gd except the mover.
func _ai_scripts() -> Array[String]:
	var found: Array[String] = _collect("res://", "_brain.gd")
	for path: String in _collect(ENEMY_AI_DIR, ".gd"):
		if path != MOVER_SCRIPT and not found.has(path):
			found.append(path)
	found.sort()
	return found


## The script on a PackedScene's root node, following an inherited scene to its base.
func _root_script(scene: PackedScene) -> Script:
	var state := scene.get_state()
	if state.get_node_count() == 0:
		return null
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"script":
			return state.get_node_property_value(0, i) as Script
	var base := state.get_node_instance(0)
	return _root_script(base) if base != null else null


## Roster B: for every scene that references the mover script, its root script and every
## `res://` ancestor of it.
func _mover_driven_root_scripts() -> Array[String]:
	var found: Array[String] = []
	for path: String in _collect("res://", ".tscn"):
		if not FileAccess.get_file_as_string(path).contains("path=\"%s\"" % MOVER_SCRIPT):
			continue
		var scene := load(path) as PackedScene
		assert_not_null(scene, "cannot load %s" % path)
		if scene == null:
			continue
		var script := _root_script(scene)
		while script != null and script.resource_path.begins_with("res://"):
			if not found.has(script.resource_path):
				found.append(script.resource_path)
			script = script.get_base_script()
	found.sort()
	return found


# ── Roster sanity (a broken glob must not read as a pass) ──────────────────────

func test_allowlist_is_empty() -> void:
	assert_eq(ALLOWLIST, [] as Array[String], "the single-writer allowlist is permanent and empty")


func test_ai_roster_includes_the_brain_base_and_target_info() -> void:
	var scripts := _ai_scripts()
	assert_has(scripts, "res://global/enemy_ai/enemy_brain.gd")
	assert_has(scripts, "res://global/enemy_ai/target_info.gd")
	assert_has(scripts, "res://tests/helpers/fixture_brain.gd")
	assert_does_not_have(scripts, MOVER_SCRIPT)


func test_root_roster_includes_the_fixture_and_its_base_enemy_ancestor() -> void:
	var scripts := _mover_driven_root_scripts()
	assert_has(scripts, "res://tests/helpers/fixture_enemy.gd")
	assert_has(scripts, "res://assault/scenes/enemies/base_enemy.gd")
	assert_does_not_have(scripts, MOVER_SCRIPT)


# ── The invariant ──────────────────────────────────────────────────────────────

func test_no_ai_script_writes_the_bodys_velocity_or_rotation() -> void:
	var report: Array[String] = []
	for path: String in _ai_scripts():
		for hit: String in _ai_hits(FileAccess.get_file_as_string(path)):
			report.append("%s %s" % [path, hit])
	assert_eq(report, [] as Array[String],
		"AI scripts must request movement from EnemyMover, never write the body:\n  "
		+ "\n  ".join(report))


func test_no_mover_driven_enemy_root_writes_its_own_velocity_or_rotation() -> void:
	var report: Array[String] = []
	for path: String in _mover_driven_root_scripts():
		for hit: String in _root_hits(FileAccess.get_file_as_string(path)):
			report.append("%s %s" % [path, hit])
	assert_eq(report, [] as Array[String],
		"an enemy with an EnemyMover must leave velocity/rotation/move_and_slide to it:\n  "
		+ "\n  ".join(report))


# ── Boundary: the matchers can fail ────────────────────────────────────────────

func test_ai_matcher_reports_writes_through_a_receiver() -> void:
	for line: String in [
		"\tactor.velocity = Vector2.ZERO",
		"\tactor.velocity.y += 1.0",
		"\t_actor.rotation -= 0.1",
		"\tself.global_rotation = 0.0",
		"\tactor.look_at(p)",
		"\tbody.rotate(0.1)",
		"\t_actor.set_velocity(v)",
		"\tmove_and_slide()",
		"\tactor.move_and_collide(v)",
	]:
		assert_eq(_ai_hits(line).size(), 1, "must be reported: %s" % line)


func test_ai_matcher_ignores_reads_snapshots_and_comments() -> void:
	for line: String in [
		"\tif actor.velocity == v:",
		"\tinfo.velocity = v",
		"\t# actor.velocity = v",
		"\tvar speed := actor.velocity.length()",
		"\tvar f := Vector2.UP.rotated(node.rotation)",
		"\tprint(\"actor.velocity = # not code\")",
	]:
		assert_eq(_ai_hits(line), [] as Array[String], "must not be reported: %s" % line)


func test_root_matcher_reports_bare_and_self_writes() -> void:
	for line: String in [
		"\trotation = 0.0",
		"\tvelocity = dir * speed",
		"\tvelocity.x = 0.0",
		"\tself.velocity += push",
		"\trotation_degrees = 90.0",
		"\trotate(0.1)",
		"\tlook_at(target)",
		"\tset_rotation(0.0)",
		"\tmove_and_slide()",
	]:
		assert_eq(_root_hits(line).size(), 1, "must be reported: %s" % line)


func test_root_matcher_ignores_child_writes_reads_and_comments() -> void:
	for line: String in [
		"\tsprite.rotation_degrees = 180.0",
		"\tvar s := velocity.x",
		"\tif velocity == Vector2.ZERO:",
		"\tvar rotation_speed := 2.0",
		"\t## rotation = heading.angle() - sprite_forward_angle",
		"\t_mover.halt()",
		"\tvar d := dir.rotated(0.5)",
	]:
		assert_eq(_root_hits(line), [] as Array[String], "must not be reported: %s" % line)
