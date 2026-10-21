# Enemy rework, phase 6: hazard perception, gravity wells, anomalies and wreck fields — completion report

Epic `cmug23om70001m52wqfwclf3l`. Plan: `docs/plans/cmug23om70001m52wqfwclf3l/3-plan.md` (revision 2), review in `4-review.md`,
tasks in `tasks.json` (19 tasks, t1-t19; task plans for t4, t10 and t14 are under `docs/plans/`). The "Phase 6 - as built
(2026-10-21)" section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` indexes every deviation; this report is the narrative.
Where they differ from the plan, "as built" wins.

## What was built

| Task | What shipped | Commit |
|---|---|---|
| t1 registry | `HazardInfo` (with claims), `Hazards`, `HazardField`, `HazardDrift`, `pulse_damage` | `fbf3bc8` |
| t2 enemy drift | Drift, slow and `own_velocity()` in `EnemyMover`; three profile fields; brain gates read `own_velocity()` | `dc8256c` |
| t3 players | Open Space ship and Assault fighter feel pull and slow; forced boost out of a core | `5705c2d` |
| t4 avoidance | Context-steering stage in `EnemyMover` (`Steering.context_avoid`), claimed-cover skip | `27b8f25` |
| t5 field art | Gravity well, anomaly, Gravity Field and reactor field sprites | `a329245` |
| t6 / t7 | Gravity Well; Energy Anomaly (pulsing swirl) | `e18fdf8`, `4cc44ee` |
| t8 projectiles | Rockets, bombs and player homing / warhead missiles bend in fields; bullets fly true | `704f7b8` |
| t9 wreck art | Wrecks, explosive wreck, satellite, cargo platform, station module | `bf14cd8` |
| t10 wreck family | `Wreck`, `DebrisFragment`, `WreckScenes`; solid, LOS-blocking, stop enemy rounds, yield rule | `4585d17` |
| t11 deaths leave wrecks | `BaseEnemy._maybe_leave_wreck()`, `HazardContainer` in level 1 and hub, caps, level-1 exit guard | `99f7ca6` |
| t12 explosive wrecks | Fused blast, `pulse_damage`, brief reactor field | `524d150` |
| t13 Sniper cover | `can_see_player()`, far-side cover candidates, claims, hysteresis | `55e877a` |
| t14 Fighter cover | `Phase.COVER` for solos and LEADs, the swoop rule | `2ec7582` |
| t15 Debris Charge | A broken Ram plate becomes a 12-damage `DebrisFragment` | `e813aa8` |
| t16 Ram well station | Ticketed station on the far side of the player from a well | `b363715` |
| t17 Gravity Field | A gravity bomb leaves a 3.5 s slowing field | `a1e94b2` |
| t18 hub | `TacticalSpace`: well, anomaly, derelict cover, still debris | `bb793cc` |
| t19 docs and close | `global.md`, `assault.md`, `open_space.md`, `PROJECT.md`, `CLAUDE.md`, roster, `ENEMY.md` x3, `HAZARD.md` per hazard, `tests/README.md`, DECISIONS, this dossier | this commit |

## How it was verified

`bash /agent/verify.sh` was green at every task. New coverage is dual-mode (Open Space and Assault) in `tests/unit/test_hazards.gd`,
`test_hazard_field.gd` and `tests/integration/test_context_avoidance.gd`, `test_player_hazards.gd`, `test_wreck.gd`,
`test_wreck_spawning.gd`, `test_hazard_projectiles.gd`, `test_hazard_art.gd`, `test_gravity_well.gd`, `test_energy_anomaly.gd` and the
Sniper / Fighter / Ram / Bomber / ordnance / hub-patrol files; collision rows use real physics on the 8x clock. The level-1 gates are
unchanged because level 1 has no hazard until a wreck is left, and `test_level1_fighter_exit.gd` replays cloud_descent with wrecks.

**Final gate (2026-10-21, `scripts/gate-time.sh`):** import 4.5 s, boot 1.2 s, GUT `Time` **216.3 s** (wall 221.4 s, total 227.1 s),
141 scripts, 2139 tests, 2139 passing, 78 348 asserts. Under the 240 s ceiling by 24 s; about 16 s over the Phase 5 close, inside the
35.5 s allowance. Per-task numbers are in `tests/README.md` -> Gate time.

## What no human has play-tested

Nothing in this phase has been flown by a person. Every number (well pull 520 and reach, anomaly rhythm, slow factors, wreck
chances / sizes / caps, avoidance and resistance per enemy, cover distances, the Ram's station) is a **starting value** chosen from the
plan and pinned by tests, not tuned by feel. Unjudged by eye: whether the hazard and wreck sprites read as dead hulls and distortions
in motion; whether wells feel like bait rather than a magnet; whether avoidance looks like temperament or like jitter; whether the hub's
tactical space is discoverable; whether wreck density in Assault is welcome. The art was checked image by image, not in a running game.

## Gaps left for later phases

- **Level-1 fighters practically never take cover** (the check runs on the spawn tick, outside the corridor; the Assault swoop band
  is 300-325 px). Checking at corridor entry is an owner option. Cover is mostly an Open Space behaviour.
- The Assault Ram well station never fires with the shipped `engage_seconds` 4.0 (needs 4.5); level 1 has no wells, so nothing changes.
- Wingman cover and squad-coordinated cover (Ph14); the anomaly's shield / targeting variants and a deliberate plate throw (owner
  options); `disables_abilities` ships with no producer (Ph9); mines (Ph7); laser walls (Ph8); capital-ship wrecks (Ph19); hazard
  audio (Ph17); placed hazards in Assault levels (Ph15).
- Fighter cover is checked at entry only; a player that moves away mid-hide can still be met on a slow lead-in (bounded, documented).
- Ph7 must start by recovering gate time (216 s of 240 s).
