# `ram_ship` bullet immunity + dead config HP

## Problem

`ram_ship.gd:19` narrows its `HurtBox` mask to missiles-only in `_ready()`. The player's primary
weapon (bullets, `collision_layer = 64`) cannot touch it at all until it has already taken a
missile hit — at which point it opens up to bullets and dies in two. The task that filed this
flagged it as an undecided design call, plus a second, independent defect: `ram_config.tres`'s
`max_health = 999` is never read by `ram_ship.gd`, so the number a developer would look up for
this enemy's "armoured" HP is fiction — the scene's bare `Health` default (100) is what actually
runs.

Player-facing framing: is the ram ship supposed to be a "missile-only obstacle" (dodge/lane-block
until you use your secondary weapon), or is the bullet immunity an oversight that leaves an enemy
type the player can't fight with their main gun?

## Design

**The immunity is intended. No behaviour change to the collision mask.**

Evidence (full detail in `1-context.md`):

1. `ram_ship/ENEMY.md` — already checked in, predates this task — describes the exact mechanic
   as the entity's fantasy: *"Effectively bullet-proof until a missile strips its armour... Blocks
   the piercing laser while armoured."* This isn't undocumented behaviour; it's a documented
   feature that one other doc (`docs/enemy-roster.md`) failed to mention.
2. `bullet.gd`'s piercing-sniper path (`_on_hit_box_area_entered`) independently special-cases the
   `ram_ships` group alongside `asteroids` as something a piercing shot stops on without dealing
   damage — the same "obstacle, not a normal target" treatment, implemented via a completely
   different code path (group membership, not the hurtbox mask). Two independent mechanisms
   agreeing is strong evidence of intent, not two independent bugs.
3. `ram_ship.gd`'s own state machine is explicit in its comments: the first hit "triggers damaged
   state instead of dealing damage," then the ship becomes "vulnerable to bullets too." This reads
   as an authored two-phase enemy (armoured charger → exposed core), not a leftover mask value.

So this plan does **not** touch `hurt_box.collision_mask` in either phase.

**What does change:**

1. **Apply `config.max_health` in `_ready()`**, matching every other config-driven enemy
   (`bomber.gd:19-20`, `gunship.gd:36-37`, `light_assault_ship.gd:19-20`, etc. — full list in
   `1-context.md`):
   ```gdscript
   if config:
       speed = config.movement_speed
       health.max_health = config.max_health
       health.current_health = config.max_health
   ```
   This is behaviourally inert during the armoured phase (health is never decremented there — the
   first hit always short-circuits to `_enter_damaged_state()`, never `health.decrease()`) and
   `_enter_damaged_state()`'s hardcoded reset to 100 HP post-armour is untouched. It just makes the
   number readers already believe (`ENEMY.md` line 12 already claims "999 while armoured") actually
   true, and closes the "config field nobody reads" class of bug that the roster invariant
   (`test_enemy_contact_damage.gd`) exists to catch for `collision_damage`.

2. **Fix `docs/enemy-roster.md`'s ram entry** (~line 127). Replace the bare `**HP:** Medium` line
   with a line naming the armour gimmick, matching the accuracy already present in `ENEMY.md`:
   ```
   **HP:** Immune to bullets while armoured (missile-only hurtbox mask); one missile hit strips
   armour, then 100 HP (two bullets) finishes it.
   ```
   `**Score:** Medium` is untouched (score is a flat `score_value`, no gimmick).

3. **New test** pinning the two-phase hurtbox behaviour and the config application, since nothing
   in the current suite exercises `ram_ship`'s own `_ready()`/`_on_received_damage()` logic (the
   existing three roster sweeps cover contact-hitbox damage/geometry and hurtbox *coverage*
   geometry, not the mask value or health application). See Test plan.

## Build sequence

1. Write `tests/unit/test_ram_ship.gd` (new file) with the failing/characterizing cases below.
   Confirm the config-application case fails against current code (`health.max_health` reads 100,
   not 999) and the mask cases already pass (characterizing existing, intentional behaviour).
2. Add the two-line `config.max_health` application to `ram_ship.gd:16-17`'s `if config:` block.
   Re-run — config case now passes.
3. Edit `docs/enemy-roster.md`'s ram entry HP line.
4. Run the full GUT suite + `bash /agent/verify.sh`.

Each step is independently small and verifiable; step 2 is the only line of production code this
plan changes.

## Test plan

New file `tests/unit/test_ram_ship.gd` (`extends GutTest`), instantiating
`res://assault/scenes/enemies/ram_ship/ram_ship.tscn` directly (add_child into a fresh `Node2D`
per `tests/README.md` conventions, `free()` in `after_each`):

- `test_applies_config_max_health_on_ready` — after `_ready()`, `ram.health.max_health == 999` and
  `ram.health.current_health == 999` (reads `ram_config.tres`'s shipped value through the private
  copy, per `ShipConfig.privatise()` — this is the case that fails before the fix).
- `test_hurtbox_mask_excludes_player_bullet_layer_while_armoured` — before any hit,
  `ram.hurt_box.collision_mask & PLAYER_BULLET_LAYER (64) == 0`. Characterizes the intended
  immunity so a future regression (someone "fixing" the mask without reading `ENEMY.md`) is
  caught here rather than rediscovered as a design debate again.
- `test_first_hit_strips_armour_and_opens_hurtbox_to_bullets` — call
  `ram._on_received_damage(1)` (simulating a missile HurtBox signal) once; assert
  `ram.hurt_box.collision_mask & PLAYER_BULLET_LAYER (64) != 0` afterward, and
  `ram.health.current_health == 100` (the documented post-armour reset).
- Boundary case — `test_second_hit_after_armour_stripped_deals_damage` — call
  `_on_received_damage()` twice; assert the second call decrements health from the reset 100
  (`current_health == 100 - damage`), proving the phase transition is one-shot and normal damage
  resumes.

This does not touch `test_enemy_contact_damage.gd` / `test_contact_hitbox_geometry.gd` /
`test_enemy_hurtbox_geometry.gd` — those assert contact-hitbox damage and hurtbox *coverage*
geometry (both unaffected by this change) and already include `ram_ship` in their roster sweeps.

## Risks

- Applying `config.max_health` could theoretically interact with something that reads
  `health.max_health` before `_ready()` runs (e.g. a UI health bar sampling on `_enter_tree`).
  Grepped: nothing outside `BaseEnemy`/the entity itself reads `ram_ship`'s `health` before
  `_ready()`. The ordering is `_enter_tree()` (privatise config) → `_ready()` (apply config) →
  first frame — the same order every other enemy using this pattern already relies on, so no new
  ordering risk is introduced.
- None of this changes `is_laser_blocking()`, the piercing-sniper group check, or scoring — kept
  explicitly out of scope below.

## Out of scope

- Changing the armoured-phase hurtbox mask (rejected — see Design).
- The hardcoded post-armour HP reset to 100 in `_enter_damaged_state()` (a separate, working
  balance choice, not dead code).
- `is_laser_blocking()` / piercing-sniper `ram_ships` group handling in `bullet.gd` (already
  correct, consistent with the design call made here).
- Any WaveBuilder / roster-builder API changes.
