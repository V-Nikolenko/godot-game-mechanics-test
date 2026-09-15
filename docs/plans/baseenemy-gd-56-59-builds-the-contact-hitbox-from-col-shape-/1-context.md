# Context — contact HitBox drops the CollisionShape2D transform

## The defect, precisely

`BaseEnemy._add_contact_hitbox()` (`assault/scenes/enemies/base_enemy.gd:49-60`) builds the
enemy's contact `HitBox` like this:

```gdscript
var shape_node := CollisionShape2D.new()
shape_node.shape = col.shape       # <-- the RESOURCE only
hb.add_child(shape_node)
```

`col.shape` is the `Shape2D` resource. It carries the shape's *intrinsic* size (a
`CircleShape2D`'s `radius`, a `RectangleShape2D`'s `size`) and nothing else. The node's
`transform` — `position`, `rotation`, `scale` — lives on the `CollisionShape2D` **node**, and the
new node is left at identity. Every scene that sizes its body by scaling the collision node
therefore gets a contact hitbox at the shape's unscaled size.

This is not one site. The same five lines are copy-pasted into **four** places:

| Site | Layer | Damage | Copies transform? |
|---|---|---|---|
| `assault/scenes/enemies/base_enemy.gd:49-60` | 256 (enemy contact) | hardcoded 20, re-applied per subclass | no |
| `assault/scenes/enemies/drone_interceptor/drone_interceptor.gd:141-153` | 256, mask 128 | `config.collision_damage` | no |
| `assault/scenes/enemies/kamikaze_drone/kamikaze_drone.gd:53-65` | 256, mask 128 | hardcoded 30 | no |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd:72-84` | 64 (player contact) | hardcoded 25 at `:79`, then overwritten from `config.collision_damage` at `:40-46` | no |

`bonus_drone.gd:29-30` overrides the helper to add nothing — deliberate, `collision_damage = 0`.

## Who is actually affected

Measured from the scenes. "Intended" = the shape resource's size times the node's scale, which is
also what the sibling `HurtBox` collision node uses in every one of these scenes.

| Entity | body `CollisionShape2D` scale | shape radius | intended radius | contact hitbox today | sprite (px) |
|---|---|---|---|---|---|
| `drone_interceptor` | 3.0799994 | 10 (default) | **30.8** | 10 | 64×64 |
| `gunship` | 2.3077412 | 18 | **41.5** | 18 | 92×84 |
| `light_assault_ship` | 2.199998 | 13 | **28.6** | 13 | 64×64 |
| `interceptor` | 1.8000002 | 14 | **25.2** | 14 | 64×74 |
| `ally_fighter` | 1.83783 | 8 | **14.7** | 8 | — |
| `sniper_enemy` | 1.4400002 | 14 | **20.2** | 14 | 64×64 |
| `bomber` | 1 | 22 | 22 | 22 | — |
| `ram_ship` | 1 | 36 | 36 | 36 | — |
| `kamikaze_drone` | 1 | 10 (default) | 10 | 10 | — |
| `bonus_drone` | 1 | 12 | (no hitbox) | — | — |
| `space_station` | 1 | 240×240 rect | 240×240 | 240×240 | — |

None of these nodes carry a `position` or `rotation` offset on the body collision shape — the
loss today is **purely scale**, on six entities, worst case 3.08×. `space_station.tscn` authors
its rect at true size with `scale = 1`, which is why the station epic never tripped over this.

The "intended radius" column tracks the sprite: `drone_interceptor` 30.8 vs a 64px sprite
(half-width 32), `gunship` 41.5 vs 92×84 (half 46/42), `light_assault_ship` 28.6 vs 64 (half 32).
The scaled figure is the visually correct one; the unscaled figure is a hitbox roughly a third
the size of the ship the player can see.

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/components/hitbox_component.gd` | `HitBox` — `Area2D` + `damage` + `damage_type`. No geometry logic of its own; the geometry is entirely whatever `CollisionShape2D` child you give it. |
| `global/components/hurtbox_component.gd` | `HurtBox` — fires `received_damage` on `area_entered`. **One-shot per entry**, no per-frame tick, so a larger hitbox changes *where* a hit registers, not how much damage per second. |
| `tests/integration/test_enemy_contact_damage.gd` | The roster-sweep pattern for this exact family: a `ROSTER` table of scene+config, `_spawn()` into a throwaway container `Node2D`, `_contact_hitbox()` searching direct children only. A geometry invariant can reuse the whole harness. |
| `tests/integration/test_project_load_integrity.gd` | Asserts every scene loads with no engine warning. Constrains how we set the transform — the existing scenes already scale `CollisionShape2D` nodes and pass, so doing the same from code is consistent. |

## Conventions that constrain this

- **Composition over inheritance.** The four duplicate sites are the thing to fix structurally;
  a shared builder on `BaseEnemy` is the minimum, but `ally_fighter` is not a `BaseEnemy`
  (`assault/scenes/allies/ally_fighter/ally_fighter.gd` extends `CharacterBody2D` directly), so a
  `BaseEnemy` method cannot serve all four.
- **Config-driven `.tres`.** Sizes here are *scene* data, not `.tres` data — `ShipConfig` has no
  radius field and should not grow one for this. The scene's collision node stays the source of
  truth; the code's job is to stop discarding half of it.
- **The gate reads geometry nowhere today.** `test_enemy_contact_damage.gd` asserts `hb.damage`
  and never looks at the shape, which is exactly why this survived the run that wrote it.

## Open questions for research

1. Is growing enemy contact hitboxes 1.4×–3.1× the right call for a shmup, or is a
   deliberately-undersized enemy contact box a genre convention I would be breaking?
2. Does Godot 4 handle a scaled `CollisionShape2D` under an `Area2D` correctly at runtime, or is
   baking the scale into a duplicated `Shape2D` the safer construction?
