# Fighter — gun-armed Tier 1 fighter (formerly the Light Assault Ship)

**Role:** The baseline shooter. Built as an AI enemy (`FighterBrain` decides, `EnemyMover` moves). While a level
rail (`EnemyPathMover`) owns its motion it falls back to the legacy weapon, so level 1 and the station's
reinforcements play as before.
**Fantasy / threat:** Bread-and-butter opposition. Manageable alone; dangerous in numbers.

> **Status (Phase 3, task t8a):** the shell. The full phase enum, APPROACH, the Assault exit and the rail fallback are
> built. The attack run (RUN_IN / EXTEND / TURN / REPOSITION), weapon selection by distance and the AI bursts arrive in
> t8b, so an AI fighter today closes on the player, holds at `standoff_radius` and does not fire.

---

## Stats

| Property | Value |
|---|---|
| HP | 60 (`fighter_config.tres`) |
| Damage | 20 contact / 8 per Pulse round on rails |
| Speed | `max_speed` 300, `acceleration` 700, `turn_rate` 1.8 rad/s (turn radius ≈ 167 px) |
| Sprite | `assault.png` placeholder `AnimatedSprite2D` (flipped 180° by `_rotate_sprite`); `sprite_forward_angle` PI/2 |
| Scene | `fighter.tscn` |
| Config | `fighter_config.tres` (flat, `@export_group`ed) |

---

## Scene

`Fighter` root, `Brain` (`FighterBrain`), `EnemyMover` (`constraint_mode = AUTO`), `StateLight`, the shared body /
`HurtBox` / `ContactHitBox` circle, and:

- `AimedAttack` + `ForwardAttack` — `AttackController`s, `driven_by_brain`, `enabled = false`;
- `AimedPool` (Pulse Round, 20) and `ForwardPool` (Scatter Round, 8) — **direct children of the root**:
  `BulletPool` resolves its container as `get_parent().get_parent()`, so a pool under a controller would carry its live
  bullets with the ship. Gated by `tests/integration/test_fighter.gd`.

There is no `AIStateMachine` and no `states/` folder.

Pool sizes are `max(AI need, rail need)` from `EnemyRounds.pool_size_for(...)`: the aimed burst (5 × ceil(4.67 s / 1.2 s))
is 20, the FORWARD rail cadence 12, the aimed rail cadence 7; the Scatter burst is 7, rounded to 8.

## Brain phases (`FighterBrain.Phase`)

`APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE` (t12 appends the idle phases). `phase_changed(new_phase: int)`
fires on every transition; `enter_phase()` is the one transition path.

- **APPROACH** — a plain curved intercept (`Steering.turn_toward` at `turn_rate`, predicted player position), brakes at
  `standoff_radius`.
- **RUN_IN .. REPOSITION** — t8b.
- **DISENGAGE** — Assault only, when the `EngagementBudget` (`engage_seconds`) expires: releases the corridor constraint,
  raises the mover to `exit_speed`, curves toward the nearest edge of the projectile world rect and frees itself once
  outside it. Open Space never disengages.

## Rail fallback

`BaseEnemy.suspend_ai()` calls `FighterBrain.on_suspended()`, which hands `AimedAttack` back to self-timed fire from config
fields: `aim_mode == "FORWARD"` → a Pulse round every `rail_forward_interval` (0.3 s) at `rail_forward_speed` (420);
otherwise an aimed round every `fire_interval` (0.8 s) at `rail_aimed_speed` (250). Damage is `bullet_damage` (8).
`aim_mode` (spawn props `shoot_forward()` / `shoot_at_player()`, else the config default) is read **only** there; an AI
fighter ignores it.

## Config

Read the real fields from `fighter_config.gd` (groups: Movement, Geometry, Attack, Tactics, Rail). The pin
`turn_rate × max_speed ≤ acceleration` is asserted in `tests/integration/test_fighter.gd`.

## Spawn notes

- WaveBuilder method: `b.fighter()` — see `docs/enemy-roster.md`. Level 1 still gives it `.move()` (a rail) until its
  migration task.
- `.shoot_forward()` / `.shoot_at_player()` are rail-only inputs.

## Files

```
fighter/
├── ENEMY.md            ← this file
├── fighter.tscn
├── fighter.gd
├── fighter_brain.gd
└── fighter_config.gd / .tres
```
