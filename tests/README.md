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

## The exceptions: the integrity tests, the space-station tests, and the module unlock gate

`integration/test_resource_uid_integrity.gd` is **not** characterization. It asserts an invariant
that must hold — every `[ext_resource]` UID in a `.tscn`/`.tres` matches the UID its target
declares — so a failure there is a regression to fix, not a quirk to document.

It reads declared UIDs **from disk** (the `.tscn`/`.tres` header line, the sibling `.gd.uid`, the
sibling `.import`) and never asks `ResourceUID` / `ResourceLoader`. Those consult
`.godot/uid_cache.bin`, which is gitignored *and* keeps stale UIDs registered as working aliases
once a warm project has loaded them — so the engine will happily report a broken reference as fine
on your machine and break on a fresh clone. Five of the eight mismatches this test first caught
behaved exactly that way. If you extend it, keep it reading files.

`integration/test_suite_integrity.gd` is the other invariant test, and it polices this directory
rather than the game. **GUT fails open on a test script it cannot use:** `test_collector.gd:131`
drops it with nothing but a `[GUT WARNING]: Ignoring script … because it does not extend GutTest`
line, the summary reports a smaller `Scripts` count, and GUT still prints
`---- All tests passed! ----` and **exits 0**. The gate only reads the exit code and greps for a
failing-test count, so neither signal fires: a test file broken by a rename or a deleted symbol
used to vanish from the suite while the gate stayed green. That is what happened to
`test_space_station.gd` while it was being written — the red was read off stderr, not off GUT's
verdict.

The check therefore lives inside the suite, where every runner sees it rather than only the gate
script. It walks `res://tests` for `test_*.gd` and asserts each one compiles and reaches
`res://addons/gut/test.gd` through its base-script chain, so a script GUT would drop now fails a
real test and the exit code goes red. Two things to know before touching it:

- **A script with a parse error still `load()`s to a non-null `GDScript`.** The giveaways are
  `can_instantiate() == false`, an empty `get_base_script()` chain and an empty
  `get_instance_base_type()`. A null check would catch nothing.
- **Its walk mirrors GUT's own collection rules** — `test_` prefix, `.gd` suffix, per
  `gut_config.gd:45`, since the gate passes no `-gprefix`. If that ever changes, change both or
  the check quietly stops covering files.

`integration/test_module_unlock_sources.gd` is the third invariant test, and it polices game
content rather than the suite. It loads `sector_hub.tscn`, walks it for
`ShipModuleUnlockerPickup` nodes, and asserts every non-`&""` id in
`ShipModuleState.SLOT_MODULES` is granted by one of them. Since `equip()` gained its unlock gate,
a module with no unlocker is a row the player can see and can never install — so adding a module
to the catalogue without a source is a regression, and this is what says so. It also pins that no
unlocker grants a module belonging to a different slot: `ShipModuleUnlockerPickup.Module` is one
flat enum across all four slots, so a mismatched pair is expressible in the inspector and would
otherwise only `push_warning` at collect time. The hub is instantiated but never added to the
tree — `_ready()` is what spawns drones and builds the HUD, and walking the node list needs none
of it.

`integration/test_gut_local_patches.gd` is the fourth invariant test, and it polices the test
runner itself. GUT 9.7.1 does not load under Godot 4.6.3 without two hand-applied changes —
`godot_singletons.gd` drops the `AccessibilityServer` entry (the class does not exist in this
build, so the identifier fails to resolve) and `stub_params.gd` types `return_val` as an explicit
`Variant` (otherwise Godot infers `StringName` from `GutConstants.NOT_SET` and the getter's
`return null` branch will not parse). Both are written up in `addons/gut/LOCAL_PATCHES.md`, and
**re-vendoring GUT deletes them along with the doc.**

That failure is silent in exactly the way `test_suite_integrity.gd` describes: the parse errors go
to stderr, `gut_cmdln.gd` still runs the suite and exits 0, and the doubler is simply gone until
some later test reaches for it and fails for a reason that looks unrelated. So the test asserts
both patched files still parse — `can_instantiate()`, since a parse error still `load()`s to a
non-null `GDScript` — *and* that each patched path still behaves: `GutUtils.GodotSingletons.names`
is populated (proving `_static_init()` resolved every `class_ref` entry), an unset
`StubParams.return_val` reads back as `null` rather than leaking the `NOT_SET` sentinel, and a
stubbed one reads back unchanged. Every failure message names `LOCAL_PATCHES.md`, because the fix
is to re-apply the patches, not to relax the test. It also asserts the doc itself still exists.

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
behaviour is marked `CHARACTERIZED` in a comment, and the suspicion is filed as a task via
`./scripts/backlog-cli.js add-task code-health-backlog "<short head>"`. Do not "fix" the code to
make one of these read better without first deciding that the behaviour itself is wrong — the
point of the suite is that a behaviour change is a *visible* change.

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
Tooling: the two local patches the vendored GUT addon needs under Godot 4.6.3
(`integration/test_gut_local_patches.gd`).
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

### The ship module unlock gate

`unit/test_ship_module_state.gd` is still mostly characterization, but five of its tests assert
**intent** and say so in a comment: `equip()` now refuses a module that is not unlocked,
unlocking makes it installable, `&""` (unequip) is exempt so a slot can always be cleared, and
`_load()` grandfathers a module that is equipped but not unlocked rather than confiscating it.
One of those, `test_load_grandfathers_a_module_equipped_before_the_gate`, asserts the *exact*
unlocked array and loads twice on purpose. Both matter: `&""` passes the `if id in valid` check
in `_load()` because `SLOT_MODULES` lists it first for every slot, so an unguarded grandfather
append would pollute all four slots with the sentinel; and without the `not in list` guard the
list grows by one duplicate entry per boot, forever. `is_unlocked()` stays `true` under both
bugs, so a weaker assertion catches neither.

`integration/test_module_list_lock.gd` covers the menu side — that locked rows are shown greyed
rather than filtered out, that confirming one is a defined no-op, and (the boundary that matters)
that row 0, the "None"/unequip row, is **never** locked. `is_unlocked(slot, &"")` is always
`false`, so a naive per-row lock check greys out the unequip row and traps the player's module in
its slot; `player_menu.gd:180-184` is the game's only `equip()` caller, so there would be no
workaround. `test_confirming_an_unlocked_row_still_emits` is the deliberate control, so the
locked-confirm test cannot pass by `confirm()` being broken outright.

It reads and restores the **live `ShipModuleState` singleton** (`_unlocked` / `_equipped`) in
`before_all`/`after_all`, on top of `SaveSandbox` — `ModuleList` talks to the autoload, not to a
fresh instance, and the whole suite shares it. Setup mutates those arrays directly rather than
calling `unlock()`, so the fixture does not depend on the very gate under test.

⚠️ `test_reopening_rebuilds_the_lock_flags` reports **24 orphans**. They are the first `open()`'s
rows: `ModuleList._clear()` `remove_child()`s and `queue_free()`s them, and the delete queue does
not flush before the test ends. Pre-existing `ModuleList` behaviour, harmless in play (menu opens
are frames apart), and awaiting `process_frame` does not change the count. Not worth contorting
the test over — but do not read it as a leak you introduced.
