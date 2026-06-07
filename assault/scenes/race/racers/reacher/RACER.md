# Reacher — The Long-Range Sniper

**Role:** Calculated back-marker. Holds a deliberate stand-off gap behind the target, times a telegraphed heavy shot, and fires. Punishes anyone who runs far ahead in a straight line.

**Fantasy:** The racer that makes *leading* dangerous. Reacher doesn't brawl — it waits for the right geometry, charges its weapon, and lands a single devastating shot. You can outrun it, but you can't outrun the bullet.

---

## Stats

| Property | Value |
|---|---|
| HP | 65 |
| Shield charges | 1 |
| Max top speed | 560 |
| Sprite | `reacher.png` |
| Scene | `reacher.tscn` |

---

## State Graph

```
POSITION ──clean LOS & charged──▶ AIM ──fires──▶ POSITION (recharge)
    │
    ├── threat? ──▶ EVADE ──clear──▶ POSITION
    │
    └── falling too far back ──▶ CATCH_UP ──recovered──▶ POSITION
```

**Initial state:** `ReacherPosition`

---

## States

### POSITION (`reacher_position_state.gd`)

The primary state. Keeps a deliberate stand-off distance behind the nearest target and charges the shot.

**Behaviour:**
- If `sensors.incoming_threat()` → **EVADE**.
- If `director.gap_to_leader(participant) > fall_behind_gap` → **CATCH_UP**.
- Queries `sensors.ship_ahead(8000, 9999)` — any ship ahead at any lateral distance (Reacher doesn't need to be in the same lane to aim).
- Calls `set_forward_match(target, standoff_gap)` — paces target at `standoff_gap` track_y behind.
- Steers toward target's X to open line of sight.
- Ticks down `_charge` timer (pre-loaded on `enter()`).
- When `_charge <= 0` AND target is within `lane_tol` px laterally → stores target in `ReacherAim.target` → **AIM**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `standoff_gap` | 1200.0 | track_y to hold behind the target |
| `lane_tol` | 90.0 | px lateral alignment required to fire |
| `fall_behind_gap` | 3000.0 | track_y behind leader that triggers CATCH_UP |
| `charge_time` | 1.2 s | how long between shots (recharge time) |

---

### AIM (`reacher_aim_state.gd`)

Telegraphed wind-up followed by a single heavy bullet. The brief pause is the readable tell.

**Behaviour:**
- Calls `set_forward_coast(0.7)` — slows slightly while aiming (intentional; creates a visual settle).
- Steers toward `target`'s X to maintain alignment.
- Counts down `telegraph` timer.
- When expired: if target is still valid → fires one bullet via `weapon.fire_at(muzzle, target.ship(), snipe_damage, snipe_speed)` → transitions to **POSITION** (which starts recharging immediately).

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `telegraph` | 0.35 s | visible wind-up before the shot fires |
| `snipe_damage` | 30 | heavy hit — roughly 1/3 of a racer's HP in one shot |
| `snipe_speed` | 700.0 | very fast bullet, hard to dodge once fired |

---

### CATCH_UP (`reacher_catchup_state.gd`)

Temporary departure from sniping when Reacher has drifted too far back. Prioritises panels to restore top speed.

**Behaviour:**
- If `sensors.incoming_threat()` → **EVADE**.
- Floors speed.
- Seeks `sensors.nearest_panel_ahead(900)` — panel-greedy until recovered.
- When `director.gap_to_leader < recovered_gap` → **POSITION**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `recovered_gap` | 1600.0 | track_y behind leader at which Reacher returns to sniping |

---

### EVADE (`reacher_evade_state.gd`)

Standard dodge. Returns to POSITION when clear.

**Behaviour:**
- If `sensors.incoming_threat()` is null → **POSITION**.
- Steers away by `sidestep` px, floors speed.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 170.0 | px lateral step |

---

## Tuning Notes

- `snipe_speed = 700` makes the bullet extremely fast — the player's dodge window after the shot fires is very short. The `telegraph = 0.35 s` wind-up is the designed tell; players should learn to move laterally *during the wind-up*, not after.
- `snipe_damage = 30` — about 43% of a racer's HP (70) or half the player's base health depending on loadout. One landed shot and a follow-up is lethal without shields.
- `standoff_gap = 1200` puts Reacher comfortably off-screen below the player; it's a threat the player can easily forget about until the shot arrives. Reduce to make it more visible; increase to make it a "sudden" threat from off-screen.
- `charge_time = 1.2 s` means Reacher can fire roughly once every 1.55 s (0.35 s telegraph + 1.2 s recharge). Reduce for constant sniper pressure; increase for rarer but harder-to-anticipate shots.
- If Reacher falls more than `fall_behind_gap = 3000` behind the leader (about half the panel spacing), it suspends sniping and chases panels. This prevents it from becoming irrelevant in the late race.

---

## Files

```
reacher/
├── RACER.md                       ← this file
├── reacher.tscn
└── states/
    ├── reacher_position_state.gd
    ├── reacher_aim_state.gd
    ├── reacher_catchup_state.gd
    └── reacher_evade_state.gd
```
