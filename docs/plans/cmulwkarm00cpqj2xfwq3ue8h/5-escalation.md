# Escalation — t16-level1-duration: the shots/s density gate cannot be met with the pre-approved levers

**Result: ESCALATE (owner decision needed). Nothing is built; the level and the tests are unchanged.**

The task text and epic plan §2.9.2 both say: if a density gate fails, use only lever 1 (fighter `engage_seconds`
6.0 → 4.5), lever 2 (a new `assault_passes` 2 → 1) or lever 3 (split a 5+ formation), and "any other change needs the
owner". The level edit itself is mechanical and done (kept as `prototype/level1_duration_rails_off.patch`: 37 lines
stripped, 9 loose pairs tagged `w<n>f` / `w0g`). Two of the three density gates pass with margin. **The shots/s gate
fails in both sections at every lever, and no lever can move deep_space at all.** Changing the gate's formula or ratio
to make it pass would be redefining an owner-approved gate, so this run stops here.

## What fails, with the plan's own formulas

Numerator per epic §2.9.2: attack-capable ships (3 per fighter squad, 2 per Gatling squad) × per-ship rate, where a
fighter counts `max burst / (gap × size + min_burst_period)` = 7 / (0.35 + 1.2) = **4.52 shots/s** and a Gatling
12 / 2.8 = **4.29**. Lifetimes from the shipped configs: fighter `engage + 0.8 deferral + Razor-shaped exit` = 9.64 s,
Gatling `7.0 + 2.08 + exit` = 12.0 s. Denominators are the frozen t1 constants.

| | all-alive ≤ 2.0× | capable ≤ 1.5× | shots/s ≤ 1.25× |
|---|---|---|---|
| deep_space (legacy 10 / 31.25) | 17 ≤ 20 ✓ | 13 ≤ 15 ✓ | **58.25 > 39.06 ✗ (1.86×)** |
| planet_approach (legacy 10 / 33.33) | 16 ≤ 20 ✓ | 14 ≤ 15 ✓ | **63.23 > 41.67 ✗ (1.90×)** |
| deep_space, lever 1 (4.5 s) | 17 ✓ | 13 ✓ | **58.25 ✗** |
| planet_approach, lever 1 | 11 ✓ | 10 ✓ | **45.16 ✗ (1.35×)** |

- **Lever 2** changes nothing: the lifetime is bounded by the budget, and at 6.0 s an Assault fighter already flies
  one pass (t8b note I8).
- **Lever 3** makes it worse: a 5-ship formation split 3 + 2 fields five attackers instead of three.
- **deep_space cannot be fixed by any budget.** Its peak is at ≈ 8 s, where V5 (2.5 s), V3 (5.5 s), the 6.5 s pair,
  Diag5 (8.0 s) and the Gatling pair (0–12 s) overlap because of their *spawn times*, which the task keeps. Even a
  2.0 s budget (not a lever) gives 53.7.
- Other readings of "max burst" do not rescue it: the strict brain ceiling (7 / 1.2 and 12 / 2.28) gives 74.7 / 81.7;
  counting only AIMED bursts (5 / 1.7 = 2.94) gives deep_space 40.92 > 39.06.

## Why: the analytic numerator is far from what the AI actually does

A real run of each section (real `WaveManager`, `HARNESS.assault()`, stationary player at lower centre, only the
fighter/Gatling entries; scratch test kept as `prototype/scratch_sim.gd.txt`):

| run | spawned / left by end | alive peak | shots fired | peak shots/s in 1 s / 2 s / 5 s windows | min centre distance between ships |
|---|---|---|---|---|---|
| legacy rails, deep_space (42 s) | 36 / 36 | 10 | 524 | 33.0 / **31.0** / 24.0 | 1.0 px |
| **AI, deep_space** | 36 / 36, all in DISENGAGE | 17 | **114** | **21.0 / 12.0 / 6.0** | 50.4 px (t = 7.6 s) |
| legacy rails, planet_approach (120 s) | 41 / 36 | 10 | 1029 | 36.0 / **35.0** / 28.0 | 0.0 px |
| **AI, planet_approach** | 41 / 41, all in DISENGAGE | 10 | **114** | **13.0 / 6.5 / 4.0** | 54.0 px (t = 84.3 s) |

- The legacy 2 s peaks (31.0, 35.0) reproduce the frozen constants (31.25, 33.33), so the counting method is sound.
- The AI fires **11–22 % of the legacy shots**, and its real 1 s peak is 0.64× / 0.36× legacy. The analytic 1.86× /
  1.90× comes from assuming every capable fighter fires at its burst ceiling for its whole life, while in Assault each
  fires about one burst before it leaves.
- One scenario only (stationary player). A moving player may draw more TURN-leg bursts; the run does not measure that.

## Options for the owner

| | Change | Result with today's data | Cost / risk |
|---|---|---|---|
| **A (recommended)** | Keep the two analytic gates (all-alive 2.0×, capable 1.5×) as the structural ceiling. Replace the analytic shots/s check with a **measured** one: a real-`WaveManager` run per section, peak shots in any 2 s window ≤ 1.25 × the frozen constant. Print the analytic figure, do not assert it | deep_space 12.0 ≤ 39.06, planet_approach 6.5 ≤ 41.67: green with a wide margin | Adds ≈ 45 s + 125 s of game-time simulation to the gate unless the run is cropped to the analytic peak window (≈ 20 s per section). Behaviour-dependent: one seeded scenario |
| B | Keep the analytic shots/s check, raise its ratio to 2.0× | 1.86× / 1.90×: green, thin | The printed number then says the level is ≈ 1.9× noisier, which the real run contradicts |
| C | Keep the analytic form, change the fighter rate to a per-life bound: (max bursts in a life × 7) / lifetime = 4 × 7 / 9.64 = 2.90; Gatling 4 × 12 / 12.0 = 4.0 | deep_space 39.96 > 39.06: still red by 2 % | Needs a ratio change too |
| D | Cap shooters in Assault (e.g. 2 per fighter squad, or a level-wide cap) | Untested | Cross-squad arbitration is Phase 14; a design change |
| E | Drop the shots/s gate for these sections; keep the other two; record the measured numbers in DECISIONS | Green | Loses a guard against later spawn changes raising fire density |

Whatever is chosen, the same gate shape will hit t17 (cloud_descent; legacy 8 / 15.0) unless the decision covers it.

## Also measured, for the owner (not part of the gate)
- **Separation (DECISIONS t9: "t16 must re-run separation on whatever formations it ships").** The closest two ships
  came was 50.4 px (deep_space, 7.6 s) and 54.0 px (planet_approach, 84.3 s), against a 57.2 px hull diameter: brief
  contacts, not stacks. The rails overlapped completely (0–1 px). Not gated; the epic's acceptance does not ask for it.
- All 77 AI ships left in DISENGAGE within the run, none on a rail.

## Resuming
Once the owner picks an option, the next run applies `prototype/level1_duration_rails_off.patch`, updates the t1 pin in
place (movement → false, aim_mode → "", free_after → 0 for these two sections), retires the live-equals-constant check
for these two sections with a comment, and adds the chosen gates. `prototype/scratch_density.gd.txt` has the analytic
interval code (per-squad `min(alive, cap)`); `prototype/scratch_sim.gd.txt` the real-run counter (it reads a copy of
the HEAD director saved as `tests/scratch/legacy_director.gd` for the legacy rows).
