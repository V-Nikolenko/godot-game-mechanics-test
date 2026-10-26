VERDICT: CHANGES_REQUESTED

# Review of t2 plan: the mine family (`EnemyMine`), round 1

I read `3-plan.md` and `1-context.md`, epic §"For every task", §2.1, §2.2, §2.3 and §2.17. I checked every claim about the code against
the files on `agent/auto-dev` @ `811351f`. The plan follows the epic closely: the three hooks, `_reset_props()`, the fizzle guard,
launch-scoped registration, hostility applied in `launch()`, the deferred `_start_if_placed()`, `EnemyMineScenes` and the levers are
all there. Every acceptance row in the brief has a test row. Most of the code claims hold up. Three items have to change before
implementation; the rest are recommendations.

## Required changes

### R1. The "`mine_life 0` live at 30 s" row cannot pass as written
- The plan puts this row under "Lifetime boundary (hand-ticked `_physics_process` + `ProjectileLifetime` ticked)" (3-plan.md, Test plan).
- `mine.tscn:49-52` authors `ProjectileLifetime.max_time = 10.0`.
- `projectile_lifetime.gd:76-77` emits the host's `expired` at 10 s.
- `enemy_ordnance.gd:113,299-301` connects `expired -> _on_expired -> _mark_done()`.

So a non-placed mine with `mine_life = 0` whose lifetime is ticked is done at 10 s, not live at 30 s. The implementer would have to
quietly pick one of two fixes: stop ticking the lifetime, or zero `max_time`. Each tests something different. The plan should say:
- **(a)** The 30 s row pins only the fizzle guard. It sets `ProjectileLifetime.max_time = 0`, or does not tick the lifetime, and says so.
- **(b)** Add a companion boundary row: a pooled-style mine with `mine_life = 0` and the scene's backstop still ends at `max_time`
  (10 s ± 1 tick, exactly one `expired`).

Row (b) guards the epic's "the `ProjectileLifetime` `max_time` is the backstop". Without it, a Mine Layer mine given life 0 by mistake
lives forever and starves its pool, and no row notices.

### R2. Placed mode does not make the backstop inert in Assault
- The epic (§2.1) and the plan set `ProjectileLifetime.max_time = 0` "(inert)".
- `projectile_lifetime.gd:82-88` still expires the host when it is outside the Assault world rect. `use_world_rect` defaults to true,
  and `mine.tscn` does not turn it off.
- That rect is `ArenaCamera._visible_rect().grow(64)` (`arena_camera.gd:52,88-89,116-119`). It is a fixed rect around the corridor,
  and `tests/helpers/enemy_ai_harness.gd:51-55` installs it in the Assault harness.

So a placed mine (`expired -> queue_free`) that starts more than 64 px outside the corridor expires and frees itself on its first tick.
Two cases hit this:
- a standalone mine authored in an Assault scene;
- the t8 Minefield, which enters from above (§2.10) and puts its outer mines about 200 px from the field centre.

This breaks the epic's promise that a lone mine dropped in a scene arms, registers and triggers. The epic already makes the field free
itself past the rect (§2.10, line 609), so the mine does not need the rule.

Fix:
- `_start_if_placed()` also sets `use_world_rect = false`. That flag is re-read every tick (`projectile_lifetime.gd:82`), so the order
  against the lazy `_arm()` does not matter. Disabling the lifetime's physics process would also work.
- Add a row in the Assault harness: a placed mine positioned outside `EnemyWorld.projectile_world_rect()` is still valid and registered
  after N ticks.
- Add a control: a pooled mine at the same spot does expire, which shows the row can fail.

### R3. The `BulletPool` reparent path and the `_enter_tree()` re-register have no test
The design adds `_enter_tree()` re-registration, which matches the brief's "BulletPool reparent interaction" concern. It relies on these
facts, which I confirmed:
- prewarm calls `add_child` (`bullet_pool.gd:66-75`);
- `acquire()` reparents **before** `reset()` (`bullet_pool.gd:86-90`), so `_enter_tree()` runs with the previous life's stale
  `_launched = true`;
- `_recycle()` reparents back into the pool (`bullet_pool.gd:112`).

The design is correct today only because `_done` is still true at both of those reparents. The test plan checks only "prewarmed →
unchanged; after `acquire` + `launch` → +1". That cannot catch the regressions that matter:
- a phantom hazard at the pool on a mine's **second** life;
- registration between `acquire()` and `launch()`;
- a live mine dropping out of the registry on a reparent. The `_enter_tree()` branch is untested code.

Add, with a real pool:
1. After `acquire()` and before `launch()`, the count is unchanged.
2. Run a full life (detonate or fizzle), wait for the deferred recycle, then `acquire()` again. The count is unchanged before `launch()`
   and exactly +1 after it.
3. A live, launched mine `reparent()`ed to another node is still counted and still found by `Hazards.around()`.

All three are hand-ticked and nearly free.

## Recommendations (not blocking)

### N1. Gate time
§2.17 gives t2 3.0 s.

My count of the planned real-physics rows at 8×:
- placed, plus the pooled control;
- PLAYER-not-set-off and ALL-set-off;
- three boundaries;
- 2 harnesses × 2 warning rows;
- two head-on mover runs of about 1000 px at 200 px/s, which is about 5 game-s each.

At the epic's own 0.25–0.4 s per case, that comes to roughly 3.5–4 s.

"Share one 8× scene where possible" is not a plan. Name the shared scenarios now:
- One scene holds the three ALL boundaries plus the PLAYER-mine control, with mines more than one trigger radius apart. The ALL-set-off
  row stays separate because it blasts.
- Per harness, one scene holds the crossing stub and the stopping stub.
- The head-on run and its `registers_hazard = false` control share one scene in separate lanes, further apart than the mover's reach.
  Each run stops once the fixture is past the mine (x > +200) instead of flying the full corridor.

This is the epic's own rule ("a scenario several rows share is computed once").

### N2. Assert every `HazardInfo` field the epic fixes
The registration row checks `kind`, `radius` and `avoid_weight`. Also assert:
- `source == self`;
- `velocity == Vector2.ZERO`;
- `pull_force == 0`;
- `movement_penalty == 0`;
- `line_of_sight_blocker == false`.

The Fighter and Sniper cover logic keys on `line_of_sight_blocker` (`fighter_brain.gd:756`, `sniper_brain.gd:579,593`), and
`Hazards.penalty_at()` keys on `movement_penalty`. A mine that wrongly carried either flag would change other enemies' behaviour with
nothing to catch it.

### N3. Tighten the `test_enemy_bullet_lifetime.gd` row
"(or `mine_life == 0`, inert backstop is placed-only)" would let a scene author `max_time = 0` and `mine_life = 0`, and a pooled mine
from that scene would never end. Placed inertness is applied at runtime by `_start_if_placed()`, so the row can be strict: every
variant scene authors `max_time > 0` and `max_time >= mine_life`.

### N4. `retire()` should unregister itself
The plan says "unregistered the same tick", but the mechanism reads as "the next `_physics_process` sees `_fizzling`". Have `retire()`
call unregister directly, so the Mine Layer's cap (t11) never sees a retired mine in `Hazards.around()` for one tick. The `retire()`
registration row should then assert the count with no tick in between.

### N5. Extend the no-Timer sweep to the new files
Add `mines/enemy_mine.gd` and `mines/enemy_mine_scenes.gd` to `test_enemy_ordnance.gd::test_the_ordnance_uses_no_timer_node_and_no_create_timer`
(`test_enemy_ordnance.gd:565-574`, which lists files by hand), or to an equivalent row in `test_enemy_mines.gd`. This is the epic's
"no `Timer`, no `create_timer`" rule.

### N6. Distances in the ALL blast row
`Hazards.pulse_damage()` uses centre distance against `blast_radius` 48 (`hazards.gd:97-115`), not the 80 px trigger radius. The ALL
row's fixture and player stub must both sit within 48 px of the mine centre, or the "Health lowered" asserts fail for the wrong reason.

The existing `_player()` stub in `test_enemy_ordnance.gd:139-156` is a bare `Area2D`, not a `HurtBox` named `HurtBox`, so
`hurt_box_of()` cannot see it. The plan already calls for a real `HurtBox` and `Health`; it should not reuse that stub.

### N7. Assault harness rows need the mine inside the world rect
Any non-placed mine in the Assault-harness warning rows must start inside `projectile_world_rect()`, for the same reason as R2.

## Checked and fine
- **Bomb paths stay byte-identical** (`enemy_ordnance.gd:176-195,214-257`). The hooks are pure extractions. `_detonate()` keeps
  latch → effect → `expired`. The only `_player_in_range` callers are inside this file; `enemy_rocket.gd:278` is a separate method and is
  untouched.
- **GDScript dispatch.**
  - `_reset_props()` called from the base `_ready()` resolves to the override, and so does `_mark_done()` from
    `_detonate`/`_defuse`/`_finish`/`_on_expired`.
  - Engine callbacks (`_ready`, `_physics_process`, `_enter_tree`, `_exit_tree`) need explicit `super`, and the plan has it.
  - A `const` typed array plus a literal gives a new untyped `Array`, which fits the `-> Array` return.
- **Deferred placed setup.**
  - `call_deferred` from `_ready()` runs after the parent's `_ready()`.
  - A deferred call on a freed node is skipped silently, so `test_project_load_integrity` stays clean.
  - Pooled mines (`PROCESS_MODE_DISABLED`) still run the deferred call, which returns at once because `placed` is false.
  - The ready-order row tells correct deferred setup apart from `_ready()`-time setup.
- **Hostility filter** (`armor_plate.gd:65-77`): the plate builds its own `HurtBox` on layer 512, so the hurtbox's parent is the plate.
  Rocket hurtboxes are parented to the rocket (`pursuit_rocket.tscn:52-53`). The `get_parent() in enemies` test correctly accepts
  `fixture_enemy`'s direct-child `HurtBox` and rejects the plate, rocket and mine boxes. A lone plate placed directly under an `enemies`
  node also catches an "any ancestor" implementation.
- **Fixture.** `fixture_enemy.tscn`'s `HurtBox` has no shape and the fixture joins no group. Adding them at runtime follows the epic's rule.
- **Real-mover row.** `EnemyMover._avoid()` (`enemy_mover.gd:279-296`) reads `hazard_avoidance` and `hazard_margin`, which can be set
  at runtime.
- **Pure-stage rows** match `test_context_avoidance.gd::_fly()`.
- **Existing rows.**
  - No test reads `mine.tscn`'s authored `warning_time` 0.5: `test_enemy_ordnance.gd:425-441` is relative.
  - `test_hazard_projectiles.gd`'s bit-identity row excludes MINE (`_BOMB_KINDS`, line 29), and its `count() == 1` assertion involves
    no mine.
  - `test_enemy_ordnance.gd:666-679` asserts `count() == 0` only after the mine detonated, which unregisters it.
- **Hazard consumers.** Fighter cover, Ram well use and Sniper cover filter by `kind` or `line_of_sight_blocker`
  (`fighter_brain.gd:756`, `ram_corvette_brain.gd:391`, `sniper_brain.gd:579`). A zero-pull mine leaves `Hazards.bend_heading()` and
  `accel_at()` exactly unchanged. Any other drift is covered by the epic's levers in build step 5.
- **Shapes reused, nothing reinvented.**
  - `EnemyMineScenes.export_of` copies the `EnemyRocketScenes.export_of` shape (`enemy_rocket_scenes.gd:48-56`), and the `node_path`
    parameter only adds to it.
  - The ALL blast reuses `Hazards.pulse_damage()`, which is safe inside a physics callback.
- **Conventions.**
  - `mine.tscn` keeps its path and gets no hand-typed UID.
  - Docs are deferred to t16, as the epic's build sequence assigns them (§3, §2.19).
  - `check-test-leaks.sh`, `gate-time.sh` before and after, the README Gate time row and the DECISIONS "built in t2" notes are all in
    the build sequence.

---

VERDICT: APPROVED

# Review of t2 plan, round 2

I re-read the revised `3-plan.md` and re-checked the code each fix depends on. All three required changes are in, and they are correct.

## Required changes from round 1: resolved
- **R1, the 30 s row and the backstop.** The 30 s row now zeroes `max_time` and says it tests the fizzle guard only. The companion row
  asserts that a non-placed mine with `mine_life 0` still ends at the scene's 10 s backstop ± 1 tick. This matches
  `projectile_lifetime.gd:76-77` and `mine.tscn:51`.
- **R2, placed mines in Assault.** `_start_if_placed()` now also sets `use_world_rect = false`.
  `projectile_lifetime.gd:82` re-reads that flag every tick, so it works however the lazy `_arm()` is ordered.
  - The new Assault-harness row can fail: its control, a launched non-placed mine at the same spot, does expire on its first lifetime
    tick. `_physics_process` arms first and then checks the rect within the same call (`projectile_lifetime.gd:68-88`), and the
    harness's `ArenaCamera` provides the rect (`enemy_ai_harness.gd:51-55`, `arena_camera.gd:88-89`).
- **R3, the pool reparent path.** The plan now has three rows:
  - after `acquire()` and before `launch()`, the hazard count is unchanged;
  - on the mine's second life, the count is unchanged before `launch()` and exactly +1 after it;
  - a live mine moved with `reparent()` is still registered.

  They cover the stale-`_launched` reparent in `acquire()` (`bullet_pool.gd:86-90`), the recycle reparent (`bullet_pool.gd:112`) and the
  `_enter_tree()` re-register branch.

## Recommendations from round 1: taken
- **N1, gate time.** The plan names six shared real-physics scenes, about 16 game-s.
- **N2, hazard fields.** The hazard-info row now asserts `source`, zero `velocity`, no pull, swirl or slow, and not a line-of-sight
  blocker.
- **N3, lifetime row.** It now requires the scene to author `max_time > 0`.
- **N4, `retire()`.** It now unregisters immediately.
- **N5, no-Timer sweep.** The `mines/` sweep now lives in `test_enemy_mines.gd`, which keeps `test_enemy_ordnance.gd` unchanged. That is
  the right call given the acceptance criteria.
- **N6, ALL blast distances.** Both stand-ins sit within the 48 px blast radius, and the stub is added only once the mine is warning.
  That second point is a real improvement: it proves the enemy alone set the mine off.
- **N7, Assault rect.** Assault-harness mines start inside the world rect.

## Notes for the implementer (not blocking)
1. **Scene C: the fixture cannot lose `blast_damage`.** `fixture_enemy.tscn` authors `max_health = 10`, and `Health.decrease()` clamps
   at 0 (`health_component.gd:39`). The fixture therefore cannot lose `blast_damage` (30), and `BaseEnemy` will also run its death path
   (`base_enemy.gd:227-249`). Raise the fixture's `max_health` and `current_health` at runtime before `add_child`, for example to 100.
   Then assert `max - current == blast_damage`, or assert on the `HurtBox.received_damage` value.
2. **Scene B: a rocket can make the boundary rows pass for the wrong reason.**
   - An enemy rocket's `HitBox` is on layer 32 with mask 640 (`dumb_rocket.tscn:40-42`), and the mine's `HurtBox` mask 96 includes 32
     (`mine.tscn:31`). If the rocket overlaps the mine's 11 px hurtbox, it **defuses** the mine. The "not set off" row would then pass
     without testing anything, and the rocket may detonate as well.
   - Fix: place the rocket inside the trigger radius but clear of the hurtbox (more than about 20 px from the centre). Stop its
     physics processing and its lifetime, so it neither flies off nor expires.
   - Have each boundary row assert that the mine is still live (`not _done`), armed and `not is_warning()`, not merely that no blast
     happened.
3. **Out of scope line: task numbers are shifted.** It credits player boost hooks to "t4", the Minefield to "t7", art to "t8" and the
   Mine Layer to "t9+". The epic's §3 has them as t5, t8, t9 and t10+. This is cosmetic, but fix it so the DECISIONS "built in t2"
   notes point at the right tasks.

No other concerns. The design still implements epic §2.1–2.3 and §2.17 as written.
