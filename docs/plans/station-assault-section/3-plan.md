# `station_assault` — the station encounter blocks Level 1 progress (EPIC sub-item 2)

Builds on `1-context.md` (files, the 10 s discovery, the delayed-spawn trap) and `2-research.md`
(boss gating, boss timers, the arrival beat). Neither is re-derived here.

> **Revision 1 (2026-09-01)** — rewritten after review round 1
> (`4-review.md`, `VERDICT: CHANGES_REQUESTED`). All seven findings were independently
> re-verified against the code before being accepted; none was disputed. Changes are listed in
> *Revision log* at the foot of this file. The headline change is new **§0**: the gate as
> originally planned was **unsatisfiable** — a default-loadout bullet cannot reach a single
> turret.

## Problem

Level 1 runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent. Sub-item 1 built the
station mini-boss entity, but nothing in the level ever spawns it — a player finishing the
asteroid belt drifts straight into the planet approach. It should instead meet the station, and
the level should refuse to continue until the station is destroyed.

Three things stop that working today. The third was found in review and is the important one.

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
- **The station's core hurtbox shadows all four turrets, so the player cannot damage them.**
  See §0.

## §0 (new, blocking) — make the turrets reachable

`space_station.tscn:16-17` declares one `RectangleShape2D` of **240 × 240** and uses it for
*both* the body collider (`:65-66`) and the core `HurtBox` (`:74-75`). The core hurtbox therefore
spans local x, y ∈ **[−120, +120]** — the entire hull. The four turret hurtboxes are
`CircleShape2D` radius **26** at (±76, ±76) (`space_station.tscn:89-99`, `station_turret.tscn:8-9`),
so each one lies **strictly inside** the core box.

Both are on `collision_layer = 512`; the player bullet's HitBox is `collision_layer = 64,
collision_mask = 513` (`bullet.tscn:44-45`), so it detects the core box first. With
`pierces_remaining == 0` and `unlimited_pierce == false` — the default: `player_base.gd:42`
leaves `pierce_module_active` false, `straight_behavior.gd:20-21` only sets pierces when it is on,
and `modes/default.tres` is straight/no-pierce — `bullet.gd:83-84` emits `expired` on the first
`area_entered`, and `bullet_pool.gd:56` recycles the bullet on the deferred flush that step.

An upward bullet therefore enters the core box at local y = +120 and dies there. The **top** pair
of turrets is 222 px further along and is unreachable; the bottom pair is 18 px further along at
15 px/frame (900 px/s ÷ 60), so it is at best intermittent and frame-rate dependent. The two
direct-emit damage paths do not help: `plasma_nova_module.gd` / `beam_behavior.gd` emit over group
`"enemies"`, which only `SpaceStation` joins (`space_station.gd:35`) — `StationTurret` is a plain
`Node2D` in no group — so they hit the armoured core and are deflected (`space_station.gd:82-86`).

`live_turret_count() > 0` would stay true forever, the core would stay armoured, the station would
never free itself, and `ENEMIES_CLEARED` would degrade to "wait 180 s, then the new free-loop
deletes the boss" **on every playthrough**. That is precisely the outcome research finding 1 warns
against ("hard gating is only safe if the player can always eventually win"), shipped as the
default rather than as an edge case.

### The fix: give the core hurtbox its own, narrower shape

Only the `HurtBox`'s shape changes. The body `CollisionShape2D` stays **240 × 240** — it is what
`BaseEnemy._add_contact_hitbox()` (`base_enemy.gd:50-59`) copies into the 40-damage contact HitBox,
and the hull really is that big.

```
[sub_resource type="RectangleShape2D" id="RectangleShape2D_core_hurt"]
size = Vector2(88, 240)
```

used by `HurtBox/CollisionShape2D` only.

**Why these numbers.** All player fire in this mode travels along ±y, so the condition for "no
turret is shadowed" is that the core hurtbox's **x-extent is disjoint from every turret's
x-extent**:

| Shape | Local x-extent |
|---|---|
| Turret hurtboxes (x = ±76, r = 26) | [50, 102] and [−102, −50] |
| Core hurtbox, 88 wide | **[−44, +44]** |

Disjoint, with 6 px of margin either side. Full hull height (240) keeps the core easy to hit down
the centre line once it is exposed, so shrinking the width costs the player nothing on the phase
that matters. Two narrow dead lanes appear at |x| ∈ (44, 50) and the hull shoulders at
|x| ∈ (102, 120) stop hitting anything — normal for a multi-part boss, and it is what makes
"shoot the guns, then the core" legible.

*Rejected:* (b) putting `StationTurret` in the `"enemies"` group so the AoE modules reach it —
that changes what every `get_nodes_in_group("enemies")` consumer sees (`ai_targeting_module.gd:49`,
`emp_blast_module.gd:39`, `warhead_missile_shooting_state.gd:61`, `beam_behavior.gd:75`) for a
`Node2D` that is not an enemy ship, and it still leaves the *default* weapon unable to hit a
turret. (c) Verifying by hand in-engine only — this container has no GUI, and the flaw survived
sub-item 1 precisely because nothing tested the collision path.

**This is arguably sub-item 1's bug**, but the gate is meaningless without it, so it lands here.
It is one sub-resource and one node property.

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
`start_ms + int(section.enemies_cleared_timeout * 1000.0)`. On expiry, after the existing
`push_warning` (`:112`), **free every remaining child of `enemy_container`** before advancing:

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

`ENEMY.md` also documents the 240×240 shared hurtbox shape and the collision-layer coverage gap;
both change under §0 and must be rewritten, along with the *Known gap* note in `BACKLOG.md`'s
sub-item 1 entry.

## Build sequence

1. **§0** — new `RectangleShape2D` (88 × 240) for the core `HurtBox` in `space_station.tscn`.
   → tests 1, 2, 3 pass.
2. `LevelSection.enemies_cleared_timeout` export. → test 4 passes.
3. `LevelDirector` reads it + frees leftovers on expiry. → tests 5, 6, 7 pass.
4. `WaveBuilder.SPACE_STATION` + `space_station()`.
5. `phase_station_assault.tres`.
6. `Level1Director._build_sections()` refactor + `_build_station_assault()`. → tests 8, 9, 10 pass.
7. Docs per §6, then `bash /agent/verify.sh`.
8. **Gate check (review S2):** the suite has **18** `test_*.gd` scripts today (15 `unit/`,
   3 `integration/`), so GUT must report **19** after this. Also grep the step-3 output for
   `Parse Error` and `SCRIPT ERROR` — `BACKLOG.md:270-278` records that GUT silently drops an
   unloadable script and still exits 0, and that channel matters here because tests 4 and 8–10
   "fail before implementation" by making the file **unparseable**
   (`LevelSection.new().enemies_cleared_timeout` on a statically-typed `LevelSection` is a parse
   error, not an assertion failure). Red-before-green for four of ten tests is read off stderr.

Each step is independently runnable; steps 1–3 are the only ones that touch shipped behaviour.

## Test plan

One new file, `tests/integration/test_station_assault_section.gd`. Director tests build a
`LevelDirector` + `WaveManager` + a `Node2D` container by hand — no camera, no level scene — and
drive it by emitting `wave_manager.waves_complete` and freeing container children.

| # | Test | Asserts | Fails before implementation because |
|---|---|---|---|
| 1 | **§0 invariant —** `test_the_core_hurtbox_never_shadows_a_turret_hurtbox` | for the real `space_station.tscn`: the core HurtBox's local **x-extent** is disjoint from every turret HurtBox's x-extent | today core x ∈ [−120,120] overlaps turret x ∈ [50,102] — **fails** |
| 2 | **§0 real projectile —** `test_a_player_bullet_damages_the_near_turret_not_the_core` | instance `bullet.tscn` at local (−76, +200) with `rotation = 0` (travels `Vector2.UP`), `expired` wired to free it exactly as `bullet_pool.gd:56` does; step physics; `Turret2.health.current_health < 120` **and** `station.health.current_health == 600` | the bullet is consumed by the core box first — **fails** |
| 3 | **§0 far turret —** `test_a_bullet_reaches_the_far_turret_once_the_near_one_is_dead` | kill `Turret2`, fire the same bullet up the x = −76 lane → `Turret0.health.current_health < 120` | core box still shadows it — **fails** |
| 4 | `test_enemies_cleared_timeout_defaults_to_ten_seconds` | `LevelSection.new().enemies_cleared_timeout == 10.0` | property does not exist → parse error |
| 5 | `test_section_does_not_advance_while_an_enemy_lives` | 2 sections, timeout 30 s, one live child; emit `waves_complete`; after ~0.5 s of frames `section_started` has fired **only** for index 0 | — (guards the gate) |
| 6 | `test_section_advances_when_the_last_enemy_is_freed` | continue from 5: `queue_free()` the child → `section_started` fires with index 1 | — (guards the gate) |
| 7 | **Boundary —** `test_timeout_frees_leftover_enemies_then_advances` | timeout `0.3`, a child that never dies → director advances, `enemy_container.get_child_count() == 0`, **and** `ScoreTracker._combo` has been multiplied by 0.75 once (B3) | today it advances with the child still parented — this is the bug |
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

**Note on tests 2 and 3 (review B2).** These exist specifically because
`tests/integration/test_space_station.gd:15-19` records that driving damage through
`HurtBox.received_damage.emit()` does **not** prove the collision layers — the gap that hid §0.
They must therefore go through a real `Area2D` overlap. The suite has no precedent for
physics-overlap tests, so this is the one genuinely new technique here. *Fallback, to be recorded
in `5-progress.md` if headless physics proves unreliable:* drive the same geometry through
`Area2D.get_overlapping_areas()` after `await get_tree().physics_frame`, which uses the same
broadphase. **Test 1 does not depend on physics at all** and is the load-bearing §0 assertion;
tests 2 and 3 are the evidence that the invariant is the right one.

Other gotchas (`tests/README.md`): no zero-parameter handlers on `Health.amount_changed`;
`push_warning` is not a GUT failure (`tests/README.md:72`) so the timeout tests will not trip on
the existing warning; nothing here touches `user://`, so no `SaveSandbox`. Test 7 must save and
restore `ScoreTracker`'s combo state, or use a locally constructed tracker.

## Risks

| Risk | Check |
|---|---|
| §0 changes a shipped entity's hitbox | Only the `HurtBox` shape; the body collider and therefore the 40-damage contact HitBox (`base_enemy.gd:50-59`) are untouched. Sub-item 1's 9 tests emit `received_damage` directly and are shape-independent, so they must still pass unchanged — checked in step 1. |
| Headless Area2D overlap may not fire in GUT | Test 1 carries the invariant without physics; documented fallback for 2 and 3. |
| Freeing leftovers on timeout changes `cloud_descent` | Runs only after `push_warning`. Tests 6 and 7 separate the paths; the ×0.75 combo penalty is now asserted rather than denied. |
| `_wait_enemies_cleared` is `await`-heavy; tests may be timing-flaky | Budgets sized off the real 1.0 s poll granularity (see above); assertions are on the `section_started` signal, not wall-clock. |
| The `_build_sections()` refactor breaks Level 1 boot | `verify.sh` step 2 boots the main scene headless; test 8 pins the order. Nothing hardcodes a section count — `LevelDirector` reads `_sections.size()`, and `section_started`'s only consumer ignores the index (`level_1_director.gd:78, :104`). |
| Station sits somewhere unplayable | Arithmetic tabled above and verified in review; the pan caveat is stated. Static placement in a section with no other spawns, so worst case is a cosmetic follow-up. |
| GUT silently drops the new test file if it fails to parse | Build step 8: assert 19 scripts **and** grep for `Parse Error` / `SCRIPT ERROR`. |

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
