# Context — t16-level1-duration (deep_space + planet_approach off rails)

Epic plan: `docs/plans/cmufs7ekv000lnm2x7nbswijy/3-plan.md` §2.9.1–2.9.2 (Revision 2, approved). Built notes for this
task's inputs: `docs/ideas/cmufkkgmx0001o02y6bnf52bq/DECISIONS.md` → "Phase 3, built in t8a / t8b / t9 Revision 3 /
t10 / t11".

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/levels/edelia/1/level_1_director.gd` | `_build_section_1()` (deep_space, 30 s DURATION) and `_build_section_2()` (planet_approach, 110 s DURATION) | 18 + 19 fighter/Gatling lines to strip of `.move()` / `.free_after()` / `shoot_*()`; loose pairs get `.squad(&"w<n>f")` / `&"w0g"` |
| `tests/integration/test_level1_fighter_spawns.gd` | t1 pin (64 rows) + frozen `_LEGACY_PEAK_FIGHTERS` {10, 10, 8} / `_LEGACY_PEAK_SHOTS_PER_S` {31.25, 33.33, 15.0} + the "live equals constant" assertion | the pin is updated in place (movement → false, aim_mode → ""), the live check is retired for these two sections, and the density gates divide by these constants |
| `tests/helpers/level1_drone_concurrency.gd` | interval-overlap arithmetic (`squad_intervals`, `spawn_intervals`, `peak_*`) | the density numerator; already generalised for per-entry lifetimes/rates |
| `assault/scenes/systems/wave_manager/wave_manager.gd` | squad key `"<wave index>:<squad_id or spawn index>"`; attaches `EnemyPathMover` only when `movement` is a `MovementResource` | a formation is one squad; loose lines sharing an id in one wave are one squad |
| `assault/scenes/enemies/fighter/fighter_brain.gd` / `fighter_config.tres` | every member (REAR too) has an `EngagementBudget(engage_seconds 6.0)`; DISENGAGE deferral ≤ telegraph + longest burst; bursts only in RUN_IN (leg a) and TURN (leg b), ≥ `min_burst_period` 1.2 s apart; REARs never fire | fighter lifetime and fire-rate model |
| `assault/scenes/enemies/gatling_interceptor/gatling_interceptor_brain.gd` / config | budget 7.0 s, deferral `spin_up + sync_wait_max + rounds_max × interval` = 2.08 s, `min_window_period()` = 2.28 s | Gatling lifetime and fire-rate model |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `DroneConcurrency.peak_min_alive_three()` shape | per-squad `min(alive, cap)` — the right capable count for fighters, whose REARs live as long as attackers and are promoted as attackers leave |
| `test_engagement_deadline.gd::_razor_deadline` | the Razor-shaped worst exit the epic plan names for fighters (§2.9.3) |
| `test_level1_drone_exit.gd` | real `WaveManager` + `HARNESS.assault()` run shape |

## Conventions that constrain this
- Triggers, offsets, delays and formations stay exactly as pinned; only `.move()`, `.free_after()`, `shoot_*()` go.
- Density denominators are the frozen t1 constants, never recomputed or hand-typed (B6).
- **If a density gate fails, only the three pre-approved levers may be used: fighter `engage_seconds` 6.0 → 4.5, a new
  `assault_passes` 2 → 1, split a 5+ formation into two squads. "Any other change needs the owner."** (epic §2.9.2)

## Measurements taken for this task (prototype level edit, scratch tests, since deleted)

### Analytic density, epic §2.9.2 formulas
Lifetimes: fighter `engage + 0.8 + Razor-shaped exit` = 9.64 s (8.14 s at lever 1); Gatling `7.0 + 2.08 + exit` =
12.00 s. Rate per attack-capable ship, plan formula: fighter `max over modes of count_max / (gap × count_max +
min_burst_period)` = 7 / 1.55 = **4.52** shots/s; Gatling 12 / 2.8 = **4.29**.

| section, engage | all-alive (≤ 2.0 × 10 = 20) | capable (≤ 1.5 × 10 = 15) | shots/s (≤ 1.25 × legacy) |
|---|---|---|---|
| deep_space, 6.0 | 17 ✓ | 13 ✓ | **58.25 ✗** (limit 39.06; 1.86×) |
| planet_approach, 6.0 | 16 ✓ | 14 ✓ | **63.23 ✗** (limit 41.67; 1.90×) |
| deep_space, 4.5 (lever 1) | 17 ✓ | 13 ✓ | **58.25 ✗** |
| planet_approach, 4.5 (lever 1) | 11 ✓ | 10 ✓ | **45.16 ✗** |
| deep_space, 2.0 (not a lever, for scale) | 13 | 12 | 53.73 ✗ |

The same rows with the alternative numerators considered: strict ceiling `7 / 1.2` = 5.83 and Gatling `12 / 2.28` =
5.26 → 74.7 / 81.7 (worse); AIMED-only `5 / 1.7` = 2.94 → deep_space 40.92 ✗ (limit 39.06), planet_approach 41.18 ✓.
The "first three per squad" model and `min(alive, 3)` per squad give identical peaks here.

- Lever 2 (`assault_passes` 2 → 1) cannot move any of these: the lifetime is bounded by the budget, not passes
  (t8b note I8: at 6.0 s an Assault fighter already flies one pass).
- Lever 3 (split a 5+ formation) *raises* the capable count (a 5 split 3 + 2 fields 5 attackers instead of 3).
- deep_space's peak sits at ≈ 8 s: V5 (2.5 s) + V3 (5.5 s) + pair (6.5 s) + Diag5 (8.0 s) + the Gatling pair (0–12 s).
  No budget short of ≈ 1 s clears it, because the waves themselves overlap.

### Real run (scratch GUT test: real `WaveManager`, `HARNESS.assault()`, stationary player at lower centre, only the
fighter / Gatling entries of the section, shots counted as newly-active `EnemyBullet`s in the container)
| run | spawned / left | alive peak | total shots | peak shots/s over 1 s / 2 s / 5 s | min ship separation |
|---|---|---|---|---|---|
| legacy rails, deep_space (HEAD) | 36 / 36 | 10 | 524 | 33.0 / 31.0 / 24.0 | 1.0 px |
| AI, deep_space (prototype edit) | 36 / 36, all in DISENGAGE | 17 | 114 | **21.0 / 12.0 / 6.0** | 50.4 px at 7.6 s (hull Ø 57.2) |
| legacy rails, planet_approach (HEAD) | 41 / 36 | 10 | 1029 | 36.0 / 35.0 / 28.0 | 0.0 px |
| AI, planet_approach (prototype edit) | 41 / 41, all in DISENGAGE | 10 | 114 | **13.0 / 6.5 / 4.0** | 54.0 px at 84.3 s |

The legacy 2 s window (31.0) reproduces the frozen constant (31.25), so the measurement method is sound. The AI fires
**about a fifth** of the legacy shots and its real 1 s peak is 0.64× legacy — the analytic gate's 1.86× comes from
modelling every capable fighter as firing at its burst ceiling continuously, while in Assault each one fires about
one burst in its life (t8b note I8).
