# Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting

Epic: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
Stage: **PLAN**. Written 2026-09-13 against `agent/auto-dev` @ `df37d42`.
Builds on [`1-context.md`](./1-context.md) (what is already here) and
[`2-research.md`](./2-research.md) (how shipped games solve it). Neither is re-derived below.

---

## Problem

In open space today the ship turns **only** with A/D, at a flat 220 °/s with no acceleration and
no lag (`player_ship.gd::_handle_rotation`, lines 107–113). There is no mouse input anywhere in
the game except LMB bound to `shoot`. Steering is therefore a two-button crank: to put the nose on
something the player holds a key and eyeballs when to let go, and fine aim is impossible because
the turn rate is the same whether you want 90° or 2°.

After this epic the player flies open space with the mouse. The ship **leans into** the cursor
rather than snapping to it: it starts turning a beat after the cursor moves, and it is
deliberately *slower* than the A/D crank (150 °/s against 220 °/s), so precision aim is paid for
in turn rate. Guns and the boost still fire along the **hull's** facing, never the cursor, so a
shot placed while the ship is still swinging goes where the nose is pointing — that lag is the
skill. A player who prefers the old crank picks **Classic (A/D)** in the pause menu and gets
today's behaviour to the degree; mouse aim is the default for everyone else. Nothing changes in
assault or infiltration.

---

## Design

### The one-sentence shape

A `ShipTurnController` node under `player_ship.tscn` becomes the **only** thing that writes the
open-space ship's `rotation`. It is a pure step function over injected inputs — cursor world
position, A/D turn axis, `delta` — so it is fully testable headlessly, which is the hard
constraint from `1-context.md` ("Testing requirements"): `Input.warp_mouse()` cannot place a
cursor in a GUT run, so the mouse must be read in exactly one place and passed in.

### Turn model: clamped exponential chase

Adopted from `2-research.md` → "What the findings imply for the plan". Per physics frame, under
the mouse scheme:

```gdscript
# 1. Target angle — held, not recomputed, inside the dead zone (finding 6).
var to_cursor: Vector2 = cursor_world_pos - ship_world_pos
if to_cursor.length() >= mouse_dead_zone_px:
    _target_angle = to_cursor.angle() + PI * 0.5   # +90°: the sprite's nose is Vector2.UP

# 2. Frame-rate-correct exponential approach (finding 3).
var lambda: float = log(2.0) / mouse_turn_half_life
var diff: float = angle_difference(current_rotation, _target_angle)   # signed, wrap-correct
var step: float = diff * (1.0 - exp(-lambda * delta))

# 3. Hard cap — this is the balance guarantee, not an emergent property (finding 2).
var cap: float = deg_to_rad(mouse_max_turn_rate_deg) * delta
step = clampf(step, -cap, cap)

# 4. Apply through the engine primitive so the wrap case cannot be got wrong,
#    and so we can never overshoot the target.
return rotate_toward(current_rotation, _target_angle, absf(step))
```

Two parameters with two distinct jobs, which is why this shape was chosen over the alternatives:
`mouse_turn_half_life` decides how it **feels** (the lag), `mouse_max_turn_rate_deg` decides how
**strong** it is (the balance). A designer can lower the cap without making the ship feel mushy,
or raise the half-life without making it stronger.

**Alternatives rejected.**

- *Angular velocity with acceleration and damping* (a true inertial body). The only model that can
  overshoot-and-settle, which is what physical inertia literally looks like, and what finding 1's
  "vehicle chases an aim point" rig implies. Rejected because its two parameters are **coupled** —
  change the acceleration and the damping that felt right no longer does — and nothing headless can
  tell us whether a given pair oscillates pleasantly or nauseatingly. Tuning two coupled numbers
  blind, in an unattended loop where each fly-test costs a human round trip, is the expensive
  failure. If the clamped chase ships and reads as "floaty rather than heavy", this is the upgrade
  path and it swaps out behind the same `step()` signature.
- *Bare `lerp(rotation, target, 0.1)`* — frame-rate dependent, the standard bug (finding 3).
- *`rotate_toward` at a constant rate, no smoothing* — arrives and stops dead; reads as a crank
  with a mouse attached, i.e. it fails the "inertia" half of the ask outright.
- *`look_at` / instant snap* — contradicts the ask.

### Where it lives

**`open_space/scenes/entities/player/ship_turn_controller.gd`** (`class_name ShipTurnController
extends Node`), added as a child node in `player_ship.tscn`.

A scene node rather than a `RefCounted` created in `_ready()` for one concrete reason: the four
tuning numbers are `@export`s and have to be inspector-visible on the ship scene, exactly like
`rotation_speed_deg` is today. A `.new()` object's exports are not.

It lives under `open_space/`, not `global/`, because the assault player has no rotation at all
(`player_fighter.gd` contains no `rotation` reference) and infiltration has its own controller.
Mode isolation is structural — `player_ship.tscn` is instantiated by exactly one scene,
`sector_hub.tscn` — so no code is needed to enforce it, and putting the controller in `global/`
would invite exactly the sharing this epic must not have.

**Public API** (all of it injectable; none of it reads `Input` or the mouse):

| Member | Purpose |
|---|---|
| `@export var scheme: StringName = &"mouse"` | `&"mouse"` or `&"keys"`. Seeded from `SettingsState` by the ship. |
| `@export var keyboard_turn_rate_deg := 220.0` | Legacy scheme. **Must stay 220.0** — Classic is today's behaviour, to the degree. |
| `@export var mouse_max_turn_rate_deg := 150.0` | The balance lever. |
| `@export var mouse_turn_half_life := 0.14` | The feel lever (seconds). |
| `@export var mouse_dead_zone_px := 48.0` | Ship→cursor world distance below which the target angle is **held**. |
| `func set_aim_target(ship_pos: Vector2, cursor_pos: Vector2) -> void` | Updates `_target_angle`, honouring the dead zone. |
| `func step(current_rotation: float, turn_input: float, delta: float) -> float` | Returns the new rotation. Branches on `scheme`. |
| `func face_instant(angle: float) -> void` | Snap: adopt `angle` as both rotation *and* target, and suppress cursor steering until the mouse next moves. |
| `func notify_mouse_moved() -> void` | Clears snap suppression. |
| `func set_steering_enabled(enabled: bool) -> void` | While `false`, the target angle is frozen (window focus loss). |
| `func set_scheme(new_scheme: StringName, current_rotation: float) -> void` | Re-seeds `_target_angle = current_rotation` so a mid-flight swap cannot produce a jump. |
| `signal scheme_applied(scheme: StringName)` | Declared with its argument — `test_signal_emit_arity.gd` sweeps every self-emit. |

`player_ship.gd::_handle_rotation` shrinks to the integration:

```gdscript
func _handle_rotation(delta: float) -> void:
    var turn: float = 0.0
    if Input.is_action_pressed("move_left"):  turn -= 1.0
    if Input.is_action_pressed("move_right"): turn += 1.0
    _turn.set_aim_target(global_position, get_global_mouse_position())
    rotation = _turn.step(rotation, turn, delta)
```

`get_global_mouse_position()` is a `CanvasItem` method that accounts for the canvas transform and
the project's `stretch/mode="canvas_items"`, so it is correct at any window size — a raw
`DisplayServer.mouse_get_position()` would not be. It appears in exactly this one line project-wide.

The dead zone is measured **ship-to-cursor in world space**, never from screen centre, because
`_update_camera_feel()` already pushes the viewport up to `_LEAD_MAX = 140 px` ahead of the ship.

### Decision: A/D do nothing under mouse aim

Open question 3 from `1-context.md`. Under `&"mouse"`, `turn_input` is ignored. A manual override
that "wins while held" is incoherent with a cursor-derived target — the moment the key is released
the ship turns straight back to the cursor, undoing the override in front of the player. Strafe is
a new movement mechanic, is out of scope, and would collide head-on with the pending
*"Add Boost/Burst Movement to Open Space"* epic in `_handle_thrust()`. W/S thrust is unchanged, so
the ship is not unresponsive to the keyboard; only turning moves to the mouse. Recorded as
out of scope, below.

### Decision: `AITargetingModule` keeps its snap, and the snap holds

Open question 4, and the one real conflict in the codebase — `ai_targeting_module.gd:38` writes
`actor.rotation =` directly, and under a controller that owns a target angle that write is undone
within a frame or two. Of the three candidates in `1-context.md`:

- **(a) instant + suppress — chosen.** The module's own description promises "instantly snaps
  weapon aim to face the nearest enemy" on a 15-second cooldown; anything slower guts a module the
  player unlocked and equipped.
- (b) *set the controller's target instead* turns a snap into a turn assist. That is a behaviour
  change to a shipped module with no user request behind it.
- (c) *no-op under mouse aim* silently breaks a purchasable module for the default control scheme.

The module's call becomes duck-typed, matching the `is_armored()` precedent in `CLAUDE.md`
(the module is in `global/` and must not assume an open-space actor):

```gdscript
var angle: float = dir.angle() + PI * 0.5
if actor.has_method("face_instant"):
    actor.face_instant(angle)
else:
    actor.rotation = angle
```

**Suppression must be driven by real mouse motion, not by cursor position.** The obvious
implementation — "hold the snap until the cursor world position changes" — is wrong here, because
`get_global_mouse_position()` returns a *world* position that moves with the camera, so a
physically stationary mouse produces a moving target while the ship flies. So the ship's existing
`_input()` gains an `InputEventMouseMotion` branch that calls `notify_mouse_moved()`. This also
gets the pause behaviour for free: `MissionTrigger._open_menu()` already calls
`set_process_input(false)` on the player, so no motion is registered while a menu is open.

### Decision: exactly one writer of the ship's rotation, enforced by a test

After this epic, the single-writer rule is the thing that keeps the feature working, and it is
exactly the kind of rule a future module breaks silently. `1-context.md` establishes by grep that
there are only two writers today. `tests/integration/test_ship_rotation_single_writer.gd` becomes
the eleventh invariant test in the suite: sweep `global/ship_modules/*.gd` and assert **no file
assigns to `actor.rotation`** (`=`, `+=`, `-=`). The allowlist is empty. This test fails on
today's `ai_targeting_module.gd` and goes green when the duck-typed call lands, which is the
proof that it can fail.

### Decision: the setting is a new `SettingsState` autoload

Open questions 6 and 7. There is no options system in the project at all — zero settings autoload,
zero options screen. `global/autoloads/settings_state.gd`, registered in `project.godot`, is a
near-copy of the `ConfigFile` template every other persistent autoload follows:

```
SAVE_PATH  = "user://settings.cfg"
SECTION    = "controls"
KEY_OPEN_SPACE_SCHEME = "open_space_scheme"
SCHEMES    : Array[StringName] = [&"mouse", &"keys"]
DEFAULT_SCHEME := &"mouse"
signal open_space_scheme_changed(scheme: StringName)
func get_open_space_scheme() -> StringName
func set_open_space_scheme(scheme: StringName) -> void   # validates, saves, emits
```

Default-on-missing comes from `ConfigFile.get_value(SECTION, KEY, String(DEFAULT_SCHEME))` and is
re-validated against `SCHEMES` on the way in, falling back to the default with a `push_warning` on
an unknown value. This is deliberately **not** the `UpgradeState.STARTING_IDS` idiom, which only
ever reaches an empty store and is therefore a fresh-profile declaration rather than a per-boot
guarantee — the wrong shape for a setting that must have a value on every boot.

`"user://settings.cfg"` **must** be added to `tests/helpers/save_sandbox.gd::PATHS`, or every test
touching the setting leaks into the player's profile and into the next suite run.

Named `SettingsState`, not `ControlsState`, so the mouse sensitivity that
`2-research.md` finding 4 warns about (Jet Lancer's actual shipped friction was not the slow
banking, it was that the rate could not be changed) lands as another key in the same store rather
than a second autoload.

### Decision: a Settings sub-overlay on the shared pause menu, appended not inserted

`global/ui/pause_menu/pause_menu.gd` hard-codes `Option0..Option4` and `_confirm()` matches on the
index, so this is a real edit to a shared file. The plan:

- A new **`Option4` = "Settings"**, and today's Exit Game moves to **`Option5`**. Both
  `pause_menu.tscn` and `open_space_pause_menu.tscn` gain the node — they duplicate their option
  nodes rather than sharing them. `_options` grows to six entries and `_confirm()` gains
  `4: _open_settings()` with `5: get_tree().quit()`.
- **The existing `tests/integration/test_pause_menu_lore_logs.gd` needs no change** — verified by
  grep, it references only indices 1, 2 and 3. Renumbering Exit Game from 4 to 5 is invisible to
  it. This is why Settings goes *before* Exit Game rather than after: Exit Game stays last in the
  list where a player expects it, and no existing assertion moves.
- `SettingsPanel` (`global/ui/pause_menu/settings_panel.gd` + `.tscn`) is a sub-overlay with the
  same `open()` / `close()` / `navigate(dir)` shape as `LoreLogList`, and the routing in
  `_unhandled_input` is a copy of the `_lore_logs_open` branch: while it is open it absorbs **all**
  menu input including `menu_confirm`, and `ui_cancel` closes it back to the option list rather
  than closing the whole pause menu. One row for now — `Open-Space Steering: Mouse Aim / Classic
  (A/D)` — with `menu_left`/`menu_right` cycling the value and writing straight to
  `SettingsState`. A second row is a copy of the first; there is no generic settings framework
  here, because building one for a single two-valued key is churn the reviewer would be right to
  reject.
- **The row is shown in all three modes.** It is a stored preference, not a mode-local toggle, and
  hiding it in missions would mean a player who wants to change their steering has to fly back to
  the hub first. The label names its scope ("Open-Space Steering"), which is what stops it being
  the discoverability trap `1-context.md` flags.
- New `.tscn`/`.gd` files either go UID-less (legal — Godot falls back to the path) or get a UID
  minted with the headless `ResourceUID.create_id()` snippet in `tests/README.md`. **Never
  hand-typed, never copied from a sibling.**

### Decision: no cursor capture, no custom reticle, no confinement

Open question 5. `MOUSE_MODE_CONFINED` takes the pointer hostage on a multi-monitor desktop;
`MOUSE_MODE_CAPTURED` obliges us to synthesise and clamp a software cursor (finding 5) — a whole
feature of its own. Neither is in the ask. What *is* addressed is the case that actually bites:
when the game window loses focus the last in-window cursor position keeps being returned, so the
ship would keep turning toward a stale target while the player is in another window. The ship
handles `NOTIFICATION_APPLICATION_FOCUS_OUT` / `_IN` and calls
`_turn.set_steering_enabled(false/true)`, which freezes the target angle. Custom cursor art, an
in-world reticle and a lead indicator are out of scope.

### Numbers

Straight from `2-research.md` → "Starting numbers". Every mouse value there is a **judgement
call** derived from this project's own constants, not from a citable source, and **none of them
can be validated headlessly — a human has to fly the hub.** The plan's job is to make them
`@export`s so that fly-test is a two-minute inspector change, not a code change.

| Parameter | Default | Rationale |
|---|---|---|
| `keyboard_turn_rate_deg` | 220.0 | Today's `rotation_speed_deg`. Classic must be today's behaviour exactly. |
| `mouse_max_turn_rate_deg` | 150.0 | ~68% of keyboard; 180° in 1.2 s, inside `EngineBoostModule`'s 2.0 s cooldown. Below ~110 °/s the flip-boost (`boost_speed_threshold = 180` px/s) stops being aimable; above ~180 °/s Classic has no reason to exist. |
| `mouse_turn_half_life` | 0.14 s | Inside finding 3's 0.1–0.2 s "snappy but visibly lagging" band. |
| `mouse_dead_zone_px` | 48.0 | ~ the 64×64 ship sprite's footprint; camera zoom runs 1.0→0.85 so it stays about a ship's width on screen. |

---

## Build sequence

Each step leaves the game playable and the gate green.

1. **`ShipTurnController` + ship integration, both schemes, `@export`-selected.** The controller
   implements mouse and keys, `player_ship.gd` delegates `_handle_rotation` to it, and the scheme
   is an `@export` on the controller defaulting to `&"mouse"`. No autoload yet, no UI yet. At this
   commit the game is fully playable under either scheme by flipping an inspector value, and
   `rotation_speed_deg` is removed from `player_ship.gd` (it has moved to the controller).
2. **`SettingsState` autoload.** New file, `project.godot` registration, `save_sandbox.gd::PATHS`
   entry. The ship seeds `_turn.scheme` from it in `_ready()` and connects
   `open_space_scheme_changed` to `_turn.set_scheme(scheme, rotation)`. The setting is now real
   and persistent but has no UI — a test is the only way to change it.
3. **`AITargetingModule` snap survives mouse aim.** `face_instant()` on the ship, the duck-typed
   module call, the `InputEventMouseMotion` branch in `_input()`.
4. **The single-writer invariant test.** Lands after step 3 so it goes green on arrival rather than
   landing red.
5. **Focus-loss steering hold.** `set_steering_enabled()` plus the two window notifications.
6. **Settings row + `SettingsPanel` sub-overlay** in both pause-menu scenes. The player can now
   actually choose. Last because it is the only step whose value depends on all the others working.

Steps 3, 4, 5 and 6 depend only on step 1 (6 also on step 2) and do not touch each other's files,
so an interrupted window loses at most one of them.

---

## Test plan

### `tests/unit/test_ship_turn_controller.gd` (new, intent)

Tree-less `ShipTurnController.new()`; `step()` called by hand, per the `tests/README.md` house rule
on keeping `_physics_process` out of the tree.

| Case | Assertion |
|---|---|
| Frame-rate independence | 60 × `step(…, 1.0/60.0)` and 30 × `step(…, 1.0/30.0)` from the same start and target land within 1e-3 rad of each other. **Fails on a bare `lerp`** — this is finding 3's bug, pinned. |
| Turn-rate cap holds | One `step()` with `delta = 1.0` from 0 toward π moves at most `deg_to_rad(150) * 1.0`. Without the clamp the exponential term is ~99.2% of π and this fails. |
| Never overshoots | Repeated steps converge on the target and no single step passes it (`angle_difference` keeps its sign throughout). |
| Wrap-around (**boundary**) | From `rotation = 3.0` toward a target of `-3.0`, the first step is **positive** and the total travel is ~0.283 rad, not ~-5.98. |
| Cursor exactly on the ship (**boundary**) | Target far to port, then `set_aim_target(p, p)` with a zero-length vector: the target angle is **unchanged**, and the ship does not snap toward world-right (`Vector2.ZERO.angle() == 0.0`, verified in-engine). |
| Dead-zone edge (**boundary**) | Cursor at 47.9 px → target held; at 48.1 px → target updated. Pins the radius rather than assuming it. |
| 180° tie-break (**boundary**) | From `rotation = 0.0` with the target at exactly π, the step is **negative** — pinning the documented `angle_difference` rule ("returns -PI if from is smaller than to"), verified in-engine. Deliberately *not* overridden with a custom tie-break: at any real cursor position the case is measure-zero, and machinery for it would be untestable-in-practice churn. |
| Classic scheme = today's numbers | `scheme = &"keys"`, `turn_input = 1.0`, total `delta = 1.0` → exactly `deg_to_rad(220.0)`, matching the pre-epic `_handle_rotation`. |
| Classic ignores the cursor | `scheme = &"keys"`, `turn_input = 0.0`, cursor far away, many steps → rotation **unchanged**. This is the "must not affect the legacy scheme" half of the ask. |
| Mouse ignores A/D | `scheme = &"mouse"`, `turn_input = 1.0`, cursor dead ahead → rotation unchanged. |
| Scheme flip mid-flight | Mid-turn `set_scheme(&"keys", rot)` then `set_scheme(&"mouse", rot)` → `step()` returns a value within one frame's cap of `rot`; no jump, no stranded state. |
| Snap holds until the mouse moves | `face_instant(a)`; steps with a cursor 90° away leave rotation at `a`. Then `notify_mouse_moved()` → the next step turns toward the cursor. |
| Steering disabled freezes the target | `set_steering_enabled(false)`, move the cursor, step → rotation unchanged; re-enable → resumes with no discontinuity. |

### `tests/unit/test_settings_state.gd` (new, intent)

Sandboxed (`SaveSandbox.capture()/restore()`), tree-less `Script.new()` instances per the house
rule, so `_ready()`/`_load()` are called explicitly.

- Empty disk → `get_open_space_scheme() == &"mouse"` (the ask's stated default).
- `set_open_space_scheme(&"keys")` → a second instance's `_load()` reads `&"keys"`.
- An unknown value written into the `.cfg` by hand → `_load()` falls back to `&"mouse"`
  (**boundary**; `push_warning` is expected and not asserted on, matching
  `test_ship_module_state.gd::test_load_does_not_grandfather_an_unknown_equipped_id`).
- `set_open_space_scheme` with a value not in `SCHEMES` → no state change, no save.
- Setting the value it already has → `open_space_scheme_changed` does **not** fire (no redundant
  save, no spurious re-seed of the turn controller mid-flight).
- The signal carries the new scheme, with a handler of matching arity (GUT reds a test on the
  arity mismatch, per `tests/README.md`).

### `tests/integration/test_ship_rotation_single_writer.gd` (new, **invariant**)

- Sweep every `global/ship_modules/*.gd`; assert none matches `actor.rotation` followed by
  `=`/`+=`/`-=`. Allowlist empty. **Fails on today's `ai_targeting_module.gd:38`.**
- Boundary: the sweep finds a non-zero number of module files (a regex that matches nothing
  because the directory glob broke must not read as a pass) and `ai_targeting_module.gd` is among
  them by name.
- Assert `OpenSpacePlayerShip` has a `face_instant` method, so the sanctioned replacement exists
  rather than the rule merely forbidding the old one.

### `tests/integration/test_pause_menu_settings.gd` (new, intent)

Same technique as `test_pause_menu_lore_logs.gd` — set `_cursor`, call `_confirm()` directly,
never pause the tree. Sandboxed, because confirming writes to `SettingsState`.

- Mission scene and open-space scene both show `_options[4]` labelled "Settings", and
  `_options[5]` labelled "Exit Game".
- `_cursor = 4; _confirm()` → the panel is visible, `_menu_container` is hidden, and the pause menu
  itself stays open.
- `ui_cancel` while the panel is open closes only the panel (one ESC does not close the menu).
- `menu_confirm` while the panel is open does **not** fall through to `_confirm()` and re-open it —
  the exact bug the lore-log branch was written to avoid.
- `menu_right` on the steering row flips `SettingsState.get_open_space_scheme()` from `&"mouse"` to
  `&"keys"` and the row's value label follows (**the placement-only trap**: a settings row whose
  handler is empty passes every "is it visible and labelled" test, so at least one case must drive
  the live autoload — the same lesson `test_weapon_unlock_sources.gd` records).
- The panel's row reflects a value changed behind its back before `open()`.

### Changes to existing tests

None expected. `test_pause_menu_lore_logs.gd` references only option indices 1–3 (verified by
grep) and is unaffected by Exit Game moving to index 5. `test_project_load_integrity.gd`,
`test_suite_integrity.gd` and `test_resource_uid_integrity.gd` cover the new files automatically.

---

## Risks

- **The turn numbers cannot be validated by this project's gate.** 150 °/s, 0.14 s and 48 px are
  judgement calls. The gate can prove the model is frame-rate correct, capped and wrap-safe; it
  cannot tell anyone whether the ship feels good. **A human has to fly the sector hub**, and the
  epic is not really finished until they have. Mitigated by making all four numbers `@export`s on
  a node in `player_ship.tscn`.
- **Mouse aim may make the flip-boost unaimable.** `_trigger_flip_boost` fires on a `move_up`
  press while moving backwards above 180 px/s, and `EngineBoostModule` latches its direction from
  `actor.rotation` at activation. At 150 °/s the player has less authority to point before
  committing. This is a *balance* consequence of the ask, not a bug, but it is the most likely
  thing a fly-test comes back unhappy about; the cap is the dial to turn.
- **`_handle_thrust()` collision with the pending boost epic.** `_handle_rotation` and
  `_handle_thrust` are independent functions, so the conflict is textual, not semantic — but the
  two epics must not be implemented in the same window.
- **A future ship module writes `actor.rotation` again.** Exactly the class of silent regression
  the suite's other invariant tests exist for; step 4 is the guard.
- **The shared pause menu.** The option list is hard-coded `Option0..N` in two duplicated scenes
  and matched by index in `_confirm()`. Renumbering is mechanical but it is the one place in this
  epic where a mistake reaches assault and infiltration.
- **Windowed play with the pointer outside the window but the window still focused** is not
  covered by the focus-out hold. Accepted: the fix is confinement or a software cursor, both
  explicitly out of scope, and the failure mode is mild (the ship holds a stale target and keeps
  turning toward the window edge).

---

## Out of scope

- **Mouse sensitivity / adjustable turn rate in the settings panel.** `SettingsState` is shaped so
  it is another key, and `2-research.md` finding 4 says it will be asked for — but the ask is for a
  scheme toggle, and one key is what ships here.
- **Strafe, or any other job for A/D under mouse aim.** New movement mechanic; collides with the
  pending boost epic.
- **Custom cursor art, an in-world reticle, a lead/target indicator, pointer confinement or
  capture.**
- **Firing or aiming weapons at the cursor.** The ask forbids it, and the current behaviour is
  already correct: every `WeaponBehavior` and `RocketState._launch_warhead()` spawns from
  `actor.rotation`. **No weapon file is touched by this epic.**
- **Any change to assault or infiltration movement**, and any rebinding in `project.godot`'s
  `[input]` block. No new input action is required.
- **Gamepad / right-stick aiming.**
