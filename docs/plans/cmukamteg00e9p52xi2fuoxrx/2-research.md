# Research — Weapon loadout: 3 Main + 3 Sub slots with Q/E cycling and persistence

Epic `cmukamteg00e9p52xi2fuoxrx`, 2026-09-27. Read `1-context.md` first: it has the requirement
list (R1–R19) taken from `docs/ideas/cmukal7cu008nmr2xvyvt5ein/EPIC_01_WEAPON_LOADOUT_UI.md`, the
files involved, and the candidate architectures. This file covers how shipped games and engine docs
handle the same problems, and what that means for this codebase.

## Findings

| Finding | Tradeoff | Typical values | Source |
|---|---|---|---|
| **Everspace 2** is the nearest shipped match: a space shooter with primary and secondary weapon groups. Secondaries **cycle on one key**. Each item has a **"skip when switching"** flag that keeps it out of the cycle while it stays selectable from the menu or wheel. | A single cycle key is cheap and easy to learn, but reaching slot N takes N−1 presses. That is fine at 2–3 slots and gets bad beyond that. The skip flag is how they avoid "dead" stops in the cycle, which is what our **skip empty slots** rule does. | 2 secondary slots. `R` cycles secondaries on PC, D-pad right on pad. Rebindable. | https://gamertweak.com/everspace-2-switch-secondary-weapons/ ; https://steamcommunity.com/app/1128920/discussions/0/3108014879965895000/ |
| **Weapon-switch taxonomy** (Game Developer): seven models, from swapping everything freely in combat to a loadout fixed per mission. The mixed model, where you pick a few in a paused menu and swap them in combat (Bayonetta, Nier), gives variety but "can very easily overwhelm new players". "Quantity in available combat options should never persevere over its quality." | More options in combat weaken each weapon's identity. A small equipped set picked from a larger collection is the standard compromise, and it is exactly EPIC_01's "current loadout vs full collection" split. | Bayonetta/Nier-style menus equip about 4. The article cites "around five to nine actions" as the short-term-memory limit, and **3 + 3 = 6** sits inside it. | https://www.gamedeveloper.com/design/weapon-switching---quality-or-quantity- |
| **Doom Eternal patch 1.06** brought back *Weapon Quick Switch*, because the time-slowing weapon wheel "inhibits high level play". | A radial selector is readable but slows or pauses the action. Fast players want cycling or direct input with **no delay**. This backs EPIC_01 §5 (Q/E only, no wheel, no mouse wheel, no hotkeys) and argues against adding a switch delay or animation lock. | Switching is instant. The wheel is optional. | https://www.gamerevolution.com/guides/654944-doom-eternal-1-06-update-patch-notes-quick-switching |
| **Godot keyboard/pad focus navigation:** no Control has focus when a menu opens, so you must call `grab_focus()`, deferred. `focus_neighbor_*` sets the routes. A node that becomes hidden or is rebuilt **loses focus**. | Godot's built-in focus is only worth adopting if the menu is made of `Control`s. **Ours is not**: `PlayerMenu`, `WeaponFrame` and `ShipModulesPanel` are `Node2D`/`Sprite2D` with a hand-rolled `(_cursor_col, _cursor_row)` cursor. Porting to Control focus would redesign the menu, which EPIC_01 §10 forbids ("do not redesign the entire UI language"). The lesson that does transfer: **re-assert the cursor after every list rebuild or panel hide**. The same bug class already bit this menu once (`player_menu.gd:194-200`, a stale column after an unlock). | Re-apply cursor and selection after every `populate()`, `open()` and `close()`. | https://docs.godotengine.org/en/stable/tutorials/ui/gui_navigation.html |
| **Godot saves:** use `user://` and `ConfigFile` for flat key/value data. `get_value(section, key, default)` returns the default when a key is missing. `load()` returns an `Error` that must be checked. The official tutorial leaves versioning "up to the project creator". | ConfigFile is readable and already the house format (8 stores). It is fine for 6 string ids plus 2 indices. It does no validation, so every value read has to be type-checked and range-checked by hand. | One `[loadout]` section: `main_0..2`, `sub_0..2` (String ids, `""` = empty), and optionally `main_active` / `sub_active` (int). | https://docs.godotengine.org/en/stable/classes/class_configfile.html ; https://docs.godotengine.org/en/stable/tutorials/io/saving_games.html |
| **Save by stable id, version the file, and invalidate references to things that no longer exist.** Bugnet's Godot save guide says to always write a version number and migrate one step at a time. Factorio's migration files map renamed ids (`[["wall","stone-wall"]]`), and references to a removed prototype "become invalid" rather than being replaced. | A rename map keeps a renamed weapon. Anything not in the map loads as invalid, which is what EPIC_01 §9 asks for: "invalidate that slot cleanly and show it as empty. Do not silently assign another weapon." The cost is a small amount of code in `_load()`, and a `version` key that has to be maintained. | A `version` int plus an optional `RENAMES` dict, then validation against the current catalogue and unlocks. **Never store positional indices**: today's `RocketState._type` 0/1 is exactly the kind of reference that silently changes meaning when a catalogue is reordered. | https://bugnet.io/blog/game-save-best-practices-godot ; https://lua-api.factorio.com/latest/auxiliary/migrations.html |

A weaker, single-source point: inventory screens should show what will change before the player
commits an equip (https://thewingless.com/index.php/2021/07/26/10-simple-ways-you-can-improve-your-videogame-inventory-screen-game-ui-ux-design-course/).
For us, that means the chosen slot should visibly preview the list item under the cursor.

### Sources tried and unreachable

- `everspace.fandom.com` (ES2 secondary weapons): 402 via WebFetch. `scripts/fetch-page.sh` returned a 504-byte stub.
- `ratchetandclank.fandom.com/wiki/Quick_Select`: 402. The retry hit a CAPTCHA. Search snippets mentioned 8 slots and a "last weapon" toggle, but the page could not be read, so **none of that is cited**.
- `game-design-snacks.fandom.com` (item wheels): 402.
- `forum.everspace-game.com` (rearranging weapons): DNS failure.
- `strategywiki.org` (Gradius III weapon edit): 403.
- A dev.to article on Godot 4 save patterns loaded but had no migration content, so it is not cited.
- No readable source was found for Returnal, Halo, Warframe, Destiny, Hades, Enter the Gungeon or R-Type Final, and **no published source on weapon-switch cooldown timings**.

### Judgement calls (no citable source)

These are reasoned from the codebase and from general genre knowledge. They are labelled as such,
and the plan should treat them as proposals.

1. **Slot-first assignment** (EPIC_01 §2) is also the flow this menu already teaches. `ModuleList`
   works that way: confirm on a module slot opens a list, confirm on a row equips it, and Esc
   cancels (`player_menu.gd:170-192`). Reusing that shape costs the player nothing to learn.
2. **Duplicate handling: reject, and show why.** EPIC_01 §7 prefers rejection, and nothing in the
   code supports duplicates (`1-context.md` R11). A silent no-op on confirm is the weakest form. The
   existing locked-row treatment (`ModuleListItem._LOCKED_MODULATE`, which makes confirm a defined
   no-op, `module_list.gd:85-90`) can mark an already-equipped row, and a short reason in the menu
   description text ("Equipped in MAIN 2") explains it. *Swap* is the common alternative: equipping
   Pulse into slot 1 while it sits in slot 2 moves it and empties slot 2. It is friendlier, but it
   changes a second slot as a side effect, which is close to what §9 calls silent reassignment. The
   plan should pick one and justify it. **Recommend reject + reason** because the spec asks for it.
3. **All main slots empty.** Nothing fires, and the HUD chip shows the empty frame. Alternatively
   the menu can refuse to clear the last occupied main slot. The second keeps the ship from being
   unable to shoot through a menu mistake. **Recommend refusing to empty the last main slot**, with
   the empty state still fully rendered. That keeps "you always have a gun", which is true today.
   Sub slots may all be empty, since that only disables `special_weapon`.
4. **Cycling with one or zero occupied slots** is a no-op with no signal. There is no "click"
   feedback, so the HUD does not flash on a press that changed nothing.
5. **No switch delay.** Switching stays instant. `WeaponState.select_weapon` already resets
   `_cooldown` to 0 and cancels beam and sniper charge, and that is the behaviour to preserve.
   Nothing in this epic should add a lockout.
6. **Active slot across scenes.** Keeping the active index in the autoload for the session, and
   saving it as well, is cheap and removes today's quirk where every scene load resets the gun to
   Standard. EPIC_01 §9 does not ask for it, so the plan should call it out as a deliberate
   extension or leave it out.

## What this means for the plan

- **Architecture.** Use a `LoadoutState` autoload (`1-context.md` option A). It holds ids only and
  validates against `UpgradeState` for main weapons and a new sub-weapon catalogue for sub weapons.
  It persists to `user://loadout.cfg` with a `version` key, and **loads invalid entries as empty
  with a `push_warning`**, never grandfathering the way `ShipModuleState._load()` does. It is
  seeded only when the file is missing, and the seed reproduces today's first-boot game: Main
  [`default`, –, –], Sub [`missile_barrage`, `homing_missile`, –].
- **Sub-weapon ids** replace `RocketState`'s positional `0/1`, and a `SubWeaponResource` catalogue
  replaces `PlayerMenu`'s parallel arrays and `RocketState`'s duplicate HUD icons. This is the
  finding about stable ids over indices, applied to R12.
- **Cycling.** E and Q step through occupied slots in order and wrap. They are instant and silent
  on a no-op. `WeaponState` and `RocketState` call their existing `select_*` primitives, so the
  side effects (beam release, sniper cancel, cooldown reset, `weapon_changed` emit) are untouched.
- **Menu.** Keep the Node2D/hand-rolled cursor. Add a loadout-slots panel built like
  `ShipModulesPanel` (fixed frames, grey empty state, hover tint). The flow is: slot → matching
  list → confirm or Esc, modelled on `ModuleList`. Re-apply the cursor after every rebuild.
  Already-equipped rows are dimmed and say why. There is an explicit "Empty" row for clearing a
  slot, which mirrors `ModuleList`'s None row.
- **Art.** Try the existing module item frame, `icon_empty_slot.png` and `Label` headers first. A
  rendered screenshot of the menu has to be looked at, because no gate step renders it. Generate
  with PixelLab only if that check shows a genuinely missing frame.
- **Tests.** The edge cases listed in `1-context.md` → *Edge cases the tests must hit*. Add
  `version`/rename coverage if the plan adopts a rename map, plus at least one boundary case per
  load-invalidation rule (unknown id, locked id, wrong kind, duplicate, out-of-range index).
