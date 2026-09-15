# Escape-combo penalty: scope it to enemies that are meant to punish a miss

## Problem

Today, `ScoreTracker` multiplies the combo by `escape_combo_multiplier` (0.75) whenever **any**
enemy leaves the tree unkilled, with no way to opt out. That is right for ordinary enemies and
(per a previous, deliberate, tested cycle) right for station reinforcement squads. It is wrong for
the bonus drone: its own header comment promises "no penalty for missing it," but the code pays
the same 0.75× penalty a missed drone would as any other escaped enemy — so a player who whiffs a
rare bonus target is punished exactly as if it were a real threat they failed to stop, which
contradicts the mechanic's own stated purpose (a free, low-stakes bonus opportunity).

Station reinforcements' double penalty (0.75 × 0.75 = 0.5625 per ignored squad) is **not** changed
by this plan — that is an already-deliberated, tested design choice
(`test_station_reinforcements.gd`, commit `9079a20`), not a bug, and this task's own body frames it
as already accepted.

## Design

Add a second, independent opt-out flag — `counts_as_escape` — mirroring the exact existing
`counts_toward_wave_clear` pattern, so the escape penalty and the wave-clear tally can be
controlled separately per enemy type:

1. `global/resources/ship_config.gd`: `@export var counts_as_escape: bool = true`, default `true`
   so every existing enemy (including reinforcement ships, which have no config override) keeps
   today's behaviour with zero code change on their part.
2. `assault/scenes/enemies/base_enemy.gd`: propagate it in `_ready()` next to
   `counts_toward_wave_clear`, from the enemy's own `config` (same generic `get("config")` idiom
   already there — no per-subclass wiring).
   - Add `var counts_as_escape: bool = true` alongside the existing `counts_toward_wave_clear` var.
3. `assault/scenes/enemies/bonus_drone/bonus_drone_config.tres`: add `counts_as_escape = false`.
4. `assault/scenes/systems/score_tracker/score_tracker.gd`:
   - `_on_enemy_spawned()`: read `counts_as_escape` with the same `enemy.get(x) != null` fallback
     idiom as `counts_toward_wave_clear` (default `true` — covers `AsteroidBase`, reinforcement
     ships, and anything else with no such property).
   - Bind it into `_on_enemy_freed()` alongside `counts_in_wave`.
   - `_on_enemy_freed()`: keep the wave-tally-escaped bookkeeping unconditional (that's a separate
     concern — whether a wave-clear bonus is still payable), but gate the
     `_combo *= score_config.escape_combo_multiplier` line and its `combo_changed` emit behind
     `if counts_as_escape:`.

### Alternative rejected

A hardcoded `if enemy is BonusDrone: return` special case in `ScoreTracker`. Rejected because the
task body explicitly asks for a general flag "rather than a special case for one enemy source,"
and because `ScoreTracker` already knows nothing about concrete enemy classes (it reads
`score_value`, `counts_toward_wave_clear` etc. structurally) — a type check would break that.

### Alternative rejected: also exempt station reinforcements

Rejected — see Problem section and `1-context.md`'s "Decision this plan must make". Changing
already-deliberated, tested balance on no new information is exactly the design call the task body
defers to the user ("Recording it so the user can overrule"). This plan implements the mechanism
generally enough that flipping reinforcements' flag later is a one-line change if the user decides
to overrule that earlier call — but does not make that call itself.

## Build sequence

1. Add `counts_as_escape` to `ShipConfig`, `BaseEnemy`, and `bonus_drone_config.tres`.
2. Update `ScoreTracker` to read and honour the flag.
3. Tests (GUT, `tests/`):
   - `tests/unit/test_score_tracker.gd` (or wherever `ScoreTracker` unit tests live — check before
     creating a new file): a fake/stub enemy with `counts_as_escape = false` that leaves the tree
     unkilled must NOT change `_combo`.
   - A control case: an enemy with `counts_as_escape` unset (no such property, like today's
     `AsteroidBase`) still pays the penalty on escape — the default-true boundary.
   - A regression assertion that `test_station_reinforcements.gd`'s existing
     `test_a_squad_that_flies_through_costs_two_escape_combo_penalties` still passes unmodified
     (no new test needed — just don't touch that file).
4. Run `bash /agent/verify.sh`.

## Test plan

- New: bonus-drone-shaped enemy (or a minimal test double with `counts_as_escape = false` and
  `counts_toward_wave_clear = false`, matching the real config) escapes → combo unchanged.
- New boundary case: enemy with neither property set (default fallback) escapes → combo still
  multiplied by `escape_combo_multiplier` — proves the default preserves current behaviour instead
  of silently flipping it off for everything.
- Existing: `test_station_reinforcements.gd`'s squad-escape test must pass unchanged, proving the
  reinforcements balance is untouched.

## Risks

- If `BonusDrone` or its mover has any other path that sets `was_killed` incorrectly, the new
  assertion could mask an unrelated bug. Mitigated by testing directly against `ScoreTracker`'s
  public signal contract (`EventBus.combo_changed`) rather than the drone scene end-to-end.

## Out of scope

- Station reinforcements' double penalty — left exactly as `9079a20` shipped it and
  `test_station_reinforcements.gd` pins it.
- Asteroid shards (`big_asteroid.gd`) — these are ordinary combat targets a player is expected to
  shoot; an escaped shard behaving like an escaped enemy is correct, not a bug, and the task body
  does not raise it.
