# Plan review — open-space movement feel, pass 2

VERDICT: CHANGES_REQUESTED

Epic: `open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy`. Stage: **PLAN-REVIEW**,
2026-09-16. Reviewed: [`1-context.md`](./1-context.md), [`2-research.md`](./2-research.md),
[`3-plan.md`](./3-plan.md), and the nine generated tasks.

This is a good plan. The diagnosis in §4.1 is correct and I reproduced it from the source; the
research is genuinely tradeoff-bearing and mostly quote-accurate; the decomposition is sane; and
the plan rejects four tempting options (cursor-bias camera, directional shake, conditional flip
threshold, lowering `blend_speed`) with reasons rather than silence. Almost every codebase claim it
makes is true — I checked them all and list the verification at the bottom.

It is not approvable as written. Seven findings below are blocking. Two of them (B2, B3) are
factual errors about `player_ship.gd`'s control flow that would ship a change that does not do what
the plan says it does; one (B1) means the epic's self-declared defining test cannot fail on any
implementation; one (B4) means the headline boost task does not deliver the behaviour its own title
promises. All seven are cheap to fix at the plan stage and expensive to discover mid-implementation.

---

## Blocking

### B1 — CAM-1: the epic's "defining case" test cannot fail. It is structurally vacuous.

`3-plan.md`, test plan, `tests/unit/test_open_space_camera_rig.gd`:

> **The epic's defining case:** velocity `(0, -400)` (travelling up) with `rotation = PI` (nose
> down) leads **up**. `get_offset().y < 0`. *This fails on today's build*, where the lead is
> `facing * mag` and points down — it is the whole reported bug in one assertion.

The rig's own API, three pages earlier in the same document, is:

```gdscript
func step(velocity: Vector2, delta: float) -> void
func get_offset() -> Vector2
```

`rotation` is never passed in. A unit test on this class therefore *cannot* set "nose down" in any
way the code under test can observe, and `get_offset().y < 0` is guaranteed by the signature for
**every** implementation that conforms to the spec — including a deliberately wrong one. It also
cannot "fail on today's build", because on today's build the class does not exist.

That is not a nitpick about wording. The regression this epic exists to prevent is *someone
reintroducing `facing` into the lead*, and after CAM-1 the only place `facing` could re-enter is
`player_ship.gd`, not the rig. The unit file as specified gives zero coverage of it.

**Required:** move the defining case into `tests/integration/test_open_space_camera_wiring.gd`,
where the ship is real: set `ship.rotation = PI` and `ship.velocity = Vector2(0, -400)` on a ship
under the `Camera2D` + `CameraDirector` harness, drive one physics frame, and assert the pushed
`speed_feel` offset has `y < 0`. That case fails on today's `player_ship.gd:381-384`
(`facing * _LEAD_MAX * t`) and fails again on any future build that reintroduces it. Keep the unit
file for what it *can* discriminate — magnitude, the dead-zone subtract-don't-clip boundary,
frame-rate independence, `_motion_scale == 0.0`, `set_boosting()`.

Evidence: `open_space/scenes/entities/player/player_ship.gd:368-384`; the rig API block in
`3-plan.md` § "Thread 2 — the camera".

---

### B2 — BST-3 §6.8 is wrong about the control flow: moving `_boost_meter.step()` changes nothing in the game.

`3-plan.md` § "Thread 4", §6.8:

> One change is needed: `_boost_meter.step(delta)` moves **above** it, so the pool refills during
> the module's 0.55 s burst instead of stalling.

"it" is `_step_boost()`'s `if engine_boost_active: return` at `player_ship.gd:263-264`. But
`_step_boost()` is called from the **last line of `_handle_thrust()`** (`player_ship.gd:253`), and
`_handle_thrust()` has its own, *earlier*, early return on the same flag:

```gdscript
216  func _handle_thrust(delta: float) -> void:
217      ## EngineBoostModule controls velocity directly while active;
218      ## skip all thrust/damping/cap to preserve straight-line direction.
219      if engine_boost_active:
220          return
...
253      _step_boost(Input.is_action_just_pressed("boost"), delta)
```

So during `EngineBoostModule`'s 0.55 s burst, `_step_boost()` is **never called at all** from the
game loop. Reordering two lines inside a function that is not reached cannot make the pool refill.
The only thing the move affects is the test path, which calls `_step_boost()` directly and so
bypasses `_handle_thrust()` — which is exactly what `player_ship.gd:258-262`'s comment says the
redundant return exists for.

**Required:** either (a) hoist the meter tick out of `_step_boost()` into `_physics_process()` (or
above `_handle_thrust()`'s return), which is the change that actually delivers the stated goal and
is a two-line move — note it also changes the meter's freeze semantics, which `boost_meter.gd:68-72`
and §6.6 both depend on, so the freeze test in BST-2 must still pass; or (b) drop the claim and
state that the meter is intentionally frozen for the module's 0.55 s. Do not ship the described
change believing it does (a).

Risk 4 in the plan tells BST-3 to "re-read the comment rather than assume" — good instinct, wrong
line. The comment is fine; the surrounding control flow is what was not read.

---

### B3 — BST-3 spends a tank before it knows the module will fire.

`3-plan.md` § "Thread 4", BST-3:

> `_step_boost()`'s press branch becomes: `if meter.try_spend_segment(): module.try_activate(self)`.
> … Its internal 2 s cooldown stays as a floor; the meter is the resource gate.

`EngineBoostModule.try_activate()` refuses outright while the module is active or cooling:

```gdscript
42  func try_activate(player: Node) -> bool:
43      if _active or _cooldown_left > 0.0:
44          return false
```

with `_COOLDOWN = 2.0` (`engine_boost_module.gd:10`). The retrigger floor the plan keeps on the
Shift side is `boost_hold_sec = 0.35`. So every press in the **0.35 s – 2.0 s window** passes the
Shift-side guard, spends a whole tank via `try_spend_segment()`, and then gets `false` back from a
module on cooldown. The charge is gone and nothing happened. At `segments = 3` that is a third of
the player's bar burned on one mistimed press, silently.

This also contradicts the plan's own framing: the two gates are described as composing ("the meter
is the resource gate", the cooldown is "a floor"), but as written they compose in the order that
loses the resource.

**Required:** specify the order — gate on the module's readiness *before* the spend (the module
needs a `can_activate()`-shaped query, which is the same duck-typed precedent BST-3 is already
introducing with `is_open_space_boost_verb()`), or refund on a `false` return. And add the test
case: **a press during the module's cooldown spends no segment and activates nothing.** The plan's
current BST-3 cases cover "meter short of a segment" but not "meter full, module not ready", which
is the one that loses the player's resource.

---

### B4 — BST-2's "sustain" applies no force, so holding Shift without W burns the bar while the ship slows down.

The task is titled *"Holding Shift burns the bar for sustained speed"*. The specified sustain branch
is:

```
sustain (_boosting):  meter.drain(drain_rate * delta); _speed_ceiling = boost_exit_speed
```

`_speed_ceiling` is a **clamp**, not a thrust — `player_ship.gd:294-295` only ever reduces velocity.
Nothing in the sustain branch adds velocity. With W not held, `_handle_thrust()` takes its `else`
branch and damps:

```gdscript
241      velocity = velocity.lerp(Vector2.ZERO, clamp(damping * delta, 0.0, 1.0))
```

— the 1.16 s half-life §4.4 measures. So the specified behaviour is: press Shift at 700 px/s, hold
it, and the ship *decelerates* on the damping curve at 1.0 bar-units/second. The player pays the
whole bar for a decay they would have got for free. Sustain only works if W happens to also be
held, and the plan never says so.

There is a second, smaller half of the same problem: the boost's visual tell is driven purely off
`_boost_hold_left`, at `player_ship.gd:231-235` and `243-247` (`ThrusterEffect.State.BOOST if
_boost_hold_left > 0.0`), and `_release_boost_flame()` fires when it reaches zero
(`player_ship.gd:282-285`). Under the new model `_boost_hold_left` is a 0.35 s *minimum*, so on any
hold longer than 0.35 s the cyan flame and both thrusters drop out of BOOST while the boost is still
running and still draining. The tell disagrees with the state.

**Required:** state what the hold actually does to velocity — re-assert `velocity = Vector2.UP
.rotated(rotation) * boost_exit_speed` each sustain frame, or add a thrust term, or make the hold
require W and say so. And route the flame/thruster state off the new `_boosting` flag rather than
`_boost_hold_left`. Then the test case list needs one more: **holding with no thrust input keeps
speed at `boost_exit_speed`** (which is the assertion that fails on the plan as written).

---

### B5 — FLY-1 skews a node that parents gameplay markers, not the sprite.

> `_step_bank(rotation_delta, delta) -> float` is a pure method on the ship returning the new skew,
> assigned to `$SpriteAnchor.skew`.

`SpriteAnchor` (`player_ship.tscn:235`) is not a sprite holder. Its children are `ShipSprite2D`,
`MuzzleLeft` `(-18, -1)`, `MuzzleRight` `(18, -1)`, `EngineLeft` `(-8, 30)`, `EngineRight` `(9, 30)`
(`player_ship.tscn:237-252`), and the muzzles are the **bullet spawn points** `WeaponState` reads
(`player_ship.tscn:270-275`, `weapon_muzzles = [.../MuzzleLeft, .../MuzzleRight]`).

`Node2D.skew` is part of the node's own transform and **propagates to children** — verified
empirically on the local Godot 4.6.3 build: with a parent at `skew = PI/4`, a child at local
`(0, 100)` resolves to global `(-70.71, 70.71)`. The shear rotates the Y basis only, so at the
plan's `bank_max_rad = 0.12` the muzzles (y = -1) move ~0.12 px — harmless — but the engine markers
(y = 30) move ~3.6 px laterally, and the thrusters move with them.

The magnitudes are small enough that this is probably fine. That is not the point: the plan states
"**It must be a sprite transform, never a hull rotation**" as a hard constraint and then picks the
one node in the hierarchy whose transform is *not* sprite-only. The right target is
`SpriteAnchor/ShipSprite2D`.

**Required:** name `$SpriteAnchor/ShipSprite2D` (or state deliberately that the engine markers are
meant to shear with the hull, which is a defensible visual choice), and add a case to FLY-1's tests
pinning the muzzles' global positions across a full-amplitude bank — the same "prove the sprite
change did not leak into gameplay" shape as the single-writer boundary case the plan already has.

---

### B6 — FLY-2 promises an accessibility guarantee its own API cannot deliver, and is missing the CAM-2 dependency.

> `CameraShake.add(0.25)` on the boost's start frame … and `rig.set_boosting(true)` for the
> duration … **both scaled by `_motion_scale`** so the accessibility setting still governs them.

The zoom half is fine — `get_zoom()` applies `_motion_scale` internally. The shake half is not.
`CameraShake.add()` is called from `player_ship.gd`, `_motion_scale` is a private member of the rig,
and the rig's specified API (`step`, `get_offset`, `get_zoom`, `set_boosting`) exposes no reader for
it. As written, `camera_motion = off` still shakes the screen on every boost — and finding 3 lists
"camera shakes or tilting" among the problem cases *by name* (I confirmed that phrase is verbatim on
the Game Accessibility Guidelines page).

There is a task-graph consequence: FLY-2's `dependsOn` is `[BST-2, CAM-1]`. If the shake is to
honour the setting, FLY-2 also needs **CAM-2**, which is where `camera_motion` and `_motion_scale`'s
non-default values come from.

**Required:** add a `get_motion_scale()` accessor to the rig's API (or route the shake call through
it), and add `players-who-get-motion-sick-can-turn-the-camera-s-automatic-` to FLY-2's `dependsOn`.
Add the test case: `_motion_scale == 0.0` ⇒ a boost start adds no trauma.

---

### B7 — `2-research.md` finding 9 presents two quotes that are not on the cited pages, contradicting the doc's own sourcing note.

The doc opens with: *"Nothing below is attached to a page that was not actually read."* That is false
for finding 9. Neither quoted passage —

- "Each Stamina Vessel received will increase the Stamina Wheel with an additional part of **one
  fifth of a wheel**. This means five Vessels are needed for each additional full Wheel"
- "10 Stamina Vessels, allowing him to have **three full Stamina Wheels**"

— appears on `zeldadungeon.net/wiki/Stamina_Wheel` or `/wiki/Stamina_Vessel`. Both pages are
Cloudflare-gated from this container (WebFetch 403; `scripts/fetch-page.sh` 403 / CAPTCHA
interstitial), so they were checked via Wayback captures (incl. a 2026-02-16 capture) and
cross-checked against `zelda.fandom.com` and `zeldawiki.wiki`. The actual text is *"each adds
another 1/5 of a wheel to the Stamina Wheel"* and *"Link can obtain a maximum of 10 Stamina Vessels
in order to gain 2 extra Stamina Wheels."*

**The facts are right and the numbers are right**, so no plan decision changes and finding 9's role
(keep visible unit ticks on the continuous bar) survives intact. But quotation marks around
reconstructed prose is the one error in a research doc that makes every other quote in it
unverifiable-by-default, and this doc is otherwise unusually careful — it labels the Nova Drift
attribution caveat, it records three sources that yielded nothing, it flags the 402 and the Steam
blocks. Fix the quotes to the real text, or mark the retrieval method.

For the record, I spot-checked the other load-bearing rows and they are **clean, verbatim**:
finding 7's *"one long gauge that requires the nitrous button to be held"*, *"If used for five
seconds…"*, Extended Type's 1.5×, Quad's extra tank, Slipstream's one-tank start; finding 8's *"hold
the nitrous button for a second"* and *"nearly hard to strategize"*; finding 4's *"at least one
frame of latency"* and all three size limits; finding 1's three Cinemachine definitions; finding 3's
player quote and its *Vision (Intermediate)* classification. See N10 for two minor citation-precision
slips in findings 3 and 7 that do not rise to blocking.

---

## Non-blocking notes

**N1 — CAM-1 bundles what the research told it to split, without saying why.**
`2-research.md` § "What the findings imply", implication 1: *"**Do not bundle them**: if the small
fix ships first, the fly-test that follows tells the user whether the layer is even wanted."* CAM-1
ships the velocity fix **and** the dead zone **and** the cap change **and** the smoothing **and** a
new node, in one task. That may well be right — the node is justified on testability grounds and the
plan argues it well — but the plan records four explicit rejections and not this one. Add a
sentence. Risk 6 already concedes the player may dislike the corrected camera; bundling three
additional tuning changes into the same task is what makes that hard to bisect by feel.

**N2 — CAM-2 needs a scene edit, not just `settings_panel.gd`.**
`settings_panel.gd:36` is `_rows = [$Rows/Row0]` — the row is a node in the pause-menu scene, and
`_refresh()` writes `$Rows/Row0/ValueLabel`. A second row is a new `Row1` node plus its `Label` /
`ValueLabel` children in `open_space_pause_menu.tscn`, not only "another entry in `_rows` and another
branch in `cycle()`". The panel's own header comment (line 15) is what the plan quotes, and it is
eliding the same thing.

**N3 — the `SaveSandbox` blanket is half the discipline for `SettingsState`.**
The plan says "All new tests use `tests/helpers/save_sandbox.gd` wherever `ShipProgressionState` or
`SettingsState` is touched." `tests/README.md:745-751` is explicit that this is not sufficient: the
sandbox covers `user://settings.cfg`, **not** the autoload's in-memory value, and a test that leaves
the live singleton changed re-seeds every later test in the same GUT process.
`test_player_ship_turn_wiring.gd:21-31` and `test_pause_menu_settings.gd` both do the two-layer
capture/restore by hand. CAM-2's new `camera_motion` key needs the same, and RET-1/RET-2's
scheme-dependent cases do too.

**N4 — FLY-1 and FLY-2's tests are filed in the wrong file.**
The plan puts `_step_bank()`'s cases and the boost-camera cases in
`tests/integration/test_open_space_boost_verb.gd`. Banking has nothing to do with the boost verb,
and that file's header states its scope as "the whole model lives in `_step_boost`". A
`test_open_space_flight_feel.gd` is the right home for FLY-1 at least.

**N5 — `segments` collides with an existing meaning in the file BST-1 extends.**
`tests/integration/test_boost_bar.gd:143` is already
`test_segments_follow_capacity_on_signal`, where "segments" means the per-charge **pips**, i.e.
`max_charges`. BST-1 introduces `BoostMeter.segments` meaning **tanks**, which is a different number
in the same file (`max_charges = 5, segments = 4`). Rename one of them — `tanks` for the new concept
reads better and matches finding 7's vocabulary.

**N6 — BST-1 is the second-biggest task and is really two deliverables.**
It ships (a) the meter's economy API — `drain()`, `try_spend_segment()`, `set_segments()`,
`segment_size()`, `segments`, `drain_rate`, `min_start_charge`, `segments_changed` — and (b) a full
re-render of `BoostBar` (proportional width, N tanks, unit ticks, per-tier colour), against two
different existing test files. Medium/sonnet is defensible *because* the plan specifies both
completely, and I am not asking for a split up front — but it is the natural split point if it
overruns, and BST-2/BST-3 both block on it.

**N7 — "make it more powerful" is answered by relabelling, and the numbers are not tunable.**
Idea point 4 says *"move existing boosting with charges to the 'boost drive' module, **but make it
more powerful**"*. BST-3 answers this by leaving `EngineBoostModule` exactly as it is (1500→500 px/s,
0.55 s, 45 damage, full i-frames — `engine_boost_module.gd:5-10`) and arguing it is already stronger
than the 700 px/s default tier. That is a fair reading and I would not block on it. But all six of
those numbers are `const`, not `@export`, so unlike every other feel number in this epic there is no
fly-test knob at all — and the plan's own rule is "`@export` anything that cannot be validated
headlessly". Converting them is two lines in BST-3 and makes the ask actually answerable after a
fly-test.

**N8 — `EngineBoostModule.get_description()` becomes false in open space.**
`engine_boost_module.gd:30` begins *"Press H to supercharge engines."* BST-3 makes H a no-op for this
module in open space (that is the whole point of `is_open_space_boost_verb()`), and the ship menu
renders that string verbatim. Add the description update to BST-3.

**N9 — idea point 3 is answered thinly but honestly; file the follow-up epic.**
The player asked for movement to be *"more responding and dynamic. Maybe movement features,
animations, skills."* The plan's answer is one animation (banking) plus one screen effect (boost
punch), and an argument — from findings 5 and 10, two shipped top-down games that withheld strafe on
purpose — that thread 4 *is* the movement feature, with strafe/stabilisation deferred to
`SLOT_MODULES[&"engines"]` as a future epic. I checked both findings and the argument is real, not a
rationalisation, and the plan states the deferral in Design **and** in Out of scope rather than
burying it. So: not a quiet drop, and I am not blocking on it. Two asks anyway: (1) the follow-up
engines-module epic is *mentioned*, never *filed* — file it, or the ask evaporates when this epic
closes; (2) Risk 6 already schedules a fly-test after CAM-1 — that is the moment to ask the player
directly whether banking + boost punch reads as "more dynamic", because nothing in the gate can.

**N10 — minor citation slips (no decision depends on any of these).**
- `3-plan.md` cites `player_ship.gd:96-108` for the resolve-children-by-type pattern; that is the
  bar construction. The loop is `player_ship.gd:84-88`.
- `player_fighter.gd:116` for the H loop; `_input` is at line 114 and the loop at 120.
- `2-research.md` finding 3 quotes *"automatic camera movement without player input"* — that phrasing
  is the research doc's own; the page says *"changing where the character is looking without the
  player's input"*. The other two quoted phrases in that row are verbatim.
- `2-research.md` finding 7's *"up to three gauges at a time can be charged, but only one shot of
  nitrous can be used at a time"* is verbatim but comes from the **Ridge Racer (PSP)** section, not
  RR7 Standard Type. RR7's own entry supports "three" independently, so the number stands.
- `1-context.md` §1 gives the hub as `open_space/scenes/levels/sector_hub.tscn` — correct; the plan's
  prose §1 reference is fine too. (Only noting it because the task brief carried a wrong path.)

**N11 — who keeps the reticle on the ship?**
RET-2 specifies `AimReticle extends Node2D`, `top_level`, "centred on the ship". `top_level` on a
`CanvasItem` reinterprets local coordinates as global (verified on 4.6.3), so it needs
`global_position` reassigned every frame exactly as `_overheat_bar` and `_boost_bar` do at
`player_ship.gd:148-151`. The plan never says who does that. One line, but it is the difference
between a ring on the ship and a ring stuck at world origin.

**N12 — BST-3 is the one complexity assignment worth re-checking on open.**
Every other task is correctly sized. BST-3 is the only cross-cutting one: it edits
`global/ship_modules/ship_module_base.gd` (the base class of all fifteen modules),
`engine_boost_module.gd`, `player_ship.gd`, and asserts behaviour in `player_fighter.gd`. With B2 and
B3 resolved in the plan it is still a medium — the virtual is three lines and the tier switch is
two — so I am not asking for a reassignment now. But it is the task Risk 5's escalation clause is
for, and the escalation should be recorded with `set-meta --complexity large --model opus` rather
than pushed through, per `CLAUDE.md`.

---

## What I verified, and what held

Everything below I opened and read; none of it is taken from the plan on trust.

**Codebase claims — all true:**

| Claim | Verified at |
|---|---|
| The lead takes magnitude from `velocity` and direction from `facing`; early-returns with no `Camera2D` | `player_ship.gd:368-384` |
| `SpriteAnchor` exists | `player_ship.tscn:235` |
| `ShipTurnController` and `BoostMeter` are direct children, resolved by type | `player_ship.tscn:290,296`; `player_ship.gd:84-88` |
| The `Camera2D` + `CameraDirector` live in the hub, parented under `PlayerShip` | `open_space/scenes/levels/sector_hub.tscn:83-86` |
| One `get_global_mouse_position()` project-wide, injected downstream | `player_ship.gd:213` |
| `get_target_angle()`, `mouse_dead_zone_px = 48`, `_snap_held`, `_steering_enabled` all exist | `ship_turn_controller.gd:130,47,55,58` |
| 180° takes 1.20 s (`mouse_max_turn_rate_deg = 150`) | `ship_turn_controller.gd:40` |
| `BoostMeter.charges` is already a `float` with a whole-unit `try_spend()` | `boost_meter.gd:39-40,59-65` |
| `BoostBar` is a fixed 32 px re-sliced into `max_charges` pips; no external consumer of `BAR_WIDTH` | `boost_bar.gd:16,45-52` |
| `SettingsState._save()` writes exactly one key and would clobber a second | `settings_state.gd:43-48` |
| `CameraDirector.set_effect(name, zoom, offset, priority)`, `blend_speed = 6.0` | `camera_director.gd:38,63` |
| `CameraShake.add()` is the real API and is scalar-only | `camera_shake.gd:31,43-51` |
| `SLOT_MODULES[&"engines"] == [&"", &"warp", &"engine_boost"]`, `get_equipped(slot)` | `ship_module_state.gd:24,52` |
| `ShipProgressionState.boost_charge_count`, 2–5 | `ship_progression_state.gd:12-59` |
| `EngineBoostModule`: 1500→500 px/s, 0.55 s, 45 dmg, 2 s cooldown, i-frames, sets `engine_boost_active` | `engine_boost_module.gd:5-10,42-69` |
| `ShipModuleBase.try_activate()` is the virtual to extend | `ship_module_base.gd:58` |
| `AssaultPlayer`'s H loop is separate and untouched | `player_fighter.gd:114-124` |
| `boost` → physical Shift (4194325), `use_ability` → H (72) | `project.godot` `[input]` |
| `MissionTrigger._open_menu()` calls `set_physics_process(false)` before pausing | `mission_select_hub.gd:142-158` |
| `test_ship_rotation_single_writer.gd` sweeps `global/ship_modules/*.gd` only | `test_ship_rotation_single_writer.gd:18,30-39` |
| `settings_panel.gd`'s "a second row is a copy of the first" comment | `settings_panel.gd:15` |
| **All ten test files the plan says it will extend exist at the names and paths given** | `tests/{unit,integration}/` |

**Arithmetic — all correct:** `140 → ±140` = 280 px = 38.9% of 720; `90 → ±90` = 180 px = 25%;
`420 × 0.30 − 32 = 94`, capped at 90; dead-zone edge at `32 / 0.30 = 106.7 px/s`; `_motion_scale = 0`
⇒ `lerpf(1.0, …, 0.0) == 1.0` exactly; `blend_speed = 6.0` ⇒ ~0.116 s half-life.

**Godot 4.6 API claims — checked against the local 4.6.3 build and the class reference:**

- `Camera2D.ignore_rotation` exists and **defaults to `true`**. §4.3's verification holds and the
  "camera inherits ship rotation" hypothesis really is dead.
- `Input.set_custom_mouse_cursor(image, shape, hotspot)` accepts an `Image` **directly** (the binding
  is typed `Resource`; the docs name both `Texture2D` and `Image`), `null` resets — but **per
  `CursorShape`**, so `restore()` only needs to null the shapes `apply()` set. It is
  DisplayServer-level state, i.e. genuinely process-global and sticky across `change_scene_to_*`, as
  §6.1 says. Usefully: under the headless DisplayServer the call is a **silent no-op** — I passed a
  deliberately over-size 512×512 image and got no error — so RET-1 applying a cursor from every test
  ship's `_ready()` will not red the suite, and the `AimCursor.is_applied()` seam the plan proposes is
  the only way to observe it. That was the right call.
- `Node2D.skew` exists, is radians in script (degrees in the inspector), shears the Y basis only —
  and propagates to children (see B5).
- `top_level` is a `CanvasItem` property, default `false`, and reinterprets local coords as global
  (see N11).
- `log()` is the natural logarithm; `log(2.0) == 0.693…`, so the plan's
  `1 - exp(-log(2.0) / half_life * delta)` is a correct half-life form, matching
  `ship_turn_controller.gd:82-86`.

**No reinvention.** I swept `global/components/` and `global/systems/`: there is no camera-rig,
reticle or cursor component to reuse. `ArenaCamera` is assault's dead-zone *follow* camera, a
different job, and the plan cites it as precedent rather than duplicating it. `BoostMeter` is
extended, not replaced — which is the right call and is what finding 7 independently supports.

**No convention violations found.** Composition over inheritance (new behaviour as typed child
nodes) ✓; single mouse read preserved and the reticle explicitly fed rather than reading ✓;
single-writer-of-rotation respected, with FLY-1 routed through a sprite transform and a boundary
test for it ✓; signal arity declared for `segments_changed` and `camera_motion_changed` ✓; no
hand-typed `uid://` ✓; no `.tres` stat or 640×360 design-space coordinate is touched, so those
conventions are simply not in scope here ✓.

**Task graph.** The nine ids, their complexities and their `dependsOn` match the plan's build-order
table exactly. The "all nine touch `player_ship.gd`, so they are worked one at a time" serialisation
is safe as stated — the harness works one task per cycle on one branch, so the listed logical deps
are sufficient and no two tasks can collide. The one dependency actually missing is FLY-2 → CAM-2
(B6). Nothing in the chain stalls, and no task looks like three tasks; BST-1 is the only one that is
arguably two (N6).

---

## Summary

Blocking: **B1** (the defining test is vacuous — the rig never sees `rotation`), **B2** (moving the
meter tick does nothing; `_handle_thrust` returns first), **B3** (a tank is spent before the module's
cooldown is checked), **B4** (the hold drains the bar but applies no force), **B5** (skewing
`SpriteAnchor` shears the muzzles and engines), **B6** (the boost shake cannot honour the
accessibility setting, and FLY-2 is missing the CAM-2 dependency), **B7** (finding 9's quotes are not
on the cited pages, contradicting the doc's sourcing note).

B1–B6 are all fixable by editing `3-plan.md` — no re-research and no redesign. B7 is a correction to
`2-research.md`. The four threads, the decomposition, the complexities and the dependency chain are
otherwise sound, and the underlying diagnosis of the camera bug is correct and well-measured. Fix the
seven and this is an approve.

---

# Round 2 — 2026-09-16

VERDICT: APPROVED

Epic: `open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy`. Stage: **PLAN-REVIEW**, round 2
of 2. Re-reviewed: the revised [`3-plan.md`](./3-plan.md) in full (including its
`## Response to review round 1`), [`2-research.md`](./2-research.md) finding 9 and its sourcing note,
[`1-context.md`](./1-context.md), the nine generated tasks, and the source files listed at the
bottom. Round 1's findings were re-derived from the source rather than taken on trust, in both
directions.

All seven blocking findings are fixed in the plan body, not just in the response table, and each fix
is consistent with the build sequence, the test plan and the task bodies. Ten of the twelve notes are
applied; the two that are not are declined with reasons I accept. **No new blocking findings.** Nine
non-blocking notes below — six of them are concrete traps in BST-2/BST-3 that the implementing task
will hit and should be told about up front; none changes a design decision.

## Disposition of round 1

| # | Disposition | Verified at |
|---|---|---|
| B1 | **fixed** — defining case moved to the wiring file; it fails on today's build (`rotation = PI` ⇒ `facing = (0,+1)` ⇒ `offset.y > 0`), and the mirror case makes a stuck sign non-passing | `3-plan.md:619-626, 641-663`; `player_ship.gd:368-384` |
| B2 | **fixed** — and round 1 was **right**. `_handle_thrust()` returns on `engine_boost_active` at `player_ship.gd:219-220`, before its last line `253` calls `_step_boost()`, so the draft's reorder was unreachable. The plan takes round 1's option (b): the tick stays put and the freeze is documented as intended. What is "withdrawn" is the *draft's change*, not the finding. The 0.035-bar-unit figure checks out (0.55 s burst − 0.5 s `recharge_delay_sec` = 0.05 s × `recharge_rate 0.7`) | `3-plan.md:538-571`; `player_ship.gd:219-220,253`; `boost_meter.gd:30,33,63` |
| B3 | **fixed** — `module.can_activate() and meter.try_spend_tank()`. `can_activate()` is specified as exactly `try_activate()`'s own guard negated (`engine_boost_module.gd:43-44`), so within a frame the two cannot disagree and no tank can be lost; the new boundary case covers full-meter/module-cooling | `3-plan.md:479-507, 750-755`; `engine_boost_module.gd:42-44`; `ship_module_base.gd:58-59` |
| B4 | **fixed** — sustain re-asserts `velocity` along the current nose; the tell moves onto `_boosting`; three new cases including the one that fails on the draft. Ordering holds: `_step_boost()` runs last inside `_handle_thrust()`, so the assignment lands after thrust *and* after damping, and `velocity.length() == _speed_ceiling` is not `>`, so the tail clamp does not bite (but see **R2-N1**) | `3-plan.md:396-441, 726-737`; `player_ship.gd:228-253,282-295` |
| B5 | **fixed** — target is `$SpriteAnchor/ShipSprite2D`, which has no children at all in the scene; the muzzles and engine markers are its siblings. Boundary case pins all four | `3-plan.md:278-288, 771-777`; `player_ship.tscn:235-252, 270-275` |
| B6 | **fixed** — `get_motion_scale()` on the rig, `CameraShake.add(trauma * scale)` at the call site, `_motion_scale == 0.0 ⇒ no trauma` case. The declined CAM-2 dependency is **correct**: `_motion_scale` defaults to `1.0`, so FLY-2 shipped before CAM-2 produces exactly today's amplitude (right answer, nothing to regress), and the day CAM-2 lands the accessor reads the live value with no FLY-2 edit. The `backlog-cli.js` limitation is real but is not what carries the argument — the design does | `3-plan.md:135-141, 295-324, 780-784`; `camera_shake.gd:31`; `scripts/backlog-cli.js:344` |
| B7 | **fixed** — finding 9 is now an explicitly marked paraphrase with its retrieval method stated, and the sourcing note carries the correction | `2-research.md:13-19, 51` |
| N1 | fixed (bundling now explicitly rejected, with the "every knob is an `@export`, so a fly-test can revert to pure-sign-fix behaviour" answer) | `3-plan.md:85-97` |
| N2 | fixed — and the scene claim is accurate: `Rows/Row0` with `NameLabel`/`ValueLabel` is a node block in `settings_panel.tscn` | `3-plan.md:170-177`; `settings_panel.tscn:24-40`; `settings_panel.gd:29,36` |
| N3 | fixed (two-layer capture/restore spelled out for CAM-2, RET-1/2 and BST-1) | `3-plan.md:610-617`; `tests/README.md:745-751`; `test_player_ship_turn_wiring.gd:21-31` |
| N4 | fixed (`tests/integration/test_open_space_flight_feel.gd`, new file) | `3-plan.md:759-764` |
| N5 | fixed (`tanks`, with the collision spelled out) | `3-plan.md:359-363`; `test_boost_bar.gd:143` |
| N6 | **declined — reasonably.** Not a required change in round 1; both halves are fully specified and Risk 7 carries the escalation route | `3-plan.md:876-879` |
| N7 | fixed (`const` → `@export`, with an honest account of what it does and does not buy) | `3-plan.md:509-522`; `engine_boost_module.gd:5-10` |
| N8 | fixed (`get_description()` update folded into BST-3; no test pins the string, so nothing else breaks) | `3-plan.md:524-527`; `grep get_description tests/` → no hits |
| N9 | **partially fixed, correctly** — recorded as Risk 8 and raised with the user; filing an epic is genuinely a triage-stage action, not a plan-stage one | `3-plan.md:831-836` |
| N10 | fixed (`player_ship.gd:84-88`, `player_fighter.gd:114-124`, the guidelines phrasing and the Ridge Racer (PSP) attribution are all corrected) — one new slip, see R2-N7 | `3-plan.md:71,536`; `2-research.md:45,49`; `player_fighter.gd:114-124` |
| N11 | fixed (`global_position` reassigned every physics frame, with the bars' precedent and the `Vector2.ZERO` offset) | `3-plan.md:218-224`; `player_ship.gd:148-151` |
| N12 | fixed (Risk 7, with the exact `set-meta` command) | `3-plan.md:823-830` |

## New blocking findings

None.

## Non-blocking notes

**R2-N1 — BST-2: the sustain will fight the ceiling-decay branch after 0.35 s, and the plan's own
±1 px/s case is what catches it.** The new sustain sets `_speed_ceiling = boost_exit_speed` and
writes `velocity`, but the existing block below it (`player_ship.gd:282-295`) still runs: once
`_boost_hold_left` reaches 0 mid-hold, the `else` branch decays the ceiling by
`boost_ceiling_decay * delta` and the tail clamp trims `velocity` to `700 - 400*delta` — 693.3 px/s
at 60 Hz, 686.7 at 30 Hz, i.e. frame-rate dependent. That fails
`3-plan.md:728-730` ("`boost_exit_speed` ± 1 px/s"), which is the right outcome. The fix is one
condition — gate the decay `else` on `not _boosting` (or set the ceiling after the decay block).
**Do not fix it by loosening the tolerance**, which would ship a frame-rate-dependent sustain speed.

**R2-N2 — BST-2 must also own `tests/integration/test_open_space_boost_wiring.gd`, which the test
plan never names.** `_step_boost(` has **37 call sites across two files**, and the plan lists only
`test_open_space_boost_verb.gd`. The arity change reds all of them at runtime (GDScript resolves the
call at call time, so this is a red suite, not a parse error), and
`test_open_space_boost_wiring.gd:120-129` asserts *"a Shift boost must spend exactly one charge"* —
which BST-2 deliberately invalidates (a tap now costs `drain_rate * boost_hold_sec` = 0.35). That
rewrite is legitimate characterization churn, but it belongs in the task's scope up front rather
than as a surprise at gate time.

**R2-N3 — BST-1: "`try_spend_tank()` … replacing `try_spend()`" is the one ambiguity left in thread
4, and the wrong reading is a live regression.** At the default `tanks = 1`, `tank_size()` is
`max_charges / 1` — the *whole bar* — so repointing `player_ship.gd:276` at `try_spend_tank()` in
BST-1 makes one Shift tap drain everything, and `tests/unit/test_boost_meter.gd` carries 12
`try_spend()` call sites that would have to be rewritten to match. BST-1 should **add**
`try_spend_tank()` and leave `try_spend()` and its cases alone; retiring it belongs to BST-2/BST-3,
which are the tasks that remove its last caller. (`test_open_space_boost_wiring.gd:128` catches the
wrong reading, so this is loud rather than silent — but it is a session's worth of noise.)

**R2-N4 — BST-3: activating the module from inside `_step_boost()` puts it in front of the tail
speed clamp for one frame.** Today `EngineBoostModule.try_activate()` runs from `_input`, *before*
`_physics_process`, so `_handle_thrust()`'s `engine_boost_active` return (`player_ship.gd:219-220`)
shields the 1500 px/s frame-one burst. Moved onto Shift, activation happens *inside* `_step_boost()`,
and execution then falls through to `player_ship.gd:294-295` with `_speed_ceiling` still at
`max_speed = 420` — clipping the burst to 420 for exactly one frame until `tick()` re-asserts it.
Cheapest fix: `return` immediately after a successful `module.try_activate()` (the module has already
set `engine_boost_active`, so the return is the same rule the function already opens with).

**R2-N5 — BST-2: the release frame drops the sprite but not the thrusters.**
`_release_boost_flame()` (`player_ship.gd:314-317`) only touches the `AnimatedSprite2D`; thruster
state is recomputed in `_handle_thrust()`, which runs *before* `_step_boost()`. So on the first
released frame `_boosting` is still true when the thrusters are set, and only the sprite drops —
the plan's case *"one released frame drops both"* (`3-plan.md:735-737`) fails as written. Give the
stop branch a counterpart to `_play_boost_flame()` that also sets both thrusters, rather than
weakening the case to two frames.

**R2-N6 — RET-2: name who hides the ring under the mission menu.** The plan says the reticle is
hidden while the ship's physics is off (`3-plan.md:246-248, 698`), but the ship is precisely what
`MissionTrigger._open_menu()` freezes (`mission_select_hub.gd`), so it cannot hide anything at that
moment — the reticle needs its own `_process` poll of the parent's `is_physics_processing()`, or the
hide has to move into the mission trigger. As specified there is no implementation that satisfies the
test; one sentence fixes it.

**R2-N7 — three citation slips, none load-bearing.** `player_ship.gd:380-381` for
`facing * _LEAD_MAX * t` is actually `382-383` (`380-381` is the comment and the zoom line);
`test_boost_bar.gd:142` is the section comment, the function is at `143`; `settings_panel.tscn`'s
Row0 block runs to line `40`, not `35`. Everything else I spot-checked was exact.

**R2-N8 — `CameraDirector` still has no test, and the plan neither schedules one nor declines it.**
`1-context.md:268-270` called it *"worth one file regardless of which camera design wins"*; grep
confirms zero references to `CameraDirector`, `speed_feel` or `_update_camera_feel` anywhere under
`tests/`. CAM-1's wiring test exercises it incidentally (it reads the pushed effect), which is
probably enough for this epic — but it should be an explicit line in Out of scope rather than a
silent drop.

**R2-N9 — two things only a human can close, and both are already flagged.** (a) Idea point 4's
*"make it more powerful"* is still answered by relabelling plus the `@export` conversion, with no
numeric buff — and Boost Drive now *costs* a tank it previously did not, so the first fly-test should
ask the player directly whether it reads as stronger; the knobs now exist to answer "no" cheaply.
(b) FLY-1's skew moves `ShipSprite2D` only, which is correct for B5 — but `_thruster` /
`_thruster_right` are parented to `EngineLeft`/`EngineRight` (`player_ship.gd:136-141`), *siblings*
of the sprite, so the exhaust will not lean with the hull. At `bank_max_rad = 0.12` that is probably
invisible; it is one more thing for the mandatory eyes-on check the plan already requires.

## What I verified

Opened and read in full or in the cited ranges, not taken from the plan or from round 1 on trust:

- `open_space/scenes/entities/player/player_ship.gd` (whole file — control flow of
  `_physics_process` → `_handle_thrust` → `_step_boost`, both `engine_boost_active` returns, the
  ceiling/clamp tail, the flame pair, `_update_camera_feel`)
- `open_space/scenes/entities/player/boost_meter.gd`, `open_space/scenes/gui/boost_bar.gd`,
  `open_space/scenes/entities/player/ship_turn_controller.gd`
- `open_space/scenes/entities/player/player_ship.tscn` (SpriteAnchor subtree, `weapon_muzzles`,
  `ShipTurnController`/`BoostMeter` children), `open_space/scenes/levels/sector_hub.tscn:83-85`
- `global/ship_modules/ship_module_base.gd`, `global/ship_modules/engine_boost_module.gd`
- `global/systems/camera_director.gd`, `global/systems/camera_shake.gd`
- `global/autoloads/settings_state.gd`, `global/ui/pause_menu/settings_panel.gd` + `.tscn`
- `assault/scenes/player/player_fighter.gd:108-124`
- `tests/integration/test_open_space_boost_verb.gd` (header + module-precedence cases),
  `tests/integration/test_open_space_boost_wiring.gd:110-148`,
  `tests/integration/test_boost_bar.gd:135-160`,
  `tests/integration/test_player_ship_turn_wiring.gd:15-40`, `tests/README.md:740-751`
- `grep` sweeps: `try_spend` (14 hits, 12 of them in `tests/unit/test_boost_meter.gd`),
  `_step_boost(` in `tests/` (37 hits across 2 files), `get_description`/`supercharge engines` in
  `tests/` (0 hits), `CameraDirector`/`speed_feel`/`_LEAD_MAX` in `tests/` (0 hits)
- `./scripts/backlog-cli.js epic show …` — the nine tasks' ids, complexities and `dependsOn` still
  match the plan's build-order table exactly, including FLY-2 → `[BST-2, CAM-1]`.

**Conventions.** Re-checked against `CLAUDE.md`: composition over inheritance (rig, reticle and
meter are typed child nodes resolved by class) ✓; the one-mouse-read rule (the reticle is fed the
same injected `Vector2`) ✓; single-writer-of-`rotation` (banking is a sprite skew, with its own
boundary case, and nothing in thread 4 writes `rotation`) ✓; signal arity declared for
`tanks_changed` / `camera_motion_changed` ✓; no hand-typed `uid://` ✓; no `.tres` stat and no
640×360 design-space coordinate is in scope ✓; projectile ownership untouched ✓. No reinvention: the
sweep of `global/components/` and `global/systems/` still shows no camera-rig, cursor or reticle
component, `BoostMeter` is extended rather than replaced, and `CameraShake`/`CameraDirector` are
used through their existing APIs.

**Complexity and graph.** Every assignment still reads correctly. BST-3 remains the only
cross-cutting task and is the one with four of the nine notes above against it; it is still
defensibly `medium` (two three-line virtuals, a two-line tier switch, a mechanical `const` → `@export`
pass), and Risk 7 records the exact escalation command if it opens up. No task is really three, no
chain stalls, and the serialisation argument (one task per cycle on one branch) still holds.
