# Bomber — area-denial bomb-dropper

**Role:** Drops persistent ordnance (gravity bombs, proximity mines, a pursuit bomb) that forces the player to reposition.
**Fantasy / threat:** A wide, slow, easy-to-hit target — but ignore it and what it leaves behind catches you. Every piece of ordnance can be shot down.

> **Build state (Phase 4, t9 shell).** The scene, config, pools, rail fallback and Assault exit are built.
> The AI bombing runs (prediction, ordnance choice, the bombing line, the Dubins approach, escape) are t10;
> until then the AI Bomber only intercepts the player. Plan: `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` §2.4.

---

## Stats

| Property | Value |
|---|---|
| HP | 150 (`bomber_config.tres`; the `.tscn` Health node is overwritten in `_ready()`) |
| Damage | 35 contact (`ContactHitBox`); ordnance blasts come from the config |
| Speed | `max_speed` 240 transit, `run_speed` 170 for the bombing run |
| Body | one 96 × 44 `RectangleShape2D`, shared by the body, `HurtBox` and `ContactHitBox` (the wings are shootable) |
| Sprite | `bomber.png` (placeholder; nose-down) |
| Scene / config | `bomber.tscn` / `bomber_config.tres` (flat `BomberConfig`) |

---

## Behaviour

- **Brain:** `BomberBrain` (`Phase { APPROACH, RUN, ESCAPE, REPOSITION, DISENGAGE }`, `enter_phase()` seam). APPROACH is a plain intercept; RUN / ESCAPE / REPOSITION are t10. Assault: an `EngagementBudget` (`engage_seconds` 8) then DISENGAGE, which curves out of the world rect and frees.
- **Mover:** `EnemyMover` AUTO (`max_speed` 240, `acceleration` 260, `max_turn_rate` 1.6).
- **Ordnance:** `Bomber.drop(kind, dir, speed, target_point)` takes it from `GravityBombPool` / `MinePool` / `PursuitBombPool`, root children with `persist_after_owner_death = true`, so a bomb or mine already dropped outlives the bomber. Pool sizes follow `EnemyOrdnanceScenes.pool_size_for()` (gated by `test_bomber.gd`).
- **Rail fallback:** while `is_ai_suspended()`, `Bomber._process` drops a gravity bomb `Vector2.DOWN` at `rail_bomb_speed` (120) every `rail_bomb_interval` (1.2 s), aimed `rail_bomb_range` below. Nothing writes motion.
- **Death / scoring:** `BaseEnemy` emits `died`, awards `score_value` 80.

---

## Spawn notes

- WaveBuilder method: `b.bomber()` — see `docs/enemy-roster.md`. Level 1 still spawns it on a rail (`.move(b.straight(...))`).

## Tests

`tests/integration/test_bomber.gd`; the `Bomber` cases in `test_enemy_dual_mode.gd`; the ordnance itself in `test_enemy_ordnance.gd`.

---

## Files

```
bomber/
├── ENEMY.md            ← this file
├── bomber.tscn
├── bomber.gd
├── bomber_brain.gd
└── bomber_config.gd / .tres
```
