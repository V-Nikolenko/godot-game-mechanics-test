# Decision log — Fast weapon and sub-weapon switching using loadouts

Shared across every phase of this idea. Append only; each phase owns its own section.

## Phase 1 - Weapon loadout: 3 Main + 3 Sub slots with Q/E cycling and persistence (2026-09-28)

Plan: `docs/plans/cmukamteg00e9p52xi2fuoxrx/3-plan.md`. Spec: `EPIC_01_WEAPON_LOADOUT_UI.md`.

**Architecture**
- EPIC_01's "LoadoutManager" is the autoload **`LoadoutState`** (`global/autoloads/loadout_state.gd`),
  named to match the house `<Thing>State` store convention and registered after `UpgradeState`.
  It stores **ids only** and never touches weapon nodes. Weapon mechanics stay on `WeaponState`
  (main) and `RocketState` (sub), which *consume* the loadout.
- `enum Kind { MAIN, SUB }`, `SLOT_COUNT = 3`, `&""` = empty slot (same sentinel as `ShipModuleState`).
- Signals: `slot_changed(kind: int, slot: int, id: StringName)`,
  `active_changed(kind: int, id: StringName)`.
- API: `get_slot`, `get_slots`, `get_active_index` (-1 = none), `get_active_id`, `is_available`,
  `check_assign -> Reject`, `assign`, `clear`, `cycle`, `set_active_slot`.
  `enum Reject { OK, BAD_SLOT, UNKNOWN, WRONG_KIND, LOCKED, DUPLICATE, LAST_MAIN }`.

**Sub-weapon ids**
- Sub-weapons are identified by `StringName` ids from a `SubWeaponResource` catalogue
  (`assault/scenes/player/weapons/sub_weapons/`: `id`, `display_name`, `icon` (menu), `hud_icon`;
  `const ALL_IDS`; `static load_id(id)`). Today: `&"missile_barrage"`, `&"homing_missile"`.
  `RocketState._type: int` is gone; it dispatches on id.
- **For the weapon epic:** add new sub-weapons by adding a `.tres` + an `ALL_IDS` entry + a
  dispatch branch in `RocketState` (or whatever replaces it). New main weapons keep using
  `UpgradeState.ALL_IDS` + `assault/scenes/player/weapons/modes/`. Sub-weapons have **no unlock
  progression**; "available" = "in the catalogue", behind the single seam
  `LoadoutState.is_available(Kind.SUB, id)` — replace that when sub unlocks arrive.

**Rules**
- Duplicates in the same kind are **rejected** (no swap). Kinds are disjoint (a main id is never
  valid in a sub slot).
- At least one Main slot must stay occupied through the menu (`clear` → `LAST_MAIN`); all Sub
  slots may be empty.
- Active index always points at an occupied slot, or -1. Assigning outside the active slot does
  not change the active weapon.
- E → `LoadoutState.cycle(MAIN)`, Q → `LoadoutState.cycle(SUB)`: next occupied slot, wraps, instant,
  no signal on a no-op. No mouse wheel, no hotkeys, no switch delay.

**Persistence**
- `user://loadout.cfg`, `[loadout]`: `version=1`, `main_0..2`, `sub_0..2` (String, `""` empty),
  `main_active`, `sub_active` (int). Active indices are persisted (deliberate extension beyond §9).
- Load **invalidates, never substitutes, never grandfathers**: unknown / wrong-kind / locked /
  duplicate / wrong-type entries load empty with `push_warning`. Load never writes the file.
- Seed only when the file is missing: Main = first up-to-3 unlocked mains, Sub = first up-to-3
  catalogue subs. Live unlocks never auto-fill slots.
- `user://loadout.cfg` is in `tests/helpers/save_sandbox.gd` PATHS.

**UI**
- Menu stays Node2D/Sprite2D with the hand-rolled cursor (no Control-focus port).
  New `LoadoutSlotsPanel` (six frames, module frame language, `icon_empty_slot.png` for empties).
  Assignment is slot-first (like `ModuleList`); list confirm in browse mode does nothing.
  Focus states `LOADOUT` / `LISTS` / `ASSIGNING`.
- Empty main in flight → `WeaponState.weapon_changed(null)`, chip shows `icon_empty_slot.png`.
  `EventBus.player_rocket_changed(icon)` / `weapon_changed(icon)` arities are unchanged.

**Deferred**
- Individual new weapons (Harpoon, Drones, Null Burst, Capacitor Gun, Minecaster…) → weapon epic.
- Sub-weapon unlocks, a save-rename migration map (`version` key exists for it), gamepad bindings,
  duplicate support/swap-on-assign.
- New PixelLab art: none planned; generated only if the layout mock-up shows a genuine gap.
