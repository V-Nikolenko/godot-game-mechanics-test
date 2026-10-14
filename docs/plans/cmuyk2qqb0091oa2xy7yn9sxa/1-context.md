# Context — t17 Ram Corvette charge (task `cmuyk2qqb0091oa2xy7yn9sxa`)

Epic `cmufs7ele0015nm2xvag3vrwc` (Enemy rework phase 4). Approved epic plan:
`docs/plans/cmufs7ele0015nm2xvag3vrwc/3-plan.md` (Revision 2) §2.6.2, §2.6.3, §2.9.4 and the t17 row of §4.
The t16 armour task built the shell this task fills (`docs/plans/cmuyk2qq8008xoa2xxoq1frgn/`). Code at HEAD `5505090`.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/ram_corvette/ram_corvette_brain.gd` | t16 shell: `Phase { APPROACH, LINE_UP, WIND_UP, CHARGE, WIDE_TURN, DISENGAGE }`, `enter_phase` seam, `phase_changed(new_phase: int)`, APPROACH = `mover.intercept(target, cruise, 0.5)`, `EngagementBudget`, DISENGAGE = nearest-edge exit (Bomber/Sniper copy) | Filled in: LINE_UP / WIND_UP / CHARGE / WIDE_TURN, stagger, exposed stats, evasion, Assault side offset, attack gate, per-state expiry, straight exit |
| `assault/scenes/enemies/ram_corvette/ram_corvette.gd` | Plates, hull deflect rule, `plate_broken` / `armor_broken` (deferred `_expose`), `_apply_config` (mover caps, shove from config), contact damage 50/60 | Must tell the brain about a plate break and exposure; plate glow helper |
| `ram_corvette_config.gd/.tres` | Flat config: armour, `cruise_speed` 280, `acceleration` 500, `max_turn_rate` 2.2, `engage_seconds` 4.5, `exit_speed` 500 | Charge fields appended |
| `global/enemy_ai/enemy_mover.gd` | Single writer; `request_velocity`, `add_nudge`, `face_toward`, `boost(dir, speed, duration)` (ignores requests/max_speed/accel; constraint still applies), `is_boosting()`, `braking` field, `max_turn_rate` caps rotation only | Charge = `boost`; LINE_UP turns via `face_toward` |
| `global/enemy_ai/steering.gd` | `clamped_lead_time`, `turn_toward`, `strafe`, `intercept` | Lead, wide turn, evasion |
| `global/enemy_ai/engagement_budget.gd` | `update`, `remaining()` (INF outside Assault), `seconds` writable (tests' expiry seam) | Attack gate and per-state expiry |
| `global/enemy_ai/target_info.gd` | `predicted_position(t)`, `facing` (UP.rotated(rotation)), `velocity` | P̂ and the evasion cone |
| `global/components/armor_plate.gd` | `set_glow(0..1)` modulates the plate sprite toward warm yellow | WIND_UP glow |
| `global/components/contact_profile.gd` | ARMOR: armed at setup, `set_armed`, `shove_speed` | Disarm outside CHARGE once exposed |
| `global/components/state_light.gd` | `set_state`, `blink_once` | CHARGING / COMMIT / blink |
| `assault/scenes/systems/assault_corridor_constraint.gd` | `inner_rect()` = visible rect x −100..1380, y −380..1100 | P̂ clamp; side choice |
| `assault/scenes/levels/edelia/1/level_1_director.gd` | 22 ram rows: (0, ±400), (±255/±270/±260/±220, −400), (±200/±180, 400) design units | Attack-in-budget classes (derived live, as t13 did) |
| `tests/integration/test_ram_corvette.gd` | t16's 20 armour tests | Extended with the t17 rows; the exposed-contact case changes (exposed contact is now armed only in CHARGE) |
| `tests/integration/test_enemy_dual_mode.gd` | Corvette approach-identical-in-both-modes case | The Assault side offset makes the approach mode-specific by design: the case must zero the offset |
| `tests/integration/test_sniper.gd` §"Attack in budget" | Real `WaveManager` + `ArenaCamera` harness, offsets read from `Level1Director._build_sections()` | Copied locally (review N9: harness local) |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `SniperBrain._request_disengage` / `disengage_pending` | The deferral shape (expiry in a committed phase waits for its end) |
| `GatlingInterceptorBrain._first_side` | Corridor side tie-break precedent (exact centre → +1) |
| `SwarmDroneBrain` attack gate | `budget.remaining() >= …` before starting an attack |
| `test_sniper.gd::_budget_run` | Attack-in-budget harness to copy |
| `test_ram_corvette.gd::_knockback_player`, `_strip`, `_count` | Contact/shove stubs and plate stripping |

## Conventions that constrain this

- Brain only requests; `EnemyMover` is the single writer (empty-allowlist gate). Field writes on the mover (`max_speed`, `braking`, `release_constraint()`) are allowed.
- No `Timer`: accumulate delta. Randomness only from `rng`.
- Config flat, `.tres` wins; `privatise()` copies.
- Signals declared with emitted arity.
- `Phase` values fixed by t16; t19 appends IDLE / NOTICING / RETURNING later.
