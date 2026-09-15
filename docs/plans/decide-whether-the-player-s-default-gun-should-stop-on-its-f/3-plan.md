# Default gun stops on its first damaging hit

## Problem

Today, firing the player's unmodified gun at a line of enemies drops every one of them with a
single bullet, at full damage, because nothing ever stops the bullet on a hit — it only dies at
the range cap or the screen edge. `PierceModule` ("Penetrating Rounds") is sold as an upgrade that
lets shots pierce through up to 3 enemies, but since the baseline already pierces through
*everything*, equipping it only shrinks the damage on hits 2-4 (50→28→15→8) and the bullet still
flies on afterward. The module is currently a strict downgrade — the opposite of what its own
description promises the player.

## Design

**Decision: yes.** The default gun stops on its first damaging hit. `PierceModule` becomes the
thing that lets a shot punch through up to 3 additional enemies (with decaying damage) before it
stops — matching its shipped description for the first time.

**The coupling.** The space-station mini-boss's armoured core deliberately spans the full 240×240
hull so a shot aimed at a turret has to physically cross it. Under the old "never stops" rule that
crossing was free. Under the new rule it would not be — a shot that stops on its first hit would
stop *at the core*, and the turrets (and the boss) become unkillable, exactly as the backlog item
warns.

**The fix for the coupling is not a change to the station.** It is a distinction the bullet
already has almost all the pieces for: a hit that is **deflected** (the core's `_on_received_damage`
override refuses it via `is_armored()` and emits `armor_deflected` instead of touching `Health`)
is not the same event as a hit that **deals damage**. The rule becomes:

> A default (non-piercing) bullet stops on the first hit that actually deals damage. A deflected
> hit does not count — the bullet keeps flying, at full damage, exactly as today.

Concretely:

1. **`bullet.gd`** — `_on_hit_box_area_entered(area)` gains one check, run before the pierce
   branch: if `area.get_parent()` has a method `is_armored` and it returns `true`, return
   immediately (no `expired`, no pierce charge spent, bullet keeps flying). This is the same
   duck-typed-query idiom `beam_behavior.gd:67-68` already uses for `is_laser_blocking()` — no new
   shared interface, no `HurtBox` flag to keep in sync, no change to `received_damage`'s contract.
   Everything else in the function is unchanged: pierce-active hits still `call_deferred` the
   damage decay and keep flying; the final branch still just `expired.emit()`.

2. **`weapon_behavior.gd`** — `_launch()` additionally connects
   `bullet.expired.connect(bullet.queue_free)`. This is the only new lifecycle wiring, and it only
   ever touches unpooled, player-fired bullets — `_launch()` is never called by `AllyFighter`'s
   pooled path (`bullet_pool.gd:47`), which already recycles on *any* `expired` emission today and
   is completely unaffected. `queue_free()` firing a second time from the existing range-cap branch
   (`bullet.gd:78-82`, which already calls `expired.emit(); queue_free()` directly) is a no-op —
   Godot tolerates a repeat `queue_free()` on the same node.

That's the entire code change. No change to `HurtBox`, `Health`, `SpaceStation`,
`StationTurret`, `PierceModule`, or any `.tres`. The station needs nothing new because the
existing `is_armored()` query already tells the bullet exactly what it needs to know, and the
station's own tests (below) prove the turret is still reachable.

### Why not distinguish "deflected" via `armor_deflected` (the signal) instead of `is_armored()` (the query)?

`armor_deflected` is emitted *by* the station's own damage-resolution path
(`space_station.gd:171-176`), synchronously, inside the same `received_damage.emit()` call the
`HurtBox`'s own `area_entered` handler makes. The bullet's own `area_entered` handler is a
*separate* Area2D's signal on the *same physics-step overlap pair*, and nothing in Godot's docs
guarantees its ordering relative to the target's handler. Querying `is_armored()` directly sidesteps
the ordering question entirely: armour state depends only on `live_turret_count()`, which this
particular hit (against the core) never changes, so the query is safe to make before, during, or
after the target's own signal has fired.

### Why not generalize to a `HurtBox.blocks_damage` property instead of a duck-typed method?

`is_armored()` is deliberately **live** — computed from `$Turrets` on every call, never cached
(`space_station.gd`'s own comment: "no cached array, no counter, so it cannot desync"). A
`HurtBox`-level boolean the station would have to remember to update on every turret death
reintroduces exactly the desync risk that design already rejected. Querying the method directly has
no state to go stale.

### Ram ship — checked, not affected

`RamShip` also has a first-hit-doesn't-damage transition (`_enter_damaged_state()`), but its
`HurtBox.collision_mask` is `33` (missiles + layer 1) until that transition runs — bullets are
excluded from the mask entirely, so a player bullet's `HitBox` never overlaps a pre-damaged ram
ship's `HurtBox` in the first place. Nothing to change there.

## Build sequence

1. **Red test first.** In `tests/integration/test_player_bullet_lifetime.gd`, rewrite
   `test_pierce_module_today_only_reduces_damage` to route the bullet through a real
   `WeaponBehavior` (`StraightBehavior.new().fire(...)`, as tests 2/3 already do) instead of a bare
   `BULLET_SCENE.instantiate()`, and change the final assertion from "still alive" to "queued for
   deletion after the 4th (pierce-exhausted) hit." Confirm it fails against the current code
   (bullet never frees).
2. **`bullet.gd`** — add the `is_armored()`-duck-typed check in `_on_hit_box_area_entered`, ahead
   of the pierce branch. Rewrite the file's header doc block (rule 1) to state the new contract:
   default bullets stop on their first damaging hit; a deflected hit is exempt; `PierceModule`
   raises the hit count before stopping.
3. **`weapon_behavior.gd`** — add the `bullet.expired.connect(bullet.queue_free)` line in
   `_launch()`; rewrite its doc comment (it currently states the opposite rule almost verbatim).
4. **Rewrite `test_player_bullet_lifetime.gd`'s test 1**
   (`test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps`) — the old assertion is now simply
   wrong for a real player-fired bullet. Split it into two tests, both routed through
   `WeaponBehavior._launch()` so the new wiring is actually exercised:
   - `test_a_launched_bullet_stops_on_its_first_damaging_hit` — a plain stand-in `HurtBox` target
     (no `is_armored`), assert the bullet is queued for deletion (or gone after a frame) and the
     target's `received_damage` still fired with the full, undecayed damage.
   - `test_a_deflected_hit_does_not_consume_the_bullet` — a stand-in target exposing
     `is_armored() -> true` (a tiny `Node2D` subclass in the test file, not a real `SpaceStation`,
     to keep this a unit-level guard independent from `test_space_station.gd`'s real-physics
     coverage), assert the bullet survives and is NOT queued for deletion.
   Update the file's top-of-file doc block (the "two rules" framing) to match: rule 1 is no longer
   "never consumed" but "consumed only by a damaging hit, never a deflected one."
5. **Run the full suite**, confirm `test_space_station.gd`'s two real-bullet tests still pass
   unmodified (they instantiate bullets directly, bypassing `_launch()`, so they're unaffected by
   the new wiring — this is the coupling's regression guard and must not need editing).
6. **Docs** — update every place that states the old "never consumed" rule as current fact:
   - `CLAUDE.md` — the "Every projectile has exactly one owner" bullet already references this;
     update its wording and the gate-test description for
     `tests/integration/test_player_bullet_lifetime.gd`.
   - `docs/architecture/PROJECT.md` (~lines 114-115, 161).
   - `tests/README.md` (~line 360, the `LevelDirector`-adjacent bullet-lifetime paragraph).
   - `assault/scenes/enemies/space_station/ENEMY.md` — the "Core hurtbox: why it spans the whole
     hull" section's "Load-bearing dependency" paragraph currently ends "...is still open, as
     `code-health-backlog` → `decide-whether-...`". Replace with the resolution: the default gun
     now stops on its first damaging hit; the core's `is_armored()` query is the exemption that
     keeps the turret reachable; cite this plan directory.
   - `global/ship_modules/pierce_module.gd` / `SHIP_MODULES.md` — description is already accurate
     to the new behaviour; only check for any stray "today this is a downgrade"-style commentary
     (there is none currently, but re-check after the code change lands, in case anything was
     added to `pierce_module.gd`'s own comment block in the meantime).
7. **`bash /agent/verify.sh`.**

## Test plan

- `test_pierce_module_today_only_reduces_damage` (rewritten, likely renamed to something like
  `test_pierce_module_extends_the_hit_count_before_stopping`): fires through `StraightBehavior`,
  drives 4 synthetic hits via direct calls to `_on_hit_box_area_entered` (as today) against a
  non-armored stand-in target, asserts the damage sequence `[50, 28, 15, 8]` is unchanged, and
  asserts the bullet is queued for deletion / freed after the 4th hit (pierce exhausted).
- `test_a_launched_bullet_stops_on_its_first_damaging_hit` (new): a real `_launch()`-spawned
  bullet against a plain stand-in `HurtBox`, no pierce — asserts one hit stops it and the hit dealt
  full, undecayed damage.
- `test_a_deflected_hit_does_not_consume_the_bullet` (new, boundary case): a real
  `_launch()`-spawned bullet against a stand-in target whose `is_armored()` returns `true` — asserts
  the bullet survives, is not queued for deletion, and no pierce charge was spent
  (`pierces_remaining` unchanged from whatever it started at).
- `test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps` — retired (its premise is now false);
  replaced by the two tests above.
- Unmodified regression guards to re-run and confirm still green:
  `tests/integration/test_space_station.gd::test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core`,
  `::test_a_real_bullet_damages_the_core_once_the_armor_is_broken`,
  `test_a_pooled_bullet_survives_leaving_the_screen`,
  `test_every_weapon_behavior_hands_off_its_projectile_s_lifetime`,
  `test_an_unlimited_pierce_bullet_is_stopped_by_an_asteroid_for_zero_damage`.

## Risks

- **Balance swing.** Every non-piercing enemy encounter in Assault mode gets meaningfully harder
  the moment a shot only kills one enemy instead of piercing the whole formation. This is a
  deliberate, player-facing difficulty change with no numeric tuning pass behind it (no wave HP
  totals were touched). Flagged as a known gap rather than silently absorbed — nobody has played
  this build. If wave balance turns out too hard after this lands, that is new backlog work, not a
  reason to leave the module broken.
- **Any future entity that deflects a bullet must implement `is_armored()` (or the check needs
  generalizing) to get the exemption.** Today only `SpaceStation` needs it. Documented in
  `bullet.gd`'s rewritten header so the next boss author finds it before shipping an unkillable one.
- **`queue_free()` called twice** at the range cap (once via the new `expired -> queue_free`
  connection, once via the existing explicit call). Confirmed safe — Godot's `queue_free()` is
  idempotent — but worth a one-line regression assertion if the reviewer wants extra certainty.

## Out of scope

- Rebalancing wave HP/enemy counts for the new single-target baseline.
- Generalizing the armor-deflection query beyond `SpaceStation` (no second consumer exists yet).
- Any change to `RamShip`, `HurtBox`, `Health`, or `.tres` balance data.
- The `unlimited_pierce` sniper-bullet path (`bullet.gd:100-111`) — already single-purpose and
  correct as shipped.
