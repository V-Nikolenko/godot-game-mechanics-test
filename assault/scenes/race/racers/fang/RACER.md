# Fang — The Tail-Hunter

**Role:** Relentless mid-field duelist. Locks onto whoever is directly ahead, suppresses them with fire, then lunges through them.

**Fantasy:** Clamps onto the nearest ship in front, harasses it, and rams it when lined up. Will hunt a rival leader as readily as the player — Fang doesn't care *who* is in front, only that something is.

---

## Stats

| Property | Value |
|---|---|
| HP | 70 |
| Shield charges | 1 |
| Max top speed | 560 |
| Sprite | `fang.png` |
| Scene | `fang.tscn` |

---

## State Graph

```
        no prey in front
  ┌────────────────────────────┐
  │                            ▼
HUNT ──lined up & in range──▶ LUNGE ──lunge time expires──▶ HUNT
  ▲                            
  └──── threat? (any state) ──▶ DODGE ──clear──▶ HUNT
```

**Initial state:** `FangHunt`

---

## States

### HUNT (`fang_hunt_state.gd`)

The default state. Finds the nearest ship ahead and stalks it.

**Behaviour:**
- Queries `sensors.ship_ahead(hunt_range, lane_tol)` each frame.
- If prey found: holds `follow_gap` behind in track space, matches the prey's lateral X, fires when lined up (within `aim_tol`).
- If prey lined up **and** within `lunge_range` → transitions to **LUNGE**.
- If `sensors.incoming_threat()` is non-null → transitions to **DODGE**.
- If no prey at all: seeks nearest panel (`sensors.nearest_panel_ahead`) — panels only as a fallback, Fang prefers the kill.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `hunt_range` | 2200.0 | track_y units ahead to scan for prey |
| `lane_tol` | 220.0 | px lateral tolerance to count as "in my lane" |
| `follow_gap` | 240.0 | track_y distance to hold behind the prey |
| `lunge_range` | 520.0 | track_y gap at which Fang commits the lunge |
| `aim_tol` | 70.0 | px X alignment required to fire / lunge |
| `fire_cd` | 0.7 s | cooldown between shots |
| `bullet_damage` | 8 | damage per bullet |
| `bullet_speed` | 300.0 | bullet travel speed |

---

### LUNGE (`fang_lunge_state.gd`)

Brief invincible over-speed straight through the prey's lane. Deals contact damage to any ship it passes through.

**Behaviour:**
- On `enter()`: disables the hurtbox (i-frames), applies a forward track_y lunge, sets cruise factor to 1.0.
- Counts down `lunge_time`. Scans for any ship within `contact_radius` each frame — damages each once via `HurtBox.received_damage`.
- When timer expires → re-enables hurtbox → transitions to **HUNT**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `lunge_time` | 0.7 s | how long the dash lasts |
| `lunge_lunge` | 500.0 | extra track_y leap on enter |
| `contact_damage` | 22 | damage dealt per ship passed |
| `contact_radius` | 70.0 | px radius for contact damage scan |

---

### DODGE (`fang_dodge_state.gd`)

Sidestep an incoming threat, then resume hunting.

**Behaviour:**
- Each frame: if `sensors.incoming_threat()` is null → transitions to **HUNT**.
- Otherwise: steers perpendicular to the threat (away by sign of dx), floors speed.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 180.0 | px lateral step away from the threat |

---

## Tuning Notes

- Fang is the **reference racer** for the FSM pattern — the simplest bespoke brain.
- Increasing `hunt_range` makes Fang engage from further back (more aggressive early pressure).
- `lunge_range` should be less than `hunt_range` — Fang closes in HUNT before committing the lunge.
- Reducing `follow_gap` makes Fang crowd the prey more aggressively (higher harassment, riskier for Fang).
- `contact_damage` on the lunge stacks with fire damage — Fang's total DPS is highest when a lunge lands.

---

## Files

```
fang/
├── RACER.md               ← this file
├── fang.tscn
└── states/
    ├── fang_hunt_state.gd
    ├── fang_lunge_state.gd
    └── fang_dodge_state.gd
```
