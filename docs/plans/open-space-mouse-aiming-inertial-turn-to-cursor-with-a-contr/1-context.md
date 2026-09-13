# Context

Epic: **Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting**
(`open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`)
Stage: RESEARCH. Written 2026-09-13 against `agent/auto-dev` @ `4ca5714`.

The ask, verbatim from the source idea: open-space flight steers with the mouse; the ship turns
*toward* the cursor with a deliberate lag rather than snapping; mouse turning is **slower** than
today's A/D so precision aim is not free; weapons and movement abilities keep firing along the
ship's **actual facing**, not the cursor; A/D stays as a selectable legacy scheme; nothing may
reach assault or infiltration; a setting toggles the schemes with **mouse aim as the default**;
overall feel "responsive but inertia-based, inspired by Jet Lancer".

---

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `open_space/scenes/entities/player/player_ship.gd` | `OpenSpacePlayerShip extends PlayerBase`. `_physics_process` → `_handle_rotation` + `_handle_thrust` + `move_and_slide` + `_update_camera_feel` + module tick. | **The only file whose behaviour has to change.** `_handle_rotation()` (line 107–113) is the whole current turn model: `rotation += deg_to_rad(rotation_speed_deg) * turn * delta` with `rotation_speed_deg = 220.0`. No angular velocity, no acceleration, no clamp. |
| `open_space/scenes/entities/player/player_ship.tscn` | The ship: `HealthComponent`, `ShieldComponent`, `OverheatComponent`, `TempHealthComponent`, `HurtBox`, `AttackStateMachine` (`WeaponState` + `RocketState`), `MovementController`, `Camera2D` (+`CameraDirector`), `SpriteAnchor/ShipSprite2D`. | Where a turn-controller node or a reticle node would be composed in. `uid://qf4mu6gg75ca`. |
| `open_space/scenes/levels/sector_hub.tscn` | The hub level. | **The only scene in the project that instantiates `player_ship.tscn`** (verified by grep). Mode isolation is therefore structural, not something the plan has to engineer. |
| `open_space/scenes/mission_select_hubs/mission_select_hub.gd` | `MissionTrigger`. On `_open_menu()` it calls `player.set_physics_process(false)` + `set_process_input(false)` (lines 155–156), plays `planet_dive`, opens the menu, then `get_tree().paused = true`. Restores both on close (lines 197–198). | Answers the triage's "does the cursor keep steering while the mission-select menu is open?" — **it already cannot**: physics is off *and* the tree is paused. Same for `PlayerMenu` and `PauseMenu`, which both set `get_tree().paused = true` while the ship's `process_mode` is the default `INHERIT`. |
| `global/ui/pause_menu/pause_menu.gd` + `open_space_pause_menu.tscn` | ESC menu. Five hard-coded `Node2D` options (`Option0..4`); in open space `Option1`/`Option2` are `visible = false`, leaving Resume / Lore Logs / Exit Game. `_navigate()` already **skips hidden options**, and `LoreLogList` is an in-place sub-overlay with its own input routing. | The natural entry point for a control-scheme setting, and the `LoreLogList` sub-overlay is the precedent to copy. Note the menu is **`global/`**, shared with assault and infiltration — a Settings row added here appears in every mode. |
| `global/ui/player_menu/player_menu.gd` | Tab menu; `process_mode = ALWAYS`, pauses the tree, rebuilds its weapon column on `UpgradeState.unlocked_changed`. | The other candidate host for a setting, and the precedent for "a menu that must rebuild when an autoload signal fires". |
| `global/autoloads/ship_module_state.gd`, `upgrade_state.gd`, `log_state.gd`, `session_state.gd` | The `user://*.cfg` `ConfigFile` persistence pattern: `const SAVE_PATH`, `const SECTION`, `_ready() -> _load()`, validate ids on the way in *and* on load, `_save()` after every mutation, a `signal` on change. | A control-scheme setting is exactly this shape. Copy it; do not invent a new persistence style. |
| `global/ship_modules/ai_targeting_module.gd` | `try_activate()` line 38: `actor.rotation = dir.angle() + PI * 0.5` — a hard snap onto the nearest enemy. `tick()` runs every frame but only updates the indicator line. | **The one real conflict.** It is one of only two writers of the open-space ship's rotation project-wide (grep over `global/` + `open_space/` for `rotation =`/`+=` returns exactly `ai_targeting_module.gd:38` and `player_ship.gd:113`). Under a turn controller that owns an angular velocity and chases the cursor, a raw `rotation =` is undone on the next frame. |
| `global/ship_modules/engine_boost_module.gd` | `try_activate()` latches `_boost_dir = Vector2.UP.rotated(actor.rotation)` and re-asserts `velocity = _boost_dir * speed` every `tick()`; sets `engine_boost_active = true` so `_handle_thrust()` early-returns. | Already reads **facing**, so "abilities follow facing, not the cursor" is satisfied for free. But a slower turn makes aiming the boost harder — a tuning risk, and the reason `_handle_rotation` must keep running during a boost (it currently does; only `_handle_thrust` is skipped). |
| `global/ship_modules/warp_module.gd` | Sets `warp_module_active`; the blink is driven by `MovementController.action_double_press`, which in open space **has no consumer** (no `DashState` in `player_ship.tscn`). | So the Warp module is inert in open space today, and double-tap A/D is free. Relevant because the plan must decide what A/D *do* under the mouse scheme. |
| `assault/scenes/player/weapons/behaviors/*.gd` | `StraightBehavior:16`, `SpreadBehavior:15`, `SniperBehavior`, `BeamBehavior:53` all spawn from `Vector2.UP.rotated(actor.rotation)` / `actor.rotation + jitter`. `RocketState._launch_warhead()` likewise (`rocket.rotation = actor.rotation`). | **"Weapons follow facing, not the cursor" is already true** and stays true as long as the mouse only writes `rotation`. No weapon code should be touched. Any design that aims a weapon at the cursor directly would break this requirement. |
| `assault/scenes/player/movement_controller.gd` | Polls `Input.is_action_just_pressed` over `move_*`, `special_weapon`, `switch_weapon`, `cycle_weapon`; emits `action_single_press(String)` / `action_double_press(String)`. | Shared with assault. It polls **actions**, not devices, so it is untouched by this work — but it is a reminder that input here is action-based, and `shoot` already has **LMB bound** in `project.godot` alongside `J`. |
| `assault/scenes/player/player_fighter.gd` | The assault player. Grep for `rotation` returns **nothing**. | Mode isolation confirmed from the other side: the assault ship has no rotation to corrupt. Infiltration likewise uses its own controller. |
| `project.godot` | `[input]` has 20 actions; the only mouse binding anywhere is LMB on `shoot`. `[display]`: viewport 1280×720, window override 1920×1080, `stretch/mode="canvas_items"`. `[autoload]`: 11 entries. | A new autoload is a `project.godot` edit. The stretch mode matters: `Node2D.get_global_mouse_position()` accounts for the canvas transform and stretch, so it is correct at any window size — a raw `DisplayServer.mouse_get_position()` would not be. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/autoloads/ship_module_state.gd` | The complete `ConfigFile` autoload template: `SAVE_PATH`/`SECTION` consts, `_ready()→_load()`, id validation on write **and** on read with `push_warning` on unknown values, `_save()` after each mutation, change signal. A `SettingsState` (or similar) should be a near-copy of ~40 lines of this. |
| `global/autoloads/upgrade_state.gd` | The `ALL_IDS` / `is_known_id()` / `STARTING_IDS` shape for "a small closed set of valid values with a default", plus the `unlocked_changed` signal that `PlayerMenu` rebuilds on. Directly analogous to "two control schemes, one default, UI rebuilds on change". |
| `global/ui/pause_menu/pause_menu.gd` `_open_lore_logs()` / `_close_lore_logs()` / `_lore_logs_open` | The sub-overlay pattern: hide `MenuContainer`, show the sub-panel, absorb **all** menu input including `menu_confirm` while it is open, route `ui_cancel` back one level. A settings panel is the same shape. `_navigate()` already skips invisible options, so adding an option that is hidden in some modes costs nothing. |
| `tests/helpers/save_sandbox.gd` | `capture()` / `restore()` / `clear_all()` over a hard-coded `PATHS` list. **A new `user://*.cfg` must be added to `PATHS`**, or every test that touches the setting leaks into the player's profile and into the next suite run. |
| `global/systems/camera_shake.gd`, `CameraDirector` | Precedent for "a small autoload/arbitrator other systems push targets into", if the plan wants the turn controller to arbitrate between cursor steering and module snaps rather than letting modules write `rotation` raw. |
| `@GlobalScope.rotate_toward(from, to, delta)` / `angle_difference(from, to)` | Engine-provided, wrap-correct shortest-path rotation. Godot in this container is **4.6.3**, and `rotate_toward` landed in 4.4, so it is available. See `2-research.md` finding 2 for the exact documented semantics. |
| `OpenSpacePlayerShip._update_camera_feel()` | Already computes `facing = Vector2.UP.rotated(rotation)` and pushes a `&"speed_feel"` effect into `CameraDirector` at priority 0. Any reticle/lead work should go through the same director rather than touching `Camera2D` directly. |

## Conventions that constrain this

- **Composition over inheritance.** A turn model is behaviour, not an entity. The two shapes that fit
  the house style are (a) a small `Node` component under `player_ship.tscn` (like
  `MovementController`), or (b) private state + a method on `OpenSpacePlayerShip`. What does **not**
  fit is a new `PlayerBase` subclass or a `global/` base class shared with assault.
- **Signal arity is declared exactly.** `signal scheme_changed(scheme: StringName)`, never a bare
  `signal scheme_changed`. `tests/integration/test_signal_emit_arity.gd` sweeps every self-emit
  project-wide and will fail on a bare declaration whose emits carry arguments.
- **Per-frame logging sits behind `if OS.is_stdout_verbose()`.** A turn controller is per-frame code.
- **Design-unit coordinates (640×360 × `ArenaCamera.WORLD_SCALE`) do not apply here** — that is an
  assault wave-authoring rule. Open space is authored in world pixels directly.
- **Config-driven `.tres` stats do not apply here either** — that convention is for *assault enemies*.
  The open-space ship's movement numbers are `@export` vars on `player_ship.gd`
  (`rotation_speed_deg`, `thrust_acceleration`, `max_speed`, `damping`, `boost_*`), and new turn
  parameters belong there, beside them, as `@export`s.
- **Never hand-type a `uid://`.** Any new `.tscn`/`.gd` either goes UID-less or gets one minted with
  the headless `ResourceUID.create_id()` snippet in `tests/README.md`.
- **`test_project_load_integrity.gd` fails on any engine error *or warning*** logged while loading or
  instantiating every non-`addons/` `.tscn`/`.tres`/`.gd`. A new autoload that `push_warning`s at
  boot, or a scene with a dangling reference, reds the gate.
- **Working branch is `agent/auto-dev`; `main` is off-limits.**

## Dependencies and blast radius

**Contained.** The mode-isolation requirement is satisfied by the existing structure, not by new code:

- `player_ship.tscn` is instantiated by exactly one scene (`sector_hub.tscn`).
- The assault player has no rotation at all; infiltration has its own controller.
- Weapons already fire from `actor.rotation`, so restricting the mouse to *writing rotation only*
  keeps the "weapons follow facing" requirement true with zero weapon-code change.

What genuinely spreads beyond `open_space/`:

1. **A settings store.** There is no options system in the project — zero settings autoload, zero
   options screen. Something new lands in `global/autoloads/` and in `project.godot`'s `[autoload]`
   block, and its `user://*.cfg` path must be added to `tests/helpers/save_sandbox.gd::PATHS`.
2. **A UI entry point.** `global/ui/pause_menu/` is shared by all three modes. Adding a Settings row
   there changes the ESC menu in assault and infiltration too (the row itself is mode-agnostic even
   if the setting it exposes only affects open space) and touches **both** `pause_menu.tscn` and
   `open_space_pause_menu.tscn`, which duplicate their option nodes rather than sharing them.
   `tests/integration/test_pause_menu_lore_logs.gd` exercises this menu and indexes options by
   cursor position, so inserting a row mid-list will need that test updated.
3. **`AITargetingModule`** (`global/ship_modules/`) needs a defined interaction, because its hard
   `actor.rotation =` write is incompatible with a controller that owns angular velocity.
4. **Possibly `project.godot`'s `[input]`** if any new action is introduced (e.g. a scheme-toggle
   hotkey). Not required by the ask.

**Scheduling collision:** the untriaged idea *"Add Boost/Burst Movement to Open Space"* targets
`_handle_thrust()` in the same file. `_handle_rotation()` and `_handle_thrust()` are independent
functions, so the collision is textual, not semantic — but the two should not be implemented
concurrently in the same window.

## Risks, edge cases, testing requirements

**Risks**

- **Turn rate is the whole balance lever.** The ask is explicit that mouse turning must be
  *noticeably slower* than the current 220 °/s, yet still "responsive". Too slow and the ship feels
  like it is on ice and the flip-boost becomes unaimable; too fast and the keyboard scheme is
  strictly worse and nobody picks it. This number cannot be validated headlessly — see "Known gaps"
  discipline in the dossier rules; the plan should say plainly that a human has to fly it.
- **`AITargetingModule` fighting the controller.** If the module keeps writing `actor.rotation`
  directly, its snap is visibly undone within a frame or two under mouse aim. Three candidate
  resolutions, all cheap: (a) give the ship a `face_angle_instant(angle)` that sets rotation, zeroes
  angular velocity **and** suppresses cursor steering until the mouse next moves; (b) have the
  module set the controller's *target* angle so the ship turns to the enemy at the normal rate
  (changes the module from "snap" to "assist" — a behaviour change, and the suite is
  characterization); (c) declare the module a no-op under mouse aim. This is the single biggest
  design decision in the epic and must be settled in `3-plan.md`, not at implementation time.
- **Second writer discipline.** Whatever is chosen, after this epic there must be exactly one way to
  set the open-space ship's facing. A raw `rotation =` from a future module reintroduces the bug.
  That is a testable invariant (see below) and worth one.
- **Cursor leaving the window.** In windowed mode the OS pointer can leave the game window; the last
  in-window position is what `get_global_mouse_position()` keeps returning, so the ship holds a
  stale target angle instead of stopping. `MOUSE_MODE_CONFINED` fixes it but confines the pointer
  globally, which is hostile on a multi-monitor desktop and in the editor. Needs an explicit call.
- **Shared pause menu.** A "Settings" row in `global/ui/pause_menu/` that only does something in
  open space is a discoverability trap in the other two modes.
- **Camera lead offsets the ship from screen centre.** `_update_camera_feel` pushes the viewport up
  to `_LEAD_MAX = 140 px` ahead of the ship and zooms 1.0 → 0.85 with speed. Any dead zone must
  therefore be measured **ship-to-cursor in world space**, never "distance from screen centre".

**Edge cases the test plan must cover**

- Cursor exactly on the ship (zero-length vector → `Vector2.angle()` of `Vector2.ZERO` is `0.0`, i.e.
  a silent snap to world-right). Must not produce a spin.
- Cursor directly *behind* the ship (±180°). Verified in-engine: `rotate_toward(0.0, PI, 0.1)`
  returns **`-0.1`**, i.e. it turns the *negative* way, because `angle_difference` returns `-PI`
  when `from < to`. The chosen direction therefore flips with the sign of the ship's current
  `rotation`. Deterministic but arbitrary from the player's seat — pin whichever behaviour the plan
  picks. See `2-research.md` → "Verified in-engine".
- Wrap-around across ±π: a naive `target - rotation` takes the long way round. This is exactly what
  `angle_difference`/`rotate_toward` exist to prevent, and is the classic bug in this feature.
- Legacy scheme selected → mouse must have **zero** effect, and A/D must behave *identically to
  today* (220 °/s, instantaneous, no angular velocity carried).
- Scheme flipped mid-flight → no rotation jump, no stranded angular velocity.
- Frame-rate independence: the same wall-clock turn from 1/60 s steps and 1/30 s steps (see
  `2-research.md` finding 3 — a raw `lerp(rotation, target, 0.1)` fails this).
- Assault and infiltration unaffected — cheap to assert, because their players expose no rotation.

**Testing requirements (the hard constraint)**

The suite is headless GUT. `Input.warp_mouse()` is documented as moving the **OS** cursor and is
unsupported on some platforms; `Input.parse_input_event()` explicitly does *not* move it. So a test
cannot reliably place a real cursor. **The turn model must therefore be driven by an injectable
target — a method like `set_aim_target(world_pos)` or `steer_toward(angle, delta)` — with
`get_global_mouse_position()` read in exactly one place and passed in.** A design that calls
`get_global_mouse_position()` from inside the integration step is effectively untestable headlessly,
and that alone should decide the API shape. House rules also apply: keep `_physics_process` out of
the tree and call the step function by hand (`tests/README.md` → "House rules"), and sandbox the new
`user://` file.

## Open questions for the plan

1. **Turn model.** Angular velocity with acceleration + damping and a max turn rate (carries
   momentum, can overshoot and settle — closest to "inertia"), versus frame-rate-correct exponential
   smoothing toward the target angle (never overshoots, always decelerating, cheaper, one parameter),
   versus `rotate_toward` at a constant rate with a short spin-up ramp. Research finding 2/3/4
   covers the tradeoffs; the plan must pick one and say why.
2. **The numbers.** Max mouse turn rate (the ask says clearly below 220 °/s), angular acceleration
   or smoothing half-life, damping, and the dead-zone radius in world px. Starting points are
   proposed in `2-research.md`; all of them need a human fly-test.
3. **What A/D do under the mouse scheme.** Nothing, a manual override that wins while held, or
   strafe. Note `action_double_press` currently has no consumer in open space, so double-tap A/D is
   free either way.
4. **`AITargetingModule`** — (a), (b) or (c) above.
5. **Cursor presentation.** Default OS arrow, a custom crosshair sprite, or a hidden OS cursor plus
   an in-world reticle. Whether to draw a facing/target-angle indicator. Whether to confine the
   pointer to the window, and if so only in the hub.
6. **Where the setting lives and what it is called.** New `SettingsState` autoload vs. extending an
   existing one; a Settings row in the shared `PauseMenu` vs. a tab in `PlayerMenu`; the id scheme
   (e.g. `&"mouse"` / `&"keys"`) and the default (`&"mouse"`, per the ask).
7. **Migration/default semantics.** `UpgradeState.STARTING_IDS` only ever reaches an *empty* store,
   so it is a fresh-profile declaration rather than a per-boot guarantee. The setting needs a real
   default-on-missing-key, which is what `ConfigFile.get_value(section, key, default)` gives — decide
   deliberately rather than copying the `STARTING_IDS` idiom, which is the wrong one here.
