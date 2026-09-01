# BACKLOG

The autonomous agent reads this file top-down every 5 hours and takes the **topmost item it can
finish end to end**. This file is the steering wheel — vague items produce drifting work.

Reorder freely; the agent always starts from the top. Delete or tick items yourself — the agent
also ticks what it finishes and appends anything it discovers under *Discovered*.

Anything non-trivial goes through the **`feature-workflow`** skill: research → plan in
`docs/plans/` → independent subagent review → implement only after approval. So an item does not
need to specify *how* — the plan stage decides that, and you get to read it before the code lands.

## How to write an item

Three things, and only the first is mandatory:

1. **The player-facing outcome.** What should be different when someone plays the game? Write
   this, not the implementation. "Dashing should feel responsive when you tap it just after
   leaving a ledge" beats "add a coyote-time timer to `player.gd`".
2. **Where it lives**, if you know — module or file paths. Saves the agent a search and stops it
   guessing at the wrong module.
3. **What "done" looks like** — the observable condition you would check yourself.

Add **constraints** when you actually have them ("must not change existing wave timing",
"reuse the existing Overheat component"). Leave them out when you do not — an over-specified item
just locks in your first idea and wastes the research stage.

**Size it to one session.** If it needs more, say so and let the agent split it; it will add the
sub-items back here.

<details><summary>Good vs bad, same feature</summary>

> ❌ **Bad** — "Improve the dash."
> No outcome, no scope, no done condition. The agent will invent all three and probably build
> something you did not want.

> ❌ **Bad** — "In `player.gd` add `var coyote_timer := 0.15` and check it in `_physics_process`
> before allowing a dash, then update the state machine."
> Over-specified. You have made the design decisions from memory, skipped the research stage, and
> baked in a magic number. If your approach is wrong, the agent implements it wrong faithfully.

> ✅ **Good** — "Dashing off a ledge feels unresponsive: if you press dash a few frames after
> walking off, nothing happens and it reads as a dropped input. It should still dash. Affects the
> infiltration module's player controller. Done when a GUT test proves a dash input shortly after
> leaving ground still triggers, and normal mid-air dashing is unchanged."
> Outcome, location, done condition. The research stage will find the standard window, the plan
> will name the files, and the reviewer will check it against the existing state machine.

</details>

---

## Now

- [x] **Bootstrap the test harness.** Install GUT into `addons/gut/`, create `tests/`, and write
      characterization tests for the eight autoloads and the `global/components/` set (Health,
      Hurtbox/Hitbox, Shield, Overheat, DamageReaction). Tests must pin down current behaviour,
      bugs included — no fixes this run. Done when `bash /agent/verify.sh` passes with a green
      suite. *(The agent does this automatically while `addons/gut/` is missing, ignoring
      everything below.)*
      **Done 2026-08-31** — GUT 9.7.1 vendored into `addons/gut/` (two files patched for Godot
      4.6.3, see `addons/gut/LOCAL_PATCHES.md`), 153 tests / 490 asserts across 16 scripts in
      `tests/`, gate green. Conventions and the gotchas that cost time are in `tests/README.md`.

## Next

- [x] **Fix the stale UID in `open_space/scenes/gui/hud.tscn:6`.** Its `ext_resource` for
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

## EPIC — Level 1 space-station mini-boss

**Outcome:** Level 1 currently runs Deep Space → Asteroid Belt → Planet Approach → Cloud Descent.
Between the asteroid belt and the planet approach, the player should meet a **space station
mini-boss**: a bullet-hell encounter they cannot skip. Turrets first, then a rotating laser phase,
and only when the station is destroyed does the level continue to the planet.

**Reuse — do not rebuild these** (checked, they exist):

| Need | Already exists |
|---|---|
| "Cannot progress until boss dead" | `LevelSection.EndCondition.ENEMIES_CLEARED` (see `cloud_descent`, `level_1_director.gd:759`) |
| Telegraphed rotating lasers | `assault/scenes/hazards/laser_ray/laser_ray.tscn` — has `warn_duration`, `active_duration`, `loop`, `off_duration` |
| Per-turret destructibility | `global/components/health_component.gd` + `hurtbox_component.gd` + `hitbox_component.gd` |
| Damage feel / death | `damage_reaction.gd`, `hit_effect.gd`, `explosion_effect.gd`, `low_health_smoke.gd` |
| Reinforcement waves | `WaveManager` + `wave_builder.gd`; enemies in `assault/scenes/enemies/` (interceptor, kamikaze_drone, bomber, ram_ship, …) |
| Bullet-hell throughput | `global/components/bullet_pool.gd` — see `docs/BULLET_POOL.md` |

**Constraints (apply to every sub-item):**

- **Top-down, no perspective.** The station is viewed flat from directly above — no vanishing
  point, no angled faces. Turrets read as mounted on its surface.
- **Sprites come from PixelLab**, saved under `assault/assets/sprites/`. Station and turrets are
  separate sprites so turrets can be destroyed and swapped independently.
- **Scale:** the player fighter is 64×64. Target the station at roughly 4× that and turrets at
  about player size. **Do not hardcode a pre-multiplied pixel size** — this project authors in
  640×360 design space and scales by `ArenaCamera.WORLD_SCALE` (2.0). The plan must state exactly
  which space the sprite is authored in and where the scale is applied; getting this wrong makes
  the boss the wrong size on screen. Confirm PixelLab maximum output size during research.
- Reuse existing enemy scenes for reinforcements. Do not create new enemy types for this.

### Sub-items — do these in order, one per session

- [ ] **1. Station and turrets exist as a destructible entity.** Generate the station and turret
      sprites via PixelLab. Assemble the station scene with N turrets as child entities, each
      individually damageable. The station core takes no damage while any turret is alive.
      *Done when:* a GUT test destroys turrets one at a time and proves the core is invulnerable
      until the last turret dies, then becomes damageable.

- [ ] **2. The encounter blocks level progress.** Add a new `LevelSection` (suggested name
      `station_assault`) to `level_1_director.gd`, between `asteroid_belt` and `planet_approach`,
      using `ENEMIES_CLEARED`. Add the matching `phases/phase_station_assault.tres`.
      *Done when:* a headless test proves the section does not advance while the station lives,
      and advances to `planet_approach` when it dies.

- [ ] **3. Laser phase.** Once all turrets are destroyed, the station rotates and fires
      `LaserRay` beams at varying positions, forcing the player to keep moving. Beams must
      telegraph before they damage (`warn_duration`) — an instant-kill beam with no tell is
      unfair, and research should set the actual timing.
      *Done when:* a test proves the phase only starts after the last turret dies, and that a
      beam damages the player only during its active window, not its warning window.

- [ ] **4. Bullet hell + reinforcements.** During the fight, existing enemy ships fly in from the
      sides, top and bottom. Turrets and station fire bullet-hell patterns.
      *Done when:* reinforcement waves spawn from at least three screen edges, projectiles route
      through `bullet_pool`, and a headless run of the section produces no errors.

- [ ] **5. Destruction hands off to the planet approach.** Station death plays out and the level
      continues into `planet_approach` and the planet entry.
      *Done when:* a headless run of the full Level 1 section sequence completes end to end.

**Open questions for the plan stage** (research these, do not guess):
PixelLab maximum sprite dimensions; how many turrets makes the first phase interesting rather
than tedious; standard telegraph durations for sweeping-laser boss attacks in shmups.

---

## Discovered

<!-- The agent appends suspected bugs and follow-ups it found but did not act on. Triage these. -->

Found on 2026-08-31 while writing the characterization suite. Each one is **pinned by a passing
test that asserts the current behaviour**, so changing any of them will fail that test — which is
the signal that the change was deliberate. Test names are given so the fix has an obvious anchor.

- [ ] **`Health.amount_changed` is declared with zero parameters but emitted with one.**
      `global/components/health_component.gd:4` declares `signal amount_changed`, and line 42
      emits `amount_changed.emit(current_health)`. One-argument handlers (`DamageReaction`,
      `PlayerBase._on_health_changed`) work, but any zero-argument handler raises
      `Error calling from signal 'amount_changed' ... Method expected 0 argument(s), but called
      with 1` at runtime. Fix is one line: `signal amount_changed(current: int)`.
      Same defect in `global/statemachine/state.gd:4` — `signal state_transition` is emitted with
      the target `State`. Pinned by `tests/unit/test_health_component.gd` (see the file header)
      and `tests/unit/test_state_machine.gd::test_states_request_transitions_through_their_own_signal`.

- [ ] **`StateMachine.change_state()` crashes if the machine has no current state.**
      `global/statemachine/state_machine.gd:29` does `print("Exiting previous state: " +
      current_state.name)` **before** the `if current_state:` guard on line 31. Any machine built
      without an `initial_state` (or whose state was cleared) dies on its first transition. Not
      reachable today because every shipped machine sets `initial_state`, so it is latent rather
      than live. Deliberately *not* covered by a test — the test would have to trigger the crash.

- [ ] **`Health.decrease()` prints to stdout on every single hit.**
      `global/components/health_component.gd:34`. In a bullet-hell section that is one line per
      projectile per frame; `print` is not free and it buries real errors in the log. Should be a
      debug-gated helper or removed. `StateMachine.change_state` and `DialogPlayer` print
      unconditionally too (`[DP] ...` on every line of every conversation).

- [ ] **`UpgradeState.unlock()` accepts ids that are not in `ALL_IDS`.**
      A typo'd id is stored and reported `true` by `is_unlocked()`, but `unlocked_ids()` iterates
      `ALL_IDS`, so it never appears in any menu — a silent, invisible failure. Compare
      `ShipModuleState.unlock()`, which validates and `push_warning`s. Pinned by
      `tests/unit/test_upgrade_state.gd::test_unknown_ids_are_stored_but_never_listed`.

- [ ] **`SessionState` recovers the temp-HP stack size with integer division.**
      `global/autoloads/session_state.gd:85` computes `_temp_hp_stack = maximum /
      TempHealth.MAX_STACKS`. When `maximum` is not a multiple of 5 the stack size rounds down and
      the pool the player gets back after a level transition is smaller than the one they earned.
      Reachable whenever a ship's `base_health / 2` is not a multiple of 5. Pinned by
      `tests/unit/test_session_state.gd::test_temp_health_stack_size_uses_integer_division`.

- [ ] **`ShipModuleState.equip()` never consults `_unlocked`.** Any module in the catalogue can be
      equipped whether or not it was earned. Fine if unlock state is purely cosmetic for the menu;
      a progression hole if it is not. Worth a decision either way. Pinned by
      `tests/unit/test_ship_module_state.gd::test_equipping_does_not_require_unlocking`.

- [ ] **`MissionState.complete()` cannot record a zero-star clear.** `clampi(stars, 1, 3)` turns a
      0-star completion into 1 star. Intentional? Pinned by
      `tests/unit/test_mission_state.gd::test_stars_are_clamped_into_one_to_three`.

- [ ] **GUT 9.7.1 needs two local patches to load under Godot 4.6.3**, documented in
      `addons/gut/LOCAL_PATCHES.md`. `AccessibilityServer` does not exist in this Godot build, and
      a property getter in `stub_params.gd` fails type inference. Re-apply both on any GUT upgrade
      — without them the whole addon fails to parse and the doubler is unusable.

Found on 2026-09-01 while fixing the stale `ext_resource` UIDs.

- [ ] **The Godot MCP `update_project_uids` tool is a no-op on this project — do not rely on it.**
      It concatenates `"res://"` onto the absolute project path it is given, so it searches
      `res:///tmp/coldclone/` (or `res:///work/repo/`), reports *"Found 0 scenes, Found 0
      scripts/shaders"*, and exits claiming success. Verified by md5summing all 151 `.tscn`/`.tres`
      before and after a run on a scratch copy: **zero files changed.** The bug is in the MCP
      server's own `godot_operations.gd`, not in this repo, so it cannot be fixed here. Use
      `tests/integration/test_resource_uid_integrity.gd` instead — it covers strictly more
      (`.tres` resources and `.gd.uid` sidecars as well as scenes).

- [ ] **`.godot/uid_cache.bin` masks broken UID references, so a warm machine disagrees with a
      fresh clone.** Once a project has been loaded, Godot keeps a *stale* UID registered as a
      working alias for its target: `ResourceLoader.get_resource_uid()` and `ResourceUID.has_id()`
      both reported the dead `uid://bi366j2tsyby` as valid, and `--import` emitted no warning for
      the five `.tres` files using it. Deleting `.godot/` and loading one of those files directly
      produced `ext_resource, invalid UID` immediately. `.godot/` is gitignored, so **CI and new
      contributors see the failures a developer's machine hides.** Two consequences worth keeping
      in mind: `bash /agent/verify.sh` runs against a warm cache and will not catch this class of
      defect on its own, and any future UID tooling must read declarations from disk rather than
      ask the engine.

- [ ] **`godot --headless --import` only loads a fraction of the project, so "import is clean" is
      a weak gate.** It surfaced 1 of the 3 live `invalid UID` warnings; the other 2 only appeared
      once every scene was actually loaded. A cheap "load all 126 `.tscn`/`.tres` and assert no
      load returns null" smoke test would close the gap — worth considering as step 4 of
      `/agent/verify.sh`. All 126 do currently load clean, so it would start green.

- [ ] **Several resources declare hand-written UIDs in their own headers** — `uid://hudscore001`
      (`assault/scenes/gui/hud_score_widget.tscn`), `uid://braceasteroid01`, `uid://00246ccaem53`,
      `uid://0024uci15m53`, `uid://00243s3wxf53` (the `assault/scenes/race/` scenes). Godot 4.6.3
      parses and registers all of them, and every reference to them resolves, so **nothing is
      broken and they were deliberately left alone.** Flagging them only because they are the same
      fingerprint as the eight references that *were* broken: a UID typed by a human or an agent
      rather than minted by the editor. If one is ever duplicated onto a second resource the
      collision will be silent.
