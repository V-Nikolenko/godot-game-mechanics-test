# Step 01 — Fix AI Bullet Collision Masks

**Priority:** Critical — blocks all racer-vs-racer projectile combat  
**Effort:** Trivial — 1 line  
**File:** `assault/scenes/race/core/race_ship.gd`

---

## Problem

`enemy_bullet.tscn` (used by every AI racer's `RacerWeapon`) places its HitBox on `collision_layer = 256`.

`RaceShip._ready()` sets each AI racer's HurtBox mask:
```gdscript
# race_ship.gd line 30  (current)
hurt_box.collision_mask = 64 | 1024   # = 1088
```

Layer 256 (enemy bullets) is **not** in mask 1088.  
→ Fang's bullets pass straight through Booster Gold. Isac's spray passes straight through Fang. None of the AI shooters can actually hit each other.

The player's HurtBox is on `collision_layer = 128` with `collision_mask = 1281` (includes 256), so player always takes AI bullet damage correctly. Only the AI-vs-AI path is broken.

---

## Fix

**`assault/scenes/race/core/race_ship.gd`, line 30:**

```gdscript
# Before
hurt_box.collision_mask = 64 | 1024

# After
hurt_box.collision_mask = 64 | 256 | 1024   # = 1344
```

That is the **entire change**.

---

## Collision Layer Reference

| Layer (bit) | Decimal | Used by |
|---|---|---|
| 7 | 64 | Player bullet HitBox — also Sensors threat mask |
| 8 | 128 | Player HurtBox layer |
| 9 | 256 | Enemy/AI bullet HitBox (`enemy_bullet.tscn`) |
| 10 | 512 | AI racer HurtBox layer (set by `race_ship.gd`) |
| 11 | 1024 | In racer HurtBox mask; no current emitter but reserved |

After the fix:
- Player bullets (64) → hit AI racers ✓ (was already true)
- AI bullets (256) → now hit AI racers ✓ (new)
- AI bullets (256) → already hit player ✓ (unchanged)
- AI racers cannot be hit by their own bullets (their HurtBox is on layer 512, bullets are on layer 256 — no self-overlap because a HitBox and HurtBox on the same node are on different collision layers and don't self-trigger in Godot)

---

## Affected Racers

| Racer | Weapon | Now hits other AI? |
|---|---|---|
| **Fang** | HUNT state, 8 dmg, 300 speed | ✓ after fix |
| **Booster Gold** | RECLAIM state, 8 dmg, 320 speed | ✓ after fix |
| **Isac** | SPRAY state, 4 dmg, 360 speed, 0.12s rate | ✓ after fix |
| **Reacher** | AIM state, 30 dmg, 700 speed | ✓ after fix |

**Pacer** and **Bogomol** have no weapons and are unaffected.

---

## No Other Files Need Changing

- `DamageReaction` is already wired on every `RaceShip` and handles all incoming damage uniformly via `HurtBox.received_damage`.
- `on_hit` callback in `race_ship.gd` line 33 calls `participant.lose_top_speed_on_hit()` for every hit — this will now fire for AI-vs-AI bullet hits automatically.
- No state machine changes required.
