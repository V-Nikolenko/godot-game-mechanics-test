# t11 — Level 1's four gunships become Heavy Gunships that fight, survive the lasers and leave in time

Task `cmwafsrbi00azqs2yuwzayuk3`, epic `cmug23oo90029m52wae4clve0` (Phase 10). The design is the epic's approved plan §2.12 (with §2.4.3, §2.5, §2.15, §2.16)
and the epic review's round-2 findings N4 and N5. This file fixes the build-level choices §2.12 leaves open and the test list; it does not redesign anything. Each
departure from a §2.12 line is marked **(D)** and goes to `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` as "Phase 10, built in t11". Context: `1-context.md`.
**Revision 3** answers review rounds 1 and 2 (`4-review.md`); the answers are listed at the end.
**Revision 4** answers review round 3 and adds what measuring the lit deep_space replay showed (§5a): **no pre-approved lever keeps the deep_space heavy
alive**, because of a physics bug no lever touches. The fix that does (§5a, option A) changes the heavy's scene and adds an opt-in to the shared
`EnemyMover`, both outside the pre-approved lever list, so it waits for the owner (`NEEDS DECISION`, questions Q1 / Q2 at the end). Every other part of
this plan is independent of that answer.
**Revision 5** answers review round 4. Option A is **withdrawn**: measured with a fire column, it keeps the heavy alive only by keeping it out of the fight
(0 of 37 runs fire a battery; R4-1). §5a now recommends **option M**, one scene property (`collision_mask = 0` on the heavy root, the Carrier's approved rule)
plus lever 2: 36 of 36 runs survive and fire inside the budget (R4-2). The cause is corrected: the heavy lands on Snipers and Fighters, not on the turret group
(R4-3). Option C's rows are listed (R4-4), and so are the hand-ticked rows Q2's alternative needs (R4-5). Round 5's three fixes to the fallback answers (option C keeps an empty 3.5 s wave; its boundary run stops at
10.83 s at the earliest; Q2's alternative has its own stop) are in. Q1 / Q2 still wait for the owner.

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
- deep_space 3.5 s, by the owner's answer to Q1 (§5a): option M → `b.heavy_gunship().at(160, -500)` (lever 2; the root's `collision_mask` 0 is in the scene);
  option C → the heavy entry is removed and the 3.5 s wave stays as an empty `b.wave(3.5, [])` (review R5-1: it gates the 2.0 s and 3.0 s waves listed after it).
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
- **The idle frame is bounded (review R3-1, (D)).** The deep_space slice is CPU-bound at 16× (≈ 2.4 ms of CPU per tick against the 1.04 ms a tick has), so with
  `max_physics_steps_per_frame` at 16 × the default its idle frames spiral to the 128-tick cap, **2.13 game s**, and the lasers read seconds late. Every lit replay
  (the deep_space run, the boundary run, the carried-over run) therefore runs with `Engine.max_physics_steps_per_frame` capped at `LIT_MAX_STEPS` **16**
  (time scale and tick rate still × 16, so a step is still 1/60 game s; Godot shortens the idle step to the capped steps, so idle and physics time stay in step).
  Measured: idle ≤ 0.283 s (cap + 1 tick), every edge inside §3's bounds, the guard 0.60 < 1.25, real time within ≈ 5–10 % (a CPU-bound run is paced by its CPU
  either way). The test's `_scale_clock(max_steps)` takes the cap; the helper returns the run's largest idle delta as `"max_idle"` and the test asserts it is
  ≤ `LIT_MAX_STEPS / 60 + 2 · TICK`, so a lost cap reads as that and never as a laser bug. README rule 1 gains the reason ("a CPU-bound replay whose rows read
  idle-time edges caps the steps instead of scaling them").
- **Every ray's `d` is seeded with the load frame's delta** (review R3-5): `d = max(own frames' largest idle delta, d_L)` for every ray, because a column's early
  side is its own creation credit plus the idle clock's head start over `t`.
- **Clearance (review R3-2b).** Each physics frame the replay also records, per ship of `target_path`, the smallest horizontal gap between the world AABB of its
  root `HurtBox` shapes and every **lethal** strip whose vertical extent it overlaps (and, separately, every warning strip: printed only). Returned as
  `"clearance"` (`{ ship index: { "lethal": px, "warning": px } }`, `INF` when it never shared a lane's height with one).

### 3. New gate `tests/integration/test_level1_heavy_spawns.gd`
Pure-data rows (no physics):
- **Pin** `EXPECTED_PH10_GUNSHIPS`: `{section, trigger, offset, delay}` × 4 (deep_space 3.5 (0, −500) 0; cloud_descent 50.0 (0, −400) 0, 62.0 (−100, −400) 0, 62.0 (100, −400) 0.8),
  read through `level1_slice_replay.placed()`; each row's effective trigger equals its wave's own. Boundary: a changed delay fails the pin. With lever 2 (§5a, option M)
  the deep_space row's offset is (160, −500); `_LEGACY_ROWS` keeps the legacy (0, −500) and is compared with the pin on section, trigger and delay only. (Option C:
  §5a lists its pin.)
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
  DURATION section; the spill-over row is the real limit); stops when the heavy has left the tree **and** slice time has passed the 6.0 s row's lethal end + 1.25 +
  TICK (14.83 s; review R3-6, so the 6.0 s row's end edge is always checked; measured exits are 15.4–18.1 s, so this costs nothing in practice), and the lit exit time
  is printed against the measured exit. `max_physics_steps_per_frame` capped at 16 (§2). Records
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
- `test_no_heavy_part_or_hull_dies_under_a_lit_laser`: no covered death; the heavy was **not killed at all** and left after DISENGAGE (non-vacuity: a heavy killed
  early by stray friendly fire would have met fewer lasers); **it entered the view and reached BROADSIDE or fired a battery before DISENGAGE** (non-vacuity, review
  R4-1: a heavy that survives by never coming down into the fight passes every other clause, as option A did in 37 of 37 runs); and its smallest lethal clearance is ≥ `LaserRay._HAZARD_PAD` (24 px, read from the class, review
  R3-2b), printed with the warning clearance. **This row counts as green only after 10 consecutive green runs of the whole file on the final tree** (build steps 4
  and 6; review R3-2a): the replay is seeded but idle-frame boundaries move run to run, and with them every spawn and laser time, so one green run proves little. A
  death or a clearance under 24 px in **any** run is "a death shows" for §5's ladder. Measured death rates (§5a) make clear why.
- `test_a_heavy_held_in_a_lit_ray_is_reported_dead` (kill-detection boundary, §2.12's "held … through the 6.0 s column's lit window"): the x 1152 heavy has a covered
  death with `source == "column"` after the 6.0 s row's onset; the x 640 heavy has a covered death with `source == "wall"` (from spawn: it spawns at (640, −420),
  already 32 px into the strip, so ≈ section 3.6–4.0 s, inside the wall's lethal window; review R3-4). Both are printed.
- `test_the_replayed_lasers_are_lethal_when_the_level_makes_them` (N4; review findings 1, 7a, R2-1). Engine semantics the bounds follow (R2-1): a `SceneTreeTimer`
  created during an idle iteration is credited that iteration's **whole** delta, and an edge is observed on the next physics tick, so an onset can read up to about
  two idle frames early (the creation-frame credit, plus the idle clock's start at the load frame's delta) or late (the timer, then the increase animation, each ending
  on an idle frame), and a lethal span is short by up to one idle frame. With `d` = the ray's own `max_idle` (creation → last lethal, seeded with the load frame's
  delta, and never below the load frame's own delta, review R3-5) and `TICK` = 1/60: first lethal ∈ [expected − 2·d − TICK, expected + 2·d + 2·TICK]; (last − first
  lethal) ∈ [lit active − d − 2·TICK, lit active + d + TICK]. A guard per checked edge asserts the late tolerance `2·d + 2·TICK < 1.25 s` (half of N4's 2.5 s shift),
  so the row still catches that bug and a hiccup elsewhere in the run cannot fail it; with the step cap (§2) it measures ≈ 0.6 s. The run's largest idle delta is
  asserted ≤ `LIT_MAX_STEPS / 60 + 2 · TICK` first. Checked edges: only those whose expected time + 1.25 s precedes the run's stop, and the wall and the 6.0 s row
  (both edges: the run lasts past 14.83 s, §3) are asserted to be among them. Expected onsets: the wall = its rays' lit warn + increase (3.56 s section in both runs), each column row = `row.time + column_lethal_offset()`. In the
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
(world x 960; never −160); (3) `assault_preferred_range` 480; (4) `assault_orbit_angular_speed` halved. **Order changed (review R3-4): lever (2) comes first**, because
at the shipped offset the heavy spawns at (640, −420) (the camera pans 220 px toward the stub: `wave_manager.gd:194`, `arena_camera.gd:122-146`), its hull already
32 px into the wall's strip, so it dies the moment the wall turns lethal (measured 3.65–4.03 s, every run) and no avoidance lever can move a hull that starts inside.
Deadline: `exit_speed` up to 360 / `exit_acceleration` up to 320 (then re-run the view-grid comparison, `ph10_exit_keys.gd` header), then `engage_seconds` down to 7.0.
None fits → stop and ask the owner with the replay log and the figures. **For the lit replay none fits (measured, §5a)**, so the deep_space heavy is built to the owner's
answer to Q1: option M (lever 2 + the root's `collision_mask` 0; levers 1, 3, 4 unused) or option C. Under option M a death or a sub-floor clearance in any of the 10
runs is not answered with levers 1, 3 or 4 (§5a measured each of them lowering the fire rate or the clearance): it stops the build with the log (`Result: ESCALATE`).

### 5a. What the levers do, measured (revisions 4 and 5) — and the fix that needs the owner
Throwaway workers outside the repo (`/tmp/t11_meas/` for revision 4; the round-4 reviewer's `/tmp/t11_r4/`, which adds a **fire** column, for revision 5) build the
§2 world exactly: `HARNESS.assault()`, the stub at +(0, 250), brains seeded `5171 + index`, a real `WaveManager`, the real wall and the director's real columns on an
idle clock, 16× with the steps capped at 16. Each replays deep_space from 0.0 s until the heavy left or died, many times per configuration (each run's idle-frame
boundaries differ, so each is a different sample). "Clearance" is the smallest horizontal gap between the heavy's hurtbox AABB and a lethal strip it shares a height
with; "fires" is a battery mount entering `FIRE` while the budget runs. The max idle delta was 0.276–0.283 s in every run (R3-1's bound, 0.30 s, holds).

| Deep_space from 0, lever 2 (`.at(160, -500)`) plus | Runs | Laser deaths | Fires a battery in budget | Min lethal clearance (survivors) | Exit |
|---|---|---|---|---|---|
| — (shipped offset `.at(0, -500)`, no lever 2) | 4 + reviewers' | every run (the wall's 588 / 644 rays at 3.65–4.03 s: it spawns at (640, −420), inside the strip) | — | — | — |
| nothing (the shipped body: GROUNDED, layer 1 / mask 1) | 12 (r4) + 9 (r3) | 8 of 12, 7 of 9 (the wall's 644 ray at 6.68–7.65 s, the 640 / 1152 columns) | 4 of 4 survivors | 6.3 px | 16.0–17.4 s |
| levers 1, 1 + 3 + 4 (revision 4) | 16 | 16 | not measured | — | — |
| `motion_mode` FLOATING | 12 | 0 | 9 of 12 | **1.5 and 9.6 px** in two runs (under the 24 px floor) | 16.0–17.1 s |
| FLOATING + lever 1 (margin 110) | 12 | 2 (1152 column at 13.90 s; 896 column at 17.98 s in DISENGAGE) | 5 of 12 | 17.1 px | 15.9–16.8 s |
| option A (FLOATING + hull term 92, revision 4's pick) | 25 | 0 | **0 of 25** | 86.7–130 px | 14.3–16.9 s |
| option A + lever 1 | 12 | 0 | **0 of 12** | 64.0–129.7 px | 14.9–17.3 s |
| **option M: root `collision_mask = 0`** | **36** (30 r4 + 6 this run) | **0** | **36 of 36** (section 9.15–9.42 s, 3.33–3.35 s of budget left, in BROADSIDE) | **33.1–66.4 px** | 15.8–16.2 s |

**Root cause of the wall deaths (corrected, review R4-3; not a tuning problem).** The heavy's root (`heavy_gunship.tscn:82`) is a `CharacterBody2D` with no
`collision_layer` / `collision_mask` / `motion_mode` line: layer 1, mask 1, `MOTION_MODE_GROUNDED`. On its APPROACH from (960, −420) its body meets other ships of the
deep_space waves. In per-tick traces of four lever-2 runs every floor contact was a **Sniper or a Fighter** (normal within the floor angle of up, `is_on_floor()`
true, `get_platform_velocity()` = that ship's velocity, e.g. (−228, 183) px/s); none was a `DefenseTurret`, which moves only by `AssaultDrift` (0, speed)
(`assault_drift.gd:27-34`). A grounded body takes a floor contact's collider as its platform and, by Godot's `platform_on_leave` default, adds the platform's velocity
when it slides off, so the heavy is thrown sideways into the wall's lane (x 0–672, lethal until 7.56 s). Revision 4 blamed the turret group and the (−251, 152)
velocity on it; that attribution was wrong, the mechanism was right. No lever touches it. Revision 4's "second cause" (a laser wall's 52 px segment footprint,
`Steering._segment_danger()`) is mostly the same body contacts: without them the shipped footprint keeps ≥ 33 px of clearance (option M row).

**Why option A is withdrawn (review R4-1).** With the hull term a column's footprint is 144 px plus the skirt on each side, so the lane between the 6.0 s row's 640 and
1152 columns (registered 6.0–13.56 s, the heavy's whole budget) is a narrow channel. The heavy's APPROACH point (`target + away · held_range()`,
`heavy_gunship_brain.gd:505`, ≈ (765, 209)) sits inside the widened 640 footprint, BROADSIDE starts only within `range_tolerance` of the held range (:496), and the
near-tie between the up and down slots goes to the previous heading, so it climbs. It spends its whole budget above the view and never fires (0 of 37 runs): it
survives by not fighting, which fails `test_every_placed_heavy_fires_a_battery_inside_its_budget` and §5's rule that a lever is legal only while the attack rows stay
green. **FLOATING alone** survives 12 of 12 but is under the clearance floor in 2 of 12 runs and never fires in 3 of 12: it would fail the 10-consecutive-runs rule.

**Option M — recommended (needs the owner, Q1).** Two changes, one of them pre-approved:
- (i) `heavy_gunship.tscn` root `collision_mask = 0`: the Carrier's approved rule (epic plan :449, "mask 0 (ploughs through, the station's rule)"; `carrier.tscn:87`;
  `space_station.tscn:65`). One property in one scene: no `ShipConfig` field, no `EnemyMover` / `Steering` change, no `HAZARD_PROFILES` edit, nothing for any other
  enemy. `collision_layer` stays as shipped (1), so other ships (mask 1) still bump into the heavy. With no body contact of its own, its motion mode is moot here.
- (ii) Lever 2, `.at(160, -500)` (pre-approved; world x 960). Levers 1, 3 and 4 are not used.
- **Trade-offs the owner accepts:** a (D) from the epic plan §2.4.1's body spec "mask ENVIRONMENT" (`CollisionLayers.ENVIRONMENT` = 1, which is what t4 shipped; §2.4.1's
  "layer ENEMY_HITBOX" was never applied and is left as shipped). Every Heavy Gunship's body (level 1, the hub, level 2's railed one, which has physics off on its
  rail anyway) stops colliding with anything: it no longer stops on other ships, asteroids or wrecks (wrecks are layer 1 / mask 0, `wreck_large.tscn:13-15`). It still
  steers round lasers, wrecks, wells and mines through `Hazards` (`EnemyMover` context avoidance), its contact damage is the `ContactHitBox` area (unchanged), and
  every hurtbox / hitbox (areas) is untouched.
- **Its rows (build step 3a):** in `test_heavy_gunship.gd`, failing first: the shipped root's `collision_mask` is 0 (read from the scene) and, on real physics, a heavy
  driven through a layer-1 `StaticBody2D` box by `move_and_slide()` ends on the far side with no slide collision (a control body with mask 1 is stopped by it, so the
  row can fail). Then the property; then every file that names the heavy runs green alone: `test_heavy_gunship.gd`, `test_enemy_dual_mode.gd`, `test_support_ship.gd`
  (the ward interposes beside the heavy), `test_sector_hub_patrol.gd`, `test_base_enemy.gd`, `test_station_reinforcements.gd`, the four roster gates
  (`test_enemy_contact_damage.gd`, `test_contact_hitbox_geometry.gd`, `test_enemy_hurtbox_geometry.gd`, `test_config_instance_isolation.gd`) and
  `test_collision_layer_names.gd` (mask 0 has no bits).
- Logged in DECISIONS as a deviation from §2.12's lever list and from §2.4.1's body spec, with the table above.

**Option C — remove the deep_space heavy** (the three Cloud Descent heavies stay). What the player loses: the level's first heavy; no heavy appears before Cloud
Descent (50 s). What the owner accepts: the lit acceptance criterion ("zero heavy parts or hulls killed by the wall or a column") becomes **vacuous** — no placed
heavy meets a lit laser, which the static "which heavies meet lasers" row proves. Its rows:
- Director: the deep_space 3.5 s heavy entry (the wave's only entry, `level_1_director.gd:347-350`) is removed, and the wave **stays in place as an empty
  `b.wave(3.5, [])`** (review R5-1): `WaveManager` triggers waves strictly in list order, the 3.5 s wave is listed before the 2.0 s (five fighters) and 3.0 s (drone trio +
  turret group) waves, and deleting it would move both earlier and shift every later wave index (`test_level1_fighter_fire_density.gd:365-372` asserts the 2.0 s wave
  fires at 3.5 s). An empty wave registers and triggers like any other (`wave_manager.gd:56-77`), so every other wave's index and effective trigger is unchanged: the
  existing specialist / fighter / drone pins and the fire-density wave-order schedule row must stay green unedited (the deep_space wave-order quirk).
- Pin: `EXPECTED_PH10_GUNSHIPS` has the three cloud_descent rows; a separate row asserts no heavy is placed outside cloud_descent. `_LEGACY_ROWS` keeps the four
  legacy rows (frozen data) and is compared with the pin on the three cloud_descent rows only.
- Count: `_LEGACY_PEAK_HEAVIES` stays `{deep_space: 1, cloud_descent: 3}` (frozen; deep_space's live peak is 0). Boundaries: cloud_descent's one extra heavy at its
  peak, as specified; for deep_space **two** inserted heavies fail (one is legal against the frozen 1, and the row says so); a heavy in planet_approach fails.
- Spill-over: no heavy sits in a DURATION section, so the live row asserts its set is empty; the `engage_seconds` 20 boundary runs on a heavy inserted in list order at
  deep_space 3.5 s, which is flagged.
- `test_heavy_gunship.gd::test_the_deep_space_heavy_fires_a_battery_inside_its_budget` (asserts exactly one deep_space heavy, :1007-1031) becomes
  `test_every_cloud_descent_heavy_fires_a_battery_inside_its_budget`: the same hand-ticked shape, once per cloud_descent spawn (three rows, each from its real spawn
  point against the stub).
- Replays: the deep_space lit run and `test_no_heavy_part_or_hull_dies_under_a_lit_laser` are dropped. The kill-detection boundary run stays, with its two held
  heavies appended to the slice's copy of the now-empty 3.5 s wave (as §3 appends its extra heavy today). **Under option C the boundary run stops at max(both covered
  deaths, 10.83 s)** (review R5-2: the 6.0 s row's onset 9.56 + 1.25 + TICK; its second death lands at ≈ 9.6–9.9 s, before that edge counts as checked; ≈ +0.1 s real),
  cap 14.06 unchanged. Timing edges: the boundary run checks the wall's onset (3.56) and end (7.56) and the 6.0 s row's onset (9.56); the carried-over run checks the 6.0 s row's relit onset (11.76) and its real end (13.56). The "asserted among the
  checked edges" list moves to those two runs. Attack-in-budget and fire density: cloud_descent only.
- Cost: the deep_space lit run (≈ 3.0–3.5 s) goes; the file costs ≈ 3.8–4.1 s, under the 4.5 s (1.5×) line, so **Q2 does not arise under option C**.

**Not offered:** option A (never fires), FLOATING alone or with lever 1 (under the floor / never fires in some runs), and keeping the shipped row while accepting laser
deaths (it contradicts an acceptance criterion; the heavy dies in the wall in every run).

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
3. Helper: `light_lasers`, the idle-clock column firing, `warm_start()`, timing statics, deaths, clearance, `max_idle` and per-ray lethal windows; the step cap in
   the test's clock helper; the warm-start data rows, the lasers-off and carried-over rows.
3a. **Q1 as the owner answered it** (§5a; only after the answer). *Option M:* first its failing rows in `test_heavy_gunship.gd` (the shipped root's
   `collision_mask` is 0; a heavy driven through a layer-1 box passes, a mask-1 control is stopped), then the property; then every file §5a lists for it runs green
   alone before moving on. *Option C:* §5a's rows for it (the director's heavy entry removed, its wave kept empty, pin / count / spill-over / `test_heavy_gunship.gd` row re-pointed, the empty 3.5 s wave the boundary run
   appends to); the existing level-1 pins and the wave-order schedule row green unedited.
4. **The deep_space lit run** and its rows (option M: lever 2 + mask 0; option C: no lit run, go to step 5); then **10 consecutive green runs of the file** (R3-2a),
   printing each run's clearance and first battery FIRE; any death, sub-floor clearance or run without a FIRE → stop and report (`Result: ESCALATE`; §5 / §5a: levers
   1, 3, 4 were measured and do not help, nothing else is pre-approved).
5. The boundary run, the cloud_descent run and their rows; the deadline boundaries; `test_heavy_gunship.gd`'s live window.
6. Every level-1 gate and replay file run alone (specialist, fighter spawns, fire density, drone spawns / exit, fighter exit, specialist exit, Ph8 / Ph9 attacks, laser
   columns, heavy gunship, and with option M the files §5a lists for it); `scripts/check-test-leaks.sh`; `test_level1_heavy_spawns.gd` 10
   consecutive green runs again on the final tree.
7. Gate time: two `scripts/gate-time.sh` runs before (done twice: 205.472 / 205.748 s at `7225e63`, and 205.627 / 205.940 s, mean **205.78**, at `8df0d59`) and
   after; the new / changed files' own time; README row; output size.
8. DECISIONS (t11 notes, levers, measured exit / legacy figures / fire density / deviations), CLAUDE.md one paragraph, the heavy `ENEMY.md` and director header lines.
9. `bash /agent/verify.sh` green.

## Test plan
As §3 and §4. Boundaries: changed delay (pin), `.move()` put back (no rail), one extra heavy at the peak (count), a heavy in planet_approach (count), 20 s budget (spill-over),
a heavy moved to 34.0 s (which heavies meet lasers), the two held heavies (kill detection: a wall kill and a column kill), the warm-start data rows (equality, rest <
MIN_ACTIVE, in-dissolve, the sweep) and the carried-over real-ray row (warm start), lasers-off (helper default), the derived-tolerance guard (timing), config-derived (a)
± 0.05, the open pod (b), the step-cap assertion, the clearance floor (24 px) and the "entered the view and reached BROADSIDE or fired" non-vacuity clause on the lit
run. Option M adds (`test_heavy_gunship.gd`): the shipped root's `collision_mask` is 0, and a heavy driven by `move_and_slide()` through a layer-1 box passes it while a
mask-1 control is stopped. Option C replaces the deep_space rows as §5a lists (two inserted heavies for the deep_space count boundary, an inserted heavy for the
spill-over boundary, the cloud_descent hand-ticked fire rows).

## Risks
- **The deep_space heavy dies in the lasers with every pre-approved lever (measured, §5a).** At the shipped offset it dies in the wall every run; with lever 2 alone 8
  of 12 runs lose it, and levers 1, 3 and 4 make it worse. Only option M or C answers it, and each needs the owner (Q1). With option M, 0 of 36 runs lost it and 36 of
  36 fired inside the budget; its smallest clearance, 33.1 px, is 9 px above the 24 px floor, so the 10-consecutive-runs rule (R3-2a) and the floor are what keep a
  marginal pass from being committed. If a run under option M ever falls under the floor, the build stops (`Result: ESCALATE`) rather than widening anything.
- **Option M changes how every Heavy Gunship's body meets the world** (no body collision of its own anywhere: it can overlap other ships, asteroids and wrecks; its
  hurtbox, contact hitbox, hazard avoidance and contact damage are unchanged). Hand-ticked rows that relied on the heavy being stopped by a body would show it; §5a
  lists every file that names the heavy, and step 3a runs each alone before the lit run is built.
- **Gate time — a measured overrun, (D), decided before building (review R3-3, Q2).** The round-3 reviewer measured the scenarios: the deep_space lit run ≈ 3.0–3.5 s
  real to the heavy's exit (CPU-bound), the cloud run ≈ 2.5–2.8 s (tick-paced, 23.85 game s), the boundary run ≈ 1 s, the carried-over run ≈ 0.3 s: **≈ 6.5–7.5 s
  against the 3.0 s allotment and the 4.5 s (1.5×) line**. Nothing in the design can be cut to reach 4.5 s without dropping an acceptance criterion: the two runs that
  carry the acceptance rows (the lit deep_space run, the Cloud Descent attack run) alone are ≈ 5.5–6.3 s. The headroom: suite 205.78 s (two-run mean at `8df0d59`) →
  ≈ 213 s; the phase then ends ≈ 215.5 s after t12's 2.5 s, against §2.15's 234.5 s phase budget, the 237 s escalation line and the 240 s ceiling (the README's
  "phase ends ≤ 213.6 s" is passed by ≈ 2 s). Proposed (Q2): accept it as a logged deviation, the t4 precedent ("over, logged, absorbed by t1's surplus"), with the
  stop moved to **the new / changed files over 9.0 s (3× the allotment) or the two-run suite mean past 237 s**. Round 4 re-measured the scenarios (lit run 3.9–4.1 s
  real with engine start and settle, cloud run 3.25 s) and confirmed the estimate. **Q2's alternative, named (review R4-5):** drop the Cloud Descent replay and prove
  the three cloud heavies' attack-in-budget by hand-ticked rows, `test_heavy_gunship.gd::test_every_cloud_descent_heavy_fires_a_battery_inside_its_budget` (the
  :1007-1031 shape once per cloud spawn, from each one's real spawn point against the stub, no traffic), with the cloud fire-density report computed from those rows'
  round times shifted to each spawn time. It saves ≈ 2.5–2.8 s but still leaves the task at ≈ 4.8–5.3 s, over the 4.5 s line, and the attack proof loses the traffic
  it really meets (round 4 measured all three firing in traffic with 4.3–4.8 s of budget left). If the owner picks it, it is the same kind of logged deviation (D)
  with its own stop: **the task's new / changed files over 6.0 s (2× the allotment) or the two-run suite mean past 237 s** (review R5-3). **Under option C, Q2 does not arise** (≈ 3.8–4.1 s, §5a). Mitigations kept (none cuts an assertion): the probe is a
  memo hit; the boundary run stops on its two covered deaths (under option C not before 10.83 s, §5a), the deep_space run at max(heavy gone, 14.83 s), the cloud run when its last heavy enters DISENGAGE; the
  warm-start branches are data rows. **Accounting (review 5):** the exit probe (≈ 2.9 s) moves from
  `test_heavy_gunship.gd`'s `before_all()` to `test_engagement_deadline.gd`'s `before_all()` (that file sorts first), outside any testcase in both; `test_heavy_gunship.gd`'s
  `_probe_s` print then reads ≈ 0 s (R2-4c; the README row says so). The task is judged by the two-run suite mean against 205.78 s and by its own files' summed
  testcase time net of that move.
- **16× laser timing** moves a lethal edge by up to two idle frames either way; the tolerances are derived per ray from the idle deltas around it (README rule 1),
  with a guard at 1.25 s (half of N4's shift). Uncapped, the CPU-bound deep_space slice reaches 2.13 s frames and fails it on every ray (R3-1); with the steps capped
  at 16 the frames stay ≤ 0.283 s and the guard reads ≈ 0.6 s. A lower cap (8) is the fallback if a slower machine ever pushes `d` toward the guard, never a wider guard.
- **Stray friendly fire** (a corvette rocket crossing the heavy) could kill a part without a laser: reported as an uncovered death, and the non-vacuity assertion would fail
  only if the hull itself died; investigate then, never widen.
- **Own `SceneTreeTimer`s:** a ray freed with the world leaves its warn / active timer to run out in later tests — not a leak at exit; `check-test-leaks.sh` confirms.

## Out of scope
The Carrier's level-1 placement, its column math and the carrier-child half of the spill-over row (t12); docs beyond the lines named in step 8 (t13); a gated heavy
fire-density ceiling (later phase, §2.12); level 2's railed heavy (Ph15). The same platform-velocity launch can hit **any** AI enemy (every root body but the Carrier's
and the station's is layer 1 / mask 1, GROUNDED): option M fixes the heavy only; whether every top-down enemy body should be `MOTION_MODE_FLOATING` is a project-wide
follow-up for the owner, not this task.

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

## Response to review round 3 (`4-review.md`, revision 4)
- *R3-1 (blocking), CPU-bound idle frames:* every lit replay caps `Engine.max_physics_steps_per_frame` at 16 (time scale and tick rate stay × 16), the helper returns
  the run's largest idle delta and the test asserts it ≤ 16/60 + 2·TICK before any edge row; marked (D), and README rule 1 gains the reason (§2, §3, Risks).
- *R3-2 (blocking, small), the no-death row is a probability:* it counts as green only after 10 consecutive green runs of the file at build steps 4 and 6; a death or a
  clearance under 24 px (`LaserRay._HAZARD_PAD`) in any run is "a death shows"; the replay records and prints each heavy's lethal and warning clearance and the row
  asserts the floor (§2, §3). The measured death rates are in §5a: every pre-approved lever combination loses the heavy in 6–8 of 8 runs, so the lever ladder alone
  cannot pass; the root cause (a platform-velocity launch off the turret group) and the fix that does pass (option A, 0 of 16, min clearance 120.7 px) are in §5a and
  wait for the owner (Q1).
- *R3-3 (blocking, small), cost:* restated from your measurements (≈ 6.5–7.5 s); nothing reaches 4.5 s without dropping an acceptance criterion, so the overrun is
  pre-declared as a (D) with the headroom figures and the stop moved to 3× the allotment / 237 s, for the owner to confirm (Q2) (Risks).
- *R3-4:* lever 2 first, with the reason (the shipped offset spawns inside the wall strip); the boundary run's x 640 death is "from spawn, ≈ 3.6–4.0 s" (§3, §5).
- *R3-5:* every ray's `d` = max(own, d_L) (§2, §3). *R3-6:* the from-0 run lasts to max(heavy gone, 14.83 s), so the 6.0 s row's both edges are always checked (§3).

## Response to review round 4 (`4-review.md`, revision 5)
- *R4-1 (blocking), option A never fights:* withdrawn. §5a's table now has fire and exit columns for every candidate (0 of 37 option-A runs fire); the reason (its
  APPROACH point inside the widened 640 footprint, BROADSIDE never reached) is in §5a. The no-death row gains a self-contained non-vacuity clause: the heavy entered
  the view and reached BROADSIDE or fired a battery before DISENGAGE (§3).
- *R4-2 (blocking), the simpler fix:* option M (root `collision_mask = 0`, the Carrier's rule, + lever 2) is the recommended answer to Q1, with its trade-offs, its rows
  and the files it must keep green (§5a, step 3a). Re-measured in this run: 6 of 6 survive and fire (3.33–3.35 s of budget left), min clearance 33.1 px; with round 4's
  30, 36 of 36.
- *R4-3 (blocking, small), the wrong body:* corrected in §5a (Snipers and Fighters; a `DefenseTurret` only drifts down); the DECISIONS line will carry the corrected text.
- *R4-4, option C:* its rows are listed in §5a (director, pin, count with a two-heavy deep_space boundary, spill-over on an inserted heavy, the re-pointed
  `test_heavy_gunship.gd` row, the boundary run's own wave, which runs check which edges, cost) and the vacuous lit criterion is stated for the owner. Option D is dropped.
- *R4-5, Q2's alternative:* the replacing rows are named (Risks, gate time), with what they save and what they lose; under option C the question does not arise.

## Owner questions (asked with `NEEDS DECISION`)
- **Q1 — the deep_space heavy and the lasers:** option M (recommended: the heavy's root body `collision_mask = 0`, the Carrier's rule, + lever 2; 36 of 36 runs survive
  and fire) or option C (remove the deep_space heavy; the lit criterion becomes vacuous, the gate-time question goes away).
- **Q2 — gate time (only under option M):** accept ≈ 6.5–7.5 s against the 3.0 s allotment as a logged deviation with the stop at 9.0 s of the task's own files / a
  237 s two-run suite mean (recommended; suite ≈ 213 s after), or replace the Cloud Descent replay by hand-ticked rows (≈ 4.8–5.3 s, still over the 4.5 s line, so also a
  logged deviation, with its stop at 6.0 s / 237 s; the three heavies' attack proof loses its traffic).

## Response to review round 5 (`4-review.md`, revision 5)
- *R5-1 (blocking for option C):* under C the 3.5 s wave stays as an empty `b.wave(3.5, [])` (it gates the 2.0 s and 3.0 s waves listed after it; deleting it would
  move them and every later index); the boundary run appends its held heavies to it (§1, §5a).
- *R5-2:* under C the boundary run stops at max(both covered deaths, 10.83 s), so the 6.0 s row's onset is a checked edge (§5a).
- *R5-3:* Q2's alternative is a logged deviation with its own stop, the task's files over 6.0 s or the two-run mean past 237 s (Risks, Q2).
- *Nit:* step 9's whole gate covers the three heavy files the step-3a list omits (`test_explosion_effect_placement.gd`, `test_ph10_sprites.gd`,
  `test_entity_sprite_transparency.gd`; none reads the body mask).

## As built (2026-11-18)
The owner answered Q1 = option M and Q2 = accept the overrun (stop at the task's files over 9.0 s or the two-run suite mean past 237 s). Built as revision 5 with
those answers; no lever beyond lever 2 and no deadline lever was used. Two build-level details the plan did not name: the helper's `run()` drops its `tweak`
before returning (a tweak that captures its own replay, to read the new `slice_time()`, otherwise forms a RefCounted cycle that leaks at exit), and the
"gone" time of a replayed heavy is recorded only when the ship queues itself for deletion (its exit or its death), never when the world is freed at the stop.
Measured figures, the ten-run record and the gate time are in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → "Phase 10, built in t11".
