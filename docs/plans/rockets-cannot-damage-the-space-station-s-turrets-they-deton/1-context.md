# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/missiles/homing/homing_missile.gd` | Player homing rocket. `_on_hit_box_area_entered` unconditionally `queue_free()`s on the first `area_entered`. | The bug: it is consumed by the armoured core before it can reach a turret behind it. |
| `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd` | Player straight-flying rocket. Same unconditional `queue_free()`. | Same bug, second source. |
| `assault/scenes/projectiles/bullets/bullet.gd` | Player primary weapon projectile. `_on_hit_box_area_entered` already checks `_hit_is_deflected(area)` before consuming itself, via `is_armored()` duck-typing on `area.get_parent()`. | This is the exact idiom already proven and documented as the general exemption mechanism (`CLAUDE.md`, `_hit_is_deflected` docstring: "Any future entity that needs to deflect a bullet without consuming it must expose its own `is_armored()`-shaped query"). |
| `assault/scenes/enemies/space_station/space_station.gd` | `SpaceStation.is_armored()` returns `live_turret_count() > 0`; `_on_received_damage` emits `armor_deflected` and refuses `Health` while armoured. | The thing rockets need to not be consumed by. |
| `assault/scenes/enemies/space_station/station_turret.gd` | `StationTurret` — the thing behind the core a rocket needs to actually reach. | Confirms turret's `HurtBox` mask (`97 | 1024`) already includes rockets (bit 32) — the geometry/layer chain is already correct, only the missile's own self-consumption is wrong. |
| `global/components/hitbox_component.gd` / `hurtbox_component.gd` | `HitBox` (Area2D, `damage`, `damage_type`) / `HurtBox` (Area2D, emits `received_damage(damage)` on `area_entered` if type accepted). | `_on_hit_box_area_entered(area: Area2D)` receives the `HurtBox` that was entered; `area.get_parent()` is the entity (mirrors `bullet.gd:140`). |
| `assault/scenes/projectiles/missiles/homing/homing_missile.tscn`, `warhead_missile.tscn` | Scene wiring: `HitBox` child (layer 32, mask 513, `damage_type = 1` ROCKET) connects `area_entered -> _on_hit_box_area_entered` on the missile root. | Confirms both missiles use the identical `HitBox` shape/connection pattern as `Bullet`, so the same duck-typed check transplants directly with no scene changes needed. |
| `tests/integration/test_station_incoming_damage_paths.gd` | Houses the CHARACTERIZED test `test_a_rocket_up_a_turret_lane_dies_on_the_armored_core_and_never_reaches_the_turret`, explicitly named in the task body as "the one that should go red" once this is fixed. Also the two `armor_deflected`-on-rocket tests that must keep passing. | Defines the target behaviour precisely and is the regression net. |
| `tests/integration/test_player_bullet_lifetime.gd` | Pins the bullet-side version of the same rule (`test_a_deflected_hit_does_not_consume_the_bullet`). | Model for the new rocket-side test. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `bullet.gd::_hit_is_deflected(area: Area2D) -> bool` | The exact duck-typed check (`area.get_parent()`, `has_method("is_armored")`, `is_armored()`) — copy this idiom verbatim into both missile scripts rather than inventing a new mechanism. No new HurtBox API needed; the task body's option 1 ("needs a 'was this absorbed' answer back from HurtBox") turns out to be already solved by this existing duck-type, which reads the *target*, not the HurtBox. |

## Conventions that constrain this

- **Duck-typed armour query, not a shared interface** (`CLAUDE.md` bullet convention): any projectile that wants the deflection exemption checks `target.has_method("is_armored") and target.is_armored()` on `area.get_parent()`. This is the sanctioned extension point — the docstring on `bullet.gd::_hit_is_deflected` says explicitly that a *future entity needing to deflect* must expose `is_armored()`, which `SpaceStation` already does. Nothing says only `Bullet` may call it.
- **A rocket still has no pierce mechanic.** Unlike `Bullet`, missiles carry no `pierces_remaining`/`MAX_PIERCE`. The fix is binary: deflected → keep flying (do nothing, no `queue_free()`); anything else → detonate (`queue_free()`, exactly as today).
- **Every projectile has exactly one owner** (`CLAUDE.md`): both missiles already free themselves off-screen (`homing_missile.gd`'s arena-bounds check, `warhead_missile.gd`'s `VisibleOnScreenNotifier2D`), so a missile that survives a deflection and then leaves the arena is already covered — no new leak surface.
- **Tests are GUT, characterization vs intent**: the target test is explicitly marked `CHARACTERIZED` and named in `ENEMY.md` and the task body as the one to flip red→green. It must be rewritten to assert the new, correct behaviour once the fix lands, and `ENEMY.md`'s "Load-bearing dependency" / "core hurtbox" sections need the now-stale "a rocket cannot reach a turret" warning corrected (structural doc update — `updating-project-docs` territory since this changes documented entity behaviour).
