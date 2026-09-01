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
| `integration/` | Several systems wired together (the player damage chain), plus project-wide integrity checks over the resource files themselves. |
| `helpers/` | Shared fixtures. **Never** named `test_*`, or GUT tries to collect them as tests. |

## Two exceptions: the UID integrity test and the space-station tests

`integration/test_resource_uid_integrity.gd` is **not** characterization. It asserts an invariant
that must hold — every `[ext_resource]` UID in a `.tscn`/`.tres` matches the UID its target
declares — so a failure there is a regression to fix, not a quirk to document.

It reads declared UIDs **from disk** (the `.tscn`/`.tres` header line, the sibling `.gd.uid`, the
sibling `.import`) and never asks `ResourceUID` / `ResourceLoader`. Those consult
`.godot/uid_cache.bin`, which is gitignored *and* keeps stale UIDs registered as working aliases
once a warm project has loaded them — so the engine will happily report a broken reference as fine
on your machine and break on a fresh clone. Five of the eight mismatches this test first caught
behaved exactly that way. If you extend it, keep it reading files.

`integration/test_space_station.gd` and `integration/test_station_assault_section.gd` are the other
exceptions, for a different reason: the `space_station` entity and the `station_assault` section
are **new code**, so their tests assert intended behaviour rather than pinning existing quirks.
`test_space_station.gd` carries a documented coverage gap — it drives damage by emitting
`HurtBox.received_damage` directly, so it proves nothing about collision layers, and the section
tests do not close that. See the file headers and
`assault/scenes/enemies/space_station/ENEMY.md`.

Two traps `test_station_assault_section.gd` had to work around, both worth knowing before you add
a `LevelDirector` test:

- **`_wait_enemies_cleared()` polls once per second.** Its deadline is only re-checked *after*
  `_wait_for_child_exit_or_timeout(container, 1.0)` returns, so a 0.3 s timeout really fires at
  ~1.0 s, plus a 0.2 s settle. Budget off the poll, not the nominal timeout.
- **A test that ends while that coroutine is suspended leaks its `SceneTreeTimer`**, which Godot
  reports at process exit as `ObjectDB instances leaked` / `resources still in use`. Neither line
  matches the gate's fatal-error regex, so **the gate stays green while leaking.** Empty the
  container and wait for the director to advance before the test returns.

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
Project-wide: `[ext_resource]` UID integrity across every `.tscn`/`.tres`.
Entities: the `space_station` mini-boss (`integration/test_space_station.gd`) — armour rule, turret
lifecycle, and the config-driven stats.
Levels: the `station_assault` section (`integration/test_station_assault_section.gd`) — the
`ENEMIES_CLEARED` gate, the per-section timeout and its free-on-expiry path, and Level 1's
section order and station wave.
