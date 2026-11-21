# Enemy rework, phase 9: electronic warfare - Jamming Structure, Hacker Frigate and EMP — completion report

Epic `cmug23onr001pm52w9swwophy`. Plan: `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` (revision 3); review `4-review.md` (round 1 and 2 CHANGES_REQUESTED, answered in plan §8). Per-task notes and every
deviation: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → *Phase 9 - as built (2026-11-10)* and the *Phase 9, built in tN* notes above it.

## What was built

| Task | What shipped | Key files | Commit |
|---|---|---|---|
| t1 ability lock | `PlayerBase` lock (H + K only), `Hazards.jammer_at`, `HazardInfo.stabilise_seconds`, `HazardField` jammer exports | `global/entities/player_base.gd`, `global/hazards/` | `3d0422c` |
| t3 homing lifetime | `ProjectileLifetime` replaces the Assault-only box | `homing_missile.gd` | `5d814dc` |
| t2 lock tells | `AbilityLockStatic`, JAMMED chip, rocket lock glyph, EventBus seams | `ability_lock_static.gd`, `mission_hud.gd` | `d0dc62d` |
| t4 hijack hook | `SeekingOrdnance` contract, hijacked homing rocket, seekers jammed in a field | `global/components/seeking_ordnance.gd` | `68f5370` |
| t5 EMP | player effect = boost disruption + lock; `EmpPulse` targets; `BaseEnemy.answers_emp()` hook | `emp_pulse.gd`, `base_enemy.gd` | `66ef0b8` |
| t6 EMP Blast | module routes by `answers_emp()` | `emp_blast_module.gd` | `31767b9`, `9b02f26` |
| t7 jammers | `JammingStructure` local / sector / pulsed, `JammerFieldArt`, `HazardField.suppress` | `enemies/jamming_structure/`, `sector_jammer/`, `pulsed_jammer/` | `5530def` |
| t11 EMP zone | `EmpZone` with child `HazardField` | `hazards/emp_zone/` | `227aa45`, `1c20d05` |
| t8 Hacker | `HackerFrigate`, `HackerFrigateBrain`, config, arcs, cone escape, break-off, Assault life, hub idle | `enemies/hacker_frigate/` | `46c9c09` |
| t9 Hijack Pulse | TELEGRAPH / PULSE, `HijackPulse` dart, claims, Disruptor hook | `projectiles/hijack_pulse/` | `290fb33` |
| t10 Disruptor | scene + config, lock at PULSE end (not placed) | `enemies/hacker_disruptor/` | `f160da6` |
| t12 art | Hacker, dish, Disruptor fin, three towers, EMP beacon | `assault/assets/sprites/` | `0013f4c` |
| t13 hub | Hacker patrol (draw 18), sector jammer, pulsed jammer, EMP zone | `sector_hub.tscn/.gd` | `7d25c23` |
| t14 level 1 | one Hacker (42.0 s) and one jammer (62.0 s) in planet_approach; `EXPECTED_PH9`; guards | `level_1_director.gd` | `6e24f59` |
| t15 docs | module docs, roster, per-entity docs, CLAUDE.md gate list, dossier, DECISIONS as-built | docs only | (this run) |

## How it was verified

- **Gate:** `bash /agent/verify.sh` (import, boot, GUT) and `scripts/check-test-leaks.sh` per task. GUT grew 2634 → 2888 tests; GUT time 212.4 s → about 225 s (budget ≤ 238 s).
- **New gate files:** `test_player_ability_lock.gd`, `test_player_ability_lock_tells.gd`, `test_homing_missile_lifetime.gd`, `test_seeking_ordnance.gd`, `test_enemy_emp.gd`, `test_emp_blast_module.gd`,
  `test_jamming_structure.gd`, `test_emp_zone.gd`, `test_hacker_frigate.gd`, `test_hijack_pulse.gd`, `test_ph9_sprites.gd`, `test_level1_ph9_attacks.gd`, plus Phase 9 rows in the roster, hub, deadline and spawn gates.

## Deviations and open items

See DECISIONS.md → *Phase 9 - as built*. Nothing was play-tested; the hijack tuning against a still, firing player is an open owner question.
