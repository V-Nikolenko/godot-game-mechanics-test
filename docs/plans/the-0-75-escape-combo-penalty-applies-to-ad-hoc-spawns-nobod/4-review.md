VERDICT: APPROVED

## Findings

All of the plan's factual claims about the codebase check out against the actual files, and the
design addresses the task body verbatim.

1. **Task body match** (`BACKLOG.json:443`, quoted verbatim). The body explicitly frames
   reinforcements' double penalty as "**accepted this deliberately**" and asks only that the
   fix, if made, be "a `counts_as_escape` flag on the spawn rather than a special case for one
   enemy source." The plan does exactly this and nothing more — it does not re-litigate
   reinforcements, and it implements a general flag rather than an `if enemy is BonusDrone`
   branch (`3-plan.md` "Alternative rejected").

2. **The mechanism claim is accurate** — `score_tracker.gd:210-211` multiplies `_combo` by
   `escape_combo_multiplier` unconditionally in `_on_enemy_freed`, outside the
   `if counts_in_wave:` block at line 205. `counts_in_wave` (from `counts_toward_wave_clear`,
   line 134-135) only gates the wave-tally bookkeeping above it, exactly as `1-context.md` states.

3. **Station reinforcements is genuinely deliberate and tested**, not the plan rationalizing
   inaction. `station_reinforcements.gd:252-257` carries an explicit, detailed comment ("That is
   a deliberate balance decision, not an oversight — adds are a combo *opportunity*...") and
   `tests/integration/test_station_reinforcements.gd:394-423`
   (`test_a_squad_that_flies_through_costs_two_escape_combo_penalties`) pins the exact number
   `4.0 * 0.75 * 0.75 = 2.25`. Leaving this untouched is well-supported, not an excuse.

4. **The BonusDrone contradiction is real.** `bonus_drone.gd:1-7`'s header says "no penalty for
   missing it (counts_toward_wave_clear = false)". `level_1_director.gd:143` emits
   `wave_manager.enemy_spawned.emit(entity, -1)` — the same "outside the wave registry" idiom as
   reinforcements — so a missed drone hits the exact same unconditional penalty at
   `score_tracker.gd:211`. `counts_toward_wave_clear = false` (`bonus_drone_config.tres:10`) only
   suppresses the wave-clear tally, not the escape combo multiply. The doc comment describes
   intent the code does not deliver.

5. **No reinvention.** `counts_as_escape` is proposed as an independent flag on `ShipConfig`
   (`global/resources/ship_config.gd:7-13` shows `counts_toward_wave_clear`'s exact existing
   shape to mirror), propagated in `base_enemy.gd:57-64`'s existing generic `get("config")`
   idiom, and read in `score_tracker.gd` with the same `enemy.get(x) != null` fallback already
   used for `counts_in_wave`. It does not fold into or overload `counts_toward_wave_clear`.

6. **CLAUDE.md conventions respected.** Config-driven stats: the flag lives on `ShipConfig`/the
   `.tres`, not hardcoded per class. `ShipConfig.privatise()` (`ship_config.gd:36-39`) does a
   shallow `duplicate()` — a plain `bool` stays flat, satisfying
   `test_config_instance_isolation.gd`. No signal shapes change (`_on_enemy_freed` is bound via
   `.bind()`, not a redeclared signal). Composition over inheritance is untouched — same
   propagation path as the existing flag, no new inheritance introduced.

7. **Default-true boundary and regression are both in the test plan.** The plan calls for (a) a
   `counts_as_escape = false` case that must not touch `_combo`, (b) a control case with no such
   property (mirrors `AsteroidBase`) that must still pay the penalty — the exact boundary the
   review brief called out — and (c) leaving `test_station_reinforcements.gd`'s existing squad
   test untouched as the regression check. These are concrete, executable GUT assertions against
   `ScoreTracker`'s real `_combo` state and `EventBus.combo_changed`, not vague intentions, and
   would fail today (before the fix) since `_on_enemy_freed` currently has no such gate.

8. **No simpler alternative available.** A `wave_index == -1` check can't work — reinforcements
   also spawn at `wave_index == -1` and must keep the penalty, so the two ad-hoc sources need a
   flag independent of the "ad hoc" idiom itself, which is what the plan builds.

Minor, non-blocking observation: no `tests/unit/test_score_tracker.gd` exists yet (verified via
`grep -rl ScoreTracker tests/`), so the plan's "check before creating a new file" instruction will
resolve to creating one from scratch — worth flagging to the implementer but not a defect in the
plan, which already anticipates this ("or wherever ScoreTracker unit tests live — check before
creating a new file").
