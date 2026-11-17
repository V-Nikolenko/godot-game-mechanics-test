# t11 — Level 1's four gunships become Heavy Gunships that fight, survive the lasers and leave in time

Task `cmwafsrbi00azqs2yuwzayuk3`, epic `cmug23oo90029m52wae4clve0` (Phase 10). The design is the epic's approved plan §2.12 (with §2.4.3, §2.5, §2.15, §2.16)
and the epic review's round-2 findings N4 and N5. This file fixes the build-level choices §2.12 leaves open and the test list; it does not redesign anything. Each
departure from a §2.12 line is marked **(D)** and goes to `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` as "Phase 10, built in t11". Context: `1-context.md`.
**Revision 3** answers review rounds 1 and 2 (`4-review.md`); the answers are listed at the end.

## Problem

Level 1 has four gunships. The deep_space one (3.5 s) has fought as an AI Heavy Gunship since t4. The three in Cloud Descent (50.0, 62.0, 62.8 s) still ride
straight rails, and a rail suspends the brain, so **they never fire**: they drift down the screen and are culled. After this task all four fight (keep range, turn a
battery side-on, fire) and leave by themselves when their budget runs out. Two things must stay true: Cloud Descent is an ENEMIES_CLEARED section with a 10 s net after its
last wave (76.0 s), so each heavy and its last rocket must be gone in time; and the deep_space heavy shares its sky with the level-start laser wall and three column
volleys, which kill anything they touch, parts included. Nothing proves the second today: the slice replay lights no lasers.

## Design

### 1. Director (`level_1_director.gd`)
- cloud_descent 50.0 s → `b.heavy_gunship().at(0, -400)`; 62.0 s → `b.heavy_gunship().at(-100, -400)` and `b.heavy_gunship().at(100, -400).delay(0.8)`. Triggers, offsets,
  delays and list order unchanged (the deep_space wave-order quirk is untouched). Comments updated ("gunship" → "Heavy Gunship, AI, no rail").
- `const COLUMN_WARN_SECONDS := 3.0`, `const COLUMN_ACTIVE_SECONDS := 4.0`; `_spawn_laser_columns(columns, warn := COLUMN_WARN_SECONDS, active := COLUMN_ACTIVE_SECONDS)`.
  Behaviour-identical (`test_level1_laser_columns.gd` stays green).
- Header paragraph: the Phase 10 lines, their gates, "only the deep_space heavy meets lasers".

### 2. Lit slice replay (`tests/helpers/level1_slice_replay.gd`)
Opt-in, set on the replay instance before `run()` (default off, so every existing caller runs the exact code path it runs today; the new code sits behind
`if light_lasers`):
```
var light_lasers := false          # light the section's real lasers on the slice timeline
var lit_section: StringName        # which section's schedule (and, for deep_space, the wall)
var lit_from := 0.0                # the slice's start in section time (slice time + lit_from = section time)
```
When on, at the `load_section()` moment (after the three settle frames, inside the same `process_frame` resume, so the wall and `WaveManager`'s clock start in
the same idle frame, as in the level):
- a spawner `Node` under the harness root gets `set_script(DIRECTOR_SCRIPT)` (the worker's technique: no `_ready()`), and each
  `laser_column_schedule()[lit_section]` row is fired through the director's real `_spawn_laser_columns(row.columns)` (so `COLUMN_WARN_SECONDS` /
  `COLUMN_ACTIVE_SECONDS` apply) when **an idle-time clock** reaches `row.time − lit_from` (review R2-1d: `Level1Director._process` fires its rows on idle time,
  `_section_elapsed += delta`). The clock starts at the load frame's own idle delta (read at the `load_section()` moment: `WaveManager` adds that frame's delta
  in its `_process` too) and a `process_frame` hook adds each later frame's delta and fires the due rows.
- **Warm start (review findings 2, R2-6).** A row that began before `lit_from` is relit at slice start only while it can still be lethal, decided by the static
  `warm_start(elapsed, warn, active) -> Dictionary` (`{}` = not lit, else `{ "warn", "active" }`). With `elapsed = lit_from − row.time`, `warn` / `active` its own
  timings, `init` (the init animation, 0.2 s), `increase` (the increase animation, 0.56 s) and `lethal_end = warn + increase + active`:
  - `elapsed < warn` (strict: at equality a `LaserRay` with warn 0 waits for the 0.2 s `laser_init` first): lit with warn `warn − elapsed` and `active` (exact:
    only the warning gets shorter);
  - `elapsed ≥ warn` and `rest = lethal_end − elapsed − (init + increase) ≥ MIN_ACTIVE` (0.25 s): lit with warn 0 and active `rest` (approximate: the ray re-runs
    init + increase before it is lethal again, so its lethal span is shorter and ends on time); **never `active ≤ 0`**, which `LaserRay` reads as "never
    dissolve";
  - otherwise (its lethal phase is over or nearly over, dissolve included): **not lit**.
  The same rule, with the wall rays' own scene `warn_duration` / `active_duration` and `row.time = 0`, decides the wall.
- `lit_section == &"deep_space"`: the wall scene the level uses (read from `level_1.tscn`'s `LaserWallWave` state: scene and position, the `_wall_wave_row()`
  source) is instantiated, each ray's `warn_duration` / `active_duration` set by the rule above **before** `add_child` (rays start in `_ready()`), and added
  under the harness root at that position. At `lit_from` 0 the rule leaves the scene's values untouched (N4: the level lights the wall at level start =
  deep_space 0.0 s).
- Every `LaserRay` entering the tree is tracked (`node_added`, disconnected at the end) with its source (`"wall"` for a ray whose parent is the wall instance, else
  `"column"`), its x and its row time. Each physics frame the replay records per ray the first and last slice time it was `is_lethal_now()`. **Per ray**, the
  largest idle delta from its creation frame to its last lethal frame is recorded as its `max_idle` (the `process_frame` hook, the `test_level1_specialist_exit.gd`
  pattern; a ray created at the load moment, the wall, is seeded with the load frame's own delta, because a hook connected during that `process_frame` emission is
  not called for it — R2-1b). An edge's tolerance then depends only on the frames around that ray, never on a hiccup elsewhere in the run.
- Every ship of `target_path` (in `tweak` time, before the caller's own tweak): its `died` and each `Modules/*` `EnemyModule.destroyed` are connected; each death
  is recorded as `{ "ship": target index, "what": "hull" | module_id, "t": section time, "covered": bool, "source": "wall" | "column" | "" }`, where *covered* =
  some ray with **`is_lethal_now()`** (never a warning one, review 7b) has a `danger_rect()` that intersects the world AABB of that node's `HurtBox` shapes at the
  moment of the signal.
- `run()`'s returned dictionary gains `"deaths"` and `"lit"` (`[{ "source", "x", "row_time", "from", "to", "max_idle", "lit_warn", "lit_active" }]`, `from` /
  `to` the first / last lethal frame in section time, −1 if never lethal; `lit_warn` / `lit_active` what the ray was lit with) only when lit; `deaths` is also readable on the instance during the run (the boundary row's `observe` stops on it).
  The connections are dropped and the hook removed before the world is freed.
- Statics: `ray_timing() -> Dictionary` = `{ "init", "increase", "dissolve" }` read from `laser_ray.tscn`'s `SpriteFrames` (sum of frame durations / speed);
  `lit_seconds()` = `COLUMN_WARN_SECONDS + increase + COLUMN_ACTIVE_SECONDS + dissolve` (a column's whole lit window, the definition t12 reuses) and
  `column_lethal_offset()` = `COLUMN_WARN_SECONDS + increase`. The wall's own onset / end come from its rays' scene values, never from these.
- Teardown unchanged (the settle loop already waits on spawn timers). A ray freed with the world leaves its warn / active `SceneTreeTimer` to run out in later
  tests, connected to a freed object (it holds no resource); `scripts/check-test-leaks.sh` confirms.

### 3. New gate `tests/integration/test_level1_heavy_spawns.gd`
Pure-data rows (no physics):
- **Pin** `EXPECTED_PH10_GUNSHIPS`: `{section, trigger, offset, delay}` × 4 (deep_space 3.5 (0, −500) 0; cloud_descent 50.0 (0, −400) 0, 62.0 (−100, −400) 0, 62.0 (100, −400) 0.8),
  read through `level1_slice_replay.placed()`; each row's effective trigger equals its wave's own. Boundary: a changed delay fails the pin.
- **No rail:** every heavy entry has `movement == null`, the default exit mode, no formation. Boundary: a `.move(b.straight(42))` put back fails it.
- **Legacy peak:** `_LEGACY_ROWS` = the pre-change four rows *as data* (the old rails built with `WaveBuilder.straight(42 / 36)`), whose section / trigger / offset / delay
  must equal the pin's; `_LEGACY_PEAK_HEAVIES` = `{deep_space: 1, cloud_descent: 3}` frozen, and a row recomputes it from `_LEGACY_ROWS` every run (never vacuous): a rail
  row lives until it leaves `enemy_cull_rect()` after entering it (`_rail_lifetime`, the `EnemyPathMover` rule; the 50.0 s gunship's figure printed and recorded, ≈ 14.8 s),
  a no-rail legacy gunship (deep_space) never left (it held until killed: life = INF — a special case in the caller, because the copied `_rail_lifetime` returns 0.0
  for `movement == null`, which would make the recomputed deep_space peak 0).
- **The exit** is read once in `before_all()` (`PH10_EXITS.heavy_gunship_exit(self)`), before any replay world exists: `prepare_probe` strips group `player` from every
  node in the tree, so a probe that missed the memo after a harness was built would leave its stub untargetable (R2-4b; in the suite it is a memo hit).
- **Count:** heavy lives = spawn + `engage_seconds` + `attack_window()` + measured exit (`ph10_exit_keys.heavy_gunship_exit()`, memo); the peak alive per section ≤ 1.0 × the
  frozen value; a section with no frozen value holds none. Boundaries: one extra heavy inserted (in list order) at each section's measured peak time fails; a heavy added to
  planet_approach fails.
- **Spill-over:** for every DURATION section, each heavy's end = spawn + `engage_seconds` + max(`attack_window()` + exit, rocket max life) is before the next
  ENEMIES_CLEARED section's last trigger (`_next_cleared_deadline`, the Ph5 predicate), and the deep_space heavy's end is before deep_space's own 30.0 s. Boundary: with
  `engage_seconds` 20 the deep_space heavy is flagged. (The carrier-child half of §2.12's sentence is t12's: no carrier exists in level 1 yet.)
- **Which heavies meet lasers:** every cloud_descent heavy spawns after every cloud_descent column row's lit window ends (`row.time + lit_seconds()`), so only the deep_space
  heavy is replayed lit; boundary: a heavy moved to cloud_descent's 34.0 s is flagged.

Replays (16× clock, `_scale_clock()` / `_restore_clock()`; each scenario run once per file, lazily by the first test that needs it (inside a testcase, so
`gate-time.sh`'s per-file sums show it; R2-3), and shared as plain data — Gate time rule 2):
- **Deep_space lit run (review finding 6: from section 0)** — slice `[0.0, …)`, `light_lasers` on, `lit_from` 0: the wall is exactly the level's (no shift) and the
  heavy meets the 0.0–3.5 s waves' real ships. Capped at deep_space's own 30.0 s (R2-5b: a heavy that detours round a lit column and leaves late is still correct for a
  DURATION section; the spill-over row is the real limit); stops when the heavy has left the tree, and the lit exit time is printed against the measured exit. Records
  deaths, the rays' lethal windows, `max_idle`, the first battery `FIRE` (mount `phase_changed`, connected through `ship.ready`: `tweak` runs before
  `build_mounts()`, review 7c) with `budget.remaining()` and the brain phase at that moment, the DISENGAGE time, and the slice time of every `round_fired` of the
  heavy's mounts (gun rounds and rockets separately). **(D)** This one run is the deep_space heavy's lit check, its attack-in-budget row and its fire-density record
  (§2.12 lists them separately; one scenario keeps the allotment). If the cap ends it with the heavy alive, the row prints its phase, position and the time
  (review 3: a detour round a lit 14.0 s column must be diagnosable).
- **Cloud_descent run** — slice `[50.0 − PRE_ROLL, 62.8 + engage + POST_ROLL)`, lasers off (none is lit there, row above), all three heavies hooked through `tweak`
  (`died`) and `ship.ready` (mounts), stops once all three have spawned and each has entered DISENGAGE or left. Records the same per heavy.
- **Kill-detection boundary run (review finding 4)** — the deep_space slice from `lit_from` 2.5 (so it also exercises the wall's warm start: warn 3.0 → 0.5), its wave
  list plus **one added heavy entry** (a `SpawnEntryResource` taken from `b.wave(0.0, [b.heavy_gunship().at(256, -500)]).entries[0]` — `b.heavy_gunship()` alone is
  a `SpawnConfig` — appended to the fresh `entries` array of the slice's copy of the 3.5 s wave, so it spawns at world x 1152), both heavies with private
  `hazard_avoidance` 0 (the caller's `tweak`, which also captures them in spawn order: `observe` sees only the first, R2-4a) and an `observe` hook that writes the
  first heavy's x to 640 (inside the wall's 644 ray) and the second's to 1152 (the 6.0 s set's column, outside the wall's x 0–672) every frame. Stops when each has a
  covered death; cap: the 6.0 s column's lethal end (section 13.56) + 0.5.

Rows on them:
- `test_no_heavy_part_or_hull_dies_under_a_lit_laser`: no covered death; and the heavy was **not killed at all** and left after DISENGAGE (non-vacuity: a heavy killed
  early by stray friendly fire would have met fewer lasers).
- `test_a_heavy_held_in_a_lit_ray_is_reported_dead` (kill-detection boundary, §2.12's "held … through the 6.0 s column's lit window"): the x 1152 heavy has a covered
  death with `source == "column"` after the 6.0 s row's onset; the x 640 heavy has a covered death with `source == "wall"` (≈ section 5.4 s, inside the wall's lethal
  window). Both are printed.
- `test_the_replayed_lasers_are_lethal_when_the_level_makes_them` (N4; review findings 1, 7a, R2-1). Engine semantics the bounds follow (R2-1): a `SceneTreeTimer`
  created during an idle iteration is credited that iteration's **whole** delta, and an edge is observed on the next physics tick, so an onset can read up to about
  two idle frames early (the creation-frame credit, plus the idle clock's start at the load frame's delta) or late (the timer, then the increase animation, each ending
  on an idle frame), and a lethal span is short by up to one idle frame. With `d` = the ray's own `max_idle` (creation → last lethal, seeded with the load frame's
  delta) and `TICK` = 1/60: first lethal ∈ [expected − 2·d − TICK, expected + 2·d + 2·TICK]; (last − first lethal) ∈ [lit active − d − 2·TICK, lit active + d +
  TICK]. A guard per checked edge asserts the late tolerance `2·d + 2·TICK < 1.25 s` (half of N4's 2.5 s shift), so the row still catches that bug and a hiccup
  elsewhere in the run cannot fail it. Checked edges: only those whose expected time + 1.25 s precedes the run's stop, and the wall and the 6.0 s row are asserted to
  be among them. Expected onsets: the wall = its rays' lit warn + increase (3.56 s section in both runs), each column row = `row.time + column_lethal_offset()`. In the
  from-0 run the wall is unshifted; in the boundary run (from 2.5, the exact warm-start branch: warn 0.5) the wall's onset is checked the same way (the shift restores
  3.56 s; the N4 bug would read 6.06 s).
- `test_the_warm_start_rule` (data rows, no physics; review finding 2, R2-6): `warm_start()` over the three branches — `elapsed < warn` exact (warn shortened, active
  unchanged), `elapsed == warn` takes the middle branch, the middle branch's `rest`, `rest < MIN_ACTIVE` not lit, inside the dissolve (13.8 − 6.0 = 7.8) not lit, the
  wall at 7.0 / 11.0 not lit — and a sweep of `elapsed` over [0, lit window] in 0.01 s steps asserting every lit result has `active ≥ MIN_ACTIVE` and `warn ≥ 0`.
- `test_a_column_carried_over_a_slice_start_is_relit_until_its_lethal_end` (review R2-2: the approximate branch on real rays; empty wave lists, rays only): from
  deep_space `lit_from` 11.0 the 6.0 s row (elapsed 5.0 > warn 3.0, rest = 7.56 − 5.0 − 0.76 = 1.8) lights its three rays at slice start with warn 0 / active 1.8:
  first lethal at section ≈ 11.76 and last lethal at ≈ 13.56 (the row's real lethal end), both within the tolerances above; the wall is not lit; at the stop no ray
  is lethal. Run length derived from what it must observe: expected lethal end − lit_from + 1.25 + TICK (≈ 3.8 game s; R2-5a).
- `test_every_placed_heavy_fires_a_battery_inside_its_budget`: all four heavies have a battery FIRE with `budget.remaining() > 0` and not in DISENGAGE; the times are
  printed.
- `test_heavy_fire_density_is_measured`: prints per section the peak gun rounds in any 2 s window (`peak_window_rate` × 2), the total gun rounds and rockets, per heavy;
  asserts only that rounds were counted (ungated by design, §2.12). Figures go to DECISIONS.
- `test_a_replay_with_lasers_off_lights_nothing`: a 0.5 s replay with an empty wave list and `light_lasers` off adds no `LaserRay` to the tree (the default path is the
  old one); the from-0 lit run saw the wall's 12 rays and the 6.0 s row's three.

### 4. Deadline rows (`test_engagement_deadline.gd`)
Terms, read live, never typed: `engage_seconds` (shipped config), `attack_window()` (a live heavy in `HARNESS.assault()`, its brain's own method), the measured exit
(`PH10_EXITS.heavy_gunship_exit(self)`, called once in this file's `before_all()` so the memo's first measurement stays outside any testcase, as it was in
`test_heavy_gunship.gd`; review finding 5), rocket life = max `max_time` over the Missiles mount's `pool_specs()` scenes (the pod's mount found through the scene's
`Modules/Missiles/MountSlots` slot variant). Tail = `engage + max(window + exit, rocket) + MARGIN`.
- `test_every_cloud_descent_heavy_gunship_clears_the_timeout_on_both_terms`: 3 rows through `_deadline_rows`; for each, `rel + engage + window + exit + MARGIN < 10` and
  `rel + engage + rocket + MARGIN < 10`; the worst row printed (expected 62.8 s: −13.2 + 19.58 = 6.38 s).
- `test_the_heavy_deadline_terms_are_read_from_the_shipped_heavy`: window 1.05 (sanity, = 0.7 + 1 × 0.35), rocket life 6.0 (PURSUIT), exit > the centre's straight run and 0
  capped.
- Boundary (a), config-derived **(D)**: §2.12 says "a heavy added to the last wave at delay `10.0 − tail ± 0.05`", which is a negative delay (tail ≈ 19.6 s > 10 s). Built the
  way the fighter's config-derived row is: a one-heavy wave inserted **in list order** at `limit ± 0.05`, `limit = last trigger + timeout − tail` (≈ 66.42 s, between the 66.0
  and 68.0 waves; the inserted wave's effective trigger is asserted to be its own; a generalised insert helper, the fighter's asserts the last two waves). `+0.05` is
  over, `−0.05` is not.
- Boundary (b), the rocket term **(D, N5)**: open-pod tail = `engage + window + exit + rocket + MARGIN` (rockets launched until the end of the exit). A heavy inserted at
  `limit − 0.05` passes with the shipped closure and is over with the pod left open — the closure is what keeps it in. Derived from config + the measured exit (N5), so it
  holds for any lever. The shipped 62.8 s row's open-pod figure is printed (≈ 12.38 s) and recorded, not asserted (it holds only while exit ≥ 6.65 s:
  −13.2 + 9.0 + 1.05 + 6.0 + 0.5 = 3.35).

### 5. Levers (only if a row fails; each legal only while every attack-in-budget row — this file's and `test_heavy_gunship.gd`'s — stays green)
Lit replay death: (1) `hazard_margin` up to 110 (then `test_enemy_dual_mode.gd` `HAZARD_PROFILES` and any config pin follow); (2) the deep_space offset `.at(160, -500)`
(world x 960; never −160); (3) `assault_preferred_range` 480; (4) `assault_orbit_angular_speed` halved. Lever (2) clears the wall only: the 6.0 s column at x 640
(lethal ≈ 9.56–13.56 s) sits under the heavy's APPROACH target (640, 190) and the middle of its arc from either spawn (review 3), so only avoidance (levers 1, 3, 4)
answers that one. Deadline: `exit_speed` up to 360 / `exit_acceleration` up to 320 (then re-run the view-grid comparison, `ph10_exit_keys.gd` header), then
`engage_seconds` down to 7.0. None fits → `Result: ESCALATE` with the replay log and the figures.

### 6. Small follow-through
- `test_heavy_gunship.gd:40` `CLOUD_DESCENT_WINDOW` 23.2 (its comment and DECISIONS t4: "t11 replaces it with the live `_deadline_rows` figure"): replaced by a live
  read — cloud_descent's last effective trigger + `enemies_cleared_timeout` − the latest cloud_descent heavy spawn (`REPLAY.placed()` / `REPLAY.section()`), 23.2 s
  today. The row's assertion is unchanged.
- `_rail_lifetime` is copied into the new file (a third copy, review 9): the two existing gates keep theirs untouched.

### Alternatives rejected
- **A separate attack replay for the deep_space heavy** (§2.12 lists "lasers" and "attack-in-budget" as two replays): doubles a ~20 game-second run for no new
  information — the lit world *is* the real world. One shared scenario.
- **The deep_space lit run from 2.5 s with the wall shifted** (revision 1): N4's other option, starting at 0.0 s, needs no shift, costs ≈ 2.5 game s (≈ 0.2 s) and puts
  the heavy among every ship it really meets; the shift stays exercised by the boundary run (review 6).
- **Lighting the cloud_descent slice too:** its last column set (34.0 s) is dark at 42.4 s, eight seconds before the first heavy; the static row proves it instead.
- **Detecting a laser kill by `amount == 9999`:** exact, but ties the test to a private constant; the coverage test is what §2.12 asks ("whether a lit ray covered it")
  and matches the worker's measurement.
- **Two boundary runs (wall, column):** one run with two held heavies costs ≈ 11 game s instead of ≈ 14.

## Build sequence
1. Progress notes; failing tests: the pin / no-rail rows of `test_level1_heavy_spawns.gd` (red: three rails) and the deadline rows (they compute on paper; the pin is the red
   one).
2. Director: rails off, constants hoisted. Pin / no-rail / count / spill-over / deadline rows green; `test_level1_laser_columns.gd` green.
3. Helper: `light_lasers`, the idle-clock column firing, `warm_start()`, timing statics, deaths and per-ray lethal windows; the warm-start data rows, the lasers-off and carried-over rows.
4. **The deep_space lit run first** (review 3: the step most likely to end in ESCALATE) and its rows; apply the lit levers in order if a death shows; log each.
5. The boundary run, the cloud_descent run and their rows; the deadline boundaries; `test_heavy_gunship.gd`'s live window.
6. Every level-1 gate and replay file run alone (specialist, fighter spawns, fire density, drone spawns / exit, fighter exit, specialist exit, Ph8 / Ph9 attacks, laser
   columns, heavy gunship); `scripts/check-test-leaks.sh`.
7. Gate time: two `scripts/gate-time.sh` runs before (done: GUT `Time` 205.472 / 205.748 s, mean 205.61) and after; the new / changed files' own time; README row;
   output size.
8. DECISIONS (t11 notes, levers, measured exit / legacy figures / fire density / deviations), CLAUDE.md one paragraph, the heavy `ENEMY.md` and director header lines.
9. `bash /agent/verify.sh` green.

## Test plan
As §3 and §4. Boundaries: changed delay (pin), `.move()` put back (no rail), one extra heavy at the peak (count), a heavy in planet_approach (count), 20 s budget (spill-over),
a heavy moved to 34.0 s (which heavies meet lasers), the two held heavies (kill detection: a wall kill and a column kill), the warm-start data rows (equality, rest <
MIN_ACTIVE, in-dissolve, the sweep) and the carried-over real-ray row (warm start), lasers-off (helper default), the derived-tolerance guard (timing), config-derived (a)
± 0.05, the open pod (b).

## Risks
- **The deep_space heavy may die in the wall or in the 6.0 s column at x 640.** It spawns at x 640 and approaches the stub at x 640, under the wall's 644 ray (lethal
  3.56–7.56 s); its APPROACH target (640, 190) and the middle of its arc lie on the 6.0 s set's x 640 column (lethal ≈ 9.56–13.56 s, hazard from 6.0 s), the likelier
  killer (review 3). Avoidance must carry it out; the levers are ordered for this; (2) clears the wall only. The lit run is built first.
- **Gate time — an expected overrun, (D).** ≈ 20 (deep_space) + 24 (cloud, 49.0 → ≈ 72.9) + 7.4 (boundary, stops on its second death) + 3.8 (carried-over) + 0.5
  (lasers-off) ≈ 56 game seconds; a 16× clock ticks at most 960 times per real second, so ≥ 3.5 s real before any CPU, and the deep_space slice is full traffic plus 21
  rays: **≈ 3.8–4.5 s is the realistic figure, over the task's 3.0 s allotment** (R2-3). Logged as a deviation in DECISIONS and the README row (the t4 precedent: over,
  logged, absorbed by t1's surplus; the suite is at 205.6 s of the 237 s escalation line). The stop stays §2.15's: past the 1.5× line (4.5 s, two-run suite mean
  against the before mean 205.61 s) with every mitigation in place, `Result: ESCALATE` with the profile. **Accounting (review 5):** the exit probe (≈ 2.9 s) moves from
  `test_heavy_gunship.gd`'s `before_all()` to `test_engagement_deadline.gd`'s `before_all()` (that file sorts first), outside any testcase in both; `test_heavy_gunship.gd`'s
  `_probe_s` print then reads ≈ 0 s (R2-4c; the README row says so). Mitigations, none of which cuts an assertion: the probe is a memo hit after its first call; the
  boundary run stops on its two covered deaths, the deep_space run when its heavy leaves, the cloud run when its last heavy enters DISENGAGE (no round leaves a mount
  after that); the warm-start branches are data rows.
- **16× laser timing** moves a lethal edge by up to two idle frames either way; the tolerances are derived per ray from the idle deltas around it (README rule 1),
  with a guard at 1.25 s (half of N4's shift). A ray whose own frames pass ≈ 0.6 game s (≈ 38 ms real at 16×) fails the guard: if the measured `d` sits near it, the
  timing row's runs move to 8× (more cost), never a wider guard.
- **Stray friendly fire** (a corvette rocket crossing the heavy) could kill a part without a laser: reported as an uncovered death, and the non-vacuity assertion would fail
  only if the hull itself died; investigate then, never widen.
- **Own `SceneTreeTimer`s:** a ray freed with the world leaves its warn / active timer to run out in later tests — not a leak at exit; `check-test-leaks.sh` confirms.

## Out of scope
The Carrier's level-1 placement, its column math and the carrier-child half of the spill-over row (t12); docs beyond the lines named in step 8 (t13); a gated heavy
fire-density ceiling (later phase, §2.12); level 2's railed heavy (Ph15).

## Response to review round 1 (`4-review.md`)
1. *The N4 row's ±0.4 s at 16× (blocking):* tolerances are derived from the run's own largest idle delta (`2 · max_idle + TICK` for an onset, `max_idle + TICK` for a span),
   with a guard keeping them under 1.0 s (the N4 bug is a 2.5 s shift); the wall's onset reads its rays' own scene `warn_duration` + increase (§3, rows).
2. *The warm start can build a never-ending ray (blocking):* relit only while `lethal_end − elapsed − (init + increase) ≥ MIN_ACTIVE` (0.25 s), never with `active ≤ 0`;
   exact while still warning; a new row runs the carried-over and the in-dissolve case (§2, §3).
3. *The 6.0 s x 640 column:* named in Risks and §5 (lever 2 does not clear it); the deep_space lit run is build step 4, ahead of the other replays; a capped run prints
   phase / position / time.
4. *The boundary never tests a column kill:* two held heavies in one boundary run, x 640 (wall) and x 1152 (6.0 s column), each must report a covered death with the right
   `source`; no departure from §2.12's wording is left.
5. *Probe accounting:* the probe call sits in `test_engagement_deadline.gd`'s `before_all()`; the task is judged by the two-run suite mean; the estimate is restated
   (3.0–3.8 s).
6. *Run from 0 s:* adopted for the main deep_space lit run; the shifted wall stays exercised by the boundary run.
7. *Definitions:* checked edges are those reached before the stop (the wall and the 6.0 s row asserted among them); *covered* = an `is_lethal_now()` ray; mounts are
   connected through `ship.ready`, `died` / `destroyed` in `tweak`.
8. *6.65 s:* corrected.
9. *A third `_rail_lifetime` copy:* kept as a copy (existing gates untouched), noted in §6.

## Response to review round 2 (`4-review.md`, revision 3)
- *R2-1 (blocking), the timing row's lower bounds and guard:* bounds follow the engine's timer semantics — onset ∈ [expected − 2·d − TICK, expected + 2·d + 2·TICK],
  span ∈ [lit active − d − 2·TICK, lit active + d + TICK] — with `d` **per ray** (its creation frame to its last lethal frame; the wall seeded with the load frame's own
  delta, R2-1b); the guard is per checked edge, `2·d + 2·TICK < 1.25 s` (half of N4's 2.5 s shift, R2-1c); the columns now fire on an idle-time clock started at the
  load frame's delta, `Level1Director._process`'s semantics (R2-1d). (§2, §3 rows, Risks.)
- *R2-2 (blocking, small), the shortened-active branch untested:* the real-ray row runs from `lit_from` 11.0 (warn 0 / active 1.8, lethal ≈ 11.76 → 13.56, both edges
  asserted, nothing lethal at the stop); every branch of `warm_start()` (equality, `rest < MIN_ACTIVE`, in-dissolve, the wall) is a data row with a 0.01 s sweep
  asserting no lit result has `active < MIN_ACTIVE`; the exact branch also runs on real rays (the boundary run's wall, warn 0.5).
- *R2-3, the estimate:* restated (≈ 56 game s, ≈ 3.8–4.5 s real), declared up front as an expected overrun (D) of the 3.0 s allotment, logged in DECISIONS and the
  README row; the §2.15 stop (past 4.5 s → ESCALATE) stands; scenarios run lazily inside the first test that needs them, so per-file sums show them.
- *R2-4, wiring:* the second held heavy is captured by the caller's `tweak` in spawn order; the extra entry comes from `b.wave(...).entries[0]` at `.at(256, -500)`; the
  new file reads the exit in `before_all()` before any harness; the README row notes `test_heavy_gunship.gd`'s `_probe_s` print reads ≈ 0 s.
- *R2-5, derived lengths:* the carried-over run's length is its expected lethal end + 1.25 + TICK; the from-0 run is capped at deep_space's 30.0 s and prints its lit
  exit against the measured exit.
- *R2-6:* `elapsed < warn` (strict); equality takes the middle branch.
- *Round-2 note on 9:* the no-rail legacy row's INF is a special case in the caller (`_rail_lifetime` returns 0.0 for `movement == null`).
