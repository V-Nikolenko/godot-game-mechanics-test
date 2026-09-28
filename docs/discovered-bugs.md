# Discovered bugs

Moved here from the old `BACKLOG.json` `notes` section when task tracking moved to AI-Kanban
(2026-09-24). This is a log of defects found in the code - mostly while writing the
characterization suite - not a task list. Most are **pinned by a passing test that asserts the
current behaviour**, so changing one fails that test: the signal that the change was deliberate.

To act on one, turn it into an idea or task on the AI-Kanban board. When you find a new suspected
bug you are not fixing, list it under **Follow-ups** in your final message rather than editing
this file.

---

Found on 2026-08-31 while writing the characterization suite. Each one is **pinned by a passing
test that asserts the current behaviour**, so changing any of them will fail that test — which is
the signal that the change was deliberate. Test names are given so the fix has an obvious anchor.

- [x] **`Health.amount_changed` is declared with zero parameters but emitted with one.**
      `global/components/health_component.gd:4` declares `signal amount_changed`, and line 42
      emits `amount_changed.emit(current_health)`. One-argument handlers (`DamageReaction`,
      `PlayerBase._on_health_changed`) work, but any zero-argument handler raises
      `Error calling from signal 'amount_changed' ... Method expected 0 argument(s), but called
      with 1` at runtime. Fix is one line: `signal amount_changed(current: int)`.
      Same defect in `global/statemachine/state.gd:4` — `signal state_transition` is emitted with
      the target `State`. Pinned by `tests/unit/test_health_component.gd` (see the file header)
      and `tests/unit/test_state_machine.gd::test_states_request_transitions_through_their_own_signal`.
      **Fixed 2026-09-03.** Both declarations now name the argument they emit
      (`amount_changed(current_health: int)`, `state_transition(new_state: State)`). This is a
      readability/tooling fix only — it does **not** make a zero-argument handler legal, and
      `tests/README.md` now says so explicitly instead of describing the old shape. Two new intent
      tests read the declared arity back off `get_signal_list()`
      (`test_amount_changed_declares_the_int_it_emits`,
      `test_state_transition_declares_the_state_it_emits`), so the declarations cannot silently
      drift from the emits again. The rule is now a convention in `docs/architecture/PROJECT.md`.

- [x] **`StateMachine.change_state()` crashes if the machine has no current state.**
      `global/statemachine/state_machine.gd:29` does `print("Exiting previous state: " +
      current_state.name)` **before** the `if current_state:` guard on line 31. Any machine built
      without an `initial_state` (or whose state was cleared) dies on its first transition. Not
      reachable today because every shipped machine sets `initial_state`, so it is latent rather
      than live. Deliberately *not* covered by a test — the test would have to trigger the crash.
      **Fixed 2026-09-03.** The log line moved inside the `if current_state:` guard, together with
      the `exit()` call it sits next to. It **is** covered by a test now —
      `test_state_machine.gd::test_change_state_from_an_idle_machine_enters_without_crashing`
      builds a machine with no `initial_state` and transitions it; before the fix that test failed
      with `Invalid access to property or key 'name' on a base object of type 'Nil'`, which is
      exactly the crash, provoked deliberately in a place where it is harmless.

- [x] **`Health.decrease()` prints to stdout on every single hit.**
      `global/components/health_component.gd:34`. In a bullet-hell section that is one line per
      projectile per frame; `print` is not free and it buries real errors in the log. Should be a
      debug-gated helper or removed. `StateMachine.change_state` and `DialogPlayer` print
      unconditionally too (`[DP] ...` on every line of every conversation).
      **Fixed 2026-09-03.** All three now trace behind `if OS.is_stdout_verbose():`, so the
      messages survive for debugging (`godot --verbose ...`) but cost nothing in a normal run.
      Measured on the GUT suite: **181 lines** suppressed (173 `[Health]`, 6 `[StateMachine]`,
      2 `[DP]`), and a normal suite run now greps 0 for all three prefixes. `DialogPlayer`'s nine
      prints went through a `_trace()` helper; its `_unhandled_input` one is additionally
      guarded at the call site because `event.as_text()` allocates per input event.
      `Health.decrease()` no longer needs a parent, since the fallback replaced the bare
      `get_parent().name`. `dialog_box.gd`, `movement_controller.gd` and `dash_state.gd` have the
      same problem and were **not** in scope — refiled below.

- [x] **The turret sprite's barrels point at −Y and no turret sets `rotation`.** All four
      `space_station.tscn` turret instances are placed at `rotation = 0`, so every barrel points
      toward the top of the screen — *away* from the player, who is always below the station.
      **Closed 2026-09-02 by sub-item 4a**, at exactly the moment it predicted.
      `StationGunnery.fire_turret_volley()` sets each firing turret's `global_rotation` to
      `aim.angle() + PI/2` immediately before firing — `global_rotation`, not `rotation`, so it
      survives the laser phase spinning the hull. Pinned by
      `test_turret_barrels_face_the_player_when_firing`, which fails by ~180° against the pre-4a
      scene. The authored `rotation = 0` remains, as a spawn orientation.
