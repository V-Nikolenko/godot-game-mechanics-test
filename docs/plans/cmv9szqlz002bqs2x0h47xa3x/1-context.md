# Context: t11, the Support Ship's ward selection, follow, retarget and Assault clamp

Epic plan: `docs/plans/cmufs7elw001pnm2xr3b6fteb/3-plan.md` §2.12 (this task), §2.11 (t10 shell), §2.5 (t4 view rect),
§2.4 (`is_ai_driven()`), §4.1, §4.3 (approved). This file records only what in the code the build leans on.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/support_ship/support_ship_brain.gd` | t10 minimal brain: SEEK_WARD = hold `follow_distance` from `nearest_ally()` (any live `BaseEnemy`, never a support) or stand still; Assault budget → DISENGAGE (Bomber exit); `on_suspended()` drops `ward`, folds the projector; full append-only `Phase` enum; `phase_changed(new_phase: int)` | The file this task fills in |
| `assault/scenes/enemies/support_ship/support_ship.gd` | `SupportShip`: config onto health/mover/brain, `can_be_repaired()` false, `fold_projector()` | Unchanged except docs |
| `assault/scenes/enemies/support_ship/support_ship_config.gd/.tres` | Every §2.11 field already authored (Follow, Ward, Assault groups included) | All numbers read here; no new field |
| `assault/scenes/enemies/base_enemy.gd` | `is_ai_driven()` (brain + mover, not suspended), `suspend_ai()`, `score_value`, `counts_toward_wave_clear` (from config in `_ready`), `health`, `died` | Candidate filter |
| `global/enemy_ai/enemy_world.gd` | `has_view_rect(tree)` / `view_rect(tree)` (t4, duck-typed on `enemy_view_rect`) | Assault clamp, view filter, `is_supporting()` |
| `assault/scenes/systems/arena_camera.gd` | `enemy_view_rect()` = centre `global_position + offset`, viewport size / zoom; reads the same frame | The harness's real provider: an `offset` change is seen at once |
| `global/enemy_ai/enemy_mover.gd` | `arrive`, `add_nudge` (summed onto the primary, capped at `max_speed`), `face_toward` | All FOLLOW motion |
| `global/enemy_ai/steering.gd` | `break_contact(pos, threat, threat_vel, side, speed)` | Evasion term |
| `global/enemy_ai/target_info.gd` | `player(tree)` → `has_target`, `position`, `velocity` | Threat score, anchor, evasion |
| `global/enemy_ai/engagement_budget.gd` | `active` = an `assault_arena` provider exists | Assault-only grace |
| `tests/helpers/fixture_enemy.tscn` | `BaseEnemy` with mover + `fixture_brain.gd`: `is_ai_driven()` true, `score_value` 0 (no config), 10 HP | Cheap candidate when the test sets `score_value` |
| `tests/helpers/enemy_ai_harness.gd` | Open Space = player only; Assault adds a real `ArenaCamera` at (640, 360) → view (0, 0)–(1280, 720), corridor y −380..1100 | Every dual row |
| `tests/integration/test_support_ship.gd` | t10 rows; four rows rely on "a fixture ally (score 0) is held in Assault for > 1.5 s", which §2.12's grace changes | Rows to re-point (below) |
| `tests/integration/test_enemy_dual_mode.gd` `test_support_ship_holds_near_an_ally_in_both_modes` | Same reliance (300 ticks in Assault with a score-0 ally) | Re-point to a real ward |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `nearest_ally()` (t10) | The SEEK_WARD fallback stays exactly this |
| `FighterBrain._mates()` | Group scan + filter shape |
| `mover.arrive` + `mover.add_nudge` | Anchor seek plus jink and evasion terms, summed and capped by the mover (no new maths) |
| `Steering.break_contact` | Evasion |
| `EnemyWorld.view_rect` | The one source of "what the camera shows now" |

## Conventions that constrain this

- Brain requests only (`test_enemy_mover_single_writer.gd`, empty allowlist): no `actor.velocity` / `rotation` writes.
- Clocks are accumulated `delta`; randomness from `brain.rng`; the player only through `TargetInfo`.
- `signal ward_changed(new_ward: Node)` emitted with exactly one argument (signal-arity sweep).
- Tests: dual-mode `use_parameters(["open_space", "assault"])`, harness built in the body, hand-ticked; GUT allotment 4.0 s.
