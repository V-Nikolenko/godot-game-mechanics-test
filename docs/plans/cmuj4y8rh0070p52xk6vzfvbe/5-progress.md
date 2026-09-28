# Progress
- [x] Step 1 — config script + `.tres`; `EngagementBudget.remaining()` + unit cases
- [x] Step 2 — scene + `SwarmDrone` + brain; rosters (contact damage, contact geometry, hurtbox geometry) — gates green
- [x] Step 3 — `tests/integration/test_swarm_drone.gd`: 30 cases green; mutation checks (braking 500 → 3 fail; budget gate off → 1 fails)
- [x] Step 4 — `test_engagement_deadline.gd` reads `swarm_drone_config.tres`, includes `swarm_drone.tscn`
- [x] Step 5 — ENEMY.md, DECISIONS (t8b section), assault.md, global.md
- [x] Step 6 — verify.sh GATE PASS (1017/1017); check-test-leaks.sh LEAK CHECK PASS

**Resume at:** done.
**Deviations from plan:**
- WINDUP gate slack is 0.15 s (`ATTACK_GATE_MARGIN`), so the gate is 1.29 s — covers review round 2 follow-up 1.
- `sprite_forward_angle` stays at `BaseEnemy`'s default (nose-down): the `drones.png` cell's nose points down
  when checked by eye (the plan assumed nose-up). Crop is `Rect2(2,2,38,38)`, inside the sheet's grid marks.
- "Exactly one second pass" does not teleport the player: hand-ticked runs have no physics step, so every burst misses.
- The Open Space control for the budget gate is its own test (two harnesses in one test share the tree's ArenaCamera).
- `test_base_enemy.gd`'s contact-profile sweep assumed every enemy is legacy COLLISION; it now takes a `_AUTHORED_CONTACT_MODES` map (`swarm_drone` → EXPLOSIVE) so the new drone is swept against its declared mode.
