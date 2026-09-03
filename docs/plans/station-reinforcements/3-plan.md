# Station reinforcements (EPIC sub-item 4b)

> **Revision 3** — Revision 2 answered `4-review.md` round 1 (`VERDICT: CHANGES_REQUESTED`); round 2
> returned `VERDICT: APPROVED` with four non-blocking findings, folded in as **[R3]**. Changes are
> marked **[R2]** / **[R3]** and summarised at the bottom under *Revision log*. Both review rounds
> also verified a long list of mechanics as correct; those are not re-argued here.

## Problem

Today the space-station mini-boss is a duel in a vacuum. The station has guns
(`StationGunnery`, 4a) and sweeping beams (`StationLaserPhase`, 3), but nothing else ever enters
the arena: the player picks a comfortable spot below the hull, streams into one turret at a time,
and only the station's own cadence ever asks them to move.

After this change, **while the turrets are still up, the station calls for help**: small squads of
existing enemy ships cross in from the left, the right, below and above on a fixed, learnable
rhythm. The player can no longer camp — the safe spot for dodging turret fans is not the safe spot
when an interceptor is strafing through it. When the last turret dies the calls stop, and phase 2
goes back to being the station's own show.

## Design

### Where the behaviour lives

A new **`StationReinforcements`** node
(`assault/scenes/enemies/space_station/station_reinforcements.gd`), authored into
`space_station.tscn` as a `Node2D` child named `Reinforcements`, alongside the existing
`LaserPhase`, `BulletPool` and `Gunnery`. It is the fourth instance of a pattern this scene already
establishes twice: a sibling behaviour node that copies its tuning out of `SpaceStationConfig` in
`_ready()`, drives a `Timer`, hangs off the station's `armor_broken` / `died` signals, and exposes
a public `spawn_next_squad()` so tests never wait out a real interval. `space_station.gd` gains
**nothing** — no new methods, no new signals.

### Lifecycle

| Event | Effect |
|---|---|
| `_ready()` | Copy config, build the squad table, `_timer.start(reinforcement_first_delay)` (8 s) |
| `_timer.timeout` -> `_on_timer_timeout()` | `spawn_next_squad()`, **then** `_timer.start(reinforcement_interval)` (10 s) |
| `SpaceStation.armor_broken` | `_stop()` — timer stopped, `spawn_next_squad()` becomes a no-op |
| `BaseEnemy.died` | `_stop()` — same |

**[R2]** The `Timer` is `one_shot = true` and is restarted **only** from `_on_timer_timeout()`.
`spawn_next_squad()` touches no timer at all. That split is load-bearing for the tests: cases 10,
11 and 12 call `spawn_next_squad()` directly after a `_stop()` or against the cap, and if the
restart lived inside it they would silently re-arm the timer they had just asserted stopped.

Stopping at `armor_broken` is the research's finding 1 applied directly: constant adds are exactly
what makes a boss get overshadowed by its own minions, and phase 2 already runs beams every 6.5 s
over rings every 2.0 s against a 48-bullet pool. Phase 1 is the half of the fight that has the
room. It also disposes of the backlog's second warning for free: reinforcements stop *before* the
core is even damageable, so by the time the station dies they have almost always already left, and
`LevelSection.ENEMIES_CLEARED` is not held open.

### The squad table

Four squads, cycled **in a fixed order, never randomised** — the laser phase already established
that random attack ordering cannot be balanced or tested. Order is
`LEFT -> RIGHT -> BOTTOM -> TOP`, applying the Toaplan alternation rule (finding 3): consecutive
squads come from opposite sides, so the player is pulled across the screen rather than nudged.

Offsets are **640x360 design units, camera-relative** — `WaveManager`'s own convention, scaled by
`ArenaCamera.WORLD_SCALE` at spawn and never pre-multiplied. Speeds are likewise design units/s;
`EnemyPathMover` applies `WORLD_SCALE` itself (`enemy_path_mover.gd:77`).

| # | Edge | Ships | Offsets (design) | Movement | Angle meaning |
|---|---|---|---|---|---|
| 0 | Left | 2 x `interceptor` | (-440, 20), (-440, 80) | `straight(200, PI/2)` | rightward |
| 1 | Right | 2 x `interceptor` | (440, 20), (440, 80) | `straight(200, -PI/2)` | leftward |
| 2 | Bottom | 2 x `kamikaze_drone` | (-100, 290), (100, 290) | `straight(170, PI)` | upward |
| 3 | Top | 2 x `fighter` + `.shoot_forward()` | (-250, -290), (250, -290) | `straight(170, 0.5)` / `straight(170, -0.5)` | down-and-inward |

Every entry additionally gets `.free_after(7.0)`.

`StraightMovement.sample()` is `Vector2(sin(angle), cos(angle)) * speed * t`, i.e. **0 = down,
PI/2 = right, -PI/2 = left, PI = up** (`straight_movement.gd:2,13`). The round-1 review checked all
four rows against that and confirmed each points where the table claims.

Why these numbers:

- **[R2] +/-440 / +/-290 design (880 / 580 world).** Finding 5's rule is that the margin must exceed
  half the largest sprite plus the camera's maximum pan. The largest reinforcement is the
  interceptor at **64x74 world px**: `interceptor.tscn:58-60` gives its `Sprite2D` no `scale`, and
  the `1.8` on `:63` belongs to the sibling `CollisionShape2D` (round 1 misread that line).
  Half-extent is therefore **37**, not 67. With `ArenaCamera.H_LIMIT = 100`, horizontal needs
  > 640 + 100 + 37 = **777** world px, and vertical needs > 360 + 37 = **397** (`V_LIMIT` is
  deliberately excluded from the budget — see *Risks*). Both +/-420 and +/-440 clear 777;
  **+/-440 is chosen for the round number and 103 px of headroom, not because +/-420 was
  insufficient.** +/-290 gives 580 against 397, 183 px of headroom.
- **Side lanes at design y = 20 and 80**, the vertical middle — not the top or bottom border.
  Finding 3: "the edges of the screen don't have lanes to prevent awkward traps."
- **Top squad enters at design x = +/-250 and angles inward** so it neither hugs the border nor
  clips the hull. Hull spans design x -64..64, y -154..-26; a ship entering at (-250, -290) on angle
  0.5 is at x ~= -176 when it reaches y = -154 and x ~= -106 when it leaves at y = -26 — clear
  throughout, and mirrored on the right. **[R3]** Review round 2 re-derived this for the *fighter's*
  sprite rather than the ram's — `assault.png` is 64x64, half-extent 16 design units, twice the
  ram's — and it still clears: closest approach 41.8 units, so **26 design units (52 world px) of
  gap**, and 17 units of clearance against the rotated hull's 90.5-unit half-diagonal. The fighter's
  bullets travel the same ray as the ship, so they inherit that clearance; they also cannot damage
  the boss at all, since `enemy_bullet.tscn:22-23` masks only the player HurtBox layer 128 while the
  station's HurtBox is layer 512 (`space_station.tscn:72-74`).
- **[R2] The top squad is `fighter` (`light_assault_ship`), not `ram_ship`.** Round 1 found that
  `ram_ship.gd:19` sets `hurt_box.collision_mask = 33` ("missiles only; bullets ignored") while the
  player's bullet is `collision_layer = 64` (`bullet.tscn:44`) — a ram ship **cannot be hit by the
  player's primary weapon at all**, and `bullet.gd:71` even has it swallow piercing sniper shots.
  Two indestructible obstacles arriving every fourth cycle is not the popcorn role finding 2
  describes, and `docs/enemy-roster.md:127` ("HP: Medium") does not document the mask. `fighter` is
  60 HP (`fighter_config.tres:7`, applied at `light_assault_ship.gd:19-20`), and its HurtBox mask at
  **runtime** is `97 | 1024` = 1121, which includes the bullet's layer 64. **[R3, review N1]** That
  mask comes from `base_enemy.gd:25`, not from the `collision_mask = 65` authored on
  `light_assault_ship.tscn:83` — `BaseEnemy._ready()` overwrites the scene value for every enemy on
  the first frame, and `ram_ship.gd:19` is the one subclass that narrows it again afterwards. So the
  governing citation for "is this ship killable by the primary weapon?" is always `base_enemy.gd:25`
  plus any subclass override, never the scene file. It is `EnemyPathMover`-driven
  (`docs/enemy-roster.md:58`), and the mover also disables its `AIStateMachine`
  (`enemy_path_mover.gd:62-65`) so its approach/strafe states do not fight the path.
  `.shoot_forward()` makes it fire along its diagonal travel: the mover writes
  `rotation = atan2(-vel.x, vel.y)` each frame (`enemy_path_mover.gd:80-87`) and
  `aimed_attack_pattern.gd:28-31` fires `Vector2.DOWN.rotated(ship.rotation)` when
  `aim_at_player` is false (selected at `light_assault_ship.gd:33-45`). That reads as a strafing run
  and does not pile a *third* source of **aimed** fire on top of the turret fans — but it is not
  free, see *Risks*. The roster's own example (`docs/enemy-roster.md:78`) is this exact construction.
- **`interceptor` / `kamikaze_drone` / `fighter`** are the popcorn tiers (finding 2), all existing
  scenes per the EPIC's "reuse existing enemy scenes, do not create new enemy types". Deliberately
  **not** `gunship` or `drone_interceptor`: `docs/enemy-roster.md:260,294` marks both as
  self-managed AI that `EnemyPathMover` would break, and the 200 HP gunship would read as a second
  boss.
- **Two ships per squad, spawning simultaneously.** Finding 3's "spawn them one-by-one with slight
  delays" is explicitly a rule about *higher-HP* enemies; these are popcorn. Simultaneous spawning
  also keeps this node free of `await`, which matters — `tests/README.md:45-52` documents that a
  test ending while a coroutine is suspended leaks a `SceneTreeTimer` **with the gate still green**.

### Spawning mechanics

Squads are authored with `WaveBuilder` and stored as `Array[SpawnEntryResource]`, obtained through
its public API (`b.wave(0.0, [...]).entries`, `wave_builder.gd:211-221`). That reuses the exact
authoring vocabulary of `docs/enemy-roster.md` — `.at()`, `.move()`, `.free_after()`,
`.shoot_forward()` — instead of inventing a second one.

`_spawn_entry(e: SpawnEntryResource)` then does what `WaveManager._spawn_ship()` does
(`wave_manager.gd:159-205` is the model). **[R2]** `Level1Director._spawn_bonus_drone()`
(`level_1_director.gd:110-144`) is cited only as the shipped precedent for spawning *outside the
wave registry* — not as a line-for-line model, because it adds a raw world-px offset
(`:125`, `Vector2(-680, 60)`) rather than scaling a design-unit one.

1. `entity = e.ship_scene.instantiate()`
2. `entity.global_position = _spawn_origin() + e.base_offset * ArenaCamera.WORLD_SCALE`
3. apply `e.initial_props` before `add_child` (so they are readable in `_ready()`)
4. `_container().add_child(entity)`
5. `EventBus.enemy_spawned_orphan.emit(entity)`
6. attach an `EnemyPathMover` with `e.movement`, `e.exit_mode`, `e.exit_time`, **and [R3, review nit] `e.look_in_moving_direction` / `e.look_angle`** — `wave_manager.gd:201-204` copies those too, and carrying them keeps the `SpawnEntryResource` the single source of truth even though the defaults (`true` / `0.0`) are already what `.shoot_forward()` needs

- `_container()` is `_station.get_parent()`. In the level that is `wave_manager.enemy_container`
  (`level_1.tscn:22-26`, a bare `Node2D` with an identity transform); in tests it is the harness
  container. Reinforcements are therefore siblings of the station, **not children of it** —
  critical, because `station_laser_phase.gd:123` writes `_station.rotation` and anything parented
  under the station would be dragged around with it (the same trap `bullet_pool.gd:47` documents).
- `_spawn_origin()` returns `get_viewport().get_camera_2d().global_position` when a camera exists,
  else the constant `Vector2(ArenaCamera.SCREEN_W, ArenaCamera.SCREEN_H) * 0.5` = (640, 360). That
  fallback is not a fudge: `arena_camera.gd:5-6` pins `global_position` at exactly (640, 360) and
  pans through `offset` only (`:8-12`), so the fallback and the real camera agree. It exists so the
  tests (which have no camera) exercise the real positioning code instead of `WaveManager`'s
  return-early-with-no-camera path (`wave_manager.gd:160-162`).
- **`ExitMode.FREE_ON_DURATION` with `exit_time = 7.0` on every entry**, not
  `FREE_ON_SCREEN_EXIT`. This is the hard guarantee that no reinforcement can strand
  `ENEMIES_CLEARED`, which polls the container's child count (`level_director.gd:116`). Longest
  actual transit is the side run, ~4.0 s, so 7.0 s is margin, not a cut-off.

### [R2] Scoring and combo — an explicit balance decision, not a side effect

Round 1 found that the round-1 plan argued this one-sided. The full contract:

`EventBus.enemy_spawned_orphan` is connected at `score_tracker.gd:74-75` and routed at `:89-90` to
`_on_enemy_spawned(enemy, -1)`. That handler connects **both** `died` (score + combo growth,
`:167-188`) **and** `tree_exited` -> `_on_enemy_freed` (`:161-164`). And `_on_enemy_freed` applies
`_combo *= score_config.escape_combo_multiplier` at `:211`, **outside** the `if counts_in_wave:`
block — a `wave_index` of `-1` does not exempt it. `escape_combo_multiplier` is `0.75`
(`score_config_default.tres`), and the combo floors at 1.0 (`:212-213`).

So with reinforcements registered, each squad the player ignores costs `0.75^2 = 0.5625` of their
combo, and roughly three squads floor it.

**Decision: register them anyway** (option (b) of the three the review offered).

- The alternative — not emitting — means killing a reinforcement awards **zero** points and zero
  combo, because `ScoreTracker` is the only thing that pays out `BaseEnemy.died`. A player who
  shoots down an add and sees nothing happen will read that as a bug, and it is a worse outcome
  than a combo cost they can avoid by shooting.
- The escape penalty is the game's **universal** rule: every wave enemy that leaves the screen in
  every section pays it, and so does an escaping bonus drone (`level_1_director.gd:135-143`).
  Exempting one enemy source would be a special case inside the scoring system, which is a larger
  and more opinionated change than sub-item 4b, and a balance call that belongs to the user.
- It is also a coherent risk/reward read: adds are a **combo opportunity**, and letting six ships
  fly past unmolested during a 40-50 s fight is a legible thing to be charged for.

This is pinned by test 17 with real numbers rather than left as a comment, and it goes to
`BACKLOG.md` *Discovered* as a balance question, flagged in the report.

### [R2] Population cap

`reinforcement_max_alive` (default 4, i.e. two squads' worth). `spawn_next_squad()` prunes freed
entries from `_alive` and then **skips the whole squad if `_alive.size() + squad.size() >
reinforcement_max_alive`**, so the real ceiling is exactly 4, not "4 plus whatever a squad adds"
(round 1: an "already met" check with 2-ship squads would have peaked at 5). Squads are never
partially spawned — half a squad reads as a bug, not as a cap.

At a 10 s interval against a ~4 s transit the cap should never bind in normal play — it is the
valve for a stalled fight where the player is not killing anything, and it is what stops the screen
becoming unreadable next to a 4-turret fan volley (finding 2's tradeoff).

### Config fields (`SpaceStationConfig`)

Three, following the discipline the laser and gunnery blocks already state: read **once** in
`_ready()` and copied into node fields, because the `.tres` is a single process-wide instance.

| Field | Default | Why |
|---|---|---|
| `reinforcement_first_delay` | `8.0` | Boss-only opening; finding 1 says adds at the very start steal the boss's introduction |
| `reinforcement_interval` | `10.0` | Top of finding 4's 5-10 s event band, so a squad punctuates the 1.8 s turret cadence instead of blurring into it |
| `reinforcement_max_alive` | `4` | Readability valve (finding 2) |

Node-level defaults are deliberately *different* and conservative (`20.0` / `30.0` / `2`), so the
config test cannot pass vacuously — the same trick `station_gunnery.gd:64-73` uses.

Squad geometry stays in the **script**, not the config: it is scene/level geometry, the same split
that keeps `laser_emitter_radius` and `turret_spawn_radius` on their nodes.

### Alternatives rejected

1. **Add reinforcement waves to the `station_assault` `LevelSection`.** Cheapest — but wrong.
   `waves_complete` fires when the last wave *triggers* (`wave_manager.gd:50-57`), so a fixed
   schedule is decoupled from the fight: a slow player gets no adds for the last 60 s, and a fast
   player has squads spawning after the boss is already dead, holding `ENEMIES_CLEARED` open. It
   also cannot see `armor_broken`, so it cannot phase-gate at all. Both of these are the exact
   failure modes the backlog item's "starting points" warn about.
2. **Add a `&"station_assault"` entry to `Level1Director._section_schedules`.** The same fixed
   timeline as (1) with the same two defects, and it puts boss behaviour in the level director
   while three sibling nodes for the same boss already exist next door.
3. **A generic reusable `ReinforcementSpawner` in `global/components/`.** No second caller exists,
   and there is no spawner component there today. Building a general component for one user is
   speculative; if sub-item 5 or Level 2 wants one, promoting this node then is a rename plus an
   export.
4. **Reinforcements through phase 2 as well, at a longer interval.** More pressure, but it is
   finding 1's documented failure and it competes with the beams and rings for a 48-bullet pool and
   for the player's attention. Left as a tuning knob: raising the interval and dropping the
   `armor_broken` stop is a two-line change if playtesting wants it.
5. **[R2] Keep `ram_ship` on the top squad as a deliberate indestructible obstacle.** Defensible in
   the abstract, and round 1 offered it as an option. Rejected: the player has no way to learn from
   the game that this one enemy ignores their main gun, `ram_config.tres:8`'s `max_health = 999` is
   never even applied (`ram_ship.gd:16-17`), and "one enemy in the roster is secretly immune"
   deserves its own backlog item rather than a debut inside a boss fight.

## Build sequence

1. **`SpaceStationConfig`**: add the three `reinforcement_*` fields with doc comments; add them to
   `space_station_config.tres`. Verify with `godot --headless --check-only`.
2. **Test file first** — `tests/integration/test_station_reinforcements.gd`, all cases below. Run
   it and watch it fail (the script and the scene node do not exist yet).
3. **`station_reinforcements.gd`**: the node — config copy, squad table via `WaveBuilder`, timer,
   `_on_timer_timeout()`, `spawn_next_squad()`, `_spawn_entry()`, cap, `_stop()`.
4. **`space_station.tscn`**: add the `Reinforcements` `Node2D` child with the script attached.
5. Run the new test file green, then the whole suite.
6. `bash /agent/verify.sh`.
7. Docs: `updating-project-docs` (this is structural — a new script and a new scene node), which
   covers `assault/scenes/enemies/space_station/ENEMY.md`,
   `docs/architecture/modules/assault.md`, `docs/architecture/PROJECT.md`; plus a
   `docs/enemy-roster.md` note that the station calls reinforcements. Tick 4b in `BACKLOG.md`.

## Test plan

`tests/integration/test_station_reinforcements.gd`, GUT, intent-asserting (new code, like the rest
of the station family). Harness follows `test_station_gunnery.gd`: station instanced under a
container `Node2D`, `LaserPhase.rotation_speed = 0`, and the reinforcement `Timer` stopped in
`before_each` so every spawn is forced. **Never write to `station.config`** — override on the node.
No case awaits more than a frame; nothing is driven by a wall clock.

| # | Case | What would fail |
|---|---|---|
| 1 | After `_ready()`, the node's three fields equal `space_station_config.tres`'s values | A field added to the config but not copied — silently ignored tuning. Cannot pass vacuously: the node defaults are 20/30/2 vs the config's 8/10/4 |
| 2 | Over one full cycle the squads cover **four distinct edges** — at least one entry with design x < -320, one with x > 320, one with y > 180, one with y < -180 | The done-condition itself ("at least three screen edges") |
| 3 | **Boundary:** *every* entry in *every* squad starts off screen — `abs(x) > 320 or abs(y) > 180` in design units | A squad authored inside the play area, popping in on top of the player |
| 4 | **[R2] Boundary:** every entry clears the finding-5 margin — side entries `abs(x) * 2 > 777`, top/bottom entries `abs(y) * 2 > 397` | The margin rule, with the corrected half-extent of 37. Would fail at design +/-380 (760 < 777), so it is a live constraint, not decoration |
| 5 | Squads cycle deterministically: 4 successive `spawn_next_squad()` calls produce the 4 edges in order `LEFT, RIGHT, BOTTOM, TOP`, and the 5th repeats `LEFT` | A `randf()` creeping in; a modulo bug that skips or repeats a squad |
| 6 | Each spawned ship is added to the station's **parent container**, not under the station, and each has an `EnemyPathMover` child | The rotation trap — a reinforcement parented under the hull would orbit with the laser phase |
| 7 | Each entry's movement vector points **into** the screen: `movement.sample(1.0).dot(centre - spawn_pos) > 0` | A sign flip in the 0-is-down angle convention — the exact bug class that shipped once already in the turret barrels |
| 8 | Every spawned mover has `exit_mode == FREE_ON_DURATION` and `exit_time > 0` | A reinforcement that can never be culled, stranding `ENEMIES_CLEARED` |
| 9 | `EventBus.enemy_spawned_orphan` is emitted once per spawned ship | Reinforcement kills silently awarding no score |
| 10 | Killing all four turrets (`armor_broken`) stops it. **[R3, review N2]** The case must `_timer.start(...)` immediately before emitting `armor_broken`, then assert `_timer.is_stopped()` — `before_each` already stops the timer, so without the restart that clause is vacuous. Then a subsequent `spawn_next_squad()` adds nothing | The phase gate, i.e. the whole design-1 finding |
| 11 | `died` stops it: kill the core, then `spawn_next_squad()` adds nothing | Reinforcements outliving the boss and holding the section open |
| 12 | **[R2] Boundary, at the shipped value:** with `reinforcement_max_alive = 4` and 2-ship squads — spawn (2 alive), spawn (4 alive), spawn -> **nothing added**; then free all four and spawn -> 2 appear | The off-by-a-squad the review caught (an "already met" check would let the third squad through at 4), and an `is_instance_valid` prune that never runs, permanently jamming the spawner |
| 13 | No squad entry uses the `gunship` or `drone_interceptor` scene | `docs/enemy-roster.md:260,294`'s self-managed-AI rule, which `EnemyPathMover` silently breaks |
| 14 | `space_station.tscn` contains a `Reinforcements` child whose script is `StationReinforcements` | The scene wiring — 4a lost time to an unwired export that left the gate green |
| 15 | **[R2]** After `_ready()`, `_timer.one_shot` is true and `_timer.wait_time == reinforcement_first_delay`; after one `_on_timer_timeout()` call, `_timer.wait_time == reinforcement_interval` and `not _timer.is_stopped()` | First squad never arriving, arriving on the boss's first frame, or the cadence collapsing to the first delay forever. Read from the timer, never awaited |
| 16 | **[R2]** Every ship the squad table can spawn is **killable by the player's primary weapon**: instantiate it, add it to the tree so its `_ready()` runs (both because `hurt_box` is `@onready` on `base_enemy.gd:7` and because the governing mask is written in `_ready()` at `base_enemy.gd:25`), and assert `hurt_box.collision_mask & 64 != 0` (`bullet.tscn:44`, `collision_layer = 64`) | Exactly the `ram_ship` defect (mask 33) the review caught, caught automatically the next time someone swaps a squad ship. **[R3, review nit]** It iterates the squad table only, so it does not *execute* the ram case — the discrimination (`1121 & 64 == 64` passes, `33 & 64 == 0` fails) is real but counterfactual today |
| 17 | **[R2]** The combo cost is what the design says it is: with a `ScoreTracker` started, force `_combo` to 4.0, spawn a squad, free both ships, and assert `4.0 * 0.75 * 0.75 = 2.25` (above the 1.0 floor, so it is exact). **[R3, review N3]** The case must also `tracker.set_process(false)` first and assert on `tracker.get("_combo")` rather than on the last `combo_changed` payload: `score_tracker.gd:112-124` decays the combo to 1.0 on the first processed frame when `_combo_decay_remaining` is 0, and `start_tracking()` turns `_process` on. `test_station_assault_section.gd:142-147` already documents this exact remedy | Pins the balance decision above with a number rather than a comment. Would fail if the escape path were quietly exempted, or if the emit were dropped |

## Risks

- **Screen density in phase 1, with the real numbers. [R3, review N4]** Four turret fans are
  4 x 3 / 1.8 s = **6.7 bullets/s at 240 px/s** (`space_station_config.gd:62-65`). The top squad
  adds more than the R2 text implied: `light_assault_ship.gd:42,44` **special-cases FORWARD mode**
  to `fire_interval = 0.3` and `bullet_speed = 420.0`, not the config's 0.8 / 250. Two fighters are
  therefore ~**6.7 bullets/s at 420 px/s** — comparable to the entire turret volley — for the ~3.3 s
  of their transit. That roughly doubles phase-1 bullet volume while the top squad is on screen.
  It is bounded three ways: the squad is 1 of 4 in the cycle so it arrives at most every ~40 s, the
  `reinforcement_max_alive` cap holds the population at 4, and everything stops at `armor_broken`.
  It is also `.shoot_forward()`, so the bullets travel the squad's own diagonal and never track the
  player. Accepted, but it is the single most likely thing to want re-tuning after a playtest — and
  it cannot be checked headless, so the cap is the structural guard and test 12 pins it at the
  shipped value.
- **The bottom-edge spawn is behind the player.** Finding 5's "spawn furthest from the player"
  cannot be honoured literally for a fixed table. Mitigated by using the *slowest* ships there
  (`kamikaze_drone`, 170 vs 200) and by the 580 world px of run-up, ~1.7 s of visible approach.
  A tuning risk, not a blocker.
- **Camera pan can reveal a spawn.** Spawns resolve against `cam.global_position`, the fixed
  centre, exactly as every wave in the game does (`arena_camera.gd:5-12`); `V_LIMIT` is 380, so a
  player panned fully down could see a bottom spawn appear. This is a pre-existing project-wide
  property of the spawn convention, not something 4b introduces, and diverging from the convention
  for one node would be worse. Hence `V_LIMIT` is excluded from the vertical margin budget above.
  Goes to `BACKLOG.md` *Discovered*.
- **[R2] The combo penalty** (see *Scoring and combo*). Accepted deliberately, pinned by test 17,
  and raised in `BACKLOG.md` *Discovered* and the run report for the user to overrule.
- **Test noise.** Real enemy scenes instantiate real timers and AI. Squads are 2 ships, every test
  forces its own spawns, and the reinforcement timer is stopped in `before_each`.
- **`ExplosionEffect` orphans particles into the container** (a known *Discovered* item), and a
  reinforcement `interceptor` builds its own `BulletPool` whose bullets reparent into the same
  container (`bullet_pool.gd:47`). Tests that count container children must filter by type, as
  `test_station_gunnery.gd:81-86` does for bullets.

## Out of scope

- Sub-item 5 (station death -> `planet_approach` handoff).
- Any new enemy type, sprite, or art. Nothing here calls PixelLab.
- Difficulty scaling of reinforcements by mission difficulty or by turrets lost.
- Reinforcements in phase 2 (see rejected alternative 4).
- Making the boss fight camera-locked so panning cannot reveal spawns.
- **[R2]** Fixing `ram_ship`'s bullet immunity, or `ram_config.tres`'s unapplied `max_health`.
  Both go to `BACKLOG.md` *Discovered*.

## Revision log

**R2, after review round 1:**

- **B1** — top squad swapped `ram_ship` -> `fighter` + `.shoot_forward()`; rejected alternative 5
  records why not the "deliberate obstacle" reading; new test 16 makes the whole class of defect
  auto-detectable.
- **B2** — new *Scoring and combo* section makes the 0.75x escape penalty an argued decision with
  the code path spelled out; new test 17 pins it numerically; it goes to the backlog and report.
- **B3** — interceptor half-extent corrected 67 -> 37, margins re-derived to 777 / 397, the false
  "+/-420 was insufficient" claim removed, test 4 constants corrected.
- **S1** — cap semantics changed to "skip the squad if `alive + squad_size > max`", ceiling is now
  exactly 4; test 12 rewritten to probe that boundary at the shipped value instead of at 1.
- **S2** — `_on_timer_timeout()` named; `one_shot = true`; `spawn_next_squad()` explicitly touches
  no timer.
- **S3** — test 15 restated as reads of `Timer.wait_time` / `one_shot` / `is_stopped()`.
- **S4** — citations corrected (`level_1_director.gd:110-144`, `level_director.gd:116`,
  `station_gunnery.gd:64-73`, `score_tracker.gd:74-75` + `:89-90`,
  `test_station_gunnery.gd:81-86`); `_spawn_bonus_drone` demoted from "line-for-line model" to
  "precedent for spawning outside the wave registry", with `wave_manager.gd:159-205` as the model.

**R3, after review round 2 (`VERDICT: APPROVED`, non-blocking findings only):**

- **N1** — the "fighter is bullet-killable" evidence now cites `base_enemy.gd:25` (runtime mask
  1121), not the authored `light_assault_ship.tscn:83` that `BaseEnemy._ready()` overwrites.
- **N2** — test 10 must `_timer.start(...)` before emitting `armor_broken`; `before_each` already
  stops the timer, so the `is_stopped()` clause was vacuous as written.
- **N3** — test 17 must `tracker.set_process(false)` and read `tracker.get("_combo")`, or the
  combo-decay `_process` resets it to 1.0 on the first frame.
- **N4** — the density risk carries the real figures: FORWARD mode forces `fire_interval = 0.3` and
  `bullet_speed = 420.0` (`light_assault_ship.gd:42,44`), so the top squad roughly doubles phase-1
  bullet volume during its transit.
- Nits — `docs/enemy-roster.md:78` (not `:76`); `aimed_attack_pattern.gd:28-31` cited alongside
  `light_assault_ship.gd:33-45`; `_spawn_entry` step 6 also carries `look_in_moving_direction` /
  `look_angle`; test 16's ram case described honestly as counterfactual.
- `2-research.md` F5 corrected to half-extent 37 / margins 777-397, and its F2 popcorn list swapped
  `ram_ship` for `fighter` — round 1 asked for both documents and only the plan had been updated.
