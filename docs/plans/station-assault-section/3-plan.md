# `station_assault` — the station encounter blocks Level 1 progress (EPIC sub-item 2)

Builds on `1-context.md` (files, the 10 s discovery, the delayed-spawn trap) and `2-research.md`
(boss gating, boss timers, the arrival beat). Neither is re-derived here.

> **Revision 1 (2026-09-01)** — rewritten after review round 1 (`VERDICT: CHANGES_REQUESTED`).
> Its headline change was a new **§0** claiming the gate was unsatisfiable.
>
> **Revision 2 (2026-09-01)** — after review round 2 (`VERDICT: APPROVED`, with three mandatory
> adjustments). Round 2 **withdrew** round 1's B1: the premise was false, `BulletPool` is not on
> the player's fire path, and the turrets were reachable all along. §0 is withdrawn with it and
> the core hurtbox is **not** touched by this sub-item. The scope is now the six changes in
> *Design* and tests 4-10. See *Revision log*.

## Problem

Level 1 runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent. Sub-item 1 built the
station mini-boss entity, but nothing in the level ever spawns it — a player finishing the
asteroid belt drifts straight into the planet approach. It should instead meet the station, and
the level should refuse to continue until the station is destroyed.

Two things stop that working today. Both are in `LevelDirector`, not in the entity.

- `LevelDirector._wait_enemies_cleared()` (`level_director.gd:105`, deadline at `:108`) abandons
  the wait after a hardcoded **10 s**. Research finding 3: the shortest boss timer found in a
  shipped game is **180 s** (G-Darius). Worse, the clock starts on `WaveManager.waves_complete`,
  which fires when the last wave *triggers* (`wave_manager.gd:52-56`), so a one-wave boss section
  starts its countdown on frame one.
- On timeout the director advances with the boss still parented to `enemy_container`
  (`push_warning` at `level_director.gd:112`). The station has no `EnemyPathMover`, so nothing
  will ever free it — it hangs on screen through `planet_approach` and `cloud_descent`, and
  (since `_wait_enemies_cleared` polls that same container) it would then block `cloud_descent`
  forever. Research finding 2: no shipped shmup does this. A timed-out boss **escapes or
  self-destructs** — the fight always actually ends.

A third problem was believed to exist and does not; §0 records why, because it was asserted twice
and must not be asserted a third time.

## §0 (WITHDRAWN in revision 2) — the turrets were always reachable

**Revision 1 was wrong here, and so was review round 1's B1.** Both argued that a default-loadout
bullet is consumed by the first HurtBox it overlaps, so the 240 x 240 core hurtbox
(`space_station.tscn:16-17`, shared by the body collider `:65-66` and the core HurtBox `:74-75`)
shadowed all four turrets and made `ENEMIES_CLEARED` unsatisfiable. The chain cited
`bullet_pool.gd:56` as the thing that recycles the bullet on `expired`.

**`BulletPool` is never used by the player.** Re-verified independently against the code before
accepting the reversal:

- The player's fire path is `player_fighter.tscn:351` -> `weapon_state.gd:83` ->
  `straight_behavior.gd:22`, which is a plain `state.add_child(bullet)`. No pool, no `expired`
  connection. `spread_behavior.gd:21` and `long_range_behavior.gd:38` are the same.
- `grep -rn "expired" --include=*.gd --include=*.tscn .` finds exactly **two** connections to
  `Bullet.expired` in the repo: `bullet_pool.gd:56` and `sniper_enemy.gd:102`. `BulletPool` is
  constructed only in `light_assault_ship.gd:27`, `gunship.gd:52`, `interceptor.gd:30` and
  `ally_fighter.gd:22` - four enemies and the ally, never the player.
- `bullet.gd:84` emits `expired` **without** `queue_free()`. The script's only `queue_free()` is
  `:49`, gated on `range_px > 0.0`, and `assault/scenes/player/weapons/modes/default.tres` sets
  `range_px = 0.0`.

So on the default loadout `expired` has no listener and the bullet keeps flying with a live
HitBox. The layers let it reach everything in its lane: core and turret HurtBoxes are all
`collision_layer = 512`, the bullet HitBox masks `513` (`bullet.tscn:44-45`), and the 240 x 240
contact HitBox is `layer 256 / mask 0` (`base_enemy.gd:54-55`), invisible to both.

**Today, unmodified:** a bullet fired up the x = -76 lane crosses the armoured core box (deflected,
`space_station.gd:82-86`), continues, deals 50 to `Turret2`, continues, deals 50 to `Turret0`.
Turrets are 120 HP and bullets 50 damage, so **three bullets down one lane kill both turrets in
it.** The gate is satisfiable by a default-loadout player right now, and this sub-item does not
need to change the entity at all.

### Consequence: the core hurtbox is not touched this cycle

Narrowing the core HurtBox to 88 x 240 would be a **design change** ("shooting the hull shoulders
should not deflect off the core"), not a bug fix, and revision 1's justification for it does not
survive. It is deferred out of this sub-item and filed under *Discovered* in `BACKLOG.md` for the
user to triage. The precision argument was moot in play anyway: `default.tres` sets
`pellet_spread_deg = 60.0` and `straight_behavior.gd:13-16` applies a +/-30 degree per-shot jitter,
so "6 px of margin either side" is not a quantity the player ever experiences.

Tests 1-3 go with it. Tests 2 and 3 asserted a fiction - they wired `expired` -> free "exactly as
`bullet_pool.gd:56` does", which is precisely the lifecycle the player path does **not** have.
`space_station.tscn` is therefore **not modified by this sub-item**, so `test_space_station.gd`'s
nine tests and `ENEMY.md`'s hurtbox description both stand unchanged.
## Design

Six changes. Nothing new is invented: the gate is the existing `EndCondition.ENEMIES_CLEARED`, the
entity is sub-item 1's scene, and the spawn goes through `WaveManager` like every other enemy.

### 1. `LevelSection` gains a per-section timeout — `level_section.gd`

```gdscript
## Safety net for ENEMIES_CLEARED: seconds to wait for the container to empty
## before giving up. Sized for "wait for stragglers to leave" (10 s) by default;
## boss sections need far longer. Ignored by the other end conditions.
@export var enemies_cleared_timeout: float = 10.0
```

The default is **exactly today's constant**, so `cloud_descent` — the only shipped
`ENEMIES_CLEARED` section (`level_1_director.gd:758-763`) — is bit-identical. A test pins the
default so a future edit to it is deliberate.

*Rejected:* raising the global constant. It would silently change `cloud_descent`, whose 10 s is
correctly sized for its actual job.

### 2. `LevelDirector._wait_enemies_cleared()` reads it, and clears leftovers on expiry

`deadline_ms` (`level_director.gd:108`) becomes
`start_ms + int(section.enemies_cleared_timeout * 1000.0)`. The method takes **no arguments** — it
is connected as a zero-arg one-shot at `level_director.gd:78` — so `section` must be read from
`_sections[_current_index]` behind an index bounds guard (review, non-blocking note). On expiry,
after the existing `push_warning` (`:112`), **free every remaining child of `enemy_container`**
before advancing:

```gdscript
push_warning(...)
## The container is not enemies-only: bullet_pool.gd:45-47 reparents in-flight
## bullets to get_parent().get_parent(), which for an enemy ship is this
## container. Freeing them here is safe — bullet_pool.gd:98-100 already frees
## in-flight bullets when the owning ship exits, and _recycle guards re-entry.
for child in container.get_children():
    child.queue_free()
break
```

This is research option (b) — the genre behaviour (finding 2: the boss is removed, the fight
ends). It closes "boss survives into the next section" directly rather than making it unlikely.

**Score consequences (corrected — review B3).** `queue_free()` does not emit `died`, so
`was_killed` stays false and `ScoreTracker._on_enemy_freed` (`score_tracker.gd:197-215`) takes its
**escape** path on `tree_exited`, for each freed child:

- `:206-209` — marks that wave's tally `escaped = true, resolved = true`;
- `:211-215` — multiplies `_combo` by `escape_combo_multiplier` = **0.75**
  (`score_config_default.tres:11`) and emits `combo_changed`.

So the earlier claim of "no score impact" was wrong. `_total_score` is unchanged at that instant,
but the combo is cut to 75 % **for the rest of the level** and the HUD combo bar visibly moves. In
`cloud_descent` the practical effect is nil (the level ends 0.2 s later and `stop_tracking()`
would mark the tally escaped anyway, `score_tracker.gd:92-100`). This is accepted as the correct
behaviour — letting a boss time out *should* cost the player something, which is exactly the
penalty research finding 2 describes — and is pinned by test 6 rather than left implicit.

*Scope of the behaviour change:* the free-loop runs only after `push_warning`, i.e. only on a path
that today already logged a failure; on the normal path the loop exits before the deadline and the
new code never runs. Tests 6 and 7 separate the two paths.

*Rejected:* an infinite wait (`timeout <= 0` means never give up). Genre-correct on paper, but it
turns any bug that leaves an unkillable enemy in the container into a hard softlock with no
diagnostic, and it would hang a headless run forever.

### 3. `WaveBuilder` learns the station — `wave_builder.gd`

```gdscript
const SPACE_STATION := "res://assault/scenes/enemies/space_station/space_station.tscn"
func space_station() -> SpawnConfig: return SpawnConfig.new(SPACE_STATION)
```

Mechanical, matching the other 14 constructors (`:78-91`, `:229-242`).

### 4. `phases/phase_station_assault.tres`

`BackgroundPhase` defaults *are* the deep-space look (`background_phase.gd:17-38`) — which is why
`phase_asteroid_belt.tres` sets only two properties. So the new phase needs only its name plus an
explicit hand-off of the asteroids:

```
phase_name = &"station_assault"
asteroids_back_enter = false
asteroids_front_enter = false
```

`transition_in_duration = 2.0` (the `cloud_descent` value) so the belt clears as the station
arrives.

### 5. `Level1Director` — the section, and a testable section list

**Refactor (small, required by the test plan):** `_ready()` currently builds and adds the sections
inline (`level_1_director.gd:38-46`). Extract that into

```gdscript
func _build_sections() -> Array[LevelSection]:
    var out: Array[LevelSection] = []
    out.assign([_build_section_1(), _build_section_asteroid(), _build_station_assault(),
                _build_section_2(), _build_section_3()])
    return out
```

and have `_ready()` loop `director.add_section(s)` over it. (`.assign()` rather than returning a
literal, matching the house style the existing builders use for `s.waves`.) Review verified that
**every** `_build_*` body touches only `LevelSection.new()`, `preload` and `WaveBuilder.new()` —
no `@export`, `@onready`, `get_tree`, `get_node` or `add_child` appears anywhere in
`level_1_director.gd:203-954`; the only matches are in `_on_level_complete` at `:955+`. So
`_build_sections()` is callable on a bare script instance that has never entered the tree, which
is what makes section **order** testable without booting the HUD, ScoreTracker and debrief.

The script has **no `class_name`** (`level_1_director.gd:10` is a bare `extends Node`), so the
test must `load("res://assault/scenes/levels/edelia/1/level_1_director.gd").new()` and `autofree()`
the result or GUT reports an orphan.

**The section itself:**

```gdscript
func _build_station_assault() -> LevelSection:
    var s := LevelSection.new()
    s.section_name             = &"station_assault"
    s.background_phase         = preload(".../phases/phase_station_assault.tres")
    s.transition_in_duration   = 2.0
    s.end_condition            = LevelSection.EndCondition.ENEMIES_CLEARED
    s.duration                 = 0.0
    s.enemies_cleared_timeout  = 180.0
    var b := WaveBuilder.new()
    s.waves.assign([ b.wave(0.0, [ b.space_station().at(0, -90) ]) ])
    return s
```

Three details that are each load-bearing:

- **No `.delay()`.** `1-context.md`'s second discovery: `_trigger_wave` (`wave_manager.gd:115-125`)
  does not await `_spawn_with_delay` (`:151-155`), and `waves_complete` fires immediately after the
  last wave triggers (`:52-56`), so a delayed spawn lets `_wait_enemies_cleared` see an **empty**
  container and advance instantly. `delay == 0.0` makes the station a child before
  `waves_complete` is emitted in the same frame. Pinned by test 10.
- **No `.move()`.** `WaveManager` attaches an `EnemyPathMover` only when `movement` is a real
  `MovementResource` (`wave_manager.gd:194`). Without one the station is stationary — the
  R-Type-stage-3 form of research finding 6 — and, critically, is never auto-freed by an exit
  mode. The only thing that removes it is dying.
- **`180.0`** — research finding 2's genre floor (G-Darius normal boss). Finding 5 sizes the actual
  fight at 30–60 s (proportional to Level 1's 30/30/110 s sections), so 180 s is a net a competent
  player never touches, not a balance knob.

**Placement arithmetic.** `at()` is in **640×360 design units**, multiplied by
`ArenaCamera.WORLD_SCALE = 2.0` in `wave_manager.gd:172`, and `ArenaCamera.global_position` is
pinned at the level origin (`arena_camera.gd:5-13`; confirmed by `level_1.tscn:18-20`,
`position = Vector2(640, 360)`) so the offset resolves from a fixed screen centre.

| Quantity | Value |
|---|---|
| Station sprite, authored at final on-screen px (`space_station.tscn`, `scale = 1`) | 256 × 256 world px = **128 × 128 design units** |
| Screen | 1280 × 720 world px; design y on screen ∈ [−180, +180] |
| Chosen offset | `at(0, -90)` → world `(640, 360) + (0, −180)` = `(640, 180)` |
| Station occupies | world y **52 → 308** (top 43 % of the screen), x 512 → 768 |
| Free space below it | world y 308 → 720 = **412 px ≈ 6.4 player heights** (player is 64 px) |

Nothing is pre-multiplied. **Caveat (review):** these numbers describe the frame at
`Camera2D.offset == 0`. The camera pans ±380 px vertically (`arena_camera.gd:39, 84-90`) and the
player clamps to world y ∈ [−380, 1100] (`player_fighter.gd:99-100`), so a player who dives to the
bottom of the play area pushes the station off the top of the screen. Cosmetic, accepted, and a
candidate follow-up for sub-item 3 when the laser phase gives a reason to constrain the camera.

**The "boss arrives" hook (research finding 4): reserve nothing — it already exists.**
`LevelDirector.section_started(index, section_name)` fires on every section start
(`level_director.gd:60`) and `Level1Director._on_section_started` already listens (`:104-106`). A
warning siren in a later sub-item hangs off `section_name == &"station_assault"`. A second,
boss-specific signal would be speculative scope with no consumer.

**Not touched:** `_section_schedules` gets no `station_assault` entry. `_process` already handles a
missing key via `.get(name, [])` (`:89`). Reinforcements are sub-item 4.

### 6. Docs (review S3) — four shipped statements become false

`CLAUDE.md` mandates the `updating-project-docs` skill after a structural change; this adds an
entity spawn path, a `LevelSection` and a `BackgroundPhase`. These four must be corrected:

| File | Currently says |
|---|---|
| `docs/enemy-roster.md:487-492` | the station "has no builder method and appears in no level yet" |
| `docs/architecture/modules/assault.md:184-193` | "it builds and adds **four** sections… The four sections are:" (list of 4) |
| `docs/architecture/modules/assault.md:229-236` | the station "is **not yet spawned by anything**" |
| `assault/scenes/enemies/space_station/ENEMY.md:139-141` | "**Not spawnable yet.**" |

`ENEMY.md`'s *Known gap* and hurtbox description are **unchanged** (review M1): this sub-item
does not modify `space_station.tscn`. `BACKLOG.md`'s sub-item 1 *Known gap* note likewise stands —
the collision-layer coverage gap it records is real and is not closed here.

## Build sequence

Six steps plus the gate check. §0 and tests 1-3 are **withdrawn** (see §0); test numbering below
keeps its original 4-10 so the round-2 review's references stay resolvable.

1. `LevelSection.enemies_cleared_timeout` export. → test 4 passes.
2. `LevelDirector` reads it + frees leftovers on expiry. → tests 5, 6, 7 pass.
3. `WaveBuilder.SPACE_STATION` + `space_station()`.
4. `phase_station_assault.tres` — **three lines only** (review M3): `BackgroundPhase` has no
   `transition_in_duration` property (`background_phase.gd:12-81`); that is a `LevelSection` field
   (`level_section.gd:19`) and is set in `_build_station_assault()`. Writing it into the `.tres`
   would produce an unknown-property resource.
5. `Level1Director._build_sections()` refactor + `_build_station_assault()`. → tests 8, 9, 10 pass.
6. Docs per §6, then `bash /agent/verify.sh`.
7. **Gate check (review S2):** the suite has **18** `test_*.gd` scripts today (15 `unit/`,
   3 `integration/`), so GUT must report **19** after this. Also grep the step-3 output for
   `Parse Error` and `SCRIPT ERROR` — `BACKLOG.md` records that GUT silently drops an unloadable
   script and still exits 0, and that channel matters here because tests 4 and 8-10 "fail before
   implementation" by making the file **unparseable**
   (`LevelSection.new().enemies_cleared_timeout` on a statically-typed `LevelSection` is a parse
   error, not an assertion failure). Red-before-green for four of seven tests is read off stderr.

Steps 1-2 are the only ones that touch shipped behaviour. `space_station.tscn` is not touched at
all.

## Test plan

One new file, `tests/integration/test_station_assault_section.gd`, seven tests. Director tests
build a `LevelDirector` + `WaveManager` + a `Node2D` container by hand — no camera, no level
scene — and drive it by emitting `wave_manager.waves_complete` and freeing container children.

| # | Test | Asserts | Fails before implementation because |
|---|---|---|---|
| 4 | `test_enemies_cleared_timeout_defaults_to_ten_seconds` | `LevelSection.new().enemies_cleared_timeout == 10.0` | property does not exist → parse error |
| 5 | `test_section_does_not_advance_while_an_enemy_lives` | 2 sections, timeout 30 s, one live child; emit `waves_complete`; after ~0.5 s of frames `section_started` has fired **only** for index 0 | — (guards the gate) |
| 6 | `test_section_advances_when_the_last_enemy_is_freed` | as 5, then `queue_free()` the child → `section_started` fires with index 1 | — (guards the gate) |
| 7 | **Boundary —** `test_timeout_frees_leftover_enemies_then_advances` | timeout `0.3`, a child that never dies → director advances, `enemy_container.get_child_count() == 0`, **and** the escape-combo penalty fired | today it advances with the child still parented — this is the bug |
| 8 | `test_level_1_sections_are_in_order_with_station_assault_third` | `_build_sections()` on a bare `Level1Director` instance → `[deep_space, asteroid_belt, station_assault, planet_approach, cloud_descent]` | section does not exist |
| 9 | `test_station_assault_is_enemies_cleared_with_a_long_timeout` | `end_condition == ENEMIES_CLEARED`, `enemies_cleared_timeout >= 60.0`, and `cloud_descent`'s is still exactly `10.0` | section does not exist |
| 10 | `test_station_assault_spawns_one_station_at_zero_delay_with_no_movement` | 1 wave, `trigger_time == 0.0`, 1 entry; `ship_scene.resource_path` ends `space_station.tscn`; `spawn_delay == 0.0`; `movement == null` | section does not exist; also pins the two traps from `1-context.md` |

**Timing budget (review S1).** `level_director.gd:110-116` re-checks the deadline only *after*
`await _wait_for_child_exit_or_timeout(container, 1.0)` returns, and with no `child_exiting_tree`
that helper always burns its full **1.0 s** poll (`:85-102`). So a 0.3 s timeout actually expires
at ≈1.0 s and `_advance()` runs after the further 0.2 s settle (`:122`) — ≈**1.2 s**. Test 7 must
observe for **≥1.8 s** and its comment must state the poll granularity. Test 6 is unaffected: a
freed child fires `child_exiting_tree`, the helper returns early, and the director advances at
≈0.3 s.

**Test 7's score assertion (review M2).** Two traps, both verified:

- `score_tracker.gd:31` starts `_combo` at `1.0`, and `:211-214` multiplies by `0.75` then clamps
  back up with `if _combo < 1.0: _combo = 1.0`. From the default the penalty is **invisible**. The
  test must pre-set `_combo` above `1 / 0.75 ≈ 1.334` (use `2.0` → expect `1.5`).
- `_on_enemy_freed` is connected **only** inside `_on_enemy_spawned` (`score_tracker.gd:161-164`),
  which is driven by `wave_manager.enemy_spawned` (`:59-60`). The camera-less harness never
  reaches `_spawn_ship` (`wave_manager.gd:160-162`), so the leftover child must be added by hand
  **and** `wave_manager.enemy_spawned.emit(child, 0)` emitted by hand after `start_tracking()`.

Use a locally constructed `ScoreTracker`, not the shipped one, so nothing leaks between tests.

Other gotchas (`tests/README.md`): no zero-parameter handlers on `Health.amount_changed`;
`push_warning` is not a GUT failure (`tests/README.md:72`) so the timeout tests will not trip on
the existing warning; nothing here touches `user://`, so no `SaveSandbox`.

## Risks

| Risk | Check |
|---|---|
| The `space_station.tscn` entity is modified | It is not. §0 is withdrawn; sub-item 1's 9 tests must still pass unchanged, which the gate checks. |
| Freeing leftovers on timeout changes `cloud_descent` | Runs only after `push_warning`. Tests 6 and 7 separate the paths; the ×0.75 combo penalty is now asserted rather than denied. |
| `_wait_enemies_cleared` is `await`-heavy; tests may be timing-flaky | Budgets sized off the real 1.0 s poll granularity (see above); assertions are on the `section_started` signal, not wall-clock. |
| The `_build_sections()` refactor breaks Level 1 boot | `verify.sh` step 2 boots the main scene headless; test 8 pins the order. Nothing hardcodes a section count — `LevelDirector` reads `_sections.size()`, and `section_started`'s only consumer ignores the index (`level_1_director.gd:78, :104`). |
| Station sits somewhere unplayable | Arithmetic tabled above and verified in review; the pan caveat is stated. Static placement in a section with no other spawns, so worst case is a cosmetic follow-up. |
| GUT silently drops the new test file if it fails to parse | Build step 7: assert 19 scripts **and** grep for `Parse Error` / `SCRIPT ERROR`. |

## Out of scope

Sub-items 3–5: the laser phase, bullet-hell patterns, reinforcement waves, and the destruction
hand-off. The "WARNING" arrival presentation (research finding 4) — the hook is identified, not
built. Station balance (`space_station_config.tres` untouched). Constraining the camera pan during
the boss (noted above; belongs with sub-item 3). Everything in `BACKLOG.md`'s *Discovered* list,
including the `base_enemy.gd:56` contact-hitbox scale bug, which `space_station.tscn` already
sidesteps.

## Revision log

**Round 1 → Revision 1**, addressing `4-review.md`:

| Finding | Resolution |
|---|---|
| **B1** gate unsatisfiable — core hurtbox shadows all turrets | Accepted after independent re-verification. New **§0**: dedicated 88 × 240 core-hurtbox shape, with the x-extent disjointness argument, plus tests 1–3 and build step 1. |
| **B2** test 4 reproduced the coverage gap it claimed to close | Accepted. The signal-emit test is gone; replaced by a geometric invariant (test 1) and two real-projectile tests (2, 3), with a documented fallback. |
| **B3** "no score impact" is wrong | Accepted and corrected: ×0.75 escape-combo penalty per leftover plus tally marked escaped, cited to `score_tracker.gd:197-215`, now **asserted** by test 7 and justified as the genre-correct cost. |
| **S1** test-5 timing budget impossible | Accepted. Poll granularity documented; the timeout test observes ≥1.8 s. |
| **S2** script-count check said 4, should be 19 | Accepted. Build step 8 now says 19 and adds the `Parse Error` / `SCRIPT ERROR` grep, with the reason it matters. |
| **S3** four shipped docs will be contradicted | Accepted. New §6 names all four plus `ENEMY.md`'s hurtbox description and `BACKLOG.md`'s *Known gap*. |
| **S4** six drifted line citations | Accepted; all six corrected throughout. |
| Note: `1-context.md` wrongly implies turrets `queue_free()` | Noted — `StationTurret._destroy()` (`station_turret.gd:62-83`) deliberately leaves wreckage in the tree. Only the core frees itself (`base_enemy.gd:65-73`); the gate depends on the **core**, and tests 1–3 and 7 are written to that truth. |
| Note: the timeout free-loop can hit pooled bullets | Accepted; the loop carries a comment explaining `bullet_pool.gd:45-47` reparenting. |

**Round 2 → Revision 2**, addressing `4-review.md`'s `VERDICT: APPROVED` with three mandatory
adjustments:

| Finding | Resolution |
|---|---|
| **M1** §0's premise is false; round 1's B1 was wrong | Accepted after re-verifying the fire path directly: `BulletPool` is constructed only by four enemies and the ally fighter, `Bullet.expired` has exactly two listeners repo-wide (neither on the player path), and `default.tres` sets `range_px = 0.0` so `bullet.gd:49` never frees. §0 is **withdrawn** and rewritten as a record of the error; build step 1 and tests 1-3 are deleted; `space_station.tscn` is untouched. The 88 x 240 hurtbox is filed under *Discovered* in `BACKLOG.md` as a design question for the user. |
| **M2** test 7's combo assertion cannot pass as written | Accepted. Test 7 now pre-sets `_combo = 2.0` (above the `1/0.75` clamp floor) and emits `wave_manager.enemy_spawned` by hand after `start_tracking()`, because `_on_enemy_freed` is only ever connected from `_on_enemy_spawned` and the camera-less harness never reaches `_spawn_ship`. Uses a locally constructed `ScoreTracker`. |
| **M3** `transition_in_duration` is not a `BackgroundPhase` field | Accepted. The `.tres` is three lines; the duration is set on the `LevelSection` in `_build_station_assault()`. |
| Non-blocking: `bullet.tscn` path | Real path is `assault/scenes/projectiles/bullets/bullet.tscn`; corrected in §0. |
| Non-blocking: `_wait_enemies_cleared` is zero-arg | Noted in §2 — read `_sections[_current_index]` with a bounds guard. |
| Non-blocking: turret hurtbox teardown is `set_deferred` | Moot; no test in the revised plan kills a turret and then fires through it. |
| Non-blocking: `phase_name` has one consumer (a `print`) | No registry to update for the new phase. |
