# Progress
- [x] Step 1 — tests first: pin flipped to `movement: false` (121 rows), no-movement + exit_mode case, re-given-.move()
  boundary, grouping rule case, C3 ratio case + helper boundary, `test_level1_drone_exit.gd` (main + rail boundary).
  Red on the old director: 4 failures (pin, no-movement, grouping, exit).
- [x] Step 2 — director: `.move()` stripped from 119 `b.drone()` lines, 2 `.free_after(5.0)` dropped, 97 loose lines
  tagged `.squad(&"w<n>")`; header note. Diff touches only `b.drone()` lines (plus the header comment).
- [x] Step 3 — C3: capable 17/7/7 (1.21/1.17/1.40 ×), all 23/9/10 (1.64/1.50/2.00 ×). No lever pulled.
- [x] Step 4 — exit test green (8.0–8.4 s over 4 runs, timeout 10 s); check-test-leaks.sh PASS (1088/1088); verify.sh GATE PASS
- [x] Step 5 — docs: enemy-roster.md drone entry + Quick Rules, swarm_drone/ENEMY.md spawn notes, DECISIONS t15 section

**Resume at:** done.
**Deviations from plan:** none
