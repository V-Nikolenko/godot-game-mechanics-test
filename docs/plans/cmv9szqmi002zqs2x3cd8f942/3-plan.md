# t17 — Level 1's Deep Space and Planet Approach sections include Missile Corvettes and Support Ships

Epic plan §2.18 (approved) is the design; this plan fixes the concrete rows, numbers and test shapes, measured on the
working tree before writing (`1-context.md`).

## Problem
Level 1 never shows the two Phase 5 enemies. The player should meet one Missile Corvette early in Deep Space (≈ 12 s),
a Support Ship riding with a ram pair (26 s), and in Planet Approach a Support Ship with the ram triple (28 s) and two
corvettes (≈ 40 s, ≈ 85 s) — each AI-driven, attacking once inside its Assault life, without crowding the screen past
the frozen density gate and without stalling an ENEMIES_CLEARED section.

## Design

### Placements (`assault/scenes/levels/edelia/1/level_1_director.gd`)
Every new line is added **inside an existing wave** (no new wave, so no other wave's list index or effective trigger
changes — the Ph3 wave-order quirk cannot bite), with no `.move()`, `.free_after()`, `.shoot_*()` or formation:

| Section | Wave | New line | Spawn moment |
|---|---|---|---|
| deep_space | 11.0 s (sniper pair + drone) | `b.missile_corvette().at(0, -400).delay(1.0)` | 12.0 s |
| deep_space | 26.0 s (ram pair) | `b.support_ship().at(-255, -460)` | 26.0 s, with the 26.0 s ram at (−255, −400) |
| planet_approach | 28.0 s (ram triple) | `b.support_ship().at(0, -460)` | 28.0 s, with the 28.0 s ram at (0, −400) |
| planet_approach | 39.0 s (fighter pair) | `b.missile_corvette().at(0, -400).delay(1.0)` | 40.0 s |
| planet_approach | 84.0 s (drone wedge) | `b.missile_corvette().at(0, -400).delay(1.0)` | 85.0 s |

"120 px behind the ram" is read as 120 *screen* px = 60 design units (offsets are design units, ×2 at runtime), i.e.
y −460 against the ram's −400. The 1.0 s delay keeps each corvette off the spawn point of the drone that shares its wave.
No existing line and no enemy config changes.

### Lifetimes for the count gate (measured, `before_all`)
- Corvette: `engage_seconds 7.0 + attack_window() (0.7 + 2 × 0.22 = 1.14) + 2 ticks + measured exit`.
- Support: `engage_seconds 9.0 + measured exit` (its budget is never deferred — the t13 report; escort does not defer).
- Exits: `SpecialistExitProbe.worst_disengage()` over **`corridor_starts()`** at speeds `[max_speed, 10]`. Measured:
  corvette 8.72 s, support 4.58 s, both from the view centre heading right (away from the tie-broken left exit) at
  10 px/s. A 3-speed run (`+ 2 px/s`) gives the identical worst for both (measured) and costs 50 % more, so 2 is dropped
  (the t22 ram-corridor precedent). Lives: corvette ≈ 16.89 s, support ≈ 13.58 s.
- Probe cost: the corvette's four rocket pools prewarm 16 rockets per instance, ×2166 runs. `worst_disengage()` /
  `disengage_seconds()` gain an optional trailing `prepare: Callable` applied to each instance before `add_child`; the
  corvette's passes one that sets every `BulletPool.pool_size = 0` (DISENGAGE never fires; measured: same 8.72 s, 2×
  faster). Existing callers are unchanged (default `Callable()`).

### Gates
**`tests/integration/test_level1_specialist_spawns.gd`**
- `EXPECTED_PH5`: the 5 rows above (section, kind, raw trigger, offset, delay), read by a separate
  `_actual_ph5_spawns()` over `_PH5_KIND_NAMES` (`MISSILE_CORVETTE`, `SUPPORT_SHIP`). The 50-row `EXPECTED`, its
  internal-consistency counts and `_KIND_NAMES` stay untouched. A pin-internal row (2 + 3 by section, 3 corvettes + 2
  supports, none outside deep_space / planet_approach) and a boundary (a Ph5 line's delay changed fails the pin).
- No-rail check covers the new rows: `test_migrated_sections_have_no_rail_left` states 50 legacy + 5 Ph5 = 55 lines and
  runs `_rail_rows` over both name maps.
- Count gate: `_ai_lives()` gains the two kinds (lives above); `_ai_intervals()` counts them as specialists. Frozen
  `_LEGACY_PEAK_SPECIALISTS` unchanged; limits 12.5 / 7.5 / 10. Expected peaks (from the measured lives): deep_space 6–8,
  planet_approach 7 (at 98.0 s: bomber, snipers 92 × 2, rams 88 × 3, corvette 85), cloud_descent unchanged.
- Sanity on the new probes: every corridor run ran and none capped; each exit ≥ the centre's straight run to the edge.
- Boundary: an extra corvette inserted (list order asserted) at planet_approach's measured peak moment fails the gate
  (peak + 1 > 7.5). **Deviation from the task text:** the task says "its 65.7 s peak"; the measured peak today is 6 at
  75.5 s and, after placement, 7 at 98.0 s. The row uses the measured `_peak()["at"]` (the existing ram-triple boundary's
  shape), prints the moment, and asserts `before["count"] == 7` so the boundary is never vacuous.
- Spill-over row: every planet_approach specialist's interval end (+ 7.0 s rocket life for a corvette, since rockets in
  the container hold ENEMIES_CLEARED open) is before `planet_approach.duration + cloud_descent's last effective trigger`
  (110 + 76 = 186 s); boundary: a synthetic corvette interval placed so its end crosses that moment is flagged by the
  same predicate.

**`tests/integration/test_engagement_deadline.gd`**
- `test_no_enemies_cleared_section_spawns_a_missile_corvette` / `…_a_support_ship` (the bomber/gatling shape).
- Boundary: a corvette added at delay 0 to cloud_descent's last wave computes `0 + 7.0 + 1.14 + 7.0 + 0.5 = 15.64 s`
  > 10 s through `_deadline_rows()` with the tail `engage_seconds + attack_window + rocket max life + MARGIN` (no exit
  term; rocket max life = max of `EnemyRocketScenes.max_time_of()` over the four launchable kinds = 7.0, read live).
  Also the support's no-section row has a boundary: the same insertion makes `_section_has_scene` true.

**Attack-in-budget rows** (new shared helper `tests/helpers/level1_slice_replay.gd`)
- `placed(path)` lists every level-1 spawn of a kind (effective trigger + delay = `rel`); `slice_waves(section, from,
  to)` keeps waves whose effective trigger is in `[from, to)`, re-timed by −from, all entries kept (the support needs the
  ram it arrives with); `run(host, waves, length, target_path, observe, tweak)` builds `HARNESS.assault()` with the
  camera current, a stationary stub at view centre + (0, 250), seeds every brain from its spawn index, waits three idle
  frames, `load_section()`, and steps physics frames calling `observe(ship, t) -> bool`; **it stops when `observe`
  returns true** (the condition is met) or the window ends, then switches the `WaveManager` off and keeps stepping
  until every already-triggered wave's spawn timers have fired (no leaked `SceneTreeTimer`). The 8× clock is the
  caller's (both files already scale it and restore it in `after_each`).
- `test_missile_corvette.gd`: `test_every_level1_corvette_spawn_telegraphs_and_fires_inside_its_budget` — 3 placed
  corvettes (asserted), each slice `rel − 1 .. rel + 7.0 + 2`: exactly one corvette in the slice, TELEGRAPH reached with
  `budget.remaining() > 0`, and `salvos_fired >= 1` with `budget.remaining() > 0` (the attack gate makes it complete
  before expiry). Measured: TELEGRAPH at 4.07–4.60 s after spawn with 2.4–2.9 s left; salvo done with 1.25–2.0 s left.
  Boundary: the deep_space slice with the corvette's private config `engage_seconds = 4.0` (tweak in `child_entered_tree`,
  after `privatise()`) never telegraphs before expiry.
- `test_support_ship.gd`: `test_every_level1_support_spawn_projects_a_shield_inside_its_budget` — 2 placed supports,
  slice `rel − 1 .. rel + 9.0 + 2`: `is_supporting()` with `brain.shield` valid, named `ProjectedShield`, a child of the
  ward, and `ward.hurt_box.has_absorber()`, all with `budget.remaining() > 0`. Measured: 3.0–3.45 s after spawn, 5.5–6.0 s
  left, ward = the ram it arrived with. Boundary: the planet_approach slice with `engage_seconds = 2.5` never does.

## Build sequence
1. Probe `prepare` hook (done in measurement; default keeps old callers identical).
2. Helper `level1_slice_replay.gd`.
3. Failing tests: `EXPECTED_PH5` pin, deadline rows, attack rows (fail without placements).
4. Placements in `level_1_director.gd`; header comment updated.
5. Count gate + spill-over + boundaries; run the three files; `scripts/check-test-leaks.sh`.
6. `scripts/gate-time.sh` after; `/agent/verify.sh`; docs (`updating-project-docs`: level-1 notes in the two
   `ENEMY.md`s, `docs/enemy-roster.md`, CLAUDE.md test list) and the DECISIONS line for the peak-moment deviation.

## Test plan
As listed under Gates; boundaries: Ph5 delay changed (pin), extra corvette at the measured peak (count), synthetic
spill-over interval, corvette / support in cloud_descent's last wave (deadline), engage 4.0 corvette and engage 2.5
support (attack rows). Existing level-1 gates must stay green unchanged (`test_level1_drone_spawns.gd`,
`test_level1_fighter_*`, `test_level1_specialist_exit.gd`, `test_level_1_sequence.gd` — the latter has no camera, so
`WaveManager` spawns nothing, unaffected).

## Gate-time budget (15.0 s)
Before: GUT 185.7 s (190.3 s wall), 1817 tests. Estimated: probes ≈ 7.2 s (corvette ≈ 4.4, support ≈ 2.8), five runs
stopped at their condition ≈ 3.8 s, two boundary runs ≈ 1.1 s, pins/deadline rows < 0.3 s → ≈ 12.4 s.

## Risks
- Real-physics runs depend on traffic (other enemies' rockets/bullets can kill a ward); seeds fixed, margins ≥ 1.25 s.
- The peak moment moved from the plan's 65.7 s; documented, asserted non-vacuous.

## Out of scope
Any change to an existing row or enemy config (escalate instead); an encounter director; a whole-section replay.
