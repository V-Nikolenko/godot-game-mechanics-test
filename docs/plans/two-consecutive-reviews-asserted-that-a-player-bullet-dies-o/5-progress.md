# Progress

- [x] **Step 1 — tests first.** `tests/integration/test_player_bullet_lifetime.gd` (new, 6 tests).
  Ran it before touching any source and confirmed the intended red:

  ```
  Passing Tests 166 / Failing Tests 2
  - test_a_launched_bullet_frees_itself_when_it_leaves_the_screen   [Failed] x2
  - test_every_weapon_behavior_hands_off_its_projectile_s_lifetime  [Failed] x4
      (LongRange / Sniper / Spread / Straight)
  ```

  Tests 1, 4 and 5 (both halves) passed on the unmodified tree, which is what they are for —
  they pin behaviour that already ships. The four named failures in test 3 also prove the
  class-list enumeration and the N1 `assert_gt(bullets.size(), 0)` guard are live: the behaviours
  were found, they really spawned bullets, and only the lifetime hand-off was missing.

  Two harness corrections against the plan, both found by running it:
  - GUT's `assert_signal_emitted_with_parameters(obj, sig, params, index)` takes an emission
    **index** as its 4th argument, not a message. Passing a string there makes GUT compare a
    `String` to an `int` and the test fails with `Invalid operands 'String' and 'int'`, which
    looks nothing like the real cause. Noted in the test.
  - Round-2 notes N1/N2 applied as written and both were load-bearing: `StubState` needs a script
    for `state.get("actor")` to resolve, and `StubActor` needs a real `velocity` property.

- [x] **Step 2 — `Bullet.free_when_offscreen()`.** `assault/scenes/projectiles/bullets/bullet.gd`.
  Opt-in, guarded by `is_connected`, warns if the notifier is missing. Also gave `bullet.gd` a
  class header stating both lifetime rules and why `expired` must never be wired to `queue_free`
  on the player path.

- [x] **Step 3 — `WeaponBehavior._launch()` + the four spawn sites.**
  `weapon_behavior.gd` gains `_launch(state, bullet)`; `straight_behavior.gd:22`,
  `long_range_behavior.gd:17`, `spread_behavior.gd:21` and `sniper_behavior.gd:87` now call it in
  place of `state.add_child(...)`. Test file went 168/168 green immediately after.

- [x] **Step 4 — docs.** `assault.md`: the ":37" tree line, the `primary_homing/` phantom
  directory (both the tree line and its bullet), the "pooled player bullet / `expired` signals the
  pool" paragraph (rewritten with the ownership rule, the `expired` warning and the
  viewport-vs-arena asymmetry), and the "instantiated by shooters (player, …)" line.
  `ENEMY.md:528-536` and `test_space_station.gd:164-171` repointed off the now-closed task onto
  the new `PierceModule` one plus the two tests that gate it.

- [x] **Step 5 — filed the `PierceModule` balance task**:
  `decide-whether-the-player-s-default-gun-should-stop-on-its-f` (epic `code-health-backlog`),
  with the station coupling copied into the body verbatim so it cannot be orphaned.

- [x] **Step 6 — gates.**
  `bash /agent/verify.sh` → `GATE PASS`, 319/319 tests, 1451 asserts.
  `bash scripts/check-test-leaks.sh` → `LEAK CHECK PASS - suite green, nothing leaked`.

**Resume at:** done — stage 7 (docs skill + backlog tick).
**Deviations from plan:** none of substance. Two harness details the plan could not have known
(the GUT `assert_signal_emitted_with_parameters` index-vs-message trap, recorded in step 1) and
the round-2 notes N1-N5, all applied.
