# Station and turrets as a destructible entity (EPIC sub-item 1)

> **Revision 2** — folds in review round 1 (`4-review.md`, `VERDICT: CHANGES_REQUESTED`,
> findings F1–F12). Changes from revision 1 are marked **[F*n*]**. The architecture is unchanged:
> the reviewer verified `extends BaseEnemy` + a single `_on_received_damage` override against the
> engine semantics and the shipped `ram_ship.gd:27` precedent, and confirmed the coordinate-space,
> `set_health`-emits and `DamageReaction` claims. All corrections are local.

## Problem

Level 1 currently runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent with no
station encounter. The EPIC's first sub-item asks only for the **entity** to exist: a top-down
space station the player can shoot, carrying turrets that are destroyed individually, whose core
refuses damage until the last turret is gone. Nothing is wired into the level this session
(sub-item 2), and it neither shoots nor fires lasers yet (sub-items 3 and 4).

Player-facing outcome once this and sub-item 2 land: shooting the station's hull does nothing
except spark, which teaches "kill the guns first"; each turret dies on its own HP bar; when the
fourth dies the hull starts taking damage.

## Design

### Shape

`assault/scenes/enemies/space_station/` — follows the per-enemy folder convention (`gunship/`,
`bomber/`, …): scene + script + config + `ENEMY.md`. There is no `bosses/` directory in this
project and one entity does not justify inventing one.

```
SpaceStation (CharacterBody2D, space_station.gd, extends BaseEnemy)
├── Sprite2D                     station_core.png (256×256), scale 1
├── CollisionShape2D             TRUE-SIZE shape, scale 1, position (0,0)   [F4]
├── HurtBox (Area2D)             the CORE's damage intake
│   └── CollisionShape2D
├── Health (Node)                core HP, overwritten from the .tres in _ready()
├── HitFlashAnimationPlayer      "hit"/"RESET" library, copied from gunship.tscn
└── Turrets (Node2D)
    └── Turret0 … Turret3        instances of station_turret.tscn
```

`StationTurret` (`station_turret.tscn`, `station_turret.gd`, `extends Node2D`):

```
StationTurret (Node2D)
├── Sprite2D         station_turret.png (64×64)
├── HurtBox (Area2D) + CollisionShape2D
└── Health (Node)
```

### Why `SpaceStation extends BaseEnemy`

`BaseEnemy` already supplies the `HurtBox.received_damage → Health.decrease` wiring, the hit-flash
`AnimationPlayer` call, `HitEffect`, `ExplosionEffect`, the contact `HitBox`, the `died` signal,
`was_killed`, and `score_value` propagation from a `ShipConfig`. All nine shipped enemies extend
it (`gunship.gd:2`, `ram_ship.gd:2`, …), and `BaseEnemy` itself composes from `global/components/`
— so this satisfies, rather than violates, `CLAUDE.md`'s "composition over inheritance".

The only missing behaviour is "refuse damage while armoured", a one-method override with an exact
shipped precedent in `ram_ship.gd:27`:

```gdscript
func _on_received_damage(damage: int) -> void:
    if is_armored():
        armor_deflected.emit(damage)   # feedback only — health untouched   [F6]
        hit_flash_player.play("hit")
        return
    super._on_received_damage(damage)
```

**Rejected — `extends CharacterBody2D` + `DamageReaction`.** `DamageReaction._on_health_changed`
calls `get_parent().queue_free()` unconditionally at ≤0 HP (`damage_reaction.gd:45`) and
`_on_received_damage` (`:31-38`) has no refuse hook, so damage would have to be intercepted before
it anyway. More code, less reuse.

**Rejected — physical shield walls that block bullets** (the literal Gradius mechanism in
`2-research.md`). Bullets here are `Area2D`s that pass through anything but a hurtbox, so
"blocking" means new bullet-lifetime logic. The armour-deflect keeps the *feedback* — the hit
visibly registers — which `2-research.md` identified as the property that actually matters.

**Why the HurtBox stays live rather than being disabled** — beyond the research argument, a
disabled hurtbox would be bypassed anyway by the player's AoE module, which emits on the signal
directly: `plasma_nova_module.gd:39-41` does
`n.get_node_or_null("HurtBox").received_damage.emit(_DAMAGE)`. Refusing damage inside
`_on_received_damage` is the only place that catches *both* the physics path and that direct-emit
path. Recorded in `ENEMY.md` so it is not "simplified" away later.

### Armour rule — derived, not counted **[F7]**

```gdscript
func live_turret_count() -> int:
    var n := 0
    for t in _turrets:
        if t.is_alive(): n += 1
    return n

func is_armored() -> bool: return live_turret_count() > 0
```

Revision 1 kept an `_live_turrets` integer decremented on a `destroyed` signal, justified by
`queue_free()` frame timing. The reviewer correctly noted that justification is void once turrets
are kept as wreckage (below) — nothing is ever freed. Iteration over four children is trivially
cheap and **structurally cannot** desync or double-decrement, deleting the entire bug class. The
turret still exposes a `destroyed(turret)` signal because sub-items 3 and 4 want the event hook
(laser phase start, escalating fire), but **no state is derived from it**.

### Turret lifecycle — wreck, do not free

A destroyed turret sets `_alive = false`, closes its hurtbox, swaps to
`station_turret_destroyed.png`, and emits `destroyed`. It **stays in the tree as wreckage** so the
station reads as damaged rather than as a station that grew smaller.

Closing the hurtbox sets **all three** of `monitoring = false`, `monitorable = false`, and the
shape `disabled = true` (deferred) **[F10]**. `monitorable = false` only stops the projectile's
HitBox seeing the turret; `HurtBox._on_area_entered` (`hurtbox_component.gd:10-18`) fires off the
turret's *own* `monitoring`, so `monitoring = false` is what actually closes the intake.

The turret's death handler is guarded `if not _alive: return`, because `Health.set_health()` emits
`amount_changed` on **every** call including 0 → 0 (`health_component.gd:40-42`) — so a dead turret
hit again would otherwise re-emit `destroyed`.

A station with **zero** live turrets is damageable immediately; the degenerate case is defined
rather than left to crash.

### Collision layers — set explicitly, do not copy the gunship's raw values **[F1]**

The gunship's `collision_mask = 65` in `gunship.tscn:69` is safe only because
`base_enemy.gd:25` overwrites it with `97 | 1024`. `StationTurret` is a plain `Node2D` — nothing
overwrites it. Verified projectile layers: player bullets `collision_layer = 64`
(`bullets/bullet.tscn:44`), homing/warhead missiles `collision_layer = 32`
(`homing_missile.tscn:54`, `warhead_missile.tscn:60`). Mask 65 omits bit 6, so **missiles would
pass through every turret silently.**

`station_turret.gd::_ready()` therefore sets, mirroring `base_enemy.gd:25`:

```gdscript
hurt_box.collision_layer = 512          # enemy_hurtbox — what projectile HitBoxes monitor (mask 513)
hurt_box.collision_mask  = 97 | 1024    # bullets(64) + rockets(32) + layer 1 + asteroid contact(1024)
```

The core's HurtBox needs no such line — `BaseEnemy._ready()` sets it.

### Contact damage — applied, not decorative **[F3]**

`BaseEnemy._add_contact_hitbox()` **hardcodes `hb.damage = 20`** (`base_enemy.gd:56`) and never
reads the config. `bomber.gd:25`, `light_assault_ship.gd:23`, `ram_ship.gd:20-23` and
`drone_interceptor.gd:148` all re-apply it after `super._ready()`; the gunship forgot to, so
`gunship_config.tres:8 collision_damage = 30` is silently ignored. The station follows the
majority and re-applies it:

```gdscript
for child in get_children():
    if child is HitBox: (child as HitBox).damage = config.collision_damage
```

The gunship's latent bug goes to `BACKLOG.md` *Discovered* — it is a pre-existing defect found
while working, not something to fix in this change.

### Collision shape authored at true size **[F4]**

`base_enemy.gd:56-59` copies `col.shape` onto a **fresh** `CollisionShape2D`, carrying over neither
`scale` nor `position`. `gunship.tscn:63-65` scales its shape by 2.31, so the gunship's contact
hitbox is ~2.3× too small. At 256×256 that error would be enormous, so the station's
`CollisionShape2D` is authored with its shape at **true size**, `scale = 1`, `position = (0,0)` —
then there is no transform to lose.

### Coordinate space

Sprite pixel dimensions in this project are **final on-screen pixels**, never multiplied by
`ArenaCamera.WORLD_SCALE`. Verified: `arena_camera.gd:33-35` documents the constant as applying to
"spawn offsets and EnemyPathMover movements"; the only two multiplication sites are
`wave_manager.gd:172` and `enemy_path_mover.gd:77`/`:83`; `player_fighter.tscn:312` has no scale
and draws 64×64 atlas regions.

- Station sprite **256×256 PNG at `scale = 1`** → 4× the 64×64 player, as the EPIC requires.
- Turret sprites **64×64 PNG at `scale = 1`** → player-sized.
- **Turret positions inside the scene are sprite-local screen pixels, not design units** — they
  are child offsets within a sprite, not spawn offsets. Four diagonal corners at `(±76, ±76)`.
- The station's *spawn position* when a level places it **is** an authored offset and **will** be
  scaled by `WORLD_SCALE` there. Sub-item 2's concern, not this one.

### Config-driven stats

`space_station_config.gd` (`class_name SpaceStationConfig extends ShipConfig`) adds exactly one
field: `turret_health: int = 120`. `max_health`, `collision_damage`, `score_value` come from
`ShipConfig`.

**[F2]** `turret_score_value` is **dropped**. Nothing could pay it out: `score_tracker.gd:55-75`
registers kills via `WaveManager.enemy_spawned` + `BaseEnemy.died`, and a turret is a `Node2D`,
never spawned through `WaveManager`, and by design never leaves the tree. Shipping a `.tres` field
that does nothing would mislead a later session. Per-turret scoring is listed in *Out of scope*.

**[F8]** `SpaceStation._ready()` is the node that applies `turret_health`, writing into each
turret's `Health` after `super._ready()`. This is safe because Godot readies children before
parents, the same ordering `gunship.gd:36-37` relies on. A test pins it.

Starting values (this project's choice, sized against the gunship's 200 HP and the damage-sponge
warning in `2-research.md`): `max_health = 600`, `turret_health = 120`, `score_value = 1000`,
`collision_damage = 40`. Real tuning belongs to sub-item 4, once it shoots.

### Group membership **[F9]**

`add_to_group("enemies")` right after `super._ready()`, as every other enemy does (`gunship.gd:31`).
The group is consumed by player targeting and AoE (`ai_targeting_module.gd:49`,
`plasma_nova_module.gd:34`, `emp_blast_module.gd:39`, `warhead_missile_shooting_state.gd:61`);
without it the station is invisible to homing missiles.

Note this group is **not** what drives `ENEMIES_CLEARED` — `level_director.gd:106` polls
`wave_manager.enemy_container.get_child_count()`. `1-context.md` claimed otherwise and has been
corrected, because sub-item 2 will be planned off that note.

### Sprites

Three `create_image_pixflux` generations (1 each; 1980 remain), `view = "high top-down"`,
`no_background = true`, saved to `assault/assets/sprites/enemies/`: `station_core.png` (256×256),
`station_turret.png` (64×64), `station_turret_destroyed.png` (64×64). Imported via
`godot --headless --import`. **No aesthetic iteration** — if serviceable, keep. If generation fails
or output is unusable, fall back to a `PlaceholderTexture2D` and say so in the report; the entity
logic and its tests do not depend on the art.

## Build sequence

1. **Tests first** — `tests/integration/test_space_station.gd` **[F5]**; watch it fail (scripts do
   not exist → GUT load failure is the expected red).
2. `space_station_config.gd` + `space_station_config.tres`.
3. `station_turret.gd` + `station_turret.tscn`.
4. `space_station.gd` + `space_station.tscn` (turrets instanced, hit-flash library copied).
5. Generate + import the three sprites; point the scenes at them.
6. **UID hygiene [F11]** — every `[ext_resource]` in the three new files must carry the UID its
   target actually declares (copied from the target's `.gd.uid` / `.import` / header line), because
   `tests/integration/test_resource_uid_integrity.gd` asserts exactly that from disk and commit
   `94e251d` already fixed 8 such breaks. Run `godot --headless --import` before the suite.
7. Run GUT; make green.
8. `ENEMY.md` beside the scene; `updating-project-docs`; tick `BACKLOG.md`.

Steps 2–4 are each independently loadable (`--check-only`), so an interrupted window resumes at a
known-good point.

## Test plan

`tests/integration/test_space_station.gd` **[F5]** — `unit/` is documented as "no scene loading"
(`tests/README.md:14-18`) and this instances the real `space_station.tscn`. Uses `GutTest`,
`add_child_autofree`, and drives damage with `hurt_box.received_damage.emit(n)`, the idiom in
`test_damage_reaction.gd:49` and `test_player_damage_chain.gd:59`.

| Test | Asserts |
|---|---|
| `test_station_starts_armored_with_four_live_turrets` | `is_armored()` true; `live_turret_count() == 4`. |
| `test_core_ignores_damage_while_any_turret_lives` | **The backlog's done-condition.** Destroy turrets one at a time; after each of the first three, damage the core and assert `current_health == max_health` still. |
| `test_core_becomes_damageable_after_last_turret_dies` | After the 4th dies: `is_armored()` false, and 50 damage moves core health to `max_health - 50`. |
| `test_armored_core_emits_armor_deflected_and_keeps_full_health` **[F6]** | `watch_signals(station)`; hit the core hurtbox for 50; `assert_signal_emitted_with_parameters(station, "armor_deflected", [50])` **and** `current_health == max_health`. Names a concrete observable, so it cannot degenerate into a duplicate of the row above, and it fails against a disabled-hurtbox implementation — the design `2-research.md` ruled out. |
| `test_turret_damage_does_not_leak_into_core_health` | Damaging a turret leaves core `current_health == max_health`. |
| **Boundary** `test_destroyed_turret_ignores_further_damage` | Kill turret 0, then damage it 3 more times: `live_turret_count()` stays 3, `destroyed` emitted exactly once, core still armoured. Targets the `set_health`-always-emits trap. |
| **Boundary** `test_station_with_no_live_turrets_is_immediately_damageable` | Kill all four in `before`, or free the turrets: `is_armored()` false. Defines the degenerate case. |
| `test_config_max_health_wins_over_scene_health_node` | Core `max_health` equals the `.tres` value, not the scene's Health node value. |
| `test_config_turret_health_is_applied_to_every_turret` **[F8]** | Each turret's `Health.max_health` equals `config.turret_health` — pins that `SpaceStation._ready()` really is the node that applies it, and that child-before-parent ready ordering holds. |

Each can fail: the first four against an inverted or missing armour flag; the boundary rows against
a naive decrement and against an undefined zero-turret case; the last two against a scene value
silently winning over the `.tres`.

**Signal-arity trap:** handlers connected to `Health.amount_changed` must take **one** argument
(`tests/README.md`), or GUT fails on the engine error. Applies to both new scripts.

**Acknowledged coverage gap:** these tests emit `received_damage` directly, so they do **not**
prove the collision layers of F1 are right. That is only provable once the station is in a live
level (sub-item 2). Stated in `ENEMY.md` rather than hidden.

## Risks

| Risk | Check |
|---|---|
| `BaseEnemy._ready()` hard-requires `$Health`, `$HurtBox`, `$HitFlashAnimationPlayer`. | Scene has all three; the tests instance the real scene, so a missing node is a red suite. |
| Hit-flash `AnimationPlayer` track paths are node-relative. | Library targets `Sprite2D:material:shader_parameter/enabled`; our sprite is also `Sprite2D` with the same ShaderMaterial. Exercised by the armour-deflect test, which plays "hit". |
| Turret collision layers unprovable by unit test. | F1 value set explicitly from verified projectile layers; gap documented above and in `ENEMY.md`. |
| New `.tscn`/`.tres` UIDs. | F11 step; `test_resource_uid_integrity.gd` is the gate. |
| PixelLab output unusable or wrong size. | Assert PNG dimensions after download; `PlaceholderTexture2D` fallback. |
| `ExplosionEffect.explode()` needs a `Node2D` parent. | `explosion_effect.gd:27-33`; satisfied under `add_child_autofree`. |

## Out of scope

Level integration and the `station_assault` `LevelSection` (sub-item 2); the rotating laser phase
(3); bullet-hell patterns, reinforcements and turret *firing* (4); the death handoff (5); balance
tuning; per-turret scoring (F2 — needs a payout path through `ScoreTracker` that does not exist);
any change to `BaseEnemy`, `Health`, or `DamageReaction`, including the `amount_changed` arity bug,
which stays filed under *Discovered*.

**Constraint handed forward to sub-item 5 [F12]:** `1-context.md` originally judged that the core
could not extend `BaseEnemy` because `BaseEnemy` frees itself at 0 HP. For sub-item 1 that is
exactly right — core death *is* station death. But `base_enemy.gd:73` calls `queue_free()` in the
same frame as `died.emit()`, so sub-item 5's "station death plays out before the level advances"
**will** have to override `_on_health_changed` to defer the free. Recorded here so that session
does not discover it mid-implementation.

---

## Addendum — review round 2 implementation notes (binding)

Round 2 returned `VERDICT: APPROVED` with five binding notes. Folded in here rather than by
rewriting the sections above, so the reviewed text stays diffable.

**N1 — the core HurtBox must author `collision_layer = 512` in the scene.** The claim above that
"the core's HurtBox needs no such line" is **wrong**: `base_enemy.gd:25` sets `collision_mask`
only and never touches `collision_layer`; the gunship works solely because `gunship.tscn:68`
authors the layer in the scene file. This is the highest-risk note in the whole plan, because of
the disclosed coverage gap — every test emits `received_damage` directly, so **all nine would pass
against a core no bullet can ever hit.** A green suite is not evidence for this line; it is
verified by reading the scene file.

**N2 — `_turrets` is read live, never cached.** `live_turret_count()` iterates
`$Turrets.get_children()` on each call and guards `if is_instance_valid(t) and t.is_alive()`. A
cached `Array` would partly give back the "structurally cannot desync" property F7 bought, and a
freed turret in a cached array raises *"call on a previously freed instance"* — which
`tests/README.md:62-63` says fails the test outright. The boundary test's "**or** free the
turrets" option is **dropped**; it kills all four instead, which is also what the production path
does.

**N3 — the signal assertions are exercised in step 1's deliberate red run.** `grep` over `tests/`
shows **zero** existing uses of `watch_signals` / `assert_signal_*`; this suite has never run that
GUT path, and GUT here carries two local parse patches for 4.6.3 (`addons/gut/LOCAL_PATCHES.md`).
If it misbehaves, the fallback needs no GUT feature: connect a lambda that appends to a local
array and assert on the array.

**N4 — the station root gets `collision_layer = 0`, deliberately.** Verified consequence of
leaving it at the CharacterBody2D default of layer 1: `beam_behavior.gd:9` rays against bodies
with `_RAY_BLOCK_MASK = 1 | 1024`, truncates the beam segment at the hull edge, and then
`beam_behavior.gd:90` explicitly skips the blocker itself (`if n == blocker_collider: continue`)
while `:94` culls every target past `seg_len`. A layer-1 hull would therefore make the station
**immune to the player's mining laser** and shield everything behind it — a concrete bug, not a
style question. Layer 0 also keeps the player from colliding with a 256×256 body.

Contact damage is unaffected: it comes from the `HitBox` on layer 256 built by
`base_enemy.gd:53-55`, not from the body layer. Whether the hull *should* be a solid obstacle is a
sub-item 2/4 decision; if it becomes one, the opt-out is a `is_laser_blocking()` method returning
`false` (`beam_behavior.gd:67-68`). Recorded in `ENEMY.md`.

**N5 — the contact-damage loop is guarded** with `if config:` and `break`s after the first HitBox,
following `bomber.gd:18-26`, so a missing `.tres` warns instead of null-dereferencing in `_ready()`.

**Also for `ENEMY.md`:** there are **two** shipped paths that drive damage through
`get_node_or_null("HurtBox")` on group `"enemies"` members, not one —
`plasma_nova_module.gd:39-41` and `beam_behavior.gd:75-76, 99-102`. Both would have been leaked by
a disabled-hurtbox design. That is the reason the armour refuses damage inside
`_on_received_damage` rather than by switching the hurtbox off.
