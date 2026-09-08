# Context

## The finding this task records

Measured on Godot 4.6.3 (throwaway `SceneTree` probe, per the task body): a signal's declared
parameter list is **documentation only**. `emit()` does not check it against the declaration,
`connect()` accepts a callable of any arity at connect time, and the only place the declared arity
is actually visible is `Object.get_signal_list()`. The 2026-09-03 fix
(`global/components/health_component.gd`'s `amount_changed` and `global/statemachine/state.gd`'s
`state_transition`) made those two declarations honest, and two hand-written tests
(`tests/unit/test_health_component.gd::test_amount_changed_declares_the_int_it_emits`,
`tests/unit/test_state_machine.gd::test_state_transition_declares_the_state_it_emits`) pin them by
reading `get_signal_list()`. `tests/README.md` (~line 449) documents the trap in prose.

Nothing currently generalizes this. Each new signal needs its own hand-written
`get_signal_list()` assertion, or a declared/emitted mismatch ships silently — exactly the
"someone 'fixes' the next one and assumes the problem is gone" the task head warns about.

## What a general check has to handle

`grep -rn "^signal .*(" --include=*.gd . | grep -v addons` finds ~45 parameterized signal
declarations across `global/`, `assault/`, `open_space/`; `grep -rn "\.emit("` finds ~150 call
sites. Key facts from reading them:

- **Signal names are not unique across the project and must be resolved per-file.**
  `signal died` is declared bare (arity 0) in `assault/scenes/enemies/base_enemy.gd`,
  `global/components/damage_reaction.gd` and
  `open_space/scenes/entities/enemies/patrol_drone.gd`, but with one `Vector2` argument in
  `assault/scenes/hazards/asteroid_base.gd`. A global name→arity map would false-positive on
  every bare `died.emit()` the moment one file declares a parameterized `died`.
- **Most emit call sites are on `self`**: `died.emit()`, `weapon_changed.emit(mode)`,
  `state_transition.emit(transition_state)` — same file as the `signal` line. These are exactly
  the pattern the two existing hand-written tests already check, generalized.
- **A real minority go through a member access**: `hb.received_damage.emit(dmg)`,
  `EventBus.score_changed.emit(...)`, `movement_controller.movement_lock.emit(...)`,
  `t.destroyed.emit(t)`. Verifying these needs the static type of `hb`/`t`/etc. across files —
  real type inference, not a text sweep. Out of scope: see `3-plan.md` Out of scope.
- **At least one emit call spans multiple lines with nested parens**:
  `assault/scenes/race/track/dash_panel.gd:83-84`
  (`body_wall_hit.emit(ship, part, dir_l if dir_l != 0.0 else 1.0, ...)` continues on the next
  line). A per-line regex silently undercounts this call's arguments. The scan must work over
  whole-file text with a paren/bracket/string-aware walk, not `String.split(",")` per line.
- **Signal declarations can carry a trailing comment**:
  `global/ui/dialog_system/ui/dialog_box.gd:17`: `signal typing_completed    ## Typing animation...`.
  The declaration regex must not swallow trailing prose as parameters.

## Existing precedent to reuse

| Path | What it gives us |
|---|---|
| `tests/integration/test_resource_uid_integrity.gd` | The project's established pattern for a "read every non-addon `.gd`/`.tscn` file from disk, `RegEx.create_from_string`, assert an invariant" sweep test — not a hand-written list. Same shape of test I'm adding. |
| `tests/unit/test_health_component.gd::_signal_args` / `tests/unit/test_state_machine.gd`'s inline loop | The two existing per-signal `get_signal_list()` assertions this task generalizes. Keep them — they document intent for those two signals specifically; the new test is a safety net underneath, not a replacement. |
| `tests/integration/test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd` | Other "value declared in one place must match value used in another" invariant tests over source, for tone/structure reference. |

## Conventions that constrain this

- New integration tests live in `tests/integration/`, extend `GutTest`, and must be picked up by
  `tests/integration/test_suite_integrity.gd`'s compile sweep automatically (no registration
  needed).
- Per `tests/README.md`, prefer reading from disk over `ResourceLoader`/engine state for anything
  that must be immune to `.godot/` cache staleness — this check is pure text analysis so it's moot
  here, but the file-walk should skip the same directories the other sweeps skip
  (`addons`, `.godot`, `.git`, `.import`).
- `CLAUDE.md` signal-arity convention: "a signal is declared with exactly what it emits" — this
  test is the enforcement mechanism for that sentence.
