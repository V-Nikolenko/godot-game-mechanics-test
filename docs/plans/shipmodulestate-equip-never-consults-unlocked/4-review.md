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

---

# Review round 2

VERDICT: APPROVED

Re-reviewed `3-plan.md` (Revision 1) against the actual source, not the plan's account of it.
All four blocking findings from round 1 are genuinely resolved, and all five smaller ones are
addressed. Three non-blocking notes below — note 1 is a *must-do* one-liner that the plan asserts
but does not spell out, and it has no test behind it; please fold it in during implementation.

## Round-1 findings — verification

**1 (BLOCKING, gate makes 14 of 15 modules unreachable) — RESOLVED.**
Design point 6 and build step 5 put the 14 missing unlockers in `sector_hub.tscn` in the same
change, and `tests/integration/test_module_unlock_sources.gd` turns "every catalogue id has a
source" into an enforced invariant. Verified feasible against real source:
- `open_space/scenes/levels/sector_hub.tscn:16` really does declare
  `id="13_b4ymh"` for `res://global/pickups/scenes/ship_module_unlocker_pickup.tscn`, so the
  reuse cited in build step 5 is correct and adds no `[ext_resource]` line — meaning
  `tests/integration/test_resource_uid_integrity.gd` is unaffected.
- `sector_hub.tscn:95-96` is the single existing instance and overrides only `position`, so the
  plan's claim it falls back to `Slot.COCKPIT` / `Module.TRAJECTORY_CALC`
  (`global/pickups/ship_module_unlocker_pickup.gd:18-19`) is correct. A repo-wide grep for
  `ship_module_unlocker_pickup.tscn` in `*.tscn` returns only `sector_hub.tscn`.
- The export names in build step 5 are right: `module_slot` and `module_id`
  (`ship_module_unlocker_pickup.gd:18-19`). Both are enums, so in the `.tscn` they serialise as
  **ints** (e.g. weapons/pierce = `module_slot = 2`, `module_id = 11` per the flat `Module` enum
  at `ship_module_unlocker_pickup.gd:7-16`). The `Module` enum is flat across slots, so a
  mismatched pair (cockpit + `PIERCE`) is expressible and would only `push_warning` at collect
  time — `test_module_unlock_sources.gd` is what catches it. Good that it is in scope.
- `unique_id=` on the node headers is **optional**: 543 of the 1047 `[node]` lines in the repo omit
  it, including whole gameplay scenes (`assault/scenes/enemies/bomber/bomber.tscn`). Hand-written
  instance blocks without it will load; Godot assigns one on next save.
- `project.godot:18` is indeed `run/main_scene="uid://bj5rbqgudkfsg"`, matching
  `sector_hub.tscn:1`. Build step 7's claim that the gate boots this exact scene holds.
- Coordinates are sane. The existing bench row is y ∈ [-223, -210], x ∈ [-280, 519]
  (`sector_hub.tscn:86-111`). `Background` spans y from -1791, so rows above are inside it. The
  nearest hazard is `voeter_k05m` at (-530, -384) with a `CircleShape2D` radius 230
  (`mission_select_hubs/mission_select_hub.tscn`); at x = -280 the horizontal gap alone is 250, so
  the whole proposed x range clears the planet's dwell trigger at any y. 14 pickups fit: x from
  -280 to 519 at ~100 px is 9 columns per row, 18 slots for 14 instances.
- Pickup-dialog spam on flying through the bench is already handled — `PickupBase._show_notification()`
  (`global/pickups/pickup_base.gd:36-40`) silently skips while `DialogPlayer.is_active`.

**2 (BLOCKING, `unlocked_ids(slot)` would have zero callers) — RESOLVED.** Design point 3 drops it
and says why. Confirmed the grey-don't-filter design only needs `is_unlocked()`
(`ship_module_state.gd:70-72`), which `ModuleList.open()` can call per row since it already
receives `slot` (`global/ui/player_menu/module_list.gd:30`).

**3 (BLOCKING, `&""` must be exempt from the row lock) — RESOLVED.** Stated twice and in the right
places: design point 1 for `equip()`, design point 4's first sub-bullet for both the visuals and
`confirm()`, plus a dedicated boundary test `test_the_none_row_is_never_locked`. Re-verified the
trap is real: `SLOT_MODULES` (`ship_module_state.gd:20-25`) starts every slot with `&""`, nothing
appends `&""` to `_unlocked` (l.63-66), and `player_menu.gd:182` is still the only `equip()` caller
in the project (repo-wide grep for `.equip(` outside `tests/` returns exactly that one line).

**4 (BLOCKING, `unlock_all()` would persist `&""`) — RESOLVED by removal.** Design point 3 drops
`unlock_all()`. See note 1 — the same `&""` hazard now lives in the `_load()` migration instead.

**5 (reuse `MissionListItem`) — RESOLVED.** All cited lines check out:
`open_space/scenes/mission_select_ui/mission_list_item.gd:13-14` (`_COLOR_LOCKED`,
`_COLOR_LOCKED_HOVERED`), `:21` (`_locked`), `:23` (`configure(mission, locked)`), `:37`, `:39-43`
(early return for locked in `set_hovered`). `mission_select_menu.gd:309-314` is the locked-confirm
no-op and `:250` the locked-description precedent. See note 2 on the colour value.

**6 (`_locked` sizing) — RESOLVED**, second sub-bullet of design point 4; `module_list.gd:34` is
indeed `mini(_ids.size(), MAX_ITEMS)` and `:68` the existing guard. See note 3.

**7 (migration ordering) — RESOLVED.** Design point 2 names `ship_module_state.gd:116-122` and
requires the append before `_unlocked[slot] = list` at l.122. Verified: l.112-113 resolves the
equipped id, l.116-121 builds `list`, l.122 assigns. An append written after l.122 is discarded.

**8 (name the round-trip test) — RESOLVED.** The churn list in the test plan names l.38, l.48,
l.58, l.69, l.117, l.127 and l.142. All seven line numbers are correct in
`tests/unit/test_ship_module_state.gd`, and l.130 (`writer.equip(&"weapons", &"shooting")` with no
unlock) is the failure the round-trip test would hit.

**9 (weak citation) — RESOLVED.** `2-research.md` row 2 now carries an explicit
"**Weak citation — flagged in review**" caveat and demotes the muscle-memory reasoning to a
judgement call.

## Standard bar

- **No reinvention.** Nothing new in `global/components/`; the locked presentation is lifted from
  the shipped `MissionListItem`, the migration from the shipped `_load()` validation shape.
- **No `CLAUDE.md` conflict.** No inheritance added, no `.tres` stat path touched, no
  640x360 / `ArenaCamera.WORLD_SCALE` coordinates involved (the `sector_hub.tscn` positions are
  open-space world coordinates, not assault design units).
- **Tests can fail.** `test_load_grandfathers_a_module_equipped_before_the_gate` goes red if design
  point 2 is dropped; `test_the_none_row_is_never_locked` red if finding 3 regresses;
  `test_load_does_not_grandfather_an_unknown_equipped_id` is a real boundary against
  `test_load_drops_a_module_id_that_is_no_longer_valid` (l.142);
  `test_confirming_an_unlocked_row_still_emits` is a proper control for the locked-confirm test;
  `test_module_unlock_sources.gd` fails the moment a 16th module is added without a source.
- **Alternatives.** Seven listed, including the three the review pushed back on.
- **Scope.** One session: two autoload edits, two small UI files, 14 `.tscn` instance blocks, one
  rewritten and two new test files, plus docs. `ModuleList` is `Node2D` + `Sprite2D` +
  `RichTextLabel` with no shader (`global/ui/player_menu/module_list.tscn`), so headless
  instantiation is safe; note it must be added to the tree for the `@onready _description_lbl`
  (`module_list.gd:18`) to resolve.

## Non-blocking notes for the implementer

**1. MUST: guard the grandfather append with `id != &"" and id not in list`, and assert it.**
Design point 2 says the migration is "idempotent" but never says how, and the naive form is wrong
in two ways. In `_load()` the equipped id reaches `_equipped[slot] = id` through
`if id in valid` (`ship_module_state.gd:112`) — and `&""` **is** in `valid`, because
`SLOT_MODULES` lists it first for every slot (l.20-25). So `if id in valid: list.append(id)` would
(a) append `&""` to all four slots on essentially every load, recreating exactly the bogus-id
pollution that round-1 finding 4 rejected in `unlock_all()`, and (b) for a genuinely unlocked +
equipped module, append a duplicate that `_save()` writes back and the next `_load()` duplicates
again — the list grows by one entry per boot, unbounded. Note l.114 already uses the
`elif id != &""` idiom one line away. No test in the plan catches either: `is_unlocked()` stays
`true` under both, so every listed assertion still passes. Add the exact-array assertion to
`test_load_grandfathers_a_module_equipped_before_the_gate` —
`assert_eq(reader._unlocked[&"weapons"], [&"pierce"] as Array[StringName])` — and load twice in
that test, which pins the `&""` exemption and idempotence in one line each.

**2. `_COLOR_LOCKED` and `_GREY_MODULATE` are the same colour.** Design point 5 says taking
`MissionListItem`'s constants is "*not* the same as reusing its existing `_GREY_MODULATE`", but
`mission_list_item.gd:13` is `Color(0.45, 0.45, 0.45)` and `module_list_item.gd:10` is
`Color(0.45, 0.45, 0.45)` — identical. So in a fresh profile the selectable "None" row and the
five locked rows look the same **when unhovered**; they only separate under the cursor (yellow
`_CURSOR_MODULATE` 1.4 vs. locked-hovered 0.65), plus the `LOCKED —` description prefix. That is
the same affordance the mission list ships with, so it is acceptable — but the plan's stated
rationale is factually wrong, and if you want the distinction visible at rest, give locked rows a
different unhovered value rather than repeating the claim. Also get the `_update_modulate()`
precedence right: locked must be tested *before* `_is_cursor` (`module_list_item.gd:44-49`), or a
locked row under the cursor lights up yellow as if selectable.

**3. Bound-check `_locked` against `_locked.size()`, not `_ids.size()`.** Design point 4 says every
read is guarded "the same way `confirm()` already guards `_cursor_row` (`module_list.gd:68`)", but
that guard is `_cursor_row < _ids.size()` and `_locked` will have `mini(_ids.size(), MAX_ITEMS)`
entries (l.34). Today the two are equal for all four slots (longest is weapons at 6 vs `MAX_ITEMS`
8), so this is latent, but write it as `_cursor_row < _locked.size()`.

**4. Build step 5's coordinates read ambiguously.** "two rows above the existing bench row
(y ≈ -215, x from -280 to 519, ~100 px spacing)" — y ≈ -215 *is* the existing row
(`sector_hub.tscn:86-111`), so the parenthetical describes the row being mirrored, not where the
new ones go. Use explicit values, e.g. y = -315 and y = -415, x from -280 upward. Both clear the
`voeter_k05m` trigger and sit inside `Background`.

**5. `test_module_unlock_sources.gd`:** instantiating `sector_hub.tscn` without adding it to the
tree does not run `_ready()`, so no drones spawn and no HUD initialises — that is the cheap way to
walk it. Free the instance. Reading `module_slot` / `module_id` back to StringNames is easiest via
the pickup's own `_slot_name()` / `_module_name()` (`ship_module_unlocker_pickup.gd:34-60`); GDScript
does not enforce the leading underscore.
