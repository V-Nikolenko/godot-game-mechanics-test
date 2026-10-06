# Progress

- [x] Step 1 — tests: pin rows updated in place, `_RAIL_SECTIONS` retirement, `test_migrated_sections_have_no_rail_left`,
  `test_loose_pairs_are_tagged_with_their_wave_index`, `test_a_fighter_line_given_move_again_fails_the_pin`, the count
  gates and their boundary (`tests/integration/test_level1_fighter_spawns.gd`); the measured gate
  (`tests/integration/test_level1_fighter_fire_density.gd`).
- [x] Step 2 — helpers (`tests/helpers/level1_drone_concurrency.gd`); `_razor_deadline` reuses `worst_exit_after_speed`.
- [x] Step 3 — level edit (prototype patch) and wave-comment touch-ups (`level_1_director.gd`).
- [ ] Step 4 — gate + leak check.
- [x] Step 5 — DECISIONS.

**Resume at:** step 4.
**Deviations from plan:**
- `_start()` waits 3 *idle* frames after scaling the clock before `load_section()`. Without it, wave 0 triggers after a
  catch-up physics burst (≈ 0.5 s late in game time). Found by the schedule test.
- The pin's frozen shots/s constant is read through `load()` + `get_script_constant_map()` at the call, not through a
  `const` preload of the pin's GutTest script.
- The Gatling's printed analytic rate uses the brain's `min_window_period()` (2.28 s), not the plan's typed 2.8 s.
