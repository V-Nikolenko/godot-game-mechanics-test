# BACKLOG

**Generated from `BACKLOG.json` - do not hand-edit this file.** Use the web UI at `:8099`, or `scripts/backlog-cli.js` from the agent. Edits here are overwritten on the next write.

## Migration note

This file was migrated from a flat checklist on 2026-09-03. The historical *Discovered* bugfix log (found-and-fixed defects, not tasks) is preserved below verbatim rather than modeled as board items.

---

<!-- The agent appends suspected bugs and follow-ups it found but did not act on. Triage these. -->

Found on 2026-08-31 while writing the characterization suite. Each one is **pinned by a passing
test that asserts the current behaviour**, so changing any of them will fail that test — which is
the signal that the change was deliberate. Test names are given so the fix has an obvious anchor.

- [x] **`Health.amount_changed` is declared with zero parameters but emitted with one.**
      `global/components/health_component.gd:4` declares `signal amount_changed`, and line 42
      emits `amount_changed.emit(current_health)`. One-argument handlers (`DamageReaction`,
      `PlayerBase._on_health_changed`) work, but any zero-argument handler raises
      `Error calling from signal 'amount_changed' ... Method expected 0 argument(s), but called
      with 1` at runtime. Fix is one line: `signal amount_changed(current: int)`.
      Same defect in `global/statemachine/state.gd:4` — `signal state_transition` is emitted with
      the target `State`. Pinned by `tests/unit/test_health_component.gd` (see the file header)
      and `tests/unit/test_state_machine.gd::test_states_request_transitions_through_their_own_signal`.
      **Fixed 2026-09-03.** Both declarations now name the argument they emit
      (`amount_changed(current_health: int)`, `state_transition(new_state: State)`). This is a
      readability/tooling fix only — it does **not** make a zero-argument handler legal, and
      `tests/README.md` now says so explicitly instead of describing the old shape. Two new intent
      tests read the declared arity back off `get_signal_list()`
      (`test_amount_changed_declares_the_int_it_emits`,
      `test_state_transition_declares_the_state_it_emits`), so the declarations cannot silently
      drift from the emits again. The rule is now a convention in `docs/architecture/PROJECT.md`.

- [x] **`StateMachine.change_state()` crashes if the machine has no current state.**
      `global/statemachine/state_machine.gd:29` does `print("Exiting previous state: " +
      current_state.name)` **before** the `if current_state:` guard on line 31. Any machine built
      without an `initial_state` (or whose state was cleared) dies on its first transition. Not
      reachable today because every shipped machine sets `initial_state`, so it is latent rather
      than live. Deliberately *not* covered by a test — the test would have to trigger the crash.
      **Fixed 2026-09-03.** The log line moved inside the `if current_state:` guard, together with
      the `exit()` call it sits next to. It **is** covered by a test now —
      `test_state_machine.gd::test_change_state_from_an_idle_machine_enters_without_crashing`
      builds a machine with no `initial_state` and transitions it; before the fix that test failed
      with `Invalid access to property or key 'name' on a base object of type 'Nil'`, which is
      exactly the crash, provoked deliberately in a place where it is harmless.

- [x] **`Health.decrease()` prints to stdout on every single hit.**
      `global/components/health_component.gd:34`. In a bullet-hell section that is one line per
      projectile per frame; `print` is not free and it buries real errors in the log. Should be a
      debug-gated helper or removed. `StateMachine.change_state` and `DialogPlayer` print
      unconditionally too (`[DP] ...` on every line of every conversation).
      **Fixed 2026-09-03.** All three now trace behind `if OS.is_stdout_verbose():`, so the
      messages survive for debugging (`godot --verbose ...`) but cost nothing in a normal run.
      Measured on the GUT suite: **181 lines** suppressed (173 `[Health]`, 6 `[StateMachine]`,
      2 `[DP]`), and a normal suite run now greps 0 for all three prefixes. `DialogPlayer`'s nine
      prints went through a `_trace()` helper; its `_unhandled_input` one is additionally
      guarded at the call site because `event.as_text()` allocates per input event.
      `Health.decrease()` no longer needs a parent, since the fallback replaced the bare
      `get_parent().name`. `dialog_box.gd`, `movement_controller.gd` and `dash_state.gd` have the
      same problem and were **not** in scope — refiled below.

- [x] **The turret sprite's barrels point at −Y and no turret sets `rotation`.** All four
      `space_station.tscn` turret instances are placed at `rotation = 0`, so every barrel points
      toward the top of the screen — *away* from the player, who is always below the station.
      **Closed 2026-09-02 by sub-item 4a**, at exactly the moment it predicted.
      `StationGunnery.fire_turret_volley()` sets each firing turret's `global_rotation` to
      `aim.angle() + PI/2` immediately before firing — `global_rotation`, not `rotation`, so it
      survives the laser phase spinning the hull. Pinned by
      `test_turret_barrels_face_the_player_when_firing`, which fails by ~180° against the pre-4a
      scene. The authored `rotation = 0` remains, as a spawn orientation.

## Code health backlog  (`code-health-backlog`, 30 open)

- [x] **Write the dossier for the completed station mini-boss epic** _(done)_
      into
      `docs/epics-done/station-mini-boss/` — `PRD.md`, `SOURCES.md`, `REPORT.md` per Stage 8
      of the `feature-workflow` skill. Everything needed is already in the six
      `docs/plans/station-*/` directories: merge their `2-research.md` source tables into
      `SOURCES.md`, and cover all five sub-items plus the rejected laser-phase plan
      (`479a66d`) in `REPORT.md`. Be specific in *Known gaps* — nothing in this epic has been
      played by a human, and the report should say so.
      *Done when:* the three files exist and every claim in `REPORT.md` names a commit, a test,
      or a plan file.

- [x] **GUT silently drops a test script it cannot load, and still exits 0.** _(done)_
      When
      `tests/integration/test_space_station.gd` referenced classes that did not exist yet, GUT
      printed `---- All tests passed! ----`, reported `Scripts 2` instead of 3, and **returned exit
      code 0**. The parse errors appeared only on stderr. `/agent/verify.sh` step 3 checks the exit
      code and greps for `^N failing`, so **neither signal fires** — a test file broken by a rename
      or a deleted symbol would vanish from the suite and the gate would stay green. Cheap fix:
      have step 3 also assert the script count, or grep its GUT output for `Parse Error` /
      `SCRIPT ERROR` the way steps 1 and 2 already do. This is the only reason the "watch it fail"
      step of the feature workflow worked here — the red was read off stderr, not off GUT's verdict.

- [x] **`UpgradeState.unlock()` accepts ids that are not in `ALL_IDS`.** _(done)_
      A typo'd id is stored and reported `true` by `is_unlocked()`, but `unlocked_ids()` iterates
      `ALL_IDS`, so it never appears in any menu — a silent, invisible failure. Compare
      `ShipModuleState.unlock()`, which validates and `push_warning`s. Pinned by
      `tests/unit/test_upgrade_state.gd::test_unknown_ids_are_stored_but_never_listed`.

- [ ] **`SessionState` recovers the temp-HP stack size with integer division.** _(in progress)_
      `global/autoloads/session_state.gd:85` computes `_temp_hp_stack = maximum /
      TempHealth.MAX_STACKS`. When `maximum` is not a multiple of 5 the stack size rounds down and
      the pool the player gets back after a level transition is smaller than the one they earned.
      Reachable whenever a ship's `base_health / 2` is not a multiple of 5. Pinned by
      `tests/unit/test_session_state.gd::test_temp_health_stack_size_uses_integer_division`.

- [ ] **`ShipModuleState.equip()` never consults `_unlocked`.** _(todo)_
      Any module in the catalogue can be
      equipped whether or not it was earned. Fine if unlock state is purely cosmetic for the menu;
      a progression hole if it is not. Worth a decision either way. Pinned by
      `tests/unit/test_ship_module_state.gd::test_equipping_does_not_require_unlocking`.

- [ ] **`MissionState.complete()` cannot record a zero-star clear.** _(todo)_
      `clampi(stars, 1, 3)` turns a
      0-star completion into 1 star. Intentional? Pinned by
      `tests/unit/test_mission_state.gd::test_stars_are_clamped_into_one_to_three`.

- [ ] **GUT 9.7.1 needs two local patches to load under Godot 4.6.3** _(todo)_
      , documented in
      `addons/gut/LOCAL_PATCHES.md`. `AccessibilityServer` does not exist in this Godot build, and
      a property getter in `stub_params.gd` fails type inference. Re-apply both on any GUT upgrade
      — without them the whole addon fails to parse and the doubler is unusable.
      
      Found on 2026-09-01 while fixing the stale `ext_resource` UIDs.

- [ ] **The Godot MCP `update_project_uids` tool is a no-op on this project — do not rely on it.** _(todo)_
      It concatenates `"res://"` onto the absolute project path it is given, so it searches
      `res:///tmp/coldclone/` (or `res:///work/repo/`), reports *"Found 0 scenes, Found 0
      scripts/shaders"*, and exits claiming success. Verified by md5summing all 151 `.tscn`/`.tres`
      before and after a run on a scratch copy: **zero files changed.** The bug is in the MCP
      server's own `godot_operations.gd`, not in this repo, so it cannot be fixed here. Use
      `tests/integration/test_resource_uid_integrity.gd` instead — it covers strictly more
      (`.tres` resources and `.gd.uid` sidecars as well as scenes).

- [ ] ****`.godot/uid_cache.bin` masks broken UID references, so a warm machine disagrees with a** _(todo)_
      fresh clone.** Once a project has been loaded, Godot keeps a *stale* UID registered as a
      working alias for its target: `ResourceLoader.get_resource_uid()` and `ResourceUID.has_id()`
      both reported the dead `uid://bi366j2tsyby` as valid, and `--import` emitted no warning for
      the five `.tres` files using it. Deleting `.godot/` and loading one of those files directly
      produced `ext_resource, invalid UID` immediately. `.godot/` is gitignored, so **CI and new
      contributors see the failures a developer's machine hides.** Two consequences worth keeping
      in mind: `bash /agent/verify.sh` runs against a warm cache and will not catch this class of
      defect on its own, and any future UID tooling must read declarations from disk rather than
      ask the engine.

- [ ] ****`godot --headless --import` only loads a fraction of the project, so "import is clean" is** _(todo)_
      a weak gate.** It surfaced 1 of the 3 live `invalid UID` warnings; the other 2 only appeared
      once every scene was actually loaded. A cheap "load all 126 `.tscn`/`.tres` and assert no
      load returns null" smoke test would close the gap — worth considering as step 4 of
      `/agent/verify.sh`. All 126 do currently load clean, so it would start green.

- [ ] **Several resources declare hand-written UIDs in their own headers** _(todo)_
      — `uid://hudscore001`
      (`assault/scenes/gui/hud_score_widget.tscn`), `uid://braceasteroid01`, `uid://00246ccaem53`,
      `uid://0024uci15m53`, `uid://00243s3wxf53` (the `assault/scenes/race/` scenes). Godot 4.6.3
      parses and registers all of them, and every reference to them resolves, so **nothing is
      broken and they were deliberately left alone.** Flagging them only because they are the same
      fingerprint as the eight references that *were* broken: a UID typed by a human or an agent
      rather than minted by the editor. If one is ever duplicated onto a second resource the
      collision will be silent.
      
      Found on 2026-09-01 while building the space-station mini-boss entity (EPIC sub-item 1).

- [ ] **`Gunship` never applies its config's `collision_damage`.** _(todo)_
      `gunship_config.tres:8` sets
      `collision_damage = 30`, but `BaseEnemy._add_contact_hitbox()` hardcodes `hb.damage = 20`
      (`base_enemy.gd:56`) and the gunship — unlike `bomber.gd:25`, `light_assault_ship.gd:23`,
      `ram_ship.gd:20-23` and `drone_interceptor.gd:148` — never re-applies it after
      `super._ready()`. So the heaviest enemy in the roster rams for 20 instead of 30 and the
      `.tres` value is dead. One loop in `gunship.gd::_ready()` fixes it; it is a balance change,
      so it should be a deliberate one rather than folded into unrelated work. `space_station.gd`
      does apply it, so the two enemies currently disagree about whether the field means anything.

- [ ] ****`base_enemy.gd:56-59` builds the contact HitBox from `col.shape` but drops the** _(todo)_
      `CollisionShape2D`'s `scale` and `position`.** Every enemy that scales its collision shape in
      the scene therefore gets a contact hitbox of the wrong size — `gunship.tscn:63-65` scales by
      2.31, so its contact hitbox is ~2.3× too small. Harmless-ish at 40 px, badly wrong at boss
      scale. `space_station.tscn` sidesteps it by authoring its shape at true size with `scale = 1`,
      but the underlying helper is still lossy for everyone else. Copying the node's transform
      onto the new `CollisionShape2D` would fix it — though it would silently enlarge several
      existing enemies' contact hitboxes, so it needs a balance pass, not a blind fix.
      
      Found on 2026-09-01 while adding the `station_assault` section (EPIC sub-item 2).

- [ ] ****A test that ends while a `LevelDirector` coroutine is suspended leaks — and the gate stays** _(todo)_
      green.** `_wait_enemies_cleared()` awaits `_wait_for_child_exit_or_timeout(container, 1.0)`,
      which holds a `SceneTreeTimer`. If the test returns while that is pending, freeing the
      director strands the timer and its `GDScriptFunctionState`, and Godot prints at process exit:
      `WARNING: ObjectDB instances leaked at exit` and
      `ERROR: 1 resources still in use at exit` / `Resource still in use: …/level_director.gd`.
      **Neither line matches `/agent/verify.sh`'s `FATAL` regex**, so the gate passed while leaking
      — I only noticed by diffing a run with and without the new file. Two follow-ups worth
      considering: add `ObjectDB instances leaked|resources still in use` to the gate's fatal
      patterns (check the existing suite is clean first — it is, verified this run), and consider
      whether `_wait_for_child_exit_or_timeout` should hold the timer in a variable it can cancel.
      Worked around in `tests/integration/test_station_assault_section.gd` and written up in
      `tests/README.md`.

- [ ] **Should the station's core hurtbox be narrowed to 88 x 240? — a design question, not a bug.** _(todo)_
      `space_station.tscn:16-17` uses ONE 240 x 240 `RectangleShape2D` for both the body collider
      and the core `HurtBox`, so the core's hurtbox spans the whole hull and the four turret
      hurtboxes sit strictly inside it. This is **not** a reachability bug — see the next item —
      but it does mean shooting the hull shoulders registers as a deflected core hit rather than
      missing, and a bullet fired up a turret lane triggers a core deflection *before* it reaches
      the turret. Giving the `HurtBox` its own 88-wide shape would make the x-extents disjoint
      ([-44, 44] vs [50, 102]) and the "shoot the guns, then the core" read cleaner. It was
      planned, then dropped when its stated justification collapsed; it needs a deliberate
      design call, not a bug fix. Cost: one `sub_resource` and one node property.

- [ ] ****Two consecutive reviews asserted that a player bullet dies on its first hurtbox overlap.** _(todo)_
      It does not — worth knowing before anyone reasons about projectile lifetime again.**
      `BulletPool` is constructed only by `light_assault_ship.gd:27`, `gunship.gd:52`,
      `interceptor.gd:30`, `ally_fighter.gd:22` and `racer_weapon.gd:11` — **never by the player**.
      `straight_behavior.gd:22` does a plain `state.add_child(bullet)`. Repo-wide there are exactly
      two connections to `Bullet.expired` (`bullet_pool.gd:56`, `sniper_enemy.gd:102`), and
      `bullet.gd:84` emits `expired` **without** `queue_free()`; the only `queue_free()` is `:49`,
      gated on `range_px > 0.0`, which `weapons/modes/default.tres` sets to `0.0`. So a default
      player bullet has no listener on `expired` and flies on with a live HitBox, damaging every
      hurtbox in its lane until it leaves the screen. Consequence worth a separate decision: the
      player's default shot is effectively **infinitely piercing against stacked hurtboxes**, which
      makes `PierceModule` (`pierces_remaining`, `MAX_PIERCE = 3`, `PIERCE_DAMAGE_FACTOR = 0.55`)
      look like it exists to *limit* damage rather than add it. That is probably not intended and
      is a real balance question for multi-part targets.

- [ ] **`test_space_station.gd`'s collision-layer coverage gap is still open.** _(todo)_
      Sub-item 1 recorded
      it as provable "once the station is in a live level (sub-item 2)". Sub-item 2 has landed and
      does **not** close it: `test_station_assault_section.gd` asserts section gating and wave data,
      never a projectile overlap. Closing it needs a test that instances
      `assault/scenes/projectiles/bullets/bullet.tscn`, positions it in a turret lane and steps
      physics — the suite has no precedent for physics-overlap tests, so budget for the technique.
      `ENEMY.md` and `tests/README.md` now say this plainly instead of promising it is coming.
      
      Found on 2026-09-01 while regenerating the turret sprites.

- [ ] ****`station_core.png` has a fully opaque background — the station will render as a grey** _(todo)_
      square in space.** Measured: **65536/65536 pixels at alpha 1.0**, corner alpha `1.00`
      (`station_turret.png`, regenerated this run, is 54.7% opaque with corner alpha `0.00`, which
      is what a sprite should look like). The cause is the same one behind the 3/4 turrets: the
      core was made with `create_image_pixflux`, whose `no_background` defaults to unset and is
      treated as `False` when there is no init image — it paints a background unless you pass
      `no_background=True`. `create_map_object` is transparent by construction, which is why the
      two regenerated turrets came back correct without anyone asking. Nobody has seen it yet
      because the station is
      never drawn against the starfield in any test — it only became visible when I composited the
      core and four turrets together for the mandatory visual check. **Not fixed this run**: the
      backlog item was scoped to the turrets, and replacing the core is a separate generation plus
      a fresh visual check. Fix by regenerating with `create_map_object` (max canvas is 400×400, so
      256×256 fits), or by alpha-keying the existing grey if the art is worth keeping.

- [ ] **This container has no `file`, no `python3` and no `xxd` — only `od`.** _(todo)_
      `scripts/pixellab.sh`
      called `file -b` unconditionally under `set -euo pipefail`, so **every `save-b64` and
      `download` aborted with exit 127 after having already written the file** — a confusing
      half-success. Fixed this run by adding a `sniff_magic()` fallback that reads PNG/JPEG/WEBP
      magic bytes with `od` when `file` is absent; the `file` path is unchanged where it exists,
      and both the success and the rejection path were tested. Flagging the wider point: any future
      tooling here should assume a **minimal** userland. Note also that the previous cycle's
      sprites were saved without the script ever succeeding, which is probably why nothing caught
      this until now.
      
      Found on 2026-09-02 while planning the station laser phase (EPIC sub-item 3). Both were measured
      at runtime by the plan reviewer on Godot 4.6.3, not inferred.

- [ ] ****Every enemy that does `@export var config = load(...)` shares ONE config resource** _(todo)_
      process-wide, and it is the same object `preload` hands a test.** `ResourceLoader` caches, and
      the scenes store no override, so `station_a.config == station_b.config == preload(".../space_station_config.tres")`
      is `true` — verified. Writing to one enemy's `config` at runtime therefore rewrites the
      shipped `.tres` values in memory for **every** instance and for **every later test in the
      same process**. This is not hypothetical: it is exactly the trap that got the laser-phase
      test plan rejected in review round 2, because a test that tuned timings through `config`
      would have silently clobbered the values a later test asserts. The pattern is used by
      `space_station.gd:24` and, by inspection, the other `*_config.tres` enemies
      (`bomber.gd`, `ram_ship.gd`, `light_assault_ship.gd`, `gunship.gd`). Worth either a
      `duplicate()` on assignment, or a line in `tests/README.md` warning that config resources are
      shared and must never be mutated from a test. No test pins this today.

- [ ] **`spike/test_spike_laser.gd` and `spike/test_spike_selfkill.gd` are tracked dead code.** _(todo)_
      `git ls-files spike/` lists both plus their `.uid`s.
      `docs/plans/station-laser-phase/1-context.md` claimed they had been "deleted afterwards";
      they had not, and the claim has now been corrected in place. They sit outside
      `-gdir=res://tests` so the gate never runs them, which means they can rot against
      `laser_ray.gd` / `space_station.gd` without anything noticing — and they are written against
      exactly the scripts the laser phase changes. Delete them (they are step 1 of
      `docs/plans/station-laser-phase/3-plan.md`), or move them under `tests/` so the gate keeps
      them honest. They are genuinely useful as fixtures: they demonstrate the layer-128 stub
      `HurtBox`, `wait_seconds` beam stepping, and the self-kill reproduction.
      
      Found on 2026-09-02 while implementing the station laser phase (EPIC sub-item 3).

- [ ] **`ExplosionEffect` orphans its particles onto whatever the dying entity's parent is.** _(todo)_
      `global/components/explosion_effect.gd:28-52` adds the `CPUParticles2D` to
      `actor.get_parent()` and relies on `p.finished.connect(p.queue_free)` to clean up ~1 s later.
      In-game that parent is `WaveManager.enemy_container`, so it is harmless. In a test it is
      whatever node the test used, and any test that kills an entity added straight to the test
      script ends with `GUT WARNING: Test script has 2 unfreed children`. Worked around in
      `tests/integration/test_station_laser_phase.gd` by parenting through a container `Node2D`
      (documented in `tests/README.md`), but the component itself would be tidier if the particles
      were parented to the entity's *owner-scene* root, or if `explode()` took an explicit
      container. Worth deciding before sub-item 4 adds many more deaths per fight.
      **Update 2026-09-02 — it bit again, one level down, and cost a full gate cycle.** For a
      `StationTurret` the parent `explode()` writes into is the station's `$Turrets` node, so from
      the first turret kill onward `$Turrets.get_children()` contains `CPUParticles2D` mixed in
      with the turrets. `test_station_gunnery.gd`'s `_turrets()` helper did a raw `get_children()`,
      so `child as StationTurret` returned `null` and the next call died with
      `Invalid call. Nonexistent function 'is_alive' in base 'Nil'` — an *Unexpected Error*, which
      GUT reds with no failing assertion to point at, so it reads as unrelated. Fixed in the test
      by filtering to `StationTurret` (what `SpaceStation._turrets()` already does), and the trap
      is now written up in `tests/README.md`. This is the second workaround for the same component;
      an explicit container argument on `explode()` would have prevented both.

- [ ] **The station's collision-layer coverage gap is now only half open.** _(todo)_
      `assault/scenes/enemies/space_station/ENEMY.md` records that
      `tests/integration/test_space_station.gd` drives damage by emitting `received_damage`
      directly and so proves nothing about collision layers.
      `tests/integration/test_station_laser_phase.gd` does now exercise a **real** physics overlap
      — a layer-128 stub `HurtBox` placed in a beam's path, found by the beam's own `Area2D` — but
      only for the *player* layer and only against a `LaserRay`. Nothing yet proves a player
      **bullet** can hit the core's layer-512 hurtbox or a turret's. Closing it still needs a test
      that instances `assault/scenes/projectiles/bullets/bullet.tscn` and steps physics.
      
      Found on 2026-09-03 while implementing station reinforcements (EPIC sub-item 4b).

- [ ] **`ram_ship` cannot be hit by the player's primary weapon, and its config HP is dead code.** _(todo)_
      `assault/scenes/enemies/ram_ship/ram_ship.gd:19` narrows the HurtBox mask to
      `33` (`# missiles only (32 + 1); bullets ignored`) after `BaseEnemy._ready()` has set the
      normal `97 | 1024`. The player's bullet is `collision_layer = 64`
      (`assault/scenes/projectiles/bullets/bullet.tscn:44`), so **no bullet ever reaches it**;
      `bullet.gd:71` additionally has a `ram_ships`-group node *consume* a piercing sniper shot and
      zero its damage. On top of that `ram_config.tres:8` sets `max_health = 999` and
      `ram_ship.gd:16-17` never applies it (only `movement_speed`), so the scene's bare `Health`
      default is what actually runs — the number a reader would look up is fiction.
      Whether the immunity is intended is a **design call**, so it is filed rather than fixed:
      either it is a deliberate dodge-only obstacle, in which case
      `docs/enemy-roster.md:127`'s "**HP:** Medium" is misleading and should say so, or it is a bug
      and the mask should be the inherited one. Either way `ram_config.tres`'s `max_health` should
      be applied or deleted. 4b swapped its top squad to `fighter` to avoid the question, and
      `tests/integration/test_station_reinforcements.gd` now asserts every squad ship is
      bullet-killable so the class of mistake cannot recur silently.

- [ ] **The 0.75× escape-combo penalty applies to ad-hoc spawns nobody expects to kill.** _(todo)_
      `assault/scenes/systems/score_tracker/score_tracker.gd:211` multiplies the combo by
      `escape_combo_multiplier` **outside** the `if counts_in_wave:` block, so a `wave_index` of
      `-1` (every `EventBus.enemy_spawned_orphan` spawn) is not exempt, and neither is
      `counts_toward_wave_clear = false`. Station reinforcements are designed to fly through, so a
      player who correctly ignores a squad to focus the boss pays 0.75 twice per squad (0.5625) and
      floors their multiplier after about three. `Level1Director._spawn_bonus_drone` has the same
      shape but a bonus drone is a rare optional pickup, not six scheduled ships.
      4b **accepted this deliberately** — the alternative is that killing a reinforcement awards
      nothing at all, which reads as a bug — and pinned the exact number in
      `test_station_reinforcements.gd`. Recording it so the user can overrule: the fix, if wanted,
      is a `counts_as_escape` flag on the spawn rather than a special case for one enemy source.

- [ ] **A spawn's off-screen margin cannot account for camera pan, project-wide.** _(todo)_
      Every spawn in the game resolves its offset against `cam.global_position`, which
      `arena_camera.gd:5-12` pins at (640, 360) and never moves — panning happens through `offset`.
      So a player panned fully down (`V_LIMIT` is 380) can in principle watch a bottom-edge spawn
      appear. 4b matched the existing convention rather than diverging for one node, and excluded
      `V_LIMIT` from its vertical margin budget on purpose. Fixing it properly means spawns
      resolving against the *visible* rect rather than the camera centre, which touches
      `wave_manager.gd:172` and every spawn offset in the game — not a 4b-sized change.
      
      Found on 2026-09-03 while building the station death sequence (EPIC sub-item 5).

- [ ] ****`race_ship.gd:97-100` renders its death explosion at the container origin, not at the** _(todo)_
      ship.** It does `get_parent().add_child(boom)` then `boom.global_position = global_position`
      — but `ExplosionEffect.explode()` reads `actor.global_position` where `actor` is the effect's
      *parent*, so the position written on line 99 is silently discarded and every race-ship
      explosion appears at the container's origin. Confirmed by reading the code and by the
      independent reviewer of `docs/plans/station-death-handoff/`. **Deliberately not fixed in that
      cycle:** it is unrelated to the mini-boss and fixing it visibly moves race-mode explosions,
      which deserves its own before/after check. `explode()` now takes an optional position
      argument, so the fix is one line: `boom.explode(global_position)`. No test pins the current
      behaviour, so nothing will fight the change.

- [ ] **The gate's step 1 (`godot --headless --import`) leaks ObjectDB instances.** _(todo)_
      It prints
      `WARNING: ObjectDB instances leaked at exit` plus a few RID-allocation errors on every run.
      Pre-existing and **not** caused by the test suite — verified by running the import against a
      stashed working tree: baseline and current both emit exactly one occurrence, while the GUT
      step emits none. Harmless today (the gate does not match on it), but it is noise that will
      mask a real leak if one ever appears in step 1, and it costs time to re-diagnose. Worth one
      cycle to find what the importer is holding.

- [ ] **`ExplosionEffect`'s container resolution is a footgun worth a guard.** _(todo)_
      `explode()` resolves
      its target as `get_parent().get_parent()` with no check on what that is, so attaching the
      effect one level too deep silently parents the particles inside the entity instead of the
      container — they are then freed with the entity and inherit its rotation, with no error. This
      is the same shape of trap as `bullet_pool.gd:47`, which the space-station scene warns about
      twice in comments. A `push_warning` when the resolved container is itself an ancestor-owned
      node, or an explicit `container` export, would turn a silent visual bug into a loud one.
      
      Found on 2026-09-03 while fixing the shared-component signal/logging defects.

- [ ] ****Three more files print unconditionally on hot paths — same defect as the one just fixed,** _(todo)_
      out of the item's stated scope.** `global/ui/dialog_system/ui/dialog_box.gd` has **11**
      prints (`[DB] ...`), several per dialog *line*, including inside tween callbacks;
      `assault/scenes/player/movement_controller.gd:74,79` print `"first/second time pressed …"`
      on **every double-press-eligible key press**, i.e. constantly during normal play; and
      `assault/scenes/player/states/dash_state.gd:54` prints on every dash attempt made during
      cooldown, so mashing dash spams it. The fix is mechanical and already has a precedent in
      three files: wrap in `if OS.is_stdout_verbose():` or route through a `_trace()` helper.
      The convention is now written down in `docs/architecture/PROJECT.md` → Conventions, so this
      is a tidy-up, not a decision. Lower-traffic leftovers, for completeness:
      `wave_manager.gd` (4), `level_1_director.gd` (4), `level_2_waves.gd` (3),
      `level_director.gd` (3), `ally_fighter.gd` (2), `boot.gd` (2),
      `skill_challenge_runner.gd` (2), `score_tracker.gd` (1), `level_1_background.gd` (1).

- [ ] **Declaring a signal's parameters does not stop the mismatch it looks like it stops.** _(todo)_
      Worth knowing before someone "fixes" the next one and assumes the problem is gone. **Measured
      on Godot 4.6.3 with a throwaway `SceneTree` probe**, not inferred: a signal's declared arity
      is **documentation only**. `signal foo` and
      `signal foo(x: int)` behave identically at `emit()` time, and connecting a zero-argument
      callable to either is accepted at connect time (`connect()` returns `OK` in both cases) and
      errors identically at emit time with `Method expected 0 argument(s), but called with 1`.
      The one thing that does differ is `Object.get_signal_list()`, which reports the declared
      arity — 0 vs 1 — which is exactly why the new tests assert against it. So the 2026-09-03 fix made
      `Health.amount_changed` and `State.state_transition` honest to a reader and to editor
      completion, and nothing more. Anything that wants a *real* guarantee has to assert the
      arity from a test the way `test_amount_changed_declares_the_int_it_emits` does, by reading
      `Object.get_signal_list()`.

- [ ] **The reflect -> AbilityState migration was abandoned half-done.** _(todo)_
      `docs/superpowers/plans/2026-05-06-abilities-health-shield.md` planned to replace the
      `reflect` upgrade with an `AbilityState` autoload. Only part of it landed:
      
      - `&"reflect"` WAS removed from `UpgradeState.ALL_IDS` (Step 5, done).
      - The `reflect` input action WAS replaced by `use_ability` in `project.godot:101` (Step 3, done).
      - `AbilityState` was NEVER created (Step 1/2 — `global/autoloads/` has no `ability_state.gd`,
        and `project.godot` has no such autoload).
      
      The leftover is `assault/scenes/player/states/reflect_state.gd`: 80 lines of working
      parry/reflect logic that is dead three times over — no `.tscn` instances it, its
      `_on_action("reflect")` waits on an input action that no longer exists, and its
      `UpgradeState.is_unlocked(&"reflect")` gate is on an id nothing unlocks.
      
      Decide one way or the other: either finish the migration (build `AbilityState`, wire
      `reflect_state.gd` to `use_ability`) or delete the script and drop `&"reflect"` from
      `UpgradeState.ABILITY_IDS`. Right now it is a trap — it reads as a live feature.

- [ ] **`long_range.tres` is an orphaned weapon mode with no id in ALL_IDS.** _(todo)_
      `assault/scenes/player/weapons/modes/` contains six `.tres` files but
      `UpgradeState.ALL_IDS` names only five: `default`, `sniper_shot`, `spread`, `gatling`,
      `mining_laser`. `long_range.tres` matches no id.
      
      `WeaponState._load_modes()` (`assault/scenes/player/states/weapon_state.gd:31-37`) iterates
      ALL_IDS and skips paths that do not exist, so the resource is simply never loaded — the
      weapon cannot be selected, cycled to, or shown in the player menu. The behaviour is a
      `LONG` entry in `_build_behaviors()` (`weapon_state.gd:41`) that nothing can ever reach.
      
      Either add `&"long_range"` to `ALL_IDS` (it needs a `_WEAPON_ICONS` entry in
      `global/ui/player_menu/player_menu.gd` too) or delete the `.tres` and the `LongRangeBehavior`
      wiring. Same abandoned-migration origin as the reflect item — the plan at
      `docs/superpowers/plans/2026-05-06-abilities-health-shield.md` renamed the mode list.

## Foundations: test harness, UID integrity, art pipeline  [DONE]  (`foundations-test-harness-uid-integrity-art-pipeline`, 0 open)

- [x] **Bootstrap the test harness.** _(done)_
      Install GUT into `addons/gut/`, create `tests/`, and write
      characterization tests for the eight autoloads and the `global/components/` set (Health,
      Hurtbox/Hitbox, Shield, Overheat, DamageReaction). Tests must pin down current behaviour,
      bugs included — no fixes this run. Done when `bash /agent/verify.sh` passes with a green
      suite. *(The agent does this automatically while `addons/gut/` is missing, ignoring
      everything below.)*
      **Done 2026-08-31** — GUT 9.7.1 vendored into `addons/gut/` (two files patched for Godot
      4.6.3, see `addons/gut/LOCAL_PATCHES.md`), 153 tests / 490 asserts across 16 scripts in
      `tests/`, gate green. Conventions and the gotchas that cost time are in `tests/README.md`.

- [x] **Fix the stale UID in `open_space/scenes/gui/hud.tscn:6`.** _(done)_
      Its `ext_resource` for
      the pause menu declares `uid://bospm3nuos001`, but
      `global/ui/pause_menu/open_space_pause_menu.tscn` actually declares
      `uid://b10bam3tnq6vw`. Godot currently falls back to the text path and only warns, so
      nothing is broken — but the fallback disappears if that scene is ever moved. Fix the
      reference, then run the Godot MCP `update_project_uids` tool and check whether any
      other file has the same problem. Done when `godot --headless --import` is warning-free.
      **Done 2026-09-01** — it was **8** stale references, not 1, in 8 files: `assault/scenes/gui/hud.tscn`,
      `assault/scenes/levels/level_2.tscn`, `open_space/scenes/gui/hud.tscn`, and the five
      `open_space/scenes/mission_data/planets/**/…_infiltration_mission_*.tres`. All 8 named a UID
      no resource declares. Added `tests/integration/test_resource_uid_integrity.gd` (3 tests) so
      the class of defect cannot come back. Verified on a **cold** `.godot/` cache by loading all
      126 `.tscn`/`.tres`: 3 `invalid UID` warnings before, 0 after, 0 load failures.
      The suggested `update_project_uids` MCP step is a no-op — see *Discovered*.
      
      ---

- [x] **Regenerate the turret sprites — `station_turret.png` is 3/4 view, not top-down.** _(done)_
      The barrel is drawn from the side with visible cylinder faces and the base sits in
      perspective; `station_core.png` in the same set is correctly overhead, so the set is
      visually inconsistent. Root cause: PixelLab was almost certainly called with
      `view: "low top-down"`, which is the 3/4 look.
      **Invoke the `pixel-art-generation` skill first.** Regenerate with
      `view: "high top-down"` and `isometric: false`, describing the shape as seen from
      above (base reads as a circle, barrel as a short flat rectangle lying across it),
      plus the negative constraints. Regenerate `station_turret_destroyed.png` to match.
      Save with `./scripts/pixellab.sh save-b64` — **never** the Write tool, it corrupts
      PNG data. Re-import so the `.import` sidecars update.
      *Done when:* both turret sprites have been opened with the Read tool and confirmed
      to show no side faces, and they sit consistently beside `station_core.png`.
      **Done 2026-09-01** — the guessed root cause was wrong in an instructive way. It was not
      `view: "low top-down"`; it was the **tool**. The originals came from `create_image_pixflux`
      (`docs/plans/station-mini-boss-destructible/5-progress.md:19`), whose `view` **defaults to
      `null` and is documented as "weakly guiding"** — so it was never set, and setting it would
      only have been a soft hint anyway. `create_map_object` defaults it to `"high top-down"` and
      honours it. The skill has been corrected: it previously named `low top-down` as "the most
      likely cause of a wrong-angle sprite in this project", which would have sent the next run
      hunting for a wrong value rather than a wrong tool.
      Regenerated with **`create_map_object`** (`view: "high top-down"`, `outline: "lineless"`,
      `detail`/`shading` medium, 64×64) and the destroyed variant with **`create_object_state`** off
      the intact one, which keeps the footprint and palette aligned for free. `isometric` is not a
      parameter on either tool — the negatives went in the description instead. **2 generations
      used**, no aesthetic iteration. Both opened at 6× and composited with `station_core.png` at
      true in-game layout (256×256 hull, turrets at ±76): no side faces, no tilt, transparent
      backgrounds (corner alpha `0.00`, was opaque before), and the dead turrets read as burnt
      craters against the light hull. Provenance and the exact prompt shape are now in `ENEMY.md`
      so a future regeneration cannot repeat the mistake. Two defects found in passing — an opaque
      `station_core.png` and a broken `scripts/pixellab.sh` — are under *Discovered*.

## Level 1 space-station mini-boss  [DONE]  (`station-mini-boss`, 0 open)

- [x] **1. Station and turrets exist as a destructible entity.** _(done)_
      Generate the station and turret
      sprites via PixelLab. Assemble the station scene with N turrets as child entities, each
      individually damageable. The station core takes no damage while any turret is alive.
      *Done when:* a GUT test destroys turrets one at a time and proves the core is invulnerable
      until the last turret dies, then becomes damageable.
      **Done 2026-09-01** — `assault/scenes/enemies/space_station/` (`SpaceStation extends BaseEnemy`
      + 4 `StationTurret` children + `SpaceStationConfig`), three PixelLab sprites, and
      `tests/integration/test_space_station.gd` (9 tests). Gate green: 165 tests / 527 asserts.
      Core refuses damage via a `_on_received_damage` override while keeping the HurtBox **live**,
      because `plasma_nova_module.gd:39-41` and `beam_behavior.gd:99-102` both emit
      `received_damage` directly and a disabled hurtbox would leak both. Plan + two review rounds:
      `docs/plans/station-mini-boss-destructible/`. **Known gap:** the tests emit `received_damage`
      directly, so they do not prove the collision layers — that needs sub-item 2.
      → [docs/plans/station-mini-boss-destructible](docs/plans/station-mini-boss-destructible)

- [x] **2. The encounter blocks level progress.** _(done)_
      Add a new `LevelSection` (suggested name
      `station_assault`) to `level_1_director.gd`, between `asteroid_belt` and `planet_approach`,
      using `ENEMIES_CLEARED`. Add the matching `phases/phase_station_assault.tres`.
      *Done when:* a headless test proves the section does not advance while the station lives,
      and advances to `planet_approach` when it dies.
      **Done 2026-09-01** — `station_assault` is Level 1's third section. New
      `LevelSection.enemies_cleared_timeout` (default `10.0`, so `cloud_descent` is bit-identical;
      the station sets `180.0`), `LevelDirector` now **frees leftover container children on
      expiry** instead of dragging the boss into the next section, `WaveBuilder.space_station()`,
      `phases/phase_station_assault.tres`, and a `_build_sections()` refactor that makes the
      section order assertable without booting the level.
      `tests/integration/test_station_assault_section.gd` (7 tests). Gate green: 19 scripts /
      172 tests / 551 asserts.
      Plan + **two** review rounds: `docs/plans/station-assault-section/`. Round 2 **withdrew**
      round 1's blocking finding — see *Discovered*; that reversal is the most useful thing this
      cycle produced.
      → [docs/plans/station-assault-section](docs/plans/station-assault-section)

- [x] **3. Laser phase.** _(done)_
      Once all turrets are destroyed, the station rotates and fires
      `LaserRay` beams at varying positions, forcing the player to keep moving. Beams must
      telegraph before they damage (`warn_duration`) — an instant-kill beam with no tell is
      unfair, and research should set the actual timing.
      *Done when:* a test proves the phase only starts after the last turret dies, and that a
      beam damages the player only during its active window, not its warning window.
      **Done 2026-09-02.** New `StationLaserPhase` (`station_laser_phase.gd`, wired into
      `space_station.tscn` as `LaserPhase`), a zero-arg `SpaceStation.armor_broken` signal with a
      once-only latch, five laser fields on `SpaceStationConfig` + the `.tres`, and an additive
      `LaserRay.hit_mask_override` export. `tests/integration/test_station_laser_phase.gd`
      (12 tests) + `test_laser_ray_hit_mask.gd` (4 tests). Gate green: 21 scripts / 188 tests /
      605 asserts.
      Plan + **three** review rounds: `docs/plans/station-laser-phase/`. Rounds 1 and 2 were
      CHANGES_REQUESTED and were worth every minute — round 1 caught that the headline "the boss
      must not kill itself with its own beam" test **could not fail** as specified (only the
      *diagonal* volley angles overlap the core hurtbox), and round 2 caught that the test plan
      would have clobbered the process-wide shared config `.tres`. Round 3 verified both fixes at
      runtime and approved.
      Two things a future cycle should not have to rediscover: the station's beams **must** set
      `hit_mask_override = 128` before `add_child()` or the boss kills itself in one frame
      (`600 → 0 HP`, reproduced), and the volley angles are a fixed list, never `randf()` — random
      attack ordering cannot be balanced or tested.
      
      **Split on 2026-09-02** into 4a (the station's own fire) and 4b (reinforcements). One
      session each; 4a is the half that changes the first phase from passive to a fight.
      → [docs/plans/station-laser-phase](docs/plans/station-laser-phase)

- [x] **4a. The station shoots back.** _(done)_
      Turrets and core fire bullet-hell patterns through
      `bullet_pool`.
      *Done when:* every live turret fires an aimed pattern, killing a turret removes its gun from
      the volley, the core fires its own pattern once the armour breaks, projectiles route through
      `bullet_pool`, and a headless run produces no errors.
      **Done 2026-09-02.** `StationGunnery` (`assault/scenes/enemies/space_station/station_gunnery.gd`)
      as a sibling node of `StationLaserPhase`, driving a new shared
      `global/resources/attack/radial_attack_pattern.gd` (`RadialAttackPattern` — one resource
      covering both the ring and the fan). Ten new `SpaceStationConfig` fields; `BulletPool` +
      `Gunnery` authored into `space_station.tscn`. Tests: `test_station_gunnery.gd` (16) +
      `test_radial_attack_pattern.gd` (10). Gate green: 23 scripts / 214 tests / 767 asserts.
      Plan + **two** review rounds: `docs/plans/station-bullet-hell/`. Round 1 was
      CHANGES_REQUESTED and earned its keep twice over — it caught that the planned
      `_station.add_child(_pool)` from the gunnery's `_ready()` **cannot work** (`_propagate_ready()`
      blocks the parent while readying its children), and that the planned `core_ring_step = 0.21`
      had exactly the defect the research said to avoid: `3 × 0.21 ≈ 0.6283` = the ring spacing, so
      rings collapse onto three radial lanes and leave a permanent safe lane. Shipped value is the
      golden-angle `0.24`, and a test now locks it.
      Two things a future cycle should not have to rediscover: the `BulletPool` **must** stay a
      direct child of `SpaceStation` (`bullet_pool.gd:47` hardcodes `get_parent().get_parent()`, so
      anywhere else the whole bullet field rotates with the hull), and a `node_paths=` tag on the
      `Gunnery` node is required or the exported reference is silently left null **with the gate
      still green**.
      → [docs/plans/station-bullet-hell](docs/plans/station-bullet-hell)

- [x] **4b. Reinforcements.** _(done)_
      During the fight, existing enemy ships fly in from the sides, top
      and bottom.
      *Done when:* reinforcement waves spawn from at least three screen edges and a headless run of
      the section produces no errors.
      **Done 2026-09-03.** `StationReinforcements`
      (`assault/scenes/enemies/space_station/station_reinforcements.gd`) as a third sibling node
      alongside `StationLaserPhase` and `StationGunnery` — `space_station.gd` gained **nothing**,
      not even an accessor. Squads cycle `LEFT → RIGHT → BOTTOM → TOP` (**four** edges, not the
      three the done-condition asked for): 2 × `interceptor` from either side, 2 × `kamikaze_drone`
      from below, 2 × `fighter` + `.shoot_forward()` from above, all authored with `WaveBuilder`'s
      own fluent API in 640×360 design units. Three new `SpaceStationConfig` fields (8 s first
      delay / 10 s interval / cap 4). Tests: `test_station_reinforcements.gd` (18). Gate green:
      24 scripts / 232 tests / 868 asserts.
      Plan + **two** review rounds: `docs/plans/station-reinforcements/`. Round 1 was
      CHANGES_REQUESTED and paid for itself: it caught that the planned top squad (`ram_ship`) is
      **immune to the player's primary weapon** — `ram_ship.gd:19` narrows its HurtBox mask to 33,
      which excludes the bullet's layer 64 — so the squad would have been two indestructible
      obstacles by accident; and that registering adds with `ScoreTracker` also opts them into the
      0.75× escape-combo penalty, which nobody had examined. Round 2 approved.
      Both backlog warnings were handled: reinforcements come from a station-owned node rather than
      the station's own wave, and stopping at `armor_broken` plus `FREE_ON_DURATION` means nothing
      can be left alive to hold `ENEMIES_CLEARED` open.
      Four things a future cycle should not have to rediscover: reinforcements must be **siblings**
      of the station and never children (the laser phase rotates the hull, and `bullet_pool.gd:47`
      hardcodes `get_parent().get_parent()`); `FREE_ON_SCREEN_EXIT` cannot be used for an
      off-screen spawn because it only culls a ship that has already been on screen once; the
      station's `died` signal cannot be tested without unhooking `armor_broken` first, because the
      armour rule makes `armor_broken` the only route to it; and a ship's **runtime** HurtBox mask
      comes from `base_enemy.gd:25`, never from the value authored in its `.tscn`.
      → [docs/plans/station-reinforcements](docs/plans/station-reinforcements)

- [x] **5. Destruction hands off to the planet approach.** _(done)_
      Station death plays out and the level
      continues into `planet_approach` and the planet entry.
      *Done when:* a headless run of the full Level 1 section sequence completes end to end.
      **Done 2026-09-03.** `StationDeathSequence`
      (`assault/scenes/enemies/space_station/station_death_sequence.gd`) as a **fifth** sibling
      node; `space_station.gd` gained a `death_started` signal, a public `death_duration`, a
      `_dying` latch and an `_on_health_changed` override that moves **only** `queue_free()`.
      Additive support: `BulletPool.cancel_active()` (extracted from `_exit_tree()`) and
      `ExplosionEffect.explode(at)` (optional position, default preserves today's behaviour).
      Two new `SpaceStationConfig` fields. Tests: `test_station_death_sequence.gd` (15) +
      `test_level_1_sequence.gd` (1 end-to-end) + 2 in `test_station_gunnery.gd`.
      Gate green: 26 scripts / 249 tests / 941 asserts.
      Plan + **two** review rounds: `docs/plans/station-death-handoff/`. Round 1 was
      CHANGES_REQUESTED on the **test plan**, not the design, and earned its keep three times:
      the headline "blasts land in the container" test **could not fail for the right reason**
      (`hit_effect.gd:21,34` keeps a permanent `CPUParticles2D` under every `BaseEnemy`, so a
      recursive search always fails and a direct one is vacuously true); the determinism test
      compared *world* offsets while the same plan rotates the hull, making it a frame-timing
      race; and the end-to-end test would have **leaked `SceneTreeTimer`s with the gate green**.
      Round 2 APPROVED with one blocking pre-condition (finding K) that was also correct — see
      below.
      Four things a future cycle should not have to rediscover:
      **(1)** the `ExplosionEffect` must be a child of the **station**, never of the sequence node
      — `explosion_effect.gd` resolves its container as `get_parent().get_parent()`, so one hop too
      deep puts every blast inside the rotating hull, where it is freed with the wreck and invisible
      to the container the director polls; and it must be added in the `death_started` handler, not
      `_ready()`, because `_propagate_ready()` blocks the parent.
      **(2)** `was_killed`/`died` must fire at HP 0, not at the free, or `ScoreTracker` scores the
      boss as an *escape* and applies the 0.75× combo penalty — silent, and no visual test catches it.
      **(3)** the handoff needed **no** `LevelDirector` change at all: `_wait_enemies_cleared()`
      already polls the container's child count, so a lingering wreck holds its section open for free.
      **(4)** compressing Level 1 for a test needs `stagger_delay` zeroed as well as `spawn_delay`
      — every formation type staggers its own slots, and missing it leaks while the gate stays green.
      
      **Open questions for the plan stage** (research these, do not guess):
      PixelLab maximum sprite dimensions; how many turrets makes the first phase interesting rather
      than tedious; standard telegraph durations for sweeping-laser boss attacks in shmups.
      
      ---
      → [docs/plans/station-death-handoff](docs/plans/station-death-handoff)

## Boss fight escalation: shared hull, flying laser projectors, desperation  [DRAFT - awaiting approval]  (`boss-fight-escalation-shared-hull-flying-laser-projectors-de`, 7 open)

- [ ] **1. Every shot that lands on the station hurts the station.** _(todo)_
      Today the core refuses **all** damage until the last of the four turrets dies
      (`space_station.gd::_on_received_damage` + `is_armored()`), and each turret carries its own
      120 HP pool that is simply thrown away when it dies. The player's shots therefore land in five
      unrelated buckets, and only the last one ever moves the boss's actual health.
      
      Replace that with **one pool**: hits on a turret, on a laser projector, or on the core all draw
      down the same station health. Destroying a part must still remove its gun from the fight and
      leave visible wreckage — a part dying becomes a *consequence* of the shared pool crossing a
      threshold, not a separate bar the player has to empty first.
      
      Already there to build on: `Health` (`global/components/health_component.gd`) on the station
      and one per turret; `StationTurret._on_received_damage` already funnels hits through its own
      `Health`; `SpaceStation.armor_deflected` / `armor_broken` / `is_armored()` /
      `live_turret_count()` are the existing seams.
      
      Three things the plan must handle rather than discover:
      - `armor_broken` is the phase-2 trigger for **four** sibling nodes (`StationLaserPhase`,
        `StationGunnery`, `StationReinforcements`, and indirectly `StationDeathSequence`).
        Retiring the armour rule without a replacement trigger silently disables the whole second
        half of the fight. Task 2 supplies the new trigger, so plan these two together even though
        they ship in order.
      - `tests/integration/test_space_station.gd` pins the armour rule **on purpose** — those are
        intent tests, not characterization. They get rewritten as part of this, never quietly deleted.
      - Effective HP today is 600 + 4x120 = 1080 spread over five bars. One pool means one number, and
        the ~30-60 s fight-length target from `docs/epics-done/station-mini-boss/` has to be
        re-derived rather than 600 being carried over by default.
      
      *Done when:* a test proves damage dealt to a turret, to a projector and to the core all reduce
      the same number by the same amount; that destroying a part neither refunds nor double-counts the
      hit that killed it; and that the station can be killed while the player only ever shoots its
      parts.

- [ ] **2. The fight visibly turns at half health.** _(todo)_
      Phase 2 begins today when the last turret dies. Under one shared pool (task 1) that moment
      stops existing, so the transition moves to **50 % of the shared pool** — the halfway point
      becomes the beat the player feels, which is the shipped convention for a desperation phase.
      
      Already there: `SpaceStation.armor_broken` is a zero-argument, once-only-latched signal that
      every sibling behaviour node already listens to, so the *shape* of the hook is right even if the
      name and the trigger are not. `_on_health_changed(current)` already sees every HP change and
      already carries a once-only `_dying` latch to copy.
      
      The trap: `Health` emits `amount_changed` on **every** call including 0 -> 0
      (`health_component.gd:51-53`), so a naive `current <= max / 2` test fires on every subsequent
      hit. Whatever replaces `armor_broken` must keep the once-only guarantee, and the entry into
      phase 2 has to be legible on screen — a phase change nobody notices is a phase change that did
      not happen.
      
      *Done when:* a test drives the pool from full to just above half and proves nothing fires;
      crosses the threshold and proves the phase starts exactly once; then keeps damaging past it (and
      back at 0 HP) and proves it never fires again.

- [ ] **3. The station is properly defended, by more than one kind of ship.** _(todo)_
      `StationReinforcements` runs a fixed four-squad cycle — 2 interceptors from the left,
      2 from the right, 2 drones from below, 2 fighters from above — first squad at 8 s, one every
      10 s, cap 4 alive, and it **stops entirely** at the phase change. The fight reads as a duel with
      occasional visitors rather than as an assault on a defended installation.
      
      Make the surrounding space feel contested: more ships, more variety, and defenders that keep
      arriving through both phases.
      
      This is mostly table work, not new machinery: `_build_squads()` already authors every squad
      through `WaveBuilder`'s fluent API in 640x360 design units, and `docs/enemy-roster.md` lists
      the roster. `bomber`, `sniper_enemy`, `gunship` and `drone_interceptor` do not appear in
      this fight at all yet.
      
      Two things the plan must argue rather than assume:
      - The phase-1-only rule is a **researched decision**, not an oversight — the Flunky-Boss critique
        that constant spawns are how a boss ends up overshadowed by its own minions. The user has asked
        for defenders "throughout the fight", so this is a deliberate reversal, and the plan owes an
        answer for how phase 2 stays readable with adds in it. The live cap, the 48-slot bullet pool and
        raw screen space are the levers.
      - `ram_ship` is the obvious "tanky obstacle" pick and is **immune to the player's primary
        weapon**: `ram_ship.gd:19` narrows its HurtBox mask to 33, which excludes the bullet's layer
        64. It was already rejected once for this exact reason.
      
      *Done when:* at least two enemy types that do not appear in this fight today are in the rotation,
      defenders arrive in both phases, and a headless run of `station_assault` still ends — nothing
      a squad leaves behind may hold `ENEMIES_CLEARED` open.

- [ ] **4. Laser projectors fly around the station and shoot at the player.** _(todo)_
      A new part type. In phase 1 the station's laser projectors are **mobile**: they move
      around the station's airspace and fire telegraphed beams at the player, instead of every beam
      coming from the hull on a fixed schedule. The point is that the arena is dangerous while the
      player is chewing through turrets, and that the threat now has a position the player can
      pressure.
      
      Reusable, and it is most of the work: `LaserRay`
      (`assault/scenes/hazards/laser_ray/laser_ray.tscn`) already does the whole telegraph -> charge
      -> lethal -> dissolve cycle with `warn_duration` / `active_duration`, and
      `hit_mask_override` exists specifically so a mounted emitter does not kill its own owner.
      `StationTurret` is the model for a destructible, non-scoring part that stays in the tree as
      wreckage. Movement resources are in `global/resources/movement/` (`arc_movement`,
      `sine_movement`, `player_focus_movement`, `sequence_movement`).
      
      Needs art: a projector sprite plus a destroyed variant, matching how turrets read as wreckage.
      **Invoke the `pixel-art-generation` skill before generating anything** — `assault/` is strict
      top-down orthographic and never isometric, and a 3/4-view turret already shipped once in this
      very boss because nobody opened the image.
      
      Traps this project has already paid for once:
      - A beam fired from inside the hull on the default hit mask took the station 600 -> 0 HP in a
        single frame. `hit_mask_override` must be set **before** `add_child()`, because
        `LaserRay._ready()` is what reads it.
      - Anything that moves independently of the station must **not** be parented under it: the hull
        rotates (`station_laser_phase.gd`), and `bullet_pool.gd:47` hardcodes its container as
        `get_parent().get_parent()`.
      
      *Done when:* projectors are destructible parts drawing on the shared pool (task 1); they change
      position over time rather than sitting at fixed offsets; they fire beams aimed at the player that
      telegraph before they can hurt anything; and a test proves a beam is harmless throughout its
      warning window and lethal only after it.

- [ ] **5. In phase 2 the projectors close ranks, and only open to fire.** _(todo)_
      Second-phase behaviour for whichever projectors survived. They take station around the
      boss, rotate around it, and fire toward the player — and they are **armoured while closed**, so
      the player can only hurt them in the window where they open to fire. That turns the second half
      from "keep shooting the same thing" into "watch, and time it", and it gives the rotation a reason
      to matter beyond looking busy.
      
      Already there: `SpaceStation._on_received_damage` is the shipped pattern for refusing damage
      while keeping the HurtBox **live** — which is required, not stylistic, because
      `plasma_nova_module.gd` and `beam_behavior.gd` both drive `received_damage` directly with
      no physics involved, so a disabled hurtbox leaks both. `armor_deflected` is the existing
      precedent for making "that hit did nothing" legible instead of silent.
      
      The design question the plan has to answer with a number **and** a reason: how long the open
      window is. Too short and it reads as the boss being invulnerable; too long and the armour is
      decoration. The reference points already measured in this project are the 1.4 s beam telegraph
      (~1.9-2.0 s to lethal) and the ~0.3 s human reaction floor.
      
      *Done when:* a test proves damage during the closed window is refused and damage during the open
      window lands on the shared pool; the open state is visually distinct from the closed one; and the
      projectors orbit the hull rather than sitting at fixed offsets.

- [ ] **6. Tearing off the station's defences makes it fight harder, not just quieter.** _(todo)_
      Killing turrets is currently pure relief — fewer guns, less fire, and the fight gets
      easier the longer it runs. The user wants the opposite curve: every destroyed turret or projector
      should make the station more **desperate**, with faster laser charge-up, faster beam movement,
      longer turret reach, higher fire rate and wider spread.
      
      This is an explicit reversal of a decision the previous epic took deliberately — the dossier
      records escalation being rejected because "it would cancel out the 4->3->2->1 quietening that is
      the player's reward". The reversal is the user's call. What the plan owes is a curve that still
      reads as *progress*: more intense, never "destroying that was a mistake".
      
      Every knob named already exists as a node field copied out of `SpaceStationConfig` in
      `_ready()` — `StationGunnery.turret_fire_interval` / `turret_burst_arc` /
      `turret_bullet_speed`, `StationLaserPhase.warn_duration` / `rotation_speed`. They are
      copied and never read back on purpose: the `.tres` is a single process-wide cached instance, so
      scaling them at runtime means writing node fields, never writing through `config`. Do not
      "tidy" that into a live read.
      
      *Done when:* one readable desperation level, derived from how many parts are gone, drives the
      affected values; a test asserts the level and at least three derived values at zero, half and all
      parts destroyed; and every derived value is bounded, so the last projector's death cannot produce
      a rate nobody can dodge.

- [ ] **7. The sweeping laser can turn on you mid-sweep.** _(todo)_
      The rotating beam attack sweeps at one constant rate (`laser_rotation_speed = 0.5`
      rad/s) in one direction for its entire life, so "pick a side and keep running" solves it. Make it
      able to **reverse direction mid-attack**, and make its starting rate depend on how many
      projectors are left and how desperate the station is (task 6).
      
      Why a reversal rather than simply "faster": the constant rate was chosen so the beam edge travels
      ~200 px/s at the distance the player actually sits, against the player's 400 px/s top speed
      (`move_state.gd:21`) — outrunning it is a decision, not a reflex. A reversal removes the
      run-one-way-forever answer while keeping that readability, as long as the turn itself is
      telegraphed or slow enough to read.
      
      Hard constraint from the shipped code: attack ordering in this boss is **never** `randf()`.
      That is the most-cited research finding in the previous epic — random attack order cannot be
      balanced and cannot be tested — and four existing tests pin determinism
      (`test_volley_angles_are_deterministic` and friends). A reversal schedule must be
      deterministic, and the plan should say what makes the turn readable to a player who is already
      dodging bullets.
      
      *Done when:* a test proves the sweep reverses at a deterministic point rather than a random one
      and does so identically on every run; and that the starting rate differs measurably between a
      full-strength station and one that has lost most of its parts.

