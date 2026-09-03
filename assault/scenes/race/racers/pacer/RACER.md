# Pacer — The Rabbit

**Role:** Benchmark pace-setter. Races clean and fast. Never fights.

**Fantasy:** A pure speedster that chases every dash panel and holds the fastest clean line available. Exists to set the standings benchmark and create pressure through speed alone — not weapons or dirty tricks.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 |
| Shield charges | 1 |
| Max top speed | 600 (highest in the field) |
| Sprite | `zipper.png` |
| Scene | `pacer.tscn` |

---

## State Graph

```
RUN ──incoming threat──▶ DODGE ──clear──▶ RUN
```

**Initial state:** `PacerRun`

---

## States

### RUN (`pacer_run_state.gd`)

The default and dominant state. Seeks the nearest panel ahead; holds a clean forward line.

**Behaviour:**
- If `sensors.incoming_threat()` is non-null → transitions to **DODGE**.
- Calls `host.set_forward_floor()` (full top speed always).
- Calls `sensors.nearest_panel_ahead(panel_reach)`: if found, steers toward it; otherwise holds current X.
- Calls `host.add_avoidance()` to passively sidestep asteroids/mines (opt-in hazard avoidance).

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `panel_reach` | 700.0 | px ahead to scan for a panel |

---

### DODGE (`pacer_dodge_state.gd`)

Brief lateral sidestep when a threat enters the sensor radius. Resumes RUN the moment it clears.

**Behaviour:**
- If `sensors.incoming_threat()` is null → transitions to **RUN**.
- Steers away from threat's X position by `sidestep` px; floors speed.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 170.0 | px lateral step away from the threat |

---

## Tuning Notes

- Pacer never fires. It is **not a combat threat** — it is a standings pressure.
- Its `max_top_speed = 600` is the highest in the field, meaning it *will* lead if it consistently hits panels and the player doesn't.
- `panel_reach = 700` is conservative — increase it to make Pacer detour more aggressively for distant panels.
- Pacer is the simplest brain: 2 states, no weapons, no signatures. Use it as a baseline when debugging race balance.

---

## Files

```
pacer/
├── RACER.md               ← this file
├── pacer.tscn
└── states/
    ├── pacer_run_state.gd
    └── pacer_dodge_state.gd
```
