# Review round 1

VERDICT: APPROVED

The plan matches the epic (§2.9.2, §2.9.4, review N4 as restated by t17) and the code it relies on. I checked its
claims against the source rather than taking them on trust. I also ran a throwaway copy of the proposed probe from
`/tmp` (not in the repo) against the real scenes in `HARNESS.assault()`, using the plan's 404-start grid and stepping
`_physics_process(DT)` by hand. Results:

| Kind | Slowest measured exit | Where | Wall time, 404 runs |
|---|---|---|---|
| sniper | 5.383 s | centre, heading right, 2 px/s | 0.85 s |
| bomber | 7.983 s | centre, heading right, 2 px/s | 1.58 s |
| ram (curved) | 6.350 s | (−280, 320), heading up, 2 px/s | 0.61 s |

Lifetimes from those exits and the config terms:
- sniper: 9 + 1.3 + 0.5 + 5.383 = 16.18 s;
- bomber: 8 + 360/170 + 0.25 + 7.983 = 18.35 s;
- ram: 4.5 + 0.65 + 1.45 + max(2274/500, 6.35) = 12.95 s.

With those, the count gate gives deep_space **6 ≤ 12.5** and planet_approach **6 ≤ 7.5** (peak at 65.7 s), so no lever
should be needed. The extra-ram-triple boundary gives **9 > 7.5**, so it can fail. Total probe cost is about 3 s
memoized, inside the plan's 5 s threshold.

## What I verified (no finding)

- **Rows.** `level_1_director.gd:277-286, 341, 361-362, 385, 407, 453-454, 479-480` hold the 11 deep_space
  specialist lines. `:610, 615, 634-636, 641, 668-669, 694-695, 700, 715-717, 738-739, 761-763, 768-769, 784,
  792-793` hold the 24 planet_approach lines. That is 35 in total, matching the plan's count and
  `test_level1_specialist_spawns.gd:173-174`.
- **No-rail check.** `.move()`, `.free_after()` and `.shoot_at_player()` map to `movement`,
  `exit_mode = FREE_ON_DURATION` and `initial_props["aim_mode"]` (`wave_builder.gd:30-64, 219, 226`). So the check
  copied from `test_level1_fighter_spawns.gd:475-491` is the right shape. `WaveManager` attaches `EnemyPathMover`
  only for a real `MovementResource` (`wave_manager.gd:220`), so a stripped line runs its AI.
- **Deferral terms are upper bounds** (up to tick rounding, see N3).
  - **Sniper.** `_request_disengage` (`sniper_brain.gd:265-271`) defers only in AIM/LOCK, and `_after_shot`
    (`:579-584`) leaves after the shot or the refusal, so the deferral is at most `aim_seconds + lock_seconds`. DECOY
    leaves at once.
  - **Bomber.** It defers only in RUN (`bomber_brain.gd:269-273`). RUN is stall-capped at
    `line_length / run_speed + RUN_STALL_SLACK` (`:765-766`), and `line_length ≤ run_length` (`_build_line`
    `length := config.run_length`, `_set_line` only clips). An expiry during ESCAPE goes straight to DISENGAGE, and in
    Assault ESCAPE leads only to DISENGAGE (`:825-830`), so no run or stall chain can stretch it.
  - **Ram.** It defers in WIND_UP / CHARGE / STAGGER (`ram_corvette_brain.gd:271-278`):
    - an expiry in WIND_UP gives at most 0.65 + 1.45 s, then the straight exit;
    - a plate break in WIND_UP after the expiry gives a single 0.4 s STAGGER, then DISENGAGE (`:510-513`), which is
      1.05 s plus the curved exit;
    - STAGGER cannot chain once `disengage_pending` is set.

    So `wind_up + charge_max_time + max(straight, curved)` covers every path.
- **Probe start speeds.** The sniper and bomber movers are capped at `max_speed` by `limit_length`
  (`enemy_mover.gd:191-192`; `bomber.gd` `_apply_config`). The ram's fastest is the boost, 700 when exposed, which
  WIDE_TURN inherits. The `_straight_exit` flag is false on a fresh instance, so the probe measures the curved
  branch.
- **Manual stepping.** `BaseEnemy._physics_process` (`base_enemy.gd:103-108`) is `brain.tick` followed by
  `mover.step`, which calls `move_and_slide()`; the probe then overwrites the position, as Ph3's does. The harness
  player stub has no shape. All three brains build their budget in `enter_phase → _start()`, and in Assault none of
  them enters IDLE. The `start_engaged` flag the Ph3 probe sets is therefore unnecessary here, as the plan implies.
  Budget expiry inside DISENGAGE is a no-op for all three (`sniper_brain.gd:266`, `bomber_brain.gd:159`,
  `ram_corvette_brain.gd:273`).
- **Ram straight bound.** It is reached along a constant `charge_dir` from inside the 1608 × 1608 rect, so the
  distance is at most the 2274 px diagonal. The only way to start below `exit_speed` along `charge_dir` is a boost
  filtered at the corridor edge, and that leaves the ram about 64 px from the world-rect edge. The measured curved
  bound (6.35 s) dominates in any case.
- **Other dependents of these rails.**
  - Filtered to their own kinds: `test_level1_fighter_fire_density.gd:139-140`, `test_level1_fighter_exit.gd:109`,
    `test_level1_drone_exit.gd:126`.
  - Never spawns, because its runner has no camera (`wave_manager.gd:174`): `test_level_1_sequence.gd`.
  - Calls one method only: `test_spawn_camera_pan.gd`.
  - Build their own rail-free waves: the attack rows (`test_sniper.gd:1083`, `test_bomber.gd:793`,
    `test_ram_corvette.gd:1378`).
  - `level_2_waves.gd` has only two live specialist lines, both on rails (`:21, :26`).
  - No test pins the lever-able config values.
- **Lever order and lever 4's floor** match the epic and N4 / t17 (`can_attack()`, `ram_corvette_brain.gd:249-250`,
  `ATTACK_GATE_MARGIN` 0.05).

## Findings

### N1. NON-BLOCKING: the "effective trigger" is stated but not wired, and the triple boundary depends on where the wave is inserted

- **Where:** §3 / §4; `level1_drone_concurrency.gd::spawn_intervals`; `test_level1_specialist_spawns.gd:285`.
- **Problem 1:** §3 says each spawn moment is the running-max trigger. §4 reuses `DroneConcurrency`, whose
  `spawn_intervals()` uses the raw `wave.trigger_time`. For these two sections the two are identical (deep_space's only
  out-of-order waves, 3.5 → 2.0 / 3.0, contain no specialist; planet_approach is monotonic). So either build the
  running max or assert `effective == raw` for every specialist wave.
- **Problem 2:** if the running max *is* built, the triple boundary must **insert** its wave in list order, as
  `test_engagement_deadline.gd`'s gatling boundary does with its "sanity: the inserted wave sits in list order"
  assertion. It must not `append()` it, as the current `test_extra_rams_at_the_peak_break_the_frozen_constant:285`
  does. An appended 65.7 s wave would take an effective trigger of 106 s. It still fails there (8 > 7.5 by my
  numbers), but for the wrong reason.
- **Also:** `peak_interval_count()` does not return the moment of the peak; that needs a small variant.
- **Suggested addition:** a sanity assertion that `peak + 3 > limit` before the boundary is trusted.

### N2. NON-BLOCKING: lever 1 may lengthen the ram's binding exit term (§5)

- **What I measured:** the ram's measured curved bound (6.35 s) is the binding exit term, not the straight 4.55 s
  (`2274 / 500`). DISENGAGE turns at `min(max_turn_rate, acceleration / exit_speed)` (`ram_corvette_brain.gd:579-581`).
  Raising `exit_speed` to 600 lowers that rate from 1.0 to 0.83 rad/s and widens the turn.
- **Effect:** "shortens the exit" is not guaranteed. The plan's own estimate ("ram ≈ 4.5 + 2.1 + 4.55", "the measured
  exits will be lower than those analytic curves") is wrong for the ram. The gate still passes (see the table above).
- **Fix:** if a lever is ever applied, keep it only if the re-measured peak actually drops.

### N3. NON-BLOCKING: tick rounding in the deferral terms and the two-speed probe

- **Deferral terms:** the sniper's AIM/LOCK checks (`sniper_brain.gd:531, 548`) and the bomber's stall check
  (`bomber_brain.gd:766`) have no `TIME_EPS`. The real deferral can therefore be one or two 1/60 s ticks above
  `aim + lock` or above the stall cap.
- **Speed sweep:** I swept 12 start speeds. Within the reachable range the two-speed probe misses the worst case by at
  most one tick (sniper 5.400 s at 10 px/s against 5.383 s at 2 px/s; bomber and ram exact).
- **Why it does not matter now:** the planet_approach gate has a whole-ship margin (6 against a limit of 7).
- **Suggestion:** add one `DT` per term, or a third speed of about 10 px/s, and record the residual in the decision.

### N4. NON-BLOCKING: wrong count in the Problem section

The Problem section says "the 26 snipers, rams and bombers that spawn there". The real figure is **35**: 17 snipers,
16 rams, 2 bombers. 26 is the level-wide sniper count.

### N5. NON-BLOCKING: stale comments for the docs step

- `bomber.gd:21` says "`.move()` is only needed until level 1 leaves its rails". After this task every level-1 bomber
  is off rails.
- The `level_1_director.gd` header (`:11-16`) describes only the drone lines' migration.
- Both belong in step 5 next to the `ENEMY.md` notes.

### N6. NON-BLOCKING (observation, no action): leftovers spill into the next section

Late spawns now live past their own section's end:
- deep_space's 29.0 s snipers live about 16 s into asteroid_belt;
- planet_approach's 98 s bomber and 102.3 s rams live about 5–8 s into cloud_descent.

The legacy rails had the same spill, and the frozen per-section constants were computed the same way, so the gate is
consistent. cloud_descent's ENEMIES_CLEARED wait is about 76 s away, so it is unaffected. Worth one line in the t21
DECISIONS entry.
