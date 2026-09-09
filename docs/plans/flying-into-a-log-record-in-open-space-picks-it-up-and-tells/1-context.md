# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/pickups/pickup_base.gd` | `Area2D` base: on `body_entered` from group `"player"`, calls `_collect(player)`, then `_get_dialog_text()`, shows a non-blocking `DialogPlayer` line if non-empty, `queue_free()`s. | This is the entire pickup mechanism. The new pickup only overrides the two hooks. |
| `global/pickups/ship_module_unlocker_pickup.gd` / `weapon_mode_unlocker_pickup.gd` | Two existing siblings: inspector-driven, one autoload call in `_collect()`, entry-derived text in `_get_dialog_text()`. | The exact shape to copy. `weapon_mode_unlocker_pickup.gd`'s docstring literally says "see that file for the pattern". |
| `global/pickups/scenes/*.tscn` (9 existing) | `Area2D` root, `collision_layer = 16`, `collision_mask = 4`, `Sprite2D` child, `CollisionShape2D` child with a `CircleShape2D`. | Scene shape to copy for `lore_log_pickup.tscn`. |
| `global/autoloads/log_state.gd` | Already built (done task `every-log-record-i-find-stays-found...`). Autoload `LogState`. `collect_next()` grants the lowest-`sequence` uncollected `LogEntryResource` and returns its id, or `&""` if none remain — explicitly designed as a no-op for "an anonymous pickup firing this after 100% completion". `get_entry(id)` returns the `LogEntryResource` (has `.title`, `.body`). | This pickup is a pure consumer: one `collect_next()` call, one `get_entry()` lookup for the notification text. No new persistence logic needed — it already exists and is tested in `tests/unit/test_log_state.gd`. |
| `global/resources/logs/log_entry_resource.gd` | `id`, `title`, `body`, `sequence` fields on a plain `Resource`. | `title` is what the notification names. |
| `global/autoload/dialog_player.gd` (autoload `DialogPlayer`) | `is_active`, `play(script)`. `PickupBase._show_notification()` already builds the `DialogScriptResource`/`DialogLineResource` and calls this — nothing new needed here. | Confirms "one-line notification, non-blocking" is already handled by the base class. |
| `tests/helpers/player_stub.gd` | Minimal `PlayerBase` stand-in with the components `PlayerBase._setup_components()` expects, no scene/input needed. | Used to call `_collect(player)` directly in a unit test without physics/collision. |
| `tests/helpers/save_sandbox.gd` | Captures/restores the `user://*.cfg` files every persistent autoload (incl. `LogState`) writes, so tests don't leak state into later runs or the real save. | Required in any test that calls `LogState.collect_next()` against the live autoload. |
| `tests/unit/fixtures/log_entries/` (+ `log_entries_duplicate/`) | 3 fixture `LogEntryResource` `.tres` files already used by `test_log_state.gd`, pointed at via `LogState.catalogue_dir` override. | Reused as-is for this pickup's unit test — no new fixtures needed. |
| `tests/integration/test_weapon_unlock_sources.gd`, `test_module_unlock_sources.gd` | Show the pattern for temporarily overriding a live autoload's mutable state in `before_all`/`before_each` and restoring it in `after_all`, on top of `SaveSandbox`. | Same pattern applies to swapping `LogState.catalogue_dir` for the duration of this pickup's test. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `PickupBase` | The entire collection/notification/cleanup mechanism. Do not reimplement any part of it. |
| `LogState.collect_next()` / `get_entry()` | The entire "advance progress, don't double count" logic, already tested. The pickup must not touch `_collected`/`_catalogue` itself. |
| `weapon_mode_unlocker_pickup.gd` | Closest sibling in shape: one field read in `_collect()`, entry-derived text in `_get_dialog_text()`, a small `res://…` art path. Model for `lore_log_pickup.gd`, except this pickup needs **no** inspector `@export` at all — it is anonymous by design (`LogState.collect_next()` takes no id), so it is even simpler than its siblings. |
| `global/pickups/scenes/weapon_mode_unlocker_pickup.tscn` | Scene structure (`Area2D` + `Sprite2D` + `CollisionShape2D`, layer 16 / mask 4, `CircleShape2D` radius 8 scaled up) to copy verbatim for `lore_log_pickup.tscn`. |
| `tests/helpers/player_stub.gd`, `tests/helpers/save_sandbox.gd`, `tests/unit/fixtures/log_entries/` | Everything a unit test needs; nothing new to fabricate. |

## Conventions that constrain this

- Pickups live in `global/pickups/` (script) + `global/pickups/scenes/` (scene), not under `open_space/` — they're shared infrastructure, per the 9 existing siblings.
- `assault/`/`open_space/` art is strict top-down orthographic (`pixel-art-generation` skill), even though this asset lives under `global/assets/sprites/` like its siblings (`ship_module_unlocker.png`, `upgrade_1.png`).
- Never hand-type or copy a `uid://` (`CLAUDE.md`); leave scene `uid=` off if minting one is not worth a headless round trip, matching `armor_tank_pickup.tscn`-style older scenes that have none, or mint one properly.
- Signal arity / logging conventions don't apply — this pickup declares no new signals and has no per-frame logging.
- This task's scope is **only** the pickup mechanism + its own unit test, per the epic breakdown: a separate task (`log-records-can-be-placed-in-assault-and-infiltration-missio...`, `test-logs-on-the-open-space-map-prove-both-log-types-work-en...`) owns placing instances in the sector hub / authoring real `LogEntryResource` content. This task does not add a `test_log_unlock_sources.gd`-style hub-invariant test (there is nothing yet to place, and no catalogue of "expected" placements — unlike ship modules/weapons, a lore log is anonymous, so there is no per-id placement invariant to check).
