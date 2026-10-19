# Enemy rework, phase 5: Missile Corvette, rockets and the Support/Shield Ship — completion report

Epic `cmufs7elw001pnm2xr3b6fteb`. Plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` (**Revision 2**), review in `4-review.md`,
tasks in `tasks.json` (18 tasks, t1-t18; task-level plans for t8, t11 and t17 are under `docs/plans/`). The "Phase 5 - as built
(2026-10-19)" section of `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` indexes every deviation; this report is the narrative.
Where they differ from the plan, "as built" wins.

## What was built

| Task | What shipped | Commit |
|---|---|---|
| t1 gate room | 8x clock on the slow real-physics files; GUT 253.4 -> 176.9 s; `scripts/gate-time.sh` | `120762d` |
| t2 enemy shields | `EnemyShield`, the `HurtBox` absorber slot and `hit_absorbed`; cyan arc; `test_enemy_shield.gd`, `test_enemy_shield_hits.gd` | `989b7f9` |
| t3 repair and tow | `BaseEnemy.repair()`, `can_be_repaired()`, `is_ai_driven()`, `accept_tow()`, `EnemyBrain.accepts_tow()` in seven brains | `10c97f5` |
| t4 view rect | `ArenaCamera.enemy_view_rect()`, `EnemyWorld.view_rect()` | `bd1a501` |
| t5 Dumb + Pursuit | `EnemyRocket` contract, `EnemyRocketScenes`, rocket collision on layer 32, `rocket_launcher_fixture.gd` | `331cbfa` |
| t6 Cluster + Warhead | Split into four unpooled submunitions; proximity-triggered, blinking Delayed Warhead | `dc1cfd3` |
| t7 corvette shell | Scene, config, four persistent pools, `fire()`, `launch_velocity()`, rail fallback, Assault exit | `1494271` |
| t8 corvette fight | HOLD_ARC, launch cone, TELEGRAPH, SALVO, predicted aim points, kind choice | `c986053` |
| t9 corvette and rocket art | 96 x 96 hull with two tubes; five nose-up rocket sprites | `9118ebb` |
| t10-t13 Support Ship | Shell (contact NONE); ward choice, retarget, soft anchor, Assault view clamp; repair pulse and projected shield; emergency escort and 360 deg bubble | `cee5193`, `fcdcbe4`, `1b2f3f1`, `7555b80` |
| t14 support art | 88 x 88 hull and a 48 x 40 dish projector that unfolds | `9395589` |
| t15 hub idle | IDLE / NOTICING / RETURNING for both ships | `4139006` |
| t16 hub placement | Corvette on a 1900 px ring at 315 deg; Support on the Ram Corvette's anchor | `4eb9c28` |
| t17 level 1 | 3 corvettes and 2 supports in the DURATION sections; count, deadline and attack-in-budget gates | `c219200` |
| t18 docs and close | Both `ENEMY.md` (with the §43 checklist), roster, module docs, conventions, `BULLET_POOL.md`, `CLAUDE.md`, `tests/README.md`, DECISIONS, this dossier | this commit |

## How it was verified

The gate (`bash /agent/verify.sh`: import, boot, GUT) was green at every task. New GUT coverage is dual-mode (Open Space and Assault,
hand-ticked) where the behaviour is shared, with real physics on the 8x clock only where a collision is the point (rocket shoot-down,
friendly fire, pool hand-over, a hub corvette's rocket landing in the container, the level 1 slice replays). Suite size grew from 1593
tests at the start to 1835 at t17. `scripts/check-test-leaks.sh` printed `LEAK CHECK PASS` for t16 and t17.

### Gate time per task

GUT `Time` from `scripts/gate-time.sh`. "-" means that task's report did not record a before / after pair.

| Task | Allotment | Before -> after |
|---|---|---|
| t1 | frees >= 70 s | 253.4 -> 176.9 s |
| t2 | 3.0 s | 177.6 -> 176.9 s |
| t3 | 2.0 s | - |
| t4 | 0.5 s | - |
| t5 | 6.0 s | 177.5 -> 180.0 s |
| t6 | 4.0 s | 180.0 -> 182.1 s |
| t7 | 3.0 s | - |
| t8 | 5.0 s | 182.9 -> 183.3 s |
| t9 | 0.5 s | 183.3 -> 183.25 s |
| t10-t13 | 2.0 / 4.0 / 4.0 / 3.0 s | - (183.3 -> 184.4 s across the four) |
| t14 | 0.5 s | 184.4 -> 185.4 s (no new tests: noise) |
| t15 | 2.0 s | 185.4 -> 185.5 s |
| t16 | 2.0 s | 185.5 -> 185.4 s |
| t17 | 15.0 s | 186.0 -> 201.8 s full suite; +12.2 s on the four affected files |
| t18 | 0 s | docs only |

t17's full-suite delta (+15.8 s) is over its allotment, but `test_fighter_squad.gd`, which it did not touch, moved from 63.2 to 66.4 s
between the two runs. GUT stayed under the 240 s ceiling throughout (about 198 s in the last gate).

## What changed course

See DECISIONS "Phase 5 - as built" for all ten items. The ones a reader is most likely to trip on: owner-distance lifetime was not built
(rockets carry their own caps); `DamageReaction` was not adopted for enemies; `launch_velocity()` on a rail is read per physics tick; a
rocket's `expired` lags a detonation by two physics ticks; `break_contact` inside an orbit uses `-orbit_dir`; a shield does not cover an
`ArmorPlate`; the level 1 support spawns 116 px outside the projectile world rect on purpose.

## Known gaps

- **Never play-tested by a human.** Play-feel cannot be tested headless. Nobody has checked that the 0.7 s salvo telegraph is a fair window at
  Assault speed, that a Pursuit rocket can be out-turned by feel, that the cyan arc, tether and projector unfold read at a glance, that
  the escort tow looks like rescue rather than a glitch, or that the added level 1 and hub ships feel right rather than crowded. The numbers
  were set by arithmetic, research and seeded hand-ticks.
- At the default `shield_capacity` 40, one Standard shot (50) breaks a projected shield and it then reboots for 4 s; whether that is too
  weak a shield is a Ph16 tuning question.
- `ArmorPlate` is not covered by a shield; module shields (Ph10) must sit on a plain part.
- The Delayed Warhead's proximity trigger fires on allies as well as the player (the Ph4 mine does the same).
- Friendly fire from blasts and beams is undecided (Ph8); only rocket impacts hurt enemies.
- No rocket audio, no flare / decoy reaction, no Hijack Pulse. The Support Ship has no state light.
- Neither enemy is in `level_2_waves.gd` or the station's reinforcements (Ph15); neither may go in an `ENEMIES_CLEARED` section.
- The local-module shield is proven only by a fixture; its shipped consumer is Ph10.
- Gate time is about 200 s of the 240 s ceiling; Phase 6 has little room and `test_fighter_squad.gd` alone costs about 63 s.
- The Support Ship's level 1 spawn point is outside the projectile world rect; harmless today, would matter if something started freeing
  AI enemies there.

## Links

- Plan directory: `docs/plans/cmufs7elw001pnm2xr3b6fteb/` (`1-context.md`, `2-research.md`, `3-plan.md`, `4-review.md`, `tasks.json`).
- Task plans: t8 `cmv9szqlq001zqs2x6vi0nlxj`, t11 `cmv9szqlz002bqs2x0h47xa3x`, t17 `cmv9szqmi002zqs2x3cd8f942`.
- Entity docs: `assault/scenes/enemies/missile_corvette/ENEMY.md`, `assault/scenes/enemies/support_ship/ENEMY.md`; `docs/enemy-roster.md`.
- Earlier phases: `docs/epics-done/cmufklb100001p92xs1ey2fb1/` (Ph1), `cmufs7ek60001nm2x6d0bt2et/` (Ph2), `cmufs7ekv000lnm2x7nbswijy/` (Ph3),
  `cmufs7ele0015nm2xvag3vrwc/` (Ph4).
