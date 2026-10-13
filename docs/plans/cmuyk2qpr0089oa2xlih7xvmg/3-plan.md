# t10 — The Bomber's bombing runs (task cmuyk2qpr0089oa2xlih7xvmg)

**Revision 3** — answers `4-review.md` round 1 (F1–F8) and round 2 (R2-1–R2-5); the tables at the end map each finding.

Builds epic plan `docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.4 items 1–8 and §2.9.4, with
the epic review's round-2 finding **B1 (c)–(e)** and **N7** applied (they name t10 and win over the plan text).
B1 (a) (`mine_warning` 0.25 s, asserted inequality) shipped in t9; B1 (b) (arming from release, overlap poll) in t6.

## Problem
Today's AI Bomber (t9 shell) only flies a plain intercept at the player and drops nothing. The player should see a
heavy ship angle in, slow down on a straight, readable run with a red light, and leave persistent danger **where
they are heading**: a mine wall across a moving player's path, a gravity bomb on a slow/close player, a pursuit bomb
on a far or boosting one; then the bomber arcs away. A player who holds course into a wall must actually get hit by
it (B1); one who turns, stops or reverses escapes it.

## Design

### Prediction (`BomberBrain`)
- `v̄`: exponential moving average of the player's velocity, τ = `velocity_smoothing`; **initialised from the first
  sample** (not zero) so a constant-velocity player is read exactly from the first tick. Updated every tick.
- `|v̄| < min_lead_speed` → `P̂ = P` for every kind.
- **Mine wall (X11 + B1c):**
  `c = (run_length/2)/run_speed + mine_arm_delay + wall_margin + (trigger_radius + arc_depth)/|v̄|`,
  `t_wall = min(t_approach_left, approach_cap) + min(c, mine_horizon)`, `P̂ = P + v̄·t_wall`.
  **Revision 3 (R2-1): only `c`, the lead at RUN entry, is capped by `mine_horizon`; the approach time is not.** The
  lead-in is therefore planned to where the line *will be* when the bomber arrives (the Fighter's arrival prediction,
  `fighter_brain.gd::_plan`), and for a constant-velocity player that point does not move during the whole APPROACH:
  `t_approach_left` falls exactly as fast as P advances. At RUN entry `t_approach_left` = 0, so the frozen wall is
  `P + v̄·min(c, mine_horizon)` — the epic's formula; with shipped numbers `c` ≤ 2.69 s < 3.0, so `mine_horizon`
  never binds and t19's inequality is unchanged. (Revision 2 capped the sum, which let the goal ride with the player
  at |v̄| for all but the last 0.54 s of the approach and turned every approach into a lag pursuit.)
  The B1(c) term measures the margin to the middle mine's **trigger edge** instead of its centre. Worked numbers
  (RUN entry, `t_approach_left` = 0, 24 px ejection lead included): the middle mine arms ≈ 1.70 s after RUN entry and
  the player reaches its trigger edge at 1.96 s at **every** speed (the term cancels the speed); detonation 0.25 s
  later finds the player 25 px short (220 px/s), 30 px past (440) and 42.5 px short (150) of the mine — all inside the
  48 px blast. `t_wall` ≤ 2.69 s (at 150 px/s) < `mine_horizon` 3.0, which stays as shipped (t19's lose-radius
  inequality reads it).
  `t_approach_left` = the current Dubins plan's remaining length / `max_speed` (0 at RUN entry).
- **Gravity / pursuit:** damped `P̂ = P + v̄·lead_factor·min(horizon, d/run_speed)`.
- `predicted_drop_point()` returns the P̂ in force for the chosen kind.

### Ordnance choice (start of each APPROACH)
`|v̄| > mine_speed_max` → PURSUIT (a boosting player, whatever the distance — F3); `mine_speed_min ≤ |v̄|` → MINE;
else `d < gravity_range` → GRAVITY; else PURSUIT. With probability `choice_jitter` (from `rng`) take the next in the
cyclic order MINE → GRAVITY → PURSUIT → MINE. On `approach_cap` the bomber takes the **next kind in the cycle**
instead of re-evaluating the rule (F5), so a bomber that cannot get ahead of a cruising player stops chasing a
receding wall.

**B1(e), recorded not honoured:** R4.5's "boosting right → mine chain" example stays a pursuit bomb above
`mine_speed_max` (440), as the board's acceptance row ("a 600 px/s player gets a pursuit bomb") requires. Logged as a
DECISIONS line (an owner question for later difficulty work: a wall for a boosting player needs a lead longer than
`mine_horizon`). R2-5, also logged: a player boosting steadily is reached only head-on — a boost is temporary, and the board row tests only the choice.

### Bombing line
- **MINE:** centre `P̂`, direction `dir ⟂ v̄`, picking the perpendicular whose start (`P̂ − dir·L/2`) is on the
  bomber's side of the player's track. Length `run_length`.
- **GRAVITY / PURSUIT:** `dir` = bearing(bomber → P̂) rotated by `approach_angle` toward the bomber's heading side,
  **chosen once at the start of APPROACH and kept**; re-plans only translate the line with P̂. (Re-deriving it from
  the live bearing would rotate it another 35° every re-plan, because from the line's start the bearing to P̂ *is*
  the line.)
  - GRAVITY: the line passes over P̂ at run coordinate `L/2 + gravity_release_lead`, so the release lands at the
    line's middle (the epic's design; the bomber overflies the player — DECISIONS line for t21's feel pass).
    **R2-2: `gravity_release_lead` ships at 120, not 80** — a bomb released 80 px short arms with a stationary player
    already inside its radius and detonates 76 px past them, a miss; at 120 it detonates 36 px past, a hit. Asserted:
    `gravity_release_lead ≥ trigger_radius + gravity_bomb_speed · gravity_bomb_arm_delay` (116).
  - PURSUIT (F2): the line passes **beside** P̂: P̂ is abeam the line's end, `pursuit_launch_range` (**new field,
    300 px**) to the side the bearing was rotated away from. The bomb is launched at the midpoint toward P̂ (≈ 350 px,
    59° off the heading); at RUN's end the player is abeam, so ESCAPE turns away from a player who is never ahead and
    the distance grows on every tick. This deviates from the epic's "passes over P̂" for the pursuit kind only: a
    steering bomb launched from overhead has nothing to steer, and the overfly rams the player.
- **Tie-break (R2-3):** when the heading is parallel to the bearing (|cross| < 0.05, e.g. a nose-down spawn straight
  above the player), the line turns toward the corridor's centre in Assault, else to a side drawn from `rng`.
- **Assault clamp (R4.6):** `R = inner_rect().grow(−drop_margin)`. The line's anchor — P̂ for MINE and GRAVITY, the
  point abeam P̂ on the **offset** line for PURSUIT — is clamped into `R`; the infinite line through it is clipped to
  `R` (`[a, b]`); the run interval is slid along `dir` to fit inside `[a, b]`, or cut to it when longer (a slide may
  move a PURSUIT line's P̂ off the exact abeam point; the per-tick ESCAPE row runs unclamped). Every mine rest point
  is also clamped into `R`. `wall_clamped()` reports whether the anchor moved.

### APPROACH
- A Dubins lead-in (`DubinsPath.candidates`, shortest) to `(start, dir)`, sampled at 8 px, tracked by pure pursuit
  with `Steering.turn_toward` (the Fighter's `_track`, without its clearance/squad logic).
- **Plan radius** = `max_speed / min(max_turn_rate, acceleration/max_speed) × 1.1` ≈ 244 px, not the plan's 150:
  at `acceleration` 260 the mover cannot hold a 150 px circle at 240 px/s (v²/a = 221 px), and a path it cannot
  follow is re-planned forever. The config values stay as shipped.
- **Re-planned every `replan_interval` (0.25 s)** from a fresh prediction; **every** plan iterates the
  `t_approach_left` ↔ path-length dependence 3 times (`T = length(path to the line through P + v̄·(T + c)) /
  max_speed`, capped at `approach_cap`), starting from the previous plan's remaining time — the Fighter's
  `GOAL_PREDICT_ITERATIONS`. GRAVITY / PURSUIT lines translate with the damped P̂ (a slow player; no arrival
  prediction needed).
- **RUN entry:** on the line — lateral ≤ 32 px, heading within 12° (inside the 15° acceptance row), run coordinate in
  `[−32, L/2]`. The line is frozen there.
- `approach_cap` (6 s) → the next ordnance kind in the cycle, re-planned from the current pose.

### RUN (StateLight ARMED)
Straight along the frozen line at `run_speed` (a seek point 40 px ahead on the line, so drift is corrected). Ends at
the line's end, or at the stall guard `line_length/run_speed + 0.25 s` (≤ 2.37 s: the RUN deferral bound — the
epic's 2.12 s plus a quarter second; no ENEMIES_CLEARED section holds a bomber; recorded in DECISIONS).
- **MINE, by distance.** `n = rng.randi_range(mines_per_run_min, max_mines_per_run)`. `s* = (P − start)·dir` at RUN
  entry. Rest points at `s* + (i − (n−1)/2)·mine_spacing` along the line plus a bow of
  `arc_depth·(1 − (k/((n−1)/2+1))²)` toward the player's side of the line (largest in the middle). `s*` is clamped so
  every release fits between the entry coordinate and the line's end (n is reduced if it cannot). Each mine is
  released when the bomber's run coordinate reaches its rest coordinate + `Δ` (`Δ = mine_eject_speed ·
  mine_eject_time / 2` = 24 px), ejected along `rest − pos` at `v₀ = 2·|rest − pos| / mine_eject_time`, so it stops on
  its planned point (the ordnance's linear decay; ≤ 2.2 px short at 60 Hz). **New field `mine_eject_time` (0.3)**,
  applied to the mine by `Bomber.drop()`, so the brain and the ordnance share one number.
- **GRAVITY:** one bomb when the live damped P̂ is ≤ `gravity_release_lead` ahead along the line (fallback: at the
  line's end); it **inherits the bomber's heading** (epic §2.4 item 5; Revision 1's 15° correction is dropped — F6
  showed it cannot cover a crossing player's drift anyway, and a gravity bomb is meant to be sidestepped).
- **PURSUIT:** one bomb at the line's midpoint, aimed at the live damped P̂, at `pursuit_launch_speed`.

### ESCAPE, REPOSITION, Assault
- **ESCAPE:** `turn_toward(heading, pos − P, min(escape_turn_rate, acceleration/escape_speed))` at `escape_speed`
  for `escape_time`; light OFF.
- **REPOSITION (Open Space):** orbit the player at `standoff`, advancing 0.4 rad ahead of the bomber's bearing, for
  `rng.randf_range(reposition_min, reposition_max)`, then APPROACH with a fresh choice.
- **Assault:** one run per life — ESCAPE ends in DISENGAGE (epic §2.4 item 8). Budget expiry in RUN sets a pending
  flag: the run finishes (every mine dropped) and RUN's end goes to DISENGAGE. Expiry anywhere else disengages at once.

### Seams for tests
Read-only accessors: `ordnance_kind`, `line_start`, `line_dir`, `line_length`, `planned_rest_points`,
`smoothed_velocity()`, `predicted_drop_point()`, `line_centre()`, `wall_clamped()` (true when the anchor was moved by
the Assault clamp). `config.choice_jitter = 0` in tests.

## Build sequence
1. Config fields (`pursuit_launch_range`, `mine_eject_time`; `gravity_release_lead` default 80 → 120) and
   `Bomber.drop()` applying `mine_eject_time`.
2. Failing tests in `test_bomber.gd` (placement, live player, outcome, choice, line, approach, escape, deferral,
   attack-in-budget) — watch them fail on the t9 shell.
3. `BomberBrain`: prediction + choice + line + clamp.
4. APPROACH (Dubins + re-plan + entry).
5. RUN drops, ESCAPE, REPOSITION, Assault deferral / DISENGAGE.
6. Update the t9 cases that pinned the shell (`test_open_space_has_no_budget…` asserted APPROACH forever;
   `test_approach_closes_on_the_player`), and the dual-mode mid-corridor case if its geometry needs moving.
7. **One-off demonstrations (recorded, then reverted):** the live-player and outcome rows run against
   (i) the Revision 1 lead (damped 0.6, line frozen at APPROACH start) — expected to fail; (ii) the Revision 2
   numbers (no B1c term) — expected to fail the "> trigger_radius ahead at arm time" clause (27 px); the outcome row's
   result is recorded whichever way it goes.
8. `bash /agent/verify.sh`, `scripts/check-test-leaks.sh`, DECISIONS lines, `bomber/ENEMY.md`.

## Test plan (`tests/integration/test_bomber.gd`; "dual" = parameterised over both harnesses)
Hand-ticked (bomber `_physics_process` + each ordnance's `_physics_process` per tick, player stub moved by the test):
- **(1) dual — rest points vs P̂:** v = (220, 0); every mine's rest point (after the ejection settles) within 40 px of
  the line through the frozen wall P̂ ⟂ v̄; each rest point within 4 px of its planned point.
- **(2) dual — live player:** the middle mine (nearest the player's track) is **more than `trigger_radius`** ahead of
  the live player at its arm time (`(mine − player)·v̂ > trigger_radius`: the player enters the radius after it arms —
  the property B1(c) buys; Revision 2 numbers give 27 px and fail it, F4), and the live straight path passes within
  `trigger_radius` of ≥ 1 mine after that mine armed.
  **Set-up (F1, N7): head-on, never a chase.** Player from (100, 700) → +x at 220; bomber from about (1150, 150)
  (ahead of the player, above its track, nose down), so the line's start comes toward it. Both harnesses use the same
  coordinates. The test **asserts the wall point was not clamped at freeze** (`wall_clamped()` false, P̂ inside
  `inner_rect().grow(−64)`), so a geometry drift fails loudly instead of testing a clamped wall. With the arrival
  prediction (R2-1) the goal is static for a constant-velocity player, so convergence is a property of the planner,
  not of the spawn point; the coordinates are printed.
- **dual — line stands still:** over the last 1.0 s of APPROACH (the epic's wording) the line centre moves < 20 px;
  the APPROACH must itself last ≥ 1.0 s, so the row cannot pass vacuously. A Revision-2 planner (sum capped) fails
  it: its centre rides with the player for all but the last 0.54 s.
- **dual — stationary player → the line passes through P** (≤ 1 px) — GRAVITY (300 px) and, for PURSUIT, the line
  passes `pursuit_launch_range` abeam P at its end.
- **dual — 600 px/s → PURSUIT, never MINE**, with the stub **inside `gravity_range`** so only the speed rule can pass
  it (F3).
- **dual — gravity ray within 30 px of the damped P̂**, the reference computed **by the test** from the RUN-entry
  snapshot (`P + v·lead_factor·min(horizon, d/run_speed)`): a stationary player at 300 px, and a 100 px/s player
  moving along the bearing (toward the bomber). A wrong lead formula (undamped, or none) moves the line off it.
- **dual — pursuit launched toward P̂ ± 10°.**
- **Assault — edge:** player at x = 1320 (60 px from the right edge) moving right: every planned and actual rest point
  inside `inner_rect().grow(−64)`.
- **dual — choice rule:** 220 → MINE; stationary at 300 px → GRAVITY; stationary at 800 px → PURSUIT (jitter 0).
- **dual — approach arrives within 15° of the line's heading.**
- **dual — ESCAPE:** velocity heading change per tick ≤ escape rate·dt + ε; distance to a stationary player grows on
  every tick of ESCAPE — for a GRAVITY run (player at 300 px) **and a PURSUIT run (player at 800 px)** (F2).
- **Assault — budget expiry mid-RUN:** every planned mine is dropped, then RUN → DISENGAGE (never ESCAPE).
- **Open Space — loop:** APPROACH → RUN → ESCAPE → REPOSITION → APPROACH; **Assault:** ESCAPE → DISENGAGE.
- **StateLight** ARMED only in RUN.

Real physics frames:
- **B1(d) outcome, dual:** a stub with a real `HurtBox` (layer 128, mask 1281; the mode's own player hurtbox circle —
  13.5 px for the Assault fighter, 5 px for the Open Space ship, R2-4) flying
  straight at 220 px/s is entered by ≥ 1 `ContactBlast` (counted on `area_entered` where `area is ContactBlast`, so
  the bomber's own layer-256 contact box can never score — F7); the same stub turning 90° at RUN entry is entered by
  none (window: the last mine's arm time + 2.5 s). Head-on set-up as in (2), unclamped-at-freeze asserted.
  At `mine_speed_max` (440): **Open Space only** — the Assault fighter tops out at 400 px/s (`move_state.gd`), and the
  wall's 972 px lead at 440 px/s cannot sit unclamped in the 1352 px grown rect with a straight approach; the clamp
  side is the edge row's job (N7, stated in the test).
- **Attack-in-budget (§2.9.4):** a real `WaveManager` + `ArenaCamera`, one wave `b.bomber().at(0, −400)` (no rail;
  spawns at (640, −440)), stub at camera centre and 200 px past it, stationary and moving sideways at 220 (the stub is
  not clamped; it keeps going, and P̂ pins to the grown rect's edge almost at once — the realistic Assault case): RUN
  entered before `engage_seconds`; time-to-RUN and runs per life printed. The harness is **file-local** to
  `test_bomber.gd` (N9: t13/t17 keep their own; a shared helper would couple parallel tasks).
- **Boundary:** the shipped-config inequality from t9 stays; the new gravity inequality (R2-2) is asserted beside it;
  `pool_size_for` stays green.

Gates that must stay green: contact damage/geometry, hurtbox geometry, config isolation, single writer (empty
allowlist), signal arity, sprite transparency, UID, project load; `scripts/check-test-leaks.sh` clean.

## Risks
- Dubins re-plans near the start can pick a loop when the line shifts laterally; mitigated by the on-line entry rule
  and `approach_cap`.
- Real-time rows (outcome, attack-in-budget) cost ~30–60 s of suite time.
- The corridor's edge pressure can bend an Assault lead-in near the rect edge (edge test).

## Out of scope
Hub idle states (t19), art (t11), level-1 migration (t21), docs beyond `bomber/ENEMY.md` and DECISIONS (t23).

## Changes in Revision 2 (review round 1)
| Finding | Change |
|---|---|
| F1 (blocking) | Head-on set-ups; unclamped-at-freeze asserted (`wall_clamped()`); the stand-still row measured over the unclamped window (≥ 0.4 s); `mine_horizon` unchanged |
| F2 (blocking) | PURSUIT line passes beside P̂ (abeam the end at `pursuit_launch_range`); ESCAPE row gains a PURSUIT case with per-tick growth |
| F3 | `|v̄| > mine_speed_max` → PURSUIT at any distance; the 600 px/s stub sits inside `gravity_range` |
| F4 | (2) asserts the middle mine is > `trigger_radius` ahead of the player when it arms |
| F5 | `approach_cap` takes the next kind in the cycle |
| F6 | Gravity bomb inherits the heading (no cone); the reference P̂ is computed by the test; the moving case is stated |
| F7 | Count `area is ContactBlast` only; stub hurtbox = the player's 13.5 px circle, mask 1281 |
| F8 | Moving stub not clamped (stated); harness file-local; stall guard `L/run_speed + 0.25`; DECISIONS lines for the guard and the gravity overfly |
| also | GRAVITY / PURSUIT `dir` is chosen once per APPROACH (a live bearing would rotate the line every re-plan) |

## Changes in Revision 3 (review round 2)
| Finding | Change |
|---|---|
| R2-1 (blocking) | Only `c` is capped by `mine_horizon`; every re-plan iterates the arrival prediction 3× (`T` ≤ `approach_cap`); the stand-still row measures the last 1.0 s of an APPROACH that lasts ≥ 1.0 s |
| R2-2 | `gravity_release_lead` 80 → 120, inequality asserted next to t9's |
| R2-3 | Tie-break: toward the corridor centre in Assault, else an `rng` side; the PURSUIT clamp acts on the offset line's anchor |
| R2-4 | Stub hurtbox per mode (13.5 px Assault, 5 px Open Space) |
| R2-5 | DECISIONS line next to B1(e) |

## As built (2026-10-11)
Where the build departs from Revision 3 (each also logged in `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md`,
"Phase 4, built in t10"):
- **Arrival prediction:** the 3x fixed-point iteration diverged from a standing start (T 4.9 -> 9.1 s, the goal
  running away). Replaced by the earliest-feasible scan (T in 0.1 s steps up to `approach_cap`, then 5 bisections),
  with a flight time that includes accelerating from the current speed. The tracked path is only swapped when its goal
  moved > 24 px or the bomber is > 40 px off it.
- **Line capture (new):** the last stretch (<= 96 px / 45 deg off the line, from 160 px before its start) pursues a point
  80 px ahead on the line; no fresh curve there, and the time left goes negative past the start.
- **Angled side and angle:** the shorter lead-in side (the heading / corridor / rng rule is the tie-break), and the angle
  narrows 35 -> 0 deg in four steps to the widest loop-free lead-in. At 35 deg a bomber within ~880 px of P-hat is beside
  the line's start, so the plan's close GRAVITY rows (300 px) were unflyable without a ~6.4 s loop.
- **Test set-ups:** close GRAVITY rows use a nose-on bomber 300 px above the player; the Assault edge row spawns the bomber
  at (1000, -300) (from (900, 0) the clamped wall at x = 1316 needs a loop). Row (2) also asserts the run is a MINE run
  with mines, so it cannot pass vacuously.
- **Step 7 results:** Revision 2 numbers: middle mine 42.9 px ahead at arm time (fails `> 80`), the outcome row still
  passes (t6's overlap poll). Revision 1 lead: no wall is laid from the head-on set-up (no RUN in 9 s in Open Space;
  Assault's `approach_cap` cycles to a gravity run), so (2) and the outcome row fail in both harnesses.
- **Test wall clock (attempt 6):** the harness's verification gives up at about 300 s, and at 1x the real-physics rows
  (blast outcome, attack-in-budget) took the gate to 348 s, so attempts 2-5 were reverted with every test green. Those
  rows and `test_enemy_ordnance.gd` now run 8x faster with the physics step kept at 1/60 game-second (the
  `test_level1_fighter_fire_density.gd` pattern); the gate takes about 244 s. Measured outcomes are unchanged apart
  from the +200 px stationary attack-in-budget row (RUN after 2.33 s, was 2.25 s; a one-frame spawn shift).
