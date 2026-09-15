# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `open_space/scenes/levels/sector_hub.tscn` | The sector hub scene: player ship, two planets, a space station, an `EnemyContainer`, and 19 pickup instances (health/armor/shield/module-unlocker/weapon-unlocker) clustered in a row around `y = -212` to `y = -515`, `x = -280` to `519`. | Where every log record in this task gets placed, as sibling scene-instance nodes — the exact pattern the 19 existing pickups already establish. |
| `global/autoloads/log_state.gd` (autoload `LogState`) | `total_count()` is derived by scanning `catalogue_dir` (`res://global/resources/logs/entries`, currently **empty — the directory does not exist yet**) for `LogEntryResource` `.tres` files. `collect_next()` grants the lowest-`sequence` uncollected entry. | This task is what puts the first real content in that directory. `total_count()` after this task must equal the number of `LoreLogPickup` instances placed (see Design in `3-plan.md`), which is the "catalogue total matches what is placeable" success criterion in the task body. |
| `global/resources/logs/log_entry_resource.gd` | `LogEntryResource`: `id`, `title`, `body` (`@export_multiline`), `sequence`. | The `.tres` shape for each new catalogue entry. |
| `global/interactables/info_log_interactable.gd` + `global/interactables/scenes/info_log_interactable.tscn` | Built and shipped (`33f8303`). `Area2D`, `collision_layer = 2`, `collision_mask = 4`, one `@export_multiline var message`, re-readable, never touches `LogState`. Already placed once each in `assault/scenes/levels/edelia/1/level_1.tscn` and `infiltration/scenes/levels/TestIsometricScene.tscn` (`ad4d5d7`) — same node name `LogRecord`, same instancing pattern this task reuses for information logs in the hub. | The information-log half of this task is pure placement — no new code. |
| `global/pickups/pickup_base.gd` | `Area2D` base every pickup subclasses: on `body_entered` from group `"player"`, calls `_collect(player)`, then `_get_dialog_text()`, shows a non-blocking `DialogPlayer` notification if non-empty, `queue_free()`s. | `LoreLogPickup` (new) is a third one-line subclass of this, alongside `ShipModuleUnlockerPickup`/`WeaponModeUnlockerPickup`. |
| `global/pickups/weapon_mode_unlocker_pickup.gd`, `global/pickups/scenes/weapon_mode_unlocker_pickup.tscn` | Closest sibling in shape: one `_collect()` call into an autoload, entry-derived `_get_dialog_text()`. Scene: `Area2D` root, `collision_layer = 16`, `collision_mask = 4`, `Sprite2D` + `CollisionShape2D` (`CircleShape2D`, radius 8, scaled). | Template for `lore_log_pickup.gd` / `.tscn`. |
| `open_space/scenes/entities/player/player_ship.tscn` | `collision_layer = 4` (line 215). | Confirms the hub player is already detectable by both `InfoLogInteractable` (`collision_mask = 4`) and every `PickupBase` (`collision_mask = 4`) — no new wiring needed, unlike the infiltration-player fix `ad4d5d7` had to make. |
| `global/ui/pause_menu/lore_log_list.gd` / `.tscn` | ESC-menu Lore Logs reader (`ba50c3a`), already built and tested against `LogState.all_ids()`/`get_entry()`. | Consumes whatever catalogue this task authors — no changes needed here, but it is the UI the task body means by "see the ESC section fill up". |
| `tests/integration/test_project_load_integrity.gd` | Loads every `.tscn`/`.tres`/`.gd` outside `addons/` via `PackedScene.get_state()` and fails on any engine error/warning. | Will load the modified `sector_hub.tscn` and the new `.tres` catalogue files — the gate this task must stay green against. |
| `tests/integration/test_module_unlock_sources.gd`, `test_weapon_unlock_sources.gd` | Precedent for an invariant test that checks placement count against a catalogue/id list. | Model for this task's own "placed pickups == catalogue size" boundary test, if one is warranted (see plan). |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `PickupBase` | The entire collection/notification/cleanup mechanism for `LoreLogPickup` — do not reimplement. |
| `LogState.collect_next()` / `get_entry()` / `total_count()` | Already built and unit-tested (`tests/unit/test_log_state.gd`). This task is a pure consumer + content author, no `LogState` changes. |
| `weapon_mode_unlocker_pickup.gd` / `.tscn` | Exact shape to copy for `lore_log_pickup.gd` / `.tscn`, per the sibling task's `3-plan.md` (already designed and twice-reviewed — see below). |
| `InfoLogInteractable` + its scene | Used unmodified; only new scene-instance placements are added. |
| `tests/helpers/player_stub.gd`, `tests/helpers/save_sandbox.gd` | Unit-test scaffolding for the new `LoreLogPickup` unit test, same pattern as `tests/unit/test_info_log_interactable.gd`. |

## Conventions that constrain this

- Pickups live in `global/pickups/` (script) + `global/pickups/scenes/` (scene) — shared
  infrastructure, not `open_space/`-local, per the 9 existing siblings and `CLAUDE.md`.
- Log placements in a scene are plain scene-instance nodes added as children of the scene root,
  exactly like the 19 pickups already in `sector_hub.tscn` and the two `LogRecord` nodes already
  placed in `level_1.tscn` / `TestIsometricScene.tscn`.
- `assault/`/`open_space/` art is strict top-down orthographic (`pixel-art-generation` skill) —
  applies to the one new sprite (`lore_log.png`), generated via `create_map_object`.
- Never hand-type or copy a `uid://` (`CLAUDE.md`); mint one with `ResourceUID.create_id()` or
  leave the reference UID-less.
- Placeholder text must be real, in-world flavour text, not "Lorem ipsum" — explicit in the task
  body.
- `tests/README.md`'s `user://` save-sandbox and coroutine-leak traps apply to any new test
  touching `LogState` or `DialogPlayer`.

## Reused design: `LoreLogPickup`

The sibling task `flying-into-a-log-record-in-open-space-picks-it-up-and-tells` designed and
partially reviewed this exact class. Its `3-plan.md` design section (the `LoreLogPickup` script,
scene shape, and sprite spec) is carried into `3-plan.md` below **unchanged** — it was never the
part either review round objected to. Both rounds objected only to that plan's **test case 4**
(driving a real `DialogPlayer.play()` coroutine end-to-end inside a unit test, which leaves a
permanently-suspended `GDScriptFunctionState` — the same class of leak `check-test-leaks.sh`
exists to catch). Round 2's review named a precise fix:

> don't drive the real `play()` coroutine in case 4 at all. Either (a) pre-set
> `DialogPlayer.is_active = true` before calling `_on_body_entered()` ... or (b) drop case 4 back
> to asserting via `_collect()` + `_get_dialog_text()` only, matching
> `test_weapon_unlock_sources.gd`'s precedent.

`3-plan.md` below applies option (b) — it is the simpler of the two and matches the precedent
`InfoLogInteractable`'s own test suite already set (its header cites the exact same stuck review
and avoids driving `DialogPlayer.play()` for the same reason). `PickupBase._on_body_entered`'s
generic signal-to-`_collect`-to-`queue_free` plumbing is already covered by
`tests/unit/test_pickup_base.gd` and does not need re-proving per subclass.
