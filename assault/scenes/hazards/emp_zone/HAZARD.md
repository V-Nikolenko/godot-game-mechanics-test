# EMP Zone — the neutral pulse area

**Role / threat:** A placed, neutral area that arms with a shrinking ring and then pulses an EMP every 6 s on everyone inside it, the
player, enemies and seeking rockets alike. It is not an enemy and hurts nothing. Enemies steer round it. Plan §2.13
(`docs/plans/cmug23onr001pm52w9swwophy/3-plan.md`).

## Stats

| Property | Value |
|---|---|
| `Field.radius` | 260 px — the pulse reach (centre-distance `<=`), the avoidance footprint and the drawn ring |
| `Field.kind` / `avoid_weight` | `&"emp_zone"`, 0.6 while TELEGRAPH or ACTIVE, 0 while QUIET (the `HazardField` rule) |
| Cycle | `cycle_telegraph` 1.0 / `cycle_active` 0.25 / `cycle_quiet` 4.75 — one pulse per 6 s, on the TELEGRAPH → ACTIVE edge |
| `emp_seconds` | 2.0 (the lock and boost refusal on the player; the halt and no-attack window on an answering enemy) |
| Pull, swirl, penalty, stress, `disables_abilities` | none — the lock comes from the EMP itself |
| Scene | `emp_zone.tscn` — `EmpZone` (`emp_zone.gd`, a plain `Node2D`) + child `Field` (a `HazardField`) + `Field/Art` (`emp_zone_art.gd`, `EmpZoneArt`) |

## Behaviour

- **Composition, not a `HazardField` subclass** (the jammer's shape). `EmpZone` connects `Field.phase_changed`; on each change TO
  ACTIVE it makes exactly one `EmpPulse.emit(tree, global_position, radius, emp_seconds, self, TARGET_ALL)`. The field registers
  itself in its own `_enter_tree()` and unregisters in `_exit_tree()`, so freeing the zone frees the footprint.
- **TARGET_ALL** = the player (`apply_emp`: ability lock + boost refusal, `emp_changed`), every `enemies` node that answers
  `answers_emp()` (halted, brain not ticked, still shootable), and seeking rockets of both sides (guidance jammed). Enemies that do
  not answer (structures, railed ships) are ignored.
- **Look (`EmpZoneArt`, code-drawn).** QUIET a dim 1 px ring at `radius`; TELEGRAPH a ring contracting from `radius` to 0.6 · `radius`
  with brightening alpha (the arm time is the counterplay: leave before it closes); ACTIVE an `EmpRing` expanding from the centre.
  The centre beacon sprite is the art task's (t12).
- **Scene-placed only.** Never spawned at runtime, and never in an Assault level in Phase 9. The hub placement is t13; until then
  the hub sweep (`test_sector_hub_patrol.gd::_element_radius()`) already reads an `EmpZone` as 260, not as a zero-radius node.

## Tests

`tests/integration/test_emp_zone.gd` (both harnesses for the enemy rows, both real player scenes for the lock row).
