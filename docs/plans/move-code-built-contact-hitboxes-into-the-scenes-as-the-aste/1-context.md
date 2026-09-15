# Context — move code-built contact hitboxes into the scenes

## The four code call sites, and who actually consumes each

`HitBox.matching_shape()` (`global/components/hitbox_component.gd:20-33`) is called from exactly
four places today, but `BaseEnemy`'s is inherited, so it covers far more than four entities:

| Call site | Entities that get a hitbox through it |
|---|---|
| `base_enemy.gd:75-79` (`_add_contact_hitbox()`, layer 256, mask 0, damage 20) | `bomber`, `gunship`, `interceptor`, `light_assault_ship`, `ram_ship`, `sniper_enemy`, `space_station` (all inherit the base, unoverridden) |
| `drone_interceptor.gd:141-148` (override: layer 256, **mask 128**, damage `config.collision_damage if config else 30`) | `drone_interceptor` |
| `kamikaze_drone.gd:53-60` (override: layer 256, **mask 128**, damage hardcoded 30) | `kamikaze_drone` |
| `ally_fighter.gd:90-95` (layer **64**, mask 0, damage hardcoded 25) | `ally_fighter` (not a `BaseEnemy` — `extends CharacterBody2D` directly) |
| `bonus_drone.gd:30-31` overrides `_add_contact_hitbox()` to `pass` | `bonus_drone` gets **no** contact hitbox — deliberate, `collision_damage = 0` |

Ten entities end up with a scene-authored `ContactHitBox` after this change; `bonus_drone` stays
without one. This is confirmed by `tests/integration/test_contact_hitbox_geometry.gd`'s `ROSTER`
(11 entries, one marked `no_hitbox: true`), which is the existing invariant test for this exact
family and needs no reworking — see below.

## Five subclasses re-apply `config.collision_damage` after the base builds the box

Because `_add_contact_hitbox()` runs from `BaseEnemy._ready()` before a subclass has read its own
`.tres`, five scripts search their own children for the `HitBox` and overwrite `.damage`
afterwards:

| File | Pattern | Damage source |
|---|---|---|
| `bomber.gd:23-26` | `for child in get_children(): if child is HitBox: ...break` | `config.collision_damage` |
| `gunship.gd:50-53` | same | `config.collision_damage` |
| `light_assault_ship.gd:21-24` | same | `config.collision_damage` |
| `ram_ship.gd:22-25` | same, **outside** the `if config:` block | `config.collision_damage if config else 50` |
| `space_station.gd:125-127` | same, inside `if config:` | `config.collision_damage` |

Two more entities inherit the base's hardcoded 20 and never touch it: `interceptor`, `sniper_enemy`
(confirmed by `tests/integration/test_enemy_contact_damage.gd`'s `ROSTER`, `expected: 20` /
`ShipConfig`'s own default of 20 — the two happen to agree, which is exactly why nothing caught the
gunship missing this re-apply before that test existed).

`space_station.gd:230-238` (`_make_corpse_harmless()`) does a **sixth** "find the HitBox child"
search, at runtime after death, to zero `collision_layer` so a dead 256 px hull stops ramming the
player.

## Geometry — confirmed per scene (`grep` on all ten `.tscn`s)

Every body `CollisionShape2D` these ten scenes author has **only** a `scale` override (no
`position`/`rotation`) and, in every case, the body's `CollisionShape2D` and the `HurtBox`'s
`CollisionShape2D` **already reference the same `SubResource` shape id**, just sometimes at a
slightly different scale (e.g. gunship body `2.3077412` vs. hurtbox `2.289032` — the hurtbox is
tuned separately, not required to match the body). This project convention — reuse one
`SubResource` id across sibling collision nodes in the same scene — is what
`HitBox.matching_shape()` reproduced at runtime by assigning `shape_node.shape = source.shape`
(the same object, not a duplicate). The scene-authored version can reproduce that identity
directly: point the new `ContactHitBox`'s `CollisionShape2D.shape` at the **same `SubResource` id**
as the body's, and copy the body's exact `scale = Vector2(...)` line. Because Godot resolves each
`SubResource` id to one shared object per scene file, `hb_shape.shape == body_shape.shape` holds by
identity — the same equality `test_contact_hitbox_geometry.gd` already asserts. **No test file
needs to change for this reason** — see "Tests" below.

Per-entity layer/mask/damage-default to author (all confirmed above):

| Entity | Layer | Mask | Damage to author (script may override) | Shape scale |
|---|---|---|---|---|
| `bomber` | 256 | 0 | 20 | 1 (unscaled) |
| `gunship` | 256 | 0 | 20 | 2.3077412 |
| `interceptor` | 256 | 0 | 20 (**never overridden**) | 1.8000002 |
| `light_assault_ship` | 256 | 0 | 20 | 2.199998 |
| `ram_ship` | 256 | 0 | 20 | 1 (unscaled) |
| `sniper_enemy` | 256 | 0 | 20 (**never overridden**) | 1.4400002 |
| `space_station` | 256 | 0 | 20 | 1 (unscaled, `RectangleShape2D`) |
| `drone_interceptor` | 256 | **128** | 30 (script overrides via config ternary) | 3.0799994 |
| `kamikaze_drone` | 256 | **128** | 30 (**never overridden** — hardcoded today) | 1 (unscaled) |
| `ally_fighter` | **64** | 0 | 25 (script overrides if `config`) | 1.83783 |

`damage_type` is `HitBox.DamageType.CONTACT` (`= 2`) on all ten — currently guaranteed by
`matching_shape()`'s default parameter; will be authored directly on each scene node.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `assault/scenes/hazards/asteroid_base.gd:26-42`, `big_asteroid.tscn:44-52` | The proven pattern: scene authors a `ContactHitBox` `Area2D` node (script `hitbox_component.gd`) with its own `CollisionShape2D` child; the entity script only does `@onready var contact_hit_box: HitBox = $ContactHitBox` and sets `.damage` / `.damage_type` in `_ready()`. Note the asteroid **duplicates** the shape resource (`Shape_contact` is a separate `SubResource` from `Shape_body`, same radius value) rather than sharing the id — our ten entities should **share** the id instead (see above), since that is what keeps `test_contact_hitbox_geometry.gd` passing unmodified. |
| `global/components/hitbox_component.gd` | `HitBox` script, already referenced via `uid://deqgbl6m44nrj` — confirmed identical everywhere it's currently used (`grep` across all `.tscn`). Safe to reference this same uid as an `ext_resource` in the ten scenes; this is referencing one shared script's real, sole UID, not minting or aliasing a new one. |
| `tests/integration/test_contact_hitbox_geometry.gd` | Already the correct invariant for the end state: same body shape resource + same transform. Needs no test-logic changes, only a header-comment refresh (it currently frames itself as guarding call sites in code; after this change there are none left — the invariant becomes a scene-authoring one). |
| `tests/integration/test_enemy_contact_damage.gd` | Already the correct invariant for damage values; needs no logic changes, only a header-comment refresh (references `_add_contact_hitbox()` and the four call sites by name/line, which stop existing). |

## Conventions that constrain this

- **Composition over inheritance / config-driven `.tres`.** Geometry is scene data (matches the
  asteroid family); damage that comes from a `.tres` still has to be applied in `_ready()` because
  the `.tres` is loaded at runtime.
- **Never hand-type or copy a `uid://` for a *new* resource.** Does not apply to referencing an
  *existing* shared resource's own real uid (e.g. `hitbox_component.gd`'s `uid://deqgbl6m44nrj`) —
  every other shared script (`health_component.gd`, `hurtbox_component.gd`) is already referenced
  this same way from all ten scenes. No new resource is being created here, so no new uid needs
  minting.
- **`tests/integration/test_project_load_integrity.gd`** loads every scene and fails on any engine
  warning — will catch a malformed node block or a stale `SubResource` reference immediately.
- **`tests/integration/test_resource_uid_integrity.gd`** — reports rather than rewrites; run after
  the scene edits to confirm no accidental uid collision.

## Open questions for the plan

1. Node insertion point in each scene — asteroid puts `ContactHitBox` after `HurtBox`; our ten
   scenes have `HurtBox`, `Health`, `HitFlashAnimationPlayer` in a row before subclass-specific
   nodes. Plan should pick one consistent slot (after `HitFlashAnimationPlayer`, before any
   subclass nodes) so the diff shape is identical across all ten.
2. Whether `HitBox.matching_shape()` becomes dead code once all four call sites are gone (yes —
   confirmed by `grep`, no other caller anywhere in the project) and should be deleted rather than
   left unused.
