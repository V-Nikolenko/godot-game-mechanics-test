# Plan review — weapon-mode unlock sources

VERDICT: CHANGES_REQUESTED

The core of the plan is right and I want to say so before the findings: mirroring
`ShipModuleUnlockerPickup` + `test_module_unlock_sources.gd` is the correct call, the enum-not-
`StringName` choice matches the precedent, the UID rule is followed, the "reuse `upgrade_1.png`
rather than spend PixelLab allowance" call is correct, and the plan already caught one downstream
consequence (`_WEAPON_ICONS[&"piercing"]`) that a weaker plan would have shipped as a bug. Four
things need fixing before implementation: two blocking, two that change what gets built.

Everything below was checked against the code, not against the plan's description of it.

---

## Verified as claimed (no action needed)

- **`UpgradeState` has no unlock caller.** `grep` for `UpgradeState.unlock` outside `tests/` returns
  only `upgrade_state.gd:5` (a doc comment) and the `unlocked_ids()` readers in
  `weapon_state.gd:47,138` and `player_menu.gd:125,157,190,210`. `unlock_all()`
  (`upgrade_state.gd:55-57`) is the only caller of `unlock()`, and nothing calls it. The premise of
  the work item holds exactly as stated.
- **`_ready()` seeding** is `upgrade_state.gd:25-29`; looping `STARTING_IDS` inside the existing
  `if _unlocked.is_empty()` guard preserves the behaviour `test_upgrade_state.gd:34-39` pins.
- **`WeaponState` needs no change.** `_load_modes()` (`weapon_state.gd:31-37`) walks `ALL_IDS`, and
  `_cycle()` (`:137-152`) / `select_weapon()` (`:163-166`) read `unlocked_ids()` /
  `is_unlocked()` live. Confirmed.
- **The pickup pattern will actually fire in the hub.** `PickupBase._on_body_entered`
  (`pickup_base.gd:13-23`) requires group `"player"` and a `PlayerBase` cast;
  `open_space/.../player_ship.gd:4` is `class_name OpenSpacePlayerShip extends PlayerBase` and
  `player_ship.tscn:215` sets `collision_layer = 4`, which the pickup's `collision_mask = 4`
  (`ship_module_unlocker_pickup.tscn:120`) matches.
- **`y = -515` is sane and reachable.** `sector_hub.tscn:26-31` gives a Background spanning
  y −1791..2209; `open_space/scenes/entities/player/player_ship.gd` applies no positional clamp and
  the hub has no camera limits, so open space is free flight. The new row at x −280..20 is *farther*
  from `voeter_k05m` at (−530, −384) (`sector_hub.tscn:61-62`) than the existing y = −415 row
  already is, and 100 px spacing clears the 56.5 px pickup diameter.
- **Omitting `unique_id=` on hand-written nodes is fine** — `global/components/shield_icon.tscn`,
  `assault/scenes/enemies/bomber/bomber.tscn` and the module-unlocker instances at
  `sector_hub.tscn:113-176` all lack it.
- **`upgrade_1.png` is unreferenced** (only its own `.import` mentions it) and carries
  `uid://dptqytf5g71or` (`upgrade_1.png.import:5`), so the new scene's `ext_resource` can carry a
  real texture UID without minting anything.

---

## Blocking findings

### 1. The unlock is invisible in the very scene the pickup lives in — and the menu goes incoherent

`1-context.md:39-41` states "`WeaponState` and `PlayerMenu` are both already unlock-driven and
correct… No consumer needs redesign." That is true of `WeaponState` and **not** true of `PlayerMenu`.

`PlayerMenu._populate_lists()` (`global/ui/player_menu/player_menu.gd:189-198`) has exactly one
caller: `connect_states()` (`:46-50`). `connect_states()` has exactly one caller:
`global/ui/mission_hud.gd:19`, `:24` and `:43`, all inside the HUD's `_ready()`. `_toggle()`
(`player_menu.gd:105-118`) refreshes the modules panel, the cursor and the selection but **never
repopulates the weapon column**. Both HUDs embed the menu — `assault/scenes/gui/hud.tscn:62` and
`open_space/scenes/gui/hud.tscn:49` — so the main-weapon column is built once per scene load.

Consequence of this change: the player flies into `WeaponUnlockerGatling` in the sector hub, gets
the "Gatling acquired!" dialog, presses Tab, and sees a one-row main-weapon column. The unlock is
real and persisted, and the next assault mission will show it (that HUD is created after the
unlock) — but the hub, which is where the plan puts all four pickups, gives no confirmation at all.

It is worse than cosmetic. `_init_cursor()` (`:124-141`) and `_confirm_selection()` (`:154-160`)
index the **live** `UpgradeState.unlocked_ids()`, while `_current_max_row()` (`:144-148`) reads the
**stale** `_main_frame.get_count()`. Today those can never disagree, because `unlocked_ids()` never
changes during a scene's lifetime. This change is precisely what makes it change during a scene's
lifetime, so the plan is what introduces the disagreement.

This is the same argument the plan itself makes for `&"piercing"` at `3-plan.md:103-110` — "today
that is invisible… this change is what makes it visible" — applied to a bigger consequence, so the
plan's own standard puts it in scope.

The hook already exists and is unused: `UpgradeState.unlocked_changed` (`upgrade_state.gd:21`,
emitted at `:46`) has **zero** listeners project-wide. Connecting it to
`_populate_lists()` + `_refresh_selection()` in `PlayerMenu._ready()` is the reuse fix and is a few
lines. Either do that (with a test: unlock while the menu exists → the column grows), or state
explicitly why the hub gives no feedback and file it. Silently leaving `1-context.md`'s claim
standing is not an option.

### 2. Test 5 is not implementable as written, and its stated fallback leaks into the rest of the suite

`3-plan.md:142-146` describes test 5 as building "a fresh `UpgradeState` instance, calls
`_collect(null)` on a real pickup instance and asserts `is_unlocked(&"gatling")` flips false →
true". Those two halves do not connect: the pickup body will be
`UpgradeState.unlock(weapon_id())`, which resolves the autoload singleton, not any instance the
test holds. The fresh-instance variant proves `unlock()` works — which
`test_upgrade_state.gd:42-51` already proves — and proves nothing about `_collect()`.

The Risks entry (`3-plan.md:162-167`) sees this but resolves it into a conditional: "if
substitution is impossible, sandbox the autoload via `SaveSandbox` and restore". That does not
work. `tests/helpers/save_sandbox.gd:33-45` restores **files** under `user://`; it does not touch
the live autoload's in-memory `_unlocked` dictionary (`upgrade_state.gd:23`). After the test,
`UpgradeState._unlocked[&"gatling"] = true` persists for the remainder of the GUT process, so
`unlocked_ids()` is permanently different for every later test in the run. That is the exact
cross-test leak `tests/README.md`'s "never let a test touch the real save files" rule exists to
prevent, in its in-memory form.

The project has already solved this and written it down. `tests/README.md:664-668`: *"It reads and
restores the **live `ShipModuleState` singleton** (`_unlocked` / `_equipped`) in
`before_all`/`after_all`, on top of `SaveSandbox` — `ModuleList` talks to the autoload, not to a
fresh instance, and the whole suite shares it."* The implementation is
`tests/integration/test_module_list_lock.gd:24-27` and `:31-40`.

Rewrite test 5 to name that pattern: `SaveSandbox` for the file, plus a `before_all` snapshot and
`after_all` restore of the live `UpgradeState._unlocked` (a `Dictionary`, so `.duplicate()`), then
`_collect(null)` on a real pickup and assert against the live autoload. Delete the conditional
branch — a plan that says "or else do something weaker" gets the weaker thing.

Two smaller notes on the same test: `_collect(null)` is legal (typed object params accept `null`),
so that risk can be struck; and calling `_collect()` directly bypasses `_on_body_entered`'s group
check, which is fine but means the test proves the effect, not the trigger — worth one sentence.

---

## Findings that change what gets built

### 3. There is a second icon map, and the plan picked the more duplicative of two fixes

`WeaponModeResource` already has an `icon` field: `assault/scenes/player/weapons/weapon_mode.gd:11`,
`@export var icon: Texture2D`. It is what the in-game HUD chip draws —
`assault/scenes/gui/weapon_chip.gd:26`, `_icon.texture = mode.icon` — and `WeaponChip` is instanced
in **both** HUDs (`assault/scenes/gui/hud.tscn:62`, `open_space/scenes/gui/hud.tscn:49`).

`grep -n icon assault/scenes/player/weapons/modes/*.tres` returns **nothing**: not one of the five
modes sets `icon`. So `mode.icon` is null everywhere and the HUD weapon chip draws an empty
texture. Today that is one blank icon on the one reachable weapon, so nobody has noticed. After
this change it is four more, on the HUD, during play — a visible consequence of the same class as
`&"piercing"`, and the plan does not mention it.

Meanwhile `PlayerMenu._WEAPON_ICONS` (`player_menu.gd:11-17`) is a second id→icon map over the same
five ids, and `_populate_lists()` (`:189-198`) *already loads the mode resource* for `display_name`
(`:193-195`) — the resource whose `icon` field is sitting empty two lines away.

The unexamined simpler alternative: set `icon = ExtResource(...)` in the five `modes/*.tres`, use
`mode.icon` in `_populate_lists()`, and delete `_WEAPON_ICONS`. One map instead of two, the stale-key
bug class becomes unrepresentable (the id and the icon live in the same file as each other), the
HUD chip is fixed for free, and it needs no new art — the same five PNGs under
`weapon_icons/` are simply referenced from the `.tres` instead of from a `const` dictionary. This is
also more consistent with the project's config-driven convention (`CLAUDE.md`: stats live in the
`*.tres`, not in code).

Take that route, or record in the plan why the duplicate map stays. If `_WEAPON_ICONS` does stay,
its coverage assertions (plan test 6) belong in
`tests/integration/test_weapon_mode_catalogue.gd:15-31`, which is already the file that pins
`ALL_IDS` ↔ catalogue completeness, rather than in a test about hub placement.

### 4. The sprite is 48×48, not 32×32, and the copied collision scale does not fit it

`3-plan.md:59` and `1-context.md:22` both call `upgrade_1.png` a "32×32" sprite. Its IHDR is
`48 48 8 3` — 48×48, 8-bit indexed, with a `tRNS` chunk (so it is genuinely transparent; good, and
note the `test_entity_sprite_transparency.gd` roots do not cover `global/pickups/`, so nothing would
have caught an opaque one here).

That matters because of the "byte-for-byte copy" instruction at `3-plan.md:52-55`.
`ship_module_unlocker.png` is 64×64, and its `CollisionShape2D` is `CircleShape2D` r=8 at
`scale = 3.531701` (`ship_module_unlocker_pickup.tscn:115-116,127-129`) — a 56.5 px pickup diameter
tuned to a 64 px sprite. Copied verbatim onto a 48 px sprite it is a hitbox noticeably larger than
the art. Copy the node *layout* verbatim; derive the scale from the new sprite's size (≈2.65 for a
parity 42 px diameter) and say so in the plan.

---

## Smaller notes (fix while you are in there; not blocking on their own)

- **Step 1's failure mode is misdescribed.** `3-plan.md:114-115` says the new test "Fails: no such
  class, no pickups in the hub." A test script that does not compile is *dropped* by GUT with only a
  warning while the suite exits 0 — that is the whole reason
  `tests/integration/test_suite_integrity.gd` exists (`tests/README.md`, "GUT fails open"). So
  between steps 1 and 3 the red comes from `test_suite_integrity`, not from the new test; the
  intended red (hub coverage) is only observable between step 4 and step 5. The ordering works —
  say what it actually does.
- **`STARTING_IDS` only ever reaches empty stores.** `_ready()` seeds inside
  `if _unlocked.is_empty()` (`upgrade_state.gd:27-29`), so a second entry added to `STARTING_IDS`
  later would never reach an existing profile. Not a problem for a one-element list; worth one line
  of comment next to the const so the next person does not assume otherwise.
- **Board metadata.** `./scripts/backlog-cli.js epic show code-health-backlog` reports this task as
  `"complexity": "medium"`, but it is being run through the escalated plan+review pipeline.
  `CLAUDE.md` asks that an escalation be recorded (`set-meta … --complexity large`) rather than run
  quietly, so the board shows what is actually happening.
- The plan's `updating-project-docs` step should name
  `docs/architecture/modules/global.md:274-286`, which lists the concrete `PickupBase` subclasses
  and will need the new one.

---

## What would make this APPROVED

1. Decide and write down what happens to the ship menu when an unlock lands mid-scene — preferably
   by connecting the already-unused `UpgradeState.unlocked_changed`, with a test — and correct
   `1-context.md:39-41`.
2. Rewrite test 5 as an unconditional live-autoload snapshot/restore modelled on
   `test_module_list_lock.gd`, with no "if substitution is impossible" branch.
3. Either fold the menu icons into `WeaponModeResource.icon` (deleting `_WEAPON_ICONS`) or record
   why the second map stays; if it stays, move the icon-coverage test to
   `test_weapon_mode_catalogue.gd`.
4. Correct the sprite dimensions and pick a collision scale that fits a 48 px sprite.

---

## Round 2

VERDICT: APPROVED

Revision 2 addresses all four round-1 findings, and it addresses them by changing the design
rather than by adding prose around it. I re-read the plan in full and re-checked every claim it
makes about the codebase against the files. Findings below are ordered: what I verified, then nits
worth fixing while implementing (none blocking), then one push-back that I am dropping.

### The four round-1 findings are resolved

**#1 (stale `PlayerMenu`) — resolved, design §3.** The line references are right:
`_populate_lists()` is `player_menu.gd:189`, its only caller is `connect_states()` at `:47`, whose
only callers are `mission_hud.gd:19/24/43` inside `_ready()`, and `_toggle()` (`:103`) does not
repopulate. The internal-inconsistency claim is also right as written: `_init_cursor()` (`:124`)
and `_confirm_selection()` (`:154`) read live `unlocked_ids()` while `_current_max_row()` (`:142`)
reads the stale frame count.

The chosen fix uses the hook that already exists — `grep unlocked_changed` across the repo returns
exactly `upgrade_state.gd:21` (declaration), `:46` (emit) and `test_upgrade_state.gd:45,72`, i.e.
zero production listeners, exactly as the plan states. The handler body is correct: `mini()` clamp
is defensive (an unlock can only grow the column) and harmless, and `_refresh_selection()` after
`_populate_lists()` is necessary rather than decorative, because `_populate_lists()` rebuilds
`_sub_frame` too (`:198`) and would otherwise drop the sub-weapon highlight.

I checked the one thing that could have made this fix produce duplicate rows instead of a correct
rebuild: `WeaponFrame.populate()` (`global/ui/player_menu/weapon_frame.gd:20-24`) `remove_child`s
and `queue_free`s the previous options and clears `_options` before rebuilding. So test 6's "count
grew by exactly one" is a sound assertion and repopulation is idempotent in the way the plan needs.

**#2 (test 5) — resolved.** The conditional fallback is gone and the fixture is now stated
unconditionally. The cited precedent is accurate: `test_module_list_lock.gd:31-35` is the
`before_all` that captures `SaveSandbox` plus the live singleton's dicts, `:38-42` is the
`after_all` that restores both, and `before_each` at `:45+` mutates the autoload directly with the
comment the plan paraphrases. `tests/README.md` documents it at `:665-668`. Using
`UpgradeState._unlocked.duplicate()` is the right shape — it is a flat `Dictionary` of
`StringName → bool` (`upgrade_state.gd:23`), so a shallow duplicate is a complete snapshot, unlike
`ShipModuleState`'s dict-of-arrays which needs the inner `.duplicate()` that test does.

**#3 (two icon maps) — resolved, and taken further than I asked.** Deleting `_WEAPON_ICONS`
outright rather than re-keying it is the right call. `grep` confirms the dictionary has exactly one
reader, so the deletion is contained. All eight icon PNGs under
`global/assets/sprites/player_menu_ui/ship_menu_ui/weapon_icons/` carry editor-minted UIDs in their
`.import` files (e.g. `icon_ship_weapon_pierce.png` → `uid://…`), so "read the UID out of the
`.import`" is a real, `CLAUDE.md`-compliant procedure and not a hand-typed one.

I also checked the gate hazard this change could plausibly have introduced and it does not exist:
`test_entity_sprite_transparency.gd` collects only `.tscn` files (`:142`) under `SCOPE_ROOTS`
(`:84-90`), and resolves textures from `Sprite2D` / `AnimatedSprite2D` / `AtlasTexture` nodes — a
`Texture2D` referenced from a `WeaponModeResource.tres` is not reachable by that walk, so the UI
icons (which are opaque card art and would likely measure over 90%) will not trip the transparency
invariant. Likewise `test_config_instance_isolation.gd` sweeps `*config*.tres` under `_ENTITY_DIRS`
only, so `weapons/modes/*.tres` is outside it. Both were worth confirming before approving an edit
to five shipped `.tres` files.

**#4 (sprite size / collision scale) — resolved and independently correct.** 48×48 is right (IHDR
`48 48 8 3`, with `tRNS`). I confirmed the precedent the plan now follows: `armor_tank`,
`health_tank` and `ship_shield_up` are the 48×48 pickups and `3.111` is the value they use, versus
`3.531701` on the 64×64 module pickup. Deriving the scale from the sprite's own size class rather
than from the copied file is the correct reading of the `test_contact_hitbox_geometry.gd` lesson
(a `Shape2D` holds the radius but not the node scale that multiplies it).

### Nits — fix while implementing, none blocking

1. **Two line references in the Risks section are wrong**, though both conclusions hold.
   `_WEAPON_ICONS` is read at `player_menu.gd:196`, not `:210` (`:206` is `_refresh_selection`);
   `grep` does confirm it is the only reader, so "one place" is correct. And `unlock()`'s
   already-unlocked early return is `upgrade_state.gd:42-43`, not `:40-41` (`:39-41` is the
   unknown-id guard) — the idempotence boundary in test 6 rests on the right behaviour, just cited
   one branch up. Minor ±1–2 drift elsewhere (`_toggle()` is `:103`, `_current_max_row()` is
   `:142`, the README paragraph is `:665-668`) is not worth chasing.
2. **Bump `load_steps` when adding the icon `ext_resource`.** `sniper_shot.tres:1` is
   `load_steps=3` for two `[ext_resource]`s; adding a third means `load_steps=4`, and the count
   differs per file (`mining_laser.tres` has no `projectile_scene`). A wrong value is a progress
   hint rather than an error, so neither `--import` nor `test_project_load_integrity` will tell
   you — which is exactly why it should be got right by hand.
3. **Expect orphan counts in test 6, and do not read them as a leak.** `WeaponFrame.populate()`
   `queue_free`s the previous rows, and the delete queue does not flush before a test ends — the
   same effect `tests/README.md` already documents for `ModuleList` ("24 orphans… harmless in
   play"). Worth one line in the test's header comment so the next reader does not chase it.
4. **§3's rejected-alternative rationale is weaker than the decision it supports.** The plan
   justifies signal-over-`_toggle()` by arguing a pickup can be collected while the menu is open,
   but `_toggle()` sets `get_tree().paused = true` (`player_menu.gd:105-108`) and `PickupBase`'s
   `Area2D` inherits pause mode, so that is at best a same-frame edge case. The decision is still
   right, for a stronger reason worth substituting: connecting the signal means *any* future unlock
   source — a mission reward, a boss drop, `unlock_all()` from a debug key — updates the menu with
   zero extra wiring, whereas repopulating in `_toggle()` re-solves the problem once per entry
   point. Swap the argument, keep the design.

### Push-back withdrawn

The board-complexity point in "Out of scope" is a fair correction and I accept it. I asserted the
`medium` label contradicted the escalated pipeline; the routing input is `kind`/`type`/`complexity`
plus `prepDir`, and re-labelling a medium change `large` to match the process it routed to would
invert cause and effect. Dropped.

### Summary

The plan now solves the work item end to end: the four modes get a source, the source is the
existing `PickupBase`/`sector_hub` pattern rather than a second mechanism, the unlock is visible in
the scene where it happens, the icon story collapses from two maps to one on the resource that
already had the field, and every test named can fail today for the reason it claims. Test 7 fails
on all five modes right now, test 6 fails on today's `PlayerMenu`, and test 1 fails on today's
`sector_hub.tscn` — three independent reds, which is what a test plan that cannot pass vacuously
looks like. Implement it.
