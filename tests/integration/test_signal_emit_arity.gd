## Invariant test: a signal's declared parameter list must match how it is actually emitted.
##
## Measured on Godot 4.6.3 (see `tests/README.md`'s "signal-arity trap" note): the engine never
## checks a signal's declaration against its `emit()` call sites. `signal foo` and
## `signal foo(x: int)` behave identically at emit time; the only place the declared arity is
## visible at all is `Object.get_signal_list()`. `Health.amount_changed` and `State.state_transition`
## drifted exactly this way — declared with zero parameters while emitted with one — until the
## 2026-09-03 fix, each now pinned by its own hand-written `get_signal_list()` assertion
## (`test_health_component.gd::test_amount_changed_declares_the_int_it_emits`,
## `test_state_machine.gd::test_state_transition_declares_the_state_it_emits`). This file
## generalizes that check to every signal in the project instead of relying on someone
## hand-writing the next one.
##
## Scope: **self-emits only** — `name.emit(...)` where `name` is a signal declared in the *same*
## file, found while writing this test to be by far the common case (~70 of ~150 `.emit(` call
## sites project-wide). A member-access emit (`hb.received_damage.emit(...)`,
## `EventBus.score_changed.emit(...)`, `t.destroyed.emit(t)`) needs the static type of the LHS
## resolved across files to know which declaration to check against — real type inference, not a
## text sweep — and is deliberately left uncovered rather than attempted with an approach likely
## to false-positive on legitimate cross-file emits. `emit_signal("name", ...)`, Godot 4's
## string-based emit form, is also unscanned; it is unused anywhere in the project today.
##
## Declared arity is scoped **per file**, never merged project-wide: `signal died` is declared
## bare (arity 0) in three different files but takes one `Vector2` argument in a fourth
## (`asteroid_base.gd`). A global name→arity map would false-positive on every bare `died.emit()`
## the moment any file in the project declares a parameterized `died`.
##
## First real run of this test caught a live instance of exactly the drift it exists to prevent:
## `MovementController.action_single_press` / `action_double_press` were declared bare while every
## `.emit()` call and every `.connect()`'d handler already agreed on one `String` argument. Fixed
## alongside this test, same shape as the 2026-09-03 fix — a declaration-only change, since arity
## is documentation only and neither the emitter nor any handler needed to change.
extends GutTest

const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]

## Comment-stripped file text must be searched for declarations and self-emit call sites — see
## `_strip_comment()` — but argument counting for a matched call must run against the
## **original** text, because a call can span multiple lines
## (`assault/scenes/race/track/dash_panel.gd`'s `body_wall_hit.emit(...)` continues onto the next
## line) and comment-stripping is a per-line operation that would otherwise have to be re-joined.
var _signal_re: RegEx
## Captures the identifier immediately before `.emit(`, but only when it is not itself accessed
## through a member (`hb.received_damage.emit(` does not match: the character before
## `received_damage` is the `.` from `hb.`, which fails both alternatives in the leading group).
var _self_emit_re: RegEx

## Every self-emit call site checked, as {file, line, name, declared, actual}. Built once in
## `before_all()` so all assertions below share one project walk.
var _sites: Array[Dictionary] = []


func before_all() -> void:
	_signal_re = RegEx.create_from_string("^\\s*signal\\s+(\\w+)\\s*(\\(([^)]*)\\))?")
	_self_emit_re = RegEx.create_from_string("(^|[^.\\w])(\\w+)\\.emit\\s*\\(")

	for file_path: String in _collect_gd_files("res://"):
		_sites.append_array(_scan_file(file_path))


## Removes everything from the first `#` not inside a quoted string onward. A comment can legally
## contain anything, including text that looks like a signal declaration or an emit call with the
## wrong arity — see `space_station.gd`'s and `test_health_component.gd`'s doc comments, both of
## which happen to dodge this only by accident today.
func _strip_comment(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var c := line[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
			i += 1
			continue
		if c == "\"" or c == "'":
			quote = c
			i += 1
			continue
		if c == "#":
			return line.substr(0, i)
		i += 1
	return line


## Number of top-level, comma-separated entries in a signal's parameter list, or 0 for an empty
## (or absent) one. Bracket-depth-aware so a generic type argument's comma
## (`order: Array[RaceParticipant, int]`-shaped params, hypothetically) is never mistaken for a
## parameter separator.
static func _count_params(param_list: String) -> int:
	var trimmed := param_list.strip_edges()
	if trimmed.is_empty():
		return 0
	var depth := 0
	var count := 1
	for c: String in trimmed:
		if c == "[" or c == "(" or c == "{":
			depth += 1
		elif c == "]" or c == ")" or c == "}":
			depth -= 1
		elif c == "," and depth == 0:
			count += 1
	return count


## Number of top-level, comma-separated arguments in a call whose `(` sits at `open_paren_index`
## in `text`. Depth- and quote-aware, so a nested call/array/dictionary argument
## (`race_finished.emit(_results.duplicate())`) and a string literal containing a comma
## (`score_event.emit(pos, points, "kill" if x else "bonus_target")`-shaped calls) are both
## counted correctly, and the scan is not line-based, so a call spanning multiple lines is too.
static func _count_call_args(text: String, open_paren_index: int) -> int:
	var i := open_paren_index + 1
	var depth := 1
	var count := 0
	var has_content := false
	var quote := ""
	while i < text.length():
		var c := text[i]
		if quote != "":
			if c == "\\":
				i += 2
				continue
			if c == quote:
				quote = ""
			i += 1
			continue
		if c == "\"" or c == "'":
			quote = c
			has_content = true
			i += 1
			continue
		if c == "(" or c == "[" or c == "{":
			depth += 1
			has_content = true
			i += 1
			continue
		if c == ")" or c == "]" or c == "}":
			depth -= 1
			if depth == 0:
				break
			has_content = true
			i += 1
			continue
		if c == "," and depth == 1:
			count += 1
			i += 1
			continue
		if not c.strip_edges().is_empty():
			has_content = true
		i += 1
	if has_content:
		count += 1
	return count


## Every self-emit call site in `path` whose signal is declared in the same file, as
## {file, line, name, declared, actual}. Call sites whose name matches no local declaration
## (a member-access emit, or a false match on an unrelated `.emit(` such as a `Tween`) are
## silently skipped — this file only asserts what it can resolve from the same file.
func _scan_file(path: String) -> Array[Dictionary]:
	var text := FileAccess.get_file_as_string(path)
	var lines := text.split("\n")

	## Absolute offset of each line's first character in `text`, so a match found in a
	## comment-stripped *line* can still be turned into an index into the original *file* text.
	var line_offsets: Array[int] = []
	var offset := 0
	for line: String in lines:
		line_offsets.append(offset)
		offset += line.length() + 1

	var declared: Dictionary = {}
	for line: String in lines:
		var stripped := _strip_comment(line)
		var m := _signal_re.search(stripped)
		if m == null:
			continue
		var has_parens := m.get_string(2) != ""
		declared[m.get_string(1)] = _count_params(m.get_string(3)) if has_parens else 0

	var found: Array[Dictionary] = []
	for i: int in lines.size():
		var stripped := _strip_comment(lines[i])
		for match_result: RegExMatch in _self_emit_re.search_all(stripped):
			var name := match_result.get_string(2)
			if not declared.has(name):
				continue
			var open_paren_index := line_offsets[i] + match_result.get_end() - 1
			found.append({
				"file": path,
				"line": i + 1,
				"name": name,
				"declared": declared[name],
				"actual": _count_call_args(text, open_paren_index),
			})
	return found


func _collect_gd_files(dir_path: String) -> Array[String]:
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
				found.append_array(_collect_gd_files(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found


func test_the_walk_actually_found_self_emit_sites_to_check() -> void:
	# Without this the assertion below would pass trivially if the walk ever broke.
	assert_gt(_sites.size(), 30, "expected well over 30 checkable self-emit call sites")


func test_all_self_emits_match_their_declared_arity() -> void:
	var mismatched: Array[String] = []
	for site: Dictionary in _sites:
		if site["declared"] != site["actual"]:
			mismatched.append("%s:%d  %s declared %d arg(s), emitted with %d" % [
				site["file"], site["line"], site["name"], site["declared"], site["actual"],
			])
	assert_eq(mismatched, [] as Array[String],
		"signals emitted with a different arity than declared:\n    " + "\n    ".join(mismatched))


func test_helper_counts_top_level_args_with_no_args() -> void:
	var text := "emit()"
	assert_eq(_count_call_args(text, text.find("(")), 0)


func test_helper_counts_top_level_args_across_multiple_lines() -> void:
	## Modeled on assault/scenes/race/track/dash_panel.gd:83-84.
	var text := (
		"body_wall_hit.emit(ship, part, dir_l if dir_l != 0.0 else 1.0,\n"
		+ "\twall_damage, wall_pushback)"
	)
	assert_eq(_count_call_args(text, text.find("(")), 5,
		"a call spanning multiple lines must not be undercounted by a line-based split")


func test_helper_does_not_split_a_comma_inside_a_string_argument() -> void:
	var text := 'score_event.emit(kill_pos, points, "kill" if counts else "bonus_target")'
	assert_eq(_count_call_args(text, text.find("(")), 3,
		"a comma inside a string literal argument is not an argument separator")


func test_declared_arity_ignores_a_trailing_comment() -> void:
	var stripped := _strip_comment("signal foo(x: int)  ## some, note, with, commas")
	var m := _signal_re.search(stripped)
	assert_eq(_count_params(m.get_string(3)), 1,
		"a trailing comment's commas must not inflate the declared arity")


func test_declared_arity_handles_a_nested_generic_param() -> void:
	var m := _signal_re.search("signal foo(order: Array[int], other: int)")
	assert_eq(_count_params(m.get_string(3)), 2,
		"the comma inside Array[int] is not a parameter separator")


func test_comment_stripping_does_not_hide_a_real_self_emit() -> void:
	## A decoy comment describing the (wrong) usage sits above a real, mismatched call. The strip
	## must remove only the comment text, never the call site beneath it.
	var lines := [
		"signal foo(x: int)",
		"## foo.emit() takes zero args",
		"foo.emit(1, 2)",
	]
	var text := "\n".join(lines)
	var declared := {}
	for line: String in lines:
		var stripped := _strip_comment(line)
		var m := _signal_re.search(stripped)
		if m != null:
			declared[m.get_string(1)] = (
				_count_params(m.get_string(3)) if m.get_string(2) != "" else 0
			)
	assert_eq(declared.get("foo"), 1, "the real declaration must still be found")

	var offset: int = lines[0].length() + 1 + lines[1].length() + 1
	var call_stripped := _strip_comment(lines[2])
	var call_match := _self_emit_re.search(call_stripped)
	assert_not_null(call_match, "the real call site must still be found, not eaten by the strip")
	var open_paren_index: int = offset + call_match.get_end() - 1
	assert_eq(_count_call_args(text, open_paren_index), 2,
		"and its actual argument count must still be read correctly")
