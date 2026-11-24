VERDICT: CHANGES_REQUESTED

Review of `3-plan.md` (t11: retire the space station, re-point its tests to the Space Fortress) against epic §2.11 / §2.4 and the code at
`c84cc5d`. Most of the plan is right and I checked its numbers against the real scene. Two of the re-pointed rows cannot work as written,
though: one fails against the real code and one relies on a premise that is false. One more row would be vacuous, and one boundary-type row
is dropped without a reason. All four need fixing before implementation.

## Blocking

### B1. The mining-laser BOUNDARY row fails as written: a layer-1 fortress does not block the beam
- `assault/scenes/enemies/space_fortress/space_fortress.gd:490`: `func is_laser_blocking() -> bool: return false`.
- `assault/scenes/player/weapons/behaviors/beam_behavior.gd:64-71`: a ray hit only becomes the blocker when `is_block` stays true, and
  `is_block = coll.is_laser_blocking()` whenever the collider has that method.
- So with `collision_layer = 1`, the ray hits the fortress body, `is_block` is false, `blocker_point` stays at full length and
  `blocker_collider` stays null. The plan expects "endpoint truncated at local y +176 (±2), nothing on the line pinged". What actually happens
  is a full-length beam, with the root (centre on the x 0 line) and ShieldSouth / Core / ShieldNorth all pinged. The row goes red on day one.
- This also means the "not blocked by the layer-0 root" row does not isolate the layer. The fortress has two independent guards: layer 0
  (already pinned in `test_space_fortress.gd:262`) and `is_laser_blocking() == false`. Epic §2.11's "a layer-1 root would block it" was true
  for the station, which had no `is_laser_blocking()`. It is false for the fortress, so the plan has to say so (DECISIONS line) rather than copy it.
- Fix, one possible shape: (a) a row in which a fortress set to `collision_layer = 1` still lets the beam run full length. This pins the second guard,
  which nothing else pins behaviourally. (b) A non-vacuity boundary: a plain layer-1 `StaticBody2D` with a `CircleShape2D` r 176 at the fortress
  centre and no `is_laser_blocking()`. It must truncate the beam at local y +176 (±2), and none of the parts may ping. Without (b) the
  full-length assertion has nothing to fail against.

### B2. The death-sequence row "script defaults differ" relies on a false premise
- `space_fortress_config.gd:40,42`: `death_sequence_duration = 2.4` and `death_blast_count = 10` are the script defaults.
  `space_fortress_config.tres:28-29` ships the same 2.4 / 10.
- The plan says to "read [`SpaceFortressConfig.new()`]'s defaults, pin them, and keep the 'differs from 2.4 / 10' assertions". Those
  assertions fail, and with them gone the config-copy row is not shown to be able to fail.
- Fix: move non-vacuity onto the nodes, where the copy actually happens.
  - `SpaceFortress.death_duration` defaults to 0.0 (`space_fortress.gd:75`). An instantiated fortress that is not yet in the tree reads 0.0;
    a readied one reads `cfg.death_sequence_duration`.
  - `BossDeathSequence._blast_count` defaults to 3 (`boss_death_sequence.gd:92`). The readied sequence reads 10. This is the pattern
    `test_space_fortress.gd:724-725` already uses.
  - Pin the shipped 2.4 / 10 on the `.tres`, as the plan already says. If 2.4 / 10 as script defaults is itself a smell, record it. Do not
    edit production code in this task.

## Should fix

### S1. The "no re-emit" row is vacuous if ported literally
- The station row drove re-entry with `hurt_box.received_damage.emit(50)` three times. That worked because the station's damage handler wrote
  `Health`. The fortress's `_on_received_damage` returns while `_dying` and never touches `Health` (`space_fortress.gd`, the
  `_on_received_damage` above `_on_core_destroyed`). A literal port therefore never re-enters `_on_health_changed`, and the row stays green
  on a build without the `_dying` latch.
- Fix: drive it with `fortress.health.set_health(0)` three times, as `test_space_fortress.gd:616` does (`Health.set_health` emits
  `amount_changed` unconditionally), and say so in the plan.

### S2. The asteroid "damage actually lands" half is dropped without a reason
- The station file had two asteroid rows: one where the unarmoured core took 40, and one deflection. The plan keeps only the deflection.
  The hull can never take damage, so the station's form of the row no longer applies. Bit 1024 on the parts' mask (1120) is still a live path
  that nothing exercises with a real asteroid, and the plan's `test_base_enemy.gd` row only reads the mask value.
- Fix: add a row in which a real asteroid on a vulnerable bare part takes 40. Example: ShieldSouth destroyed, asteroid at local (150, 0) over
  BatterySweep. That point is 111 px from BatterySpread and from BatteryMissiles, so neither (r 22 + 28 = 50) is touched. The hull also
  reports `armor_deflected` 40. If the row is dropped instead, the plan has to state why.

## Minor

- **M1.** `test_base_enemy.gd`'s replacement checks "every fortress part's mask is 1120". Every `Modules/*/HurtBox` in the roster already
  shares that value: heavy gunship 6/6, carrier 7/7 (both `.tscn` checked), fortress 9/9. A roster-wide sweep over `Modules/*/HurtBox` costs
  the same and also covers the next modular host. Optional.
- **M2.** Transparency, measured on `fortress_hull.png` (384 × 384):
  - 68.12 % of pixels are fully opaque, so the 0.60 bound does not hold. The plan's fallback (pin the measured value plus slack) applies.
    That bound means little: a disc of r 176 in 384² is already 66 %, and the sweep's own maximum is 0.90.
  - The corners are [0, 0, 0, 0], which passes.
  - Pixels with alpha > 0 beyond each radius from the centre: 3124 beyond r 176, 954 beyond 178, 4 beyond 180, 0 beyond 185.
  - Suggestion: assert that every pixel beyond r 185 from the centre is alpha 0. That is the "sky around it" property itself, and it would
    catch a background painted in.
  - The control texture `battery_spread.png` is 71.28 % opaque, below 0.90, so it is a valid control.
- **M3.** `test_enemy_bullet_lifetime.gd`: `_every_shipped_enemy_bullet_speed()` returns a flat `Array[float]`, so "pin the name" requires
  a name-keyed list (e.g. `[name, speed]` pairs). Say which.
- **M4.** Stale citations that the anchored grep will not catch, all missing from the plan's lists:
  - `tests/integration/test_ram_corvette.gd:436` cites `test_station_incoming_damage_paths.gd`, which is being renamed.
  - `docs/assault-spawning-scoring-internals.md:272` cites `test_station_reinforcements.gd`, which is being deleted.
  - `tests/README.md` has about 26 station mentions, well beyond the gate-time row: the "space-station family" passage at lines 305-343,
    and lines 92, 127, 225, 832, 883-933.
  - `docs/architecture/modules/global.md:438` (`SpaceStation`).
  - `assault/scenes/hazards/laser_ray/HAZARD.md:47`.
  - `docs/BULLET_POOL.md`.
  - `.claude/skills/pixel-art-generation/SKILL.md:97,108,151-171`, which cites `space_station.tscn` and `station_core.png` as live
    examples. Re-word these as history.
  - CLAUDE.md's list of test files names the deleted station family, which the plan already covers.
- **M5.** Build step 4 runs only three users of `fixture_modular_host.tscn`. `tests/unit/test_boss_phase_driver.gd` also uses it, through
  `tests/helpers/fixture_boss_host.gd`, so add it to that run. The full gate catches it anyway.
- **M6.** `test_level_1_sequence.gd`: the `_station` → `_fortress` rename is cosmetic. Lines 40-145 hold no `SpaceStation` type or preload,
  and §2.11 asks only for those to be dropped. It is harmless, but it is optional churn.

## Checked and correct

- **Acceptance grep coverage.** I ran the anchored grep. It hits 42 files: the station folder (9), `base_enemy.gd`, `laser_ray.gd`,
  `bullet.gd`, `arena_camera.gd`, `wave_builder.gd`, `boss_death_sequence.gd`, `bullet_pool.gd`, `enemy_module.gd`,
  `radial_attack_pattern.gd`, and 23 test files. The plan covers every one. No Fortuna `space_stations/` path matches. Nothing outside the
  tests and `wave_builder.gd` references the station.
- **Hurtbox geometry.**
  - The hull's body, HurtBox and contact box share `CircleShape2D_hull` r 176 (`space_fortress.tscn:53-55,146-174`).
  - Assigning a fresh r 44 shape (Core, `:65-66`) to the HurtBox node leaves the body untouched, and the per-edge shortfall is 176 − 44 = 132.
  - Each part's reach is within 176. Batteries at (±99, ±99): 140 + 22 = 162. Sweep at (150, 0): 172. Hangar 36 × 56 at (−150, 0): farthest
    corner 170.3. Generators: 146. Core: 44.
- **Damage-path lanes.**
  - Asteroid at (60, −50), r 28 (`big_asteroid.tscn:12-18`): 78.1 from the core (needs > 72), 92.2 from the north generator (> 54),
    62.6 from the missiles battery (> 50), 103 from the sweep battery. It touches the hull only.
  - Homing missile from (99, 300): `homing_point()` picks BatterySpread at 201 px over BatteryPulse (282) and BatterySweep (304), since the
    generators are locked (`space_fortress.tscn:416-423`). On the x 99 lane it crosses the hull edge at y ≈ 145.5, before the battery rim at
    y 121. Root HurtBox mask 1121 includes 32. `homing_missile.gd:106-107` asks `homing_point()`.
  - `ShieldSector` detaches its bubbles in the same call as the generator's `destroyed` (`shield_sector.gd:9-11`), and the bubbles are
    absorbers on the hurtbox, not separate areas.
  - `EnemyModule.destroy()` works on a locked part (`enemy_module.gd:206-207`), and the `deflected` signal exists (`:47`).
  - On the beam: `BeamBehavior` picks targets by node centre within 12 px of the line, so the x 0 line hits the root and three parts, and the
    x 99 line hits BatterySpread and BatteryMissiles.
- **Death sequence.** `blast_offset(i)` has length 150 (`blast_spread_radius`, `space_fortress.tscn:201`), which is under 176.
  `space_fortress.gd` frees in the same call at duration 0, makes the corpse harmless (`contact 256 → 0`, hurtbox monitoring off) and latches
  `_dying`.
- **Explosion row.** `EnemyModule.destroy()` explodes into `host.get_parent()` at the part's position (`enemy_module.gd:233-237`), so "one
  burst in the container at the battery's position, none under the fortress" holds.
- **Engagement-deadline scan.** None of the scan's needles (`emp_zone.tscn`, `EmpZone`, `emp_mine`, `EMP_MINE`, `sector_jammer`,
  `SECTOR_JAMMER`, `w_emp`, `jammer(&"sector")`) appears in `global/boss/*.gd`, `space_fortress/*.gd` or `space_fortress.tscn` (grep exit 1).
  The bay payloads are authored in the `.tscn` (`:540-580`).
- **Replacement coverage.** `test_spawn_camera_pan.gd`'s two rows are replaced by `test_fortress_reinforcements.gd:525`. The station-children
  row in `test_config_instance_isolation.gd` is replaced by its existing fortress row at `:338`. `_MIN_ROSTER_SIZE` 26 → 25 is correct.
- **Conventions.** I found no conflict with CLAUDE.md: no hand-typed UIDs (`git mv` keeps the sidecars), no writes to loaded resources,
  real-physics rows at 8×, Fortuna untouched, and the rename to `_host` matches §2.4.

---

# Round 2 (after "Revisions after review round 1", 3-plan.md:113-)

VERDICT: APPROVED

I checked each revised claim against the code. All of them hold, and every round-1 finding is addressed.

- **B1: resolved.**
  - `beam_behavior.gd:58-71`: the ray uses `collision_mask = 1 | 1024` with bodies only. A hit blocks the beam unless the collider answers
    `is_laser_blocking()`. A plain `StaticBody2D` has that method on neither itself nor its ancestors, and its default `collision_layer` is 1.
    A r 176 circle at the fortress centre therefore truncates a beam fired up from (0, 300) at y +176, and every part beyond `seg_len` is culled.
  - Row (b) is also right. `intersect_ray` returns only the first collider, so a layer-1 fortress is hit, answers false and leaves
    `blocker_collider` null. The beam runs full length and the root and the parts on the line are still targeted.
  - The DECISIONS line records the departure from §2.11.
- **B2: resolved.**
  - `space_fortress.gd:75` declares `var death_duration: float = 0.0`. Its only other write is `_apply_config()`, called from `_ready()`
    (`:163`). `base_enemy.gd` never writes it. A fortress that has been instantiated but not yet added to the tree therefore reads 0.0.
  - `boss_death_sequence.gd:92` declares `var _blast_count: int = 3`. Only `_ready()` changes it (`:120`).
  - Implementation note: `free()` the probe fortress that never entered the tree (or use `autofree`). An orphan would trip the leak check.
- **S1: resolved.** `health.set_health(0)` re-enters `_on_health_changed`, which is what the `_dying` latch guards. `test_space_fortress.gd:616`
  uses the same driver.
- **S2: resolved.**
  - The asteroid's `ContactHitBox` is layer 1024, damage 40, `damage_type` 2 (`big_asteroid.tscn:44-49`).
  - The part hurtboxes set no `accepted_damage_types`, so they accept any type (`space_fortress.tscn:351-354`; `hurtbox_component.gd:42`).
    Their mask 1120 includes 1024.
  - With the south generator destroyed, BatterySweep has no absorber (`hurtbox_component.gd:44`), so it takes 40.
  - The asteroid at (150, 0) also overlaps the hull, because 150 + 28 > 176. Expect `armor_deflected` 40 there as well. The row may assert
    it, and must not assert its absence.
- **M1: resolved.** Only `carrier.tscn`, `heavy_gunship.tscn` and `space_fortress.tscn` author `Modules/*/HurtBox`. They hold 7 + 6 + 9 = 22
  parts, all with mask 1120, so the floor of at least 3 hosts and at least 20 parts holds.
- **M2: resolved.** I measured `fortress_hull.png` with pixel centres against (192, 192): no pixel with alpha > 0 lies beyond r 185. The
  corners are 0.
- **M3–M6: resolved as written.**

No remaining findings.
