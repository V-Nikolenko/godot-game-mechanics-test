# Assault Race Mode — Bespoke Racer AI

**Date:** 2026-06-01
**Status:** Research / proposed design.
**Reads with:** [Deep research & direction](2026-06-01-race-mode-deep-research.md) ·
[Architecture](2026-06-01-race-mode-architecture.md)

This document designs the **AI movement and decision-making** for the race rivals. It satisfies
your hard constraint (R7): *each racer has unique stats, movement, states, and logic — no
abstract racer brain reused for all of them* — while still satisfying R9 (*no duplicated
components*). The reconciling rule, from the research doc:

> **Mechanics are shared components. Decisions are bespoke FSMs.**

> Skills to invoke during implementation: `godot-prompter:state-machine` (the FSM backbone),
> `godot-prompter:ai-navigation` (steering, lookahead, lead-the-target), `godot-prompter:component-system`
> (the shared sensor/weapon kit), `godot-prompter:gdscript-patterns` (static typing, match).

---

## 1. Why bespoke FSMs (and not the current `TacticRacerBehavior`)

The current code makes a racer *a `.tres` of weights* fed to one shared utility-AI. The
downsides for *this* game (samey motion, signatures wedged in by subclassing, coupling to the
projection inverse-math) are covered in [research §2.4](2026-06-01-race-mode-deep-research.md#24-the-ai-is-shared-brain-not-bespoke-the-r7-violation).

What you want instead is what the engine *already* uses everywhere else: an explicit finite
state machine per actor, built on [`global/statemachine/state.gd`](../../../global/statemachine/state.gd)
+ [`state_machine.gd`](../../../global/statemachine/state_machine.gd). The player uses it
([`assault/scenes/player/states/`](../../../assault/scenes/player/states/move_state.gd)); the
fighter enemy uses it ([`light_assault_ship/states/`](../../../assault/scenes/enemies/light_assault_ship/states/approach_state.gd)).
Each racer joins that family with *its own* states.

**The benefit:** a racer's personality is *legible in its state graph*. "Fang hunts the leader's
tail, then lunges" is three states and two transitions you can read, tune, and debug — not an
emergent property of six weights. And a signature that doesn't fit a shared vocabulary (mine the
panel you just used) is just *a state*, not a subclass hack.

---

## 2. The existing FSM backbone (what we build on)

```gdscript
# global/statemachine/state.gd
class_name State extends Node
signal state_transition          # emit(next_state) to switch
func enter() -> void: pass
func process_physics(delta: float): pass
func exit() -> void: pass

# global/statemachine/state_machine.gd
class_name StateMachine extends Node
@export var initial_state: State
# connects each child State.state_transition -> change_state; ticks current_state.process_physics
```

Two small upgrades make it race-ready (both backward-compatible):
1. **Tick in `_physics_process`** for the racers (the player's machine ticks in `_process`; AI
   movement wants physics-rate). Add a `physics_tick: bool` export, or a `RacerStateMachine`
   that ticks in `_physics_process`. *(Reuse the same `State` base.)*
2. **A typed `host` reference** (the `RaceShip`) injected into each state on ready, so states can
   read sensors / drive the weapon / set intents without `get_parent()` chains.

That's it — no shared *decision* base class. Each racer's states extend `State` directly.

---

## 3. Shared mechanics (the kit every brain calls — but none of them *decides*)

These are components on the `RaceShip` (architecture §2.2). They are **stateless about
strategy**: they perceive or act on command. Reusing them is *not* reusing a brain.

### 3.1 `Sensors` (pure perception; cached per frame)

```gdscript
class_name Sensors extends Node
# All queries are read-only and refer to track_y (longitudinal) + screen-X (lateral).

func ship_ahead(max_gap: float, lane_tol: float) -> RaceParticipant   # nearest ship in my column ahead
func ship_behind(max_gap: float, lane_tol: float) -> RaceParticipant
func nearest_panel_ahead(max_gap: float) -> Node2D                    # group "dash_panels"
func incoming_threat() -> Node2D                                      # nearest bullet/laser on a collision course
func hazard_ahead(lookahead: float) -> Node2D                        # asteroids/mines/laser columns
func gap_to(p: RaceParticipant) -> float                             # track_y delta (signed)
func player() -> RaceParticipant
func leader() -> RaceParticipant
```

Implemented once, used by all. Internally it asks `RaceDirector` for the per-frame standings and
does the small group scans **once**, caching results for the frame (fixing the per-racer O(n²)
of the current `racer_steering`).

### 3.2 `Weapon` (firing; no targeting policy)

```gdscript
class_name Weapon extends Node
@export var bullet_scene: PackedScene
@export var pool_size: int = 12
func fire(from: Vector2, dir: Vector2, damage: int, speed: float) -> void
func fire_at(target: Node2D, damage: int, speed: float) -> void       # convenience: aim then fire
```

Wraps a `BulletPool`. *Which* target and *when* is the brain's call. (Reuses
[`bullet_pool.gd`](../../../global/components/bullet_pool.gd) and the existing `enemy_bullet`.)

### 3.3 `LateralMover` (actuation; no steering policy)

```gdscript
class_name LateralMover extends Node
@export var smooth_tau: float = 0.12
@export var min_x: float = 80.0
@export var max_x: float = 1200.0
func step_toward(current_x: float, target_x: float, delta: float) -> float   # critically-damped glide + clamp
```

The smoothing the current `racer_base` does inline, extracted so every racer slides cleanly.
**Obstacle avoidance / bullet dodge are *offered* as helper nudges** the brain can add to its
target X — but the brain decides whether to (a panel-greedy racer might tank a graze to keep its
line; a cautious sniper always dodges). Avoidance is a *mechanic*, dodging-vs-not is a
*decision*.

### 3.4 `RaceParticipant` (the longitudinal mover + top-speed; architecture §5)

The brain reads `participant.top_speed`, calls `participant.request_panel_detour()` indirectly by
*steering toward a panel*, and the participant handles the speed integration. A brain can also
ask for a temporary forward intent (coast/floor) if you keep a throttle lever.

> **The line, restated:** Sensors/Weapon/LateralMover/Participant are shared *verbs*. Each
> racer's FSM is the *sentence*. No two racers share a sentence.

---

## 4. The per-racer FSM pattern (template)

Every racer lives in its own folder and is its own scene:

```
assault/scenes/race/racers/fang/
├── fang.tscn                 # RaceShip skeleton (shared comps) + Fang sprite + Fang brain
├── fang.gd                   # class_name Fang extends RaceShip — its @export STATS live here
└── states/
    ├── fang_hunt_state.gd    # class_name FangHuntState extends State
    ├── fang_lunge_state.gd
    └── fang_dodge_state.gd
```

- **Stats are `@export`s on `fang.gd`** (HP, top-speed tuning, lunge range, fire rate…). No
  `RacerPersonality` resource. If you *want* editor-tunable data, each racer may own its *own*
  small typed resource (e.g. `FangStats`) — but it is Fang's, not shared across racers.
- **States extend `State` directly.** They read `host.sensors`, drive `host.weapon`, set
  `host.desired_lateral_x` / forward intent, and `state_transition.emit(next)` to switch.
- **No shared brain base, no shared beat enum.** Fang's `HUNT` is not Bogomol's anything.

A representative state (Fang hunting the ship in front), to show the texture:

```gdscript
## FangHuntState — sit just behind the ship in front (player or rival), match its lane,
## and suppress it with forward fire. Break to LUNGE when lined up and in range; break to
## DODGE when a threat enters the dodge sensor.
class_name FangHuntState extends State

@export var host: Fang
@export var lunge_state: State
@export var dodge_state: State
@export var follow_gap: float = 160.0     # track_y units to hold behind the target
@export var fire_cd: float = 0.7

var _cd: float = 0.0

func process_physics(delta: float) -> void:
    _cd = maxf(0.0, _cd - delta)
    if host.sensors.incoming_threat() != null:
        state_transition.emit(dodge_state); return

    var target := host.sensors.ship_ahead(host.hunt_range, host.lane_tol)
    if target == null:
        # No prey in front → chase panels to keep top speed up (still Fang's choice: it
        # is a hunter, so it only bothers with panels when there's nothing to hunt).
        host.steer_toward_panel_or_center(delta); return

    # Hold station behind the target, matched in lane.
    host.set_forward_intent_match(target, follow_gap)
    host.desired_lateral_x = target.host_x()
    if _cd <= 0.0 and host.is_lined_up(target):
        host.weapon.fire_at(target.node(), host.bullet_damage, host.bullet_speed)
        _cd = fire_cd

    if host.can_lunge(target):
        state_transition.emit(lunge_state)
```

Note what's reused (`sensors`, `weapon`, helpers on the shared `RaceShip`) versus what's Fang's
alone (the *graph*: HUNT↔LUNGE↔DODGE, the *thresholds*, the *priority* "hunt over panels").

---

## 5. The five racers (bespoke designs)

Each is a distinct movement + firing identity, expressed as its own small FSM. Stat numbers are
starting suggestions for tuning. The two patterns you named — *bomb-on-panel* and *ram-the-ship-
in-front* — are Bogomol and Booster Gold respectively, and reuse existing enemy mechanics.

### 5.1 Fang — the tail-hunter / lunger

**Fantasy:** clamps onto whoever is in front, suppresses them, then lunges to ram. Relentless
mid-field duelist.

**Stats:** HP 70 · shield 1 · top-speed: high accel, average cap · `hunt_range` 700 ·
`lunge_range` 220 · `lunge_speed` ×2.4 · `bullet_damage` 8 · `fire_cd` 0.7.

**States & transitions:**

```
        no prey in front
  ┌────────────────────────────┐
  │                            ▼
HUNT ──lined up & in range──▶ LUNGE ──ram done / miss──▶ HUNT
  ▲                            │
  └────────threat? any state──▶ DODGE ──clear──▶ HUNT
```

- **HUNT:** find `ship_ahead`; hold `follow_gap` behind, match lane, fire when lined up. If none,
  drift toward panels (only because there's nothing to hunt).
- **LUNGE:** brief forward over-speed straight through the target's lane; deals contact damage
  via the real `HitBox` (architecture §7); brief hurtbox-off i-frames. Returns to HUNT.
- **DODGE:** sidestep `incoming_threat` perpendicular, then resume.
- **Signature:** *targets the ship directly ahead, player or rival* — Fang will hunt a rival
  leader as readily as the player.

### 5.2 Bogomol — the panel-denier (bomb / mine-on-panel)

**Fantasy:** races for panels not (only) for the speed, but to **mine them behind itself** so the
field eats the mine. Area-denial saboteur. *This is your "drops bombs on the dash panel it just
used" racer.*

**Mechanic reuse:** the drop is exactly [`Bomber._drop_bomb()`](../../../assault/scenes/enemies/bomber/bomber.gd)
— instance a `Mine`/`bomb` scene at the panel position. A `Mine` is a track-anchored `TrackObject`
(architecture §6) with a small `HitBox` and a fuse, in group `mines` so everyone's `Sensors`/
avoidance already account for it.

**Stats:** HP 60 · shield 2 · top-speed: average · `mine_scene` · `mine_drop_offset` (just past
the panel) · `panel_greed` high.

**States & transitions:**

```
SEEK_PANEL ──reached panel──▶ MINE_DROP ──dropped──▶ SEEK_PANEL
   ▲                                                    │
   └──no reachable panel──▶ CRUISE ──panel appears──────┘
   threat? any ──▶ EVADE ──clear──▶ SEEK_PANEL
```

- **SEEK_PANEL:** steer toward `nearest_panel_ahead` on both axes; this *also* grows Bogomol's
  own top speed when it crosses (it benefits and denies).
- **MINE_DROP:** on crossing the panel, drop a mine at/just behind it (so trailing ships hit it),
  then immediately seek the next.
- **CRUISE:** no panel reachable → hold a defensive line, maybe lay an occasional mine on its own
  lane.
- **EVADE:** dodge threats.
- **Signature:** turns the player's own speed economy against them — the panels you want are
  trapped.

### 5.3 Isac — the area-suppressor (gatling)

**Fantasy:** doesn't chase; *parks* near a cluster and hoses everything in a radius. A
slow-but-deadly turret on the move.

**Mechanic reuse:** the gatling is the existing `AttackController` + `AimedAttackPattern` at a
fast `fire_interval` (as `LightAssaultShip` builds), pointed by the brain.

**Stats:** HP 90 (tanky) · shield 1 · top-speed: low cap, low decay (steady) · `spray_radius`
300 · `fire_interval` 0.12 · `bullet_damage` 4.

**States & transitions:**

```
PROWL ──ship within spray_radius──▶ SPRAY ──radius empty──▶ PROWL
  threat? ──▶ REPOSITION (short slide) ──▶ PROWL
```

- **PROWL:** ease toward the densest part of the field (most ships within radius), grabbing
  panels of convenience.
- **SPRAY:** while any ship (player or rival) is within `spray_radius`, fire continuously, leading
  the nearest. Doesn't pursue — it *occupies* space.
- **REPOSITION:** brief slide when directly threatened; never fully flees.
- **Signature:** a moving no-go zone; punishes anyone who packs in for a panel.

### 5.4 Booster Gold — the front-runner (panel-greedy leader + reclaim-dasher)

**Fantasy:** the rabbit that *refuses to be passed*. His whole identity is **staying in front**.
He does it by **hoarding dash panels** — panels are his single highest opportunity priority,
because every panel keeps his top speed maxed and his lead intact. The moment he *does* fall
behind, he flips aggressive: he spends his **invincible dash** to ram through whoever's ahead and
claw his way back to first. Holds the lead with speed; takes it back with violence.

He is the salvage target for the existing
[`booster_gold_behavior.gd`](../../../assault/scenes/race/behaviors/booster_gold_behavior.gd) —
re-expressed as his *own* FSM (no `extends TacticRacerBehavior`).

**Mechanic reuse:** the dash-ram is `RamShip`'s contact-damage idea + a timed i-frame dash; on
hit it applies damage via the real `HitBox` (architecture §7) rather than the current manual scan.

**Stats:** HP 60 · shield 1 · top-speed: **highest cap**, agile, low decay · `panel_priority`
**max** (always seek a reachable panel) · `lead_margin` 250 (track_y he wants to hold over 2nd) ·
`behind_threshold` 0 (any place worse than 1st = "behind") · `dash_cooldown` 7 · `dash_speed`
×3.2 · `dash_damage` 45 · `dash_range` [40, 430] px · `dash_aim_tol` 80 · `desperation_gap` 900
(track_y behind leader at which he dashes even with no clean target, just to surge).

**The core idea: priorities depend on whether he's in front.** A single `_am_in_front()` /
`_gap_to_leader()` check (cheap — `RaceDirector` already sorts standings) drives the whole graph.

**States & transitions:**

```
                      ┌──────────────── EVADE (threat? from any state) ────────────────┐
                      ▼                                                                 │
                  (survival)                                                            │
   in 1st place ──────────────▶ FRONTRUN ◀───────────── reclaimed the lead ◀───── RECLAIM
       ▲   │  panel reachable?     │ │ ▲                                            ▲  │
       │   │      ▼                │ │ │ tailed while leading                       │  │
       │   └─▶ GRAB_PANEL ─done────┘ │ └────────▶ JUKE ──shaken──▶ FRONTRUN         │  │
       │        (very high prio)     │                                              │  │
       │                             │  fell behind 1st (place > 1)                 │  │
       │                             └──────────────────────────────────────────────┘  │
       │                                                                                │
   target ahead in dash range & cd ready ──▶ DASH ──dash ends (cd)──▶ back to RECLAIM ──┘
                                              (also: GRAB_PANEL en route if one's on the way)
DASH is invincible and owns movement until it ends.
```

- **FRONTRUN** *(active while he is in 1st)*: hold a fast clean line and **defend the lead**. He
  constantly checks for a reachable panel — if one exists, it preempts almost everything
  (→ GRAB_PANEL), because keeping top speed maxed is how he stays ahead. He can drift his lane to
  **sit on the panels the player wants** (soft block). If a chaser is tailing him → JUKE. He does
  *not* waste his dash here (saves it for reclaiming).
- **GRAB_PANEL** *(highest opportunity priority, reachable from FRONTRUN and RECLAIM)*: commit to
  the nearest reachable dash panel on both axes and fly through it; raises his own top speed, then
  returns to whichever mode he was in. This is the state that expresses "panels are very high
  priority."
- **RECLAIM** *(active the instant he is **not** in 1st)*: aggressive catch-up. Floor it, **still
  grab panels greedily** (GRAB_PANEL preempts), and — the key flip — **use the dash**: if a ship
  ahead is in `dash_range` and the dash is off cooldown, → DASH to ram past it and climb; if no
  clean target but he's more than `desperation_gap` behind the leader, dash anyway as a pure
  forward surge. Fire forward at the ship ahead while the dash recharges.
- **DASH** *(signature)*: invincible boosted lunge straight up his target's lane; contact damage
  once per ship passed (overtakes *and* hurts); then `dash_cooldown`. Used almost exclusively from
  RECLAIM — i.e. *he dashes when he's behind*, exactly as specified.
- **JUKE:** brief sidestep when a chaser sits on his tail while he's leading, to deny the slipstream.
- **EVADE:** dodge an incoming threat, then resume the appropriate mode.

- **Signature & feel:** when ahead he's a slippery panel-hog you can't quite catch; when you *do*
  get past him he comes back hard with an invincible ram. Beating Booster Gold means denying him
  panels *and* surviving his reclaim dashes.

> **Why this reads as "always keeps in front":** the FSM is split by standing. `FRONTRUN` is the
> home state and its dominant drive is GRAB_PANEL (panels = max top speed = lead). `RECLAIM` only
> exists while he's been passed, and it's where the dashes live. So his default behaviour is
> *hold the front via panels*, and dashing is the explicit *fallback for falling behind* — which
> is precisely the behaviour you asked for.

### 5.5 Reacher — the long-range sniper

**Fantasy:** hangs back, lines up, and lands heavy long-range shots on whoever's leading. Plays
the *position* game, not the brawl.

**Mechanic reuse:** the project already has a `sniper_enemy` and a sniper-shot design
([`specs/2026-05-22-sniper-shot-design.md`](../specs/2026-05-22-sniper-shot-design.md)) — reuse
the telegraph + heavy-bullet pattern.

**Stats:** HP 65 · shield 1 · top-speed: average, but *prefers* to sit a touch behind for line of
sight · `snipe_charge` 1.2 s · `snipe_damage` 30 · `snipe_range` very long.

**States & transitions:**

```
POSITION ──clean LOS to a target & charged──▶ AIM ──fire──▶ POSITION (recharge)
   threat? ──▶ EVADE ──clear──▶ POSITION
   falling too far back ──▶ CATCH_UP (grab panels) ──▶ POSITION
```

- **POSITION:** keep a stand-off gap and a clear lane to the target; sidestep to open a shot.
- **AIM:** telegraphed charge, then a fast heavy bullet leading the target.
- **CATCH_UP:** if it drops too far back (top speed bled away), temporarily prioritise panels.
- **EVADE:** dodge.
- **Signature:** the racer that makes *leading* dangerous — rewards the player for not running
  away in a straight line.

### 5.6 (Optional) Pacer — the rabbit

If you want a baseline non-gimmick rival to set the pace (replacing the old
`GenericRacerBehavior`), a tiny two-state racer (`RUN` / `EVADE`) that just chases panels and
holds a fast clean line. It exists to be the standings benchmark. Its own scene + 2 states — not
a shared base.

---

## 6. Movement vocabulary (shared verbs the bespoke brains compose)

So the brains stay readable, the `RaceShip` exposes a few **intent helpers** (thin wrappers over
the shared mechanics; they *act*, they don't *decide*):

| Helper on `RaceShip` | Effect |
|---|---|
| `set_forward_intent_floor()` | run at full current top speed |
| `set_forward_intent_coast()` | ease off (let others pass / hold a gap) |
| `set_forward_intent_match(target, gap)` | match a target's pace at a `track_y` gap |
| `steer_toward(x)` | set `desired_lateral_x` |
| `steer_toward_panel_or_center(delta)` | convenience: seek nearest panel else recenter |
| `add_avoidance_nudge()` | optional hazard sidestep (brain opts in) |
| `is_lined_up(target)` / `can_lunge(target)` / `can_ram(target)` | geometry predicates |

Each racer's states call these in *their own order with their own thresholds*. Two racers calling
`steer_toward_panel_or_center` is code reuse, not brain reuse — just as two `CharacterBody2D`
calling `move_and_slide` aren't sharing a brain.

---

## 7. Decision cadence & perf (offline, so spend cycles on *good* AI)

- **One sort, one scan, per frame, in the director/sensors** — cached and read by all brains
  (fixes the current per-racer re-sort + O(n²) group scans).
- **States tick at physics rate**; transitions are cheap (predicate checks). A racer evaluates a
  handful of sensor queries per frame — trivial for a field of 5–8.
- **Pool bombs/mines/bullets** (reuse `BulletPool`; a small mine pool).
- Because it's offline, you can afford *richer* per-racer logic (lookahead, target selection,
  feints) without sync/determinism limits — lean into making each brain *feel* different.

---

## 8. How this satisfies your constraints

| Constraint | How |
|---|---|
| R7 — unique stats/movement/states/logic per racer | Each racer = own scene + own `StateMachine` + own `states/` + own `@export` stats. No shared brain, no personality `.tres`. |
| R7 — *no abstract class reused for racers* | States extend the generic `State` (a Godot primitive, like `Node`) — there is **no** `RacerBehavior`/`TacticRacerBehavior` decision base. |
| R9 — reusable components, no duplication | `Sensors`/`Weapon`/`LateralMover`/`RaceParticipant`/`Shield`/`Health`/`DamageReaction` are single shared components composed onto every ship. |
| R5 — unique attack patterns (bomb-on-panel, ram) | Bogomol (mine-on-panel, reusing `Bomber`) and Booster Gold (dash-ram, reusing `RamShip`) — plus Isac/Reacher/Fang for variety. |
| R4/R3 — rivals also build top speed via panels | Every brain seeks panels (to its own taste); the shared `RaceParticipant` top-speed mechanic applies identically to all. |
| R8 — offline, focus on movement/thinking | FSMs are authored for *feel*; no netcode; perf budget spent on perception/decisions. |

---

## 9. Build order for the AI (Phases 3–4 of the architecture plan)

1. Build `Sensors`, `Weapon`, `LateralMover` and the `RaceShip` intent helpers (shared kit).
   Skill: `godot-prompter:component-system`.
2. Add the `RacerStateMachine` physics-tick variant + typed `host` injection. Skill:
   `godot-prompter:state-machine`.
3. Implement **Fang** end-to-end (HUNT/LUNGE/DODGE) as the pattern reference. Skill:
   `godot-prompter:ai-navigation`.
4. Implement Bogomol (mine reuse), Booster Gold (re-express the old `BoosterGoldBehavior`), Isac (gatling),
   Reacher (sniper), and optionally Pacer — each its own scene + states. Skill:
   `godot-prompter:state-machine`, `godot-prompter:ai-navigation`.
5. Tune in-engine; AI movement/feel is heuristic and validated by playtest, not unit tests.

When you've picked the world model (research §6, Open Decisions) and a starting roster, I can
turn all three research docs into an executable, task-by-task plan under
`docs/superpowers/plans/`.
