# tests/

GUT (Godot Unit Test) suite. Run it exactly the way the gate does:

```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

`bash /agent/verify.sh` runs this as its third step, after the headless import and the headless
project boot.

## Layout

| Path | Contents |
|---|---|
| `unit/` | One file per autoload or `global/components/` component. No scene loading. |
| `integration/` | Several systems wired together (the player damage chain), plus project-wide integrity checks over the resource files themselves. |
| `helpers/` | Shared fixtures. **Never** named `test_*`, or GUT tries to collect them as tests. |

## Two exceptions: the UID integrity test and the space-station tests

`integration/test_resource_uid_integrity.gd` is **not** characterization. It asserts an invariant
that must hold — every `[ext_resource]` UID in a `.tscn`/`.tres` matches the UID its target
declares — so a failure there is a regression to fix, not a quirk to document.

It reads declared UIDs **from disk** (the `.tscn`/`.tres` header line, the sibling `.gd.uid`, the
sibling `.import`) and never asks `ResourceUID` / `ResourceLoader`. Those consult
`.godot/uid_cache.bin`, which is gitignored *and* keeps stale UIDs registered as working aliases
once a warm project has loaded them — so the engine will happily report a broken reference as fine
on your machine and break on a fresh clone. Five of the eight mismatches this test first caught
behaved exactly that way. If you extend it, keep it reading files.

The whole **space-station family** — `integration/test_space_station.gd`,
`test_station_assault_section.gd`, `test_station_laser_phase.gd`, `test_laser_ray_hit_mask.gd`,
`test_station_gunnery.gd`, `test_station_reinforcements.gd`, `test_station_death_sequence.gd`,
`test_level_1_sequence.gd` and `test_radial_attack_pattern.gd` — are the other exceptions, for a
different reason: the `space_station` entity, the `station_assault` section, the laser phase, the
gunnery, the reinforcement spawner, the death sequence and `RadialAttackPattern` are all **new code**, so their tests assert intended behaviour
rather than pinning existing quirks.
`test_space_station.gd` carries a documented coverage gap — it drives damage by emitting
`HurtBox.received_damage` directly, so it proves nothing about collision layers, and the section
tests do not close that. See the file headers and
`assault/scenes/enemies/space_station/ENEMY.md`.

Two traps `test_station_assault_section.gd` had to work around, both worth knowing before you add
a `LevelDirector` test:

- **`_wait_enemies_cleared()` polls once per second.** Its deadline is only re-checked *after*
  `_wait_for_child_exit_or_timeout(container, 1.0)` returns, so a 0.3 s timeout really fires at
  ~1.0 s, plus a 0.2 s settle. Budget off the poll, not the nominal timeout.
- **A test that ends while that coroutine is suspended leaks its `SceneTreeTimer`**, which Godot
  reports at process exit as `ObjectDB instances leaked` / `resources still in use`. Neither line
  matches the gate's fatal-error regex, so **the gate stays green while leaking.** Empty the
  container and wait for the director to advance before the test returns.

## These are characterization tests

They pin down what the code does **today**, bugs included. A test that documents surprising
behaviour is marked `CHARACTERIZED` in a comment, and the suspicion is filed under *Discovered*
in `BACKLOG.md`. Do not "fix" the code to make one of these read better without first deciding
that the behaviour itself is wrong — the point of the suite is that a behaviour change is a
*visible* change.

## House rules learned the hard way

- **Never let a test touch the real save files.** Every persistent autoload writes to a fixed
  `user://*.cfg`, and the live autoload reads it at boot, so an unsandboxed test leaks into the
  player's profile and into the next run of the suite. Use `helpers/save_sandbox.gd`:

  ```gdscript
  const SaveSandbox := preload("res://tests/helpers/save_sandbox.gd")
  var _sandbox := SaveSandbox.new()
  func before_all() -> void: _sandbox.capture()
  func after_all() -> void:  _sandbox.restore()
  ```

- **Prefer a tree-less `Script.new()` instance to the live autoload.** Outside the tree
  `_ready()` never fires, so `_load()` never runs and the object starts from a known-empty
  state. Use the real singleton only when the code under test needs `get_tree()`.

- **Keep `_process` / `_physics_process` out of the tree and call them by hand** when timing
  matters (see `unit/test_overheat_component.gd`, `unit/test_camera_shake.gd`). Real frame
  timing makes assertions approximate for no benefit.

- **GUT fails a test on any unexpected engine error**, including one raised inside a signal
  callback. Connect a callable whose arity matches the signal exactly: `Health.amount_changed`
  and `State.state_transition` each carry one argument, so a **zero-argument** handler raises
  `Method expected 0 argument(s), but called with 1` and reds the test. Both were declared with
  zero parameters until 2026-09-03 while being emitted with one; the declarations are now honest,
  which makes the mismatch visible in the source, but it does not make a zero-arg handler legal.
  `push_warning` is *not* treated as a failure.

- Components that need a `_ready()` pass (`Health` builds its i-frame `Timer` there; `Shield`
  builds its regen `Timer` there) must actually be in the tree. Add the host to the tree *first*,
  then add the component to the host. `Health` no longer needs a parent to take damage — its
  `get_parent().name` log line is now behind `OS.is_stdout_verbose()` and has a fallback.

## Coverage today

Autoloads: `MissionState`, `UpgradeState`, `ShipModuleState`, `ShipProgressionState`,
`SessionState`, `EventBus`, `DialogPlayer`, `CameraShake`.
Components: `Health`, `HitBox`/`HurtBox`, `Shield`, `TempHealth`, `Overheat`, `DamageReaction`.
Plus `global/statemachine/` and the `PlayerBase` damage chain.
Project-wide: `[ext_resource]` UID integrity across every `.tscn`/`.tres`.
Entities: the `space_station` mini-boss (`integration/test_space_station.gd`) — armour rule, turret
lifecycle, and the config-driven stats.
Levels: the `station_assault` section (`integration/test_station_assault_section.gd`) — the
`ENEMIES_CLEARED` gate, the per-section timeout and its free-on-expiry path, and Level 1's
section order and station wave.
Hazards: `LaserRay.hit_mask_override` (`integration/test_laser_ray_hit_mask.gd`) — pins the shared
default mask `128 | 256 | 512` so the race hazards and Level 1's laser columns cannot be silently
narrowed, and pins that `0` means "use the default" rather than "collide with nothing".
Entities, phase 2: the station laser phase (`integration/test_station_laser_phase.gd`) — the
`armor_broken` trigger and its once-only guard, the telegraph window (a beam damages a real
layer-128 probe HurtBox only after it arms, never during the warning), the self-damage regression,
the rotation rate, volley determinism, teardown on boss death, and the config copy.
Entities, the guns: `StationGunnery` (`integration/test_station_gunnery.gd`) — that the `BulletPool`
is a direct child of the station, both phases and the handover between them, per-turret aim and
barrel rotation, dead turrets dropping out of the volley, ring precession, the `core_ring_step`
design lock, teardown, and the config copy. Plus the shared pattern resource it drives
(`integration/test_radial_attack_pattern.gd`) — ring vs fan spacing, aiming, `spawn_radius`, that
it ignores `ship.rotation`, and that `bullet_count <= 0` fires nothing.
Entities, the adds: `StationReinforcements` (`integration/test_station_reinforcements.gd`) — the
config copy, four-edge coverage, that every squad entry starts off screen and clears the measured
spawn margin, deterministic `LEFT→RIGHT→BOTTOM→TOP` cycling, that ships are spawned as *siblings*
of the station with an `EnemyPathMover`, that every movement points into the screen, the
`FREE_ON_DURATION` guarantee, `enemy_spawned_orphan` registration, both stop signals, the
whole-squad population cap, the one-shot-timer split, that every ship the table can spawn is
killable by the player's primary weapon, and the two-ship escape-combo cost.

Two things that file had to work around, both worth knowing:

- **`died` cannot be tested without unhooking `armor_broken` first.** The station refuses all core
  damage while a turret lives, so the only route to `died` runs through `armor_broken` — which
  already stops the spawner. Without the disconnect, the case passes even if the `died` connection
  is deleted.
- **`ScoreTracker._process` resets any forced combo to 1.0 on the first frame** when
  `_combo_decay_remaining` is 0, and `start_tracking()` turns `_process` on. Call
  `tracker.set_process(false)` and assert on `tracker.get("_combo")`, as
  `integration/test_station_assault_section.gd` already does.

### Three traps `test_station_laser_phase.gd` had to work around

- **`SpaceStation.config` is a single process-wide object.** `space_station.gd` `load()`s the
  `.tres` and `ResourceLoader` caches, so every station in the process shares it — and it is the
  same object `preload()` hands the test. Writing to it to shorten the laser timings permanently
  rewrites the shipped values for every later test in the run. Override the **`LaserPhase` node's**
  own fields instead; it copies the config in `_ready()` and never reads it again.
- **`ExplosionEffect.explode()` parents its `CPUParticles2D` to `actor.get_parent()`** and lets it
  self-free on `finished` ~1 s later. A station added straight to the test script therefore leaves
  particles behind as unfreed children when the test that kills the core returns
  (`GUT WARNING: Test script has 2 unfreed children`). Parent entities that will die to a
  container `Node2D` that `add_child_autofree` owns — which is also how they are really parented,
  under `WaveManager.enemy_container`.

  **The same rule bites one level down, and cost a whole gate cycle.** For a `StationTurret` the
  "parent" `ExplosionEffect` writes into is the station's `$Turrets` node, so from the first turret
  kill onward `$Turrets.get_children()` also contains `CPUParticles2D`. A test helper doing a raw
  `get_children()` then hands back a particle node, `child as StationTurret` yields `null`, and the
  next method call fails with `Invalid call. Nonexistent function 'is_alive' in base 'Nil'` — an
  *Unexpected Error*, so GUT reds the test with no failed assertion to point at.
  **Always filter a container's children by type before casting.** `SpaceStation._turrets()` does,
  which is why production code never hit this.
- **A beam's full lifetime is longer than it looks.** At `warn 0.2 / active 0.3` it is ~1.9 s, not
  0.5: `warn` + a ~0.56 s `laser_increase` charge-up + `active` + a 0.84 s dissolve. Any test
  volley interval must exceed it, or a second volley spawns while the first is still dissolving and
  the child-count assertions become false rather than merely flaky.

Entities, the death: `StationDeathSequence` (`integration/test_station_death_sequence.gd`) — that
the wreck stays in the tree after HP hits 0, that `died`/`was_killed` still fire at that instant
(the `ScoreTracker` kill-vs-escape contract), the `_dying` latch against `Health`'s 0 → 0 re-emit,
the disarmed corpse, the free-after-duration path and the `death_duration = 0.0` boundary that
proves the new path is additive, the blast chain rolling across the hull, deterministic
`blast_offset(i)`, the decaying spin and darkening, and the config copy. Plus
`BulletPool.cancel_active()` in `test_station_gunnery.gd`.
Levels, end to end: `integration/test_level_1_sequence.gd` — Level 1's real five-section sequence
(`deep_space → asteroid_belt → station_assault → planet_approach → cloud_descent`) with a real
`SpaceStation` killed in the middle, asserting it reaches `level_complete`, that the boss section
does not advance while the wreck is present, and that the run finishes well inside the timeouts.

### The leak trap has a second half — zero `stagger_delay`, not just `spawn_delay`

`test_level_1_sequence.gd` compresses the real Level 1 sections to run in seconds. Zeroing every
`WaveResource.trigger_time` and `SpawnEntryResource.spawn_delay` is **not enough**:
`wave_manager.gd:143` expands a formation as `base_delay + slot.delay`, and every formation type
(v, wedge, line, diagonal, cluster) staggers its own slots. Level 1 uses formations heavily, so
~30 `_spawn_with_delay()` coroutines were left suspended holding `SceneTreeTimer`s after
`level_complete`.

That prints `ObjectDB instances leaked` at exit, which **does not match the gate's fatal-error
regex** — so the suite stayed green while leaking, exactly as the trap above describes. The fix is
`entry.formation.set(&"stagger_delay", 0.0)` alongside the other two. Safe for the same reason:
`wave_builder.gd:154-192` builds every formation with `.new()` per call, so nothing shipped is
shared.

⚠️ Separately, the `ObjectDB instances leaked` line the **gate** prints comes from step 1, the
headless `--import`, and predates this suite. Verified against a stashed working tree: baseline
and current both emit exactly one. Do not go hunting for it in the tests.
