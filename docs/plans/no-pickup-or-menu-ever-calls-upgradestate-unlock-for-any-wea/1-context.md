# Context

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/autoloads/upgrade_state.gd` | Persistent weapon-mode unlock store (`user://upgrades.cfg`). `ALL_IDS` = `default, sniper_shot, spread, gatling, mining_laser`. `_ready()` seeds only `&"default"` on a fresh profile. | `unlock()` has exactly one caller project-wide: `unlock_all()` in the same file, which nothing invokes. Four of five modes are unreachable. |
| `assault/scenes/player/states/weapon_state.gd` | Loads every `<id>.tres`, but `_cycle()` (`:138`) and `select_weapon()` (`:164`) only walk/accept `UpgradeState.unlocked_ids()`. | The consumer is already correct — it will pick the new modes up the moment they unlock. No change needed. |
| `global/ui/player_menu/player_menu.gd` | Main-weapon column is `UpgradeState.unlocked_ids()` (`:125`, `:190`, `:210`), icons from `_WEAPON_ICONS` (`:11-17`). | Renders a one-row column today. `_WEAPON_ICONS` is keyed `&"piercing"` — **not an id in `ALL_IDS`** — so the icon is dead and `sniper_shot` has none. Only visible once modes are unlockable. |
| `global/pickups/ship_module_unlocker_pickup.gd` + `scenes/ship_module_unlocker_pickup.tscn` | `PickupBase` subclass, inspector enums for slot+module, `_collect()` calls `ShipModuleState.unlock()`, `_get_dialog_text()` names the module. | **The pattern to mirror.** Area2D layer 16 / mask 4, CircleShape2D r=8 scaled 3.53. |
| `open_space/scenes/levels/sector_hub.tscn` | Hub world. Carries a 3-row pickup bench: generic pickups at y≈-215, module unlockers at y=-315 and y=-415, x stepping 100 from -280. | Where 14 module unlockers already live; the obvious home for weapon unlockers. |
| `tests/integration/test_module_unlock_sources.gd` | INVARIANT: every catalogue module has exactly one unlocker in the hub, and none is slot-mismatched. Instantiates the hub without adding it to the tree. | **The test to mirror.** |
| `tests/integration/test_weapon_mode_catalogue.gd` | Asserts every `<id>.tres` in `weapons/modes/` has an `ALL_IDS` entry and vice versa. | Already pins file↔id; says nothing about reachability. The gap this task fills. |
| `tests/unit/test_upgrade_state.gd` | Characterization over `UpgradeState`, incl. `unlock_all()` and the save sandbox. | Must keep passing; `_ready()` seeding is pinned there. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/pickups/pickup_base.gd` | `body_entered` → group check → `_collect(player)` → optional dialog → `queue_free()`. Subclass overrides two methods; no new plumbing. |
| `global/pickups/scenes/ship_module_unlocker_pickup.tscn` | Node *layout* + collision layer/mask (16/4) + `CircleShape2D` r=8 for a hub pickup. Copy the layout, **not** its `scale` — that is tuned to a 64×64 sprite. |
| `global/assets/sprites/upgrade_1.png` | An existing **48×48** weapon-crate sprite (IHDR `48 48 8 3`, has `tRNS`) **referenced by nothing in the project**, uid `uid://dptqytf5g71or`. Reusing it spends no PixelLab allowance. 48×48 pickups in `global/pickups/scenes/` all use `CollisionShape2D` scale `3.111`, not the 64×64 module unlocker's `3.531701`. |
| `assault/scenes/player/weapons/modes/*.tres` | `WeaponModeResource.display_name` ("Sniper Shot", "Spread", "Gatling", "Mining Laser") for the pickup dialog line — no hand-typed names. |
| `global/assets/sprites/player_menu_ui/ship_menu_ui/weapon_icons/icon_ship_weapon_pierce.png` | Already imported (uid `uid://yu1cwveum40p`); currently reachable only under the dead `&"piercing"` key in `_WEAPON_ICONS`, which `3-plan.md` §4 deletes in favour of `WeaponModeResource.icon`. |

## Conventions that constrain this

- **Never hand-type a `uid://`.** New `.tscn` UID must come from the headless
  `ResourceUID.create_id()` snippet in `tests/README.md` (or be omitted entirely).
- Inspector-facing pickup selection is an **enum**, not a raw StringName export
  (`ShipModuleUnlockerPickup` sets that precedent — no typo-able strings in the scene file).
- Tests are GUT under `tests/`; anything that loads a scene goes in `integration/`.
- The hub is instantiated-not-added in tests: its `_ready()` spawns drones and builds a HUD.
- `docs/architecture/modules/global.md` documents `global/pickups/` and must be updated
  (`updating-project-docs`) since this adds a pickup type.

## What is *not* broken — and what is

> **Corrected after review round 1.** This section originally read "`WeaponState` and `PlayerMenu`
> are both already unlock-driven and correct… No consumer needs redesign." Half of that is wrong.

`WeaponState` **is** already unlock-driven and correct: `_load_modes()` (`:31-37`) walks `ALL_IDS`,
and `_cycle()` (`:137-152`) / `select_weapon()` (`:163-166`) read `unlocked_ids()` / `is_unlocked()`
live, every time. It picks a newly unlocked mode up with no change.

`PlayerMenu` **is not**. `_populate_lists()` (`player_menu.gd:189`) has one caller,
`connect_states()` (`:47`), whose only callers are `mission_hud.gd:19/24/43` inside HUD `_ready()`.
`_toggle()` never repopulates. So the main-weapon column is built once per scene load, and an
unlock that lands mid-scene — which is exactly what this task introduces — is invisible until the
next scene. It also makes `_init_cursor()`/`_confirm_selection()` (live `unlocked_ids()`) disagree
with `_current_max_row()` (stale `_main_frame.get_count()`), which cannot happen today.

`UpgradeState.unlocked_changed` (`upgrade_state.gd:21`) exists and has **zero** listeners
project-wide — it is the hook for this, unused. See `3-plan.md` §3.

There is also a **second** id→icon map nobody was using: `WeaponModeResource.icon`
(`weapon_mode.gd:11`) is what `WeaponChip` draws (`weapon_chip.gd:26`), and no `modes/*.tres` sets
it, so the in-game HUD chip renders a null texture today. See `3-plan.md` §4.

The **missing source** remains the core of the task, and it is still structurally identical to the
one `ShipModuleState` solved with `ShipModuleUnlockerPickup` + `test_module_unlock_sources.gd`.
