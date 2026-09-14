## INVARIANT test (not characterization): `global/ship_modules/*.gd` must never write an actor's
## `rotation` directly.
##
## `open_space/mouse-aiming` plan (`docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/3-plan.md`,
## "Decision: exactly one writer of the ship's rotation, enforced by a test") made
## `ShipTurnController` the only writer of the open-space ship's `rotation`, and `AssaultPlayer`'s
## own one-liner the only writer of the assault fighter's. A ship module that assigns
## `actor.rotation` directly fights whichever of those owns it — exactly what
## `ai_targeting_module.gd:38` did before it was rewritten to call the duck-typed `face_instant()`
## every player class now exposes (same precedent as `Bullet.is_armored()` in `CLAUDE.md`).
## Allowlist is empty and stays empty: the sanctioned route for a module that needs to turn an
## actor is `face_instant()`, not a rotation write of any kind.
##
## Reverting the duck-typed call in `ai_targeting_module.gd` back to `actor.rotation = ...` must
## make this test fail — verified by hand before this test was committed.
extends GutTest

const MODULES_DIR := "res://global/ship_modules"

## Matches `actor.rotation` (or any identifier) followed by `=`, `+=` or `-=`, but not `==`.
## `\bROTATION_RE\b` intentionally has no anchor on the receiver name — a future module could call
## its actor parameter anything.
var _rotation_write_re: RegEx


func before_all() -> void:
	_rotation_write_re = RegEx.create_from_string("\\.rotation\\s*(\\+=|-=|=(?!=))")


func _module_scripts() -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(MODULES_DIR)
	assert_not_null(dir, "cannot open %s" % MODULES_DIR)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append("%s/%s" % [MODULES_DIR, file])
	return found


func test_sweep_finds_a_non_zero_number_of_module_files() -> void:
	## Boundary: a broken glob that silently matches nothing must not read as a pass.
	var scripts := _module_scripts()
	assert_gt(scripts.size(), 0, "expected to find ship module scripts under %s" % MODULES_DIR)


func test_sweep_includes_ai_targeting_module_by_name() -> void:
	## Boundary: the one module this rule was written for must actually be in the roster.
	var scripts := _module_scripts()
	var names: Array[String] = []
	for path: String in scripts:
		names.append(path.get_file())
	assert_true(
		names.has("ai_targeting_module.gd"),
		"expected ai_targeting_module.gd among swept module scripts, found: %s" % [names]
	)


func test_no_ship_module_assigns_to_rotation() -> void:
	var scripts := _module_scripts()
	for path: String in scripts:
		var text := FileAccess.get_file_as_string(path)
		var result := _rotation_write_re.search(text)
		assert_null(
			result,
			(
				"%s assigns to .rotation directly - ship modules must call face_instant() "
				+ "instead, so they do not fight the actor's single rotation writer"
			) % path
		)


func _declares_method(script: GDScript, method_name: String) -> bool:
	for m: Dictionary in script.get_script_method_list():
		if m.get("name") == method_name:
			return true
	return false


func test_open_space_player_ship_exposes_face_instant() -> void:
	var script: GDScript = load("res://open_space/scenes/entities/player/player_ship.gd")
	assert_true(
		_declares_method(script, "face_instant"),
		"OpenSpacePlayerShip must expose face_instant() as the sanctioned rotation-write route"
	)


func test_assault_player_exposes_face_instant() -> void:
	var script: GDScript = load("res://assault/scenes/player/player_fighter.gd")
	assert_true(
		_declares_method(script, "face_instant"),
		"AssaultPlayer must expose face_instant() as the sanctioned rotation-write route"
	)
