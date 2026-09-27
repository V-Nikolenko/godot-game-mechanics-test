# Context — Weapon loadout: 3 Main + 3 Sub slots with Q/E cycling and persistence

Epic `cmukamteg00e9p52xi2fuoxrx`, research task `cmukamteu00efp52xue91vklz`, 2026-09-27.
Spec: `docs/ideas/cmukal7cu008nmr2xvyvt5ein/EPIC_01_WEAPON_LOADOUT_UI.md` (referred to below as
**EPIC_01**). Everything here was read from the code on `agent/auto-dev` at `60a7d51`; line numbers
are from that commit.

## Requirements from the attached documents

Every concrete requirement in EPIC_01, quoted briefly, with what the code says about it today.

| # | Requirement (EPIC_01 §) | Today in the code | Research needed? |
|---|---|---|---|
| R1 | "3 Main Weapons / 3 Sub-Weapons" loadout (Goal, §6) | No loadout concept. Main column = every `UpgradeState.unlocked_ids()` entry; sub column = two hard-coded rows. | No — design. |
| R2 | Keep the two collections but "move them lower in the menu" (§1) | `MainWeaponFrame` / `SubWeaponFrame` are full-height 153×270 columns at design-space (93,148) and (261,148), `ShipModulesPanel` 270×270 at (488,148) — the whole 640×360 menu is used. | Layout — see *Risks*. |
| R3 | Six loadout frames at the top: `MAIN [1][2][3]`, `SUB [1][2][3]` (§1, §14) | Nothing. | UX (2-research). |
| R4 | Assignment: pick a slot, then a compatible weapon from the list below (§2) | Menu confirm on a main row calls `WeaponState.select_weapon(id)` directly — it picks the **active** weapon; there is no assign step. | UX (2-research). |
| R5 | Main slot accepts only Main weapons; Sub slot only Sub (§2) | Main and sub ids live in unrelated spaces (StringName ids vs positional ints) — no shared type to check. | No. |
| R6 | Empty slots are "a proper visible frame … intentional UI … existing weapon/module frame language" (§3) | Existing empty treatments: `ShipModulesPanel` greys an empty module frame (`_EMPTY_COLOR` 0.4); `ModuleListItem` has `_GREY_MODULATE` for "None"; HUD has an unused `assault/assets/gui/weaponselector/icon_empty_slot.png` (32×32). | Art check — see *Existing code to reuse*. |
| R7 | Loadout frames visually stronger than the lists (§4) | n/a | UX. |
| R8 | `E` cycles Main 1→2→3→1; `Q` cycles Sub 1→2→3→1 (§5); skip empty slots (epic summary) | `E` (`cycle_weapon`) → `WeaponState._cycle()` over **all** unlocked ids (`weapon_state.gd:137`); `Q` (`switch_weapon`) → `RocketState._type = (_type + 1) % 2` (`warhead_missile_shooting_state.gd:40`). | Genre (2-research). |
| R9 | No mouse-wheel cycling, no direct hotkeys (§5) | None exist; nothing to remove. | No. |
| R10 | `LoadoutManager` "or equivalent" owning 3+3 slots, current indices, validation, unlocked refs, persistence, Q/E cycling; "knows what is equipped, not how weapons behave" (§6) | No such system. `ShipModuleState` is the nearest analogue (slot → id + per-slot unlocks + ConfigFile). | Architecture — see *Candidate approaches*. |
| R11 | Duplicates rejected by default unless the game already supports them (§7) | Nothing in the code supports a duplicate: `WeaponState` keys everything by one `_active_id`; `UpgradeState._unlocked` is a set. → **reject** is consistent. | UX of *how* to reject (2-research). |
| R12 | Lower lists = full collection of discovered weapons, browseable, same visual language; "do not duplicate weapon definitions" (§8) | Mains already come from `WeaponModeResource.icon`/`display_name` in `assault/scenes/player/weapons/modes/<id>.tres`. **Subs are duplicated today**: names/icons as parallel arrays in `player_menu.gd:18-22` *and* separate HUD icons in `RocketState` (`warhead_missile_shooting_state.gd:10-11`). | No. |
| R13 | Persist the six slots through the existing save architecture (§9) | Every persistent store is an autoload with its own `user://*.cfg` via `ConfigFile` (8 of them). | Save robustness (2-research). |
| R14 | A saved weapon no longer available → slot loads **empty**, never silently replaced (§9) | Precedent both ways: `UpgradeState._load()` drops unknown ids with `push_warning`; `ShipModuleState._load()` *grandfathers* an equipped-but-locked module (the opposite rule — must not be copied here). | No. |
| R15 | Player can see: selected slot, Main vs Sub, assigned weapon, list item being assigned, empty slots (§10) | Existing tints: cursor = yellow `Color(1.4,1.4,1.0)` on whole row; selected = pink `Color(2.0,0.5,1.2)` on row BG; module hover = green `Color(0.5,1.5,0.5)`; empty = grey. | UX. |
| R16 | Reuse existing icons/frames; PixelLab only for genuinely missing assets, matching style (§11) | See *Existing code to reuse → art*. | Art check. |
| R17 | Tests for 3 main, 3 sub, empty rendering, slot select, compatible/incompatible assign, duplicates, Q, E, persistence, invalid saved refs, behaviour unchanged (§12) | No test exercises `WeaponState` or `RocketState` today. | See *Testing requirements*. |
| R18 | Implementation order §13 (menu → frames → move lists → select → assign → manager → Q/E → persistence → polish → art) | — | The plan may reorder (manager first is more testable); say so explicitly. |
| R19 | Individual weapons (Harpoon, Drones, Null Burst, Capacitor Gun…) out of scope (Goal; epic summary) | Named in EPIC_01's example only. | No — out of scope. |

## Modules and files involved

| Path | What it does | Why it matters here |
|---|---|---|
| `global/ui/player_menu/player_menu.gd` (244 lines) | `PlayerMenu` CanvasLayer overlay. Tab toggles and pauses the tree; WASD cursor over 3 columns (0 main, 1 sub, 2 modules); Space/F confirms. `connect_states(WeaponState, RocketState)` is called by the HUD. Rebuilds on `UpgradeState.unlocked_changed`. | The menu that gets the loadout row. Its cursor model is a flat `(_cursor_col, _cursor_row)` over columns — must become a 2-level focus model (loadout row ↔ lists). Sub-weapon parallel arrays at `:18-22`. `_on_main_weapon_pressed` / `_on_sub_weapon_pressed` (`:236-244`) currently *select the active* weapon. |
| `global/ui/player_menu/player_menu.tscn` | Background + overlay sprites, `ShipLayout` (Node2D, `scale = 2`) holding `MainWeaponFrame`, `SubWeaponFrame`, `ShipModulesPanel`; `ModuleList` overlay. All positions in 640×360 design units ×2. | Layout lives here; everything is `Sprite2D`/`Node2D`, **not** Control containers — no `focus_neighbor`, no `grab_focus`; focus is hand-rolled via `set_cursor`/`set_selected`. |
| `global/ui/player_menu/weapon_frame.gd` / `.tscn` | `WeaponFrame` (Node2D): list column; `populate(names, icons)`, `set_cursor(idx)`, `set_selected(idx)`, `get_count()`. `MAX_ITEMS = 8`, `_ROW_HEIGHT = 30`. Background `weapong_list_frame.png` 153×270. | Reused for the lower full-collection lists. Needs a way to mark a row "already in another slot" / "incompatible" if the plan wants that (it has no locked/dim state today — `ModuleListItem` does). |
| `global/ui/player_menu/weapon_option.gd` / `.tscn` | `WeaponOption` row: 145×27 `weapon_list_item.png` BG, icon at x −59 scaled 0.4, name label. Yellow cursor, pink selected. | Row visual language to reuse. |
| `global/ui/player_menu/ship_modules_panel.gd` / `.tscn` | Module column: 4 fixed 40×30 `menu_ship_modules_item_frame.png` frames with an `Icon` child; grey when empty, green on hover, white when equipped. | **The "module frame language" EPIC_01 §3 asks empty loadout frames to use.** Fixed-slot, grey-when-empty, icon-inside-frame — exactly the loadout-slot shape. |
| `global/ui/player_menu/module_list.gd`, `module_list_item.gd` | Slot-first sub-overlay: confirm on a module slot opens a list; confirm in the list emits `confirmed(id)`, Esc emits nothing and closes. Locked rows (`_LOCKED_MODULATE`) are a defined no-op. | **Existing slot-first assignment flow** — the loadout flow (select slot → pick from list) is the same interaction the player already knows from modules. Its locked-row treatment is the model for "incompatible / already equipped" rows. |
| `assault/scenes/player/states/weapon_state.gd` (`WeaponState`) | Main weapon State. Loads every `UpgradeState.ALL_IDS` `.tres` into `_modes`; `_active_id` defaults `&"default"`; `_cycle()` walks all unlocked ids; `select_weapon(id)` switches with beam release / sniper cancel / cooldown reset; emits `weapon_changed(mode)` + `EventBus.player_weapon_changed`. | Becomes a **consumer** of the loadout: `E` must step main slots instead of the unlocked list. The switch side-effects in `select_weapon` (`:163-174`) must be kept — they are the "behaviour unchanged" contract. |
| `assault/scenes/player/states/warhead_missile_shooting_state.gd` (`RocketState`) | Sub-weapon State. `_type: int` 0 = warhead ("Missiles Barrage"), 1 = homing. `Q` toggles; `special_weapon` launches on a shared `CooldownTimer`. `get_current_icon()` returns 32×32 HUD icons. | Needs stable ids instead of 0/1, driven by the loadout. `_launch_warhead` / `_launch_homing` bodies must stay byte-identical (EPIC_01: mechanics unchanged). |
| `assault/scenes/player/movement_controller.gd` | Emits `action_single_press(key_name)` for `switch_weapon` (Q), `cycle_weapon` (E), `special_weapon`; blocked while `movement_lock_timer` runs (dash). | Q/E routing stays here; no new input actions needed. `_process` pauses with the tree, so Q/E are inert while the menu is open. |
| `global/ui/mission_hud.gd` | Shared HUD for assault + open space. Finds `AttackStateMachine/WarheadMissileShootingState` and `/WeaponState` by path, shows the rocket icon + cooldown overlay in `WeaponContainer`, calls `player_menu.connect_states(...)` (or `(null, null)` with no player). | HUD sub chip must follow the active sub slot — today it already follows `RocketState.weapon_changed(icon)`. |
| `assault/scenes/gui/weapon_chip.gd` (`WeaponChip`) | Main-weapon HUD chip: icon + `display_name` from `WeaponState.weapon_changed(mode)`. | Already follows the active main weapon; needs nothing if `WeaponState` keeps emitting on every change — but must handle "no main weapon" if all main slots can be empty. |
| `global/autoloads/upgrade_state.gd` | Main-weapon unlock set; `ALL_IDS` (5), `STARTING_IDS = [&"default"]`, `unlocked_changed(id)`, `user://upgrades.cfg`. Drops unknown ids on load. | Source of "unlocked main weapons". There is **no lock/revoke API** — an id can only become unlocked. So "no longer available" can arise only from (a) an id removed from `ALL_IDS`/catalogue, (b) a hand-edited or stale `upgrades.cfg`, (c) a future progression rule. |
| `global/autoloads/ship_module_state.gd` | Slot → equipped id + per-slot unlocked list, `user://ship_modules.cfg`, `module_equipped`/`module_unequipped`/`module_unlocked` signals, `equip()` validates slot + catalogue + unlock. | **Closest pattern for the loadout store.** Copy its shape (validated `equip`, per-key ConfigFile, signals) — but *not* its grandfathering in `_load()` (`:150-157`), which is the opposite of EPIC_01 §9. |
| `global/systems/event_bus.gd` | `player_weapon_changed(mode)`, `player_rocket_changed(icon: Texture2D)`. | **No listeners anywhere** except `tests/unit/test_event_bus.gd` (arity pins). Changing `player_rocket_changed`'s payload means updating that test. |
| `assault/scenes/player/player_fighter.tscn`, `open_space/scenes/entities/player/player_ship.tscn` | Both have `AttackStateMachine/WeaponState` and `AttackStateMachine/WarheadMissileShootingState` (+ `CooldownTimer`). | The two consumers; both HUDs (`assault/scenes/gui/hud.tscn`, `open_space/scenes/gui/hud.tscn`) instance `PlayerMenu`. Infiltration has neither. |
| `project.godot` `[autoload]` / `[input]` | 11 autoloads, `UpgradeState` before `ShipModuleState`. Inputs: `switch_weapon` = Q, `cycle_weapon` = E, `toggle_player_menu` = Tab, `menu_*` = WASD, `menu_confirm` = F/Space. | A new autoload must be registered **after** `UpgradeState` (it reads it in `_ready`). No input changes. |
| `tests/helpers/save_sandbox.gd` | `PATHS` list of every `user://*.cfg`. | A new save file **must** be added here or tests leak into the player's profile. |

## Existing code to reuse

| Path | What it gives us |
|---|---|
| `global/autoloads/ship_module_state.gd` | Template for a slot store: `SLOTS` const, validated `equip()`, `_save()`/`_load()` over `ConfigFile`, per-key `push_warning` on unknown ids, signals with explicit arity. |
| `global/autoloads/upgrade_state.gd` | `is_unlocked(id)`, `unlocked_ids()` (catalogue order), `unlocked_changed` — the main-weapon availability source. `is_known_id()` static. `STARTING_IDS`-on-empty-store idiom for seeding a fresh profile. |
| `assault/scenes/player/weapons/weapon_mode.gd` (`WeaponModeResource`) + `modes/*.tres` | Single id → `display_name` + `icon` map for mains (`test_weapon_unlock_sources.gd` asserts every mode has an icon). A sub-weapon catalogue should follow the same shape (`id`, `display_name`, `icon`) so sub definitions stop being duplicated (R12). |
| `WeaponState.select_weapon(id)` (`weapon_state.gd:163`) | Already the correct "switch main weapon" primitive (beam release, sniper cancel, cooldown reset, emit). Loadout cycling can call it instead of `_cycle()`'s own copy of the same side-effects. |
| `RocketState.select_sub_weapon(type)` (`:30`) | Same for subs, once it takes an id instead of an int. |
| `global/ui/player_menu/module_list.gd` + `module_list_item.gd` | Slot-first pick-from-list interaction; `confirmed`/`cancelled` signals; locked-row no-op + `_LOCKED_MODULATE`/`_LOCKED_CURSOR_MODULATE` tints. |
| `global/ui/player_menu/ship_modules_panel.gd` | Fixed-frame slot rendering: frame sprite + `Icon` child, `_EMPTY_COLOR` grey, `_HOVER_COLOR`, `set_cursor(row)`. A `LoadoutSlotsPanel` can be the same thing laid out 3 + 3 horizontally. |
| `WeaponFrame` / `WeaponOption` | Lower collection lists, unchanged API; rows ≤ 8. |
| **Art already in the repo (no PixelLab needed for the base case):** `global/assets/sprites/player_menu_ui/ship_menu_ui/menu_ship_modules_item_frame.png` (40×30 rounded-octagon teal frame — the module frame language), `assault/assets/gui/weaponselector/frame_center.png` / `frame_left.png` / `frame_right.png` (40×40 teal HUD frames), `assault/assets/gui/weaponselector/icon_empty_slot.png` (32×32 dark dotted empty slot, **currently unused**), main icons `.../weapon_icons/*.png` (67×67), sub icons `.../sub_weapon_icons/*.png` (67×67), HUD sub icons `assault/assets/gui/weaponselector/icon_{warhead,homing}_missiles.png` (32×32). Palette: dark `#001010`-ish background with teal `#008F7A`-ish outlines. | Enough for six slot frames (module item frame, scaled or used as-is) with an empty state (`icon_empty_slot.png` or grey tint). A **"MAIN"/"SUB" header plate** or a slot frame sized for 67×67 icons is the only plausibly missing asset; the plan should first try `Label` text + existing frames. |
| `tests/helpers/save_sandbox.gd`, `tests/integration/test_module_list_lock.gd`, `test_weapon_unlock_sources.gd` | Established patterns for sandboxing the file *and* snapshot/restoring a live autoload's in-memory dict (`before_all`/`after_all`), and for driving a real `player_menu.tscn` (`connect_states(null, null)`). |
| `tests/unit/test_ship_module_state.gd`, `tests/unit/test_upgrade_state.gd` | Tree-less `Script.new()` store tests — round-trip save/load, unknown-id rejection. The loadout store's unit test should mirror these. |

## Conventions that constrain this

- **Autoload naming.** Every persistent autoload is `<Thing>State` in `global/autoloads/` with one
  `user://<thing>.cfg`. EPIC_01 says "`LoadoutManager` *or equivalent*"; `LoadoutState`
  (`global/autoloads/loadout_state.gd`, `user://loadout.cfg`) fits the house naming. Its role is
  the manager EPIC_01 §6 describes.
- **Ids are `StringName`, validated on the way in and on load** (`UpgradeState.is_known_id`,
  `ShipModuleState.SLOT_MODULES`), unknown ids `push_warning`ed and dropped — `push_warning` is not
  a GUT failure, `push_error` is.
- **`&""` means empty** (`ShipModuleState`). Use the same sentinel for an empty loadout slot.
- **Signal arity is declared exactly** and self-emits are swept by
  `tests/integration/test_signal_emit_arity.gd`. `test_event_bus.gd` pins EventBus arities by name.
- **Verbose-only logging** for anything per-frame / per-press (`OS.is_stdout_verbose()`).
- **Composition** — weapon mechanics stay on the State nodes; the store holds ids only (EPIC_01 §6
  says the same thing).
- **Never hand-type a `uid://`**; new `.tscn`/`.tres` may be UID-less or minted with
  `ResourceUID.create_id()` (tests/README). `test_resource_uid_integrity.gd`,
  `test_project_load_integrity.gd` (loads every new scene/script) and
  `test_suite_integrity.gd` all run over whatever this epic adds.
- **Menu coordinates** are 640×360 art pixels under `ShipLayout.scale = 2` — the same design-unit
  idea as gameplay (`ArenaCamera.WORLD_SCALE`), but here it is a node scale, not a constant.
- **Docs:** adding an autoload, a resource class and a menu panel is structural →
  `updating-project-docs` (global.md autoload table, assault.md weapon section, PROJECT.md,
  CLAUDE.md if a new invariant test is added).
- **Pixel art** only via the `pixel-art-generation` skill, strict top-down (UI frames are flat, so
  the angle rule is trivially met, but the skill's save/inspect rules still apply).

## Candidate approaches (for the plan to choose between)

| Option | Shape | For | Against |
|---|---|---|---|
| **A. New `LoadoutState` autoload** (recommended) | `MAIN_SLOTS = 3`, `SUB_SLOTS = 3`; `_main: Array[StringName]`, `_sub: Array[StringName]`, `_main_index`, `_sub_index`; `assign(kind, slot, id) -> bool`, `clear(kind, slot)`, `get_slot`, `active_id(kind)`, `cycle(kind) -> StringName`, `set_active_slot`; signals `slot_changed(kind, slot, id)`, `active_changed(kind, id)`; `user://loadout.cfg`. Validation asks `UpgradeState` (main) / the sub catalogue (sub). | Matches every other store; unit-testable tree-less; survives scene changes (both ship scenes and both HUDs just read it); single owner of "what is equipped". | One more autoload + one more `SaveSandbox` path. |
| B. Extend `UpgradeState` | Add slot arrays to the unlock store. | No new autoload. | Mixes "what I own" with "what I equip"; `UpgradeState` knows nothing about subs; its tests pin its current contract. |
| C. Extend `ShipModuleState` with `main_1..3`/`sub_1..3` slots | Reuse `SLOTS`/`SLOT_MODULES`/`equip`. | Maximum reuse. | Its per-slot catalogue model would need the same id legal in three slots *and* a cross-slot duplicate rule it doesn't have; its load grandfathers locked ids (contradicts R14); `ShipModulesPanel.get_slot_count() == 4` and `test_module_unlock_sources.gd` iterate `SLOTS` and would all change. |
| D. Loadout as a node on the player (per-scene) | `LoadoutComponent` under `AttackStateMachine`. | Local. | Two ship scenes, two copies, persistence still needs an autoload; menu would have to find it. |

**Sub-weapon ids.** Needed regardless of option: a `SubWeaponResource` (`id`, `display_name`,
`icon` (menu 67×67), `hud_icon` (32×32)) with two `.tres` —
`&"missile_barrage"` (today's `_type 0`, `_launch_warhead`) and `&"homing_missile"` (`_type 1`,
`_launch_homing`) — in e.g. `assault/scenes/player/weapons/sub_weapons/`, and a catalogue const
(`ALL_SUB_IDS`) mirroring `UpgradeState.ALL_IDS`. `RocketState` keeps `_launch_warhead`/`_launch_homing`
and dispatches on id. Both subs are **always available today** (no unlock exists); the plan must
state that "available sub" = "in the sub catalogue" until the weapon epic adds sub unlocks, and
leave a single `is_sub_available(id)` seam for it.

## Dependencies and blast radius

- **`PlayerMenu` rewrite of the cursor/confirm model** — the biggest change. Every existing menu
  behaviour must survive: Tab toggle + pause guard, module column + `ModuleList` overlay,
  `unlocked_changed` repopulate. Tests that drive it: `test_weapon_unlock_sources.gd`
  (`test_unlocking_repopulates_an_already_built_player_menu` reads
  `ShipLayout/MainWeaponFrame` by path and asserts its row count — keep that node path or update
  the test deliberately), `test_module_list_lock.gd`, `test_pause_menu_*` (pause interplay).
- **`WeaponState` / `RocketState`** — shared by both ship scenes; `_cycle()` semantics change
  (all-unlocked → loadout slots). Nothing else calls `_cycle()`, `select_weapon`, `get_type`,
  `select_sub_weapon` (grep: only `player_menu.gd`).
- **HUD** — `mission_hud.gd` (sub icon via `RocketState.weapon_changed(icon)`), `WeaponChip`
  (main via `WeaponState.weapon_changed(mode)`). EventBus weapon signals have no listeners.
- **Saves** — new `user://loadout.cfg`; `SaveSandbox.PATHS`; no change to `upgrades.cfg`.
- **Docs** — `global.md` autoload table and PlayerMenu section, `assault.md` §weapons
  (`:92`, `:268`, `:610`), `open_space.md:92`, PROJECT.md, CLAUDE.md, tests/README.
- **Separate weapon epic** will add main/sub weapons (Harpoon, Drones…). The catalogue shapes chosen
  here are its extension point; nothing in this epic may hard-code "2 subs" or "5 mains".

## Risks, edge cases, testing requirements

### Risks

1. **Layout space.** The menu is full: two 153×270 columns + a 270×270 module panel across 640
   design px. Six frames on top need ~60–70 design px of height, so the lower lists shrink to
   ~190 px (6 rows at 30 px — enough for today's 5 mains / 2 subs, `MAX_ITEMS = 8` would overflow).
   Either the list frame background is re-cut (`weapong_list_frame.png` is 270 tall) or stretched
   via a `NinePatchRect`, or the lists scroll. The module panel's vertical position must move
   too, or the loadout row only spans the two weapon columns (≈ 330 design px wide — enough for
   3 × 40 px frames per group plus labels). This must be *looked at*: nothing in the gate renders
   the menu (see `CLAUDE.md` on `station_core.png`), so a screenshot/eyeball step belongs in the plan.
2. **Behaviour drift.** Moving `E`/`Q` onto the loadout is exactly where a mechanic changes by
   accident (e.g. dropping the beam-release or cooldown reset in `select_weapon`, or firing an
   empty slot). "Loadout changes not altering weapon behaviour" (R17) needs a real test: same mode
   → same projectiles/damage/heat before and after a loadout reassign.
3. **Active-weapon persistence across scenes.** Today `_active_id` resets to `&"default"` and
   `_type` to 0 in every new scene (both ship scenes create fresh State nodes). With an autoload the
   current *index* can survive scene changes; whether it should be saved to disk is a plan decision
   (EPIC_01 §9 only lists the six slots).
4. **All main slots empty.** EPIC_01 allows empty slots; the plan must define what the gun does if
   the player empties all three (options: forbid clearing the last main; or no main weapon fires
   and the chip shows empty). `WeaponState._first_unlocked_id()` falls back to `&"default"` today.
5. **Fresh-profile / migration seeding.** Existing profiles have no `loadout.cfg`. To keep today's
   game identical on first boot: Main = [`default`, empty, empty] (or the first three unlocked ids),
   Sub = [`missile_barrage`, `homing_missile`, empty]. Seeding must only happen on a missing file,
   never to "repair" an invalid slot (R14).
6. **Unlock arrives mid-scene.** `unlocked_changed` must refresh the collection list (already
   wired) — should a newly unlocked weapon auto-fill an empty slot? Auto-fill is convenient but is
   the "silent assignment" EPIC_01 §9 warns about in spirit; recommend no auto-fill except the
   fresh-profile seed.
7. **Input overlap.** Menu `menu_confirm` is F and Space; `interact` is also F; `jump` Space. The
   menu already consumes via `set_input_as_handled()` while visible. Esc (`ui_cancel`) is also
   the pause menu; a new "cancel assignment" step inside the menu must consume it the same way
   `ModuleList` does (`player_menu.gd:74-77`) or the pause menu opens underneath.
8. **Autoload order.** The store reads `UpgradeState` in `_ready` for validation → register after it.
9. **Orphans / leaks.** Menu tests that re-populate report orphans (documented); any `await` in the
   new code → run `scripts/check-test-leaks.sh`.

### Edge cases the tests must hit

- Assign to slot index −1 / 3 → rejected; 3 main + 3 sub exactly.
- Assign a main id to a sub slot and vice versa → rejected, slot unchanged, no signal.
- Assign an unknown id / a locked main id → rejected.
- Assign an id already in another slot of the same kind → rejected (slot and other slot unchanged).
  Re-assigning an id to the slot it already occupies → no-op, no signal.
- Clearing a slot → `&""`; clearing the *active* slot moves the active index to the next
  non-empty slot (or none).
- Cycle: `[a, "", c]` → a→c→a (skips empty); `[a, "", ""]` → stays on a, no change signal;
  all empty → no-op, returns `&""`; wraps 3→1.
- Load: missing file → seed; file with an unknown id → that slot empty + warning, others intact;
  file with a known-but-locked main id → empty; same id saved in two slots (hand-edited file) →
  second occurrence empty; wrong-typed value → empty; index out of range → clamped/first non-empty.
- Round-trip: assign → new tree-less instance `_load()` → same six slots.
- Menu: six frames exist, empty ones render the empty treatment, cursor on a slot + confirm opens
  assignment with only compatible rows selectable, cancel restores, assigned weapon shows in the
  frame, HUD chip follows the active slot after `E`/`Q`.
- Behaviour: firing the same mode before/after a loadout change spawns the same projectile count
  and deals the same damage; `RocketState` with `missile_barrage` spawns 3 warheads at the same
  offsets, with `homing_missile` `homing_count` homing missiles.

### Testing requirements

- Unit: `tests/unit/test_loadout_state.gd` (tree-less `Script.new()`, `SaveSandbox`).
- Integration: menu (`player_menu.tscn`), Q/E through a real `MovementController` signal or by
  calling `_on_action("cycle_weapon")` on real `WeaponState`/`RocketState` nodes, and a
  sub-catalogue invariant (every `SubWeaponResource` has an id matching its file and an icon, same
  as `test_weapon_mode_catalogue.gd` / `test_every_weapon_mode_resource_has_an_icon`).
- Live-autoload tests must snapshot/restore `LoadoutState`'s arrays (and `UpgradeState._unlocked`)
  exactly as `test_weapon_unlock_sources.gd` does.

## Open questions for the plan

1. `LoadoutState` (house naming) vs literal `LoadoutManager` — recommend `LoadoutState`, documented
   as EPIC_01's LoadoutManager.
2. Assignment flow: slot-first only (EPIC_01 §2) — should picking a list row with **no** slot
   selected do anything? Recommend: lists are browse-only until a slot is selected; confirm on a
   slot enters "assigning" mode, which moves the cursor into the matching list.
3. Duplicate UX: hard-reject (row dimmed like a locked module row) vs *swap* (move the weapon from
   its old slot into the chosen one). EPIC_01 §7 says "rejected"; see 2-research for the swap
   convention in shipped games — the plan must pick and justify.
4. How to clear a slot (an "Empty/None" row at the top of each list, like `ModuleList`'s None row?).
5. What fires when every main slot is empty (Risk 4).
6. Persist the active indices to disk, or only keep them for the session?
7. Does picking in the menu also make that slot active (today confirming a main row *switches* the
   gun)? Recommend: assignment does not change the active slot, except when assigning into the
   active slot itself.
8. `EventBus.player_rocket_changed(icon)` → keep for arity stability, or change to a
   `SubWeaponResource` payload (no listeners; only `test_event_bus.gd` pins it).
9. Whether one new art asset (a header plate or a larger 67×67-icon slot frame) is needed at all,
   after trying the module item frame + `Label`s in a rendered screenshot.
