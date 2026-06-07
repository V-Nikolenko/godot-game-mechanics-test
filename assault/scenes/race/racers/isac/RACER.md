# Isac — The Area Suppressor

**Role:** Slow-moving turret. Doesn't chase. Positions near ship clusters and hoses everything in radius with sustained gatling fire.

**Fantasy:** A moving no-go zone. Isac doesn't need to aim at the player — it just needs the player to fly near it. Punishes anyone who packs in for a panel or tries to overtake in a crowd.

---

## Stats

| Property | Value |
|---|---|
| HP | 90 (tankiest in the field) |
| Shield charges | 1 |
| Max top speed | 480 (slowest cap) |
| Top speed decay | 14.0/s (very low — steady comfortable pace) |
| Bullet pool size | 24 (large pool to sustain 0.12 s fire rate) |
| Sprite | `Isac.png` |
| Scene | `isac.tscn` |

---

## State Graph

```
PROWL ──ship within spray_radius──▶ SPRAY ──radius empty──▶ PROWL
  └── threat? ──▶ REPOSITION ──(timer)──▶ PROWL
```

**Initial state:** `IsacProwl`

---

## States

### PROWL (`isac_prowl_state.gd`)

Drifts toward the densest part of the field, collecting panels of opportunity.

**Behaviour:**
- If `sensors.incoming_threat()` → **REPOSITION**.
- If `_nearest_ship_within(spray_radius)` returns a ship → **SPRAY**.
- Calls `set_forward_floor()`.
- Calls `sensors.nearest_panel_ahead(panel_reach)`: if found, steers toward it; otherwise holds current X.

`_nearest_ship_within(r)` — internal helper: scans `"player"` and `"racers"` groups for the nearest ship within `r` px of Isac's position. Used in both PROWL and SPRAY.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `spray_radius` | 320.0 | px radius to detect ships (must match SPRAY) |
| `panel_reach` | 600.0 | px to scan for panels |

---

### SPRAY (`isac_spray_state.gd`)

Sustained continuous fire at the nearest ship in radius. Isac barely moves during this — it occupies space, not chases.

**Behaviour:**
- If `sensors.incoming_threat()` → **REPOSITION**.
- If `_nearest_ship_within(spray_radius)` returns null → **PROWL**.
- Calls `set_forward_coast(0.8)` (slightly slower; Isac decelerates while spraying).
- Steers a small amount toward the target's X side (40 px nudge) — drifts to stay in range, not chase.
- Fires at `fire_interval` using `weapon.fire_at(host.muzzle(), prey, bullet_damage, bullet_speed)`.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `spray_radius` | 320.0 | px radius — must match PROWL |
| `fire_interval` | 0.12 s | time between shots (very fast) |
| `bullet_damage` | 4 | low per-bullet, high sustained DPS |
| `bullet_speed` | 360.0 | bullet travel speed |

---

### REPOSITION (`isac_reposition_state.gd`)

Brief slide off a direct threat. Never fully retreats — just a short displacement.

**Behaviour:**
- Counts down `slide_time`.
- If a threat is present, steers away from it by `sidestep` px; otherwise steps the same direction as entered.
- When timer expires → **PROWL**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 150.0 | px lateral step |
| `slide_time` | 0.4 s | duration of reposition |

---

## Tuning Notes

- Isac's 90 HP and tanky decay mean it survives prolonged engagements where a lighter racer would be knocked back.
- `spray_radius = 320` is the radius *of the occupied zone*. Increase for a larger suppression area; decrease to make it easier to outflank.
- `fire_interval = 0.12 s` means ~8 rounds/second. At `bullet_damage = 4` that's ~33 DPS — enough to drain a full shield in under 2 seconds if caught inside.
- Isac's low `max_top_speed = 480` means it naturally falls toward the back of the pack. It compensates by being dangerous to pass — ships that overtake it enter its spray zone.
- The `set_forward_coast(0.8)` during SPRAY means Isac doesn't accelerate while firing. If you want a more aggressive tracking Isac, increase this toward 1.0.

---

## Files

```
isac/
├── RACER.md                  ← this file
├── isac.tscn
└── states/
    ├── isac_prowl_state.gd
    ├── isac_spray_state.gd
    └── isac_reposition_state.gd
```
