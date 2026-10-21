# Context — t14: the Fighter waits behind a wreck before its pass

Epic `cmug23om70001m52wqfwclf3l` (enemy rework phase 6), plan §2.12; epic review items N2, N3 and N8 are addressed to
this task's own plan (`docs/plans/cmug23om70001m52wqfwclf3l/4-review.md`).

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/fighter/fighter_brain.gd` (1,650 lines) | `FighterBrain`: `enum Phase { APPROACH, RUN_IN, EXTEND, TURN, REPOSITION, DISENGAGE, IDLE, NOTICING, RETURNING }`, `tick()` dispatch, `enter_phase()` (the one place a transition happens, emits `phase_changed`), pass geometry (`_derive_pass`), squad hold, weapons, DISENGAGE | COVER is a new phase here. APPROACH is entered at spawn (the default `phase`, never through `enter_phase`), from NOTICING (`_tick_anchor_idle`, COMBAT) and through the test seam. REPOSITION never hands to APPROACH (it goes to RUN_IN or a breach). |
| `assault/scenes/enemies/fighter/fighter_config.gd` / `.tres` | Flat `FighterConfig`; `engage_seconds` 6.0, `max_speed` 300, `braking` 700, `standoff_radius` 480, `perceive_radius` 540, `lose_radius` 900, `flank_wait_max` 2.0, `lead_wait_max` 3.5; Hazards group `hazard_avoidance` 0.8, `hazard_margin` 60 | New cover fields go in a new `@export_group("Cover")`. |
| `assault/scenes/enemies/fighter/ENEMY.md` | The fighter's behaviour doc, phase list | Gains COVER. |
| `global/hazards/hazard_info.gd` | `HazardInfo`: `kind`, `radius`, `line_of_sight_blocker`, `source`, `contains()`, `try_claim()` / `release()` / `is_claimed_by()` / `is_claimed()` (claim by instance id) | The cover claim. |
| `global/hazards/hazards.gd` | Static registry: `count()` (O(1)), `around(pos, reach)` (allocates) | The cover search, gated on `count() > 0`. |
| `assault/scenes/hazards/wreck/wreck.gd` | `Wreck`: `hazard_info()` refreshes `position`; `radius` = body radius (small 13, medium 25, large 40; structures 28/45/55); `retire()` unregisters and clears the claim; `is_retiring()` | The "wreck freed or retiring" exit. |
| `global/enemy_ai/enemy_mover.gd` | `arrive()`, `face_toward()`, `own_velocity()`; `_avoid()` drops a LOS blocker claimed by its own actor | COVER requests through these only (single-writer gate). |
| `global/enemy_ai/enemy_brain.gd` | `EnemyBrain.can_see_player()` (t13): a `TargetInfo.line_of_sight` ray from the actor, excluding its own RID | The hold condition. Physics-step only: fine from `tick()`. |
| `global/enemy_ai/engagement_budget.gd` | `update(delta)` runs before the phase dispatch; `remaining()` is INF in Open Space | N2: on APPROACH's first tick `remaining()` is already `6.0 − 1/60`. |
| `global/enemy_ai/squad_controller.gd` | Roles LEAD / FLANK_LEFT / FLANK_RIGHT / REAR / NONE | Only a solo fighter or a LEAD may take cover. |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = the visible rect grown by the camera's pan limits; before `_entered` it discards outward motion | A cover point outside the corridor is unreachable in Assault. |
| `tests/integration/test_fighter.gd` (1,428 lines) | Fighter intent spec; `_harness(mode)`, `_spawn()`, `_tick()` (hand-tick: `_physics_process` then overwrite position with `before + velocity·DT`), `_simulate()` log | Extended with the COVER rows. |
| `tests/integration/test_level1_fighter_exit.gd` | `test_cloud_descent_clears_in_time_with_wrecks_left_behind`: a `HazardContainer`, every ship leaves a wreck, every fighter dies on its first EXTEND | The one level-1 gate where fighters will meet wrecks: COVER can now trigger in it. |
| `tests/integration/test_fighter_squad.gd` | The 168-layout squad sweep (no hazards) | Must stay green unchanged. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `SniperBrain._cover_candidates()` / `_inside_other_hazard()` (`assault/scenes/enemies/sniper/sniper_brain.gd:587-638`) | The far-side cover point `W + (W − P)^ · (radius + gap)`, the "outside every other hazard's `radius + hazard_margin`" filter, and skipping a wreck another ship holds. |
| `SniperBrain._update_cover_claim()` / `_release_cover()` | The claim pattern: hold a `HazardInfo` reference, `try_claim(actor)`, release on exits; a freed claimer frees the claim by instance id. |
| `tests/integration/test_sniper.gd:1450-1745` | Cover test helpers: a real `wreck_medium.tscn` held still (`set_physics_process(false)`), `await wait_physics_frames(2)` before a ray can see it, and the live-physics (8× clock) row with `after_each` restoring the clock. |
| `tests/helpers/fixture_wreck.gd` | A body-less, claimable LOS-blocker `HazardInfo` for rows that need no ray. |
| `tests/helpers/enemy_ai_harness.gd` | Both harnesses (Open Space: no constraint; Assault: `ArenaCamera` → corridor + budget). |
| `FighterBrain._corridor()`, `_hull_radius`, `_in_squad()`, `_role()`, `budget` | Mode, role and corridor queries the entry conditions need. |

## Conventions that constrain this

- **Single writer:** the brain only calls `mover.arrive()` / `face_toward()`; never writes `actor.velocity` / `rotation`
  (`test_enemy_mover_single_writer.gd`).
- **Determinism:** no `Timer`, clocks are accumulated `delta`; COVER draws no rng; with `Hazards.count() == 0` nothing new
  runs (one compare), so every no-hazard gate is bit-identical.
- **Config:** new fields are flat (`test_config_instance_isolation.gd`), set in the `.tres`, never written on the shared
  preload in tests.
- **Enum values never move:** COVER is appended after RETURNING (= 9).
- **Squad hold machinery, `_derive_pass()` and the RUN_IN latch are not touched** (task statement).
- **Tests:** dual-mode via `use_parameters(["open_space", "assault"])`, harness built in the body; hazards added with the
  harness root (autofreed); a real wreck needs two physics frames before a ray sees it; anything that awaits must pass
  `scripts/check-test-leaks.sh`.
- **Gate time:** allowance +3 s; GUT ≤ 240 s.
- **Docs:** the fighter's `ENEMY.md` phase list; a deviation later phases depend on goes into the Phase 6 section of
  `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`.
