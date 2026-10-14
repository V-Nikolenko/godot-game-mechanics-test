VERDICT: CHANGES_REQUESTED

# Review round 1: t22 plan (Revision 1)

Reviewed `3-plan.md` and `1-context.md` against the code. I also read the epic plan (§2.6.2 expiry table, §2.9.2–§2.9.4,
§4 t22 rows, review N2) and the t21 plan, and re-ran the ram exit measurement myself with a throwaway SceneTree script
in `/tmp`. That script used the same tick-and-integrate loop as `specialist_exit_probe.gd::disengage_seconds`, on the
real `ram_corvette.tscn` in `HARNESS.assault()`. It has been deleted, and nothing in the repo was touched.

The plan gets most things right:
- N2 is resolved: replaying from 0.0 s spawns all 9 snipers and 6 rams.
- The shipped config really does fail the 73.2 s row. I reproduced the view-grid curved exit of **6.35 s at
  `exit_speed` 500** and **3.72 s at 560**.
- The expiry-table reasoning matches `ram_corvette_brain.gd`.
- The count-gate and pin changes follow the Ph3 t17 precedent.

One problem blocks approval. The plan has found that the ram's deadline row is not an upper bound, and it gates on
that row anyway. The correct figure is only printed.

## Blocking

### B1. The ram row's "measured nearest-edge bound" misses starts the ram reaches in normal play, and the plan knows it

Files checked:
- `tests/helpers/specialist_exit_probe.gd:24-30`: the grid is x ±560 × y ±320 around (640, 360), which is the
  1280×720 screen.
- `assault/scenes/systems/assault_corridor_constraint.gd:84-89` and `arena_camera.gd:88-112`: the corridor that holds
  an AI ram in APPROACH, LINE_UP, WIND_UP and WIDE_TURN is the 1480×1480 visible rect, x −100…1380 and y −380…1100.
  The world rect is that rect grown by 64 px.
- `ram_corvette_brain.gd:256-263, 504-510, 520-561`: a curved exit follows an APPROACH, LINE_UP or WIDE_TURN expiry
  immediately, or follows a STAGGER.

So a ram can begin its curved DISENGAGE anywhere in the corridor. Examples: a WIDE_TURN after a charge that
overshot toward a corner, or the end of a STAGGER near a player who is flying high in the corridor. That is the normal
play area, not an exotic band. Plan §3 calls these starts "outside the view (corridor soft/hard band)", which
undersells how ordinary they are.

My measurement at `exit_speed` 560: a 40 px grid over ±800, 16 headings, speeds 700, 280, 10 and 2 px/s gives a
slowest exit of **5.77 s**, from offset (−480, −480) heading right at 10 px/s. That is world (160, −120), inside the
corridor. The view grid gives 3.72 s. The 404-start grid therefore under-reports this ship's curved exit by about 2 s,
which disproves t21's risk note "the grid includes the starts known to be slowest" for the ram (t21 `3-plan.md:137`).

The consequences:
- **Gate as planned** (task formula, view-grid term): −2.8 + 4.5 + 2.133 + max(4.06, 3.72) + 0.5 = **8.39**. Passes.
- **Same formula with a term that bounds realisable starts**: −2.8 + 4.5 + 2.133 + 5.77 + 0.5 = **10.10**. Fails.
- **The plan's own "realisable" split**, max(2.133 + 4.06, 1.05 + 0.033 + 5.77): about **9.05**. It is correct
  structurally (I checked the expiry table: after CHARGE the exit is straight, and a curved exit after a deferral
  needs WIND_UP then STAGGER, at most 1.05 s). But under the plan it is only printed.

The asserted number is smaller than the real worst case. A future retune that lengthens the corridor-wide exit could
push the real worst past 10 s while the gate stays green: `acceleration` sets the curved turn rate
(`ram_corvette_brain.gd:557-559`), and `stagger_seconds` also matters. That is exactly the failure mode the epic's
"measured, never straight-line" rule exists to prevent (epic §2.9.2, review finding 13). This is a test that cannot
catch a regression it is meant to catch.

**Required.** Choose one and state it in the plan:
1. **(Preferred, in scope.)** Measure the ram's curved exit over starts that cover the region it can actually be in
   when it disengages (the corridor plus the 64 px band to the world rect). Add this as a **separate** start set or
   probe entry so that t21's 404-start grid and its count gates do not change. Use it in the task's formula.
   - That formula then fails at 560 (about 10.1), so apply the task's second pre-approved lever: ram
     `engage_seconds` 4.0. That gives about 9.6 (margin about 0.4 s).
   - Re-run the t17 attack-in-budget row to prove the lever is legal. Today's worst WIND_UP is 3.07 s, so a LINE_UP
     must start by 3.45 s to pass the attack gate (`can_attack()`, `ram_corvette_brain.gd:241-242`). This is expected
     to hold but must be shown.
   - Keep printing the realisable split as a record.
   - The grid has to be affordable. My dense grid cost 2m19s, which is far too slow. A sensible design: positions
     every ~100 px over the corridor, headings pointing away from each start's nearest edge (±45°), and speeds 10 px/s
     and `max(charge, exposed_charge)`. Measure its cost and record it.
2. Assert the realisable split, `engage + max(wind_up + charge_max_time + straight, wind_up + stagger + curved_corridor)`,
   as the gate. That changes the deadline formula the task fixed, so per the plan's own Out-of-scope list it needs an
   owner decision (`Result: ESCALATE`). Do not just do it.

Either way, the forced-LINE_UP boundary's bound (`engage_seconds + measured curved exit`) should use the same
corridor-wide figure.

## Non-blocking

- **N1. The sniper rows use the same narrow grid.** `test_engagement_deadline.gd` gets the sniper exit from the
  404-start probe. With about 6 s of slack on the 63.2 s row this is harmless, but the plan should say so explicitly,
  or use the corridor-wide set for consistency. The t21 count gates (`test_level1_specialist_spawns.gd:425-447`)
  inherit the same under-report for the ram (about 1.7 s per life). Record it as a follow-up in DECISIONS; do not fix
  it silently here.
- **N2. The static memo** (`specialist_exit_probe.gd`):
  - It is safe as described. The values are plain Variants, so there is no ObjectDB leak at exit. The ships are fresh
    instances of privatised configs, and nothing in the suite may write to a shared `.tres`.
  - Return a `duplicate()` so that one caller cannot mutate the dictionary another caller reads.
  - The key must include the start set once B1 adds a second one.
  - Note in the header that the memo lives for the whole process, so results are order-independent but computed by
    whichever file runs first.
  - It saves only about 1–3 s. If it adds complexity, a per-file instance memo (the t21 shape) is acceptable.
- **N3. The 8× replay is sound in principle.** `test_bomber.gd:667` and `test_enemy_ordnance.gd:31` set the 8×
  precedent, and the physics step stays 1/60 game-second. The plan omits two documented traps:
  - **Waiting for idle frames.** `tests/README.md:756-760` and `test_level1_fighter_fire_density.gd::_start` wait three
    *idle* frames after scaling the clock and before `load_section()`, so wave 0 does not trigger after a catch-up
    burst. Do the same.
  - **The WM-clock tolerance.** "`waves_complete` fires on the 76.0 s tick" is checked on `WaveManager._time_elapsed`,
    which advances in idle-delta steps (`wave_manager.gd:56-64`). At 8× one idle delta can exceed the 0.1 s that
    `test_level1_fighter_exit.gd:215` uses at 1×. Either size the tolerance from the measured largest idle delta or
    reuse fire-density's `_TRIGGER_TOLERANCE` logic, and state the tolerance in the plan.
- **N4. Suite time.** The current suite is about 240 s against a harness limit of about 300 s. On top of that come the
  11 s replay, the bomber/ram/sniper probes in the deadline file, and B1's corridor grid. The plan should commit to
  checking `real` time from `bash /agent/verify.sh` before committing, and to a fallback if it goes over (for example,
  starting the replay at the first specialist wave, 11.0 s, which still spawns all 9 + 6).
- **N5. The bomber boundary.** The task says "a bomber in any ENEMIES_CLEARED section fails". station_assault has a
  180 s net and cannot fail. Following the Gatling precedent (assert cloud_descent, report station_assault;
  `test_engagement_deadline.gd:398-417`) is right, but the plan should name this as a deliberate reading of the task.
- **N6. Duplicated terms.** The sniper/ram/bomber tail terms (`_TICK_SLACK`, deferrals, `max(straight, measured)`)
  would exist twice: once in `test_level1_specialist_spawns.gd::_ai_lives` and again in `test_engagement_deadline.gd`.
  Consider one shared helper (for example in `specialist_exit_probe.gd` or a sibling) so the two gates cannot drift.
- **N7. Retiring the frozen-constant boundary is acceptable.** It matches Ph3 t17 (`test_level1_fighter_spawns.gd:412`
  `_RAIL_SECTIONS = []`), and the "neither live-checked nor gated" assertion keeps the constant guarded. The cost is
  that `_rail_lifetime`'s sampling branch is no longer exercised at all; say so in the header.
- **N8. An optional, cheap boundary.** Add a check that the 73.2 s ram row fails with the pre-lever config. This would
  record in the gate itself why each lever was needed.

## Verified as stated

- 9 sniper lines and 6 ram lines in `_build_section_3` (`level_1_director.gd:804-985`). The last wave is 76.0 s with
  drones only, and the timeout is 10 s.
- Every ram row figure at 560: straight term 2274/560 = 4.06 s, tail 11.19 s, 73.2 s row 8.39 s, 76.0 + 1.2 boundary
  12.39 s.
- `exit_speed` is read only in DISENGAGE (`ram_corvette_brain.gd:525, 555-561`), so lever 1 cannot move the t17
  attack row.
- No test pins ram `exit_speed` or `engage_seconds` to their shipped values (`test_ram_corvette.gd:673-697`).
- The t17 seam `budget.seconds -= remaining()` exists and is used at `test_ram_corvette.gd:1035, 1181, 1225, 1237`.
- The cloud_descent count gate passes comfortably. By hand I get a peak of about 7 at 38.6 s against a limit of 10.

---

# Review round 2: Revision 2

VERDICT: APPROVED

I re-read Revision 2 against the code. B1 is resolved, and every non-blocking finding is either applied or declined
with a reason I accept.

## B1: resolved

- **The corridor start set is shaped correctly.** It covers ±720 in 80 px steps (19 × 19). Each start heads away from
  its tie-broken nearest world-rect edge, and ±45° from that.
  - Its edge order is the brain's own: left, right, top, bottom, against `projectile_world_rect`
    (`ram_corvette_brain.gd:528-542`). That rect is ±804 around (640, 360) (`arena_camera.gd:88-112`).
  - Its speeds are `max(charge, exposed_charge)` and 10 px/s.
  - My round-1 reference grid ran to ±800 in 40 px steps with 16 headings and four speeds. Its worst start was
    (−480, −480), heading away from the tie-broken left edge at 10 px/s, which falls inside this set. The
    coordinator's 5.767 s matches my 5.77 s.
- **t21 is unaffected.** `worst_disengage()` keeps `starts()` as its default, so t21's gates and the run-count check
  in `test_measured_exits_are_real` (`test_level1_specialist_spawns.gd:482-494`) do not move.
- **The new sanity case can fail.** `test_the_corridor_start_set_finds_a_slower_ram_exit_than_the_view_grid` asserts
  the corridor figure is at least the view-grid figure, that no run hits the cap, and that every start lies inside the
  world rect.
- **The arithmetic checks out:**
  - Tail: 4.0 + (0.65 + 1.45 + 2/60) + max(2274 / 560 = 4.06, 5.77) + 0.5 = 12.40.
  - 73.2 s row: −2.8 + 12.40 = 9.60, a margin of 0.40 s.
  - At 560 without the second lever: 10.10.
  - Shipped config: 10.75. My 100 px world grid gave 6.38 s at 500; the plan's 6.42 s is consistent with it.
  - Each lever is applied only because the row still fails without it, in the task's order.
- **Lever 2 (`engage_seconds` 4.0) is legal on paper.**
  - The attack gate (`can_attack()`, `ram_corvette_brain.gd:241-242`) needs 0.55 s of budget left, so it stays open
    until 3.45 s.
  - Today's worst WIND_UP is 3.07 s, so that LINE_UP started by about 2.9 s at the latest.
  - The epic's floor for this lever (worst WIND_UP + 0.25 = 3.32 s) is also met.
  - The plan re-runs the t17 row, which covers every level-1 ram offset (`test_ram_corvette.gd:1378-1396`), and
    records its times. No test pins `engage_seconds` 4.5 or `exit_speed` 500 to the shipped values
    (`test_ram_corvette.gd:673-697`). Line 1248 sets 4.5 explicitly on its own instance.
- **The forced-LINE_UP boundary** uses the same corridor figure.

## Non-blocking findings from round 1: all addressed

- N1 is stated, and it goes into DECISIONS.
- N2: the static memo is gone, replaced by a per-file memo.
- N3: the replay waits three idle frames, and its tolerance is the largest observed idle delta plus 1/60 s.
- N4 names a fallback.
- N5 is stated as deliberate.
- N6 is declined with a reason that holds: the two gates now deliberately use different exit measurements.
- N7 adds the header note.
- N8 is declined. The reason given is slightly wrong: the pre-lever value could be set on an instance's private copy,
  the way the t17 `_budget_tweak` does it, with no write to the shared `.tres`. The row was optional anyway.

## New notes (non-blocking)

- **R2-1. Stray probe file.** `tests/zz_tmp_probe.gd` (a throwaway `GutTest`, untracked) is in the working tree.
  GUT's `test_` prefix means the suite won't run it. But `test_project_load_integrity.gd` loads every `.gd` outside
  `addons/`, and the harness commits whatever is left behind. Delete it before running the gate.
- **R2-2. The bomber boundary has a narrow margin.** Without its exit term, its lower bound is about 10.90 s against
  10 s: 8.0 + 360/170 + 0.25 + 2/60 + 0.5. If the t21 bomber lever (`engage_seconds` 6.5) is ever applied, the row
  stops being flagged. The test would then fail loudly rather than pass silently, so this is acceptable. A comment
  saying so would spare the next person the investigation.
- **R2-3. The margin is about 0.40 s over a grid maximum.** That is acceptable: the asserted formula stacks the 2.1 s
  charge deferral onto the curved exit, which never actually happens, and the realisable split (about 9.05 s, printed)
  is the true figure. Keep the print in the test output so a future retune shows how much room is left.
