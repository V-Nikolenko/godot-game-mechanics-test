## Round 1

VERDICT: CHANGES_REQUESTED

The design is a faithful §2.7 implementation and most of its mechanics check out against the code. The problems are in the test plan. One row cannot work as
written, and several rows do not pin the numbers they claim to pin, so a wrong build would still pass them. All the fixes are small and none changes the design.

### Verified against the code (no change needed)

- **Frames and bearings.** Port is local +x: `carrier.gd:22`, and `carrier_brain.gd:157` / `:386`. `TurretMountSlot.rest_bearing_deg` is local to the
  slot's parent (`turret_mount_slot.gd:11`). The chain `Modules/GunPort/MountSlots/Slot0` → mount carries no rotation of its own, so a rest of 0 / 180 / 90 is
  hull-local port / starboard / nose as the plan says. The epic's "bearing = heading − 90°" is the same as the test helper `_port(c)`
  (`test_carrier.gd:139`).
- **One side safe is guaranteed by geometry.** `_turn_toward` clamps a limited mount's rotation into `rest ± traverse/2` (`turret_mount.gd:326-330`), and
  `BurstCannonMount._shoot` fires along `global_rotation` (`burst_cannon_mount.gd:88`). The starboard battery therefore always fires with local
  direction x ≤ cos 105° < 0. `_target_in_arc` uses the target's position from the pivot (`turret_mount.gd:360-364`), and a port-side stub is never in the
  starboard arc. In the dead-port case the bow arc from (0, 116) (the player is at −16°), the bank (400 < 450) and the pulse (400 > 340) all stay silent, so
  row 1's dead case sees no rounds at all. That is correct. The row would fail on a build that dropped `traverse_deg_override`, and the control fails on a
  carrier that never fires.
- **Building the mounts.** `ModularHull.build_mounts(host, rng, owner_group, gate, first_index) -> int` (`modular_hull.gd:78-94`) followed by
  `TurretMountBuilder.build()` (`turret_mount_builder.gd:14-40`) gives unique pool names: PulsePool_0/1/2, DumbPool_3, PursuitPool_3. The brain's `rng` is
  seeded in the child `_ready()` (`enemy_brain.gd:57-60`) before `Carrier._ready()` runs.
- **Bank pools.** The period at 5.5 s is 6.35 s and at 7.0 s it is 7.85 s, both longer than PURSUIT's 6.0 s life (`rocket_battery_mount.gd:42-53`, `:101`),
  so each pool holds 2 rockets either way. "Never too small" holds.
- **Ring.** One ring lasts 1.0 + 420/360 + 0.15 = 2.32 s, which is under the 2.5 s PANIC interval. `start()` is ignored only in TELEGRAPH / EXPANDING
  (`energy_ring.gd:98-100`). `cancel()` followed by `tick(fade_seconds)` reaches OFF without a scan (`energy_ring.gd:128-136`, `:189-201`).
  `EnergyHitScan` never lists `enemy_parts` and exempts both the host and the owner group (`energy_hit_scan.gd:17`, `:37-42`). An inherited scene with only
  export overrides needs no UID, and `energy_ring.tscn` itself has none.
- **Precedent and EMP.** The `can_fire` and view rule copies `HeavyGunshipBrain._tick_weapons` (`heavy_gunship_brain.gd:438-448`). The brain is not ticked
  during an EMP window (`base_enemy.gd:126-139`), which is the reason the ring has to be killed in `on_emp_started()`.

### Findings

1. **Rows 4, 6, 7 and 9 do not say the player and the hull are held, so row 4 cannot pass as written. (must fix)**
   - Open Space: with the player at 300 px (< `screen_range_min` 600), `_tick_screen` arrives away from it at up to 70 px/s (`carrier_brain.gd:309-313`).
   - Assault: CROSS descends at a constant 90 px/s (`carrier_brain.gd:367-374`). The pulse needs `in_view`, and the root frees the hull below the
     projectile rect (`carrier.gd:72-82`).
   - In both modes `_tick` integrates the velocity (`test_carrier.gd:109-112`), so a player "held there" in world coordinates is outside 340 px, or the hull
     is out of view, long before the 5.0 s restart. Row 4's restart, the PANIC 2.5 s interval and the "back to 300 at 6.0 s" step never happen.
   - Fix: state for each row, as row 1 already does, that the stub is re-placed relative to the hull every tick (hull + nose × d) and that the Assault hull's
     y is held inside the view. Row 6 (about 2.4 s) and row 9 also need the Assault hull to start well inside the view.
2. **The trigger numbers are not pinned by any boundary. (must fix; plan "For every task": an edge case per row)**
   - Row 4 tests the pulse only at 300 and 600 px, so any `pulse_trigger_range` between 300 and 600 passes. A brain that read `missile_min_range` (450) by
     mistake would pass too.
   - Row 3 tests the bank at 400, 440 and 600 px, so a min range of 550 passes.
   - Fix: add the pairs just inside and just outside each number: pulse at `pulse_trigger_range − 10` starts and `+ 10` does not; bank at `missile_min_range
     + 10` fires and `− 10` does not.
   - Read every one of these distances from `SHIPPED`, never typed (the `core_exposure_count` precedent in t6). The same applies to row 7's "2.2": read it
     from `burst_cannon_mount.tscn` through `TurretMountScenes.export_of()`.
3. **Row 2's bearings are measured from the hull centre, but the arc is measured from the bow pivot at (0, 116). (should fix)**
   - At 600 px from the centre, +25° is 30.7° from the pivot (inside by 4.3°) and +45° is about 54° (19° outside).
   - The plan's statement "the 45° bearing sits 10° outside the arc edge" is therefore wrong, and the row's boundary is looser than claimed.
   - Fix: place the player by bearing from `bow_mount().global_position` (relative to the nose), with a tight pair such as 30° (fires) and 40° (none).
   - The shell-direction check can be "≤ 35° + 1e-3": rotation is clamped to the arc (`turret_mount.gd:328-330`), so "+ half the fire cone" only adds
     slack.
4. **The pulse clock does not follow the project's clock rule. (should fix)**
   - `_pulse_left <= 0` should follow the `x -= delta`, over at `x <= 1e-6` rule (CLAUDE.md, ability lock; `TurretMount.CLOCK_EPS`). As written, 300 ticks
     of 1/60 can leave a positive remainder, and row 4's "± 1 tick" tolerance hides the off-by-one.
   - Fix: use the epsilon and tighten the row to "exactly on tick N".
   - Also use a strict `<` for `pulse_trigger_range`, matching §2.7's wording ("distance … < 340").
5. **Some behaviour that can regress has no assertion. (should fix; adds no gate time if folded into existing rows)**
   - (a) The hull light reads CHARGING while the ring is in TELEGRAPH. This is the pulse's only tell, and §2.9 requires it. Add it to row 4.
   - (b) In PANIC the hull light strobes, but never hides a CHARGING. Add it to row 7.
   - (c) Row 9 only tests an EMP while the ring is in TELEGRAPH. The path the plan introduces, `cancel()` then `tick(fade_seconds)`, runs only from
     EXPANDING. Add an EMP while EXPANDING: OFF on the same call, and no further `target_hit`.
   - (d) `on_suspended()` (`suspend_ai()`) killing the ring and scanning the mounts has no row.
   - (e) The bank's host writes have no row. Assert `missile_mount().cooldown_seconds == SHIPPED.missile_cooldown` and `pursuit_chance == 1.0` on the live
     mount. Row 3 cannot observe the 7 s interval: in a hand-ticked loop the 2-rocket PURSUIT pool never recycles (`bullet_pool.gd:80-84` returns null), so
     the second salvo is refused.
6. **Row 9's death check cannot fail as worded. (should fix)**
   - "Ring not lethal in that call" is ambiguous. A dead carrier's brain is never ticked again and the ring is freed with it, so a build without the
     `died → cancel_pulse()` hook passes any check that ticks afterwards.
   - Fix: assert `ring.is_lethal() == false` and `phase() == OFF` immediately after the core's `destroy()` call, while the queued carrier is still valid. The
     t6 R2-4 row shows how to observe inside that call.
7. **PANIC battery pool sizing is not argued. (minor; DECISIONS note)**
   - The battery pools are sized at build time from a 2.2 s cooldown: a period of 2.96 s gives 12 rounds (`burst_cannon_mount.gd:40-44`).
   - At 2.2 × 0.7 the `pool_size_for` formula over `max_time` 8 asks for 16.
   - It is safe in play because `max_distance` 1400 / 300 = 4.67 s (`pulse_round.tscn`) keeps three bursts in flight, which is 12 rounds. Say so in the t7
     notes, as the plan does for the bank.
   - Hand-ticked rows exhaust every pool, because no frame recycles a round, and each refused round prints a `push_warning`. Stop the control rows (row 1
     control, row 3 positive) at the first evidence instead of running 20 s / 10 s. That is less noise and less of the 1.8 s allotment.
8. **Weapon tuning in a host config. (minor; log it as a deviation)**
   - `missile_cooldown` and `missile_pursuit_chance` in `CarrierConfig` depart from "weapon tuning lives in that scene's exports, never in a host config"
     (`turret_mount.gd:9`, and the epic's "For every task" conventions).
   - The choice is defensible: §2.7 states these as this host's numbers, and the PANIC factor already writes onto the mounts.
   - Fix: record it in DECISIONS as a named deviation, not just a choice, and keep `rocket_battery_mount.tscn` untouched (the Ph8 rows read it).
9. **`PulseRingMount` is not in the rejected alternatives. (minor)**
   - `pulse_ring_mount.gd:1-83` already owns, starts and ticks an `EnergyRing` on distance.
   - §2.7 requires brain ownership, so the plan is right not to use it. It should still name it and give the reasons: the ring scene and trigger are mount
     scene exports, so it would need a new variant; its cooldown counts from the end of the expansion, while the plan counts from `start()`; and it carries a
     head sprite.
   - The plan should also state that the cooldown-from-`start()` choice differs from that precedent.
10. **Fairness row mechanics. (minor)**
    - `_player_r_p()` and the `R` constant are private to `test_energy_ring.gd`. Copy them into `test_carrier.gd` with a pointer back, or move them to a
      helper.
    - The boundary case must run the same predicate on an instance with `gap_deg = 15`. It must not use `EnemyBeamScenes.export_of_scene` or `_synthetic()`:
      `get_state()` on an inherited scene lists only the overridden properties (`enemy_beam_scenes.gd:49-64`), and `_synthetic()` instantiates the base
      ring.
11. **Node name. (nit)**
    - A root child named `PulseRing` reads like `class_name PulseRing` (Ph7's visual; CLAUDE.md calls the distinction out). Use `AntiApproachRing` or
      `CarrierPulseRing` for the node.

Once findings 1–6 are folded into the test plan, the plan is ready. Findings 7–11 are notes or one-line additions.

## Round 2

VERDICT: APPROVED

I re-checked the revised `3-plan.md` against the code. Round-1 findings 1–6 are all resolved, and every row in the test plan can now fail on a build where its
feature is missing or broken. The two items below are optional: they tighten a row and do not block implementation.

### Round-1 findings, re-checked

1. **Drift.** The test-plan preamble (`3-plan.md:113-116`) pins the hull after each `_tick` and re-places the player relative to it. That removes the
   SCREEN back-off (`carrier_brain.gd:309-313`), the CROSS descent (`:367-374`) and the free-below check (`carrier.gd:72-82`). Row 7's leash check is the
   only unpinned part, and the plan says so.
2. **Boundaries.** Each number now has a pair just either side of it, read from `SHIPPED`:
   - Pulse at `pulse_trigger_range ± 10` (330 / 350). Both are outside the bank's range.
   - Bank at `missile_min_range ± 10`. 460 from the centre is 396 px from the Dorsal pivot (0, 64), well inside the 900 `fire_range` in
     `rocket_battery_mount.tscn`.

   A build that uses the wrong field or the wrong range now fails one side of a pair.
3. **Bow.** Distance and bearings are now taken from the pivot, and `_target_in_arc` measures from that same pivot (`turret_mount.gd:360-364`). 30° fires
   and 40° / −40° do not. Reaching 30° from rest takes about 1.1 s at 0.9 rad/s, plus the 0.7 s charge, which fits the 4 s window.
4. **Clock.** `_pulse_left <= 1e-6` with a strict `<` gives exactly 300 ticks for 5.0 s and 150 ticks for 2.5 s, whichever side of the check the decrement
   falls. One PANIC ring lasts 60 + 70 + 9 = 139 ticks, under 150, so a restart is never refused by a busy ring.
5. **Missing assertions, now present.**
   - Row 4: CHARGING on the start tick, and on every tick of the PANIC ring's telegraph.
   - Row 9(b): an EMP while EXPANDING ends OFF. It would stay in FADE without the `tick(fade_seconds)` step (`energy_ring.gd:128-136`).
   - Row 9(c): a rail.
   - Row 3: the live bank's `cooldown_seconds` and `pursuit_chance`.
6. **Death.** Row 9(d) asserts OFF and not lethal straight after `destroy()`, and fails without the `died` hook.

Round-1 minors 7–11 are addressed:
- the pool reasoning and the config deviation are logged (`3-plan.md:81-87`);
- `PulseRingMount` is rejected with its reasons (`:95-97`);
- the fairness check runs on an instance (`:138-140`), against `R` 0.25 at `test_energy_ring.gd:31`;
- the node is renamed `AntiApproachRing`;
- controls stop at the first evidence.

### Optional

- **Row 4: isolate the ring's tell.** Place the player astern (local −y). That bearing is outside the bow arc (90 ± 35) and both battery arcs (0 ± 75,
  180 ± 75), and closer than the bank's minimum range. CHARGING then comes from the ring alone and cannot be lent by a bow telegraph. The row already fails
  without the ring mapping (a 0.7 s bow charge cannot cover a 1.0 s ring telegraph), so this only removes a coincidence.
- **Row 7: check the hull strobe too.** It asserts the core light's strobe only. Adding "the hull `StateLight` shows both OFF and a lit state within 1 s of
  PANIC, with the player inside a battery arc" would also cover §2.7's "hull running lights strobe", at no gate cost.
