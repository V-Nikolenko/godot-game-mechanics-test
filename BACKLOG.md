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

- [x] **Regenerate the turret sprites — `station_turret.png` is 3/4 view, not top-down.**
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

- **Strict top-down orthographic — see the `pixel-art-generation` skill.** Camera directly
  overhead, zero tilt, no isometric, no 3/4, no perspective, no foreshortening. Every
  generated image must be opened and visually checked before commit.
  separate sprites so turrets can be destroyed and swapped independently.
- **Scale:** the player fighter is 64×64. Target the station at roughly 4× that and turrets at
  about player size. **Do not hardcode a pre-multiplied pixel size** — this project authors in
  640×360 design space and scales by `ArenaCamera.WORLD_SCALE` (2.0). The plan must state exactly
  which space the sprite is authored in and where the scale is applied; getting this wrong makes
  the boss the wrong size on screen. Confirm PixelLab maximum output size during research.
- Reuse existing enemy scenes for reinforcements. Do not create new enemy types for this.

### Sub-items — do these in order, one per session

- [x] **1. Station and turrets exist as a destructible entity.** Generate the station and turret
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

- [x] **2. The encounter blocks level progress.** Add a new `LevelSection` (suggested name
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

- [x] **3. Laser phase.** Once all turrets are destroyed, the station rotates and fires
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

- [x] **4a. The station shoots back.** Turrets and core fire bullet-hell patterns through
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

- [x] **4b. Reinforcements.** During the fight, existing enemy ships fly in from the sides, top
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

Found on 2026-09-01 while building the space-station mini-boss entity (EPIC sub-item 1).

- [ ] **GUT silently drops a test script it cannot load, and still exits 0.** When
      `tests/integration/test_space_station.gd` referenced classes that did not exist yet, GUT
      printed `---- All tests passed! ----`, reported `Scripts 2` instead of 3, and **returned exit
      code 0**. The parse errors appeared only on stderr. `/agent/verify.sh` step 3 checks the exit
      code and greps for `^N failing`, so **neither signal fires** — a test file broken by a rename
      or a deleted symbol would vanish from the suite and the gate would stay green. Cheap fix:
      have step 3 also assert the script count, or grep its GUT output for `Parse Error` /
      `SCRIPT ERROR` the way steps 1 and 2 already do. This is the only reason the "watch it fail"
      step of the feature workflow worked here — the red was read off stderr, not off GUT's verdict.

- [ ] **`Gunship` never applies its config's `collision_damage`.** `gunship_config.tres:8` sets
      `collision_damage = 30`, but `BaseEnemy._add_contact_hitbox()` hardcodes `hb.damage = 20`
      (`base_enemy.gd:56`) and the gunship — unlike `bomber.gd:25`, `light_assault_ship.gd:23`,
      `ram_ship.gd:20-23` and `drone_interceptor.gd:148` — never re-applies it after
      `super._ready()`. So the heaviest enemy in the roster rams for 20 instead of 30 and the
      `.tres` value is dead. One loop in `gunship.gd::_ready()` fixes it; it is a balance change,
      so it should be a deliberate one rather than folded into unrelated work. `space_station.gd`
      does apply it, so the two enemies currently disagree about whether the field means anything.

- [ ] **`base_enemy.gd:56-59` builds the contact HitBox from `col.shape` but drops the
      `CollisionShape2D`'s `scale` and `position`.** Every enemy that scales its collision shape in
      the scene therefore gets a contact hitbox of the wrong size — `gunship.tscn:63-65` scales by
      2.31, so its contact hitbox is ~2.3× too small. Harmless-ish at 40 px, badly wrong at boss
      scale. `space_station.tscn` sidesteps it by authoring its shape at true size with `scale = 1`,
      but the underlying helper is still lossy for everyone else. Copying the node's transform
      onto the new `CollisionShape2D` would fix it — though it would silently enlarge several
      existing enemies' contact hitboxes, so it needs a balance pass, not a blind fix.

Found on 2026-09-01 while adding the `station_assault` section (EPIC sub-item 2).

- [ ] **A test that ends while a `LevelDirector` coroutine is suspended leaks — and the gate stays
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

- [ ] **Should the station's core hurtbox be narrowed to 88 x 240? — a design question, not a bug.**
      `space_station.tscn:16-17` uses ONE 240 x 240 `RectangleShape2D` for both the body collider
      and the core `HurtBox`, so the core's hurtbox spans the whole hull and the four turret
      hurtboxes sit strictly inside it. This is **not** a reachability bug — see the next item —
      but it does mean shooting the hull shoulders registers as a deflected core hit rather than
      missing, and a bullet fired up a turret lane triggers a core deflection *before* it reaches
      the turret. Giving the `HurtBox` its own 88-wide shape would make the x-extents disjoint
      ([-44, 44] vs [50, 102]) and the "shoot the guns, then the core" read cleaner. It was
      planned, then dropped when its stated justification collapsed; it needs a deliberate
      design call, not a bug fix. Cost: one `sub_resource` and one node property.

- [ ] **Two consecutive reviews asserted that a player bullet dies on its first hurtbox overlap.
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

- [ ] **`test_space_station.gd`'s collision-layer coverage gap is still open.** Sub-item 1 recorded
      it as provable "once the station is in a live level (sub-item 2)". Sub-item 2 has landed and
      does **not** close it: `test_station_assault_section.gd` asserts section gating and wave data,
      never a projectile overlap. Closing it needs a test that instances
      `assault/scenes/projectiles/bullets/bullet.tscn`, positions it in a turret lane and steps
      physics — the suite has no precedent for physics-overlap tests, so budget for the technique.
      `ENEMY.md` and `tests/README.md` now say this plainly instead of promising it is coming.

Found on 2026-09-01 while regenerating the turret sprites.

- [ ] **`station_core.png` has a fully opaque background — the station will render as a grey
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

- [x] **The turret sprite's barrels point at −Y and no turret sets `rotation`.** All four
      `space_station.tscn` turret instances are placed at `rotation = 0`, so every barrel points
      toward the top of the screen — *away* from the player, who is always below the station.
      **Closed 2026-09-02 by sub-item 4a**, at exactly the moment it predicted.
      `StationGunnery.fire_turret_volley()` sets each firing turret's `global_rotation` to
      `aim.angle() + PI/2` immediately before firing — `global_rotation`, not `rotation`, so it
      survives the laser phase spinning the hull. Pinned by
      `test_turret_barrels_face_the_player_when_firing`, which fails by ~180° against the pre-4a
      scene. The authored `rotation = 0` remains, as a spawn orientation.

- [ ] **This container has no `file`, no `python3` and no `xxd` — only `od`.** `scripts/pixellab.sh`
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

- [ ] **Every enemy that does `@export var config = load(...)` shares ONE config resource
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

- [ ] **`spike/test_spike_laser.gd` and `spike/test_spike_selfkill.gd` are tracked dead code.**
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

- [ ] **`ExplosionEffect` orphans its particles onto whatever the dying entity's parent is.**
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

- [ ] **The station's collision-layer coverage gap is now only half open.**
      `assault/scenes/enemies/space_station/ENEMY.md` records that
      `tests/integration/test_space_station.gd` drives damage by emitting `received_damage`
      directly and so proves nothing about collision layers.
      `tests/integration/test_station_laser_phase.gd` does now exercise a **real** physics overlap
      — a layer-128 stub `HurtBox` placed in a beam's path, found by the beam's own `Area2D` — but
      only for the *player* layer and only against a `LaserRay`. Nothing yet proves a player
      **bullet** can hit the core's layer-512 hurtbox or a turret's. Closing it still needs a test
      that instances `assault/scenes/projectiles/bullets/bullet.tscn` and steps physics.

Found on 2026-09-03 while implementing station reinforcements (EPIC sub-item 4b).

- [ ] **`ram_ship` cannot be hit by the player's primary weapon, and its config HP is dead code.**
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

- [ ] **The 0.75× escape-combo penalty applies to ad-hoc spawns nobody expects to kill.**
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

- [ ] **A spawn's off-screen margin cannot account for camera pan, project-wide.**
      Every spawn in the game resolves its offset against `cam.global_position`, which
      `arena_camera.gd:5-12` pins at (640, 360) and never moves — panning happens through `offset`.
      So a player panned fully down (`V_LIMIT` is 380) can in principle watch a bottom-edge spawn
      appear. 4b matched the existing convention rather than diverging for one node, and excluded
      `V_LIMIT` from its vertical margin budget on purpose. Fixing it properly means spawns
      resolving against the *visible* rect rather than the camera centre, which touches
      `wave_manager.gd:172` and every spawn offset in the game — not a 4b-sized change.
