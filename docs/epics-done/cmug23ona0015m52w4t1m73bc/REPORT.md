# Enemy rework, phase 8: energy weapons, defense turrets and Twin-Laser Drones — completion report

Epic `cmug23ona0015m52w4t1m73bc`. Plan: `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md` (revision 2); review `4-review.md` (round 1 CHANGES_REQUESTED, answered in plan §8). Per-task notes and
every deviation: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 8 - as built (2026-11-06)* and the *Built in tN* notes above it.

## What was built

| Task | What shipped | Key files | Commit |
|---|---|---|---|
| t1 gate room | GUT 219.06 → 199.99 s (−19.1 s), nothing weakened; a bit-identical `FighterBrain` squad give-way speed-up | `tests/…`, `fighter_brain.gd` | `82924c9` |
| t2 beam core | `EnemyBeam` BEAM / SWEEP / LANCE, timeline, `EnergyHitScan`, owner set, direct emit | `assault/scenes/projectiles/enemy_beams/` | `ca48074` |
| t3 Pulse Ring | `EnergyRing` | `energy_ring.gd/.tscn` | `a20891e` |
| t4 segment hazards | `HazardInfo.segment_half` / `exempt_group`, `Steering` segment branch | `global/…/hazard_info.gd`, `steering.gd` | `1c9f541` |
| t5 endpoint beams | TWIN kind, cover clipping, strain, `&"laser_wall"` registration | `twin_beam.tscn` | `daff3de`, `1acfeef` |
| t6 turret shell | `DefenseTurret`, brain, `TurretMount`, burst cannon, `AssaultDrift` | `defense_turret/`, `global/components/assault_drift.gd` | `da9a8a6` |
| t17 level-1 columns | `laser_column_schedule()`, measurement script, opt-in `LaserRay.registers_hazard` | `level_1_director.gd`, `scripts/measure-level1-columns.sh` | `8ef43e3` |
| t7 / t8 mounts | SWEEP_BEAM, LANCE, BEAM_CANNON; ROCKET_BATTERY, PULSE_RING | `defense_turret/mounts/` | `aac878c`, `7e85b84` |
| t9 / t9s groups | `TurretGroup`, `PowerSource`, `assault_pair` preset, `ShieldGenerator` | `structures/turret_group/` | `1f708d3`, `fc5d6dc` |
| t10 laser fence | `LaserEmitter`, `LaserFence` (STATIC / CYCLE), linger | `structures/laser_fence/` | `2ad87bc` |
| t11 heavy emplacement | beam cannon + burst cannon, independent aim | `heavy_emplacement/` | `4772ffc` |
| t12 / t13 drones, tender | `TwinLaserDrone`, `TwinLaserPair`, `TwinLaserPairSpawn`; `LaserTender` and Attack B | `twin_laser_drone/`, `laser_tender/` | `d865fa2`, `7926c8e`, `cb7fed4`, `7597711` |
| t14 hub idle, exits | `AnchorIdle` for pair and tender; two memoised corridor exit probes | `tests/helpers/ph8_exit_keys.gd` | `ccb8bd9`, `bc991e4` |
| t15 / t16 art | static structure heads / bases; drone, tender, cradles | `assault/assets/sprites/…` | `3bff056`, `2711e16` |
| t18 hub | defended derelict site, tender and pair patrols, sweeps A and B | `sector_hub.tscn/.gd`, `hub_defense_site.tscn` | `8d2af49` |
| t19 level 1 | group + pair in deep_space, tender in planet_approach; `EXPECTED_PH8`; replays | `level_1_director.gd` | `63691e2`, `a87b58a` |
| t20 docs | module docs, PROJECT.md conventions, roster, per-entity docs, CLAUDE.md, tests/README, this dossier, DECISIONS as-built | docs only | (this run) |

## How it was verified

- **Gate:** `bash /agent/verify.sh` (import, boot, GUT) and `scripts/check-test-leaks.sh` per task. GUT grew 2344 → 2634 tests across the phase.
- **New test files:** `test_enemy_beams.gd`, `test_energy_ring.gd`, `test_defense_turret.gd`, `test_turret_group.gd`, `test_laser_fence.gd`, `test_twin_laser_drones.gd`, `test_laser_tender.gd`,
  `test_ph8_sprites.gd`, `test_level1_laser_columns.gd`, `test_level1_ph8_attacks.gd`; extended: hazards / context-avoidance units, the roster gates, `test_base_enemy.gd`, `test_enemy_dual_mode.gd`,
  `test_enemy_bullet_lifetime.gd`, `test_sector_hub_patrol.gd` (sweeps A and B), `test_level1_specialist_spawns.gd` (`EXPECTED_PH8`, column clearance, alive curves),
  `test_engagement_deadline.gd` (no Ph8 structure / drone / tender in `ENEMIES_CLEARED`).
- **Measured, not assumed:** level-1 column and wall kills (`scripts/measure-level1-columns.sh`); alive curves (deep_space 12 at 29.0 s against 12.5; planet_approach 7 at 28.4 s against 7.5); measured
  corridor exits for the drone (5.83 s) and the tender (3.82 s); the real-player i-frame cadence.
- **What the gate cannot see:** no gate step renders a scene. Art was looked at upscaled and in composites, never in a running game; nothing was play-tested for feel or fairness.

## Decisions and course changes

- **Plan review (round 1):** gate allotments re-summed to 33.1 s with the exit probes budgeted (B1); the tender moved to the 2.0 s wave and the pair to 29.0 s (B2); world-anchored x and the
  diagonal `assault_pair` layout (B3); same-file tasks chained (B4); `rehit_interval` 0.55 s (N1); `telegraph_width` export (N2); `turn_rate_override` (N3); hub sweeps A / B (N4); fence linger (N8).
- **Built-time deviations** (all in DECISIONS): the level-1 group sits at **+64**, not −64 (the level-start `LaserWallWave` killed it); cover beams bite 2 px into the blocker they end on; the real-player
  cadence rows run at 4×, not 8×; `launch_pair()` adds the drones synchronously; the launched advance is capped at `standoff`; the drone exit probe runs speeds `[10]` only; cradle positions
  moved to the art; the hub heavy emplacement and power source offsets moved off overlapping derelicts; the hub barrier is an inherited scene; no `rng_seed` export on the group.

## Numbers

Every number and its origin is tabled in plan §2.21. **§2.21 starting values (judgement, not play-tested):** beam telegraph 0.9 s; ignite grace 0.1 s; hit / drawn half-width 12 / 16 px;
`rehit_interval` 0.55 s (derived: above the player's 0.5 s i-frames); telegraph line 4 px (≥ 3); fence linger 1.0 s; sweep 100° over 2.0 s, length 400; lance commit 0.5 s, active 0.2 s, 24 dmg;
Pulse Ring 360 px/s to 280 px, band 24, two 45° gaps at 30°/s; turret burst 4 @ 0.12 s with 2.2 s cooldown, rockets 2 per 5.5 s; `lead_blend` 0.6; HP 90 / heavy 260 / generator 120 / source 150 /
post 140; group stagger 0.3 s; twin rig L 420, tolerance 16, strain 0.15 s, advance 240 px/s, standoff 260; drone HP 30; tender rearm 7.0 s, launch 520 px/s ≤ 1.4 s, lead ≤ 1.5 s; Assault drift
60 px/s. Level-1 placements: group at (+64, −220) in the 3.0 s deep_space wave, pair at 29.0 s, tender in planet_approach's 2.0 s wave.
**GUT time:** 219.06 s at Ph7's close → 199.99 s after t1 → **212.4 s** at the end of t19 (ceiling 240 s).

## Known gaps

- **Nothing was play-tested.** All §2.21 judgement values are unverified, in particular whether a 0.9 s telegraph and 0.55 s re-hit feel fair, whether the diagonal turret group is dangerous enough, and
  whether the twin wall can be slipped round at 240 px/s advance.
- **Art was checked at upscaled sizes and in composites only.** The readability of six turret head silhouettes at 48 px is the most likely art redo.
- **Level-1 columns still kill some AI enemies** (deep_space 20, planet_approach 5 in the last measurement) even with `registers_hazard`; that is the lasers working as designed, not a bug, and the
  measurement only counts ships with a brain, so brainless structures (power sources) are never in it. **A static thing in deep_space must clear the level-start `LaserWallWave` as well as the schedule.**
- **The mining beam still stops at every layer-1 enemy root** (S13); only the new roots answer `is_laser_blocking()` false.
- **No kill attribution:** a kill by an enemy weapon scores for the player.
- **Deferred to later phases:** turrets on ships and bosses (Ph10 / Ph11), the station on `EnemyBeam` and an endpoint-rig beam rotating about an anchor (Ph11), jammer-linked groups and `disables_abilities`
  (Ph9 / Ph20), placed Assault corridor layouts (Ph15), difficulty tiers (Ph16), audio (Ph17), turret wreckage (Ph19).
- **Gate time:** 212.4 s, 27.6 s of headroom; run noise ≈ ±1 s. The two corridor exit probes cost ≈ 4.5 s once per run via a process-wide memo, and break if a probe call is built outside `ph8_exit_keys.gd`.
- **One unidentified single-test flake** in a t18 timing run (name not captured); the next two full runs were green. If it recurs, capture the test name first.
- **Hand-ticked tests never cast cover rays**; every cover row must run on real physics at 8×, or it silently passes.

## Links

- Epic id `cmug23ona0015m52w4t1m73bc`; plan `docs/plans/cmug23ona0015m52w4t1m73bc/3-plan.md`, research `2-research.md`, review `4-review.md`.
- Phase record: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 8 - as built (2026-11-06)*.
- Docs: `docs/architecture/PROJECT.md` → Conventions (items 4–13), `docs/architecture/modules/assault.md`, `global.md` (hazards, `AssaultDrift`), `docs/enemy-roster.md`, `assault/scenes/projectiles/enemy_beams/BEAMS.md`,
  the `ENEMY.md` of each new enemy and the `STRUCTURE.md` of `turret_group/` and `laser_fence/`.
- Commits: listed in the table above (`82924c9` … `a87b58a`).
