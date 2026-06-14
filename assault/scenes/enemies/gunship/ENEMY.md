# Gunship — Heavy dual-barrel turret

**Role:** Self-managed mini-boss. Drops in from the top, parks below the screen edge, tracks the player horizontally, and pours burst fire until it's nearly dead — then retreats.
**Fantasy / threat:** A tanky wall of bullets. High HP forces sustained fire; its sprite cracks at half health, and it flees rather than dying clean.

---

## Stats

| Property | Value |
|---|---|
| HP | 200 |
| Damage | 30 contact / 15 per bullet (`bullet_damage`) |
| Speed | 60 entry/descent (`entry_speed`); retreat = `entry_speed × 1.5` = 90; horizontal track ≤ 70 (`track_speed`) |
| Sprite | `heave_gunship.png` (swaps to `heavy_gunship_non_shielded.png` at ≤50% HP) |
| Scene | `gunship.tscn` |
| Config | `gunship_config.tres` |

---

## Behaviour & Movement

- **Movement:** ⚠️ Self-managed AI in `_physics_process`. Do NOT attach `.move()` — it would disable the brain. Phases: ENTER → HOLD → RETREAT.
- **Attack:** Dual-barrel burst via a child `Timer` (`burst_interval` 1.0 s). Each burst fires the left barrel `Vector2(-12, 8)`, waits `burst_gap` (0.12 s), then the right barrel `Vector2(12, 8)`, both aimed at the player. Bullets pooled (`BulletPool`, size 15), `bullet_damage` 15, `bullet_speed` 260.
- **Death / scoring:** Awards `score_value` 200. At ≤50% HP the sprite swaps to the damaged texture. At HP ≤ `retreat_hp_ratio` (0.3) it stops firing and flees upward, freeing itself once off the top edge (so it can escape rather than die).

---

## State Graph

```
ENTER ──reaches hold_y──▶ HOLD ──HP ≤ retreat_hp_ratio──▶ RETREAT
  │                         │                                │
drop at entry_speed   track player X,                  fly up at
until hold_y          fire bursts                      entry_speed×1.5 → free
```

**Initial phase:** `ENTER`

> Note: phases are an `enum` inside `gunship.gd` (not separate `State` node files); there is no `states/` folder.

### ENTER
- Descends at `Vector2(0, entry_speed)` until `global_position.y ≥ _hold_y`.
- `hold_y = cam.y - viewport.y*0.5 + hold_y_offset` (default offset 55 → 55 px below the top edge).
- Then zeroes velocity, switches to HOLD, starts the burst timer.

### HOLD
- Holds Y; if `track_player`, steers X toward the player at up to `track_speed`.
- Fires bursts via the timer.
- When `current_health ≤ max_health * retreat_hp_ratio`, stops the timer → RETREAT.

### RETREAT
- Flies up at `-entry_speed * 1.5`; frees itself once above the top edge (−50 px).

---

## Config exports

| Export | Default | Meaning |
|---|---|---|
| `max_health` | `200` | HP. |
| `collision_damage` | `30` | Contact HitBox damage. |
| `score_value` | `200` | Points on kill. |
| `counts_toward_wave_clear` | `true` | Counts toward wave-clear bonus. |
| `burst_interval` | `1.0` | Seconds between burst pairs. |
| `burst_gap` | `0.12` | Delay between left and right shot in a burst. |
| `bullet_damage` | `15` | Per-bullet damage. |
| `bullet_speed` | `260.0` | Bullet speed (px/s). |
| `entry_speed` | `60.0` | Descent and (×1.5) retreat speed (px/s). |
| `hold_y_offset` | `55.0` | Px below viewport top where it holds. |
| `track_speed` | `70.0` | Max horizontal tracking speed (px/s). |
| `track_player` | `true` | Enable horizontal tracking during HOLD. |
| `retreat_hp_ratio` | `0.3` | HP fraction (0–1) that triggers RETREAT. |

(Read the real defaults from `gunship_config.gd` and `gunship_config.tres`.)

---

## Spawn notes

- WaveBuilder method: `b.gunship()` — see `docs/enemy-roster.md`.
- ⚠️ Never `.move()`. Spawn above the visible screen (`y` between −400 and −600 design units) so it enters from the top; it descends to `hold_y` on its own. Often escorted by `.move()`-driven fighters.

---

## Files

```
gunship/
├── ENEMY.md            ← this file
├── gunship.tscn
├── gunship.gd
└── gunship_config.gd / .tres
```
