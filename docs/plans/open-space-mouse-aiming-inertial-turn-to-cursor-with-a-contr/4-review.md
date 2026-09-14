# Plan review — Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting

VERDICT: CHANGES_REQUESTED

Epic: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
Stage: **PLAN REVIEW**, written 2026-09-14 against `agent/auto-dev` @ `e60ebd6`.
Reviewed: [`1-context.md`](./1-context.md), [`2-research.md`](./2-research.md),
[`3-plan.md`](./3-plan.md) and the six implementation tasks on the board, against the actual
files, against Godot 4.6.3 run headlessly in this container, and against two of the three
cited sources refetched.

The design is sound and the decomposition is good. Five things must be fixed before an
unattended session starts; two of them (B1, B2) would red the gate inside the session that hits
them, and one (B3) would quietly change assault behaviour, which the idea forbids.

---

## What was verified as correct

Every structural claim below was checked against the file, not taken from the plan.

- `open_space/scenes/entities/player/player_ship.gd:107-113` is `_handle_rotation`, exactly as
  quoted; `rotation_speed_deg = 220.0` at line 8; `_input()` exists at line 97; `_LEAD_MAX = 140.0`
  at line 34 and is applied in `_update_camera_feel` (line 226). `rotation_speed_deg` is **not**
  overridden anywhere in `player_ship.tscn` or any other file, so moving it onto the controller is
  safe (grep over the whole tree: only `player_ship.gd:8` and `:113`).
- `global/ship_modules/ai_targeting_module.gd:38` is `actor.rotation = dir.angle() + PI * 0.5`.
  A sweep of all 17 `global/ship_modules/*.gd` files finds **no other** module writing rotation,
  and a project-wide grep for `rotation =` / `+=` / `-=` / `look_at` / `set_rotation` /
  `global_rotation` / `rotate(` over `global/` + `open_space/` returns only that line,
  `player_ship.gd:113`, `player_ship.gd:46` (`rotation = 0.0` in `_ready()`) and
  `forward_attack_pattern.gd:16` (a bullet, not the ship). No tween targets `"rotation"` anywhere.
- Weapons already fire from facing: `straight_behavior.gd:10,16`, `spread_behavior.gd:12,15`,
  `sniper_behavior.gd:80,81`, `beam_behavior.gd:53` and
  `assault/scenes/player/states/warhead_missile_shooting_state.gd:56,57,71,72` all read
  `actor.rotation`. The "weapons follow facing, not the cursor" clause of the idea is satisfied
  with no weapon file touched. (Naming nit: the plan calls it `RocketState._launch_warhead()`;
  the class is `WarheadMissileShootingState` and it lives under `assault/scenes/player/states/`.)
- `player_ship.tscn` is instantiated by exactly one scene, `open_space/scenes/levels/sector_hub.tscn`
  (grep on both the path and `uid://qf4mu6gg75ca`). Mode isolation for the *turn model* is
  structural, as claimed.
- No mouse code exists outside `addons/gut/`: zero `get_global_mouse_position`, zero
  `InputEventMouseMotion`, zero `MOUSE_MODE`. `project.godot:45` is `stretch/mode="canvas_items"`,
  so the `get_global_mouse_position()` justification holds.
- `pause_menu.gd:52-58` hard-codes `Option0..Option4`; `_confirm()` (line 134) matches on the
  index with `4: get_tree().quit()`; `_navigate()` (line 184) skips hidden options;
  `_options[1]/[2].visible = mission_mode`. Both `pause_menu.tscn` and
  `open_space_pause_menu.tscn` carry their own `Option0..Option4` nodes. `LoreLogList` really has
  `open()` (line 37), `close()` (45), `navigate()` (51) — plus `page()` (59), which the routing
  branch also uses.
- `MissionTrigger._open_menu()` really calls `player.set_process_input(false)` (and
  `set_physics_process(false)`), restoring both in `_close_menu()`. For `PauseMenu`/`PlayerMenu`
  the tree pause covers it: the ship's `process_mode` is the default INHERIT and Godot gates
  `_input` on `can_process()`. The snap-suppression design's premise holds.
- The `ConfigFile` idiom in `global/autoloads/ship_module_state.gd` (`SAVE_PATH`/`SECTION` consts,
  `_ready() -> _load()`, validate on write *and* read with `push_warning`, `_save()` per mutation,
  change signal) is exactly what the plan copies, and
  `tests/unit/test_ship_module_state.gd:219` (`test_load_does_not_grandfather_an_unknown_equipped_id`)
  exists and is the right precedent for "corrupt value falls back, `push_warning` not asserted on".
  `tests/helpers/save_sandbox.gd::PATHS` (lines 16-24) is a hard-coded list, so the
  `"user://settings.cfg"` entry is genuinely required.
- `engine_boost_module.gd`: `_COOLDOWN = 2.0` (line 10), `_boost_dir = Vector2.UP.rotated(actor.rotation)`
  latched at activation (line 56). `player_ship.gd:17` `boost_speed_threshold = 180.0`. All three
  numbers the balance argument rests on are right. `_handle_rotation` does keep running during a
  boost — only `_handle_thrust` early-returns (line 118).
- Engine semantics, run headlessly on Godot **4.6.3.stable** in this container:
  `Vector2.ZERO.angle() == 0.0`; `angle_difference(0.0, PI) == -3.14159…` (so the 180° tie-break
  really is negative); `angle_difference(3.0, -3.0) == 0.28318…`; `rotate_toward(0.0, PI, 0.1) == -0.1`.
  The wrap case's claimed "total travel ~0.283 rad" is exact — 600 steps of the plan's own five-line
  model from `3.0` toward `-3.0` converge on `3.28318…`, i.e. 0.28318 rad of travel. (Note for the
  test author: `rotate_toward` does **not** wrap its result into `[-PI, PI]`, so the final rotation
  is `3.2832`, not `-3.0`.) `NOTIFICATION_APPLICATION_FOCUS_OUT`/`_IN` do propagate from the
  `SceneTree` to ordinary nodes' `_notification` — verified with a probe node.
- Sources: the MouseFlight README says verbatim "If you want to fly towards something, you simply
  put the mouse cursor over it" and "The mouse is not an ideal method of controlling an aircraft",
  and does expose `MouseAimPos`/`BoresightPos`. The Jet Lancer thread contains "way more accurate,
  but don't seem to be as fast as they should be", the adjustable-banking request, and WhyNot's
  reply. Both findings are supported.
- Decomposition: the plan's **6** build steps map **1:1** onto **6** implementation tasks on the
  board (the brief's "5 implementation tasks" is off by one — there are six). No build step is
  unclaimed, no task is really three, and each is a single session's work. The `dependsOn` chain
  (`your-ship-leans` ← `the-game-remembers` ← `choose-mouse-aim`; `your-ship-leans` ←
  `ai-targeting` ← `a-future-ship-module`; `your-ship-leans` ← `alt-tabbing`) matches the build
  sequence's real dependencies, including the plan's "step 6 needs 1 and 2" (transitive through
  step 2). Impl tasks not depending on prep tasks is this board's convention — every other epic in
  `BACKLOG.json` does the same. Nothing collides: tasks 3, 4, 5 touch disjoint files.
- Conventions: composition over inheritance (a `Node` child, like `MovementController`) ✓;
  `.tres`-config and 640×360 design-space rules correctly identified as not applying ✓; UID
  minting rule stated ✓; signal arity declared ✓; no projectile-ownership impact ✓. Nothing here
  reinvents an existing `global/components/` component — there is no turn/steering component today.
- Against the idea, clause by clause: mouse rotation ✓; A/D kept as a selectable legacy scheme at
  today's 220 °/s ✓; lag rather than snap ✓ (clamped exponential chase); slower on purpose ✓
  (150 vs 220, and the cap is a hard guarantee, not an emergent one); weapons and abilities follow
  the hull ✓ (nothing reads the cursor but `rotation`); open-space only ✓; setting with mouse as
  default ✓; Jet Lancer inertia ✓ with the true-inertia alternative examined and rejected for a
  stated reason (two coupled parameters, untunable headlessly). The research has real tradeoffs in
  every row.

---

## Blocking findings

### B1. The plan's "no existing test changes" is false — `test_pause_menu_lore_logs.gd` pins Exit Game at index 4

`tests/integration/test_pause_menu_lore_logs.gd:82-83`:

```gdscript
func test_exit_game_is_now_at_index_4() -> void:
	assert_eq(_menu._options[4].get_node("Label").text, "Exit Game")
```

The plan states, twice and emphatically, that this file "references only indices 1, 2 and 3
(**verified by grep**)" (`3-plan.md` → "a Settings sub-overlay…", and again under "Changes to
existing tests: None expected"), and uses that as the justification for inserting Settings at
index 4 rather than after Exit Game. The grep was wrong. Moving Exit Game to `Option5` reds this
assertion, and the test's *name* encodes the old index too.

Task `choose-mouse-aim-or-classic-a-d-steering-from-the-pause-menu` hedges ("confirm that before
assuming it") but its DONE WHEN does not include the edit, so a sonnet session will follow the
plan's stated fact and hit a red gate.

**Required:** correct both statements in `3-plan.md`, and add to that task: rename
`test_exit_game_is_now_at_index_4` → `…index_5` and update the index. Placing Settings at index 4
is still the right call (Exit Game stays last); it just is not free.

### B2. Step 3's prescribed code cannot pass step 4's invariant test

The duck-typed replacement the plan writes for `ai_targeting_module.gd` keeps the old write in the
fallback branch:

```gdscript
if actor.has_method("face_instant"):
	actor.face_instant(angle)
else:
	actor.rotation = angle          # <- still an `actor.rotation` assignment
```

and the very next build step specifies
`tests/integration/test_ship_rotation_single_writer.gd` as "sweep every `global/ship_modules/*.gd`;
assert **no file assigns to `actor.rotation`** (`=`, `+=`, `-=`). **The allowlist is empty.**"
(`3-plan.md`, "Decision: exactly one writer…", repeated in the task body of
`a-future-ship-module-cannot-silently-fight-your-steering`).

A text sweep with an empty allowlist fails on the file step 3 produces. The two steps as written
are mutually exclusive: whichever lands second forces an undocumented change to the other. Because
task 4 `dependsOn` task 3, the session that hits this is task 4, and its DONE WHEN ("the test
passes on the fixed tree") is unreachable without re-opening a decision the plan thought it had
made.

**Required:** pick one and write it down — either delete the `else` branch (but see **B3**), or
state the sweep as "no *unconditional* write; the single documented fallback line is allowlisted by
exact text", and say which in both the plan and the task body.

### B3. The `else` fallback has a live consumer, and it is the assault player — so deleting it changes assault

`1-context.md` justifies the whole mode-isolation argument with "the assault player has no rotation
at all (`player_fighter.gd` … grep for `rotation` returns **nothing**)". That is true of
`player_fighter.gd` itself and false of the system: `assault/scenes/player/player_fighter.gd:29-35`
applies every equipped `ShipModuleState` module to the assault fighter, `:92-93` ticks them, and
`:108-118` calls `try_activate(self)` on `use_ability` — the same `AITargetingModule`, on a
`CharacterBody2D`. **Today, activating AI Targeting in an assault mission writes the assault
fighter's `rotation`.**

So the `else: actor.rotation = angle` branch is not dead defensive code, it is the assault path.
Resolving B2 by deleting it silently removes an existing (if odd) assault behaviour — directly
against the idea's "must not affect assault/land missions" — and no test covers it
(`grep -rl ai_targeting tests/` finds only `test_ship_module_state.gd`, which never activates it).

**Required:** decide this explicitly. The cheapest resolution that satisfies B2 and B3 together is
to give `AssaultPlayer` its own one-line `face_instant(angle)` (set `rotation`; there is no
controller to suppress), so the duck-typed call is total, the `else` branch can be deleted, the
empty allowlist stands, and assault behaviour is byte-for-byte what it is today. Then
`test_ship_rotation_single_writer.gd` should assert the method exists on **both** player classes,
not only `OpenSpacePlayerShip`. Whatever is chosen, `1-context.md`'s "the assault player has no
rotation to corrupt" needs correcting so the next reader does not repeat the mistake.

### B4. Nothing tests the wiring — the whole feature can ship inert with every named test green

The test plan covers the controller in isolation (`test_ship_turn_controller.gd`), the store in
isolation (`test_settings_state.gd`), a text sweep, and the pause menu. It contains **no test that
the ship is actually wired to either**. Concretely, all of these pass every named case while the
game is unchanged:

- `ShipTurnController` is never added as a child in `player_ship.tscn` (or is added under the wrong
  parent), and `_handle_rotation` keeps its old body;
- `player_ship.gd::_ready()` never seeds `_turn.scheme` from `SettingsState`, so the pause-menu
  setting is cosmetic — the exact failure `test_weapon_unlock_sources.gd` exists to remember, and
  which the plan itself cites ("a settings row whose handler is empty passes every 'is it visible
  and labelled' test") for the menu but not for the ship;
- `open_space_scheme_changed` is never connected, so flipping the scheme does nothing until the
  scene reloads;
- `ai_targeting_module.gd` guards on a *misspelled* method name, silently taking the fallback.

`test_project_load_integrity.gd` proves the scene still loads, nothing more.

**Required:** add wiring assertions, sized to the headless constraint (which is real — the cursor
cannot be placed, so do not try). An integration test that instantiates `player_ship.tscn` can
assert: a `ShipTurnController` child exists; after `_ready()` its `scheme` equals
`SettingsState.get_open_space_scheme()`; emitting `open_space_scheme_changed(&"keys")` re-seeds it;
and with `scheme = &"keys"` plus `Input.action_press("move_right")`, a hand-called
`_handle_rotation(1.0)` advances rotation by `deg_to_rad(220.0)` — which fails on an unrewired
`_handle_rotation` only if the controller's rate is left at a different value, so prefer asserting
delegation directly (e.g. the controller node is the object whose `step()` result lands in
`rotation`). For the AI-targeting task, one case with a stub actor exposing `face_instant` asserting
the module calls it (and does **not** write `rotation`) closes the duck-typing hole. Sandbox it —
it touches `SettingsState`.

### B5. The mandatory docs step is attached to only one of the six tasks

`CLAUDE.md` → "MANDATORY — keep the docs current" applies to "adding … an entity, component,
module, or mechanic". Task 1 adds a new node class to `player_ship.tscn`, which
`docs/architecture/modules/open_space.md:19-20` and `:78` enumerate by name; task 2 adds the
project's eleventh autoload, and `docs/architecture/modules/global.md:68-79` carries a per-autoload
table introduced by the sentence "**All ten** are registered in `project.godot`". Only
`choose-mouse-aim-…` mentions the `updating-project-docs` skill.

**Required:** add the docs step to tasks 1 and 2 at minimum (open_space.md ship composition;
global.md autoload table + the "ten" count; `PROJECT.md`), and to task 4 — its own body already
asks for a `CLAUDE.md` / `tests/README.md` entry, which is the same obligation stated informally.

---

## Non-blocking observations

1. **The frame-rate-independence case pins the clamp, not the exponential.** Run headlessly with
   the plan's own numbers (half-life 0.14, cap 150 °/s): stepping from `0` toward `π` for 1 s gives
   `-2.617993877991` at *both* 60 × 1/60 and 30 × 1/30 — difference exactly `0.0` — because the
   rate cap binds for the entire second, making the model a constant-rate turn there. It still
   fails a clamped bare `lerp(…, 0.1)` (`-2.61799` vs `-2.56904`, 0.049 rad apart), so the case is
   not vacuous, but it is testing the wrong component. Add or switch to a small target inside the
   unclamped band — from `0` toward `0.3` rad the correct model gives `0.29787721016188` at both
   rates (difference `0.0`) while a bare lerp gives `0.29946` vs `0.28728`, 0.0122 apart. That
   version fails for the right reason.
2. **The turn-rate-cap case's result is negative.** One `step()` with `delta = 1.0` from `0` toward
   `π` returns **`-2.61799387799149`** (the 180° tie-break again), not `+2.618`. The plan's wording
   ("moves at most") is fine; an implementer who writes
   `assert_almost_eq(result, deg_to_rad(150.0), …)` will be baffled. Say "assert `absf(result)`".
3. **"Exactly `deg_to_rad(220.0)`" is only exact for one step.** Sixty accumulations of
   `deg_to_rad(220.0) * (1.0/60.0)` print as `3.83972435438753` and compare `!= deg_to_rad(220.0)`
   (verified). GUT's `assert_eq` on floats is exact. Either specify a single `step(delta = 1.0)` or
   use `assert_almost_eq`.
4. **The scheme-flip case is close to a tautology.** "Returns a value within one frame's cap of
   `rot`" is true of *any* implementation that applies the cap. It catches only a `set_scheme` that
   snaps rotation — worth saying so. Related: `set_scheme`'s `_target_angle = current_rotation`
   re-seed is overwritten by the next `set_aim_target()` in `_handle_rotation` on the very next
   frame, so it only has an effect while steering is disabled or the cursor is in the dead zone.
   Keep it, but do not let the test imply it is what prevents the jump — the cap is.
5. **`signal scheme_applied(scheme: StringName)` has no emit site and no consumer** anywhere in the
   plan or in any task body. Drop it, or name who connects to it. (It is harmless w.r.t.
   `test_signal_emit_arity.gd`, which only sweeps signals that are actually self-emitted.)
6. **Pause-menu layout is unspecified.** Options are absolutely positioned:
   `pause_menu.tscn` `MenuContainer` at `y=184` with rows at 110/178/244/310/376 (66 px pitch), so
   a sixth row lands near `y≈442` → ~626 px down a 720 px viewport, plus the button sprite's
   `+14` offset and 2× scale. It fits, but only just, and the new row needs a `Bg`, a `Label` and
   an icon in *both* scenes. Also note `open_space_pause_menu.tscn`'s `Option1`/`Option2` are bare
   `Node2D`s with **no `Label` child** — a new test must not `get_node("Label")` on them.
7. **The dead-zone rationale overstates the ship.** `player_ship.tscn:208-209` gives the hull
   `CircleShape2D_body` a radius of `11.045` px; the `64×64` in the plan is the atlas cell, most of
   which is padding. 48 px is ≈4.4 hull radii — a 96 px-diameter dead circle around a ~22 px ship.
   Probably still fine, and it is an `@export`, but flag it for the human fly-test rather than
   claiming it is "about a ship's width".
8. **One research claim is not in its cited source.** Finding 5 attributes to the Nova Drift thread
   that "the game also drives aiming from a **software mouse** rather than the OS pointer position".
   The full page (refetched with `scripts/fetch-page.sh`, 28 KB, all 14 comments) contains no such
   statement — the two quoted lines about twin-stick design and the directional-steering setting
   *are* there and are accurate. The software-cursor idea is then used in finding 7 and in the
   plan's "no cursor capture" decision, where it is only being rejected, so nothing downstream
   breaks; but the attribution should be dropped or re-sourced.
9. **Two counts are wrong.** `1-context.md` says `project.godot`'s `[autoload]` has 11 entries; it
   has 10. `global.md:70` says "All ten" — that line becomes "eleven" with `SettingsState`.
10. **Model assignment.** All six impl tasks are `sonnet`, which is defensible — the plan is
    written, and none of the work is architectural. The one I would reconsider is
    `choose-mouse-aim-…` (`medium`/`sonnet`): it edits a file shared by all three modes whose
    `_confirm()` is matched by *index*, in two duplicated scenes, adds a new sub-overlay scene and
    script, updates an existing test (B1), and must not break assault or infiltration. It is the
    highest-blast-radius task in the epic. Either raise it to `opus`, or leave it at sonnet with
    B1's test edit spelled out explicitly in the DONE WHEN. `your-ship-leans-…` at
    `medium`/`sonnet` is right.
11. **"Exactly one writer" is one writer *per frame*.** `player_ship.gd:46` still sets
    `rotation = 0.0` in `_ready()`. Harmless, but the controller's `_target_angle` should be seeded
    from the ship's rotation on ready rather than relying on both defaulting to `0.0` — today they
    coincide by accident, and the dead zone holds whatever the initial target is.
12. **Window-focus hold is the right call, but note where the notification is handled.**
    `PlayerBase` declares no `_notification`, so `player_ship.gd` can add one without a `super()`
    call — verified, no conflict.
