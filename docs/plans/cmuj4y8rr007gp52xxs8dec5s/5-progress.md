# Progress
- [x] Step 1 — config `.gd`/`.tres` (new fields, `dash_max_distance` removed, `orbit_correct_speed` 260)
- [x] Step 2 — scene (ContactProfile RAMMING, StateLight, BulletPool, AttackController, mover AUTO + accel/braking/turn); root `_apply_config` builds the pulse pattern, wires `contact_made`
- [x] Step 3 — brain state machine (amendments A2, A3 applied)
- [x] Step 4 — tests: test_razor_drone.gd rewritten (31 cases green), test_enemy_dual_mode.gd Razor cases re-pinned (5 green), test_base_enemy.gd map, test_engagement_deadline.gd A4 (3 green). Mutations M1–M6 (COMMIT in feint, pulse on hit, no inner clamp, instant reverse, lane at current pos, lunge at player) each fail ≥ 1 case
- [x] Step 5 — docs: ENEMY.md, enemy-roster.md, assault.md, global.md, DECISIONS t10 section
- [x] Step 6 — verify.sh GATE PASS (1069/1069); check-test-leaks.sh LEAK CHECK PASS

**Resume at:** done.
**Deviations from plan:** FEINT_LUNGE/FEINT_BRAKE show light OFF (plan said CHARGING stays) so the fake reads yellow → dark → the real yellow/white/red; the "fake never shows COMMIT" rule is unaffected.
