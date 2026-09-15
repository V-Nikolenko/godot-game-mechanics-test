# Context

## The task, and the design call it defers

`ram_ship.gd` narrows `hurt_box.collision_mask` to `33` (missile layer 32 + layer bit 1) in
`_ready()`, after `BaseEnemy._ready()` set the normal `97 | 1024`. The player's bullet is
`collision_layer = 64` (`bullet.tscn:44`), so no bullet can hit the ram ship until it has already
taken a missile hit. The task filed this as a design call rather than fixing it outright, and asks
this cycle to make the call and act on it, plus fix the always-broken `ram_config.tres.max_health`
dead code either way.

## Finding: the immunity is already documented as intentional, twice over

1. **`ram_ship/ENEMY.md`** (already checked in, predates this task) is explicit:
   > "Effectively bullet-proof until a missile strips its armour, after which it's finishable."
   > "Shooting it with bullets does nothing until you hit it with a missile — then its armour
   > shatters and two bullets finish it. Blocks the piercing laser while armoured."
2. **`bullet.gd:100-107`**, in the piercing-sniper path, treats the `ram_ships` group exactly like
   `asteroids` — a wall the piercing shot stops on without dealing damage:
   ```gdscript
   ## Asteroids and ram-ships block the sniper bullet without taking damage.
   if parent.is_in_group("asteroids") or parent.is_in_group("ram_ships"):
   ```
   This is deliberate obstacle-course design applied consistently across two different weapon
   paths (regular bullets via the hurtbox mask, piercing sniper shots via an explicit group
   check), not an oversight in one place.
3. `ram_ship.gd`'s own code has a two-phase state machine with comments describing exactly this:
   `_on_received_damage()` — "first missile hit triggers damaged state instead of dealing damage" —
   and `_enter_damaged_state()` — "Now vulnerable to bullets too" (`collision_mask = 97`).

**Conclusion: the bullet immunity while armoured is intended design, not a bug.** The only actual
defect is that `docs/enemy-roster.md:127`'s roster entry says "**HP:** Medium" with no mention of
the armour gimmick, which contradicts the correct, detailed description already in the entity's
own `ENEMY.md`. That is a doc-sync gap, not a code bug.

## Finding: the dead `max_health` is real, and every sibling enemy applies it the same way

`ram_config.tres` sets `max_health = 999`. `ram_ship.gd` reads `config.movement_speed` and
`config.collision_damage` in `_ready()` but never reads `config.max_health` — so the scene's bare
`Health` node defaults (`max_health = 100`, `current_health = 100`,
`global/components/health_component.gd:13-14`) are what actually runs while armoured, not 999.
Because `_on_received_damage()` never decrements health during the armoured phase (the first hit
always short-circuits into `_enter_damaged_state()` instead of calling `health.decrease()`), this
number has **zero gameplay effect** either way — but it is read by a human via `ENEMY.md` line 12,
which already (incorrectly) claims "HP | 999 while armoured (config)".

Every other enemy with a `max_health` config field applies it the same two lines in `_ready()`:

| File | Lines |
|---|---|
| `bomber.gd` | 19-20 |
| `bonus_drone.gd` | 18-19 |
| `gunship.gd` | 36-37 |
| `drone_interceptor.gd` | 44-45 |
| `interceptor.gd` | 26-27 |
| `kamikaze_drone.gd` | 22-23 |
| `light_assault_ship.gd` | 19-20 |
| `space_station.gd` | 109-110 |

```gdscript
health.max_health = config.max_health
health.current_health = config.max_health
```

`ram_ship.gd` is the one outlier. Adding the same two lines inside its existing
`if config:` block (`ram_ship.gd:16-17`) matches the project convention, makes `ENEMY.md`'s
existing "999 while armoured" claim true instead of fictional, and is a no-op on the armoured-phase
behaviour (health is never read or decremented while `collision_mask = 33` keeps bullets out, and
the first missile hit still routes to `_enter_damaged_state()`, not `health.decrease()`).
`_enter_damaged_state()` already hardcodes the post-armour reset to `health.max_health = 100` /
`health.current_health = 100` (`ram_ship.gd:46-47`) — that reset is a deliberate balance choice
(two standard 50-damage bullets kill it), separate from the armoured-phase max_health, and is out
of scope here.

## Files involved

| Path | Role |
|---|---|
| `assault/scenes/enemies/ram_ship/ram_ship.gd` | Add `config.max_health` application in `_ready()`. |
| `docs/enemy-roster.md` | Fix the "**HP:** Medium" line (~line 127) to describe the armour gimmick instead. |
| `tests/integration/test_config_instance_isolation.gd` | Already sweeps every `*_config.tres` including `ram_config.tres` — confirms this change does not touch resource-sharing/privatisation. No change needed here, just confirmed compatible. |
| new: `tests/unit/test_ram_ship.gd` or an addition to an existing enemy-behaviour test | Needs a test that pins (a) bullets cannot hit an armoured ram ship, (b) a missile hit opens it to bullets, (c) `health.max_health`/`current_health` read `config.max_health` before the first hit. |

## Existing code to reuse

- `HurtBox`/`HitBox` components (`global/components/`) — no change needed, just exercised by the
  new test.
- The enemy scene instantiation + config-injection pattern already used by
  `tests/integration/test_enemy_contact_damage.gd` (roster-array-of-dicts + `PackedScene.instantiate()`
  + `add_child()` + `config` override) is the right template for a ram_ship-specific test rather
  than inventing a new harness.
- `tests/README.md`'s notes on `user://` sandboxing and signal-arity don't apply here (no
  autoload, no save file); the `LevelDirector` coroutine-leak trap doesn't apply either (no
  `SceneTreeTimer`/`await` involved in `ram_ship.gd`).

## Conventions that constrain this

- Config-driven enemies: `.tres` values win over scene node defaults, applied in `_ready()` after
  `super._ready()` — `ram_ship.gd` already follows this shape for `movement_speed` and
  `collision_damage`; this just extends the same `if config:` block.
  `ShipConfig.privatise()` isolation is already handled by `BaseEnemy._init()`/`_enter_tree()` and
  is untouched by this change.
- Every module doc update after a structural change → `updating-project-docs` skill. This is a
  behaviour-preserving bugfix plus a doc correction, not a new entity/component/mechanic, so the
  bar for "structural change" is arguably not crossed — but `docs/enemy-roster.md` is touched
  regardless since the task explicitly requires it.
