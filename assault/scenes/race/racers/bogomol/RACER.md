# Bogomol — The Panel-Denier

**Role:** Area-denial saboteur. Races for panels not (only) for the speed gain, but to mine them immediately after crossing so trailing ships eat the hazard.

**Fantasy:** Turns the player's own speed economy against them. Every panel Bogomol crosses becomes a trap. The panels you need are the ones most likely to be mined.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 |
| Shield charges | 2 (tankier than average for a greedy rusher) |
| Max top speed | 560 |
| Sprite | `bogomol.png` |
| Scene | `bogomol.tscn` |

---

## State Graph

```
SEEK ──reached panel──▶ MINE_DROP ──(instant)──▶ SEEK
  ▲        ▲                                       │
  │        └────────── panel appears ──────────────┘
  │
  └── no panel ──▶ CRUISE ──(panel appears)──▶ SEEK
       threat? (any state) ──▶ EVADE ──clear──▶ SEEK
```

**Initial state:** `BogomolSeek`

---

## States

### SEEK (`bogomol_seek_state.gd`)

Races toward the nearest reachable dash panel on both axes simultaneously. Bogomol *benefits* from crossing it (top speed rises) and immediately uses the crossing to deny it.

**Behaviour:**
- If `sensors.incoming_threat()` is non-null → transitions to **EVADE**.
- Calls `sensors.nearest_panel_ahead(panel_reach)`.
- If no panel reachable → transitions to **CRUISE**.
- Otherwise: floors speed (`set_forward_floor`), steers toward the panel's X.
- When within `cross_dist` px of the panel → stores panel position in `BogomolMine.drop_at` → transitions to **MINE_DROP**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `panel_reach` | 900.0 | px ahead to look for panels |
| `cross_dist` | 60.0 | px proximity at which the crossing is triggered |

---

### MINE_DROP (`bogomol_mine_state.gd`)

Instantaneous: drops a `Mine` at the panel location (just behind, so ships following through hit it), then immediately returns to **SEEK**.

**Behaviour:**
- `enter()` fires synchronously: instantiates `mine.tscn` at `drop_at`, sets the mine's `track_y` from the panel's screen position via `RaceWorld.track_y_for_screen_y`, adds it to the scene under Bogomol's parent → transitions to **SEEK** immediately.
- `process_physics` is a no-op (the state is entered and exited within the same frame).

**Mine properties (from `mine.gd`):**
- `arm_delay = 0.4 s` — won't trigger for 0.4 s after placement (so Bogomol itself clears it).
- `lifetime = 8.0 s` — despawns after 8 s if never triggered.
- `trigger_radius = 46 px` — any ship that passes within range is hit.
- `damage = 30` — moderate hit; also triggers `lose_top_speed_on_hit` via `DamageReaction`.
- In group `mines` — all racers' `sensors.hazard_ahead()` and `lateral_mover.avoidance_nudge()` see it immediately.

---

### CRUISE (`bogomol_cruise_state.gd`)

Fallback when no panel is reachable. Holds a fast defensive line and periodically lays a mine on its current lane (opportunistic denial).

**Behaviour:**
- If `sensors.incoming_threat()` is non-null → transitions to **EVADE**.
- If `sensors.nearest_panel_ahead(900)` is non-null → transitions to **SEEK**.
- Calls `set_forward_floor()` and `add_avoidance()`.
- On `lay_interval` timer: instantiates a mine just behind the current position on the current lane.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `lay_interval` | 3.0 s | how often a lane mine is dropped while cruising |

---

### EVADE (`bogomol_evade_state.gd`)

Standard dodge: sidestep the threat, return to SEEK.

**Behaviour:**
- If `sensors.incoming_threat()` is null → transitions to **SEEK**.
- Steers away from threat by `sidestep` px; floors speed.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 180.0 | px lateral step |

---

## Tuning Notes

- Bogomol's 2 shield charges make it harder to punish — it can eat a hit while charging for a panel.
- The mine `arm_delay = 0.4 s` is what prevents Bogomol from mining itself. Do not reduce it below ~0.3 s without also increasing `cross_dist`.
- Increasing `panel_reach` makes Bogomol detour aggressively for far panels — effective but exposes it laterally.
- `lay_interval` in CRUISE is a secondary denial tool — useful when the field bunches up and panels are sparse.
- Mines remain on the track for 8 seconds. With 5+ racers and a dense panel layout, the mid-track can become heavily mined in the later race segment.

---

## Files

```
bogomol/
├── RACER.md               ← this file
├── bogomol.tscn
└── states/
    ├── bogomol_seek_state.gd
    ├── bogomol_mine_state.gd
    ├── bogomol_cruise_state.gd
    └── bogomol_evade_state.gd
```
