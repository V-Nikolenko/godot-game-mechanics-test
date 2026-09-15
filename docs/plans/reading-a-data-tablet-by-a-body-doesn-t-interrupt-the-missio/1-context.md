# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/pickups/pickup_base.gd` | `Area2D` base for all collectibles: `body_entered` -> `_collect()` -> optional dialog notification -> `queue_free()`. | The task brief explicitly says this is the wrong parent (frees itself, needs no input) but the **precedent** for the notification path: `_show_notification()` builds a one-line `DialogScriptResource` (`INNER_THOUGHT`, `INSTANT`, `pause_gameplay = false`) and skips silently if `DialogPlayer.is_active`. Our interactable needs the same non-blocking notification shape and the same busy-guard, but triggered by input instead of contact, and never consumed. |
| `global/autoload/dialog_player.gd` | Autoload dialog runner. `play(script)` is async; `is_active` is true from `dialog_started` to `dialog_finished`. | We call `DialogPlayer.play()` to show the message. `pause_gameplay = false` scripts don't pause the tree — matches "doesn't interrupt the mission." Guard on `is_active` before calling `play()`, exactly like `PickupBase._show_notification()`. |
| `global/ui/dialog_system/resources/dialog_script.gd`, `dialog_line.gd` | `DialogScriptResource` (ordered lines + `pause_gameplay`), `DialogLineResource` (`text`, `side`, `reveal`, `post_delay`). | Used to build the one-line message resource at runtime, same shape `PickupBase` builds. |
| `global/ui/dialog_system/triggers/dialog_trigger.gd` | Declarative `DialogPlayer.play()` wrapper with `play_once` and signal-driven `fire()`. | Considered and **rejected** as the mechanism here — see Design/rejected alternatives. Still worth knowing it exists so the plan doesn't reinvent its signal-wiring idea. |
| `global/entities/player_base.gd` | `PlayerBase extends CharacterBody2D`. `_ready()` does `add_to_group("player")`. Used by `open_space/scenes/entities/player/player_ship.gd` and `assault/scenes/player/player_fighter.gd`. | The "player" group and the `PlayerBase` type are what pickups use to recognize the player body. `infiltration`'s player (see below) is **not** one of these. |
| `infiltration/scenes/entities/player/player.gd` (`extends CharacterBody2D`, no `class_name`) | Standalone isometric player controller. Does **not** call `add_to_group("player")` and its `player.tscn` sets no explicit `collision_layer`/`collision_mask` (CharacterBody2D defaults: layer 1, mask 1). | Confirms the task brief's claim that "no script uses `interact` yet" — and shows that an interactable built to fire off the "player" group or layer 4 (below) will **not** yet be reachable by the infiltration player. Wiring infiltration into this is out of scope (see Out of scope) but this gap is worth recording so nobody assumes "walk up to it" already works there. |
| `project.godot` (`[input]` `interact`, `[layer_names]`) | `interact` is bound to physical keycode 70 (**F**), line ~121. Physics layers: `layer_1=environment`, `layer_2=environment_interactable`, `layer_3=environemnt_player` (typo in the project, not ours to fix), `layer_7..10` = hit/hurt boxes. | `interact` has exactly zero script references project-wide (verified via `grep -rn "interact"`) — first user. `environment_interactable` (bit value 2) is clearly the layer meant for exactly this kind of object; `environemnt_player` (bit value 4) is what `open_space`/`assault` players' main body already sits on (see next row) — the pairing an `Area2D` interactable should use. |
| `open_space/scenes/entities/player/player_ship.tscn`, `assault/scenes/player/player_fighter.tscn` | Player body `CollisionShape2D`: `collision_layer = 4` (= layer 3, `environemnt_player`). | Confirms `collision_mask = 4` is the correct mask for an `Area2D` interactable to detect these two players' bodies — it is exactly the mask every existing pickup scene already uses (`collision_mask = 4` on all 9 `global/pickups/scenes/*.tscn`). |
| `global/pickups/scenes/*.tscn` (9 scenes) | `collision_layer = 16` (own, unnamed bit), `collision_mask = 4`. `Area2D` root, `Sprite2D` + `CollisionShape2D` (`CircleShape2D`) children. | Direct template for our scene's collision setup and node shape, except our own layer should be `environment_interactable` (2), not 16 — pickups don't need a *named* layer since nothing scans for "a pickup" from outside; an interactable arguably could be scanned for later, and the project already minted a layer name for exactly this case. |
| `tests/helpers/player_stub.gd` | `PlayerStub extends PlayerBase`, `static func spawn(...)`. No `class_name` (test-only types shouldn't appear in autocomplete). | Use this to get a real `PlayerBase`-shaped body for `body_entered`/`body_exited` tests, matching `test_weapon_unlock_sources.gd`'s and other suite conventions. |
| `tests/unit/test_dialog_player.gd` | Characterization tests for `DialogPlayer`. Never drives `play()` to a real completion — only the guarded no-op paths (`play(null)`, `play(empty)`) and the idle/skip-while-idle paths. | **Hard constraint on our test plan.** See "Sibling-task lesson" below. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/pickups/pickup_base.gd:36-49` (`_show_notification`) | The exact shape of a non-blocking, busy-guarded, one-line notification. We mirror this construction rather than importing it (see Design — duplicating ~8 lines here is deliberate; extracting a shared helper would mean editing an unrelated, currently-untested file for a task that doesn't need to touch it). |
| `tests/helpers/player_stub.gd` | Real `PlayerBase` instance for `body_entered`/`body_exited` simulation in tests, no scene loading needed. |
| `tests/helpers/save_sandbox.gd` | Not needed here — this interactable touches no persistent state (`LogState` or otherwise) by design. |

## Sibling-task lesson (read before writing the test)

The epic's other in-flight task, `flying-into-a-log-record-in-open-space-picks-it-up-and-tells`
(same epic, `docs/plans/flying-into-a-log-record-in-open-space-picks-it-up-and-tells/4-review.md`),
is **currently stuck** after two review rounds over exactly this hazard: a test that drives a real
`_on_body_entered()` (or here, a real interact-fire) starts a genuine `DialogPlayer.play()`
coroutine. That coroutine's first `await` is *inside* `DialogBox.present_line()` (a ~0.22s fade-in
tween), **not** `DialogPlayer`'s own `await _box.line_finished` — so a test that returns without
processing real frames leaves a suspended `GDScriptFunctionState` that:

- Is invisible to the gate's `FATAL` regex (reported only at process exit, per
  `scripts/check-test-leaks.sh` / `tests/README.md`'s leak-trap section).
- Leaves `DialogPlayer.is_active` stuck `true`, which every other `DialogPlayer` test's
  `before_each()` asserts is false at the start.
- Cannot be resolved by calling `DialogPlayer.skip_dialog()` immediately afterward — `skip_dialog()`
  kills the fade-in tween via `Tween.kill()`, which per `dialog_box.gd`'s own documented Godot-4
  behavior does **not** emit `finished`, so that produces a *second*, permanently-stuck await
  instead of resolving the first one.

The reviewer's own recommended way out (still applicable here): **do not let the interact-fire path
reach a real `DialogPlayer.play()` in a test that will end synchronously.** Either assert the
message-showing behavior through a small internal seam that stops short of calling `play()` (e.g.
a `_build_notification_script(text)` helper the test can call and inspect the returned
`DialogScriptResource` without ever invoking `play()`), or pre-set `DialogPlayer.is_active = true`
before firing so the busy-guard short-circuits before `play()` is ever called — proving the guard
fires without ever starting a real coroutine. The enter/exit/re-read cycle itself (prompt
visibility, repeatability, no `LogState` interaction) needs neither of those and can be asserted
entirely off `body_entered`/`body_exited` and repeated direct calls to the interact handler with
the guard pre-armed.

## Conventions that constrain this

- **Composition over inheritance / sibling of `PickupBase`, not a subclass** — per the task brief.
  Own `Area2D`-derived class, own scene.
- **Physics layers**: `environment_interactable` (2) for the interactable itself,
  `environemnt_player` (4, the typo'd layer-3 name) as its `collision_mask` — the same mask value
  every pickup already uses, but a layer of its own rather than reusing the pickups' unnamed 16, since
  the project already named a layer for exactly this purpose.
- **Signal arity / verbose-only logging** — any new signal must declare exactly what it emits; any
  per-frame print stays behind `OS.is_stdout_verbose()`. This interactable is not expected to need
  per-frame logging or a new signal (no external listener needs one — the prompt and message are
  entirely local effects), so neither convention is exercised, but keep it in mind if the design
  changes.
- **Godot 4.6 UID rules** — never hand-type or copy a `uid://` line; leave new resource references
  UID-less or mint via the headless `ResourceUID.create_id()` snippet in `tests/README.md`.
- **Tests are GUT** — `tests/unit/` for anything not requiring a full scene load, matching
  `test_dialog_player.gd` / `test_log_state.gd`'s existing pattern of exercising the live/instanced
  script directly rather than instantiating a whole level.
- **`scripts/check-test-leaks.sh`** must be run once the new test exists, since it touches
  `DialogPlayer` and awaits — required by `CLAUDE.md`'s "run it after touching anything that
  awaits."

## Out of scope (confirmed against the epic's task list)

`./scripts/backlog-cli.js epic show log-records-discoverable-lore-and-info-logs-across-all-three`
shows two *later* tasks that own everything this task must not attempt:

- `log-records-can-be-placed-in-assault-and-infiltration-missio` — placing any interactable
  (lore or info) into `assault/` or `infiltration/` missions, and by extension wiring the
  infiltration player into the "player" detection story (group membership / collision layer).
- `test-logs-on-the-open-space-map-prove-both-log-types-work-en` — placing demo instances of both
  log types into the open-space hub to demonstrate the system end to end.

So this task builds the reusable script + scene + test only. No sprite is generated: the task
brief's own wording ("a data tablet, a terminal, or a scrap of hull") describes several different
physical dressings for the *same* interaction contract, unlike `LoreLogPickup`'s single canonical
collectible appearance — so baking in one sprite here would just be thrown away or reskinned by
whichever later task places the first real instance. The scene ships as an undressed template
(`Area2D` + `CollisionShape2D` + prompt `Label`); a placement task adds its own `Sprite2D` child
and sets `message`/`prompt_text`.
