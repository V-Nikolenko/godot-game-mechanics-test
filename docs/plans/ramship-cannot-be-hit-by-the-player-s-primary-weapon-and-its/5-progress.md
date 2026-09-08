# Progress

- [x] 1. Wrote `tests/integration/test_ram_ship.gd` (4 cases: config max_health application,
  armoured-phase mask exclusion, armour-strip transition, post-strip damage). Confirmed
  `test_applies_config_max_health_on_ready` failed against pre-fix code (`health.max_health` read
  100, not 999); the other three characterize existing, intentional behaviour and passed
  unchanged.
- [x] 2. Applied `config.max_health` in `RamShip._ready()` (`ram_ship.gd:16-19`), matching every
  sibling config-driven enemy. All 4 new tests pass.
- [x] 3. Fixed `docs/enemy-roster.md`'s ram entry — replaced `**HP:** Medium` with a line naming
  the armour gimmick, consistent with `ram_ship/ENEMY.md` (already accurate, unchanged).
- [x] 4. Full GUT suite: 359/359 passing. `bash /agent/verify.sh` → GATE PASS.
  `scripts/check-test-leaks.sh` → LEAK CHECK PASS.

**Resume at:** done.
**Deviations from plan:** none. Reviewer's two non-blocking style nits both applied (tightened the
roster HP line wording; no code citation was load-bearing so nothing else changed).
