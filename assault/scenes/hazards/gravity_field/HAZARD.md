# Gravity Field — the slow a gravity bomb leaves behind

**Role / threat:** A Bomber's gravity bomb that bursts leaves a short-lived slowing field where it went off. It
slows the player and every mover-driven enemy caught inside; it pulls nothing and hurts nothing. Plan §2.15
(`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`).

## Stats

| Property | Value |
|---|---|
| `radius` | 150 px — the slow area, the avoidance footprint and the drawn ring |
| `movement_penalty` | 0.4, flat inside `radius` (strongest slow only; overlapping fields do not stack, 0.5 cap in `Hazards.penalty_at`) |
| `duration` | 3.5 s, then it frees itself; the sprite fades over the last 0.5 s (`GravityField.FADE_TIME`) |
| `avoid_weight` | 0.6 |
| Pull, swirl, stress, cycle | none |
| Scene | `gravity_field.tscn` — `GravityField` (`gravity_field.gd`, a `HazardField`) + `Sprite` (t5 `gravity_field.png`, scaled to the radius) |

## Behaviour

- **Spawned by `EnemyOrdnance._detonate()`** for `Kind.GRAVITY_BOMB` only (mines, pursuit bombs and a shot-down bomb
  leave none), through the deferred `spawn_into(Hazards.container(tree), global_position)`. With no
  `hazard_container` nothing is instanced.
- **Sampled, never applied.** Enemies feel `0.4 · (1 − hazard_resistance)` in their mover's slow step (a Bomber,
  resistance 0.4, moves at 0.76×); the player feels 0.4 on thrust, speed ceiling and boost (Open Space) or move and
  dash speed (Assault) through `hazard_speed_factor()`.
- No physics body, does not block line of sight.

## Tests

`tests/integration/test_enemy_ordnance.gd` (Phase 6 t17 section) and
`tests/integration/test_enemy_dual_mode.gd::test_the_gravity_field_slows_a_bomber_resistance_enemy_to_0_76`.
