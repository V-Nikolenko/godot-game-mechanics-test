# Track Side-Wall Collisions — Design

**Date:** 2026-06-07
**Status:** Approved (design); pending implementation plan

---

## Problem

The race track has left/right side walls, but they are a **visual-only**
`TileMapLayer` (`Track/RaceTrack/Layer0`) with no physics or collision. Ships fly
through them freely. We want the side walls to behave like the dash-panel walls:
**push the ship back and deal damage on contact**, and additionally act as a **hard
barrier** the player cannot leave.

The damage + push reaction is currently duplicated conceptually inside
`race_level_config._on_panel_wall_hit()`. We want one reusable reaction shared by both
the dash panels and the side walls.

---

## Current state (measured)

- **Side walls** are two straight vertical tile bands (4 tiles = 256 px wide each),
  at fixed X, running the full track length. They scroll vertically with `Track`; X
  is constant in world space.
  - Left band inner edge ≈ **x = 128**
  - Right band inner edge ≈ **x = 1152**
  - Playable lane ≈ x ∈ [128, 1152] (≈1024 px, centred on 640; screen is 1280 wide).
  - The TileSet has **no physics layer** — tiles are decorative only.
- **Dash-panel reaction** is centralised: `DashPanel` only *detects* a wall clip and
  emits `body_wall_hit(ship, part, push_dir, damage, pushback)`;
  `race_level_config._on_panel_wall_hit()` performs the reaction:
  - `HurtBox.received_damage.emit(damage)` (routes through shield → HP for both ship
    types).
  - Player → `apply_knockback(push_dir * WALL_KNOCKBACK_PLAYER)` (420 px/s velocity
    impulse that survives held input).
  - AI → `global_position.x += push_dir * pushback` then `steer_toward(...)`
    (AI ships are assignment-positioned, not physics-driven).
- **Ship vs ship / dash walls** detection is **geometric polling** (iterating the
  `player` and `racers` groups), not physics signals, because AI racers do **not** use
  `move_and_slide` and pass through `StaticBody2D` collisions.

---

## Chosen approach

**Shared reaction helper + a `TrackSideWalls` scene that copies the dash-panel
collision mechanism.** The side walls get real `StaticBody2D` + `CollisionShape2D`
nodes (left and right), exactly like `DashPanel`'s `WallL`/`WallR`. The `StaticBody2D`
physically blocks the **player** (it is a `CharacterBody2D` using `move_and_slide`),
giving the hard barrier "for free" — no manual position clamp. The same **geometric
poll** the dash panel uses (`_in_shape` point-in-rect against those collision shapes,
with a margin) detects contact for *all* ships — including AI racers, which pass
through `StaticBody2D` because they are assignment-positioned — and routes the hit into
the shared `WallImpact.resolve()`.

(Rejected: a fixed-X float boundary check + manual player clamp — works, but does not
reuse the dash-panel collision mechanism the project already has; the user asked to use
collisions like the dash panel. Rejected: a TileSet physics layer on the wall tiles —
AI still pass through and per-tile collision is heavier. Rejected: per-wall `Area2D`
overlap — the dash panel's geometric poll is the established pattern and works for AI.)

---

## Components

### 1. `WallImpact` — shared reaction (NEW)

A stateless helper holding the single copy of the "ship clipped a wall" reaction. Both
the dash-panel handler and the side-wall detector call it.

- Type: `class_name WallImpact extends RefCounted` (pure static logic — no scene
  wiring, no per-instance state).
- Location: `assault/scenes/race/core/wall_impact.gd`.
- API:
  ```
  const KNOCKBACK_PLAYER_SPEED : float = 420.0   ## px/s for the player velocity impulse

  static func resolve(ship: Node2D, push_dir: float, damage: int, ai_push: float) -> void
  ```
- Behaviour (identical to today's `_on_panel_wall_hit`):
  1. `hb := ship.get_node_or_null("HurtBox")`; if present, `hb.received_damage.emit(damage)`.
  2. If `ship.has_method("apply_knockback")` (player):
     `ship.apply_knockback(Vector2(push_dir * KNOCKBACK_PLAYER_SPEED, 0.0))`.
  3. Else if `ship.has_method("steer_toward")` (AI racer):
     `ship.global_position.x += push_dir * ai_push`; `ship.steer_toward(ship.global_position.x)`.
- `push_dir`: +1 pushes toward +X (right / track centre from the left wall), −1 toward
  −X. Caller decides based on which wall/side was hit.

### 2. `TrackSideWalls` — collision walls + detector (NEW SCENE)

A small scene that mirrors `DashPanel`'s wall mechanism: physical `StaticBody2D`
collision for the player's hard barrier, plus a geometric poll for damage+push on all
ships. It is the authority on side-wall collisions for the level.

- Scene: `assault/scenes/race/track/track_side_walls.tscn`; script
  `assault/scenes/race/core/track_side_walls.gd` (`class_name TrackSideWalls`).
- Node tree (positions are world-space; measured from the wall tilemap):
  ```
  TrackSideWalls (Node2D, script)
  ├─ LeftWall (StaticBody2D, collision_layer = 1)
  │   └─ LeftShape (CollisionShape2D)  RectangleShape2D size (256, 1600), position (0, 360)
  │        → spans world X [-128, 128]  → inner (right) face at x = 128
  └─ RightWall (StaticBody2D, collision_layer = 1)
      └─ RightShape (CollisionShape2D) RectangleShape2D size (256, 1600), position (1280, 360)
           → spans world X [1152, 1408] → inner (left) face at x = 1152
  ```
  - `collision_layer = 1` matches the dash-panel walls, so the player
    (`CharacterBody2D`, mask 1) is blocked by `move_and_slide`. AI racers do not use
    `move_and_slide` and pass through — handled by the geometric poll below.
  - Vertical size 1600 centred on y=360 covers the player's roam band (`move_state`
    clamps y∈[-380, 1100]); the walls are screen-fixed (X never scrolls), so a child of
    `RaceLevel1` is correct — it does **not** go under the scrolling `Track`.
- Exports (geometry lives in the scene's shapes; these tune the reaction):
  | Export | Default | Meaning |
  |---|---|---|
  | `wall_damage` | `15` | Damage per hit (matches dash panel) |
  | `wall_ai_push` | `60.0` | AI positional nudge px (matches dash panel) |
  | `hit_cooldown` | `0.6` | Seconds between re-hits per ship (matches dash panel) |
  | `wall_margin` | `20.0` | Detection margin so a ship blocked one body-radius outside the rect still registers (same value/justification as `DashPanel.WALL_MARGIN`) |
- `@onready` refs to `LeftShape` and `RightShape` (the two `CollisionShape2D`s).
- State: `_cooldowns: Dictionary` — `String(instance_id) -> seconds remaining`.
- `_physics_process(delta)`:
  1. Tick down and prune `_cooldowns` (same pattern as `DashPanel._tick_cooldowns`).
  2. For each ship in groups `["player", "racers"]` (skip null / no `RaceParticipant`):
     - `pos := ship.global_position`
     - If `_in_shape(pos, _left_shape, wall_margin)` → `_try_hit(ship, _left_shape)`
     - Else if `_in_shape(pos, _right_shape, wall_margin)` → `_try_hit(ship, _right_shape)`
  - `_try_hit(ship, shape)`: if `ship` is on cooldown, return; else set cooldown and
    `WallImpact.resolve(ship, signf(pos.x - shape.global_position.x), wall_damage, wall_ai_push)`.
    `push_dir = signf(pos.x - wall_centre)` shoves the ship toward the track centre
    regardless of which face it touched — identical to the dash panel's wall push.
- `_in_shape(world_pos, col, x_margin)`: point-in-rect test with X-margin and scale
  handling — the **same helper `DashPanel` uses**. Kept as a small private method here
  mirroring `dash_panel.gd` (a ~10-line pure function; if a third caller appears it can
  be extracted to a shared static, but duplicating it now keeps the working `DashPanel`
  untouched).

**No manual player clamp.** The hard barrier is the `StaticBody2D` physics block — the
player simply cannot `move_and_slide` through it, exactly as with the dash-panel walls.
The geometric poll only adds the damage + knockback on contact.

### 3. `race_level_config._on_panel_wall_hit` — delegate (EDIT)

- Body collapses to: `WallImpact.resolve(ship, push_dir, damage, pushback)`.
- The `WALL_KNOCKBACK_PLAYER` const is **removed** (its value lives in
  `WallImpact.KNOCKBACK_PLAYER_SPEED`).
- The push-direction computation already done in `dash_panel.gd` (`signf(pos.x -
  wall_center)`) is unchanged — it still produces `push_dir` and passes it through.

---

## Data flow

```
Dash panel:  DashPanel._physics_process ──body_wall_hit──▶ race_level_config
                                                            ._on_panel_wall_hit ──┐
                                                                                  │
Side walls:  TrackSideWalls._physics_process ─────────────────────────────────────┤
             (geometric _in_shape against its own CollisionShape2D walls)         │
                                                                                  ▼
                                                   WallImpact.resolve(ship, dir, dmg, push)
                                                       ├─ HurtBox.received_damage → shield→HP
                                                       ├─ player: apply_knockback (impulse)
                                                       └─ AI: global_position.x += ; steer_toward

Hard barrier (player only): StaticBody2D walls block move_and_slide — pure physics,
no code path.
```

---

## Behaviour summary

| Ship | Side wall | Dash-panel wall |
|---|---|---|
| **Player** | `StaticBody2D` block + knockback + damage (cooldown) | `StaticBody2D` block + knockback + damage (cooldown) |
| **AI racer** | Push (positional nudge) + damage (cooldown), pass-through | Push + damage (cooldown), pass-through |

Player knockback pushes *toward track centre* (away from the wall); the `StaticBody2D`
prevents leaving, so the two coexist (the body blocks outward, the knockback shoves
inward). This is exactly the dash-panel wall behaviour — now applied to the long side
walls.

---

## Edge cases & decisions

- **Hard barrier is physics, not a clamp:** The player is blocked by the `StaticBody2D`
  via `move_and_slide`, identical to the dash-panel walls — no race-specific clamp is
  added to `move_state` (which stays generic for non-race levels).
- **AI pass through, geometric reaction only:** AI racers are assignment-positioned and
  do not collide with `StaticBody2D`, so the geometric poll is what damages/pushes them
  — same as at dash-panel walls. AI steer within lanes; the positional nudge corrects
  drift.
- **`wall_margin` for blocked players:** A player blocked by the body stops with its
  *centre* one body-radius (~13.77 px) outside the collision rect. The geometric poll
  therefore needs a margin to register the contact — same reason and value (~20) as
  `DashPanel.WALL_MARGIN`.
- **Screen-fixed walls (not under `Track`):** The walls never move in X and span the
  player's full Y roam, so a single pair of tall static shapes on `RaceLevel1` is
  simpler and equivalent (for gameplay) to scrolling per-segment collision. The visual
  tile walls under `Track` are unchanged and purely decorative.
- **Wall geometry from the tilemap:** Left band world X [-128, 128] (inner face 128),
  right band [1152, 1408] (inner face 1152), measured by decoding `Layer0`. Encoded as
  the scene's shape sizes/positions; a designer retunes by moving the shapes.
- **`has_method` ship-type test:** Player has `apply_knockback`; AI has `steer_toward`.
  Existing convention in `WallImpact`/`race_level_config` — reused, not introduced.

---

## Files

| File | Change |
|---|---|
| `assault/scenes/race/core/wall_impact.gd` | **NEW** — `WallImpact` static reaction helper |
| `assault/scenes/race/core/track_side_walls.gd` | **NEW** — `TrackSideWalls` script (collision walls + geometric detector) |
| `assault/scenes/race/track/track_side_walls.tscn` | **NEW** — scene: 2× `StaticBody2D` + `CollisionShape2D` + the script |
| `assault/scenes/race/race_level_config.gd` | **EDIT** — `_on_panel_wall_hit` delegates to `WallImpact`; remove `WALL_KNOCKBACK_PLAYER` |
| `assault/scenes/levels/race/race_level_1.tscn` | **EDIT** — instance `track_side_walls.tscn` under `RaceLevel1` |

---

## Verification (play-observation; no automated race tests exist)

1. **Side wall damage + push:** Fly the player into the left or right wall — it takes
   damage (shield first, then HP) and is shoved back toward centre, on a ~0.6 s
   cooldown. Same feel as ramming a dash-panel wall.
2. **Hard barrier:** Hold the player into a side wall — it cannot pass beyond the inner
   edge; it sits at the wall and takes periodic damage.
3. **AI:** Nudge/observe an AI racer drifting into a wall — it gets pushed back toward
   its lane and takes damage; it is not hard-blocked (consistent with dash panels).
4. **No regression on dash panels:** Dash-panel wall hits still damage + knock back
   exactly as before (now routed through `WallImpact`).
5. **Shields honoured:** First N side-wall hits are absorbed by shield charges before HP
   drops (same path as bullets/mines/dash walls).
