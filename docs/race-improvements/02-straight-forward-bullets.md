# Step 02 — Straight-Forward Bullets + Forward-Only Firing Constraint

**Priority:** High — defines the tactical feel of racer combat  
**Effort:** Small — 1 core change + 1 guard added to Isac  
**Files:** `assault/scenes/race/core/racer_weapon.gd`, `assault/scenes/race/racers/isac/states/isac_spray_state.gd`

---

## Problem

`racer_weapon.gd`'s `fire_at()` computes:
```gdscript
var dir := (target.global_position - from).normalized()
```
This fires diagonally toward the target's current screen position. Bullets travel at an angle, which:
- Is inconsistent with the "race lane" spatial logic (lanes are vertical strips)
- Makes aiming trivially easy — the bullet homes to the exact position regardless of lateral offset
- Feels wrong visually (bullets curve toward ships instead of flying straight ahead)

**Desired behaviour:** Bullets always fly straight up the screen (`Vector2(0, -1)`) — "forward" in the race coordinate system. A racer must be physically in the correct lane before its shots become effective.

---

## Fix 1: Change `fire_at` direction in `racer_weapon.gd`

`fire_at` is only called by AI states (never by the player weapon system). Change it to always fire forward:

```gdscript
# racer_weapon.gd — fire_at method
# Before:
func fire_at(from: Vector2, target: Node2D, damage: int, speed: float) -> void:
    var dir := (target.global_position - from).normalized()
    fire(from, dir, damage, speed)

# After:
func fire_at(from: Vector2, _target: Node2D, damage: int, speed: float) -> void:
    fire(from, Vector2(0.0, -1.0), damage, speed)
```

The `_target` parameter is kept (prefixed with `_`) so all call sites remain valid without changes.

No changes needed to Fang, BG Reclaim, or Reacher — they all already call `fire_at` with a valid target and have their own `is_lined_up()` / `lane_tol` guard before firing. The direction change is transparent to them.

---

## Fix 2: Add forward-only guard to Isac SPRAY (`isac_spray_state.gd`)

Isac is unique: it fires at the **nearest ship within 320 px**, which can be beside or even slightly behind Isac. With straight-up bullets, those lateral shots would always miss.

Isac needs a forward-target check added before it fires. Use `RaceShip.is_lined_up(target, tol)` which already checks:
1. Target is ahead in `track_y` (the only direction a straight bullet travels into)
2. Target is within `tol` px laterally

**In `isac_spray_state.gd`**, change the fire block (currently something like):

```gdscript
# Before — fires at any ship within spray_radius, no forward check
if _nearest_ship_within(spray_radius) and _fire_t <= 0.0:
    weapon.fire_at(host.muzzle(), prey, bullet_damage, bullet_speed)
    _fire_t = fire_interval
```

To:
```gdscript
# After — only fires if the target is ahead and roughly in-lane
if _nearest_ship_within(spray_radius) and _fire_t <= 0.0:
    if host.is_lined_up(prey, aim_tol):   # aim_tol new export, default 120.0
        weapon.fire_at(host.muzzle(), prey, bullet_damage, bullet_speed)
        _fire_t = fire_interval
```

Add a new export to `isac_spray_state.gd`:
```gdscript
@export var aim_tol: float = 120.0   ## px lateral tolerance; wider than Fang/BG because Isac is a suppressor
```

`120.0` is generous enough that Isac fires when any ship drifts into its forward cone, but tight enough that it won't waste shots at ships purely beside it.

---

## How Existing Forward Guards Work (No Changes Needed)

| Racer | Forward check | Guard location |
|---|---|---|
| **Fang** | `is_lined_up(prey, aim_tol=70)` | `fang_hunt_state.gd` before `weapon.fire_at` |
| **BG Reclaim** | `is_lined_up(target, dash_aim_tol=90)` | `bg_reclaim_state.gd` before `weapon.fire_at` |
| **Reacher** | `lane_tol=90` + `_charge` countdown, only fires in AIM state | `reacher_aim_state.gd` |
| **Isac** | NONE currently — to be added (see Fix 2 above) | |

`is_lined_up()` is defined in `race_ship.gd` lines 60–63:
```gdscript
func is_lined_up(target: RaceParticipant, tol: float) -> bool:
    return absf(global_position.x - target.global_x()) < tol \
        and participant.track_y < target.track_y
```
The second condition (`track_y < target.track_y`) is what ensures "target is ahead" — not just laterally aligned.

---

## Effect on Each Racer

| Racer | Before | After |
|---|---|---|
| **Fang** | Diagonal aimed shots at ~240 track_y gap (≈16° off vertical) | Straight up; nearly identical result since gap is small |
| **BG Reclaim** | Diagonal aimed shots | Straight up; same forward constraint |
| **Isac** | Hosing any ship in 320 px in all directions | Fires at ships ahead only, within 120 px lane cone |
| **Reacher** | Diagonal but near-vertical at 1200 track_y gap (≈4° off) | Straight up; almost identical to before |

---

## Optional: Tighten Lateral Tolerances After This Change

With straight bullets, a racer must be in the correct lane to land a hit. The lateral tolerances (`aim_tol`) now directly control how wide the "fire cone" is rather than being a proxy for aiming. Consider tightening:

- Fang `aim_tol`: 70 px → 50 px  
- BG `dash_aim_tol`: 90 px → 65 px  
- Reacher `lane_tol`: 90 px → 70 px  

These are all `@export` vars — tune in the Godot inspector without code changes.
