# Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting

Epic: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
Stage: **PLAN**. Written 2026-09-13 against `agent/auto-dev` @ `df37d42`.
**Revision 2, 2026-09-14** — rewritten in response to round 1 of
[`4-review.md`](./4-review.md) (`VERDICT: CHANGES_REQUESTED`, blocking findings B1-B5 plus
twelve observations). Every change is listed under [Response to review](#response-to-review) at
the foot of this file; the sections themselves have been edited in place rather than annotated,
so what you read above that section is the plan as it now stands.
Builds on [`1-context.md`](./1-context.md) (what is already here) and
[`2-research.md`](./2-research.md) (how shipped games solve it). Neither is re-derived below.
Both were corrected in the same revision (B3, obs 8, obs 9).

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

It lives under `open_space/`, not `global/`, because mode isolation for the **turn model** is
structural: `player_ship.tscn` is instantiated by exactly one scene, `sector_hub.tscn`, so no
code is needed to enforce it, and putting the controller in `global/` would invite exactly the
sharing this epic must not have. Infiltration has its own controller; `AssaultPlayer` never
instances a `ShipTurnController`.

**Isolation is *not* free for `global/ship_modules/`.** `AssaultPlayer` applies, ticks and
activates the same equipped modules the open-space ship does
(`player_fighter.gd:29-35`, `:92-93`, `:108-118`), so `AITargetingModule` runs against the
assault fighter and writes its `rotation` **today**. The earlier claim that `player_fighter.gd`
"contains no `rotation` reference, so assault has no rotation to corrupt" was true of the file and
false of the system; `1-context.md` has been corrected. Everything this plan does to
`ai_targeting_module.gd` is therefore an edit to assault as well, and is designed below to leave
assault behaviour byte-for-byte identical.

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
| `func set_scheme(new_scheme: StringName, current_rotation: float) -> void` | Sets the scheme and re-seeds `_target_angle = current_rotation`. Also the **ready-time seeder**: the ship calls it in `_ready()` so the target angle starts at the hull's actual facing instead of relying on both defaulting to `0.0`. |

**No signal on the controller.** An earlier draft declared `signal scheme_applied(scheme)`; it had
no emit site and no consumer anywhere in the plan, so it is dropped. The controller is a pure step
function with setters — the ship calls it, nothing listens to it.

**What `set_scheme`'s re-seed actually buys** is narrower than it looks: under `&"mouse"` the very
next `_handle_rotation` calls `set_aim_target()`, which overwrites `_target_angle` from the cursor
on the next frame. The re-seed matters while steering is disabled, inside the dead zone, and under
`&"keys"`; **the thing that actually prevents a visible jump on a mid-flight scheme flip is the
per-frame rate cap**, which no code path can bypass. The test plan says so explicitly rather than
implying the re-seed is the guard.

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
(the module is in `global/` and must not assume an open-space actor). **The call is total — there
is no `actor.rotation` fallback**, because an earlier draft kept one and that draft could not pass
the single-writer sweep two steps later (review B2: the sweep's allowlist is empty, so the fallback
line fails it; the two build steps were mutually exclusive as written). The fallback is removed and
its one live consumer is served properly instead (review B3):

```gdscript
func try_activate(player: Node) -> bool:
    if _cooldown_left > 0.0:
        return false
    var actor := player as Node2D
    var target := _find_nearest_enemy(actor)
    if target == null:
        return false
    ## Duck-typed, exactly like Bullet's is_armored() query: the module lives in global/
    ## and must not assume which mode's player it is looking at. No rotation fallback —
    ## an actor that cannot face is an actor this module has nothing to do with, and the
    ## cooldown is deliberately NOT spent in that case.
    if not actor.has_method("face_instant"):
        push_warning("AITargetingModule: %s has no face_instant(); snap skipped." % actor.name)
        return false
    _cooldown_left = _COOLDOWN
    var dir: Vector2 = target.global_position - actor.global_position
    actor.face_instant(dir.angle() + PI * 0.5)
    return true
```

**Both player classes get `face_instant`, and assault's is a one-liner that reproduces today's
write exactly:**

| Class | `face_instant(angle)` does |
|---|---|
| `OpenSpacePlayerShip` (`open_space/.../player_ship.gd`) | `rotation = angle` **and** `_turn.face_instant(angle)` — adopt the angle as the controller's target and suppress cursor steering until the mouse next moves. |
| `AssaultPlayer` (`assault/scenes/player/player_fighter.gd`) | `rotation = angle`. Nothing else — there is no turn controller in assault to suppress. This is character-for-character what `ai_targeting_module.gd:38` does to the fighter today, so **assault behaviour is unchanged**. |

**Deliberately not on `PlayerBase`.** A base-class default would cover both players in one line,
but `tests/helpers/player_stub.gd` also extends `PlayerBase`, and more importantly a future
player subclass would then inherit an instant-snap it never asked for — silently, which is the
exact failure mode the single-writer rule exists to catch. Two explicit three-line methods keep
the duck-typed query meaningful and keep each mode's snap readable in the mode's own file.

**The assault path needs its own test, because nothing covers it today**
(`grep -rl ai_targeting tests/` finds only `test_ship_module_state.gd`, which never activates the
module). See `test_ai_targeting_faces_actor.gd` in the test plan.

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
assigns to `actor.rotation`** (`=`, `+=`, `-=`). **The allowlist is empty, and it stays empty** —
that is consistent with the code above only because the `else: actor.rotation = angle` fallback is
gone and `AssaultPlayer.face_instant()` replaces it (review B2/B3). Nothing in
`global/ship_modules/` writes an actor's rotation after this epic; the two writes that remain live
in the two player scripts, where the sweep does not look and where they are each one line long.
This test fails on today's `ai_targeting_module.gd` and goes green when the duck-typed call lands,
which is the proof that it can fail.

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
- **`tests/integration/test_pause_menu_lore_logs.gd` MUST be edited.** An earlier draft claimed it
  "references only indices 1, 2 and 3, verified by grep". That was wrong (review B1). It contains:

  ```gdscript
  func test_exit_game_is_now_at_index_4() -> void:          # line 82
      assert_eq(_menu._options[4].get_node("Label").text, "Exit Game")   # line 83
  ```

  Inserting Settings at index 4 reds that assertion, and the test's **name** encodes the old index
  too. The required edit is mechanical and is part of the pause-menu task, not a surprise for the
  session that hits it: rename `test_exit_game_is_now_at_index_4` →
  `test_exit_game_is_now_at_index_5` and change `_options[4]` → `_options[5]`. Lines 25-26 and
  35-37 reference indices 1, 2 and 3 and are genuinely unaffected.
  Settings still goes *before* Exit Game: Exit Game stays last in the list where a player expects
  it, which is worth one two-line test edit.
- **Layout is spelled out, because the rows are absolutely positioned.** `MenuContainer` sits at
  `y = 184` with option rows at `110 / 178 / 244 / 310 / 376` — a 66 px pitch — so the new sixth
  row goes at `y ≈ 442`, landing around 626 px down a 720 px viewport once the container offset
  and the button sprite's `+14` are counted. It fits, with little room to spare; if a fly-test says
  it crowds the bottom edge, the fix is to lift `MenuContainer` rather than to re-order the list.
- **The two scenes are not symmetrical, and a test must not assume they are.** In
  `pause_menu.tscn` every `Option0..Option4` has `Bg` + `Label` (and all but `Option3` an `Icon`).
  In `open_space_pause_menu.tscn`, `Option1` and `Option2` — Restart Mission and Exit Mission,
  the two rows that scene hides — are **bare `Node2D`s with no `Bg`, `Icon` or `Label` child at
  all**. Any new assertion that calls `get_node("Label")` in a loop over `_options` will crash on
  that scene; assert on the specific indices you mean (4 and 5), never on the whole list.
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
| `mouse_dead_zone_px` | 48.0 | **A judgement call that needs the fly-test most.** Not "about a ship's width": `player_ship.tscn` gives the hull `CircleShape2D_body` a radius of **11.045 px** (the 64×64 in an earlier draft is the atlas cell, mostly padding), so 48 px is ≈4.4 hull radii — a ~96 px dead circle around a ~22 px ship. It is there to stop the target angle thrashing when the cursor sits under the hull, which needs *some* radius; whether 48 is that radius is exactly what a human flying the hub has to say. `@export`, so the answer is an inspector change. |

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
3. **`AITargetingModule` snap survives mouse aim, in both modes.** `face_instant()` on
   `OpenSpacePlayerShip` **and** on `AssaultPlayer`, the duck-typed module call with **no
   `actor.rotation` fallback**, and the `InputEventMouseMotion` branch in `_input()`. Ships with
   `test_ai_targeting_faces_actor.gd`, which is what proves the assault snap is unchanged.
4. **The single-writer invariant test.** Lands after step 3 so it goes green on arrival rather than
   landing red. Empty allowlist; also asserts both player classes expose `face_instant`.
5. **Focus-loss steering hold.** `set_steering_enabled()` plus the two window notifications.
6. **Settings row + `SettingsPanel` sub-overlay** in both pause-menu scenes, **plus the two-line
   edit to `test_pause_menu_lore_logs.gd`** the renumber forces. The player can now actually
   choose. Last because it is the only step whose value depends on all the others working.

**Docs are part of steps 1, 2, 4 and 6, not an afterthought.** `CLAUDE.md` → "MANDATORY — keep the
docs current" covers "adding … an entity, component, module, or mechanic", and this epic adds a
node class to the ship (step 1), the project's **eleventh** autoload (step 2), an invariant test
(step 4) and a UI overlay (step 6). Concretely: step 1 updates the ship-composition lines in
`docs/architecture/modules/open_space.md` (`:19-20`, `:78`); step 2 updates the per-autoload table
in `docs/architecture/modules/global.md` (`:68-79`) **including the sentence that reads "All ten
are registered in `project.godot`"**, which becomes eleven; step 4 adds the new invariant test to
the list in `CLAUDE.md` and to `tests/README.md`; step 6 updates `docs/architecture/PROJECT.md`
and the shell/UI doc. Invoke the `updating-project-docs` skill in each of those sessions.

Steps 3, 4, 5 and 6 depend only on step 1 (6 also on step 2) and do not touch each other's files,
so an interrupted window loses at most one of them.

---

## Test plan

### `tests/unit/test_ship_turn_controller.gd` (new, intent)

Tree-less `ShipTurnController.new()`; `step()` called by hand, per the `tests/README.md` house rule
on keeping `_physics_process` out of the tree.

| Case | Assertion |
|---|---|
| Frame-rate independence | From `rotation = 0.0` toward a target of **0.3 rad** (small on purpose — see below), 60 × `step(…, 1.0/60.0)` and 30 × `step(…, 1.0/30.0)` land within 1e-3 rad of each other. Verified in-engine: both give `0.29787721016188`, difference exactly `0.0`, while a bare `lerpf(…, 0.1)` gives `0.29946` vs `0.28728` — 0.0122 apart, so the case reds on finding 3's bug. **The target must be inside the unclamped band.** With the shipped numbers (half-life 0.14 s, cap 150 °/s) a target of π keeps the cap binding for the whole second, which makes the model a constant-rate turn and the case passes for the wrong reason — it would then pin the clamp, not the exponential. |
| Turn-rate cap holds | One `step()` with `delta = 1.0` from 0 toward π moves at most `deg_to_rad(150) * 1.0`. **Assert on `absf(result)`**: the returned value is `-2.61799387799149`, negative, because `angle_difference(0, PI)` is `-PI` (the 180° tie-break below) — verified in-engine. Without the clamp the exponential term is ~99.2% of π and the case fails. |
| Never overshoots | Repeated steps converge on the target and no single step passes it (`angle_difference` keeps its sign throughout). |
| Wrap-around (**boundary**) | From `rotation = 3.0` toward a target of `-3.0`, the first step is **positive** and the total travel is ~0.283 rad, not ~-5.98. |
| Cursor exactly on the ship (**boundary**) | Target far to port, then `set_aim_target(p, p)` with a zero-length vector: the target angle is **unchanged**, and the ship does not snap toward world-right (`Vector2.ZERO.angle() == 0.0`, verified in-engine). |
| Dead-zone edge (**boundary**) | Cursor at 47.9 px → target held; at 48.1 px → target updated. Pins the radius rather than assuming it. |
| 180° tie-break (**boundary**) | From `rotation = 0.0` with the target at exactly π, the step is **negative** — pinning the documented `angle_difference` rule ("returns -PI if from is smaller than to"), verified in-engine. Deliberately *not* overridden with a custom tie-break: at any real cursor position the case is measure-zero, and machinery for it would be untestable-in-practice churn. |
| Classic scheme = today's numbers | `scheme = &"keys"`, `turn_input = 1.0`, **one** `step(0.0, 1.0, 1.0)` → `deg_to_rad(220.0)`, matching the pre-epic `_handle_rotation`. Use `assert_almost_eq(…, 1e-6)`, or a single step: sixty accumulations of `deg_to_rad(220.0) * (1.0/60.0)` print as `3.83972435438753` and still compare `!= deg_to_rad(220.0)` (verified), and GUT's `assert_eq` on floats is exact. |
| Classic ignores the cursor | `scheme = &"keys"`, `turn_input = 0.0`, cursor far away, many steps → rotation **unchanged**. This is the "must not affect the legacy scheme" half of the ask. |
| Mouse ignores A/D | `scheme = &"mouse"`, `turn_input = 1.0`, cursor dead ahead → rotation unchanged. |
| Scheme flip mid-flight | Mid-turn `set_scheme(&"keys", rot)` then `set_scheme(&"mouse", rot)` → `step()` returns a value within one frame's cap of `rot`; no jump, no stranded state. **Say in the test's own comment what it does and does not catch:** it catches a `set_scheme` that snaps rotation itself, which is the realistic bug; it cannot distinguish the re-seed from the cap, because the cap alone already guarantees this bound. The re-seed's real job is the frozen-steering and dead-zone cases. |
| Snap holds until the mouse moves | `face_instant(a)`; steps with a cursor 90° away leave rotation at `a`. Then `notify_mouse_moved()` → the next step turns toward the cursor. |
| Steering disabled freezes the target | `set_steering_enabled(false)`, move the cursor, step → rotation unchanged; re-enable → resumes with no discontinuity. |

### `tests/integration/test_player_ship_turn_wiring.gd` (new, intent) — **the anti-inert test**

Review B4: every other test in this plan passes on a build where the feature is never plugged in.
All of these are green while the game is unchanged — the controller is never added to
`player_ship.tscn`, `_handle_rotation` keeps its old body, `_ready()` never seeds the scheme, the
`open_space_scheme_changed` signal is never connected, or the module guards on a **misspelled**
method name and silently does nothing. `test_project_load_integrity.gd` proves the scene loads and
nothing more. This file is the one that fails on an unwired build. It instantiates
`player_ship.tscn`, is sandboxed (it touches `SettingsState`), and is sized to the headless
constraint — **it never tries to place a cursor.**

| Case | Assertion |
|---|---|
| The controller is in the scene | The instantiated `player_ship.tscn` has a `ShipTurnController` child, found by class not by node path, so a rename does not silently pass. |
| `_handle_rotation` actually delegates | With `scheme = &"keys"` and `move_right` pressed via `Input.action_press`, a hand-called `_handle_rotation(1.0)` moves `rotation` by the value the **controller instance** returns for the same inputs — compared against `controller.step(…)` computed in the test, not against a hard-coded 220°, so a controller whose rate was changed still proves delegation rather than coincidence. |
| The scheme is seeded on ready | After `_ready()`, the child controller's `scheme` equals `SettingsState.get_open_space_scheme()`. Fails on the "the setting is cosmetic" build — the exact failure `test_weapon_unlock_sources.gd` exists to remember. |
| The scheme signal is connected | Emitting `SettingsState.open_space_scheme_changed(&"keys")` (or calling the setter) re-seeds the live controller's `scheme` without a scene reload. |
| The target angle starts at the hull's facing (**boundary**) | Set the ship's `rotation` to a non-zero angle before `_ready()` runs, and assert the first `step()` with steering disabled returns that same angle — i.e. the controller was seeded from the ship rather than both happening to default to `0.0`. |
| Old API is gone | `rotation_speed_deg` no longer exists on `OpenSpacePlayerShip` (it moved to the controller), so a half-finished step 1 that leaves both cannot read as done. |

### `tests/integration/test_ai_targeting_faces_actor.gd` (new, intent) — **the duck-typing hole**

Also review B4, and B3's assault half. Nothing in the suite activates `AITargetingModule` today
(`grep -rl ai_targeting tests/` → only `test_ship_module_state.gd`), so both the method-name typo
and a silent change to assault would ship green.

| Case | Assertion |
|---|---|
| The module calls `face_instant` | A stub `Node2D` actor exposing `face_instant(angle)` and a stub enemy: `try_activate()` returns `true`, the stub records the angle as `dir.angle() + PI * 0.5`, and the stub's `rotation` is **still untouched** — the module must not write it. Reds on a misspelled `has_method` guard. |
| Assault is unchanged (**the B3 case**) | A real `AssaultPlayer` (or a `PlayerBase` subclass that implements only the one-line `face_instant`) ends at exactly the angle `ai_targeting_module.gd` produces today for the same geometry. This is the regression gate on "must not affect assault". |
| An actor that cannot face is left alone (**boundary**) | A bare `Node2D` with no `face_instant`: `try_activate()` returns `false`, `rotation` is untouched, and **the cooldown is not spent** — so the failure is inert rather than eating a 15-second ability. |

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
- Assert **both** `OpenSpacePlayerShip` **and** `AssaultPlayer` have a `face_instant` method, so
  the sanctioned replacement exists for every actor the modules run against rather than the rule
  merely forbidding the old call. Checked on the classes, not on `PlayerBase` — a base-class
  method would satisfy this assertion while giving every future player an inherited silent snap.

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

**One, and it is mandatory** (review B1). `tests/integration/test_pause_menu_lore_logs.gd`:
rename `test_exit_game_is_now_at_index_4` (line 82) to `…_index_5` and change `_options[4]` to
`_options[5]` (line 83). Without it the pause-menu step reds the gate. Lines 25-26 and 35-37 use
indices 1-3 and do not move.

Everything else is automatic: `test_project_load_integrity.gd`, `test_suite_integrity.gd` and
`test_resource_uid_integrity.gd` pick up the new files with no edit, and
`test_signal_emit_arity.gd` will sweep `SettingsState.open_space_scheme_changed` — declare it with
its `scheme: StringName` argument.

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
- **`global/ship_modules/` is shared with assault.** The one place this epic reaches outside open
  space. `AssaultPlayer` applies and activates the same modules, so the `ai_targeting_module.gd`
  edit is an assault edit; `test_ai_targeting_faces_actor.gd`'s assault case is the guard, and it
  is new coverage over code that had none. If a later module starts driving assault rotation for
  real, the single-writer sweep will make that visible rather than silent.
- **The feature ships inert.** Every unit test green, nothing wired. Called out because the epic's
  first draft had exactly that hole; `test_player_ship_turn_wiring.gd` is the guard, and it is the
  test to write **first** in step 1.
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

---

## Task-body corrections (read this before starting any implementation task)

`scripts/backlog-cli.js` can create a task and change its `type`/`complexity`/`model`, but it
**cannot edit a task body**, and the six implementation tasks were written from revision 1 of this
plan. Where a body and this section disagree, **this section wins** — it is the correction list the
round-1 review (B1, B2, B3, B5) requires, and each implementation session reads this plan before
it starts.

| Task | Correction |
|---|---|
| `your-ship-leans-toward-the-mouse-cursor-instead-of-snapping-` | **Add to DONE WHEN:** `tests/integration/test_player_ship_turn_wiring.gd` passes (the anti-inert test — write it first; the unit tests alone are all green on a build where the controller is never added to `player_ship.tscn`). **Add:** the controller declares **no signals** (`scheme_applied` is dropped), and `player_ship.gd::_ready()` seeds the controller's target angle from the hull's actual `rotation` via `set_scheme()`. **Add:** invoke `updating-project-docs` — this adds a node class to the ship scene, which `docs/architecture/modules/open_space.md:19-20` and `:78` enumerate by name. |
| `the-game-remembers-which-steering-scheme-you-fly-with` | **Add to DONE WHEN:** the two wiring cases in `test_player_ship_turn_wiring.gd` — the scheme is seeded from `SettingsState` in `_ready()`, and emitting `open_space_scheme_changed` re-seeds the live controller without a scene reload. Without those the setting is cosmetic and every named test still passes. **Add:** invoke `updating-project-docs` — this is the project's **eleventh** autoload, and `docs/architecture/modules/global.md:68-79` carries a per-autoload table introduced by the sentence "**All ten** are registered in `project.godot`", which must become eleven. |
| `ai-targeting-still-snaps-your-nose-onto-an-enemy-and-the-sna` | **Changed, not added.** The duck-typed call has **no `else: actor.rotation = angle` fallback** — the body's shape is from revision 1 and would fail the next task's sweep (review B2). Instead, `AssaultPlayer` gets its own one-line `face_instant(angle)` (`rotation = angle`, nothing else), because activating this module in an **assault** mission writes the fighter's rotation today and deleting the fallback without that would silently change assault (review B3). **Add to DONE WHEN:** `tests/integration/test_ai_targeting_faces_actor.gd` passes, including the assault case and the "actor without `face_instant` keeps its cooldown" boundary. |
| `a-future-ship-module-cannot-silently-fight-your-steering` | **Add:** the `face_instant` existence assertion covers **both** `OpenSpacePlayerShip` **and** `AssaultPlayer`, not only the open-space ship. The empty allowlist is correct **and** achievable only because the task above removed the fallback — if you find yourself wanting to allowlist a line, the previous task is unfinished. |
| `alt-tabbing-away-no-longer-leaves-your-ship-turning-on-its-o` | No correction. |
| `choose-mouse-aim-or-classic-a-d-steering-from-the-pause-menu` | **Changed.** The body says `test_pause_menu_lore_logs.gd` "references only indices 1-3 so it needs no change — confirm that before assuming it". It was confirmed, and it is **false**: line 82-83 is `test_exit_game_is_now_at_index_4` asserting `_options[4]` reads "Exit Game" (review B1). **Add to DONE WHEN:** rename that test to `…_index_5` and change the index. **Also:** `open_space_pause_menu.tscn`'s `Option1`/`Option2` are bare `Node2D`s with **no `Label` child** — never loop `get_node("Label")` over `_options` in that scene. **Model raised to `opus`** (see below). |

### Model and complexity

One change, applied with `set-meta`: `choose-mouse-aim-or-classic-a-d-steering-from-the-pause-menu`
moves from `sonnet` to **`opus`**, staying `medium` (so it stays on the Direct track — the epic's
plan is written and reviewed, and a second plan for it would be waste). It is the epic's
highest-blast-radius task: it edits a file shared by all three modes whose `_confirm()` is matched
by *index*, in two scenes that are **not** structurally identical, adds a new sub-overlay scene and
script, and must edit an existing test. The other five stay `sonnet`; none of them is
architectural and all read from this plan.

Dependencies are unchanged and still correct: tasks 3, 5 and 6 depend on task 1; task 4 on task 3;
task 6 on task 2. Steps 3, 5 and 6 touch disjoint files, so an interrupted window loses at most one.

---

## Response to review

Round 1 of [`4-review.md`](./4-review.md), `VERDICT: CHANGES_REQUESTED`. Every blocking finding
was reproduced against the files before being acted on, not taken on trust.

| Finding | What changed |
|---|---|
| **B1** — `test_pause_menu_lore_logs.gd` pins Exit Game at index 4; the plan's "verified by grep" claim was wrong | Confirmed (`:82-83`). Both false statements corrected; the rename + reindex is now an explicit line in "Changes to existing tests", in the build sequence and in the task-body corrections. Settings stays at index 4. |
| **B2** — step 3's `else: actor.rotation = angle` cannot pass step 4's empty-allowlist sweep | Confirmed. Resolved by **deleting the fallback**, not by allowlisting it: the module now returns `false` with a `push_warning` (and does **not** spend its cooldown) for an actor that cannot face. The sweep's allowlist stays empty, and the plan says so in both places. |
| **B3** — the fallback's live consumer is the **assault** player, so deleting it changes assault | Confirmed (`player_fighter.gd:29-35`, `:92-93`, `:108-118`). `AssaultPlayer` gets a one-line `face_instant()` reproducing today's write exactly, so assault behaviour is byte-for-byte unchanged. Deliberately not on `PlayerBase` (`tests/helpers/player_stub.gd` extends it too, and an inherited silent snap is the failure the single-writer rule exists to catch). `1-context.md`'s wrong claim is corrected at source. New `test_ai_targeting_faces_actor.gd` covers code that had no coverage at all. |
| **B4** — nothing tested the wiring; the feature could ship inert | Two new integration tests: `test_player_ship_turn_wiring.gd` (controller present, `_handle_rotation` delegates to **that instance**, scheme seeded from `SettingsState` on ready, signal re-seeds live, target seeded from the hull's facing, `rotation_speed_deg` gone) and the duck-typing case in `test_ai_targeting_faces_actor.gd`. Both stay inside the headless constraint — neither places a cursor. |
| **B5** — the mandatory docs step was on one task of six | Docs obligations are now a named paragraph in the build sequence (steps 1, 2, 4, 6, with the exact files and the "All ten" → eleven line) and repeated per task in the corrections table. |

Non-blocking observations: **1** (frame-rate case moved to a 0.3 rad target inside the unclamped
band — the π version passed for the wrong reason, difference exactly `0.0` at both rates because
the cap bound for the whole second), **2** (assert `absf(result)`; the value is `-2.61799387799149`),
**3** (single step or `assert_almost_eq`; sixty accumulations of `deg_to_rad(220)/60` compare
`!=` the constant), **4** (the scheme-flip case's limits are now stated in the case itself — the
cap is what prevents the jump, not the re-seed), **5** (`scheme_applied` dropped — no emit site, no
consumer), **6** (row pitch, the `y ≈ 442` sixth row, and the missing `Label` children in
`open_space_pause_menu.tscn`), **7** (dead-zone rationale corrected to the 11.045 px hull radius and
flagged for the fly-test), **8** (the Nova Drift software-mouse attribution withdrawn in
`2-research.md`; the idea is retained and labelled unsourced), **9** (both counts fixed: 10
autoloads today, "All ten" → eleven when `SettingsState` lands), **10** (pause-menu task raised to
`opus`; B1's test edit also spelled out, since `backlog-cli` cannot rewrite the body), **11**
(`_target_angle` is seeded from the ship's rotation via `set_scheme()` in `_ready()`, with a
boundary case), **12** (no change needed — noted that `PlayerBase` declares no `_notification`, so
`player_ship.gd` can add one without a `super()` call).

All numeric claims above were re-verified in this container against Godot 4.6.3 headless before
being written into the test plan.
