# Progress

- [x] Step 1 — `tests/integration/test_weapon_unlock_sources.gd` written first. Confirmed the
      predicted red: the file does not compile against the not-yet-existing API, so GUT drops it
      and the failure surfaces through `test_suite_integrity.gd::test_every_test_script_compiles`
      (8 parse errors: missing `WeaponModeUnlockerPickup`, missing scene, missing `STARTING_IDS`)
      — exactly as the plan's step 1 said it would, not as a failing assertion.
- [x] Step 2 — `UpgradeState.STARTING_IDS` + `_ready()` loop + the pointer comment naming
      `WeaponModeUnlockerPickup`, the hub, and the gate. `global/autoloads/upgrade_state.gd`.
- [x] Step 3 — `global/pickups/weapon_mode_unlocker_pickup.gd` (`class_name
      WeaponModeUnlockerPickup`, `Weapon` enum, `weapon_id()`, `.tres`-sourced dialog line).
- [x] Step 4 — `global/pickups/scenes/weapon_mode_unlocker_pickup.tscn`.
      UID `uid://c0oc8owfaowo3` minted with the headless `ResourceUID.create_id()` snippet and
      grepped to confirm it is unused. `CollisionShape2D` scale `3.111` (the 48x48 precedent),
      not the module pickup's `3.531701`. `--import` clean.
- [x] Step 5 — `PlayerMenu._ready()` connects `UpgradeState.unlocked_changed` ->
      `_on_upgrade_unlocked()` (repopulate, clamp cursor, refresh cursor + selection).
- [x] Step 6 — four instances on a new `y = -515` bench row in `sector_hub.tscn`
      (`WeaponUnlockerSniperShot` / `Spread` / `Gatling` / `MiningLaser`, x -280..20).
- [x] Step 7 — `icon` set on all five `modes/*.tres` from the existing `.import` UIDs,
      `load_steps` bumped per file (4/4/4/4/**3** — `mining_laser.tres` has no
      `projectile_scene`); `_populate_lists()` reads `mode.icon`; `_WEAPON_ICONS` deleted.
      `sniper_shot` takes `icon_ship_weapon_pierce.png`. This also fixes the in-game HUD
      `WeaponChip`, which drew a null texture for every mode.
- [x] Step 8 — gate + leak check + docs. See below.

## Non-vacuity check (each test proved to fail without its own fix)

Ran the new file three times with one fix reverted at a time, restoring after each:

| Reverted | Result |
|---|---|
| `PlayerMenu`'s `unlocked_changed.connect(...)` commented out | test 6 fails both assertions (1 != 2), 6/7 |
| `icon = ...` removed from `spread.tres` only | test 7 fails on `spread`, 6/7 |
| the four hub instances removed | test 1 fails on all four modes, 4/7 |

With everything in place: **7/7 passed**, 12 orphans — the documented `WeaponFrame.populate()`
`queue_free()` effect, called out in the test's header comment.

**Deviations from plan:** none. The four non-blocking nits from review round 2 (two stale line
refs, the `load_steps` bump, the orphan note, the stronger §3 rationale) were folded into
`3-plan.md` before implementation and are all reflected above.
