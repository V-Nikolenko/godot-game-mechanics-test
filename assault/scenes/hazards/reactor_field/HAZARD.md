# Reactor Field — the fire an explosive wreck leaves

**Role / threat:** The brief reactor fire where an explosive wreck blew. It hurts every ship that stays in it, the
player and enemies alike. It pulls nothing and slows nothing, and the AI keeps clear of it. Plan §2.10
(`docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md`).

## Stats

| Property | Value |
|---|---|
| `radius` | 90 px: the avoidance footprint and the drawn ring |
| `damage_radius` | 90 px, by **centre distance** (`Hazards.pulse_damage`) |
| `stress_damage` / `stress_period` | 4 every 0.5 s (8 /s) |
| `duration` | 2.0 s, then it frees itself; the sprite fades over the last 0.5 s (`ReactorField.FADE_TIME`) |
| `avoid_weight` | 1.0 |
| Pull, swirl, slow, cycle | none |
| Scene | `reactor_field.tscn`: `ReactorField` (`reactor_field.gd`, a `HazardField`) + `Sprite` (`reactor_field_frames.tres`, animation `burn`, scaled to the radius) |

## Behaviour

- **Spawned by `Wreck._detonate()`** through the deferred `spawn_into(Hazards.container(tree), global_position)`.
  With no `hazard_container` nothing is instanced. One detonation leaves one field.
- **Hull stress bypasses `EnemyShield`** (a direct `received_damage` emit) and a plated Ram deflects it, like the
  gravity well's stress.
- No physics body, no pull, does not block line of sight.

## Tests

`tests/integration/test_wreck.gd` (explosive-wreck section): scene numbers, 2.0 s of stress pulses, one field per
detonation, none without a container, and the real-physics row (a real bullet kills an explosive wreck, exactly one
field appears).
