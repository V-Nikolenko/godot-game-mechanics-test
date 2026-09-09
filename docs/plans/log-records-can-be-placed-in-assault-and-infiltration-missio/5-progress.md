# Progress

- [x] Step 1 — infiltration player `add_to_group("player")` (`infiltration/scenes/entities/player/player.gd`) + `tests/unit/test_infiltration_player_group.gd`
- [x] Step 2 — `PickupState` autoload (`global/autoloads/pickup_state.gd`, registered in `project.godot`, `tests/helpers/save_sandbox.gd` path added) + `tests/unit/test_pickup_state.gd`
- [x] Step 3 — `PickupBase` `_collect_any` + `persistent_id` (`global/pickups/pickup_base.gd`) + `tests/unit/test_pickup_base.gd`
- [x] Step 4 — placed `InfoLogInteractable` (as node "LogRecord") in `level_1.tscn` (520, 240) and
      `TestIsometricScene.tscn` (260, -120) + `tests/integration/test_log_record_mission_placement.gd`
- [x] Step 5 — `bash /agent/verify.sh` -> GATE PASS (435/435 tests, 2084 asserts) and
      `bash scripts/check-test-leaks.sh` -> LEAK CHECK PASS

**Resume at:** done — invoke `updating-project-docs`, then `set-state ... done`.

**Deviations from plan (found during implementation, after both review rounds approved):**
The group-membership fix alone did not make the infiltration player physically reachable —
`InfoLogInteractable`/`PickupBase`'s Area2Ds only fire `body_entered` for a body whose
`collision_layer` overlaps their `collision_mask` (4, "environemnt_player"), and
`infiltration/scenes/entities/player/player.tscn`'s `CharacterBody2D` set no `collision_layer` at
all (Godot default: layer 1). Neither review round caught this because the plan's own test
strategy calls `_on_body_entered()` directly, which bypasses physics. Fixed by adding
`collision_layer = 4` to the `Player` node, and added
`test_test_isometric_scene_log_record_detects_the_real_player_via_physics` (real physics overlap,
no direct method call) to `tests/integration/test_log_record_mission_placement.gd` — confirmed by
hand that this test fails without the `collision_layer` line and passes with it.
**Deviations from plan:** none — the plan was already reordered (round-2 review) to build PickupState before PickupBase.
