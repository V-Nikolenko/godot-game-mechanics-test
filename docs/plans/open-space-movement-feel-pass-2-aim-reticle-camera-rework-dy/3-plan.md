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
(`player_ship.gd:84-88`). `_update_camera_feel()` keeps its job — find the `Camera2D`, find the
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

**Also rejected — splitting CAM-1 into "the sign fix" and "the motion layer"** (review N1).
`2-research.md`'s implication 1 says *"do not bundle them: if the small fix ships first, the
fly-test that follows tells the user whether the layer is even wanted"*, and this plan knowingly
goes the other way. The reason is the one the rest of the task rests on: **the one-line sign fix is
not separately testable.** `_update_camera_feel()` early-returns with no `Camera2D`, so on today's
build the formula is unreachable by the gate in either form; shipping the sign fix alone means
shipping an untested change and then immediately reworking the same six lines into a node. The
extraction is the cost of admission, and once the node exists the dead zone, the cap and the
smoothing are three `@export` defaults inside it rather than three separate edits. **The
bisect-by-feel concern is real and is answered by tuning, not by task splitting**: every one of the
four is an `@export`, so a fly-test that dislikes the result sets `lead_dead_zone_px = 0`,
`lead_max_px = 140`, `lead_half_life = 0` and is back to pure-sign-fix behaviour with no code
change. Risk 6 already schedules that fly-test.

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

## PUBLIC, and load-bearing for FLY-2 (review B6): the rig owns the accessibility scale, but
## CameraShake.add() is called from the ship, not from here. Without a reader, `camera_motion =
## off` would still shake the screen on every boost — and finding 3 names "camera shakes or
## tilting" among the problem cases by name. Every automatic-motion channel in the epic routes
## its amplitude through this one number, wherever the call site lives.
func get_motion_scale() -> float:
    return _motion_scale
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
signal, and a second row in the settings panel.

**That second row is a scene edit as well as a script edit** (review N2). `settings_panel.gd:29,36`
are `@onready var _value_lbl: Label = $Rows/Row0/ValueLabel` and `_rows = [$Rows/Row0]` — the row is
a **node in `global/ui/pause_menu/settings_panel.tscn`** (`Rows/Row0`, with its `NameLabel` and
`ValueLabel` children at lines 26-35), so CAM-2 adds a `Row1` of the same shape there, and
`_refresh()` stops hard-coding the single `@onready _value_lbl` and resolves `ValueLabel` per row. The panel's own header comment ("a second row is a copy of the first:
another entry in `_rows` and another branch in `cycle()`", `settings_panel.gd:15`) elides the scene
half; this plan does not. It is still a small task — one duplicated node, one array entry, one
`cycle()` branch, one `_refresh()` generalisation.

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
`OverheatBar`.

`top_level` on a `CanvasItem` reinterprets local coordinates as global, so **the ship must
reassign `_reticle.global_position` every physics frame**, exactly as it already does for the two
bars at `player_ship.gd:148-151` (review N11). Without that line the ring sits at world origin, not
on the ship — the offset is `Vector2.ZERO` rather than the bars' `(0, 20)` / `(0, 26)`, because the
ring is centred on the hull. `top_level` is what keeps it *upright* while the hull rotates, which is
the whole reason the bars use it and the reason the ring does too: an angular readout that rotates
with the thing it is measuring reads nothing.

It draws, centred on the ship:

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

**FLY-1 — the hull banks into its turns.** `$SpriteAnchor/ShipSprite2D.skew`, driven from the
per-frame rotation delta, smoothed, clamped to a small angle:

```gdscript
@export var bank_max_rad: float = 0.12       ## ~7°, the visual limit
@export var bank_rate_ref_deg: float = 150.0 ## turn rate that reaches full bank
@export var bank_half_life: float = 0.12
```

`_step_bank(rotation_delta, delta) -> float` is a pure method on the ship returning the new skew,
assigned to `$SpriteAnchor/ShipSprite2D.skew`. **It must be a sprite transform, never a hull
rotation** — `tests/integration/test_ship_rotation_single_writer.gd` makes `ShipTurnController` the
only writer of `OpenSpacePlayerShip.rotation` (§3), and `SpriteAnchor` is the subtree the project
already uses to separate visuals from the body.

**The target is `ShipSprite2D`, not `SpriteAnchor` itself** (review B5, and the original draft got
this wrong). `SpriteAnchor` (`player_ship.tscn:235`) is not a sprite holder: its children are
`ShipSprite2D`, `MuzzleLeft (-18, -1)`, `MuzzleRight (18, -1)`, `EngineLeft (-8, 30)` and
`EngineRight (9, 30)` (`player_ship.tscn:237-252`), and the two muzzles are the **bullet spawn
points** `WeaponState` reads (`player_ship.tscn:270-275`). `Node2D.skew` is part of the node's own
transform and **propagates to children**, so skewing the anchor shears the gameplay markers along
with the art — ~0.12 px at the muzzles and ~3.6 px laterally at the engine markers, at
`bank_max_rad = 0.12`. Small enough to go unnoticed, which is exactly what makes it the wrong kind
of bug: a later `bank_max_rad` increase would silently start walking the player's gun barrels.
Skewing `ShipSprite2D` alone shears only the art. A test case pins it (below).

Skew rather than a banked sprite frame because banked frames mean PixelLab and the capped monthly
allowance. **This is the one thing in the epic a human has to look at before it can be called done**
— a shear on a top-down hull either reads as a lean or reads as a glitch, and no headless test can
tell the difference. If it reads badly, the export goes to `0.0` and banked frames become a
follow-up; that is a one-value revert, which is why this is the cheap version to try first.

**FLY-2 — a boost you can see.** Two channels that already exist, wired to the boost state:
`CameraShake.add(...)` on the boost's start frame (between the existing `0.35` on a hit and
nothing), and `rig.set_boosting(true)` for the duration, which pulls the zoom a further
`boost_zoom_bonus = 0.06` out — the cheap, one-call version of finding 7's shipped "tunnel vision"
effect.

**Both must be scaled by `_motion_scale`, and only the zoom gets that for free** (review B6). The
rig applies the scale inside `get_zoom()`, but `CameraShake` is an autoload
(`project.godot:33` → `global/systems/camera_shake.gd`) whose `add(amount: float)` is called *from
the ship*, so the shake is outside the rig entirely. Finding 3 lists "camera shakes or tilting"
among the problem cases **by name**, so leaving it unscaled would make `camera_motion = off` a lie
on the one channel most likely to trigger the symptom. The ship therefore calls

```gdscript
CameraShake.add(boost_shake_trauma * _rig.get_motion_scale())   ## boost_shake_trauma: 0.25
```

using the `get_motion_scale()` reader added to the rig in CAM-1 above, with a null-rig fallback of
`1.0` so a ship instantiated without a camera still behaves as it does today.

**Why this does *not* add a `dependsOn` on CAM-2.** Reading the live scale through the rig makes
the two tasks order-independent: CAM-1 introduces `_motion_scale` defaulting to `1.0`, CAM-2 is
merely what lets the player move it off that default, and FLY-2 honours whatever the rig currently
holds either way. Ship FLY-2 first and the shake is already correctly wired the day CAM-2 lands;
ship CAM-2 first and nothing about FLY-2 changes. FLY-2's test sets `_motion_scale` on the rig
directly rather than going through `SettingsState`, so it does not need CAM-2 either. (An
`if _motion_scale == 0.0` special case inside the ship *would* have needed the dependency — this is
the reason to prefer the accessor.) A hard `dependsOn` here would also have to be hand-added:
`backlog-cli.js` has `--depends-on` on `add-task` only and no way to amend an existing task's
dependencies (`scripts/backlog-cli.js:344-365`), and hand-editing `BACKLOG.json` is forbidden.

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
signal tanks_changed(tanks: int)            ## declared with its parameter; the arity sweep checks this

@export var drain_rate: float = 1.0         ## bar-units per second, continuous tier
@export var min_start_charge: float = 0.25  ## below this a boost refuses to start

var tanks: int = 1                          ## 1 = one long bar; N = N discrete tanks

func set_tanks(n: int) -> void               ## clamps >= 1, emits
func tank_size() -> float                    ## float(max_charges) / float(tanks)
func drain(amount: float) -> bool            ## continuous spend; false when it hits empty
func try_spend_tank() -> bool                ## whole-tank spend, replacing try_spend()
```

**"Tanks", not "segments"** (review N5). `tests/integration/test_boost_bar.gd:142` already has
`test_segments_follow_capacity_on_signal`, where *segments* means the per-charge **pips**, i.e.
`max_charges`. BST-1 extends that same file, so reusing the word for the new partition count would
put `max_charges = 5, segments = 4` in one test body with two different meanings of the same noun.
`tanks` is also finding 7's own vocabulary for the Ridge Racer 7 gauge this is modelled on.

`drain()` and `try_spend_tank()` both set `_delay_left = recharge_delay_sec`, so the existing
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
- **`tanks` tanks**, split evenly across that width with the existing 1 px gap. `tanks == 1`
  is one long bar — the default tier, no special case.
- **faint unit ticks at every whole bar-unit boundary**, drawn in both tiers. Finding 9 again: the
  continuous gauge only communicates its upgrade if the increment is a visible fraction.
- **a per-tier fill colour** — the existing cyan for the continuous tier, a warmer colour for the
  Boost Drive tier. Finding 7 ships per-tier nitrous colours for exactly this reason.

The `setup()` seed-then-connect pattern stays verbatim; it now seeds `tanks` as well and connects
`tanks_changed` alongside `charges_changed`.

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
        flame on   (driven by _boosting from here on, NOT by _boost_hold_left)

sustain (_boosting):
        meter.drain(drain_rate * delta)
        _speed_ceiling = boost_exit_speed
        ## THE THRUST. Re-assert the velocity along the CURRENT nose every frame, exactly as
        ## the start frame does. Without this the hold buys nothing (review B4).
        velocity = Vector2.UP.rotated(rotation) * boost_exit_speed

stop    (not held and _boost_hold_left <= 0.0)  or  meter empty:
        _boosting = false; flame off; ceiling decays at boost_ceiling_decay as today
```

**The sustain branch must write `velocity`, and the original draft's did not** (review B4). The
draft's sustain was `meter.drain(...)` plus `_speed_ceiling = boost_exit_speed`, and
`_speed_ceiling` is a **clamp, never a force** — `player_ship.gd:294-295` only ever *reduces*
velocity. With W not held, `_handle_thrust()` takes its `else` branch and damps
(`player_ship.gd:241`, the 1.16 s half-life §4.4 measures), so the specified behaviour was: press
Shift at 700 px/s, hold, and **decelerate on the damping curve while paying 1.0 bar-units per
second**. A task titled "holding Shift burns the bar for sustained speed" that slows you down is
the bug the review caught. Re-asserting the velocity each frame is the smallest fix and it reuses
the start frame's own line.

Re-asserting along the **current** `rotation`, not a direction locked at the start, is deliberate
and is the one place this differs from `EngineBoostModule` (which locks `_boost_dir` at activation
precisely to keep its dash straight, `engine_boost_module.gd:56-58`). A held boost the player can
steer is the whole point of a hold — and it makes the 180° flip continuous rather than a one-shot:
spin the nose mid-hold and the momentum follows. That is a *stronger* reading of the player's
*"when we rotate 180 degrees and press and hold shift, we quickly start moving to other direction"*
than the tap-only version, not a weaker one.

**The flame and thruster tell move onto `_boosting`.** Today both read `_boost_hold_left > 0.0`
(`player_ship.gd:231-235,243-247`) and `_release_boost_flame()` fires when it reaches zero
(`player_ship.gd:282-285`). Under the new model `_boost_hold_left` is a **0.35 s minimum**, not the
boost's length, so on any hold longer than that the cyan flame and both thrusters would drop out of
`BOOST` while the boost is still running and still draining — the tell disagreeing with the state.
BST-2 changes those four reads to `_boosting` and moves `_release_boost_flame()` to the stop branch.
`_handle_thrust()`'s `else`/damping branch also stops being reached during a sustain, since the
sustain assignment overwrites whatever it computed; the ordering (`_step_boost()` runs *after* the
thrust/damping block, `player_ship.gd:253`) is what makes that work and must not be changed.

**No ramp, no spin-up.** Finding 8 is a shipped game that nerfed exactly this verb by requiring the
button be held "for a second for the speed boost to kick in" and made it "nearly hard to
strategize". The hold **sustains**; it never **builds**. That is also what keeps the 180° flip
intact: the redirect is a single frame-one assignment, and a ramp would destroy it.

**The flip stays unconditional.** `2-research.md`'s numbers table offers a ">120° between velocity
and facing" threshold and labels it a judgement call with no source; the boost epic's own finding 1
(ULTRAKILL) uses no threshold at all, and an unconditional redirect already satisfies the player's
ask — *"when we rotate 180 degrees and press and hold shift, we quickly start moving to other
direction"* — with fewer moving parts and nothing to mistune. **Rejected: the threshold.**

`_boost_hold_left` **sheds** the cyan-flame job (it moves to `_boosting`, above) and keeps the other
two: it is the anti-mash retrigger floor, and it is now the minimum burn, so a tap still buys the
full flip plus 0.35 s of sustained thrust for 0.35 bar-units. At the default capacity of 2 units
that is ~5 taps or 2.0 s of continuous hold; both numbers are `@export`s and both are fly-test
material, not gate material.

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
_boost_meter.set_tanks(3 if not drive else (4 if at_max_capacity else 3))
```

— 3 tanks normally, 4 at full `boost_charge_count`, per the player's "3-4 parts depending on the
amount of upgrades" and finding 7's Standard-3 / Quad-4. Without the module, `tanks = 1`.

With the module equipped, `_step_boost()`'s press branch becomes:

```gdscript
if module.can_activate() and meter.try_spend_tank():
    module.try_activate(self)
```

**Readiness is checked BEFORE the spend, and the order is part of the contract** (review B3). The
draft had `if meter.try_spend_tank(): module.try_activate(self)`, and `try_activate()` refuses
outright while the module is active or cooling (`engine_boost_module.gd:42-44`, `_COOLDOWN = 2.0`
at line 10). The Shift-side retrigger floor is `boost_hold_sec = 0.35`, so **every press in the
0.35 s – 2.0 s window would pass the Shift guard, burn a whole tank, and get `false` back** — at
`tanks = 3`, a third of the bar gone, silently, for nothing. Same short-circuit discipline as the
existing press branch, whose comment already says "ORDER IS PART OF THE CONTRACT: the hold-window
floor is checked BEFORE any spend" (`player_ship.gd:272-274`); this extends that rule to the
module's own gate rather than inventing one.

`can_activate()` is the new query. It goes on `ShipModuleBase` as a virtual returning **`false`** —
mirroring the base `try_activate()`, which also returns `false` (`ship_module_base.gd:58-59`), so
"the base module cannot activate" reads the same through both — and is overridden in
`EngineBoostModule` as `return not _active and _cooldown_left <= 0.0`, which is literally
`try_activate()`'s own first two lines negated (`engine_boost_module.gd:43-44`). Keeping it to that
one expression is what stops the two drifting. A refund on a `false` return was the alternative and
is rejected: a refund path means the meter briefly holds a spent value and the recharge-delay reset
has to be undone too, where the query costs three lines and no state.

The module otherwise keeps its 1500→500 px/s burst, its full i-frames and its 45 contact damage —
that is the "make it more powerful" half of the ask, and it is now *paid for* with a tank instead
of being free.

**Those six numbers become `@export var`s** (review N7). `_BOOST_SPEED`, `_BOOST_END_SPEED`,
`_BOOST_DURATION`, `_DAMAGE`, `_HIT_RADIUS` and `_COOLDOWN` are `const`
(`engine_boost_module.gd:5-10`), so the one thing the player explicitly asked to be "more powerful"
is the only feel number in this epic that cannot be moved without editing a constant.

Be honest about what this buys: `ShipModuleBase extends RefCounted` (`ship_module_base.gd:3`) and
every module is built by `ShipModuleBase.create()` with `.new()`, so there is **no inspector row and
no `.tres`** — `@export` on a `RefCounted` script is legal in 4.6 (verified by loading one headless:
no error, no warning, so `test_project_load_integrity.gd` stays green) but gains only per-instance
assignability. The real wins are that a test can set them without touching the shipped numbers, and
that the project's own "anything that cannot be validated headlessly is an `@export`" rule stops
having one exception sitting on the epic's own headline ask. **Defaults are unchanged**, so this is
behaviour-neutral and every existing module test stays green. If the churn is judged not worth it,
dropping this paragraph costs the plan nothing else.

**`get_description()` must be updated too** (review N8). `engine_boost_module.gd:30` begins *"Press
H to supercharge engines."*, the ship menu renders that string verbatim, and BST-3 is precisely the
change that makes H a no-op for this module in open space. The new text names Shift, names the tank
cost, and keeps the H mention scoped to assault.

**The H key stays generic, and Boost Drive opts out of it.** `player_ship.gd::_input` loops the whole
module pool on `use_ability` (H) — every other active module needs that, so H cannot simply be
retired. Leaving it would also make Boost Drive fireable **for free** on H while Shift charges a
tank. The fix follows the project's established duck-typed precedent (`Bullet.is_armored()`,
`face_instant()`): `ShipModuleBase` grows a virtual `is_open_space_boost_verb() -> bool` returning
`false`, `EngineBoostModule` overrides it `true`, and `OpenSpacePlayerShip._input` skips modules that
report it. `AssaultPlayer`'s own H loop (`player_fighter.gd:114-124`) is untouched, so Boost Drive
still works on H in assault, where there is no Shift boost to conflict with.

§6.8 — **who owns `velocity`, and the meter's clock**. `EngineBoostModule` sets
`engine_boost_active`, and `_step_boost()` early-returns on it, so exactly one of the two writes
velocity at a time. That early return is documented in `player_ship.gd:258-262` as deliberately
redundant with `_handle_thrust()`'s and is **not** to be removed.

**The draft's stated change here was wrong and is withdrawn** (review B2). It said
`_boost_meter.step(delta)` should move above `_step_boost()`'s early return "so the pool refills
during the module's 0.55 s burst instead of stalling". It would not: `_step_boost()` is called from
the **last line of `_handle_thrust()`** (`player_ship.gd:253`), and `_handle_thrust()` has its own
*earlier* return on the same flag (`player_ship.gd:219-220`). During the module's burst
`_step_boost()` is never called from the game loop at all, so reordering two lines inside it changes
nothing except the direct-call test path — which is exactly what the redundant return exists to
serve.

**What BST-3 does instead: nothing.** The meter is intentionally frozen for the module's 0.55 s, and
that is the correct behaviour rather than a shortcoming to route around:

- It is the same rule §6.6 relies on — *the ship owns the meter's clock*
  (`open_space/scenes/entities/player/boost_meter.gd:68-72` says so in as many words and has no
  `_physics_process`). A mission menu freezes the meter by freezing the ship, and so does a module
  burst. One rule, two cases, no new one.
- The amount at stake is ~0.035 bar-units. The tank spend that *starts* the burst sets
  `_delay_left = recharge_delay_sec = 0.5` (`boost_meter.gd:33,63`), so 0.5 s of the 0.55 s burst is
  inside the post-spend pause regardless; only the last 0.05 s would regen, at
  `recharge_rate = 0.7` units/s (`boost_meter.gd:30`).
- Hoisting the tick into `_physics_process()` above `_handle_thrust()` would move the meter's clock
  out of the one function that owns the whole boost model and into a place neither `engine_boost_active`
  return guards — a behaviour change to a component BST-1 and BST-2 both depend on, for 0.035 units.
  (It would *not* break §6.6: `set_physics_process(false)` stops `_physics_process` too, so the
  mission-menu freeze survives either placement. The objection is scope, not correctness.)

So BST-3 leaves the tick where it is and adds one line of comment saying why. The existing
module-precedence cases in `test_open_space_boost_verb.gd` assert on `velocity`, not on charges, so
they stay green — the task must re-run them and confirm rather than assume.

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
| BST-1 | `the-boost-meter-is-one-long-line-that-gets-longer-with-every` | `BoostMeter.drain/tanks`, `BoostBar` rework | medium | — |
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

`tests/helpers/save_sandbox.gd` is **half** the discipline and is not sufficient on its own
(review N3). `tests/README.md:745-751` is explicit: the sandbox redirects the `user://` file, but
the autoloads hold their value **in memory** and never re-read it after boot, so a test that leaves
`SettingsState` changed re-seeds every later test in the same GUT process.
`test_player_ship_turn_wiring.gd:21-31` and `test_pause_menu_settings.gd` both do the two-layer
capture-and-restore by hand, and **every** test here that touches `SettingsState` does the same:
CAM-2's `camera_motion` cases, and RET-1/RET-2's scheme-dependent cases. Same for
`ShipProgressionState.boost_charge_count` in BST-1. Every wiring test finds its node **by class**,
never by path, following `test_player_ship_turn_wiring.gd`.

### `tests/unit/test_open_space_camera_rig.gd` (CAM-1) — new code, asserts intent

**The epic's defining case is NOT here** — see the wiring file below. The draft put it here and the
review was right that it is vacuous at this level (B1): `step(velocity, delta)` never receives
`rotation`, so "nose down" is unobservable to the code under test and `get_offset().y < 0` is
guaranteed by the *signature* for every conforming implementation, correct or not. It also cannot
"fail on today's build", because on today's build this class does not exist. This file keeps only
what a pure `step()` can actually discriminate:

- Lead magnitude at cruise: 420 px/s → `420*0.30 - 32 = 94` → capped at `lead_max_px = 90`.
- Direction tracks the velocity argument: a velocity of `(0, -400)` leads with `y < 0`, `(0, +400)`
  leads with `y > 0`. Weak on its own (it is the signature), but it pins the sign convention the
  wiring test then checks end to end.
- **Boundary — the dead zone:** velocity of 1 px/s (the §4.4 ten-second coast tail) leads exactly
  `Vector2.ZERO` after settling, and zero velocity leads zero.
- **Boundary — no pop at the dead-zone edge:** stepping from just under to just over
  `lead_dead_zone_px / lookahead_time` moves the raw lead by ≪ `lead_dead_zone_px`, proving the
  subtract-don't-clip choice.
- Frame-rate independence: 60 steps of `1/60` and 6 steps of `1/6` settle to within 1 px.
- `_motion_scale = 0.0` ⇒ offset exactly zero **and** zoom exactly `Vector2.ONE` at any speed.
- `set_boosting(true)` lowers the zoom target (FLY-2's assertion, written with that task).

### `tests/integration/test_open_space_camera_wiring.gd` (CAM-1) — anti-inert, and the defining case

Every case above is green on a build where `OpenSpaceCameraRig` exists as a script but was never
added to `player_ship.tscn`. This file is the one that fails on it: the rig is found **by class** as
a direct child of an instantiated `player_ship.tscn`, and a ship placed under a `Camera2D` +
`CameraDirector` harness is driven one physics frame and asserted to have pushed a `speed_feel`
effect whose offset equals `rig.get_offset()`. The harness must reproduce `sector_hub.tscn:80-85`
exactly — a `Camera2D` named `Camera2D` as a **child of the ship**, with a `CameraDirector` as a
child of *that* — because `_update_camera_feel()` finds both by `get_node_or_null` on those names
(`player_ship.gd:369,372`) and silently returns if either is missing. A harness that gets the
parenting wrong makes every case in this file pass vacuously, which is the same failure mode B1
caught one level up.

- **THE DEFINING CASE, and it lives here because only here is `rotation` real** (review B1). On that
  same harness, set `ship.rotation = PI` (nose down) and `ship.velocity = Vector2(0, -400)`
  (travelling up), drive one physics frame, and assert the pushed `speed_feel` **offset has
  `y < 0`** — the camera leads where the ship is going, not where the nose points. This case fails
  on today's `player_ship.gd:380-381` (`facing * _LEAD_MAX * t`, which points **down** here), and it
  fails again on any future build that reintroduces `facing` into the lead. That is the regression
  this epic exists to prevent, and after CAM-1 the only file where `facing` could re-enter is
  `player_ship.gd` — which is the file this test drives and the unit file does not.
- Its mirror, so the assertion is not satisfiable by a stuck sign: `rotation = 0` (nose up) with
  `velocity = (0, +400)` pushes an offset with `y > 0`.

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
- `try_spend_tank()` at `tanks = 3`, `max_charges = 3` spends exactly 1.0; at `tanks = 4`,
  `max_charges = 5` spends 1.25; it refuses when the remainder is short by any amount.
- Both spends set the full `recharge_delay_sec` pause.
- `set_tanks()` clamps to ≥ 1 and emits `tanks_changed` once.
- **Boundary — the persistence claim:** `boost_charge_count` values 2 and 5 both produce a legal
  meter, and a capacity raise mid-hold does not drop `charges` (the existing
  `_on_progression_changed` contract).

### `tests/integration/test_boost_bar.gd` (BST-1) — extend the existing file

- Bar width grows with `max_charges` (2 units → 32 px, 5 units → 80 px). **This is the assertion
  that fails on a fixed-width implementation**, which is finding 9's whole point.
- `tanks = 1` draws one tank; `tanks = 3` draws three, evenly, with gaps.
- Unit ticks are drawn at each whole bar-unit in both tiers.
- Fill colour differs between the two tiers.

### `tests/integration/test_open_space_boost_verb.gd` (BST-2, BST-3) — extend the existing file

- Frame one of a press sets `velocity` to `boost_exit_speed` along the nose — **unchanged**, and the
  regression guard that says the hold did not become a ramp (finding 8).
- **The 180° flip, end to end:** travelling at `(0, -420)` with `rotation = PI`, one pressed frame
  leaves `velocity.y > 0` at `boost_exit_speed`. This is the player's headline ask.
- **Holding with NO thrust input keeps the speed** (review B4, and the case that fails on the
  draft's ceiling-only sustain): from a standing start, one pressed frame then 30 held frames at
  `1/60` with `move_up` unheld leaves `velocity.length()` at `boost_exit_speed` ± 1 px/s, not the
  ~0.7× the 1.16 s damping half-life would have left. Its companion asserts the bar actually paid
  for it: `charges` dropped by `drain_rate * 0.5` over those frames.
- **Steering mid-hold turns the momentum:** hold through a `rotation` change of PI and the velocity
  direction follows the nose within one frame, at `boost_exit_speed` — the continuous form of the
  180° flip, and the assertion that fails on a start-locked `_boost_dir`.
- **The tell matches the state:** at 30 held frames (well past `boost_hold_sec = 0.35`) the thruster
  effects are still `ThrusterEffect.State.BOOST` and the sprite is still on `flame_boost`; one
  released frame past the minimum drops both. This is the case that fails if the flame is left
  reading `_boost_hold_left` (review B4's second half).
- Releasing lets the ceiling decay at `boost_ceiling_decay`.
- **Boundary — a tap:** one `pressed` frame then all-released frames still burns the full
  `boost_hold_sec` minimum and no more.
- **Boundary — empty:** with `charges < min_start_charge` a press changes nothing at all — no
  velocity write, no spend.
- **Boundary — drained mid-hold:** the boost ends on the frame the meter empties, with `charges`
  exactly `0.0`, and holding through it does not restart.
- **Boundary — §6.6 the freeze:** `set_physics_process(false)`, drive no frames, re-enable; charges
  are unchanged and no boost is in progress.
- BST-3: with `engine_boost` equipped, one press spends exactly one tank and activates the
  module; with the meter short of a tank, the press spends nothing and the module does **not**
  activate. Equipping mid-hold re-partitions the bar without losing charge.
- **BST-3 boundary — a press during the module's cooldown costs nothing** (review B3, and the case
  that fails on the draft's spend-then-ask ordering): fire once, wait past `boost_hold_sec = 0.35`
  but well inside `_COOLDOWN = 2.0`, press again on a **full** meter, and assert `charges` is
  unchanged and no second activation happened. This is the one that loses the player's resource, and
  it is distinct from the "meter short of a tank" case above — here the meter is full and the
  *module* is the one refusing.
- BST-3 boundary: the module fires on **H in assault** (`player_fighter.tscn`) and **not** on H in
  open space — the free-activation hole the duck-typed opt-out exists to close.

### `tests/integration/test_open_space_flight_feel.gd` (FLY-1, FLY-2) — new file

A **new** file, not an extension of `test_open_space_boost_verb.gd` (review N4): banking has nothing
to do with the boost verb, and that file's header scopes it to "the whole model lives in
`_step_boost`". FLY-2's two cases live here too, next to the bank, because both are the same
subject — what the screen does about how hard you are flying.

- `_step_bank()` returns 0 for no rotation change, saturates at `bank_max_rad`, is sign-correct for
  both directions, and decays back toward 0 when turning stops.
- **Boundary — the single-writer rule:** after a bank step the ship's `rotation` is byte-identical
  to what `ShipTurnController.step()` returned. `test_ship_rotation_single_writer.gd` sweeps
  `global/ship_modules/*.gd` only, so this case is what covers the ship script itself.
- **Boundary — the bank does not move the guns** (review B5): capture
  `$SpriteAnchor/MuzzleLeft.global_position`, `MuzzleRight`, `EngineLeft` and `EngineRight`, drive a
  full-amplitude bank, and assert all four are unchanged to within float epsilon while
  `$SpriteAnchor/ShipSprite2D.skew` is non-zero. **This case fails on the draft's
  `$SpriteAnchor.skew`** — `Node2D.skew` propagates to children, so the anchor version shears the
  engine markers ~3.6 px sideways. It is the "prove the sprite change did not leak into gameplay"
  shape the single-writer case above already uses.
- A boost's start frame raises `CameraShake` trauma; the rig reports `_boosting` for the boost's
  duration and clears on release.
- **Boundary — `off` really is off** (review B6): with the rig's `_motion_scale` set to `0.0`, a
  boost's start frame adds **no** trauma (`CameraShake` trauma unchanged) and the rig's zoom stays
  `Vector2.ONE`. This is the case that fails on a bare `CameraShake.add(0.25)`, and it is why the
  rig exposes `get_motion_scale()`. It sets the scale on the rig directly rather than through
  `SettingsState`, which is what keeps FLY-2 independent of CAM-2 having shipped.

### Suite-wide gates that apply

`test_signal_emit_arity.gd` (the new `tanks_changed` and `camera_motion_changed` must declare
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
4. **BST-2 rewrites the busiest function in the module, and its sustain now writes `velocity`.**
   `_step_boost()` gains a held-input argument, a `_boosting` flag, a per-frame velocity assignment
   and a moved flame tell, while three other things still read `_boost_hold_left`. The ordering it
   depends on — `_step_boost()` runs *after* the thrust/damping block, as the last line of
   `_handle_thrust()` (`player_ship.gd:253`) — is load-bearing and undocumented at the call site;
   BST-2 must add that comment. Two existing early returns on `engine_boost_active`
   (`player_ship.gd:219-220` and `263-264`) also both guard this path, and the draft of this plan got
   their relationship wrong (see §6.8) — re-read both before editing either.
5. **Nine tasks all editing `player_ship.gd`.** The file is already the busiest script in
   `open_space/` at ~390 lines and this adds a rig hookup, a reticle hookup, a cursor pair, a bank
   step and a rewritten boost. If it passes ~500 lines the boost block should move to its own child
   node in the `ShipTurnController` shape — noted, not scheduled.
6. **The player may dislike the corrected camera anyway.** A velocity lead is *by construction*
   behind a hard turn (finding 1's stated tradeoff): the camera keeps looking where you were going
   until momentum actually changes. That is honest, and it is what the physics does — but it is a
   different feel from the instant facing lead, and CAM-1 should be fly-tested before CAM-2 and
   FLY-2 build on it.
7. **BST-3 is the one cross-cutting task, and it is the one to re-check on open** (review N12). It
   edits `ship_module_base.gd` — the base class of all fifteen modules — plus
   `engine_boost_module.gd`, `player_ship.gd`, and asserts behaviour in `player_fighter.gd`. It is
   still correctly a `medium`: the two new virtuals are three lines each, the tier switch is two,
   and the `const` → `@export` conversion is mechanical. But it is precisely what Risk 5's
   escalation clause is for, and if it turns out to need structural change the move is
   `./scripts/backlog-cli.js set-meta equipping-boost-drive-splits-the-bar-into-3-4-tanks-each-spe
   --complexity large --model opus`, **not** pushing through on sonnet.
8. **The follow-up "engine modules" epic is mentioned but not filed** (review N9). Strafe and
   stabilisation are the research's real answer to *"movement is not very fun"* and this epic
   deliberately defers them — but a deferral recorded only in an Out-of-scope bullet evaporates when
   the epic closes. Filing an epic is a triage-stage action and is not this plan's to take, so it is
   flagged for the user here and in the review report instead: **if idea point 3 matters, the engines
   epic needs to exist before this one closes.**

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

---

## Response to review round 1

`4-review.md` returned **CHANGES_REQUESTED** with seven blocking findings on 2026-09-16. Every one
is addressed above; B2, B3, B4 and B5 were independently re-confirmed against the source before
being acted on, because four of the seven contradicted something this document asserted.

| # | Finding | What changed |
|---|---|---|
| B1 | The "defining case" test was vacuous — `step(velocity, delta)` never sees `rotation` | Moved to `test_open_space_camera_wiring.gd`, where the ship is real and the case fails on `player_ship.gd:380-381`. The unit file keeps only what a pure `step()` can discriminate, and says so. A mirror case was added so a stuck sign cannot pass. |
| B2 | §6.8's meter-tick move does nothing: `_handle_thrust()` returns first | **Withdrawn.** Confirmed at `player_ship.gd:219-220` vs `253`. BST-3 now changes nothing there and documents *why* the freeze is correct, with the 0.035-bar-unit figure computed from `boost_meter.gd:30,33,63`. Risk 4 rewritten. |
| B3 | A tank was spent before the module's 2 s cooldown was checked | Press branch is now `if module.can_activate() and meter.try_spend_tank()`. New virtual `can_activate()` on `ShipModuleBase` (returns `false`, mirroring `try_activate()`), overridden in `EngineBoostModule`. New boundary test: a press on a full meter during the module's cooldown spends nothing. |
| B4 | The "sustain" applied no force — `_speed_ceiling` is a clamp, so the hold *decelerated* you | Sustain now re-asserts `velocity` along the **current** nose each frame (which also makes the 180° flip continuous, not one-shot). The flame/thruster tell moves off `_boost_hold_left` onto `_boosting`. Three new test cases, including the one that fails on the draft. |
| B5 | `SpriteAnchor.skew` shears the muzzle and engine markers, not just the art | Target is now `$SpriteAnchor/ShipSprite2D`. New boundary test pins all four markers' global positions across a full-amplitude bank. |
| B6 | `camera_motion = off` would still shake the screen; FLY-2 missing a CAM-2 dep | Rig gains `get_motion_scale()`; the ship scales its `CameraShake.add()` through it. New test: scale `0.0` ⇒ no trauma. The CAM-2 dependency is deliberately **not** added — the accessor makes the two order-independent, and `backlog-cli.js` cannot amend an existing task's `dependsOn` anyway (reasoning recorded under FLY-2). |
| B7 | Finding 9's two quotes are not on the cited pages | `2-research.md` finding 9 is now a marked paraphrase with its retrieval method stated, and the doc's sourcing note carries an explicit correction. The numbers were correct and no plan decision changes. |

Non-blocking notes N1, N2, N3, N4, N5, N7, N8, N10, N11 and N12 are also applied, each marked
`(review Nx)` at the point of change. **N6** (BST-1 is arguably two deliverables) is accepted as
stated and left as one task: the reviewer did not ask for a split, the plan specifies both halves
completely, and Risk 7's escalation route covers it if it overruns. **N9** (file the follow-up
engines epic) is not this stage's to do — filing an epic is a triage action — so it is recorded as
Risk 8 and raised with the user instead.
