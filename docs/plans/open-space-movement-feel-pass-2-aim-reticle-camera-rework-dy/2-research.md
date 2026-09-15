# Research — reticles, look-ahead cameras, dynamic top-down flight, and hold-to-boost

Epic: `open-space-movement-feel-pass-2-aim-reticle-camera-rework-dy`. Stage: **RESEARCH**,
2026-09-15. Companion to [`1-context.md`](./1-context.md), which covers what is already in this
codebase and the measurements behind the reported bugs; it is not repeated here.

**Sourcing note.** One page needed `scripts/fetch-page.sh` after WebFetch returned **402**
(`ridgeracer.fandom.com`) and was recovered in full. One (`steamcommunity.com`) was read through
the script directly, since Steam reliably blocks automated clients. Two sources came back empty of
what the search index promised and are recorded as such at the bottom rather than quietly dropped.
Nothing below is attached to a page that was not actually read.

**Not repeated from the two sibling epics** — these already-recorded findings apply here and the
plan should treat them as in force rather than re-deriving them:

- Frame-rate-independent exponential damping, `1 - exp(-λ·dt)`, half-life 0.1–0.2 s for a player
  vehicle — [`../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md`](../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md) finding 5.
- Steer an *aim point*, let the vehicle chase it (War Thunder-style mouse flight) — same file,
  finding 1. This is the split `ShipTurnController` already implements and it is what makes a
  reticle meaningful.
- ULTRAKILL's dash spends discrete stamina and **always** resets momentum (max 3, 0.7/s regen);
  stamina regen should pause during and just after the action; Asteroids' "flip and burn" is an
  emergent skill this project is proposing to sell as a button —
  [`../open-space-boost-shift-burst-movement-on-an-upgradeable-boos/2-research.md`](../open-space-boost-shift-burst-movement-on-an-upgradeable-boos/2-research.md)
  findings 1, 4 and 6.

---

## Findings

| # | Finding | Tradeoff | Typical values | Source |
|---|---|---|---|---|
| **1** | **The industry-standard look-ahead is driven by the target's *motion*, not its facing — and it needs its own smoothing on top.** Cinemachine's Position Composer defines Lookahead Time as adjusting "the offset of the Cinemachine Camera from the Tracking target **based on the motion of the target**", and ships a separate Lookahead Smoothing whose docs say larger values "smooth out jittery predictions and increase prediction lag". The same component carries a Dead Zone — "the width and height of the region where the camera will **not** respond to target movement, expressed as a fraction of screen size" — and per-axis Damping, "how responsively the camera tries to maintain the desired position". | A velocity-derived lead is always *behind* a hard turn by construction: the camera keeps looking where you were going until the velocity actually changes, which is honest but reads as sluggish if the vehicle can turn far faster than it can change heading. A facing-derived lead is instant but is a **prediction the physics does not honour** — which is precisely today's bug (`1-context.md` §4.1). The smoothing/damping dial is a straight trade of jitter against lag, and the dead zone is the only one of the three that is free: it removes small-motion response without costing any responsiveness on large motion. | Not published as defaults. `1-context.md` §4.1 shows this project's shipped formula already *is* a lookahead of **0.35 s** (`140 px ÷ 400 px/s`) — it just points the wrong way. | [Unity — Cinemachine 3.1, Position Composer](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachinePositionComposer.html) |
| **2** | **Three shipped 2D cameras, three different answers — and one of them is the player's own proposal.** Mark Brown's survey: *Nuclear Throne* centres the camera **between the character and the cursor** — "you can get a better look at the enemies you're shooting at". *Sonic Generations* scales the lead by momentum — "it settles on the hedgehog when he's stood still, but it moves further and further in front of him as he picks up momentum". *Fez* uses a dead zone — "an invisible window where the character can wander around freely without the camera moving at all. But if you push beyond that window, the camera shifts." On smoothing: "if the camera perfectly tracks the character then it's going to react to every single movement, no matter how small - and that can lead to a camera that feels erratic and jerky", with the caution that over-damping leaves "the character actually in front of the camera". And on impact: in Celeste the camera "wobbles in the same direction as Madeline's dash, to really sell the speed and power". | The Nuclear Throne rule is the *only* one of the three that also answers thread 1 — biasing toward the cursor puts the aim point permanently on screen, so the reticle can never be lost off-frame. Its cost is that the camera now responds to mouse motion the ship has not acted on yet, which is the same class of complaint as today's bug, and (`1-context.md` §6.3) it risks a camera↔cursor feedback loop because `get_global_mouse_position()` is a *world* position. The Sonic rule is what a corrected velocity-lead already gives. The Fez dead zone is the cheapest single improvement available and composes with either. | No numbers published in the source. The article's closing position is explicit: "there's no such thing as a perfect camera that works for every game." | [Game Maker's Toolkit — *How to Make a Good 2D Camera*](https://gmtk.substack.com/p/how-to-make-a-good-2d-camera) |
| **3** | **"Camera moves while the player isn't moving" is a named accessibility barrier, not a taste complaint.** The Game Accessibility Guidelines entry *Avoid (or provide option to disable) any difference between controller movement and camera movement* lists "automatic camera movement without player input", "camera shakes or tilting" and "mouse smoothing" as the problem cases, and quotes a player: **"Games that have two types of movement going on at once...make me sick every single time."** It is classified *Vision / Intermediate*, and the recommended implementation is a **toggle**, not removal. | The guideline's remedy is a settings toggle, which is cheap here (`SettingsState` + one `settings_panel.gd` row) — but a toggle does not excuse a camera that swings 280 px on a turn by default (`1-context.md` §4.2). Taken literally the guideline also disfavours the speed-zoom this game already ships and any boost "tunnel vision" (finding 7): they are camera motion the player did not directly command. The defensible reading is *bound* the automatic motion and let it be turned off, rather than avoid it. | Barrier level: intermediate. No numeric thresholds given. | [Game Accessibility Guidelines — *Avoid (or provide option to disable) any difference between controller movement and camera movement*](https://gameaccessibilityguidelines.com/avoid-or-provide-option-to-disable-any-difference-between-controller-movement-and-camera-movement/) |
| **4** | **Godot's own docs tell you not to draw your cursor.** "You could display a 'software' mouse cursor by hiding the mouse cursor and moving a `Sprite2D` to the cursor position in a `_process()` method, but this will add **at least one frame of latency** compared to a 'hardware' mouse cursor. Therefore, it's recommended to use the approach described here whenever possible" — i.e. `Input.set_custom_mouse_cursor()`. If a software cursor is unavoidable, "consider adding an extrapolation step to better display the actual mouse input". | A hardware cursor is free and a frame faster, and at 60 Hz one frame is ~16.7 ms of visible lag on a fast flick — noticeable on a *precise aim point*. But a hardware cursor is a flat image at the pointer: it cannot draw the 48 px dead-zone ring **around the ship**, cannot show `_snap_held`, and cannot show the ship→target lag that `ShipTurnController` deliberately creates. It also swaps only on an explicit call, so every state change is an image swap. The synthesis the plan should consider: hardware image for the point, `_draw()` geometry on the *ship* for state — neither of which costs PixelLab budget if the ring is drawn rather than generated. | Cursor image **≤ 256×256**, "sizes of 128×128 or smaller are recommended"; web caps at 128×128. | [Godot docs — *Customizing the mouse cursor*](https://docs.godotengine.org/en/stable/tutorials/inputs/custom_mouse_cursor.html) |
| **5** | **A shipped top-down mouse-aimed space roguelite deliberately ships with *no* strafe and *no* reverse thrust, and sells both as upgrades.** Nova Drift's developer, in the game's FAQ: "Forgoing twin-stick controls is core to the design and the titular 'Drift' mechanic. Players must learn to set themselves in motion in anticipation of enemy actions, retaliating while drifting in low friction. The result is sort of a graceful fluidity … It also means that **positioning and facing matter**, which allows for unique abilities that the game leverages, such as ramming enemies head-on, burning enemies with your thrusters, or building around a front-facing shield barrier." Strafe and reverse thrust are mods (Strafe, Stabilization). The FAQ also concedes the cost: "this design decision does cause some friction from new players". | This is the direct answer to thread 3's temptation to "add strafe to make it dynamic". Strafe **deletes the meaning of facing**, and facing is what this project's whole open-space verb set rests on — the mouse-aim epic, the boost's nose-direction redirect, the 180° flip. Shipping strafe as an **engines-slot module** keeps the default identity intact, gives the module system content it can actually differentiate on, and matches `SLOT_MODULES[&"engines"]` exactly. The cost is that new players will keep asking for it, as Nova Drift's forum shows. | Nova Drift also ships a "Directional" alternate scheme where the stick sets a *target* facing rather than a turn rate — the same split this project's `&"mouse"` scheme already uses. | [Steam Community — *No strafe & reverse by default*, Nova Drift](https://steamcommunity.com/app/858210/discussions/0/6045572169619449901/) (read via `scripts/fetch-page.sh`). **Attribution caveat:** the passage is the developer's FAQ *reproduced verbatim by two independent posters* in that thread; the official FAQ page was not reachable from this container (see below), so this is a second-hand quote, corroborated but not primary. |
| **6** | **A dual-stick developer's post-mortem: the aim must never snap, the crosshair needs its own smoothing, and the camera should sit on a "sweet spot" between player and aim point.** "**the aim must never, EVER snap into position**" — the implementation keeps *two* directional values, a "target" direction straight from input and a "view" direction that interpolates toward it at a set rotation speed. The crosshair does the same: it "uses its own 'target' and 'view' positions with separate speed/acceleration values rather than snapping directly to input direction", and varies its distance from the player with input intensity between a minimum and maximum. The camera "follows a 'sweet spot' between player position and aiming position, with interpolation applied to all movements including sudden transitions like dashing". On dead zones: use a **radial** one — "find the vector combining both axes (normalized to 0-1) and then compare its length with your Deadzone" — because per-axis tests make diagonals sticky. On assists: invisible auto-aim "created problematic gaps between input and display", so visible snapping with a colour change was preferred. | The "two values, interpolate between them" pattern is *exactly* `ShipTurnController`'s `_target_angle` vs the returned rotation — so this source independently validates the existing architecture, and says the **reticle should be a third such pair**, not a rigid marker glued to the pointer. That costs another frame of apparent lag on top of finding 4's one, which argues for the smoothed element being the *state ring*, not the aim point. The "sweet spot" camera is the same recommendation as finding 2's Nuclear Throne row, from an independent practitioner. The radial-dead-zone note validates `mouse_dead_zone_px`'s existing `to_cursor.length() >= 48` test as already correct. | Auto-aim cone "~30 degrees"; crosshair distance has explicit min and max thresholds. | [Game Developer — *Everything I Learned About Dual-Stick Shooter Controls*](https://www.gamedeveloper.com/design/everything-i-learned-about-dual-stick-shooter-controls) |
| **7** | **Ridge Racer 7 ships the epic's exact boost proposal — as two *interchangeable* configurations of one gauge.** Standard nitrous is three discrete tanks: "up to three gauges at a time can be charged, but only one shot of nitrous can be used at a time", and RR6 added Double/Triple Nitrous where "using two or all three boosts will increase the engine power gained from using it, as well as its duration". **Flex Nitrous** is the other half: "The nitrous is **one long gauge that requires the nitrous button to be held** to utilize its power. If used for five seconds, the boost becomes more powerful but a little less long lasting than Standard. This nitrous type can allow for easy to chain Ultimate Charges, **even in small bursts of nitrous when tapping** the nitrous button." **Extended Type** re-partitions the *same pool*: "the same amount of nitrous provided by three tanks is instead split between two larger tanks … a single tank will last **1.5 times longer** than Standard." **Quad Nitrous** is the capacity upgrade: "an extra tank of nitrous is provided". In *Ridge Racer Slipstream*, "initially, only one tank is available upon purchasing a new car. As the nitrous system is upgraded, additional tanks become available." And on feedback: "when using triple nitrous in Ridge Racer 6, a **'tunnel vision' effect** will display across the entire screen and HUD", with per-tier colours (single red, double green, triple light blue). | This is a shipped, iterated-on answer to `1-context.md` open questions 6 and 5: **one gauge, one drain model, a partition count that the loadout changes** — not two components. The tanks and the long bar are the *same resource* rendered and spent differently, which is why Extended Type can re-slice it without changing the total. The cost the series itself documents is that the two feel different enough that track knowledge does not transfer ("may require the player to learn new places to activate it"), i.e. **a player who equips Boost Drive has to relearn the verb** — which is a design position to take deliberately, not a bug. The tunnel-vision effect is the shipped precedent for thread 3's FOV/speed-line ask, and is per-*tier*, which gives the segmented mode a free visual identity. | Standard **3 tanks**; Extended **2 tanks at 1.5× duration each**; Quad **4 tanks**; Slipstream starts at **1 tank** and upgrades add more. Flex's power ramp kicks in at **5 s** of continuous hold. | [Ridge Racer Wiki — *Nitrous*](https://ridgeracer.fandom.com/wiki/Nitrous) (recovered via `scripts/fetch-page.sh`; WebFetch returned 402) |
| **8** | **The same series shows how a hold-to-boost gets ruined: by adding spin-up.** *Ridge Racer 3D* nerfed Flex Nitrous so that "you can no longer get an immediate speed boost via activation. **You'd have to hold the nitrous button for a second for the speed boost to kick in.**" The wiki's verdict on the combined changes is that it became "nearly hard to strategize", and recommends Flex only because it "allow[s] more leniency for how the driver uses it". | Directly relevant to thread 4, and it cuts against the intuitive implementation. The natural way to write hold-to-boost — ramp the ceiling up while the key is held — *is* a spin-up, and a full second of it turns a movement verb into a commitment. The shipped-and-then-nerfed version says: make the **first instant** of the hold as strong as today's tap (`boost_exit_speed = 700` fires on frame one), and let the hold *sustain* rather than *build*. That also preserves the existing 180° flip, which is a one-frame redirect and would be destroyed by a ramp. | Spin-up delay that broke it: **1 second**. | [Ridge Racer Wiki — *Nitrous*](https://ridgeracer.fandom.com/wiki/Nitrous) (same page as finding 7) |
| **9** | **Breath of the Wild's stamina wheel is a continuous gauge whose *upgrade granularity* is discrete.** "Each Stamina Vessel received will increase the Stamina Wheel with an additional part of **one fifth of a wheel**. This means five Vessels are needed for each additional full Wheel", up to "10 Stamina Vessels, allowing him to have **three full Stamina Wheels**." The wheel itself drains continuously — sprint, swim, climb, glide all pull from it. | The relevant lesson for thread 4's "the bar's length is what the upgrade extends": a continuous bar **can** make an upgrade legible, but only if the increment is a *visible fraction* of the whole. BotW gets that by drawing fifths; a smooth 32 px bar that silently becomes 38 px communicates nothing, which is the strongest argument against a featureless long bar and for keeping tick marks even in the continuous tier. The cost of the BotW model is the inverse of Ridge Racer's: at 3 wheels the player has three *wholes*, so capacity and partition are locked together and cannot be tuned independently. | 1 vessel = **1/5 wheel**; 10 vessels max = **3 wheels**. This project's `boost_charge_count` range is **2–5**, which maps cleanly onto "bar units" without a save migration. | [Zelda Dungeon Wiki — *Stamina Wheel*](https://www.zeldadungeon.net/wiki/Stamina_Wheel) / [*Stamina Vessel*](https://www.zeldadungeon.net/wiki/Stamina_Vessel) |
| **10** | **A top-down space developer who removed drift and strafe on purpose, for a stated feel goal.** Space Pirates and Zombies 2's developer on ship handling: "in the end we are going for **huge battleships on the ocean feel, so broadsides and no strafing**, but there is all ahead full, which works quite well when you build for it." The dodge verb is the afterburner instead: "You do have an afterburner though and if you build your ship with engine speed in mind, it can be very effective at dodging." And on the turn as a skill expression: "If you choose your moment correctly and do a hard turn, you can bring all your guns down on the enemy. **You can't do it constantly, but when you do, it hits hard.**" | Second independent data point for finding 5, from a different genre position, and it names the replacement: when you refuse strafe, the **boost becomes the dodge**. That is exactly the role the Shift boost plays in this project, and it argues that thread 4 (hold-to-boost) is the *primary* answer to thread 3's "movement is not very fun" — not an addition to it. The cost the quote also implies: this only works if the boost is frequent enough to be a dodge, which is a direct argument for the continuous bar over two discrete charges. | None published. | [Steam Community — *Drift and Strafe*, Space Pirates and Zombies 2](https://steamcommunity.com/app/252470/discussions/0/1483235412212630089/) |

### Sources tried that yielded nothing

- **Nova Drift official FAQ** (`novadrift.io/faq`, `www.novadrift.io/faq`, `www.novadrift.io`) —
  `scripts/fetch-page.sh` returned non-zero for the first two and a page with no matching text for
  the third. Finding 5 is therefore the Steam-thread reproduction, labelled as such.
- **Game Developer — *2D Space Shooter Design Lessons*** — read in full; it covers visual effects
  and overheat-vs-cooldown weapon design and contains **no** discussion of inertia, drift, strafe,
  sense of speed or camera. Recorded here so the plan stage does not spend a fetch on it again.
- A general search for **peer-reviewed segmented-vs-continuous bar readability** surfaced only a
  ResearchGate pilot-study abstract and patent filings; nothing citable was actually read.
  Finding 9 is the substitute, and it is a design precedent, not evidence.

---

## What the findings imply for the plan

**1. Thread 2 has a small correct fix and a larger optional one, and they should be separate tasks.**
Findings 1 and 2 agree that the lead belongs on **motion**; `1-context.md` §4.1 shows the shipped
formula is already a 0.35 s lookahead pointed at the wrong vector. Replacing `facing` with the
velocity direction is a three-line change that kills the reported "behind the ship" / "mixes up and
down" bug outright. Everything else — dead zone (finding 2, Fez), lookahead smoothing (finding 1),
cursor bias (findings 2 and 6) — is a second, optional layer. **Do not bundle them**: if the small
fix ships first, the fly-test that follows tells the user whether the layer is even wanted.

**2. The user's own proposal is half right, and the research says which half.** They proposed
"extend it only when the ship is *rotated to* the cursor direction". Findings 1 and 2 say the
condition should be on **actually moving that way**, not on facing that way — which is the same
instinct (don't lead where you aren't going) expressed in the variable that the physics honours.
The plan should say this explicitly rather than silently substituting.

**3. Finding 3 makes a lead cap and a settings toggle non-optional.** A 280 px swing (39% of
viewport height) is precisely "two types of movement going on at once". Whatever formula wins,
`_LEAD_MAX` should come down from 140 and the whole effect should be disableable from the existing
settings panel.

**4. Thread 1's answer is probably a split, not a choice.** Finding 4 says the *point* should be a
hardware cursor; findings 2 and 6 say the *state* (dead zone, snap, steering-disabled, the lag
between target and hull) is information about the **ship**, and belongs drawn around the ship where
`BoostBar` and `OverheatBar` already live. Drawing it with `_draw()` avoids the PixelLab allowance,
the top-down-view rule and `test_entity_sprite_transparency.gd` in one move.

**5. Thread 3 should be answered by thread 4, plus modules — not by adding strafe to the default
ship.** Findings 5 and 10 are two independent shipped games that deliberately withheld strafe and
reverse thrust to protect the meaning of facing, and this project's entire open-space verb set
(mouse aim, nose-direction boost, 180° flip) rests on facing. Finding 10 names the replacement: the
boost *is* the dodge. Strafe/reverse belong in `SLOT_MODULES[&"engines"]` alongside `warp` and
`engine_boost`, where they are content rather than a default.

**6. Thread 4 is one component with a partition count, not two components.** Finding 7 is a shipped
system where the long held gauge and the three discrete tanks are the *same pool* rendered and spent
differently, and where a loadout item re-partitions it (Extended Type: same total, two tanks instead
of three) or extends it (Quad: a fourth tank). `BoostMeter.charges` is already a continuous float
with a whole-unit `try_spend()` on top, so this is the *smaller* change as well as the
better-precedented one: add a drain path and a segment count, keep `bind_progression` and the regen
pause.

**7. Do not build the hold as a ramp.** Finding 8 is a shipped game that added a 1 s spin-up to
exactly this verb and made it worse. The hold should deliver today's `boost_exit_speed` on frame one
and then *sustain* the ceiling while the key is down — which also leaves the existing one-frame 180°
redirect intact, so the flip and the hold can genuinely be one verb.

**8. Give the two tiers different colours and a screen effect, not just different maths.** Finding 7
ships per-tier nitrous colours and a tunnel-vision effect on the strongest tier. This project already
has the channels: `BoostBar._FILL_COLOR`, the `flame_boost` animation, `CameraShake.add()`, and the
speed-zoom already wired into `CameraDirector`. Finding 2's Celeste note (camera wobbles *in the
direction of* the dash) is the cheap, directional version of the same idea and is one call.

---

## Starting numbers for the plan

Everything here is a **starting default to be `@export`ed and fly-tested**, not a validated value.
Provenance is stated for each.

| Value | Suggestion | Where it comes from |
|---|---|---|
| Camera lookahead time | **0.30 s** of travel along `velocity.normalized()` | The shipped formula's own implied 0.35 s (`1-context.md` §4.1), trimmed slightly because finding 3 wants less automatic motion. |
| `_LEAD_MAX` cap | **90 px** (down from 140) | Caps the worst-case swing at 180 px = 25% of viewport height instead of 39%. Judgement call, anchored on finding 3. |
| Camera dead zone | **32 px** radius around the follow point | Finding 2 (Fez) + this project's own `ArenaCamera.deadzone_half_size = (40, 30)`. Radial, per finding 6. |
| Lookahead smoothing half-life | **0.20 s** | Finding 1 (smoothing exists and is separate from damping) + the sibling epic's 0.1–0.2 s player-vehicle band. |
| `CameraDirector.blend_speed` | **leave at 6.0** | Measured at a 0.116 s half-life (`1-context.md` §4.2) — already responsive; it is not the problem. |
| Cursor bias (if adopted) | **≤ 25%** of the ship→cursor vector, capped at the lead cap | Finding 2's Nuclear Throne rule, deliberately weak on the first pass because of the feedback-loop risk (`1-context.md` §6.3). |
| Reticle dead-zone ring radius | **48 px** | Must equal `ShipTurnController.mouse_dead_zone_px` exactly — read it, do not duplicate the constant. |
| Hardware cursor image size | **32×32** | Well inside finding 4's 128×128 recommendation; matches the project's 64×64 sprite idiom at HUD scale. |
| Boost drain rate (continuous tier) | **1.0 bar-unit/s** | Makes today's `boost_charge_count` of 2 into a 2-second continuous burn, comparable to the shipped one-shot's ~1.05 s above-cruise signature × 2 charges. Judgement call. |
| Boost hold speed | **700 px/s on frame one**, sustained | `boost_exit_speed` unchanged; finding 8 says do not ramp. |
| Regen delay / rate | **0.5 s / 0.7 units per s** | Unchanged from `BoostMeter`; finding 4 of the boost epic and `Overheat._SHOOT_GRACE`. |
| Segment count with Boost Drive | **3**, rising to 4 at full `boost_charge_count` | Finding 7 (Standard = 3 tanks, Quad = 4) and the epic's own "3-4". |
| 180° flip threshold (if conditional) | **> 120°** between `velocity` and facing | Judgement call. No source gives a number; ULTRAKILL (boost epic finding 1) uses no threshold at all, which remains the simpler option. |
| Boost camera kick | `CameraShake.add(0.25)` | Between the existing `0.35` hit and nothing; finding 2's Celeste note argues it should be *directional*, which `CameraShake` cannot currently do — noted as a possible small extension, not assumed. |

---

## Links

- [`1-context.md`](./1-context.md) — the codebase side, with the measured diagnosis of the camera bug.
- Sibling epics: [mouse aiming](../open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/),
  [boost](../open-space-boost-shift-burst-movement-on-an-upgradeable-boos/).
- [Unity — Cinemachine Position Composer](https://docs.unity3d.com/Packages/com.unity.cinemachine@3.1/manual/CinemachinePositionComposer.html)
- [Game Maker's Toolkit — How to Make a Good 2D Camera](https://gmtk.substack.com/p/how-to-make-a-good-2d-camera)
- [Game Accessibility Guidelines — controller vs camera movement](https://gameaccessibilityguidelines.com/avoid-or-provide-option-to-disable-any-difference-between-controller-movement-and-camera-movement/)
- [Godot — Customizing the mouse cursor](https://docs.godotengine.org/en/stable/tutorials/inputs/custom_mouse_cursor.html)
- [Game Developer — Everything I Learned About Dual-Stick Shooter Controls](https://www.gamedeveloper.com/design/everything-i-learned-about-dual-stick-shooter-controls)
- [Steam — Nova Drift, "No strafe & reverse by default"](https://steamcommunity.com/app/858210/discussions/0/6045572169619449901/)
- [Steam — Space Pirates and Zombies 2, "Drift and Strafe"](https://steamcommunity.com/app/252470/discussions/0/1483235412212630089/)
- [Ridge Racer Wiki — Nitrous](https://ridgeracer.fandom.com/wiki/Nitrous)
- [Zelda Dungeon Wiki — Stamina Wheel](https://www.zeldadungeon.net/wiki/Stamina_Wheel)
