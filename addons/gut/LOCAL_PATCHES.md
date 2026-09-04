# Local patches to the vendored GUT addon

GUT 9.7.1 was vendored from https://github.com/bitwes/Gut/releases/tag/v9.7.1.
Two files needed a change to load under **Godot 4.6.3**. Re-apply both if GUT is upgraded.

| File | Change | Why |
|---|---|---|
| `godot_singletons.gd` | Commented out the `AccessibilityServer` entry in `class_ref` | `ClassDB.class_exists("AccessibilityServer")` is `false` in this Godot build, so the identifier fails to resolve and the whole script fails to parse. That takes the doubler down with it. |
| `stub_params.gd` | `var return_val = ...` → `var return_val: Variant = ...` | `GutConstants.NOT_SET` is a `StringName`, so Godot inferred the property getter's return type as `StringName`; the getter's `return null` branch then failed to parse. |

Both were parse errors printed on every `gut_cmdln.gd` run before the patch. Neither changes GUT
behaviour on the paths this project uses.

`tests/integration/test_gut_local_patches.gd` guards both patches. It asserts each file still
parses (`can_instantiate()`, since a parse error still `load()`s to a non-null `GDScript`) and that
each patched code path still behaves — `GodotSingletons.names` is populated, and an unset
`StubParams.return_val` reads back as `null` instead of leaking the `NOT_SET` sentinel. Without it
a re-vendor fails *quietly*: the parse errors go to stderr, the suite still exits 0, and the
doubler is simply gone.
