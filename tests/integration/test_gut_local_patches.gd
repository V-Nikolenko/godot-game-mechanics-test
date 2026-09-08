## Integrity test over the three local patches applied to the vendored GUT addon.
##
## GUT 9.7.1 does not load cleanly under Godot 4.6.3, and leaks a SceneTreeTimer on every headless
## run. Three files were patched by hand — the `AccessibilityServer` entry in
## `godot_singletons.gd` (the class does not exist in this build, so the identifier fails to
## resolve), the `return_val` property in `stub_params.gd` (Godot inferred the getter's type as
## `StringName` from `GutConstants.NOT_SET`, so its `return null` branch failed to parse), and the
## editor-GUI startup delay in `gut_plugin.gd` (a 1-second `SceneTreeTimer` awaited in
## `_enter_tree()` that never fires under `--headless --import`/`--quit`, since both exit before
## the main loop processes a frame, and leaks at engine shutdown instead). All three are written up
## in `addons/gut/LOCAL_PATCHES.md`.
##
## Re-vendoring GUT drops all three patches, and the resulting failure is quiet: the parse errors
## go to stderr, `gut_cmdln.gd` still runs the suite, and the gate (`/agent/verify.sh` step 3)
## checks only the exit code and the `^N failing` line. Nothing turns red — the doubler is simply
## gone, any test that reaches for it fails later for a reason that looks unrelated, and the leaked
## timer's `WARNING: ObjectDB instances leaked at exit` is easy to write off as engine noise.
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
const GUT_PLUGIN_SCRIPT := "res://addons/gut/gut_plugin.gd"
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


## Patch 3, structurally: `gut_plugin.gd` extends `EditorPlugin`, which cannot be meaningfully
## instantiated outside an editor context, so — unlike patches 1 and 2 — this test cannot exercise
## `_enter_tree()` directly. It can still confirm the file still parses at all.
func test_gut_plugin_script_parses() -> void:
	var script := load(GUT_PLUGIN_SCRIPT) as GDScript
	assert_not_null(script, "%s did not load at all." % GUT_PLUGIN_SCRIPT)
	assert_true(
		script.can_instantiate(),
		"%s has a parse error%s" % [GUT_PLUGIN_SCRIPT, REAPPLY]
	)


## Patch 3, behaviourally: the leaked-timer regression is a property of a whole process
## (`--import`/`--quit` exiting with a suspended coroutine still holding a `SceneTreeTimer`), not
## something a single running test can trigger and observe. The closest in-process check is
## textual: the delay-creating line must still be the guarded one, not a bare, unconditional await.
func test_gut_plugin_delay_is_guarded_under_headless() -> void:
	var source := FileAccess.get_file_as_string(GUT_PLUGIN_SCRIPT)
	assert_true(
		source.contains("GutUtils.is_headless()"),
		"gut_plugin.gd no longer guards its startup delay with GutUtils.is_headless()%s" % REAPPLY
	)
	var guard_line := source.find("if not GutUtils.is_headless():")
	var timer_line := source.find("get_tree().create_timer(1).timeout")
	assert_true(
		guard_line != -1 and timer_line != -1 and guard_line < timer_line,
		(
			"gut_plugin.gd's 1-second startup SceneTreeTimer is no longer inside the " +
			"`if not GutUtils.is_headless():` guard%s"
		) % REAPPLY
	)


## ...and the guard actually does something in the context this suite always runs in: GUT's own
## `gut_cmdln.gd` requires `--headless`, so if `is_headless()` ever stopped reporting true here,
## the guard above would be dead code passing a text match while the leak came back for real.
func test_is_headless_reports_true_in_this_suite() -> void:
	assert_true(
		GutUtils.is_headless(),
		"This suite always runs under --headless; if is_headless() reports false here, the " +
		"gut_plugin.gd guard silently stops skipping the leaking delay."
	)
