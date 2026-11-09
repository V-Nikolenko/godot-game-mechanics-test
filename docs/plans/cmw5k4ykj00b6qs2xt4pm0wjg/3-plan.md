# t14: Level 1's Planet Approach sends one local jammer and, after it has gone, one Hacker Frigate

Epic plan `docs/plans/cmug23onr001pm52w9swwophy/3-plan.md` §2.17 (approved). This plan only picks the option, fixes the numbers it measures
and names the rows; it does not re-design §2.17.

## Problem
Level 1 never shows the player Phase 9's two Assault-capable enemies. Planet Approach should send one Hacker Frigate (hijacks the player's homing
rockets) and, later, one small jammer (locks H abilities and K rockets inside its drifting ring), never together (a jammed player cannot launch, so the
hijack would be moot), without raising the section's crowding past the frozen 2.5x specialist gate or parking the jammer in a laser column.

## Design

### Option chosen: A (the default), measured by hand first and re-measured by the gate
Lives (every term read from configs, scenes or the memoised probe in the tests):
- **Hacker** = `engage_seconds` 9.0 + deferral (`pulse_seconds` 1.6 + `_TICK_SLACK`; a budget expiring in PULSE lets the window finish, one expiring
  in TELEGRAPH cancels it) + `PH9_EXITS.hacker_exit(self)` (5.67 s, t8's measurement) = **16.30 s**.
- **Jammer** = `_TICK_SLACK` + `(world.end.y − y_spawn) / assault_drift_speed`, the Ph8 `_member_life()` formula (spawn at the highest view centre,
  shake included: `y_spawn = 360 − 380 − 8 + 2·design_y`; `world.end.y` = 1164): from design y −220, (1164 + 468) / 60 = **27.23 s**.

Placement:
- `b.hacker_frigate().at(-400, -180)` in the **42.0 s** wave (the 3-drone cluster from the upper right; the Hacker enters from the left, the opposite
  side) → alive 42.00–58.30 s.
- `b.jammer().at(-80, -220)` in the **62.0 s** wave (the two-drone weave, no specialist in it) → alive 62.00–89.23 s, world x = 640 + 2·(−80) = **480**.

Constraints (§2.17):
1. Count ≤ 7: today's planet_approach curve (t19 print) during 42.0–58.3 s peaks at 6 (55.30 s, 58.00 s) → 7 with the Hacker; during 62.0–89.23 s it
   peaks at 6 (65.00, 75.50, 88.80 s) → 7 with the jammer. Peak stays **7 of 7.5**, first reached at 28.40 s as today, so the peak-moment
   boundaries (ram triple, corvette, mine layer) are unchanged. deep_space and cloud_descent unchanged.
2. Hacker ends 58.30 < 98.0; jammer ends 89.23 < 98.0.
3. Hacker ends 58.30 ≤ jammer starts 62.00 (3.7 s gap).
4. The jammer (r 28) needs |x − column| ≥ `LaserRay._BEAM_WIDTH`/2 + 28 = 56 px against every planet_approach column **lit before it leaves**
   (the existing row's rule: no end filter, so the 10 / 25 / 38 / 55 s rows count too, stricter than "lit during its life"). Columns with time < 89.23:
   128, 150, 200, 300, 384, 400, 550, 600, 640, 700, 800, 896, 950, 1000, 1100, 1152. x 480: nearest 400 (80 px) and 550 (70 px), clear. The 98.0 s row
   (450 / 850) starts after it is gone.

Why 42 / 62: 42.0 is the earliest A wave after the 40 s bonus drone, which leaves the most room after the Hacker; 62.0 is the first wave after the
Hacker is gone and carries no specialist. 44 / 47 / 50 / 53 for the Hacker also pass (47 shares a wave with the Mine Layer — rejected as crowding). If
the gate's measured figures differ from the above and A fails, fall through B → C → D exactly as §2.17 orders them, and ESCALATE if none fits.

### Tests
**`test_level1_specialist_spawns.gd`, new "Phase 9 t14" section** (shape of the Ph8 section):
- `EXPECTED_PH9` = `[{planet_approach, "HACKER_FRIGATE", 42.00, (-400,-180), 0.00}, {planet_approach, "JAMMER", 62.00, (-80,-220), 0.00}]`;
  `_PH9_KIND_NAMES` keyed by `WaveBuilder.HACKER_FRIGATE`, `JAMMER`, `PULSED_JAMMER`, `SECTOR_JAMMER`, and the Disruptor's path.
- `_ph9_lives()` (cached): Hacker life (above, exit via `PH9_EXITS.hacker_exit(self)` only), jammer drift life via a generalised
  `_static_life(design_y, slot_y, speed)` that `_member_life()` now calls (Ph8 numbers bit-identical).
- `_ph9_intervals(section)` appended in `_ai_intervals()` (as `_ph8_intervals`): one interval per Ph9 ship, kinds `HACKER_FRIGATE` / `JAMMER`; so the
  frozen 2.5x gate, every peak boundary and the spill-over rows count them. `_ordnance_tail()` is 0 for both (darts are pooled without
  `persist_after_owner_death`; asserted by reading the Hacker scene's `BulletPool`).
- Rows: pin matches; pin internally consistent (2 rows, planet_approach only, DURATION, each joins a wave that already had entries);
  delay-changed boundary; no-rail row + `.move()` boundary; lives printed with sanity (Hacker exit > 0, jammer life within 27.3 s);
  **constraints 2 and 3** row (`hacker.end < 98.0`, `jammer.end < 98.0`, the two intervals disjoint) with a boundary (the jammer moved into the 50.0 s
  wave overlaps the Hacker and fails the disjointness predicate); **Hacker at 96 s boundary** (insert `b.wave(96.0, [b.hacker_frigate().at(-400,-180)])`
  in list order: planet_approach's peak 7 → 8 > 7.5); the alive curve printed with Ph9 ships marked (extending `_curve_text`).
- `_column_conflicts()` extended: every Ph9 static line (any jammer path) is checked like a member with slot ZERO, its body radius read from its scene's
  `CollisionShape2D`, its life from `_static_life`. `test_ph8_static_members_clear_every_lit_column` renamed `test_static_members_clear_every_lit_column`
  and its count sanity becomes `3·(8+12) + 1·16`. Boundary `test_a_jammer_moved_onto_a_lit_column_fails_the_column_row`: the jammer at design x −45
  (world 550, the 78.0 s column) is reported, and only against columns at 550.

**`test_engagement_deadline.gd`, new rows** (each with a failing synthetic boundary):
- `test_no_enemies_cleared_section_spawns_a_disruptor` (scene path `hacker_disruptor.tscn`; boundary: added to cloud_descent's last wave is seen).
- `test_no_section_spawns_an_emp_zone` (scene path `emp_zone.tscn` in any section's wave entries; boundary as above).
- `test_no_section_spawns_an_emp_laying_minefield`: a wave entry whose path is `minefield.tscn` with a non-zero `initial_props["w_emp"]`; boundaries:
  one with `w_emp` 0.15 is flagged, one with 0.0 is not.
- `test_no_assault_level_source_places_emp_or_a_sector_jammer`: a pure `_level_source_violations(files: Dictionary) -> Array[String]` over every
  `.tscn`/`.gd` under `res://assault/scenes/levels/` (recursive, `DirAccess`, read with `FileAccess`) plus `res://assault/scenes/systems/wave_builder.gd`
  for the `w_emp` string only. Flags: any level file containing `emp_zone.tscn` or `EmpZone`; a level `.tscn` containing `emp_mine.tscn`; a level
  `.tscn` line `w_emp = <v>` with `float(v) != 0`; a level `.gd` or `wave_builder.gd` containing `w_emp`; a level file containing `sector_jammer` or
  `SECTOR_JAMMER`. The real scan is empty and has read ≥ 7 files (sanity). Boundaries, each a synthetic `{path: text}`: a `.tscn` with `w_emp = 0.15`
  fails, `w_emp = 0.0` passes; a `.tscn` instancing `emp_mine.tscn` fails; a `.gd` with `EmpZone` fails; a `.gd` with `w_emp` fails; a
  `wave_builder.gd` text with `w_emp` fails; a `.gd` with `SECTOR_JAMMER` fails.

**New `tests/integration/test_level1_ph9_attacks.gd`** (the `test_level1_ph8_attacks.gd` shape, 16x clock, `level1_slice_replay.gd`):
- `test_the_level1_hacker_reaches_pulse_inside_its_budget`: slice `rel − 1 .. rel + engage + 2`; every 0.4 game s the observe callback launches one
  live homing rocket from the player stub, locked onto the nearest live non-Hacker `BaseEnemy` whose bearing from the stub is > 30° off the Hacker's
  (none → no rocket), parented to the stub's parent (freed with the world). Hook on the Hacker's `brain.phase_changed`: record `budget.remaining()` at
  PULSE; count `retargeted` on every rocket. Stops once PULSE has ended or the Hacker has left. Asserts: exactly one PULSE, entered with budget left,
  rockets were in flight at PULSE start; claims printed (asserted ≥ 1 only if stable over repeated runs — decided while building and recorded).
- Boundary `test_a_level1_hacker_with_a_1_s_budget_never_pulses`: private `engage_seconds` 1.0 (< `first_pulse_delay` 2.0): no TELEGRAPH, DISENGAGE;
  the shipped config untouched.
- `test_the_level1_jammer_locks_a_parked_player`: slice from the jammer's `rel − 1`; on the first observe tick a real `player_fighter.tscn` is parked at
  the stub's position (physics and process off, removed from group `player`, its `HurtBox` disabled so traffic can neither target nor hurt it), and a
  second one at the same y and x 1240 (outside the r 240 field at x 480 for all its life). Each tick both get `_step_disruption(dt)`. Stops on the first
  lock of the near ship. Asserts: the near ship locks while the jammer is alive and `Hazards.jammer_at()` there is the jammer's field; the far
  (control) ship never locks.

### Director change
Two lines in `_build_section_2()` with a comment each (the Ph7 / Ph8 comment style): "never in an ENEMIES_CLEARED section", "lives never overlap".

### Docs
`DECISIONS.md` "Phase 9, built in t14" (option A, the measured peaks, lives, x, any deviation); `tests/README.md` gate row; one-line placement notes in
`hacker_frigate/ENEMY.md`, `jamming_structure/ENEMY.md`, `docs/enemy-roster.md`, `CLAUDE.md` (Phase 9 paragraph), `assault.md` if it lists level-1
placements. No structural change (no new entity), so `updating-project-docs` is used only for the placement lines.

## Build sequence
1. Specialist-spawn rows (`EXPECTED_PH9` etc.) written first; they fail (no Ph9 lines).
2. Director: the two lines. Rows go green; record the measured peak / lives.
3. Column-clearance extension + boundary.
4. `test_engagement_deadline.gd` guard rows + boundaries (green on today's data, boundaries prove they bite).
5. `test_level1_ph9_attacks.gd` replays; `scripts/check-test-leaks.sh`.
6. Docs, DECISIONS, gate time (`scripts/gate-time.sh` before / after), `bash /agent/verify.sh`.

## Test plan
As above. Boundaries: delay-changed pin, `.move()` rail, jammer in the 50 s wave (overlap), Hacker at 96 s (count 8), jammer at x 550 (column),
Disruptor / EMP zone / EMP Minefield (w_emp 0.15 vs 0.0) wave entries, seven synthetic source texts, Hacker with a 1 s budget, the far parked ship.

## Risks
- **A rocket hits the Hacker during TELEGRAPH** in the replay (the designed counter cancels the pulse). Mitigated by locking rockets on other traffic
  > 30° off the Hacker's bearing; if still flaky, rockets launch only while the Hacker is not in TELEGRAPH, documented.
- Spawn timers are idle-time at 16x: the replay helper already waits for every triggered spawn (Ph9 t1 fix).
- A parked real fighter: `PlayerBase._ready()` joins `player`; removing it from the group and disabling the hurtbox keeps traffic on the stub.
- Gate time: ~25 game s of replay at 16x plus memo-hit probe calls; target ≤ 2.5 s.

## Out of scope
Retuning either enemy; deep_space; any EMP zone or EMP mine in Assault; the Disruptor's placement; a laser-column replay of the jammer
(`scripts/measure-level1-columns.sh` is manual and optional).

## Revision 1 (answers review round 1)
- **B1:** the column boundary (jammer at design x −45, world 550) asserts the conflicts are non-empty and **include** the 78.0 s column at 550; it no
  longer says "only". (The no-end-filter rule stays, so the 10.0 s column at 600 is reported too, 50 < 56 px; that is the stricter rule working.)
- **B2:** the source scan also flags a `jammer(&"sector")` / `jammer("sector")` call (regex `jammer\(\s*&?"sector"`), with a failing synthetic `.gd`
  boundary and a passing `b.jammer(&"pulsed")` case.
- **N1:** `test_ph8_static_members_clear_every_lit_column` keeps its name (CLAUDE.md, the director comment and `STRUCTURE.md` cite it); it gains the Ph9
  statics and its doc comment says so.
- **N2:** the constraint-2/3 row gets two failing boundaries: the jammer moved into the 50.0 s wave (overlaps the Hacker) and the jammer moved into the
  75.0 s wave (ends 102.23 s ≥ 98.0).
- **N3:** the Hacker replay's rockets: locked onto the nearest live non-Hacker enemy > 30° off the Hacker's bearing; with none, an unlocked rocket on a
  fixed heading 60° off the Hacker's bearing (away side). Slice length `engage_seconds + PRE_ROLL + POST_ROLL` = 12 game s; asserts the run stopped on
  its claim (PULSE ended), not on its length.
- **N4:** kept, as in Ph8.
- **N5:** the scan's file set adds `assault/scenes/enemies/space_station/station_reinforcements.gd` (an Assault wave source authored through
  `WaveBuilder`), and flags `emp_mine` (the scene file name or `EMP_MINE`) in any scanned `.gd` as well as `.tscn`. Boundaries for both.
- **N6:** the jammer replay's slice length is the jammer's drift life + PRE_ROLL (28.3 game s, a cap; the lock comes ≈ 8–9 s in), and it asserts it
  stopped on the lock.

## As built
- Option A fitted on the first measurement; every figure above matched the gate (Hacker 42.00–58.30 s, jammer 62.00–89.23 s, peak 7 of 7.5 first at 28.40 s).
- `_ph9_intervals()` fails the gate on a Disruptor line (no Disruptor life is measured) instead of counting it as a Hacker.
- The EMP-zone and EMP-mine wave-entry guards share one row (`test_no_section_spawns_an_emp_zone_or_an_emp_mine`); the synthetic source boundaries are their own row
  (`test_synthetic_level_sources_with_emp_or_a_sector_jammer_fail_the_scan`).
- The Hacker replay claims 2 rockets in each of 5 runs, so `claims >= 1` is asserted. The parked fighter locks 4.9 s after the jammer spawns (the plan guessed 8–9 s).
- GUT 223.575 → 224.17 s (+0.60 s of the 2.5 s allotment).
