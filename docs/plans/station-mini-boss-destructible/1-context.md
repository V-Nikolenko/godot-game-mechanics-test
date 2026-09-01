# Context — Station and turrets as a destructible entity

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/enemies/base_enemy.gd` | `BaseEnemy` (CharacterBody2D): wires `HurtBox.received_damage → Health.decrease`, hit flash, contact HitBox, explosion + `queue_free()` on death, propagates `score_value` from a `ShipConfig`. | The station core and each turret are destructible enemies. But `BaseEnemy` **hard-requires** `$Health`, `$HurtBox` and `$HitFlashAnimationPlayer` and **always frees itself at 0 HP** — so the core cannot extend it unmodified (the core must survive turret deaths and stay alive until its own death sequence). |
| `assault/scenes/enemies/gunship/*` | The closest existing analogue: a self-managed "mini-boss" with an enum phase machine, `GunshipConfig` `.tres`, sprite swap at 50% HP. | The exemplar for config-driven stats, scene layout, hit-flash shader wiring, and the `ENEMY.md` doc format. |
| `global/components/health_component.gd` | `Health`: `max_health`/`current_health`, `increase/decrease`, `set_health`, optional i-frames, `amount_changed` signal. | Per-turret and core HP. **`decrease()` clamps at 0 and `set_health` always emits** — so a turret at 0 HP that is hit again re-emits `amount_changed(0)`. Any "died" handler must be idempotent. |
| `global/components/hurtbox_component.gd` / `hitbox_component.gd` | `HurtBox` (Area2D, emits `received_damage(damage)`, optional `accepted_damage_types` filter) / `HitBox` (Area2D, `damage`, `damage_type`). | One HurtBox per turret + one for the core. The core's HurtBox is what must be inert while turrets live. |
| `global/components/damage_reaction.gd` | `setup(health, shield, hurt_box, sprite)`: routes HurtBox → optional Shield → Health, tween flash, explodes and **`get_parent().queue_free()`** at ≤0 HP. | Reusable for turrets — but note it frees `get_parent()`, so a turret using it must be its own node whose parent is the turret root, and it is **not** usable for the core (which must not free itself on reaching 0 before its death sequence). |
| `global/components/hit_effect.gd`, `explosion_effect.gd` | One-shot CPUParticles bursts; `ExplosionEffect.explode()` reparents particles so they outlive the entity. | Turret destruction feedback, station death. |
| `assault/scenes/systems/arena_camera.gd` | `const WORLD_SCALE : float = 2.0`; camera holds `global_position` fixed at level origin and pans via `offset`. | Coordinate-space rule (below). |
| `assault/scenes/systems/wave_manager/wave_manager.gd:172` | `spawn_pos = cam.global_position + offset * ArenaCamera.WORLD_SCALE` | The **only** place WORLD_SCALE multiplies a spawn position — proves the scale applies to authored *offsets*, not to sprite pixel sizes. |
| `assault/scenes/levels/edelia/1/level_1_director.gd:758` | `_build_section_3` uses `LevelSection.EndCondition.ENEMIES_CLEARED`. | Sub-item 2's hook. Out of scope here, but the station must join the `"enemies"` group for it to work later. |
| `tests/README.md` | Suite house rules. | The signal-arity trap and the "component needs a parent in the tree" rule both bite this feature directly. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/components/health_component.gd` | All HP bookkeeping for core and every turret. Do not write a second HP counter. |
| `global/components/hurtbox_component.gd` + `hitbox_component.gd` | Damage intake per part. Turret separation is just "one HurtBox per turret". |
| `global/components/hit_effect.gd` + `explosion_effect.gd` | Hit and destruction feedback — no new particle code. |
| `global/resources/ship_config.gd` (`ShipConfig`) | Base for `StationConfig`: already has `max_health`, `collision_damage`, `score_value`, `counts_toward_wave_clear`. |
| `assault/assets/shader/hit_flash_vs.tres` | The hit-flash shader the gunship scene already uses, driven by an `AnimationPlayer` "hit" animation. |
| `global/components/bullet_pool.gd` | For sub-item 4 (bullet hell). Not needed this sub-item. |
| `assault/scenes/hazards/laser_ray/laser_ray.tscn` | For sub-item 3. Not needed this sub-item. |

## Conventions that constrain this

- **Sprite pixel size is final screen size — never pre-multiplied by `WORLD_SCALE`.** Verified:
  the player's `ShipSprite2D` (`assault/scenes/player/player_fighter.tscn:312`) has **no scale**
  and draws 64×64 atlas regions from `ply2.png`; every enemy sprite is authored at its on-screen
  size (32×32 ram_ship, 92×84 gunship). `WORLD_SCALE` is applied *only* to authored spawn offsets
  (`wave_manager.gd:172`) and `EnemyPathMover` movement (`enemy_path_mover.gd:77`). So a station at
  "4× the 64×64 player" means a **256×256 PNG placed at scale 1**, and turret sprites ~64×64.
- **Composition over inheritance** — assemble from `global/components/`.
- **Config-driven stats** — a `*_config.tres` applied in `_ready()`; the `.tres` wins over the
  scene's Health node.
- **Simple entities use in-script `enum` phases**, not `State` node files (gunship precedent).
  A `states/` folder is only for the player/racers/light_assault_ship.
- **Collision layers** (`project.godot`): 7 player_hitbox, 8 player_hurtbox, 9 enemy_hitbox,
  10 enemy_hurtbox. Gunship's HurtBox uses `collision_layer = 512` (bit 10) and
  `collision_mask = 65` (bits 1+7 = environment + player_hitbox); `BaseEnemy._ready()` then
  overrides the mask to `97 | 1024`. Turret/core hurtboxes must match this so player bullets hit.
- **Tests are GUT characterization** in `tests/`; new-behaviour tests for new code are legitimate
  assertions (this is new code, so its tests assert intent rather than pin bugs).

## Known traps this feature walks into

- **`Health.amount_changed` is declared with zero parameters but emitted with one**
  (`health_component.gd:4` vs `:42`). Handlers **must take one argument** or GUT fails the test
  on the engine error. Already filed under *Discovered* in `BACKLOG.md`.
- **`Health.set_health` emits on every call, including 0 → 0.** A `died` handler wired to
  `amount_changed` fires repeatedly once a part is dead unless guarded.
- **`DamageReaction._on_health_changed` calls `get_parent().queue_free()` unconditionally at ≤0.**
  Convenient for turrets, fatal for the core.
- **Components that print `get_parent().name` (`Health.decrease`) need a real parent in the tree.**

## Open questions for research

1. How many turrets makes a first phase interesting rather than tedious? (backlog asks this)
2. Is "core invulnerable until all turrets die" better expressed as *invulnerable* (damage
   ignored) or *unhittable* (hurtbox disabled)? They differ in player feedback — a bullet that
   visibly pings off teaches the rule; one that passes through reads as a bug.
3. PixelLab maximum output size — does a 256×256 top-down station sprite fit in one generation?
4. Typical shmup convention for whether destroyed turrets leave visible wreckage on the boss.

---

## Corrections (after review round 1)

Two claims above were checked by the reviewer against the real code and found wrong. They are
left in place with this correction appended rather than silently edited, because sub-item 2 will
be planned off this file.

1. **`ENEMIES_CLEARED` does not consult the `"enemies"` group.** The table row for
   `level_1_director.gd:758` implies the station "must join the `enemies` group" for the end
   condition to work. It does not: `level_director.gd:78-81` connects `_wait_enemies_cleared`, and
   `level_director.gd:106-110` polls `wave_manager.enemy_container.get_child_count()`. The real
   requirement for sub-item 2 is that the station be a **child of `enemy_container`** and that it
   **actually leave the tree** when destroyed. The `"enemies"` group is still worth joining, but
   for a different reason — player targeting and AoE modules query it
   (`ai_targeting_module.gd:49`, `plasma_nova_module.gd:34`, `emp_blast_module.gd:39`,
   `warhead_missile_shooting_state.gd:61`).
2. **The core *can* extend `BaseEnemy`.** The "Modules and files involved" row argues it cannot,
   because `BaseEnemy` always frees itself at 0 HP. For sub-item 1 that behaviour is exactly what
   is wanted (core death = station death), and refusing damage needs only a `_on_received_damage`
   override — a pattern already shipped in `ram_ship.gd:27`. The original objection becomes real
   only at sub-item 5; see the closing note in `3-plan.md`.
