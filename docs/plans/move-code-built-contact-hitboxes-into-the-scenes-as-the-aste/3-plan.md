# Move code-built contact hitboxes into the scenes

## Problem

Ten entities' contact `HitBox` — the collider that lets a ramming hull deal damage — is built at
runtime by copying a `Shape2D` resource and a `CollisionShape2D` transform off the body shape.
That construction was itself the site of a real bug (the gunship's ram box was 38% of its hull
until `HitBox.matching_shape()` fixed the transform-drop). The asteroid family
(`asteroid_base.gd` + `big_asteroid.tscn`/`small_asteroid.tscn`) already proves the alternative:
author the `ContactHitBox` node directly in the scene, next to the body shape it has to match, and
let the script only set `.damage`/`.damage_type`. That moves the hull geometry to where a scene
author can see body and hitbox side by side, and it structurally removes the whole class of bug —
there is no runtime construction left to get wrong.

## Design

### The change

For each of the ten entities that has a code-built contact `HitBox`
(`bomber`, `gunship`, `interceptor`, `light_assault_ship`, `ram_ship`, `sniper_enemy`,
`space_station`, `drone_interceptor`, `kamikaze_drone`, `ally_fighter` — full detail in
`1-context.md`):

1. **Author a `ContactHitBox` node in the `.tscn`**: `Area2D`, script
   `res://global/components/hitbox_component.gd` (referenced via its existing
   `uid://deqgbl6m44nrj` — the same uid every other consumer already uses, not a new mint), with
   `collision_layer`/`collision_mask`/`damage`/`damage_type` authored per the table in
   `1-context.md`. Its one `CollisionShape2D` child references the **same `SubResource` shape id**
   as the entity's body `CollisionShape2D` and copies that node's exact `scale = Vector2(...)`
   line (no entity in this set has a `position`/`rotation` override on its body shape).
   Insertion point: immediately after `HitFlashAnimationPlayer` (after `Health` for
   `ally_fighter`, which has no flash player) — one consistent slot across all ten scenes.
2. **Delete the runtime construction.** Remove `BaseEnemy._add_contact_hitbox()` and its call in
   `_ready()`; remove the `drone_interceptor.gd` / `kamikaze_drone.gd` overrides; remove
   `ally_fighter.gd._add_contact_hitbox()` and its call; remove `bonus_drone.gd`'s no-op override
   (nothing to override once the base no longer builds one, and `bonus_drone.tscn` gets no
   `ContactHitBox` node — the absence *is* the "contact-harmless" behaviour, exactly like an
   asteroid variant that never sets `contact_damage`).
3. **Replace every "search my children for a `HitBox`" with a typed reference.** `BaseEnemy` gains
   `@onready var contact_hit_box: HitBox = get_node_or_null("ContactHitBox") as HitBox` (nullable —
   `bonus_drone` has none). The five `for child in get_children(): if child is HitBox: ...`
   call sites (`bomber.gd`, `gunship.gd`, `light_assault_ship.gd`, `ram_ship.gd`,
   `space_station.gd` ×2, including `_make_corpse_harmless()`) become
   `if contact_hit_box: contact_hit_box.damage = ...` / `.set_deferred("collision_layer", 0)`.
   `drone_interceptor.gd` and `kamikaze_drone.gd` connect
   `contact_hit_box.area_entered.connect(_on_contact_hit)` in `_ready()` instead of doing it right
   after building the node. `ally_fighter.gd` gets its own
   `@onready var _contact_hit_box: HitBox = get_node_or_null("ContactHitBox") as HitBox` (it is not
   a `BaseEnemy`).
4. **Delete `HitBox.matching_shape()`** (`global/components/hitbox_component.gd:20-33`). Confirmed
   by `grep` (`1-context.md`) that all four call sites are the ones being removed and nothing else
   in the project calls it — keeping an unused static factory around is exactly the vestigial
   abstraction `CLAUDE.md` says not to leave.

### Why the shared-`SubResource`-id construction, not the asteroid's duplicated one

`big_asteroid.tscn` gives `ContactHitBox` its **own** `SubResource` (`Shape_contact`, same radius
value as `Shape_body`, different object). That is a legitimate choice, but it means
`test_contact_hitbox_geometry.gd`'s `assert_eq(shape_nodes[0].shape, body.shape, ...)` — which
checks **object identity**, since GDScript's `==` on a `Resource` is identity, not value, equality
— would fail the moment we did the same thing for these ten. Referencing the exact same
`SubResource` id from both the body node and the new `ContactHitBox` node instead reproduces
`HitBox.matching_shape()`'s own construction (`shape_node.shape = source.shape`, the same object),
keeps `test_contact_hitbox_geometry.gd` **unmodified**, and matches how these same ten scenes
already share one shape id between the body `CollisionShape2D` and the `HurtBox`'s.

### Alternatives rejected

- **Keep `HitBox.matching_shape()` and just also author scenes for future entities.** Leaves two
  parallel ways to build the same thing and the factory permanently unused — rejected, this task's
  whole premise is that the scene-authored version is the single correct pattern going forward.
- **Duplicate the shape resource per entity (asteroid's exact construction).** Rejected above —
  breaks the existing identity-based geometry test for no benefit; sharing the id is strictly
  simpler (no new `SubResource` blocks to write) and matches the sibling `HurtBox` convention
  already in every one of these scenes.
- **Give `BaseEnemy` a virtual `_add_contact_hitbox()` hook that scene-authored subclasses call at
  `_ready()` to *validate* the node exists, rather than deleting it outright.** Rejected — no
  remaining caller needs a hook; a plain `@onready` reference is simpler and is exactly what
  `asteroid_base.gd` does.

## Build sequence

**Revised after review round 1** (`4-review.md`): the original ordering deleted
`HitBox.matching_shape()` in step 2, before three subclass overrides (`drone_interceptor.gd`,
`kamikaze_drone.gd`, `ally_fighter.gd`) stopped calling it — the reviewer reproduced that this
makes those `.gd` files **fail to `load()` at all** (a hard parse error on a call to a
nonexistent static method, even inside a never-invoked function), which would have broken the
per-scene verification in step 4 for a third of the roster throughout the whole sequence. Fixed
by interleaving each entity's script edit with its scene edit, and moving the
`matching_shape()` deletion to the very end, after all four call sites are confirmed gone.

1. **Confirm the current gate is green** before touching anything (`bash /agent/verify.sh` or the
   three-step manual sequence), so any later failure is attributable to this change.
2. **`base_enemy.gd`**: add the `contact_hit_box` onready var; delete `_add_contact_hitbox()` and
   its call in `_ready()`. (Base default construction is gone; each subclass's scene now carries
   its own `ContactHitBox` — added in the steps below, entity by entity.)
3. **`bomber`, `gunship`, `light_assault_ship`, `ram_ship`, `space_station`, `interceptor`,
   `sniper_enemy`** — for each entity, in one step per entity: author the `ContactHitBox` node in
   its `.tscn` (layer 256 / mask 0 / damage 20 / damage_type 2, shape = body's `SubResource` id,
   scale copied from body), **and**, for the five that re-apply config damage (`bomber.gd`,
   `gunship.gd`, `light_assault_ship.gd`, `ram_ship.gd`, `space_station.gd` — the two remaining,
   `interceptor`/`sniper_enemy`, need no script change since they keep the base default of 20),
   swap the `for child in get_children(): if child is HitBox: ...` search for
   `if contact_hit_box: contact_hit_box.damage = ...` in the same step. `space_station.gd` also
   gets its `_make_corpse_harmless()` search swapped to
   `if contact_hit_box: contact_hit_box.set_deferred("collision_layer", 0)` in this same step,
   since it is the same entity. After each entity's step, re-run
   `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` — neither `.gd` file for
   this entity calls `matching_shape()` (they never did; only `base_enemy.gd` did, and that's
   already gone from step 2), so a red result at this point is attributable to *this* entity's
   edit.
4. **`drone_interceptor`**: in one step, author `drone_interceptor.tscn`'s `ContactHitBox` (layer
   256 / mask 128 / damage 30 / damage_type 2) **and** edit `drone_interceptor.gd`: delete the
   `_add_contact_hitbox()` override (removing its `matching_shape()` call), add
   `contact_hit_box.area_entered.connect(_on_contact_hit)` and
   `contact_hit_box.damage = config.collision_damage if config else 30` in `_ready()`. Re-run both
   test files — this is the first point at which zero call sites remain for this entity.
5. **`kamikaze_drone`**: same pairing — scene node (layer 256 / mask 128 / damage 30) plus
   deleting the `_add_contact_hitbox()` override and adding
   `contact_hit_box.area_entered.connect(_on_contact_hit)` in `_ready()`. Re-run both test files.
6. **`ally_fighter`**: same pairing — scene node (layer 64 / mask 0 / damage 25) plus deleting
   `_add_contact_hitbox()` and its call in `_ready()`, adding its own
   `@onready var _contact_hit_box: HitBox = get_node_or_null("ContactHitBox") as HitBox`, and
   swapping its child-search re-apply for `if _contact_hit_box: _contact_hit_box.damage =
   config.collision_damage`. Re-run both test files.
7. **`bonus_drone.gd`**: delete the now-pointless `_add_contact_hitbox() -> void: pass` override
   (it called nothing itself, so this step carries no `matching_shape()` dependency and could in
   principle run anywhere — placed here for tidiness, after the entity it mirrors conceptually).
   Confirm `bonus_drone.tscn` needs no edit (no `ContactHitBox` node, by design).
8. **Confirm zero remaining callers**: `grep -rn "matching_shape" --include=*.gd .` — expect only
   the definition in `hitbox_component.gd` itself and comment references in the two test files
   (updated in step 10). Only once this is confirmed empty of real callers:
   **`global/components/hitbox_component.gd`**: delete `matching_shape()`.
9. **Full suite**: `bash /agent/verify.sh`. Expect `test_contact_hitbox_geometry.gd` and
   `test_enemy_contact_damage.gd` green with **zero test-file changes** to their assertions (only
   header-comment refreshes, step 10).
10. **Refresh stale comments**: `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd`
    header comments currently describe code call sites (`base_enemy.gd:49-53` etc.) that no longer
    exist — update the prose to describe the scene-authoring invariant without changing any
    assertion.
11. **`updating-project-docs` skill** — mandatory, this is structural: `docs/architecture/modules/
    global.md:123` documents `HitBox.matching_shape()` as "the" way to build a contact hitbox in
    code (now deleted) and its code sample at `:139-142`; `CLAUDE.md`'s own paragraphs for
    `test_contact_hitbox_geometry.gd` and `test_enemy_contact_damage.gd` cite the exact call sites
    and line numbers being removed. All three need updating to describe the scene-authored
    end state.

## Test plan

No new test files — the two existing invariant tests already assert exactly the right things
(confirmed in `1-context.md`):

- `tests/integration/test_contact_hitbox_geometry.gd` — `test_every_contact_hitbox_matches_its_body_shape`
  (shape identity + transform equality), `test_the_roster_contains_a_scaled_body_or_this_file_is_vacuous`,
  `test_no_body_collision_shape_uses_non_uniform_scale`, `test_bonus_drone_still_has_no_contact_hitbox`,
  `test_every_contact_hitbox_is_typed_as_contact_damage` — all must stay green with **no assertion
  changes**. Green here is the direct proof that the shared-`SubResource`-id construction actually
  reproduces `matching_shape()`'s object-identity behaviour rather than merely resembling it.
- `tests/integration/test_enemy_contact_damage.gd` — `test_every_enemy_contact_hitbox_matches_its_config`,
  `test_bonus_drone_has_no_contact_hitbox_and_a_zero_damage_config`,
  `test_gunship_rams_for_its_configured_collision_damage` — must stay green with no assertion
  changes, proving damage values are unaffected by the authoring-location change.
- Boundary case already covered by both files: `bonus_drone` (no hitbox at all) and the two
  entities that keep the base default of 20 with no override (`interceptor`, `sniper_enemy`) —
  these are the cases most likely to regress if a scene edit is dropped or a default typoed.
- `tests/integration/test_project_load_integrity.gd` — every touched scene must still load with no
  engine warning (catches a malformed node block or dangling `SubResource` reference).
- `tests/integration/test_resource_uid_integrity.gd` — run after the scene edits; no new uid is
  minted, so this should be a no-op confirmation, not a source of new findings.

## Risks

- **Ten scene edits by hand is exactly the "UID risk" the backlog item calls out.** Mitigated by
  reusing the *existing* `hitbox_component.gd` uid (already used project-wide, confirmed identical
  everywhere) rather than typing or minting anything new, and by running the geometry/damage tests
  after each scene rather than batching all ten before the first check.
  `test_resource_uid_integrity.gd` and `test_project_load_integrity.gd` are both gate steps and
  will catch a malformed reference regardless.
- **Losing the object-identity shape sharing silently.** If a scene edit accidentally gives
  `ContactHitBox` its own duplicated `SubResource` instead of the body's id,
  `test_every_contact_hitbox_matches_its_body_shape` fails loudly (identity comparison) rather than
  silently — this is exactly the test that catches it.
- **`space_station`'s `_make_corpse_harmless()` collision-layer zeroing** is timing-sensitive
  (`set_deferred`, called after death). Swapping the child-search for the typed onready reference
  is a pure refactor of *how* the node is found, not *when* — no behavior change expected, but
  `tests/integration/test_space_station.gd` / `test_station_death_handoff` (if present) exercise
  this path and will be run as part of the full suite.

## Out of scope

- Re-tuning any contact damage value — this is a structural move, not a balance change.
- Re-tuning the hurtbox scale mismatches noted in `1-context.md` (e.g. gunship body `2.3077412` vs.
  hurtbox `2.289032`) — pre-existing, unrelated to contact hitboxes.
- Any change to `asteroid_base.gd`/`asteroid.tscn` — already scene-authored, not touched.
