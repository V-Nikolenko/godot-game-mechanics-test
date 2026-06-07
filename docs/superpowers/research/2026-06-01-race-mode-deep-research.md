# Assault Race Mode — Deep Research & Direction

**Date:** 2026-06-01
**Status:** Research / pre-design. No code changes proposed here yet — this document
exists to *choose a direction* before we touch the existing race code.
**Author:** Claude (commissioned deep-dive)

**Companion documents:**
- [Recommended architecture](2026-06-01-race-mode-architecture.md) — the world model, scene
  trees, reusable components, top-speed mechanic, level-building workflow, build sequence.
- [Bespoke racer AI](2026-06-01-race-ai-bespoke-racers.md) — per-racer FSM designs (Fang,
  Isac, Bogomol, Booster Gold, Reacher) with the "reusable mechanics, unique brains" rule.

---

## 0. TL;DR (read this first)

1. **The single biggest source of bugs and "hard to build a level" is the *relative-progress
   projection model*** — the abstract `progress` scalar that each object projects onto a
   screen-Y *relative to the live player position*, with band clamps and inverse-projection
   math in the AI. It splits the world into two coordinate systems that constantly have to be
   reconciled. **Recommendation: replace it with a single absolute "track space" + one global
   scroll offset.** This keeps the pinned camera and the parallax background *exactly as they
   are today*, but collapses two coordinate systems into one. Most of the current bug surface
   (band wind-up, dual-space dash detection, broken `body_entered`, magic px offsets tuned
   against `screen_y_scale`) disappears because it was *caused by* the projection seam.

2. **`racer_shield.gd` and the standalone `racer_base.gd` are duplication symptoms, not the
   disease.** The disease is that two shared components — `Shield` and `BaseEnemy`'s
   damage-reaction — hard-wire a player-only dependency (`ShipProgressionState`) and a
   player-only node (`HitFlashAnimationPlayer`). Fix the *components* to be configurable, and
   the duplicates delete themselves. (See [architecture §4](2026-06-01-race-mode-architecture.md#4-reusable-components-killing-the-duplication).)

3. **The current AI is the *opposite* of what you asked for.** `TacticRacerBehavior` +
   `RacerPersonality.tres` is a *single shared utility-AI brain* parameterised by a data
   resource — "a racer is a `.tres` of numbers." You explicitly want each racer to have its
   own states and logic. **Recommendation: per-racer FSMs** built on the engine's *existing*
   `State` / `StateMachine` pattern (already used by the player and `LightAssaultShip`), with
   shared *mechanics* (sensors, weapons, the longitudinal mover) as composition components but
   *bespoke decision logic* per racer. No shared brain, no personality resource.

4. **Your actual top-speed mechanic does not exist in the current code.** The spec you dislike
   models a *transient* dash boost + a *stamina* boost meter. You described a *persistent
   top-speed that you accumulate by hitting panels and bleed off from damage / not boosting* —
   a Wipeout/F-Zero "speed class" you build and defend. This is a different, better mechanic
   and it should be a first-class part of the model. (See
   [architecture §5](2026-06-01-race-mode-architecture.md#5-the-top-speed-mechanic-the-core-loop).)

5. **The ChatGPT plan is a generic circuit-racer checklist and its core architecture is a
   mismatch** for a vertical-scroll, straight-line, dead-race shmup. Useful as a *subsystem
   checklist*; wrong on the big calls (Path2D circuit, `NavigationAgent2D`, RigidBody impulse
   boosts, lap counting). Details in [§3](#3-review-of-the-chatgpt-research-document).

---

## 1. The design we are actually building (requirements, restated)

From your brief, distilled to testable requirements. I separate them from the old spec so we
don't inherit decisions you've rejected.

### 1.1 Core loop
- **R1.** Player flies *forward* along a **straight-line track** toward a finish line. No laps,
  no branching circuit. "Forward" = toward the top of the screen (the existing shmup framing).
- **R2.** The track is littered with **obstacles** that *slow down* whoever hits them (player
  and rivals alike) — and with **dash panels** that *push* whoever crosses them forward.
- **R3.** **Top speed is a resource you build and lose.** Crossing dash panels raises your top
  speed. Taking damage lowers it. *Not* crossing panels for a while bleeds it down. So the
  player must continuously (a) dodge incoming fire, (b) dodge/clear obstacles, (c) chase and
  hit panels — or fall behind.
- **R4.** **Every rival plays the same game.** Each AI racer also seeks panels to grow its own
  top speed, dodges hazards, and tries to win.

### 1.2 Combat / "dead race"
- **R5.** Rivals attack via **unique movement + firing patterns**. Named examples you gave:
  - a rival that **drops a bomb on the dash panel it just used** (denial),
  - a rival that **rams the ship in front** of it (player or other rival).
- **R6.** Damage is meaningful: it costs **top speed** (R3) and can **destroy** a ship at 0 HP.
  Killing rivals is a legitimate strategy. Player death = race failed.

### 1.3 AI authoring constraint (the one you were most emphatic about)
- **R7.** **Each racer has unique stats, movement, states, and logic.** Do **not** build one
  abstract racer brain and reuse it for all of them. A racer's "thinking" is bespoke.
- **R8.** This is **fully offline / single-player** — no netcode, no determinism-for-rollback
  constraints. Optimise for *interesting AI movement and decision-making*, not sync.

### 1.4 Engineering constraint
- **R9.** **Shared mechanics live in reusable global components, with no duplication.** The
  `racer_shield` copy-of-player-shield is the anti-pattern to eliminate. Shields, health,
  hurt/hit boxes, projectiles, thrusters, explosions are *one* implementation used by both
  player and rivals.

> **Tension to resolve up front (R7 vs R9):** "unique logic per racer" and "no duplicated
> components" seem to pull against each other. They don't, once you draw the line in the right
> place: **mechanics are shared, decisions are bespoke.** A racer reuses the *same* shield, the
> *same* gun, the *same* "is there a ship in front of me?" sensor — but *decides* what to do
> with them in its own FSM. This is the central architectural idea and it's spelled out in
> [the AI doc](2026-06-01-race-ai-bespoke-racers.md). The current code violates it in both directions:
> it duplicates a mechanic (shield) *and* shares a brain (tactic behavior). We want the exact
> opposite.

---

## 2. Review of the existing implementation

The code on disk has grown well past the "Phase 1" plan you linked. It is genuinely clever —
the relative-progress projection is an elegant idea — but it is *the wrong elegant idea* for
this game, and most of the pain traces back to it.

### 2.1 What exists today (inventory)

| File | Role |
|---|---|
| [`race_participant.gd`](../../../assault/scenes/race/race_participant.gd) | Per-ship longitudinal model: `progress`, throttle→speed, dash boost (timed mult + lunge), setback bleed, **stamina "boost meter"** |
| [`race_director.gd`](../../../assault/scenes/race/race_director.gd) | Standings sort, the **`project_y` seam** (progress→screen-Y relative to player), drives background scroll |
| [`racer_base.gd`](../../../assault/scenes/race/racer_base.gd) | Standalone `CharacterBody2D` racer; re-implements health/hurtbox/flash/death/thrusters; X from steering, Y from director |
| [`racer_steering.gd`](../../../assault/scenes/race/racer_steering.gd) | Per-frame group scans: obstacle avoidance + dash-seek + bullet-dodge → target X |
| [`racer_shield.gd`](../../../assault/scenes/race/racer_shield.gd) | **Duplicate** of `Shield`, overriding `_ready()` to skip `ShipProgressionState` |
| [`track_object.gd`](../../../assault/scenes/race/track_object.gd) / [`dash_panel.gd`](../../../assault/scenes/race/dash_panel.gd) | Track-anchored objects projected via the director |
| [`player_throttle_adapter.gd`](../../../assault/scenes/race/player_throttle_adapter.gd) | Player screen-Y → throttle; setback on damage |
| [`behaviors/racer_behavior.gd`](../../../assault/scenes/race/behaviors/racer_behavior.gd) | Brain base (refs + defaults) |
| [`behaviors/tactic_racer_behavior.gd`](../../../assault/scenes/race/behaviors/tactic_racer_behavior.gd) | **Shared utility-AI FSM** (Cruise/Flank/Attack/Block/Evade/GrabPanel) driven by a personality resource |
| [`behaviors/booster_gold_behavior.gd`](../../../assault/scenes/race/behaviors/booster_gold_behavior.gd) | `extends TacticRacerBehavior`; ram skill |
| [`behaviors/generic_racer_behavior.gd`](../../../assault/scenes/race/behaviors/generic_racer_behavior.gd) | Minimal timer-fire brain |
| [`ai/racer_personality.gd`](../../../assault/scenes/race/ai/racer_personality.gd) + `ai/personalities/*.tres` | **Data-driven racer "identities"** |

### 2.2 The root cause: the relative-progress projection model

Everything in the race lives in an **abstract `progress` scalar**, and the on-screen Y is
*derived every frame relative to the player*:

```gdscript
# race_director.gd
func project_y(track_progress, clamp_to_band):
    var raw = (_player.progress - track_progress) * screen_y_scale
    if clamp_to_band: raw = clampf(raw, -max_offset_y, max_offset_y)
    return player_anchor_y + raw
```

The player is **pinned** at a constant `player_anchor_y` regardless of its own speed; rivals
and track objects float around it. This one decision spawns the whole bug family:

1. **Two coordinate systems that must be constantly reconciled.** Gameplay logic lives in
   `progress` (boosts, setbacks, standings), but *perception and steering* live in screen
   pixels (`global_position`). Every interaction across the seam is a conversion, and every
   conversion is tuned against `screen_y_scale`. The AI literally has to invert the projection
   to choose a throttle:

   ```gdscript
   # tactic_racer_behavior.gd — solving the projection backwards to avoid the band clamp
   var desired_delta = (desired_screen_y - director.player_anchor_y) / scale
   var err = (_player_part.progress - participant.progress) - desired_delta
   return clampf(cruise_throttle + kp * err, 0.0, 1.0)
   ```
   That comment — *"so it never winds up against the director's screen-Y band clamp"* — is the
   model admitting it fights itself.

2. **Broken physics → manual everything.** `racer_base` is a `CharacterBody2D` but moves by
   directly assigning `global_position` (no `move_and_slide`). So `Area2D.body_entered` never
   fires for racers, which is why `DashPanel` had to abandon signals for a **geometric scan
   loop**, and why `BoosterGold` does its ram damage with a **manual distance scan** that
   emits `received_damage` by hand. The engine's collision system is being bypassed and
   re-implemented in GDScript, piecemeal, per feature.

3. **Magic numbers coupled to the projection scale.** `_reachable_panel()` uses `+120.0` px;
   `DashPanel.trigger_half_h = 90`; `evade_screen_y = 120`. These are all implicitly tuned
   against `screen_y_scale` and `player_anchor_y`. Change the projection and the AI silently
   mis-detects panels and mis-aims. This is *exactly* why "building a race level is hard": the
   level designer is tuning against an invisible coordinate transform, not placing objects.

4. **Per-frame O(n²) scans.** `racer_steering` and the behaviors call
   `get_tree().get_nodes_in_group(...)` for asteroids, mines, dash panels, *and* iterate
   bullet areas, *for every racer, every physics frame*. `RaceDirector` re-sorts standings
   every frame and `get_ahead`/`get_behind` each re-sort again. Fine for 3 racers; a smell
   that will bite as the field or hazard count grows.

5. **The relative field "breathes."** Because Y is `player.progress - obj.progress`, slowing
   down makes the *entire* rival field slide down the screen toward you (and vice-versa). It's
   disorienting and it forced the `max_offset_y` clamp, which in turn created the wind-up the
   AI fights in (1). 

**None of these are bad code per se — they're the unavoidable consequences of choosing a
relative, dual-coordinate model.** The fix is not to patch them; it's to remove the seam.

### 2.3 The duplication symptoms

- **`racer_shield.gd`** exists *only* because `Shield._ready()` hard-calls
  `ShipProgressionState.permanent_shield_count` (a player-only autoload). The subclass
  copy-pastes the regen-timer setup to avoid that one line — so any change to `Shield._ready()`
  now silently drifts from the racer copy. The right fix is one configurable component
  (architecture §4), after which `racer_shield` is deleted.
- **`racer_base.gd`** re-implements what `BaseEnemy` already does (health wiring, hurtbox,
  hit-flash, death + explosion, contact hitbox) because `BaseEnemy` hard-wires a
  `HitFlashAnimationPlayer` node and `ShipConfig`. Two shared concerns (damage reaction; the
  "I am a destructible ship" plumbing) are trapped inside `BaseEnemy`'s inheritance. Extract
  them and racers reuse them by composition.
- **`Shield._emit_snapshot()` prints every snapshot.** With N racers each owning a shield,
  that's console spam every shield event. Symptomatic of a component that wasn't designed to be
  instanced many times.

### 2.4 The AI is shared-brain, not bespoke (the R7 violation)

`TacticRacerBehavior` is a single 256-line utility-AI: it scores five "beats" each frame, picks
the argmax with a stay-bias, and a *shared* actuator realises the chosen target. The *only*
thing that differs between "Hawk", "Jackal", "Warden", etc. is a `RacerPersonality.tres` of
weights and offsets. `BoosterGoldBehavior` then `extends` that brain to bolt on a ram.

That is precisely the "abstract class reused for all racers" you rejected. It has real
downsides for *this* game:
- A racer's identity is a spreadsheet of weights, which is hard to make *read* as a distinct
  personality in motion. Utility AIs tend toward a samey "hover near the player and occasionally
  do a thing" feel.
- Signature behaviors that don't fit the beat vocabulary (drop a bomb *on the panel you just
  used*; sit on a target's tail and ram) have to be wedged in by subclassing the shared brain,
  re-deriving its private state. `BoosterGold` re-implements caching, firing, and the realise
  loop because it can't cleanly reuse them.
- It couples every racer to the projection inverse-math in `_throttle_for`.

We keep none of this. We keep the *good* primitives it contains — the idea of sensors, a
weave oscillator, lead-the-target aiming, a panel-seek — but as **shared mechanics each racer's
own FSM can call**, not as a brain they inherit.

### 2.5 What is genuinely worth keeping

Not everything should be thrown out. Salvage:
- **The `RaceParticipant` *idea*** — a per-ship component that owns the longitudinal model
  (position along the track + speed). We keep the concept, simplify the model it implements
  (absolute, not relative), and *drop* the stamina "boost meter" in favour of the real
  top-speed mechanic (R3).
- **The `RaceDirector` *idea*** — one coordinator that owns standings and the finish line. We
  keep it; it gets *simpler* (no projection seam to own).
- **`TrackObject` / `DashPanel` as "things placed at a track position."** The concept is right;
  in the new model "track position" is a real world coordinate, so projection vanishes.
- **The existing `State` / `StateMachine`** ([`global/statemachine/`](../../../global/statemachine/state.gd))
  — already used by the player and `LightAssaultShip`. This is the backbone for bespoke racer
  brains.
- **The existing enemy patterns you literally described:** [`RamShip`](../../../assault/scenes/enemies/ram_ship/ram_ship.gd)
  (ram), [`Bomber`](../../../assault/scenes/enemies/bomber/bomber.gd) + `bomb.tscn` (drop
  bombs on a timer). The racer signatures map onto these almost directly.
- **The `WaveBuilder` / `WaveManager`** spawn pipeline — though for a *placed* track we'll want
  a level-authoring path too (architecture §6).

---

## 3. Review of the ChatGPT research document

You asked me to sanity-check `space_racing_plan_english.md`. Honest assessment: **it's a
competent generic checklist for a *circuit* racing game, and a poor fit for the game you're
actually building.** It's useful for *naming subsystems you'll need*; it's misleading on every
major architectural call.

### 3.1 Where it's wrong for this project

| ChatGPT recommendation | Why it doesn't fit | What you actually have / want |
|---|---|---|
| **Free movement + hidden Path2D for AI** | Implies a 2-D circuit with curves; your track is a **straight line** with a fixed forward axis | A 1-D longitudinal model + lateral lane steering. No path to follow. |
| **`NavigationAgent2D` for AI** | Pathfinding solves *mazes*; a straight corridor has nothing to path-find. It would add a nav mesh, agents, and avoidance you don't need | **Local steering** (lookahead + lateral nudge) — which you already have in `racer_steering` |
| **Lap counting via `Area2D` checkpoints; HUD lap/best-lap** | No laps. One straight run to a finish line | Single finish line; placement (1st…Nth) is the result |
| **Boost = `apply_central_impulse(dir * force)`** | That's a `RigidBody2D` API; your ships are `CharacterBody2D`. Impulse-based boost on a kinematic body does nothing | Boost = raise the ship's *top-speed*/forward velocity directly (R3) |
| **`RigidBody2D` for physical obstacles** | Physics-driven debris fights a scripted-scroll world and a kinematic player | Obstacles are `Area2D`/`StaticBody2D` with scripted motion, like your existing asteroids/lasers |
| **Steering by `rotation += rot_input`** | A top/forward-locked shmup ship doesn't rotate to steer; it strafes laterally | Lateral strafe (X), forward speed (longitudinal) |
| **`ParallaxBackground` shader-scroll example** | Fine in isolation, but you already have a richer multi-layer [`Level1Background`](../../../assault/scenes/levels/edelia/1/level_1_background.gd) with a `set_throttle_scroll` seam | Reuse your background controller |

### 3.2 Where it's fine (use it as a checklist)

The *enumeration* of subsystems is reasonable and worth keeping as a coverage list: boost
panels, obstacle taxonomy (static / destructible / moving / enemy), separate collision layers
per role, a phased roadmap, parallax layering, and the "additional ideas" (risk/reward
shortcuts, multiple AI personalities, power-ups). None of that is novel, but it's a fair
checklist to make sure we didn't forget a system. Its **collision-layer separation** advice
matches what your project already does.

### 3.3 Verdict

Treat it as a *table of contents*, not an architecture. Every concrete code snippet in it
assumes a different genre (physics-circuit racer) than yours (kinematic vertical-scroll
straight-line dead-race). Your *existing* engine conventions — components, FSM, wave spawner,
scrolling background — are the right substrate; the ChatGPT doc would pull you off them.

---

## 4. The implementation approaches (survey + recommendation)

There are four credible ways to structure a "ships race forward along a straight track" game in
Godot. I evaluate each against *this* project's constraints (pinned-camera shmup foundation,
straight track, offline, bespoke AI, no duplication).

### Approach A — Relative-progress projection (the current code)

One abstract `progress` per ship; on-screen Y projected *relative to the live player*; pinned
camera; scrolling background sells motion.

- ✅ Camera and background never move; perfectly preserves the shmup feel.
- ✅ "Infinite" track for free (no level length to stream).
- ❌ Dual coordinate system → the entire bug family in §2.2.
- ❌ Level-building = scheduling camera-relative waves + tuning projection constants (your
  stated pain).
- ❌ AI must invert the projection; physics/signals don't work normally.

### Approach B — Absolute *track space* + single global scroll (RECOMMENDED)

Keep the pinned camera **and** the scrolling background. But give every race object **one real
longitudinal coordinate `track_y`** in a shared track space, and render with **one global
`scroll_offset`**: `screen_y = track_y - scroll_offset`. The player is a real object in this
space too; its `track_y` velocity is its speed; its progress *is* its `track_y`. Standings =
sort by `track_y`. There is exactly **one** coordinate and **one** projection (a subtraction),
shared by everything, with no per-object relative term and no band clamp.

- ✅ **One coordinate system.** Gameplay and perception agree. No inverse-projection in the AI:
  a racer that wants to be ahead just increases its `track_y` speed.
- ✅ **Keeps the pinned camera + parallax background** unchanged (the scroll offset drives the
  same `set_throttle_scroll` you already have).
- ✅ **Level-building becomes "place objects at a `track_y`"** — a real, linear, designable
  axis. A panel at `track_y = 5000` is unambiguous and independent of player position.
- ✅ Real movement and real `Area2D` overlaps work again (the player and ships move in screen
  space derived from `track_y`; collisions and `body_entered` behave normally for hazards).
- ✅ The whole field no longer "breathes" relative to the player.
- ⚠️ You now have a finite track length to author (a feature, not a bug, for a race with a
  finish line) and must cull/spawn objects by `track_y` window (you already cull by screen-Y).
- ⚠️ Slightly different *feel*: the player's ship now sits higher on screen when fast and lower
  when slow (its screen position reflects speed). Most racers consider this *good* feedback;
  confirm you like it. (You can damp it so the ship only drifts within a band.)

> **Why B over a literal moving Camera2D:** A real scrolling camera over a long world-space
> level is the textbook approach and is *also* fine — but it would mean re-pointing your
> background system at a moving camera and authoring a physically long level. Approach B gets
> the same single-coordinate simplicity while leaving the camera pinned and the background
> system literally untouched. It's the smallest change that removes the root cause. If you ever
> want curved tracks or a free-roaming camera, you'd graduate to a real moving camera — but for
> a straight-line race, B is strictly simpler.

### Approach C — `Path2D` + `PathFollow2D` rail

Lay a `Path2D` down the track; each ship is a `PathFollow2D` whose `progress` advances by
speed, with a lateral `h_offset` for strafing. Camera follows the lead PathFollow.

- ✅ Trivially supports *curved* tracks and perfectly-defined "forward."
- ✅ Standings = compare `progress`.
- ❌ Overkill for a *straight* line (a path with two points is just an axis — i.e. Approach B
  with extra machinery).
- ❌ Lateral combat/dodging in `h_offset` space is more awkward than real X.
- ❌ Still needs a moving camera + streamed background.

Keep C in your back pocket *only if* "straight-line" later becomes "mostly-straight with gentle
curves." For a literal straight line it's strictly more complex than B.

### Approach D — Hybrid scalar + decorative visuals (variant of A)

Like A, but the relative projection is hidden and ships are positioned by a rubber-band visual
layer. This is essentially what the current code is creeping toward (the `transition_smooth`,
the lunge bleed, the boost meter). It accumulates *more* special-cased smoothing on top of the
seam rather than removing it. Not recommended — it's A with more epicycles.

### Recommendation

**Adopt Approach B (absolute track space + single global scroll).** It is the only option that
*removes* the root cause (the dual-coordinate seam) while *preserving* your two hard constraints
(pinned camera, existing parallax background). It makes levels authorable, makes physics/signals
work again, and — critically — gives the AI the *same* mental model as the player, which is what
makes bespoke racer brains (the AI doc) clean to write.

A full description of the track-space math, scene trees, and migration is in
[the architecture doc](2026-06-01-race-mode-architecture.md).

---

## 5. How the AI should be structured (summary; full design in the AI doc)

The R7 constraint ("unique stats, movement, states, logic; no abstract racer brain") and the R9
constraint ("no duplicated components") are reconciled by one rule:

> **Mechanics are shared components. Decisions are bespoke FSMs.**

- **Shared, reused by every racer (composition):** the longitudinal mover (`RaceParticipant`),
  a lateral mover, the shield/health/hurtbox/hitbox, the bullet/weapon firing, the explosion,
  and a small kit of **stateless sensors** (`ship_ahead()`, `incoming_threat()`,
  `nearest_panel_ahead()`, `gap_to(participant)`). None of these decide anything; they perceive
  and act on command.
- **Bespoke, written once per racer (no inheritance of decisions):** each named racer is its
  own scene with its own `StateMachine` and its own `State` nodes that encode *its* logic.
  Fang's states are not Bogomol's states. There is **no `TacticRacerBehavior`** and **no
  `RacerPersonality.tres`**. A racer's "stats" are plain `@export`s on its own script.

This mirrors exactly how [`LightAssaultShip`](../../../assault/scenes/enemies/light_assault_ship/light_assault_ship.gd)
already composes shared parts (`Health`, `BulletPool`, `AttackController`) but owns its
behavior in [`states/`](../../../assault/scenes/enemies/light_assault_ship/states/approach_state.gd).
We're applying the pattern the codebase already endorses — the race code is the outlier that
went data-driven.

The [AI doc](2026-06-01-race-ai-bespoke-racers.md) gives each of the five named racers a full
FSM (states, transitions, signature ability) and shows how the "bomb on the panel" and "ram the
ship in front" patterns reuse `Bomber`/`bomb` and `RamShip` mechanics.

---

## 6. Open decisions (need your call before we write the implementation plan)

These are the forks where your preference changes the design. I have a recommendation for each;
none is blocking the research, but the *plan* should lock them.

1. **World model — confirm Approach B.** Are you happy to move to absolute track-space (player
   ship drifts up/down with speed, levels authored along a real axis), keeping the pinned
   camera and parallax background? *My strong recommendation: yes.* The alternative is staying
   on the relative-progress model and paying the §2.2 tax forever.

2. **Player ship vertical feel.** In B the player's *screen* Y can either (a) directly equal its
   speed (rides high when fast — strong feedback, more vertical travel) or (b) be damped to a
   small band around centre while a separate readout shows speed. Which feel do you want?

3. **Top-speed mechanic numbers.** R3 says panels raise top speed and damage/idleness lower it.
   We need: starting top speed, per-panel gain, decay-per-second when not boosting, loss-per-hit,
   and a cap. I'll propose defaults in the plan; flag if you have target race durations (e.g.
   "60–90 s").

4. **Track authoring path.** Two ways to place panels/obstacles along `track_y`: (a) keep using
   `WaveBuilder`/`WaveManager` with `track_y`-based spawn timing, or (b) author a literal long
   scene / `TileMapLayer` you can see and edit in the editor. *Recommendation: (b) for the
   static furniture (panels, walls, asteroid fields) so a level is visible and designable, with
   `WaveManager` retained for timed dynamic spawns.* This is the direct answer to "building a
   race level is hard."

5. **Scope of the rewrite.** Do you want to (a) *refactor in place* (keep `race/` files, swap
   the model underneath), or (b) start a clean `race/` v2 alongside and port the good parts? The
   §2.5 salvage list is small enough that (b) is cleaner and lower-risk; (a) churns every file.

6. **Number and roster of racers for the first playable.** The AI doc designs all five, but the
   first vertical slice probably wants 2–3 *distinct* brains (e.g. Fang the ram + Bogomol the
   mine-layer + one pace-setter) to prove the "bespoke FSM" pattern before authoring the rest.

---

## 7. Where to go next

- Read [the architecture doc](2026-06-01-race-mode-architecture.md) for the concrete track-space
  model, scene trees, the component de-duplication, the top-speed mechanic, and a phased build
  sequence (with `godot-prompter:*` skill annotations per task).
- Read [the AI doc](2026-06-01-race-ai-bespoke-racers.md) for the per-racer FSM designs.
- Then answer the §6 decisions and I'll turn this into an executable implementation plan under
  `docs/superpowers/plans/`.
