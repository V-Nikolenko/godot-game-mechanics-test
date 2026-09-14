# Open-space mouse aiming: inertial turn-to-cursor with a control-scheme setting — completion report

Epic id: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
Nine tasks (3 preparation + 6 implementation), all `done`. Closed 2026-09-15 on `agent/auto-dev`.

---

## What was built

### Preparation

| Task | Artifact |
|---|---|
| Research | [`2-research.md`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/2-research.md) — 7 findings, 5 external sources, plus three behaviours **verified in-engine** (Godot 4.6.3 headless) rather than assumed. |
| Plan | [`3-plan.md`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/3-plan.md) — revision 2, 728 lines. |
| Plan review | [`4-review.md`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/4-review.md) — two rounds by an independent subagent. Round 1 `CHANGES_REQUESTED` (B1–B5 + 12 observations); round 2 `VERDICT: APPROVED` with 9 non-blocking findings. User approved 2026-09-14. |

### Implementation

| # | Task | What shipped | Commit |
|---|---|---|---|
| 1 | Your ship leans toward the mouse cursor instead of snapping to it | `open_space/scenes/entities/player/ship_turn_controller.gd` (`ShipTurnController`), added as a child of `player_ship.tscn` and made **the only writer** of that ship's `rotation`. Both schemes behind `@export var scheme`, defaulting to `&"mouse"`. `player_ship.gd::_handle_rotation` shrank to three lines; `rotation_speed_deg` moved off the ship onto the controller. | `49f7836` |
| 2 | The game remembers which steering scheme you fly with | `global/autoloads/settings_state.gd` (`SettingsState`) — the project's **eleventh** autoload and first settings store, `user://settings.cfg`. Registered in `project.godot`, added to `save_sandbox.gd::PATHS`. The ship seeds `_turn.scheme` in `_ready()` and re-seeds live on `open_space_scheme_changed`. | `6187050` |
| 3 | AI Targeting still snaps your nose onto an enemy, and the snap holds | `face_instant(angle)` on **both** `OpenSpacePlayerShip` and `AssaultPlayer`; `ai_targeting_module.gd` calls it duck-typed with no `actor.rotation` fallback. The hold is released by a real `InputEventMouseMotion`, routed through `player_ship.gd::_input()` → `_turn.notify_mouse_moved()`. | `4d6bed2` |
| 4 | A future ship module cannot silently fight your steering | `tests/integration/test_ship_rotation_single_writer.gd`, the suite's **eleventh invariant test**. Sweeps `global/ship_modules/*.gd` for a direct `.rotation =`/`+=`/`-=` with an empty, permanent allowlist. Listed in `CLAUDE.md` and `tests/README.md`. | `5ee8951` |
| 5 | Alt-tabbing away no longer leaves your ship turning on its own | `ShipTurnController.set_steering_enabled()` (freezes the target angle, keeps stepping, so there is no discontinuity on resume) + `player_ship.gd::_notification()` on `NOTIFICATION_APPLICATION_FOCUS_OUT` / `_IN`. | `50debd3` |
| 6 | Choose mouse aim or classic A/D steering from the pause menu | `global/ui/pause_menu/settings_panel.{gd,tscn}` (`SettingsPanel`) — a sub-overlay with `LoreLogList`'s `open()`/`close()`/`navigate()` shape plus `cycle(dir)`. `PauseMenu` gains `Option4` = Settings; Exit Game moved to `Option5` in **both** pause-menu scenes, each with its own row geometry. One row: Open-Space Steering: Mouse Aim / Classic (A/D). | `43e7cb7` |

**Docs updated alongside the code, not after it:** `docs/architecture/PROJECT.md` (autoload table,
now eleven), `docs/architecture/modules/global.md` (autoload table + a new "Settings panel"
section), `docs/architecture/modules/open_space.md` (ship composition), `CLAUDE.md` (the
single-mouse-read convention and the single-writer gate) and `tests/README.md` (three new sections).

---

## How it was verified

`bash /agent/verify.sh` — import, headless boot, full GUT suite — green at the end of every one of
the six implementation tasks. Final run: **63 scripts, 487 tests, 2467 asserts, all passing.**
`bash scripts/check-test-leaks.sh` (gate step 3 plus the leak-line grep) also clean, which the plain
gate cannot tell you: a leaked `SceneTreeTimer` is reported at *process exit*, after GUT has already
set exit code 0.

### Tests this epic added — 43 cases across six files

**`tests/unit/test_ship_turn_controller.gd` (14)** — the turn model, on a tree-less instance with
injected cursor positions:
`test_shipped_defaults`, `test_turn_is_frame_rate_independent`, `test_turn_rate_cap_holds`,
`test_never_overshoots_the_target`, `test_wraps_the_short_way_across_pi`,
`test_cursor_exactly_on_the_ship_holds_the_target`, `test_dead_zone_edge`,
`test_exact_180_degree_tie_break_turns_negative`,
`test_classic_scheme_is_still_220_deg_per_second`, `test_classic_scheme_ignores_the_cursor`,
`test_mouse_scheme_ignores_the_ad_axis`, `test_scheme_flip_mid_turn_does_not_jump`,
`test_snap_holds_until_the_mouse_moves`, `test_disabled_steering_freezes_the_target`.

**`tests/integration/test_player_ship_turn_wiring.gd` (7)** — **the anti-inert test**, and the most
important file in the set: every unit test above is green on a build where the controller was never
added to the scene. This one asserts the wiring:
`test_ship_scene_carries_a_turn_controller`, `test_handle_rotation_delegates_to_the_controller`,
`test_scheme_is_seeded_from_settings_state_on_ready`,
`test_scheme_signal_reseeds_the_live_controller`, `test_target_angle_is_seeded_from_the_hull_facing`,
`test_focus_out_disables_steering_and_focus_in_re_enables`,
`test_old_rotation_speed_export_is_gone`.

**`tests/unit/test_settings_state.gd` (6)** — default on empty disk, round-trip through a second
instance, fallback on a hand-corrupted value, rejection of a value not in `SCHEMES`, no emit on a
redundant set, and the signal carrying its argument.

**`tests/integration/test_ai_targeting_faces_actor.gd` (3)** — the module calls `face_instant` and
leaves `rotation` alone; **the assault fighter's snap is unchanged** (new coverage over code that
had none); an actor without `face_instant` is left alone and keeps its cooldown.

**`tests/integration/test_ship_rotation_single_writer.gd` (5)** — the invariant, plus the two
boundary cases that make it *able* to fail (the sweep must find a non-zero number of module files
and must find `ai_targeting_module.gd` by name) and the two coverage cases (both player classes
declare `face_instant`, checked via `GDScript.get_script_method_list()` so an inherited
`PlayerBase` method would **not** satisfy it).

**`tests/integration/test_pause_menu_settings.gd` (8)** — row placement in both scenes, open/close
routing, and the two load-bearing ones:
`test_menu_right_on_the_steering_row_flips_the_live_setting_and_the_value_label` drives the **live**
`SettingsState` (a row with an empty handler passes every placement assertion), and
`test_menu_confirm_while_panel_open_does_not_fall_through_to_confirm` parks `_cursor` on **Exit
Game** first, so a fall-through kills the test run outright instead of failing quietly.

One existing test changed: `test_pause_menu_lore_logs.gd::test_exit_game_is_now_at_index_4` →
`…_index_5`, `_options[4]` → `_options[5]`.

### What the gate cannot cover

- **Whether any of it feels right.** 150 °/s, 0.14 s and 48 px are judgement calls. Nothing headless
  can validate feel. A human has to fly the sector hub.
- **Where the rows land on screen.** Both pause-menu scenes position options absolutely and do not
  agree on the geometry. No gate step renders a scene, so a misplaced or off-screen row is invisible
  to the suite. Mission-mode Exit Game now sits ~626 px down a 720 px viewport.
- **Real focus loss.** `test_focus_out_disables_steering_and_focus_in_re_enables` sends the
  notification by hand; no headless run can alt-tab.
- **Real mouse input.** By construction — that constraint is what shaped the design.

---

## Decisions and course changes

**The reviewer's round-1 verdict was `CHANGES_REQUESTED`, and it was right.** Five blocking findings:

- **B1** — the plan (and task 6's body, which `backlog-cli` cannot rewrite) claimed
  `test_pause_menu_lore_logs.gd` "references only indices 1-3, verified by grep". It does not:
  `test_exit_game_is_now_at_index_4` asserts `_options[4]` is "Exit Game", so inserting Settings at
  index 4 reds it. The claim was false *and* presented as verified. Corrected into an explicit line
  in the build sequence; the implementation session made the edit as a known step rather than
  hitting it as a surprise.
- **B2–B5** and twelve observations produced the dead-zone rationale correction (11.045 px hull
  radius, not a 64×64 atlas cell), the withdrawal of the Nova Drift "software mouse" attribution
  after refetching the page in full, and the per-scene row geometry (**N4**: the numbers were right
  for `pause_menu.tscn` and silently wrong for `open_space_pause_menu.tscn`, whose container sits at
  `y = 226` with `Option1`/`Option2` as bare `Node2D`s carrying no `Label` child at all).

Round 2: **`VERDICT: APPROVED`**, nine non-blocking findings folded in. The user approved the epic
2026-09-14. The earlier `decision: changes` from 2026-09-13 was process bookkeeping — the
plan-review task had been marked done before the review had returned — not a rejection of any
design.

**Mid-build changes to the plan**

- Task 6's body was already known-wrong before it started (B1 above) and was corrected in the plan
  rather than in the body, because `backlog-cli` cannot rewrite a task body. The plan carries a
  "Task-body corrections" section for exactly this. **This worked** — but it depends on the
  implementing session reading the plan first, which is the Direct track's first step for a reason.
- The one deviation taken without asking, in task 6: a doc line in `global.md` called Lore Logs
  "a fifth `PauseMenu` option (`Option3`…)". `Option3` is the fourth. Corrected in passing.
- `test_pause_menu_settings.gd` ended up with **8** cases rather than the plan's 6: `menu_left` was
  split out from the `menu_right` case, and the fall-through case was strengthened to park the
  cursor on Exit Game. Both are additions, not substitutions.

**Design choices worth restating**

- `face_instant()` is duck-typed with **no `actor.rotation` fallback**. A fallback would have made
  the invariant test unenforceable and re-created the bug for any actor missing the method.
- The `AITargetingModule` hold releases on *motion*, not on cursor position, because
  `get_global_mouse_position()` is a world position that moves with the camera — a physically still
  mouse would otherwise clear the hold on the next frame the ship drifts.
- No generic settings framework. One row, one branch in `cycle()`.

---

## Numbers

| Value | Where it came from |
|---|---|
| `keyboard_turn_rate_deg = 220.0` | **Existing code.** Today's `player_ship.gd::rotation_speed_deg`, moved not changed — Classic must be today's behaviour exactly. |
| `mouse_max_turn_rate_deg = 150.0` | **Judgement**, derived from this project's constants: ~68% of the keyboard rate; 180° in 1.2 s, inside `EngineBoostModule`'s 2.0 s cooldown. Below ~110 °/s the flip-boost (`boost_speed_threshold = 180` px/s) stops being aimable; above ~180 °/s Classic has no reason to exist. |
| `mouse_turn_half_life = 0.14 s` | **Band from research** (Driscoll / Holmér: 0.1–0.2 s is "snappy but visibly lagging"); the specific value inside it is judgement. λ = ln2/0.14 ≈ 4.95, ≈8% per frame at 60 Hz before the cap bites. |
| `mouse_dead_zone_px = 48.0` | **Mechanism from research** (the cursor-on-ship singularity), radius from this project's geometry: ≈4.4× the hull's 11.045 px `CircleShape2D_body`. **The number most in need of a fly-test.** |
| `DEFAULT_SCHEME = &"mouse"` | Stated in the original idea. |

All four turn values are `@export`s on a node in `player_ship.tscn`, so acting on a fly-test is an
inspector change, not a code change. That was a deliberate response to the Jet Lancer finding.

---

## Known gaps

**Nobody has flown this.** That is the headline. The entire feel side of the epic —
the four numbers above and the AI-Targeting hold — has been proven correct, frame-rate
independent, capped and wrap-safe, and has been validated for *feel* not at all.

1. **The three turn numbers need a human in the sector hub.** If 150 °/s reads as sludge, or 48 px
   as a dead patch in close-quarters dogfighting, the fix is an inspector value.
2. **The AI-Targeting snap may release almost instantly in practice** (review N7).
   `notify_mouse_moved()` fires on *any* `InputEventMouseMotion`, including one pixel of hand
   tremor, so for a player actively aiming the hold lasts a fraction of a second. The design is
   still right, but "the snap holds" is only true for a player who stops moving the mouse. If it
   reads badly the dial is a short *timed* hold behind the same `notify_mouse_moved()` seam.
3. **Nobody has looked at the pause menu.** Mission-mode Exit Game moved to ~626 px down a 720 px
   viewport — it fits with little room to spare, and no gate step renders a scene. If it crowds the
   bottom edge, lift `MenuContainer` rather than re-ordering the list (Exit Game stays last). The
   `SettingsPanel` layout itself — a 960×520 panel with one row at the top-left — has also never
   been seen by a human; it is functional, not designed.
4. **The flip-boost may be harder to aim under mouse steering.** `EngineBoostModule` latches its
   direction from `actor.rotation` at activation, and the player now has less authority to point
   before committing. That is a *balance* consequence of the ask, not a bug, but it is the most
   likely thing a fly-test comes back unhappy about.
5. **"Pointer left the window but the window is still focused" stays uncovered**, accepted
   explicitly in task 5. Only focus loss freezes steering.
6. **`SettingsPanel` has no second row yet**, so `navigate()` is exercised by nothing but a clamp.
   The first real second setting will be the test of whether "a copy of the first branch" was the
   right call, or whether a framework was wanted after all.
7. **`_handle_thrust()` and the pending open-space boost epic.** The plan warns the two epics must
   not be implemented in the same window. This epic only ever touched `_handle_rotation`, so the
   conflict is textual — but the boost epic's plan predates these changes to `player_ship.gd`.

---

## Links

- Epic preparation: [`docs/plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/`](../../plans/open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr/)
  (`1-context.md`, `2-research.md`, `3-plan.md` rev 2, `4-review.md` two rounds)
- Epic id: `open-space-mouse-aiming-inertial-turn-to-cursor-with-a-contr`
- Commits, in order: `49f7836`, `6187050`, `4d6bed2`, `5ee8951`, `50debd3`, `43e7cb7`
- No escalated task needed its own plan directory — all six ran the Direct track against the
  approved epic plan.
