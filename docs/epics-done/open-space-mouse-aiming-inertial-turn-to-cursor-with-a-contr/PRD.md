# Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting — PRD

Epic id: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
Closed: 2026-09-15. Preparation: [`docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/).

---

## The ask

### The original idea, verbatim (`idea-1789305113892`)

> Rework Open-Space Movement & Mouse Aiming:
>
> Rework open-space movement to support mouse-based ship rotation and aiming.
>
> Keep the existing A/D rotation controls as an alternative/legacy control scheme.
>
> The new mouse system should rotate the ship toward the mouse position, providing more precise
> movement and shooting control.
>
> Add a slight rotation delay/inertia when following the mouse, rather than making the ship
> instantly point at the cursor.
>
> Make mouse-based rotation somewhat slower to keep the system balanced and avoid making aiming
> too powerful.
>
> Weapons and movement abilities must follow the ship's actual facing direction, not the mouse
> position. The mouse only determines the direction the ship is trying to rotate toward.
>
> This system should apply only to open-space missions and must not affect assault/land missions
> or other gameplay modes.
>
> Add a setting/option to switch between the new mouse movement and the existing movement system,
> with the new mouse-based system enabled by default.
>
> Overall movement should aim for a responsive but inertia-based feel, inspired by the movement
> style of Jet Lancer.

### The user's own words afterwards (epic `feedback`, verbatim)

> **2026-09-13, `decision: changes`** — "Sorry, I moved 'plan review' step from progress to done.
> Looks like you didn't finish it yet, so I rejecting it for you to move it to done when you ready.
> As for now it looks great!"

> **2026-09-14, `decision: approve`** — *(no text)*

The first is process bookkeeping, not a design change: the plan-review task had been moved to
`done` before the review subagent had actually returned. Nothing about the plan was rejected by the
user. The second is the approval that unblocked implementation.

### The six implementation tasks, verbatim heads + bodies

#### 1. Your ship leans toward the mouse cursor instead of snapping to it *(medium)*

> Adds `open_space/scenes/entities/player/ship_turn_controller.gd` (`class_name ShipTurnController
> extends Node`) and wires it into `open_space/scenes/entities/player/player_ship.tscn` as a child
> node of PlayerShip. It becomes the only writer of the open-space ship's rotation.
>
> Implements BOTH schemes behind an `@export var scheme: StringName` defaulting to `&"mouse"`:
> - mouse: clamped exponential chase toward the cursor angle (see the plan → "Turn model" for the
>   exact five lines), dead zone holds the target angle, `rotate_toward` applies the step.
> - keys: today's behaviour exactly, 220 deg/s, instantaneous, cursor ignored.
>
> `player_ship.gd::_handle_rotation` shrinks to reading the A/D axis, calling
> `set_aim_target(global_position, get_global_mouse_position())` and
> `rotation = _turn.step(rotation, turn, delta)`. `rotation_speed_deg` moves off `player_ship.gd`
> onto the controller. `get_global_mouse_position()` must appear in exactly one line project-wide.
>
> DONE WHEN: `tests/unit/test_ship_turn_controller.gd` passes with every case in the plan's test
> plan for that file — frame-rate independence, the turn-rate cap, no overshoot, wrap-around across
> ±pi, cursor-exactly-on-ship, the 47.9/48.1 px dead-zone edge, the 180-degree tie-break, "classic
> is still 220 deg/s", "classic ignores the cursor", "mouse ignores A/D". No autoload and no UI in
> this task — the scheme is flipped by hand in the test / inspector. Gate green.

#### 2. The game remembers which steering scheme you fly with *(small)*

> Adds `global/autoloads/settings_state.gd` (`SettingsState`), the project's first settings store.
> Near-copy of the `ConfigFile` template in `global/autoloads/ship_module_state.gd`:
> `SAVE_PATH = "user://settings.cfg"`, `SECTION = "controls"`, key `open_space_scheme`,
> `SCHEMES = [&"mouse", &"keys"]`, `DEFAULT_SCHEME = &"mouse"`,
> `signal open_space_scheme_changed(scheme: StringName)` (declared with its argument —
> `test_signal_emit_arity.gd` sweeps self-emits).
>
> Default-on-missing comes from `ConfigFile.get_value(SECTION, KEY, default)` and is re-validated
> against `SCHEMES` on load. Deliberately NOT the `UpgradeState.STARTING_IDS` idiom.
>
> Also: register in `project.godot` `[autoload]`; add `"user://settings.cfg"` to
> `tests/helpers/save_sandbox.gd::PATHS`. `player_ship.gd` seeds `_turn.scheme` from the autoload
> in `_ready()` and connects `open_space_scheme_changed` to `_turn.set_scheme(scheme, rotation)`.
>
> DONE WHEN: `tests/unit/test_settings_state.gd` passes — default on empty disk, round-trips
> through a second instance's `_load()`, falls back to the default on a hand-corrupted value,
> rejects a value not in SCHEMES, and does not emit when set to the value it already holds. Plus
> the "scheme flip mid-flight causes no rotation jump" case in
> `tests/unit/test_ship_turn_controller.gd`. No UI yet. Gate green.

#### 3. AI Targeting still snaps your nose onto an enemy, and the snap holds *(small)*

> `global/ship_modules/ai_targeting_module.gd:38` writes `actor.rotation =` directly. Under the
> turn controller that write is undone within a frame or two, so the 15-second-cooldown module the
> player unlocked and equipped visibly does nothing under mouse aim.
>
> Fix, per the plan's chosen option (a):
> - `OpenSpacePlayerShip.face_instant(angle: float)` — sets rotation, adopts `angle` as the
>   controller's target, and suppresses cursor steering.
> - The module calls it duck-typed (`if actor.has_method("face_instant")`), the same shape as
>   `is_armored()` in CLAUDE.md, because the module lives in `global/`.
> - Suppression is cleared by REAL mouse motion, not by cursor position:
>   `get_global_mouse_position()` is a world position that moves with the camera, so a physically
>   still mouse would otherwise clear it immediately. `player_ship.gd::_input()` gains an
>   `InputEventMouseMotion` branch calling `_turn.notify_mouse_moved()` before its existing
>   `use_ability` early-return. Do not mark motion events as handled.
>
> DONE WHEN: the "snap holds until the mouse moves" case in
> `tests/unit/test_ship_turn_controller.gd` passes, and the module still snaps under
> `scheme = &"keys"` exactly as it does today. Gate green.

#### 4. A future ship module cannot silently fight your steering *(test)*

> Adds `tests/integration/test_ship_rotation_single_writer.gd`, the suite's eleventh invariant
> test. [...] Sweep every `global/ship_modules/*.gd` and assert none assigns to `actor.rotation`
> (`=`, `+=`, `-=`). Allowlist empty; the sanctioned route is `face_instant()`.
>
> Boundary cases that make it able to fail: the sweep must find a non-zero number of module files
> and must find `ai_targeting_module.gd` among them by name; `OpenSpacePlayerShip` must expose a
> `face_instant` method.
>
> DONE WHEN: the test passes on the fixed tree, and reverting the duck-typed call in
> `ai_targeting_module.gd` makes it fail (check that by hand before committing — an invariant that
> cannot fail is worth nothing). Gate green. Add the test to the list in `CLAUDE.md` and
> `tests/README.md`.

#### 5. Alt-tabbing away no longer leaves your ship turning on its own *(small)*

> When the game window loses focus the OS pointer stops updating but `get_global_mouse_position()`
> keeps returning the last in-window position, so the ship holds a stale target angle and keeps
> turning toward it while the player is in another window.
>
> Adds `ShipTurnController.set_steering_enabled(enabled: bool)` — while false the target angle is
> frozen and `step()` still runs (so no rotation discontinuity on resume) — and
> `player_ship.gd::_notification()` handling `NOTIFICATION_APPLICATION_FOCUS_OUT` /
> `NOTIFICATION_APPLICATION_FOCUS_IN`.
>
> Explicitly NOT doing pointer confinement or capture with a software cursor. The narrower "pointer
> left the window but the window is still focused" case stays uncovered and that is accepted.

#### 6. Choose mouse aim or classic A/D steering from the pause menu *(medium)*

> The last step: the player can actually pick a scheme. Until this lands the setting exists but only
> a test can change it.
>
> `global/ui/pause_menu/pause_menu.gd` hard-codes `Option0..Option4` and `_confirm()` matches on the
> index. Add a new `Option4` = "Settings" and move today's Exit Game to `Option5`, in BOTH
> `pause_menu.tscn` and `open_space_pause_menu.tscn` (they duplicate their option nodes rather than
> sharing them). Settings goes before Exit Game so Exit Game stays last where a player expects it
> [...]
>
> `global/ui/pause_menu/settings_panel.{gd,tscn}` is a sub-overlay copying `LoreLogList`'s
> `open()`/`close()`/`navigate()` shape and the `_lore_logs_open` routing branch verbatim in spirit:
> while open it absorbs ALL menu input including `menu_confirm` [...] and `ui_cancel` returns to the
> option list rather than closing the whole menu. One row — "Open-Space Steering: Mouse Aim /
> Classic (A/D)" — with menu_left/menu_right cycling the value straight into `SettingsState`. No
> generic settings framework for one two-valued key.
>
> The row is shown in all three modes: it is a stored preference, and hiding it in missions would
> make a player fly back to the hub to change their controls.
>
> DONE WHEN: `tests/integration/test_pause_menu_settings.gd` passes with every case in the plan's
> test plan for that file — including the one that drives the LIVE `SettingsState` through
> `menu_right` [...] and the one proving `menu_confirm` does not fall through while the panel is
> open. Sandboxed via `tests/helpers/save_sandbox.gd`. Gate green, and `updating-project-docs` run.

> **Note:** task 6's body claims `test_pause_menu_lore_logs.gd` "references only indices 1-3 so it
> needs no change — confirm that before assuming it." That was confirmed, and it was **false** —
> see the plan's "Task-body corrections". The plan (revision 2, finding B1) corrected it before
> implementation started; the two-line edit was made.

---

## Player-facing goal

In open space the ship **leans into** the mouse cursor rather than snapping to it. It starts
turning a beat after the cursor moves and turns deliberately slower than the old A/D crank, so fine
aim is paid for in turn rate. Guns and the boost fire along the **hull's** facing, never the
cursor, so a shot placed mid-swing goes where the nose is pointing — that lag is the skill.

A player who prefers the crank opens the ESC menu → **Settings** → **Open-Space Steering: Classic
(A/D)** and gets today's behaviour exactly. The choice survives a restart. Mouse aim is the default.

Assault and infiltration are untouched.

---

## Scope

**In scope**

- Open-space ship rotation only (`open_space/scenes/entities/player/player_ship.tscn`).
- Both schemes, as first-class equals, selected by a persisted setting with a UI entry point.
- The one shared-module collision the change forces: `AITargetingModule`'s raw rotation write.
- An invariant test that stops the next ship module re-introducing that collision.
- Freezing steering on window focus loss.

**Explicitly out of scope** (each rejected in the plan with a reason, not dropped)

- Pointer confinement (`MOUSE_MODE_CONFINED`) and capture with a synthesised software cursor.
- Custom cursor art, an in-world reticle, a lead indicator.
- Mouse sensitivity as a tunable — `SettingsState` is shaped so it lands as another key later.
- A generic settings framework. One two-valued key does not pay for one.
- Thrust/strafe changes. `_handle_thrust()` belongs to the pending open-space boost epic, and the
  plan states the two epics must not be implemented in the same window.
- Any change to assault or infiltration steering.

**Where the epic was split, and why** — six implementation tasks, ordered so each leaves the game
playable and the gate green. Task 1 is the whole turn model behind an `@export` (playable under
either scheme from the inspector, no autoload, no UI); task 2 makes the choice persistent but
test-only; tasks 3, 4 and 5 each close one consequence of task 1 and touch no shared files with one
another; task 6 is last because its value depends on every earlier step working. The plan notes
tasks 3-6 depend only on task 1 (6 also on 2), so an interrupted window loses at most one of them.

---

## Constraints that shaped it

- **The mouse is read in exactly one line project-wide.** `Input.warp_mouse()` cannot place a
  cursor in a headless GUT run, so anything that reads the mouse itself is untestable by the gate.
  The turn model therefore takes the cursor as an injected `Vector2` and reads no `Input` at all.
  This is now a `CLAUDE.md` convention, gated by `test_player_ship_turn_wiring.gd`.
- **Single writer of `rotation`.** A second writer is invisible in code review and silent at
  runtime — it just loses an argument with the controller a frame or two later.
- **Duck-typed cross-module queries, no shared interface** — `face_instant()` follows the
  `Bullet.is_armored()` precedent, because ship modules live in `global/` and run against assault
  and open-space actors alike.
- **Signals are declared with exactly what they emit** — `open_space_scheme_changed(scheme:
  StringName)`, swept by `test_signal_emit_arity.gd`.
- **`user://` sandboxing** — a new save file means a new entry in `save_sandbox.gd::PATHS`, or
  every test touching it leaks into the player's profile and the next suite run.
- **Never hand-type or copy a `uid://`.**

---

## Open questions at the time, and how each resolved

| Question | Resolution |
|---|---|
| Exponential damping, or a true angular-velocity model with overshoot-and-settle? | **Clamped exponential chase.** Research finding 3 gives frame-rate-correct "lag" with one honest parameter; finding 2's `rotate_toward` supplies the hard rate cap that makes "slower than the keys" a guarantee rather than an emergent property. The velocity model is the only one that can overshoot, but has two coupled parameters that are hard to tune blind. Recorded as the rejected alternative, not omitted. |
| What happens when the cursor sits exactly on the ship? | `Vector2.ZERO.angle()` returns `0.0` — an exact snap to world-right. Verified in-engine, not assumed. A dead zone **holds** the previous target angle rather than recomputing. Radius 48 px, an explicit judgement call. |
| What breaks the 180°-behind tie? | `angle_difference` follows its documented rule, so the turn direction depends on which side of zero the ship's `rotation` sits. Deterministic but arbitrary. The plan chose to accept and **pin** it in the test rather than add angular-velocity state to break the tie. |
| Where does the setting live — a new autoload, or an existing one? | New `SettingsState`, named for settings in general rather than controls, so mouse sensitivity lands as another key rather than a twelfth autoload. |
| Confine or capture the pointer? | Neither. Both were rejected with reasons; the case that actually bites — a stale cursor while the window is unfocused — is handled by freezing steering on `NOTIFICATION_APPLICATION_FOCUS_OUT`. |
| Is the Settings row hidden outside open space? | No. It is a stored preference; hiding it mid-mission would mean flying back to the hub to change your controls. The label names its scope instead. |
| Does `AITargetingModule`'s snap survive mouse aim? | Only via `face_instant()`, and the hold is released by **real mouse motion** (`InputEventMouseMotion`), not by cursor position — a world-space cursor moves with the camera even when the physical mouse is still. |
