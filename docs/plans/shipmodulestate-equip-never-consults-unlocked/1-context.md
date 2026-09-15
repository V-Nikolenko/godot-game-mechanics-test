# Context — ship module unlock gate

## Modules and files involved
| Path | What it does | Why it matters here |
|---|---|---|
| `global/autoloads/ship_module_state.gd` | Persists equipped + unlocked module id per slot to `user://ship_modules.cfg`. | `equip()` (l.74) never reads `_unlocked`; `is_unlocked()` (l.70) has **no non-test caller** anywhere in the project. |
| `global/pickups/ship_module_unlocker_pickup.gd` | `_collect()` calls `ShipModuleState.unlock(slot, id)` (l.23). | The only thing in the game that writes unlock state. Today collecting it changes nothing the player can observe. |
| `global/ui/player_menu/module_list.gd` | Overlay list of the modules for one slot; `open()` (l.30) populates straight from `SLOT_MODULES`, `confirm()` (l.67) emits the id. | Where "locked" has to become visible; it currently lists every catalogue entry as equippable. |
| `global/ui/player_menu/module_list_item.gd` | One row: icon, name, cursor/selected tints; already has a `_GREY_MODULATE` used for the "None" row (l.10, l.47). | Gives us a locked appearance without new art. |
| `global/ui/player_menu/player_menu.gd` | `_open_module_list()` (l.165) / `_on_module_confirmed()` (l.180) wire the list to `ShipModuleState.equip`. | Confirms the menu is the only equip path in the game. |
| `global/ui/player_menu/ship_modules_panel.gd` | Draws the four slot icons from `get_equipped`. | Unaffected — it reads equipped, not unlocked. |
| `assault/scenes/player/player_fighter.gd` l.29-35, `open_space/scenes/entities/player/player_ship.gd` l.56-62 | Re-apply equipped modules on spawn and follow `module_equipped`/`module_unequipped`. | Any change to what can be equipped propagates here for free; no change needed. |
| `tests/unit/test_ship_module_state.gd` | Characterization suite; `test_equipping_does_not_require_unlocking` (l.117) pins today's hole. | That test is the one this task exists to flip. |

## Existing code to reuse
| Path | What it gives us |
|---|---|
| `global/autoloads/upgrade_state.gd` | The house pattern for exactly this problem, already shipped for weapons: `is_unlocked(id)` (l.38), `unlocked_ids()` (l.56) filtered in catalogue order, a first-run starter grant in `_ready()` (l.34-37), and `unlock_all()` (l.62) kept for the dev bench. `player_menu._populate_lists()` (l.188) builds the weapon column *only* from `unlocked_ids()`. Mirror the API shape, don't invent one. |
| `ShipModuleState.SLOT_MODULES` | Already the display-ordered catalogue with `&""` first; `unlocked_ids(slot)` can filter it in place, same as `UpgradeState.unlocked_ids()` walks `ALL_IDS`. |
| `ModuleListItem._GREY_MODULATE` / `_update_modulate()` | Locked rows can reuse the existing dim treatment; no new sprite, no PixelLab. |
| `ModuleList._descs` + `_description_lbl` | Per-row description text already exists, so "how do I get this" can be said in words on the row the cursor is on. |
| `tests/helpers/save_sandbox.gd` | Keeps the new save-migration test off the real `user://ship_modules.cfg`. |

## Conventions that constrain this
- Signals declare exactly what they emit; `module_equipped(slot, module_id)` etc. stay as they are — no new signal unless the UI genuinely needs one.
- Autoloads validate on the way *in* and on `_load()`, warning with `push_warning` and dropping bad data (see `UpgradeState._load`, and `ShipModuleState._load` l.104-122 which already drops unknown ids).
- Tests are GUT under `tests/`; this file is characterization, so a deliberate behaviour change means **rewriting the pinned test and saying in a comment that the behaviour changed on purpose** rather than leaving a stale CHARACTERIZED note.
- No git commits to `main`; docs must be updated via `updating-project-docs` because this changes what a documented autoload does.

## What the code says about intent
- `docs/superpowers/plans/2026-05-26-pickup-system.md` created the module unlocker pickup in the same pass that removed `UpgradeState`'s debug `unlock_all()` call from `_ready()`, with the note "Now that pickups are the unlock path". Weapons got the gate; modules got the pickup and the store but never the gate.
- `docs/architecture/modules/global.md` l.72 describes `ShipModuleState` as "Equipped + unlocked module id per slot", and the inline comment on `_unlocked` (l.39) reads "equipping doesn't require unlocking" — the doc records the hole rather than a decision.
- Every one of the 15 modules is a pure bonus (e.g. `ShootingModule` adds +65% fire rate; `WarpModule` sets a flag read by `DashState`). Nothing in baseline flight, shooting or dashing depends on a module, so a player with an empty loadout is still fully playable. That is what makes gating safe.

## Open questions for research
1. Do shipped games hide locked items or show them greyed out, and what does each choice cost?
2. When a game adds a gate to something previously ungated, what happens to existing saves — is grandfathering the norm?
3. Is a zero-item starting loadout acceptable, or do games always seed one?
