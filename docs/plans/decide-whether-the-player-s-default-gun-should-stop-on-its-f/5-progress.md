# Progress

- [x] Step 1 — Rewrote `test_pierce_module_today_only_reduces_damage` (now
      `test_pierce_module_extends_the_hit_count_before_stopping`), confirmed red against
      pre-change code.
- [x] Step 2 — `bullet.gd`: added `_hit_is_deflected()` and the early-return check in
      `_on_hit_box_area_entered`; rewrote the file's header doc block.
- [x] Step 3 — `weapon_behavior.gd`: `_launch()` now connects `bullet.expired -> bullet.queue_free`;
      rewrote its doc comment.
- [x] Step 4 — `tests/integration/test_player_bullet_lifetime.gd`: retired
      `test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps`, replaced with
      `test_a_launched_bullet_stops_on_its_first_damaging_hit` and
      `test_a_deflected_hit_does_not_consume_the_bullet` (using a new `ArmoredStandIn` stub class
      and a shared `_hurtbox_at()` helper); rewrote the file's top doc block; rewrote the pierce
      test (step 1) to route through `StraightBehavior.fire()` so it actually carries the
      `_launch()` wiring.
- [x] Step 5 — `tests/integration/test_player_bullet_lifetime.gd` (7/7) and
      `tests/integration/test_space_station.gd` (11/11, including both real-bullet tests)
      confirmed green, unmodified for the latter.
- [x] Step 6 — Docs updated: `CLAUDE.md`, `docs/architecture/PROJECT.md`, `tests/README.md`,
      `assault/scenes/enemies/space_station/ENEMY.md`, plus `test_space_station.gd`'s own header
      comment (also stated the now-stale "still open" framing).
- [x] Step 7 — `bash /agent/verify.sh`: GATE PASS, 383/383 tests. Also ran
      `scripts/check-test-leaks.sh`: LEAK CHECK PASS.

**Resume at:** done — ready to commit.

**Deviations from plan:**
- The pierce test's final assertions had to be captured *inside* the loop, right after the 4th hit
  and before that iteration's trailing `await get_tree().process_frame` — that await flushes the
  `queue_free()` the 4th hit just triggered, so reading `bullet.pierces_remaining` /
  `bullet.is_queued_for_deletion()` afterward hit "previously freed" errors. Not a plan error, just
  a detail the plan didn't spell out at that level.
