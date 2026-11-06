# Enemy rework, phase 7: mines, minefields and the Mine Layer — completion report

Epic `cmug23omu000lm52wu7rak0q5`. Plan: `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` (Revision 4); review history `4-review.md` (rounds 1–3 CHANGES_REQUESTED, round 4
APPROVED). Per-task notes and every deviation: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 7 - as built* and the *Built in tN* notes above it.

## What was built

| Task | What shipped | Key files | Commit |
|---|---|---|---|
| t1 gate room | GUT 216.34 → 202.3 s (−13.8 s) with no test weakened: 8× clock on four 1× files, shared scenarios, `SpecialistExitProbe` memoised | `tests/…` (see `tests/README.md` → Gate time) | `811351f` |
| t2 mine family | `EnemyMine extends EnemyOrdnance`; Bomber's `mine.tscn` becomes PROXIMITY; `Hostility`; hazard registration on `launch()`; `placed` mode; `EnemyMineScenes` | `assault/scenes/projectiles/enemy_ordnance/mines/enemy_mine.gd`, `enemy_mine_scenes.gd`, `../mine.tscn` | `69df85e` |
| t5 boost disruption | `PlayerBase.apply_boost_disruption` / `boost_efficiency` / `disrupted_speed` / `cruise_speed`; both ships; violet ring + boost-bar tint | `global/entities/player_base.gd`, `global/ship_modules/engine_boost_module.gd`, `assault/scenes/player/states/dash_state.gd`, `open_space/scenes/gui/boost_bar.gd` | `ada3e76` |
| t3 drifting, homing | DRIFTING and HOMING variants (hysteresis, hold at the distance cap) | `mines/drifting_mine.tscn`, `homing_mine.tscn` | `e8756d2` |
| t4 chain | `chain_trigger`, ripple by delay, shot detonates, fuse links | `mines/chain_mine.tscn` | `72fbc48` |
| t6 pulse | PULSE variant, blast 8 + disruption (0.6 / 2.5 s / 170 px), `PulseRing` | `mines/pulse_mine.tscn`, `pulse_ring.gd` | `f5f3c52` |
| t7 EMP | `EmpPulse.emit`, `PlayerBase.apply_emp` stand-in, EMP variant, `EmpRing` | `global/components/emp_pulse.gd`, `mines/emp_mine.tscn`, `emp_ring.gd` | `4b947ec` |
| t10 Mine Layer shell | `MineLayer`, `MineLayerBrain` (shell), `MineLayerConfig`, pools, `drop_mine`, rail fallback, `WaveBuilder.mine_layer()` | `assault/scenes/enemies/mine_layer/` | `4f9d899` |
| t8 Minefield | `Minefield` (AUTHORED / RING / GRID / SCATTER), beacon, Assault drift; `EnemyMine.carry_velocity` | `assault/scenes/hazards/minefield/` | `c3ec47f` |
| t9 mine art | six mine sprites, homing eye, beacon (PixelLab, top-down) | `assault/assets/sprites/projectiles/mines/` | `61db03c` |
| t11 passes | APPROACH → run-in → LAY → BREAK_OFF → REPOSITION; lead / fence / assault forms; spread; live cap; tail drop | `mine_layer_brain.gd` | `a281140` |
| t12 hub idle | `AnchorIdle` IDLE / NOTICING / RETURNING; persistence rows | `mine_layer_brain.gd`, `test_mine_layer.gd` | `0f78ac6` |
| t13 layer art | 96 px hull, dispenser hatch, `MineWake` | `mine_layer.png`, `mine_layer_hatch.png`, `mine_wake.gd` | `4312174` |
| t14 hub | Mine Layer patrol (draw 15, bearing −22.5°, 2600 px) + placed RING minefield | `sector_hub.gd`, `sector_hub.tscn` | `a2169a5` |
| t15 level 1 | A layer in deep_space (16.0 s) and planet_approach (47.0 s); `EXPECTED_PH7`; deadline guards; slice replays | `level_1_director.gd`, `test_level1_specialist_spawns.gd`, `test_mine_layer.gd` | `4fed94b`, `00e63c1` |
| t16 docs | Module docs, PROJECT.md conventions, roster, ENEMY / HAZARD / MINES docs, CLAUDE.md, tests/README, this dossier, DECISIONS as-built | docs only | (this run) |

## How it was verified

- **Gate:** `bash /agent/verify.sh` (import, boot, GUT) and `scripts/check-test-leaks.sh` per task. GUT grew 2139 → 2344 tests across the phase.
- **New test files:** `tests/integration/test_enemy_mines.gd` (each variant's trigger, scene numbers, the warning rule read from scene exports, chain ripple, pulse / EMP application,
  sprites; both harnesses), `test_minefield.gd`, `test_mine_layer.gd`, `test_player_boost_disruption.gd`, `tests/unit/test_emp_pulse.gd`.
- **Extended gates:** `test_level1_specialist_spawns.gd` (`EXPECTED_PH7`, peaks 8 / 7 against the frozen 2.5× gate; spill-over with `assault_mine_life`), `test_engagement_deadline.gd`
  (no `ENEMIES_CLEARED` section holds a Mine Layer, with a detection row and a boundary), `test_sector_hub_patrol.gd` (the layer and the field in the clearance sweep), the four hand
  rosters (contact damage, contact geometry, hurtbox geometry, `test_wreck.gd` `_SHIP_SCENES`), `test_hazards.gd` (field registry row), `test_hazard_art.gd` (beacon).
- **Measured, not assumed:** avoidance distances per `hazard_avoidance` (plan §2.3, reproduced by the t2 rows: 90.1 / 99.2 / 109.1 px at 0.6, 152.9 / 152.5 / 156.2 px at 0.8; real mover 154.5 px
  head-on against a 0.0 px control); boost speeds (532, 852 → 452, 248 px/s, warp 48 px); the layer's exit (7.53 s over 2166 starts); hub clearances (585.6 / 775.1 px); hub frame cost (≈ +1.8 ms).
- **What the gate cannot see:** no gate step renders a scene. Sprites were looked at upscaled and in composites, never in a running game; nothing was play-tested for feel or fairness.

## Decisions and course changes

- **Plan review.** Round 1 found the footprint could not keep ships outside the trigger (B1, fixed by `hazard_pad` 60 and weight 1.0), contradictory zig-zag rows (B2), numbers failing the
  warning rule (B3, `home_speed` 60, `warning_time` 0.25), a refused Boost Drive that burned a tank (B4) and a hub anchor that broke the clearance rule (B5). Round 2 (N1–N11) fixed the
  crooked line (run-in), the spread rule and the lerp floors. Round 3 (R1–R6) fixed the frame latch against a standing player, the self-referencing lead (→ earliest-feasible scan), the
  placed-mine life (`placed_life`) and the corridor holding an exiting layer. Round 4 approved. Owner: "Fix those issues in your plan" (no further comments).
- **Built-time deviations** (all logged in DECISIONS): `EnemyMine.carry_velocity` (additive, so avoidance can lead a scrolling field); a placed mine also drops `use_world_rect`; the mine eject speed
  is `2d / (eject_time − 1 tick)`; the layer's `ContactHitBox` uses layer 256 / mask 0 (the COLLISION idiom), not mask 128; **LAY skips the avoidance stage** (driven through an
  acceleration-limited `mover.boost()`) because avoidance turned a layer 85° off its line near an older line; NOTICING hands over to REPOSITION, not APPROACH; the level-1 slice replays run
  on a 16× clock (a departure from the README's 8× convention); `EnemyMine` must not name its own `class_name`.
- **Not merged:** the race-track mine stays a race prop (racers are outside the rework).

## Numbers

Every number and where it comes from is tabled in plan §2.18. Headlines: mine trigger 80 / warning 0.25 s / blast 48 / damage 30 / arm 0.5 s (the Bomber's); `hazard_pad` 60, `avoid_weight`
1.0 (measured); `home_speed` 60 (derived from the warning rule), `drift_speed` 35, `chain_radius` 150 / `chain_delay` 0.2 s, pulse 0.6 / 2.5 s / 170, EMP 2.0 s / 190, `MIN_BOOST_EFFICIENCY`
0.15 (starting values); pass 6 mines, step 100, 600 px, zig-zag ±35, arc depth 110, `run_in` 150 (derived / measured by review); `lay_speed` 170, `max_speed` 240, `exit_speed` 300; passes 5–7 s
apart + 1.2 s break-off; live cap 18 / 8; Assault mine life 9 s; Open Space backstop 240 s; HP 140, contact 25, score 60; perceive / lose 650 / 1500; hub anchor −22.5° at 2600 px.
**GUT time:** 216.34 s at Ph6's close → 202.3 s after t1 → **218.44 s** at the end (allotments summed to 28.5 s; the ceiling is 240 s).

## Known gaps

- **Nothing was play-tested.** The numbers marked *starting value* are judgement. In particular: whether six mines per ~10–14 s is "gradual" or oppressive, whether 60 px/s homing is fair, and
  whether the EMP stand-in (a boost lock-out with a violet tint, not a real EMP) reads as a bug to a player.
- **Art was checked at 8× zoom and in composites only.** The drifting mine has fins but no nozzle; the beacon is 32 × 32 (generator limit); the Mine Layer hull is shield-shaped rather than
  dramatically wide; the wake is not forced behind the ships (it draws in container order).
- **A cruising player rarely sees a line laid across their path.** Above ≈ 120–150 px/s the scan finds no arrival and the layer lays a fence line beside or behind (persistence makes it matter
  on the return); above ≈ 220 px/s the layer is let go by `lose_radius` on purpose. Stated to the owner in the plan.
- **EMP is a stand-in** on the player, reaching group `player` only; enemies, seeking weapons and the real effect are Ph9. Pulse and EMP mines never affect enemies.
- **In LAY the layer ignores avoidance**, so it crosses an older line, and a placed ALL minefield in its path could set it off (PLAYER mines cannot).
- **Gate time is tight:** 218.44 s, 0.4 s under t15's allotment ceiling, run noise ≈ ±1 s; the phase has 21.6 s of headroom to 240 s, but Ph8+ must not assume more.
- **Two unidentified single-test flakes** (a t13 `verify.sh` run and a t14 `gate-time.sh` run each reported one red test whose name was not captured; a later run printed `GUT LEAKED at exit` once in
  t1). Every re-run was green. If one recurs, capture the test name first.
- **No Assault level places a minefield** (Ph15); the scene is proven only in the Assault harness.
- **Mine audio, difficulty scaling and encounter compositions** are later phases (17, 16, 13/14).
- The hub frame cost (+1.8 ms of script time per frame for the layer, its idle, nine mines and their registrations) was measured headless without rendering and is approximate.

## Links

- Epic id `cmug23omu000lm52wu7rak0q5`; plan `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md`, review `4-review.md`; t11's own plan `docs/plans/cmvkb0hdc00uiqs2xhvb2awai/3-plan.md`.
- Phase record: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 7 - as built (2026-10-27)*.
- Docs: `docs/architecture/PROJECT.md` → Conventions, `docs/architecture/modules/assault.md` → *Mines and the Mine Layer*, `global.md` → Hazards / Boost disruption / EMP hook,
  `docs/enemy-roster.md` → `mine_layer`, `assault/scenes/enemies/mine_layer/ENEMY.md`, `assault/scenes/hazards/minefield/HAZARD.md`, `assault/scenes/projectiles/enemy_ordnance/mines/MINES.md`.
- Commits: listed in the table above (`811351f` … `00e63c1`).
