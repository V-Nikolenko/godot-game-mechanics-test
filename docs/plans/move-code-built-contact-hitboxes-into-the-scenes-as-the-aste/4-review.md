VERDICT: CHANGES_REQUESTED

## Summary

The design is sound and every factual claim I could independently verify checks out: the
per-entity layer/mask/damage table, the shape-scale values, the SubResource-id-sharing
identity claim, the "no other caller of `matching_shape()`" claim, and the UID reasoning are
all correct against the actual current code and scenes. The one real problem is in the **build
sequence**: as written, step 2 (delete `HitBox.matching_shape()`) runs before steps 6 and 7
(remove the three subclass overrides that still call it), which I confirmed experimentally
produces a hard parse error the moment any of those three scripts is loaded — not a
hypothetical, a reproduced one. That breaks the plan's own "each scene edit is immediately
verified in isolation" claim for a third of the roster during the middle of the sequence.

## Findings

### 1. Build-sequence ordering: step 2 breaks 3 of 10 entities until steps 6–7, undermining step 4's per-scene verification (blocking)

`3-plan.md` build sequence, steps 2–7:
- Step 2: delete `HitBox.matching_shape()` from `global/components/hitbox_component.gd`.
- Step 4: ten scene edits, "each immediately verified by re-running
  `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` for just that entity
  ... before moving to the next, so a mistake is caught at the file that caused it."
- Step 6: only now does `drone_interceptor.gd`/`kamikaze_drone.gd` lose their
  `_add_contact_hitbox()` overrides (which call `HitBox.matching_shape(...)` —
  `drone_interceptor.gd:146`, `kamikaze_drone.gd:58`).
- Step 7: only now does `ally_fighter.gd` lose its `_add_contact_hitbox()`
  (`ally_fighter.gd:95`, also a `matching_shape()` call).

I verified in an isolated scratch Godot 4.6 project that a script containing **any** call to a
now-nonexistent static method — even inside a function that is never invoked — fails to
*load* at all, with a hard parse error:

```
SCRIPT ERROR: Parse Error: Static function "does_not_exist()" not found in base "Foo".
ERROR: Failed to load script "res://baz.gd" with error "Parse error".
```

This is not deferred to call time; `load()` on the `.gd` (and therefore on any `.tscn` whose
root script is that `.gd`) fails immediately. Applied here: from the moment step 2 completes
until steps 6 and 7 land, `drone_interceptor.gd`, `kamikaze_drone.gd`, and `ally_fighter.gd`
all fail to load, because each still contains its own dead `_add_contact_hitbox()` body calling
the now-deleted `HitBox.matching_shape()`.

Both `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` iterate a fixed
roster covering **all** ten/eleven entities in one test function (`ROSTER` at
`test_contact_hitbox_geometry.gd:34`, `test_enemy_contact_damage.gd:54`), so every single
"immediately verified" run in step 4 — for all ten scenes, not just the three affected ones —
will show real, non-transient failures for `drone_interceptor`, `kamikaze_drone`, and
`ally_fighter` (`assert_not_null(scene, ...)` fails because `load()` returns null) for the
entire span of step 4. That directly contradicts the stated purpose of running the tests after
each scene edit ("a mistake is caught at the file that caused it") — for a third of the roster,
every check in that window fails regardless of whether the edit just made was correct. It would
also trip `test_project_load_integrity.gd` if the full gate were run at any point in this
window.

**Fix**: reorder so no intermediate state has a dangling call to a deleted method. Either:
(a) do each entity's script edit and scene edit together, entity by entity (so
`drone_interceptor.gd`'s override and `drone_interceptor.tscn`'s new node land in the same
step), and move the `matching_shape()` deletion to the very end once all four call sites are
confirmed gone (i.e. swap the position of today's step 2 with today's step 8-ish), or
(b) move today's steps 6 and 7 to before step 4, so all four call sites are gone before any
scene-edit verification pass begins. Either way, `HitBox.matching_shape()` should be the
**last** thing deleted, not the first.

### Everything else checked out

- **Per-entity table** (`1-context.md` lines 60–76): every layer/mask/damage-default value and
  every shape scale value matches the actual `.tscn`/`.gd` content, confirmed by direct
  inspection of all ten scenes and nine scripts (`base_enemy.gd:75–79`,
  `drone_interceptor.gd:141–148`, `kamikaze_drone.gd:53–60`, `ally_fighter.gd:90–95`, and the
  five re-apply sites at `bomber.gd:23–26`, `gunship.gd:50–53`, `light_assault_ship.gd:21–24`,
  `ram_ship.gd:22–25`, `space_station.gd:124–127`). No table error found.
- **SubResource identity claim** (the core technical premise): confirmed correct. Not only is
  this standard Godot `.tscn` deserialization behaviour (one object per `SubResource` id per
  scene file), it is already load-bearing, tested-by-implication behaviour in this exact
  codebase — `tests/integration/test_enemy_hurtbox_geometry.gd:224–227` explicitly documents
  that `space_station.tscn` "shares one `RectangleShape2D_ss` sub-resource between the body
  collider and the core HurtBox and it is not `resource_local_to_scene`, so an in-place edit
  would resize the body too." Every one of the ten scenes already shares one `SubResource` id
  between its body `CollisionShape2D` and its `HurtBox`'s `CollisionShape2D` today (confirmed by
  reading all ten), so the plan's approach reuses an already-proven-live pattern, not merely a
  theoretical one. The claim that the two existing tests need zero assertion changes for this
  reason holds.
- **`HitBox.matching_shape()` deletion safety**: confirmed by `grep` — the only callers anywhere
  in the project are the four sites the plan removes; no test instantiates it directly
  (`tests/unit/test_hitbox_hurtbox.gd` does not reference it). Safe to delete once (and only
  once) all four callers are actually gone — see Finding 1 for the timing problem.
- **UID reasoning**: `hitbox_component.gd.uid` on disk is `uid://deqgbl6m44nrj`, and it's already
  referenced this same way (bare `ext_resource` citation of an existing script's real uid) from
  7+ other `.tscn` files project-wide, including the asteroid family this plan is modelled on.
  No new uid is minted; the CLAUDE.md convention is not violated.
- **Insertion point**: "after `HitFlashAnimationPlayer`" (after `Health` for `ally_fighter`) is
  consistent across all ten scenes as read; no scene indexes children by position
  (`get_child(i)` not used anywhere in these scripts) and no `%unique_name` references the
  affected region, so node-order insertion is safe.
- **`_make_corpse_harmless()` / space_station risk**: the plan's own risk section hedges with
  "`tests/integration/test_space_station.gd` / `test_station_death_handoff` (if present)" — the
  actual test that exercises this exact path is `tests/integration/test_station_death_sequence.gd`,
  specifically `test_the_corpse_cannot_ram_the_player` (lines 111–129), which does exist and
  does search `_station.get_children()` for a `HitBox` the same way `_make_corpse_harmless()`
  does. This is a minor citation gap (the plan didn't find the actual test by name), not a
  functional risk — `bash /agent/verify.sh` runs the whole suite including this file regardless,
  so the behaviour is still gated. Worth naming correctly when the plan is revised, but not
  blocking on its own.
- **Drone self-destruct wiring** (`_on_contact_hit` via `area_entered`): the plan's step 6
  correctly moves the `.connect()` call into `_ready()` off the typed `contact_hit_box` var
  rather than dropping it — no signal-connection regression found.
- **Bonus drone**: confirmed `bonus_drone.tscn` has no `ContactHitBox`-shaped node and needs no
  scene edit; deleting `bonus_drone.gd`'s no-op override is inert once the base no longer calls
  it.

## What to change before this proceeds

Only Finding 1. Fix the build-sequence ordering (interleave script+scene edits per entity, or
move all four call-site removals before any scene-edit verification pass, with
`matching_shape()` itself deleted last), then this plan is ready to implement.
