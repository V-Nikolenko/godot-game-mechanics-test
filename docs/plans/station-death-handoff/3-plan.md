# Station destruction hands off to the planet approach (EPIC sub-item 5)

> **Revision 2** (after review round 1, `4-review.md`). The design was approved unchanged; every
> change below is to the **test plan** plus one simplification the reviewer asked to be examined.
> Findings addressed: **A** test 8 rewritten to assert blast *offset* (the old form could not fail
> for the right reason — `hit_effect.gd` keeps a permanent `CPUParticles2D` under every enemy);
> **B** test 9 now asserts the pure `blast_offset(i)` table instead of time-dependent world
> offsets; **C** test 12 zeroes `SpawnEntryResource.spawn_delay`, without which it leaks
> `SceneTreeTimer`s while the gate stays green; **D** tests 5/6 now name the override mechanism
> (`station.death_duration`, never `station.config`); **E** `ExplosionEffect.explode()` takes an
> optional position instead of the transient-`site` trick; **F** line citations corrected;
> **G** fixed in `2-research.md` (four `CameraShake.add` sites, not two, plus the measured note
> that the chain shake never accumulates); **H** test 7's post-condition now states that
> `cancel_active()` permanently shrinks the pool; **I** naming slips (`bullet_pool`,
> `death_duration`); **J** the lost `HitEffect.burst()` is now called out explicitly.
>
> **Revision 3** (after review round 2, which returned `VERDICT: APPROVED` with one blocking
> pre-condition). **K** — the blocker — the `ExplosionEffect` must be parented to the
> **`SpaceStation`**, not to `StationDeathSequence`: revision 2 claimed the sequence node's actor
> chain resolved to the enemy container and it does not, it is one hop short, which would have put
> every blast under the rotating hull. **L** `explode()` uses a typed assignment, never
> `at as Vector2` (a documented silent-null trap). **M** the set-before-add ordering in `explode()`
> is written down now that position is load-bearing. **N** test 7 asserts relative pool sizes, not
> a literal. **O/P** two stragglers: `beam_behavior.gd:151` (was `:99-102`, an error inherited from
> a stale comment in `space_station.gd:8-9` — fix it there too while implementing) and
> `bullet_pool.gd:98-102` in `2-research.md`. Plus the two guards round 2 asked for on the interval
> derivation: `maxi(blast_count, 1)` and an early return when `death_duration <= 0.0`.

## Problem

Four sessions of build-up — armoured turrets, a laser phase, bullet-hell rings, reinforcement
squads — end with the 256×256 mini-boss **disappearing between one frame and the next** behind a
single 22-particle burst, the identical death a 40 px interceptor gets
(`base_enemy.gd:65-73`). 0.2 s later the background starts tweening to `planet_approach`.

What should change:

1. **The kill reads as a kill.** The station stops firing, the hull drifts and darkens, and a
   chain of explosions rolls across it for about two seconds before the wreck goes, ending on one
   big central blast and a screen rattle.
2. **The corpse is harmless.** From the instant HP hits 0 the station cannot damage the player —
   not by contact, and not with the ring of bullets it fired half a second earlier.
3. **The level demonstrably continues.** A headless test walks Level 1's real five-section
   sequence — `deep_space → asteroid_belt → station_assault → planet_approach → cloud_descent` —
   with a **real `SpaceStation` killed for real** in the middle of it, and reaches `level_complete`.

Nothing about the fight itself changes. This is the last 2 seconds of it, plus the proof that the
handoff works.

## Design

### The handoff needs no director change — and that is the point

`LevelDirector._wait_enemies_cleared()` polls `wave_manager.enemy_container.get_child_count()`
(`level_director.gd:116`). A station that stays parented while it dies therefore holds
`station_assault` open **for free**, and the section advances the moment the wreck (and its last
particles) leave the container. So the entire feature is: *stop freeing the station instantly*.
No new end condition, no new signal on the director, no change to `LevelSection`.

### Split of responsibility

Following the split the last three sub-items established, and keeping `space_station.gd` as thin
as the composition rule demands:

| Owner | Responsibility |
|---|---|
| `space_station.gd` | **Lifetime only.** Latch the death, emit `died` + set `was_killed` at the true moment HP hits 0, make the corpse harmless, hold the wreck in the tree for `death_sequence_duration`, then free it. |
| `station_death_sequence.gd` (new, 5th sibling node) | **Spectacle only.** The blast chain, the shake, the drift and the darkening. Listens to `SpaceStation.died`. Owns nothing the level depends on. |
| `station_gunnery.gd` | Already stops on `died`; additionally **cancels its in-flight bullets** there. |

**The station must not depend on the sequence node existing.** If `StationDeathSequence` were the
thing that called `queue_free()`, a station instantiated without it (or with the node renamed)
would never leave the container and `station_assault` would hang until the 180 s timeout. So the
station owns the timer and the free; the sequence node only draws.

### `space_station.gd` — the changes

```gdscript
signal death_started            ## zero-arg, fires with `died`; what the sequence node listens to

## Copied from `config.death_sequence_duration` in _ready(), never read live from the shared
## .tres. PUBLIC and deliberately so: overriding this copied field is how a test shortens the
## sequence (`station.death_duration = 0.05`), exactly as test_station_laser_phase.gd and
## test_station_gunnery.gd override their nodes' copied timings. Never write to `station.config`.
var death_duration: float = 0.0

var _dying: bool = false
var _death_timer: Timer         ## one-shot child, built in _ready()

func is_dying() -> bool: return _dying

## Override. BaseEnemy frees the actor in the same call that emits `died`; a boss needs the
## wreck to stay in the tree long enough to explode. Everything BaseEnemy does at the moment
## of death still happens at the moment of death — only queue_free() moves.
func _on_health_changed(current: int) -> void:
    if current > 0:
        super._on_health_changed(current)
        return
    if _dying:
        return                              # 0 -> 0 re-emit; see below
    _dying = true
    was_killed = true                       # ScoreTracker's kill/escape discriminator
    died.emit()                             # laser phase, gunnery, reinforcements all stop here
    _make_corpse_harmless()
    death_started.emit()
    if death_duration <= 0.0:
        _finish_death()
    else:
        _death_timer.start(death_duration)

func _finish_death() -> void:
    _explosion_effect.explode()             # the final central blast, as BaseEnemy would
    queue_free()
```

Three things this has to get right, each with a named reason:

- **`Health.set_health()` emits `amount_changed` unconditionally** (`health_component.gd:40-42`),
  so any hit landing on a 0-HP station re-enters this handler. `_dying` is the latch. Without it
  a stray bullet mid-sequence re-emits `died` (double-scoring the boss) and starts a second timer.
- **`was_killed` and `died` must fire now, not at `_finish_death()`.** `ScoreTracker` connects the
  kill path to `died` and the escape path to `tree_exited`, discriminating on `enemy.was_killed`
  (`score_tracker.gd:151-164` kill, `:197-215` escape, `:201` the `was_killed` guard, `:211` the
  0.75× multiply). Deferring either would score the boss as an *escape* and apply the combo
  penalty — a silent scoring regression the gate would not catch. As a bonus, `:171` captures
  `enemy.global_position` on `died`, which the delayed free makes *more* accurate, not less.
- **The wreck also stops flashing and sparking, and that is intended.** `base_enemy.gd:66-67` runs
  `hit_flash_player.play("hit")` **and** `_hit_effect.burst()` *before* the zero check, so moving
  both behind the `current > 0` branch drops two visual behaviours, not one. A corpse that still
  flashes white and sparks on every stray bullet reads as "still alive"; a corpse that does not is
  the readable signal that the fight is over. Called out because it is a second visual change
  hiding inside a one-line guard.
- **`_death_timer` is a `Timer` node child, not `get_tree().create_timer()`.** A `SceneTreeTimer`
  awaited across the station's own destruction is exactly the leak `tests/README.md` documents,
  where the gate stays green while `ObjectDB instances leaked` prints at exit. A `Timer` child dies
  with its owner.

`_make_corpse_harmless()`:
- `hurt_box.set_deferred("monitoring", false)` — no more physics-driven damage. (The direct
  `received_damage.emit()` paths in `plasma_nova_module.gd:41` / `beam_behavior.gd:151`
  bypass this, which is why the `_dying` latch, not the hurtbox, is the real guard.)
- The contact `HitBox`'s `collision_layer` → `0`, deferred. The player's HurtBox monitors layer
  256; zeroing the layer is what stops a dead 256 px hull from ramming the player.

### `station_death_sequence.gd` — the spectacle

`Node2D`, fifth child of `space_station.tscn`, alongside `LaserPhase` / `BulletPool` / `Gunnery` /
`Reinforcements`. Same shape as its siblings: resolves `_station = get_parent() as SpaceStation`
in `_ready()`, **copies** its tuning out of `_station.config` (never reads the shared process-wide
`.tres` live), connects `death_started`.

On `death_started`:

- Fires `blast_count` explosions on a repeating `Timer`, at **deterministic** offsets around the
  hull — a fixed table of unit vectors × `blast_spread_radius`, cycled by blast index, never
  `randf()`. The laser phase and the gunnery both established that random attack ordering cannot
  be balanced or tested; the same argument applies to anything a test has to assert.

  The offset table is exposed as a pure function of the index:

  ```gdscript
  ## Hull-LOCAL offset of blast `i`. Pure: no transform, no time, no RNG — which is exactly
  ## what makes it assertable (test 9).
  func blast_offset(i: int) -> Vector2:
      return _BLAST_DIRS[i % _BLAST_DIRS.size()] * blast_spread_radius
  ```

  The world position of a blast is then `_station.to_global(blast_offset(i))`, so the chain rolls
  across the hull *as the hull drifts*.

- **The blast interval is derived from `_station.death_duration`, not from the node's own copy of
  the config.** `blast_count` is copied from the config in `_ready()` (siblings' discipline), but
  the cadence is read as `_station.death_duration / blast_count` **at `death_started` time**.
  This is deliberate and load-bearing: the station owns the timer that frees the wreck, so if the
  two were copied independently a test (or a future config edit) that shortened one would leave
  the chain still firing into a freed station. Reading the station's already-copied field is not
  a shared-`.tres` read — it is a sibling's local value — and it makes the two impossible to
  desync.

  Two guards this needs:

  - **`maxi(blast_count, 1)` before dividing.** `blast_count` is copied from the config, and a
    `death_blast_count = 0` would make the interval `INF`. `station_laser_phase.gd:144` already
    applies exactly this guard to `beam_count`; follow it.
  - **Early-return the whole chain when `_station.death_duration <= 0.0`.** `death_started` is
    emitted *before* `_finish_death()` in the zero case (test 6, and any station with no `.tres`),
    so without the guard the node starts a chain with a `0.0` interval against a station being
    freed in the same call. `Timer.start(0.0)` does **not** error — Godot only calls
    `set_wait_time` when `p_time > 0`, so it silently falls back to the default 1.0 s `wait_time`.
    It happens to be harmless because the sequence node is a child of the station and dies with
    it, but that is an accident of tree shape, not a design. Make it explicit.
- Each blast reuses `global/components/explosion_effect.gd` rather than hand-rolling particles.
  `explode()` today spawns into `actor.get_parent()` at `actor.global_position`
  (`explosion_effect.gd:28-36`) — i.e. it can only explode *where its owner is*, which is the one
  thing a blast chain across a hull must not do.

  **`explode()` gains an optional position argument** — three additive lines, default preserves
  today's behaviour exactly:

  ```gdscript
  ## `at` overrides the spawn position. Omitted/null keeps the historic behaviour
  ## (explode at the owning actor's own global_position).
  func explode(at: Variant = null) -> void:
      ...
      ## Direct typed assignment, NOT `at as Vector2`: `as` is invalid on built-in value types
      ## in GDScript 4 and would silently return null — see wave_manager.gd:137 and :170-171,
      ## which document this trap twice. A silent null is the worst possible failure for a
      ## position: the blast would render at the origin with no error.
      if at is Vector2:
          var pos: Vector2 = at
          p.global_position = pos
      else:
          p.global_position = actor.global_position
  ```

  **The `ExplosionEffect` must be parented to the `SpaceStation`, not to `StationDeathSequence`.**
  This is the one thing in this design that is easy to get wrong and silent when wrong.
  `explosion_effect.gd:28` reads `actor = fx.get_parent()` and `:31` reads
  `container = actor.get_parent()`. With `fx` under the sequence node — itself the fifth child of
  the station — that chain is **one hop short**: `actor` = `StationDeathSequence`,
  `container` = `SpaceStation`, and the particles become children of the *hull*. Four things break
  at once, none of them loudly:

  1. Particles are freed **with** the wreck, which is the exact opposite of the property
     `explosion_effect.gd:5-6` exists to provide.
  2. They never enter the container `_wait_enemies_cleared()` polls (`level_director.gd:116`), so
     they cannot hold `station_assault` open — breaking the design point below and risk row 3.
  3. The whole blast field **rotates with the drifting hull**, because this same node writes
     `_station.rotation`. `space_station.tscn:109-112` and `:132-136` warn about precisely this
     hazard, twice, for `BulletPool` and `StationReinforcements`.
  4. Test 8 fails — which is the point of writing test 8 that way. **If test 8 fails, the node
     placement is wrong; do not weaken test 8.**

  So the sequence node creates one `ExplosionEffect`, sets `amount = blast_particle_amount`, and
  `_station.add_child(fx)` — the same place `base_enemy.gd:32-33` puts its own. It **cannot** be
  done in `StationDeathSequence._ready()`: `station_gunnery.gd:25-29` documents that
  `Node::_propagate_ready()` sets `data.blocked` on the parent while it readies its children, so
  `add_child()` on the parent fails hard there. This is the same mistake round 1 of sub-item 4a's
  review caught. Do it lazily in the `death_started` handler, where the parent is unblocked.

  With that placement, `actor` = the station and `container` = the enemy container: particles land
  in the **container**, survive the wreck, and — deliberately — keep `station_assault` open for
  their own ~0.5 s. The level does not transition mid-explosion.

  **Ordering note:** `explosion_effect.gd:36` sets `p.global_position` *before* `:51` adds it to
  the tree, so for a not-yet-parented node `global_position` == `position`. That has always been
  true but only starts mattering now that `at` makes the position meaningful. It is safe here
  because the real `EnemyContainer` is a bare `Node2D` with an identity transform
  (`level_1.tscn:22`, as `station_reinforcements.gd:33-34` already records) and so is the test
  harness container — but test 8's tolerance depends on it, so it is written down.

  *Chosen over the transient-`site`-node trick in review round 1 (finding E).* That trick works —
  `actor = site`, `container = site.get_parent()` — but costs two node creations per blast in the
  very container `_wait_enemies_cleared()` polls (`level_director.gd:116`) and subscribes to via
  `child_exiting_tree` (`:93`), so every blast would fire a spurious wake-up on the director's
  wait helper. The optional argument is simpler on every axis and leaves nothing transient to
  reason about in the tests.
- `CameraShake.add(blast_shake)` (0.25) per blast, and `CameraShake.add(final_shake)` (1.0) on the
  last one. Research finding 3: two respected sources disagree about shake volume, and the tiebreak
  is that **nothing an enemy does currently shakes this game's screen at all** — only
  `player_fighter.gd:169,177`. So a boss death is where the budget is meant to be spent, but the
  *chain* gets a whisper and the *finale* gets the spike.
- **Drift and darken** (research finding 7): `_station.rotation += _spin * delta` with `_spin`
  decaying to zero over the sequence, and `_station.modulate` lerped toward a burnt grey. The hull
  is already rotating in phase 2 (`station_laser_phase.gd:123`), so a hard stop at death is the
  *more* jarring option.

### Bullet cancel at the moment of death

`BulletPool` already frees its in-flight bullets — but in `_exit_tree()` (`bullet_pool.gd:98-102`),
which now fires ~1.8 s later than it used to. The station would keep a full ring of live bullets
in the air while visibly exploding, and could kill the player after it is dead.

Fix, in two additive parts:

1. `global/components/bullet_pool.gd` gains a public `cancel_active()` that frees every in-flight
   bullet and clears `_active`; `_exit_tree()` becomes a call to it. Pure extraction — no existing
   behaviour changes for the eight other ships that use the pool.
2. `station_gunnery.gd::_stop()` (already connected to `died`, `:134`) calls
   `bullet_pool.cancel_active()`. The gunnery owns the pool reference; the death-sequence node
   does not need to know the pool exists.

Research finding 5 records this as a judgement call: the wiki's bullet-cancel convention is stated
for *player* death. It is applied here because the alternative is not a design choice but an
artefact of this change — the boss firing while exploding.

### Config

Two new `SpaceStationConfig` fields (stats/feel → config, copied in `_ready()`):

| Field | Default in `.gd` | Value in `.tres` | Why |
|---|---|---|---|
| `death_sequence_duration` | `0.0` | `1.8` | `0.0` is the honest fallback: a station with no config behaves exactly as `BaseEnemy` always has. The `.tres` carries the shipped value, so the config test cannot pass vacuously. |
| `death_blast_count` | `3` | `7` | Same split. 7 reads as a chain; research finding 1. |

Geometry and feel that belong to the *scene*, not the stat block, stay as `@export`s on
`StationDeathSequence` — matching `StationLaserPhase.emitter_radius`,
`StationGunnery.spawn_radius` and `StationReinforcements.reinforcement_lifetime`:
`blast_spread_radius` (96.0), `blast_particle_amount` (18), `blast_shake` (0.25),
`final_shake` (1.0), `death_spin` (1.2 rad/s), `burnt_tint`.

### Rejected alternatives

| Alternative | Why not |
|---|---|
| Hitstop / `Engine.time_scale` dip on the killing blow (research findings 2 and 4 both ask for it) | `LevelDirector._wait_enemies_cleared()`, `WaveManager._spawn_with_delay()` and every gunnery/laser `Timer` run on tree time and would all stretch with it. High blast radius, and finding 4's own boss-rank scaling says a *mini*-boss gets the brief pause, not the cinematic. Recorded as a follow-up idea, not built. |
| An `AnimationPlayer` death animation on `space_station.tscn` | The hull is a single 256 px sprite with four independently-destroyed turret children; a keyframed animation would have to encode turret state it cannot see. Code-driven blasts read the live hull. |
| A new `LevelSection.EndCondition.BOSS_DEAD` | `ENEMIES_CLEARED` already does exactly this, correctly, and is already tested. Adding a second path is the reviewer's "reinvents something that already exists". |
| Put the death sequence in `space_station.gd` | Violates the composition rule three sibling nodes in this same scene already follow. |
| `StationDeathSequence` owns `queue_free()` | Makes the level's progression depend on an optional visual node. A renamed or missing node would hang `station_assault` for 180 s with no error. |
| A transient `Node2D` "site" per blast, to trick `explode()` into firing off-centre | Works, and was the round-1 plan. Rejected in favour of the optional `at` argument: it created two throwaway nodes per blast *in the enemy container*, which `_wait_enemies_cleared()` polls (`level_director.gd:116`) and whose `child_exiting_tree` it subscribes to (`:93`), so each blast would spuriously wake the director's wait helper. |
| Also fixing `race_ship.gd:97-100` while adding the `at` argument | It is a real latent bug — `boom.global_position` is written and then ignored, because `explode()` reads `actor.global_position` where `actor` is the *parent*, so race-ship explosions render at the container origin. But it is unrelated to this sub-item and changing it alters shipped visuals in the race mode. Filed under *Discovered* in `BACKLOG.md` instead. The new `at` argument is what makes the eventual fix a one-liner. |

## Build sequence

1. **`BulletPool.cancel_active()`** — extract from `_exit_tree()`. Test first
   (`test_station_gunnery.gd`): acquire bullets, `cancel_active()`, assert they are freed, that
   `_active` is empty, and that `_idle` has shrunk by the cancelled count (test 7).
1b. **`ExplosionEffect.explode(at)`** — the optional position argument, default `null` preserving
   today's behaviour exactly. Purely additive; no existing caller changes.
2. **`SpaceStationConfig`** — add `death_sequence_duration` / `death_blast_count` + the `.tres`
   values. Test: the shipped `.tres` carries 1.8 / 7 and the script defaults differ.
3. **`space_station.gd` lifetime** — `death_duration`, `_dying`, `death_started`, `_death_timer`,
   `_on_health_changed` override, `_make_corpse_harmless()`, `_finish_death()`. Tests 1-6 below.
4. **`station_gunnery.gd::_stop()`** — cancel the pool. Test 7.
5. **`station_death_sequence.gd` + wire it into `space_station.tscn`.** Tests 8-11.
6. **`tests/integration/test_level_1_sequence.gd`** — the end-to-end run. Test 12.
7. Docs (`updating-project-docs`), `BACKLOG.md`, `tests/README.md`.

Each step is independently runnable; steps 1-2 are safe to land even if 5 runs out of window.

## Test plan

New file `tests/integration/test_station_death_sequence.gd` (asserts intent, not
characterization — new code, like the rest of the station family):

1. `test_the_wreck_stays_in_the_tree_after_hp_reaches_zero` — kill all four turrets, then the
   core; after two `process_frame`s the station is **still** `is_instance_valid` and still
   parented. *(This test fails today: `base_enemy.gd:73` frees it in the same call.)*
2. `test_died_and_was_killed_fire_at_the_moment_hp_reaches_zero` — `died` has fired **once** and
   `was_killed` is already `true` on the frame HP hits 0, long before the wreck is freed. Pins the
   `ScoreTracker` contract that would otherwise silently mis-score the boss as an escape.
3. `test_further_damage_during_the_death_sequence_does_not_re_emit_died` — emit
   `received_damage` three more times on the 0-HP core; `died` count stays 1 and the station is
   still freed exactly once. Covers the `Health` 0→0 re-emit.
4. `test_the_corpse_cannot_ram_the_player` — the contact `HitBox`'s `collision_layer` is 256 while
   alive and `0` after death.
5. `test_the_wreck_is_freed_after_death_sequence_duration` — **set `station.death_duration = 0.05`
   on the station's own copied field, after `_ready()` has run.** Then the station is gone after
   the timer elapses.

   *Mechanism named explicitly (review round 1, finding D).* **Never** write to `station.config`:
   `space_station.gd:36` `load()`s the `.tres` and `ResourceLoader` caches it, so it is a single
   process-wide object shared with every later test in the run (`tests/README.md`, and
   `test_station_gunnery.gd:9-13`). And **not** a fresh `SpaceStationConfig.new()` either — that
   resets `max_health` to the `ShipConfig` default and `turret_health` to the script default,
   silently changing what "kill the four turrets, then the core" means in exactly the two tests
   that need it to be exact. Overriding the node's copied field is the established pattern and the
   reason `death_duration` is public.
6. **Boundary:** `test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour` — with
   `station.death_duration = 0.0` the station is freed in the same frame, exactly as every other
   enemy. This is the case that proves the new path is *additive*: the script default is 0.0, so
   this is also what a station with no `.tres` does.
7. `test_bullet_pool_cancel_active_frees_in_flight_bullets` (in `test_station_gunnery.gd`) —
   acquire two bullets, `cancel_active()`, then assert the **real** post-condition: both bullets
   are freed, `_active` is empty, and `acquire()` still returns a bullet **from the remaining idle
   set**.

   *Post-condition corrected (finding H).* `cancel_active()` permanently **shrinks** the pool:
   `_recycle()` (`bullet_pool.gd:80-92`) is the only path back into `_idle`, and both
   `cancel_active()` and `_exit_tree()` `queue_free()` the bullet instead of recycling it. So
   "the pool is reusable afterwards" is only true while `_idle` is non-empty.

   The assertion is written **relative**, not against a literal pool size: acquire 2, record
   `_idle.size()`, `cancel_active()`, then assert `_active` is empty, `_idle.size()` is
   **unchanged** from that post-`acquire()` reading (the cancelled bullets did *not* come back),
   both cancelled bullets are freed, and `acquire()` still returns a bullet. The station's pool is
   `pool_size = 48` (`space_station.tscn:122`) and `test_station_gunnery.gd`'s `before_each`
   instantiates the real scene, so a "pool of 4" literal would simply be wrong here — the
   *property* is what is being pinned, not a number.
8. `test_the_blast_chain_rolls_across_the_hull_rather_than_detonating_at_its_centre` — during the
   sequence, look at the **direct children of the container only**, filtered to `CPUParticles2D`,
   and assert at least one has a `global_position` differing from `station.global_position` by
   roughly `blast_spread_radius`.

   *Rewritten (finding A).* The original — "assert 0 `CPUParticles2D` under the station" — could
   not fail for the right reason. `base_enemy.gd:29-30` adds a `HitEffect` to every enemy and
   `hit_effect.gd:21,34` keeps a permanent `CPUParticles2D` as *its* child, and each of the four
   turrets this test must destroy parents its explosion under `$Turrets`
   (`station_turret.gd:79-81`). A recursive search therefore finds ≥ 5 particle nodes and fails on
   frame one for reasons unrelated to this feature; a direct-children search finds 0 and always
   will, because nothing in this codebase parents a raw `CPUParticles2D` directly to an enemy — so
   the assertion is already true before the feature exists. `tests/README.md:145-159` documents
   this exact trap and records that it cost a whole gate cycle. Asserting on the blast **offset**
   is the property actually wanted: it fails today, fails against a centre-only burst, and fails
   if a blast is ever parented to the hull.
9. `test_blast_offsets_are_deterministic` — assert on `sequence.blast_offset(i)` for
   `i in 0..blast_count`: the values are identical across two fresh stations, and re-querying the
   same index twice returns the same vector. Locks out `randf()`.

   *Rewritten (finding B).* The original compared blast **world** offsets across two runs — but
   this same plan has the sequence node rotating the hull with a decaying spin, so a world offset
   is a function of accumulated `delta` and the test would fail on frame timing rather than on
   RNG. It also compared two runs without pinning the blast count, so a run one tick short
   produced arrays of different lengths. `blast_offset(i)` is a pure function of the index — no
   transform, no time, no RNG — which is precisely the thing determinism means here. The
   companion `test_blasts_are_emitted_at_the_hull_local_offsets` drives the emit method directly
   with `death_spin = 0.0` (the way `test_station_gunnery.gd` forces volleys instead of awaiting
   real timers) and checks the spawned particle positions against `to_global(blast_offset(i))`.
10. `test_the_hull_drifts_and_darkens_during_the_sequence` — `rotation` changes between two
    samples and `modulate` is darker than it was; the spin magnitude at the end is smaller than at
    the start (decay, not constant spin).
11. `test_death_sequence_copies_its_tuning_from_the_config` — the node's copied values equal the
    shipped `.tres` and **differ** from the script defaults, and mutating the node's copy does not
    write back to the shared resource.

New file `tests/integration/test_level_1_sequence.gd`:

12. `test_level_1_runs_all_five_sections_end_to_end_with_a_real_station` —
    - Build the harness from `test_station_assault_section.gd` (bare `Node2D` container +
      `WaveManager` + `LevelDirector`; no camera, so `wave_manager._spawn_ship()` returns early
      at `:160-162` and nothing auto-spawns).
    - Take the **real** sections from `Level1Director._build_sections()` on a bare script
      instance. Safe to mutate: `WaveBuilder.wave()` returns a fresh `WaveResource.new()`
      (`wave_builder.gd:211-212`), so nothing shipped is shared. Compress every DURATION
      section's `duration` to 0.1, every wave's `trigger_time` to 0.0, **and every
      `SpawnEntryResource.spawn_delay` to 0.0.**

      **Zeroing `spawn_delay` is not optional — omitting it leaks with the gate green
      (review round 1, finding C).** `level_1_director.gd` calls `.delay()` **182 times**, up to
      1.5 s, and `wave_manager.gd:151-155` turns each into
      `await get_tree().create_timer(delay).timeout`. With `trigger_time = 0.0` every wave in a
      section triggers on one frame, `waves_complete` fires immediately, and `cloud_descent`
      reaches `level_complete` ~0.2 s after starting ~30 spawn coroutines that are still holding
      timers of up to 1.5 s. The test returns; they stay suspended; Godot prints
      `ObjectDB instances leaked` at exit — and **neither line matches the gate's fatal-error
      regex**, so the gate passes while leaking. This is verbatim the trap
      `tests/README.md:50-53` documents. Zeroing `spawn_delay` is exactly as safe as zeroing
      `trigger_time`: `wave_builder.gd:196-197` builds a fresh `SpawnEntryResource.new()` per
      `_config_to_entry` call, so nothing shipped is shared. (The alternative — awaiting ≥ 1.6 s
      past `level_complete` — was rejected: it adds to an already ~6 s budget and only hides the
      coroutines rather than preventing them.) **`enemies_cleared_timeout`
      is left untouched** — the point is that the sections end because they *finish*, not because
      the safety net fires; the test asserts total elapsed time is well under the 10 s cloud-descent
      timeout.
    - On `section_started(&"station_assault")`, instantiate a real `space_station.tscn` into the
      container **synchronously**. This ordering is load-bearing: `_advance()` emits
      `section_started` *before* `wave_manager.load_section()` (`level_director.gd:60` vs `:66`), so the
      station is in the container before `waves_complete` can fire — otherwise the director sees an
      empty container and advances past the boss instantly.
    - Kill the four turrets, then the core, by emitting `received_damage` on their HurtBoxes.
    - Assert: the recorded `section_started` names are exactly
      `[deep_space, asteroid_belt, station_assault, planet_approach, cloud_descent]` in order;
      `station_assault` did **not** advance while the wreck was still in the container;
      `level_complete` fired; and the run produced no orphaned `SpaceStation`.
    - Return only after `level_complete`, so no `_wait_enemies_cleared()` coroutine is left
      suspended (`tests/README.md`'s leak trap — it leaks with the gate still green).

## Risks

| Risk | Check |
|---|---|
| The station's own gunnery fires during the ~2 s sequence and its bullets, which live in the container, hold `station_assault` open. | This is exactly what `cancel_active()` in step 4 removes. Test 12 exercises it for real — a live station with a live gunnery is in the container for seconds. |
| Reinforcements spawned into the container outlive the boss and hold the section open. | Already handled by sub-item 4b (`_stop()` on `armor_broken` **and** on `died`, plus `FREE_ON_DURATION`). Test 12 covers it incidentally; its 8 s first delay means none spawn inside the test window. |
| The blast `CPUParticles2D` in the container delay the section by up to one 1.0 s poll. | Intended (no transition mid-explosion) and bounded by `ExplosionEffect.lifetime` (0.5 s). Test 12's time budget is sized off the poll, not the nominal timeout — the trap `tests/README.md` documents. |
| Test 12 is slow. | Budget ≈ 0.1 + 0.1 + (kill + a shortened sequence + ~1.0 s poll + 0.2 s settle) + 0.1 + ~1.2 s ≈ 4-6 s, with `spawn_delay` zeroed so no section is padded by its spawn coroutines. Test 12 sets `station.death_duration` short rather than running the shipped 1.8 s — the end-to-end claim is about the *handoff*, and test 5 already pins the real duration. Acceptable for one integration test; the suite is currently ~30 s. |
| Test 12 leaves suspended `_spawn_with_delay` coroutines, leaking `SceneTreeTimer`s **with the gate still green**. | The `spawn_delay = 0.0` sweep (finding C). Checked by eye at the tail of the GUT run for `ObjectDB instances leaked` / `resources still in use` — the gate's fatal regex does **not** match either line, so this cannot be delegated to the gate. |
| `_death_timer` still running when the director's 180 s timeout frees the station. | A `Timer` node is a child and is freed with it. This is the whole reason it is not a `SceneTreeTimer`. |
| `modulate` and `rotation` writes on the station fight `StationLaserPhase`. | The laser phase `_stop()`s on `died` (`station_laser_phase.gd:109`), which fires before `death_started`. Test 10 samples after death, so a regression here shows up as a failing rotation assertion. |
| `hit_flash_player.play("hit")` on a dying station. | Unchanged from today; `_on_health_changed`'s flash happens only on the `current > 0` branch after this change, so the wreck stops flashing white — which is what "it is dead now" should look like. |

## Out of scope

- Hitstop / `Engine.time_scale` (rejected above; a follow-up idea, not a defect).
- New art. The blast chain reuses `ExplosionEffect`'s particles; no PixelLab call, no sprite for a
  wrecked hull.
- Sound. There is no audio system in this project yet.
- Any change to `planet_approach`, `cloud_descent`, the debrief, or the level-exit cutscene. This
  item proves the handoff works; it does not retune what comes after.
- The score/debrief flow on `level_complete` — `_on_level_complete()` loads dialog and changes
  scene, so test 12 drives a bare `LevelDirector`, not `Level1Director` in the tree.
