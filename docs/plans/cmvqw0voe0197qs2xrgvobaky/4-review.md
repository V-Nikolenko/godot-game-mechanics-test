VERDICT: APPROVED

# Review of t18 (hub placement): `3-plan.md`, round 1

I read the plan and the context file, then epic `cmug23ona0015m52w4t1m73bc/3-plan.md` "For every task" and §2.17. I checked every
geometry claim against the code at `2711e16` by recomputing it (node script, numbers below). The design is sound and delivers §2.17.
Its deviations each have a sound reason. It reuses what exists: `TurretGroup.spawn_members()`, `TwinLaserPairSpawn.spawn_pair()`, the
coverage row and the hub sweeps. Item 1 below is a test-spec error the implementer must fix when writing the row; it does not need a
re-plan. The rest are nits.

## Verified (no action)

- **Derelicts relative to the origin (2520, 1040)** (`sector_hub.tscn` TacticalSpace, radii from `structure_*.tscn:11`): module (−63, 163) r45,
  cargo (−25, −7) r55, satellite (68, −153) r28. These match the plan.
- **Why the two offsets move.** At (0, 0) the heavy emplacement (r64, `heavy_emplacement.tscn:15`) has a −93 px gap to the cargo platform
  (centres 26 px apart against 119 px of radii). The power source at (120, −120) has a −0.4 px gap to the satellite. Both deviations are
  needed and correctly argued. After the moves, the smallest body-to-body gap is 36.9 px (post A to cargo), then 41.4 (heavy to post A),
  43.4 (heavy to power), 46.7 (module to post B). Every pair is ≥ 30 px.
- **Barrier.** Slot (44, 98) ± (33, −146) puts the posts at (77, −48) and (11, 244), 299.4 px apart. The slot is 90.2 px from the
  module–cargo gap midpoint (−44, 78). The segment clears the bodies by: cargo 35.5, module 45.0, satellite 77.4, heavy 51.5, power 108.5,
  the rest > 170 px. The post axis is at −77.3°, the wreck line at −67.5°: "parallel" is approximate but fine. `LaserEmitter` has no
  facing, so the posts need no rotation. `TurretGroupSlot` (`turret_group_slot.gd`) really has only `member_scene` / `variant` /
  `rest_bearing_deg`, and `spawn_members()` (`turret_group.gd:91-120`) copies nothing else. An inherited `hub_barrier.tscn` outside
  `presets/` is therefore right: `test_turret_group.gd:423-434` loads every preset `as TurretGroup`.
- **Anchors.** 112.5° on 2600 gives (−995.0, 2402.1); −157.5° gives (−2402.1, −995.0). Nearest other anchors: tender to sniper 1217.7 px,
  pair to ram 1217.7 px. The tightest pair of all eleven anchors is still corvette to Mine Layer at 1114.5 px, so all are > 1000.
- **Interactable clearance.** Tender: nearest interactable is lore log (−700, 460) at 1964.4 px, so 1964.4 − 160 − 700 = +1104. Pair:
  nearest is Voeter at 1969.3 px, so 1969.3 − 210 − 650 = +1109. The 210 worst idle offset is `rig_length / 2` and is correct:
  `twin_laser_pair_spawn.gd` puts the drones ±210 px along X.
- **Sweep A.** Lance: 260 + max(perceive 900, `lance_mount.tscn` `fire_range` 1100) = 1360; the `lance.tscn` `length` is 1100 too.
  Rocket and sweep turrets: 288.4 + 900 = 1188. Heavy: 181.1 + 900 = 1081. Nearest interactable is lore log (720, 420) at 1903.8 px, so
  it clears by 543.8 against the 300 px margin. The boundary (a trigger 1000 px away) is inside 1660 and will be reported.
- **Sweep B.** Footprint = max(rocket or sweep 288.4 + 28, fence 107.4 + 149.7 + 18 = 275) + 100 = 416.4 < 500. The nearest patrol
  anchor to the site is the Bomber at 1327.8 px, then Gatling 1456.7 and Mine Layer 2038.4. The new anchors are 3770 / 5326 px away.
- **Coverage at 450** (`coverage_holes()`, `coverage_min` 2): lance (1100 from (0, −260)) and rocket (900 from (240, 160)) each reach
  every point (worst 710 and 738 px). The heavy's two 700 px mounts at (180, −10) and (180, 54) also do (worst 630 px). The preset passes.
- **Draws.** Appended as 16 and 17, so draws 1–15 are unchanged. The spawner's seed is set before `add_child`. `spawn_pair()` sets each
  brain's seed / `patrol_anchor` before adding the drone (`twin_laser_pair_spawn.gd:41-52`), A before B. It is idempotent (`_spawned`),
  so the spawner's own deferred call is a no-op. `_next_seed()` never returns 0, so `rng_seed + i` always applies.
- **Existing rows the change touches.** The plan names each one: `_brain_seeds()` (`test_sector_hub_patrol.gd:564`, would crash on the
  Brain-less spawner), the count asserts at `:464` and `:1010`, and the seed rows at `:586-592` and `:1004-1007`.
  `_spawn_hub()` (`:348`) builds a bare hub with no site, so the site cannot change those counts. Nothing adds the whole
  `sector_hub.tscn` to the tree: `test_hub_log_placement`, `test_module_unlock_sources`, `test_weapon_unlock_sources` and
  `test_boost_upgrade_source` instantiate it off-tree and look only for pickups. Gate step 2 never reaches the hub, because
  `boot.gd` defers `change_scene`. The TacticalSpace copies in `_spawn_hub(with_space)` and the sniper LOS row duplicate only
  `TacticalSpace`, and the site is not in it.
- **Other existing rows** (not in the plan, but they stay green):
  - `test_an_engaged_hub_support_selects_the_hub_ram_as_its_ward` (`:787`): drone B spawns at (−2192, −995), 1011 px from the support.
    That is outside `ward_search_radius` 900 (`support_ship_config.tres`), so `changes == [ram]` still holds.
  - The no-space frame-0 variant asserts `Hazards.count() == 0` before any tick. The twin beam registers only at TELEGRAPH
    (`enemy_beam.gd:251`), so it is not registered yet.
- **Friendly fire on the derelicts.** None: wrecks are in group `wrecks` (`wreck.gd:29`), not in `EnergyHitScan.VICTIM_GROUPS`.
- **Off-tree reads.** None of the off-tree rows expects the deferred `spawn_members()` to run (the plan's own risk note is correct).

## Findings

1. **Must fix when writing the row.** S3 says every member is "in `owner_group`, each `is_powered()`". Two members do not fit that:
   - `PowerSource` has no `is_powered()`. Only `defense_turret.gd:77`, `shield_generator.gd:59`, `laser_fence.gd:117` and
     `turret_group.gd:127` declare it, so calling it on the source is a script error.
   - The `LaserFence` node never joins the owner group. `laser_fence.gd:94-104` only copies the name; `:83` adds the *posts*.

   Write the row as follows:
   - Every `BaseEnemy` member and both fence posts are in `g.owner_group`.
   - Every member that has `is_powered()` (the four turrets, the generator, the fence) is powered.
   - The source `provides_power()`.
   - The group `is_powered()`.

   Do not "fix" this by adding `is_powered()` to `PowerSource` or putting the fence in the group. That would be churn outside the task.
2. **Nit (reuse).** `_slot_reach()` re-derives the mount reaches from `MountSlots` / `TurretMountSlot` with the first-slot variant override.
   `TurretGroup.mount_reaches()` (`turret_group.gd:174-197`) already does exactly that off-tree. Build sweep A from `g.mount_reaches()`:
   max of |position| + reach, combined with each slot's config `perceive_radius` (0 for the generator, the source and the posts: their
   configs have none). The lance still gives 1360, because `defense_turret.tscn` Slot0 is at (0, 0).
3. **Nit (numbers in prose).** The fence's TELEGRAPH is `twin_beam.tscn:8` `telegraph_seconds = 0.8`, not 0.9. Its `draw_half_width` is 14
   (`twin_beam.tscn:15`), not the 16 in context and S6. The rows read them from the scene, so only fix the prose and the DECISIONS text.
4. **Nit (pin what you moved).** Both moved members now sit inside the Gravity Well's 420 px field: heavy 304.6 px and power source 385.6
   px from its centre (relative (436, 185)). The rocket turret is at 197.6 px, as in the epic. All are outside `damage_radius` 150
   (`gravity_well.tscn`). Static members have no mover, so this is harmless today. Still, add to S6 that every member body clears the
   well's `damage_radius` (read from the scene). A later move or retune would otherwise put a member under the well's stress pulse silently.
   Also mention the well in the DECISIONS entry for the move.
5. **Nit (gate time).** The 1.2 s estimate does not count the extra cost every existing `_spawn_hub()` row (about 20) now pays for one
   tender plus a pair with a twin beam. It is small, but report it in the before / after `scripts/gate-time.sh` figures.
6. **Nit (docs).** Step 6 should invoke the `updating-project-docs` skill (CLAUDE.md, "MANDATORY — keep the docs current"). It should also
   note the hub placement in `laser_tender/ENEMY.md` and `twin_laser_drone/ENEMY.md`, since t20 only closes the roster.
7. **Accepted deviation.** No `rng_seed` export on the group: `TurretGroup` has no rng, and the site, as a scene node, draws nothing from
   the patrol rng. That is the property §2.17 cares about. Log it as planned.
