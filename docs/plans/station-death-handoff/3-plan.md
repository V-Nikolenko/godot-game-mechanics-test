# Station destruction hands off to the planet approach (EPIC sub-item 5)

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
    if _death_duration <= 0.0:
        _finish_death()
    else:
        _death_timer.start(_death_duration)

func _finish_death() -> void:
    _explosion_effect.explode()             # the final central blast, as BaseEnemy would
    queue_free()
```

Three things this has to get right, each with a named reason:

- **`Health.set_health()` emits `amount_changed` unconditionally** (`health_component.gd:39-41`),
  so any hit landing on a 0-HP station re-enters this handler. `_dying` is the latch. Without it
  a stray bullet mid-sequence re-emits `died` (double-scoring the boss) and starts a second timer.
- **`was_killed` and `died` must fire now, not at `_finish_death()`.** `ScoreTracker` connects the
  kill path to `died` and the escape path to `tree_exited`, discriminating on `enemy.was_killed`
  (`score_tracker.gd:147-165, 198-211`). Deferring either would score the boss as an *escape* and
  apply the 0.75× combo penalty — a silent scoring regression the gate would not catch.
- **`_death_timer` is a `Timer` node child, not `get_tree().create_timer()`.** A `SceneTreeTimer`
  awaited across the station's own destruction is exactly the leak `tests/README.md` documents,
  where the gate stays green while `ObjectDB instances leaked` prints at exit. A `Timer` child dies
  with its owner.

`_make_corpse_harmless()`:
- `hurt_box.set_deferred("monitoring", false)` — no more physics-driven damage. (The direct
  `received_damage.emit()` paths in `plasma_nova_module.gd:39-41` / `beam_behavior.gd:99-102`
  bypass this, which is why the `_dying` latch, not the hurtbox, is the real guard.)
- The contact `HitBox`'s `collision_layer` → `0`, deferred. The player's HurtBox monitors layer
  256; zeroing the layer is what stops a dead 256 px hull from ramming the player.

### `station_death_sequence.gd` — the spectacle

`Node2D`, fifth child of `space_station.tscn`, alongside `LaserPhase` / `BulletPool` / `Gunnery` /
`Reinforcements`. Same shape as its siblings: resolves `_station = get_parent() as SpaceStation`
in `_ready()`, **copies** its tuning out of `_station.config` (never reads the shared process-wide
`.tres` live), connects `death_started`.

On `death_started`:

- Fires `blast_count` explosions on a repeating one-shot `Timer`, `death_sequence_duration /
  blast_count` apart, at **deterministic** offsets around the hull — a fixed table of unit vectors
  × `blast_spread_radius`, cycled, never `randf()`. The laser phase and the gunnery both
  established that random attack ordering cannot be balanced or tested; the same argument applies
  to anything a test has to assert.
- Each blast reuses `global/components/explosion_effect.gd` rather than hand-rolling particles:

  ```gdscript
  var site := Node2D.new()
  _container().add_child(site)          # _station.get_parent(), i.e. the enemy container
  site.global_position = world_pos
  var fx := ExplosionEffect.new()
  fx.amount = blast_particle_amount
  site.add_child(fx)
  fx.explode()                          # spawns the CPUParticles2D into _container()
  site.queue_free()
  ```

  `ExplosionEffect.explode()` spawns into `actor.get_parent()` at `actor.global_position`
  (`explosion_effect.gd:29-36`), so the transient `site` node is what lets a component designed
  for "explode where I am" place a blast anywhere. Particles therefore live in the **container**,
  survive the wreck, and — deliberately — keep `station_assault` open for their own ~0.5 s. The
  level does not transition mid-explosion.
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

`BulletPool` already frees its in-flight bullets — but in `_exit_tree()` (`bullet_pool.gd:96-101`),
which now fires ~1.8 s later than it used to. The station would keep a full ring of live bullets
in the air while visibly exploding, and could kill the player after it is dead.

Fix, in two additive parts:

1. `global/components/bullet_pool.gd` gains a public `cancel_active()` that frees every in-flight
   bullet and clears `_active`; `_exit_tree()` becomes a call to it. Pure extraction — no existing
   behaviour changes for the eight other ships that use the pool.
2. `station_gunnery.gd::_stop()` (already connected to `died`, `:134`) calls
   `_bullet_pool.cancel_active()`. The gunnery owns the pool reference; the death-sequence node
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

## Build sequence

1. **`BulletPool.cancel_active()`** — extract from `_exit_tree()`. Test first
   (`test_station_gunnery.gd`): acquire bullets, `cancel_active()`, assert they are freed and the
   pool is reusable afterwards.
2. **`SpaceStationConfig`** — add `death_sequence_duration` / `death_blast_count` + the `.tres`
   values. Test: the shipped `.tres` carries 1.8 / 7 and the script defaults differ.
3. **`space_station.gd` lifetime** — `_dying`, `death_started`, `_death_timer`,
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
5. `test_the_wreck_is_freed_after_death_sequence_duration` — with a short duration set on a
   per-test config, the station is gone after the timer elapses.
6. **Boundary:** `test_death_sequence_duration_zero_keeps_the_base_enemy_behaviour` — with
   `death_sequence_duration = 0.0` the station is freed in the same frame, exactly as every other
   enemy. This is the case that proves the new path is *additive*: the script default is 0.0, so
   this is also what a station with no `.tres` does.
7. `test_bullet_pool_cancel_active_frees_in_flight_bullets` (in `test_station_gunnery.gd`) —
   acquire two bullets, `cancel_active()`, assert both are freed, `_active` is empty, and a
   subsequent `acquire()` still works.
8. `test_the_death_sequence_spawns_its_blasts_into_the_container_not_the_station` — count
   `CPUParticles2D` children of the container during the sequence; assert > 0 there and **0**
   under the station (a blast parented to the hull would rotate with it and vanish with it).
9. `test_blast_offsets_are_deterministic` — run the sequence twice on two fresh stations and
   assert the recorded blast world offsets (relative to the hull) are identical. Locks out
   `randf()`.
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
      section's `duration` to 0.1 and every wave's `trigger_time` to 0.0. **`enemies_cleared_timeout`
      is left untouched** — the point is that the sections end because they *finish*, not because
      the safety net fires; the test asserts total elapsed time is well under the 10 s cloud-descent
      timeout.
    - On `section_started(&"station_assault")`, instantiate a real `space_station.tscn` into the
      container **synchronously**. This ordering is load-bearing: `_advance()` emits
      `section_started` *before* `wave_manager.load_section()` (`level_director.gd:57-64`), so the
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
| Test 12 is slow. | Budget ≈ 0.1 + 0.1 + (kill + 1.8 s sequence + ~1.0 s poll + 0.2 s settle) + 0.1 + ~1.2 s ≈ 6 s. Acceptable for one integration test; the suite is currently ~30 s. |
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
