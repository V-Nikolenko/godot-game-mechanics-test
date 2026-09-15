# Weapon-mode unlock sources

> **Revision 2** — reworked after `4-review.md` round 1 returned `CHANGES_REQUESTED`. The four
> substantive findings (stale `PlayerMenu` population, an unimplementable test 5, the second
> unexamined icon map on `WeaponModeResource`, and `upgrade_1.png` being 48×48 rather than 32×32)
> are folded in below and each is marked **[R1]** where it changed the design.

## Problem

A player who starts a fresh profile flies the **Standard** gun and nothing else, for the whole
game. `UpgradeState._ready()` seeds `&"default"` and nothing in the shipped game ever calls
`UpgradeState.unlock()` again — the only call site in the project is `unlock_all()` inside the
autoload itself, which nothing invokes. So `Sniper Shot`, `Spread`, `Gatling` and `Mining Laser`
each have a tuned `.tres`, a `WeaponBehavior` implementation and a menu icon slot, and none of
them can ever be fired. Cycling the weapon key does nothing (the cycle list has one entry) and the
ship menu's main-weapon column is a single row.

`Mining Laser` is the sharpest case: `BeamBehavior` exists, the space-station hull is authored on
layer 0 specifically so the mining laser can pass it, and `test_laser_ray_hit_mask.gd` covers it —
all for a weapon the player cannot equip.

After this change the four modes are obtainable in the sector hub, exactly the way the fourteen
ship modules already are; picking one up updates the ship menu **while the player is standing
there**; and a test makes it impossible to add a fifth weapon mode without a source or without an
icon.

## Design

### 1. Mirror `ShipModuleUnlockerPickup`, do not invent a second pattern

`ShipModuleState` had this identical problem and solved it with a `PickupBase` subclass placed in
`sector_hub.tscn` plus an invariant test. Doing anything else here would leave the project with
two unrelated unlock mechanisms for two near-identical stores.

**New `global/pickups/weapon_mode_unlocker_pickup.gd`** — `class_name WeaponModeUnlockerPickup`,
extends `PickupBase`:

```gdscript
enum Weapon { SNIPER_SHOT, SPREAD, GATLING, MINING_LASER }
@export var weapon: Weapon = Weapon.SNIPER_SHOT

func _collect(_player: PlayerBase) -> void:
    UpgradeState.unlock(weapon_id())
func _get_dialog_text() -> String:   # "Gatling acquired!" from the .tres display_name
func weapon_id() -> StringName:      # match on the enum, &"" if an arm is missing
```

- The selection is an **enum**, not an exported `StringName`, for the same reason
  `ShipModuleUnlockerPickup` uses one (`ship_module_unlocker_pickup.gd:6-19`): a scene file cannot
  then contain a typo'd id that only `push_warning`s at collect time.
- `&"default"` is deliberately **not** in the enum — it is seeded, so a pickup for it would be a
  no-op the player can walk into.
- `weapon_id()` is public (no leading underscore) because the invariant test reads it. The
  module test reaches into `_slot_name()`/`_module_name()`; not repeating that here.
- The dialog line comes from the mode `.tres`'s `display_name`, so a rename in the `.tres` cannot
  desync from the pickup text. Falls back to `"Weapon acquired!"` if the `.tres` is missing.

**New `global/pickups/scenes/weapon_mode_unlocker_pickup.tscn`** — same node layout as
`ship_module_unlocker_pickup.tscn` (Area2D `collision_layer = 16`, `collision_mask = 4` — which is
`OpenSpacePlayerShip`'s layer; `Sprite2D` with `texture_filter = 1`; `CollisionShape2D` with a
`CircleShape2D` r=8), with the new script and `global/assets/sprites/upgrade_1.png`.

**[R1] Collision scale is `3.111`, not the module pickup's `3.531701`.** `upgrade_1.png` is
**48×48** (the round-1 plan said 32×32; verified from the PNG IHDR). `ship_module_unlocker.png` is
64×64, and its `3.531701` is tuned to that. Every 48×48 pickup already in
`global/pickups/scenes/` — `armor_tank`, `health_tank`, `ship_shield_up` — uses `3.111`
(r=8 × 3.111 = 24.9 px ≈ half of 48). So the new scene copies the *layout* of the module scene
but the *scale* of its own sprite size's precedent. "Byte-for-byte copy" is withdrawn.

Its `uid://` is minted with the headless `ResourceUID.create_id()` snippet from `tests/README.md`
— never typed, never copied.

**Art: reuse, do not generate.** `upgrade_1.png` is an existing 48×48 weapon-crate sprite that no
scene, script or resource references. Generating a new sprite would spend the capped monthly
PixelLab allowance on an asset the project already has. (Rejected: recolouring
`ship_module_unlocker.png` — it depicts a *ship schematic*, which reads as the module bench and
would be indistinguishable in-world from the pickup it sits next to.)

### 2. `UpgradeState.STARTING_IDS`

`_ready()` currently hard-codes `_unlocked[&"default"] = true` when the store loads empty. The
invariant test needs to know which ids legitimately have no pickup, and "every id except
`default`" hard-coded in a test is a second copy of that fact. So:

```gdscript
## Ids a fresh profile starts with. Everything else in ALL_IDS must be granted by a
## WeaponModeUnlockerPickup placed in the world — gated by
## tests/integration/test_weapon_unlock_sources.gd.
const STARTING_IDS: Array[StringName] = [&"default"]
```

`_ready()` loops over it. **[R1]** To be explicit about a limit the reviewer flagged: this seeding
branch runs *only* when the loaded store is empty, so `STARTING_IDS` is a fresh-profile
declaration, not a per-boot guarantee. That is exactly the existing behaviour and
`tests/unit/test_upgrade_state.gd` pins it; this change must not alter it.

This is also the pointer-comment the work item asked for: the next person grepping
`upgrade_state.gd` finds the unlock path named in the file itself.

Rejected alternative: a `starting: bool` flag or a per-id dictionary in `ALL_IDS`. `ALL_IDS` is
consumed as a flat ordered list by `unlocked_ids()`, `_load()` and `WeaponState._load_modes()`;
changing its shape touches four call sites to express one boolean about one id.

### 3. [R1] `PlayerMenu` must repopulate when something unlocks

This is the finding that decides whether the feature works at all. `_populate_lists()`
(`player_menu.gd:189`) has exactly one caller — `connect_states()` (`:47-51`) — which is called
once, from `mission_hud.gd:19/24/43`, during HUD `_ready()`. `_toggle()` (`:105-122`) never
repopulates. Both the assault HUD and the open-space HUD embed the same `MissionHUD`.

So without this, the player walks into a Gatling crate in the hub, opens the ship menu two seconds
later, and still sees a one-row column. Worse, the menu is then internally inconsistent:
`_init_cursor()` (`:124`) and `_confirm_selection()` (`:154-158`) read the **live**
`UpgradeState.unlocked_ids()`, while `_current_max_row()` (`:142`) reads the **stale** frame count.
Those two can only disagree once unlocks happen mid-scene — which is precisely what this change
introduces. The cursor would clamp to row 0 while `_confirm_selection()` indexed a longer array.

The fix is one signal that already exists and has zero listeners project-wide
(`upgrade_state.gd:21`, `grep unlocked_changed` finds only the declaration, the emit, and two
tests):

```gdscript
func _ready() -> void:
    ...
    UpgradeState.unlocked_changed.connect(_on_upgrade_unlocked)

func _on_upgrade_unlocked(_id: StringName) -> void:
    _populate_lists()
    _cursor_row = mini(_cursor_row, _current_max_row())   ## frame count just grew/changed
    _refresh_cursor()
    _refresh_selection()
```

Rejected alternative: repopulate in `_toggle()` on open. It is fewer lines, and the "menu already
open when the unlock lands" case that first argued against it is at best a same-frame edge (the
menu sets `get_tree().paused = true`, `player_menu.gd:105-108`, and the pickup's `Area2D` inherits
pause mode) — so that is **not** the reason to reject it. The real reason: connecting the signal
means *every* unlock source updates the menu with zero extra wiring — this pickup, a future mission
reward, a boss drop, `unlock_all()` from a debug key. Repopulating in `_toggle()` re-solves the
problem once per entry point and silently misses the next one. That is what the signal is for, and
it has been sitting unused since it was declared.

By the round-1 plan's own argument about `&"piercing"` — "this change is what makes it visible, so
fixing it is part of this work" — this is in scope, not drive-by.

### 4. [R1] One icon map, on the resource, not two

The round-1 plan proposed re-keying `player_menu.gd`'s dead `_WEAPON_ICONS[&"piercing"]` entry to
`&"sniper_shot"`. The reviewer found the reason that is the wrong repair: **`WeaponModeResource`
already has an `icon` field** (`weapon_mode.gd:11`), and it is what the in-game HUD chip draws
(`weapon_chip.gd:26`, `_icon.texture = mode.icon`). No `modes/*.tres` sets it. So there are two
id→icon maps, one of them a constant `Dictionary` in a UI script with a stale key, and the other
empty.

Today that costs one blank chip on the Standard gun. After this change it would be four more blank
chips, mid-mission, on every newly unlocked weapon.

So instead of re-keying:

- Set `icon` on all five `assault/scenes/player/weapons/modes/*.tres`, as an `[ext_resource
  type="Texture2D" ...]` pointing at the icon each one is already mapped to in `_WEAPON_ICONS`,
  with `sniper_shot` taking `icon_ship_weapon_pierce.png` (a sniper round *is* the piercing shot
  that icon depicts). Each PNG's `uid://` is read out of its existing `.import` file — an
  editor-minted UID, not a hand-typed or copied one, which is what `CLAUDE.md` forbids.
- `_populate_lists()` already calls `_load_mode(id)` for `display_name`; take `mode.icon` from the
  same object.
- **Delete `_WEAPON_ICONS` entirely.** The stale-key bug class goes with it, the HUD chip starts
  rendering, and there is one place to look when a sixth mode lands.

`_SUB_WEAPON_ICONS` stays as it is — sub-weapons are a positional `Array` on `RocketState`, not an
id-keyed catalogue, and folding them in is a different change.

Rejected alternative: keep both maps and just re-key. It leaves the HUD chip blank for all five
modes and leaves a duplicate that the next mode has to be added to twice.

### 5. Hub placement

Four instances in `sector_hub.tscn`, a fourth bench row at `y = -515`, `x` stepping 100 from
`-280`, matching the module rows at `-315`/`-415` (`sector_hub.tscn:113-177`):

| Node | weapon | position |
|---|---|---|
| `WeaponUnlockerSniperShot` | `SNIPER_SHOT` (0, default value → no property line) | `(-280, -515)` |
| `WeaponUnlockerSpread` | `SPREAD` (1) | `(-180, -515)` |
| `WeaponUnlockerGatling` | `GATLING` (2) | `(-80, -515)` |
| `WeaponUnlockerMiningLaser` | `MINING_LASER` (3) | `(20, -515)` |

`y = -515` is inside the hub's `Background` rect (`offset_top = -1791`, `sector_hub.tscn:26-31`)
and the open-space ship has no movement clamp, so the row is reachable — confirmed in review.

This is a **bench**, not designed progression: the existing module unlockers are laid out the same
way and this change is about removing dead content, not authoring a reward curve. Gating weapon
modes behind missions is a separate design question and is called out in "Out of scope".

## Build sequence

1. **Test first — `tests/integration/test_weapon_unlock_sources.gd`.** **[R1]** Note the honest
   failure mode: a test file referencing a `class_name` that does not exist yet does not *compile*,
   and GUT drops an unloadable script with a warning while still exiting 0 — the red comes from
   `tests/integration/test_suite_integrity.gd`. So write step 1 against the API step 3 will create,
   run the suite, and confirm the failure is `test_suite_integrity` (missing class) before step 3,
   then a real assertion failure (no pickups in the hub) between steps 3 and 6.
2. `UpgradeState.STARTING_IDS` + `_ready()` loop + the pointer comment.
3. `weapon_mode_unlocker_pickup.gd`.
4. Mint a UID; write `weapon_mode_unlocker_pickup.tscn` with `scale = Vector2(3.111, 3.111)`;
   `godot --headless --path . --import`.
5. Wire `PlayerMenu` to `UpgradeState.unlocked_changed` (design §3).
6. Add the four instances to `sector_hub.tscn`. Tests 1–5 of the test plan go green.
7. Move the icons onto the five mode `.tres`, switch `_populate_lists()` to `mode.icon`, delete
   `_WEAPON_ICONS` (design §4). Test 7 goes green.
   **Bump `load_steps` by hand in each edited `.tres`** — it differs per file (`mining_laser.tres`
   has no `projectile_scene`), and a wrong value is a progress hint rather than an error, so
   neither `--import` nor `test_project_load_integrity.gd` will report it.
8. `bash /agent/verify.sh`; `scripts/check-test-leaks.sh` (step 5 adds a signal connection to a
   `CanvasLayer`, and this suite awaits); `updating-project-docs`.

Steps 2–6 are the feature; 7 is the visible consequence; 5 is what makes 6 observable in play.

## Test plan

`tests/integration/test_weapon_unlock_sources.gd` — INVARIANT (not characterization), stated as
such in a header comment. Loads `sector_hub.tscn` and instantiates **without** adding to the tree
(the hub's `_ready()` spawns drones and builds a HUD).

**[R1] Autoload isolation, decided rather than left conditional.** `WeaponModeUnlockerPickup`
calls the `UpgradeState` **autoload** by name, so a fresh script instance proves nothing about
`_collect()`. The round-1 plan's "or else weaken it" branch is removed. This file follows the
pattern the repo already established for exactly this problem in
`tests/integration/test_module_list_lock.gd:31-42` and documents in `tests/README.md:665-668`:
`before_all()` calls `SaveSandbox.capture()` **and** snapshots the live singleton's state
(`UpgradeState._unlocked.duplicate()`); `after_all()` restores both. `before_each()` sets
`UpgradeState._unlocked` to a known state by direct assignment — not via `unlock()`, so the
fixture does not depend on the code under test and writes nothing to disk.

1. `test_every_non_starting_weapon_id_has_an_unlocker_in_the_sector_hub` — for every id in
   `UpgradeState.ALL_IDS` not in `STARTING_IDS`, some `WeaponModeUnlockerPickup` in the hub has
   that `weapon_id()`. This is the test the whole task exists to add.
2. `test_no_unlocker_grants_a_starting_weapon` — a pickup for `&"default"` is a walk-into no-op;
   assert none exists.
3. `test_every_unlocker_grants_a_known_id` — `weapon_id()` must return something in `ALL_IDS`, so
   an enum value added without its `match` arm (which returns `&""`) fails here rather than
   `push_warning`ing at collect time. Mirrors the module test's slot-mismatch case.
4. `test_no_weapon_has_two_unlockers_in_the_hub` — a duplicate means a copy-paste slip left some
   other mode without one.
5. **Boundary — `test_collecting_an_unlocker_actually_unlocks_the_mode`.** Tests 1–4 all pass
   against a pickup whose `_collect()` is empty. This one instantiates a real
   `weapon_mode_unlocker_pickup.tscn`, sets `weapon = GATLING`, asserts
   `UpgradeState.is_unlocked(&"gatling")` is false, calls `_collect(null)`, and asserts it is
   true. `PickupBase._collect(_player: PlayerBase)` ignores its argument and `null` is a legal
   value for an object-typed parameter in GDScript; if that turns out not to hold, the test builds
   a bare `PlayerBase` local and frees it — the assertion does not weaken either way.
6. **[R1] `test_unlocking_repopulates_an_already_built_player_menu`** — the regression guard for
   design §3, and the only test that can fail on the stale-column bug. Instantiates
   `player_menu.tscn`, `add_child_autofree`s it, calls `connect_states(null, null)` (the exact call
   `mission_hud.gd:19` makes when there is no player), records the main frame's `get_count()`, then
   calls `UpgradeState.unlock(&"gatling")` and asserts the count grew by one. Uses the same
   snapshot/restore fixture. Boundary within it: unlocking an **already**-unlocked id must not
   change the count (`unlock()` early-returns without emitting, `upgrade_state.gd:40-41`), so the
   handler cannot be duplicating rows.
7. **[R1] Boundary — `test_every_weapon_mode_resource_has_an_icon`** — replaces the round-1
   `_WEAPON_ICONS` coverage test, since that dictionary no longer exists. For every id in
   `ALL_IDS`, `modes/<id>.tres` loads and its `icon` is non-null. This is what stops the next
   weapon mode landing with a blank menu row *and* a blank HUD chip, and it is the assertion that
   fails today (all five icons are unset).

Existing tests that must stay green: `tests/unit/test_upgrade_state.gd` (pins `_ready()` seeding —
`STARTING_IDS` must not change observable behaviour), `test_weapon_mode_catalogue.gd`,
`test_project_load_integrity.gd` (loads the new `.tscn` and the five edited `.tres`),
`test_resource_uid_integrity.gd` (the minted scene UID must be canonical and unique; the five
texture UIDs added to the `.tres` files must decode to the ones the `.import` files own),
`test_suite_integrity.gd`, `test_signal_emit_arity.gd`.

## Risks

- **Icon re-key by another name.** If `icon_ship_weapon_pierce.png` was drawn for a future
  `piercing` mode rather than for `sniper_shot`, the menu and chip show a slightly-off icon. Cheap
  to change, no behaviour depends on it, and a blank icon is worse.
- **Deleting `_WEAPON_ICONS` touches a shipped UI path.** It is a `const Dictionary` read in one
  place (`player_menu.gd:196`); `grep` confirms no other reader. `test_project_load_integrity.gd`
  catches a compile error, test 7 catches a missing icon, and the menu-population test (6) catches
  a broken column.
- **Scene-file edits by hand.** `sector_hub.tscn` and the five `.tres` are edited as text (no GUI
  in this container). The import step, `test_project_load_integrity.gd` and
  `test_resource_uid_integrity.gd` catch a malformed result.
- **Signal connection in `PlayerMenu._ready()`.** The menu is freed with its HUD and the autoload
  outlives it; Godot disconnects automatically when the receiver is freed, so this is not a leak.
  `scripts/check-test-leaks.sh` is run anyway (build step 8).
- **Test 6 mutates a live autoload.** Handled by the snapshot/restore fixture above; without it,
  `gatling` would stay unlocked for the rest of the GUT process and quietly change what tests 1–5
  and `test_upgrade_state.gd` see.

## Out of scope

- **Progression design.** Which mission or boss should grant which weapon, costs, or an unlock
  order. The bench mirrors what the ship modules already do; turning either into authored
  progression is one epic, not this task.
- Removing `UpgradeState.unlock_all()` — a useful debug affordance, and `test_upgrade_state.gd`
  covers it.
- Sub-weapons (`RocketState`) and `_SUB_WEAPON_ICONS` — a separate positional store with its own
  selection path, not gated by `UpgradeState`.
- Retuning any weapon `.tres`. The four modes ship at their current numbers; whether Gatling is
  balanced at 14 damage / 0.06s is a question that can only be asked once they are reachable.
- The `player_menu.gd` header comment naming a stale path (`global/ui/dialog_system/playermenu/`).
- **Board complexity stays `medium`.** The reviewer flagged the mismatch between
  `complexity: medium` and running the escalated pipeline, but that is not a mismatch: the
  `feature-workflow` routing table sends `impl` + `medium` + `prepDir: null` to the escalated
  track by design. Re-labelling it `large` would misreport the size of the change.

## Docs to update (`updating-project-docs`)

- `docs/architecture/modules/global.md` — the `global/pickups/` table (currently `:274-286`) gains
  `WeaponModeUnlockerPickup`; the `global/ui/` entry for `PlayerMenu` gains the
  `unlocked_changed` wiring.
- `docs/architecture/PROJECT.md` — the unlock-source convention now covers weapon modes as well as
  ship modules.
- `tests/README.md` — the new invariant test and its autoload-snapshot fixture, next to the
  existing note on `test_module_list_lock.gd`.
- `CLAUDE.md` — the invariant-test list gains `test_weapon_unlock_sources.gd`.
