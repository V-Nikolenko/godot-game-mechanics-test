# Ship module unlock gate

> **Revision 1** (after `4-review.md` round 1, `VERDICT: CHANGES_REQUESTED`). Changed:
> the 14 missing unlock sources are now *in scope* and ship in this change (finding 1);
> `unlocked_ids()` and `unlock_all()` are dropped rather than added dead (findings 2 and 4);
> the "None" row is stated non-lockable everywhere, not just in the tests (finding 3); the
> locked presentation now mirrors `MissionListItem` instead of inventing a colour (smaller item
> 1); `_locked` sizing, the grandfather ordering, and the fourth broken existing test are all
> called out (smaller items 2–4); the misattributed citation in `2-research.md` is corrected
> (smaller item 5).

## Problem
Today the ship menu lets the player install any of the 15 modules from the moment they first open
it. `ShipModuleState.equip()` (`global/autoloads/ship_module_state.gd:74`) validates the slot and
the id against the catalogue but never looks at `_unlocked`, and `is_unlocked()` has **no caller
anywhere in the game** — only tests. The `ShipModuleUnlockerPickup` sitting in the sector hub says
"Trajectory Calculator module acquired!" and grants something the player already had.

After this change: a module the player has not recovered still appears in the list, greyed, and
cannot be installed. Collecting its unlocker pickup is what turns it on. A player already flying
with a module keeps it — the save is migrated, not confiscated. And every one of the 15 modules
has a pickup that grants it, so nothing becomes unreachable.

## Design

**Gate in the autoload, present it in the menu the way the mission list already does, migrate on
load, and ship the unlock sources in the same change.**

1. **`ShipModuleState.equip()` refuses a locked module.** Same shape as the catalogue check one
   line above it: `push_warning`, no state change, no signal. **`&""` (unequip) is always
   allowed** — the player can always take a module *out*, and a gate that could trap a module in
   a slot would be a worse bug than the one being fixed.
2. **`_load()` grandfathers an equipped-but-locked module.** If a save has `weapons = pierce` and
   `pierce` is not in `weapons_unlocked` — which is every save written before this change — the id
   is appended to the slot's unlocked list *before* it is assigned to `_unlocked[slot]`
   (`ship_module_state.gd:116-122`), so the invariant *equipped ⇒ unlocked* holds from then on.
   This is the migrate-on-load pattern from `2-research.md`: the old state is self-describing, so
   no version stamp is needed. It is not written back from inside `_load()` — the next `_save()`
   persists it, and re-running the migration on a later boot is idempotent.
3. **No new autoload API.** `is_unlocked(slot, id)` already exists and is all the menu needs.
   An `unlocked_ids()` mirror of `UpgradeState` would have **zero callers** under the grey-don't-
   filter design, and an `unlock_all()` mirror would have zero in-game callers *and* would append
   the `&""` sentinel that `SLOT_MODULES` puts first in every slot list. Adding dead API in the
   change whose entire purpose is to retire dead API is not worth the symmetry.
4. **`ModuleList` greys locked rows instead of hiding them** (`2-research.md`, findings 1–3):
   `open()` asks `ShipModuleState.is_unlocked()` per row, `ModuleListItem.configure()` takes a
   third `locked` argument (defaulting to `false`), and the row's description is replaced with
   `LOCKED — recover this module's unlocker to install it.` followed by the module's own
   description, so the greyed row carries its own call to action. `confirm()` on a locked row is a
   defined no-op: it emits nothing and the list stays open — exactly what
   `MissionSelectMenu._try_confirm()` (`mission_select_menu.gd:311-314`) already does for a locked
   mission.
   - **The "None" row (`&""`) is never locked**, in either the visuals or `confirm()`. It is
     tested explicitly, because `is_unlocked(slot, &"")` returns `false` (nothing ever appends
     `&""` to `_unlocked`), so a naive per-row call would grey out the unequip row.
   - `_locked` is built alongside `_descs`, one entry per **created item** (`open()` creates
     `mini(_ids.size(), MAX_ITEMS)` of them, `module_list.gd:34`), and every read is index-guarded
     the same way `confirm()` already guards `_cursor_row` (`module_list.gd:68`).
5. **Reuse the existing locked-row presentation.** *(Corrected during implementation: review
   round-2 note 2 is right that `MissionListItem._COLOR_LOCKED` and
   `ModuleListItem._GREY_MODULATE` are the **same** `Color(0.45,0.45,0.45)`, so borrowing the
   constants verbatim would leave the selectable "None" row and the locked rows identical at
   rest. Taking the option the reviewer allowed: the structure and the precedence rule come
   from `MissionListItem`, but locked rows get their own darker values —
   `_LOCKED_MODULATE` `(0.30,0.30,0.32)` and `_LOCKED_CURSOR_MODULATE` `(0.50,0.50,0.52)` — so
   "nothing installed" and "cannot install this" are distinguishable without the cursor.)*
   `MissionListItem`
   (`open_space/scenes/mission_select_ui/mission_list_item.gd:13-14,21,37,39-43`) already solved
   this: a `_locked` flag set in `configure()`, `_COLOR_LOCKED` `(0.45,0.45,0.45)` and a distinct
   `_COLOR_LOCKED_HOVERED` `(0.65,0.65,0.65)` so the cursor stays findable on a row it cannot
   pick. `ModuleListItem` takes the same two constants and the same precedence rule. Note this is
   *not* the same as reusing its existing `_GREY_MODULATE`: that value is already spoken for by
   the selectable "None" row, so locked rows get the lighter hovered variant to stay
   distinguishable under the cursor. Locked rows keep their real name and icon — unlike a locked
   mission's `??`, a module name is the goal, not a spoiler (`2-research.md`, finding 3).
6. **Every module gets an unlock source, in this change.** There is exactly one
   `ShipModuleUnlockerPickup` in the project (`open_space/scenes/levels/sector_hub.tscn:95`,
   overriding only `position`, so it grants the script defaults `COCKPIT`/`TRAJECTORY_CALC`).
   Gating without adding sources would take reachable modules from 15 to 1. The sector hub is
   already documented as a pickup bench — "a row of every shared pickup from
   `global/pickups/scenes/` … so the hub doubles as a test/equip bench"
   (`docs/architecture/modules/open_space.md:63`) — so the remaining 14 unlockers join that bench
   as two further rows above the existing one, each with its `module_slot` / `module_id` exports
   set. This is a dev/test bench, not final content placement: distributing unlockers through
   missions is content authoring and stays out of scope.

### Alternatives rejected
- **Filter locked modules out of the list.** A fresh profile would open the weapons slot onto a
  single "None" row — indistinguishable from a broken menu, and it throws away the motivational
  value of the unlock system (`2-research.md`, finding 3).
- **Delete the unlock store as dead code.** Defensible on the evidence that nothing reads it, but
  `docs/superpowers/plans/2026-05-26-pickup-system.md` built the pickup as "the unlock path", and
  the save format, the signal and the pickup all already exist.
- **Gate now, place unlock sources later.** Rejected in review: it makes 14 of 15 modules
  unreachable for however long "later" is, and contradicts finding 3.
- **Ship `unlock_all()` as the escape hatch instead of real pickups.** A debug function is not a
  substitute for the content being reachable in play.
- **Seed a starter module per slot.** Would be inventing content: every module is a pure additive
  bonus, so four empty slots is a complete, playable ship (`2-research.md`, judgement calls).
- **Drop equipped-but-locked modules on load.** Confiscates the loadout of anyone mid-playthrough
  to satisfy an invariant they never agreed to.
- **Auto-equip on unlock.** Tempting QoL, but a separate design decision that changes what the
  pickup does, and it can be added later without touching any of this.

## Build sequence
1. **Tests first** — rewrite `tests/unit/test_ship_module_state.gd` for the new contract. Run the
   suite and watch the new assertions fail.
2. **`ship_module_state.gd`** — the unlock check in `equip()`, the grandfather branch in
   `_load()`, and the now-false comment on `_unlocked` (l.39, "equipping doesn't require
   unlocking"). Suite green.
3. **`module_list_item.gd`** — `_is_locked`, third `configure()` argument, `MissionListItem`'s two
   locked colours in `_update_modulate()`.
4. **`module_list.gd`** — `_locked: Array[bool]` filled in `open()`, locked description prefix,
   `confirm()` no-op on a locked row.
5. **`sector_hub.tscn`** — 14 further `ship_module_unlocker_pickup.tscn` instances with
   `module_slot`/`module_id` set, laid out as two rows above the existing bench row (y ≈ -215,
   x from -280 to 519, ~100 px spacing), reusing `ExtResource("13_b4ymh")`.
6. **Tests for the UI and the bench** (below).
7. `bash /agent/verify.sh` — note its step 2 boots the **main scene, which is the sector hub**
   (`project.godot:18` → `uid://bj5rbqgudkfsg`), so a malformed scene edit fails the gate loudly.
8. `updating-project-docs`.

## Test plan

`tests/unit/test_ship_module_state.gd` (existing; **four existing tests equip without unlocking
and must unlock first** — `test_equip_sets_the_slot_and_emits` l.38,
`test_equipping_the_same_module_twice_emits_nothing` l.48,
`test_swapping_modules_emits_unequip_then_equip` l.58,
`test_unequipping_emits_only_unequipped` l.69, plus
`test_equipped_and_unlocked_survive_a_save_load_round_trip` l.127 which equips `shooting`
unlocked. That churn is the point of a characterization suite):
- `test_equipping_requires_unlocking` — **replaces** `test_equipping_does_not_require_unlocking`
  (l.117), with a comment recording that the behaviour changed deliberately and pointing here.
  Equip a locked module → slot stays `&""`, no `module_equipped`.
- `test_equipping_works_after_unlocking` — unlock then equip → slot set, signal fired once.
- `test_unequipping_never_requires_an_unlock` — **boundary**: unlock+equip, then `equip(slot, &"")`
  still clears the slot and emits `module_unequipped`.
- `test_load_grandfathers_a_module_equipped_before_the_gate` — write a cfg with
  `weapons = "pierce"` and **no** `weapons_unlocked` key, `_load()`, assert
  `is_unlocked(&"weapons", &"pierce")`, then unequip and re-equip `pierce` to prove the migration
  is usable and not just a flag. Fails loudly if design point 2 is dropped.
- `test_load_does_not_grandfather_an_unknown_equipped_id` — **boundary**: the existing
  `test_load_drops_a_module_id_that_is_no_longer_valid` (l.142) case must not now unlock
  `removed_in_a_later_patch` on its way out.
- Untouched and still meaningful: cross-slot rejection, unknown-slot rejection, duplicate unlock,
  the catalogue-shape test.

`tests/integration/test_module_list_lock.gd` (new — `unit/` forbids scene loading, `integration/`
already instantiates scenes):
- Uses `SaveSandbox` **and** snapshots/restores the live `ShipModuleState._unlocked` and
  `_equipped` in `before_all`/`after_all`, because `ModuleList` reads the singleton and the whole
  suite shares it.
- `test_locked_rows_are_marked_and_unlocked_ones_are_not` — unlock `pierce` only, open the
  weapons slot, assert 6 rows and that exactly the `pierce` row is unlocked among the modules.
- `test_the_none_row_is_never_locked` — **boundary**, from review finding 3: with nothing
  unlocked, row 0 must not be locked and confirming it must emit `confirmed(&"")`.
- `test_confirming_a_locked_row_emits_nothing` — cursor onto a locked row, `confirm()`, assert no
  `confirmed` signal.
- `test_confirming_an_unlocked_row_still_emits` — the control case, so the test above cannot pass
  by breaking `confirm()` outright.

`tests/integration/test_module_unlock_sources.gd` (new — an **invariant** test, not
characterization, and it says so in its header): load `sector_hub.tscn`, walk it for
`ShipModuleUnlockerPickup` nodes, and assert the set of `(slot, module_id)` they grant covers
every non-`&""` id in `ShipModuleState.SLOT_MODULES`. This both verifies the scene edit and stops
a future module being added to the catalogue with no way to obtain it — the exact failure the
review caught.

## Risks
- **The suite shares the live `ShipModuleState`.** Mitigated by the snapshot/restore above; if it
  proves fragile the integration test drops to asserting `ModuleListItem` visuals only, and the
  gate still covers the autoload logic.
- **Hand-edited `.tscn`.** 14 instance blocks written by hand can break the main scene. The gate
  boots that exact scene (step 7) and `test_module_unlock_sources.gd` re-loads and walks it, so a
  mistake fails, not slips.
- **`push_warning` in `equip()` on a locked module** — GUT does not fail on warnings
  (`tests/README.md`), so the refusal tests stay green.
- **A player mid-run finds a module they had unlocked-but-not-equipped is still locked.** Only
  possible for a save where the pickup was collected but never used — that state is already
  recorded correctly in `*_unlocked` and stays unlocked, so no loss.

## Out of scope
- Distributing module unlockers through missions, or deciding which mission grants which module.
- Auto-equipping on unlock.
- Any change to `ship_modules_panel.gd`, the two player scripts, or the pickup script itself.
