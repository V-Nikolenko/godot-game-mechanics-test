# Minefield — a placed, visible structure of mines with a warning beacon

**Role / threat:** area denial the player has to remember. A `Minefield` (`minefield.tscn`, `Minefield extends Node2D`) holds
`EnemyMine`s as `placed` mines (self-owned, hostility **ALL** by default, so they hurt and are set off by enemies as well as
the player) and marks itself with an amber blinking beacon. Plan §2.10 (`docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md`).
No level-1 placement: Phase 15 places Assault hazards; the hub placement is a later task.

## Nodes

| Node | Role |
|---|---|
| `Mines` (`Node2D`) | Parent of every mine. AUTHORED fields have their `EnemyMine` children here. |
| `Beacon` (`MinefieldBeacon`) | Amber blink, code-drawn until the art task adds a `Sprite` child with a texture (then it draws nothing itself and the sprite blinks). Goes dark with the last mine. |

## Exports

- `pattern`: `AUTHORED` (the editor-placed children), `RING` (`count` mines on a circle of `radius`), `GRID` (`count` cells filled
  row by row, `spacing` apart, centred), `SCATTER` (`count` points in a disc of `radius`).
- `count` 9, `radius` 200, `spacing` 110, `rng_seed` (0 = fixed seed 1: an unseeded field is still the same every time).
- Flat variant weights `w_proximity` 1.0, `w_drifting`, `w_homing`, `w_chain`, `w_pulse`, `w_emp` (0 by default). All 0 = PROXIMITY.
- `hostility` (`EnemyMine.Hostility`, default `ALL`), `drift_leash` 120, `assault_drift_speed` 60.

## Behaviour

- **Every mine the field holds** is `placed = true` with the field's hostility. The field never sets `placed_life`, so every mine
  keeps 0 and never fizzles, whatever `mine_life` its scene authors (`mine.tscn` authors 8.0 for the Bomber).
- **AUTHORED children are readied before the field**, so the field's `_ready()` sets `placed` / `hostility` on mines whose own
  `_ready()` already ran; they rely on the mine's deferred `_start_if_placed()` and launch-time mask. A child that is not an
  `EnemyMine` is a `push_error` and is ignored. Authored drifting mines keep their direction and leash and only get the field's
  where they have none.
- **Generated mines** draw their variant from the weights with the field's own seeded rng (position first, then variant, then a
  drift direction for a DRIFTING mine), so a seed builds the same field twice. A DRIFTING mine gets a random direction and
  `drift_leash` 120: it ping-pongs within 120 px of its place and never wanders off.
- **Dark and gone:** when the last mine is gone the beacon goes dark; the field frees itself 1 s later.
- **Open Space:** the field is still. **Assault** (an `assault_arena` provider exists): the field moves itself down at
  `assault_drift_speed` (the wreck precedent for scrolling), frees itself once every mine is below
  `EnemyWorld.projectile_world_rect()`, or after 40 s. It sets `EnemyMine.carry_velocity` on its mines each tick, so the
  `HazardInfo` velocity is the drift and the avoidance stage leads a carried mine.
- **Runtime spawn:** `spawn_into(container, at)` (deferred, safe in a physics callback; a freed container frees the field).

## What enemies do at a field (measured, plan §2.3)

Avoidance >= 0.8 never sets it off (closest >= 140 px to a mine centre in both modes, a ship that flies *with* the Assault
scroll). 0.6 skirts it at 96–130 px and can graze it with a large hull. The 0.5 Ram grazes it at 68–114 px. A ship with avoidance 0
flies straight in: that is the lure. Mines are never in group `enemies` and never scored.

## Tests

`tests/integration/test_minefield.gd` (pattern geometry, seeds, weights, AUTHORED ready-order boundary, 60 s no-fizzle,
drifting leash, beacon, spawn, Assault drift / world-rect / 40 s, and both modes at 8x real physics) and a registry row in
`tests/unit/test_hazards.gd`.
