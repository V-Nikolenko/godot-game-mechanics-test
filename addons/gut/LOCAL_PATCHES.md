# Local patches to the vendored GUT addon

GUT 9.7.1 was vendored from https://github.com/bitwes/Gut/releases/tag/v9.7.1.
Three files needed a change under **Godot 4.6.3**. Re-apply all three if GUT is upgraded.

| File | Change | Why |
|---|---|---|
| `godot_singletons.gd` | Commented out the `AccessibilityServer` entry in `class_ref` | `ClassDB.class_exists("AccessibilityServer")` is `false` in this Godot build, so the identifier fails to resolve and the whole script fails to parse. That takes the doubler down with it. |
| `stub_params.gd` | `var return_val = ...` → `var return_val: Variant = ...` | `GutConstants.NOT_SET` is a `StringName`, so Godot inferred the property getter's return type as `StringName`; the getter's `return null` branch then failed to parse. |
| `gut_plugin.gd` | Guarded `await get_tree().create_timer(1).timeout` in `_enter_tree()` behind `if not GutUtils.is_headless():` | The plugin loads under `--headless --import` and `--quit` (it's enabled in `[editor_plugins]`), which exit before the main loop processes a frame the 1-second `SceneTreeTimer` could fire on. The still-suspended coroutine holds the timer, so it leaks at engine shutdown on every headless run (`WARNING: ObjectDB instances leaked at exit`, `Leaked instance: SceneTreeTimer`). The delay's own comments say it exists for editor GUI races (a shortcut button, "window stuff") that don't exist headless, so skipping it there changes nothing GUT uses on this project's paths. |

The first two were parse errors printed on every `gut_cmdln.gd` run before the patch; the third was
a silent leak on every `--import`/`--quit` run. None change GUT behaviour on the paths this project
uses.

`tests/integration/test_gut_local_patches.gd` guards all three patches. It asserts each patched
file still parses (`can_instantiate()`, since a parse error still `load()`s to a non-null
`GDScript`) and that each patched code path still behaves — `GodotSingletons.names` is populated,
an unset `StubParams.return_val` reads back as `null` instead of leaking the `NOT_SET` sentinel,
and `gut_plugin.gd`'s source still guards the timer behind `GutUtils.is_headless()`. Without it a
re-vendor fails *quietly*: the first two patch losses print parse errors to stderr while the suite
still exits 0 and the doubler is simply gone, and the third resurfaces the leaked-timer warning
noise the patch removed.
