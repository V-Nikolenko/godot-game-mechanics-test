# Review — Ship module unlock gate (stage 4)

VERDICT: CHANGES_REQUESTED

Reviewed against the actual source, not the plan's summary of it. The core diagnosis is
**correct and verified**, the research is real, and the scope is finishable in one session.
Four changes are required before implementation, plus four smaller ones.

## Verified as accurate

- `equip()` (`global/autoloads/ship_module_state.gd:74-90`) validates slot (l.75) and catalogue
  membership (l.79) and never touches `_unlocked`. Confirmed.
- `is_unlocked()` (`ship_module_state.gd:70-72`) has **no non-test caller**. A repo-wide grep for
  `ShipModuleState.` returns only `SLOTS`/`SLOT_MODULES`/`get_equipped`/`equip`/`unlock` and the
  two signal connections. Confirmed.
- The two module re-apply paths read `get_equipped()` only — `assault/scenes/player/player_fighter.gd:32-35`
  and `open_space/scenes/entities/player/player_ship.gd:59-62`. Neither calls `equip()`, so a
  grandfathered module is not stripped on spawn. The plan's "no change needed" holds.
- `push_warning` is explicitly not a GUT failure (`tests/README.md`, "House rules learned the hard
  way", signal-arity bullet). Risk 4 in the plan is correctly assessed.
- No `CLAUDE.md` convention is violated: no new component, no `.tres`-driven stats, no
  640x360/`ArenaCamera.WORLD_SCALE` coordinates in play.
- The test plan has genuine edge cases that can fail: unequip-while-locked, `unlocked_ids` on an
  empty store, catalogue-order-vs-unlock-order, and the migration test written from a raw
  `ConfigFile` with no `weapons_unlocked` key. `test_load_grandfathers_a_module_equipped_before_the_gate`
  really does go red if design step 4 is dropped.

## Required changes

### 1. BLOCKING — the gate makes 14 of the 15 modules permanently unobtainable

There is exactly one `ShipModuleUnlockerPickup` instance in the entire project:
`open_space/scenes/levels/sector_hub.tscn:95`. It overrides only `position` (l.96), so it uses the
script defaults `Slot.COCKPIT` / `Module.TRAJECTORY_CALC`
(`global/pickups/ship_module_unlocker_pickup.gd:18-19`). There is no other writer of `_unlocked`
anywhere.

So the moment `equip()` consults `_unlocked`, the reachable module count drops from 15 to 1. The
ship menu becomes one installable row and fourteen grey rows the player can never turn on, forever.
That is precisely the criterion "leaves game content unreachable", and the plan's own research
argues against it: `2-research.md` finding 3 says a locked entry "only pays off if the player can
see *how* to get it; a locked row with no stated source is worse than no row." A hardcoded
"recover this module's unlocker" description does not satisfy that when no such unlocker exists in
the world.

"Placing module unlocker pickups in missions" being out of scope is fine. Shipping the gate
*without* any replacement for the reachability it removes is not. Required: in the same change,
keep all 15 reachable. The cheapest option consistent with the repo is to add the remaining 14
`ship_module_unlocker_pickup.tscn` instances to `sector_hub.tscn`, which already functions as a
pickup bench (it holds one of every other pickup type — see l.91-110). That is a scene edit, no new
art, no design call about which mission grants what, and it can be replaced by real placement later.
If you prefer a different mechanism, say which — but the gate cannot land with 14 dead modules.

Do not lean on `unlock_all()` for this: it has no in-game caller and the player cannot invoke it.

### 2. BLOCKING — `unlocked_ids(slot)` would have zero callers

Design bullet 2 adds `unlocked_ids(slot)` "mirroring `UpgradeState.unlocked_ids()`". But the
mirror does not hold. `UpgradeState.unlocked_ids()` (`global/autoloads/upgrade_state.gd:56`) has six
real consumers: `assault/scenes/player/states/weapon_state.gd:48` and `:139`, and
`global/ui/player_menu/player_menu.gd:125`, `:157`, `:190`, `:210`. The chosen design for modules is
*grey, don't filter*, so `ModuleList` needs the full catalogue plus a per-row flag — it will call
`is_unlocked()`, never `unlocked_ids()`.

Adding a public API with no consumer, in the change whose entire justification is that
`is_unlocked()` had no consumer, is self-defeating. Either delete bullet 2 (and its test), or name
the caller that will use it in this change.

### 3. BLOCKING — `&""` must be exempted from the row lock, or the menu traps the player

Design bullet 5 says `open()` "asks `ShipModuleState.is_unlocked()` per row". Taken literally that
locks the None row: `_unlocked` never contains `&""` (nothing appends it — `ship_module_state.gd:63-66`),
so `is_unlocked(slot, &"")` returns `false` (l.70-72). Row 0 of every slot
(`SLOT_MODULES`, l.20-25, always starts with `&""`) would then be greyed and `confirm()` would
no-op on it, so **the player could never unequip from the menu** — the exact trap bullet 1 says it
is avoiding at the autoload layer, reintroduced one layer up. `player_menu._on_module_confirmed()`
(`global/ui/player_menu/player_menu.gd:180-184`) is the only equip path, so there is no workaround.

The integration test's wording ("the `pierce` row plus the 'None' row are unlocked") implies the
right behaviour, but the design text must state it: `&""` is always unlocked/selectable, in
`ModuleList` and in `equip()`.

### 4. BLOCKING — `unlock_all()` will persist `&""` into `_unlocked` if written as a mirror

`UpgradeState.unlock_all()` (`upgrade_state.gd:63-65`) iterates `ALL_IDS`, which contains no empty
entry. `SLOT_MODULES[slot]` does — `&""` is element 0 of all four slots
(`ship_module_state.gd:20-25`) — and `unlock()` validates against that same list (l.59-62), so it
will happily accept `&""`, append it (l.66), `_save()` it (l.99), and `_load()` will keep it because
it is `in valid` (l.120). The store then permanently contains a bogus id, and any `unlocked_ids()`
that also prepends `&""` returns it twice. `unlock_all()` must skip `&""` explicitly, and say so in
the plan.

## Smaller changes

### 5. Reuse the project's own locked-row UI, not just `UpgradeState`

The plan cites two web sources and `UpgradeState`, but the repo already ships a greyed-locked list
with a defined no-op confirm — `open_space/scenes/mission_select_ui/`:

- `mission_list_item.gd:13-14` defines `_COLOR_LOCKED := Color(0.45,0.45,0.45)` **and**
  `_COLOR_LOCKED_HOVERED := Color(0.65,0.65,0.65)`; `set_hovered()` (l.39-43) returns early for a
  locked row so the cursor tint never applies. That is exactly the "dimmed cursor tint" build step 3
  describes, already written.
- `configure(mission, locked)` (l.23) is the same signature shape being proposed for
  `ModuleListItem.configure()`.
- `mission_select_menu._try_confirm()` (l.311-314) is the shipped "confirm no-ops on a locked row"
  precedent.
- `MissionConfigResource.locked_description`, used at `mission_select_menu.gd:250`, is the shipped
  "tell the player why it is locked" precedent.

Nothing here is a reinvented *component*, so this is not a rejection — but mirror the naming and
behaviour rather than deriving it from a forum thread.

Related: `ModuleListItem._GREY_MODULATE` (`module_list_item.gd:10`) is **already** the None row's
colour (used at l.47). If locked rows reuse it, the one selectable row in a fresh profile looks
identical to the five unselectable ones. Use a distinct locked colour, as `mission_list_item.gd`
does.

### 6. `_locked` must be indexed safely in `confirm()`

`ModuleList.open()` creates `mini(_ids.size(), MAX_ITEMS)` items (`module_list.gd:34`) while `_ids`
keeps the full catalogue (l.33), and `confirm()` bounds-checks against `_ids.size()` (l.68). The new
locked check must bound-check against `_locked.size()` (or fill `_locked` to `_ids.size()`), or a
future slot with more than `MAX_ITEMS` = 8 entries indexes out of range.

### 7. Migration must append after `_unlocked[slot]` is rebuilt

In `_load()` the equipped id is resolved at l.109-115 but `_unlocked[slot] = list` is assigned last,
at l.122. A grandfather append written before that line is silently discarded. State the ordering in
the plan so the implementer does not have to rediscover it.

### 8. Name `test_equipped_and_unlocked_survive_a_save_load_round_trip` in the churn list

The plan says "several tests equip without unlocking and must be updated". Concretely that is
`tests/unit/test_ship_module_state.gd` l.38, l.48, l.58, l.69, l.117 **and l.127** — the round-trip
test equips `shooting` without unlocking it (l.130), so after the gate nothing is written and the
assertion at l.136 fails. It is the least obvious of the six; call it out explicitly.

### 9. Research citation does not support its finding

`2-research.md` row 2 claims greyed entries keep a fixed menu position and preserve muscle memory,
and sources it to uichallenges.design with the quote *"hide the things you have no access to (or
heavily gray out the buttons)"*. That quote says nothing about position or muscle memory, and its
leading recommendation is hiding — the alternative the plan rejects. Either substitute a source that
supports the claim or move it to "Judgement calls (no citable source)", where it stands fine on its
own.

## Not blocking

- The migrate-on-load design (design bullet 4) is sound and idempotent, and not writing back from
  inside `_load()` is the right call.
- Always allowing `equip(slot, &"")` (design bullet 1) is correct and necessary.
- Instancing `module_list.tscn` headless should work — it is `Node2D` + `Sprite2D` + `RichTextLabel`
  with no shader (`global/ui/player_menu/module_list.tscn`), and `tests/integration/` already
  instances scenes. The stated fallback is reasonable.
- Snapshot/restore of the live `ShipModuleState` in the integration test, on top of `SaveSandbox`
  (`tests/helpers/save_sandbox.gd:16-22` already covers `user://ship_modules.cfg`), is the right
  precaution.
- Scope is one session's work — two autoload methods, two small UI files, two test files, and (with
  change 1) one `.tscn` edit.

## Re-review

Update `3-plan.md` for items 1-4 at minimum, then re-submit. Items 5-9 can be folded into the same
revision.
