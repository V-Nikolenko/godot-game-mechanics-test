# Open-space mouse aiming — sources

Merged from [`2-research.md`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md).
No implementation task ran its own research stage (all were Direct-track against the approved
plan), so that file is the complete set.

| Source (URL) | What it contributed | Where it shows up in the build |
|---|---|---|
| [brihernandez/MouseFlight](https://github.com/brihernandez/MouseFlight) | The canonical War Thunder-style rig steers an **aim point**, not the vehicle: `MouseAimPos` and `BoresightPos` are two separate readable values and "fly toward that point" is left to the vehicle's own steering. | The whole shape of `ShipTurnController`: `_target_angle` (cursor-owned) is separate from the hull's `rotation` (controller-owned), and weapons/boost read the hull. `set_aim_target()` / `step()` is that split expressed as two calls. |
| [Godot `@GlobalScope` class reference](https://docs.godotengine.org/en/stable/classes/class_%40globalscope.html) | `rotate_toward(from, to, delta)` is a constant-rate chase that "interpolates correctly when the angles wrap around `TAU`"; `angle_difference` returns the signed shortest difference and, at exactly ±180°, "returns `-PI` if `from` is smaller than `to`, or `PI` otherwise". **WebFetch truncated this page (it is enormous); `scripts/fetch-page.sh` recovered it in full.** | `rotate_toward` applies the final per-frame step, so the wrap case cannot be got wrong by hand. The documented ±180° tie-break is what `test_ship_turn_controller.gd`'s 180°-behind case pins. |
| [Rory Driscoll, *Frame Rate Independent Damping using Lerp*](https://www.rorydriscoll.com/2016/03/07/frame-rate-independent-damping-using-lerp/) + [Freya Holmér's framerate-independent lerp writeup](https://mastodon.social/@acegikmo/111931613710775864) | A per-frame `lerp(current, target, k)` is frame-rate dependent and is *the* standard bug here. The fix is exponential decay, `Damp(a,b,λ,dt) = Lerp(a,b,1-exp(-λ·dt))`, expressed as a **half-life**; `t½ ≈ 0.1–0.2 s` is the "snappy but visibly lagging" band for a player vehicle. | The smoothing half of the turn model, and `mouse_turn_half_life = 0.14 s` sitting inside the cited band. Directly responsible for `test_ship_turn_controller.gd`'s frame-rate-independence case (60×1/60 s vs 1×1 s must agree). |
| [Jet Lancer Steam discussion — "What the hell is up with the Mouse controls?"](https://steamcommunity.com/app/913060/discussions/0/3606765810634090111/) | The stated reference game **did** ship mouse banking slower than keyboard. The shipped friction was not the slowness — it was that the rate could not be changed, and the dev confirmed custom mouse banking was "not possible in the current build". | Validates the "precision paid for in turn rate" premise. Its second half is why every turn number is an `@export` on a node in `player_ship.tscn`, and why the store is `SettingsState` (a settings store) rather than `ControlsState`, so a sensitivity key lands without reshaping anything. |
| [Nova Drift — "Directional gamepad controls"](https://steamcommunity.com/app/858210/discussions/0/1631916887498615323/) | A deliberately limited rotation speed is a **design asset**, not a tax: "Forgoing twin-stick controls is core to the design and the titular 'Drift' mechanic". After pushback the alternate scheme was added *in settings*, where "the stick designates the target direction the ship should rotate to face, rather than clockwise or counter-clockwise steering" — exactly this epic's turn-to-target vs. turn-left/right split. | Justifies keeping both schemes as first-class settings rather than treating Classic as legacy, and justifies the 150 °/s cap as a feature. ⚠️ **An earlier draft of the research also attributed a "software mouse cursor" claim to this thread. The page was refetched in full (14 comments) during plan review and contains no such statement; the attribution was withdrawn.** The two quoted lines above are verbatim and do stand. |
| [Unity — "Inaccurate top-down mouse aim (2D)"](https://discussions.unity.com/t/inaccurate-top-down-mouse-aim-2d/126542) and [Unreal — "Top Down Shooter Mouse Aim Bug"](https://forums.unrealengine.com/t/top-down-shooter-mouse-aim-bug/59694) | The cursor-on-top-of-the-ship singularity is a known recurring failure of turn-to-cursor, and a dead zone is the standard remedy. **Weaker sourcing than the rest** — practitioner forum consensus, not a postmortem, and treated as authority for the *mechanism* only, never for a radius. | `mouse_dead_zone_px` and the decision to **hold** the previous target angle inside it. The dead-zone-edge test cases (47.9 px / 48.1 px) exist because of this finding. |
| [Godot `Input` class reference](https://docs.godotengine.org/en/stable/classes/class_input.html) | `MOUSE_MODE_CONFINED` / `MOUSE_MODE_CAPTURED` semantics; `Input.warp_mouse()` is "only supported on Windows, macOS and Linux" and `parse_input_event()` "will not move the OS mouse cursor". | Both pointer modes rejected on the record. More importantly: this is the source for "no headless GUT test can place a real cursor", which forced the injected-`Vector2` design and, through it, the project-wide "the mouse is read in exactly one line" convention. |

## Unreachable or degraded sources

- **None were abandoned.** The Godot `@GlobalScope` page was the only one WebFetch could not deliver
  intact, and `scripts/fetch-page.sh` recovered it.

## Findings with no citable source — judgement calls, labelled as such

These were the plan's own reasoning from this project's constants, and the plan says so explicitly
rather than dressing them as research:

- **`mouse_max_turn_rate_deg = 150.0`** — ~68% of the existing 220 °/s keyboard rate; 180° in 1.2 s,
  inside `EngineBoostModule`'s 2.0 s cooldown. Below ~110 °/s the flip-boost
  (`boost_speed_threshold = 180` px/s) stops being aimable; above ~180 °/s Classic has no reason to
  exist. No source publishes Jet Lancer's or Nova Drift's actual rate, and no figure was invented.
- **`mouse_dead_zone_px = 48.0`** — mechanism from the practitioner threads, radius from this
  project's own geometry: `player_ship.tscn`'s hull `CircleShape2D_body` has radius **11.045 px**
  (the 64×64 figure in an earlier draft was the atlas cell, mostly padding), so 48 px is ≈4.4 hull
  radii. Flagged in the plan as the number needing a human fly-test most.
- **`mouse_turn_half_life = 0.14 s`** — the *band* is cited (finding 3); the specific value inside it
  is a judgement call.
- **The software-cursor option** sketched in research finding 5 is **our own idea**, not a report of
  what any shipped game does. It was rejected anyway.
