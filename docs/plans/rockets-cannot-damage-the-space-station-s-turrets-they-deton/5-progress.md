# Progress

- [x] Step 1 — `_hit_is_deflected()` guard added to `assault/scenes/projectiles/missiles/homing/homing_missile.gd`
- [x] Step 2 — identical guard added to `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd`
- [x] Step 3 — `tests/integration/test_station_incoming_damage_paths.gd`:
      - renamed/rewrote `test_a_rocket_up_a_turret_lane_dies_on_the_armored_core_and_never_reaches_the_turret`
        to `test_a_rocket_up_a_turret_lane_survives_the_armored_core_and_damages_the_turret_behind_it`,
        asserting `armor_deflected` still fires, the core takes 0, the turret takes `HOMING_DAMAGE`,
        and the missile is spent on the turret.
      - **Deviation from plan**: the plan said `test_a_real_rocket_is_deflected_by_the_armored_core_rather_than_missing_it`
        (centre lane, no turret behind it) could stay "passing unmodified". Running it after the fix
        showed this was wrong — its last assertion (`assert_false(is_instance_valid(missile), "the
        missile is spent on the deflect")`) is itself the bug being fixed: a deflected rocket must
        *not* be consumed, so on a lane with nothing behind the core it now simply keeps flying.
        Updated the assertion to `assert_true(is_instance_valid(missile), ...)`, matching the same
        "deflected does not consume" rule `bullet.gd::_hit_is_deflected` already establishes.
- [x] Step 4 — `ENEMY.md` rocket paragraph and load-bearing-dependency section updated (see below).
- [x] Step 5 — gate: see verification.

**Resume at:** done.

**Deviations from plan:** the one noted above (a pre-existing test's assertion, not called out in
the plan's build sequence, had to flip along with the CHARACTERIZED one, for the same reason).
