# Step 05 — Expand AI Threat Detection to Include AI Bullets

**Priority:** Medium — quality-of-life for AI after Step 01 makes AI bullets dangerous  
**Effort:** Trivial — 1 export default change  
**File:** `assault/scenes/race/core/sensors.gd`

---

## Problem

`Sensors` creates a runtime `Area2D` (the "threat area") in `setup()` with:
```gdscript
@export var bullet_mask: int = 64   ## player bullets only
```

The threat area has `collision_mask = bullet_mask`. It detects overlapping `Area2D`s (HitBox nodes on bullets) using `get_overlapping_areas()` each frame — this is the `incoming_threat()` query that all racers use to decide when to dodge.

`collision_mask = 64` means only **player bullets** (layer 64) register as threats. After Step 01, AI bullets (layer 256) can actually damage other AI racers — but those racers still won't dodge them because 256 is not in the threat mask. A ship being shot by Isac from 95 px away won't even flinch.

---

## Fix

**`assault/scenes/race/core/sensors.gd`** — change the export default:

```gdscript
# Before
@export var bullet_mask: int = 64

# After
@export var bullet_mask: int = 64 | 256   # = 320
```

That is the entire change.

---

## Why Self-Dodge Is Not A Problem

Forward-fired bullets (after Step 02) are created at the muzzle, 24 px above the shooter, and immediately travel upward at 300–700 px/s. They exit the 95 px threat-circle radius in under one physics frame. A racer cannot detect its own just-fired bullet before it has already left the sphere.

No shooter-identity filtering is needed.

---

## Why "Forward bullets only come from behind" Means the Logic Is Clean

After Step 02:
- All AI bullets travel straight up (forward)
- A bullet is only fired when the shooter's target is AHEAD (enforced by `is_lined_up`)
- Therefore, a bullet threatening a ship must have originated from a ship BEHIND it

A ship that detects `incoming_threat()` steers sideways away from the bullet's X position — exactly the right response: "something behind me is shooting into my lane, move over."

There is no case where a forward-only bullet from a ship AHEAD poses a threat (it's flying away from you), so expanding the mask cannot produce false positives.

---

## Effect Per Racer

| Racer | Behaviour change |
|---|---|
| **Pacer** | Now dodges AI bullets — uses `add_avoidance()` already, this adds bullet-aware DODGE transitions |
| **Bogomol** | Now dodges AI bullets (previously only dodged player bullets) |
| **Fang** | Now dodges Isac's spray and Reacher's shots, not just player bullets |
| **Booster Gold** | Now dodges Fang, Isac, and Reacher fire |
| **Isac** | Now dodges Fang and BG shots during REPOSITION |
| **Reacher** | Now dodges Isac spray and others during EVADE / CATCH_UP |

---

## Optional: Per-Racer Tuning

`bullet_mask` is an `@export` var so individual racer scenes can override it. For example:
- Give Pacer `bullet_mask = 64` (player-only): simpler, dumber — makes it slightly easier to shoot
- Give Reacher `bullet_mask = 64 | 256` (full threat): the sniper is paranoid and dodges everything

Scene inspector override takes priority over the script default.

---

## Relationship to Step 01

This step only becomes meaningful **after Step 01** (AI bullet masks). Before Step 01, AI bullets pass through AI HurtBoxes and never matter — there's nothing to dodge. Always do Step 01 first.
