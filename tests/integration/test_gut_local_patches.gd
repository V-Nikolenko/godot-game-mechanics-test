## Integrity test over the two local patches applied to the vendored GUT addon.
##
## GUT 9.7.1 does not load cleanly under Godot 4.6.3. Two files were patched by hand — the
## `AccessibilityServer` entry in `godot_singletons.gd` (the class does not exist in this build,
## so the identifier fails to resolve) and the `return_val` property in `stub_params.gd` (Godot
## inferred the getter's type as `StringName` from `GutConstants.NOT_SET`, so its `return null`
## branch failed to parse). Both are written up in `addons/gut/LOCAL_PATCHES.md`.
##
## Re-vendoring GUT drops both patches, and the resulting failure is quiet: the parse errors go to
## stderr, `gut_cmdln.gd` still runs the suite, and the gate (`/agent/verify.sh` step 3) checks
## only the exit code and the `^N failing` line. Nothing turns red — the doubler is simply gone,
## and any test that reaches for it fails later for a reason that looks unrelated.
##
## Like `test_suite_integrity.gd` and `test_resource_uid_integrity.gd`, this is NOT a
## characterization test: it asserts a property that must hold, so a failure here is a regression
## to fix — by re-applying the patches, not by relaxing the test.
##
## Note that a script with a parse error still `load()`s to a non-null `GDScript`; the giveaway is
## `can_instantiate() == false`. Checking for null would catch nothing.
extends GutTest

const SINGLETONS_SCRIPT := "res://addons/gut/godot_singletons.gd"
const STUB_PARAMS_SCRIPT := "res://addons/gut/stub_params.gd"
const PATCH_DOC := "res://addons/gut/LOCAL_PATCHES.md"

## Appended to every failure message: the patches are only recoverable if the reader finds the doc.
const REAPPLY := " — re-apply the local patches documented in %s." % PATCH_DOC


## The doc is the only record of what was changed and why. A wholesale re-vendor of `addons/gut/`
## deletes it along with the patches, so losing it is itself the regression.
func test_local_patch_doc_still_exists() -> void:
	assert_true(
		FileAccess.file_exists(PATCH_DOC),
		"%s is missing: the record of GUT's local patches was lost with it." % PATCH_DOC
	)


## Patch 1, structurally: an unresolved `AccessibilityServer` identifier is a parse error for the
## whole script, which leaves it loadable but not instantiable.
func test_godot_singletons_script_parses() -> void:
	var script := load(SINGLETONS_SCRIPT) as GDScript
	assert_not_null(script, "%s did not load at all." % SINGLETONS_SCRIPT)
	assert_true(
		script.can_instantiate(),
		"%s has a parse error%s" % [SINGLETONS_SCRIPT, REAPPLY]
	)


## Patch 1, behaviourally: `_static_init()` calls `get_class()` on every entry of `class_ref`, so a
## populated `names` proves the whole array resolved to live singletons in this build. `GutUtils`
## reaches for `GodotSingletons.names` in `is_native_class`, which is what the doubler uses to tell
## an engine class from a script.
func test_godot_singletons_resolved_every_entry() -> void:
	var names: Array = GutUtils.GodotSingletons.names
	assert_gt(names.size(), 0, "GodotSingletons.names is empty: _static_init() never ran%s" % REAPPLY)
	assert_true(names.has("OS"), "GodotSingletons.names is missing a known singleton%s" % REAPPLY)


## Patch 2, structurally: without the explicit `: Variant`, the getter's `return null` branch is a
## parse error and `stub_params.gd` goes the same way as above.
func test_stub_params_script_parses() -> void:
	var script := load(STUB_PARAMS_SCRIPT) as GDScript
	assert_not_null(script, "%s did not load at all." % STUB_PARAMS_SCRIPT)
	assert_true(
		script.can_instantiate(),
		"%s has a parse error%s" % [STUB_PARAMS_SCRIPT, REAPPLY]
	)


## Patch 2, behaviourally: an unset stub reads back as `null` rather than leaking the
## `GutConstants.NOT_SET` sentinel. This is the `return null` branch the patch exists to keep
## parseable.
func test_stub_params_unset_return_val_reads_as_null() -> void:
	var params = GutUtils.StubParams.new()
	assert_null(params.return_val, "An unset stub leaked its NOT_SET sentinel%s" % REAPPLY)


## ...and a stubbed value still reads back unchanged, so the getter's other branch is intact too.
func test_stub_params_returns_stubbed_value() -> void:
	var params = GutUtils.StubParams.new()
	params.to_return(7)
	assert_eq(params.return_val, 7, "A stubbed return value did not survive the getter%s" % REAPPLY)
