VERDICT: APPROVED

## Summary

The plan's central claim — that the deflection/damage distinction can be made with a duck-typed
`is_armored()` query in `bullet.gd`, wired to `queue_free()` only inside `WeaponBehavior._launch()`
— checks out against the actual code on every point the task asked me to verify. Findings below,
each against the real file/line I read (not the plan's prose).

## Findings

1. **Solves the stated problem, without breaking the station.** Confirmed by reading
   `assault/scenes/projectiles/bullets/bullet.gd:99-117` (current, unmodified
   `_on_hit_box_area_entered`) and `assault/scenes/enemies/space_station/space_station.gd:155-176`
   (`is_armored()` / `_on_received_damage`). Today a default bullet (`pierces_remaining == 0`)
   falls through to `expired.emit()` on every hit and nothing frees it. Adding the `is_armored()`
   early-return ahead of the pierce branch, plus `bullet.expired.connect(bullet.queue_free)` in
   `_launch()`, makes an ordinary hit terminate the bullet while a deflected hit (armor still up)
   does not — exactly the "damaging vs deflected" split the plan states. `PierceModule`
   (`global/ship_modules/pierce_module.gd:9-11`, "pierce through up to 3 enemies... reduces damage
   by 45%") becomes accurate for the first time, since the baseline no longer pierces without
   limit.

2. **Physics-ordering claim holds.** Verified via `assault/scenes/projectiles/bullets/bullet.tscn`
   (`HitBox` is a *separate* `Area2D`, `collision_layer=64`/`mask=513`, connected
   `area_entered -> _on_hit_box_area_entered` on the bullet) and
   `global/components/hurtbox_component.gd` (`HurtBox._on_area_entered` independently emits
   `received_damage`). These are two independently-fired signals on the same physics-step overlap
   pair, so their relative order is not guaranteed — but `is_armored()` reads
   `live_turret_count()` (`space_station.gd:147-152`), which a hit against the *core's own hurtbox*
   never changes (only `_on_turret_destroyed` mutates the count, and that only fires from a
   turret's own death, not the core's). So the query is stable no matter which of the two signals
   fires first. Reasoning is sound and matches the code.

3. **`_launch()` genuinely never reaches a pooled `AllyFighter` bullet.** Confirmed:
   `assault/scenes/allies/ally_fighter/ally_fighter.gd:34-48` builds a `BulletPool` and an
   `AttackController` — no `WeaponBehavior` or `_launch()` anywhere in that file.
   `global/components/bullet_pool.gd:50-57` (`_prewarm`) is the only place a pooled bullet's
   `expired` gets a listener, and it's always `_recycle`, never `queue_free`. The new
   `expired -> queue_free` connection is added exclusively inside `WeaponBehavior._launch()`
   (`weapon_behavior.gd:23-25`), which only unpooled player spawn sites call. Pooled ally bullets
   are unaffected, confirmed by code path, not just by the plan's assertion.

4. **`test_space_station.gd`'s two real-bullet tests are correctly predicted to stay green.**
   `_fire_bullet_at()` (`tests/integration/test_space_station.gd:184-188`) does
   `_container.add_child(bullet)` directly — never `WeaponBehavior._launch()` — so the new wiring
   never attaches to these test bullets. Both
   `test_a_real_bullet_in_a_turret_lane_damages_the_turret_through_the_armored_core` (:198-227) and
   `test_a_real_bullet_damages_the_core_once_the_armor_is_broken` (:237-253) assert only
   `is_instance_valid(bullet)`, never `is_queued_for_deletion() == false`. Confirmed accurate.

5. **`RamShip` is genuinely unaffected.** `assault/scenes/enemies/ram_ship/ram_ship.gd:21` sets
   `hurt_box.collision_mask = 33` (32 rockets + 1) before `_enter_damaged_state()`, and the bullet's
   `HitBox` ships on `collision_layer = 64` (`bullet.tscn:34`). 64 has no bit in common with 33, so
   a bullet's `HitBox` cannot overlap a pre-damaged ram ship's `HurtBox` — matches
   `station_turret.gd:33`'s own comment on bit assignments ("bullets (64) + rockets (32) + layer 1
   + asteroids (1024)" = mask 97, vs ram ship's pre-damage 33 which omits 64). Confirmed by
   layer/mask arithmetic, not just by the plan's prose.

6. **The duck-typed pattern is real precedent, not invented.** `beam_behavior.gd:67-68` does
   exactly `if coll.has_method("is_laser_blocking"): is_block = coll.is_laser_blocking()` against a
   foreign collider with no shared base/interface — the same shape the plan proposes for
   `is_armored()`. `ram_ship.gd:53-54` already implements the *sibling* query
   (`is_laser_blocking()`) using the same idiom, so this is an established, repeated pattern in the
   codebase, not a one-off invention.

7. **Double `queue_free()` is safe, and is not just a hypothetical.** `bullet.gd:78-82`
   (`_physics_process`'s range-cap branch) already does `expired.emit(); queue_free()`
   unconditionally whenever `range_px > 0.0`. Checking the shipped weapon-mode resources
   (`assault/scenes/player/weapons/modes/spread.tres:12` = 360.0,
   `assault/scenes/player/weapons/modes/gatling.tres:12` = 450.0), this is a *routine* path for two
   of the five player weapon modes, not an edge case. Godot's `queue_free()` is documented as safe
   to call more than once (it queues a deferred free; a second call on an already-queued/freed
   object is a no-op, no error). No behavioral or diagnostic-noise risk here.

8. **Test plan is adequate and each new test can fail on a broken implementation.**
   `test_a_launched_bullet_stops_on_its_first_damaging_hit` catches a missing/broken
   `expired -> queue_free` wiring or a missing pierce-baseline stop.
   `test_a_deflected_hit_does_not_consume_the_bullet` catches a missing or mis-ordered
   `is_armored()` check. The rewritten pierce test catches a decay or pierce-count regression *and*
   now also catches the bullet failing to stop once pierce is exhausted, closing the gap the old
   test explicitly left open ("the bullet is STILL ALIVE... which is why PierceModule reads as a
   limiter" — `test_player_bullet_lifetime.gd:322-324` — under the new contract this must flip to
   queued-for-deletion). One real, if minor, gap: no test — old or newly proposed — exercises a
   *pooled* `AllyFighter` bullet through the **hit** path (only the **screen-exit** path is covered
   by `test_a_pooled_bullet_survives_leaving_the_screen`, which is scoped to a different lifecycle
   event). This is not a new hole this plan opens (`_recycle()`'s hit-triggered path was already
   untested before this change), and the new `is_armored()` check is provably a no-op for any
   target lacking that method — including the player, the only thing an ally bullet ever hits — so
   the risk is low. Still, an optional one-line addition to
   `test_a_pooled_bullet_survives_leaving_the_screen` (fire one pooled bullet at a plain stand-in
   `HurtBox`, assert it recycles rather than frees) would close this for good and costs little. Not
   a blocking gap.

9. **CLAUDE.md conventions respected.** No `HurtBox`/`Health` signal-arity changes (confirmed —
   `received_damage(damage: int)` untouched in `global/components/hurtbox_component.gd`). No new
   inheritance or shared interface — the duck-typed check is composition-friendly and mirrors
   existing precedent (finding 6). "The pool is smart, bullets are dumb" is respected: the new
   lifecycle decision lives in `_launch()` (the launcher), not baked into `bullet.gd` calling
   `queue_free()` on itself unconditionally — `bullet.gd` only gains a read-only armor query, still
   just emitting `expired`. The plan explicitly schedules updates to every doc location that states
   the old rule as fact (`CLAUDE.md`, `docs/architecture/PROJECT.md:114-115,161`,
   `tests/README.md:360`, `space_station/ENEMY.md:580-584`), and I confirmed each of those line
   locations exists and says what the plan says it says.

10. **No unnecessary complexity found; a simpler alternative (a cached `HurtBox.blocks_damage`
    flag) was considered and correctly rejected** — `space_station.gd:144-152`'s own comment says
    `live_turret_count()` is deliberately live/uncached "so it cannot desync," and a boolean the
    station would need to remember to flip on every turret death reintroduces exactly that risk.
    The duck-typed query has no state to go stale. This is the right call.

## Minor nits (non-blocking)

- `1-context.md`'s table lists the pool script as `global/bullet_pool.gd`; the real path is
  `global/components/bullet_pool.gd`. The line-number claims (`bullet_pool.gd:47`) are otherwise
  accurate against the real file — just a stale path in the context doc, worth a fix in passing
  but does not affect the implementation.
- The backlog entry for this task (`BACKLOG.json`, id
  `decide-whether-the-player-s-default-gun-should-stop-on-its-f`) still shows
  `"complexity": "medium"`, `"model": "sonnet"`, even though this task is being run through the
  full plan+independent-review pipeline CLAUDE.md reserves for escalated/large work. Per
  CLAUDE.md's own instruction ("record the escalation with `backlog-cli.js set-meta ... --complexity
  large --model opus`"), whoever escalated this should have updated the metadata. Not a defect in
  the plan's technical content, but worth reconciling so the board reflects reality.

## Conclusion

Every load-bearing claim in the plan — the physics-ordering safety of `is_armored()`, the
`_launch()`-only wiring reaching no pooled bullet, the two station regression tests surviving
unmodified, the ram-ship exclusion by layer mask, the duck-typed precedent, and idempotent
`queue_free()` — is verified against the actual code, not just asserted. The design is minimal,
respects every constraint in `CLAUDE.md`, and the test plan is capable of catching a broken
implementation on each of its new assertions. Approved as written.
