VERDICT: CHANGES_REQUESTED

# Review, round 1: EMP really disrupts (Phase 9 t5)

I checked the plan against epic §2.6, §2.1, §2.5 and "For every task", and read the real code. Most of the design is correct:
- `EmpPulse.emit` keeps its default call bit-identical.
- `PlayerBase.apply_emp` becomes the boost disruption plus `apply_ability_lock`, and the Ph7 `_emp_left` clock is left alone.
- On `BaseEnemy`, `answers_emp()` returns `is_ai_driven()`, and the 1e-6 window clock means the brain is skipped on ticks 1..119 and runs again on tick 120.
- `suspend_ai()` clears a live window.
- The beam-freeing fix in `TwinLaserPair.release` is right. The plan sets `_emp_left` before it calls `on_emp_started()`, so `is_emp_disrupted()` is already true inside `release()`.
- The tender's LAUNCH cancel goes through `enter_phase`, so the light leaves CHARGING on that call.
- `EnemyRocket` joins the group in `launch()` after `_apply_exports()` and leaves it in `_mark_done()` / `reset()`.
- The mine's target expression uses the unqualified `Hostility`, so `enemy_mine.gd` gains no `EnemyMine` token.
- The single-writer rule holds: the plan stops the ship through `mover.halt()` only.

I also confirmed the plan's "risks" claim. Every mover-driven scene's `AttackController` is `driven_by_brain = true` (fighter, gatling, razor). The bomber, corvette and mine layer `_process` hooks are gated on `is_ai_suspended()`, so nothing fires during the window.

Three problems need fixing before build: one test row is wrong against the real fixture, one design gap breaks the brainless path the plan itself guards, and the `halt()` call has no row that can catch its removal.

## Findings

### 1. Major: the `fixture_enemy.tscn` row asserts the wrong value
- **Where:** `tests/helpers/fixture_enemy.tscn` (nodes `EnemyMover` and `Brain`, the last two in the file) and `tests/helpers/fixture_enemy.gd`.
- **The problem:** The plan's `test_answers_emp_follows_is_ai_driven` expects `fixture_enemy.tscn` to answer **false**. But the fixture has a `fixture_brain.gd` Brain and an `EnemyMover`, and it does not override `_physics_process`. So `is_ai_driven()` is true and `answers_emp()` is **true**. The row fails as written. If someone "fixes" it by changing the fixture, many other gates that use this fixture break.
- **Side effect worth noting:** Many existing rows put this fixture in group `enemies` (`test_enemy_mines.gd`, `test_minefield.gd`, `test_energy_ring.gd`, `test_enemy_beams.gd`). It now answers EMP from any `TARGET_ENEMIES` source. I found no current row where a placed EMP mine detonates next to a fixture, so nothing should regress. Run those files in the regression step (step 7). `test_minefield.gd` is not on that list today.
- **Fix:**
  - For the "no brain, answers false" case, use a real legacy enemy (`gunship.tscn` or `bonus_drone.tscn`). Keep `ShieldGenerator` as the "brain, no mover" structure case.
  - Add `fixture_enemy.tscn` as a **true** case.
- **Simpler alternative for the start counter:** The plan swaps a test-only `_CountingBrain extends FighterBrain` onto the Fighter's `Brain` node to count `on_emp_started()` calls. Instead, add `var emp_started_count := 0` and an `on_emp_started()` override to `tests/helpers/fixture_brain.gd`, next to its existing `suspended_count` / `on_suspended()`. Then count on the fixture enemy. That is the established pattern and needs no `set_script` on a shipped scene. Keep the Fighter for the fire / resume rows.

### 2. Major: a brainless enemy that answers EMP never leaves the window
- **Where:** `assault/scenes/enemies/base_enemy.gd`, `_physics_process`: `if _ai_suspended or _brain == null: return`.
- **The problem:** The plan steps the EMP clock "after the existing early return", and that early return includes `_brain == null`.
- **Why it matters:** The plan explicitly guards `apply_emp` "for a subclass override of `answers_emp()` with no brain / mover". That path is real:
  - t6's row is "a fixture enemy answering `answers_emp()` true without a brain goes through `apply_emp`".
  - t7's `JammingStructure` is brainless and answers true.

  Any such enemy that reaches the base `apply_emp` (directly, or through `super`) gets `_emp_left > 0` and the overlay shown. Then its clock is never stepped, so `is_emp_disrupted()` stays true and the `EmpStatic` ring stays on for the rest of its life.
- **Fix (pick one):**
  - (a) Step the window before the brain check:
    ```
    if _ai_suspended: return
    if _emp_left > 0: _step_emp(delta)
    if _brain == null: return
    ```
    Then skip the brain while still disrupted, as planned. Legacy enemies that override `_physics_process` are unaffected, because they never answer EMP.
  - (b) Make the base `apply_emp` return when `_brain == null or _mover == null`, and document that an override must own its whole window.
- **Test:** Whichever you pick, add one row on a brainless stub that overrides `answers_emp()` to true. It must not end up permanently disrupted: either its window ends on tick 120, or the base `apply_emp` refuses it.

### 3. Medium: removing `mover.halt()` would not fail any row
- **Where:** `global/enemy_ai/enemy_mover.gd` (`halt()`, and `boost()` / `step()`, which ignore requests while `_boost_left > 0`).
- **The problem:** `halt()` is what cancels a committed boost. Without it, a ship EMP'd mid-boost keeps flying at boost speed until the boost ends, because a boost ignores the empty request. This applies to a Swarm BURST, a Razor dash, a Ram CHARGE (`ram_corvette_brain.gd:555`) or a twin ADVANCE.
- **Why the planned row misses it:** The only motion row is on a Fighter, which never boosts. It checks "speed < 5 px/s from tick 30 to 119". A Fighter braking at its config rate passes that with or without `halt()`.
- **Fix:** Add a row, in both harnesses, with a boosting enemy EMP'd mid-boost (a Swarm Drone in BURST is simplest; the drone's `is_boosting()` gates exist at `swarm_drone_brain.gd:444`). Assert:
  - on the `apply_emp` call: `mover.is_boosting()` is false and `velocity == Vector2.ZERO`;
  - in Open Space with no hazards: the position is unchanged across the window.
- **Wording:** Because `halt()` stops the ship dead, fix "coasts to a stop" in the Problem section and the docs. Tighten the Fighter row to speed 0 from the EMP tick in Open Space.

### 4. Minor: the Assault corridor still moves an EMP'd ship that is outside the view
- **Where:** `assault/scenes/systems/assault_corridor_constraint.gd`, `filter` / `_apply_axis`.
- **The problem:** Outside the visible rect, before the ship has entered, the filter floors the inward speed at `entry_speed`. An EMP'd ship spawned off-screen therefore keeps moving inward, which is correct (the mover still steps the constraint).
- **Fix:** In the Assault harness, spawn the Fighter rows inside the view, or the "speed < 5" / speed-0 row fails for an unrelated reason. Say so in the row so the implementer does not "fix" the constraint.

### 5. Minor: the re-hit arithmetic is wrong
- **The problem:** `test_the_emp_window_is_exactly_120_ticks_and_the_longest_wins` says "a 3.0 s re-hit at 1.0 s extends to tick 180". With `_emp_left = maxf(_emp_left, seconds)` (the plan's own rule, and the player's `apply_ability_lock` precedent in `test_player_ability_lock.gd::test_timed_locks_longest_wins_and_never_add`), a 3.0 s hit at tick 60 sets 3.0 s remaining. The window ends on **tick 240**: disrupted after tick 239, clear after tick 240.
- **Fix:** Correct the tick numbers.

### 6. Minor: leaving the group on `_mark_done()` is untested
- **Where:** `assault/scenes/projectiles/enemy_rockets/enemy_rocket.gd`, `_mark_done()` and `_end_after_overlaps()`.
- **The problem:** The seeker row checks that a guided rocket leaves `enemy_seeking_ordnance` after `reset()`, but not after a detonation / defuse / lifetime fizzle. A done rocket sitting idle in its pool would still be found by `EmpPulse`. That is harmless today, because `reset()` clears `_jammed`, but it is exactly the group-membership leak this file should pin.
- **Fix:** Add an assertion that a rocket is out of the group right after `_detonate()` (or `_on_expired()`).

### 7. Nit: say how the sweep detects an override
- **The problem:** The plan does not say how `test_every_beam_brain_of_a_mover_driven_ship_overrides_on_emp_started` decides a brain "overrides" the hook.
- **Fix:** Name the matcher, e.g. a source regex `(?m)^func on_emp_started\(` in the brain file. The current matches are `laser_tender_brain.gd` and `twin_laser_drone_brain.gd`, which agree with the plan's boundary row.

## Not findings (checked and fine)
- **Ph7 rows stay green as written:**
  - `test_enemy_mines.gd:1472`: the ALL mine row has no enemies in reach.
  - `test_player_boost_disruption.gd:440`: `_emp_left` keeps the `<= 0.0` clock, ending on tick 121.
  - `test_player_boost_disruption.gd:531`: the Assault H-key Drive row is now refused by the lock before the disruption is read. It is still green and asserts the same outcome. Efficiency coverage of the H-key Drive stays in `test_assault_h_key_boost_drive_follows_the_efficiency`.
- **The `emp_changed` timing** of `[true, false]` after 121 ticks matches the Ph7 clock.
- **Freeing the twin beam:** `queue_free()` on the beam unregisters its `laser_wall` hazard through `EnemyBeam._exit_tree`.
- **The drone tests hand-tick through `drone._physics_process(DT)`** (`test_twin_laser_drones.gd::_step`), and so does `test_fighter.gd::_tick`. Both go through the new EMP branch.

---

VERDICT: APPROVED

# Review, round 2

I re-read the revised `3-plan.md` against the same code. All seven round-1 findings are fixed.

1. **Fixed.** `fixture_enemy.tscn` is now listed as answering true, and a legacy Gunship is the false case. The Gunship has no brain, so `is_ai_driven()` is false; its own `_physics_process` override never reaches the base tick. `on_emp_started` is now counted through a new `emp_started_count` on `tests/helpers/fixture_brain.gd`, next to the existing `suspended_count`. `test_minefield.gd` was added to step 7, with a risk line.
2. **Fixed.** `_physics_process` now runs `if _ai_suspended: return`, then the EMP clock, then `if _brain == null: return`, and steps the mover during the window only when both a brain and a mover exist. The new brainless row can fail on the old order:
   - Setup: the fixture with its `Brain` freed before it enters the tree, plus an `answers_emp()` override. Freeing the Brain means `_resolve_ai()` finds only the mover.
   - Old order: the clock never ticks, so the row's "not disrupted after 120" check fails.

   When no EMP is live, `_emp_left == 0`, so enemies that never answer EMP behave exactly as before. That covers structures with a brain and no mover (defense turret, shield generator).
3. **Fixed.** `test_emp_halts_a_committed_boost_on_the_call` stages a real `mover.boost()` and asserts `is_boosting()` is false and `velocity` is zero on the `apply_emp` call. Without `halt()`, `_boost_left` survives and the row fails. Its control proves the staging still boosts on the next tick. The test drives the mover from the test file, not a brain or a root script, so the single-writer sweep does not see it. The Problem wording now says the ship stops dead.
4. **Fixed.** The Assault Fighter rows now spawn inside the view, so the corridor's `entry_speed` floor never applies.
5. **Fixed.** A 3.0 s re-hit at tick 60 now ends on tick 240.
6. **Fixed.** The rocket is out of the group after `_mark_done()` (detonation), and a DUMB rocket never joins.
7. **Fixed.** The sweep uses the regex `^func on_emp_started\(`, with two boundaries: it finds both shipped brains, and it reports a synthetic source that lacks the override.

## Nits (no change required)
- **Keep the `_mover != null` guard.** In the non-EMP branch of `_physics_process`, keep the existing `if _mover != null: _mover.step(delta)` guard. Structures with a brain and no mover rely on it today.
- **Fighter row name and threshold.** `test_an_emp_d_fighter_fires_nothing_coasts_and_resumes` still says "coasts", and still uses "speed < 5 px/s from tick 30". The halt row now covers the stop, so this is cosmetic. Asserting speed 0 from the EMP tick in Open Space would still be the sharper check.
