# Assault Race Mode — Recommended Architecture (Track-Space Model)

**Date:** 2026-06-01
**Status:** Research / proposed design.
**Reads with:** [Deep research & direction](2026-06-01-race-mode-deep-research.md) ·
[Bespoke racer AI](2026-06-01-race-ai-bespoke-racers.md)

This document specifies **Approach B** from the research doc: an *absolute track-space* model
with a single global scroll offset, keeping the pinned camera and parallax background. It covers
the model math, scene trees, signal maps, the component de-duplication, the top-speed mechanic,
the level-authoring workflow, collision layers, and a phased build sequence.

> Skills to invoke during implementation (per task, noted inline):
> `godot-prompter:state-machine`, `godot-prompter:component-system`,
> `godot-prompter:ai-navigation`, `godot-prompter:scene-organization`,
> `godot-prompter:resource-pattern`, `godot-prompter:2d-essentials`,
> `godot-prompter:hud-system`, `godot-prompter:physics-system`.

---

## 1. The track-space model (the one idea that fixes everything)

### 1.1 Coordinates

There is **one** longitudinal axis, `track_y`, measured in world units, increasing **toward the
finish line**. Larger `track_y` = further along the track = "more ahead."

There is **one** render transform, owned by a single `RaceWorld` node:

```
screen_y(object) = base_screen_y - (object.track_y - world.scroll_offset)
```

- `world.scroll_offset` is "how far the camera viewport has advanced down the track." It is
  driven by the **player's** `track_y` so the player stays in a comfortable screen band.
- `base_screen_y` is the screen Y the player rests at (e.g. ~520 px, lower third).

Because *every* object uses the *same* `scroll_offset` and the *same* formula, there is no
per-object relative term, no `player_anchor`, no band clamp, no inverse projection. A leader is
simply at a higher `track_y`; it renders higher on screen until it leaves the top, exactly like
a real object passing the camera.

> This is mathematically a *camera*: `scroll_offset` is the camera's track position and the
> formula is "world minus camera." We implement it as a scripted offset (not a moving
> `Camera2D`) purely so the existing pinned `ArenaCamera` and `Level1Background` keep working
> untouched. If you later want a literal moving camera, `RaceWorld` is the single seam to swap.

### 1.2 What each value *is* now (vs the old model)

| Concept | Old (relative-progress) | New (track-space) |
|---|---|---|
| Position along track | abstract `progress` per ship | real `track_y` per ship |
| On-screen Y | `anchor + (player.progress − obj.progress)·scale`, clamped | `base − (obj.track_y − scroll_offset)` |
| Player screen-Y | **pinned** at `player_anchor_y` | derived from player `track_y` (sits in a band) |
| "Ahead of me" | compare `progress` | compare `track_y` |
| Forward speed | `lerp(min,max,throttle)·boost·meter` | `current_speed` (see top-speed mechanic §5) |
| Camera | pinned | pinned (`scroll_offset` is the virtual camera) |
| Background scroll | `lerp(bg_min,bg_max,throttle)·boost` | driven by `world_scroll_speed` = d(scroll_offset)/dt |

### 1.3 The player is a normal object

Crucial difference from the old model: the **player is just another `track_y` mover**. Its
forward speed advances its `track_y`; `RaceWorld` keeps `scroll_offset` chasing the player so the
player renders inside a screen band. The player's *lateral* input is real X movement (unchanged
from the shmup). Its *forward* speed is the top-speed mechanic (§5), not a position-as-throttle
inversion.

This means **the player and every AI racer share one mover** (`RaceParticipant`) and one
perception space. That symmetry is what makes the bespoke AI (AI doc) clean — a racer reasons
about `track_y` and screen-X exactly like it reasons about the player.

### 1.4 Why this deletes the bug family

- No dual coordinate → no inverse-projection in AI (`_throttle_for` disappears).
- Ships move in real screen space (derived once per frame from `track_y`) → real `Area2D`
  overlaps and `body_entered` work → `DashPanel`'s manual scan and BoosterGold's manual ram
  scan can become real collisions (optional; scanning is still fine for a few objects).
- No `screen_y_scale` → the magic px offsets that were tuned against it become plain world
  distances a designer can see.
- No relative "breathing" field → no `max_offset_y` clamp → no wind-up.

---

## 2. Node / scene architecture

### 2.1 Race level scene tree

```
RaceLevel1 (Node2D)
├── Level1Background (reused, group "background")     # untouched; driven by RaceWorld scroll speed
├── ArenaCamera (Camera2D, pinned)                    # unchanged
├── RaceWorld (Node, group "race_world")              # owns scroll_offset; the ONE projection seam
├── Track (Node2D)                                    # authored static furniture (see §6)
│   ├── DashPanel (Area2D)   @ track_y = 1200, x = 420
│   ├── DashPanel            @ track_y = 1900, x = 900
│   ├── LaserWall            @ track_y = 2600
│   ├── AsteroidField        @ track_y = 3000 …
│   └── FinishLine (Area2D)  @ track_y = track_length
├── RaceDirector (Node, group "race_director")        # standings, finish/fail, results
├── Racers (Node2D)                                   # AI ships spawned here
│   ├── Fang (RaceShip)
│   ├── Bogomol (RaceShip)
│   └── …
├── WaveManager (Node)                                # optional timed dynamic spawns
├── RaceHUD (CanvasLayer)
├── RaceLevelConfig (Node)                            # boot: attach player race comps, wire HUD
└── PlayerFighter (instance, group "player")          # shared player, unmodified scene
```

### 2.2 A race ship (player *and* AI share the same skeleton)

The player keeps its own scene; at race start `RaceLevelConfig` *adds* the race components to it.
AI racers are authored scenes that contain the same components plus a bespoke brain. The shared
skeleton:

```
RaceShip (CharacterBody2D)              # AI racer root; player gets these added at runtime
├── Sprite2D / AnimatedSprite2D         # unique per racer
├── CollisionShape2D
├── HurtBox (Area2D, HurtBox)           # SHARED component — takes damage
├── HitBox (Area2D, HitBox)             # SHARED — contact damage
├── Health (Node, Health)               # SHARED component
├── Shield (Node, Shield)               # SHARED component (de-duplicated, §4)
├── BubbleShield (instance)             # SHARED visual
├── RaceParticipant (Node)              # SHARED — owns track_y + speed + top-speed
├── DamageReaction (Node)               # SHARED — flash + explosion + setback-on-hit (§4.2)
├── Thruster markers (LeftEngine/RightEngine) → ThrusterEffect  # SHARED
├── Sensors (Node)                      # SHARED stateless perception kit (AI doc §3)
├── Weapon (Node)                       # SHARED firing component (AI doc §3)
└── Brain (StateMachine)                # BESPOKE per racer — its own State children
    ├── <RacerName>SomeState (State)
    └── …
```

The only nodes that differ between racers are the **Sprite** and the **Brain** subtree (and the
`@export` stat values). Everything else is the same component, instanced. That is R9 satisfied.

### 2.3 Responsibilities

| Node | Owns | Single responsibility |
|---|---|---|
| `RaceWorld` | `scroll_offset`, `world_scroll_speed` | The one projection: advance scroll to follow the player; expose `screen_y_for(track_y)` |
| `RaceDirector` | `participants[]`, `track_length`, results | Standings (sorted by `track_y`), finish line, fail-on-player-death, neighbour queries |
| `RaceParticipant` | `track_y`, `current_speed`, `top_speed` | The longitudinal mover + the top-speed resource (§5). No projection, no AI |
| `RaceShip` | its transform | Each frame: ask Brain for lateral intent + forward intent; set X from lateral mover, Y from `RaceWorld.screen_y_for(participant.track_y)` |
| `Sensors` | nothing (stateless) | Answer perception queries (`ship_ahead`, `incoming_threat`, `nearest_panel_ahead`, `gap_to`) |
| `Weapon` | a `BulletPool` | `fire(direction, damage, speed)` / `fire_at(target)` |
| `DamageReaction` | flash tween, explosion | React to `HurtBox.received_damage` uniformly (shield→health, flash, setback, death) |
| `Brain` (`StateMachine`) | current `State` | **Bespoke** decisions; writes intents the `RaceShip` reads |

### 2.4 Signal map

| Signal | Source | Consumer | Payload | Purpose |
|---|---|---|---|---|
| `received_damage(dmg)` | `HurtBox` | `DamageReaction` | `int` | Uniform hit handling |
| `amount_changed(cur)` | `Health` | `DamageReaction`, `RaceDirector` (player only) | `int` | Death → eliminate / fail |
| `shield_state_changed(snap)` | `Shield` | `BubbleShield`, HUD | `Dictionary` | Shield visuals |
| `top_speed_changed(value, max)` | `RaceParticipant` | HUD (player), thruster tint | `float,float` | Speed-class readout |
| `panel_boosted` | `RaceParticipant` | thruster/VFX | — | Boost flare |
| `finished(participant)` | `RaceParticipant` | `RaceDirector` | `RaceParticipant` | Record placement |
| `standings_changed(order)` | `RaceDirector` | `RaceHUD` | `Array` | Live placement list |
| `race_finished(results)` / `race_failed` | `RaceDirector` | `RaceHUD`, `RaceLevelConfig` | `Array` / — | End flow |

Communication rule (matches the brainstorming skill): **signals up** (HurtBox→reaction,
Participant→director), **method calls down** (Brain→Weapon.fire, Ship→Participant.set_speed),
**group lookup sideways** (find `RaceDirector`/`RaceWorld` via group once on ready, cache it).

---

## 3. The frame loop (who runs in what order)

Determinism isn't required (offline), but a stable order avoids 1-frame jitter:

1. **Brains** (`StateMachine._process` / `_physics_process`): each racer's current `State`
   reads sensors + director, writes `desired_lateral_x` and `forward_intent` (e.g. "floor it",
   "coast", "match player") onto its `RaceShip` (or directly onto its `RaceParticipant`).
2. **`RaceParticipant._physics_process`**: integrate `top_speed` (decay), compute
   `current_speed`, advance `track_y += current_speed·delta`; apply panel boosts / setbacks
   (bled smoothly). Emit `finished` on crossing `track_length`.
3. **`RaceWorld._process`**: move `scroll_offset` toward the player's `track_y` (so the player
   sits at `base_screen_y`), compute `world_scroll_speed`, push it to the background via the
   existing `set_throttle_scroll`.
4. **`RaceShip._physics_process`**: `x = lateral_mover(desired_lateral_x)`,
   `y = RaceWorld.screen_y_for(participant.track_y)`, assign `global_position`.
5. **`RaceDirector._process`**: re-sort standings **only when needed** (e.g. every K frames or
   on a `track_y` cross event), emit `standings_changed` on change.

> Optimisation note vs current code: standings sort and neighbour queries should be computed
> **once per frame in the director** and *read* by everyone, not recomputed inside each racer's
> `get_ahead`/`get_behind`. Sensors should likewise be **pull, cached per frame**.

---

## 4. Reusable components: killing the duplication

This section is the direct answer to R9 and to "global components must be reusable, not
duplicated like `racer_shield`."

### 4.1 `Shield` — make the charge source injectable (delete `racer_shield.gd`)

**Problem:** `Shield._ready()` hard-calls `ShipProgressionState.permanent_shield_count`, a
player-only autoload, forcing `RacerShield` to override `_ready()` and copy the timer setup.

**Fix — one component, configurable source.** Two clean options:

- **Option 1 (recommended): export the initial charges + an opt-in progression bind.**
  ```gdscript
  # shield_component.gd
  @export var permanent_charges: int = 1          ## used when bind_progression == false
  @export var bind_progression: bool = false      ## player sets true in its scene

  func _ready() -> void:
      if bind_progression:
          permanent_max = ShipProgressionState.permanent_shield_count
          ShipProgressionState.permanent_shield_count_changed.connect(_on_progression_changed)
      else:
          permanent_max = permanent_charges
      permanent_active = permanent_max
      _setup_regen_timer()     ## extracted helper, called by both paths
      _emit_snapshot()
  ```
  Player scene: `bind_progression = true`. Racer scene: `bind_progression = false,
  permanent_charges = 2`. **`racer_shield.gd` is deleted.** No subclass, no copy-pasted timer.

- **Option 2: a tiny `ProgressionShieldBinder` node** that lives only on the player and pushes
  the progression count into a plain `Shield`. Keeps `Shield` zero-dependency. Slightly more
  nodes; also valid.

Either way, also **remove the `print()` in `_emit_snapshot()`** (or gate it behind a debug
flag) — it spams once per shield event per ship.

### 4.2 Extract `DamageReaction` (so racers stop re-implementing `BaseEnemy`)

**Problem:** `racer_base.gd` re-implements health wiring, hurtbox masking, hit-flash, death +
explosion because `BaseEnemy` hard-wires a `HitFlashAnimationPlayer` node and `ShipConfig`.

**Fix — pull the shared "destructible ship reaction" into a component** used by *both*
`BaseEnemy` and race ships:

```
DamageReaction (Node)
  setup(health: Health, shield: Shield, hurt_box: HurtBox, sprite: CanvasItem)
  # On hurt_box.received_damage:
  #   apply setback hook (optional) → shield.consume_one() ? return : health.decrease(dmg)
  #   flash sprite (modulate tween — no AnimationPlayer dependency)
  # On health.amount_changed == 0:
  #   explosion.explode(); emit died; queue_free()
```

- Hit-flash becomes a **modulate tween** (works with any sprite; no required
  `HitFlashAnimationPlayer` node). `BaseEnemy` can keep using its AnimationPlayer if present, or
  switch to this — either way the *racer* uses the component and stops duplicating.
- `BaseEnemy` optionally composes `DamageReaction` too, so there is **one** death/explosion path
  project-wide.
- Result: a race ship does **not** need to extend `BaseEnemy` *or* re-implement it. It composes
  `Health` + `Shield` + `HurtBox` + `DamageReaction` like every other entity. `racer_base.gd`
  shrinks to "wire components, read brain intents, set transform."

### 4.3 Component placement (global vs assault)

Per the brainstorming skill's reuse rule and your "global components must be reusable":

- **`global/components/`** (truly cross-mode): `Shield`, `Health`, `HurtBox`, `HitBox`,
  `BulletPool`, `ThrusterEffect`, `ExplosionEffect`, `HitEffect`, and the new
  `DamageReaction`. These already mostly live there — the fix is making `Shield`
  mode-agnostic (§4.1) so it *truly* is global.
- **`assault/scenes/race/components/`** (race-specific but racer-agnostic): `RaceParticipant`,
  `Sensors`, `Weapon` wrapper, `LateralMover`. Shared by all racers and the player, but only
  meaningful in race mode.
- **`assault/scenes/race/racers/<name>/`** (bespoke): each racer's scene, brain script, and
  `states/`. Nothing here is reused by another racer.

### 4.4 De-duplication scorecard

| Today | After |
|---|---|
| `racer_shield.gd` (copy of `Shield`) | **deleted**; one `Shield`, configurable |
| `racer_base.gd` re-implements `BaseEnemy` reaction | uses shared `DamageReaction` component |
| `Shield._emit_snapshot()` prints per ship | print removed / debug-gated |
| `TacticRacerBehavior` shared by all racers | **deleted**; bespoke brains (AI doc) |
| `RacerPersonality.tres` per racer | **deleted**; stats are `@export`s on each racer |
| Per-racer ad-hoc bullet pools, manual scans | shared `Weapon` + `Sensors` components |

---

## 5. The top-speed mechanic (the core loop)

This is **R3**, and it does not exist in the current code (which has a *transient* dash boost +
a *stamina* meter instead). Model it explicitly on `RaceParticipant`.

### 5.1 State

```gdscript
# race_participant.gd (new model)
@export var base_top_speed: float = 200.0     ## speed with zero charge
@export var max_top_speed: float = 600.0      ## hard cap
@export var panel_gain: float = 70.0          ## top-speed added per dash panel crossed
@export var decay_per_sec: float = 25.0       ## top-speed bled off when not recently boosted
@export var loss_per_hit: float = 90.0        ## top-speed lost on taking a hit
@export var grace_after_panel: float = 1.5    ## seconds of no-decay right after a panel

var top_speed: float = base_top_speed         ## the resource you build/defend
var current_speed: float = 0.0                ## actual forward speed this frame
```

### 5.2 Rules

- **Crossing a panel:** `top_speed = min(max_top_speed, top_speed + panel_gain)`, reset the
  grace timer, and apply a short *instant* forward lunge (the satisfying launch) on top.
- **Decay:** while the grace timer is 0, `top_speed = max(base_top_speed, top_speed −
  decay_per_sec·delta)`. So neglecting panels slowly demotes you toward base speed.
- **On hit:** `top_speed = max(base_top_speed, top_speed − loss_per_hit)` (in addition to the
  HP/shield handling). This is the "damage costs speed" of R3/R6.
- **Actual speed:** `current_speed = top_speed` (optionally times a player throttle in `[0..1]`
  if you keep a manual "ease off" control; otherwise the ship always runs at its current top
  speed and the *only* speed lever is panels-vs-decay). `track_y += current_speed·delta`.

### 5.3 Player vs AI symmetry

Both player and AI use the **same** `RaceParticipant` and the **same** top-speed rules. The
*difference* is who hits the panels: the player flies into them by skill; each AI's **brain**
decides how aggressively to detour for them (AI doc — e.g. Bogomol *always* detours and then
mines them; a pace-setter only grabs panels on its lane).

### 5.4 Feedback (so the player can read their speed class)

- `top_speed_changed` → HUD speed bar / "speed class" pips; thruster tint scales with
  `top_speed / max_top_speed`.
- The player's *screen band* (§1.3) can also reflect speed: higher `top_speed` → the player
  rides slightly higher, reinforcing the feel. Tune per Open-Decision #2.

---

## 6. Level authoring (the direct fix for "building a race level is hard")

In the old model a level was a *time schedule of camera-relative wave offsets* tuned against an
invisible projection. In track-space a level is **objects placed at real `track_y` positions** —
visible and editable.

### 6.1 Static furniture: author it as a scene you can see

- `Track` is a `Node2D` whose children are panels, walls, asteroid clusters, mines, and the
  finish line, each carrying a `track_y` (and a real screen-X lane). On `_ready` each registers
  with `RaceWorld`; each frame its `screen_y = RaceWorld.screen_y_for(track_y)`; it culls when it
  scrolls off the bottom and (for "ahead" objects) is hidden until it scrolls in from the top.
- Because `track_y` is linear and real, **you can build a `Track` editing tool later** (an
  `@tool` script or an editor gizmo) that lays out the corridor visually. Even without tooling,
  placing `DashPanel(track_y=1900, x=900)` is unambiguous and order-independent.
- A literal **`TileMapLayer`** can paint the corridor walls / boundary art down the track if you
  want a drawn track surface (skill: `godot-prompter:2d-essentials`).

### 6.2 Dynamic spawns: keep `WaveManager`

Timed/aggressive spawns (a laser sweep at a moment, a pack of interceptors) still come from
`WaveManager`, but anchored by `track_y` (spawn when `scroll_offset` passes a threshold) rather
than wall-clock seconds, so pacing tracks the *player's progress* not real time. Reuse the
existing asteroid/laser scenes (`godot-prompter:scene-organization`).

### 6.3 Why this is designable

A designer can answer "where's the third boost panel and what guards it?" by reading one number
(`track_y`) and seeing the object in the `Track` scene — not by reverse-engineering a wave
schedule and a projection constant. That is the whole point.

---

## 7. Collision layers (unchanged conventions, applied cleanly)

Reuse the project's existing layers (player body 4, player_hurtbox 128, enemy_hitbox 256,
enemy_hurtbox 512, bullets 64, rockets 32, asteroid-contact 1024). For race ships:

- **Racer `HurtBox`:** layer 512, mask = player bullets (64) | rockets (32) | asteroid (1024)
  | (rival contact, see below). The laser hazard's `896` mask already kills layer-512 hurtboxes.
- **Rival-vs-rival / rival-vs-player damage** (rams, bombs): give ships a contact `HitBox`
  (layer 256) and let hurtboxes mask it, so a ram is a *real collision* rather than a manual
  distance scan. (This becomes possible again because §1 restores real movement; if you prefer
  to keep scanning for a handful of ships, that's also fine — but real collisions remove a bug
  class.)
- **Dash panels / pickups / mines:** layer 8 ("pickup") so racer forward-sensors can see them
  ahead; the trigger itself can be a real `Area2D` overlap now that ships move for real.

(Skill: `godot-prompter:physics-system` for layer/mask setup and the `Area2D` vs body choices.)

---

## 8. Phased build sequence (turn into a plan after Open-Decisions are answered)

Each phase is independently runnable. Skills noted per phase.

- **Phase 0 — De-duplicate components (no race logic).**
  Make `Shield` configurable (§4.1), delete `racer_shield.gd`, extract `DamageReaction` (§4.2),
  remove the shield `print`. Verify the *existing* player/enemies still behave.
  Skills: `godot-prompter:component-system`, `godot-prompter:godot-code-review`.

- **Phase 1 — Track-space core.**
  `RaceWorld` (`scroll_offset`, `screen_y_for`, drive background) + new `RaceParticipant`
  (track_y + top-speed mechanic §5) + slim `RaceDirector` (standings by track_y, finish/fail).
  Spawn the *player only* as a participant; prove it advances, the world scrolls, top speed
  builds/decays. Skills: `godot-prompter:component-system`, `godot-prompter:2d-essentials`.

- **Phase 2 — Track furniture.**
  `TrackObject` re-based on `track_y` (real placement), `DashPanel` (real `Area2D` overlap +
  top-speed gain + lunge), a static `Track` scene with a few panels and a `FinishLine`. Author
  one short track you can *see*. Skills: `godot-prompter:scene-organization`,
  `godot-prompter:2d-essentials`.

- **Phase 3 — One bespoke racer (proof of the AI pattern).**
  Shared `Sensors` + `Weapon` + `LateralMover` components; one named racer (e.g. **Fang**) as a
  scene with its own `StateMachine` + `states/`. No `TacticRacerBehavior`, no personality
  `.tres`. Prove it seeks panels, dodges, and runs its signature. Skills:
  `godot-prompter:state-machine`, `godot-prompter:ai-navigation`,
  `godot-prompter:component-system`.

- **Phase 4 — The rest of the roster.**
  Bogomol (mines on panels), Isac (gatling), Booster Gold (dash-ram), Reacher (sniper) — each
  its own scene + brain, reusing the Phase-3 components and the `Bomber`/`RamShip` mechanics.
  Skills: `godot-prompter:state-machine`, `godot-prompter:ai-navigation`.

- **Phase 5 — HUD + finish/fail flow + polish.**
  Standings list, speed-class readout, results overlay, restart-on-death. Skills:
  `godot-prompter:hud-system`, `godot-prompter:godot-ui`.

- **Phase 6 — Optimisation pass.**
  Cache standings/sensors once per frame; reduce group scans; pool bombs/mines. Skills:
  `godot-prompter:godot-optimization`.

---

## 9. Mapping the old files to the new architecture

| Old file | Fate |
|---|---|
| `race_director.gd` | **Rewrite slim** — standings by `track_y`, finish/fail; projection moves to `RaceWorld` |
| `race_participant.gd` | **Rewrite** — `track_y` + top-speed mechanic; drop boost-meter + relative math |
| `racer_base.gd` | **Replace** with `race_ship.gd` (read brain intents, set transform via `RaceWorld`) |
| `racer_steering.gd` | **Refactor into `Sensors` + `LateralMover`** (stateless perception + actuator) |
| `racer_shield.gd` | **Delete** (Shield configurable) |
| `track_object.gd` / `dash_panel.gd` | **Keep, re-base on `track_y`** (real placement, real overlap) |
| `player_throttle_adapter.gd` | **Replace** — player forward speed is the top-speed mechanic, not screen-Y inversion |
| `behaviors/racer_behavior.gd` | **Delete** (no shared brain base) |
| `behaviors/tactic_racer_behavior.gd` | **Delete** (no shared utility-AI) |
| `behaviors/generic_racer_behavior.gd` | **Delete** / fold into a simple "Pacer" racer FSM |
| `behaviors/booster_gold_behavior.gd` | **Re-express** as Booster Gold's own FSM (AI doc) |
| `ai/racer_personality.gd` + `.tres` | **Delete** (stats become per-racer `@export`s) |
| `race_hud.gd/.tscn` | **Keep, extend** with speed-class readout |

New per the research-recommended split: `RaceWorld`, `DamageReaction`, `Sensors`, `Weapon`,
`LateralMover`, and one scene+brain per racer.

---

## 10. Risks & mitigations

- **Feel change from a moving player band.** Mitigate by damping the player's screen-Y band and
  tuning `base_screen_y`; validate early (Phase 1) before building content.
- **Track length / streaming.** A finite track means authoring length and culling windows;
  trivial for a straight corridor but must be in from Phase 1 (cull by `track_y` window).
- **Refactor blast radius of `Shield`.** Phase 0 touches a shared component the player relies on
  — do it first, in isolation, and verify existing modes before any race work (skill:
  `godot-prompter:godot-code-review`).
- **Scope.** Five bespoke brains is a lot of authoring. Phases 3–4 are deliberately split so a
  2–3-racer slice is playable before the full roster.

See [the AI doc](2026-06-01-race-ai-bespoke-racers.md) for the per-racer FSMs that Phases 3–4
implement.
