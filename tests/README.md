# tests/

GUT (Godot Unit Test) suite. Run it exactly the way the gate does:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

`bash /agent/verify.sh` runs this as its third step, after the headless import and the headless
project boot.

## Layout

| Path | Contents |
|---|---|
| `unit/` | One file per autoload or `global/components/` component. No scene loading. |
| `integration/` | Several systems wired together — currently the player damage chain. |
| `helpers/` | Shared fixtures. **Never** named `test_*`, or GUT tries to collect them as tests. |

## These are characterization tests

They pin down what the code does **today**, bugs included. A test that documents surprising
behaviour is marked `CHARACTERIZED` in a comment, and the suspicion is filed under *Discovered*
in `BACKLOG.md`. Do not "fix" the code to make one of these read better without first deciding
that the behaviour itself is wrong — the point of the suite is that a behaviour change is a
*visible* change.

## House rules learned the hard way

- **Never let a test touch the real save files.** Every persistent autoload writes to a fixed
  `user://*.cfg`, and the live autoload reads it at boot, so an unsandboxed test leaks into the
  player's profile and into the next run of the suite. Use `helpers/save_sandbox.gd`:

  ```gdscript
  const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
  var _sandbox := SaveSandbox.new()
  func before_all() -> void: _sandbox.capture()
  func after_all() -> void:  _sandbox.restore()
  ```

- **Prefer a tree-less `Script.new()` instance to the live autoload.** Outside the tree
  `_ready()` never fires, so `_load()` never runs and the object starts from a known-empty
  state. Use the real singleton only when the code under test needs `get_tree()`.

- **Keep `_process` / `_physics_process` out of the tree and call them by hand** when timing
  matters (see `unit/test_overheat_component.gd`, `unit/test_camera_shake.gd`). Real frame
  timing makes assertions approximate for no benefit.

- **GUT fails a test on any unexpected engine error**, including one raised inside a signal
  callback. `Health.amount_changed` and `State.state_transition` are declared with zero
  parameters but emitted with one, so connect **one-argument** callables to them — a
  zero-argument handler raises `Method expected 0 argument(s), but called with 1`.
  `push_warning` is *not* treated as a failure.

- Components that need a parent or a `_ready()` pass (`Health` prints `get_parent().name`;
  `Shield` builds its regen `Timer` in `_ready()`) must actually be in the tree. Add the host to
  the tree *first*, then add the component to the host.

## Coverage today

Autoloads: `MissionState`, `UpgradeState`, `ShipModuleState`, `ShipProgressionState`,
`SessionState`, `EventBus`, `DialogPlayer`, `CameraShake`.
Components: `Health`, `HitBox`/`HurtBox`, `Shield`, `TempHealth`, `Overheat`, `DamageReaction`.
Plus `global/statemachine/` and the `PlayerBase` damage chain.
