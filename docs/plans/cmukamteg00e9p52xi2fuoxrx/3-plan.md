# Weapon loadout: 3 Main + 3 Sub slots with Q/E cycling and persistence

Epic `cmukamteg00e9p52xi2fuoxrx`, plan task `cmukamtey00ejp52xjxwrgg2y`, 2026-09-28.
Spec: `docs/ideas/cmukal7cu008nmr2xvyvt5ein/EPIC_01_WEAPON_LOADOUT_UI.md` (**EPIC_01**).
This plan builds on `1-context.md` (requirements R1–R19, files, candidate architectures) and
`2-research.md` (Everspace 2 cycling, weapon-switch taxonomy, Doom Eternal quick switch, Godot
focus/ConfigFile docs, stable-id save migration). It does not repeat them. Line numbers are from
`b2a551b`.

## Problem

Today the ship menu (Tab) shows every unlocked main weapon and two hard-coded sub-weapons, and
confirming a row switches the gun there and then. In flight, **E** steps through *every* unlocked
main weapon and **Q** flips between the two missile types. Nothing is remembered: every scene
load puts the player back on Standard + Missiles Barrage.

After this epic the player owns a **combat loadout**: three Main slots and three Sub slots, shown
as six prominent frames at the top of the ship menu. Below them the full collections stay
browseable. The player picks a slot, then picks a compatible weapon from the matching list. In
flight **E** cycles Main slot 1→2→3→1 and **Q** cycles Sub slot 1→2→3→1, skipping empty slots.
The loadout (and which slot is active) survives scene changes and restarts. A saved weapon that is
no longer available comes back as an empty slot, never as a silent substitute. The weapons
themselves fire exactly as they do today.

## Design

### 1. Sub-weapons get stable ids and one catalogue (R5, R12, R13)

Sub-weapons are positional ints today (`RocketState._type` 0/1, `warhead_missile_shooting_state.gd:17`)
with their names/icons duplicated in `PlayerMenu._SUB_WEAPON_NAMES/_ICONS` (`player_menu.gd:18-22`)
and `RocketState.warhead_icon/homing_icon` (`:10-11`). A positional index cannot be persisted
safely (2-research, Factorio/Bugnet finding) and cannot be validated against a slot kind.

- New `SubWeaponResource` (`class_name SubWeaponResource extends Resource`) at
  `assault/scenes/player/weapons/sub_weapons/sub_weapon.gd`, same shape as
  `WeaponModeResource`: `@export var id: StringName`, `display_name: String`,
  `icon: Texture2D` (menu, 67×67, from `sub_weapon_icons/`), `hud_icon: Texture2D` (32×32, from
  `assault/assets/gui/weaponselector/`). Pure data — no behaviour field; mechanics stay on
  `RocketState`.
- Two `.tres` beside it: `missile_barrage.tres` (today's `_type 0`, `_launch_warhead`) and
  `homing_missile.tres` (`_type 1`, `_launch_homing`), UID-less or with a minted UID.
- Catalogue: `const ALL_IDS: Array[StringName] = [&"missile_barrage", &"homing_missile"]` and
  `static func load_id(id: StringName) -> SubWeaponResource` on `SubWeaponResource` (mirrors
  `UpgradeState.ALL_IDS` + `_MODES_DIR`). The weapon epic extends this list; nothing here may
  hard-code "2 subs".
- `RocketState` holds `_active_id: StringName` instead of `_type: int`; `_launch()` dispatches
  `&"missile_barrage"` → `_launch_warhead()`, `&"homing_missile"` → `_launch_homing()`, `&""` →
  nothing (and the cooldown timer does **not** start). `_launch_warhead`/`_launch_homing` bodies
  are untouched. `get_type()` → `get_active_id()`; `select_sub_weapon(id: StringName)`.
  `get_current_icon()` returns the resource's `hud_icon`, or
  `assault/assets/gui/weaponselector/icon_empty_slot.png` (exists, currently unused) for `&""`.
  `weapon_changed(icon: Texture2D)` and `EventBus.player_rocket_changed(icon: Texture2D)` keep
  their arity — no churn in `test_event_bus.gd` or `mission_hud.gd`.

### 2. `LoadoutState` autoload — EPIC_01's LoadoutManager (R1, R5, R10, R11, R13, R14)

Option A of `1-context.md`. Named `LoadoutState` to match the house convention (every persistent
store is a `<Thing>State` autoload with one `user://` ConfigFile); its doc comment says it is
EPIC_01 §6's LoadoutManager. Rejected: extending `UpgradeState` (mixes owning with equipping,
knows nothing of subs), extending `ShipModuleState` (per-slot catalogue model, and its `_load()`
*grandfathers* locked ids — the exact opposite of EPIC_01 §9), a per-scene node (two ship scenes,
still needs an autoload for persistence).

File `global/autoloads/loadout_state.gd`, registered in `project.godot` **after `UpgradeState`**
(it validates against it in `_ready`). It holds ids only; it never touches a weapon node.

```gdscript
enum Kind { MAIN, SUB }
const SLOT_COUNT := 3
const SAVE_PATH := "user://loadout.cfg"
const SAVE_VERSION := 1
enum Reject { OK, BAD_SLOT, UNKNOWN, WRONG_KIND, LOCKED, DUPLICATE, LAST_MAIN }

signal slot_changed(kind: int, slot: int, id: StringName)   # after assign/clear
signal active_changed(kind: int, id: StringName)            # active slot's weapon changed

func get_slot(kind: int, slot: int) -> StringName            # &"" = empty (ShipModuleState sentinel)
func get_slots(kind: int) -> Array[StringName]               # copy, always SLOT_COUNT long
func get_active_index(kind: int) -> int                      # -1 when every slot of kind is empty
func get_active_id(kind: int) -> StringName                  # &"" when none
func is_available(kind: int, id: StringName) -> bool         # MAIN: UpgradeState.is_unlocked; SUB: in SubWeaponResource.ALL_IDS
func check_assign(kind: int, slot: int, id: StringName) -> int   # Reject value; the menu uses it to dim rows and say why
func assign(kind: int, slot: int, id: StringName) -> bool
func clear(kind: int, slot: int) -> bool
func cycle(kind: int) -> StringName                           # next occupied slot, wraps; returns active id
func set_active_slot(kind: int, slot: int) -> bool            # refuses an empty slot
```

Rules (each one is a test case in `test_loadout_state.gd`):

- **Exactly 3 + 3.** `slot` outside `0..2` → `BAD_SLOT`.
- **Compatibility.** A main id (any `UpgradeState.ALL_IDS`) in a SUB slot, or a sub id in a MAIN
  slot → `WRONG_KIND`; an id in neither catalogue → `UNKNOWN`; a main id that is not unlocked →
  `LOCKED`. `is_available(SUB, …)` is "in the catalogue" today — **the single seam** the weapon
  epic replaces when sub-weapons get unlocks.
- **Duplicates rejected** (EPIC_01 §7; nothing in the code supports duplicates, R11): the id in
  *another* slot of the same kind → `DUPLICATE`, both slots unchanged, no signal. Assigning the id
  the slot already holds → returns `true`, no signal. Swap was considered (2-research judgement
  call 2) and rejected: it rewrites a second slot as a side effect, which is the silent
  reassignment §9 forbids in spirit, and §7 asks for rejection.
- **At least one main weapon.** `clear(MAIN, slot)` on the only occupied Main slot →
  `LAST_MAIN`, refused. Keeps today's "you always have a gun" (2-research judgement call 3).
  Sub slots may all be empty — that only disables `special_weapon`.
- **Active index.** Always points at an occupied slot when one exists, else `-1`.
  Assigning into the active slot, clearing the active slot (active moves to the next occupied
  slot, wrapping), or assigning into a kind whose active index is `-1` (that slot becomes active)
  emits `active_changed`. Assigning elsewhere does **not** change the active weapon (1-context
  open question 7).
- **Cycle** walks forward from the active index to the next occupied slot, wraps 3→1, returns the
  new active id. `[a,"",c]`: a→c→a. One or zero occupied slots → no-op, **no signal** (no HUD
  flash on a press that changed nothing; 2-research judgement call 4). Switching is instant — no
  delay or lockout (Doom Eternal finding).
- **Persistence.** `user://loadout.cfg`, section `[loadout]`: `version=1`, `main_0..main_2`,
  `sub_0..sub_2` (String, `""` = empty), `main_active`, `sub_active` (int). Saved on every
  successful assign/clear/cycle/set_active. Persisting the active index is a deliberate extension
  beyond §9's six slots: it is two ints, and it removes today's quirk of every scene load resetting
  the gun (2-research judgement call 6). A version mismatch is treated like a missing file's keys
  (no migration map yet — nothing has been renamed; add `_RENAMES` the day something is).
- **Load invalidation — never substitute** (EPIC_01 §9). Each slot is validated through the same
  `check_assign` rules: non-String value, unknown id, wrong kind, locked main, or a second
  occurrence of an id → that slot loads **empty** with a `push_warning` (not `push_error` — GUT
  fails on errors). An active index that is out of range, non-int or points at an empty slot →
  first occupied slot (or `-1`). A load that leaves every Main slot empty is allowed (hand-edited
  file only; `default` can never be locked) — the gun then fires nothing and the chip shows the
  empty frame; the player fixes it in the menu. Load never writes the file.
- **Seed only on a missing file** (never to repair an invalid slot): Main = the first up-to-three
  `UpgradeState.unlocked_ids()` in catalogue order (fresh profile: `[default, "", ""]`, exactly
  today's first boot; an existing profile keeps up to three of the weapons it could already cycle
  through), Sub = the first up-to-three `SubWeaponResource.ALL_IDS`
  (`[missile_barrage, homing_missile, ""]` — today's pair), both actives 0.
- **Live unlocks** do not auto-fill empty slots (1-context risk 6): only the missing-file seed ever
  assigns without the player. `UpgradeState` has no revoke API, so no live invalidation is needed;
  if the weapon epic adds one, it connects that signal to `clear()`.
- `tests/helpers/save_sandbox.gd` `PATHS` gains `user://loadout.cfg`. Tree-less
  `Script.new()` + `_load()` works like `test_ship_module_state.gd`.

### 3. In-flight consumers: E and Q cycle the loadout (R8, R9, R17 "behaviour unchanged")

- `WeaponState._ready()`: `_active_id = LoadoutState.get_active_id(Kind.MAIN)`; connects
  `LoadoutState.active_changed`. `cycle_weapon` (E) → `LoadoutState.cycle(MAIN)`; the handler for
  `active_changed(MAIN, id)` calls the existing switch primitive. `_cycle()`'s duplicated
  side-effect block (`weapon_state.gd:137-151`) is deleted; the side-effects in `select_weapon`
  (`:163-174` — beam release, sniper cancel, `_cooldown = 0`, emit) are the *only* switch path,
  factored into a private `_switch_to(id)` that also accepts `&""`. `select_weapon(id)` stays
  public, still gated on `UpgradeState.is_unlocked`.
- Empty main (`&""`): `_modes.get(&"")` is null, so every fire path already returns;
  `_emit_changed()` emits `weapon_changed(null)` / `EventBus.player_weapon_changed(null)` and
  `WeaponChip` (`assault/scenes/gui/weapon_chip.gd`) renders `icon_empty_slot.png` + `"EMPTY"`.
- `RocketState`: `switch_weapon` (Q) → `LoadoutState.cycle(SUB)`; `active_changed(SUB, id)` →
  `select_sub_weapon(id)`. `special_weapon` on an empty sub slot is a no-op that does not start the
  cooldown.
- Input actions, `MovementController` and the dash lock are untouched; Q/E are already inert while
  the menu pauses the tree. No mouse wheel, no hotkeys (R9 — nothing to remove).
- HUD: `mission_hud.gd` already follows `RocketState.weapon_changed(icon)`; `WeaponChip` already
  follows `WeaponState.weapon_changed(mode)`. Both therefore follow the active slot with no new
  wiring; only the empty state is new.
- **Interim menu behaviour** (between this step and step 5): the lists' confirm no longer switches
  the gun directly (it would bypass the loadout). Confirm on a main/sub row whose weapon is in the
  loadout makes that slot active (`set_active_slot`); otherwise it is a no-op. The pink "selected"
  row highlight follows `LoadoutState.get_active_id`.

### 4. Menu: six loadout frames on top, collections below (R2, R3, R6, R7, R15, R16)

Keep the Node2D/Sprite2D menu and its hand-rolled cursor — porting to Control focus would redesign
the UI language, which EPIC_01 §10 forbids (2-research, Godot focus finding).

- New `LoadoutSlotsPanel` (`global/ui/player_menu/loadout_slots_panel.gd` + `.tscn`, Node2D),
  built like `ShipModulesPanel`: six fixed frames in two labelled groups, `MAIN [1][2][3]` and
  `SUB [1][2][3]`, laid out horizontally across the band above the two weapon columns. Frame art:
  `menu_ship_modules_item_frame.png` (the module frame language §3 asks for), `Icon` child
  showing the assigned weapon's menu icon (`WeaponModeResource.icon` / `SubWeaponResource.icon`,
  scaled to fit), a `Label` "1/2/3" slot number, and a `Label` group header. The weapon's
  `display_name` for the cursor slot is shown in one caption label under the band.
- **Empty** frames: same frame, `icon_empty_slot.png` inside, `_EMPTY_COLOR` grey tint from
  `ShipModulesPanel` — a deliberate empty state, not a missing icon.
- Prominence (§4): frames are drawn larger than list rows (frame scale chosen at layout time,
  pixel-integer), sit at the top, have headers; lists sit below under "MAIN WEAPONS" / "SUB
  WEAPONS" collection captions.
- States a frame can show at once: **cursor** (yellow `Color(1.4,1.4,1.0)`, as `WeaponOption`),
  **selected for assignment** (pink `Color(2.0,0.5,1.2)`, as `WeaponOption` selected), **active in
  flight** (small marker, e.g. a bright underline `ColorRect` — not a new texture), **empty**
  (grey + empty icon). API: `refresh()` (reads `LoadoutState`), `set_cursor(kind, slot)` (-1 =
  none), `set_assigning(kind, slot)`, `get_slot_node(kind, slot)` for tests. Panel refreshes on
  `LoadoutState.slot_changed` / `active_changed`.
- Layout: `ShipLayout` coordinates are 640×360 art px under `scale = 2`. The loadout band takes
  roughly y 20–90; `MainWeaponFrame` and `SubWeaponFrame` move down and shorten to fit ~6 rows
  (today: 5 mains, 2 subs; `WeaponFrame.MAX_ITEMS` stays 8 but the visible height shrinks).
  `weapong_list_frame.png` (153×270) cannot be scaled vertically without smearing pixels, so the
  list background becomes a `NinePatchRect` over the same texture (a Control child of a Node2D is
  fine) — no new art. `ShipModulesPanel` stays in the right column. Node paths
  `ShipLayout/MainWeaponFrame` / `SubWeaponFrame` are kept (`test_weapon_unlock_sources.gd` reads
  them).
- **Visual check.** No gate step renders a scene, and this container has no display or Xvfb, so
  the layout cannot be screenshotted from Godot here. The layout task composes a static mock-up
  PNG of the band + lists from the real sprite files at the planned positions (a headless Godot
  script using `Image.blend_rect`, which needs no renderer; output under `/tmp`) and looks at it; the owner eyeballs the real menu in the editor
  afterwards (listed in Known gaps of the dossier).

### 5. Menu: slot-first assignment (R4, R5, R10, R11, R15)

The flow is the one `ModuleList` already teaches (confirm on a slot → pick from a list → confirm or
Esc; `player_menu.gd:170-192`), so the player learns nothing new (2-research judgement call 1).

- **Focus model.** `PlayerMenu` gains a `_focus` state: `LOADOUT` (cursor on one of six frames,
  left/right across all six, down → lists), `LISTS` (today's `(_cursor_col, _cursor_row)` over
  main list / sub list / modules; up from row 0 of a weapon list → loadout row), and `ASSIGNING`.
  The module column and `ModuleList` overlay keep their current behaviour. Menu opens with the
  cursor on the active Main slot.
- **Confirm on a slot** → `ASSIGNING`: that frame turns pink ("selected"), the matching list is
  rebuilt with a leading **"Empty"** row (clears the slot; drawn with `icon_empty_slot.png`), the
  cursor jumps into that list on the slot's current weapon (or "Empty"), and the *other* list is
  dimmed. Each row is tinted by `LoadoutState.check_assign`: OK rows normal; `DUPLICATE` /
  `LAST_MAIN` rows dimmed with `ModuleListItem._LOCKED_MODULATE` and a one-line reason in the
  caption ("Equipped in MAIN 2", "Keep at least one main weapon"). The slot frame previews the
  row under the cursor (2-research, "show what will change").
- **Confirm on a row**: OK → `LoadoutState.assign` (or `clear` for "Empty"), back to `LOADOUT` on
  the same slot; rejected → stays in `ASSIGNING`, the reason stays shown, nothing changes.
  **Esc** (`ui_cancel`) → back to `LOADOUT`, nothing changed, event consumed so the pause menu does
  not open underneath (same as `player_menu.gd:74-77`). **Tab** in `ASSIGNING` cancels first,
  second Tab closes (as with `ModuleList`).
- **Browse** (`LISTS` focus): list rows are browseable (cursor + caption) but confirm does nothing
  — assignment is slot-first only (1-context open question 2). This removes today's "confirm a row
  to switch the gun"; in-flight switching is E/Q over the loadout.
- After every `populate()`, open, close and `unlocked_changed` rebuild, cursor and selection are
  re-applied (2-research, Godot focus finding; the bug class `player_menu.gd:194-200` already hit).
- Parallel sub arrays `_SUB_WEAPON_NAMES/_ICONS` are gone after step 1; the sub list reads
  `SubWeaponResource`.

### 6. Art (R16)

Existing art covers everything planned: module item frame, `icon_empty_slot.png`, main/sub menu
icons, HUD sub icons, `weapong_list_frame.png` via NinePatch, `Label`s for headers. PixelLab is
used **only** if the mock-up in step 4 shows a genuinely missing piece (most plausibly a frame
sized for the 67×67 menu icons, or a MAIN/SUB header plate), and then only through the
`pixel-art-generation` skill and `scripts/pixellab.sh`, with the visual check. That decision is
made inside the layout task — there is no standalone art task, because generating nothing is the
expected outcome.

## Build sequence

Manager-first rather than EPIC_01 §13's menu-first order (R18): the store is the thing every other
step reads, and it is the only part fully testable tree-less, so building it first gives each later
step a tested foundation. EPIC_01 §13's steps all still happen, in this order:

1. **t1 — Sub-weapon ids + catalogue** (§1). Characterization test of `RocketState` launches
   *first* (green on today's code), then the refactor, same test still green.
2. **t2 — `LoadoutState` autoload** (§2). Unit tests first.
3. **t3 — E/Q cycle the loadout; HUD follows; empty states** (§3).
4. **t4 — Six loadout frames + lists moved lower** (§4), render-only; interim confirm from §3 kept.
5. **t5 — Slot-first assignment flow** (§5).

Each step leaves the game playable and the gate green.

## Test plan

All live-autoload tests snapshot/restore `LoadoutState`'s slot arrays + active indices and
`UpgradeState._unlocked` in `before_all`/`after_all`, and sandbox files with `SaveSandbox`, as
`test_weapon_unlock_sources.gd` does. Read `tests/README.md` first (signal-arity trap, save
sandbox, orphans).

| Test file | Task | Cases |
|---|---|---|
| `tests/integration/test_rocket_state_launch.gd` (characterization, written before t1's refactor) | t1 | warhead type spawns 3 `WarheadMissile` at offsets (-16,26),(0,36),(16,26) rotated by actor rotation; homing type spawns `homing_count` missiles with the ±7 px spread and round-robin targets; `special_weapon` starts `CooldownTimer`, a second press while running spawns nothing. Green before and after the refactor. After: an empty sub id launches nothing and leaves the timer stopped. |
| `tests/integration/test_sub_weapon_catalogue.gd` (invariant) | t1 | every `SubWeaponResource.ALL_IDS` entry has `<id>.tres` whose `id` equals the filename, non-empty `display_name`, `icon` and `hud_icon`; every `.tres` in the directory is in `ALL_IDS` (directory sweep, like `test_config_instance_isolation.gd`); boundary: a synthetic resource with a mismatched id is rejected by the check helper. |
| `tests/unit/test_loadout_state.gd` | t2 | `get_slots` length 3 for both kinds; slot −1 and 3 → `BAD_SLOT`; main id into SUB and sub id into MAIN → `WRONG_KIND`, slot unchanged, no `slot_changed`; unknown id → `UNKNOWN`; locked main → `LOCKED`; duplicate in same kind → `DUPLICATE`, both slots unchanged; same id into same slot → true, no signal; the same id may sit in MAIN and never in SUB (kinds are disjoint); clear active slot moves active to next occupied, emits `active_changed`; clear last main → `LAST_MAIN`; clear last sub → allowed, active −1; assigning into a kind with active −1 makes that slot active; cycle `[a,"",c]` a→c→a; cycle `[a,"",""]` no signal; cycle all-empty sub returns `&""`, no signal; wrap 3→1; round-trip save/load of six slots + two actives; missing file → seed (fresh profile `[default,"",""]`, subs `[missile_barrage,homing_missile,""]`); seed with four mains unlocked takes the first three in catalogue order; load with unknown id → that slot empty + others intact; locked main → empty; `homing_missile` saved under `main_1` → empty; same id in `main_0` and `main_2` → `main_2` empty; int where a String is expected → empty; `main_active = 7` → first occupied; `main_active` pointing at an invalidated slot → first occupied (**not** a substitute weapon in that slot); load never writes the file (mtime/contents unchanged). |
| `tests/integration/test_loadout_cycling.gd` | t3 | on a real `player_fighter.tscn` (and one case on `open_space/.../player_ship.tscn`): emit `cycle_weapon` on the real `MovementController` → `WeaponState.get_active_id()` follows Main 1→2→3→1 and `weapon_changed` fires once per real change; empty middle slot skipped; `switch_weapon` → `RocketState` follows Sub slots; one occupied slot → no `weapon_changed`; HUD `WeaponChip` label shows the new `display_name`; `mission_hud` sub icon equals the active `hud_icon`; all-empty subs → sub icon is `icon_empty_slot`, `special_weapon` spawns nothing. |
| `tests/integration/test_loadout_weapon_behaviour.gd` | t3 | "loadout changes do not alter behaviour": fire `default` once, record bullet count/damage/heat increase; reorder the loadout and cycle back to `default`; fire again → identical numbers. Switch away from a beam mode releases the beam (`BeamBehavior` inactive) and from a charging sniper cancels the charge (same side-effects as today's `select_weapon`); `_cooldown` is 0 after a switch. Empty main → shoot spawns nothing, no heat. |
| `tests/integration/test_player_menu_loadout.gd` | t4, extended in t5 | t4: `LoadoutSlotsPanel` has exactly 3 MAIN + 3 SUB frames; an empty slot shows `icon_empty_slot` and the grey tint; an assigned slot shows that weapon's menu icon; the active slot shows the active marker; panel follows `slot_changed` without reopening the menu; `ShipLayout/MainWeaponFrame` still lists every unlocked main (existing test untouched). t5: menu opens with cursor on active Main slot; confirm on MAIN 2 → `ASSIGNING`, frame pink, cursor in main list, sub list dimmed; confirm an OK row → `LoadoutState` slot updated, focus back on the slot; a row equipped in MAIN 1 is dimmed and confirm leaves everything unchanged with the reason shown; a sub row cannot be reached from a MAIN slot (incompatible); "Empty" clears a slot, and on the last main is refused; Esc cancels with no change and does **not** open the pause menu; Tab in `ASSIGNING` cancels, second Tab closes and unpauses; `unlocked_changed` while assigning keeps the cursor on a valid row; `ModuleList` flow still works (existing `test_module_list_lock.gd` untouched and green). |

Existing suites that must stay green unchanged: `test_weapon_unlock_sources.gd`,
`test_module_list_lock.gd`, `test_event_bus.gd` (arities unchanged), `test_signal_emit_arity.gd`
(new signals declared with exact arity), `test_project_load_integrity.gd` (new scenes/scripts load
clean), `test_resource_uid_integrity.gd` (no hand-typed UIDs). Run `scripts/check-test-leaks.sh`
after any task that adds an `await`.

## Requirements coverage

| Req (1-context) | EPIC_01 § | Delivered by |
|---|---|---|
| R1 3 Main + 3 Sub loadout | Goal, §6 | t2 (store), t4 (frames) |
| R2 collections kept, moved lower | §1 | t4 |
| R3 six frames `MAIN [1][2][3]` / `SUB [1][2][3]` | §1, §14 | t4 |
| R4 slot-first assignment | §2 | t5 |
| R5 main slots only mains, sub only subs | §2 | t1 (sub ids), t2 (`WRONG_KIND`), t5 (UI) |
| R6 empty slots as intentional frames | §3 | t4 (+ t3 for HUD empty state) |
| R7 loadout visually stronger than lists | §4 | t4 |
| R8 E cycles Main, Q cycles Sub, skipping empties | §5 | t2 (`cycle`), t3 (wiring) |
| R9 no mouse wheel / hotkeys | §5 | t3 (asserted by keeping the input map unchanged; nothing to remove) |
| R10 manager owns slots, indices, validation, unlock refs, persistence, cycling; not behaviour | §6 | t2 |
| R11 duplicates rejected | §7 | t2 (`DUPLICATE`), t5 (dimmed row + reason) |
| R12 lower lists = full collection, no duplicated definitions | §8 | t1 (sub catalogue replaces 2 duplicate maps), t4/t5 |
| R13 persist six slots | §9 | t2 |
| R14 invalid saved weapon → empty, never substituted | §9 | t2 |
| R15 selected slot, kind, assigned weapon, list item, empties visible | §10 | t4 (frame states), t5 (assigning states, preview, caption) |
| R16 reuse art; PixelLab only if missing | §11 | t4 (mock-up decides; generation only if needed) |
| R17 tests (all twelve bullets of §12) | §12 | t1–t5, see Test plan |
| R18 implementation order | §13 | Build sequence (reordered manager-first, justified above) |
| R19 individual weapons (Harpoon, Drones, …) | Goal | **Out of scope** — separate weapon epic |

## Risks

1. **Layout does not fit** — six frames + shortened lists + module panel in 640×360. Mitigation:
   mock-up in t4 before committing positions; NinePatch list background; module panel untouched.
   Residual: no one sees the real render until the owner opens the menu.
2. **Behaviour drift on switch** — dropping beam release / sniper cancel / cooldown reset.
   Mitigation: one `_switch_to` path; `test_loadout_weapon_behaviour.gd`.
3. **Autoload signals into freed State nodes** across scene changes — Godot drops connections to
   freed objects; tests instantiate and free two player scenes in sequence to prove no error.
4. **Existing profile migration** — a player who unlocked 4–5 mains now reaches at most 3 by E.
   That is the epic's intent; the seed keeps the first three and the menu shows the rest.
5. **Menu state explosion** (`LOADOUT`/`LISTS`/`ASSIGNING` + `ModuleList`) — Esc and Tab paths are
   where it breaks; t5 is sized `large` so it gets its own plan and review, and every Esc/Tab path
   has a test.
6. **Interim menu (t3→t5)** can make a slot active but cannot assign; acceptable because the seed
   reproduces today's first-boot loadout and the tasks run in sequence.

## Out of scope

- Implementing any new weapon (Harpoon, Drones, Null Burst, Capacitor Gun, Minecaster…) — the
  separate weapon epic. It extends `UpgradeState.ALL_IDS`/`modes/` and `SubWeaponResource.ALL_IDS`,
  and replaces `LoadoutState.is_available(SUB, …)` if subs get unlocks.
- Sub-weapon unlock progression (none exists today; both subs are always available).
- Mouse-wheel cycling, direct weapon hotkeys, a weapon wheel, switch delays (EPIC_01 §5).
- Duplicate-weapon support, and swap-on-assign.
- Controller/gamepad bindings beyond today's input map.
- A save-rename migration map (`version` key is written so one can be added later).
- Infiltration (has no weapon states).
