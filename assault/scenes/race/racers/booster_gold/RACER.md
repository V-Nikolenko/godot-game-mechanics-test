# Booster Gold — The Front-Runner

**Role:** Panel-greedy leader who refuses to be passed. When in front: hoards panels to keep top speed maxed. When passed: uses an invincible ram dash to claw back to 1st.

**Fantasy:** The rabbit that *refuses to be passed*. His identity is staying in front. He does it by speed (panels) first, and violence (dash) as a fallback. Beating Booster Gold means denying him panels *and* surviving his reclaim dashes.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 |
| Shield charges | 1 |
| Max top speed | 600 (tied highest) |
| Top speed decay | 16.0/s (lowest — slow bleeder) |
| Sprite | `gold_exprerience.png` |
| Scene | `booster_gold.tscn` |

---

## State Graph

```
				  ┌─────── EVADE (threat? from any state) ────────┐
				  ▼                                                │
   in 1st ──▶ FRONTRUN ◀──── reclaimed the lead ◀────── RECLAIM   │
	   │  panel reachable?    │                           ▲  │    │
	   │      ▼               │ tailed while leading      │  │    │
	   └─▶ GRAB_PANEL─done────┘     ▼                     │  │    │
								  JUKE──shaken──▶ FRONTRUN │  │    │
														   │  │    │
   not 1st ──────────────────────────────────────────────►─┘  │    │
															   │    │
   target in dash range & cd ready ──▶ DASH ──ends──▶ RECLAIM ◄───┘
								   (GRAB_PANEL preempts en route)
```

**Initial state:** `BgFrontrun`

The FSM is split by standing. `FRONTRUN` is the home state (active while 1st). `RECLAIM` activates the instant he's no longer 1st. **The dash lives only in RECLAIM** — Booster Gold never wastes it while leading.

---

## States

### FRONTRUN (`bg_frontrun_state.gd`)

Active while Booster Gold is in 1st place. Goal: defend the lead.

**Behaviour:**
- If `sensors.incoming_threat()` → **EVADE**.
- If `director.is_in_front(participant)` is false → **RECLAIM** (instantly flips when passed).
- If `sensors.nearest_panel_ahead(panel_reach)` returns a panel → sets `BgGrabPanel.return_to = &"BgFrontrun"` → **GRAB_PANEL** (highest priority; almost nothing overrides it).
- If a chaser is within `tail_gap` track_y and `tail_lane` px laterally → **JUKE**.
- Otherwise: floors speed, holds current X (clean fast line).

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `panel_reach` | 900.0 | px to scan for panels |
| `tail_gap` | 220.0 | track_y within which a chaser triggers JUKE |
| `tail_lane` | 160.0 | px lateral tolerance to count as "on my tail" |

---

### GRAB_PANEL (`bg_grab_panel_state.gd`)

Commits to the nearest reachable panel on both axes. Shared between FRONTRUN and RECLAIM (both modes use it). `return_to` determines where to go after crossing.

**Behaviour:**
- If `sensors.incoming_threat()` → **EVADE**.
- If no panel reachable → transitions to `return_to` (caller's mode).
- Floors speed, steers to panel X.
- When within `cross_dist` px → transitions to `return_to`.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `panel_reach` | 1000.0 | slightly larger reach than FRONTRUN's scan |
| `cross_dist` | 60.0 | px proximity to count as "crossed" |

**Note:** `return_to` is a `StringName` set by the calling state before transitioning here (`BgFrontrun` sets it to `&"BgFrontrun"`; `BgReclaim` sets it to `&"BgReclaim"`).

---

### RECLAIM (`bg_reclaim_state.gd`)

Active the instant Booster Gold is NOT in 1st. Aggressive catch-up — still panel-greedy, but the dash is now available.

**Behaviour:**
- If `sensors.incoming_threat()` → **EVADE**.
- If `director.is_in_front(participant)` is true → **FRONTRUN** (instantly flips back when leading).
- Floors speed.
- If `BgDash.dash_ready` AND a ship is ahead within `[dash_range_min, dash_range_max]` and within `dash_aim_tol` px laterally → set `BgDash.target` → **DASH**.
- If no clean target but `director.gap_to_leader > desperation_gap` → **DASH** as a pure forward surge.
- If a panel is reachable → `BgGrabPanel.return_to = &"BgReclaim"` → **GRAB_PANEL**.
- Otherwise: steers toward the ship ahead, fires when lined up.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `panel_reach` | 900.0 | px to scan for panels |
| `dash_range_min` | 120.0 | minimum track_y gap to the target to dash |
| `dash_range_max` | 1400.0 | maximum track_y gap |
| `dash_aim_tol` | 90.0 | px lateral tolerance to commit the dash |
| `lane_tol` | 240.0 | px lane tolerance for ship detection |
| `desperation_gap` | 2200.0 | track_y behind leader → surge dash with no target |
| `fire_cd` | 0.5 s | fire rate while chasing |
| `bullet_damage` | 8 | |
| `bullet_speed` | 320.0 | |

---

### DASH (`bg_dash_state.gd`)

The signature: an invincible boosted ram. Fires almost exclusively from RECLAIM.

**Behaviour:**
- `enter()`: sets `dash_ready = false`, disables hurtbox (i-frames), applies `dash_lunge` track_y forward, sets cruise to 1.0.
- Each frame: steers toward `target`'s X if set; scans for contact damage (any ship within `dash_radius`, once each, via `HurtBox.received_damage`); counts down `dash_time`.
- When timer expires: re-enables hurtbox, starts `cooldown` → transitions to **RECLAIM**.
- **Cooldown ticking:** `BgDashState._physics_process` (Godot `Node._physics_process`, not the brain-driven `process_physics`) ticks `_cd` down even while OTHER states are active, so `dash_ready` flips back on time. The guard `if host.brain.current == self: return` prevents double-ticking.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `dash_time` | 0.85 s | duration of the invincible dash |
| `dash_lunge` | 950.0 | track_y leap on enter |
| `dash_damage` | 45 | contact damage per ship passed |
| `dash_radius` | 72.0 | px contact radius |
| `cooldown` | 7.0 s | wait before `dash_ready` resets |

---

### JUKE (`bg_juke_state.gd`)

Brief sidestep to deny a tailing ship the slipstream while leading. Does not flee — just disrupts.

**Behaviour:**
- On `enter()`: latches a `_side` direction (alternates each juke so Booster doesn't always juke the same way).
- If threat → **EVADE**.
- After `juke_time` → **FRONTRUN**.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `juke_distance` | 320.0 | px lateral displacement |
| `juke_time` | 0.5 s | duration of the juke |

---

### EVADE (`bg_evade_state.gd`)

Standard threat dodge from any state. Returns to the appropriate mode based on standing.

**Behaviour:**
- If `sensors.incoming_threat()` is null → transitions to **RECLAIM** if not in 1st, else **FRONTRUN**.
- Steers away by `sidestep` px, floors speed.

**Tuning exports:**

| Export | Default | Meaning |
|---|---|---|
| `sidestep` | 180.0 | px lateral step |

---

## Tuning Notes

- The `decay_per_sec = 16.0` (vs the field average ~22) means Booster Gold bleeds top speed slowly — panels he grabs stay "in his tank" longer, reinforcing the front-runner feel.
- `desperation_gap = 2200` — if more than ~2.2 s at max speed behind the leader, he will dash even without a target. Reduces this to prevent gap surges; increase to make him more patient.
- The dash `cooldown = 7 s` means he can dash roughly once every 7 s when reclaiming. Against a well-defended lead, he may need 2–3 dashes — time them by positioning to hit dash windows.
- JUKE only triggers when the chaser is within `tail_gap = 220` track_y AND within `tail_lane = 160` px. Tight thresholds — only activates on genuine tailgating.

---

## Files

```
booster_gold/
├── RACER.md                 ← this file
├── booster_gold.tscn
└── states/
    ├── bg_frontrun_state.gd
    ├── bg_grab_panel_state.gd
    ├── bg_reclaim_state.gd
    ├── bg_dash_state.gd
    ├── bg_juke_state.gd
    └── bg_evade_state.gd
```
