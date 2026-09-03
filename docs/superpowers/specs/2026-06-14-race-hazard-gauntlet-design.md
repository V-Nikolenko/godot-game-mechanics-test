# Race Hazard Gauntlet + Speed Feel — Design

**Date:** 2026-06-14
**Status:** Approved (design); pending implementation plan
**Module:** `assault/scenes/race/` (race sub-mode) — see `docs/architecture/modules/assault.md`

---

## Problem / Goal

The race mode simulates a 7-ship combat race well, but the auto-scrolling track is mostly
empty between dash panels, a fast leader can run away (tension drops), and it does not yet
*feel* fast. Turn each race into a **reflex gauntlet**: seed the track with lethal,
authored hazards that always leave a survivable option, make AI avoid them (and die when
cornered), give the player throttle agency, and add a light sense-of-speed layer.

Two pillars (from brainstorming): **(1) sense of speed & flow**, **(2) track variety &
gauntlets**.

---

## Pillars / pitch

- The track is seeded with **one-shot hazards** that always leave a survivable line.
- **Survival is the new skill floor**; speed is the reward for threading cleanly.
- The pack **thins via attrition** — AI that get boxed in die, creating overtakes/drama.
- It **feels fast**: speed-reactive streaks + a boost punch on panels.

---

## Current systems reused (measured)

- **DashPanel** (`track/dash_panel.gd`) — a `Track` child placed at negative Y; scrolls
  naturally; geometric per-ship poll. The authoring + culling pattern every hazard copies.
- **AsteroidBase** (`hazards/asteroid_base.gd`) — `CharacterBody2D` + `Health` + `HurtBox`
  (rocket damage → break/split) + `ContactHitBox` (one-shots at speed). The breakable-wall
  blueprint.
- **laser_ray** (`hazards/laser_ray/laser_ray.gd`) — state machine `init→increase→idle→
  dissolve`, `active_duration`, `warn_duration`, `_KILL_DAMAGE = 9999`, tiled beam, plus a
  `laser_wall.tscn` variant. The laser blueprint.
- **RaceParticipant** (`core/race_participant.gd`) — `track_y`, top-speed economy,
  `cruise_factor` (AI ease-off), `panel_lunge = 650`, `add_lunge()`.
- **RaceShip / sensors / brains** (`core/race_ship.gd`, `core/sensors.gd`, `racers/*`) —
  `desired_x`, `steer_toward()`, `nearest_panel_ahead`, `ship_ahead`, `incoming_threat`;
  bespoke per-racer FSMs.
- **PlayerRaceController** (`player_race_controller.gd`) — player screen-Y band clamp.
- **RaceWorld** (`core/race_world.gd`) — scrolls `Track` by `player.track_y`.
- **RaceDirector** (`core/race_director.gd`) — standings, `register/unregister`,
  `race_failed`.
- **Player rockets** — `player/states/warhead_missile_shooting_state.gd`,
  `projectiles/missiles/`, `projectiles/primary_homing/`.
- **Wall asset** — `assault/assets/sprites/racers/race_track/walls/wall_1.png`.

---

## Architecture

### A. Track-hazard contract (the backbone)

A uniform contract so AI sensing, lethal contact, and authoring all share one source of
truth. A hazard:

- is placed as a child of `Track` (authored at negative Y, like dash panels) and scrolls
  with the world;
- joins group **`race_hazards`**;
- exposes its **lethal zone** in world space and whether it is lethal *right now*:
  - `func danger_rect() -> Rect2` — world-space rectangle of the lethal area (partial for
    walls/vertical lasers, full-width for horizontal lasers).
  - `func is_lethal_now() -> bool` — always `true` for walls/asteroids; for lasers, only
    during the active state.
  - `func lethal_eta() -> float` — seconds until it next becomes lethal (`0` = active now,
    `INF` = never/again). Used by AI laser timing. Walls/asteroids return `0`.

A small base script `core/track_hazard.gd` (`class_name TrackHazard`) provides the group
registration + default implementations; the wall extends it, and thin adapters expose the
same three methods for reused asteroid/laser scenes (duck-typed — callers use
`has_method`, matching the existing project style).

### B. HazardSystem — lethal contact (one place)

A `core/hazard_system.gd` node (sibling of `RaceLevelConfig`, like `WallBarrier`) polls,
each `_physics_process`, every ship in `["player","racers"]` against every on-screen
`race_hazards` member whose `is_lethal_now()`. On overlap (ship centre inside
`danger_rect()` + small margin) it calls the ship's **lethal** path — which **bypasses
shields** (a hazard is an instakill obstacle, not a combat hit):

- Player → `RaceDirector.race_failed` (instant fail → existing reload).
- AI racer → eliminate: explosion, `unregister` from standings, `queue_free`.

Ships expose `func apply_lethal_hazard() -> void` (player + RaceShip) so the system has a
single, shield-bypassing kill entrypoint. Centralising contact here (rather than per-hazard
`ContactHitBox`) keeps "where is lethal" identical to what the AI reads for avoidance.

### C. Hazard types

1. **Breakable wall** — `track/race_wall.gd` + `race_wall.tscn` (NEW). Reuses the
   `AsteroidBase` pattern: `Sprite2D` (`wall_1.png`), `Health` + `HurtBox` (player rockets
   damage it → at 0 HP it breaks: explosion, leave `race_hazards`, `queue_free`). **Partial
   width** (narrower than the 128–1152 lane) placed at an authored X → always dodgeable.
   `danger_rect()` = its world rect; `is_lethal_now()` = `true`; rocket-break is optional
   (cleaner line) **except** in trap placements (§E).

2. **Asteroid on track** — reuse `big/small_asteroid` via a thin adapter
   (`track/race_asteroid.gd` or a `static_on_track`/`race_hazard` flag on `AsteroidBase`):
   no `EnemyPathMover`, no off-screen self-free until scrolled well past, joins
   `race_hazards`, lethal-on-contact via HazardSystem. Still rocket-breakable (existing
   HurtBox), dodgeable.

3. **Horizontal laser** — full-width timing gate at a Y. Reuses `laser_ray` state machine:
   telegraphed `warn` → lethal `active` → off. `danger_rect()` spans the full lane;
   `is_lethal_now()` true only while active; `lethal_eta()` from the warn timer.
   Indestructible. Survive by crossing while off (boost through before it fires, or slow and
   wait, then cross).

4. **Vertical laser** — lethal lateral band along a Y stretch (reuse the vertical
   `laser_ray` beam). `danger_rect()` = the band's X span × its Y length; lethal while
   active. Dodge laterally out of the band. Indestructible.

### D. Player throttle / brake (flow)

The player's `track_y` auto-advances, so to time a laser they need to slow down. Add a
**throttle**: `throttle ∈ [throttle_min..1]` (default 1). A brake input (hold) lowers it;
the player's forward advance becomes `top_speed * throttle`, so the world (scrolled by
`player.track_y` in `RaceWorld`) slows and the player drops back. Release → 1; dash
panels/forward speed still boost through. Lives on `PlayerRaceController` (reads input,
writes the player `RaceParticipant.cruise_factor`, which `RaceParticipant._physics_process`
must apply to the player too — currently the player ignores `cruise_factor`). Brake input:
a `race_brake` action (default: hold **Down**).

### E. Trapped panels (rocket-or-die routes)

No new node — emergent from authoring: a wall placed within the panel's lunge distance
(`≤ panel_lunge = 650` track_y) **behind** a dash panel, in the same lane. Crossing the
panel lunges you `+650` into the wall before you can steer clear, so the only survival is
to **rocket the wall** (or never take that panel). Other lanes' panels remain safe.

### F. AI behavior — shared reflex + route refusal + attrition

A **reflex layer** runs in `race_ship.gd` *before* the personality FSM each frame, using new
`sensors.gd` queries over `race_hazards`:

- `hazard_ahead(lookahead) -> Node2D` — nearest lethal/danger hazard within Y lookahead
  whose `danger_rect()` overlaps my projected lane.
- `safe_x(current_x, lookahead) -> float` — nearest X clear of all hazard danger spans at
  the lookahead (uses the authored guarantee that a gap exists).
- `laser_plan(hazard) -> enum {CLEAR, BRAKE, SPEED_THROUGH}` — for horizontal lasers, from
  `lethal_eta()` vs my ETA to its Y at current speed.
- `panel_is_trapped(panel) -> bool` — a wall hazard sits within `panel_lunge` behind the
  panel in its lane.

Reflex actions (override the FSM's intent for that frame):
- **Lateral dodge** (walls, asteroids, vertical lasers): set `desired_x = safe_x(...)`.
- **Temporal timing** (horizontal laser): `BRAKE` → `cruise_factor → 0` and hold before
  its Y; `SPEED_THROUGH` → `cruise_factor → 1`.
- **Route refusal**: brains that seek panels (`nearest_panel_ahead`) skip any
  `panel_is_trapped` panel.
- **Attrition**: if no `safe_x` is reachable in time (boxed by ships + hazards), the ship
  takes the hit → `apply_lethal_hazard()` eliminates it. The 6 personalities keep
  racing/fighting on top of the survival reflex.

### G. Speed-feel layer (light)

- **Speed streaks** — a `CanvasLayer` overlay (`ui/speed_streaks.gd` + scene; GPUParticles2D
  or a shader) whose intensity/alpha scales with the player `top_speed_fraction()`.
- **Boost punch** — on `RaceParticipant.panel_boosted`, a quick `Camera2D.zoom` kick tween
  (and a streak spike) so panels feel impactful.

---

## Authoring conventions

Designers place hazard scenes under `Track/RaceTrack` at negative Y (same convention as
dash panels), **staggered so at least one survivable option always exists** at every Y:
- walls/asteroids/vertical lasers → leave a clear X gap;
- horizontal lasers → a crossable off-window;
- trapped panels → an alternative safe lane.

---

## Phased implementation

1. **Core gauntlet** — `TrackHazard` contract + group, `HazardSystem` (overlap → lethal;
   player fail, AI eliminate, shield-bypass), breakable wall, asteroid-on-track adapter,
   `sensors` hazard scan + lateral-dodge reflex, AI elimination/attrition for lateral
   hazards.
2. **Lasers + throttle** — horizontal & vertical laser hazards (telegraph, `is_lethal_now`,
   `lethal_eta`), player throttle/brake (`race_brake` action), AI `laser_plan` timing.
3. **Traps + route refusal** — `panel_is_trapped` + brain route refusal, attrition tuning.
4. **Speed FX** — speed-streak overlay + boost zoom-punch.

Each phase is independently testable by play-observation (no automated race tests exist).

---

## Files

| File | Change |
|---|---|
| `assault/scenes/race/core/track_hazard.gd` | **NEW** — `TrackHazard` base (group + `danger_rect`/`is_lethal_now`/`lethal_eta`) |
| `assault/scenes/race/core/hazard_system.gd` | **NEW** — central lethal-contact poll (player fail / AI eliminate, shield-bypass) |
| `assault/scenes/race/track/race_wall.gd` + `.tscn` | **NEW** — breakable partial wall (`wall_1.png`, asteroid pattern) |
| `assault/scenes/race/track/race_asteroid.gd` (or `AsteroidBase` flag) | **NEW/EDIT** — static-on-track asteroid adapter |
| `assault/scenes/race/track/race_laser.gd` + `.tscn` | **NEW** — horizontal & vertical laser hazards (reuse `laser_ray` SM) |
| `assault/scenes/race/core/sensors.gd` | **EDIT** — `hazard_ahead`, `safe_x`, `laser_plan`, `panel_is_trapped` |
| `assault/scenes/race/core/race_ship.gd` | **EDIT** — pre-FSM avoidance reflex + `apply_lethal_hazard()` (AI eliminate) |
| `assault/scenes/race/racers/*/states/*` | **EDIT** — panel-seeking states skip trapped panels |
| `assault/scenes/race/core/race_participant.gd` | **EDIT** — apply `cruise_factor` to the player too (throttle) |
| `assault/scenes/race/player_race_controller.gd` | **EDIT** — `race_brake` input → player throttle; `apply_lethal_hazard()` → fail |
| `assault/scenes/race/race_level_config.gd` | **EDIT** — instance `HazardSystem`; wire boost-punch |
| `assault/scenes/race/ui/speed_streaks.gd` + `.tscn` | **NEW** — speed-reactive overlay |
| `assault/scenes/systems/arena_camera.gd` (or RaceWorld) | **EDIT** — zoom-punch on `panel_boosted` |
| `assault/scenes/levels/race/race_level_1.tscn` | **EDIT** — author a first hazard gauntlet |
| `project.godot` | **EDIT** — add `race_brake` input action |
| Docs (`assault.md`, per-entity docs, `enemy-roster`/hazard docs) | **EDIT** — via `updating-project-docs` skill after structural changes |

---

## Verification (play-observation)

1. **Walls** — fly into a partial wall → instant race fail; dodge the gap → pass; rocket it
   → it breaks and clears.
2. **Trapped panel** — take a panel with a wall behind it without firing → lunged into the
   wall → fail; rocket the wall first → survive; skip the panel → survive.
3. **Asteroids** — placed asteroids scroll with the track, one-shot on contact, rocket-break.
4. **Horizontal laser** — telegraphed; boosting through before active = safe; arriving while
   active = fail; braking to wait then crossing = safe.
5. **Vertical laser** — staying out of the lethal band = safe; entering while active = fail.
6. **AI** — racers visibly dodge walls/asteroids, time lasers (brake or floor it), skip
   trapped panels; a boxed-in racer dies and leaves the standings (attrition).
7. **Throttle** — holding brake slows the world/drops the player back; releasing recovers.
8. **Speed feel** — streaks intensify near max speed; panels give a visible zoom punch.

---

## Notes / constraints

- **Never commit** — the user handles git; all changes left unstaged.
- Lethal hazard contact **bypasses shields** by design (instakill obstacle).
- Authoring must guarantee a survivable option at every Y; the AI `safe_x`/`laser_plan`
  rely on it. A genuinely unsurvivable placement would kill the whole field (acceptable
  failure mode, but flagged for level design).
- After structural changes, invoke the **`updating-project-docs`** skill to refresh the
  knowledge base (new race hazard entities get per-entity docs).
