# Open-space movement feel, pass 2 — implementation plan

Epic: `open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy`. Stage: **PLAN**, 2026-09-15.

Built on [`1-context.md`](./1-context.md) (the codebase, and the *measured* diagnosis of the camera
bug) and [`2-research.md`](./2-research.md) (how shipped games solve these four problems). Neither is
re-derived here; every "finding N" reference below points at `2-research.md` and every "§N" at
`1-context.md`.

---

## Problem

The player flew the two shipped movement epics and reported four things. In their words, and what
each actually is:

1. **"Add target icon or something like that instead of the mouse cursor."** Open space is aimed
   with the mouse, and the player flies with the bare OS arrow (§4.6). The arrow says nothing about
   the three states `ShipTurnController` already tracks — inside the 48 px dead zone, honouring an
   AI-Targeting snap, steering frozen on focus loss — and nothing about the deliberate lag between
   where the cursor is and where the nose is going.

2. **"It moves camera in the wrong direction… like it is behind the ship… rotating it at high speed
   makes me sick… take a look why it mixes up and down."** Diagnosed in §4.1: the camera lead takes
   its *magnitude* from `velocity` and its *direction* from the hull's facing. Turn the nose away
   from your momentum and the camera extends **opposite to travel** — the ship runs off the top of
   the frame while the camera pushes down. There is no axis bug and no up/down mix-up; the sign is
   simply read off the wrong vector. The nausea is the second half: a 180° turn takes a flat 1.20 s
   and swings the lead target 280 px, **39% of the 720 px viewport**, at ~233 px/s of pure camera
   motion the ship is not making (§4.2). Finding 3 names this as an accessibility barrier, not a
   taste complaint. §4.3 kills the other hypothesis from triage: the camera does **not** inherit the
   ship's rotation (`Camera2D.ignore_rotation` defaults true, verified against the engine).

3. **"In general movement is not very fun… I want it to be more responding and dynamic."** Today the
   ship accelerates, coasts on a 1.16 s-half-life damping tail, and turns. Nothing on screen reacts
   to *how hard* you are flying: the hull is a rigid sprite at a rigid angle, and a boost looks
   identical to cruising apart from a flame.

4. **"Boosting is not what I imagined… without boost module we must have 'hold to boost'… one long
   charging line that is upgradable… can be split to 3-4 parts for boost drive module… this default
   charge must have a 180 degrees speed boost."** Today Shift is a one-shot redirect costing one
   whole pip (§4.5); Boost Drive is a *different verb on a different key* (H) with no charge cost at
   all. The 180° flip the player wants already works — it is the unconditional nose-direction
   redirect — but there is no hold, no long bar, and the two tiers are unrelated systems.

### What should change

- The cursor becomes a crosshair, and the ship wears a ring that shows what the aim is actually
  doing.
- The camera leads **where the ship is going**, by a bounded amount, and stops moving when the ship
  effectively stops. The whole automatic-motion layer can be turned down or off from the pause menu.
- The hull leans into its turns and the screen reacts to a boost, so speed is legible.
- Shift is **one verb with two tiers**: hold it to burn a continuous bar that upgrades by getting
  longer; equip Boost Drive and the same bar becomes 3–4 tanks, each spent on a far stronger burst.
  Either tier redirects momentum to the nose on frame one, so "spin 180°, hold Shift, leave the
  other way" is the same button in both.

---

## Design

Four threads, nine tasks. They share `player_ship.gd` and `player_ship.tscn` (§5) but are otherwise
independent; the sequencing below is the build order, not a dependency web.

### Thread 2 — the camera (tasks CAM-1, CAM-2)

**`OpenSpaceCameraRig`, a new `Node` child of `player_ship.tscn`.** The speed-zoom and lead
computation moves out of `player_ship.gd::_update_camera_feel()` into a node with `@export`s and a
pure `step()`, resolved **by type** in `_ready()` exactly like `_turn` and `_boost_meter`
(`player_ship.gd:96-108`). `_update_camera_feel()` keeps its job — find the `Camera2D`, find the
`CameraDirector`, push one `speed_feel` effect at priority 0 — and nothing else.

Why a node and not three edited lines in place: `_update_camera_feel()` early-returns whenever there
is no `Camera2D`, and the camera lives in `sector_hub.tscn`, not in the ship scene (§1). **Every
headless test that instantiates `player_ship.tscn` alone takes that early return**, so today the
formula is completely unreachable by the gate. A rig node with a pure step is the same shape that
made `ShipTurnController` testable at all, and it is the only way the boundary case that defines
this epic — *lead while facing is 180° from velocity* — can be written as a test that fails on
today's build.

Rejected: putting it inside `CameraDirector`. The director is shared with `MissionTrigger`'s
priority-10 `planet_dwell` effect and is side-stepped by the pause menu's tween; changing *what
`speed_feel` pushes* affects neither, changing the director's contract affects both (§5).

The formula, replacing `facing * _LEAD_MAX * t`:

```gdscript
## OpenSpaceCameraRig
@export var lookahead_time: float      = 0.30   ## seconds of travel to lead by
@export var lead_max_px: float         = 90.0   ## hard cap on the lead
@export var lead_dead_zone_px: float   = 32.0   ## raw lead under this reads as zero
@export var lead_half_life: float      = 0.20   ## smoothing on the lead vector
@export var zoom_min: float            = 0.85
@export var zoom_speed_threshold: float = 400.0
@export var boost_zoom_bonus: float    = 0.06   ## extra pull-back while boosting (FLY-2)

var _lead: Vector2 = Vector2.ZERO    ## the smoothed, applied lead
var _motion_scale: float = 1.0       ## 1.0 / 0.5 / 0.0, from SettingsState (CAM-2)
var _boosting: bool = false

func step(velocity: Vector2, delta: float) -> void:
    var raw: Vector2 = velocity * lookahead_time
    var mag: float = raw.length()
    ## Subtract the dead zone rather than clipping below it: clipping makes the lead
    ## POP from 0 to 32 px the instant the ship crosses the threshold.
    if mag <= lead_dead_zone_px:
        raw = Vector2.ZERO
    else:
        raw = raw.normalized() * minf(mag - lead_dead_zone_px, lead_max_px)
    var k: float = 1.0 - exp(-log(2.0) / maxf(lead_half_life, 0.0001) * delta)
    _lead = _lead.lerp(raw, k)

func get_offset() -> Vector2:
    return _lead * _motion_scale

func get_zoom(velocity: Vector2) -> Vector2:
    var t: float = clampf(velocity.length() / zoom_speed_threshold, 0.0, 1.0)
    var target: float = zoom_min - (boost_zoom_bonus if _boosting else 0.0)
    return Vector2.ONE * lerpf(1.0, lerpf(1.0, target, t), _motion_scale)
```

Four properties this buys, each with a source:

- **Direction from `velocity`, not `facing`** (findings 1 and 2). This *is* the bug fix. The player
  proposed "extend it only when the ship is rotated to that direction of the mouse"; findings 1 and
  2 say the condition belongs on *actually moving that way*, which is the same instinct expressed in
  the variable the physics honours. Say so to the player rather than silently substituting.
- **Cap down from 140 px to 90 px** — worst-case swing 180 px, 25% of viewport height instead of
  39% (finding 3, and the judgement call recorded in `2-research.md`'s numbers table). Note that a
  velocity lead cannot swing 180 px on a *turn* any more anyway: velocity changes on the 1.16 s
  damping half-life, not on the 1.20 s rotation. The cap is belt-and-braces.
- **A radial dead zone** (finding 2, Fez; radial per finding 6; matching `ArenaCamera`'s shipped
  `deadzone_half_size = (40, 30)`). This is the direct answer to *"when ship stays in place, it
  moves camera"*: §4.4 measures a 10-second coast tail during which the ship never actually reaches
  zero, so a velocity lead would otherwise hold a small permanent offset forever.
- **Lookahead smoothing separate from the director's blend** (finding 1: Cinemachine ships Lookahead
  Smoothing as its own dial, distinct from Damping). `CameraDirector.blend_speed` stays at **6.0** —
  §4.2 measures it at a 0.116 s half-life, which is responsive; lowering it adds lag without
  removing the swing, so the triage note's "blends at only 6/s" diagnosis is wrong and this plan
  does not act on it.

**CAM-2 — the accessibility setting.** Finding 3 quotes a player: *"Games that have two types of
movement going on at once… make me sick every single time"*, classifies it *Vision / Intermediate*,
and prescribes a **toggle**, not removal. A new `SettingsState` key `camera_motion` with values
`&"full"` / `&"reduced"` / `&"off"` → `_motion_scale` of `1.0` / `0.5` / `0.0`, a `camera_motion_changed`
signal, and a second row in `settings_panel.gd` (whose header comment already says "a second row is
a copy of the first: another entry in `_rows` and another branch in `cycle()`").

One trap: `SettingsState._save()` today writes exactly one key and would clobber the other. It must
write both. The scheme key stays in `SECTION = "controls"`; the camera key goes in a new
`SECTION_CAMERA = "camera"`, and an unreadable or unknown value falls back to `&"full"` the same way
the scheme does.

`_motion_scale` deliberately scales the **zoom as well as the lead** — finding 3 reads on speed-zoom
too, and `off` should mean off.

### Thread 1 — the reticle (tasks RET-1, RET-2)

Finding 4 is Godot's own documentation: a software cursor "will add **at least one frame of latency**
compared to a hardware mouse cursor", and `Input.set_custom_mouse_cursor()` is "recommended… whenever
possible". Findings 2 and 6 say the *state* — dead zone, snap, the lag between the target angle and
the hull — is information about the **ship**, and belongs drawn at the ship. So this is a split, not
a choice, exactly as `2-research.md`'s "what the findings imply" §4 concludes.

**RET-1 — the aim point is a hardware crosshair.** A new `global/systems/aim_cursor.gd`
(`class_name AimCursor`, `RefCounted` or a static-only script) with one pure function
`build_image(size: int, color: Color) -> Image` that draws a 32×32 crosshair — four ticks and a
centre gap, no filled middle so the thing under the cursor stays visible — plus `apply()` /
`restore()` that wrap `Input.set_custom_mouse_cursor()`.

Generated procedurally, not with PixelLab: it costs no monthly allowance, it is a UI asset rather
than a world entity so the top-down-orthographic rule does not apply, and a `_draw()`-or-`Image`
approach sidesteps `test_entity_sprite_transparency.gd` entirely (§3). 32×32 is well inside finding
4's "128×128 or smaller are recommended".

`Input.set_custom_mouse_cursor()` is **process-global and sticky** (§6.1): set it in the hub and the
crosshair follows the player into assault, infiltration and the boot menu. The owner is
`OpenSpacePlayerShip`, and the pair is exactly symmetric — `apply()` from `_ready()`, `restore()`
from `_exit_tree()`. `_exit_tree()` covers every exit path there is: mission launch, the death
`reload_current_scene()`, and quit. Under the `&"keys"` scheme there is no cursor steering, so the
crosshair is not applied and the OS arrow stays (§6, and `SettingsState.open_space_scheme_changed`
is already connected in `_ready()`).

**RET-2 — the ship wears an aim ring.** A new `AimReticle extends Node2D`, `top_level`, child of
`player_ship.tscn`, drawn with `_draw()` primitives in the same idiom as `BoostBar` and
`OverheatBar`. It draws, centred on the ship:

- the **dead-zone ring** at `ShipTurnController.mouse_dead_zone_px` — *read from the controller, never
  duplicated as a constant* (`2-research.md` numbers table);
- a **tick on the ring at the turn controller's `_target_angle`**, which is where the nose is going,
  and a second at the hull's actual `rotation`. The gap between them is the inertial lag the turn
  epic deliberately built, made visible — finding 6's "two values, interpolate between them" pattern,
  which that source says the crosshair should mirror rather than snapping;
- **state by colour**: normal, `_snap_held` (an AI-Targeting snap is being honoured — finding 6 is
  explicit that assists should be *visible*, because invisible auto-aim "created problematic gaps
  between input and display"), and `_steering_enabled == false` (window unfocused).

It is **fed** its inputs, never reading the mouse: `player_ship.gd::_handle_rotation` already holds
the one `get_global_mouse_position()` call project-wide (§3) and passes the cursor to
`_turn.set_aim_target()`; it passes the same `Vector2` to `_reticle.set_aim(...)` on the next line.
A reticle that read the mouse itself would be the second read project-wide and untestable headlessly.

`ShipTurnController` grows two read-only accessors — `is_snap_held()` and `is_steering_enabled()` —
beside the existing `get_target_angle()`. No behaviour change.

Hidden when: the `&"keys"` scheme is active, or the ship's physics is off (`MissionTrigger._open_menu()`
calls `set_physics_process(false)` before pausing the tree — §6.5), so the ring is not left
mid-swing under the mission menu.

### Thread 3 — dynamic flight (tasks FLY-1, FLY-2)

**The research's answer to "movement is not very fun" is thread 4, not new default verbs.** Findings
5 (Nova Drift) and 10 (Space Pirates and Zombies 2) are two shipped top-down games that deliberately
withheld strafe and reverse thrust *to protect the meaning of facing* — and this project's entire
open-space verb set (mouse aim, nose-direction boost, the 180° flip) rests on facing. Finding 10
names the replacement outright: when you refuse strafe, **the boost becomes the dodge**. So strafe
and stabilisation belong in `SLOT_MODULES[&"engines"]` as content, not in the default ship, and they
are out of scope here (see Out of scope).

What this thread ships instead is *legibility*: two bounded, numbered mechanics that make the ship
read as reacting to what the player does.

**FLY-1 — the hull banks into its turns.** `SpriteAnchor.skew`, driven from the per-frame rotation
delta, smoothed, clamped to a small angle:

```gdscript
@export var bank_max_rad: float = 0.12       ## ~7°, the visual limit
@export var bank_rate_ref_deg: float = 150.0 ## turn rate that reaches full bank
@export var bank_half_life: float = 0.12
```

`_step_bank(rotation_delta, delta) -> float` is a pure method on the ship returning the new skew,
assigned to `$SpriteAnchor.skew`. **It must be a sprite transform, never a hull rotation** —
`tests/integration/test_ship_rotation_single_writer.gd` makes `ShipTurnController` the only writer
of `OpenSpacePlayerShip.rotation` (§3), and `SpriteAnchor` is the node the project already uses to
separate visuals from the body.

Skew rather than a banked sprite frame because banked frames mean PixelLab and the capped monthly
allowance. **This is the one thing in the epic a human has to look at before it can be called done**
— a shear on a top-down hull either reads as a lean or reads as a glitch, and no headless test can
tell the difference. If it reads badly, the export goes to `0.0` and banked frames become a
follow-up; that is a one-value revert, which is why this is the cheap version to try first.

**FLY-2 — a boost you can see.** Two channels that already exist, wired to the boost state:
`CameraShake.add(0.25)` on the boost's start frame (between the existing `0.35` on a hit and
nothing), and `rig.set_boosting(true)` for the duration, which pulls the zoom a further
`boost_zoom_bonus = 0.06` out — the cheap, one-call version of finding 7's shipped "tunnel vision"
effect, and both scaled by `_motion_scale` so the accessibility setting still governs them.

Rejected: a *directional* kick. Finding 2 notes Celeste wobbles the camera in the direction of the
dash, but `CameraShake` has only a scalar trauma model; adding a direction channel is a change to a
tested shared autoload for a flourish. Recorded in `2-research.md` as "a possible small extension,
not assumed", and left there.

### Thread 4 — one gauge, two tiers (tasks BST-1, BST-2, BST-3)

Finding 7 is the decisive one: Ridge Racer 7 ships **this exact proposal** as two interchangeable
configurations of one gauge. Standard nitrous is three discrete tanks; **Flex Nitrous is "one long
gauge that requires the nitrous button to be held"**; Extended Type re-partitions *the same pool*
into two larger tanks; Quad adds a tank. Tanks and the long bar are the same resource rendered and
spent differently. §1 records that `BoostMeter.charges` is **already a continuous float** with a
whole-unit `try_spend()` layered on top — so this is the smaller change as well as the
better-precedented one.

**BST-1 — the meter and the bar learn about partitions.**

`BoostMeter` gains:

```gdscript
signal segments_changed(segments: int)      ## declared with its parameter; the arity sweep checks this

@export var drain_rate: float = 1.0         ## bar-units per second, continuous tier
@export var min_start_charge: float = 0.25  ## below this a boost refuses to start

var segments: int = 1                       ## 1 = one long bar; N = N tanks

func set_segments(n: int) -> void            ## clamps >= 1, emits
func segment_size() -> float                 ## float(max_charges) / float(segments)
func drain(amount: float) -> bool            ## continuous spend; false when it hits empty
func try_spend_segment() -> bool             ## whole-tank spend, replacing try_spend()
```

`drain()` and `try_spend_segment()` both set `_delay_left = recharge_delay_sec`, so the existing
post-spend regen pause covers both tiers unchanged. `bind_progression`, `_on_progression_changed`
and the hand-driven `step(delta)` are untouched.

**No save migration.** `ShipProgressionState.boost_charge_count` keeps its 2–5 range and its
`+1 boost` pickup; only the *meaning* changes from "pips" to "bar units" (§5), and every value
already on disk is legal. Stating this is the task's job; assuming it is how a save gets broken.

`BoostBar` changes from "`max_charges` pips of fixed total width" to:

- **width proportional to capacity** — `_UNIT_WIDTH = 16.0`, so 2 units is today's 32 px and 5 units
  is 80 px. Finding 9 (Breath of the Wild's stamina wheel) is the reason: an upgrade has to be a
  *visible* increment, and a bar that silently re-slices a fixed 32 px into more, thinner pieces
  reads as a **downgrade**. "One long charging line that is upgradable" means it gets longer.
- **`segments` tanks**, split evenly across that width with the existing 1 px gap. `segments == 1`
  is one long bar — the default tier, no special case.
- **faint unit ticks at every whole bar-unit boundary**, drawn in both tiers. Finding 9 again: the
  continuous gauge only communicates its upgrade if the increment is a visible fraction.
- **a per-tier fill colour** — the existing cyan for the continuous tier, a warmer colour for the
  Boost Drive tier. Finding 7 ships per-tier nitrous colours for exactly this reason.

The `setup()` seed-then-connect pattern stays verbatim; it now seeds `segments` as well and connects
`segments_changed` alongside `charges_changed`.

**BST-2 — hold Shift to boost (default tier).** `_step_boost()` extends from
`(boost_pressed, delta)` to `(boost_pressed, boost_held, delta)`, keeping the injected-input shape
that makes it testable at all (§3 — `Input.is_action_pressed()` can never return true in the gate).
`_handle_thrust()`'s one `Input` read becomes two:
`_step_boost(Input.is_action_just_pressed("boost"), Input.is_action_pressed("boost"), delta)`.
No new input action: §1 records `boost` is already bound to physical Shift.

```
start   (pressed, not already boosting, _boost_hold_left <= 0.0, charges >= min_start_charge):
        velocity = Vector2.UP.rotated(rotation) * boost_exit_speed   ## 700, frame one, unchanged
        _speed_ceiling = boost_exit_speed
        _boosting = true
        _boost_hold_left = boost_hold_sec                            ## 0.35, now the MINIMUM burn
        flame on

sustain (_boosting):  meter.drain(drain_rate * delta); _speed_ceiling = boost_exit_speed

stop    (not held and _boost_hold_left <= 0.0)  or  meter empty:
        _boosting = false; flame off; ceiling decays at boost_ceiling_decay as today
```

**No ramp, no spin-up.** Finding 8 is a shipped game that nerfed exactly this verb by requiring the
button be held "for a second for the speed boost to kick in" and made it "nearly hard to
strategize". The hold **sustains**; it never **builds**. That is also what keeps the 180° flip
intact: the redirect is a single frame-one assignment, and a ramp would destroy it.

**The flip stays unconditional.** `2-research.md`'s numbers table offers a ">120° between velocity
and facing" threshold and labels it a judgement call with no source; the boost epic's own finding 1
(ULTRAKILL) uses no threshold at all, and an unconditional redirect already satisfies the player's
ask — *"when we rotate 180 degrees and press and hold shift, we quickly start moving to other
direction"* — with fewer moving parts and nothing to mistune. **Rejected: the threshold.**

`_boost_hold_left` keeps both of its existing jobs and gains a third: it is the cyan-flame window,
the anti-mash retrigger floor, and now the minimum burn, so a tap still buys the full flip plus
0.35 s of thrust for 0.35 bar-units. At the default capacity of 2 units that is ~5 taps or 2.0 s of
continuous hold; both numbers are `@export`s and both are fly-test material, not gate material.

§6.6 — **Shift held while the mission menu opens**. `MissionTrigger._open_menu()` calls
`set_physics_process(false)` on the ship, so `_step_boost()` stops being called and the meter (which
has no clock of its own) freezes with it. The bar cannot drain behind the menu. On close, physics
resumes with `boost_pressed == false` — a held key produces no `just_pressed` — so a boost cannot
auto-resume. This falls out of the existing design; the task's job is a test that pins it.

**BST-3 — Boost Drive re-partitions the bar and moves onto Shift.**

`OpenSpacePlayerShip` already connects `ShipModuleState.module_equipped` / `module_unequipped` and
applies whatever is equipped in `_ready()` (§1), so the tier switch needs **no new state**:

```gdscript
var drive := ShipModuleState.get_equipped(&"engines") == &"engine_boost"
_boost_meter.set_segments(3 if not drive else (4 if at_max_capacity else 3))
```

— 3 tanks normally, 4 at full `boost_charge_count`, per the player's "3-4 parts depending on the
amount of upgrades" and finding 7's Standard-3 / Quad-4. Without the module, `segments = 1`.

With the module equipped, `_step_boost()`'s press branch becomes: `if meter.try_spend_segment(): module.try_activate(self)`.
The module keeps its 1500→500 px/s burst, its full i-frames and its 45 contact damage — that is the
"make it more powerful" half of the ask, and it is now *paid for* with a tank instead of being free.
Its internal 2 s cooldown stays as a floor; the meter is the resource gate.

**The H key stays generic, and Boost Drive opts out of it.** `player_ship.gd::_input` loops the whole
module pool on `use_ability` (H) — every other active module needs that, so H cannot simply be
retired. Leaving it would also make Boost Drive fireable **for free** on H while Shift charges a
tank. The fix follows the project's established duck-typed precedent (`Bullet.is_armored()`,
`face_instant()`): `ShipModuleBase` grows a virtual `is_open_space_boost_verb() -> bool` returning
`false`, `EngineBoostModule` overrides it `true`, and `OpenSpacePlayerShip._input` skips modules that
report it. `AssaultPlayer`'s own H loop (`player_fighter.gd:116`) is untouched, so Boost Drive still
works on H in assault, where there is no Shift boost to conflict with.

§6.8 — **who owns `velocity`**. `EngineBoostModule` sets `engine_boost_active`, and `_step_boost()`
early-returns on it, so exactly one of the two writes velocity at a time. That early return is
documented in `player_ship.gd` as deliberately redundant with `_handle_thrust()`'s and is not to be
removed. One change is needed: `_boost_meter.step(delta)` moves **above** it, so the pool refills
during the module's 0.55 s burst instead of stalling. The existing module-precedence cases in
`test_open_space_boost_verb.gd` assert on `velocity`, not on charges, and should stay green — the
task must confirm that rather than assume it.

---

## Build sequence

Each step is one session, independently testable, and leaves the game playable. All nine touch
`player_ship.gd`, so they are worked one at a time (§5); only the dependencies listed are *logical*.

| # | Task id | Ships | Complexity | Depends on |
|---|---|---|---|---|
| CAM-1 | `the-camera-leads-where-the-ship-is-actually-travelling-not-w` | `OpenSpaceCameraRig` + the corrected formula, dead zone, cap, smoothing | medium | — |
| CAM-2 | `players-who-get-motion-sick-can-turn-the-camera-s-automatic-` | `SettingsState.camera_motion`, `settings_panel.gd` row | small | CAM-1 |
| RET-1 | `flying-the-hub-shows-a-crosshair-instead-of-the-desktop-arro` | `AimCursor`, apply/restore on the ship | medium | — |
| RET-2 | `a-ring-around-the-ship-shows-where-the-nose-is-actually-head` | `AimReticle`, two `ShipTurnController` accessors | medium | — |
| BST-1 | `the-boost-meter-is-one-long-line-that-gets-longer-with-every` | `BoostMeter.drain/segments`, `BoostBar` rework | medium | — |
| BST-2 | `holding-shift-burns-the-bar-for-sustained-speed-a-tap-still-` | `_step_boost(pressed, held, delta)` | medium | BST-1 |
| BST-3 | `equipping-boost-drive-splits-the-bar-into-3-4-tanks-each-spe` | tier switch, `is_open_space_boost_verb()` | medium | BST-2 |
| FLY-1 | `the-hull-leans-into-its-turns-instead-of-pivoting-like-a-rig` | `_step_bank()` → `SpriteAnchor.skew` | small | — |
| FLY-2 | `boosting-punches-the-camera-so-speed-reads-at-a-glance` | `CameraShake.add`, `rig.set_boosting()` | small | CAM-1, BST-2 |

**On the complexities.** Every task here is `medium` or `small`, which routes them to the Direct
track on sonnet — *because this plan is the thinking they would otherwise each have to pay for
again*. Each names its files, its exports with starting values, its algorithm, and the specific test
cases including the boundary. None of them is architectural: CAM-1 and RET-2 add a child node in a
shape the codebase already ships twice (`ShipTurnController`, `BoostMeter`), and BST-1..3 extend one
component and one script. If any turns out to need structural change once opened, the correct move
is `set-meta <taskId> --complexity large --model opus`, not pushing through — Risk 5 below is the
one most likely to trigger that.

---

## Test plan

The gate's reach here is lopsided and the plan says so rather than promising coverage it cannot
deliver (§7). Every pure step function is fully testable; **no test can say whether any of this
feels good**, which is why every tuning number in this plan is an `@export`.

All new tests use `tests/helpers/save_sandbox.gd` wherever `ShipProgressionState` or `SettingsState`
is touched, plus the in-memory two-layer discipline `test_open_space_boost_wiring.gd:38-53`
established — the sandbox covers the `user://` file only, and the autoloads never re-read it after
boot. Every wiring test finds its node **by class**, never by path, following
`test_player_ship_turn_wiring.gd`.

### `tests/unit/test_open_space_camera_rig.gd` (CAM-1) — new code, asserts intent

- **The epic's defining case:** velocity `(0, -400)` (travelling up) with `rotation = PI` (nose
  down) leads **up**. `get_offset().y < 0`. *This fails on today's build*, where the lead is
  `facing * mag` and points down — it is the whole reported bug in one assertion.
- Lead magnitude at cruise: 420 px/s → `420*0.30 - 32 = 94` → capped at `lead_max_px = 90`.
- **Boundary — the dead zone:** velocity of 1 px/s (the §4.4 ten-second coast tail) leads exactly
  `Vector2.ZERO` after settling, and zero velocity leads zero.
- **Boundary — no pop at the dead-zone edge:** stepping from just under to just over
  `lead_dead_zone_px / lookahead_time` moves the raw lead by ≪ `lead_dead_zone_px`, proving the
  subtract-don't-clip choice.
- Frame-rate independence: 60 steps of `1/60` and 6 steps of `1/6` settle to within 1 px.
- `_motion_scale = 0.0` ⇒ offset exactly zero **and** zoom exactly `Vector2.ONE` at any speed.
- `set_boosting(true)` lowers the zoom target (FLY-2's assertion, written with that task).

### `tests/integration/test_open_space_camera_wiring.gd` (CAM-1) — anti-inert

Every case above is green on a build where `OpenSpaceCameraRig` exists as a script but was never
added to `player_ship.tscn`. This file is the one that fails on it: the rig is found **by class** as
a direct child of an instantiated `player_ship.tscn`, and a ship placed under a `Camera2D` +
`CameraDirector` harness (the `sector_hub.tscn` shape) is driven one physics frame and asserted to
have pushed a `speed_feel` effect whose offset equals `rig.get_offset()`.

### `tests/unit/test_settings_state.gd` (CAM-2) — extend the existing file

- `camera_motion` round-trips through `_save()`/`_load()` **without clobbering
  `open_space_scheme`**, and vice versa. This is the boundary case: it fails on the obvious
  one-key `_save()` implementation.
- An unknown value on disk falls back to `&"full"` with a warning, matching the scheme's behaviour.
- Setting the same value twice emits once.
- `tests/integration/test_pause_menu_settings.gd` gains: two rows exist; `navigate(1)` reaches the
  camera row; `cycle(1)` walks `full → reduced → off → full`; the ship's rig `_motion_scale`
  follows a live change via the signal.

### `tests/unit/test_aim_cursor.gd` (RET-1)

- `build_image(32, color)` returns a 32×32 `Image` with a transparent centre pixel (the thing under
  the cursor stays visible) and opaque pixels on all four ticks.
- **Boundary:** `apply()` then `restore()` leaves the cursor back at the engine default, and
  `restore()` without a prior `apply()` is a safe no-op.
- `tests/integration/test_open_space_aim_cursor.gd`: instantiating `player_ship.tscn` under the
  `&"mouse"` scheme applies the cursor and freeing it restores — asserted through a seam on
  `AimCursor` (a static `is_applied()` flag), since `Input`'s cursor state is not readable. Under
  `&"keys"` it is never applied.

### `tests/unit/test_aim_reticle.gd` + `tests/integration/test_aim_reticle_wiring.gd` (RET-2)

- `set_aim()` stores what it will draw (`_ring_radius`, `_target_angle`, `_hull_angle`, `_state`) —
  a `_draw()`-only node exposes nothing assertable, the same reason `OverheatBar` keeps
  `_percentage` as a member.
- The ring radius **equals `ShipTurnController.mouse_dead_zone_px`** on a ship whose controller has
  had that export changed from its default — proving it is read, not duplicated.
- State colour changes for `_snap_held` and for `set_steering_enabled(false)`.
- **Boundary:** cursor exactly on the ship (zero-length vector) does not spin the target tick to
  world-right — the dead zone holds it, mirroring the guard in `set_aim_target()`.
- Wiring: the reticle is a child of `player_ship.tscn` found by class; it is hidden under `&"keys"`
  and hidden while `set_physics_process(false)` (the mission-menu freeze, §6.5).

### `tests/unit/test_boost_meter.gd` (BST-1) — extend the existing file

- `drain()` spends continuously and returns false on the frame it hits empty.
- **Boundary:** a drain larger than the remaining charge lands exactly on `0.0` and never negative.
- `try_spend_segment()` at `segments = 3`, `max_charges = 3` spends exactly 1.0; at `segments = 4`,
  `max_charges = 5` spends 1.25; it refuses when the remainder is short by any amount.
- Both spends set the full `recharge_delay_sec` pause.
- `set_segments()` clamps to ≥ 1 and emits `segments_changed` once.
- **Boundary — the persistence claim:** `boost_charge_count` values 2 and 5 both produce a legal
  meter, and a capacity raise mid-hold does not drop `charges` (the existing
  `_on_progression_changed` contract).

### `tests/integration/test_boost_bar.gd` (BST-1) — extend the existing file

- Bar width grows with `max_charges` (2 units → 32 px, 5 units → 80 px). **This is the assertion
  that fails on a fixed-width implementation**, which is finding 9's whole point.
- `segments = 1` draws one tank; `segments = 3` draws three, evenly, with gaps.
- Unit ticks are drawn at each whole bar-unit in both tiers.
- Fill colour differs between the two tiers.

### `tests/integration/test_open_space_boost_verb.gd` (BST-2, BST-3) — extend the existing file

- Frame one of a press sets `velocity` to `boost_exit_speed` along the nose — **unchanged**, and the
  regression guard that says the hold did not become a ramp (finding 8).
- **The 180° flip, end to end:** travelling at `(0, -420)` with `rotation = PI`, one pressed frame
  leaves `velocity.y > 0` at `boost_exit_speed`. This is the player's headline ask.
- Holding drains at `drain_rate` and keeps `_speed_ceiling` at `boost_exit_speed` for as long as the
  key is down; releasing lets the ceiling decay at `boost_ceiling_decay`.
- **Boundary — a tap:** one `pressed` frame then all-released frames still burns the full
  `boost_hold_sec` minimum and no more.
- **Boundary — empty:** with `charges < min_start_charge` a press changes nothing at all — no
  velocity write, no spend.
- **Boundary — drained mid-hold:** the boost ends on the frame the meter empties, with `charges`
  exactly `0.0`, and holding through it does not restart.
- **Boundary — §6.6 the freeze:** `set_physics_process(false)`, drive no frames, re-enable; charges
  are unchanged and no boost is in progress.
- BST-3: with `engine_boost` equipped, one press spends exactly one segment and activates the
  module; with the meter short of a segment, the press spends nothing and the module does **not**
  activate. Equipping mid-hold re-partitions the bar without losing charge.
- BST-3 boundary: the module fires on **H in assault** (`player_fighter.tscn`) and **not** on H in
  open space — the free-activation hole the duck-typed opt-out exists to close.

### `tests/integration/test_open_space_boost_verb.gd` (FLY-1, FLY-2)

- `_step_bank()` returns 0 for no rotation change, saturates at `bank_max_rad`, is sign-correct for
  both directions, and decays back toward 0 when turning stops.
- **Boundary — the single-writer rule:** after a bank step the ship's `rotation` is byte-identical
  to what `ShipTurnController.step()` returned. `test_ship_rotation_single_writer.gd` sweeps
  `global/ship_modules/*.gd` only, so this case is what covers the ship script itself.
- A boost's start frame raises `CameraShake` trauma; the rig reports `_boosting` for the boost's
  duration and clears on release.

### Suite-wide gates that apply

`test_signal_emit_arity.gd` (the new `segments_changed` and `camera_motion_changed` must declare
their parameters — §3), `test_project_load_integrity.gd` and `test_resource_uid_integrity.gd` (new
`.gd` files take their UID from `--import`; none is hand-typed), `test_suite_integrity.gd`, and
`scripts/check-test-leaks.sh` after any task whose tests `await`.

---

## Risks

1. **Skew banking may simply look wrong** (FLY-1). No headless test can tell. Mitigation: it is one
   `@export`; setting `bank_max_rad = 0.0` reverts it with no code change, and banked sprite frames
   become a follow-up rather than a blocker.
2. **`Input.set_custom_mouse_cursor()` is process-global and sticky** (§6.1). A missed restore path
   leaves a crosshair in the boot menu. Mitigation: `_ready()`/`_exit_tree()` is the only pair, and
   `_exit_tree()` fires on every exit including `reload_current_scene()`. A test asserts the restore.
3. **The camera↔cursor feedback loop** (§6.3) is real but this plan does not enter it: nothing in
   the camera rig reads the cursor. It is listed because it is the reason cursor bias is out of
   scope, and the reason a future task adding it must compute from *screen* position.
4. **Moving `_boost_meter.step()` above the `engine_boost_active` early return** touches a line the
   source comments call "deliberately redundant … not to be cleaned up". The comment is about the
   *early return*, not about the step's position, but BST-3 must re-read it and re-run
   `test_open_space_boost_verb.gd` rather than assuming.
5. **Nine tasks all editing `player_ship.gd`.** The file is already the busiest script in
   `open_space/` at ~390 lines and this adds a rig hookup, a reticle hookup, a cursor pair, a bank
   step and a rewritten boost. If it passes ~500 lines the boost block should move to its own child
   node in the `ShipTurnController` shape — noted, not scheduled.
6. **The player may dislike the corrected camera anyway.** A velocity lead is *by construction*
   behind a hard turn (finding 1's stated tradeoff): the camera keeps looking where you were going
   until momentum actually changes. That is honest, and it is what the physics does — but it is a
   different feel from the instant facing lead, and CAM-1 should be fly-tested before CAM-2 and
   FLY-2 build on it.

---

## Out of scope

- **Strafe and reverse-thrust engine modules.** Findings 5 and 10 endorse them *as modules* and
  `SLOT_MODULES[&"engines"]` is the right home, but each needs a module class, an icon, an unlocker
  pickup placed in the hub and a `test_module_unlock_sources.gd` entry — a separate epic's worth of
  work, and the research is explicit that they must not become defaults.
- **Cursor-bias ("sweet spot") camera** — findings 2 and 6 both recommend it, but §6.3's feedback
  loop makes it the riskiest item in the epic and the velocity lead already answers the player's
  stated instinct. Revisit after CAM-1 is flown.
- **A directional `CameraShake`** (finding 2's Celeste note). Scalar trauma is enough for FLY-2.
- **Banked sprite frames from PixelLab.** Only if FLY-1's skew reads badly.
- **Any save migration.** `boost_charge_count` keeps its name, range and pickup; only its
  interpretation changes, and every on-disk value stays legal.
- **A conditional 180° flip threshold.** Rejected in Design above; the unconditional redirect is
  simpler, already shipped, and is what the player asked for.
- **Lowering `CameraDirector.blend_speed`.** §4.2 measures it as responsive; the swing was the
  target's, not the blend's.
