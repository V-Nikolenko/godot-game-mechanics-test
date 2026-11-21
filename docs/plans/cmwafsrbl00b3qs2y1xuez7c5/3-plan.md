# t12 — A Carrier crosses Planet Approach between two laser-column volleys

Task `cmwafsrbl00b3qs2y1xuez7c5`; epic plan `docs/plans/cmug23oo90029m52wae4clve0/3-plan.md` §2.13 (approved). Context: `1-context.md`.

## Problem

Level 1 has no Carrier. The player should meet one in Planet Approach: a slow armoured ship crossing the screen top to bottom as a moving
battlefield, opening its hangars to launch drones, firing its batteries, and gone before the section ends. It must never be cut apart by the
level's own laser columns (a column kills any part it touches: 9999 on layer 512), never crowd the section past the drone density gates,
and never sit in an ENEMIES_CLEARED section.

## Design

### 1. Placement: option A, as the epic plan orders it

`level_1_director.gd`, planet_approach's **65.0 s** wave gains `b.carrier().at(55, -260)` (appended after the ram; no new wave, so no effective
trigger moves and the fire-density schedule row is untouched). World x 750. Options B / C are taken only if A fails a row (§2.13's order); the
computed figures below say it will not.

Computed from the code (the rows compute them; these are the expected values):

| Quantity | Formula (all read, none typed) | Value |
|---|---|---|
| Worst life | `TICK_SLACK + (world.end.y + body_half_h − y_spawn) / assault_cross_speed`, `y_spawn = world centre y − V_LIMIT − CameraShake._MAX_OFFSET + design_y · WORLD_SCALE` (`_static_life()`'s rule) | (1304 + 548) / 90 + 0.033 ≈ 20.61 s → alive 65.0 – 85.61 s |
| Swept x | world x ± (`assault_sway_leash` + `module_x_extent`) | 750 ± 130 = 620 – 880 |
| Lit window of a row | `[t, t + lit_seconds()]`, `lit_seconds()` = `COLUMN_WARN_SECONDS` + increase + `COLUMN_ACTIVE_SECONDS` + dissolve (t11's static) | 8.4 s |
| Rows overlapping its life | 55.0 (ends 63.4 < 65.0: no), **78.0 (x 150 / 550 / 950)**, 98.0 (starts after 85.61: no) | one set |
| Needed clearance | `LaserRay._BEAM_WIDTH / 2` + a second half-beam margin (§2.13's "28 + 28") = 56 px beyond the swept edge | 550: 70 px, 950: 70 px |

### 2. A shared timeline helper

New `tests/helpers/level1_carrier_timeline.gd` (statics, no `class_name`; used by the heavy and drone gates so the carrier's numbers exist once):
- `lines(section) -> Array[Dictionary]`: one `{ "spawn", "trigger", "offset", "delay" }` per Carrier entry (effective trigger + delay), for the
  mutated-section boundaries (the pin and the guard read the shipped lines through `REPLAY.placed(WaveBuilder.CARRIER)`, review finding 7);
- `world_rect()` (`ArenaCamera.new().projectile_world_rect()`, freed), `body_half_height()` (from `carrier.tscn`'s `CollisionShape2D`),
  `world_x(design_x)`, `worst_life(design_y, cfg)` (table above);
- `launch_windows(spawn, design_y, cfg) -> Array[Dictionary]`: per bay (port, starboard) `{ "earliest", "latest", "count" }` for an
  **undamaged** carrier (the attack-in-budget row only): earliest = spawn + `first_launch_delay` (+ `starboard_launch_delay`) +
  `door_open_seconds` (the view entered at once); latest = spawn + worst life (a bay launches only while the carrier lives); count =
  `assault_launch_count`;
- `swarm_lifetimes()` moves from `test_level1_drone_spawns.gd::_c3_lifetimes()` into `level1_drone_concurrency.gd` as a static over the world
  rect and the two drone configs (review finding 6); both test files read it;
- `drone_intervals(section, cfg, lifetimes)`: per carrier one squad (both bays share one `SquadController`, t8), its drones ordered port first,
  the first `DroneConcurrency.ATTACKERS_PER_SQUAD` capable; each interval **`[spawn, spawn + worst life + its lifetime]`** (review finding 1:
  PANIC's `emergency_deploy()` launches every unlaunched bay at once with no schedule or view check, so after three outer wrecks drones can
  come out at any moment of the carrier's life). Whatever the camera or the player does, every drone is alive only inside it.

### 3. Rows in `test_level1_heavy_spawns.gd`

- **Pin** `EXPECTED_PH10_CARRIER` = `[{ section planet_approach, trigger 65.0, offset (55, −260), delay 0.0 }]` against the director (exactly one
  carrier line in level 1, so at most one alive). Boundary: a changed offset fails it.
- **`_carrier_column_conflicts(sections) -> { "checked", "overlapping", "conflicts" }`** (new; `_column_conflicts()` is not reused): for each
  carrier line, every schedule row of its section (plus the wall for the first section) whose lit window overlaps `[spawn, spawn + worst life]`;
  for each column, conflict when `|x − col| < leash + module_x_extent + _BEAM_WIDTH / 2 + _BEAM_WIDTH / 2`. Rows: no conflict, `overlapping` ==
  the 78.0 s set only (the 55.0 s set's lit end is before the spawn; asserted with the numbers printed). **Boundaries:** the same line moved into the
  58.0 s wave is flagged (the 55.0 s set's x 700 column); option A at `.at(-45, -260)` (world x 550) is flagged (the 78.0 s set's 550 column).
- **Gone before the section ends / spill-over:** carrier end = spawn + worst life + the missile bank's longest rocket `max_time` (its
  `HullMounts/Dorsal` slot's `pool_specs()` scenes; rockets persist), children end = latest launch + max drone lifetime; both < `min(section
  duration, _next_cleared_deadline())` (110.0 s); the child end is the interval end above (≈ 65.0 + 20.61 + 8.1 ≈ 93.7 s). Boundary: the
  same carrier at a 95.0 s wave fails it.
- **The lit replay (one scenario, shared)**: planet_approach from 64.0 s (spawn − `PRE_ROLL`) with `light_lasers` on, the 16× clock capped at
  `LIT_MAX_STEPS`, **the stub at the view's highest**: new opt-in `player_offset` on the replay helper (default `PLAYER_OFFSET`, every other
  caller unchanged), set to `(0, −(V_LIMIT + deadzone y + 50))` so `ArenaCamera` pans to −`V_LIMIT` and the carrier spawns at the highest view,
  the worst life the static row assumes. (**Deviation from §2.13's "the player stub at the replay's usual place"**, with reason: at the usual
  place the camera offset is +220 (250 − the 30 px deadzone), the carrier spawns at y 60 (608 px below the worst case) and is freed at about
  78.8 s, before the 78.0 s set turns lethal at 81.56 s, so the laser check would be vacuous.) Stops once the carrier is gone and section time ≥ 78.0 + `lit_seconds()` + a tick (cap `PRE_ROLL` + worst
  life + 2 s). Hooks (before `_ready()`; mounts and hangars after `ready`): the carrier's spawn / gone time, `hangars().launched`, every mount's
  `round_fired` (batteries, bow, bank) and the children of each launch. One run gives:
  - **lasers:** `deaths` empty (no part, no hull); the carrier's lethal clearance is finite (it shared a height with a lethal 78.0 s strip:
    the check is not vacuous) and **≥ the computed floor** `min |x − col| − leash − hull half-width (scene) − _BEAM_WIDTH / 2` (54 px, review
    finding 2; and ≥ `LaserRay._HAZARD_PAD` as t11); the carrier's largest `|x − brain.anchor_x()|` over the run ≤ `assault_sway_leash` + 0.5 px
    (the swept-x model's one runtime input); the measured life lies in `[worst life − 0.5, worst life + TICK]` (the stub put the view at its
    highest); `_check_ray_edges()` on the run (the 78.0 s row's onset on the level's time); **the real-laser sanity row**: every 78.0 s ray was
    lethal and its last lethal tick < 78.0 + `lit_seconds()`, and no ray is lethal at the stop (the lit window is a true upper bound); idle
    frames within the step cap;
  - **attack in budget:** both bays launched exactly once, `assault_launch_count` children each (4), each launch time inside its
    `launch_windows()` bounds (no part is damaged in this replay, so no PANIC and no emergency deployment: `is_core_exposed()` false,
    asserted), and at least one mount round fired, all before the carrier left;
  - **fire record:** the carrier's rounds per mount kind and the peak in any 2 s window, printed in `test_heavy_fire_density_is_measured`
    (measured, ungated, §2.12) and recorded in DECISIONS.
- **Constraint 4:** unchanged rows prove it: the heavy count gate (planet_approach holds no heavy), the specialist gate (scene-path counts; the
  carrier and its drones are not specialists).

### 4. Other gates

- `test_level1_drone_spawns.gd::test_c3_peak_concurrency_stays_within_the_pre_decided_ratios` appends `drone_intervals()` per section (only
  planet_approach has a carrier) to the squad intervals before both peaks; it asserts the planet_approach carrier contributed 4 intervals.
  Expected: capable ≤ 10 of 12, all ≤ 13 of 15. **Boundary (derived, review finding 5):** `k = ceil((floor(2.5 × legacy) + 1 − all) / (2 ×
  assault_launch_count))` more carriers, each spawned AT planet_approach's all-drones peak moment (so every new interval contains it), push
  the all-drones peak past 2.5×. Lever if the gate fails: `assault_launch_count` 2 → 1 (not expected).
- `test_engagement_deadline.gd::test_no_enemies_cleared_section_spawns_a_carrier` gains the non-vacuity line: level 1 places exactly one
  carrier, in a DURATION section.
- Must stay green unchanged: `test_level1_specialist_spawns.gd`, `test_level1_ph8_attacks.gd`, `test_level1_ph9_attacks.gd` (its jammer slice
  now spawns the carrier at slice 4.0 s; the lock comes ≈ 65.9 s, before the carrier comes within its 340 px pulse trigger of the stub; if the
  carrier's fire kills the jammer before the lock → option B, per §2.13), `test_level1_fighter_fire_density.gd` (schedule row),
  `test_level1_laser_columns.gd`.

## Build sequence

1. Helper `level1_carrier_timeline.gd` + replay `player_offset`; the rows of §3 / §4 written against the director **before** placing the
   carrier (pin, conflicts, spill, replay and drone count fail: no carrier line).
2. Place the carrier (director line + header comment). Run the touched files; then the level-1 family and `test_level1_ph9_attacks.gd`.
3. If any constraint fails, the next option (B, then C); none → `Result: ESCALATE` with the timeline.
4. `scripts/check-test-leaks.sh`, two `scripts/gate-time.sh` runs (baseline two runs at `7aba280`), `bash /agent/verify.sh`.
5. DECISIONS (t12 entry: option, worst life, x span, overlapping lit windows, drone peaks, measured replay figures, the stub deviation),
   README gate-time row, short CLAUDE.md / carrier `ENEMY.md` / `assault.md` lines.

## Test plan

| Row | File | Boundary |
|---|---|---|
| `test_the_carrier_line_is_pinned` | heavy spawns | `test_a_moved_carrier_line_fails_the_pin` |
| `test_the_carrier_clears_every_lit_column` (no conflict; overlapping = 78.0 s set; 55.0 s set ends before spawn) | heavy spawns | `test_a_carrier_at_the_58_s_wave_is_flagged`, `test_a_carrier_at_world_x_550_is_flagged` |
| `test_the_carrier_and_its_children_are_gone_before_the_section_ends` | heavy spawns | `test_a_carrier_at_95_s_spills_over` |
| `test_no_carrier_part_dies_under_a_lit_laser` (deaths, clearance finite, life, ray edges, idle cap) | heavy spawns | the kill side is t11's `test_a_heavy_held_in_a_lit_ray_is_reported_dead` (same `deaths` code path); the static boundaries above |
| `test_the_replayed_column_lit_window_is_an_upper_bound` (real-laser sanity) | heavy spawns | — |
| `test_the_carrier_launches_both_hangars_and_fires_before_it_leaves` | heavy spawns | launch times inside the computed windows |
| fire record line in `test_heavy_fire_density_is_measured` | heavy spawns | ungated |
| C3 with carrier intervals | drone spawns | `test_extra_carriers_at_the_peak_fail_the_c3_gate` |
| guard non-vacuity | engagement deadline | existing synthetic boundary |

## Risks

- **Gate time** (allotment 2.5 s): one ≈ 23 game s lit replay at 16×, CPU-bound with planet_approach traffic; plus the carrier in the ph9 jammer
  slice. If over: only the README's rules (share / memoise), never an assertion (review finding 3); past the 1.5× line, report it.
- **The high stub changes the traffic's behaviour** (the AI targets the stub high on the screen): the replay is the carrier's lit check and
  attack row, not a section replay; the other replays keep their stub.
- **The ring's friendly fire on the jammer** in the ph9 slice: accepted by owner choice 8; the ph9 row decides (option B if it breaks).
- **A carrier child may die in a lit column**: not gated (children avoid hazards; the claim is the carrier's parts).

## Out of scope

Docs beyond the lines named (t13); hub carrier (t10, done); heavy rows (t11, done); any change to frozen constants or the carrier's tuning.

## Response to review round 1

1. Drone intervals start at the carrier's spawn (PANIC's emergency deployment); the tight windows stay only in the attack row, which asserts no PANIC.
2. The lit row asserts the computed clearance floor (and `_HAZARD_PAD`) and the measured sway ≤ the leash.
3. The gate-time lever that dropped an assertion is removed.
4. The usual-stub figures corrected (offset +220, spawn y 60, freed ≈ 78.8 s) in the plan and the context.
5. The C3 boundary is derived: `k` carriers spawned at the all-drones peak moment.
6. `swarm_lifetimes()` moves into `level1_drone_concurrency.gd`; both files read it.
7. The pin and the guard read `REPLAY.placed(WaveBuilder.CARRIER)`; `lines()` serves the mutated-section boundaries only.
