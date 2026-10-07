# Enemy rework, phase 3: Fighter, Gatling Interceptor and the bullet family — completion report

Epic `cmufs7ekv000lnm2x7nbswijy`. Plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` (**Revision 2**), review history in
`4-review.md`, tasks in `tasks.json` (19 tasks: t1–t7, t8a/t8b, t9–t18). The decision log's **"Phase 3 - as built"** section in
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` is the index of every deviation; this report is the narrative.

## What was built

### Foundations (t1–t5, direct track, one commit each)

| Task | What shipped | Commit |
|---|---|---|
| t1 pin | `test_level1_fighter_spawns.gd` pins every fighter / interceptor spawn row of level 1 from data, with the legacy peak constants **frozen** (`_LEGACY_PEAK_FIGHTERS` 10 / 10 / 8, `_LEGACY_PEAK_SHOTS_PER_S` 31.25 / 33.33 / 15.0) and asserted equal to a live computation of the rails; `test_station_reinforcements.gd::test_rail_reinforcements_fire` | `628557e` (first attempt `6928965`) |
| t2 rounds | `assault/scenes/projectiles/enemy_bullet/rounds/` — Pulse, Scatter, Gatling Stream, Heavy Shell (inherited scenes of `enemy_bullet.tscn`), `EnemyRounds` (`pool_size_for`), `EnemyBullet._authored_speed/_authored_damage` so `reset()` restores the scene's identity; the per-round lifetime sweep; `test_enemy_rounds.gd` | `51666d9` |
| t3 burst + patterns | `BurstClock` (`global/enemy_ai/burst_clock.gd`); `rng`, `aim_point`, `spread_angle` on the aimed and Gatling patterns; `EnemyMover.sprite_forward_angle_of()` as the one reader (the Swarm and Razor brains' `_facing()` migrated to it); nose-correct forward fire and `EnemyPathMover` facing | `38b0d7b` |
| t4 convergence field | `SquadController.convergence_point` / `convergence_stage`, cleared with the LEAD | `5293ee7` |
| t5 W formation | `WFormation` + `WaveBuilder.w_formation()`; `test_wave_builder_formations.gd` | `b300594` |

### Renames (t6, t7)

`light_assault_ship/` → `fighter/` (`Fighter`, `FighterConfig` kept) and `interceptor/` → `gatling_interceptor/`
(`GatlingInterceptor`, `GatlingInterceptorConfig`), by `git mv` so the `.uid` sidecars moved with them; every gate roster, the
station's reinforcement table, level 1, `WaveBuilder.GATLING_INTERCEPTOR` / `gatling_interceptor()` updated; no behaviour
change (the t1 pin stayed green). t6 also added `tests/helpers/ai_state_machine_fixture.tscn`, which keeps the
`EnemyPathMover` `"AIStateMachine"` name lookup pinned now that its only real subject is deleted. Commits `7f6dafe`/`8ed6e2f`
(t6), `9d12d6f` (t7).

### The Fighter (t8a, t8b, t9, t12, t14)

- **t8a** (`f8efc74`): `fighter.tscn` rebuilt as an AI scene (`Brain`, `EnemyMover` AUTO, `StateLight`, `AimedAttack` +
  `ForwardAttack`, `AimedPool` + `ForwardPool` as root children), `states/` and the `AIStateMachine` deleted, flat
  `FighterConfig` with the `rail_*` fields, the rail fallback in `on_suspended()`, the Assault `EngagementBudget` + DISENGAGE.
- **t8b** (`6711274`, task plan `cmulwkar000btqj2x1e58sfd4`): `FighterBrain`'s attack runs — the §2.4.1 geometry, **a new
  shared `DubinsPath`** for the lead-ins, RUN_IN as path following with a look-ahead, EXTEND, a TURN that first turns back onto
  the player, REPOSITION, the Assault clamps and bearing flips, and weapon selection by distance with hysteresis
  (AIMED 3–5 Pulse ≥ 385 px, FORWARD 5–7 Scatter < 325 px with the nose inside 12°), a 0.3 s yellow telegraph and `BurstClock`.
- **t9** (`34984b6`, `5c9e122`, `bd0450c`; task plan `cmulwkar300bxqj2xgtk6jyu3`, three revisions): `Fighter.squad`, roles →
  pass kinds (LEAD FRONTAL; FLANK_LEFT / FLANK_RIGHT on two lanes; REARs dry passes), the window open/close and answer-once
  rule, a latched pass, `flank_stagger` and brain-local give-way for separation, the REAR dry-pass slot.
- **t12** (`ada5d4a`, `b1a4a65`): hub idle (`IDLE`, `NOTICING`, `RETURNING`) via `AnchorIdle`, appended to both brains.
- **t14** (`cb97c8f`): `fighter.png`, 64×64, dark hull / pale-blue edge light / red stripe, in the unchanged single-frame
  `AnimatedSprite2D`; `sprite_forward_angle` derived after the 180° flip.

### The Gatling Interceptor (t10, t11, t12, t15)

- **t10** (`f753884`, task plan `cmulwkar600c1qj2xnqykqsvo`): `GatlingInterceptorBrain` — APPROACH, SWING_IN, SPIN_UP, STREAM,
  COOLDOWN, REPOSITION, DISENGAGE; the flank point `F = P̂ + right(h)·side·380`; routed swings; first-window and flip rules
  for sides; the SWING_IN budget rule and deferred DISENGAGE; the rail fallback; `StreamPool` (36).
- **t11** (`1edf1d6`): convergence fire in the same brain — the LEAD opens the window at SWING_IN, FLANKs answer once, ready =
  own spin-up elapsed, rendezvous capped by `sync_wait_max`, the window closes on the later COOLDOWN.
- **t15** (`0f794f0`): a redrawn `interceptor.png`, 64×64, wide wing pods and a three-barrel rotary cannon, in the unchanged
  `Sprite2D`.

### Open Space (t13)

`SectorHub._spawn_patrol()` (`ea934a4`) adds a fighter pair and a Gatling pair (`SHOOTER_SQUAD_SIZE` 2) on a 1500 px ring at
bearings 180° / 0°, each sharing a `SquadController` and a `patrol_anchor` set on the brains before `add_child`. The plan's
starting values were accepted unchanged by the generic clearance sweep: fighter **+232.8 px** (nearest
`LoreLogFortunaManifest`), Gatling **+88.7 px** (nearest `ShipBoostUpPickup`) over their perceive radius.

### Level 1 (t16, t17)

All 64 fighter / Gatling lines (62 fighters + the deep_space Gatling pair; 18 + 19 + 27 per section) lost `.move()`,
`.free_after()` and `shoot_*()`, with triggers, offsets, delays and formations unchanged and pinned. t16 (`b4069db`,
`bae74d0`) covers deep_space and planet_approach and adds the measured density gate; t17 (`9e8e893`) covers cloud_descent and
adds the per-entry deadline rows and `test_level1_fighter_exit.gd`. **No pre-approved lever was used.**

### Documentation (t18, this task)

Both `ENEMY.md` files (each answers the IDEAS §43 checklist, the Gatling's corrects the "always fires forward" claim),
`docs/enemy-roster.md` (Fighter and Gatling entries, `w_formation`, an *Enemy Rounds* section), `assault.md`, `global.md`,
`PROJECT.md`, `docs/BULLET_POOL.md`, the `CLAUDE.md` gate paragraph (eighteenth to twenty-first gates), `tests/README.md`, the
DECISIONS "as built" section and this dossier.

## How it was verified

`bash /agent/verify.sh` (import → headless boot → full GUT suite) is green; `scripts/check-test-leaks.sh` is clean (1322 tests in 118 scripts, 45058 asserts, all passing on 2026-10-07). The Phase 3 tests by name:

- **Rounds and burst plumbing:** `tests/integration/test_enemy_rounds.gd` (shape, `reset()`, Scatter dies by 450 px while the
  Pulse is alive at 1280 px, Heavy Shell fixture shooter, `pool_size_for` incl. a burst of 1);
  `test_enemy_bullet_lifetime.gd::test_every_round_clears_its_own_lifetime_at_its_slowest_fired_speed` and its boundary
  `test_a_synthetic_100px_per_s_round_fails_the_sweep`; `tests/unit/test_burst_clock.gd` (a single `advance(1.0)` returns
  exactly N); `test_attack_patterns_forward.gd` (both sprite conventions, `(−1, −1)` where the raw angles differ by 2π, a
  source sweep for the one reader); `test_squad_controller.gd` (convergence fields); `test_wave_builder_formations.gd`;
  `tests/unit/test_dubins_path.gd` (7 cases).
- **Fighter:** `test_fighter.gd` — scene (pools are root children, ≥ `pool_size_for` for AI **and** rail cadences), rail fallback
  from config fields, `aim_mode` ignored on an AI fighter, Assault DISENGAGE, pass geometry (closest approach `pass_offset` ±
  40 px for a holding player and against `P̂` for a moving one), the TURN radius within 15 %, RUN_IN never stalling, Assault
  clamps and flips, weapon-selection hysteresis, off-nose FORWARD skipped-not-spent, no mid-burst change, cadence within a
  tick, deferred DISENGAGE, the sprite's forward direction, hub idle. `test_fighter_squad.gd` — 17 cases through a real
  `WaveManager`: window open/close and answer-once, same-call reassignment, REAR promotion, full-cycle separation on V3 / W5
  (0 overlaps in 168 layouts), REARs fire 0 shots; mutation checks listed in the task plan.
- **Gatling:** `test_gatling_interceptor.gd` — the window rhythm, N ∈ [8, 12] with both ends seen over a seed sweep, side-on
  streams, the side rules and their boundaries, corridor-top routing, no SWING_IN without budget, deferred DISENGAGE within
  2.08 s, the pool (36), the rail stream. `test_gatling_convergence.gd` — CHARGING within a tick, same half-plane, ≥ 30° apart,
  overlapping STREAM intervals, every round with a finite `aim_point`, the later-COOLDOWN close, the bounded wait, a far
  FLANK skipping, LEAD death mid-window, a solo Gatling never converging. `test_enemy_dual_mode.gd` — both enemies in both
  harnesses.
- **Hub:** `test_sector_hub_patrol.gd` (per-group counts, the clearance sweep over all four groups, shared anchors, frame-0
  IDLE, a fighter Pulse and a Gatling round landing in `EnemyContainer`).
- **Level 1:** `test_level1_fighter_spawns.gd` (the 64-row pin; `test_a_fighter_line_given_move_again_fails_the_pin`;
  `test_migrated_sections_have_no_rail_left`; the count gates and `test_extra_formations_at_the_peak_break_the_count_gates`);
  `test_level1_fighter_fire_density.gd` (the **measured** shots/s gate, plus `test_peak_window_rate_rejects_a_dense_burst`);
  `test_engagement_deadline.gd` (per-entry fighter rows, `test_a_fighter_just_past_the_config_derived_limit_misses_the_timeout`,
  the Gatling boundary, `test_the_fighter_exit_term_bounds_a_real_fighters_disengage` over 404 starts);
  `test_level1_fighter_exit.gd` (a real `WaveManager` replay of cloud_descent).
- **Existing invariant gates** (contact damage, contact and hurtbox geometry, config isolation, single writer, signal arity,
  sprite transparency, UID integrity, project load integrity, collision-layer names) stayed green with their rosters renamed;
  the single-writer gate is why `DubinsPath`, `BurstClock` and the squad board only *plan* and all motion is a request.

**What the gate cannot tell you:** whether any of it *feels* right. No test renders a scene for a human; see Known gaps.

## Decisions and course changes

- **Plan Revision 1 was rejected (`CHANGES_REQUESTED`)** on six blockers — B1 (pass geometry flew ≈ 67 px from the player), B2
  (convergence mis-sequenced), B3 (Assault side rule vs REPOSITION flip), B4 (cloud_descent arithmetic), B5 (t2 vs t6/t7), B6
  (baselines computed from deleted data) — and ten should-fix points; Revision 2 answered each (`3-plan.md` §9), was approved
  in round 2, and its notes N1–N12 were applied. That the geometry fix turned out to need a *new shared class* (`DubinsPath`)
  is the clearest sign the first plan under-specified the pass.
- **Two tasks ended a run escalated with nothing built, and their findings changed the later plan:** t9 (round 1: separation
  could not be met by `flank_stagger`; 271 of 290 failing runs were fan-out from spawn slots; round 2: without ORCA the first
  window can be clean but REAR dry passes and the Assault budget are open) and t16 (the epic's analytic shots/s gate cannot pass
  with the pre-approved levers — an **owner decision, option A: measure it**). t17's own plan review then found the fighter's
  exit is a curved swing, not the Razor's straight line. Their prototype patches live in `docs/plans/cmulwkar…/prototype/`.
- **t9 was re-queued after round 2 without a recorded owner answer** and took the reviewer's reading — separation is asserted
  over a *full cycle* — which relaxes nothing. That is recorded as open in DECISIONS.
- **Per-task deviations from Revision 2** are indexed in DECISIONS (21 rows). The ones that change what a later phase will
  see: `AimedPool` 20 not 12; TURN turns back onto the player; `forward_range` 325; the Gatling's average window period ≈ 5.8 s
  not ≈ 2.8 s; "ready" means *spin-up elapsed*; the Gatling REAR rule is not built; the shots/s gate is measured; the exit term
  is a curved bound.

## Numbers

| Value | Chosen | Where it came from |
|---|---|---|
| Fighter HP / contact / score | 60 / 20 / 25 | legacy `fighter_config.tres` |
| Fighter `max_speed`, `acceleration`, `turn_rate` | 300, 700, 1.8 rad/s (radius ≈ 167 px) | judgement; pinned `turn_rate × max_speed ≤ acceleration` (the Ph2 rule) |
| Pass: `standoff_radius`, `pass_offset`, `flank_lane_gap`, `lookahead` | 480, 160, 100, 220 px | judgement from Reynolds' offset pursuit (R ≈ 2.5 hull radii) |
| Fighter weapons | AIMED 3–5 × 0.10 s, Pulse 300 px/s, 8 dmg, `accuracy` 0.7; FORWARD 5–7 × 0.05 s, Scatter 420 px/s, 6 dmg; telegraph 0.3 s; `min_burst_period` 1.2 s | the owner's burst sizes (IDEAS §5.3); the rest judgement |
| `fire_range` / `forward_range` / hysteresis / `nose_cone_deg` | 520 / 325 / 60 / 12° | judgement; 325 was 300 until t8b measured the TURN snapshot at 220–305 px |
| Fighter Assault budget | `engage_seconds` 6.0, `passes` 2, `exit_speed` 520 | judgement; lever 4.5 left unused |
| Pools | AimedPool 20, ForwardPool 8, StreamPool 36 | `pool_size_for`: `max_burst × ceil(round_lifetime / min_burst_period)`, larger of AI and rail |
| Rounds | Pulse 300 / 8 dmg / 8 s / 1400 px; Scatter 420 / 6 / 2 s / 450; Gatling Stream 240 / 4 / 8 s / 1400; Heavy Shell 160 / 20 / 12 s / 1800 | judgement; the 150 px/s floor from the lifetime derivation |
| Gatling HP / contact / score | 70 / 20 / 75 | legacy |
| Gatling `max_speed`, `acceleration`, `braking`, `preferred_range` | 260, 600, 900, 380 px | judgement; range sits outside the fighter's pass radius |
| Gatling window | SWING_IN ≤ 1.5 s, spin-up 0.25 s, 8–12 × 0.09 s, cooldown 0.4 s, REPOSITION 1.0–1.5 s (+ reach rule, cap 5 s) | the owner's 0.25 / 8–12 / 0.4 (IDEAS §5.4); the reach rule is t10's deviation |
| Gatling rhythm | average ≈ 5.8 s per window (≈ 1.7 shots/s); minimum 2.28 s | measured in t10 |
| Convergence | bearing offset 40°, aim error ±3°, join range 1.5 × `preferred_range`, `sync_wait_max` 0.75 s | judgement from research findings 4–5 |
| Hub | ring 1500 px, bearings 180° / 0°, perceive 540 / 560, lose 900, notice 0.35 s, idle 150 px | plan's starting values, accepted unchanged by the clearance sweep; clearance +232.8 / +88.7 px |
| Level-1 gates | all-alive ≤ 2.0×, attack-capable ≤ 1.5×, shots/s ≤ 1.25× the frozen legacy peaks | the plan's levers table; shots/s measured: 9.0 / 6.5 / 8.5 against limits 39.1 / 41.7 / 18.75 |
| cloud_descent deadline | fighter exit term 5.37 s; worst entry 9.47 s of 10 s; real replay empty at 9.07 s | measured on the real `fighter.tscn` |

## Known gaps

Honest list. The first four are things only a person at a controller can answer.

1. **Does level 1's density *feel* right?** The gates say fighters and Gatlings fire far *less* than the rails did (peak 9.0 /
   6.5 / 8.5 shots/s against legacy 31 / 33 / 15) and that nothing clears worse than 1.5× / 2.0× in counts — but fighters now
   linger for their whole 6 s budget plus a curved exit instead of a rail's on-screen time, and an Assault fighter fires about
   **one burst per life**. Whether that is more or less threatening than before is a playtest question. The run measured one
   scenario: a **stationary** player. A moving player was not measured.
2. **Readability at speed.** The yellow telegraph, the red ARMED light and the round colours were checked by eye on single
   frames, never at Assault's scroll speed over a busy starfield. The `StateLight` is the only telegraph (no SFX, muzzle
   flash or spin-up particles — Ph17).
3. **Open Space feel.** Idle drift, noticing and drifting home were asserted by distances and phases, not watched. In Open Space a
   *moving* player (cruising at 200 px/s) gets a **breach-shaped pass about every 15 s** rather than a clean run every ≈ 10 s,
   and from abeam or behind the first pass comes from APPROACH's deadline at 5–11 s. Whether the hub patrols stay quiet while
   the player dwells at a mission trigger or the pickup bench is untested (the Gatling's clearance margin is only +88.7 px).
4. **Assault never fires FORWARD, and rarely shows a Gatling's second side.** At `engage_seconds` 6.0 a fighter flies exactly one
   lateral pass with one AIMED burst and leaves during EXTEND; a Gatling at 7.0 usually gets one window. The "weapon switches
   by distance" and "attacks from the other side" behaviours exist, are tested with long budgets, and are mostly seen in Open
   Space.
5. **Squad separation is incomplete (measured, not gated):** after a death `_reassign()` can swap two members' stations or leave a
   mid-pass squad with a new LEAD whose turn meets a flank's (up to 9 of 42 W5 layouts, worst 7.3 px); a V6 fails 1 of 42; spawn
   fan-out from 80 px slots overlaps in 19 of 168 layouts; the shipped level-1 formations come within 50–54 px against a 57.2 px
   hull diameter. In Assault, 7 of 84 dense layouts leave a late flank that holds and leaves without firing. Fighter bodies
   collide with each other (layer 1 / mask 1).
6. **Open owner decisions (unrecorded answers):** the Assault budget (6.0 s vs a longer budget that is not separation-safe vs
   4.5 s that silences most squads); fighter body collision; and `DroneConcurrency.ai_shooter_kinds()`'s straight-line fighter
   exit (9.64 s), which understates the curved ≈ 12.2 s and puts deep_space's all-alive peak at **21 against a limit of 20** when
   measured with the curved bound (18 with the measured 11.67 s life). The Ph2 Swarm/Razor deadline rows assume the same
   straight exit.
7. **Not built:** the §2.6.1 Gatling REAR rule (a third Gatling in a squad fires solo windows); `Steering.lead_target`; the
   Heavy Shell has **no consumer** (fixture-tested only).
8. **Found and left:** `WaveManager` triggers waves strictly in list order, so in deep_space the 2.0 s V5-fighter wave and the
   3.0 s drone wave trigger at **3.5 s** in the game (triggers are pinned, so not touched); `light_assault_ship.png` is now an
   unreferenced asset; `EnemyPathMover`'s `"AIStateMachine"` lookup has no subject (kept for Ph15); a leaving or dying
   shooter's in-flight rounds vanish with it (legacy; Ph5).
9. **Docs gap:** `docs/enemy-rework/current-enemies.md` and `assault/DEVELOPMENT_PLAN.md` are historical snapshots that still name
   the Light Assault Ship and the Interceptor by their old folders; they were left as the record of "before".

## Links

- Epic id `cmufs7ekv000lnm2x7nbswijy`; idea `cmufkkgmx0001o02y6bnf52bq` (`docs/ideas/cmufkkgmx0001o02y6bnf52bq/`).
- Plan directory `docs/plans/cmufs7ekv000lnm2x7nbswijy/` (`1-context.md`, `2-research.md`, `3-plan.md`, `4-review.md`, `tasks.json`).
- Task plans: t8b `docs/plans/cmulwkar000btqj2x1e58sfd4/`, t9 `docs/plans/cmulwkar300bxqj2xgtk6jyu3/` (with `prototype/`),
  t10 `docs/plans/cmulwkar600c1qj2xnqykqsvo/`, t16 `docs/plans/cmulwkarm00cpqj2xfwq3ue8h/` (with `prototype/`),
  t17 `docs/plans/cmulwkarp00ctqj2x6ih09c0k/`.
- Phase 1 as built `docs/epics-done/cmufklb100001p92xs1ey2fb1/REPORT.md`; Phase 2 `docs/epics-done/cmufs7ek60001nm2x6d0bt2et/REPORT.md`.
- Key commits: `628557e` (pin), `51666d9` (rounds), `38b0d7b` (bursts), `f8efc74` (fighter shell), `6711274` (attack runs),
  `bd0450c` (squads), `f753884` (Gatling windows), `1edf1d6` (convergence), `cb97c8f` / `0f794f0` (art), `ea934a4` (hub),
  `bae74d0` (level 1 deep_space + planet_approach), `9e8e893` (cloud_descent).
