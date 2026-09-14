# Research — how shipped games and engines solve turn-to-cursor with inertia

Epic: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`. Stage: RESEARCH, 2026-09-13.
Companion to [`1-context.md`](./1-context.md), which covers what is already in this codebase.

Sources were reachable without needing `scripts/fetch-page.sh` except for the Godot class reference,
which WebFetch truncated (the `@GlobalScope` page is enormous) and which the script recovered in
full. Nothing was abandoned as unreachable. Where a number below has no citation it is labelled a
**judgement call** and derived from this project's own constants, not from a source.

---

## Findings

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **1. Do not steer the vehicle with the mouse — steer an *aim point*, and have the vehicle chase it.** The canonical War Thunder-style mouse-flight rig rotates a dedicated aim transform from mouse input, exposes `MouseAimPos` and `BoresightPos` as two separate readable values, and leaves "fly toward that point" to the vehicle's own steering. The stated philosophy: "if you want to fly towards something, you simply put the mouse cursor over it." | Buys exactly the split this epic requires — the cursor owns the *target* angle, the hull owns the *actual* angle, and weapons read the hull. Costs a second piece of state that can desync from the hull, and the author is blunt that "the mouse is not an ideal method of controlling an aircraft". | — | [brihernandez/MouseFlight](https://github.com/brihernandez/MouseFlight) |
| **2. Godot ships the wrap-correct primitive; use it rather than hand-rolling angle math.** `rotate_toward(from, to, delta)` — "Rotates `from` toward `to` by the `delta` amount. Will not go past `to`. Similar to `move_toward()`, but interpolates correctly when the angles wrap around `TAU`." `angle_difference(from, to)` returns the signed shortest difference "in the range of `[-PI, +PI]`. When `from` and `to` are opposite, returns `-PI` if `from` is smaller than `to`, or `PI` otherwise." | `rotate_toward` is a **constant-rate** chase: no overshoot, no momentum, arrives exactly. That is precisely why it alone will not read as "inertia" — it decelerates instantly at arrival. Its value here is as the *clamp* on whatever smoothing supplies the feel, and as the guaranteed-correct wrap handling. Available since Godot 4.4; this project is on **4.6.3**. **Verified in-engine, and the ±180° tie-break is counter-intuitive** — see the note below the table. | `delta` in radians/frame = `max_rate * dt` | [Godot `@GlobalScope`](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html) |
| **3. A naive `lerp(current, target, k)` per frame is frame-rate dependent and is the standard bug here.** The fix is exponential decay: `Damp(a, b, λ, dt) = Lerp(a, b, 1 - exp(-λ·dt))`, which gives identical results whether you step 60×@1/60 s, 30×@1/30 s, or once @1 s. | Exponential approach **never overshoots and never quite arrives** — it is asymptotic. Cheap (one parameter), stable, and reads as "heavy but obedient". It cannot express overshoot-and-settle, which is what physical inertia actually looks like. Pick it if "lag" is the goal; pick finding 4 if "momentum" is. Godot has no built-in `exp_decay`, so this is three lines written by hand. | Express the parameter as a **half-life**: `λ = ln(2)/t½`. `t½ ≈ 0.1–0.2 s` is the snappy-but-visibly-lagging band for a player vehicle. | [Rory Driscoll, *Frame Rate Independent Damping using Lerp*](https://www.rorydriscoll.com/2016/03/07/frame-rate-independent-damping-using-lerp/); [Freya Holmér's framerate-independent lerp writeup](https://mastodon.social/@acegikmo/111931613710775864) |
| **4. Jet Lancer — the stated reference — did ship mouse banking *slower* than keyboard, and the complaint was not the slowness but that it was not adjustable.** A player reports mouse controls are "way more accurate, but don't seem to be as fast as they should be", asks why banking sensitivity cannot be changed for mouse when keyboard is fully customisable, and notes mouse bank/shoot/dodge "are all bound to mouse buttons that cannot be unbound". Developer WhyNot: "we known about some issue with mouse bindings, and will try to address them in the future" and confirmed custom mouse banking was "not possible in the current build". | Validates the epic's core balance premise — precision-for-speed is the trade the reference game made, and it is defensible. The warning is the *second half*: hard-coding the mouse turn rate and the mouse bindings is what generated the friction. Expose the turn rate as an `@export` at minimum, and design the settings store so a sensitivity value can be added later without reshaping it. | — | [Jet Lancer Steam discussion: "What the hell is up with the Mouse controls?"](https://steamcommunity.com/app/913060/discussions/0/3606765810634090111/) |
| **5. A fixed, deliberately-limited rotation speed is a design *asset* in a top-down space game, and both schemes must be first-class settings.** Nova Drift's developer: "Forgoing twin-stick controls is core to the design and the titular 'Drift' mechanic", with the fixed rotation speed a deliberate choice that enables ramming and front-facing shields. After player pushback the alternate scheme was added *in settings* — "the stick designates the target direction the ship should rotate to face, rather than clockwise or counter-clockwise steering" — which is exactly the turn-to-target vs. turn-left/right split this epic proposes. *(Correction, 2026-09-14 plan review, obs 8: an earlier version of this row also attributed to this thread the claim that the game drives aiming from a **software mouse** rather than the OS pointer position. The page was refetched in full — 14 comments — and contains no such statement. The two quoted lines above are verbatim and do stand. The software-cursor option below is retained as an **unsourced design option**, not a report of what Nova Drift does.)* | The turn-rate cap is not a tax to apologise for, it is what makes this ship's future front-arc mechanics (the `EngineBoostModule` ram, the armoured-core deflection rules) mean something. A software cursor — synthesised from `InputEventMouseMotion.relative` and clamped by the game rather than read from the OS pointer, **our own idea, no source** — would sidestep the window-exit and pointer-confinement problems in `1-context.md` — at the cost of rendering and clamping your own cursor, and of the OS pointer no longer matching what the game shows. | — | [Nova Drift: "Directional gamepad controls"](https://steamcommunity.com/app/858210/discussions/0/1631916887498615323/) |
| **6. The cursor-on-top-of-the-ship singularity is a known, recurring failure of turn-to-cursor, and the standard remedy is a dead zone.** As the cursor approaches the vehicle the angle subtended by a fixed mouse movement grows without bound, so sub-pixel jitter becomes large target-angle swings and the vehicle "spins out of control"; a dead zone around the player stops it "slowly drifting toward your cursor as the angle of shooting change increases with proximity". | A dead zone removes the jitter but creates a region where the ship simply will not turn — too big and close-quarters dogfighting feels dead. It also has to be measured **ship-to-cursor in world space**, not from screen centre, because `_update_camera_feel()` already pushes the viewport up to `_LEAD_MAX = 140 px` off the ship. In this codebase the degenerate case is worse than jitter: `Vector2.ZERO.angle()` returns `0.0`, so an exactly-coincident cursor commands a hard snap to world-right. | Dead-zone radius on the order of the ship sprite's own footprint. | Aggregated practitioner threads: [Unity — inaccurate top-down mouse aim (2D)](https://discussions.unity.com/t/inaccurate-top-down-mouse-aim-2d/126542); [Unreal — Top Down Shooter Mouse Aim Bug](https://forums.unrealengine.com/t/top-down-shooter-mouse-aim-bug/59694). **Weaker sourcing than the rest** — forum consensus, not a postmortem. Treated as a known failure mode, not as authority for any specific radius. |
| **7. Pointer confinement is an explicit, documented engine choice with a real cost.** Godot's `MOUSE_MODE_CONFINED` "confines the mouse cursor to the game window, and make it visible"; `MOUSE_MODE_CAPTURED` locks it to window centre and forces you to read `InputEventMouseMotion.relative`. `Input.warp_mouse()` "sets the mouse position … relative to an origin at the upper left corner of the currently focused Window Manager game window" and is "only supported on Windows, macOS and Linux", while `parse_input_event()` explicitly "will not move the OS mouse cursor". | Confinement fixes the stale-target-angle-when-the-pointer-leaves problem, but it takes the pointer hostage on a multi-monitor desktop and is obnoxious when the game is windowed. Capture solves it properly but obliges you to synthesise and clamp your own cursor — i.e. the software-cursor option sketched in finding 5 (an idea of ours, not something the cited thread reports). **The testing consequence is the important one:** no headless GUT test can reliably place a real cursor, so the turn model must accept an injected target rather than calling `get_global_mouse_position()` internally. | — | [Godot `Input` class reference](https://docs.godotengine.org/en/stable/classes/class_input.html) |

---

### Verified in-engine (Godot 4.6.3.stable, headless, this container)

```
rotate_toward(0.0, PI, 0.1)   = -0.1      # turns CLOCKWISE toward a target dead astern
angle_difference(3.0, -3.0)   =  0.283…   # wraps correctly across ±π instead of taking the long way
Vector2.ZERO.angle()          =  0.0      # a cursor exactly on the ship commands "face world-right"
```

The first line is the trap. With the cursor **exactly 180° behind** the ship, `angle_difference`
follows its documented rule — "returns `-PI` if `from` is smaller than `to`, or `PI` otherwise" — so
`rotate_toward` turns *negatively*, i.e. the direction flips depending on which side of zero the
ship's current `rotation` happens to sit. It is deterministic, but it is not "keep turning the way I
was already turning", and a player pulling a 180 will see the ship pick a side arbitrarily. The plan
should decide whether that is acceptable or whether the tie is broken by the sign of the current
angular velocity, and the test plan should pin whichever is chosen. The third line is the
dead-zone singularity from finding 6, confirmed rather than assumed.

## What the findings imply for the plan

**A clamped exponential chase is the shape that satisfies both halves of the ask.** Finding 3 gives
the "responsive but lagging" feel with one honest parameter and correct frame-rate behaviour;
finding 2 gives the hard per-frame cap that makes "slower than the keys" a *balance guarantee*
rather than an emergent property of a smoothing constant. Concretely: compute the desired step with
exponential decay toward the target angle, then clamp that step to `max_turn_rate_deg * delta`, and
apply it with `rotate_toward` so the wrap case cannot be got wrong. The cap is the number a designer
tunes; the half-life is the number that decides how it feels.

The alternative — a true angular-velocity model with acceleration and damping — is the only one that
can *overshoot and settle*, which is what physical inertia looks like and what finding 1's "vehicle
chases an aim point" rig implies. It is more code, has two coupled parameters that are hard to tune
blind, and can oscillate around the target if damped too lightly. It is a legitimate choice, and if
the plan picks it, it should say so against this alternative rather than by default. What is **not**
defensible is a bare `lerp(rotation, target, 0.1)` in `_physics_process` (finding 3) or a direct
`look_at`-style snap (contradicts the ask outright).

## Starting numbers

Everything in this section marked *(judgement)* is derived from this project's own constants, not
from a cited source. All of them need a human to fly the hub; nothing headless can validate feel.

| Parameter | Proposed start | Where it comes from |
|---|---|---|
| Keyboard turn rate (legacy scheme) | **220 °/s, unchanged** | `player_ship.gd::rotation_speed_deg`. 180° in 0.82 s. Must not move — the legacy scheme is meant to be today's behaviour exactly. |
| Mouse **max** turn rate | **150 °/s** *(judgement)* | ~68% of the keyboard rate; 180° in 1.2 s. Clearly slower as the ask requires, while still turning a half-circle inside the `EngineBoostModule` cooldown (2.0 s). Below ~110 °/s the flip-boost (`boost_speed_threshold = 180` px/s) stops being aimable; above ~180 °/s the keyboard scheme has no reason to exist. |
| Turn smoothing half-life | **0.14 s** *(judgement, band from finding 3)* | Inside the 0.1–0.2 s "snappy but visibly lagging" band. λ = ln2/0.14 ≈ 4.95. At 60 Hz physics that is a ~8% step per frame toward the target before the rate clamp bites. |
| Dead-zone radius (ship → cursor, world px) | **48 px** *(judgement, mechanism from finding 6)* | The ship sprite is a 64×64 atlas region; camera zoom runs 1.0 → 0.85 with speed, so 48 world px stays roughly a ship's-width on screen at any speed. Inside it, hold the current target angle — do **not** recompute from a near-zero vector, or `Vector2.ZERO.angle() == 0.0` snaps the ship to world-right. |
| Default scheme | **mouse** | Stated in the idea. |

## Questions research could not settle

- **Nova Drift's actual rotation rate** is not published (and the "software mouse" attribution has been withdrawn — see the correction in finding 5);
  the developer quotes establish the *design stance*, not numbers. No fabricated figure is offered.
- **Jet Lancer's mouse bank rate** is likewise unpublished — the Steam thread establishes only that
  it is slower than keyboard and was not adjustable at that time.
- **No dead-zone radius has a citable source.** Finding 6 supports the mechanism and the remedy;
  the 48 px above is derived from this project's sprite and camera constants.
