# Sniper — precision marksman

**Role:** Holds a long firing line on the player and fires a single fast rail shot after a telegraph.
**Fantasy / threat:** A patient sniper. The shot is broadcast by a red line that turns bright when it locks; reading that tell and stepping aside is the whole fight.

> **Build state (Phase 4, t12 shell).** The scene, config, rail round, aim line, rail fallback and Assault exit are built.
> The AI relocation loop (BREAK_CONTACT → RELOCATE → SETTLE → AIM → LOCK → FIRE), the firing-point selection, the
> line-of-sight refusal and the rail trail are t13; the decoy is t14; the unfolding barrel art is t15. Until then an AI
> Sniper only flies to its nearest legal firing point and holds there. Plan:
> `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.5, §2.8.

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

- **Brain:** `SniperBrain` (`Phase { ENTER, BREAK_CONTACT, RELOCATE, SETTLE, DECOY, AIM, LOCK, FIRE, DISENGAGE }`, `enter_phase()` seam). Only ENTER and DISENGAGE play so far. ENTER seeks the nearest legal firing point (the `preferred_range` ring round the player, on the sniper's own side; in Assault `assault_preferred_range` and inside `inner_rect()` shrunk by `fire_margin`) at `relocate_speed`, and holds still once there. There is no fly-in timer: ENTER lasts `distance / relocate_speed`.
- **Assault:** an `EngagementBudget` (`engage_seconds` 9) then DISENGAGE, which releases the corridor, curves out of the world rect at `exit_speed` and frees.
- **Mover:** `EnemyMover` AUTO.
- **Rail round:** `RailPool` (a root child, size 2, not persistent) hands out `projectiles/enemy_bullet/rounds/rail_round.tscn` (`EnemyRounds.RAIL`): speed 2200, damage 28, capsule r 1.5 × h 24, `ProjectileLifetime` 4 s / 2400 px, no `WorldEnvironment`.
- **Aim line:** `Telegraph` (`SniperTelegraph`, the sniper's own `Node2D`) draws from the `Muzzle` marker toward an aim point, at least 900 px long: dim red, width 1 while tracking; near-white, width 3 once locked. The player weapon's `SniperAimVisualizer` is separate and untouched.
- **Rail fallback (§2.8):** while a rail owns the sniper (`is_ai_suspended()`), `SniperBrain.on_suspended()` starts `Telegraph.start_rail_cycle()`: aim `rail_aim_seconds` 2.0 tracking at `rail_track_rate` 4.0 rad/s, lock `rail_lock_seconds` 0.5, then one round at `rail_fallback_speed` 1400 (damage `rail_fallback_damage` 25) along the locked line, `rail_shot_count` 5 times. It runs from `suspend_ai()` (no 2.5 s fly-in wait any more) and **never writes `rotation`**: the path mover owns it.
- **Death / scoring:** `BaseEnemy` emits `died`, awards `score_value` 50.

---

## Spawn notes

- WaveBuilder method: `b.sniper()` (alias `b.sniper_enemy()`) — see `docs/enemy-roster.md`. Level 1 still spawns it on a rail (`.move(...)`); the `shot_count` prop is gone (use `SniperConfig.rail_shot_count`).

## Tests

`tests/integration/test_sniper.gd`; the `Sniper` cases in `test_enemy_dual_mode.gd`; the rail round in `test_enemy_bullet_lifetime.gd`.

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
