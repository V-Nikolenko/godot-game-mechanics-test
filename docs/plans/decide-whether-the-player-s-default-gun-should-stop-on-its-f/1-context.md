# Context

## The question

`PierceModule` ("Penetrating Rounds") is strictly a downgrade today. The root cause:
`bullet.gd`'s ordinary-hit path (`_on_hit_box_area_entered`) never calls `queue_free()` on a hit —
it only calls `expired.emit()`, and nothing in the player-bullet spawn path
(`WeaponBehavior._launch()`) wires `expired` to `queue_free()` (that wiring is reserved for
`screen_exited`, deliberately — see `bullet.gd`'s header). So an unmodded player bullet already
pierces every enemy it touches, forever, at full damage, until it leaves the screen. Equipping
`PierceModule` only *caps* that at 3 extra hits with decaying damage (50→28→15→8), then — since
the fall-through branch still doesn't free the bullet — it also keeps flying at 8 forever. The
module never grants anything a default shot didn't already have; it only narrows it.

Genre convention is the reverse: an unmodified gun kills what it hits and stops; piercing multiple
enemies with one shot is what an upgrade buys.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/bullets/bullet.gd` | The shared bullet script — used unpooled by the player and pooled by `AllyFighter` | `_on_hit_box_area_entered()` is the ordinary-hit path; `MAX_PIERCE`/`PIERCE_DAMAGE_FACTOR`/`pierces_remaining` live here |
| `assault/scenes/player/weapons/behaviors/weapon_behavior.gd` | `_launch()` is the single hand-off point that gives an unpooled player bullet its own lifetime (`free_when_offscreen()`) | The natural place to also wire "stop on an ordinary hit", because it only ever runs for player-fired, unpooled bullets — never for `AllyFighter`'s pooled ones |
| `global/ship_modules/pierce_module.gd` | Sets `player.pierce_module_active = true`; weapon behaviors read this to set `Bullet.MAX_PIERCE` on spawn | No change needed — the module's own contract ("pierce through up to 3 enemies, damage decays") is already correct; only the *baseline* it's being compared against is wrong |
| `global/components/bullet_pool.gd` | Recycles `AllyFighter`'s pooled bullets; connects `bullet.expired -> _recycle()` in `_prewarm()`, once, forever | **Already implements "stop on first hit" today** — any `expired` emission (hit, range cap, or screen exit) recycles a pooled bullet immediately. Confirms this change brings the player path in line with the ally path, not the other way around |
| `assault/scenes/enemies/space_station/space_station.gd` | `is_armored()` (public, live-computed from `live_turret_count() > 0`) governs whether the core's `_on_received_damage` override deflects (`armor_deflected.emit()`, no `Health.decrease()`) or applies damage | The one entity in the whole roster whose hurtbox can be hit without taking real damage. If a "stop on hit" bullet treats a deflection as a stop, the turrets — and the boss — become unkillable. This is the coupling the backlog item warns about |
| `assault/scenes/enemies/space_station/station_turret.gd` | Plain `Node2D`, own `HurtBox`, `_on_received_damage()` always calls `health.decrease(damage)` — never deflects | Confirms only the **core's** hurtbox needs the exemption; turrets behave like every other enemy |
| `assault/scenes/enemies/ram_ship/ram_ship.gd` | Has a first-hit "damaged state" transition that also doesn't apply damage | **Does not need the exemption**: `hurt_box.collision_mask = 33` (missiles + layer 1 only) excludes bullets entirely until `_enter_damaged_state()` runs, so a player bullet's `HitBox` never overlaps a pre-damaged ram ship's `HurtBox` in the first place. Confirmed by grep — no bullet-vs-ram-ship interaction exists to break |
| `tests/integration/test_player_bullet_lifetime.gd` | The characterization/intent suite for bullet lifetime, including `test_pierce_module_today_only_reduces_damage`, explicitly marked "changing pierce behaviour should fail this test; that is the signal the change was deliberate" | This is the test file the task requires me to make deliberately red, then rewrite green under the new contract |
| `tests/integration/test_space_station.gd` | Two real-physics tests (`test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core`, `test_a_real_bullet_damages_the_core_once_the_armor_is_broken`) that fire a real `bullet.tscn` up a turret lane | Both instantiate the bullet directly (`_container.add_child(bullet)`), **bypassing `WeaponBehavior._launch()`** — so the new `expired -> queue_free` wiring (added only in `_launch()`) never attaches to these test bullets. Both tests only assert `is_instance_valid(bullet)`, never `is_queued_for_deletion() == false`, so they keep passing unmodified and remain the coupling's regression guard |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `beam_behavior.gd:67-68` — `if coll.has_method("is_laser_blocking"): is_block = coll.is_laser_blocking()` | The established idiom in this codebase for a projectile querying a foreign enemy for a boolean property with no shared interface/base class. `SpaceStation.is_armored()` is public and already used this way by tests. The fix reuses the exact same duck-typed-method pattern rather than inventing a new contract (a shared `Armored` interface, a `HurtBox` flag kept in sync, a new signal) |
| `WeaponBehavior._launch()` (`weapon_behavior.gd:23-25`) | Already the sole hand-off point for unpooled player bullets; already proven safe to extend (this is exactly how `free_when_offscreen()` was added for the screen-exit rule) |

## Conventions that constrain this

- **Signal arity & the project's own rule**: don't touch `HurtBox.received_damage(damage: int)`'s
  contract — many unrelated listeners depend on its current shape (`damage_reaction.gd`,
  `station_turret.gd`, `base_enemy.gd`, several ship modules that emit it directly). The fix must
  not need to change that signal.
- **"The pool is smart, bullets are dumb"** (`docs/BULLET_POOL.md`, restated in `bullet.gd`'s
  header): any new lifecycle wiring belongs in the launcher/pool, not baked into `bullet.gd`
  itself calling `queue_free()` on itself. `bullet.gd` stays a dumb data+signal object; only
  `_launch()` (player) and `bullet_pool.gd` (ally) decide what `expired` means for their bullets.
- **`CLAUDE.md`'s existing rule** ("Never wire `Bullet.expired` to `queue_free` on the player
  path") is the rule this task is explicitly revisiting, and it must be rewritten — not silently
  contradicted — everywhere it's stated: `bullet.gd`'s header, `weapon_behavior.gd`'s header,
  `docs/architecture/PROJECT.md`, `tests/README.md`, `CLAUDE.md` itself,
  `assault/scenes/enemies/space_station/ENEMY.md`.
- **Deferred pierce reduction** (`_apply_pierce` via `call_deferred`): the deflection check must
  run and return *before* the pierce branch, so a deflected hit costs no pierce charge — it never
  happened as far as the gun is concerned.
