# Progress

- [x] **Step 1 — failing test first.** `tests/integration/test_space_station.gd` (9 tests).
      Confirmed red before any implementation: parse errors on the four missing symbols
      (`space_station.tscn`, `space_station_config.tres`, `SpaceStation`, `StationTurret`).
      **Discovery worth keeping:** GUT does not *report* an unloadable test script — it drops it
      silently, printed `All tests passed!`, ran only 2 scripts and **exited 0**. `/agent/verify.sh`
      step 3 checks the exit code and greps for `N failing`, so neither would have caught it. The
      red was confirmed by reading stderr, not from GUT's verdict. Filed under *Discovered*.
- [x] **Step 2 — config.** `space_station_config.gd` (`SpaceStationConfig extends ShipConfig`,
      adds only `turret_health`) + `space_station_config.tres` (`max_health = 600`,
      `turret_health = 120`, `collision_damage = 40`, `score_value = 1000`).
- [x] **Step 3 — turret.** `station_turret.gd` + `station_turret.tscn`. Collision set in script
      per **N1/F1**: `collision_layer = 512`, `collision_mask = 97 | 1024`. Wreckage on death
      (`monitoring` + `monitorable` + shape `disabled`), idempotent via `_alive`.
- [x] **Step 4 — station.** `space_station.gd` + `space_station.tscn`. `extends BaseEnemy`,
      `armor_deflected(damage)` signal, live-read `live_turret_count()` per **N2**, contact damage
      re-applied per **F3/N5**, `add_to_group("enemies")` per **F9**.
- [x] **Step 5 — sprites.** Three PixelLab `create_image_pixflux` generations (3 of 1980 used),
      verified at exactly 256×256 / 64×64 / 64×64, imported so `.import` sidecars exist. No
      aesthetic iteration — all three were serviceable first time.
- [x] **Step 6 — UID hygiene (F11).** Every `[ext_resource]` UID copied from the target's own
      `.gd.uid` / `.import` / header. The two new scene UIDs were **minted with
      `ResourceUID.create_id()`**, not typed by hand — the backlog's *Discovered* section flags
      hand-written UIDs as a latent collision risk, and an invented one would have passed the
      integrity test (it only checks pairing) while carrying that risk.
- [x] **Step 7 — suite green.** 9/9 station tests; 29/29 across `tests/integration/`.
- [ ] **Step 8 — docs + backlog.** `ENEMY.md`, `updating-project-docs`, tick `BACKLOG.md`.

## Mutation testing — evidence the suite is not vacuous

The reviewer warned (N1) that a green suite is weak evidence here. Four mutants were run:

| Mutant | Result |
|---|---|
| `is_armored()` inverted to always-false | **4 tests fail** ✔ |
| `_alive` guard removed from `_on_health_changed` only | survives — see below |
| `_alive` guard removed from `_on_received_damage` only | survives — see below |
| **Both** `_alive` guards removed | **`test_destroyed_turret_ignores_further_damage` fails**: `destroyed` emit count 4, expected 1 ✔ |

The two single-guard mutants survive because either guard alone is sufficient: with the intake
guard, a dead turret's `Health` is never touched; with the death-path guard, a re-emitted
`amount_changed(0)` cannot re-enter `_destroy()`. The guards are redundant *with respect to each
other*, not dead code — removing both reproduces exactly the `set_health`-always-emits defect the
test exists to catch, and the test fails. Both are kept so each function is correct in isolation.

## Deviations from plan

None in design. Two additions the plan did not specify:
- Scene UIDs minted via `ResourceUID.create_id()` rather than hand-written (step 6 above).
- The station root also gets `collision_mask = 0`, not just `collision_layer = 0` (**N4**). The
  note only specified the layer; a 256×256 `CharacterBody2D` with a non-zero mask would still
  collide *against* the environment, which is meaningless for a station that never moves.

**Resume at:** step 8.
