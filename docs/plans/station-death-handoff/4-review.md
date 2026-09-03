# Review — EPIC sub-item 5: station destruction hands off to the planet approach

VERDICT: CHANGES_REQUESTED

The **design is sound and I want it built**. The central claim — that `_wait_enemies_cleared()`
already *is* the handoff, so the whole feature is "stop freeing the station instantly" — is
correct, and I verified it against the director rather than taking it on trust. The split of
responsibility, the `_dying` latch, the `died`/`was_killed` timing argument and the `Timer`-node
choice are all right for the reasons the plan gives.

What blocks approval is the **test plan**, not the design. Three of the twelve tests, including
the headline end-to-end one, do not do what they say:

- Test 8 either always fails or passes vacuously (findings **A**).
- Test 9 is flaky by construction, against a hazard the same plan introduces (**B**).
- Test 12 leaks `SceneTreeTimer`s with the gate green — the exact trap `tests/README.md` warns
  about, and the one thing this sub-item's done-condition rests on (**C**).

Fix A–E and this is an approve. No re-research needed.

---

## Claims I checked and confirmed

| Plan claim | Checked | Result |
|---|---|---|
| `_on_health_changed` at `base_enemy.gd:65-73`; `was_killed` → `died` → `explode()` → `queue_free()` all in one call | `assault/scenes/enemies/base_enemy.gd:65-73` | **Exact.** Lines 68-73 in that order. |
| `Health.set_health()` emits `amount_changed` unconditionally, so a 0→0 hit re-enters | `global/components/health_component.gd:40-42` | **True.** No guard at all. The `_dying` latch is genuinely required, and `station_turret.gd:63-66` already documents the same trap. |
| `ScoreTracker` discriminates kill vs escape on `was_killed` | `assault/scenes/systems/score_tracker/score_tracker.gd:151-164` (kill via `died`), `:161-164` (escape via `tree_exited`), `:201` (`enemy.get("was_killed")` guard), `:211` (`_combo *= escape_combo_multiplier`) | **True.** Deferring `was_killed`/`died` to `_finish_death()` really would score the boss as an escape and apply 0.75×. Also confirmed `_on_enemy_died` captures `enemy.global_position` at `:171`, which the delayed free makes *more* correct, not less. |
| `section_started` is emitted BEFORE `wave_manager.load_section()` | `assault/scenes/systems/level_director/level_director.gd:60` vs `:66` | **True**, and load-bearing for test 12 as claimed. Also confirmed the `ENEMIES_CLEARED` → `_wait_enemies_cleared` connection at `:78` happens *after* `load_section()`, but `load_section()` only calls `set_process(true)` — waves trigger on the next `_process`, so the connection cannot be missed. |
| `_wait_enemies_cleared()` polls `enemy_container.get_child_count()` | `level_director.gd:105-147`, poll at `:116` | **True.** No director change is needed. |
| `explode()` spawns into `actor.get_parent()` at `actor.global_position` | `global/components/explosion_effect.gd:28-36` | **True.** The transient-`site` trick is therefore *correct* — see finding E. |
| `bullet_pool.gd` hardcodes `get_parent().get_parent()`; `_exit_tree()` frees in-flight bullets | `global/components/bullet_pool.gd:47`, `:98-102` | **True.** Delaying `queue_free()` really does delay the cleanup by ~1.8 s. |
| Laser phase / gunnery / reinforcements already stop on `died` | `station_laser_phase.gd:109` (`_stop` at `:172`), `station_gunnery.gd:134` (`_stop` at `:230`), `station_reinforcements.gd:124,127` | **True** for all three. The laser phase also `set_physics_process(false)`s at `:174`, so the sequence node writing `_station.rotation` cannot fight it. |
| Zeroing the contact `HitBox.collision_layer` stops the corpse ramming the player | `base_enemy.gd:54` (layer 256, mask 0), player `HurtBox` `collision_mask = 1281` (= 1024+256+1) in the player scene, `hurtbox_component.gd:12-18` | **True.** The player's hurtbox is the monitoring side, so layer 0 on the corpse's hitbox is the right lever. |
| `_build_sections()` order and the 180 s timeout | `level_1_director.gd:199-208`, `:228-243` (`enemies_cleared_timeout = 180.0` at `:235`), `:800-806` (cloud_descent, no override → `level_section.gd:35` default 10.0) | **True.** |
| Test-12 harness: `_spawn_ship()` returns early with no camera | `wave_manager.gd:159-162` | **True.** |
| `WaveBuilder.wave()` returns a fresh `WaveResource` so the test may mutate it | `assault/scenes/systems/wave_builder.gd:211-212` | **True** — and `_config_to_entry` at `:196-197` builds a fresh `SpawnEntryResource.new()` per call too, which matters for finding C. |
| Only `player_fighter.gd:169,177` shake the screen | `grep CameraShake.add` | **Substantively true, literally wrong.** See finding G. |
| Nothing is being reinvented | `ls global/components/` | **Confirmed.** No death-sequence / blast-chain component exists. `damage_reaction.gd:39-44` is the only other "die on zero HP" path and it is a different composition root (`get_parent().queue_free()`), correctly not touched. |
| Conventions | — | **Composition:** fifth sibling node matches `LaserPhase`/`BulletPool`/`Gunnery`/`Reinforcements` in `space_station.tscn:106-138`. **Config-driven `.tres`:** two fields with `.gd` defaults deliberately unequal to the `.tres`, matching the three existing blocks in `space_station_config.gd`. **Design units:** correctly *not* applied — blasts are hull-local on-screen pixels, the same call `station_laser_phase.gd:44-48` and `station_gunnery.gd:47-53` already make. No violations found. |

One bonus verification the plan did not claim but depends on: `_station.modulate` **will** actually
darken the hull. `assault/assets/shader/hit_flash_vs.tres` feeds `VisualShaderNodeInput`
`input_name = "color"` into the `If` node's false branch, so with `enabled = false` the incoming
vertex colour (which carries the parent's modulate) passes straight through. A shader that wrote
`COLOR = texture(...)` outright would have silently swallowed the whole "darken" half of the
feature. It does not.

---

## Findings that must be addressed

### A. Test 8 cannot fail for the right reason — it either always fails or is vacuous

> *"count `CPUParticles2D` children of the container during the sequence; assert > 0 there and
> **0** under the station"*

There is **always** a `CPUParticles2D` under the station: `base_enemy.gd:29-30` adds a `HitEffect`
child, and `global/components/hit_effect.gd:21,34` creates a persistent `CPUParticles2D` as *its*
child in `_ready()`. On top of that, every dead turret's explosion parents its particles to
`$Turrets` (`station_turret.gd:79-81`) — and test 8 has to kill four turrets to reach the core.

So a recursive search under the station finds ≥ 5 particle nodes and the test fails on frame one,
for a reason that has nothing to do with the code under test. A *direct-children* search finds
zero and always will, because no explosion in this codebase ever parents a raw `CPUParticles2D`
directly to an enemy — the assertion is then true before the feature is written.

`tests/README.md:145-159` documents this exact class of mistake and records that it "cost a whole
gate cycle"; `test_station_gunnery.gd:55-59` carries the filtered-`get_children()` workaround.

**Required:** state the search explicitly (direct children of the *container* only), and make the
test assert what it actually cares about — that at least one blast's `global_position` differs
from `station.global_position` by roughly `blast_spread_radius`. That is the property "the blasts
roll across the hull" and it fails today, fails on a hand-rolled centre-only burst, and fails if
someone parents the blast to the hull.

### B. Test 9 (`test_blast_offsets_are_deterministic`) is flaky by construction

The test compares "the recorded blast **world** offsets (relative to the hull)" across two runs on
two fresh stations. But the same plan has the sequence node writing
`_station.rotation += _spin * delta` with `_spin` decaying over the sequence. If a blast offset is
carried through the hull's live transform, its world offset is a function of accumulated `delta` —
which differs between two runs. The test then fails on frame timing, not on `randf()`.

It also compares two runs without pinning how many blasts each got, so a run that is one tick short
produces arrays of different length.

**Required:** either assert on the node's *local* offset table (a pure function of the blast index,
no transform involved — which is what actually locks out `randf()`), or set `death_spin = 0.0` and
drive the blasts by calling the emit method directly, the way `test_station_gunnery.gd` forces
volleys instead of awaiting real timers.

### C. Test 12 leaks `SceneTreeTimer`s — the trap `tests/README.md:50-53` documents

The plan compresses "every DURATION section's `duration` to 0.1 and every wave's `trigger_time` to
0.0" and says nothing about `SpawnEntryResource.spawn_delay`.

`level_1_director.gd` calls `.delay()` **182 times**, with values up to 1.5 s. `cloud_descent`
alone (`:800-995`) carries delays from 0.2 to 1.5 s. Each one becomes
`await get_tree().create_timer(delay).timeout` inside `wave_manager.gd:151-155`.

With `trigger_time = 0.0` every wave in a section triggers on the same frame, `waves_complete`
fires immediately (`wave_manager.gd:55-57`), `_wait_enemies_cleared` sees an empty container and
reaches `_advance()` after the 0.2 s settle. For cloud_descent that means `level_complete` fires
roughly **0.2 s** into a section that has just started ~30 spawn coroutines holding timers of up to
1.5 s. The test returns; they are still suspended. Godot prints `ObjectDB instances leaked` at
exit, **neither line matches the gate's fatal-error regex**, and the gate stays green while
leaking — precisely the failure mode `tests/README.md:50-53` was written about.

The same applies to `deep_space`, `asteroid_belt` and `planet_approach`: at 0.1 s each, their
delayed spawns spill into every later section.

**Required:** zero `entry.spawn_delay` on every entry as well. This is as safe as zeroing
`trigger_time` — `wave_builder.gd:196-197` builds a fresh `SpawnEntryResource.new()` per
`_config_to_entry` call, so nothing shipped is shared. (Alternatively await ≥ 1.6 s past
`level_complete`, but that adds to a budget that is already ~6 s.) Either way, say which, and
reflect it in the risk table's time budget.

### D. Tests 5/6 propose "a per-test config", against the rule the plan itself cites

Tests 5 and 6 say "with a short duration set on a per-test config". The plan's own Design section
correctly warns that `space_station.gd:36` `load()`s the `.tres` and ResourceLoader caches it, and
`tests/README.md:140-144` plus `test_station_gunnery.gd:9-13` both say: never write to
`station.config`, override the **node's copied field**.

A `SpaceStationConfig.new()` assigned before `add_child` avoids the shared-object hazard but
introduces a different one — it resets `max_health` to `ShipConfig`'s default and `turret_health`
to the script default, silently changing what "kill the turrets, then the core" means in the two
tests that most need that to be exact.

**Required:** name the mechanism. The established one is to set the station's own copied field
(`station._death_duration = 0.05`) after `_ready()`, exactly as `test_station_laser_phase.gd` and
`test_station_gunnery.gd` do for their timings.

### E. `explode()` with an optional position is a plainly simpler alternative, unexamined

The transient-`site` trick is *correct* — I traced it: `actor = site` (a `Node2D`),
`container = site.get_parent()` (the enemy container), `p.global_position = site.global_position`.
It is notably more correct than the shipped precedent at `race_ship.gd:96-99`, which sets
`boom.global_position` that `explode()` then ignores because it reads `actor.global_position`
where `actor` is the *parent*. That shipped line is a latent bug.

But the alternative is three additive lines on `explosion_effect.gd` — an optional
`at: Variant = null` argument, defaulting to today's behaviour — and it is simpler on every axis:
no two-node-per-blast churn in the enemy container (a container `_wait_enemies_cleared` polls at
`level_director.gd:116` and `_wait_for_child_exit_or_timeout` subscribes to via
`child_exiting_tree` at `:93`), nothing transient to reason about in test 8, and it fixes
`race_ship.gd` for free.

The "Rejected alternatives" table is otherwise good — the `BOSS_DEAD` end-condition and the
`AnimationPlayer` rejections are both right. This one belongs in it.

**Required:** examine it and record the choice either way. I am not mandating the outcome.

---

## Smaller things to fix while you are in there

**F. Line citations drift by 1–3 throughout.** Every underlying claim checked out; only the numbers
are wrong. `health_component.gd:39-41` → `40-42`. `bullet_pool.gd:96-101` → `98-102`.
`explosion_effect.gd:29-36` → `28-36`. `level_director.gd:57-64` → `60` and `66`.
`score_tracker.gd:198-211` → `197-215`. Fix them; the next reader will be greping.

**G. Research finding 3's tiebreak overstates its evidence.** "In this project only two things do"
— there are four call sites: `player_fighter.gd:169,177` **and**
`open_space/scenes/entities/player/player_ship.gd:195,202`. The conclusion survives intact
(nothing an *enemy* does shakes the assault screen, and the boss-death budget is unspent), but the
sentence as written is false. Also worth noting for tuning, not correctness: `camera_shake.gd:32`
saturates at 1.0 and `:24` decays at 1.5/s, so seven `add(0.25)` blasts ~0.26 s apart never
accumulate past ~0.25 trauma — which at the quadratic curve (`:46-50`) is a ~0.5 px offset. That
is consistent with "the chain gets a whisper", but it means the chain shake is essentially
invisible; do not be surprised, and do not "fix" it by raising the value without re-reading
finding 3.

**H. `cancel_active()` permanently shrinks the pool, and test 7 should say so.**
`bullet_pool.gd:80-92` — `_recycle()` is the only path back into `_idle`, and
`cancel_active()`/`_exit_tree()` `queue_free()` the bullets instead. Test 7's "the pool is reusable
afterwards" is true only while `_idle` is non-empty. State the real post-condition (`_active`
empty, the cancelled bullets freed, `acquire()` still returns from the remaining idle set) so
nobody later assumes capacity recovers.

**I. Two naming slips in the pseudocode.** `_bullet_pool.cancel_active()` — the gunnery's field is
`bullet_pool`, no underscore (`station_gunnery.gd:42`). And `_death_duration` in the
`_on_health_changed` sketch vs `death_sequence_duration` in the config table.

**J. The killing blow also loses its `HitEffect`.** The risk table covers `hit_flash_player`, but
`base_enemy.gd:66-67` runs `hit_flash_player.play("hit")` **and** `_hit_effect.burst()` before the
zero check, so the `if current > 0` guard drops both. Probably what you want — the wreck should
stop sparking white — but say it, since it is a second visual change hiding inside a one-line
guard.

---

## Things I looked for and did not find

- **No reinvention.** `global/components/` has no death-sequence, blast-chain or corpse-disable
  component. `damage_reaction.gd:39-44` is the only other zero-HP path and belongs to a different
  composition root; correctly untouched.
- **No convention violations.** Composition, config-driven `.tres` (with defaults deliberately
  unequal to the shipped values, matching all three existing blocks), and the design-unit rule
  (correctly *not* applied to hull-local geometry) all hold.
- **Scope is proportionate.** Twelve tests across two files, one new node, one scene edit, two
  config fields, one pure extraction, docs — against sub-item 4a's 26 tests and 4b's 18. The build
  sequence is genuinely resumable and steps 1–2 land alone, as claimed. No objection.
- **Research supports its conclusions.** Finding 1's weakest row is labelled weak and corroborated
  by a source that *was* read; findings 2 and 4 both argue *for* hitstop and are declined with a
  concrete, verifiable reason (the director's own progression runs on `get_tree().create_timer`,
  `level_director.gd:86,144`); finding 3 records a genuine disagreement between two sources rather
  than picking one. The tradeoff column is real, not decorative. Only finding 3's project-specific
  tiebreak is factually loose (G).

## What I would not change

The instinct to keep `queue_free()` on `space_station.gd` rather than on the sequence node is
right, and the reason given is the correct one: `level_1_director.gd:235` sets a 180 s timeout, so
a station whose free depended on a renamed or missing visual node would hang `station_assault` for
three minutes with no error and then take the escape-combo penalty at `score_tracker.gd:211`. Keep
that boundary exactly where the plan puts it.

---
---

# Review round 2 — revision 2 of `3-plan.md`

VERDICT: APPROVED

**Approved with one blocking pre-condition on build step 5, stated immediately below.** It is a
one-line node-placement fix, not a redesign, and the plan's own revised test 8 will catch it — but
it must be corrected in the plan text before an unattended implementer reads it, because the plan
currently asserts something about the codebase that is false.

All ten round-1 findings (A–J) are genuinely fixed. I checked each against the code rather than
against the description; every claim in the revision note held up. The design is unchanged and
remains sound.

---

## BLOCKING PRE-CONDITION — finding K (new in revision 2)

### The `ExplosionEffect` must be a child of `SpaceStation`, **not** of `StationDeathSequence`

Plan lines 183-187 say:

> *"The sequence node then holds **one** long-lived `ExplosionEffect` child and calls
> `fx.explode(world_pos)` per blast. Particles still land in the **container** (they are parented
> to `actor.get_parent()`, and the sequence node's actor chain resolves there), survive the wreck,
> and — deliberately — keep `station_assault` open for their own ~0.5 s."*

**The parenthetical is false.** Traced against `global/components/explosion_effect.gd`:

| line | code | with `fx` as a child of `StationDeathSequence` |
|---|---|---|
| `:28` | `var actor := get_parent() as Node2D` | `actor` = `StationDeathSequence` |
| `:31` | `var container := actor.get_parent()` | `container` = **`SpaceStation`** |
| `:51` | `container.add_child(p)` | particles become children of the **hull** |

`StationDeathSequence` is the fifth child of `space_station.tscn` (plan line 135), so
`actor.get_parent()` resolves to the station, not to the enemy container. The chain is one hop
short. This breaks four things at once:

1. **Particles do not survive the wreck.** They are freed with the station at `death_duration` —
   the exact opposite of the property `explosion_effect.gd:5-6` exists to provide, and the reason
   `BaseEnemy` parents its own effect to the entity (`base_enemy.gd:32-33`) rather than one level
   down.
2. **Particles do not hold `station_assault` open.** Design line 186 and risk-table row 3 both
   depend on blast particles sitting in the container that `_wait_enemies_cleared()` polls
   (`level_director.gd:116`). Under the hull they are invisible to it.
3. **The blast field rotates with the drifting hull**, because the same plan writes
   `_station.rotation += _spin * delta`. This is the hazard `space_station.tscn:109-112` and
   `:132-136` warn about *twice*, in this very scene file, for `BulletPool` and
   `StationReinforcements` respectively.
4. **Revised test 8 fails.** It counts direct `CPUParticles2D` children of the *container* and
   would find zero.

**The fix, precisely:** add the `ExplosionEffect` as a child of `_station`, which is where
`BaseEnemy` already puts its own — then `actor` = the station, `container` = the enemy container,
and `p.global_position = at` lands correctly. It **cannot** be done from
`StationDeathSequence._ready()`: `station_gunnery.gd:25-29` documents that
`Node::_propagate_ready()` sets `data.blocked` on the parent while readying its children and
`add_child()` fails hard on that — the exact mistake round 1 of the sub-item 4a review caught. Do
it in the `death_started` handler (the parent is unblocked by then), or author the node in
`space_station.tscn` as a direct child of `SpaceStation`.

**To the implementer:** if test 8 fails, the node placement is wrong — do **not** weaken test 8.

I flag this at full weight even though it is downstream of my own round-1 finding E. The optional
`at` argument is still the right call (see below); only the parenting claim that came with it is
wrong.

---

## The question you asked: reading `_station.death_duration` at `death_started` time

**The distinction holds. Keep it — this is a good call, and it fixes a bug I did not catch in
round 1.**

The copy-from-config discipline is documented four times — `station_laser_phase.gd:50-64`,
`station_gunnery.gd:55-63`, `station_reinforcements.gd:71-79`, `space_station_config.gd:17-25` —
and every one of them frames the rule the same way: *do not read the shared process-wide `.tres`
at runtime, because `space_station.gd:36` `load()`s it and `ResourceLoader` caches, so it is
mutable global state shared with every other station and every test in the process.*
`death_duration` is a plain per-instance `var` on the station. Reading it is not a resource read,
so the rule does not reach it.

Sibling nodes already read live station state per call, deliberately:
`station_gunnery.gd:153` calls `_station.turrets()` on **every** volley (and `:146-148` documents
why caching it in `_ready()` would be wrong), and `station_reinforcements.gd:270` reads
`_station.get_parent()` on every spawn. Your read is the same shape.

The desync argument is not merely defensive — it is load-bearing. Tests 5, 6 and 12 all write
`station.death_duration` **after** `_ready()`. Had the sequence node taken its own `_ready()` copy
of `config.death_sequence_duration`, all three would have fired a 1.8 s seven-blast chain into a
station freed at 0.05 s, and test 5 would have "passed" while the chain kept running against a
node that no longer existed. Deriving the cadence from the station's field makes them impossible
to disagree. Right decision, right reason.

Two guards it needs (minor, but fix them while you are there):

- **`maxi(blast_count, 1)`** before dividing. `blast_count` is copied from the config, and a
  `death_blast_count = 0` would make the interval `INF`. `station_laser_phase.gd:144` already
  applies exactly this guard to `beam_count`; follow it.
- **Early-return the chain when `_station.death_duration <= 0.0`.** Plan line 93 emits
  `death_started` *before* line 95's `_finish_death()`, so in the `0.0` case (test 6, and any
  station with no `.tres`) the sequence node starts a chain with a `0.0` interval on a station
  that is freed in the same call. `Timer.start(0.0)` does not error — Godot's `Timer::start` only
  calls `set_wait_time` when `p_time > 0`, so it silently falls back to the default `wait_time` of
  1.0 s. It happens to be harmless because the sequence node is a child of the station and is
  freed with it before that timer can fire, but that is an accident of the tree shape, not a
  design. Make it explicit.

---

## Round-1 findings — all verified fixed

| # | Change | Verified against | Result |
|---|---|---|---|
| **A** | Test 8 rewritten to assert blast *offset*, direct children of the container only | `hit_effect.gd:21,34` (permanent `CPUParticles2D` under every enemy via `base_enemy.gd:29-30`), `station_turret.gd:79-81` | **Fixed.** The new assertion fails today, fails against a centre-only burst, and fails if a blast is parented to the hull. It is now a real test. (It also correctly catches finding K.) |
| **B** | Test 9 asserts the pure `blast_offset(i)` table; companion test drives emit directly with `death_spin = 0.0` | plan lines 147-157, 328-340 | **Fixed.** A pure index → `Vector2` function has no `delta` dependence, so the flakiness is gone and the test now isolates exactly what "deterministic" means. Driving emit directly mirrors `test_station_gunnery.gd`'s forced-volley approach. |
| **C** | Test 12 zeroes `SpawnEntryResource.spawn_delay` | `wave_builder.gd:196-197` (fresh `SpawnEntryResource.new()`), `:211-212` (fresh `WaveResource.new()`), `:216-219` — and I confirmed **`level_1_director.gd` contains no raw `SpawnEntryResource`**, so every entry goes through `SpawnConfig` → `_config_to_entry` and the sweep touches nothing shipped | **Fixed, and the safety argument is sound.** The leak the gate could not see is closed. Rejecting the "await 1.6 s" alternative was right — it hides the coroutines rather than preventing them. |
| **D** | Tests 5/6 name `station.death_duration`; `station.config` and `SpaceStationConfig.new()` both explicitly rejected | `test_station_gunnery.gd:9-13`, `tests/README.md:140-144`, `space_station.gd:36` | **Fixed**, and the `SpaceStationConfig.new()` rejection reasoning (it resets `max_health`/`turret_health`, changing what "kill the turrets then the core" means) is correct. |
| **E** | Optional `at` on `explode()`; transient-`site` moved to rejected alternatives | `explosion_effect.gd:28-36,51`, `level_director.gd:93,116` | **Adopted**, and the rejection reason given (two throwaway nodes per blast in the container the director subscribes to via `child_exiting_tree`) is accurate. Default `at = null` preserves all nine existing callers bit-for-bit. See finding K and L for the two things the adoption needs. |
| **F** | Citations corrected | spot-checked `health_component.gd:40-42`, `bullet_pool.gd:98-102` & `:80-92`, `explosion_effect.gd:28-36`, `level_director.gd:60`/`:66`/`:93`/`:116`, `score_tracker.gd:151-164`/`:171`/`:197-215`/`:201`/`:211`, `wave_manager.gd:151-155`/`:160-162`, `station_turret.gd:79-81`, `hit_effect.gd:21,34`, `race_ship.gd:97-100`, `tests/README.md:50-53`/`:145-159` | **All correct now.** Two stragglers in finding O/P below. |
| **G** | Research finding 3: four `CameraShake.add` sites, plus the decay arithmetic | `camera_shake.gd:24` (decay 1.5/s), `:32` (saturate 1.0), `:46-50` (quadratic × `_MAX_OFFSET` 8.0) | **Fixed and the arithmetic checks out**: 0.25 / 1.5 = 0.167 s < the ~0.26 s interval, and 8.0 × 0.25² = 0.5 px. Recording it as a caveat rather than changing the number is the right call, and the "do not later 'fix' the invisibility" warning is the useful part. |
| **H** | Test 7 states that `cancel_active()` permanently shrinks the pool | `bullet_pool.gd:80-92` (`_recycle` is the only path back to `_idle`), `:98-102` | **Fixed.** See minor finding N on the pool size. |
| **I** | `bullet_pool` / `death_duration` naming | `station_gunnery.gd:42`, plan lines 73, 94-97, 217 | **Fixed.** |
| **J** | The lost `HitEffect.burst()` called out | `base_enemy.gd:66-67` | **Fixed**, and the justification added (a corpse that still sparks reads as alive) is better than a bare note. |

### On deferring `race_ship.gd:97-100` to BACKLOG — your call is right

I verified it at `assault/scenes/race/core/race_ship.gd:97-100`: `boom` is added to `get_parent()`
(the container), so `explode()` resolves `actor` = the container and `container` = the container's
parent, and `p.global_position = actor.global_position` — the `boom.global_position =
global_position` on `:99` is written and then ignored. Race-ship explosions render at the
container's origin, not at the ship. Real bug, confirmed.

Deferring it is correct on all three counts you gave: it is unrelated to this sub-item, fixing it
**changes shipped visuals in a mode this plan does not touch** (explosions would move from the
container origin to the ship's actual position — the right behaviour, but a visible change that
belongs in its own cycle with its own before/after check), and the new `at` argument reduces the
eventual fix to one line. *Discovered* in `BACKLOG.md` is the right home. Do not fix it here.

---

## Minor items to fix alongside K

**L. `(at as Vector2)` violates a house rule this codebase documents twice.** Plan line 180 uses
`p.global_position = (at as Vector2) if at != null else actor.global_position`.
`wave_manager.gd:137` and `:170-171` both record: *"'as Vector2' is invalid on built-in value
types in GDScript 4 and would silently return null."* Silently — which is the worst failure mode
for a position. Use the documented form instead:

```gdscript
func explode(at: Variant = null) -> void:
    ...
    if at is Vector2:
        var pos: Vector2 = at        # direct typed assignment, per wave_manager.gd:170-171
        p.global_position = pos
    else:
        p.global_position = actor.global_position
```

**M. Note the set-before-add ordering, now that position is load-bearing.**
`explosion_effect.gd:36` sets `p.global_position` **before** `:51` adds it to the container, so for
a not-yet-in-tree node `global_position` == `position`. That has always been true, but it only
started mattering when `at` made the position meaningful. It is safe here — the real
`enemy_container` is a bare `Node2D` with an identity transform (`level_1.tscn:22-26`, recorded at
`station_reinforcements.gd:33-34`) and so is the test harness container — but say so in the plan,
because test 8's tolerance depends on it.

**N. Test 7's "acquire 2 of a pool of 4" does not match the harness.** The station's `BulletPool`
is `pool_size = 48` (`space_station.tscn:122`), and `test_station_gunnery.gd`'s `before_each`
instantiates the real scene. Either build a standalone 4-bullet pool for this test or make the
assertion relative — `_idle.size()` unchanged from its post-`acquire()` value, and neither
cancelled bullet is back in `_idle`. The *property* being pinned is right; only the literal is.

**O. `beam_behavior.gd:99-102` (plan line 128) points at the wrong lines.** `:99-102` is the
`get_node_or_null("HurtBox")` lookup; the actual `hb.received_damage.emit(whole)` is at **`:151`**.
The claim — that this path bypasses physics and so the `_dying` latch, not the hurtbox, is the
real guard — is **true**. The citation is inherited from `space_station.gd:8-9`, which carries the
same stale numbers, so the plan copied a pre-existing error rather than making one. Worth fixing in
both places while the file is open. (`plasma_nova_module.gd:39-41` is correct — the emit is at
`:41`.)

**P. `2-research.md` finding 5 still cites `bullet_pool.gd:96-101`.** The plan corrected this to
`:98-102`; the research row did not follow. One-character fix, but it is the row that carries the
whole bullet-cancel justification.

---

## Standing assessment

Everything I checked in round 1 still holds and I did not re-litigate it: the "no director change
needed" claim, the `died`/`was_killed` timing contract, the `_dying` latch requirement, the
`Timer`-node choice, the contact-`HitBox` layer-zeroing, the composition split, the config
discipline, the design-unit handling, and the absence of any reinvention in `global/components/`.
Scope remains proportionate to sub-items 4a and 4b, and the build sequence is still resumable with
steps 1, 1b and 2 landable on their own.

Fix K (blocking), then L–P (cheap, same sitting), and build it.
