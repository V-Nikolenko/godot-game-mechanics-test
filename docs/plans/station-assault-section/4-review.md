# Review — `station_assault` LevelSection (EPIC sub-item 2)

VERDICT: CHANGES_REQUESTED

Reviewed against the actual files, not the plan's summaries. The core design is sound and most of
the plan is unusually well-evidenced — **the placement arithmetic is correct**, **the
`_build_sections()` tree-independence claim is correct**, and the `10.0` default genuinely leaves
`cloud_descent` bit-identical. But three things must change before implementation, one of them
because the feature's own done-condition ("the level does not continue until the station is
destroyed") is currently unsatisfiable by a default-loadout player, and the plan never checks it.

---

## Blocking

### B1. The gate cannot be satisfied: a non-piercing bullet can never reach the turrets

This is the finding that matters. The plan's whole premise is that the station is a gate the
player opens by killing it. Reading the entity + the projectile path says they cannot.

- `space_station.tscn:16-17` — one `RectangleShape2D` of **240 × 240**, used by both the body
  collider (`:65-66`) and the core `HurtBox` (`:74-75`), centred on the root. So the core's
  hurtbox spans local y ∈ **[−120, +120]**, covering the entire hull.
- `space_station.tscn:89-99` — the four turrets sit at (±76, ±76); `station_turret.tscn:8-9` gives
  each a `CircleShape2D` of radius **26**. Every turret hurtbox is therefore **strictly inside**
  the core hurtbox (bottom pair spans y ∈ [50, 102]; top pair y ∈ [−102, −50]).
- Both hurtboxes are on `collision_layer = 512` and the player bullet's HitBox is
  `collision_layer = 64, collision_mask = 513` (`bullet.tscn:44-45`), so the bullet detects the
  **core** box first.
- `bullet.gd:66-84` — with `pierces_remaining == 0` and `unlimited_pierce == false`, the first
  `area_entered` calls `expired.emit()`; `bullet_pool.gd:56` recycles the bullet on the deferred
  flush at the end of that physics step.
- `player_base.gd:42` — `pierce_module_active` defaults to **false**; `straight_behavior.gd:20-21`
  only sets `pierces_remaining` when that flag is on; `modes/default.tres` is `behavior = 0`
  (straight), no pierce.

Consequence, for an upward-travelling bullet: it enters the core hurtbox at local y = +120 and is
recycled that step. The **top** pair of turrets is 222 px further along — it can never be reached.
The bottom pair is 18 px further along at 15 px/frame (900 px/s ÷ 60 fps), i.e. it is reached only
when the player's forward-velocity bonus (`bullet.gd:43-44`) pushes a single step past 18 px — so
at best intermittent and frame-rate dependent.

The two direct-emit damage paths don't help either: `plasma_nova_module` / `beam_behavior` emit
`HurtBox.received_damage` over group **`"enemies"`**, and only `SpaceStation` joins that group
(`space_station.gd:35`) — `StationTurret` is a plain `Node2D` that joins no group
(`station_turret.gd:1-38`). They hit the armoured core and are deflected
(`space_station.gd:82-86`).

So `live_turret_count() > 0` stays true forever for a default loadout, the core stays armoured,
the station never `queue_free()`s, and `ENEMIES_CLEARED` becomes "stand still for 180 s, then the
new free-loop deletes the boss". That is the plan's own *rejected* outcome (`3-plan.md:22-24`,
research finding 1: "Hard gating is only safe if the player can always eventually win") shipped by
default rather than as an edge case.

**Required:** before or as part of this sub-item, either
(a) shrink/reshape the core hurtbox so the turret mounts are not shadowed by it (e.g. the core
hurtbox becomes a smaller central shape, turret hurtboxes sit outside it), or
(b) give `StationTurret` a group + damage path the shipped weapons can reach, or
(c) demonstrate in-engine (not by `received_damage.emit`) that the default weapon can strip all
four turrets, and record the evidence in `5-progress.md`.
Whichever is chosen, the plan must say so and must add a test that drives damage through a **real
projectile HitBox overlap**, not a signal emit — see B2. If the fix is judged to belong to
sub-item 1, then this sub-item must not land the `ENEMIES_CLEARED` gate until it does.

### B2. Test 4 does not close the coverage gap the plan says it closes

`3-plan.md:194` claims test 4 "closes sub-item 1's noted coverage gap", and `3-plan.md:218` says
it "reuses [`test_space_station.gd`'s] idiom verbatim". Those two statements contradict each
other. The gap, as written at `tests/integration/test_space_station.gd:15-19`, is precisely that
"damage is driven by emitting `HurtBox.received_damage` directly, so these tests do **NOT** prove
the collision layers are right"; `space_station/ENEMY.md:139-141` says the layers are provable
"only once the station is in a live level (sub-item 2)". A test that emits `received_damage`
reproduces the gap rather than closing it — and it is exactly the gap that hides B1.

**Required:** either drop the claim (and keep test 4 as a gate-mechanics test only), or add a test
that instantiates a real `bullet.tscn`, positions it below a turret, and steps physics until the
turret's `Health` drops. The latter is what would have caught B1.

### B3. "No score impact" is wrong — `ScoreTracker` does react to the timeout free-loop

`3-plan.md:69` and the Risks table (`3-plan.md:216`) both assert **"No score impact"**, and the
plan promises a test pinning it. The cited line, `score_tracker.gd:134`, is inside
`_on_enemy_spawned`, not the escape path. The escape path is `_on_enemy_freed`
(`score_tracker.gd:197-215`), and on `tree_exited` with `was_killed == false` and `_running == true`
it does two things:

- `score_tracker.gd:206-209` — marks the wave tally `escaped = true, resolved = true`.
- `score_tracker.gd:211-215` — **`_combo *= score_config.escape_combo_multiplier`**, which is
  `0.75` (`global/resources/score_config_default.tres:11`), and emits `combo_changed`.

Today the station never leaves the container, so `tree_exited` never fires during play and no
penalty is applied; with the free-loop it is. In `cloud_descent` the practical effect is nil (the
level ends 0.2 s later and `stop_tracking()` would have marked the tally escaped anyway,
`score_tracker.gd:92-100`), but in `station_assault` the combo is cut to 75 % **for the rest of the
level** and the HUD combo bar visibly changes. That is a real behaviour change, and a test written
against the stated claim would either be vacuous (`get_total_score()` is indeed unchanged at that
instant) or fail (`_combo`).

**Required:** correct the claim to "no direct `_total_score` change; one escape-combo penalty
(×0.75) per leftover enemy plus the tally marked escaped", and make the test assert *that*, citing
`score_tracker.gd:197-215`.

---

## Should fix before implementing

### S1. Test 5's timing budget is wrong — as specified it will fail

`3-plan.md:217` sizes test 5 as "0.3 s timeout vs 0.5 s observation". The deadline in
`level_director.gd:110-116` is only re-checked **after** `await _wait_for_child_exit_or_timeout(
container, 1.0)` returns, and with no `child_exiting_tree` that helper always burns its full
`1.0 s` poll (`level_director.gd:85-102`). So a 0.3 s timeout actually expires at ≈1.0 s, and
`_advance()` runs after the further 0.2 s settle (`level_director.gd:122`) — ≈**1.2 s**. Observing
for 0.5 s would see no advance and the test would fail for a reason unrelated to the change.
Budget ≥1.5 s, or state the poll granularity in the test comment.

(Test 6 is fine: a child freed at 0.1 s fires `child_exiting_tree`, so the helper returns early and
the director advances at ≈0.3 s.)

### S2. Build step 6's script count is wrong

`3-plan.md:178-179` says to "confirm GUT reports **4** scripts, not 3". The suite is collected with
`-gdir=res://tests -ginclude_subdirs`, and `tests/` currently holds **18** `test_*.gd` scripts
(15 in `unit/`, 3 in `integration/`), so GUT should report **19**, not 4. As written the check is
unfalsifiable and the guard against the hazard it exists for (`BACKLOG.md:270-278`, "GUT silently
drops a test script it cannot load, and still exits 0") is lost. `BACKLOG.md:276` already suggests
the more robust form: grep GUT's output for `Parse Error`. Use that, or the correct total.

This matters more than it looks, because tests 1 and 7–9 "fail today" only by making the file
unparseable — `LevelSection.new().enemies_cleared_timeout` on a statically-typed `LevelSection` is
a parse error, not a runtime assertion failure — so the red-before-green signal for four of nine
tests *is* the parse-error channel.

### S3. Doc updates are named nowhere, and one shipped doc will be actively contradicted

`CLAUDE.md` mandates the `updating-project-docs` skill after any structural change; this adds an
entity spawn path, a `LevelSection`, and a `BackgroundPhase` resource. `STATUS.md` has a generic
step 7, but the plan's "Out of scope" (`3-plan.md:223-229`) lists nothing. Four files make
statements that become false the moment this lands:

- `docs/enemy-roster.md:487-492` — "`assault/scenes/enemies/space_station/` is a multi-part
  mini-boss, **not** a `WaveBuilder`-spawnable wave enemy. It has no builder method and appears in
  no level yet."
- `docs/architecture/modules/assault.md:184-193` — "In `_ready()` it builds and adds **four**
  sections… The four sections are: …" (list of 4).
- `docs/architecture/modules/assault.md:229-236` — "It is **not yet spawned by anything**".
- `assault/scenes/enemies/space_station/ENEMY.md:139-141` — "**Not spawnable yet.** There is no
  `WaveBuilder` method for it and it appears in no level".

Name these four explicitly in the build sequence.

### S4. Line citations drift; fix them so the implementer edits the right code

Verified against the files:

| Plan says | Actual |
|---|---|
| `level_director.gd:104-107` / `:106-107` for the 10 s cap | `_wait_enemies_cleared` at `:105`; `deadline_ms` at `:108`; `push_warning` at `:112` |
| `wave_manager.gd:126-131` for `_trigger_wave` not awaiting the delay | `_trigger_wave` at `:115-125`; `_spawn_with_delay` at `:151-155` |
| `wave_manager.gd:186` for the `is MovementResource` guard | `:194` |
| `space_station.gd:88` for the armour check | file is 86 lines; the override is `:82-86` |
| `level_1_director.gd:38-45` for the inline section build | `:38-46` |
| `score_tracker.gd:134` for the escape path | `:197-215` (see B3) |

Correct (leave as-is): `wave_manager.gd:52-56`, `wave_manager.gd:172`, `level_director.gd:60`,
`level_1_director.gd:104-106`, `level_1_director.gd:763`, `wave_builder.gd:78-91` and `:229-242`,
`background_phase.gd:17-38`, `arena_camera.gd:5-13`.

---

## Verified correct (no action)

### Placement arithmetic — checks out exactly

Every input in the table is right:

- `arena_camera.gd:1-11` documents the pinned origin, and `level_1.tscn:18-20` confirms it:
  `Camera2D` at `position = Vector2(640, 360)` with `arena_camera.gd` attached, panning only via
  `offset` (`arena_camera.gd:89-90`). So `cam.global_position` really is `(640, 360)`.
- `wave_manager.gd:172` — `cam.global_position + offset * ArenaCamera.WORLD_SCALE`, `WORLD_SCALE =
  2.0` (`arena_camera.gd:35`). `at(0, -90)` → `(640, 360) + (0, −180)` = **`(640, 180)`**. ✅
- `station_core.png` is genuinely **256 × 256** (IHDR read from disk), placed at `scale = 1`
  (`space_station.tscn:61-63`), and `ENEMY.md:23-32` confirms sprites are authored at final
  on-screen pixels and are *not* WORLD_SCALE-multiplied. So 256 world px = 128 design units. ✅
- Occupancy world y 52→308, x 512→768, free space below 308→720 = 412 px. ✅ Nothing is
  pre-multiplied, per the `CLAUDE.md` design-unit convention. ✅
- Turrets at ±76 with 64 × 64 sprites reach ±108, inside the 256 hull — no overhang. ✅

One caveat worth a sentence in the plan, not a change: those numbers describe the **frame at
`offset = 0`**. The camera pans ±380 px vertically (`arena_camera.gd:39, 84-90`) and the player is
clamped to world y ∈ [−380, 1100] (`player_fighter.gd:99-100`), so a player who dives to the
bottom of the play area pushes the station off the top of the screen entirely. Cosmetic, and the
plan's own risk row already accepts that class of outcome — but say it, since the table currently
reads as if the framing were fixed.

### `_build_sections()` on a bare instance — true for all five

Checked every `_build_*` body (`level_1_director.gd:203-437`, `:437-520`, `:520-758`, `:758-954`).
A grep for `get_tree|get_viewport|get_node|get_parent|add_child|@onready|@export|director\.|
wave_manager|score_tracker` over lines 203-991 matches **only** inside `_on_level_complete`
(`:955+`). Every builder touches `LevelSection.new()`, `preload`, and `WaveBuilder.new()` (which is
`RefCounted` — `wave_builder.gd:4` has no `extends`). The proposed `_build_station_assault()` is
the same shape. So the claim holds. Two small notes for the implementer:

- `level_1_director.gd:10` is a bare `extends Node` with **no `class_name`**, so the test must
  `load("res://assault/scenes/levels/edelia/1/level_1_director.gd").new()` and must `autofree()`
  the result or GUT will report an orphan.
- The existing builders all do `var raw_waves: Array = [...]` then `s.waves.assign(raw_waves)`
  rather than assigning a literal to the typed array. If `return [_build_section_1(), …]` from a
  `-> Array[LevelSection]` trips the parser, use the same `.assign()` escape hatch.

### The rest

- `enemies_cleared_timeout: float = 10.0` defaulting to today's constant does keep
  `cloud_descent` (`level_1_director.gd:758-763`, the only shipped `ENEMIES_CLEARED` section)
  bit-identical. ✅
- The phase resource is right: `background_phase.gd:17-38` defaults *are* the deep-space look, and
  `phase_asteroid_belt.tres` sets only `phase_name` + the two asteroid flags, exactly as the plan
  describes. Setting `asteroids_*_enter = false` explicitly is a redundant-but-harmless no-op
  matching `phase_deep_space.tres`'s house style. ✅
- No reinvention: the gate is the existing `EndCondition.ENEMIES_CLEARED`, the spawn is the
  existing `WaveManager` path, the entity composes from `global/components/`. Nothing duplicates
  anything in `global/components/`. ✅
- Nothing hardcodes a section count — `section_started` has one consumer
  (`level_1_director.gd:78, :104`) and it ignores the index; `LevelDirector` reads
  `_sections.size()` dynamically. Inserting a fifth section is safe. ✅
- `push_warning` is not a GUT failure (`tests/README.md:72`), so the timeout tests won't trip on
  the existing warning. ✅
- Scope is right-sized for one session: one export, ~4 lines in `LevelDirector`, 2 lines in
  `WaveBuilder`, one `.tres`, one refactor + one builder, one test file. ✅
- Research cites real sources that support the claims made (G-Darius 180 s, the "boss escapes or
  self-destructs" pattern, the Darius warning beat), and it explicitly reports the one question it
  could **not** answer (Q2, screen placement) instead of inventing a number. Tradeoffs are present
  in every row. ✅

### One incorrect statement carried in from `1-context.md`

`1-context.md`'s reuse table says "`SpaceStation` + `StationTurret` | … death → `queue_free()` (so
`child_exiting_tree` fires)". That is true of the **core only** (`base_enemy.gd:65-73`).
`StationTurret._destroy()` (`station_turret.gd:62-83`) deliberately never frees itself — it stays
as wreckage. The plan doesn't repeat the error, and test 4's design is consistent with the truth,
but the sentence should not be relied on.

### Minor observation on the free-loop

`bullet_pool.gd:45-47` reparents in-flight bullets to `get_parent().get_parent()` — for an enemy
ship that is `enemy_container`. So enemy bullets are already counted by
`level_director.gd:110`'s `get_child_count()`, and the new loop will `queue_free()` pooled bullets
whose pool may outlive them. Self-correcting in practice (`bullet_pool.gd:98-100` frees in-flight
bullets when the owning ship exits, and `_recycle` guards re-entry), and irrelevant to
`station_assault` where nothing shoots yet — but worth a comment on the loop so the next reader
knows the container is not enemies-only.

---

## Summary of what must change

1. **B1** — resolve or explicitly gate on "can a default-loadout player actually strip the four
   turrets"; do not ship an `ENEMIES_CLEARED` gate on a target the shipped weapon cannot damage.
2. **B2** — add a real-projectile test, or drop the "closes the coverage gap" claim.
3. **B3** — correct "No score impact" to name the ×0.75 escape-combo penalty and the escaped tally.
4. **S1** — give test 5 ≥1.5 s; the deadline is only polled once per second.
5. **S2** — fix the GUT script-count check (19, or grep for `Parse Error`).
6. **S3** — list the four docs that this contradicts in the build sequence.
7. **S4** — correct the six drifted line citations.

Re-submit with these addressed and the plan is approvable — the architecture, the reuse story and
the arithmetic are all sound.
