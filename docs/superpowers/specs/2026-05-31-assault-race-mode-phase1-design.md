# Assault Race Mode — Phase 1 Design (Race Core + Playable Level)

**Date:** 2026-05-31
**Status:** Approved design, pre-implementation
**Scope:** Phase 1 of 2. This spec covers the race *framework* and a playable race level
with generic placeholder racers. The five named racers (Fang, Isac, Bogomol, Gold
Experience, Reacher) and mines are **Phase 2** (separate spec).

---

## 1. Background & Motivation

`assault` is being promoted from "a mission type" to a **gameplay/control style** — the
side-on (technically vertical-scroll) shoot-'em-up view, player ship, controls, and
scrolling-background system. New *kinds* of gameplay can now live inside `assault`.

The first new kind is a **race**: the player races rival ships to a finish line. It is a
"dead race" — ships can damage and destroy each other. Future obstacles (electricity
walls, mines, asteroids, lasers, enemy attacks) make finishing non-trivial. Ships gain
speed by driving over **dash panels**.

### Key engine facts this design builds on

- **Vertical-scroll shmup, pinned camera.** `ArenaCamera` keeps `global_position` fixed
  at world (640, 360) and follows the player only via `Camera2D.offset`. The illusion of
  forward motion comes from `Level1Background` scrolling its layers at fixed per-layer
  speeds in `_process(delta)`. "Forward / ahead" = toward the top of the screen.
- **Enemies** = `BaseEnemy : CharacterBody2D` with `Health` + `HurtBox` + a contact
  `HitBox`, configured from a `ShipConfig`. They either self-drive via phase AI in
  `_physics_process` (e.g. `Gunship`) or are driven by an attached `EnemyPathMover` +
  `MovementResource`.
- **WaveManager** instantiates any scene at a camera-relative offset
  (`cam.global_position + offset * ArenaCamera.WORLD_SCALE`), optionally running an
  `on_spawned(node)` callback and optionally attaching an `EnemyPathMover`.
- **Player** = `PlayerBase` / `player_fighter` with `Health`/`Shield`/`Overheat`
  components and a reusable bubble-shield visual (`bubble_shield.tscn`).
- **Collision layers:** player body 4, player_hurtbox 128, enemy_hitbox 256,
  enemy_hurtbox 512, bullets 64, rockets 32, asteroid-contact 1024. `BaseEnemy.HurtBox`
  masks `97 | 1024` (= bullets 64 + rockets 32 + layer 1 + asteroid 1024).
- **Laser hazard** (`laser_ray`/`laser_wall`) one-hit-kills anything whose `HurtBox` sits
  on layer 128/256/512 (its `HitZone` mask is `896`), after a configurable `warn_duration`
  telegraph.

---

## 2. Race Rules (decided)

- **Race model: relative-progress.** The pinned camera and scrolling background are
  unchanged. Every participant has an abstract `progress` value (0 → `track_length`). A
  rival's on-screen **Y** is derived from `(rival.progress − player.progress)`: ahead →
  higher up the screen, behind → lower; clamped off-screen when far away.
- **Player speed: position-as-throttle.** The player's own screen-Y in the play box *is*
  the throttle — toward the top = faster, toward the bottom = slower. Dash panels add
  timed bursts on top. (Consequence: accelerating makes rivals drift downward; slowing
  makes them climb up past you.)
- **Rival speed.** Each AI racer's baseline race speed is slightly **above** the player's
  neutral (mid-box) speed, so the player is under constant pressure and must ride the top
  of the box / chase dash panels to keep up.
- **Damage = setback.** A non-fatal hit pops a bubble-shield charge (if any), applies a
  brief control stun, and **knocks the victim back** (a chunk of `progress` is lost).
- **0 HP = destroyed/eliminated.** Killing rivals is a valid strategy and removes them
  from the race permanently.
- **Player destroyed = race failed → restart the level.** The player can eliminate
  every rival and still fail by dying to an obstacle.
- **Win = cross the finish line** (`progress ≥ track_length`); finishing 1st is the goal.
  Final placement (1st…Nth) is the result.
- **Track length:** tuned to roughly 60–90 s of racing for this small level
  (`track_length` is an exported number on `RaceDirector`, default chosen in-engine).

---

## 3. Architecture Overview

Component-based, separating "being in the race" (applies to the player too) from "what
kind of ship you are."

```
RaceDirector (Node, one per race level)
  ├─ holds all RaceParticipants
  ├─ sorts standings by progress each frame
  ├─ get_screen_y(participant) → Y for AI rivals (relative-progress mapping)
  ├─ finish detection + placement results
  ├─ player-death → race_failed → restart
  └─ in group "race_director" (so participants self-register)

RaceParticipant (Node component on EVERY race ship — player and AI)
  ├─ progress, min/max/current_speed, throttle, finished
  ├─ dash-boost state (timed multiplier)
  ├─ advances progress += current_speed * delta each physics frame
  ├─ throttle source injected (player: screen-Y; AI: behavior)
  └─ registers with RaceDirector on _ready

Player ship (shared player_fighter — NOT modified)
  └─ at race start, RaceDirector attaches at runtime:
       ├─ RaceParticipant
       ├─ PlayerThrottleAdapter (screen-Y → throttle 0..1)
       └─ dash-panel overlap handling (boost + background scroll multiplier)

AI racer = RacerBase : BaseEnemy
  ├─ RaceParticipant
  ├─ RacerBehavior (Phase 2 per-racer; Phase 1 = GenericRacerBehavior)
  ├─ RacerTargeting (queries RaceDirector for ship directly ahead/behind)
  ├─ ObstacleAvoidance (lookahead Area2D → lateral steer)
  ├─ BulletDodge (incoming-bullet Area2D → sidestep)
  ├─ DashSeeker (bias steering toward a reachable dash panel)
  ├─ ShieldComponent + bubble-shield visual (reused from player)
  └─ owns its full transform: X from steering, Y from RaceDirector.get_screen_y(self)
```

### Single position-owner rule

To avoid two nodes fighting over a transform, **the racer owns its full position.** Each
physics frame the racer sets its own **X** from steering and reads its **Y** from
`RaceDirector.get_screen_y(self)`. The director computes standings and the Y mapping but
never writes transforms.

---

## 4. Components — responsibilities & interfaces

### 4.1 `RaceParticipant` (Node)
- **Speed fields (explicit):** `min_speed` and `max_speed` define the throttle range;
  `current_speed` is derived each frame from throttle as
  `lerp(min_speed, max_speed, throttle)`. A racer's "baseline" pressure is set by giving
  AI racers a higher *resting* throttle than the player's mid-box throttle (≈0.5), so no
  separate `base_speed` field is needed.
- **State:** `progress: float`, `min_speed: float`, `max_speed: float`,
  `current_speed: float`, `throttle: float`, `finished: bool`,
  dash-boost `(_boost_mult: float, _boost_timer)`.
- **API:**
  - `set_throttle(t: float)` — `t` in `0..1`; stored and applied to `current_speed` via
    the lerp above.
  - `apply_dash_boost(mult: float, duration: float)` — timed multiplier on `current_speed`.
  - `apply_setback(progress_loss: float)` — subtract from `progress` (clamped ≥ 0).
  - `func _physics_process(delta)` → `progress += current_speed * boost * delta`; on
    crossing `track_length`, set `finished = true` and notify `RaceDirector`.
- **Depends on:** `RaceDirector` (found via `race_director` group) for register/finish.

### 4.2 `RaceDirector` (Node)
- **State:** `participants: Array`, `track_length: float`, `screen_y_scale: float`
  (px per progress-unit), `player_anchor_y: float` (the y rivals converge toward when
  level with the player), `results: Array`.
- **API:**
  - `register(p: RaceParticipant)` / `unregister(p)`.
  - `get_screen_y(p) -> float` = `player_anchor_y - clamp((p.progress - player.progress) *
    screen_y_scale, -max_off, +max_off)`.
  - `get_ahead(p)` / `get_behind(p)` — neighbours in the progress-sorted standings.
  - `get_standings() -> Array` (sorted, for HUD).
  - emits `race_finished(results)`, `race_failed`.
- **Per frame:** sort standings; detect player finish/death.
- **Player death:** connect to the player `Health` reaching 0 → emit `race_failed`.

### 4.3 `PlayerThrottleAdapter` (Node, attached to player at runtime)
- Reads the player ship's screen-Y, normalizes against the play-box vertical bounds
  (from `move_state`/arena bounds), inverts (top = 1.0), feeds `RaceParticipant.set_throttle`.
- Handles dash-panel overlap for the player: calls `RaceParticipant.apply_dash_boost`
  **and** `BackgroundController.set_scroll_multiplier(m)` for the boost duration.

### 4.4 `RacerBase : BaseEnemy`
- Reuses `Health`/`HurtBox`/contact-`HitBox`/death/explosion/scoring.
- Adds `ShieldComponent` + bubble-shield visual, a `RaceParticipant`, a `RacerBehavior`,
  and the steering subsystems.
- `_physics_process`: gather X-nudges from `ObstacleAvoidance` + `BulletDodge` +
  `DashSeeker` + behavior → weighted target X → move toward it; set
  `global_position.y = RaceDirector.get_screen_y(participant)`; ask behavior for throttle.
- On damage (`HurtBox.received_damage`): if a shield charge exists, consume it; else apply
  HP damage; either way apply control stun + `participant.apply_setback(setback_amount)`.

### 4.5 Steering subsystems (each returns a lateral X-nudge, weighted-summed)
- **`ObstacleAvoidance`** — forward lookahead `Area2D`; scans groups `asteroids`, `mines`,
  and active laser columns; nudges X away from the nearest threat; optional throttle-down.
- **`BulletDodge`** — detection `Area2D` (mask bullets 64 + enemy bullets 256); for a
  projectile on a collision course, nudge X perpendicular to its velocity.
- **`DashSeeker`** — if a `DashPanel` is within reach ahead, nudge X toward it.

### 4.6 `RacerBehavior` (base; Phase 1 = `GenericRacerBehavior`)
- Interface: `get_throttle() -> float`, `process_behavior(delta)`, `get_steer_x() -> float`.
- Reads `RacerTargeting.get_ahead()/get_behind()` to decide shoot-vs-outrun.
- **Generic Phase-1 brain:** hold pace near the player, fire an occasional forward bullet
  when something is ahead, rely on the shared avoidance/dodge/dash subsystems.

### 4.7 `DashPanel` (Area2D + chevron sprite, new scene)
- On overlap by a race ship (per-ship re-trigger cooldown), apply a timed boost to that
  ship's `RaceParticipant`. For the player, also drive the background scroll multiplier.
- Exported `boost_mult`, `boost_duration`, `cooldown`.

### 4.8 `BackgroundController.set_scroll_multiplier(m: float)` (new method on base)
- Multiplies all per-layer scroll speeds by `m` (default 1.0). `Level1Background`'s
  per-layer logic is untouched; it reads the multiplier when accumulating scroll.

---

## 5. Level & Spawning

### 5.1 `race_level_1.tscn`
Reuses existing assets. Node tree:
- `Level1Background` (reused), `ArenaCamera`, `player_fighter` (shared),
  `EnemyContainer`, `WaveManager`, `RaceDirector`, `RaceHUD`, `RaceLevel1Config`.

### 5.2 `RaceLevel1Config` (script, mirrors `level_1_director.gd`)
- On `_ready`: attach race components to the player via `RaceDirector`; build the spawn
  schedule and feed it to `WaveManager`; start the race.

### 5.3 WaveManager-driven spawns (no WaveManager changes needed)
- **Racers** spawn at t≈0, spread across the start line, **without** an `EnemyPathMover`
  (they self-drive). Each self-registers with `RaceDirector` on `_ready`.
- **Asteroids** reuse existing `big_asteroid()`/`small_asteroid()` entries with
  `StraightMovement`.
- **Lasers** (`laser_ray`/`laser_wall`) and **`DashPanel`s** spawn as static scenes at
  fixed camera-relative offsets across the race timeline.
- New `WaveBuilder` constructors: `racer(scene_path)`, `dash_panel()` (alongside existing
  `big_asteroid()`, `small_asteroid()`). `RaceLevel1Config` assembles `WaveResource`s
  through `WaveBuilder`.

### 5.4 Obstacle reuse (unchanged scenes)
- Asteroid contact already damages racer `HurtBox`es (layer 512, mask incl. 1024).
- Laser `896` mask already one-hit-kills racers (eliminated) or the player (fail); the
  `warn_duration` telegraph is the cue racers steer around.
- `mines` group reserved for Phase 2 so `ObstacleAvoidance` already accounts for it.

---

## 6. HUD

`RaceHUD` (CanvasLayer): standings list (1st…Nth by progress), the player's current place
highlighted, and a progress-to-finish bar. Minimal but functional; subscribes to
`RaceDirector` standings updates.

---

## 7. Finish / Fail Flow

- Player `progress ≥ track_length` → record placement; show results.
- Racer finishes → record placement; remove from active field.
- Player ship `Health == 0` → `RaceDirector.race_failed` → restart the level scene.
- Race ends when the player finishes or fails. Phase 1 ships a **minimal results overlay**
  (ordered placement list + restart/continue); richer debrief is later polish.

---

## 8. Testing

Headless unit tests (GUT/gdUnit, already in repo) for pure logic:
- `RaceParticipant`: progress integration, throttle→speed mapping, dash-boost timing,
  setback clamping, finish flag.
- `RaceDirector`: standings sort, `get_screen_y` mapping (ahead→up, behind→down, clamp),
  `get_ahead`/`get_behind` neighbours, finish/fail signal emission.
- `DashPanel`: boost application + per-ship cooldown.
- `BackgroundController.set_scroll_multiplier`: speeds scale correctly.

AI steering/behaviors (avoidance, dodge, dash-seek, generic brain) are verified manually
in-engine — they are heuristic and not unit-test-friendly.

---

## 9. New / Changed Files (Phase 1)

**New:**
- `assault/scenes/race/race_participant.gd` (`RaceParticipant`)
- `assault/scenes/race/race_director.gd` (`RaceDirector`)
- `assault/scenes/race/player_throttle_adapter.gd` (`PlayerThrottleAdapter`)
- `assault/scenes/race/racer_base.gd` (`RacerBase`) + `racer_base.tscn`
- `assault/scenes/race/behaviors/racer_behavior.gd` (base)
- `assault/scenes/race/behaviors/generic_racer_behavior.gd`
- `assault/scenes/race/steering/obstacle_avoidance.gd`
- `assault/scenes/race/steering/bullet_dodge.gd`
- `assault/scenes/race/steering/dash_seeker.gd`
- `assault/scenes/race/racer_targeting.gd`
- `assault/scenes/race/dash_panel.gd` + `dash_panel.tscn`
- `assault/scenes/race/race_hud.gd` + `race_hud.tscn`
- `assault/scenes/levels/race/race_level_1.tscn`
- `assault/scenes/levels/race/race_level_1_config.gd`
- `assault/scenes/race/placeholder_racer.tscn` (generic racer using a reused sprite)
- Test files under the repo's existing test directory.

**Changed:**
- `BackgroundController` (base) — add `set_scroll_multiplier(m)`; `Level1Background`
  reads it in scroll accumulation.
- `WaveBuilder` — add `racer(...)` and `dash_panel()` constructors + scene-path constants.

(WaveManager itself needs no changes.)

---

## 10. Phase Boundary

- **Phase 1 (this spec):** framework + `race_level_1` + dash panel + obstacle wiring +
  `RaceDirector` + `RaceHUD` + **one generic placeholder racer** (spawn 2–3 copies) to
  prove standings, relative-Y, dash boosts, finish, and fail.
- **Phase 2 (next spec):** Fang, Isac, Bogomol (+ `Mine`), Gold Experience, Reacher as
  `RacerBehavior` modules dropped into the same level, each with its signature ability:
  - **Fang** — when behind the player, shoots forward; repositions to sit behind the
    player; diverts to dash panels when the gap is large; avoids obstacles.
  - **Isac** — detects ships within a 300 px radius and sprays Gatling fire at them.
  - **Bogomol** — drops mines behind itself; runs over dash panels and litters them with
    mines to deny others.
  - **Gold Experience** — very agile/fast; self-boost dash that deals contact damage,
    used to close gaps or pull away.
  - **Reacher** — long-range sniper shots at the targeted ship.
  - All Phase-2 logic applies relative to *any* neighbour (rival-vs-rival too), not just
    the player; all use the shared bubble shield + bullet-dodge.
