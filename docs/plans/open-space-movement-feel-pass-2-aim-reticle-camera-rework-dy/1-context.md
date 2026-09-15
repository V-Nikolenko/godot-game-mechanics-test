# Context — open-space movement feel, pass 2

Epic: `open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy`. Stage: **RESEARCH**,
2026-09-15. Companion to [`2-research.md`](./2-research.md), which covers how shipped games solve
the same four problems and is not repeated here.

This is a **play-test follow-up** to two already-shipped epics. Their artifacts are the starting
point for this one and must not be re-derived:

- [`../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/`](../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/)
  — `ShipTurnController`, the single-writer rule, the `&"mouse"`/`&"keys"` setting.
- [`../open-space-boost-shift-burst-movement-on-an-upgradeable-boos/`](../open-space-boost-shift-burst-movement-on-an-upgradeable-boos/)
  — `BoostMeter`, `BoostBar`, `ShipProgressionState.boost_charge_count`, `ShipBoostUpPickup`.

The epic carries **four threads**. They share one file (`player_ship.gd`) and one scene
(`player_ship.tscn`) but are otherwise independent, and the plan stage should treat them as four
separable deliverables rather than one change.

---

## 1. Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `open_space/scenes/entities/player/player_ship.gd` | `OpenSpacePlayerShip extends PlayerBase`. Owns `_physics_process`, `_handle_rotation`, `_handle_thrust`, `_step_boost`, `_update_camera_feel`, module pool. | **Every one of the four threads lands in this file.** It is 390 lines and already the busiest script in `open_space/`. |
| `open_space/scenes/entities/player/player_ship.tscn` | The ship scene. Children: `HealthComponent`, `ShieldComponent`, `OverheatComponent`, `TempHealthComponent`, `SpriteAnchor/{ShipSprite2D, MuzzleLeft/Right, EngineLeft/Right}`, `Collision`, `HurtBox`, `AttackStateMachine`, **`ShipTurnController`**, **`BoostMeter`**, `MovementController`. | Where a reticle node and/or a replacement meter node would be parented. **Note: it contains no `Camera2D`** — see row below. |
| `open_space/scenes/entities/player/ship_turn_controller.gd` | Pure step function; the only writer of the ship's `rotation`. Holds `mouse_dead_zone_px = 48`, `mouse_max_turn_rate_deg = 150`, `mouse_turn_half_life = 0.14`, `_snap_held`, `_steering_enabled`. | Thread 1: the reticle must show the dead zone, the snap hold and the steering-disabled state — all three already exist as state here, and none of it is currently readable from outside except `get_target_angle()`. |
| `open_space/scenes/levels/sector_hub.tscn` | The hub. **Owns the `Camera2D`** — `PlayerShip/Camera2D`, with `PlayerShip/Camera2D/CameraDirector` under it. | Thread 2. The camera is *not* part of the ship scene, so any test that instantiates `player_ship.tscn` alone gets `_update_camera_feel()`'s `get_node_or_null("Camera2D") == null` early return. |
| `global/systems/camera_director.gd` | `CameraDirector`. Named effects → `{priority, zoom, offset}`; per-frame picks max priority, lerps `_applied_*` toward it at `blend_speed` (6.0), writes `camera.zoom` and `camera.offset + CameraShake.get_offset()`. Resyncs and skips a frame if `camera.zoom` was written externally. | Thread 2's arbitration layer. **It has no test file anywhere in `tests/`.** |
| `global/systems/camera_shake.gd` | `CameraShake` autoload, trauma model, `_MAX_OFFSET = 8.0`, `_DECAY = 1.5`. Unit-tested (`tests/unit/test_camera_shake.gd`). | Thread 2/3: the existing "impact" channel. A boost kick would go through it rather than a new system. |
| `open_space/scenes/mission_select_hubs/mission_select_hub.gd` | `MissionTrigger`. Pushes `&"planet_dwell"` at **priority 10** with `zoom 1.0→1.2` and `offset dir*40*progress`; clears it on exit/menu. Freezes the ship (`set_physics_process(false)`, `set_process_input(false)`) for the `planet_dive` animation, then pauses the tree. | Thread 1: the reticle must disappear while the menu is up and the ship is frozen. Thread 2: the second consumer of the director, and the reason a camera rework must stay inside the effect model rather than writing the camera directly. |
| `open_space/scenes/entities/player/boost_meter.gd` | `BoostMeter`. Continuous internal `charges: float`, whole-unit `try_spend()`, `recharge_rate = 0.7/s`, `recharge_delay_sec = 0.5`, `bind_progression`, `charges_changed(current: float, maximum: int)`. Driven by the ship's `step(delta)`, never its own `_physics_process`. | Thread 4. **The economy is already continuous internally** — only `try_spend()` and `BoostBar._draw()` are whole-charge. That is the single most important fact for thread 4. |
| `open_space/scenes/gui/boost_bar.gd` | `BoostBar extends Node2D`, `top_level`, drawn at ship + `(0, 26)`. 32×4 px, draws `_max_charges` pips with a 1 px gap, cyan `#59E6FF`. Always visible. | Thread 4's readout. The pip loop is the only part that has to change for a continuous bar; the seed-then-connect `setup()` pattern stays. |
| `global/ship_modules/engine_boost_module.gd` | `EngineBoostModule`, `get_display_name() == "Boost Drive"`, slot `&"engines"`, H key (`use_ability`). 1500→500 px/s over 0.55 s, 45 damage in a 32 px radius, `damage_reduction = 1.0` for the whole window, 2 s cooldown, sets `player.engine_boost_active`. | Thread 4's "with the module" tier. Today it is a *separate verb on a separate key*; the epic asks for it to become a *modifier on Shift*. |
| `global/autoloads/ship_module_state.gd` | `SLOTS = [cockpit, armor, weapons, engines]`, `SLOT_MODULES[&"engines"] == [&"", &"warp", &"engine_boost"]`, `get_equipped(slot)`, signals `module_equipped(slot, id)` / `module_unequipped(slot, prev_id)`. | Thread 4's tier switch. `player_ship.gd:_ready()` already connects both signals and applies whatever is equipped, so the hook for "the bar changes shape when Boost Drive is equipped" already exists. |
| `global/autoloads/ship_progression_state.gd` | `boost_charge_count`, `MIN_BOOST_CHARGES = 2`, `MAX_BOOST_CHARGES = 5`, `add_boost_charge()`, `boost_charge_count_changed(new_count)`, persisted to `user://ship_progression.cfg`. | Thread 4's upgrade economy. Reusable as-is whether the readout is pips or a bar — the number just changes meaning from "pips" to "bar units". |
| `global/pickups/ship_boost_up_pickup.gd` + `.tscn` | The `+1 boost` pickup, placed in `sector_hub.tscn` at `(730, -212)`. Gated by `tests/integration/test_boost_upgrade_source.gd`. | Thread 4: the upgrade is already reachable; only its *meaning* changes. |
| `global/autoloads/settings_state.gd` | `SCHEMES = [&"mouse", &"keys"]`, `get/set_open_space_scheme()`, `open_space_scheme_changed(scheme)`, persisted. Surfaced in `global/ui/pause_menu/settings_panel.gd`. | Threads 1–3: under `&"keys"` there is no cursor, so a cursor-driven reticle and a cursor-driven camera must both degrade to something sane. This is the single most commonly-missed case. |
| `open_space/scenes/gui/hud.tscn` (`OpenSpaceHUD`, `global/ui/mission_hud.gd`) | Screen-space `CanvasLayer`: weapon chip, health/shield, shield strip, `PlayerMenu`, `PauseMenu`. | Thread 1's other candidate home for the reticle (screen space, no camera transform, already the HUD root). |
| `project.godot` `[input]` | `boost` and `dash` are **both** bound to physical `KEY_SHIFT` (4194325); `use_ability` is `H`; `move_up/down/left/right` are WASD-ish. `dash` is read only by `infiltration/scenes/entities/player/player.gd:84`. | Thread 4: Shift is free in open space. No new action is needed for hold-to-boost — `Input.is_action_pressed("boost")` is the same action. |

---

## 2. Existing code to reuse

| Path | What it gives us |
|---|---|
| `ShipTurnController` (`ship_turn_controller.gd`) | An already-tested, frame-rate-correct, injected-input turn model, plus `get_target_angle()`. **The reticle's aim point is `_target_angle`, not the raw cursor** — reusing it is what makes the reticle show the lag the ship actually has. |
| `BoostMeter` | A continuous float pool with a post-spend regen pause, progression binding and a hand-driven `step(delta)`. A hold-drain is `charges -= drain_rate * delta` on the *same* field — no new component is required for the continuous tier. |
| `BoostBar.setup()` | The seed-then-connect pattern that avoids drawing an empty bar for the first frames, plus the `top_level` + `_physics_process` repositioning pattern shared with `OverheatBar`. |
| `assault/scenes/player/overheat_bar.gd` | The sibling world-space bar. `BAR_HEIGHT = 4`, drawn at `(0, 20)`; the boost bar sits at `(0, 26)`. Any third readout has to fit under these two. |
| `CameraDirector.set_effect()/clear_effect()` | Named, prioritised, blended camera control with a working hand-off to `planet_dwell` and the pause menu. **A camera rework should change what `speed_feel` pushes, not bypass the director.** |
| `CameraShake.add(amount)` | The impact channel (`0.35` on a hit, `1.0` on death). Thread 3's "boost kick" and thread 2's "land the 180° flip" both want this, not a new shake. |
| `assault/scenes/systems/arena_camera.gd` | **The project already ships a dead-zone follow camera** — `deadzone_half_size = Vector2(40, 30)`, `follow_speed = 12.0`, follow state kept separate from shake so shake never pollutes the lerp baseline. The assault camera is the precedent for the open-space rework, and its separation of follow-state from shake is a pattern worth copying verbatim. |
| `ShipModuleBase` + `ShipModuleState` signals | The equip/unequip hook the ship already listens to. The Boost-Drive tier switch is `get_equipped(&"engines") == &"engine_boost"` plus the two signals — no new state. |
| `global/pickups/ship_boost_up_pickup.gd` | The `+1 capacity` verb, already placed and already gate-tested. |
| `tests/helpers/save_sandbox.gd` | The `user://` sandbox every test that touches `ShipProgressionState`/`SettingsState` must use. |
| `tests/integration/test_player_ship_turn_wiring.gd`, `test_open_space_boost_wiring.gd` | The **anti-inert** pattern: find the node *by class*, prove the scene actually carries it, so a rename or a deleted node fails loudly. Any new node (reticle, second meter) needs the same. |

---

## 3. Conventions that constrain this

- **The mouse is read in exactly one line project-wide** — `player_ship.gd::_handle_rotation`'s
  `get_global_mouse_position()`. Everything downstream takes the cursor as an injected `Vector2`.
  A reticle that calls `get_global_mouse_position()` itself would be the second read and would be
  untestable headlessly (`Input.warp_mouse()` cannot place a cursor in a headless GUT run). The
  reticle must be **fed** the position from that one line, or from `ShipTurnController`.
- **`ShipTurnController` is the only writer of `OpenSpacePlayerShip.rotation`** — gated by
  `tests/integration/test_ship_rotation_single_writer.gd`, which sweeps `global/ship_modules/*.gd`
  for a raw `.rotation =`. A "banking"/roll animation (thread 3) must therefore be a **sprite**
  transform (`SpriteAnchor.rotation`/`skew`/frame choice), never a hull rotation.
- **Headless input is a hard constraint.** Neither `Input.is_action_just_pressed()` nor
  `Input.is_action_pressed()` can return true in the gate. `_step_boost(boost_pressed, delta)`
  exists precisely because of this. **Hold-to-boost must extend the same shape** — e.g.
  `_step_boost(pressed: bool, held: bool, delta: float)` — or the whole thread is untestable.
- **Composition over inheritance** — new behaviour is a child node of `player_ship.tscn` resolved
  *by type* in `_ready()`, like `ShipTurnController` and `BoostMeter`, not a new base class.
- **Signal arity is declared and swept** — `tests/integration/test_signal_emit_arity.gd` checks
  every self-emit against `get_signal_list()`. Any new signal (e.g. `boost_state_changed`) must
  declare its parameters.
- **`@export` anything that cannot be validated headlessly.** The turn epic put all four turn
  numbers on the scene for exactly this reason; the boost epic did the same with
  `boost_exit_speed`/`boost_hold_sec`/`boost_ceiling_decay`. Every new feel number here —
  lookahead time, dead-zone size, drain rate, flip threshold — is in that category.
- **No hand-typed `uid://`.** New `.gd`/`.tscn`/`.png` files get their UID from the editor import
  or are left UID-less; `tests/integration/test_resource_uid_integrity.gd` decodes rather than
  string-matches.
- **Art is strict top-down orthographic** and goes through the `pixel-art-generation` skill.
  A reticle sprite is a **UI asset**, not a world entity — but if it is drawn over the game world
  under `assault/scenes/{...}` roots it would also have to clear
  `tests/integration/test_entity_sprite_transparency.gd`'s 90%-opacity rule. Drawing the reticle
  with `_draw()` primitives (as `BoostBar` and `OverheatBar` already do) sidesteps both the
  PixelLab allowance and that gate entirely, and is the cheaper first version.

---

## 4. What is actually wrong today — measured, not assumed

Numbers below were computed from the shipped constants (`/tmp/calc.gd`, 60 Hz), and the Camera2D
behaviour was verified against the engine rather than assumed.

### 4.1 The camera lead uses the wrong direction vector

```gdscript
var spd := velocity.length()
var t   := clampf(spd / _SPEED_THRESHOLD, 0.0, 1.0)      # _SPEED_THRESHOLD = 400
var facing        := Vector2.UP.rotated(rotation)
var target_offset := facing * _LEAD_MAX * t if spd > 1.0 else Vector2.ZERO   # _LEAD_MAX = 140
```

The **magnitude** comes from the speed of the actual `velocity`; the **direction** comes from the
hull's facing. Rearranged, `140 * (speed/400) == speed * 0.35`, so the shipped formula is exactly
**"0.35 seconds of travel, pointed along the nose"**. Swap `facing` for `velocity.normalized()`
and it becomes exactly the textbook look-ahead — `velocity × lookahead_time` — that
[`2-research.md`](./2-research.md) findings 1 and 2 describe. That is the smallest correct fix and
the plan should start from it rather than from a new subsystem.

Consequences of the facing/velocity mismatch, in the player's words:

- *"it is behind the ship"* — cursor dragged to the bottom of the screen while momentum still
  carries the ship up: `facing` points down, `velocity` points up, the camera extends **opposite to
  travel**, so the ship runs off the top of the frame with the camera pushing the other way.
- *"it mixes up and down"* — same cause; there is no axis bug, the sign is simply taken from the
  wrong vector.

### 4.2 The swing is 280 px, and it is the *target* that swings, not the blend

- Any aim error above **30.3°** is rate-cap-limited, so a 180° turn takes a flat **1.20 s**
  (`mouse_max_turn_rate_deg = 150`).
- Over that 1.20 s the lead target travels from `-140` to `+140` px — a **280 px** swing, **39% of
  the 720 px viewport height**, at up to ~233 px/s of pure camera motion the ship is not making.
- `CameraDirector.blend_speed = 6.0` is a **0.116 s half-life** (95% settled in 0.5 s). It is
  *responsive*, not sluggish: it faithfully reproduces the swing. **Lowering it would only add lag
  without removing the swing** — the triage note's "blends at only 6/s" framing is the wrong
  diagnosis. The fix has to be to the target.

### 4.3 The camera does **not** rotate with the ship — verified

`Camera2D.ignore_rotation` defaults to `true` (checked against Godot 4.6.3 via
`ClassDB.class_get_property_default_value`), and a probe with a camera parented to a node rotated
90° returned an identical `get_screen_center_position()` of `(0, -140)` for a `(0, -140)` offset.
So the `Camera2D` being a child of a per-frame-rotated `CharacterBody2D` is **harmless**, and the
offset is world-axis-aligned. This hypothesis from triage is dead; do not spend plan time on it.

### 4.4 Coasting is very long, but the lead decays faster than it looks

`velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0, 1))` with `damping = 0.6` is an exponential
with a **1.16 s half-life**:

| t after releasing W | speed | lead |
|---|---|---|
| 0.00 s | 420 px/s | 140 px (capped) |
| 0.57 s | 300 px/s | 105 px |
| 1.23 s | 200 px/s | 70 px |
| 2.38 s | 100 px/s | 35 px |
| 3.90 s | 40 px/s | 14 px |
| **10.03 s** | 1 px/s | 0.4 px |

So "the ship looks stopped while the lead is at full strength" is only true for the first ~1 s;
by 2.4 s the lead is a quarter of maximum. The **10 s tail** is a separate observation: the ship
never actually stops, which matters for a *velocity*-based lead (it will keep a small permanent
offset) and is the argument for a **dead zone** (finding 3) rather than only for damping.

### 4.5 Boost is a one-shot redirect with no orientation condition

`_step_boost()` sets `velocity = Vector2.UP.rotated(rotation) * 700` on any press with a charge.
The 180° flip therefore already *works* — rotate 180°, tap Shift, fly the other way at 700 px/s —
but there is no hold, no orientation test, no ramp, and the whole above-cruise signature is
~1.05 s (0.35 s hold + 0.70 s ceiling decay at 400 px/s²). What the player asked for is the
**hold** and the **long bar**, not the redirect, which already exists.

### 4.6 There is no cursor feedback of any kind

`grep` over the whole project for `MOUSE_MODE`, `set_custom_mouse_cursor` and `CURSOR_` returns
only unrelated menu-highlight colour constants. The player flies with the bare OS arrow, which
carries none of the three states the turn controller already tracks: inside `mouse_dead_zone_px`
(48 px), `_snap_held` (an AI-Targeting snap is being honoured), `_steering_enabled == false`
(window unfocused).

---

## 5. Dependencies and blast radius

- **All four threads touch `player_ship.gd`.** Ordered sequentially they are fine; run in parallel
  they will collide in `_physics_process` and `_step_boost`. The plan's task list must serialise
  them or split the file first.
- **Thread 2 touches a shared autoload-adjacent system.** `CameraDirector` is used by the mission
  trigger (priority 10) and side-stepped by the pause menu's zoom tween. Changing the *contract*
  (e.g. adding a position channel, or a second effect name) affects both. Changing only what
  `speed_feel` pushes affects neither.
- **Thread 4 changes the meaning of a persisted value.** `ShipProgressionState.boost_charge_count`
  is on disk in `user://ship_progression.cfg` with range 2–5. If the continuous tier reinterprets
  it as "bar length", an existing save's `3` must still mean something sensible. Migration is
  cheap here (the range does not change) but must be stated, not assumed.
- **Thread 4 changes `EngineBoostModule`'s role.** It currently has its own key, its own cooldown,
  its own i-frames and its own 45 contact damage. Folding it onto Shift means deciding what
  happens to `use_ability`/H (freed? kept as an alias?), and `tests/integration/`'s module tests
  plus `test_module_unlock_sources.gd` will need to still pass.
- **`&"keys"` scheme.** No cursor exists. Reticle must hide; a cursor-biased camera must fall back
  to a pure velocity lead.
- **Assault and infiltration are untouched** by all four threads — but `Input.mouse_mode` is a
  **process-global** singleton, so any cursor hiding must be set on entering the hub and restored
  on leaving it, or the arrow stays hidden in every other mode and in the boot menu.

---

## 6. Risks and edge cases

1. **Hiding the OS cursor is global and sticky.** Set `Input.mouse_mode` in the hub and it survives
   into `assault/`, `infiltration/`, the boot menu and the pause menu. Every exit path
   (mission launch, scene reload on death at `player_ship.gd`'s `reload_current_scene()`, quit)
   must restore it. `Input.set_custom_mouse_cursor()` has the same globality problem but fails
   softer — the player still has *a* cursor.
2. **A software reticle lags the hardware cursor by at least one frame** (engine docs, finding 4).
   For a *precise* aim point that is felt. For a *state ring around the ship* it is irrelevant.
3. **A cursor-biased camera moves the world under the cursor, which moves the cursor's world
   position, which moves the camera** — a feedback loop. `get_global_mouse_position()` is a world
   position; the aim target is recomputed from it every frame *after* the camera moved. Any camera
   offset driven by the cursor must be computed from the cursor's **screen** position (or from the
   ship→cursor vector captured before the camera update) or it can oscillate. This is the single
   biggest correctness trap in thread 2.
4. **The 48 px dead zone is measured ship→cursor in world space**, and the camera already leads by
   up to 140 px, so the "cursor sitting on the ship" case is not the same as "cursor at screen
   centre". A reticle that draws the dead zone must draw it **around the ship**, not around the
   screen centre.
5. **Freeze paths.** `MissionTrigger._open_menu()` disables the ship's physics *and* input, then
   pauses the tree. A reticle and any camera effect must not be left mid-swing, and `BoostMeter`
   must stay frozen (it already is, because the ship drives its `step()`).
6. **Boost hold across a freeze.** With hold-to-boost, Shift held while the mission menu opens must
   not drain the bar for the duration of the menu, and must not auto-resume on close. This is a new
   failure mode the one-shot boost does not have.
7. **`_speed_ceiling` is the one clamp on this ship.** A hold-drain boost has to *hold* the ceiling
   up for as long as the key is down, and `_speed_ceiling` is floored at `max_speed`, so the
   existing decay path must not fight the hold.
8. **`EngineBoostModule` sets `engine_boost_active`, and `_step_boost()` early-returns on it.**
   A merged Shift verb must decide which of the two owns `velocity`, or they will both write it.
9. **Motion sickness is the reported symptom, and it is an accessibility issue, not a taste issue**
   (finding 3). Whatever the camera does, there should be a way to turn the lead down or off —
   `SettingsState` already has the pattern (`open_space_scheme`), and the pause menu already has a
   settings panel with rows.
10. **Thread 3 is genuinely open-ended.** "Movement is not very fun" has no acceptance criterion a
    headless gate can check. The plan must convert it into a small number of *named, bounded*
    mechanics with numbers, or it will absorb the whole epic.

---

## 7. Testing requirements

What the gate can and cannot prove here is unusually lopsided, and the plan should say so
explicitly rather than promising coverage it cannot deliver.

**Can be tested headlessly:**

- Every pure step function, driven with injected inputs: a camera-target function
  `f(velocity, facing, cursor_offset, delta) -> Vector2`, a drain/refill step on the meter, a flip
  detector `f(velocity, rotation) -> bool`. This is the `ShipTurnController` / `_step_boost`
  precedent and it is the reason both of those are testable at all.
- Anti-inert wiring: the reticle node / meter node is actually in `player_ship.tscn` (or the HUD)
  and is found **by class**, following `test_player_ship_turn_wiring.gd` and
  `test_open_space_boost_wiring.gd`.
- Boundary cases that matter: lead at zero velocity; lead while facing is 180° from velocity
  (**the bug this epic exists to fix — this case must fail on today's build**); drain to exactly
  zero mid-frame; a hold that spans a `step()` where `delta` is larger than the remaining bar;
  Boost Drive equipped *during* a hold; `&"keys"` scheme with no cursor.
- Persistence: `boost_charge_count` round-trips and still clamps to 2–5 after any reinterpretation.
- The camera **director** itself, which today has **no test at all**: priority arbitration,
  hand-off blending, `clear_effect`, and the external-write resync. Worth one file regardless of
  which camera design wins.

**Cannot be tested headlessly, and must be flagged for a human fly-test:**

- Whether the camera still induces motion sickness.
- Whether hold-to-boost *feels* better than tap-to-boost.
- Whether the reticle reads at a glance over a starfield.
- Every tuning number. All of them belong on `@export`s.

**Traps from `tests/README.md` that apply here:** the `user://` save sandbox
(`ShipProgressionState`, `SettingsState`), the signal-arity sweep, and the coroutine/`SceneTreeTimer`
leak rule (`scripts/check-test-leaks.sh` after touching anything that `await`s).

---

## 8. Open questions for the plan

1. **Thread 2 — one formula or a new effect?** Replacing `facing` with `velocity.normalized()`
   inside `_update_camera_feel()` is a ~3-line change that fixes the reported bug. Adding a dead
   zone, a cursor bias and a damped look-ahead is a small camera *system*. Which of these is the
   epic buying, and does the system belong in `_update_camera_feel()`, in a new
   `OpenSpaceCameraRig` child node (testable, `@export`-able, the `ShipTurnController` shape), or
   inside `CameraDirector`? **Recommendation from this stage: a new child node**, because the
   director is shared with assault-adjacent code and a pure step function is the only thing the
   gate can check.
2. **Thread 2 — does the cursor bias the camera at all?** Nuclear Throne's "centre between
   character and cursor" (finding 2) solves the player's stated proposal *and* thread 1's
   "where is my cursor" problem in one move, but it is a bigger behaviour change than a lead fix,
   and it risks the feedback loop in §6.3.
3. **Thread 1 — hardware cursor, software reticle, or both?** Finding 4 says the hardware cursor
   is a frame faster and is what the engine recommends; only a software node can draw the dead-zone
   ring around the *ship*. A split (hardware cursor image for the aim point, `_draw()` ring on the
   ship for state) gets both and needs no PixelLab budget.
4. **Thread 3 — which two or three mechanics?** Candidates, all bounded: (a) strafe/reverse as
   *unlockable engine modules* rather than defaults (finding 5's shipped precedent, and it fits
   `SLOT_MODULES[&"engines"]` exactly); (b) sprite-level banking on turn (must not touch hull
   `rotation`); (c) a speed/zoom "tunnel vision" kick on boost (finding 7); (d) a directional
   `CameraShake` kick on the flip (finding 2's Celeste note). The plan must pick, not list.
5. **Thread 4 — one verb or two?** Is the 180° flip a *condition* on hold-to-boost (hold Shift
   while facing >N° away from travel ⇒ hard redirect) or a separate tap-vs-hold split on the same
   key? Finding 6 (ULTRAKILL, from the previous epic's research) argues for one unconditional rule;
   finding 8 (Ridge Racer 3D's Flex nerf) warns that a hold with a spin-up delay kills
   responsiveness.
6. **Thread 4 — one component or two?** The continuous tier is `charges -= rate * delta` on
   `BoostMeter`'s existing float; the segmented tier is today's `try_spend()`. Both already live in
   that file. A **mode flag on `BoostMeter`** is the smaller change; a second component duplicates
   the progression binding and the regen pause. Note that Ridge Racer 7 ships *exactly* this as one
   system with swappable nitrous types (finding 7).
7. **Thread 4 — what happens to the H key?** If Boost Drive moves onto Shift, `use_ability` has no
   consumer in the engines slot. Does H stay as an alias, or does the module lose its key?
8. **Thread 4 — does the core Shift boost keep `EngineBoostModule`'s 45 contact damage and full
   i-frames?** The previous epic's research (its findings 2, 4, 5) already argued **no** for the
   core boost; if the module now shares the key, the differentiation has to move somewhere else.
9. **Accessibility** — does a "reduce camera lead" setting go in `SettingsState` in this epic or a
   later one? Finding 3 says it should exist; it is one row in `settings_panel.gd`.
