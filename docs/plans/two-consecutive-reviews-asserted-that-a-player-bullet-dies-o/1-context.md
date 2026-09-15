# Context — player bullet lifetime and piercing

## The claim under investigation

The backlog task says two consecutive reviews asserted that a player bullet dies on its first
hurtbox overlap, and that it does not. **Confirmed, and it is worse than the task states: a
default player bullet is never freed at all — not on hit, and not off-screen.**

Traced end to end:

| Step | File:line | What actually happens |
|---|---|---|
| Player fires | `assault/scenes/player/states/weapon_state.gd:83` | `beh.fire(self, mode, muzzle)` |
| Bullet spawned | `straight_behavior.gd:22`, `spread_behavior.gd:21`, `long_range_behavior.gd:17`, `sniper_behavior.gd:87` | plain `state.add_child(bullet)` — **no `BulletPool`, no `expired` listener** |
| Hits a hurtbox | `bullet.gd:79-84` | `pierces_remaining == 0` → `expired.emit()` and nothing else. No `queue_free()` |
| Runs out of range | `bullet.gd:45-49` | `expired.emit()` **and** `queue_free()` — but gated on `range_px > 0.0` |
| Leaves the screen | `bullet.gd:51-52` | `expired.emit()` and nothing else |

`expired` has exactly two connections in the whole repo — `bullet_pool.gd:56` and
`sniper_enemy.gd:102` — and neither is on the player path.

## Two distinct consequences

**1. A node leak, unambiguous.** Three of the five player modes ship `range_px = 0.0`
(`default.tres:11`, `long_range.tres:11`, `sniper_shot.tres:11`), so their bullets hit *none* of
the three free paths. Every shot stays a child of `WeaponState` for the rest of the mission,
running `_physics_process` and travelling to infinity. `bullet.tscn` is not cheap: `Area2D` +
2 `Line2D` + a **`WorldEnvironment`** + a notifier + a second `Area2D` for the HitBox. At
`default.tres`'s `fire_interval = 0.18`, three minutes of held fire is ~1000 of them. Framerate
decays over a mission and there is no visible cause.

`gatling.tres` (450) and `spread.tres` (360) do free at range, so the leak is mode-dependent —
which is exactly why it has never been noticed.

**2. Infinite piercing, a design question.** With a live HitBox and no free, the bullet keeps
travelling and damages every hurtbox in its lane. `PierceModule` ("Penetrating Rounds", 3 pierces
at ×0.55 damage each, `pierce_module.gd:11`) is therefore **strictly a downgrade** — the base gun
already pierces without limit, so equipping the module only shrinks the damage of hits 2-4 (50 →
27 → 15 → 8) and then, once `pierces_remaining` hits 0, the bullet flies on at 8 anyway.

## The load-bearing coupling: the space station boss

`docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-/3-plan.md` rests on this
exact behaviour, and `tests/integration/test_space_station.gd:150-171` says so in its header:

> **a player bullet is not consumed by the first hurtbox it overlaps.**
> … If it is ever "fixed" without also changing the station, every shot aimed at a turret is
> absorbed by the core one to two physics frames early, deflects for 0 and dies — **the turrets
> become unkillable and so does the boss.**

`SpaceStation._on_received_damage()` (`space_station.gd:169-174`) refuses damage while any turret
lives but keeps the `HurtBox` live and full-hull-sized on purpose. The turrets sit at station-local
(±76, ±76) **inside** the core's 240×240 rect, so a shot must cross the core's hurtbox to reach a
turret. Consuming the bullet on the first overlap makes the boss unwinnable.

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `assault/scenes/projectiles/bullets/bullet.gd` | Player/ally bullet: travel, range cap, pierce, `expired` | Owns all four "done" paths |
| `assault/scenes/projectiles/bullets/bullet.tscn` | The scene, incl. `VisibleOnScreenNotifier2D` and `HitBox` | Shared by player **and** ally pool |
| `assault/scenes/projectiles/bullets/sniper_bullet.tscn` | Same script, unlimited-pierce variant | Player-only, same leak |
| `assault/scenes/player/weapons/behaviors/*.gd` | The four spawn sites | Where lifetime ownership must be taken |
| `global/components/bullet_pool.gd` | Recycles bullets via `expired` | **Blocks** a fix inside `bullet.gd` (see below) |
| `assault/scenes/allies/ally_fighter/ally_fighter.gd:11,22-25` | Pools `bullet.tscn`, size 8 | The reason `bullet.gd` may not free itself |
| `assault/scenes/enemies/space_station/space_station.gd:169-174` | Armoured core, damage refused in the handler | The coupling above |
| `tests/integration/test_space_station.gd:150-210` | Two real-physics tests built on the premise | Must stay green |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `assault/scenes/projectiles/missiles/warhead/warhead_missile.gd:19-24` | **The shipped precedent**: an unpooled player projectile connects its own `VisibleOnScreenNotifier2D.screen_exited` to `queue_free()` and also frees on hit. Homing missile does the same (`homing_missile.gd:32,47`). |
| `assault/scenes/enemies/sniper_enemy/sniper_enemy.gd:102` | `bullet.expired.connect(bullet.queue_free)` — the shipped pattern for an unpooled `expired` owner. Not usable verbatim here (see Risks) but it is the idiom. |
| `global/components/bullet_pool.gd:80-92` | `_recycle()`; shows what a pooled bullet must be allowed to reach |
| `tests/integration/test_space_station.gd:171-186` | A working "instance a real bullet, let the physics server find the hurtboxes" harness to copy |

## The constraint that shapes the fix

**The fix cannot live in `bullet.gd`'s screen-exit handler.** `ally_fighter.gd:11` pools
`bullet.tscn`. A `queue_free()` there would free a bullet the pool still lists in `_active`;
`_recycle()`'s deferred call would land on a freed object and be dropped, so the bullet never
returns to `_idle`. `BulletPool` has no path that grows `_idle` again (`bullet_pool.gd:96-98`
says so explicitly), so the ally's pool of 8 drains permanently and it stops shooting after eight
shots, with only a `push_warning` to show for it.

So ownership must be taken **on the player spawn path**, per bullet.

## Conventions that constrain this

- Composition over inheritance; a shared behaviour goes in one place, not copied into four files.
- Signal arity is declared exactly (`tests/README.md`); `expired` takes no arguments.
- New behaviour asserts intent; characterization pins today's behaviour bugs included.
- `NEVER` change balance data silently — enemy/weapon stats live in `.tres`.

## Open questions for research

1. Do shipped shmups consume a shot on the first *overlap*, or on the first *damaging* hit? What
   is the convention for armoured/invulnerable boss parts in front of destructible ones?
2. Is "the base weapon pierces everything" ever a deliberate design, or always a bug?
3. What do shipped projects do about projectile despawn — off-screen notifier, arena bounds,
   or lifetime timer — and what are the failure modes of each?
