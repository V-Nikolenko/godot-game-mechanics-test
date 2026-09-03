# Review — Station reinforcements (EPIC sub-item 4b)

VERDICT: CHANGES_REQUESTED

Reviewed `1-context.md`, `2-research.md`, `3-plan.md` against the code, not against the plan's own
description of the code. Every `file:line` citation in the plan was opened.

The **architecture is right** and I want to say so before the findings: a fourth sibling behaviour
node under `space_station.tscn`, config-copied-in-`_ready()`, phase-gated on `armor_broken`,
spawning as a *sibling* of the station into `_station.get_parent()`, authored in 640x360 design
units, is the correct shape for this codebase. Rejected alternatives 1-4 are each correctly
reasoned (alternative 1's `waves_complete` argument is verified below). Nothing here reinvents a
`global/components/` component — there is no spawner component in that folder, and none elsewhere.
Scope (3 files touched + 1 test + docs) is one session's work, comparable to 4a.

Three findings are blocking. Two of them are *gameplay* defects that headless tests will not
catch, which is exactly the class of thing this review exists to catch.

---

## Blocking

### B1. `ram_ship` is immune to the player's primary weapon. The top squad is unkillable.

`assault/scenes/enemies/ram_ship/ram_ship.gd:19` — `hurt_box.collision_mask = 33 # missiles only
(32 + 1); bullets ignored`. The player's bullet is `collision_layer = 64`
(`assault/scenes/projectiles/bullets/bullet.tscn:44`). 33 excludes 64, so **no player bullet ever
reaches a ram ship's hurtbox.**

It compounds three ways:

- `ram_ship.gd:27-31` — even the first *missile* hit deals no damage; it only calls
  `_enter_damaged_state()`, which then re-opens the mask to 97 and resets HP to 100
  (`ram_ship.gd:44-48`). So the kill cost is one missile plus further damage.
- `assault/scenes/projectiles/bullets/bullet.gd:71` — a piercing sniper bullet is *consumed* by a
  `ram_ships`-group node and zeroed to 0 damage. Ram reinforcements would eat the pierce build's
  shots too.
- `assault/scenes/enemies/ram_ship/ram_config.tres:8` is `max_health = 999`, and `ram_ship.gd:16-17`
  never applies it (only `movement_speed`), so the scene's bare `Health` default is what runs
  (`ram_ship.tscn:88-90`). The number nobody can read is 999 in the file the plan would point a
  reader at.

`3-plan.md:79-83` calls `ram_ship` one of "the popcorn tiers (finding 2)" and `1-context.md`'s reuse
table lists it as a reinforcement candidate. `2-research.md` finding 2 defines popcorn as "the
lowest HP tier" that "should not have much more HP than is needed to fulfil their function". A
bullet-immune enemy is the opposite of that. The plan took `docs/enemy-roster.md:127` ("**HP:**
Medium") at face value; the roster simply does not document the mask.

Net effect at runtime: squad 3 (top) becomes two indestructible 50-collision-damage obstacles that
the player can only dodge, arriving every 4th cycle, on top of four turret fans. That may even be
*defensible* as a pure-obstacle beat — but it has to be a decision, not an accident, and the plan
currently asserts the opposite.

**Required:** either swap the top squad to `fighter` (`light_assault_ship`, 60 HP, mask-normal,
`docs/enemy-roster.md:54-58` confirms it is `EnemyPathMover`-driven), or keep `ram_ship`, say
explicitly in the plan and in the node's docstring that it is an *undestroyable obstacle by
design*, and add a test asserting the choice is deliberate. Do not ship the current justification.

### B2. Every reinforcement that flies through costs the player a 0.75x combo penalty. Unexamined.

The plan's whole argument for `EventBus.enemy_spawned_orphan` (`3-plan.md:106-111`) is upside-only:
"reinforcements award kill score and never disturb a wave-clear tally". The citation is right —
`score_tracker.gd:74-75` connects it, `score_tracker.gd:89-90` routes to `_on_enemy_spawned(enemy,
-1)`. But follow the handler:

- `score_tracker.gd:161-164` — `_on_enemy_spawned` unconditionally connects
  `enemy.tree_exited -> _on_enemy_freed(...)`, one-shot.
- `score_tracker.gd:197-215` — `_on_enemy_freed` runs whenever the node leaves the tree without
  having been killed, and line **211** does `_combo *= score_config.escape_combo_multiplier`
  **outside** the `if counts_in_wave:` block. `wave_index == -1` does not exempt it.
  `counts_toward_wave_clear = false` would not exempt it either — that flag only gates lines
  205-209.

The plan mandates `ExitMode.FREE_ON_DURATION, exit_time = 7.0` on *every* entry
(`3-plan.md:123-127`), and the transit maths says the ships are meant to fly through and be culled.
So a player who does not kill a squad eats 0.75 twice: 0.5625 per squad, and across the ~3 squads
of a phase-1 the multiplier floors out (`score_tracker.gd:212-213` clamps at 1.0). Reinforcements
would systematically destroy the combo of a player who correctly ignores them to focus the boss —
the precise opposite of the design intent in `3-plan.md:10-14`.

`test_station_assault_section.gd:132-134` and `:162-163` already pin this penalty path, so it is
known behaviour in this repo, not my inference. `Level1Director._spawn_bonus_drone` has the same
latent issue (`level_1_director.gd:135-143`), but a bonus drone is a rare optional pickup, not six
scheduled ships.

**Required:** pick one and write it into the plan — (a) drop the `enemy_spawned_orphan` emit and
accept that reinforcement kills award no score, (b) emit it and add an explicit test asserting the
combo cost with real numbers so it is a chosen balance decision, or (c) change the exit strategy so
kills are the expected outcome. Add a test case: "a reinforcement freed by its mover does not
silently gut the combo" — the current test 9 asserts only that the signal fires, which is the half
of the behaviour that is fine.

### B3. `interceptor.tscn:63` does not say what the research says it says. The F5 margin derivation is wrong.

`2-research.md` finding 5 and `3-plan.md:70-72` both state: "a 64x74 texture on a `Sprite2D` scaled
1.8 (`interceptor.tscn:63`) = 115x133 world px, half-extent ~67".

Actual `assault/scenes/enemies/interceptor/interceptor.tscn`:

```
58  [node name="Sprite2D" type="Sprite2D" parent="." unique_id=339261469]
59  material = SubResource("ShaderMaterial_int")
60  texture = ExtResource("3_int")          <- no scale property; renders at 1.0
61
62  [node name="CollisionShape2D" type="CollisionShape2D" parent="." unique_id=267320844]
63  scale = Vector2(1.8000002, 1.8000002)   <- the cited line: COLLISION, not sprite
64  shape = SubResource("CircleShape2D_int") <- CircleShape2D radius = 14 (:15-16)
```

Line 63 is the *CollisionShape2D*'s scale, and the shape under it is a radius-14 circle, so the
scaled collider is r=25.2. The `Sprite2D` at :58-60 has no `scale`, so the interceptor renders at
its texture size, 64x74 (verified from the PNG header). Half-extent is **37**, not 67.

Consequences:

- F5's required horizontal margin is `640 + 100 + 37 = 777` world px, not 807.
- `3-plan.md:201` (test 4) hardcodes `640 + 100 + 67` and `360 + 67`. The test still passes at
  +/-440, so it cannot catch anything — but it enshrines a fabricated measurement as an assertion.
- `3-plan.md:201`'s stated purpose, "it pins the +/-440 that was +/-420 before the interceptor's 1.8
  scale was measured", is arithmetically false under **either** number: 420 * 2 = 840, and
  840 > 807 > 777. +/-420 was never insufficient. The one test case whose stated reason for existing
  is a measurement has a reason that does not survive arithmetic.

The chosen +/-440 is safe (it over-shoots), so this is not a runtime bug — it is a false claim load-
bearing for a design number and a test constant, in a document that will be read as the record of
why the numbers are what they are.

**Required:** correct the half-extent in `2-research.md` F5 and `3-plan.md`, re-derive 777/397, and
either restate why +/-440 over +/-420 (fine: round number, extra headroom) or drop that sentence.

---

## Should fix before implementing

### S1. `reinforcement_max_alive = 4` does not cap the population at 4.

`3-plan.md:131-132`: "`spawn_next_squad()` ... returns early when the cap is already met." With a
squad size of 2, three live ships is under the cap, so a full squad still spawns: real ceiling is
5, not 4. Test 12 (`3-plan.md:209`) uses `max_alive = 1` and therefore never exercises the
off-by-squad-size case. Either document the field as "do not *start* a squad above N alive" or gate
per entry, and make test 12 use `max_alive = 3` against a 2-ship squad so the boundary is real.

### S2. The timer-restart location is unspecified, and four test cases depend on it.

`3-plan.md:33-36` puts the restart on `Timer.timeout` ("`spawn_next_squad()`, then restart the
timer") but never says whether the restart lives *inside* `spawn_next_squad()` or in a wrapper.
It must be a wrapper. If it is inside, tests 10 and 11 (`3-plan.md:207-208`) — which call
`spawn_next_squad()` after `_stop()` and assert nothing spawns — would restart the very timer they
just asserted stopped, and test 15's "repeats at `reinforcement_interval`" becomes untestable
without waiting a real 8 s. Name the handler (`_on_timer_timeout()`) in the plan and state that
`spawn_next_squad()` touches no timer.

### S3. Test 15 is the only case with no stated way to run without wall-clock time.

Every other case is driven by a forced `spawn_next_squad()`. Test 15 asserts a first delay of 8 s
and a repeat of 10 s. Spell out that it reads `Timer.wait_time` / `is_stopped()` after `_ready()`
and after one `_on_timer_timeout()` call — not `await wait_seconds(8)`. The existing station files
cap out at 1.4 s of tree time (`test_station_laser_phase.gd:244`), and a multi-second test file
would be an outlier.

### S4. Citation drift (all minor, all worth fixing since the plan trades on precision).

| Plan says | Actually |
|---|---|
| `level_1_director.gd:110-140` (`_spawn_bonus_drone`) | the function is `:110-144` |
| `level_1_director.gd:104-107` (angle convention) | `:104-108` |
| `station_gunnery.gd:63-75` (conservative defaults) | defaults are `:64-73`, the comment `:61-63` |
| `level_director.gd:106` "polls the container's child count" | `:106` is the container lookup; the poll is `:116` |
| `test_station_gunnery.gd:56-64` "count container children, filter by type" | `:55-66` filters `$Turrets`' children; the *container* filter is `_bullets()` at `:81-86` |
| `score_tracker.gd:73-75` "routes it to `_on_enemy_spawned(enemy, -1)`" | connect is `:74-75`; the routing body is `:89-90` |

Also: `3-plan.md:96-98` describes `_spawn_entry` as "modelled line-for-line" on
`_spawn_bonus_drone`, but the plan multiplies the offset by `WORLD_SCALE` (correctly, per
`wave_manager.gd:172`) while `level_1_director.gd:125` does **not** — its `Vector2(-680, 60)` is
raw world px. The plan's behaviour is right; the sentence is not. Cite `wave_manager.gd:159-205`
as the model and `_spawn_bonus_drone` only as precedent for spawning outside the wave registry.

---

## Verified correct — do not re-litigate these during implementation

Checked and confirmed, so the implementer does not spend the session second-guessing them:

- **The angle table is right in all four rows.** `global/resources/movement/straight_movement.gd:13`
  is `Vector2(sin(angle), cos(angle)) * speed * t`, and `:2` documents `0=down, PI/2=right,
  -PI/2=left, PI=up`. Left at x=-440 with `PI/2` -> (+200, ~0) rightward; right at +440 with `-PI/2`
  leftward; bottom at y=+290 with `PI` -> (~0, -170) upward; top at y=-290 with `+/-0.5` ->
  (+/-81.4, +149.2), i.e. down-and-inward from both sides. Test 7's dot-product formulation
  (`3-plan.md:204`) yields a positive value for all eight entries and *would* flip negative on a
  sign error — it is a real assertion.
- **Hull clearance arithmetic is right.** `level_1_director.gd:225-227` confirms `at(0, -90)` ->
  world (640, 180) with a 256 px hull spanning world y 52-308, i.e. design y -154..-26, x -64..64.
  A ram from (-250, -290) on angle 0.5 (`tan 0.5 = 0.5463`) is at x = -175.7 at y = -154 and
  x = -105.8 at y = -26. Closest approach to the hull box is 42 design units (84 world px) against
  a 32x32 sprite. Clear, and still clear against the rotated hull's 181 px half-diagonal.
- **Transit times fit inside `exit_time = 7.0`.** `enemy_path_mover.gd:77` does apply
  `ArenaCamera.WORLD_SCALE` to `movement.sample()`, so 200 design/s = 400 world px/s. Side run
  880 + 640 + ~70 = ~1590 px -> 3.97 s. Bottom: 340 px/s over ~975 px -> 2.87 s. Top: vertical
  component `170 * cos(0.5) * 2 = 298` px/s over ~975 px -> 3.27 s, with 533 px of inward drift
  (from world x -500 to +33 — stays on screen). The "~1.7 s of visible approach" for the bottom
  squad (`3-plan.md:222`) is also right: 580 px at 340 px/s.
- **`_ready()` ordering is safe.** Godot readies children before parents, so `Reinforcements._ready()`
  runs before `SpaceStation._ready()`. `space_station.gd:36` declares `config` as an `@export` with
  a `load()` default, which is assigned at property-init, so `_station.config` is populated —
  `station_gunnery.gd:101-104` documents exactly this and works today. Nothing in the plan's
  `_ready()` touches `SpaceStation.turret_root`, which is `@onready` and genuinely still null
  (`station_gunnery.gd:146-148`). `get_parent() as SpaceStation` resolves.
- **No `data.blocked` trap.** The plan never `add_child`es onto an ancestor from `_ready()` — the
  first `_container().add_child()` happens on a timer 8 s later. The hazard
  `station_gunnery.gd:26-29` documents does not apply.
- **`_station.get_parent()` resolves to the right container with an identity transform.**
  `level_1.tscn:22` `EnemyContainer` is a bare `Node2D` with no transform, and `:24-26` wires it as
  `WaveManager.enemy_container`. Setting `global_position` on the orphan before `add_child`
  therefore behaves identically to `wave_manager.gd:174-181`.
- **Parenting to the container rather than the station is genuinely load-bearing.**
  `station_laser_phase.gd:123` writes `_station.rotation`, and `bullet_pool.gd:47` hardcodes
  `get_parent().get_parent()`. Test 6 is a real test.
- **`FREE_ON_DURATION` cannot strand `ENEMIES_CLEARED`.** `enemy_path_mover.gd:91-96` frees on
  `exit_time` and short-circuits before `_check_off_screen`. Reinforcement interceptors build their
  own `BulletPool` in `interceptor.gd:30-34`, whose bullets reparent into the same container via
  `bullet_pool.gd:47` — but `bullet_pool.gd:98-102` `_exit_tree()` frees every in-flight bullet when
  the ship goes, so the bullets cannot outlive the ships either.
- **Cameraless tests are safe.** `enemy_path_mover.gd:44-46` only `push_warning`s with no camera,
  guards `_cam` at `:75`, and `tests/README.md:88` states `push_warning` is not a GUT failure.
  Diverging from `wave_manager.gd:160-162`'s return-early is therefore a legitimate call, and
  `arena_camera.gd:5-6` does pin `global_position` at (640, 360) with panning through `offset`
  (`:8-12`), so the (640, 360) fallback and the live camera really do agree.
- **Adding an 8 s timer to `space_station.tscn` will not contaminate the existing station tests.**
  The longest await across `test_space_station.gd`, `test_station_gunnery.gd` and
  `test_station_laser_phase.gd` is `wait_seconds(1.4)`; `before_each` re-instantiates the station
  each test.
- **Rejected alternative 1 is correctly reasoned.** `wave_manager.gd:50-57` really does emit
  `waves_complete` the moment the last wave *triggers*, before delayed spawns land.
- **`docs/enemy-roster.md:260` and `:294`** really are the "Self-managed AI. Do NOT add `.move()`"
  warnings for `drone_interceptor` and `gunship`. Test 13 is a legitimate guard.
- **The `WaveBuilder` API the plan assumes all exists**: `wave(trigger, entries) -> WaveResource`
  with `.entries` (`wave_builder.gd:211-221`), `at()` `:24`, `move()` `:29`, `free_after()` `:39-42`
  (which does set `FREE_ON_DURATION` + `exit_time`), `straight(speed, angle)` `:97-102`,
  `interceptor()` `:83`, `drone()` `:79`, `ram()` `:80`. `SpawnEntryResource` carries every field
  `_spawn_entry` reads.
- **`kamikaze_drone` and `interceptor` behave correctly under `EnemyPathMover`.** Both are listed as
  `.move()`-driven (`docs/enemy-roster.md:93`, `:231`). `kamikaze_drone.gd:47-49`'s self-movement is
  suppressed by `enemy_path_mover.gd:62`, and its `_ready()` player-lookup (`:39-45`) degrades to
  `Vector2(0,1)` with no player, which the mover then overrides anyway.
- **`BaseEnemy.died` is genuinely zero-argument** (`base_enemy.gd:4`), so the plan's zero-arg
  `_stop` handler is the right shape and does not hit the `tests/README.md:84-88` trap.
- **Config discipline matches the house rule.** `station_gunnery.gd:55-73` establishes read-once-and-
  copy with deliberately-different conservative defaults; the plan's 20/30/2 vs 8/10/4 makes test 1
  non-vacuous, as claimed.
- **Research sources support their claims** where they could be checked. F5's own quoted rule
  ("high enough where the largest spawned mob is still not visible") is applied correctly in method;
  only the measured input is wrong (B3). F1 is honestly flagged as resting on a search summary plus
  two forum threads, and is used only for direction, never for a number — that is the right way to
  handle an unreachable source. Every finding carries a real tradeoff column.

---

## Summary of what to change

1. Resolve the `ram_ship` choice (B1) — swap to `fighter`, or declare and test the obstacle intent.
2. Resolve the escape-combo consequence of `enemy_spawned_orphan` + `FREE_ON_DURATION` (B2), and
   add a test for whichever way it goes.
3. Fix the interceptor half-extent (37, not 67) in `2-research.md` F5, `3-plan.md`'s geometry
   bullet and test 4's constants; drop or restate the "+/-420 was insufficient" claim (B3).
4. S1-S4: cap semantics, timer-restart split, test 15's mechanism, citation line numbers.

Re-submit with those and this is an approve — the skeleton does not need to change.

---

# Review round 2

VERDICT: APPROVED

Reviewed Revision 2 against the code, not against the plan's description of it. Every `file:line`
the plan cites that is load-bearing for a decision was opened, plus the three squad ship scenes,
`base_enemy.gd`, `aimed_attack_pattern.gd` and the PNG headers. All three blocking findings from
round 1 are genuinely resolved — not merely acknowledged — and S1-S4 are resolved as well. The
findings below are non-blocking: four test/citation corrections to make while implementing, none of
which changes the design. Implementation may start.

## Round-1 findings: verification

### B1 — RESOLVED. `fighter` is real, bullet-killable, mover-driven, and 60 HP.

- `assault/scenes/enemies/light_assault_ship/` exists with `light_assault_ship.tscn`,
  `light_assault_ship.gd`, `fighter_config.tres`. `WaveBuilder.FIGHTER`
  (`assault/scenes/systems/wave_builder.gd:231`) points at it; `b.fighter()` is `wave_builder.gd:78`;
  `.shoot_forward()` is `wave_builder.gd:50-52` and sets `_props["aim_mode"] = "FORWARD"`, which
  `light_assault_ship.gd:10` declares as a plain var readable in `_ready()`. All real.
- **60 HP confirmed**: `assault/scenes/enemies/light_assault_ship/fighter_config.tres:7`
  `max_health = 60`, applied at `light_assault_ship.gd:19-20`.
- **Bullet-killable confirmed, but the plan cites the wrong line for it** (see N1 below). Runtime
  mask is `1121` from `assault/scenes/enemies/base_enemy.gd:25`, and `1121 & 64 == 64`.
- **Fires along travel, confirmed at the mechanism**: `EnemyPathMover` sets
  `_actor.rotation = atan2(-vel.x, vel.y)` every frame
  (`assault/scenes/enemies/enemy_path_mover.gd:80-87`), and
  `global/resources/attack/aimed_attack_pattern.gd:28-31` with `aim_at_player = false` fires
  `Vector2.DOWN.rotated(ship.rotation)`. For `straight(170, 0.5)` I get bullet direction
  `(0.479, 0.878)` — exactly the travel vector. The plan's claim holds.
- **`EnemyPathMover` does not fight the fighter's AI.** `light_assault_ship.tscn:99-111` has an
  `AIStateMachine` with `ApproachState`/`StrafeExitState` that call `move_and_slide()`;
  `enemy_path_mover.gd:62-65` disables `_physics_process` *and* sets
  `get_node_or_null("AIStateMachine").process_mode = PROCESS_MODE_DISABLED`. Both are suppressed.
  `docs/enemy-roster.md:58` ("Fully delegated to `EnemyPathMover`") is accurate.
- The `ram_ship` evidence the swap rests on all re-checked and correct: `ram_ship.gd:19`
  (`collision_mask = 33`), `ram_ship.gd:16-17` (only `movement_speed` applied),
  `ram_config.tres:8` (`max_health = 999`, dead), `bullet.tscn:44` (`collision_layer = 64`).
  Rejected-alternative 5 is a fair statement of the counter-case.

### B2 — RESOLVED. The "Scoring and combo" section is accurate and test 17's arithmetic is right.

Every step of the chain re-read in `assault/scenes/systems/score_tracker/score_tracker.gd`:
`:74-75` connects `EventBus.enemy_spawned_orphan`, `:89-90` routes to `_on_enemy_spawned(enemy, -1)`,
`:161-164` connects `tree_exited -> _on_enemy_freed` unconditionally, `:211` applies
`_combo *= score_config.escape_combo_multiplier` **outside** the `if counts_in_wave:` block at
`:205-209`, and `:212-213` floors at 1.0. **`combo_changed` is emitted on the escape path** —
`:215`, so test 17's premise is sound.
`global/resources/score_config_default.tres:11` is `escape_combo_multiplier = 0.75`; `4.0 * 0.75 *
0.75 = 2.25`, above the 1.0 floor, so the assertion is exact and not clamped. The decision to
register anyway is argued with both sides and routed to the backlog — that satisfies what round 1
asked for.

### B3 — RESOLVED. Half-extent 37 and the 777/397 margins re-derive correctly.

`assault/scenes/enemies/interceptor/interceptor.tscn:58-60` — `Sprite2D`, no `scale`;
`:62-64` — the `1.8` is the sibling `CollisionShape2D` over a radius-14 circle. PNG header of
`assault/assets/sprites/enemies/interceptor.png` reads **64x74**, so half-extent 37. ✓
`arena_camera.gd:35-39` gives `WORLD_SCALE 2.0`, `SCREEN_W 1280`, `SCREEN_H 720`, `H_LIMIT 100`,
`V_LIMIT 380`. `640 + 100 + 37 = 777`; `360 + 37 = 397`. ✓ The false "±420 was insufficient" claim
is gone and replaced with an honest "round number, 103 px of headroom".

**Test 4 is now non-vacuous** in the sense that matters: it is a constraint on future edits
(`abs(x)*2 > 777` fails at design ±380), and its constants are no longer fabricated. Its vertical
clause (`abs(y)*2 > 397`, i.e. `abs(y) > 198.5`) is only marginally stronger than test 3's
`abs(y) > 180` — that is a nit, not a defect.

### S1-S4 — all RESOLVED.

- **S1**: cap is now `skip the squad if _alive.size() + squad.size() > max`. With `max = 4` and
  2-ship squads the sequence is 2 → 4 → skip. Ceiling is exactly 4. Test 12 probes that boundary at
  the shipped value. ✓
- **S2**: `_on_timer_timeout()` is named, `one_shot = true`, and "`spawn_next_squad()` touches no
  timer at all" is stated explicitly with the reason (cases 10/11/12). ✓
- **S3**: test 15 is now reads of `Timer.one_shot` / `wait_time` / `is_stopped()`, no wall clock.
  `Timer.start(x)` does assign `wait_time`, so the assertion is well-formed. ✓
- **S4**: spot-checked six corrected citations, all now correct —
  `level_1_director.gd:110-144` (`_spawn_bonus_drone`, and `:125` really is a raw world-px
  `Vector2(-680, 60)`), `level_director.gd:116` (the `while container.get_child_count() > 0` poll),
  `station_gunnery.gd:64-73` (the conservative fallback block, comment at `:61-63`),
  `score_tracker.gd:74-75` + `:89-90`, `test_station_gunnery.gd:81-86` (`_bullets()`),
  `wave_manager.gd:159-205` (the model, incl. the `* ArenaCamera.WORLD_SCALE` at `:172` that
  `_spawn_bonus_drone` lacks). Also verified `wave_builder.gd:211-221`, `enemy_path_mover.gd:77`,
  `straight_movement.gd:2,13`, `arena_camera.gd:5-12`, `event_bus.gd:69`, `bullet_pool.gd:47`,
  `station_laser_phase.gd:123`, `level_1.tscn:22-26`, `space_station.gd:36`.

## New in Revision 2: sanity checks

- **Fighter squad geometry — clear, re-derived for the bigger sprite.** Round 1 verified hull
  clearance against `ram_ship`'s 32x32 sprite; the fighter uses
  `assault/assets/sprites/enemies/assault.png`, which is **64x64** (half-extent 16 design units), so
  the check needed redoing. `straight(170, 0.5)` gives `tan = 0.5463`; from design (-250, -290) the
  ship is at x = -175.7 when it reaches the hull's y = -154 and x = -105.8 at y = -26 (hull spans
  design x -64..64, y -154..-26, confirmed from `level_1_director.gd:225-227` and the 256x256
  `station_core.png`). Closest approach 41.8 design units against a 16-unit half-extent — **26 design
  units (52 world px) of gap.** Against the rotated hull (half-diagonal 90.5 design units) the
  perpendicular distance from the path line to the hull centre is 123.5 units, clear by 17. Mirrored
  on the right. Still clear.
- **`.shoot_forward()` × `EnemyPathMover` — no bad interaction.** Verified above at
  `aimed_attack_pattern.gd:28-31` and `enemy_path_mover.gd:80-87`. Also checked friendly fire:
  `enemy_bullet.tscn:22-23` is `collision_layer 256 / mask 128` (player HurtBox only) and the
  station's HurtBox is layer 512 (`space_station.tscn:72-74`), so fighter bullets cannot damage the
  boss. And bullets travel along the same ray as the ship, so they inherit the hull clearance.
- **Test 16 is implementable as written.** `hurt_box` is `@onready var hurt_box: HurtBox = $HurtBox`
  on `base_enemy.gd:7`, and all three squad scenes have a `HurtBox` child at that exact path
  (`light_assault_ship.tscn:81`, `interceptor.tscn:66`, `kamikaze_drone.tscn:34`). It **must** be in
  the tree for two independent reasons — the `@onready` resolution, and because the governing mask
  is written in `_ready()` (`base_enemy.gd:25`, and `ram_ship.gd:19` overriding it after
  `super._ready()`). The plan says exactly that. `1121 & 64 == 64` passes for the three chosen ships
  and `33 & 64 == 0` fails for `ram_ship`, so the assertion discriminates.

## Non-blocking findings (fix while implementing)

### N1. The plan's evidence for "the fighter is bullet-killable" is a line that does not govern runtime.

`3-plan.md:102-103` cites `light_assault_ship.tscn:83` (`collision_mask = 65`). That authored value
is **overwritten** on the first frame: `assault/scenes/enemies/base_enemy.gd:25` sets
`hurt_box.collision_mask = 97 | 1024` (= 1121) for every `BaseEnemy` before any subclass runs. The
conclusion is right — 1121 includes 64 — but the correct citation is `base_enemy.gd:25`, with
`ram_ship.gd:19` as the one subclass that narrows it afterwards. This is the same class of
scene-line misreading round 1 caught, and it is exactly the sentence that carries the B1 fix. Cite
`base_enemy.gd:25`.

### N2. Test 10's `_timer.is_stopped()` clause is vacuous under the stated harness.

`3-plan.md:258-259` says the reinforcement `Timer` is "stopped in `before_each` so every spawn is
forced". Test 10 (`3-plan.md:273`) then asserts `_timer.is_stopped()` after `armor_broken` — but it
is already stopped before the test does anything. The second clause ("a subsequent
`spawn_next_squad()` adds nothing") is the real assertion and carries the case. Fix: have test 10
call `_reinf._timer.start(...)` immediately before emitting `armor_broken`, so the stop is observed
rather than pre-supposed. `test_station_gunnery.gd:42-44` stops both timers in `before_each` and
notes "One test exercises the timers" — same shape.

### N3. Test 17 will fail intermittently unless it also disables `ScoreTracker._process`.

`score_tracker.gd:112-124`: while `_combo > 1.0`, `_process` decrements `_combo_decay_remaining`
every frame and, the moment it reaches 0, sets `_combo = 1.0` and emits `combo_changed(1.0, 0.0)`.
Forcing `_combo = 4.0` without also setting `_combo_decay_remaining` leaves it at its default 0.0,
so the very next processed frame resets the combo to 1.0 — and `start_tracking()`
(`score_tracker.gd:55-57`) turns `_process` on. This repo already documents the trap and its remedy:
`tests/integration/test_station_assault_section.gd:142-147` calls `tracker.set_process(false)` with
a comment, and then asserts on `tracker.get("_combo")` (`:162-163`) rather than on the last
`combo_changed` payload. Test 17 should say it does both. As written the case is meaningful and can
fail for the right reason; it just also fails for the wrong one.

### N4. The Risks section understates the top squad's fire rate after the B1 swap.

`3-plan.md:284-287` notes the top squad "now shoot" but gives no numbers, and a reader will assume
`fighter_config.tres:11`'s `fire_interval = 0.8` / the 250 px/s default. `light_assault_ship.gd:42`
and `:44` special-case FORWARD mode: `fire_interval = 0.3` and `bullet_speed = 420.0`. Two fighters
therefore add ~6.7 bullets/s at 420 px/s — comparable to the entire four-turret fan (6.7 bullets/s
at 240 px/s, `space_station_config.gd:62-65`) — for the ~3.3 s of their transit. That may well be
fine, and the cap plus the phase gate bound it, but the density risk should carry the real figure
since the B1 swap is what introduced it. `3-plan.md:104-106`'s "does not pile a *third* source of
*aimed* fire" is true and is not the point.

### Nits

- `3-plan.md:107` cites `docs/enemy-roster.md:76` for "the roster's own example"; line 76 is blank,
  the example is `docs/enemy-roster.md:78`.
- `3-plan.md:104` cites `light_assault_ship.gd:33-42` for firing along travel. Those lines resolve
  `aim_mode` and build the pattern; the actual "fire along `ship.rotation`" is
  `global/resources/attack/aimed_attack_pattern.gd:28-31`. Worth citing both.
- `3-plan.md:136` lists `_spawn_entry` step 6 as attaching a mover with `movement` / `exit_mode` /
  `exit_time` only. `wave_manager.gd:201-204` also copies `look_in_moving_direction` and
  `look_angle`. The defaults (`true` / `0.0`) are what `.shoot_forward()` needs, so nothing breaks —
  but carry them anyway so the entry stays the single source of truth.
- Test 4's vertical clause (`abs(y)*2 > 397`) barely exceeds test 3's (`abs(y) > 180`). Harmless.
- Test 16 iterates only the squad table, so "it fails today for `ram_ship`" is a counterfactual, not
  an executed assertion. It is still a real guard against a future swap; just do not describe it as
  currently exercising the ram case.

## Standard gate

- **Reinvention:** none. `global/components/` has no spawner (listed and checked); nothing else in
  the repo spawns ad-hoc except `big_asteroid.gd:77` and `level_1_director.gd:110-144`, both of which
  the plan cites as precedent rather than duplicating. Rejected alternative 3 correctly declines to
  build a generic component for one caller.
- **Conventions:** composition (a fourth sibling behaviour node, `space_station.gd` gains nothing) ✓;
  config-driven `.tres` with read-once-and-copy and deliberately different node defaults, matching
  `station_gunnery.gd:55-73` ✓; 640x360 design units scaled by `ArenaCamera.WORLD_SCALE` at spawn,
  never pre-multiplied, with speeds left unscaled because `enemy_path_mover.gd:77` applies the scale ✓;
  zero-arg `died` / `armor_broken` handlers ✓ (`base_enemy.gd:4`, `space_station.gd:34`).
- **Test plan:** read `tests/README.md` first. The file lands in the space-station family, so
  intent-asserting is correct (`tests/README.md:33-38`). No case waits on a wall clock; the
  `LevelDirector` coroutine-leak trap (`:47-53`) does not apply; the `ExplosionEffect`-parents-to-
  container trap (`:127-141`) is acknowledged in Risks and the container-child filter is cited at
  `test_station_gunnery.gd:81-86`; the `station.config` shared-instance trap (`:122-126`) is
  explicitly forbidden in the harness. Cases 4, 12, 15, 16 and 17 all discriminate; see N2 and N3
  for the two that need a mechanical tweak.
- **Simpler unexamined alternative:** I looked for one and did not find a better option. The nearest
  is "make `WaveManager._spawn_ship` public and call it", which would couple the boss node to a
  `WaveManager` reference it has no other reason to hold and would inherit the
  `wave_manager.gd:160-162` no-camera return that the plan deliberately diverges from. ~15 lines of
  duplication against the cited model is the right trade.
- **Research:** five findings, each with a tradeoff column; F1's unreachable source is honestly
  flagged and used only for direction. Round 1 verified the sources; B3 was the only measurement
  error and it is fixed. `2-research.md:34` still needs the same 67 -> 37 correction the plan already
  made — the build sequence should include it, since round 1 asked for both documents.
- **Scope:** 2 code files + 1 scene + 1 test file + docs. One session, comparable to 4a.
