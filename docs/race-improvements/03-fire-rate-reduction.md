# Step 03 — Reduce AI Fire Rates

**Priority:** Medium — balance pass after Steps 01 and 02 enable racer-vs-racer damage  
**Effort:** Trivial — export var default changes only, no logic changes  
**Files:** `fang_hunt_state.gd`, `bg_reclaim_state.gd`, `isac_spray_state.gd`

---

## Problem

Current fire rates were tuned before AI bullets could hit other AI racers (the mask bug from Step 01). Once all racers shoot each other:
- Isac's 0.12 s fire interval (~8 rounds/sec) at 4 dmg = ~33 sustained DPS — lethal to any ship in seconds
- Fang fires every 0.7 s; with 5 racers on the track this creates nonstop bullet spray
- BG Reclaim fires every 0.5 s while chasing

These rates made sense when only the player was at risk. With racer-vs-racer damage live, mid-pack ships would shred each other in seconds. The race would become a lottery of who clears the field fastest.

---

## Changes

### Fang — `assault/scenes/race/racers/fang/states/fang_hunt_state.gd`

```gdscript
# Before
@export var fire_cd: float = 0.7

# After
@export var fire_cd: float = 1.4
```

One shot every ~1.4 s. Fang is a hunter, not a gunship — the lunge is its primary kill tool. The bullet is a harassment/top-speed debuff, not the main damage source.

---

### Booster Gold — `assault/scenes/race/racers/booster_gold/states/bg_reclaim_state.gd`

```gdscript
# Before
@export var fire_cd: float = 0.5

# After
@export var fire_cd: float = 1.0
```

One shot per second while reclaiming. BG fires only from RECLAIM (when not leading) and only when lined up. The dash is the lethal tool; the bullet is a lane-denial harass.

---

### Isac — `assault/scenes/race/racers/isac/states/isac_spray_state.gd`

```gdscript
# Before
@export var fire_interval: float = 0.12   # ~8 shots/sec

# After
@export var fire_interval: float = 0.25   # ~4 shots/sec
```

Still the fastest fire rate in the field by a large margin. At 4 dmg × 4 shots/sec = 16 DPS in the suppression zone. A ship that stays in Isac's cone for 4 seconds will lose a full shield + ~24 HP — enough to deny the lane without instantly deleting a racer.

Isac's identity is "scary to pass, punishing to stay near" — it should feel threatening but not impossible to survive.

---

### Reacher — No Change

Reacher fires once every ~1.55 s (0.35 s telegraph + 1.2 s recharge). This is already slow and balanced for a sniper. The 30 damage is high but the shot is telegraphed and dodgeable. Leave as-is.

---

## These Are @export Vars

All three values can be overridden **in the Godot scene inspector** per-instance without touching the script. Changing the script defaults affects all instances that haven't been overridden in a scene.

If the race uses multiple instances of the same racer type, set per-instance values in the scene to fine-tune further.

---

## Reference: Fire Rate → DPS Table (after changes)

| Racer | Dmg/bullet | Rate | DPS | Notes |
|---|---|---|---|---|
| Isac | 4 | 0.25 s | 16 | Only within 320 px suppression zone |
| BG Reclaim | 8 | 1.0 s | 8 | Forward-lane only while not leading |
| Fang | 8 | 1.4 s | 5.7 | Forward-lane; lunge (22 dmg contact) adds burst |
| Reacher | 30 | ~1.55 s | 19 (burst) | Single shot, telegraphed, very hard to land |
