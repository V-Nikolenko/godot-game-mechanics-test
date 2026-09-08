# Progress

- [x] Step 1 — added `test_every_contact_hitbox_is_typed_as_contact_damage()` to
      `tests/integration/test_contact_hitbox_geometry.gd`, confirmed it fails against pre-fix code
      (10/10 roster entries typed LASER).
- [x] Step 2 — added `dmg_type: DamageType = DamageType.CONTACT` parameter to
      `HitBox.matching_shape()` in `global/components/hitbox_component.gd`, sets
      `hb.damage_type = dmg_type`. No call-site changes needed.
- [x] Step 3 — re-ran `test_contact_hitbox_geometry.gd`, `test_hitbox_hurtbox.gd`,
      `test_enemy_contact_damage.gd`: all green (14/14, 234 asserts).
- [x] Step 4 — `bash /agent/verify.sh`: full suite green (379/379, 1937 asserts).
      `scripts/check-test-leaks.sh`: LEAK CHECK PASS.
- [x] Extra — updated `docs/architecture/modules/global.md`'s `matching_shape()` signature
      reference (flagged non-blocking by the plan reviewer).

**Resume at:** done.
**Deviations from plan:** none.
