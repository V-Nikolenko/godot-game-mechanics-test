# t22 — cloud_descent: snipers and rams off rails, and the section still clears in time

Revision 2 (answers review round 1, `4-review.md`; the changes are mapped at the end). Task
`cmuyk2qqp009loa2xb1k3py8o`. Builds epic plan §2.9.3 (with §2.9.2's count gate, §2.9.4 and §4's t22 rows) on the t21
machinery. Context and the measurements behind every number: `1-context.md`. Epic-review findings applied: **N2**
(the replay runs the whole section from 0.0 s, so all 9 snipers and 6 rams are inside it). The other epic findings
(B1, B2, N1, N3–N10) concern other tasks.

## Problem

cloud_descent is level 1's ENEMIES_CLEARED section: once its last wave triggers (76.0 s) the director waits up to
`enemies_cleared_timeout` (10 s) for the enemy container to empty, then force-frees what is left. Its 9 snipers and 6
rams still fly authored rails (drop in, hover a fixed number of shots, slide out; a ram runs a straight line), while
the same ships in the two other sections now fight with their own AI and leave when their engagement budget runs out.
After this task they arrive at the same moments and places, fight off rails, and the section still empties before
the 10 s net — proven on paper per entry and by a real replay.

## Design

### 1. Strip the rails (`level_1_director.gd::_build_section_3`)

The 15 sniper and ram lines lose `.move()`, `.free_after()` and `.shoot_at_player()`; `.at()` / `.delay()` stay
byte-identical, so the t1 pin is untouched. Wave comments that describe a rail are rewritten to say where the ship
enters. Nothing else in the section changes (fighters, drones, gunships, allies).

### 2. Deadline rows (`test_engagement_deadline.gd`)

Per entry, through the existing `_deadline_rows(section, path, tail)` (effective triggers, relative to the last
trigger): `rel + tail < timeout`, `tail = engage + deferral + exit + MARGIN`. Every term from the shipped config or a
measurement; each deferral gets t21's `_TICK_SLACK` (2/60 s):

| Kind | engage | deferral | exit |
|---|---|---|---|
| Sniper | `engage_seconds` | `aim_seconds + lock_seconds` (+ slack) | probe-measured curved exit on `sniper.tscn`, t21's view grid |
| Ram | `engage_seconds` | `wind_up_seconds + charge_max_time` (+ slack); LINE_UP never defers | `max(diagonal(projectile_world_rect) / exit_speed, probe-measured curved exit on ram_corvette.tscn over the CORRIDOR start set)` |

**The corridor start set (review B1).** A ram can begin its curved DISENGAGE anywhere it fights: APPROACH, LINE_UP,
WIDE_TURN and STAGGER all run inside `AssaultCorridorConstraint`'s visible rect, 1480 x 1480 round the view centre
(±740; the world rect is that + 64). t21's 404-start grid covers only the 1280 x 720 view and under-reports the ram's
curved exit by about 2 s (5.77 s vs 3.72 s at `exit_speed` 560: corner-tie starts such as offset (−480, −480) heading
away from the tie-broken left edge at 10 px/s, where the `v²/a` turning circle keeps the ship inside). So
`specialist_exit_probe.gd` gains a **second, separate** start set, `corridor_starts()`: offsets every 80 px over ±720
on both axes (19 x 19), each with the heading pointing straight away from that start's tie-broken nearest world-rect
edge (the brain's own left/right/top/bottom order) and ±45° from it — 1083 starts. `worst_disengage()` takes the start
set as an optional argument (default: t21's `starts()`, so t21's gates do not change). Speeds
`max(charge_speed, exposed_charge_speed)` and 10 px/s. Measured while revising: 5.767 s at 560, ≈ 2.9 s of wall
clock — the same as a 40 px / 24-heading reference grid (5.767) and the reviewer's 40 px / 16-heading grid (5.77).

**Sniper (review N1).** The sniper keeps t21's view grid: its corridor-wide figure, measured once while revising over
the same 80 px corridor set, is the same 5.40 s (slowest from the centre) at 8 s of wall clock, and its rows carry
about 6 s of slack. Stated in the file's comments and in DECISIONS.

No static memo (review N2): the deadline file keeps a per-file instance memo (the t21 shape); the only overlap with
the spawns file is the ~1 s sniper view probe.

Prints: each kind's tail with its terms, the worst row per kind, the 73.2 s ram row with its margin, and the
realisable split `engage + max(wind_up + charge_max + straight, wind_up + stagger + curved)` for the record.

### 3. The tight row and the levers

With the corridor-measured curved exit:

| Config | straight | curved | 73.2 s ram row | |
|---|---|---|---|---|
| shipped (exit 500, engage 4.5) | 4.55 | 6.42 | −2.8 + 4.5 + 2.133 + 6.42 + 0.5 = **10.75** | fails |
| lever 1 (exit 560) | 4.06 | 5.77 | **10.10** | fails |
| lever 1 + lever 2 (engage 4.0) | 4.06 | 5.77 | **9.60**, margin ≈ 0.40 s | passes |

Both pre-approved levers are applied, in order, each because the row still failed without it. Legality: `exit_speed`
acts only in DISENGAGE; `engage_seconds` 4.0 must keep the t17 attack-in-budget row green — today's worst WIND_UP is
at 3.07 s (top-wide, stub away), so LINE_UP starts by ≈ 2.57 s and the attack gate (`remaining() ≥ line_up_cap +
ATTACK_GATE_MARGIN` = 0.55 s) is open until 3.45 s. Re-run, and its printed times recorded. Side effects: shorter ram
lives in deep_space / planet_approach (their count gate only improves); Open Space has no budget and never
disengages; level 2's rams are on rails. (The epic's 1.15 s slack estimate assumed the straight term was the larger;
the measured curved exit is the larger.)

No pre-lever boundary row (review N8, optional): measuring the old config would need a write to the shared `.tres`,
which the config-isolation rule forbids; the table above goes into DECISIONS instead.

### 4. Boundaries (`test_engagement_deadline.gd`)

- **Ram at 76.0 + 1.2 fails**: `_add_to_last_wave(cloud_descent, ram, 1.2)` → exactly that row is over (≈ 1.2 +
  12.40 = 13.6 s). Control: the shipped section has no ram or sniper row over.
- **Ram forced to expire on its first LINE_UP tick**: for every cloud_descent ram spawn offset, the real
  `ram_corvette.tscn` in a `HARNESS.assault()` world at `MID_VIEW + offset * WORLD_SCALE`, player stub at the
  fighter-exit test's spot, hand-ticked (probe shape). The tick after it first reports LINE_UP, the budget is set to
  expire on the next update (the t17 seam). Asserted: it reaches LINE_UP; never WIND_UP; DISENGAGE on that tick; out
  of the world rect (queued for deletion) within `engage_seconds + corridor-measured curved exit + slack` of spawn.
  Prints the time.
- **Bomber**: no ENEMIES_CLEARED section's waves contain `WaveBuilder.BOMBER` (asserted for every such section). A
  bomber added at delay 0 to each ENEMIES_CLEARED section's last wave, tail `engage + run_length / run_speed +
  RUN_STALL_SLACK + slack + MARGIN` **with the exit term left out** — a lower bound, so a row flagged without it is
  flagged with any exit, and no probe is paid for (≈ 10.9 s vs 10) — is flagged in cloud_descent and reported for
  station_assault. **Deliberate reading of "a bomber in any ENEMIES_CLEARED section fails" (review N5):**
  station_assault's 180 s net is sized for the boss fight and no bomber timing can fail it; the Gatling precedent
  asserts cloud_descent and reports the rest, and the "contains none" row covers every section. The comment names C5:
  its persisted mines would hold the section open even longer.

### 5. Count gate and pin (`test_level1_specialist_spawns.gd`)

- `MIGRATED_SECTIONS` gains `cloud_descent`; `_RAIL_SECTIONS` becomes `[]` (Ph3 t17 shape; the check re-arms if a
  section goes back on rails). The no-rail row count becomes 50 (all specialist rows).
- `test_extra_rams_at_the_peak_break_the_frozen_constant` is deleted: with no section on rails it has nothing to
  recompute (the live peak of a rail-less section is 0); the count gate's ram-triple boundary keeps proving the gate
  rejects. The frozen `cloud_descent: 4` stays as the gate's denominator (limit 10). The header says that
  `_rail_lifetime()`'s sampling branch is now exercised by nothing (review N7); it stays for a section put back on
  rails.
- The count gate keeps t21's view-grid exits (review N1): its ram life under-reports by ≈ 1.7 s per life. Recorded as a
  follow-up in DECISIONS, not changed here. A shared lifetime helper (review N6) is not added: the two gates now
  deliberately use different exit measurements, so the helper would take the exit as input and share only one-line
  config reads.

### 6. Real replays

- **`test_level1_fighter_exit.gd`** (from 66.0 s, includes the 73.2 s ram): unchanged logic; header updated ("the
  72 s rail ram" → the AI ram). Must still empty within 10 s.
- **New `test_level1_specialist_exit.gd`**: cloud_descent's waves **from 0.0 s** (epic review N2), every wave kept in
  list order with only the sniper and ram entries left (dropping a wave could move a later one; the fire-density
  shape), real `WaveManager` + `ArenaCamera`, stationary hurtbox-less stub at the lower centre, brains seeded before
  `_ready()`. Clock sped up **8x** with the physics step kept at 1/60 game-second (the `test_bomber.gd` /
  `test_enemy_ordnance.gd` precedent: `time_scale`, `physics_ticks_per_second`, `max_physics_steps_per_frame` scaled
  together, restored at the end of the run and in `after_each`) — 86 s of game time in ~11 s of wall clock. After
  scaling it waits three idle frames before `load_section()` (review N3; `tests/README.md`), and judges
  `waves_complete` on `WaveManager`'s own clock with a tolerance of the largest idle delta observed during the run
  (recorded from `process_frame`) plus 1/60 s, instead of the 1x file's fixed 0.1 s.
  Asserted: `waves_complete` fires on the 76.0 s tick (WM clock); 9 snipers and 6 rams spawned (counted by class); the
  container is empty before `timeout` after it; every sniper and ram left in DISENGAGE with no `EnemyPathMover`.
  Printed: margin, and each kind's last exit relative to `waves_complete`.
  Boundary: the 28.0 s ram wave alone, re-timed to 0 with `.move()` put back on its entries, spawns rams that carry an
  `EnemyPathMover` — the predicate the main case rejects (≈ 1 s of game time).

## Build sequence

1. Tests first: deadline rows + boundaries, the corridor start set, count-gate/pin changes, the new replay file. Run
   them: the sniper/ram deadline rows, the no-rail check (15 rails) and the replay's DISENGAGE/no-path-mover asserts
   fail.
2. Strip the 15 lines' rails; rewrite comments. The 73.2 s ram row still fails (10.75).
3. Lever 1: `exit_speed` 560 in `ram_corvette_config.tres`. Re-run the deadline file, the t17 attack row,
   `test_ram_corvette.gd`, `test_level1_specialist_spawns.gd`. Still failing (10.10) → lever 2: `engage_seconds`
   4.0; re-run the same and record the attack row's printed WIND_UP times.
4. Level-1 gates, both replays, full gate (`REPO=/workspaces bash /agent/verify.sh`), `scripts/check-test-leaks.sh`.
   Read the gate's GUT `Time` (≈ 240 s before this task). Fallback if it nears 300 s: the replay starts at 11.0 s
   (re-timed by −11 s; the first specialist wave, so all 9 + 6 still spawn), then a coarser corridor grid.
5. Docs: ram `ENEMY.md` (exit_speed, engage_seconds, level-1 note), sniper `ENEMY.md` level-1 note,
   `docs/enemy-roster.md`, `CLAUDE.md` gate list (sixteenth gate's specialist rows, the new replay), `tests/README.md`
   if it lists the replays, a t22 entry in `DECISIONS.md` (both levers with the table above, the corridor start set,
   the sniper and count-gate notes).

## Test plan

`test_engagement_deadline.gd`:
- `test_every_enemies_cleared_sniper_and_ram_entry_clears_the_timeout` (9 + 6 rows counted for cloud_descent; prints).
- `test_the_corridor_start_set_finds_a_slower_ram_exit_than_the_view_grid` (sanity: corridor ≥ view figure, no run
  capped, every start inside the world rect).
- `test_a_ram_in_the_last_wave_at_delay_1_2_misses_the_timeout` (**boundary**).
- `test_a_ram_forced_to_expire_on_its_first_line_up_tick_leaves_within_its_bound` (**boundary**, real scene).
- `test_a_bomber_in_an_enemies_cleared_last_wave_misses_the_timeout` (**boundary**).
- `test_no_enemies_cleared_section_spawns_a_bomber`.

`test_level1_specialist_spawns.gd`: `test_migrated_sections_have_no_rail_left` (50 rows); the count gate now covers
cloud_descent; legacy check vacuous-but-guarded; extra-rams frozen-constant test removed.

`test_level1_specialist_exit.gd`: `test_cloud_descents_snipers_and_rams_leave_under_ai_before_the_timeout`,
`test_a_rail_driven_ram_wave_is_rejected` (**boundary**).

Regression: `test_level1_fighter_exit.gd`, `test_ram_corvette.gd` (t17 attack row), every level-1 gate, the invariant
gates in the acceptance criteria, leak check.

## Risks

- **Suite time** (≈ 240 s, harness limit ≈ 300 s): replay at 8x (~11 s), corridor probe ≈ 3 s, bomber row probe-free;
  fallback in Build 4.
- **8x clock**: physics step stays 1/60, so brain behaviour is unchanged; precedent files already run at 8x.
- **Replay stability**: a seeded scenario; idle-frame ordering can shift a spawn by a frame. The paper margin on the
  tightest row is ≈ 0.4 s, the replay's actual margin is printed.
- **A grid maximum is not a proof of a bound.** The corridor set agrees with two denser reference grids (§2); the
  realisable split is printed beside the asserted formula.
- **engage 4.0** leaves the ram ≈ 0.9 s of budget at its latest WIND_UP: still one charge per life (it was one at 4.5).

## Out of scope

Changing the deadline formula (the realisable split is printed, not asserted); changing t21's count-gate exits;
level 2; any brain change; epic docs closure (t23).

## Response to review round 1

| Finding | Change |
|---|---|
| B1 | Ram exit measured over a separate corridor start set (§2); lever 1 and lever 2 both applied, in order, each because the row still failed (§3); the forced-LINE_UP boundary uses the same figure (§4) |
| N1 | Sniper stays on the view grid, its corridor figure measured equal (5.40 s) and stated; the count-gate under-report goes into DECISIONS as a follow-up (§2, §5) |
| N2 | No static memo; per-file instance memo (§2) |
| N3 | Three idle frames before `load_section()`; WM-clock tolerance from the measured largest idle delta (§6) |
| N4 | Gate time read from the GUT summary; fallback named (Build 4) |
| N5 | Bomber reading stated as deliberate (§4); its exit term dropped as a lower bound |
| N6 | Declined with reason (§5) |
| N7 | Header note (§5) |
| N8 | Not added: it would need a write to the shared `.tres`; the numbers go into DECISIONS (§3) |
