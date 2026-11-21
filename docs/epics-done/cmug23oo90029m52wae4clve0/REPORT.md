# Enemy rework, phase 10: modular damage, Heavy Gunship and Carrier — completion report

Epic `cmug23oo90029m52wae4clve0`. Plan: `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` (revision 2); review `4-review.md` (round 1 CHANGES_REQUESTED, answered in plan §8). Per-task notes and every
deviation: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 10 - as built (2026-11-18)* and the *Phase 10, built in tN* notes above it.

## What was built

| Task | What shipped | Key files | Commit |
|---|---|---|---|
| t1 gate room | GUT 224.7 → 192.1 s (≥ 12 s floor met) | test suite / `tests/README.md` | `503faeb` |
| t2 modules | `EnemyModule`, `ModularHull`, beam / nova reach of `enemy_parts` | `global/components/enemy_module.gd`, `modular_hull.gd` | `293f34d` |
| t3 mounts | `TurretMountBuilder`, `traverse_deg`, `HEAVY_CANNON` (Heavy Shell's first consumer) | `global/components/`, `assault/scenes/enemies/defense_turret/` | `2f7425b` |
| t4 Heavy Gunship shell | `gunship/` → `heavy_gunship/`, rectangle body, flush-edge parts, movement, Assault life, legacy rows moved | `assault/scenes/enemies/heavy_gunship/` | `0f41d93`, `92ff4cb` |
| t5 Gunship phases | CONTROLLED / OVERHEAT / EMERGENCY, vents, rear pod, cannon shield | same | `c3f397a`, `bab5066` |
| t6 Carrier shell | armoured hull, seven parts, core exposure, both-mode movement, EMP-proof crossing | `assault/scenes/enemies/carrier/` | `a6e24a6`, `7bdd10b` |
| t7 Carrier weapons | side batteries, bow cannon, missile bank, pulse ring, PANIC | same | `e17f753` |
| t8 hangars | `CarrierHangars`, doors, launches, caps, emergency deployment | same | `2791f05` |
| t9 art | 19 hand-drawn sprites, widened transparency walk | `assault/assets/sprites/enemies/heavy_gunship/`, `carrier/` | `aad6094` |
| t10 hub | draws 19 (Heavy Gunship) and 20 (Carrier) | `open_space/` hub | `7225e63` |
| t11 level 1 gunships | four Heavy Gunships off rails, lit slice replay, deadline rocket term | `level_1_director.gd`, `tests/helpers/level1_slice_replay.gd` | `8df0d59`, `68ecccb`, `7aba280` |
| t12 level 1 Carrier | one Carrier in planet_approach 65.0 s | `level_1_director.gd`, `tests/helpers/level1_carrier_timeline.gd` | `99edde0` |
| t13 docs | module docs, roster, per-entity docs, CLAUDE.md gate list, dossier, DECISIONS as-built | docs only | (this run) |

## How it was verified

- **Gate:** `bash /agent/verify.sh` (import, boot, GUT) and `scripts/check-test-leaks.sh` per task. GUT grew 2888 → 3062 tests; GUT time 192.1 s after t1 → ≈ 210.3 s at t12 (ceiling 240 s; the t11 overrun of the 3.0 s allotment was owner-accepted).
- **New gate files:** `test_enemy_module.gd`, `test_turret_mount_traverse.gd`, `test_heavy_gunship.gd`, `test_carrier.gd`, `test_carrier_hangars.gd`, `test_level1_heavy_spawns.gd`, `test_ph10_sprites.gd`, plus the widened
  `test_entity_sprite_transparency.gd` walk and Phase 10 rows in the roster, hub, deadline, drone-density and slice-replay gates.

## Deviations and open items

See DECISIONS.md → *Phase 10 - as built*. Nothing was play-tested (three firing Heavy Gunships in Cloud Descent, the Carrier's crossing, the vent window). In the level-1 Carrier replay only the side guns
fired; the bow cannon and missile bank are untested there, and nothing checks whether the carrier's drones fly into a lit laser column.
