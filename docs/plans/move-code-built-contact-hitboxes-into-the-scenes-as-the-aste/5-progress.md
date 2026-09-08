# Progress

- [x] Step 1 — confirmed baseline gate green (`bash /agent/verify.sh`, 379/379 tests passing)
- [x] Step 2 — `base_enemy.gd`: add `contact_hit_box` onready var, delete `_add_contact_hitbox()` and its call
- [x] Step 3 — bomber, gunship, light_assault_ship, ram_ship, space_station, interceptor, sniper_enemy: scene node + script re-apply.
      Verified: `test_contact_hitbox_geometry.gd` 3/5, `test_enemy_contact_damage.gd` 2/3 — the
      only failures are drone_interceptor/kamikaze_drone ("no contact HitBox"), exactly the
      expected mid-sequence state per the round-2 review.
- [x] Step 4 — drone_interceptor: scene node (layer 256/mask 128/damage 30) + script edit.
      Verified: both test files back to green (5/5, 3/3) once drone_interceptor migrated.
- [x] Step 5 — kamikaze_drone: scene node (layer 256/mask 128/damage 30) + script edit.
      Verified: both test files 5/5, 3/3 (ally_fighter still on the old runtime path, unaffected
      since it's not a BaseEnemy).
- [x] Step 6 — ally_fighter: scene node (layer 64/mask 0/damage 25), `_contact_hit_box` onready
      var, deleted `_add_contact_hitbox()`.
- [x] Step 7 — bonus_drone.gd: deleted the now-pointless `_add_contact_hitbox() -> void: pass`
      override; bonus_drone.tscn needed no edit (confirmed no ContactHitBox node).
- [x] Step 8 — confirmed `grep -rn matching_shape --include=*.gd` has zero real callers (only the
      definition + two test-file comments); deleted `HitBox.matching_shape()` from
      `global/components/hitbox_component.gd`.
- [x] Step 9 — full suite: `bash /agent/verify.sh` → GATE PASS, 379/379 tests passing, 1937 asserts
- [x] Step 10 — refreshed stale comments in `test_contact_hitbox_geometry.gd` and
      `test_enemy_contact_damage.gd` (header prose + two inline comments each); no assertion
      changed
- [x] Step 11 — `updating-project-docs`: updated `CLAUDE.md`, `docs/architecture/PROJECT.md`,
      `docs/architecture/modules/global.md` (rewrote the Hurtbox/Hitbox section to describe the
      scene-authored pattern, dropped the code-sample using the deleted factory),
      `docs/architecture/modules/assault.md`, `assault/scenes/enemies/bonus_drone/ENEMY.md`,
      `assault/scenes/enemies/space_station/ENEMY.md` (two sites) and `tests/README.md` (two
      sections). Confirmed by `grep -rn "matching_shape|_add_contact_hitbox"` across the repo:
      zero hits outside `BACKLOG.md` and `docs/superpowers/` (historical logs, correctly left
      untouched). Full gate re-run after the doc pass: GATE PASS, 379/379.

**All steps complete.**
**Deviations from plan:** none.
