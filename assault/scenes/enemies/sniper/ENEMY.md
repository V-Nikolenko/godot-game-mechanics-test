# Sniper — precision marksman

**Role:** Holds a long firing line on the player and fires a single fast rail shot after a telegraph.
**Fantasy / threat:** A patient sniper. The shot is broadcast by a red line that turns bright when it locks; reading that tell and stepping aside is the whole fight.

> **Build state (Phase 4, t12 shell + t13 cycle).** The scene, config, rail round, aim line, rail fallback, Assault
> exit and the AI relocation cycle (with firing-point selection, the line-of-sight refusal and the rail trail) are
> built. The decoy (t14, behind `decoy_telegraph`) is built; the real unfolding barrel art is t15 (the `Barrel` is a placeholder gradient whose length the
> brain scales). Plans: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.5, §2.8;
> `docs/plans/cmuyk2qq0008loa2xqwco8raj/3-plan.md` (the cycle).

---

## Stats

| Property | Value |
|---|---|
| HP | 60 (`sniper_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 20 contact (`ContactHitBox`); rail round 28 (`rail_damage`), 25 on a rail (`rail_fallback_damage`) |
| Speed | `max_speed` 320, `relocate_speed` 260, `break_speed` 320, `exit_speed` 320 |
| Score | 50 (`SniperConfig.score_value`; it used to be hardcoded in `_ready()`) |
| Sprite | `sniper.png` (nose-up, so `sprite_forward_angle = -PI / 2`) plus a placeholder `Barrel` |
| Scene / config | `sniper.tscn` / `sniper_config.tres` (flat `SniperConfig`) |

---

## Behaviour & Movement

- **Mover:** `EnemyMover` AUTO. The brain only requests; it never writes `velocity` / `rotation`.
- **Rail round:** `RailPool` (a root child, size 2, not persistent) hands out `projectiles/enemy_bullet/rounds/rail_round.tscn` (`EnemyRounds.RAIL`): speed 2200, damage 28, capsule r 1.5 × h 24, `ProjectileLifetime` 4 s / 2400 px, no `WorldEnvironment`.
- **Rail trail:** every AI shot spawns a `RailTrail` (`rounds/rail_trail.gd`, a code-built `Line2D`) in the round's container. It follows the round until the round's `expired` (connected one-shot — a pooled round is recycled, not freed, so it never follows a parked round), or until the round is freed without `expired` (owner death, `cancel_active()`), then fades over `trail_fade` 0.4 s on its own clock and frees itself.
- **Aim line:** `Telegraph` (`SniperTelegraph`, the sniper's own `Node2D`) draws from the `Muzzle` marker toward an aim point, at least 900 px long: dim red, width 1 while tracking; near-white, width 3 once locked. The player weapon's `SniperAimVisualizer` is separate and untouched.
- **Rail fallback (§2.8):** while a rail owns the sniper (`is_ai_suspended()`), `SniperBrain.on_suspended()` starts `Telegraph.start_rail_cycle()`: aim `rail_aim_seconds` 2.0 tracking at `rail_track_rate` 4.0 rad/s, lock `rail_lock_seconds` 0.5, then one round at `rail_fallback_speed` 1400 (damage `rail_fallback_damage` 25) along the locked line, `rail_shot_count` 5 times, with no trail. It runs from `suspend_ai()` and **never writes `rotation`**: the path mover owns it.
- **Death / scoring:** `BaseEnemy` emits `died`, awards `score_value` 50.

---

## State Graph

`SniperBrain.Phase` (`sniper_brain.gd`; one script, an in-script enum; `enter_phase()` is the one transition and emits `phase_changed(new_phase: int)`):

```
ENTER ──arrived──► SETTLE ──still, LOS clear──► AIM ──1.3 s──► LOCK ──0.5 s, both lines clear──► FIRE
                     │  └─LOS blocked / 1.5 s─┐                  └─LOS blocked (refusal)─┐       │
                     ▲                        ▼                                         ▼       ▼
                  RELOCATE ◄──point chosen── BREAK_CONTACT ◄────────────────────────────┴───────┘
Assault budget expiry: DISENGAGE at once, except in AIM / LOCK, where it waits for the shot or the refusal.
With `SniperConfig.decoy_telegraph` (default false) SETTLE -> DECOY -> AIM: a 0.6 s dim orange line 25-35 deg off the player, CHARGING, never COMMIT, no round. A budget expiry in DECOY disengages at once.
```

### ENTER
Seeks the first firing point from `choose_firing_point()` — with no last bearing the score is pure travel, so it is the **nearest legal candidate** (fallback: the t12 `nearest_firing_point()` ring point) — at `relocate_speed`, with an arrival latch (`arrive_radius` 12 px, released at twice that). No fly-in timer: its length is `distance / relocate_speed`.

### SETTLE
Zero velocity, faces the player. Once under `settle_epsilon` 2 px/s it re-checks line of sight from the muzzle: clear → AIM, blocked → BREAK_CONTACT (a refusal). `SETTLE_CAP` 1.5 s → BREAK_CONTACT.

### AIM / LOCK — the player's window
Stationary. AIM (1.3 s, light CHARGING, dim line) tracks the **full intercept** of the player for a 2200 px/s round, turning at most `aim_track_rate` 2 rad/s; the barrel unfolds over `barrel_unfold_seconds` 0.4. LOCK (0.5 s, light COMMIT, bright line) freezes the point. On the tick it would fire it re-checks line of sight to the player **and** along the locked line; either blocked → no round (a refusal) → BREAK_CONTACT.

### FIRE
One round along the locked line at `rail_speed` for `rail_damage`, plus its `RailTrail`; records the player-frame bearing of its position (`last_bearing`); the barrel folds over `barrel_fold_seconds` 0.3. Entered and left on the same tick.

### BREAK_CONTACT
`Steering.break_contact` at `break_speed`, lateral share on the side of the player's line (the player frame through the player) it is already on, so it never crosses the player's nose. Lasts at least `break_min` 1.0 s (so every shot is followed by a real retreat), then until `0.9 × range` or `break_cap` 2 s. Past `range + range_jitter` it stops and waits. Nothing legal → it holds and retries every `break_cap`. **Assault:** an outward request on an axis stops while it could still brake before the corridor's visible edge (at `break_speed`, half the acceleration, + 16 px); a remainder toward the player is turned round (a slide along the wall, which may cross the player's line — the corridor wins); in a corner it stops.

### RELOCATE
`arrive` at `relocate_speed`. Re-picks after `max(relocate_cap, trip / relocate_speed + 1 s)`.

### Choosing a firing point (`choose_firing_point()`)
In the **player frame** (the player's smoothed velocity, τ `velocity_smoothing` 0.3 s, while it moves at ≥ `frame_speed` 60; else its facing):
1. Seven seeds at ±60°, ±90°, ±135°, 180° (each ± `seed_jitter` 15°) plus `random_candidates` 3, at the mode's range ± jitter (Open Space 900 ± 100, Assault 680 ± 80).
2. Filters: Assault — inside `inner_rect()` shrunk by `fire_margin` 96; **path** — the straight route never passes closer to the player than `pass_clearance_ratio` 0.45 × range (or than the sniper already is); **forward cone** — not within 30° of a player moving ≥ 200 px/s.
3. Tiers after a shot: A ≥ 50° from the last firing bearing (`min_bearing_change` + a 5° slack, because the shot is fired from where it settles), B ≥ 45°, C the rest (the fallback for a cornered player, logged under `--verbose`).
4. Score `w_sep · Δ/180° − w_travel · travel / (2 · range)`; line of sight from each candidate in rank order, at most `max_los_rays` 6 rays.

Line of sight is `LineOfSight` (opt-in blockers: group `asteroids` or `blocks_line_of_sight()`); a fighter or the player never blocks.

---

## Config exports (added by t13; the rest are in `sniper_config.gd`)

| Export | Default | Meaning |
|---|---|---|
| `break_min` | 1.0 | BREAK_CONTACT never ends sooner (s) |
| `velocity_smoothing` | 0.3 | Player-velocity smoothing time constant (s) |
| `frame_speed` | 60 | Below this the player frame is its facing (px/s) |
| `forward_cone_speed` | 200 | The forward cone applies at or above this (px/s) |
| `seed_jitter` | 15 | Seed bearing jitter (deg) |
| `random_candidates` | 3 | Random bearings added to the seeds |
| `max_los_rays` | 6 | Ray cap per choice |
| `pass_clearance_ratio` | 0.45 | Relocation path clearance, as a share of the range |
| `barrel_unfold_seconds` / `barrel_fold_seconds` | 0.4 / 0.3 | Barrel animation (s) |

---

## Spawn notes

- WaveBuilder method: `b.sniper()` (alias `b.sniper_enemy()`) — see `docs/enemy-roster.md`. Level 1 still spawns it on a rail (`.move(...)`); the `shot_count` prop is gone (use `SniperConfig.rail_shot_count`).

## Tests

`tests/integration/test_sniper.gd` (the cycle specs run in both harnesses, plus the level-1 attack-in-budget row through a real `WaveManager`); the `Sniper` cases in `test_enemy_dual_mode.gd`; the rail round in `test_enemy_bullet_lifetime.gd`.

---

## Files

```
sniper/
├── ENEMY.md            ← this file
├── sniper.tscn
├── sniper.gd
├── sniper_brain.gd
├── sniper_telegraph.gd
└── sniper_config.gd / .tres
```
