# Weapon-mode unlock sources

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
ship modules already are, and a test makes it impossible to add a fifth weapon mode without a
source.

## Design

### Mirror `ShipModuleUnlockerPickup`, do not invent a second pattern

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
func weapon_id() -> StringName:      # match on the enum
```

- The selection is an **enum**, not an exported `StringName`, for the same reason
  `ShipModuleUnlockerPickup` uses one: a scene file cannot then contain a typo'd id that only
  `push_warning`s at collect time.
- `&"default"` is deliberately **not** in the enum — it is seeded, so a pickup for it would be a
  no-op the player can walk into.
- `weapon_id()` is public (no leading underscore) because the invariant test reads it. The
  module test reaches into `_slot_name()`/`_module_name()`; not repeating that here.
- The dialog line comes from the mode `.tres`'s `display_name`, so a rename in the `.tres` cannot
  desync from the pickup text. Falls back to `"Weapon acquired!"` if the `.tres` is missing.

**New `global/pickups/scenes/weapon_mode_unlocker_pickup.tscn`** — a byte-for-byte copy of
`ship_module_unlocker_pickup.tscn`'s node layout (Area2D `collision_layer = 16`,
`collision_mask = 4`, `Sprite2D` with `texture_filter = 1`, `CollisionShape2D` with
`CircleShape2D` r=8 at `scale 3.53`), with the new script and
`global/assets/sprites/upgrade_1.png` as the texture. Its `uid://` is minted with the headless
`ResourceUID.create_id()` snippet from `tests/README.md` — never typed, never copied.

**Art: reuse, do not generate.** `upgrade_1.png` is an existing 32×32 weapon-crate sprite that no
scene, script or resource references. Generating a new sprite would spend the capped monthly
PixelLab allowance on an asset the project already has. (Rejected: recolouring
`ship_module_unlocker.png` — it depicts a *ship schematic*, which reads as the module bench and
would be indistinguishable in-world from the pickup it sits next to.)

### `UpgradeState.STARTING_IDS`

`_ready()` currently hard-codes `_unlocked[&"default"] = true`. The invariant test needs to know
which ids legitimately have no pickup, and "every id except `default`" hard-coded in a test is a
second copy of that fact. So:

```gdscript
## Ids a fresh profile starts with. Everything else in ALL_IDS must be granted by a
## WeaponModeUnlockerPickup in the world — gated by
## tests/integration/test_weapon_unlock_sources.gd.
const STARTING_IDS: Array[StringName] = [&"default"]
```

`_ready()` loops over it. This is also the pointer-comment the work item asked for: the next
person grepping `upgrade_state.gd` finds the unlock path named in the file itself.

Rejected alternative: a `starting: bool` flag or a per-id dictionary in `ALL_IDS`. `ALL_IDS` is
consumed as a flat ordered list by `unlocked_ids()`, `_load()` and `WeaponState._load_modes()`;
changing its shape touches four call sites to express one boolean about one id.

### Hub placement

Four instances in `sector_hub.tscn`, a fourth bench row at `y = -515`, `x` stepping 100 from
`-280`, matching the module rows at `-315`/`-415`:

| Node | weapon | position |
|---|---|---|
| `WeaponUnlockerSniperShot` | `SNIPER_SHOT` (0, default value → no property line) | `(-280, -515)` |
| `WeaponUnlockerSpread` | `SPREAD` (1) | `(-180, -515)` |
| `WeaponUnlockerGatling` | `GATLING` (2) | `(-80, -515)` |
| `WeaponUnlockerMiningLaser` | `MINING_LASER` (3) | `(20, -515)` |

This is a **bench**, not designed progression: the existing module unlockers are laid out the same
way and this change is about removing dead content, not authoring a reward curve. Gating weapon
modes behind missions is a separate design question and is called out in "Out of scope".

### `_WEAPON_ICONS` key `&"piercing"`

`player_menu.gd:13` maps `&"piercing"` → `icon_ship_weapon_pierce.png`. `&"piercing"` is not in
`ALL_IDS` (the id is `&"sniper_shot"`; the rename predates the current catalogue), so that entry
is unreachable and `sniper_shot` resolves to `null` in `_WEAPON_ICONS.get(id, null)`.

Today that is invisible because no unlocked id ever reaches it. **This change is what makes it
visible** — the first `sniper_shot` pickup puts an iconless row in the menu — so re-keying it to
`&"sniper_shot"` is part of this work, not a drive-by. A sniper round is the piercing shot the
icon depicts; no new art.

## Build sequence

1. **Test first — `tests/integration/test_weapon_unlock_sources.gd`.** Fails: no such class, no
   pickups in the hub. (Written against the API step 2 will create.)
2. `UpgradeState.STARTING_IDS` + `_ready()` loop + the pointer comment.
3. `weapon_mode_unlocker_pickup.gd`.
4. Mint a UID; write `weapon_mode_unlocker_pickup.tscn`; `godot --headless --import`.
5. Add the four instances to `sector_hub.tscn`. Test from step 1 goes green.
6. Re-key `_WEAPON_ICONS` `&"piercing"` → `&"sniper_shot"`; add the icon-coverage assertions to
   the same test file.
7. `bash /agent/verify.sh`; `updating-project-docs`.

Each step is independently checkable; steps 1–5 are the feature, 6 is the visible consequence.

## Test plan

`tests/integration/test_weapon_unlock_sources.gd` — INVARIANT (not characterization), stated as
such in a header comment. Loads `sector_hub.tscn` and instantiates **without** adding to the tree
(the hub's `_ready()` spawns drones and builds a HUD).

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
5. **Boundary — `test_collecting_an_unlocker_actually_unlocks_the_mode`.** The four tests above
   all pass against a pickup whose `_collect()` is empty. This one uses the `SaveSandbox` helper,
   builds a fresh `UpgradeState` instance, calls `_collect(null)` on a real pickup instance and
   asserts `is_unlocked(&"gatling")` flips false → true. It is the only test that proves the
   pickup does the thing.
6. **Boundary — `test_every_all_id_has_a_menu_icon`** over `PlayerMenu._WEAPON_ICONS`: every id in
   `ALL_IDS` is a key, and every key is in `ALL_IDS`. The second half is what catches the stale
   `&"piercing"`; the first half is what stops the next weapon mode landing iconless.

Existing tests that must stay green: `tests/unit/test_upgrade_state.gd` (pins `_ready()` seeding —
`STARTING_IDS` must not change observable behaviour), `test_weapon_mode_catalogue.gd`,
`test_project_load_integrity.gd` (loads the new `.tscn`), `test_resource_uid_integrity.gd` (the
minted UID must be canonical and unique), `test_suite_integrity.gd`.

## Risks

- **`_collect(null)` in test 5.** `PickupBase._collect(_player: PlayerBase)` ignores its argument
  and the override will too, but the signature is typed. Passing `null` is legal for an object
  parameter in GDScript; if it is not, the test builds a bare `PlayerBase`-typed local instead.
- **Autoload vs. instance in test 5.** `UpgradeState` is a live autoload during the suite; writing
  to it would leak state into other tests. `test_upgrade_state.gd` already solves this with
  `SaveSandbox` + a fresh script instance, and this test follows it. The pickup calls the autoload
  by name, so test 5 asserts against a fresh instance's `unlock()`/`is_unlocked()` pair directly
  rather than through `_collect()` if the autoload cannot be substituted — the value proved is the
  same only if `_collect()` is exercised, so: if substitution is impossible, sandbox the autoload
  via `SaveSandbox` and restore, rather than weakening the assertion.
- **Icon re-key.** If `icon_ship_weapon_pierce.png` was actually drawn for a future `piercing`
  mode rather than for `sniper_shot`, the menu shows a slightly-off icon. Cheap to change, no
  behaviour depends on it, and an iconless row is worse.
- **Scene-file edit by hand.** `sector_hub.tscn` is edited as text (no GUI in this container).
  `test_project_load_integrity.gd` and the import step catch a malformed result.

## Out of scope

- **Progression design.** Which mission or boss should grant which weapon, costs, or an unlock
  order. The bench mirrors what the ship modules already do; turning either into authored
  progression is one epic, not this task.
- Removing `UpgradeState.unlock_all()` — a useful debug affordance, and `test_upgrade_state.gd`
  covers it.
- Sub-weapons (`RocketState`) — a separate store with its own selection path, not gated by
  `UpgradeState`.
- Retuning any weapon `.tres`. The four modes ship at their current numbers; whether Gatling is
  balanced at 14 damage / 0.06s is a question that can only be asked once they are reachable.
- The `player_menu.gd` header comment naming a stale path (`global/ui/dialog_system/playermenu/`).
