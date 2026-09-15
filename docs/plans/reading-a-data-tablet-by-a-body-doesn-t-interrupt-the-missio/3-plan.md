# Readable log-record interactable (information logs)

## Problem

`interact` (bound to **F**) exists in `project.godot` but no script in the project uses it. The
epic wants two kinds of log record: lore logs (a separate, already-in-flight task) and
**information logs** — one-time environmental flavor text (a tablet by a body, a wall terminal, a
scrap of hull) that:

- shows a prompt when the player is close enough,
- on `interact`, plays its message inline via `DialogPlayer` **without pausing gameplay**,
- never gets consumed — walking away and back and pressing `interact` again replays it,
- never touches `LogState` and never counts toward completion,
- refuses to fire while a dialog is already on screen (`DialogPlayer.is_active`).

`PickupBase` is the wrong parent: it frees itself on contact and needs no input. This is a sibling
of it.

## Design

New class `InfoLogInteractable`, `Area2D`, in a new top-level-under-`global` category
(`global/interactables/`) — this is a genuinely new kind of shared building block (not a pickup,
not a component in the composable-child-node sense, not a ship module), so it gets its own
directory the same way `pickups/`, `components/`, `ship_modules/` each did.

```
global/interactables/
├── info_log_interactable.gd
└── scenes/
    └── info_log_interactable.tscn
```

```gdscript
class_name InfoLogInteractable
extends Area2D

## A re-readable environmental message: a tablet, terminal, or scrap of hull. On `interact`
## while the player is in range, plays `message` inline via DialogPlayer (pause_gameplay = false)
## and does NOT consume itself — the same object can be read again after walking away and back.
## Never touches LogState: information logs don't count toward completion.

@export_multiline var message: String = ""
@export var prompt_text: String = "Press F to read"

@onready var _prompt: Label = $PromptLabel

var _in_range: Array[Node2D] = []


func _ready() -> void:
	_prompt.text = prompt_text
	_prompt.visible = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if not _in_range.has(body):
		_in_range.append(body)
	_prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	_in_range.erase(body)
	if _in_range.is_empty():
		_prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _in_range.is_empty():
		return
	if not event.is_action_pressed("interact"):
		return
	if DialogPlayer.is_active:
		return
	get_viewport().set_input_as_handled()
	_read()


func _read() -> void:
	if message.is_empty():
		return
	DialogPlayer.play(_build_script(message))


## Split out from _read() so a test can assert the resource's shape (single INSTANT
## inner-thought line, pause_gameplay = false) without ever calling DialogPlayer.play() —
## starting a real play() cannot be resolved synchronously inside a test (see the sibling
## lore-log-pickup task's stuck review for why).
func _build_script(text: String) -> DialogScriptResource:
	var line := DialogLineResource.new()
	line.text = text
	line.side = DialogLineResource.Side.INNER_THOUGHT
	line.reveal = DialogLineResource.Reveal.INSTANT
	line.post_delay = 0.4
	var script_res := DialogScriptResource.new()
	script_res.lines = [line]
	script_res.pause_gameplay = false
	return script_res
```

Notes on the choices above:

- **Own directory, not `global/pickups/`.** `pickups/`'s own docstring convention
  (`PickupBase`'s header comment) and every existing subclass name end in `*Pickup` and share the
  free-on-contact contract. Filing a never-consumed, input-driven interactable next to them under
  a name that doesn't end in `Pickup` would be a worse fit than a new, equally-flat directory.
- **`_in_range: Array[Node2D]`, not a single `Node2D`.** Two players can't exist in solo play, but
  an `Area2D` can report more than one overlapping body in principle (e.g. a large hitbox briefly
  overlapping two colliders on the same body), and tracking a list is exactly as simple as a
  nullable single reference while being correct if that ever happens — the prompt should only hide
  once *nothing* is in range, not on the first exit.
- **`is_in_group("player")` filter, same as `PickupBase`.** Matches the existing convention even
  though `collision_mask` (below) already narrows candidates to the "environemnt_player" layer —
  defensive and consistent, not redundant in the sense of policing a layer that could pick up
  something else later.
- **Duplicating `PickupBase._show_notification()`'s ~8-line construction instead of extracting a
  shared helper.** The two call sites want subtly different lifecycles (`PickupBase` calls this
  once then frees itself; this fires repeatedly on demand), and extracting a helper now means
  editing an unrelated, currently-test-free file (`pickup_base.gd`) for a task that doesn't need to
  touch it. If a third consumer of this exact notification shape shows up, that is the point to
  extract it.
- **`_unhandled_input` over `_input`**: matches `DialogPlayer._unhandled_input`'s own choice for
  the same reason — UI (menus, dialog) gets first claim on input, environment interaction is
  lower-priority. `set_input_as_handled()` on a successful read stops the event from also
  triggering anything else bound to the same physical key.
- **No `LogState` reference anywhere in the file** — the "unaffected by `LogState`" acceptance
  criterion is structural (the class doesn't `preload`/reference the autoload at all), not just
  behavioral.
- **`DialogPlayer.is_active` guard checked in `_unhandled_input`, before `_read()` is even
  called** — so a repeated key press while a message is already showing is a true no-op (doesn't
  re-enter `_read()`, doesn't rebuild a `DialogScriptResource` it would then discard).

### Rejected alternatives

- **Reusing `DialogTrigger`** (`global/ui/dialog_system/triggers/dialog_trigger.gd`): it wraps
  `DialogPlayer.play()` behind `fire()`/`fire_from_signal()`/`play_once`, but `play_once` defaults
  to consuming — the opposite of what "read it again" needs — and it expects a pre-built
  `@export var script_resource: DialogScriptResource`, which would push every placement to author
  a nested `DialogScriptResource`/`DialogLineResource` pair in the editor instead of a single
  `message` string. `PickupBase`'s own notification path already establishes "build the one-liner
  resource in code from a plain string" as the project's convention for this exact kind of short
  inline text; `InfoLogInteractable` follows that, not `DialogTrigger`.
- **A `collision_layer = 16` matching pickups**: rejected in favor of `environment_interactable`
  (2) — the project already named a physics layer for exactly this kind of object
  (`project.godot`'s `2d_physics/layer_2="environment_interactable"`), unused by anything today.
  Reusing the pickups' unnamed 16 would leave that name meaning nothing.
- **A generic sprite baked into the scene now**: rejected — see `1-context.md`'s "Out of scope."
  The brief's own wording ("tablet, terminal, or scrap of hull") describes different physical
  dressings for one interaction contract; a later placement task adds its own `Sprite2D` per
  instance. The scene ships as an undressed template.

### Scene

`global/interactables/scenes/info_log_interactable.tscn`:

```
InfoLogInteractable (Area2D)          collision_layer = 2, collision_mask = 4
├── CollisionShape2D                  CircleShape2D radius 10 (mid-size between the two
│                                     interaction ranges implied by "walk up to" / "fly up to")
└── PromptLabel (Label)               visible = false, positioned above (offset_top ~ -32),
                                      horizontal_alignment = CENTER
```

No `Sprite2D` (see above). `collision_layer = 2` matches `environment_interactable`;
`collision_mask = 4` matches `environemnt_player`, the same mask value every existing pickup scene
already uses to detect the `open_space`/`assault` player bodies (`PlayerBase` subclasses set
`collision_layer = 4` on their main body shape).

## Build sequence

1. Write `tests/unit/test_info_log_interactable.gd` (failing first — nothing exists yet).
2. Write `global/interactables/info_log_interactable.gd`.
3. Build `global/interactables/scenes/info_log_interactable.tscn` (script + `CollisionShape2D` +
   `PromptLabel`, no sprite).
4. Run the GUT suite; confirm the new test passes and nothing else regresses.
5. `bash scripts/check-test-leaks.sh` — this test touches `DialogPlayer`/awaits nothing itself, but
   verifying it against the leak checker is cheap insurance given the sibling task's exact failure
   mode was in this same area.
6. `bash /agent/verify.sh`.
7. Invoke the `updating-project-docs` skill — this adds a genuinely new top-level shared category
   (`global/interactables/`, alongside `pickups/`, `components/`, `ship_modules/`) and a new class,
   which is exactly the "adding an entity/component/module" case `CLAUDE.md`'s "MANDATORY — keep
   the docs current" section requires it for. At minimum this means adding a row to
   `docs/architecture/modules/global.md`'s directory map and its "Autoloads"-adjacent prose (the
   doc currently lists `pickups/` etc. as a single line — `interactables/` needs the same), and
   checking whether `docs/architecture/PROJECT.md` needs a matching mention.

Each step is independently checkable; 1-3 are the only steps that touch game code.

## Test plan

New file `tests/unit/test_info_log_interactable.gd` (unit — matches `test_dialog_player.gd` /
`test_log_state.gd`'s pattern: exercise the script directly, minimal tree). Uses
`tests/helpers/player_stub.gd` (`PlayerStub.spawn()`) for a real `PlayerBase`-shaped body so
`is_in_group("player")` passes exactly as it would in the game.

**Per the sibling task's review lesson (see `1-context.md`): no test here may let a real
`DialogPlayer.play()` coroutine start and then end the test without that coroutine having actually
resolved.** Every case that needs the busy-guard to have *already fired* pre-arms
`DialogPlayer.is_active = true` first (restored to `false` in `after_each`) so `_read()`'s guard
short-circuits before `play()` is ever called — proving the guard without starting a real
coroutine. `is_active` is a plain `bool` field on the autoload, not something with a resource of
its own to sandbox, so `after_each` just resets it directly (mirroring how `SaveSandbox` isn't
needed here, per `1-context.md`).

- `after_each`: `DialogPlayer.is_active = false` (belt-and-braces reset in case a case sets it and
  a later assertion fails before the manual reset line runs).

Cases:

1. **The prompt is hidden until the player enters range.** Instantiate `InfoLogInteractable`
   (`add_child_autofree`), assert `$PromptLabel.visible == false` before any body event.
2. **Entering range shows the prompt; leaving range hides it.** Call `_on_body_entered(player)`
   directly with a `PlayerStub`, assert `visible == true`; call `_on_body_exited(player)`, assert
   `visible == false`.
3. **A non-player body entering is ignored.** Call `_on_body_entered(Node2D.new())` (no "player"
   group membership): assert the prompt stays hidden and `_in_range` stays empty (guards against a
   stray rock/projectile `Area2D` overlap turning the prompt on).
4. **`interact` while out of range does nothing.** With no body ever entered, feed
   `_unhandled_input` a real `InputEventAction` (`action = "interact"`, `pressed = true`) — plain
   method call, no need to route through `Input`/a live viewport — and assert
   `DialogPlayer.is_active` is still `false` afterward (`_read()` was never reached).
5. **`interact` while in range is blocked if `DialogPlayer` is already busy.** Enter range, set
   `DialogPlayer.is_active = true` (simulating some other dialog already on screen), feed the same
   `interact` event, and assert `_read()`'s guard means nothing changed: `is_active` stays exactly
   `true` (not toggled, not reset) and `DialogPlayer._current_script` stays whatever it was
   (`null`, since nothing real was ever started). Proves the busy-guard without ever starting a
   real coroutine.
6. **`interact` while in range and idle builds the right message.** Enter range, set `message` to
   a known string, keep `DialogPlayer.is_active == false`. Instead of calling `_read()` (which
   would call the real `play()`), call `_build_script(message)` directly and assert on its return:
   `lines.size() == 1`, `lines[0].text == message`, `lines[0].side ==
   DialogLineResource.Side.INNER_THOUGHT`, `lines[0].reveal == DialogLineResource.Reveal.INSTANT`,
   `pause_gameplay == false`. This is the seam `1-context.md` flags as the safe way to assert
   message content without a real `DialogPlayer.play()` coroutine.
7. **Re-reading doesn't consume or mutate anything.** Call `_build_script(message)` twice in a
   row (standing in for two separate reads, per case 6's rationale) and assert both calls return an
   equally-shaped result and the node itself is never freed/queued for deletion and `message` is
   unchanged — the interactable has no internal "already read" flag to trip.
8. **No `LogState` coupling.** Snapshot `LogState.collected_count()`, run the case-7 double-read
   sequence, assert the count is unchanged. No save-file interaction expected, so no `SaveSandbox`
   needed here — this only reads the live in-memory count.
9. **Boundary — empty `message`.** With `message == ""`, call `_read()` for real: assert
   `DialogPlayer.is_active` stays `false` afterward (the empty-string guard returns before ever
   calling `play()`, so this is safe to call for real, unlike the non-empty case). Matches
   `PickupBase._show_notification`'s existing "empty string = no dialog" contract for the sibling
   pickup feature.

No test in this file calls `DialogPlayer.play()` with a non-empty script — case 9 is the only
`_read()` call with real content reaching `play()`'s call site, and it reaches it with an empty
script, which `play()` itself guards and returns from before entering the coroutine body
(`dialog_player.gd:42-44`), so nothing is left suspended. Every other assertion about message
content or the busy-guard goes through `_build_script()` or a pre-armed `is_active`, sidestepping
the sibling task's exact stuck point (a real, unresolvable suspended `play()` coroutine) entirely
rather than attempting a timing-sensitive fix to it.

## Risks

- `_build_script` is a seam added partly for testability. It earns its place independent of the
  tests too — naming the construction step makes `_read()` a one-liner — but if review disagrees,
  the fallback is to inline it into `_read()` and drop case 6/7's direct assertions in favor of
  asserting the same shape by reaching into the DialogScriptResource that would be passed, via a
  test double for `DialogPlayer` — a heavier change not preferred here.

## Out of scope

- Wiring `infiltration/scenes/entities/player/player.gd` into the "player" group or the
  `environemnt_player` collision layer — it currently has neither (`1-context.md`), and giving it
  either is squarely `log-records-can-be-placed-in-assault-and-infiltration-missio`'s job, since
  that task already owns placing interactables into `infiltration/` missions and will need the
  player detectable there regardless of which log type it's placing.
- Any placement of an actual instance in a real level/scene.
- Any sprite/art generation (see `1-context.md`).
- The ESC-menu Lore Logs section and `LogState` itself — unrelated to information logs by design.
