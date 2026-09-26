# Enemy rework, phase 1 — completion report

Epic `cmufklb100001p92xs1ey2fb1`. Plan directory: `docs/plans/cmufklb100001p92xs1ey2fb1/`
(`1-context.md`, `2-research.md`, `3-plan.md` revision 2, `4-review.md` — two rounds). The one
escalated task under this epic, `t10-brain-mover`, has its own directory:
`docs/plans/cmug33ldn00d3m52wfe1j6fct/`. The idea's running decision log is
`docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`, whose "Phase 1 - as built" section (appended
by this dossier's own task) is the fast-reference summary for later phases.

## What was built

Per build-sequence task (`3-plan.md` §3):

1. **t1-pin-base-enemy** — `tests/integration/test_base_enemy.gd`: characterizes `BaseEnemy` over
   the live roster (post-`_ready()` hurtbox mask, the ram ship's 33→97 flip, damage → flash → death,
   `died` then free, scoring-field propagation, the `AnimatedSprite2D` 180° flip) before any
   refactor landed, using a directory-sweep roster (`<dir>/<dir>.tscn` with a `BaseEnemy` root) plus
   the station turret as an explicit extra case.
2. **t2-pin-path-mover** — `tests/integration/test_enemy_path_mover.gd` (name approximate; see the
   test tree): characterizes `EnemyPathMover` (sample × `WORLD_SCALE`, physics/AI suspension, both
   exit modes, off-screen cull, no-camera warning, nose-down facing), plus a case on the real
   `light_assault_ship.tscn` proving `AIStateMachine.process_mode == DISABLED` after attachment.
3. **t3-pin-drones** — characterizes `PatrolDrone` (drift, mask 64 rocket immunity, body layer 256)
   and the pre-port Drone Interceptor (ENTER→ORBIT, dash direction/speed, contact kill), with
   seed-robust timing assertions so the pins survive the RNG later moving to `brain.rng`.
4. **t4-layers** — `global/physics/collision_layers.gd` (`CollisionLayers`), naming layers 3
   (fixing the `environemnt_player` typo to `environment_player`), 5 (`pickups`), 6
   (`player_rockets`) and 11 (`hazard_contact`) in `project.godot`, with no numeric value changed;
   `tests/integration/test_collision_layer_names.gd`.
5. **t4b-arena-provider** — `ArenaCamera` joins group `&"assault_arena"` (before its early return,
   per N5) and answers `projectile_world_rect()` / `enemy_cull_rect()`; `global/enemy_ai/
   enemy_world.gd` (`EnemyWorld`) as the sole duck-typed lookup of that group.
6. **t5-defense-profile** — `global/components/defense_profile.gd` (`DefenseProfile`, a `Node`);
   `BaseEnemy` resolves a scene-authored one or creates a default (mask 1121); the ram ship and
   station turret moved onto `CollisionLayers` constants. Every t1 pin stayed green unchanged.
7. **t6-base-enemy-debt** — the death `print` moved behind `OS.is_stdout_verbose()`;
   `sprite_forward_angle` export (default `PI/2`, nose-down); `_on_received_damage`/
   `_on_health_changed` documented as virtual hooks; `ShipConfig` `@export_group`s for Defense/
   Scoring.
8. **t7-target-info** — `global/enemy_ai/target_info.gd` (`TargetInfo`), with `tests/unit/
   test_target_info.gd`.
9. **t8-attack-controller** — `AttackController` extended (`enabled`, `driven_by_brain`,
   `fire_now()`); `accuracy` added to `aimed_attack_pattern.gd` and `gatling_attack_pattern.gd`,
   defaulted to `0.0` everywhere shipped.
10. **t9-steering** — `global/enemy_ai/steering.gd` (`Steering`): seek, arrive, orbit, intercept,
    evade, retreat_from, strafe, hold_position, drift — pure functions, unit-tested individually.
11. **t10-brain-mover** *(escalated, own plan/review)* — `EnemyBrain`, `EnemyMover` (with
    `braking` and `max_turn_rate`), `MovementConstraint` (identity), the `BaseEnemy._physics_process`
    tick loop, `suspend_ai()`, `EnemyPathMover`'s additional duck-typed suspension call (the name
    lookup stays unconditional), a fixture enemy (`tests/helpers/fixture_enemy.tscn`), and
    `tests/integration/test_enemy_mover_single_writer.gd`.
12. **t11-corridor** — `assault/scenes/systems/assault_corridor_constraint.gd`
    (`AssaultCorridorConstraint`, the full soft/hard-band spec) and
    `ArenaCamera.enemy_movement_constraint()`.
13. **t12-dual-harness** — `tests/helpers/enemy_ai_harness.gd` (`open_space()`/`assault()`
    builders) and the fixture behaviour spec run in both, `tests/integration/test_enemy_dual_mode.gd`.
14. **t13-projectile-lifetime** — `global/components/projectile_lifetime.gd` (`ProjectileLifetime`,
    lazy-arming); `EnemyBullet` migrated off its hardcoded arena-bounds constants; the sniper's
    unpooled shot given its own instance; `tests/integration/test_enemy_bullet_lifetime.gd`.
15. **t14-port-interceptor** — the Drone Interceptor ported onto `DroneInterceptorBrain` +
    `EnemyMover` (`constraint_mode = NONE`), its ENTER/ORBIT/DASH kept 1:1 in Assault and now
    functional in Open Space via `dash_max_distance`; behaviour spec added to the dual-mode harness.
16. **t15-docs** *(this task)* — module docs (`global.md`, `assault.md`), `PROJECT.md`
    conventions, `CLAUDE.md`'s test-gate paragraph, `drone_interceptor/ENEMY.md` (verified current),
    the repo-wide `base_enemy.gd:<line>` citation sweep, this dossier, and the idea's "Phase 1 - as
    built" section.

Every task's commit is on `agent/auto-dev`; see `git log` for exact SHAs (this dossier does not
duplicate the commit list — the branch history is authoritative and the task list above is the
join key into it).

## How it was verified

- `bash /agent/verify.sh` (import, headless boot, full GUT suite) was green after every task,
  including this one.
- New unit coverage: `test_enemy_mover.gd`, `test_target_info.gd`, `test_projectile_lifetime.gd`,
  `test_assault_corridor_constraint.gd`, plus `Steering`'s per-primitive unit tests.
- New integration coverage: `test_base_enemy.gd`, `test_collision_layer_names.gd`,
  `test_enemy_brain_contract.gd`, `test_enemy_mover_single_writer.gd`, `test_enemy_dual_mode.gd`,
  `test_enemy_bullet_lifetime.gd`, `test_attack_controller.gd` (extended), plus the `EnemyPathMover`
  and Drone Interceptor/PatrolDrone characterization tests from t2/t3.
- The pre-existing invariant gates all stayed green throughout: config isolation
  (`test_config_instance_isolation.gd`), contact-damage (`test_enemy_contact_damage.gd`),
  contact-hitbox and hurtbox geometry (`test_contact_hitbox_geometry.gd`,
  `test_enemy_hurtbox_geometry.gd`), player-bullet lifetime (`test_player_bullet_lifetime.gd`),
  signal arity (`test_signal_emit_arity.gd`), project load integrity
  (`test_project_load_integrity.gd`), and the space-station family
  (`test_space_station.gd` and siblings).
- What the gate **cannot** verify: this phase shipped no player-visible content beyond the Drone
  Interceptor now functioning in Open Space, and nobody has played that encounter by hand — see
  *Known gaps*.

## Decisions and course changes

- **Plan review, round 1 (`CHANGES_REQUESTED`).** Seven blocking findings (F1–F7) and four
  non-blocking ones (F8–F11) — see `4-review.md`. The revision fixed all eleven before
  implementation started: `ProjectileLifetime` arms lazily instead of only in `reset()` (F1); the
  `EnemyBullet` `max_time` derivation was corrected from a wrong minimum bullet speed to the
  actual slowest shipped source, 150 px/s, giving 18 s instead of the original (also wrong) 10 s
  (F2); `EnemyPathMover`'s three suspension steps became explicitly unconditional rather than a
  `has_method` fallback chain, closing a path that could have silently stopped suspending the
  light assault ship's `AIStateMachine` (F3); the Drone Interceptor's Phase 1 constraint mode was
  decided as `NONE` rather than `AUTO`, with the corridor's full band spec written out (F4); the
  task graph gained explicit dependencies to remove two same-file collisions between
  parallel-eligible tasks (F5); several factual errors about shipped test/code behaviour were
  corrected (F6); and the roadmap phase count was reconciled from 17 to 19 (F7, later 20 — see
  below).
- **Plan review, round 2 (`APPROVED`).** Seven further non-blocking notes (N1–N7), applied during
  implementation rather than triggering a third review round: the sniper shot's
  `ProjectileLifetime` could not literally "inherit" a node from a non-inherited scene, so it
  carries its own instance instead (N1); the single-writer sweep's naive form would have flagged
  `TargetInfo.velocity` and `BaseEnemy.suspend_ai()`'s own zeroing, so it was scoped to
  receiver-qualified writes plus the mover-driven root script and its ancestors (N2); the
  `base_enemy.gd:<line>` citation sweep was scoped to exclude historical plan/review records,
  finished-epic dossiers and the owner's own attached audit documents (N3, applied by this task —
  see below); the board grew to 20 phases before this round closed, reconciled without a new
  review round since no requirement moved out of scope, only Phase 20's late-system integration
  slot needed naming (N4); `ArenaCamera` was confirmed to join its provider group *before* its
  early return (N5); the rect-edge boundary and a one-frame dash-onset timing tolerance were
  written into the relevant tests rather than left implicit (N6, N7).
- **This task's own scoping decision (t15, N3's application).** The repo-wide
  `grep -rn "base_enemy.gd:[0-9]"` sweep was run against `assault/`, `global/`, `open_space/`,
  `tests/` and `docs/architecture/` only — excluding `docs/plans/`, `docs/epics-done/`,
  `docs/ideas/` and `docs/enemy-rework/`, which are historical records, finished dossiers and the
  owner's own attachments that this phase has no license to rewrite. Within that scope the actual
  hit list differed slightly from the plan's "known hits today": `station_turret.gd:31` had
  already been cleaned up by an earlier task, and two hits the plan missed
  (`station_reinforcements.gd:128`, `test_station_incoming_damage_paths.gd:17`) were found and
  fixed alongside the eight the plan named. All ten now cite the symbol
  (`BaseEnemy._on_health_changed`, `BaseEnemy.died`, `BaseEnemy.hurt_box`, or the `DefenseProfile`
  call that now owns the mask write) instead of a line number.
- **No plan was rejected outright.** Both review rounds ended in a path forward (`CHANGES_REQUESTED`
  then `APPROVED`), so there is no discarded design to record here beyond the alternatives each
  contract's research candidate table already rejected with reasons (see `2-research.md` §3, and
  `SOURCES.md`).

## Numbers

| Value | Where used | Origin |
|---|---|---|
| `1121` (`97 | 1024`) | Default `DefenseProfile` mask | Existing code — `BaseEnemy`'s pre-rework hardcoded mask, kept byte-identical. |
| `33` → `97` | Ram ship's armour-stripped mask flip | Existing code, moved onto `DefenseProfile.apply_alternate()` unchanged. |
| `max_time = 18 s`, `max_distance = 2400 px` | `EnemyBullet`'s `ProjectileLifetime` defaults | Derived: rect diagonal ≈2274 px over the slowest shipped enemy-bullet speed (150 px/s, `station_gunnery.gd`), `ceil(2274/150) + 2 = 18 s`; `ceil_to_100(2274 + 64 margin) = 2400 px`. Corrected during round-1 review (F2) from an initial, wrong 250 px/s assumption. |
| `entry_speed = 60`, `soft_band = 120`, `edge_pressure = 200` px/s | `AssaultCorridorConstraint` | Judgement (research found no numeric steering tuning in any source read) — sized against the existing player/enemy speed ranges. |
| `hard_band = 450` px | `AssaultCorridorConstraint` | From the owner's own idea document (IDEAS §34). |
| `dash_max_distance = 1600` px | Drone Interceptor's Open Space dash-end rule | Judgement — "a little more than a 1280 px screen width plus the orbit radius" — since Open Space has no screen-relative cull to reuse. |
| `accuracy = 0.0` | Every shipped aimed/gatling pattern | Chosen so this phase changes no enemy's aim; it is the difficulty-tier hook for Phase 16. |

## Known gaps

- **Nobody has played the Drone Interceptor's new Open Space behaviour by hand.** The gate proves
  the ported brain reproduces the pre-port Assault behaviour and that the same behaviour spec runs
  in an Open Space harness, but a harness is not a played encounter — whether hunting the player in
  the Open Space hub actually *feels* right (approach speed, orbit radius, dash telegraph) has not
  been eyeballed.
- **The corridor's band tuning (`entry_speed`/`soft_band`/`edge_pressure`) is unplayed judgement.**
  It has never been exercised by a real AI-driven enemy in Assault yet — the Drone Interceptor
  ships this phase with `constraint_mode = NONE` specifically to avoid depending on it. Phase 2 is
  the first phase that actually flies an enemy through it.
- **`AttackController`'s `accuracy` and `driven_by_brain` are wired but unused in anger.** No
  shipped enemy sets `accuracy` above `0.0` or `driven_by_brain = true` yet; both are exercised
  only by unit/contract tests, not by a real firing enemy.
- **The full 20-phase roadmap is a plan, not a commitment already reviewed phase-by-phase.** Only
  this phase went through research → plan → review. Phases 2–20 are scoped in `3-plan.md` §7/§8
  and the idea's `DECISIONS.md`, but each still needs its own preparation pass before
  implementation, per the epic's own process.
- **The `base_enemy.gd:<line>` sweep's scope (assault/global/open_space/tests/docs-architecture)
  is a judgement call (N3), not something the acceptance text spelled out character-for-character.**
  A literal, unscoped `grep -rn "base_enemy.gd:[0-9]"` still returns hits inside `docs/plans/`,
  `docs/epics-done/` and `docs/ideas/` — all historical records or owner-attached documents this
  phase does not rewrite. See *Decisions and course changes* above for the reasoning.

## Links

- Plan directory: `docs/plans/cmufklb100001p92xs1ey2fb1/` (`1-context.md`, `2-research.md`,
  `3-plan.md`, `4-review.md`).
- Escalated task plan directory: `docs/plans/cmug33ldn00d3m52wfe1j6fct/` (t10-brain-mover).
- Idea folder and decision log: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/` (`ENEMIES_OPEN_SPACE_REWORK_IDEAS.md`,
  `ENEMIES.md`, `DECISIONS.md` — see its "Phase 1 - as built" section).
- Epic id: `cmufklb100001p92xs1ey2fb1`. Phase 2's epic (Swarm Drone, Razor Drone and squad roles)
  is next in the chain.
