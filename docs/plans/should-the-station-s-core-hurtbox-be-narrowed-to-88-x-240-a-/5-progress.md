# Progress

- [x] **Step 1 — premise first.** Two physics tests appended to
  `tests/integration/test_space_station.gd`
  (`test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core`,
  `test_a_real_bullet_damages_the_core_once_the_armor_is_broken`) plus the `BULLET_SCENE`
  preload, `_LANE_TURRET_INDEX` and the `_fire_bullet_at()` helper. File went 9/9 → 11/11.
  Non-vacuity checked by mutation: cutting the frame budget from 12 to 2 turns all three of the
  load-bearing assertions red (turret 120 ≠ 70, no `armor_deflected`, core 600 ≠ 550).
- [x] **Step 2 — the sweep.** New `tests/integration/test_enemy_hurtbox_geometry.gd`, 6 tests /
  141 asserts, green on the current tree.
- [x] **Step 3 — confirm the guards bite.** Three mutations run and reverted; see the table below.
  No `.tscn` was edited at any point — the 88x240 proposal is applied to the *instance*.
- [x] **Step 4 — docs at the entity.** `ENEMY.md`: the "Known coverage gap — still open" block is
  now "now closed for the bullet path" and names what is still uncovered (rocket/asteroid mask
  bits, incoming laser ray); new section **"Core hurtbox: why it spans the whole hull, and why
  88 x 240 was rejected"** with the decision, the rejected alternatives, and the load-bearing
  dependency note cross-linked to the open backlog item; `Files` lists the new test. Reviewer note
  N6 done too: `test_space_station.gd`'s own header docstring updated to match.
- [x] **Step 5 — gate + leak check.** `bash /agent/verify.sh` -> **GATE PASS**, 35 scripts / 313
  tests / 1413 asserts, all passing. `bash scripts/check-test-leaks.sh` -> **LEAK CHECK PASS**,
  nothing leaked (the two new tests `await`, which is the documented trap).
- [x] **Step 6 — `updating-project-docs`.** Five docs touched:
  `tests/README.md` (new section: the eighth invariant test, with the four extension notes; plus
  the space-station family paragraph, whose "proves nothing about collision layers" claim was made
  stale by step 1), `CLAUDE.md` (new fifth invariant check, `test_level_director_polling.gd`
  renumbered to sixth), `docs/architecture/PROJECT.md` (invariant-test list),
  `docs/architecture/modules/assault.md` (the incoming side of the collision pair, next to the
  existing outgoing-side paragraph) and `docs/architecture/modules/global.md` (the
  `HitBox`/`HurtBox` integration recipe now states the coverage rule where someone wiring a new
  entity will actually read it).

**Resume at:** nothing — implementation complete, gate and leak check green.

## Mutation results (step 3)

| Mutation | Expected | Result |
|---|---|---|
| `_covers()` stubbed to `return true` | `test_the_88x240_proposal_fails_this_sweep` red | **Red**, reporting the 75.0 px per-side shortfall |
| `sniper_enemy` removed from `ROSTER` | completeness guard red | **Red**, naming the escaped scene path |
| `_local_rect()` stubbed to `return cs.shape.get_rect()` | vacuity guard red | **Green at first — the plan's guard was too weak.** See deviation 1 |

## Deviations from plan

1. **The vacuity guard was rewritten, stronger than the plan specified.** The plan's
   `test_the_roster_contains_a_scaled_hurtbox_or_this_file_is_vacuous` asserted only that some
   entity has a non-identity hurtbox transform — copied from
   `test_contact_hitbox_geometry.gd:150-165`. That precedent does not transfer: the sibling file
   compares two *transforms* directly, whereas this sweep compares two *rects both built by
   `_local_rect()`*, so dropping the transform composition cancels out on almost every row.
   Measured: with `_local_rect()` stubbed to return the raw shape rect, all six tests stayed
   green — the sweep had silently degraded to comparing raw `Shape2D` sizes and the guard did not
   notice. Replaced with
   `test_the_transform_composition_changes_at_least_one_rect_or_this_file_is_vacuous`, which
   asserts the composition **changes at least one rect**. That mutation is now red. Same test
   count (6).
2. **The completeness guard covers `assault/scenes/allies/` as well as `assault/scenes/enemies/`.**
   The plan said enemies only, but `ally_fighter` is in the roster and lives under `allies/`, so
   enemies-only would have left the one non-`BaseEnemy` row unguarded — the same gap the guard
   exists to close. Two extra lines.
3. **Reviewer notes N1–N9 folded in as specified.** N2: the helper is `_kill_turret(index)`, not
   `_kill_all_turrets()`. N3: `get_directories()`, top level only. N5: 12 frames, asserting on
   `Health` not on frame indices. N7: `health.max_health`, not the literal 600. N9: the turret
   span is derived from each turret's own position + hurtbox radius, not hardcoded at 102.
   N10 (fold the sweep into `test_contact_hitbox_geometry.gd`) declined, as the reviewer also
   preferred: that file's roster carries a `no_hitbox` flag and a `BaseEnemy`-vs-`Node2D` harness
   note that do not apply here, and merging would put two different invariants behind one name.
