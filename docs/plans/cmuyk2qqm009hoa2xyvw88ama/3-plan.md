# t21 — level 1 deep_space and planet_approach: snipers, rams and bombers off rails

Revision 1. Epic plan §2.9.2 (with §2.9.4 and epic review N4); context in `1-context.md`.

## Problem

In level 1's first and third sections (deep_space, planet_approach) the snipers, rams and bombers that spawn there
still fly authored rails (35 of them: 17 snipers, 16 rams, 2 bombers; review N4): a sniper drops in, hovers through a fixed number of shots and slides out; a ram flies a
straight line down the screen; a bomber creeps down the middle dropping a bomb every 1.2 s. Their AI (relocation loop,
predicted-intercept charge, bombing runs on the predicted path) only runs in tests and the hub. After this task they
arrive at exactly the same moments and places, then fight with their own AI and leave when their engagement budget
is spent — and the section must not get more crowded than 2.5× the legacy peak.

## Design

### 1. Strip the rails (`level_1_director.gd`)

Every `b.sniper()` / `b.sniper_enemy()` / `b.ram()` / `b.bomber()` line in `_build_section_1()` and
`_build_section_2()` loses `.move(...)`, `.free_after(...)` and `.shoot_at_player()`. `.at()` and `.delay()` stay
byte-identical, so the t1 pin (trigger, offset, delay) stays green unchanged. No `.squad()` tags: these brains have
no squad logic, and `WaveManager` keys a loose line as a squad of one anyway. Wave comments that describe a rail
("fires 5 times, then retreats", the fly-in sequence) are rewritten to say where the ship enters. cloud_descent is
untouched (t22).

The config budgets replace the dropped `free_after` values (sniper 9.0 s, ram 4.5 s, bomber 8.0 s, all from the
shipped configs, unchanged unless a lever fires).

### 2. Measured exits (`tests/helpers/specialist_exit_probe.gd`, new)

A static helper (RefCounted, like `level1_drone_concurrency.gd`), so t22's deadline rows can reuse it:

```
static func worst_disengage(host: Node, scene: PackedScene, disengage_phase: int, speeds: Array[float],
		cap: float) -> Dictionary   # { "seconds": float, "start": String, "runs": int }
```

It builds one `HARNESS.assault()` world under `host` (player stub at view centre + (0, 300), the Ph3 placement), then
for each start of the Ph3 grid — x ∈ {−560, −280, 0, 280, 560} × y ∈ {−320, −160, 0, 160, 320} around the view centre,
× 8 headings (k·45°), plus the two named starts (centre heading right; 200 px below centre heading up) — and each speed,
instantiates the real scene, sets `brain.rng_seed = 1`, adds it under the harness root, disables its physics
processing, sets `velocity`, calls `brain.enter_phase(disengage_phase)` and steps `_physics_process(DT)` integrating
`global_position += velocity * DT` until `is_queued_for_deletion()` (or `cap`). It returns the slowest. This is
`test_engagement_deadline.gd::_disengage_seconds()` generalised over the scene (no real-time physics: cheap).
404 runs per kind.

Speeds (the fastest a ship can be moving when its curved DISENGAGE starts, and a near-standstill just above the
brains' `HEADING_MIN_SPEED` of 1.0, so `_heading()` is the velocity's):
- sniper: `max_speed` (320; covers `break_speed`, `relocate_speed`, `exit_speed`), 2.0;
- bomber: `max_speed` (240; covers `run_speed`, `escape_speed`), 2.0;
- ram (curved, non-charge exit): `exposed_charge_speed` (700 — a budget that expires early in WIDE_TURN finds it
  still slowing from a charge), 2.0. The ram's `_straight_exit` is false on a fresh instance, so `enter_phase` takes
  the curved branch.

All speeds read from the shipped config instance (`ship.config` after `_ready`), never typed.

### 3. Lifetimes (all terms from config fields or the probe)

| Kind | Lifetime after its spawn moment |
|---|---|
| Sniper | `engage_seconds + aim_seconds + lock_seconds + measured_exit(sniper)` — expiry in AIM / LOCK defers to the shot; DECOY (off in the shipped game) leaves at once |
| Bomber | `engage_seconds + run_length / run_speed + BomberBrain.RUN_STALL_SLACK + measured_exit(bomber)` — expiry in RUN defers to the run's end, which is stall-capped at `line_length / run_speed + RUN_STALL_SLACK` and `line_length ≤ run_length` |
| Ram | `engage_seconds + wind_up_seconds + charge_max_time + max(diagonal(projectile_world_rect) / exit_speed, measured_exit(ram))` — the straight-along-the-charge bound vs. the measured curved bound |

A spawn's moment is its wave's **effective** trigger (running max of `trigger_time` in list order — `WaveManager`
triggers strictly in order) plus `spawn_delay`. No specialist line uses a formation (asserted by the pin already).

### 4. The count gate (`test_level1_specialist_spawns.gd`)

`MIGRATED_SECTIONS = [&"deep_space", &"planet_approach"]`; `_RAIL_SECTIONS` shrinks to `[&"cloud_descent"]`.

- `test_migrated_sections_have_no_rail_left`: every specialist entry of a migrated section has `movement == null`,
  `exit_mode != FREE_ON_DURATION` and no `aim_mode` in `initial_props`; counted (35 rows).
- `test_migrated_sections_peak_alive_specialists_within_2_5x`: per migrated section, peak alive specialists (intervals
  from §3, `peak_interval_count`) ≤ `2.5 × _LEGACY_PEAK_SPECIALISTS[section]`. Prints each kind's lifetime with its
  terms, the measured exits next to the straight-line term they replace (for the record), and the peak vs limit.
- The probe runs once per file run (memoized), not once per test.

Boundaries:
- `test_a_specialist_line_given_move_again_fails_the_no_rail_check`: a fresh `_build_sections()` with one deep_space
  ram line given `StraightMovement.new()` → the no-rail helper reports exactly that row.
- `test_an_extra_ram_triple_at_the_peak_fails_the_count_gate`: a ram triple added as a new wave at planet_approach's
  peak moment (the start time at which the peak is reached) → the peak exceeds the limit.
- The existing `test_extra_rams_at_the_peak_break_the_frozen_constant` moves to cloud_descent (still on rails), so the
  live-equals-constant check keeps a boundary until t22 retires it.
- The "never vacuous" loop accepts a constant that is in `_RAIL_SECTIONS` **or** `MIGRATED_SECTIONS`.

The probe itself gets a sanity boundary: every measured exit is finite and below the probe's cap (a ship that never
leaves would otherwise read as `cap`), and each kind's measured exit is ≥ `exit_distance / exit_speed` (a probe that
measured nothing — e.g. freed on tick 0 — fails).

### 5. Levers (only if the gate fails, in order, each kept only while the attack-in-budget rows stay green)

1. ram `exit_speed` 500 → 600;
2. sniper `engage_seconds` 9.0 → 7.0;
3. bomber `engage_seconds` 8.0 → 6.5;
4. ram `engage_seconds` down to its floor: measured worst spawn-to-LINE_UP + `line_up_cap` + `ATTACK_GATE_MARGIN`
   (epic review N4, as restated by t17).

Still over → revert, end with `Result: ESCALATE`. Estimate with the analytic bounds (sniper ≈ 9 + 1.8 + ≤ 5.7,
ram ≈ 4.5 + 2.1 + 4.55, bomber ≈ 8 + 2.37 + ≤ 8.2): deep_space peak ≈ 6 vs limit 12.5; planet_approach ≈ 6–7 vs
7.5 [estimate]. The measured exits will be lower than those analytic curves, so no lever is expected. After any lever
the three attack-in-budget rows (`test_sniper.gd::test_every_level1_sniper_spawn_class_aims_inside_its_budget`,
`test_bomber.gd::test_a_level_1_bomber_attacks_inside_its_budget`,
`test_ram_corvette.gd::test_every_level1_ram_spawn_class_winds_up_inside_its_budget`) are re-run; they read the
shipped `.tres`.

## Build sequence

1. Tests first: no-rail check + its boundary, count gate + its boundary, `_RAIL_SECTIONS` shrink, the moved
   frozen-constant boundary, the probe helper. Run the file: the no-rail test fails (35 rails), the count gate runs.
2. Strip the 35 lines' rails in `level_1_director.gd`, rewrite the stale comments. File green.
3. If the count gate is red: levers in order (§5), re-running the three attack-in-budget rows after each.
4. Run the level-1 gates (`test_level1_*`, `test_engagement_deadline.gd`, `test_level_1_sequence.gd`), then the
   full gate and `scripts/check-test-leaks.sh`. Check the file's run time (the suite sits near the harness's
   ~300 s limit).
5. Docs: the per-entity `ENEMY.md` "level 1" notes, `docs/enemy-roster.md`, `assault.md` if they say level 1 flies
   these on rails; a t21 entry in `DECISIONS.md` (measured exits, lever outcome, the probe helper for t22).

## Test plan

In `tests/integration/test_level1_specialist_spawns.gd`:
- `test_migrated_sections_have_no_rail_left` (35 rows, counted).
- **`test_a_specialist_line_given_move_again_fails_the_no_rail_check`** (boundary).
- `test_measured_exits_are_real` — finite, under cap, ≥ the straight distance / exit_speed floor (sanity boundary).
- `test_migrated_sections_peak_alive_specialists_within_2_5x` (prints every term).
- **`test_an_extra_ram_triple_at_the_peak_fails_the_count_gate`** (boundary).
- `test_legacy_peak_specialists_match_frozen_constants` — now over cloud_descent only; never vacuous.
- **`test_extra_rams_at_the_peak_break_the_frozen_constant`** — retargeted to cloud_descent.
- Unchanged: the pin, its internal consistency, the alias row, the changed-delay and missing-row boundaries.

Regression: every existing level-1 drone / fighter gate, the three attack-in-budget rows, and the invariant gates.

## Risks

- **Suite time.** 3 × 404 probe runs of manual ticks. Mitigation: memoized once per file; if the file costs more
  than ~5 s, reduce the grid (keep the named starts and the 8 headings at the grid's centre column) and record it.
- **A measured max over a grid is not a proof of a bound.** Same standing as Ph3's probe; the grid includes the
  starts known to be slowest (centre heading away from its nearest edge). Printed for the record.
- **Levers change level 2 too** (`level_2_waves.gd` uses the same scenes): engage_seconds only matters off rails,
  and level 2's specialists are on rails, so a budget lever does not change level 2; a ram `exit_speed` lever only
  applies in DISENGAGE (AI). Noted, not tested.

## Out of scope

cloud_descent (t22, including its deadline rows and the replay); `level_2_waves.gd`; any behaviour change to the
three brains; trigger/offset/delay changes; doc closure of the epic (t23).

## Review round 1 (APPROVED) — notes applied

- **N1:** intervals are built in the test with the running-max effective trigger (not `spawn_intervals()`'s raw
  trigger), and the peak's moment is returned; the ram-triple boundary inserts its wave in list order (asserted) and
  sanity-checks `peak + 3 > limit` first.
- **N2:** a lever is kept only if the re-measured peak actually drops (lever 1 can lengthen the ram's curved exit).
- **N3:** the probe gets a third start speed, 10 px/s, and each deferral term gets one `DT` of tick rounding.
- **N4:** the Problem section's count fixed (35 rows).
- **N5:** `bomber.gd:21` and the `level_1_director.gd` header comments updated in the docs step.
- **N6:** the spill of late spawns into the next section is noted in the t21 DECISIONS entry.
