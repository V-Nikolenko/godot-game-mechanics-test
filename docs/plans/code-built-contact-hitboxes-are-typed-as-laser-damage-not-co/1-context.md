# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/components/hitbox_component.gd` | `HitBox` class: `damage`, `damage_type` (enum `LASER=0, ROCKET=1, CONTACT=2`, default `LASER`), and the `matching_shape()` static factory used to build a contact hitbox that copies a body's `CollisionShape2D` shape + transform. | `matching_shape()` never sets `damage_type`, so every hitbox it builds inherits the `LASER` default. This is the bug. |
| `global/components/hurtbox_component.gd` | `HurtBox`: `accepted_damage_types` (empty = accept all), filters in `_on_area_entered()`. | The filter that would eventually need `damage_type` to be correct. |
| `assault/scenes/enemies/base_enemy.gd:74-79` (`_add_contact_hitbox`) | Builds the generic enemy ram hitbox via `matching_shape(col, 256, 0, 20)`. | Call site 1. |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd:141-148` | Overrides `_add_contact_hitbox()`, calls `matching_shape(col, 256, 128, config.collision_damage if config else 30)`. | Call site 2. |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.gd:53-60` | Same override pattern, `matching_shape(col, 256, 128, 30)`. | Call site 3. |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd:95` | `matching_shape(col, 64, 0, 25)` for the ally's own ram hitbox. | Call site 4. |
| `assault/scenes/hazards/asteroid_base.gd:29-42` | Contact hitbox is authored in the `.tscn` (`$ContactHitBox`), not built by `matching_shape()`. `_ready()` sets `contact_hit_box.damage_type = HitBox.DamageType.CONTACT` explicitly. | Confirms `CONTACT` is already the intended type for ramming damage everywhere else in the codebase — this task is about making the code-built path agree with the hand-authored one. Untouched by this fix. |
| `tests/integration/test_contact_hitbox_geometry.gd` | Invariant sweep (11-entry roster) asserting every code-built contact `HitBox` copies its body's `Shape2D` + transform. | This is where the task's suggested new assertion (`damage_type == CONTACT`) belongs — the roster and harness (`_spawn`, `_contact_hitbox`, throwaway container parent, direct-children-only search) already exist and are reusable as-is. |
| `tests/integration/test_enemy_contact_damage.gd` | Separate invariant: contact `HitBox.damage` matches the enemy's config `collision_damage`. Same 4 call sites, `BaseEnemy`-typed roster (excludes `ally_fighter`). | Not touched — it is about `damage`, not `damage_type`, and its own file header explains why its harness can't cover `ally_fighter`. |
| `tests/unit/test_hitbox_hurtbox.gd` | Characterization tests for `HitBox`/`HurtBox`, including `test_hitbox_defaults()` (asserts a bare `HitBox.new()` defaults to `LASER`) and `test_damage_type_enum_is_stable()` (pins the enum ordinals). | Confirms the plain `HitBox.new()` default of `LASER` is intentional and must NOT change — only `matching_shape()`'s behaviour changes. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `tests/integration/test_contact_hitbox_geometry.gd` `ROSTER`, `_spawn()`, `_contact_hitbox()` | Exact harness to add a `damage_type` assertion to, no new fixture code needed. |

## Verification that nothing currently filters on LASER (task's explicit ask)

Full-project greps:

- `accepted_damage_types` is set (non-default) in exactly 3 scenes: `big_asteroid.tscn`,
  `assault/scenes/race/track/race_wall.tscn`, `assault/scenes/race/track/race_asteroid.tscn` — all
  three set `Array[int]([1])`, i.e. **`ROCKET`-only**. These are hazard `HurtBox`es that receive
  *weapon fire* (player bullets/rockets), not contact damage from an enemy's ram hitbox — nothing
  ram-related targets them. Changing the ram hitboxes' `damage_type` from `LASER` to `CONTACT`
  cannot affect this filter either way (it never accepted `LASER` and won't accept `CONTACT`
  either).
- The only other `HurtBox` in the project that matters here is the player's
  (`assault/scenes/player/player_fighter.tscn:335-336`, `collision_layer = 128`,
  `collision_mask = 1281`) — it has no `accepted_damage_types` override, i.e. the default empty
  array, which accepts every `damage_type`. This is the box every one of the 4 `matching_shape()`
  call sites' hitboxes is built to hit (directly, or per `CLAUDE.md`'s note that the base helper's
  `mask = 0` box is on layer 256, checked from the other side).
- No `.gd` file reads `HitBox.DamageType.LASER` anywhere except `hitbox_component.gd`'s own default
  and `tests/unit/test_hitbox_hurtbox.gd`'s characterization assertions (which pin the *default of
  `HitBox.new()`*, not `matching_shape()`).

**Conclusion: retyping the 4 `matching_shape()` call sites' output from `LASER` to `CONTACT` changes
no currently-observable game behaviour.** It is purely correcting metadata that nothing reads yet,
exactly as the task describes.

## Conventions that constrain this

- Composition over inheritance / shared component in `global/components/` — the fix belongs in
  `HitBox.matching_shape()`, not duplicated across the 4 call sites.
- GUT characterization vs. invariant test split (`CLAUDE.md`): this file's invariant sweep
  (`test_contact_hitbox_geometry.gd`) is the right home, matching the task body's own suggestion.
- Signal/enum stability: `HitBox.DamageType` ordinals are serialised into `.tscn`/.tres` files and
  must not be reordered — not touched by this fix (no new enum member, no reorder).
