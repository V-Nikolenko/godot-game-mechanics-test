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

## Log records: discoverable lore and info logs across all three modes  [DONE]  (`log-records-discoverable-lore-and-info-logs-across-all-three`, 0 open)

- [x] **Every log record I find stays found, and the game knows how many are left** _(done - feature, medium, sonnet)_
      **Player outcome:** Logs I picked up three missions ago are still mine after quitting and
      relaunching, and the game can always answer "how many logs are there, and how many do I have?"
      without anyone hand-maintaining that number.
      
      **Why this is first:** every other task in this epic reads or writes this store. Nothing else can
      be built until "what is a log" and "where is it saved" exist.
      
      **Shape (leave the details to this task's own plan):**
      - A `LogEntryResource` (`Resource`) per lore entry — id, title, body text, and its position in
        the reading order. Entries live as `.tres` files, matching the project's config-driven
        convention (see `open_space/scenes/mission_data/mission_config_resource.gd` for the pattern).
      - A `LogState` autoload alongside the existing eight in `project.godot`, persisting to
        `user://` with `ConfigFile` exactly like `MissionState` and `ShipModuleState` already do.
        Copy `ShipModuleState`'s validate-on-load behaviour: an unknown id in the save file is warned
        about and dropped, never trusted.
      - **The total must be derived, not typed.** The user's ask is that adding a log requires no
        bookkeeping. Deriving it from the catalogue on disk is what makes that true; a hardcoded
        `TOTAL_LOGS = 12` is the exact thing this task exists to avoid.
      
      **Open design question for the plan — flag it, don't silently pick:** the idea says lore logs
      "are unlocked in a specific order". The cheapest reading, and the one that best matches "place the
      collectible on the map and everything else happens automatically", is that a lore-log collectible
      is *anonymous*: collecting one grants the next still-locked entry in catalogue order, so the story
      always reads in sequence no matter which corner of the map the player explored first. The
      alternative — each collectible names its entry, and the menu shows gaps — is also defensible but
      makes placement order narratively load-bearing. Pick one in the plan and say why.
      
      **Done when:** `tests/unit/test_log_state.gd` covers collect / already-collected / save round-trip
      / unknown-id-in-save / the derived total, and the gate is green. Follow `tests/README.md` for the
      `user://` save-file sandbox — `LogState` writes to `user://` and will otherwise leak between tests.
      -> [docs/plans/every-log-record-i-find-stays-found-and-the-game-knows-how-m](docs/plans/every-log-record-i-find-stays-found-and-the-game-knows-how-m)
      1 run(s), $3.03; last on claude-sonnet-5

- [x] **Flying into a log record in open space picks it up and tells me what I found** _(done - feature, medium, sonnet)_
      **Player outcome:** a log record floating in the sector hub is visually readable as
      "something to collect", flying into it picks it up, and a one-line notification tells me what I
      just recovered without stopping the ship.
      
      **Reuse — this should be a small script:** `PickupBase` (`global/pickups/pickup_base.gd`) already
      does the whole dance: `body_entered` → check group `"player"` → `_collect(player)` →
      `_get_dialog_text()` → non-blocking `DialogPlayer` line → `queue_free()`.
      `ship_module_unlocker_pickup.gd` is the closest existing sibling (36 lines, an inspector enum, one
      autoload call) and is the model to copy. If this task ends up writing its own overlap detection or
      its own notification path, something has gone wrong.
      
      **Art:** the log record needs its own sprite. `assault/` and `open_space/` are strict top-down
      orthographic — **invoke the `pixel-art-generation` skill before generating anything**, and open
      the result and look at it. A 3/4-view collectible is unusable and cannot be fixed in code.
      
      **Done when:** a `lore_log_pickup.tscn` exists under `global/pickups/scenes/` next to the other
      nine, collecting it advances `LogState`, collecting it twice in one run cannot double-count, and
      the notification text names the entry. Test in `tests/unit/`.
      -> [docs/plans/flying-into-a-log-record-in-open-space-picks-it-up-and-tells](docs/plans/flying-into-a-log-record-in-open-space-picks-it-up-and-tells)
      3 run(s), $5.48; last on claude-sonnet-5

- [x] **Reading a data tablet by a body doesn't interrupt the mission, and I can read it again** _(done - feature, medium, sonnet)_
      **Player outcome:** I walk or fly up to a tablet, a terminal, or a scrap of hull, a prompt
      tells me I can read it, and pressing the key shows the message *without* yanking control away. If
      I come back later it is still readable — it is scenery with something to say, not a consumable.
      
      **This is the other half of the user's idea:** information logs are not stored, not counted, and
      not part of 100% completion. They exist to make a place feel inhabited.
      
      **Two things worth knowing before planning:**
      - The `interact` action is already bound to **F** in `project.godot` (line ~121) and **no script
        in the project uses it**. This task is the first user of it, so there is no existing interaction
        system to extend — but also no existing conventions to fight.
      - `PickupBase` is the wrong parent here: it frees itself on contact and requires no input. This is
        a sibling of it, not a subclass.
      
      **Research finding that should shape the design:** the most common complaint about lore
      collectibles in shipped games is that they stop the game dead — the player is parked in a menu
      listening to something they could have read ten times faster
      (https://www.giantbomb.com/forums/general-discussion-30/why-do-developers-keep-using-the-audio-log-game-me-1479403/,
      https://www.resetera.com/threads/do-you-listen-to-audio-logs-that-require-you-to-stare-at-a-menu-as-it-plays.804642/).
      That is the argument for the split the user already drew: short in-world text plays inline via
      `DialogPlayer` with `pause_gameplay = false` (the pickup notification path already does exactly
      this), and only the long-form lore lives in a menu the player opens deliberately.
      
      **Done when:** an interactable exists that shows a prompt on approach, replays its message on every
      interaction, is unaffected by `LogState`, and refuses to fire while `DialogPlayer.is_active` (the
      guard `PickupBase._show_notification()` already uses). Test the enter/exit/re-read cycle.
      -> [docs/plans/reading-a-data-tablet-by-a-body-doesn-t-interrupt-the-missio](docs/plans/reading-a-data-tablet-by-a-body-doesn-t-interrupt-the-missio)
      1 run(s), $3.40; last on claude-sonnet-5

- [x] **The ESC menu has a Lore Logs section where I can re-read everything I've found** _(done - feature, medium, sonnet)_
      **Player outcome:** ESC → Lore Logs shows the whole catalogue. Entries I have found are
      readable in full; ones I have not are visibly there but withheld, so I can see there is more to
      find and roughly how much. The header tells me where I stand: "7 / 14".
      
      **Reuse — the locked/unlocked list already exists.** `global/ui/player_menu/module_list.gd`
      (`ModuleList`) is a navigable overlay that renders one row per catalogue entry, greys locked rows,
      and prefixes a locked row's description with a call to action rather than leaving it a dead end.
      Its lock gate is `ShipModuleState.is_unlocked()`; this list's is `LogState`. Read
      `tests/integration/test_module_list_lock.gd` — it already pins the locked-row behaviour and is the
      model for this list's test.
      
      **The ESC menu itself:** `global/ui/pause_menu/pause_menu.gd` has exactly four hardcoded options
      (`Option0..Option3`) wired by index in `_confirm()`, with `_navigate()` skipping hidden ones, and
      `mission_mode` toggling options 1 and 2. Adding a fifth option means touching that index-matched
      `match` and the scene's `MenuContainer`, plus the two scenes that instance it
      (`pause_menu.tscn`, `open_space_pause_menu.tscn`). Worth deciding in the plan whether Lore Logs
      appears in mission mode, in open space, or both.
      
      **Done when:** the section opens from ESC, unlocked entries show their full text, locked ones are
      withheld but counted, the ratio is correct, and the gate is green. Note `ModuleList.MAX_ITEMS = 8`
      — a log catalogue will outgrow one screen, so scrolling or paging is in scope for this task.
      -> [docs/plans/the-esc-menu-has-a-lore-logs-section-where-i-can-re-read-eve](docs/plans/the-esc-menu-has-a-lore-logs-section-where-i-can-re-read-eve)
      1 run(s), $4.80; last on claude-sonnet-5

- [x] **Log records can be placed in assault and infiltration missions, not just the hub** _(done - feature, medium, sonnet)_
      **Player outcome:** the same log record I recognise from open space can be tucked into a
      wave gap in an assault run or behind a crate on a ground mission, and it counts the same way.
      
      **This is the task with the real obstacle, and it is worth knowing up front:** the infiltration
      player (`infiltration/scenes/entities/player/player.gd`) is a plain `CharacterBody2D` — it does
      **not** extend `PlayerBase` and is **not** in the `"player"` group. `PickupBase` finds the player
      by that group and then casts to `PlayerBase`, so **no existing pickup in the game can be collected
      on a ground mission today.** The plan has to choose between widening the pickup's detection so it
      does not require `PlayerBase`, or giving the ground player what the group contract expects — and
      the second is a much larger change to a module this epic is not otherwise touching.
      
      **Also in scope:**
      - Assault placement is authored in **640x360 design space, scaled by
        `ArenaCamera.WORLD_SCALE` (2.0) at runtime — never pre-multiply.**
      - An assault mission can be restarted or replayed from the pause menu. Decide and test what
        happens to an already-collected log on a replay: it must not double-count, and a player who
        quits mid-mission after grabbing one should not be punished for it. This is the "missable
        collectible" trap — a counter stuck at 99% because of a bookkeeping edge is the single most
        reliably infuriating thing about collectible systems
        (https://www.gamedeveloper.com/design/miss-able-collectibles-i-want-it-but-not-so-bad-i-ll-start-the-game-over-again).
      
      **Done when:** a log placed in an assault level and one placed in the infiltration test scene are
      both collectable, and a test pins the replay/restart behaviour. This task may well need splitting
      once its plan is written — if so, split it rather than half-finishing both modes.
      -> [docs/plans/log-records-can-be-placed-in-assault-and-infiltration-missio](docs/plans/log-records-can-be-placed-in-assault-and-infiltration-missio)
      2 run(s), $7.97; last on claude-sonnet-5

- [x] **Test logs on the open-space map prove both log types work end to end** _(done - feature, medium, sonnet)_
      **Player outcome (and the user's explicit ask):** boot the game, fly around the sector hub,
      and actually find several lore logs and a couple of information logs — enough to see the counter
      move, the ESC section fill up, and an in-world tablet re-read cleanly.
      
      **Where:** `open_space/scenes/levels/sector_hub.tscn` already carries nine pickup types and
      fourteen module unlockers placed as scene instances; the log records go in the same way, so this
      task is mostly authoring — placement, and writing real placeholder entry text rather than
      "Lorem ipsum". Spread them so at least one requires actually leaving the mission-select lane.
      
      **Done when:** at least three lore logs and two information logs are placed in the hub, the
      catalogue total reported by `LogState` matches what is placeable, and `bash /agent/verify.sh` is
      green — `tests/integration/test_project_load_integrity.gd` will load the modified hub scene and
      fail on any engine error or warning it produces.
      
      **Also finish the epic here:** update `docs/architecture/modules/global.md` (the pickups table in
      section 6 and the autoload list), `docs/architecture/PROJECT.md`, `open_space.md`, and
      `CLAUDE.md` via the `updating-project-docs` skill.
      -> [docs/plans/test-logs-on-the-open-space-map-prove-both-log-types-work-en](docs/plans/test-logs-on-the-open-space-map-prove-both-log-types-work-en)
      2 run(s), $3.58; last on claude-sonnet-5

## Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting  (`open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`, 0 open)

**Review history**

- _2026-09-13T14:02:11.598Z_ **changes** - Sorry, I moved 'plan review' step from progress to done. Looks like you didn't finish it yet, so I rejecting it for you to move it to done when you ready. As for now it looks great!
- _2026-09-14T08:26:43.992Z_ **approve**

**Preparation**

- [x] **Research: Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting** _(done - research)_
      Investigate this as a professional game developer would, before anything is designed: the existing architecture and systems it touches, reusable patterns already in the project, dependencies, constraints, candidate approaches with their tradeoffs, risks, edge cases, testing requirements, and impact on other systems. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage RESEARCH. Output: `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/1-context.md` and `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md`.
      
      **Triage summary:** The user wants open-space flight to steer with the mouse: the ship turns toward the cursor with a deliberate lag/inertia rather than snapping to it, turning noticeably slower than the current keys so precision aiming is not free, with weapons and movement abilities still firing along the ship's actual facing (the cursor only sets the target angle) - a Jet Lancer-style responsive-but-inertial feel. A/D turning stays as a selectable legacy scheme, the change must not reach assault or infiltration, and a setting toggles the schemes with mouse-aim as the default. What it builds on: open_space/scenes/entities/player/player_ship.gd is the only mode-specific controller (its `_handle_rotation()` is a flat `rotation += rotation_speed_deg * turn * delta` with no angular velocity, next to `_handle_thrust()`'s already-inertial thrust/damping/max_speed/flip-boost model), and because the open-space ship reuses the shared assault WeaponState node whose behaviors all fire from `actor.rotation` (straight_behavior.gd:16, spread_behavior.gd:15, sniper_behavior.gd:81, beam_behavior.gd:53), the 'weapons follow facing, not the cursor' requirement comes for free the moment the mouse only drives rotation - and mode isolation comes for free too, since assault's player is a separate scene (assault/scenes/player/player_fighter.tscn) with its own controller. The gap is the settings half: the project reads no mouse input anywhere (zero `get_global_mouse_position` / `InputEventMouseMotion` uses) and has no options system at all - no settings autoload, no options screen, and a PauseMenu whose five entries are hard-coded Node2D children - so this needs a small persisted settings store following the `user://*.cfg` ConfigFile pattern of SessionState/MissionState/ShipModuleState, plus a UI entry point to flip the scheme. Open questions for research and the plan: the turn model (max turn rate plus angular acceleration/damping, versus exponential smoothing toward the cursor angle) and the actual numbers that make mouse turning feel responsive yet slower than the 220 deg/s keyboard rate; whether the cursor should keep steering while the mission-select menu, PlayerMenu or PauseMenu is open, and what the cursor looks like on screen (crosshair, dead zone near the ship); and how mouse aim coexists with AiTargetingModule, which writes `actor.rotation` directly every frame to snap onto a target and would otherwise fight the turn controller, and EngineBoostModule, which latches its direction from `actor.rotation` at activation. Note for scheduling only: a separate untriaged idea, 'Add Boost/Burst Movement to Open Space', touches the same `_handle_thrust()` code path.
      
      **Original idea (idea-1789305113892):** Rework Open-Space Movement & Mouse Aiming:  Rework open-space movement to support mouse-based ship rotation and aiming.  Keep the existing A/D rotation controls as an alternative/legacy control scheme.  The new mouse system should rotate the ship toward the mouse position, providing more precise movement and shooting control.  Add a slight rotation delay/inertia when following the mouse, rather than making the ship instantly point at the cursor.  Make mouse-based rotation somewhat slower to keep the system balanced and avoid making aiming too powerful.  Weapons and movement abilities must follow the ship's actual facing direction, not the mouse position. The mouse only determines the direction the ship is trying to rotate toward.  This system should apply only to open-space missions and must not affect assault/land missions or other gameplay modes.  Add a setting/option to switch between the new mouse movement and the existing movement system, with the new mouse-based system enabled by default.  Overall movement should aim for a responsive but inertia-based feel, inspired by the movement style of Jet Lancer.
      -> [docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr](docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr)
      2 run(s), $6.35; last on claude-opus-5

- [x] **Plan: Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting** _(done - plan)_
      Consume the research and write the implementation plan to `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/3-plan.md`, then add this epic's implementation tasks with `add-task` - each with its own type, complexity, model and dependencies. The task list is half the deliverable: it is what the user reviews and prioritises. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage PLAN.
      after: research-open-space-mouse-aiming-inertial-turn-to-cursor-wit
      -> [docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr](docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr)
      1 run(s), $2.98; last on claude-opus-5

- [x] **Plan review: Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting** _(done - plan-review)_
      Dispatch an independent subagent to critique the plan AND the generated task list - technical correctness, missing requirements, architectural problems, unnecessary complexity, regressions, wrong task decomposition, wrong model assignments, missing tests or dependencies, and whether it actually solves the original idea. Verdict to `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/4-review.md`. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage PLAN REVIEW. Marking this done sends the epic to the user for approval.
      after: plan-open-space-mouse-aiming-inertial-turn-to-cursor-with-a-
      -> [docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr](docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr)
      4 run(s), $17.52; last on claude-opus-5

**Implementation**

- [x] **Your ship leans toward the mouse cursor instead of snapping to it** _(done - feature, medium, opus)_
      Adds `open_space/scenes/entities/player/ship_turn_controller.gd` (`class_name ShipTurnController extends Node`) and wires it into `open_space/scenes/entities/player/player_ship.tscn` as a child node of PlayerShip. It becomes the only writer of the open-space ship's rotation.
      
      Implements BOTH schemes behind an `@export var scheme: StringName` defaulting to `&"mouse"`:
      - mouse: clamped exponential chase toward the cursor angle (see `docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/3-plan.md` -> "Turn model" for the exact five lines), dead zone holds the target angle, `rotate_toward` applies the step.
      - keys: today's behaviour exactly, 220 deg/s, instantaneous, cursor ignored.
      
      `player_ship.gd::_handle_rotation` shrinks to reading the A/D axis, calling `set_aim_target(global_position, get_global_mouse_position())` and `rotation = _turn.step(rotation, turn, delta)`. `rotation_speed_deg` moves off `player_ship.gd` onto the controller. `get_global_mouse_position()` must appear in exactly one line project-wide.
      
      DONE WHEN: `tests/unit/test_ship_turn_controller.gd` passes with every case in the plan's test plan for that file - frame-rate independence, the turn-rate cap, no overshoot, wrap-around across +-pi, cursor-exactly-on-ship, the 47.9/48.1 px dead-zone edge, the 180-degree tie-break, "classic is still 220 deg/s", "classic ignores the cursor", "mouse ignores A/D". No autoload and no UI in this task - the scheme is flipped by hand in the test / inspector. Gate green.
      1 run(s), $4.08; last on claude-opus-5

- [x] **The game remembers which steering scheme you fly with** _(done - feature, small, sonnet)_
      Adds `global/autoloads/settings_state.gd` (`SettingsState`), the project's first settings store. Near-copy of the `ConfigFile` template in `global/autoloads/ship_module_state.gd`: `SAVE_PATH = "user://settings.cfg"`, `SECTION = "controls"`, key `open_space_scheme`, `SCHEMES = [&"mouse", &"keys"]`, `DEFAULT_SCHEME = &"mouse"`, `signal open_space_scheme_changed(scheme: StringName)` (declared with its argument - `test_signal_emit_arity.gd` sweeps self-emits).
      
      Default-on-missing comes from `ConfigFile.get_value(SECTION, KEY, default)` and is re-validated against `SCHEMES` on load. Deliberately NOT the `UpgradeState.STARTING_IDS` idiom - see the plan's "the setting is a new SettingsState autoload" for why that shape is wrong here.
      
      Also: register in `project.godot` `[autoload]`; add `"user://settings.cfg"` to `tests/helpers/save_sandbox.gd::PATHS` (without it every test touching the setting leaks into the player's profile and the next suite run). `player_ship.gd` seeds `_turn.scheme` from the autoload in `_ready()` and connects `open_space_scheme_changed` to `_turn.set_scheme(scheme, rotation)`.
      
      DONE WHEN: `tests/unit/test_settings_state.gd` passes - default on empty disk, round-trips through a second instance's `_load()`, falls back to the default on a hand-corrupted value, rejects a value not in SCHEMES, and does not emit when set to the value it already holds. Plus the "scheme flip mid-flight causes no rotation jump" case in `tests/unit/test_ship_turn_controller.gd`. No UI yet. Gate green.
      after: your-ship-leans-toward-the-mouse-cursor-instead-of-snapping-
      1 run(s), $1.37; last on claude-sonnet-5

- [x] **AI Targeting still snaps your nose onto an enemy, and the snap holds** _(done - feature, small, sonnet)_
      `global/ship_modules/ai_targeting_module.gd:38` writes `actor.rotation =` directly. Under the turn controller that write is undone within a frame or two, so the 15-second-cooldown module the player unlocked and equipped visibly does nothing under mouse aim.
      
      Fix, per the plan's chosen option (a):
      - `OpenSpacePlayerShip.face_instant(angle: float)` - sets rotation, adopts `angle` as the controller's target, and suppresses cursor steering.
      - The module calls it duck-typed (`if actor.has_method("face_instant")`), the same shape as `is_armored()` in CLAUDE.md, because the module lives in `global/` and must not assume an open-space actor.
      - Suppression is cleared by REAL mouse motion, not by cursor position: `get_global_mouse_position()` is a world position that moves with the camera, so a physically still mouse would otherwise clear it immediately. `player_ship.gd::_input()` gains an `InputEventMouseMotion` branch calling `_turn.notify_mouse_moved()` before its existing `use_ability` early-return. Do not mark motion events as handled.
      
      DONE WHEN: the "snap holds until the mouse moves" case in `tests/unit/test_ship_turn_controller.gd` passes (face_instant, then steps with a cursor 90 degrees away leave rotation put; notify_mouse_moved, and the next step turns), and the module still snaps under `scheme = &"keys"` exactly as it does today. Gate green.
      after: your-ship-leans-toward-the-mouse-cursor-instead-of-snapping-
      1 run(s), $1.19; last on claude-sonnet-5

- [x] **A future ship module cannot silently fight your steering** _(done - test, small, sonnet)_
      Adds `tests/integration/test_ship_rotation_single_writer.gd`, the suite's eleventh invariant test. After this epic the "exactly one writer of the open-space ship's rotation" rule is what keeps mouse aim working, and it is precisely the kind of rule the fifteenth ship module breaks with no visible symptom - which is exactly how `ai_targeting_module.gd` came to fight the controller in the first place.
      
      Sweep every `global/ship_modules/*.gd` and assert none assigns to `actor.rotation` (`=`, `+=`, `-=`). Allowlist empty; the sanctioned route is `face_instant()`.
      
      Boundary cases that make it able to fail:
      - the sweep must find a non-zero number of module files and must find `ai_targeting_module.gd` among them by name - a glob that silently matched nothing must not read as a pass;
      - `OpenSpacePlayerShip` must expose a `face_instant` method, so the rule points at a replacement rather than only forbidding the old call.
      
      DONE WHEN: the test passes on the fixed tree, and reverting the duck-typed call in `ai_targeting_module.gd` makes it fail (check that by hand before committing - an invariant that cannot fail is worth nothing). Gate green. Add the test to the list in `CLAUDE.md` and `tests/README.md` alongside the other invariant tests.
      after: ai-targeting-still-snaps-your-nose-onto-an-enemy-and-the-sna
      1 run(s), $1.02; last on claude-sonnet-5

- [x] **Alt-tabbing away no longer leaves your ship turning on its own** _(done - feature, small, sonnet)_
      When the game window loses focus the OS pointer stops updating but `get_global_mouse_position()` keeps returning the last in-window position, so the ship holds a stale target angle and keeps turning toward it while the player is in another window.
      
      Adds `ShipTurnController.set_steering_enabled(enabled: bool)` - while false the target angle is frozen and `step()` still runs (so no rotation discontinuity on resume) - and `player_ship.gd::_notification()` handling `NOTIFICATION_APPLICATION_FOCUS_OUT` / `NOTIFICATION_APPLICATION_FOCUS_IN`.
      
      Explicitly NOT doing pointer confinement (`MOUSE_MODE_CONFINED` takes the pointer hostage on a multi-monitor desktop) or capture with a software cursor - both are out of scope per the plan. The narrower "pointer left the window but the window is still focused" case stays uncovered and that is accepted.
      
      DONE WHEN: the "steering disabled freezes the target" case in `tests/unit/test_ship_turn_controller.gd` passes - cursor moves while disabled and rotation does not change, re-enabling resumes with no jump. Gate green.
      after: your-ship-leans-toward-the-mouse-cursor-instead-of-snapping-
      1 run(s), $0.60; last on claude-sonnet-5

- [x] **Choose mouse aim or classic A/D steering from the pause menu** _(done - feature, medium, opus)_
      The last step: the player can actually pick a scheme. Until this lands the setting exists but only a test can change it.
      
      `global/ui/pause_menu/pause_menu.gd` hard-codes `Option0..Option4` and `_confirm()` matches on the index. Add a new `Option4` = "Settings" and move today's Exit Game to `Option5`, in BOTH `pause_menu.tscn` and `open_space_pause_menu.tscn` (they duplicate their option nodes rather than sharing them). Settings goes before Exit Game so Exit Game stays last where a player expects it; `tests/integration/test_pause_menu_lore_logs.gd` references only indices 1-3 so it needs no change - confirm that before assuming it.
      
      `global/ui/pause_menu/settings_panel.{gd,tscn}` is a sub-overlay copying `LoreLogList`'s `open()`/`close()`/`navigate()` shape and the `_lore_logs_open` routing branch verbatim in spirit: while open it absorbs ALL menu input including `menu_confirm` (it must never fall through to `_confirm()` and re-open itself), and `ui_cancel` returns to the option list rather than closing the whole menu. One row - "Open-Space Steering: Mouse Aim / Classic (A/D)" - with menu_left/menu_right cycling the value straight into `SettingsState`. No generic settings framework for one two-valued key.
      
      The row is shown in all three modes: it is a stored preference, and hiding it in missions would make a player fly back to the hub to change their controls. The label names its scope, which is what keeps it from being a discoverability trap.
      
      New `.tscn`/`.gd` go UID-less or get a UID minted with the headless `ResourceUID.create_id()` snippet in `tests/README.md`. Never hand-typed, never copied from a sibling.
      
      DONE WHEN: `tests/integration/test_pause_menu_settings.gd` passes with every case in the plan's test plan for that file - including the one that drives the LIVE `SettingsState` through `menu_right` (a settings row whose handler is empty passes every "is it visible and labelled" assertion), and the one proving `menu_confirm` does not fall through while the panel is open. Sandboxed via `tests/helpers/save_sandbox.gd`. Gate green, and `updating-project-docs` run - this adds a UI component to a shared module.
      after: the-game-remembers-which-steering-scheme-you-fly-with

## Open-space boost: Shift burst movement on an upgradeable boost meter  (`open-space-boost-shift-burst-movement-on-an-upgradeable-boos`, 6 open)

**Review history**

- _2026-09-14T20:57:44.351Z_ **approve**

**Preparation**

- [x] **Research: Open-space boost: Shift burst movement on an upgradeable boost meter** _(done - research)_
      Investigate this as a professional game developer would, before anything is designed: the existing architecture and systems it touches, reusable patterns already in the project, dependencies, constraints, candidate approaches with their tradeoffs, risks, edge cases, testing requirements, and impact on other systems. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage RESEARCH. Output: `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/1-context.md` and `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/2-research.md`.
      
      **Triage summary:** The user wants Jet Lancer-style momentum movement in open space: Shift fires a burst of speed along the ship's current facing, drains a dedicated boost meter, shows the existing blue/cyan afterburner, and a ~180-degree turn plus boost should kill current momentum and redirect it, so flying becomes bursts and redirects rather than held thrust. The meter should be an upgradeable resource like health and shields, with a bar shown next to the weapon overheat meter, and none of it may touch assault or infiltration. Much of this already exists in pieces. OpenSpacePlayerShip (open_space/scenes/entities/player/player_ship.gd) already carries the momentum model (thrust_acceleration 380, reverse_acceleration 220, max_speed 420, damping 0.6) and a prototype of the flip mechanic: _trigger_flip_boost() fires when move_up is pressed while the ship is travelling backwards at >= boost_speed_threshold 180 px/s, snapping velocity to boost_redirect_speed 200 for boost_duration_sec 0.3 - the idea is essentially to promote that hidden special case into the primary, metered, upgradeable verb. ThrusterEffect.State.BOOST is the cyan afterburner the idea asks to reuse, and the ship sprite has a flame_boost animation. ShipProgressionState (global/autoloads/ship_progression_state.gd) is the exact precedent for a persisted, clamped, signal-emitting upgrade stat, and ShipShieldUpPickup plus the test_module_unlock_sources.gd placement invariant are the precedent for the collectible that raises it. Mode exclusivity is structural rather than a flag: this player script is open-space only. The open question the research stage has to settle is EngineBoostModule (global/ship_modules/engine_boost_module.gd), the equippable engines-slot module that already does a facing-direction burst - 1500 px/s easing to 500 over 0.55 s, i-frames, 45 contact damage, 2 s cooldown on the H key - and owns velocity by setting engine_boost_active to make _handle_thrust() stand down. A core Shift boost would be a second system claiming the same velocity, the same cyan flame and the same fantasy, so the epic must decide whether the module is superseded, re-cast as a meter upgrade, or kept as a distinct heavier ability. Three smaller decisions go with it: no boost input action exists (dash is already bound to Shift but is read only by the infiltration player); in open space the overheat meter is a world-space bar under the ship, not a HUD control, so where the boost bar actually belongs needs a call; and the sibling draft epic open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr rewrites _handle_rotation in the same _physics_process, so the two need a shared story about who owns open-space movement.
      
      **Original idea (idea-1789305251413):** Add Boost/Burst Movement to Open Space  Introduce a dedicated boost mechanic for open-space movement.  Reuse the existing blue boost flames/effect as the visual feedback for boosting.  Pressing Shift activates the boost and consumes a dedicated boost meter.  Boost should provide a significant burst of speed in the current direction the ship is facing.  The boost meter should become a progression/resource system that can be improved through collectibles/upgrades, similar to the existing health and shield upgrades.  Move the existing thrust/braking behavior into the boost system.  If the player turns the ship approximately 180° and activates boost, the ship should use the boost to rapidly reduce its current movement and transition into movement in the newly facing direction.  The goal is to allow quick direction changes and momentum manipulation rather than requiring continuous thrusting.  The overall movement should aim to reproduce the fast, momentum-based combat movement of Jet Lancer, while fitting the game's existing physics and balance.  Add a boost meter UI near the existing weapon overheat meter so both combat resources are visible together.  Boost should be exclusive to open-space gameplay and should not alter movement in other mission types.
      -> [docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos](docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos)
      2 run(s), $9.65; last on claude-opus-5

- [x] **Plan: Open-space boost: Shift burst movement on an upgradeable boost meter** _(done - plan)_
      Consume the research and write the implementation plan to `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`, then add this epic's implementation tasks with `add-task` - each with its own type, complexity, model and dependencies. The task list is half the deliverable: it is what the user reviews and prioritises. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage PLAN.
      after: research-open-space-boost-shift-burst-movement-on-an-upgrade
      -> [docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos](docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos)
      2 run(s), $5.04; last on claude-opus-5

- [x] **Plan review: Open-space boost: Shift burst movement on an upgradeable boost meter** _(done - plan-review)_
      Dispatch an independent subagent to critique the plan AND the generated task list - technical correctness, missing requirements, architectural problems, unnecessary complexity, regressions, wrong task decomposition, wrong model assignments, missing tests or dependencies, and whether it actually solves the original idea. Verdict to `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/4-review.md`. Follow the `feature-workflow` skill's `references/epic-prep.md`, stage PLAN REVIEW. Marking this done sends the epic to the user for approval.
      after: plan-open-space-boost-shift-burst-movement-on-an-upgradeable
      -> [docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos](docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos)
      2 run(s), $16.76; last on claude-opus-5

**Implementation**

- [ ] **Shift slams your ship onto its new heading and launches it** _(todo - feature, medium, opus)_
      The core verb, with no meter yet. Plan: `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/3-plan.md`
      (sections **Design → The one decision**, **The speed cap**, **Where Input is read**, **What is
      deleted**, and **Test plan → Ship instances go in the tree**).
      
      DONE WHEN a player in the sector hub can press Shift and have the ship's momentum snap onto the
      nose's heading at `boost_exit_speed = 700` px/s (vs `max_speed = 420`), with the cyan `flame_boost`
      animation and both `ThrusterEffect`s in `BOOST` for `boost_hold_sec = 0.35` s — so a 180° turn plus
      Shift replaces the ~3.0 s manual reversal — and all cases of the new
      `tests/integration/test_open_space_boost_verb.gd` pass.
      
      Touches:
      - `project.godot` `[input]` — new `boost` action on Shift (`physical_keycode 4194325`). Third
        action on that key; deliberate, argued in the plan.
      - `open_space/scenes/entities/player/player_ship.gd` — new `@export`s (`boost_exit_speed`,
        `boost_hold_sec`, `boost_ceiling_decay`); new `_step_boost(boost_pressed: bool, delta: float)`
        holding the whole model; `_handle_thrust()` reads `Input.is_action_just_pressed("boost")` in
        **exactly one place** and calls `_step_boost()` last; `_step_boost()` takes over the tail speed
        clamp via the decaying `_speed_ceiling` (there must be exactly one clamp when you are done).
      - **`_step_boost()` opens with `if engine_boost_active: return`.** This is deliberately redundant
        with `_handle_thrust()`'s own early return and must not be "cleaned up": every test calls
        `_step_boost()` directly and so bypasses the outer guard, so without this line the two cases
        that pin module precedence fail on a *correct* build. See `3-plan.md` → "the precedence guard is
        deliberately doubled". If either precedence case fails, add the guard — do not weaken the case.
      - **Delete** `_trigger_flip_boost()`, its `move_up`-just-pressed trigger, and the
        `boost_redirect_speed` / `boost_speed_threshold` exports. Rename `boost_duration_sec` →
        `boost_hold_sec`.
      - New `tests/integration/test_open_space_boost_verb.gd`.
      
      Do NOT: **write** `engine_boost_active` — it is read here and stays owned by
      `global/ship_modules/engine_boost_module.gd`; edit `global/entities/player_base.gd`; edit
      `engine_boost_module.gd` or anything in `assault/`; touch the `damping` line.
      
      **Order inside `_step_boost()` is part of the contract:** the `boost_hold_sec` retrigger floor is
      checked **before** any spend, so mashing Shift inside the hold window costs nothing. Assert it —
      two `_step_boost(true, d)` calls inside `boost_hold_sec` leave `charges` down by exactly 1.0 once
      the meter exists (step 2); in this task assert only that the second call does not re-slam
      `velocity` to 700.
      
      **Who plays the flame:** `_step_boost()` is otherwise pure, but the animation needs the tree —
      put the `flame_boost` / `ThrusterEffect.State.BOOST` call in `_step_boost()`'s trigger branch and
      note in the plan that this is its one tree touch, following
      `global/ship_modules/engine_boost_module.gd:15,63-67`. `sprite.animation == &"flame_boost"` is
      assertable headless, so give the epic's "reuse the blue boost flames" bullet a real case.
      Note that because `_step_boost()` runs at the *tail* of `_handle_thrust()`, the thruster visual
      lands one physics frame after the boost (today's `_boost_timer` is set before the branches). That
      is a known, accepted one-frame difference, not a bug to chase.
      
      **Every case in this file adds the ship to the tree** (`add_child_autofree(ship)`) before calling
      anything: `_handle_thrust` dereferences `_thruster`, which only exists after `_setup_effects()`
      runs from `_ready()`. Parenting also runs `SessionState.apply_to()`.
      
      Write the regression case first — `ship.has_method("_trigger_flip_boost")` is false and
      `"boost_speed_threshold" not in ship` — and the cruise-boost boundary case
      (`velocity = UP * 420`, boost, `velocity.length() > max_speed`). Both fail on today's build.
      
      **Re-read `player_ship.gd` and `player_ship.tscn` from HEAD before editing** — the mouse-aiming
      epic lands first and moves these line numbers (it deletes `_ready()`'s `rotation = 0.0`; boost
      reads `rotation` for facing, which is fine). **Do not work this in the same window as a
      mouse-aiming task.**
      
      Invoke `updating-project-docs`: this adds an input action and a movement verb that
      `docs/architecture/modules/open_space.md` enumerates.
      
      The numbers are `@export`s on purpose — the gate cannot say whether 700 px/s feels right. Say so in
      the report and leave them for a human fly-test.

- [ ] **Boosting costs a charge, and charges come back on their own** _(todo - feature, medium, opus)_
      The cost. Plan sections **Design → The meter: `BoostMeter`, a component beside the ship** AND
      **Test plan → Autoload discipline** (read both — the second one is not optional, see below).
      
      DONE WHEN each Shift boost spends one charge from a 2-charge meter, an empty meter refuses the
      boost outright (nothing happens, nothing is spent, W/S still fly the ship), charges refill at 0.7
      per second starting 0.5 s after the last boost — empty to full in ~3.4 s — and both new test files
      pass.
      
      Touches:
      - New `open_space/scenes/entities/player/boost_meter.gd` — `class_name BoostMeter extends Node`.
        `signal charges_changed(current: float, maximum: int)` (declared with its parameters —
        `tests/integration/test_signal_emit_arity.gd` sweeps this). `@export`s `recharge_rate`,
        `recharge_delay_sec`, `bind_progression`. API `can_spend()`, `try_spend()`, `step(delta)`.
        Continuous internal float, whole-unit spends.
      - `open_space/scenes/entities/player/player_ship.tscn` — add the `BoostMeter` child node.
      - `player_ship.gd` — `_step_boost()` calls `meter.step(delta)` and gates the trigger on
        `meter.try_spend()`, replacing step 1's `boost_hold_sec`-only floor (the hold window stays, as
        the flame window and a retrigger floor). **Check the hold window before the spend**, so a boost
        refused by the retrigger floor costs nothing; assert it (two `_step_boost(true, d)` inside
        `boost_hold_sec` → `charges` down by exactly 1.0).
      - New `tests/unit/test_boost_meter.gd` (tree-less `BoostMeter.new()`, `free()` in `after_each`).
      - New `tests/integration/test_open_space_boost_wiring.gd`.
      
      ⚠️ **`test_open_space_boost_wiring.gd` must carry the autoload-snapshot block from day one**, even
      though nothing here binds to the autoload yet. It instantiates `player_ship.tscn`, and from the
      persistence task onward that scene carries a `BoostMeter` whose `_ready()` reads the **live**
      `ShipProgressionState`. `tests/helpers/save_sandbox.gd` covers the `user://` **file only** and does
      nothing to the in-memory singleton, so `SaveSandbox` alone is not enough. Copy the two-layer
      `before_all` / `after_all` / `before_each` pattern from **`3-plan.md` → Test plan → "Autoload
      discipline"** (the shape is `tests/integration/test_weapon_unlock_sources.gd:38-53`): sandbox the
      file **plus** snapshot and restore `ShipProgressionState._boost_charge_count` and
      `_permanent_shield_count`. It is inert today and correct later; retrofitting it after the
      persistence task means debugging a failure that only reproduces in a **full-suite** run.
      
      Ship instances go in the tree: `add_child_autofree(ship)` before any `_handle_thrust()` call, or
      `_thruster` is null and the call is a hard error.
      
      `BoostMeter` must NOT define its own `_physics_process` — the ship drives `step()`. That is a
      deliberate difference from `Overheat`, because `set_physics_process(false)` on the ship (which
      `MissionTrigger._open_menu()` calls) does not stop a child's own physics tick, and because a
      hand-driven `step()` is what makes the component unit-testable headless. It must also read no
      `Input` and touch no tree.
      
      `bind_progression` exists now but has nothing to bind to yet — default it `false` here and leave
      the `ShipProgressionState` hookup to the persistence task. `max_charges` starts at 2.
      
      Write `tests/integration/test_open_space_boost_wiring.gd` FIRST — it is the anti-inert test, and
      the unit tests are all green on a build where `BoostMeter` is never added to `player_ship.tscn`.
      Find the node **by class, not by node path**. Its two boundary cases matter most: an empty meter
      leaves `velocity` untouched, and a boost refused because `engine_boost_active` is true burns no
      charge (that one passes on `_step_boost()`'s own guard and on nothing else — if it fails, add the
      guard, do not weaken the case).
      
      The "boost is open-space only" invariant names two scenes explicitly:
      `assault/scenes/player/player_fighter.tscn` and the infiltration player scene under
      `infiltration/scenes/entities/player/` — name the actual file, or the sweep quietly covers one.
      
      Run `scripts/check-test-leaks.sh` if any test awaits.
      
      Invoke `updating-project-docs`: a new component class in the ship scene, which
      `docs/architecture/modules/open_space.md` and `global.md` enumerate.
      after: shift-slams-your-ship-onto-its-new-heading-and-launches-it

- [ ] **A cyan pip bar under your ship shows how many boosts you have left** _(todo - feature, small, sonnet)_
      The readout. Plan sections **Design → The bar** AND **Test plan → Autoload discipline**.
      
      DONE WHEN the player can see their boost charges as cyan pips in a 32x4 bar drawn just below the
      existing overheat bar under the hull, the bar is correct **the instant the scene loads** (not only
      after the first boost), the partially-recharged pip fills smoothly as it recovers, and
      `tests/integration/test_boost_bar.gd` passes.
      
      Touches:
      - New `open_space/scenes/gui/boost_bar.gd` — `class_name BoostBar extends Node2D`, modelled on
        `assault/scenes/player/overheat_bar.gd`: `_draw()` with a dark backing rect, `BAR_WIDTH 32`,
        `BAR_HEIGHT 4`, split into `max_charges` segments with a 1 px gap, filled segments in the
        thruster cyan `Color(0.35, 0.9, 1.0)`. `setup(meter: BoostMeter)` connects `charges_changed`;
        the segment count follows the signal's `maximum` argument so a mid-session upgrade widens the
        bar with no extra wiring.
      - **The handler stores what it draws:** `_on_charges_changed` assigns members `_charges: float`
        and `_max_charges: int` then calls `queue_redraw()`. Do not compute geometry inline in `_draw()`
        from a held meter reference — `overheat_bar.gd:7` keeps `_percentage` the same way, and a
        `_draw()`-only node exposes nothing a headless test can assert.
      - ⚠️ **`setup()` must also SEED `_charges` / `_max_charges` from the meter and `queue_redraw()`.**
        Children `_ready()` before parents, so `BoostMeter`'s initial emit fires *before*
        `OpenSpacePlayerShip._ready()` creates the bar and calls `setup()`. Connecting alone means
        nothing emits again until the first spend, so a freshly loaded hub draws an empty bar on a full
        meter. `OverheatBar` hides this hole with `visible = false`; an always-visible bar cannot.
        Assert it: immediately after `_ready()`, with **no** signal emitted, `bar._max_charges ==
        meter.max_charges`. The "visible at full" case passes on the broken build (`visible` defaults
        true), so it does not cover this.
      - `player_ship.gd::_ready()` — create it exactly as `_overheat_bar` is created (`top_level = true`,
        `add_child`), and in `_physics_process` position it at `global_position + Vector2(0, 26)`.
      - New `tests/integration/test_boost_bar.gd`.
      
      **Every case in this file needs `add_child_autofree(ship)`**, not just the overlap one: the bar is
      constructed in `_ready()`, so on a merely-instantiated ship there is no `BoostBar` child at all and
      even "the bar is in the scene" fails.
      
      ⚠️ **This file needs the autoload-snapshot block from day one.** It instantiates `player_ship.tscn`
      and adds it to the tree, and from the persistence task onward that scene carries a `BoostMeter`
      whose `_ready()` reads the **live** `ShipProgressionState`. `tests/helpers/save_sandbox.gd` covers
      the `user://` **file only**. Copy the two-layer pattern from **`3-plan.md` → Test plan → "Autoload
      discipline"** (shape: `tests/integration/test_weapon_unlock_sources.gd:38-53`) — sandbox the file
      **plus** snapshot/restore `ShipProgressionState._boost_charge_count` and `_permanent_shield_count`.
      Inert today, correct later, and it saves debugging a full-suite-only failure.
      
      **Where it goes is settled, do not re-litigate it.** The epic asks for the bar "near the existing
      weapon overheat meter"; in open space the overheat meter is a world-space bar under the ship at
      `(0, 20)`, NOT a HUD element — `open_space/scenes/gui/hud.tscn` has no overheat element at all.
      Putting this in the HUD would satisfy the words and break the intent.
      
      The bar is always visible, including at full charges. A resource readout that hides itself is the
      failure the epic exists to fix. Pin that in a test.
      
      The overlap boundary case needs one physics frame awaited; assert the two bars' `global_position.y`
      differ by at least `OverheatBar.BAR_HEIGHT`.
      
      Invoke `updating-project-docs`: a new UI class under `open_space/scenes/gui/`.
      after: boosting-costs-a-charge-and-charges-come-back-on-their-own

- [ ] **Extra boost charges you earn stay with your ship between runs** _(todo - feature, small, sonnet)_
      The persistence. Plan sections **Design → Persistence and the upgrade** AND **Test plan →
      Autoload discipline**.
      
      DONE WHEN the ship's boost capacity is a saved stat (2 at base, 5 at cap) that survives quitting
      the game, raising it mid-flight immediately widens the live meter AND grants the new charge right
      away rather than next session, and the new cases in `tests/unit/test_ship_progression_state.gd`
      and `tests/unit/test_boost_meter.gd` pass.
      
      Touches:
      - `global/autoloads/ship_progression_state.gd` — a **second key on the existing ConfigFile**, not a
        new autoload: `KEY_BOOST`, `MIN_BOOST_CHARGES = 2`, `MAX_BOOST_CHARGES = 5`,
        `signal boost_charge_count_changed(new_count: int)`, `boost_charge_count` getter,
        `set_boost_charge_count()` (clamp, no-op when unchanged, save, emit) and `add_boost_charge()`
        (false at cap). Mirror the shield stat line for line, including the out-of-range
        `push_warning` on load. `_save()` writes both keys; `_load()` reads and clamps both independently.
      - `open_space/scenes/entities/player/boost_meter.gd` — flip `bind_progression` to `true` by
        default and implement `_ready()` / `_on_progression_changed()` copying
        `global/components/shield_component.gd:38-46` and `:116-124`, **including the immediate grant of
        the new charge**.
      - ⚠️ `open_space/scenes/entities/player/player_ship.tscn` — **set `bind_progression = true`
        explicitly on the `BoostMeter` node, and make sure the scene diff shows that line.** The
        `@export` default is not enough to rely on, and this is not hypothetical: `player_ship.tscn:223`
        authors its `ShieldComponent` with no `bind_progression` line, falls back to
        `shield_component.gd:20`'s `false`, and that is exactly why the hub's shield-up pickup raises a
        number the open-space ship never reads (filed as
        `the-open-space-ship-never-reads-the-permanent-shield-upgrade`). Follow
        `assault/scenes/player/player_fighter.tscn:301`, the one scene that gets this right — **not**
        `player_ship.tscn`'s `ShieldComponent`. A meter that silently ignores the upgrade makes the next
        two tasks ship a pickup that does nothing visible.
      - Extend `tests/unit/test_ship_progression_state.gd` and `tests/unit/test_boost_meter.gd`.
      
      **Write the autoload cases against a tree-less `ProgressionScript.new()` via the existing
      `_fresh()` helper (`test_ship_progression_state.gd:18-19`), like their shield siblings** — that
      file does not touch the live singleton today and should not start. `tests/README.md`'s house rule
      is to prefer a tree-less `Script.new()` instance. `SaveSandbox` still applies wherever a save path
      is exercised. The live-singleton snapshot pattern is for the files that instantiate
      `player_ship.tscn` or collect a real pickup, not for this one.
      
      Note that flipping `bind_progression` to `true` is what arms the hazard the wiring and bar test
      files were told to guard against — if either starts failing only in a **full-suite** run, it is
      missing the two-layer snapshot block, not broken.
      
      Three boundary cases are the point of this task: `add_boost_charge()` at the cap returns false and
      emits **nothing**; a saved value of 99 clamps on load; and adding a boost charge does not disturb
      `permanent_shield_count`, because the two stats share one `ConfigFile`.
      
      Invoke `updating-project-docs`: `docs/architecture/modules/global.md` documents the autoload's
      contract.
      after: boosting-costs-a-charge-and-charges-come-back-on-their-own

- [ ] **A pickup in the hub permanently adds a boost charge** _(todo - feature, small, sonnet)_
      The source. Plan sections **Design → Persistence and the upgrade** (pickup paragraph) AND
      **Test plan → Autoload discipline**.
      
      DONE WHEN the player can fly into a collectible on the sector hub's pickup bench, see the "+1
      boost" notification, watch the pip bar gain a segment on the spot, and still have that charge after
      restarting the game — and `tests/integration/test_boost_upgrade_source.gd` passes.
      
      Touches:
      - New `global/pickups/ship_boost_up_pickup.gd` — `class_name ShipBoostUpPickup extends PickupBase`,
        a near-verbatim copy of `ship_shield_up_pickup.gd`: `_collect()` calls
        `ShipProgressionState.add_boost_charge()`, `_get_dialog_text()` returns the notification line.
      - New `global/pickups/scenes/ship_boost_up_pickup.tscn` — copy
        `scenes/ship_shield_up_pickup.tscn`: `Area2D` `collision_layer = 16`, `collision_mask = 4`,
        `Sprite2D`, `CollisionShape2D` with a `CircleShape2D` radius 8 at `scale = 3.111`.
        **v1 reuses the existing `global/assets/sprites/player_menu_ui/ship_menu_ui/module_icons/icon_ship_module_engine_boost.png`**
        (40x30) scaled to roughly match the shield pickup's 48x48 on-screen size. Do not generate art in
        this task — that is its own, droppable task.
      - `open_space/scenes/levels/sector_hub.tscn` — instance it on the bench row at
        `position = Vector2(620, -212)`. The row currently runs x = 27, 104, 205, 304, 413, 519.
      - New `tests/integration/test_boost_upgrade_source.gd`, in the same family as
        `tests/integration/test_module_unlock_sources.gd`.
      
      **Never hand-type a `uid://` and never copy one from a sibling file.** Leave the new `.tscn`
      UID-less (legal) or mint one with the headless `ResourceUID.create_id()` snippet in
      `tests/README.md`. `tests/integration/test_resource_uid_integrity.gd` and
      `test_project_load_integrity.gd` both see this file.
      
      The second test case is the one that matters: every placement test passes on a pickup whose
      `_collect()` is empty, so collect a **real instance** and assert the count went up.
      
      ⚠️ **`_collect()` calls the `ShipProgressionState` AUTOLOAD**, not any instance the test holds, and
      the whole GUT process shares it — so a fresh script instance would prove nothing, and mutating the
      live one leaks a raised boost count into every later test. `tests/helpers/save_sandbox.gd` covers
      the `user://` **file only** and does nothing to the in-memory singleton; there is no such thing as
      a "sandboxed autoload". Use the two-layer pattern in **`3-plan.md` → Test plan → "Autoload
      discipline"**, whose shape is `tests/integration/test_weapon_unlock_sources.gd:38-53`: `SaveSandbox`
      for the file, **plus** `before_all`/`after_all` snapshot and restore of
      `ShipProgressionState._boost_charge_count` and `_permanent_shield_count`, and a `before_each` that
      assigns the backing fields directly so the fixture does not depend on the code under test.
      Get this wrong and `tests/unit/test_boost_meter.gd` fails — GUT walks `res://tests` with
      `-ginclude_subdirs`, so `integration/` runs before `unit/` and the damage only shows up in a
      **full-suite** run.
      
      Reach the cap for the at-cap boundary case by assigning `_boost_charge_count` directly, never by
      collecting five pickups — same reason: the fixture must not depend on the code under test.
      
      Invoke `updating-project-docs`: a new pickup, which `docs/architecture/modules/global.md`
      enumerates.
      after: extra-boost-charges-you-earn-stay-with-your-ship-between-run

- [ ] **The boost-up pickup has its own sprite instead of a borrowed menu icon** _(todo - art, small, sonnet)_
      Cosmetic finish. **Optional and droppable** — the feature is complete and playable without it, and
      this task spends the capped monthly PixelLab allowance irreversibly. Drop it if the allowance is
      tight.
      
      DONE WHEN the boost-up collectible on the hub bench reads as its own thing rather than a menu icon
      someone dropped into the world, matching the visual weight of `ship_shield_up.png` (48x48) next to
      it on the same row.
      
      Touches:
      - One new sprite under `global/assets/sprites/`.
      - `global/pickups/scenes/ship_boost_up_pickup.tscn` — swap the `Sprite2D` texture and drop the
        scale workaround the previous task added.
      
      **Invoke the `pixel-art-generation` skill before generating anything.** `open_space/` is strict
      top-down orthographic and NEVER isometric; the skill enforces that with explicit PixelLab
      parameters (`view: "high top-down"`, `isometric: false`), picks the right tool for a single small
      object, and covers saving the binary safely via `scripts/pixellab.sh` (the Write tool corrupts
      PNGs). **Open the generated image and look at it before committing** — a wrong-angle sprite cannot
      be fixed in code.
      
      Read cyan/blue to match the thruster's boost palette `Color(0.35, 0.9, 1.0)` and the pip bar, so
      the pickup and the resource it feeds are visibly the same system.
      
      Check it against `tests/integration/test_entity_sprite_transparency.gd`'s rule (no painted-in
      background) even though a pickup under `global/` is outside that test's roots — a card of opaque
      background cut out of the starfield looks just as wrong here.
      after: a-pickup-in-the-hub-permanently-adds-a-boost-charge

## Foundations: test harness, UID integrity, art pipeline  [DONE]  (`foundations-test-harness-uid-integrity-art-pipeline`, 0 open)

- [x] **Bootstrap the test harness.** _(done - feature, medium, sonnet)_
      Install GUT into `addons/gut/`, create `tests/`, and write
      characterization tests for the eight autoloads and the `global/components/` set (Health,
      Hurtbox/Hitbox, Shield, Overheat, DamageReaction). Tests must pin down current behaviour,
      bugs included — no fixes this run. Done when `bash /agent/verify.sh` passes with a green
      suite. *(The agent does this automatically while `addons/gut/` is missing, ignoring
      everything below.)*
      **Done 2026-08-31** — GUT 9.7.1 vendored into `addons/gut/` (two files patched for Godot
      4.6.3, see `addons/gut/LOCAL_PATCHES.md`), 153 tests / 490 asserts across 16 scripts in
      `tests/`, gate green. Conventions and the gotchas that cost time are in `tests/README.md`.

- [x] **Fix the stale UID in `open_space/scenes/gui/hud.tscn:6`.** _(done - feature, medium, sonnet)_
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

- [x] **Regenerate the turret sprites — `station_turret.png` is 3/4 view, not top-down.** _(done - feature, medium, sonnet)_
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

- [x] **1. Station and turrets exist as a destructible entity.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-mini-boss-destructible](docs/plans/station-mini-boss-destructible)

- [x] **2. The encounter blocks level progress.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-assault-section](docs/plans/station-assault-section)

- [x] **3. Laser phase.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-laser-phase](docs/plans/station-laser-phase)

- [x] **4a. The station shoots back.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-bullet-hell](docs/plans/station-bullet-hell)

- [x] **4b. Reinforcements.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-reinforcements](docs/plans/station-reinforcements)

- [x] **5. Destruction hands off to the planet approach.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/station-death-handoff](docs/plans/station-death-handoff)

## Code health backlog  (`code-health-backlog`, 1 open)

- [x] **Write the dossier for the completed station mini-boss epic** _(done - feature, medium, sonnet)_
      into
      `docs/epics-done/station-mini-boss/` — `PRD.md`, `SOURCES.md`, `REPORT.md` per Stage 8
      of the `feature-workflow` skill. Everything needed is already in the six
      `docs/plans/station-*/` directories: merge their `2-research.md` source tables into
      `SOURCES.md`, and cover all five sub-items plus the rejected laser-phase plan
      (`479a66d`) in `REPORT.md`. Be specific in *Known gaps* — nothing in this epic has been
      played by a human, and the report should say so.
      *Done when:* the three files exist and every claim in `REPORT.md` names a commit, a test,
      or a plan file.

- [x] **GUT silently drops a test script it cannot load, and still exits 0.** _(done - feature, medium, sonnet)_
      When
      `tests/integration/test_space_station.gd` referenced classes that did not exist yet, GUT
      printed `---- All tests passed! ----`, reported `Scripts 2` instead of 3, and **returned exit
      code 0**. The parse errors appeared only on stderr. `/agent/verify.sh` step 3 checks the exit
      code and greps for `^N failing`, so **neither signal fires** — a test file broken by a rename
      or a deleted symbol would vanish from the suite and the gate would stay green. Cheap fix:
      have step 3 also assert the script count, or grep its GUT output for `Parse Error` /
      `SCRIPT ERROR` the way steps 1 and 2 already do. This is the only reason the "watch it fail"
      step of the feature workflow worked here — the red was read off stderr, not off GUT's verdict.

- [x] **`UpgradeState.unlock()` accepts ids that are not in `ALL_IDS`.** _(done - feature, medium, sonnet)_
      A typo'd id is stored and reported `true` by `is_unlocked()`, but `unlocked_ids()` iterates
      `ALL_IDS`, so it never appears in any menu — a silent, invisible failure. Compare
      `ShipModuleState.unlock()`, which validates and `push_warning`s. Pinned by
      `tests/unit/test_upgrade_state.gd::test_unknown_ids_are_stored_but_never_listed`.

- [x] **`SessionState` recovers the temp-HP stack size with integer division.** _(done - feature, medium, sonnet)_
      `global/autoloads/session_state.gd:85` computes `_temp_hp_stack = maximum /
      TempHealth.MAX_STACKS`. When `maximum` is not a multiple of 5 the stack size rounds down and
      the pool the player gets back after a level transition is smaller than the one they earned.
      Reachable whenever a ship's `base_health / 2` is not a multiple of 5. Pinned by
      `tests/unit/test_session_state.gd::test_temp_health_stack_size_uses_integer_division`.

- [x] **`ShipModuleState.equip()` never consults `_unlocked`.** _(done - feature, medium, sonnet)_
      Any module in the catalogue can be
      equipped whether or not it was earned. Fine if unlock state is purely cosmetic for the menu;
      a progression hole if it is not. Worth a decision either way. Pinned by
      `tests/unit/test_ship_module_state.gd::test_equipping_does_not_require_unlocking`.
      -> [docs/plans/shipmodulestate-equip-never-consults-unlocked](docs/plans/shipmodulestate-equip-never-consults-unlocked)

- [x] **`MissionState.complete()` cannot record a zero-star clear.** _(done - feature, medium, sonnet)_
      `clampi(stars, 1, 3)` turns a
      0-star completion into 1 star. Intentional? Pinned by
      `tests/unit/test_mission_state.gd::test_stars_are_clamped_into_one_to_three`.

- [x] **GUT 9.7.1 needs two local patches to load under Godot 4.6.3** _(done - feature, medium, sonnet)_
      , documented in
      `addons/gut/LOCAL_PATCHES.md`. `AccessibilityServer` does not exist in this Godot build, and
      a property getter in `stub_params.gd` fails type inference. Re-apply both on any GUT upgrade
      — without them the whole addon fails to parse and the doubler is unusable.
      
      Found on 2026-09-01 while fixing the stale `ext_resource` UIDs.

- [x] **The Godot MCP `update_project_uids` tool is a no-op on this project — do not rely on it.** _(done - feature, medium, sonnet)_
      It concatenates `"res://"` onto the absolute project path it is given, so it searches
      `res:///tmp/coldclone/` (or `res:///work/repo/`), reports *"Found 0 scenes, Found 0
      scripts/shaders"*, and exits claiming success. Verified by md5summing all 151 `.tscn`/`.tres`
      before and after a run on a scratch copy: **zero files changed.** The bug is in the MCP
      server's own `godot_operations.gd`, not in this repo, so it cannot be fixed here. Use
      `tests/integration/test_resource_uid_integrity.gd` instead — it covers strictly more
      (`.tres` resources and `.gd.uid` sidecars as well as scenes).

- [x] ****`.godot/uid_cache.bin` masks broken UID references, so a warm machine disagrees with a** _(done - feature, medium, sonnet)_
      fresh clone.** Once a project has been loaded, Godot keeps a *stale* UID registered as a
      working alias for its target: `ResourceLoader.get_resource_uid()` and `ResourceUID.has_id()`
      both reported the dead `uid://bi366j2tsyby` as valid, and `--import` emitted no warning for
      the five `.tres` files using it. Deleting `.godot/` and loading one of those files directly
      produced `ext_resource, invalid UID` immediately. `.godot/` is gitignored, so **CI and new
      contributors see the failures a developer's machine hides.** Two consequences worth keeping
      in mind: `bash /agent/verify.sh` runs against a warm cache and will not catch this class of
      defect on its own, and any future UID tooling must read declarations from disk rather than
      ask the engine.

- [x] ****`godot --headless --import` only loads a fraction of the project, so "import is clean" is** _(done - feature, medium, sonnet)_
      a weak gate.** It surfaced 1 of the 3 live `invalid UID` warnings; the other 2 only appeared
      once every scene was actually loaded. A cheap "load all 126 `.tscn`/`.tres` and assert no
      load returns null" smoke test would close the gap — worth considering as step 4 of
      `/agent/verify.sh`. All 126 do currently load clean, so it would start green.

- [x] **Several resources declare hand-written UIDs in their own headers** _(done - feature, medium, sonnet)_
      — `uid://hudscore001`
      (`assault/scenes/gui/hud_score_widget.tscn`), `uid://braceasteroid01`, `uid://00246ccaem53`,
      `uid://0024uci15m53`, `uid://00243s3wxf53` (the `assault/scenes/race/` scenes). Godot 4.6.3
      parses and registers all of them, and every reference to them resolves, so **nothing is
      broken and they were deliberately left alone.** Flagging them only because they are the same
      fingerprint as the eight references that *were* broken: a UID typed by a human or an agent
      rather than minted by the editor. If one is ever duplicated onto a second resource the
      collision will be silent.
      
      Found on 2026-09-01 while building the space-station mini-boss entity (EPIC sub-item 1).

- [x] **`Gunship` never applies its config's `collision_damage`.** _(done - feature, medium, sonnet)_
      `gunship_config.tres:8` sets
      `collision_damage = 30`, but `BaseEnemy._add_contact_hitbox()` hardcodes `hb.damage = 20`
      (`base_enemy.gd:56`) and the gunship — unlike `bomber.gd:25`, `light_assault_ship.gd:23`,
      `ram_ship.gd:20-23` and `drone_interceptor.gd:148` — never re-applies it after
      `super._ready()`. So the heaviest enemy in the roster rams for 20 instead of 30 and the
      `.tres` value is dead. One loop in `gunship.gd::_ready()` fixes it; it is a balance change,
      so it should be a deliberate one rather than folded into unrelated work. `space_station.gd`
      does apply it, so the two enemies currently disagree about whether the field means anything.

- [x] ****`base_enemy.gd:56-59` builds the contact HitBox from `col.shape` but drops the** _(done - feature, medium, sonnet)_
      `CollisionShape2D`'s `scale` and `position`.** Every enemy that scales its collision shape in
      the scene therefore gets a contact hitbox of the wrong size — `gunship.tscn:63-65` scales by
      2.31, so its contact hitbox is ~2.3× too small. Harmless-ish at 40 px, badly wrong at boss
      scale. `space_station.tscn` sidesteps it by authoring its shape at true size with `scale = 1`,
      but the underlying helper is still lossy for everyone else. Copying the node's transform
      onto the new `CollisionShape2D` would fix it — though it would silently enlarge several
      existing enemies' contact hitboxes, so it needs a balance pass, not a blind fix.
      
      Found on 2026-09-01 while adding the `station_assault` section (EPIC sub-item 2).
      -> [docs/plans/baseenemy-gd-56-59-builds-the-contact-hitbox-from-col-shape-](docs/plans/baseenemy-gd-56-59-builds-the-contact-hitbox-from-col-shape-)

- [x] ****A test that ends while a `LevelDirector` coroutine is suspended leaks — and the gate stays** _(done - feature, medium, sonnet)_
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

- [x] **Should the station's core hurtbox be narrowed to 88 x 240? — a design question, not a bug.** _(done - feature, medium, sonnet)_
      `space_station.tscn:16-17` uses ONE 240 x 240 `RectangleShape2D` for both the body collider
      and the core `HurtBox`, so the core's hurtbox spans the whole hull and the four turret
      hurtboxes sit strictly inside it. This is **not** a reachability bug — see the next item —
      but it does mean shooting the hull shoulders registers as a deflected core hit rather than
      missing, and a bullet fired up a turret lane triggers a core deflection *before* it reaches
      the turret. Giving the `HurtBox` its own 88-wide shape would make the x-extents disjoint
      ([-44, 44] vs [50, 102]) and the "shoot the guns, then the core" read cleaner. It was
      planned, then dropped when its stated justification collapsed; it needs a deliberate
      design call, not a bug fix. Cost: one `sub_resource` and one node property.
      -> [docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-](docs/plans/should-the-station-s-core-hurtbox-be-narrowed-to-88-x-240-a-)

- [x] ****Two consecutive reviews asserted that a player bullet dies on its first hurtbox overlap.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/two-consecutive-reviews-asserted-that-a-player-bullet-dies-o](docs/plans/two-consecutive-reviews-asserted-that-a-player-bullet-dies-o)

- [x] **`test_space_station.gd`'s collision-layer coverage gap is still open.** _(done - feature, medium, sonnet)_
      Sub-item 1 recorded
      it as provable "once the station is in a live level (sub-item 2)". Sub-item 2 has landed and
      does **not** close it: `test_station_assault_section.gd` asserts section gating and wave data,
      never a projectile overlap. Closing it needs a test that instances
      `assault/scenes/projectiles/bullets/bullet.tscn`, positions it in a turret lane and steps
      physics — the suite has no precedent for physics-overlap tests, so budget for the technique.
      `ENEMY.md` and `tests/README.md` now say this plainly instead of promising it is coming.
      
      Found on 2026-09-01 while regenerating the turret sprites.

- [x] ****`station_core.png` has a fully opaque background — the station will render as a grey** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/stationcore-png-has-a-fully-opaque-background-the-station-wi](docs/plans/stationcore-png-has-a-fully-opaque-background-the-station-wi)

- [x] **This container has no `file`, no `python3` and no `xxd` — only `od`.** _(done - feature, medium, sonnet)_
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

- [x] ****Every enemy that does `@export var config = load(...)` shares ONE config resource** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/every-enemy-that-does-export-var-config-load-shares-one-conf](docs/plans/every-enemy-that-does-export-var-config-load-shares-one-conf)

- [x] **`spike/test_spike_laser.gd` and `spike/test_spike_selfkill.gd` are tracked dead code.** _(done - feature, medium, sonnet)_
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

- [x] **`ExplosionEffect` orphans its particles onto whatever the dying entity's parent is.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin](docs/plans/explosioneffect-orphans-its-particles-onto-whatever-the-dyin)
      2 run(s), $4.55; last on claude-sonnet-5

- [x] **The station's collision-layer coverage gap is now only half open.** _(done - feature, medium, sonnet)_
      `assault/scenes/enemies/space_station/ENEMY.md` records that
      `tests/integration/test_space_station.gd` drives damage by emitting `received_damage`
      directly and so proves nothing about collision layers.
      `tests/integration/test_station_laser_phase.gd` does now exercise a **real** physics overlap
      — a layer-128 stub `HurtBox` placed in a beam's path, found by the beam's own `Area2D` — but
      only for the *player* layer and only against a `LaserRay`. Nothing yet proves a player
      **bullet** can hit the core's layer-512 hurtbox or a turret's. Closing it still needs a test
      that instances `assault/scenes/projectiles/bullets/bullet.tscn` and steps physics.
      
      Found on 2026-09-03 while implementing station reinforcements (EPIC sub-item 4b).
      1 run(s), $0.58; last on claude-sonnet-5

- [x] **`ram_ship` cannot be hit by the player's primary weapon, and its config HP is dead code.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/ramship-cannot-be-hit-by-the-player-s-primary-weapon-and-its](docs/plans/ramship-cannot-be-hit-by-the-player-s-primary-weapon-and-its)
      1 run(s), $1.67; last on claude-sonnet-5

- [x] **The 0.75× escape-combo penalty applies to ad-hoc spawns nobody expects to kill.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/the-0-75-escape-combo-penalty-applies-to-ad-hoc-spawns-nobod](docs/plans/the-0-75-escape-combo-penalty-applies-to-ad-hoc-spawns-nobod)
      1 run(s), $2.79; last on claude-sonnet-5

- [x] **A spawn's off-screen margin cannot account for camera pan, project-wide.** _(done - feature, medium, sonnet)_
      Every spawn in the game resolves its offset against `cam.global_position`, which
      `arena_camera.gd:5-12` pins at (640, 360) and never moves — panning happens through `offset`.
      So a player panned fully down (`V_LIMIT` is 380) can in principle watch a bottom-edge spawn
      appear. 4b matched the existing convention rather than diverging for one node, and excluded
      `V_LIMIT` from its vertical margin budget on purpose. Fixing it properly means spawns
      resolving against the *visible* rect rather than the camera centre, which touches
      `wave_manager.gd:172` and every spawn offset in the game — not a 4b-sized change.
      
      Found on 2026-09-03 while building the station death sequence (EPIC sub-item 5).
      -> [docs/plans/a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr](docs/plans/a-spawn-s-off-screen-margin-cannot-account-for-camera-pan-pr)
      1 run(s), $4.65; last on claude-sonnet-5

- [x] ****`race_ship.gd:97-100` renders its death explosion at the container origin, not at the** _(done - feature, medium, sonnet)_
      ship.** It does `get_parent().add_child(boom)` then `boom.global_position = global_position`
      — but `ExplosionEffect.explode()` reads `actor.global_position` where `actor` is the effect's
      *parent*, so the position written on line 99 is silently discarded and every race-ship
      explosion appears at the container's origin. Confirmed by reading the code and by the
      independent reviewer of `docs/plans/station-death-handoff/`. **Deliberately not fixed in that
      cycle:** it is unrelated to the mini-boss and fixing it visibly moves race-mode explosions,
      which deserves its own before/after check. `explode()` now takes an optional position
      argument, so the fix is one line: `boom.explode(global_position)`. No test pins the current
      behaviour, so nothing will fight the change.
      1 run(s), $0.52; last on claude-sonnet-5

- [x] **The gate's step 1 (`godot --headless --import`) leaks ObjectDB instances.** _(done - feature, medium, sonnet)_
      It prints
      `WARNING: ObjectDB instances leaked at exit` plus a few RID-allocation errors on every run.
      Pre-existing and **not** caused by the test suite — verified by running the import against a
      stashed working tree: baseline and current both emit exactly one occurrence, while the GUT
      step emits none. Harmless today (the gate does not match on it), but it is noise that will
      mask a real leak if one ever appears in step 1, and it costs time to re-diagnose. Worth one
      cycle to find what the importer is holding.
      1 run(s), $0.87; last on claude-sonnet-5

- [x] **`ExplosionEffect`'s container resolution is a footgun worth a guard.** _(done - feature, medium, sonnet)_
      `explode()` resolves
      its target as `get_parent().get_parent()` with no check on what that is, so attaching the
      effect one level too deep silently parents the particles inside the entity instead of the
      container — they are then freed with the entity and inherit its rotation, with no error. This
      is the same shape of trap as `bullet_pool.gd:47`, which the space-station scene warns about
      twice in comments. A `push_warning` when the resolved container is itself an ancestor-owned
      node, or an explicit `container` export, would turn a silent visual bug into a loud one.
      
      Found on 2026-09-03 while fixing the shared-component signal/logging defects.
      -> [docs/plans/explosioneffect-s-container-resolution-is-a-footgun-worth-a-](docs/plans/explosioneffect-s-container-resolution-is-a-footgun-worth-a-)
      2 run(s), $1.33; last on claude-sonnet-5

- [x] ****Three more files print unconditionally on hot paths — same defect as the one just fixed,** _(done - feature, medium, sonnet)_
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
      1 run(s), $1.72; last on claude-sonnet-5

- [x] **Declaring a signal's parameters does not stop the mismatch it looks like it stops.** _(done - feature, medium, sonnet)_
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
      -> [docs/plans/declaring-a-signal-s-parameters-does-not-stop-the-mismatch-i](docs/plans/declaring-a-signal-s-parameters-does-not-stop-the-mismatch-i)
      1 run(s), $3.01; last on claude-sonnet-5

- [x] **The reflect -> AbilityState migration was abandoned half-done.** _(done - feature, medium, sonnet)_
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
      1 run(s), $0.93; last on claude-sonnet-5

- [x] **`long_range.tres` is an orphaned weapon mode with no id in ALL_IDS.** _(done - feature, medium, sonnet)_
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
      1 run(s), $1.19; last on claude-sonnet-5

- [x] **Two committed `.tscn*.tmp` files duplicate light_assault_ship's UID and dodge every integrity check** _(done - feature, small, sonnet)_
      `assault/scenes/enemies/light_assault_ship/` has two Godot editor scratch files tracked in git —
      `light_assault_ship.tscn777863979.tmp` and `light_assault_ship.tscn785603970.tmp` (both added in
      `613ad48`). They are stale copies of `light_assault_ship.tscn`, and each one declares
      `uid="uid://br4qs4w455h3m"` — the **same UID the live scene declares**. Three files, one UID.
      
      They also point an `ext_resource` at
      `res://assault/scenes/enemies/light_assault_ship/enemyship.png`, which does not exist anywhere in
      the repo, and they predate the state machine: neither has the `StateMachine` / `ApproachState` /
      `StrafeExitState` scripts the real scene carries, so anything that loaded one would get a
      light assault ship with no AI.
      
      Nothing in the gate can see any of this. `test_resource_uid_integrity.gd` walks `.tscn`, `.tres`
      and `.gd.uid`, so its "no two files declare the same UID" and "every UID resolves" checks skip
      `.tmp` entirely; `test_project_load_integrity.gd` walks the same three extensions, so the dangling
      `enemyship.png` reference is never loaded either. The duplicate-UID hazard is exactly the failure
      mode that test was written to catch, arriving through a file extension it does not look at.
      
      Two parts, and the second is the one that matters:
      
      1. Delete both `.tmp` files and add a `*.tscn*.tmp` / editor-scratch pattern to `.gitignore` so
         the next editor crash does not re-commit them.
      2. Decide whether `test_resource_uid_integrity.gd` should widen its walk — e.g. flag ANY tracked
         file that declares a `uid://` in a `gd_scene` / `gd_resource` header regardless of extension,
         or simply fail on tracked editor-scratch files by name. Widening the walk is the version that
         catches the next variant rather than this instance.
      1 run(s), $0.67; last on claude-sonnet-5

- [x] **Code-built contact hitboxes are typed as LASER damage, not CONTACT** _(done - feature, medium, sonnet)_
      Every code-built contact `HitBox` leaves `damage_type` at the `HitBox.DamageType.LASER` default.
      `HitBox.matching_shape()` (`global/components/hitbox_component.gd`) does not set it, and none of
      the four callers (`base_enemy.gd:49-53`, `drone_interceptor.gd:141-148`,
      `kamikaze_drone.gd:53-60`, `ally_fighter.gd:72-77`) set it afterwards. So every ram in the game
      is typed as laser damage.
      
      `asteroid_base.gd:42` is the only place that sets `CONTACT`, and it does so on a hitbox authored
      in the scene rather than built in code.
      
      Harmless today: the player's `HurtBox` has an empty `accepted_damage_types`, so the filter in
      `hurtbox_component.gd:12-18` accepts everything. It becomes a live bug the moment anything wants
      to resist or react to contact damage specifically — a laser-immune enemy would also become
      ram-immune, with no visible cause.
      
      Fix is probably a `damage_type` parameter on `matching_shape()` defaulting to `CONTACT`, plus a
      row in `tests/integration/test_contact_hitbox_geometry.gd`. Needs a check that nothing currently
      filters on LASER first.
      
      Found on 2026-09-06 while fixing the contact-hitbox transform bug (recorded as an explicit
      out-of-scope follow-up in that task's approved plan).
      -> [docs/plans/code-built-contact-hitboxes-are-typed-as-laser-damage-not-co](docs/plans/code-built-contact-hitboxes-are-typed-as-laser-damage-not-co)
      1 run(s), $1.33; last on claude-sonnet-5

- [x] **Move code-built contact hitboxes into the scenes, as the asteroids already do** _(done - feature, medium, sonnet)_
      Four scripts build a contact `HitBox` at runtime (`base_enemy.gd:49-53`,
      `drone_interceptor.gd:141-148`, `kamikaze_drone.gd:53-60`, `ally_fighter.gd:72-77`), all now via
      `HitBox.matching_shape()`. The asteroid family already does it the other way:
      `big_asteroid.tscn`/`small_asteroid.tscn` author a `ContactHitBox` node in the scene and
      `asteroid_base.gd:41-42` only sets `damage`/`damage_type` on it.
      
      The scene-authored version is the cleaner end state — the hull geometry lives next to the body
      shape where an author can see both, instead of being reconstructed in code from it — and it is
      the pattern already proven in this repo. It is also what removes the whole class of bug the
      transform fix just closed.
      
      Not free: nine scene edits with UID risk, and the per-subclass layer/mask logic that
      `drone_interceptor.gd:147` and `kamikaze_drone.gd:59` depend on (mask 128 rather than 0) has to
      move into the scenes too. `tests/integration/test_contact_hitbox_geometry.gd` covers the result
      either way, so the migration is verifiable.
      
      Found on 2026-09-06; recorded as an explicit out-of-scope follow-up (rejected alternative 3) in
      the approved plan for the contact-hitbox transform fix.
      -> [docs/plans/move-code-built-contact-hitboxes-into-the-scenes-as-the-aste](docs/plans/move-code-built-contact-hitboxes-into-the-scenes-as-the-aste)
      2 run(s), $7.34; last on claude-sonnet-5

- [x] **Wire the leak grep into /agent/verify.sh — the agent cannot, /agent is read-only** _(done - feature, medium, opus)_
      `/agent` is mounted **read-only** inside the dev container (`/dev/bcache0 on /agent type btrfs
      (ro,...)`), so the agent cannot add leak patterns to the gate itself — verified by an append,
      which failed with "Read-only file system".
      
      Everything else is in place. `scripts/check-test-leaks.sh` (new this cycle) runs gate step 3 with
      the *exact* same arguments and additionally greps the output for
      `ObjectDB instances leaked|resources still in use|Resource still in use`, exiting 1 on a hit. It
      was verified both ways: green on the current 305-test suite, and red (exit 1) with a deliberate
      stranding test dropped in.
      
      The gate change is one line in step 3 of `/agent/verify.sh`, after the existing `failing` grep:
      
      ```bash
      LEAK='ObjectDB instances leaked|resources still in use|Resource still in use'
      grep -Eq "$LEAK" "$LOG" && fail "the GUT run leaked objects at exit"
      ```
      
      ⚠️ Apply it to **step 3 only**. Step 1, the headless `--import`, emits one benign
      `ObjectDB instances leaked` of its own that predates the test suite — adding the pattern to the
      shared `FATAL` regex would fail the gate on every run forever.
      1 run(s), $0.35; last on claude-sonnet-5

- [x] **Freeing LevelDirector mid-wait still strands its GDScriptFunctionState** _(done - feature, medium, sonnet)_
      Follow-up to the SceneTreeTimer fix. `_wait_for_child_exit_or_timeout()` and `_wait_seconds()` no
      longer create timers, so an *early return* leaves nothing behind — but a test (or a scene change)
      that frees the director while `_wait_enemies_cleared()` is suspended still strands the coroutine
      itself. Measured with `--verbose` after the fix:
      
      ```
      Leaked instance: GDScriptNativeClass / GDScript / GDScriptFunctionState
      Resource still in use: res://assault/scenes/systems/level_director/level_director.gd (GDScript)
      ```
      
      Three objects per abandonment. It is inherent to Godot: once the object is freed the function
      state can never be resumed, so nothing inside the loop's `if not is_instance_valid(self): return`
      guard can help — that guard only runs if the coroutine gets one more frame first.
      
      A real fix means giving the director a cancel seam: suspend on a director-owned signal
      (`await _wait_tick`) fed from `get_tree().process_frame`, and have `_exit_tree()` set a
      `_cancelled` flag and emit `_wait_tick` once, which resumes every suspended wait *synchronously*
      while the object is still alive so each can return and release its state. That is a change to live
      gameplay code with re-entry cases to get right (`_enter_tree` must reset the flag and reconnect),
      so it wants its own plan and review rather than being folded into the timer fix.
      
      Cost of not doing it: three leaked objects per level teardown, plus every test that ends mid-wait
      needs the documented drain (`test_station_assault_section.gd` test 5). Bounded and small — this is
      tidiness, not a bug the player can feel.
      -> [docs/plans/freeing-leveldirector-mid-wait-still-strands-its-gdscriptfun](docs/plans/freeing-leveldirector-mid-wait-still-strands-its-gdscriptfun)
      2 run(s), $2.93; last on claude-sonnet-5

- [x] **Decide whether the player's default gun should stop on its first damaging hit (PierceModule is currently a downgrade)** _(done - feature, medium, sonnet)_
      **Split out of `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`, which fixed the
      projectile *leak* and deliberately left this balance question alone.**
      
      `PierceModule` ("Penetrating Rounds": `MAX_PIERCE = 3`, `PIERCE_DAMAGE_FACTOR = 0.55`) is
      **strictly a downgrade today**, because the base gun already pierces without limit. A default
      bullet is not consumed by a hurtbox it overlaps — `bullet.gd`'s ordinary-hit path emits `expired`
      and keeps flying — so against stacked hurtboxes the unmodded gun hits every one of them for full
      damage. Equipping the module only *shrinks* hits 2-4 from 50 to 28/15/8 (verified on Godot 4.6.3:
      `50 -> 28 -> 15 -> 8 -> 4`), and once `pierces_remaining` reaches 0 the bullet flies on at 8
      anyway. Genre convention is the reverse: piercing is what an upgrade buys, not a baseline.
      
      Pinned as characterization by
      `tests/integration/test_player_bullet_lifetime.gd::test_pierce_module_today_only_reduces_damage`,
      so any change to pierce behaviour fails that test — which is the signal the change was deliberate.
      
      **THE COUPLING, carried over verbatim so it is never orphaned.** Fixing this means deciding that
      the default gun stops on its first damaging hit, and that decision cannot be made in isolation:
      the space-station mini-boss depends on pass-through. Its armoured core spans the whole hull and
      sits between the player and the turrets, deflecting for 0. If the gun starts stopping on first
      contact **without** the station also changing, every shot aimed at a turret is absorbed by the
      core one to two physics frames early, deflects for 0 and dies — **the turrets become unkillable
      and so does the boss.** That is asserted, at two levels:
        - `tests/integration/test_space_station.gd` — two real-physics tests firing a real `bullet.tscn`
          up a turret lane through the core.
        - `tests/integration/test_player_bullet_lifetime.gd::test_a_bullet_is_not_consumed_by_a_hurtbox_it_overlaps`
          — the same premise at the bullet level.
      Background: `assault/scenes/enemies/space_station/ENEMY.md` -> "Core hurtbox: why it spans the
      whole hull".
      
      So this is a coupled, whole-game balance change (player weapon feel + the first boss fight), not a
      one-line fix. Any plan for it has to say what the station does instead — e.g. a damage rule that
      lets shots pass the core while any turret lives, rather than the current deflect-and-continue.
      
      **Not in scope here:** the leak itself, which is fixed —
      `WeaponBehavior._launch()` now calls `Bullet.free_when_offscreen()` at all four spawn sites.
      -> [docs/plans/decide-whether-the-player-s-default-gun-should-stop-on-its-f](docs/plans/decide-whether-the-player-s-default-gun-should-stop-on-its-f)
      1 run(s), $4.51; last on claude-sonnet-5

- [x] **Five weapon-mode .tres files still set homing_* keys that WeaponModeResource no longer declares** _(done - feature, small, sonnet)_
      Found while working `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`.
      
      All five bullet-firing weapon modes — `default.tres`, `gatling.tres`, `long_range.tres`,
      `spread.tres`, `sniper_shot.tres` in `assault/scenes/player/weapons/modes/` — end with:
      
      ```
      homing_turn_rate_deg_per_sec = 90.0
      homing_lifetime_sec = 1.6
      ```
      
      `assault/scenes/player/weapons/weapon_mode.gd` declares neither property. They are leftovers from
      the `primary_homing/` projectile directory, which no longer exists (`ls
      assault/scenes/projectiles/` → `bullets enemy_bullet enemy_bullets missiles piercing_beam`); the
      docs reference to it was removed in that same task.
      
      Godot silently ignores unknown keys when loading a `.tres`, so nothing is broken today — but they
      read as live tuning knobs to anyone opening the file, and someone will eventually "fix" a homing
      bug by editing a number that does nothing. Delete the two lines from each of the five files.
      
      Small; verify with `bash /agent/verify.sh` (`test_project_load_integrity.gd` already loads every
      `.tres` and asserts the engine logs nothing).
      1 run(s), $0.30; last on claude-sonnet-5

- [x] **assault/scenes/player/states/shooting_state.gd is dead code referenced by no scene** _(done - feature, small, sonnet)_
      Found while working `two-consecutive-reviews-asserted-that-a-player-bullet-dies-o`, which had to
      decide whether it counted as a spawn site.
      
      `assault/scenes/player/states/shooting_state.gd` instantiates `bullets/bullet.tscn` directly
      (around line 42) and is a legacy shooter — the real player scenes mount only
      `warhead_missile_shooting_state.gd`. A repo-wide grep found it referenced by **no** `.tscn`:
      `player_fighter.tscn` and `open_space/.../player_ship.tscn` both list the warhead state and not
      this one.
      
      Two reasons it is worth removing rather than leaving:
      - It is the one remaining place that spawns a player bullet **outside** `WeaponBehavior._launch()`,
        so it does not get `Bullet.free_when_offscreen()` and would leak if ever wired up. That is the
        known, accepted residual gap in the lifetime fix; deleting the file closes it outright.
      - `tests/integration/test_project_load_integrity.gd` compiles it on every gate run, so it costs
        maintenance without earning anything.
      
      Confirm nothing references it (including by UID) before deleting, and check whether it has a
      sibling `.gd.uid`.
      1 run(s), $0.44; last on claude-sonnet-5

- [x] **Rockets cannot damage the space station's turrets — they detonate on the armoured core** _(done - feature, medium, sonnet)_
      `homing_missile.gd:47-48` and `warhead_missile.gd:22-23` both `queue_free()` on ANY
      `area_entered`, so a rocket is consumed by the first hurtbox it overlaps. A player bullet is
      not (`tests/integration/test_player_bullet_lifetime.gd`), and the space station's whole armour
      design rests on that difference.
      
      On this boss it means: the core's HurtBox spans the full 240x240 hull and the four turrets sit
      *inside* it at (+-76, +-76), so a rocket fired up a turret lane reaches the core rect (y = +120)
      about two frames before the turret rim (y = +102), deflects for 0 and dies there. The player's
      homing and warhead missiles therefore cannot destroy a single station turret — and since the core
      is armoured until all four are dead, rockets contribute nothing to the fight until it is already
      won with another weapon. A player who has invested in missiles reads that as "my rockets are
      broken", which is exactly the failure mode `ENEMY.md` -> "Core hurtbox" argues against for the
      88x240 proposal.
      
      Pinned today, not fixed:
      `tests/integration/test_station_incoming_damage_paths.gd`
      -> `test_a_rocket_up_a_turret_lane_dies_on_the_armored_core_and_never_reaches_the_turret`,
      marked CHARACTERIZED. That test should go red when this is addressed.
      
      Options worth weighing before touching it (this is a fight-design decision, not a one-line fix):
      - have the rocket ignore a hurtbox that refused the damage (needs a "was this absorbed" answer
        back from HurtBox, which does not exist today);
      - give the station a separate armour-plate HurtBox over the core only, the Gradius idiom already
        deferred in `ENEMY.md`;
      - accept it as intended weapon-vs-boss counterplay and say so in `ENEMY.md`, so the next reader
        does not file this again.
      
      Found on 2026-09-07 while closing the collision-layer coverage gap.
      -> [docs/plans/rockets-cannot-damage-the-space-station-s-turrets-they-deton](docs/plans/rockets-cannot-damage-the-space-station-s-turrets-they-deton)
      1 run(s), $2.43; last on claude-sonnet-5

- [x] **There are five tracked .tscn*.tmp files, not two — the existing task under-scopes it** _(done - feature, medium, sonnet)_
      While verifying the sprite-transparency sweep I found the tmp-file count in that task is wrong: `git ls-files | grep "\.tmp$"` returns **five** tracked editor-scratch files, not two.
      
          assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn777863979.tmp
          assault/scenes/enemies/light_assault_ship/light_assault_ship.tscn785603970.tmp
          assault/scenes/player/player_fighter.tscn6026545143.tmp
          infiltration/scenes/entities/player/player.tscn1097983848.tmp
          infiltration/scenes/entities/player/player.tscn1101780008.tmp
      
      The existing task `two-committed-tscn-tmp-files-duplicate-lightassaultship-s-ui` describes only the
      two under `light_assault_ship/` and its duplicate-UID analysis covers only those. The other three
      are the same class of file and dodge the same integrity checks (`test_resource_uid_integrity.gd`
      and `test_project_load_integrity.gd` both walk `.tscn`/`.tres`/`.gd` only, so no `.tmp` is ever
      read), and nobody has checked whether the player_fighter and infiltration ones also duplicate a
      live UID.
      
      Fold this into that task rather than doing it separately - the fix is the same one it already
      proposes (delete + `.gitignore` + widen the UID walk to any file declaring a `uid://` in a
      `gd_scene`/`gd_resource` header regardless of extension). Recording it so the scope is right when
      someone picks it up.
      
      Found 2026-09-07 while fixing the station core sprite background.
      1 run(s), $0.27; last on claude-sonnet-5

- [x] **`ScoreTracker.score_config` is still a shared process-wide resource** _(done - feature, medium, sonnet)_
      `score_tracker.gd:26` declares `@export var score_config: ScoreConfig = preload("res://global/resources/score_config_default.tres")`
      and `:52` re-`preload()`s the same path as a fallback. This is the same
      `ResourceLoader`-caches-by-path sharing that
      `tests/integration/test_config_instance_isolation.gd` now closes for the ten entity configs —
      but `ScoreConfig` extends `Resource`, not `ShipConfig`, so `ShipConfig.privatise()` does not
      reach it and the new invariant test does not sweep it.
      
      Left out of that change deliberately, and it is genuinely lower risk: there is exactly one
      `ScoreTracker` per level, so there is no cross-*instance* contamination to cause. What remains is
      the test hazard — a test that tunes scoring through `tracker.score_config` writes to the object
      every other test's `preload()` of `score_config_default.tres` also holds, and the corruption
      surfaces later, in a different file, as a wrong expected score.
      
      Cheapest fix is probably to widen `privatise()` to take any `Resource`-typed property name (or to
      move it off `ShipConfig` onto a small util) and call it from `ScoreTracker._ready()`, plus one
      assertion in the existing isolation test. Worth checking `skill_challenge_resource.gd` and the
      movement/formation/wave/level resources at the same time — `station_gunnery.gd:79` says attack
      patterns must stay pure configuration, so those are deliberately shared and should be excluded
      rather than copied.
      -> [docs/plans/scoretracker-scoreconfig-is-still-a-shared-process-wide-reso](docs/plans/scoretracker-scoreconfig-is-still-a-shared-process-wide-reso)
      1 run(s), $1.63; last on claude-sonnet-5

- [x] **No pickup or menu ever calls UpgradeState.unlock() for any weapon mode** _(done - feature, medium, opus)_
      While fixing the orphaned `long_range.tres` (ALL_IDS entry), a grep for `UpgradeState.unlock(`
      across the whole project (excluding `tests/`) found exactly one call site: `unlock_all()` inside
      `global/autoloads/upgrade_state.gd` itself, which nothing in game code ever invokes.
      
      `UpgradeState._ready()` seeds only `&"default"` on a fresh profile
      (`global/autoloads/upgrade_state.gd:26-28`). `sniper_shot`, `spread`, `gatling` and `mining_laser`
      are all listed in `ALL_IDS` and all have a `.tres` in `weapons/modes/` and (except `sniper_shot`)
      an icon in `player_menu.gd`'s `_WEAPON_ICONS` - the plumbing for a real unlock system is there -
      but nothing in `global/pickups/` or anywhere else ever calls `UpgradeState.unlock(&"gatling")` etc.
      Contrast with `ShipModuleState`, which has `ShipModuleUnlockerPickup` instances placed in the
      sector hub and an invariant test (`tests/integration/test_module_unlock_sources.gd`) guaranteeing
      every module has one.
      
      Net effect: in an actual playthrough the player is permanently stuck on the default weapon mode.
      Either every other weapon mode is unreachable dead content, or there is an unlock path I did not
      find and it needs a pointer added somewhere discoverable (a comment in upgrade_state.gd would have
      saved this grep). Worth an epic-sized look rather than a quick fix: it likely needs pickup scenes
      placed in the world (mirroring `ShipModuleUnlockerPickup`) plus the same kind of coverage test
      `test_module_unlock_sources.gd` already provides for ship modules.
      -> [docs/plans/no-pickup-or-menu-ever-calls-upgradestate-unlock-for-any-wea](docs/plans/no-pickup-or-menu-ever-calls-upgradestate-unlock-for-any-wea)
      2 run(s), $14.88; last on claude-opus-5

- [ ] **The open-space ship never reads the permanent shield upgrade** _(todo - bug, small, sonnet)_
      `open_space/scenes/entities/player/player_ship.tscn:223-224` authors its `ShieldComponent` with
      no `bind_progression` line, so it falls back to `global/components/shield_component.gd:20`'s
      default of `false` and the open-space ship starts with the component's own charge count instead of
      `ShipProgressionState.permanent_shield_count`.
      
      `assault/scenes/player/player_fighter.tscn:301` is the only scene that sets it. So the hub's
      `ShipShieldUpPickup` raises a saved number that the ship the player flies in the hub never reads —
      the upgrade is visible in the menu and inert in open space.
      
      Found while reviewing the open-space boost plan (finding A8 of
      `docs/plans/open-space-boost-shift-burst-movement-on-an-upgradeable-boos/4-review.md`); confirmed
      against the scene and the component. Not that epic's to fix.
      
      Done looks like: `bind_progression = true` on the `ShieldComponent` node in `player_ship.tscn`,
      plus a test that fails on today's build — instantiate `player_ship.tscn`, set the live
      `ShipProgressionState` permanent shield count (snapshot and restore it, `SaveSandbox` only covers
      the file), and assert the ship's shield charges follow it. Check whether any other scene in the
      project has the same omission while you are there.

## Ideas turned into epics

- The first boss looks great, but I want to make the fight much harder and more dynamic.  -> `boss-fight-escalation-shared-hull-flying-laser-projectors-de`
- Let's fill the world with more collectibles, such as log records, that players can discover in open-space, assault, and land missions.  -> `log-records-discoverable-lore-and-info-logs-across-all-three`
- Rework Open-Space Movement & Mouse Aiming:  -> `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
- Add Boost/Burst Movement to Open Space  -> `open-space-boost-shift-burst-movement-on-an-upgradeable-boos`

