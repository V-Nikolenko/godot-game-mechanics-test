# t2 — Mines are one family that enemies steer around (`EnemyMine`)

Builds epic plan `docs/plans/cmug23omu000lm52wu7rak0q5/3-plan.md` §2.1, §2.2, §2.3 (approved). This file does not
redesign those sections; it fixes the concrete code shape and the test list. Where it says "§2.x", the epic plan wins.

## Problem
Today a mine is one `kind` of `EnemyOrdnance`, only the Bomber drops it, enemies fly straight through it (it is not a
hazard), it always fizzles after 8 s, and nothing can place one in a level. Phase 7 needs a mine family: the Bomber's
mine becomes the PROXIMITY variant, every mine is a hazard enemies steer round, a mine can be placed in a scene as a
standalone structure that never fizzles, and a placed mine can be set off by — and hurt — enemies as well as the player.

## Design

### `EnemyOrdnance` (bomb paths byte-identical)
- `_reset_props() -> Array` returns `_RESET_PROPS`; `_ready()` and `reset()` iterate `_reset_props()`.
- `_move()`'s `Kind.MINE` branch body moves to `_move_mine(delta)` (same code); the match calls it.
- `_player_in_range()` is renamed `_trigger_seen()` (same body); `_update_trigger()` calls it.
- `_detonate()`: `_mark_done()`, then `_on_detonated()`, then `expired.emit()`. Base `_on_detonated()` = today's
  `ContactBlast.spawn(...)` + `if GRAVITY_BOMB: _leave_gravity_field()`.
- Fizzle guard: `kind == Kind.MINE and mine_life > 0.0 and _clock >= mine_life` (0 = never fizzles; Bomber sets 8.0).
- `_draw()`: the `body_color` circle is drawn only when there is no `Sprite` (`Sprite2D`) child with a texture. No
  scene has one yet, so every draw is unchanged.

### `EnemyMine extends EnemyOrdnance` (`mines/enemy_mine.gd`)
- `enum Variant { PROXIMITY, DRIFTING, HOMING, CHAIN, PULSE, EMP }`, `enum Hostility { PLAYER, ALL }`.
- Exports: `variant`, `hostility` (PLAYER), `hazard_pad` 60, `registers_hazard` true, `placed` false, `placed_life` 0.
- `_reset_props()` = base + `hostility`, `hazard_pad`, `registers_hazard`, `placed_life`.
- One `HazardInfo` (`_info`), filled on launch: `kind &"mine"`, `radius = trigger_radius + hazard_pad`,
  `avoid_weight 1.0`, `velocity` ZERO (moving variants set it from t3), `source self`; `hazard_info()` refreshes
  `position`.
- Registration state: `_launched` (set by `launch()`, cleared by `reset()`). `_should_register()` =
  `_launched and registers_hazard and not _done and not _fizzling`.
  - `launch()`: `super.launch(...)`, set `ProximityArea.collision_mask` from hostility (128 / 128|512), `_launched = true`,
    fill `_info`, register if `_should_register()`.
  - `_physics_process`: `super`, then if registered and no longer `_should_register()` (fizzle started, done) ->
    unregister; else refresh `_info.position`.
  - `_mark_done()` override: `super`, then unregister. `reset()` override: `super`, `_launched = false`, unregister.
  - `_exit_tree()`: unregister. `_enter_tree()`: re-register if `_should_register()` (a reparent of a live mine keeps it
    registered; pool prewarm/acquire/recycle reparents happen while it is unlaunched or done, so they never register).
- `retire()`: if not done and not fizzling, start the fizzle (`_fizzling = true`, `_fizzle_clock = 0`): fade, no blast,
  one `expired` via the base `_finish()`; unregistered immediately (inside `retire()`).
- `_trigger_seen()`: any overlapping area on layer 128; for ALL also a layer-512 area whose `get_parent()` is in group
  `enemies` (hull hurtboxes; not mines, rocket boxes, plates).
- `_on_detonated()`: PLAYER -> `ContactBlast.spawn(get_parent(), ...)` (unchanged); ALL ->
  `Hazards.pulse_damage(get_tree(), global_position, blast_radius, blast_damage)`.
- Placed mode: `_ready()` = `super`, then `_start_if_placed.call_deferred()`. `_start_if_placed()` returns unless
  `placed` and in tree and not yet started; otherwise connects `expired -> queue_free`, sets
  `ProjectileLifetime.max_time = 0` **and `use_world_rect = false`** (review r1 #2: in Assault the rect is the corridor
  + 64 px, so a placed mine authored outside it would otherwise expire and free itself on its first tick), sets `mine_life = placed_life` (always), and calls
  `launch(Vector2.ZERO, 0.0, global_position)`.

### `EnemyMineScenes` (`mines/enemy_mine_scenes.gd`, RefCounted)
- `PROXIMITY` = `preload("res://assault/scenes/projectiles/enemy_ordnance/mine.tscn")` (the cached same resource as
  `EnemyOrdnanceScenes.MINE`).
- `scene_for(variant)` -> the scene, or null for a variant whose scene is not built yet (t3–t6 add them; no
  `push_error`, so callers can sweep "every built variant").
- `pool_size_for(variant, cfg)`: PROXIMITY `max_live_mines + 2`; other variants `ceil(max_live_mines * w / Σw) + 2`
  with weight > 0, else 0. Weights `w_<variant lower>` read duck-typed (`property in cfg`, missing = 0); Σw over all six.
- `export_of(variant, property, fallback, node_path := ^".")` through `PackedScene.get_state()`; the optional
  `node_path` reads a child (the `ProjectileLifetime`'s `max_time`) — an additive parameter over §2.1's signature.

### `mine.tscn`
Script -> `mines/enemy_mine.gd` (no UID on the ext_resource), `variant = 0` (PROXIMITY, default), `warning_time` 0.25.
Everything else unchanged.

Alternatives rejected: in §2.1 (more `Kind` values; a component per variant).

## Build sequence
1. Measure `scripts/gate-time.sh` (before).
2. Write `tests/integration/test_enemy_mines.gd` and the lifetime rows; watch them fail (class missing).
3. `EnemyOrdnance` hooks + guard + draw; run `test_enemy_ordnance.gd`, `test_bomber.gd` (unchanged, green).
4. `EnemyMine`, `EnemyMineScenes`, `mine.tscn` switch; run the new file.
5. Full gate, levers only if a pre-existing row goes red because of registration (confirmed with
   `registers_hazard = false`).
6. `check-test-leaks.sh`, `gate-time.sh` (after); README Gate time row; DECISIONS "built in t2".

## Test plan (`tests/integration/test_enemy_mines.gd`; 8x clock for every real-physics row)
Scene facts
- `scene_for(PROXIMITY) == EnemyOrdnanceScenes.MINE`; instance `is EnemyMine`; `export_of(PROXIMITY, &"warning_time")`
  == 0.25; `pool_size_for` rows (PROXIMITY = cap+2; weighted ceil; weight 0 -> 0).
Registration (hand-ticked where possible)
- prewarmed pooled mine (real `BulletPool`) -> `Hazards.count()` unchanged; after `acquire` + `launch` +1, info
  `kind == &"mine"`, `radius == trigger_radius + hazard_pad`, `avoid_weight 1.0`.
- unregistered after each of detonate (player stub in radius), defuse (`HurtBox.received_damage`), fizzle
  (`mine_life` short), `retire()`; freed mine -> unregistered (`_exit_tree`); `registers_hazard = false` never counted.
Pool reparent path (review r1 #3; real `BulletPool`, hand-ticked)
- after `acquire()`, before `launch()`: count unchanged (the reparent's `_enter_tree()` must not register).
- second life: launch, retire, recycle, `acquire()` again -> count unchanged before `launch()`, exactly +1 after.
- a live mine moved with `reparent()` is still registered (the `_enter_tree()` re-register).
Lifetime boundary (hand-ticked `_physics_process` + `ProjectileLifetime` ticked)
- `mine_life 0` with the backstop zeroed (`max_time = 0`; this row tests the fizzle guard only) -> live at 30 s.
- companion: a non-placed mine with `mine_life 0` and the scene's backstop still ends at the backstop `max_time`
  (10 s) ± 1 tick — a dropper that sets life 0 by mistake cannot starve its pool.
- `mine_life 8` fizzles at 8.0 s ± 1 tick.
- bare `mine.tscn` `placed = true` live and registered at 60 s; `placed_life 5.0` -> fizzle starts at 5.0 s ± 1 tick,
  `expired` once, then freed (`is_instance_valid` false after a frame).
Placed / ready order (real physics)
- Assault harness, hand-ticked: a placed mine authored outside the world rect is still live after 1 s; a launched
  non-placed mine at the same spot expires on its first lifetime tick (control).
- placed PROXIMITY mine: armed after `arm_delay`, registered, set off by player stub, one blast, freed. Control: a
  pooled mine after the same blast is still valid (recycled, not freed).
- parent whose `_ready()` sets child `placed = true`, `hostility = ALL` -> after one frame: `expired` connected to
  `queue_free`, registered, `ProximityArea.collision_mask == 128 | 512`.
Hostility (fixture_enemy + 14 px shape + group `enemies`, added at runtime before `add_child`)
- PLAYER mine not set off by the fixture inside the radius; ALL mine set off, fixture Health and player-stub damage
  lowered by `blast_damage` (both within `blast_radius` 48 of the centre — `pulse_damage` is centre distance; the stub
  is added only once the mine is warning, so the enemy alone set it off).
- Boundary: ALL mine not set off by another mine, a dumb rocket's hurtbox, a lone `ArmorPlate` (under a node in
  `enemies`, inside the radius, hull outside).
- `retire()`: no blast (no `ContactBlast`), exactly one `expired`.
Warning rule (§2.2)
- for every built variant scene: `(trigger + effect) / warning >= 440 + own_speed` from `export_of`.
- synthetic: warning 0.4, blast 48 -> fails; HOMING `home_speed` 75 -> fails (formula boundary, exports the
  HOMING scene will author).
- dual-mode (harness `open_space()` / `assault()`), real physics: a stub crossing at 220 px/s through the trigger takes
  the blast; one stopping at `trigger_radius + 30` does not.
Avoidance (§2.3)
- pure stage via `Hazards.around()` over a launched real mine: av 0.6 / margin 24 / 200 px/s, offsets 0/30/60 ->
  closest ≥ 85; av 0.8 -> ≥ 145; `registers_hazard = false` -> closest == offset ± 1.
- real mover, head-on, 8x: fixture_enemy av 0.8 margin 24 at 200 px/s -> closest ≥ 120 and ≥ control + 100.
`test_enemy_bullet_lifetime.gd`: per built variant, `max_distance == 0`, the scene authors a backstop `max_time > 0`
(placed mode, not the scene, makes it inert) and `max_time >= mine_life`; mine speeds absent from the round speed list.
Also in `test_enemy_mines.gd`: no `Timer` / `create_timer` in any `mines/` file (the `test_enemy_ordnance.gd` sweep's
shape; that file stays unchanged). The hazard-info row asserts `kind`, `radius`, `avoid_weight`, `source`, `velocity`
ZERO, no pull / swirl / slow, not a LOS blocker.

### Sharing (gate time, allotment 3.0 s)
Real-physics (8x) scenes, each run once: (A) placed + pooled control (≈1.4 game-s); (B) PLAYER-vs-enemy and the three
ALL non-ship boundaries, four mines 1500 px apart (≈1.3 game-s); (C) ALL trigger + both-sides blast (≈1 game-s);
(D) per mode, the crossing and stopping stubs in one run (2 × 2.7 game-s); (E) the real mover and its control in one
run, 2000 px apart (6 game-s); (F) ready order (1 frame). ≈ 16 game-s ≈ 2 s wall. Everything else is hand-ticked or
pure. Assault-harness mines start inside the world rect.

## Risks
- Bomber mines registering moves a level-1 timing gate or a `test_bomber.gd` row -> pre-approved levers in order
  (`hazard_pad = 0`, then `registers_hazard = false`, on `mine.tscn` only), reported.
- Static registry leaking between tests -> every row frees its mines; `_exit_tree` unregisters.
- Gate time: allotment 3.0 s; real-physics rows share one 8x scene where possible.

## Out of scope
Other variant scenes (t3, t4, t6, t7), player boost hooks (t5), Minefield (t8), art (t9), Mine Layer (t10+), docs (t16).
