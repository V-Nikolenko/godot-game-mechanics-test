## Invariant test over collision layer naming.
##
## `project.godot [layer_names]` is the single place a physics layer bit gets a human name; Godot
## itself never checks that every bit actually used in a scene or resource has one there. This
## sweeps every `.tscn`/`.tres` outside `addons/` for `collision_layer`/`collision_mask` values,
## decomposes each into its set bits, and asserts every bit found is named. It also asserts
## `global/physics/collision_layers.gd` declares one constant per named layer, equal to
## `1 << (layer_number - 1)`, so code can refer to a layer by name instead of a magic number.
##
## Not characterization: a name removed from `project.godot` or a constant drifting from its
## layer number is a regression, not a documented quirk.
extends GutTest

const SKIPPED_DIRS: Array[String] = ["addons", ".godot", ".git", ".import"]
const COLLISION_LAYERS_SCRIPT_PATH := "res://global/physics/collision_layers.gd"

var _layer_re: RegEx
var _value_re: RegEx

## layer number (1-based) -> name, parsed from project.godot [layer_names].
var _layer_names: Dictionary = {}

## bit number (1-based) -> a sample "file:line" that set it, for a readable failure message.
var _used_bits: Dictionary = {}

var _scanned_files: int = 0


func before_all() -> void:
	_layer_re = RegEx.create_from_string('^2d_physics/layer_(\\d+)="([^"]*)"$')
	_value_re = RegEx.create_from_string('(collision_layer|collision_mask) = (\\d+)')

	_parse_layer_names()

	for file_path: String in _collect_resource_files("res://"):
		_scanned_files += 1
		var line_number := 0
		for line: String in FileAccess.get_file_as_string(file_path).split("\n"):
			line_number += 1
			var m := _value_re.search(line)
			if m == null:
				continue
			var mask := int(m.get_string(2))
			for bit: int in _bits_set(mask):
				if not _used_bits.has(bit):
					_used_bits[bit] = "%s:%d" % [file_path, line_number]


func _parse_layer_names() -> void:
	for line: String in FileAccess.get_file_as_string("res://project.godot").split("\n"):
		var m := _layer_re.search(line)
		if m == null:
			continue
		_layer_names[int(m.get_string(1))] = m.get_string(2)


## Recursive walk of the project tree returning every `.tscn` / `.tres` outside `addons/`.
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


## Every 1-based bit position set in `mask` that `project.godot [layer_names]` does not name.
func _unnamed_bits(mask: int) -> Array[int]:
	var unnamed: Array[int] = []
	for bit: int in _bits_set(mask):
		if not _layer_names.has(bit):
			unnamed.append(bit)
	return unnamed


## Every 1-based bit position set in `mask`.
func _bits_set(mask: int) -> Array[int]:
	var bits: Array[int] = []
	for bit: int in range(1, 33):
		if mask & (1 << (bit - 1)) != 0:
			bits.append(bit)
	return bits


func test_the_walk_actually_found_project_scenes_and_layer_names() -> void:
	# Without this, every check below would pass vacuously if the walk or the parse ever broke.
	assert_gt(_scanned_files, 100,
		"expected the project to contain well over 100 .tscn/.tres files outside addons/")
	assert_gt(_layer_names.size(), 5, "expected several named layers in project.godot")


func test_every_used_collision_bit_has_a_name() -> void:
	var unnamed: Array[String] = []
	for bit: int in _used_bits.keys():
		if not _layer_names.has(bit):
			unnamed.append("bit %d (value %d), first seen at %s" %
					[bit, 1 << (bit - 1), _used_bits[bit]])
	assert_eq(unnamed, [] as Array[String],
			"every collision_layer/collision_mask bit set anywhere must be named in " +
			"project.godot [layer_names]:\n" + "\n".join(unnamed))


func test_synthetic_unnamed_bit_is_reported() -> void:
	# Boundary case: bit 4 (mask 8) is not named in project.godot today. This proves the
	# unnamed-bit check actually rejects something, rather than passing vacuously.
	assert_eq(_unnamed_bits(8), [4],
			"bit 4 (mask 8) is not named in project.godot and must be reported as unnamed")


func test_every_named_layer_has_a_matching_collision_layers_constant() -> void:
	var script := load(COLLISION_LAYERS_SCRIPT_PATH) as GDScript
	assert_not_null(script, "expected %s to exist" % COLLISION_LAYERS_SCRIPT_PATH)
	if script == null:
		return

	var constants := script.get_script_constant_map()
	var mismatches: Array[String] = []
	for layer_number: int in _layer_names.keys():
		var expected_name: String = String(_layer_names[layer_number]).to_upper()
		var expected_value := 1 << (layer_number - 1)
		if not constants.has(expected_name):
			mismatches.append("missing constant %s (layer %d)" % [expected_name, layer_number])
		elif constants[expected_name] != expected_value:
			mismatches.append("%s = %s, expected %d (layer %d)" %
					[expected_name, constants[expected_name], expected_value, layer_number])
	assert_eq(mismatches, [] as Array[String],
			"CollisionLayers must declare one constant per named layer, equal to 1 << (n-1):\n" +
			"\n".join(mismatches))
