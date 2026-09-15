# Progress

- [x] Step 1 — wrote `tests/integration/test_contact_hitbox_geometry.gd` first and watched it
      fail. Red list reproduced the plan's prediction **exactly**, six entities, all on the
      transform assertion (`ally_fighter` 1.83783, `drone_interceptor` 3.079999, `gunship`
      2.307741, `interceptor` 1.8, `light_assault_ship` 2.199998, `sniper_enemy` 1.44 — the
      generated shape node carried `Transform2D.IDENTITY` in every case). The other three tests
      (vacuity guard, non-uniform-scale guard, `bonus_drone` exception) were green from the start,
      as expected — they are guards, not the bug.
- [x] Step 2 — added `HitBox.matching_shape(source, layer, mask, dmg)` to
      `global/components/hitbox_component.gd`. Shares the `Shape2D` resource (unchanged from
      today), copies `source.transform`, returns the `HitBox` **unparented** so the two callers
      that connect `area_entered` can do so before `add_child()`.
- [x] Step 3 — `assault/scenes/enemies/base_enemy.gd:49-53` now one line. Re-ran: four of the six
      went green (gunship, interceptor, light_assault_ship, sniper_enemy), leaving exactly the two
      predicted overrides red.
- [x] Step 4 — `drone_interceptor.gd:141-148` and `kamikaze_drone.gd:53-60` converted; both keep
      `hb.area_entered.connect(_on_contact_hit)` between construction and `add_child()`. The
      mask-128 comment moved above the call so it is not lost.
- [x] Step 5 — `ally_fighter.gd:72-77` converted. File green, 4/4, 129 asserts.
- [x] Step 6 — full gate.
- [x] Step 7 — `updating-project-docs`.

**Resume at:** done.

**Deviations from plan:** none to the design. Two corrections the round-2 review asked for were
applied to `3-plan.md` before implementing (findings 6 and 7): five *enemy* contact boxes grow, not
six — the sixth affected entity is `ally_fighter` itself, whose box is layer 64 and invisible to
ally `HurtBox` mask 1281 — and `kamikaze_drone`'s box does **not** grow at all, since it authors
its body at `scale = 1` (`kamikaze_drone.tscn:31-32`). Its call site was still converted, so the
next person to scale that scene gets the right box for free.

**The human-eyeball list** (headless tests cannot judge feel):
1. `drone_interceptor` now self-destructs from 3.08× further out.
2. Ally fighters are more fragile — the same five enlarged enemy boxes reach them
   (`ally_fighter.tscn:41-42`, mask 1281 contains bit 256), and `drone_interceptor` suicides into
   an ally from further out too.
3. Ally rams land more often — the ally's own box grew 1.84× and enemy `HurtBox` masks 97/65 both
   contain bit 64.
