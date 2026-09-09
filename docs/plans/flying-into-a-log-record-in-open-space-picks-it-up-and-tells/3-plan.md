# Lore-log pickup

## Problem

`LogState` (autoload) already tracks which lore-log entries the player has found and derives the
total from the catalogue directory, but nothing in the world can grant one yet. A log record
floating in the sector hub should read as collectible, picking it up on contact should advance
`LogState`, and the player should get a one-line, non-blocking notification naming what they found
— without stopping the ship, and without being able to double-count one entry.

## Design

Add `LoreLogPickup`, a third sibling of `ShipModuleUnlockerPickup` / `WeaponModeUnlockerPickup`,
subclassing `PickupBase`. Unlike its two siblings it carries **no `@export` field** — `LogState`'s
model is deliberately anonymous (`collect_next()` grants whichever catalogue entry has the lowest
`sequence` and isn't collected yet, regardless of where in the world it was found), so there is
nothing for a level designer to configure per instance.

```gdscript
class_name LoreLogPickup
extends PickupBase

var _collected_id: StringName = &""

func _collect(_player: PlayerBase) -> void:
    _collected_id = LogState.collect_next()

func _get_dialog_text() -> String:
    if _collected_id == &"":
        return ""  # nothing left in the catalogue - LogState.collect_next() was a no-op
    var entry := LogState.get_entry(_collected_id)
    if entry == null:
        return "Log recovered."
    return "Log recovered: %s" % entry.title
```

- **Double-count safety is `LogState`'s job, already built and tested**: `collect_next()` only
  ever flips one flag from false to true and is a no-op once the catalogue is exhausted
  (`test_log_state.gd::test_collect_next_is_idempotent_once_everything_is_collected`). This
  pickup's own boundary case (below) proves that a *second* `LoreLogPickup` instance colliding
  with the player after the catalogue is already exhausted collects nothing and shows no
  notification — it does not reimplement any collected-state tracking of its own.
- **Single-physical-pickup double-count** (the same `Area2D` firing `body_entered` twice) is
  already excluded by `PickupBase._on_body_entered()`, which `queue_free()`s the node
  unconditionally after one collection — no change needed there.
- Empty dialog text (`""`) is deliberate, not a bug: `PickupBase._show_notification()` already
  skips showing anything for an empty string, so a log record collected after 100% completion is
  silently removed with no message — matching the "no-op" contract `LogState`'s own docstring
  states.
- No inspector enum, no id lookup table — deliberately simpler than the two siblings it's modeled
  on, because there is nothing to configure.

### Rejected alternative

Giving `LoreLogPickup` an `@export var entry_id: StringName` (naming a specific entry, mirroring
`ShipModuleUnlockerPickup`'s `module_id`) was considered and rejected: `LogState.collect_next()`
has no id parameter and is explicitly designed to keep the reading order independent of world
placement (see its docstring). Adding an id to the pickup would require a second entry point on
`LogState` that nothing else needs, duplicating a decision `LogState` already made.

### Scene

`global/pickups/scenes/lore_log_pickup.tscn` — copy the shape of
`global/pickups/scenes/weapon_mode_unlocker_pickup.tscn`: `Area2D` root (`collision_layer = 16`,
`collision_mask = 4`, script attached), `Sprite2D` child with the new texture, `CollisionShape2D`
child with a `CircleShape2D` (radius 8, scaled to match sprite size, same as siblings).

### Art

One new sprite, `global/assets/sprites/lore_log.png` — a small glowing sci-fi datapad/tablet, top-
down orthographic (per `pixel-art-generation` skill), sized like the other pickup icons (64×64,
matching `ship_module_unlocker.png`/`upgrade_1.png`). Generated via `create_map_object` (transparent
by construction, per the skill's tool table).

## Build sequence

1. Generate and visually verify the sprite (`pixel-art-generation` skill: look at it upscaled,
   confirm no side face visible, confirm transparency).
2. Write `tests/unit/test_lore_log_pickup.gd` (failing first — script doesn't exist yet).
3. Write `global/pickups/lore_log_pickup.gd`.
4. Build `global/pickups/scenes/lore_log_pickup.tscn` wiring the script + sprite + collision shape.
5. Run the GUT suite, confirm the new test passes and nothing else regresses.
6. `bash /agent/verify.sh`.

Each step is independently checkable; 2-4 are the only steps that touch game code.

## Test plan

New file `tests/unit/test_lore_log_pickup.gd` (unit — no scene loading, matches
`test_dialog_player.gd`/`test_log_state.gd`'s pattern of exercising the live autoload directly).
Reuses `tests/unit/fixtures/log_entries/` (3 entries: alpha/beta/gamma, already used by
`test_log_state.gd`) by pointing the live `LogState.catalogue_dir` at it for the duration of the
test, exactly like `test_weapon_unlock_sources.gd` snapshots/restores `UpgradeState._unlocked`
around the live autoload.

- `before_all`: `SaveSandbox.capture()`, snapshot `LogState.catalogue_dir` and `LogState._collected`.
- `before_each`: point `catalogue_dir` at the fixture dir, `SaveSandbox.clear_all()`,
  `_load_catalogue()` + `_load()` so each test starts from a clean, known 3-entry catalogue.
- `after_all`: restore `catalogue_dir` and `_collected`, reload, `SaveSandbox.restore()`.

Cases:

1. **Colliding with the pickup collects the next entry and advances `LogState`.**
   Instantiate `LoreLogPickup`, call `_collect(player_stub)` directly (`PlayerStub.spawn()`),
   assert `LogState.collected_count() == 1` and `LogState.is_collected(&"entry_beta")` (lowest
   sequence in the fixture set).
2. **The notification names the entry.** After the same collect, assert
   `pickup._get_dialog_text()` contains `"Test Entry Beta"` (the fixture's title).
3. **Boundary — collecting after the catalogue is exhausted does not double-count.** Drain the
   3-entry fixture catalogue via three separate `LoreLogPickup` instances (or three direct
   `LogState.collect_next()` calls plus one pickup), then collide a fourth `LoreLogPickup` with
   the player: assert `LogState.collected_count()` is unchanged (still 3, never 4) and
   `_get_dialog_text()` returns `""` (no false notification).
4. **`_on_body_entered` end-to-end**: add the pickup as a child of the test tree
   (`add_child_autofree`), call `_on_body_entered(player_stub)` (the real `PickupBase` signal
   handler, not `_collect` directly) once, and assert the pickup is queued for deletion
   (`is_queued_for_deletion()`) and `LogState.collected_count() == 1` — proves the wiring through
   `PickupBase`, not just the overridden hooks in isolation. Immediately after, call
   `DialogPlayer.skip_dialog()` and assert `DialogPlayer.is_active == false`, so the
   `await _box.line_finished` inside `DialogPlayer.play()` actually resolves before the test ends
   instead of leaving a permanently-suspended coroutine.

## Risks

- The live `DialogPlayer` autoload starts an async `play()` when `_on_body_entered` runs (test
  case 4), and its non-auto-mode branch awaits `_box.line_finished`, which nothing but player
  input, `DialogBox.advance()`/`close_now()`, or `DialogPlayer.skip_dialog()` ever emits. Case 4
  must call `DialogPlayer.skip_dialog()` before the test ends to resolve that await — otherwise
  it leaves a suspended `GDScriptFunctionState`, the same leak class `tests/README.md` and
  `scripts/check-test-leaks.sh` document for `LevelDirector` (invisible to the gate's `FATAL`
  regex, reported only at process exit) and leaves `DialogPlayer.is_active` stuck `true` for the
  rest of the suite. Run `scripts/check-test-leaks.sh` once this test is written, per CLAUDE.md's
  instruction to run it "after touching anything that awaits."

## Out of scope

- Placing any `LoreLogPickup` instance in `sector_hub.tscn` — a later task in this epic
  (`test-logs-on-the-open-space-map-prove-both-log-types-work-en...`) owns creating real
  `LogEntryResource` catalogue content and placing pickups in the world to demonstrate it.
- The ESC-menu Lore Logs section (separate task).
- Information logs (one-time, non-persisted) — separate task, separate pickup/interactable shape.
