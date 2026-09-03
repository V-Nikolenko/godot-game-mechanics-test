# Review — Station and turrets as a destructible entity (EPIC sub-item 1)

VERDICT: CHANGES_REQUESTED

Reviewed against the real files, not the plan's summaries. The core design decision
(`extends BaseEnemy` + a single `_on_received_damage` override, hurtbox stays live, damage is
refused) is **correct and well-grounded** — I verified it against the engine semantics and the
established project pattern, and it is better than the plan even claims. The scope is
finishable in one session.

But there are **four defects that would ship silently broken behaviour** (F1–F4), one test-suite
convention violation (F5), and several under-specifications. None require a redesign; all are
local corrections to the plan. Fix F1–F6 and this is APPROVED.

---

## Verified correct — do not change these

| Plan claim | Verdict | Evidence |
|---|---|---|
| `extends BaseEnemy` is the project pattern, not an inheritance violation | **Correct** | All 9 enemies do it: `gunship.gd:2`, `ram_ship.gd:2`, `bomber.gd:2`, `interceptor.gd:3`, `drone_interceptor.gd:3`, `kamikaze_drone.gd:2`, `sniper_enemy.gd:3`, `light_assault_ship.gd:2`, `bonus_drone.gd:9`. "Composition over inheritance" in `CLAUDE.md` refers to building entities from `global/components/` (Health/HurtBox/HitBox/effects), which `BaseEnemy` itself does. No violation. |
| Overriding `_on_received_damage` genuinely intercepts damage | **Correct** | `base_enemy.gd:23` connects `Callable(self, "_on_received_damage")`; GDScript Callables dispatch by name, so the subclass override wins. **Exact precedent exists**: `ram_ship.gd:27` overrides `_on_received_damage` to refuse the first hit — the plan is reusing a shipped pattern, not inventing one. |
| `Health.set_health` emits on every call including 0→0 | **Correct** | `health_component.gd:40-42` — `current_health = changed_health; amount_changed.emit(current_health)`, no guard. `decrease()` clamps at 0 (`:33`) and still calls `set_health`. The idempotence hazard is real. |
| Rejecting `DamageReaction` | **Correct** | `damage_reaction.gd:45` is `get_parent().queue_free()` inside an unconditional `if current <= 0` block, and `_on_received_damage` (`:31-38`) has no refuse hook. The plan's reasoning holds. |
| Coordinate space: sprite pixels are final screen pixels, never × `WORLD_SCALE` | **Correct** | `arena_camera.gd:33-35` documents `WORLD_SCALE` as "applied to all spawn offsets and EnemyPathMover movements". The only two multiplication sites are `wave_manager.gd:172` (`cam.global_position + offset * ArenaCamera.WORLD_SCALE`) and `enemy_path_mover.gd:77`/`:83` (`movement.sample(...) * ArenaCamera.WORLD_SCALE`). `player_fighter.tscn:312-315` `ShipSprite2D` has no `scale` line. 256×256 at scale 1 is right, and this satisfies the EPIC constraint that the plan "state exactly which space the sprite is authored in". |
| `_rotate_sprite()` is a harmless no-op | **Correct** | `base_enemy.gd:44-47` looks up `"AnimatedSprite2D"`; a `Sprite2D`-only scene gets `null` and returns. |
| Signal-arity trap | **Correct** | `health_component.gd:4` declares `signal amount_changed` (zero params), `:42` emits with one. `tests/README.md:62-66` confirms handlers must take one argument. |
| PixelLab: 256×256 in one generation, `view = "high top-down"` | **Correct** | Confirmed against the live `create_image_pixflux` schema: 16–400 px per side, total area ≥ 32×32, `view` enum is `side` / `low top-down` / `high top-down`, cost 1 generation. |
| Gunship hurtbox `collision_layer = 512` / `collision_mask = 65`, overridden by `BaseEnemy` to `97 \| 1024` | **Correct** | `gunship.tscn:67-69`, `base_enemy.gd:25`. |
| Research honesty | **Acceptable** | `2-research.md` opens by declaring four 403s and a 402, marks unverifiable numbers *(excerpt only)*, and every row carries a tradeoff. It explicitly labels the parameter choices as this project's decisions rather than industry standards. That is the right way to handle a fetch failure. |

**One benefit the plan under-claims:** keeping the HurtBox live and refusing damage in
`_on_received_damage` also correctly gates the player's AoE module, which bypasses physics
entirely — `plasma_nova_module.gd:39-41` does `n.get_node_or_null("HurtBox").received_damage.emit(_DAMAGE)`.
A "disable the hurtbox" implementation would have been bypassed by that path. Worth stating in
`ENEMY.md` as a reason the design is what it is.

---

## Findings — must fix before implementation

### F1 — Turret HurtBox `collision_mask = 65` makes turrets immune to the player's missiles

`3-plan.md:182` says "Copy the gunship's `collision_layer = 512` / `collision_mask = 65` exactly".
For the gunship that is safe **only because** `base_enemy.gd:25` immediately overwrites the mask
with `97 | 1024`. `StationTurret extends Node2D` (`3-plan.md:35`) — **nothing overrides it**, so the
mask stays at 65 = bits 1 + 7.

- Player bullets: `bullets/bullet.tscn:44` `collision_layer = 64` (bit 7) → detected. Fine.
- Player missiles: `missiles/homing_missile.tscn:54` and `warhead_missile.tscn:60` are
  `collision_layer = 32` (bit 6) → **not in mask 65, silently pass through every turret.**
- Asteroid contact (1024), which `base_enemy.gd:25` includes → also dropped.

The plan's own risk table admits unit tests emitting `received_damage` directly cannot catch this,
then prescribes the wrong value anyway. **Set the turret HurtBox mask explicitly to `97 | 1024` in
`station_turret.gd::_ready()`** (mirroring `base_enemy.gd:25`), and keep `collision_layer = 512`
because that is what the projectile HitBoxes monitor (`bullet.tscn:45` / missiles `:55` are
`collision_mask = 513` = 1 + 512).

### F2 — `turret_score_value` awards nothing; it is a dead config field

`3-plan.md:120-125` adds `turret_score_value: int = 150` to `SpaceStationConfig`. Nothing can pay
it out. `score_tracker.gd:1-11` and `:55-75` register enemies only via
`WaveManager.enemy_spawned` and `EventBus.enemy_spawned_orphan`, and award kill points from
`BaseEnemy.died` + `score_value` (`base_enemy.gd:39-42, 71`). A turret is a `Node2D`, is never
spawned through `WaveManager`, and by the plan's own design (`3-plan.md:84`) **never leaves the
tree**, so neither `died` nor `tree_exited` ever reaches ScoreTracker.

Either drop the field this session, or specify the payout path (e.g. the station emits
`EventBus.enemy_spawned_orphan` per turret, or awards directly). Do not ship a `.tres` field that
does nothing — a later session will assume it works.

### F3 — `collision_damage = 40` is inert as planned

`base_enemy.gd:49-60` `_add_contact_hitbox()` **hardcodes `hb.damage = 20`** and never reads the
config. Enemies that want config-driven contact damage re-apply it themselves after
`super._ready()`: `bomber.gd:25`, `light_assault_ship.gd:23`, `ram_ship.gd:20-23`,
`drone_interceptor.gd:148`. The gunship — the exemplar the plan copies — **forgot to**, so
`gunship_config.tres:8 collision_damage = 30` is silently ignored and the gunship rams for 20.

The plan copies the gunship and inherits the bug. Either apply it in `space_station.gd::_ready()`
(the majority pattern) or state in the plan that the field is decorative. Also note the gunship
bug in `BACKLOG.md` *Discovered*.

### F4 — `_add_contact_hitbox()` does not copy the CollisionShape2D's transform

`base_enemy.gd:56-59` does `shape_node.shape = col.shape` on a **fresh** `CollisionShape2D` — it
copies the shape resource but not the node's `scale`/`position`. `gunship.tscn:63-65` scales its
`CollisionShape2D` by 2.31, so the gunship's contact hitbox is ~2.3× smaller than its body.

For a 256×256 station this matters far more than for a 40 px gunship. **Author the station's
`CollisionShape2D` shape at true size with `scale = 1` and `position = (0,0)`**, or the contact
hitbox will be wrong by whatever scale factor is used. Add this as an explicit line in the plan's
scene spec; it is exactly the kind of thing that gets copied from the gunship without thought.

### F5 — `tests/unit/test_space_station.gd` violates the suite's own layout rule

`tests/README.md:14-18` — `unit/` is "One file per autoload or `global/components/` component.
**No scene loading.**"; `integration/` is "Several systems wired together". I confirmed no file in
`tests/unit/` loads a `.tscn` today. The planned test instances the real `space_station.tscn`
(`3-plan.md:155`) and even cites `tests/integration/test_player_damage_chain.gd` as its idiom
(`3-plan.md:156-157`).

Move it to **`tests/integration/test_space_station.gd`**. The GutTest / `add_child_autofree`
idiom itself is correct (`test_player_damage_chain.gd:11, 59`; `test_damage_reaction.gd:4, 16-27`),
as is driving damage by `hurt_box.received_damage.emit(n)` (`test_damage_reaction.gd:49`).

### F6 — `test_armored_core_still_registers_the_hit` names no observable

`3-plan.md:164` asserts "armour ping fires / hit is observed" without saying what is asserted.
This is the one test that distinguishes the chosen design from the design research explicitly
ruled out (`2-research.md`, answer 2), so it must not be hand-wavy. Name the assertion in the
plan — either add an `armor_ping(damage)` signal on `SpaceStation` and use GUT's
`watch_signals` / `assert_signal_emitted`, or assert
`hit_flash_player.current_animation == "hit"` after the hit. As written it risks degenerating
into a duplicate of `test_core_ignores_damage_while_any_turret_lives`.

---

## Findings — should fix

### F7 — The justification for the `_live_turrets` counter contradicts the plan's own design

`3-plan.md:88-90` justifies the integer counter with "`queue_free()` only leaves the tree at end of
frame. Counting live turrets by counting children would be frame-timing-dependent". But
`3-plan.md:84` decides turrets **stay in the tree as wreckage** and are never freed. With that
decision the frame-timing argument evaporates, and the plainly simpler alternative is unexamined:

```gdscript
func live_turret_count() -> int:
    var n := 0
    for t in $Turrets.get_children():
        if t.is_alive(): n += 1
    return n
```

This is deterministic, needs no `destroyed` signal wiring, and **structurally cannot**
double-decrement — deleting the entire class of bug that `test_destroyed_turret_ignores_further_damage`
(`3-plan.md:166`) exists to guard. The signal counter is still defensible (O(1), and the
`destroyed` signal is wanted for sub-items 3/4 anyway), but the plan must justify it on those
grounds instead of on a reason its own design invalidates. The turret's `if not _alive: return`
guard is required either way.

### F8 — Nothing specifies which node applies `turret_health`, and no test pins it

`3-plan.md:120-126` puts `turret_health` on `SpaceStationConfig` but never says who writes it into
each turret's `Health`. It works (Godot readies children before parents, so
`SpaceStation._ready()` can push values into already-`_ready`'d turret `Health` nodes — same
ordering `gunship.gd:36-37` relies on), but the plan must say it explicitly. And
`test_config_values_win_over_scene_health` (`3-plan.md:168`) covers the **core only**; add the
turret case, since the config-driven rule in `CLAUDE.md` is exactly what that test exists to pin.

### F9 — `add_to_group("enemies")` is omitted

Every other enemy does it right after `super._ready()` (`gunship.gd:31`, `ram_ship.gd:14`). The
group is consumed by player targeting and AoE modules — `ai_targeting_module.gd:49`,
`plasma_nova_module.gd:34`, `emp_blast_module.gd:39`, `beam_behavior.gd:75`,
`warhead_missile_shooting_state.gd:61`, `dash_state.gd:65`. Without it the station is invisible to
homing missiles and the plasma nova. One line; add it now.

**Correct a factual error in `1-context.md` while you are there:** it claims the station "must join
the `"enemies"` group" for `ENEMIES_CLEARED` to work. It does not —
`level_director.gd:78-81` connects `_wait_enemies_cleared`, and `level_director.gd:106` polls
`wave_manager.enemy_container` child count (`wave_manager.gd:15, 181`). The group is irrelevant to
that end condition. Sub-item 2 will be planned off this note; fix it.

### F10 — Turret hurtbox teardown: `monitorable = false` alone is not enough

`3-plan.md:82-83` sets `monitorable = false` **and** disables the shape. Keep both — but note the
reason: `monitorable = false` only stops the *projectile's* HitBox from seeing the turret; the
turret's own `HurtBox._on_area_entered` (`hurtbox_component.gd:10-18`) fires off `area_entered` on
its own `monitoring`, so with only `monitorable = false` a dead turret would still emit
`received_damage`. The shape disable is what actually closes it. Setting `monitoring = false` as
well is cheaper to reason about than relying on that.

### F11 — New `.tscn`/`.tres` files must carry real ext_resource UIDs

`tests/integration/test_resource_uid_integrity.gd` asserts every `[ext_resource]` UID matches the
target's declared UID, reading from disk (`tests/README.md:20-31`). Commit `94e251d` fixed 8 stale
ones. Three new scene/resource files are being authored here — if they are hand-written with
invented or copy-pasted UIDs the gate goes red. Build them through the Godot editor/MCP, or copy
each UID from the target's `.gd.uid` / `.import` / header line, and run
`godot --headless --import` before the suite. Add this to the build sequence.

### F12 — `1-context.md` and `3-plan.md` contradict each other on `BaseEnemy`

`1-context.md` states the core "cannot extend `BaseEnemy` unmodified" because it "always frees
itself at 0 HP". `3-plan.md:44-64` reverses this without acknowledging the reversal. The reversal
is **right for sub-item 1** (core death == station death, `base_enemy.gd:65-73` is exactly what is
wanted). But sub-item 5 requires "station death plays out" before the level advances, and
`base_enemy.gd:73` `queue_free()`s in the same frame as `died.emit()`. State this in the plan's
*Out of scope* section so sub-item 5 knows it must override `_on_health_changed`, rather than
discovering it mid-session.

---

## Checks that came back clean

- **Reinvention:** none. The plan reuses `Health`, `HurtBox`/`HitBox`, `HitEffect`,
  `ExplosionEffect`, `ShipConfig` and the `hit_flash_vs.tres` shader, and explicitly refuses to
  create a `bosses/` directory or a second HP counter. `2-research.md`'s rejected options are
  recorded with reasons.
- **`CLAUDE.md` conventions:** per-enemy folder + scene + script + `*_config.tres` + `ENEMY.md`
  matches `assault/scenes/enemies/gunship/`. In-script state, not a `states/` folder — correct for
  a simple entity. Config applied in `_ready()` with the `.tres` winning — correct.
- **Test plan can fail:** yes. `test_core_becomes_damageable_after_last_turret_dies` fails against
  an inverted flag; `test_destroyed_turret_ignores_further_damage` fails against the naive
  decrement and directly targets the `set_health`-always-emits trap (`health_component.gd:40-42`);
  `test_station_with_no_turrets_is_immediately_damageable` is a genuine degenerate-case boundary.
  Not vacuous — subject to F5 and F6.
- **Scope:** one config script + one `.tres` + two scripts + two scenes + three 1-generation
  sprites + ~8 tests + `ENEMY.md`. Comparable to the gunship, which already exists at this size.
  Finishable and verifiable in one session. The checkpointed build sequence
  (`3-plan.md:138-151`) with `--check-only` between steps is a good call.
- **`ExplosionEffect` parent requirement:** `explosion_effect.gd:27-33` needs `get_parent()` to be
  a `Node2D` with a non-null parent. Satisfied under `add_child_autofree` on the GutTest node. The
  plan's risk row is accurate.

---

## Summary of required changes

1. **F1** Turret HurtBox `collision_mask = 97 | 1024`, set in script — not the gunship's raw 65.
2. **F2** Drop `turret_score_value` or specify how it is paid out.
3. **F3** Apply `config.collision_damage` to the contact HitBox, or declare it decorative.
4. **F4** Station `CollisionShape2D` authored at true size, `scale = 1`, `position = (0,0)`.
5. **F5** Test file moves to `tests/integration/test_space_station.gd`.
6. **F6** Name the concrete assertion for `test_armored_core_still_registers_the_hit`.
7. **F7–F12** Fix the counter justification, name the node that applies `turret_health` (+ test it),
   add `add_to_group("enemies")`, set `monitoring = false` too, add the UID-integrity precaution to
   the build sequence, correct `1-context.md`'s `ENEMIES_CLEARED` claim, and record the sub-item-5
   `queue_free` constraint in *Out of scope*.

Re-submit with these folded in and the plan is approved. The architecture does not need to change.

---

# Round 2

VERDICT: APPROVED

All twelve findings are genuinely addressed, and I re-verified each fix against the source rather
than against the revision note. The three items I was asked to check specifically — the `97 | 1024`
mask, the derived `live_turret_count()`, and whether the `armor_deflected` assertion is expressible
in this vendored GUT — all came back clean.

Four **binding implementation notes** below (N1–N4). They are corrections to note-level detail, not
to the design, and none of them justifies a third review round — but N1 is a wrong sentence in the
plan that would ship a broken boss past a green suite, so read it before writing the scene.

## Re-verification of F1–F12

| # | Fix | Verified against | Verdict |
|---|---|---|---|
| F1 | Turret HurtBox `collision_layer = 512`, `collision_mask = 97 \| 1024` set in `station_turret.gd::_ready()` | `97 \| 1024` = bits 1 + 6 + 7 + 11. Bit 7 (64) = player bullets `bullets/bullet.tscn:44`; bit 6 (32) = `homing_missile.tscn:54` / `warhead_missile.tscn:60`; bit 11 (1024) = asteroids, confirmed `small_asteroid.tscn:46` and `big_asteroid.tscn:45` — so `base_enemy.gd:25`'s "asteroid contact (1024)" comment is accurate, not folklore. Byte-identical to what `BaseEnemy` gives every other enemy. Layer 512 is what the projectile HitBoxes monitor (`bullet.tscn:45`, missiles `:55`, both `collision_mask = 513` = 1 + 512). Both detection directions covered. | **Correct** |
| F2 | `turret_score_value` dropped, moved to Out of scope | `3-plan.md:183-190, 283`. Reasoning reproduced accurately. | **Correct** |
| F3 | `config.collision_damage` re-applied after `super._ready()` | Matches the majority pattern at `bomber.gd:18-26`. `add_child()` is immediate, so the HitBox created by `_add_contact_hitbox()` (`base_enemy.gd:60`) is in `get_children()` by the time the loop runs. See **N2** for a nit. | **Correct** |
| F4 | True-size shape, `scale = 1`, `position = (0,0)` | `3-plan.md:158-164`; removes the `base_enemy.gd:56-59` transform-loss entirely rather than working around it. Right call. | **Correct** |
| F5 | `tests/integration/test_space_station.gd` | Satisfies `tests/README.md:14-18`. | **Correct** |
| F6 | `armor_deflected(damage)` + `watch_signals` / `assert_signal_emitted_with_parameters` | Both exist in the vendored GUT 9.7.1: `watch_signals` at `addons/gut/test.gd:534` → `addons/gut/signal_watcher.gd:122`; `assert_signal_emitted_with_parameters(p1, p2, p3=-1, p4=-1)` at `addons/gut/test.gd:1637`. The planned call `assert_signal_emitted_with_parameters(station, "armor_deflected", [50])` matches the object+name+params overload exactly — the docstring example at `test.gd:1620` is `assert_signal_emitted_with_parameters(obj, 'some_signal', ['one', 'two', 'three'])`, and `p4` defaults to -1 = "most recent emission" (`signal_watcher.gd:160-161`). No arity hazard: `watch_signals` connects every signal on the object (`signal_watcher.gd:123-126`) and `_on_watched_signal` accepts 0–11 args (`signal_watcher.gd:77-80`), comfortably above `CollisionObject2D.input_event`'s 3. See **N3**. | **Correct, and expressible** |
| F7 | Derived `live_turret_count()`, no counter; `destroyed` retained as a pure event hook | `3-plan.md:87-104`. No ordering hazard in the production path: `BaseEnemy` connects `received_damage` in `_ready()` (`base_enemy.gd:23`), so `_on_received_damage` can never fire before `SpaceStation._ready()` has populated the turret list. One residual validity hazard the revision introduced — see **N1**. | **Correct** |
| F8 | `SpaceStation._ready()` applies `turret_health`; new test pins it | Child-before-parent ready ordering is real and is the same ordering `gunship.gd:36-37` depends on. `Health._ready()` (`health_component.gd:16-17`) only clamps, so a later `max_health` write is not undone. | **Correct** |
| F9 | `add_to_group("enemies")`, justified by consumers not by `ENEMIES_CLEARED` | `gunship.gd:31`, `ram_ship.gd:14`; consumers at `ai_targeting_module.gd:49`, `plasma_nova_module.gd:34`, `emp_blast_module.gd:39`, `warhead_missile_shooting_state.gd:61`, `beam_behavior.gd:75-76`. The `ENEMIES_CLEARED` correction is right: `level_director.gd:106` reads `wave_manager.enemy_container`. | **Correct** |
| F10 | All three of `monitoring`, `monitorable`, shape `disabled` | Reasoning about `hurtbox_component.gd:10-18` reproduced correctly. | **Correct** |
| F11 | UID hygiene as build step 6 | `tests/README.md:20-31`; commit `94e251d`. | **Correct** |
| F12 | Sub-item-5 `queue_free`-same-frame constraint recorded | `base_enemy.gd:71-73` — `died.emit()` then `queue_free()` with nothing between. | **Correct** |

`1-context.md` corrections appended rather than silently rewritten — right call; the diff history is
what makes the earlier error findable.

**Bonus confirmation for the `plasma_nova_module` justification (`3-plan.md:80-85`):** it is stronger
than the plan states. `beam_behavior.gd:75-76, 99-102` does the *same* thing — collects group
`"enemies"`, then `n.get_node_or_null("HurtBox")` and drives damage through it. So the mining laser
is a **second** shipped path that a disabled-hurtbox implementation would have leaked. Two consumers,
not one; worth saying so in `ENEMY.md`.

## Binding implementation notes

### N1 — "The core's HurtBox needs no such line" is wrong for the *layer*

`3-plan.md:140` says the core's HurtBox needs no explicit collision setup because
`BaseEnemy._ready()` sets it. `base_enemy.gd:25` sets **`collision_mask` only** — it never touches
`collision_layer`. The gunship works because `gunship.tscn:68` authors `collision_layer = 512` in the
scene file.

If `space_station.tscn`'s HurtBox is left at the Area2D default (layer 1), the projectile HitBoxes
(`collision_mask = 513` = 1 + 512) would still see it via bit 1 — but the station's own
`CharacterBody2D` root is also on default layer 1, so hit resolution becomes accidental rather than
designed. **Author `collision_layer = 512` explicitly on the core's HurtBox node in the scene,
exactly as `gunship.tscn:68` does.**

This is the highest-value note in this round because of the plan's own acknowledged coverage gap
(`3-plan.md:264-266`): every planned test emits `received_damage` directly, so **all nine would pass
with a core that no bullet can ever hit.** A green suite is not evidence here. Correct the sentence
at `3-plan.md:140` before building the scene.

### N2 — `_turrets` provenance is unspecified, and one test row would raise a freed-instance error

`3-plan.md:92` iterates `for t in _turrets` without ever saying where `_turrets` comes from. Combined
with the boundary row at `3-plan.md:253` — "Kill all four in `before`, **or free the turrets**" — a
cached `Array` of turret references plus a freed turret gives
`Attempt to call function 'is_alive' on a previously freed instance`. `tests/README.md:62-63` is
explicit that GUT fails a test on any unexpected engine error, so that path is a guaranteed red for a
reason unrelated to the code under test.

Two-part fix, both cheap:
- Derive the list live from the container — `for t in $Turrets.get_children()` — and guard
  `if is_instance_valid(t) and t.is_alive()`. A live read is already what F7's "structurally cannot
  desync" argument is buying; a cached array partially gives that back.
- Drop the "or free the turrets" option from the boundary test. Killing all four is what the
  production path actually does, so it is also the more faithful test.

### N3 — This is the suite's first use of GUT's signal assertions

`grep` over `tests/` returns **zero** existing uses of `watch_signals` or any `assert_signal_*`. The
API is present and correct in the vendored copy (verified above), but this project vendored GUT with
two local parse-error patches for Godot 4.6.3 (`addons/gut/LOCAL_PATCHES.md`), so no path is proven
here until it runs. Both `armor_deflected` (`3-plan.md:250`) and "`destroyed` emitted exactly once"
(`3-plan.md:252`, which needs `assert_signal_emit_count`) depend on it.

Exercise it in build step 1's deliberate red run, not at the end. If it misbehaves, the fallback is
three lines and needs no GUT feature — connect a lambda that appends to a local array and assert on
the array.

### N4 — Decide the station root's `collision_layer` deliberately

The plan specifies collision layers for both HurtBoxes but says nothing about the
`CharacterBody2D` root. The gunship leaves it at the default (layer 1, environment) — invisible at
40 px, but this body is 256×256. Consequence: `beam_behavior.gd:9` casts its blocking ray with
`_RAY_BLOCK_MASK = 1 | 1024` against **bodies**, so a layer-1 station hull will stop the player's
mining laser dead at its edge and shield everything behind it.

That may well be what you want for a station. Decide it rather than inherit it, and record the
decision in `ENEMY.md`. Note `beam_behavior.gd:67-68` offers the opt-out: a collider exposing
`is_laser_blocking()` returning `false` is skipped.

### N5 (nit) — guard the contact-damage loop

`3-plan.md:150-153` writes `(child as HitBox).damage = config.collision_damage` unguarded.
`bomber.gd:18-26` wraps the equivalent loop in `if config:` and `break`s after the first HitBox.
Follow it — `config` has a `load()` default, but a missing `.tres` would otherwise be a null-deref
inside `_ready()` rather than a warning.

## Gating criteria — final pass

- **Reinvention:** none. F7 removed the last piece of bespoke state.
- **`CLAUDE.md` conventions:** satisfied. `extends BaseEnemy` is the pattern (9/9 enemies), stats are
  config-driven with the `.tres` winning, coordinate space is stated explicitly and correctly, and
  the per-enemy folder + `ENEMY.md` layout matches `gunship/`.
- **Test plan can fail:** yes, and F6 fixed the one row that could have degenerated. The two boundary
  rows target real traps (`health_component.gd:40-42`; the zero-turret degenerate case). The
  coverage gap is disclosed rather than hidden — subject to N1, which is precisely the bug that gap
  conceals.
- **Unexamined simpler alternative:** none remaining; the simpler alternative from round 1 was
  adopted.
- **Research:** tradeoffs on every row, fetch failures declared, unverifiable numbers marked, and the
  PixelLab claim independently confirmed against the live tool schema.
- **Scope:** one config + two scripts + two scenes + three 1-generation sprites + nine tests +
  `ENEMY.md`. Comparable to the gunship, which already exists at this size. Checkpointed at
  `--check-only` boundaries. Finishable and verifiable in one session.

Approved. Implement it.
